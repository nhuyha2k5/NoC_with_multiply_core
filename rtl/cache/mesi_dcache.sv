// Direct-mapped, one-word-line, write-back/write-allocate MESI data cache.
// The CPU side and NoC side are AXI4-Lite. Coherence ownership and snoops use
// coherence_if; dirty snoop/eviction data is written back over the normal NoC.
//
// Error policy: a failed snoop write-back is retried up to WB_RETRY_LIMIT
// times. After that the snoop is answered with snoop_err while the dirty line
// stays Modified, and the peer's request completes with SLVERR. Dirty data is
// never dropped and the system cannot hang on a persistently failing backend.
// Uncached write responses are registered before reaching the CPU so the NoC
// B channel does not form a combinational path into the core.
//
// Snoop concurrency: a snoop that needs no write-back (line clean or absent)
// is answered even while the main FSM owns the NoC port for a different
// address (the manager never overlaps two transactions on one word). A dirty
// snoop waits until the main FSM's NoC access is finished. The snoop update is
// re-checked against the current tag and skipped if the main FSM replaces
// that line in the same cycle.
//
// Storage mapping (Step 1, 15/10/2026): the three writers of the data array
// (write hit in M_IDLE, upgrade merge in M_COH_APPLY, fill in M_MEM_READ_DATA)
// are in mutually exclusive main-FSM states, so they share one synchronous
// write port. AR and AW/W acceptance are mutually exclusive as well and share
// one lookup index. Reads stay asynchronous, so hit latency and
// read-during-write behaviour are unchanged, and the data array maps to
// distributed RAM instead of 4096 flip-flops. Line state stays in flip-flops
// (it needs reset and has a concurrent snoop writer).
module mesi_dcache #(
  parameter int LINES = 64,
  parameter int WB_RETRY_LIMIT = 16,
  localparam int INDEX_W = $clog2(LINES),
  localparam int TAG_W = 32 - INDEX_W - 2
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  axi_lite_if.slave   s_axi,
  axi_lite_if.master  m_axi,
  coherence_if.cache  coh,
  output logic [31:0] hit_count_o,
  output logic [31:0] miss_count_o,
  output logic [31:0] writeback_count_o,
  output logic [31:0] invalidate_count_o
);
  import coherence_pkg::*;
  import router_pkg::*;

  typedef enum logic [3:0] {
    M_IDLE, M_READ_RESP, M_WRITE_RESP,
    M_EVICT_SEND, M_EVICT_RESP,
    M_COH_REQ, M_COH_APPLY,
    M_MEM_READ_ADDR, M_MEM_READ_DATA,
    M_BYPASS_WRITE_SEND, M_BYPASS_WRITE_RESP
  } main_state_t;

  typedef enum logic [2:0] {
    S_IDLE, S_WB_SEND, S_WB_RESP, S_APPLY, S_ACK, S_WAIT_DROP, S_NACK
  } snoop_state_t;
  localparam int RETRY_W = $clog2(WB_RETRY_LIMIT + 1);

  main_state_t  main_state_q, main_state_d;
  snoop_state_t snoop_state_q, snoop_state_d;

  logic [TAG_W-1:0] tag_q [0:LINES-1];
  logic [31:0]       data_q[0:LINES-1];
  mesi_state_e       line_state_q[0:LINES-1];

  logic [31:0] addr_q, wdata_q, resp_data_q;
  logic [3:0]  wstrb_q;
  logic [1:0]  resp_q;
  logic        write_q;
  coherence_request_e req_cmd_q;
  logic        grant_shared_q, grant_err_q;
  logic        aw_hold_q, w_hold_q, aw_done_q, w_done_q;
  logic [31:0] evict_addr_q, evict_data_q;

  logic [31:0] snoop_addr_q, snoop_data_q;
  logic        snoop_cmd_q, snoop_hit_q;
  logic        snoop_aw_done_q, snoop_w_done_q;
  logic [RETRY_W-1:0] snoop_retry_q;

  logic [31:0] hit_count_q, miss_count_q, writeback_count_q, invalidate_count_q;

  logic [INDEX_W-1:0] cpu_index, snoop_index;
  logic [TAG_W-1:0] cpu_tag, snoop_tag;
  logic cpu_hit, snoop_line_hit;
  logic main_axi_active, snoop_axi_active;
  logic snoop_needs_wb, snoop_start, main_install, snoop_apply;
  logic write_pair_ready;
  logic [31:0] effective_write_addr, effective_write_data;
  logic [3:0] effective_write_strb;
  logic accept_is_read;
  logic [INDEX_W-1:0] accept_index;
  logic [TAG_W-1:0] accept_tag, accept_line_tag;
  mesi_state_e accept_state;
  logic [31:0] accept_data;
  logic data_we, data_we_hit, data_we_upgrade, data_we_fill;
  logic [INDEX_W-1:0] data_waddr;
  logic [31:0] data_wdata;

  function automatic logic cacheable(input logic [31:0] addr);
    return cache_address(addr);
  endfunction

  function automatic logic [31:0] merge_bytes(
    input logic [31:0] old_data,
    input logic [31:0] new_data,
    input logic [3:0]  strb
  );
    logic [31:0] merged;
    begin
      merged = old_data;
      for (int b = 0; b < 4; b++)
        if (strb[b]) merged[b*8 +: 8] = new_data[b*8 +: 8];
      return merged;
    end
  endfunction

  assign cpu_index = addr_q[INDEX_W+1:2];
  assign cpu_tag   = addr_q[31:INDEX_W+2];
  assign cpu_hit   = (line_state_q[cpu_index] != MESI_INVALID) &&
                     (tag_q[cpu_index] == cpu_tag);

  assign snoop_index    = snoop_addr_q[INDEX_W+1:2];
  assign snoop_tag      = snoop_addr_q[31:INDEX_W+2];
  assign snoop_line_hit = (line_state_q[snoop_index] != MESI_INVALID) &&
                          (tag_q[snoop_index] == snoop_tag);

  assign effective_write_addr = aw_hold_q ? addr_q : s_axi.awaddr;
  assign effective_write_data = w_hold_q ? wdata_q : s_axi.wdata;
  assign effective_write_strb = w_hold_q ? wstrb_q : s_axi.wstrb;
  assign write_pair_ready =
    (aw_hold_q || s_axi.awvalid) &&
    (w_hold_q  || s_axi.wvalid);

  // One lookup port for CPU acceptance. A read is accepted only when no AW/W
  // is pending (see s_axi.arready), so the read and write index never compete.
  assign accept_is_read  = s_axi.arvalid && !aw_hold_q && !w_hold_q &&
                           !s_axi.awvalid && !s_axi.wvalid;
  assign accept_index    = accept_is_read ? s_axi.araddr[INDEX_W+1:2]
                                          : effective_write_addr[INDEX_W+1:2];
  assign accept_tag      = accept_is_read ? s_axi.araddr[31:INDEX_W+2]
                                          : effective_write_addr[31:INDEX_W+2];
  assign accept_state    = line_state_q[accept_index];
  assign accept_line_tag = tag_q[accept_index];
  assign accept_data     = data_q[accept_index];

  assign hit_count_o        = hit_count_q;
  assign miss_count_o       = miss_count_q;
  assign writeback_count_o  = writeback_count_q;
  assign invalidate_count_o = invalidate_count_q;
  assign coh.snoop_ack      = (snoop_state_q == S_ACK) || (snoop_state_q == S_NACK);
  assign coh.snoop_hit      = snoop_hit_q;
  assign coh.snoop_err      = (snoop_state_q == S_NACK);
  assign coh.req_valid      = (main_state_q == M_COH_REQ);
  assign coh.req_cmd        = req_cmd_q;
  assign coh.req_addr       = addr_q;

  assign main_axi_active = (main_state_q == M_EVICT_SEND) ||
                           (main_state_q == M_EVICT_RESP) ||
                           (main_state_q == M_MEM_READ_ADDR) ||
                           (main_state_q == M_MEM_READ_DATA) ||
                           (main_state_q == M_BYPASS_WRITE_SEND) ||
                           (main_state_q == M_BYPASS_WRITE_RESP);
  assign snoop_axi_active = (snoop_state_q == S_WB_SEND) ||
                            (snoop_state_q == S_WB_RESP);
  assign snoop_needs_wb =
    (line_state_q[coh.snoop_addr[INDEX_W+1:2]] == MESI_MODIFIED) &&
    (tag_q[coh.snoop_addr[INDEX_W+1:2]] == coh.snoop_addr[31:INDEX_W+2]);
  // M_COH_APPLY is about to enter a NoC state, so it also blocks dirty snoops.
  assign snoop_start = (snoop_state_q == S_IDLE) && coh.snoop_valid &&
    (!snoop_needs_wb || (!main_axi_active && main_state_q != M_COH_APPLY));
  assign main_install = (main_state_q == M_MEM_READ_DATA) && m_axi.rvalid &&
                        cacheable(addr_q) && (m_axi.rresp == 2'b00);
  assign snoop_apply = (snoop_state_q == S_APPLY) && snoop_line_hit &&
                       !(main_install && cpu_index == snoop_index);

  always_comb begin
    main_state_d  = main_state_q;
    snoop_state_d = snoop_state_q;

    s_axi.awready = 1'b0;
    s_axi.wready  = 1'b0;
    s_axi.bvalid  = 1'b0;
    s_axi.bresp   = resp_q;
    s_axi.arready = 1'b0;
    s_axi.rvalid  = 1'b0;
    s_axi.rdata   = resp_data_q;
    s_axi.rresp   = resp_q;

    m_axi.awaddr  = addr_q;
    m_axi.awvalid = 1'b0;
    m_axi.wdata   = wdata_q;
    m_axi.wstrb   = wstrb_q;
    m_axi.wvalid  = 1'b0;
    m_axi.bready  = 1'b0;
    m_axi.araddr  = addr_q;
    m_axi.arvalid = 1'b0;
    m_axi.rready  = 1'b0;

    coh.complete  = 1'b0;

    unique case (main_state_q)
      M_IDLE: begin
        // Snoop control wins acceptance of a new CPU operation.
        if (!coh.snoop_valid && snoop_state_q == S_IDLE) begin
          s_axi.arready = !aw_hold_q && !w_hold_q &&
                          !s_axi.awvalid && !s_axi.wvalid;
          // AW/W have priority if channels arrive together. Do not gate both
          // read and write READY by the opposing VALID (that deadlocks).
          s_axi.awready = !aw_hold_q;
          s_axi.wready  = !w_hold_q;

          if (s_axi.arvalid && s_axi.arready) begin
            if (!cacheable(s_axi.araddr))
              main_state_d = M_MEM_READ_ADDR;
            else begin
              if ((accept_state != MESI_INVALID) && accept_line_tag == accept_tag)
                main_state_d = M_READ_RESP;
              else if (accept_state == MESI_MODIFIED)
                main_state_d = M_EVICT_SEND;
              else
                main_state_d = M_COH_REQ;
            end
          end else if (write_pair_ready) begin
            if (!cacheable(effective_write_addr))
              main_state_d = M_BYPASS_WRITE_SEND;
            else begin
              if ((accept_state == MESI_MODIFIED ||
                   accept_state == MESI_EXCLUSIVE) && accept_line_tag == accept_tag)
                main_state_d = M_WRITE_RESP;
              else if (accept_state == MESI_SHARED && accept_line_tag == accept_tag)
                main_state_d = M_COH_REQ;
              else if (accept_state == MESI_MODIFIED)
                main_state_d = M_EVICT_SEND;
              else
                main_state_d = M_COH_REQ;
            end
          end
        end
      end

      M_READ_RESP: begin
        s_axi.rvalid = 1'b1;
        if (s_axi.rready) main_state_d = M_IDLE;
      end

      M_WRITE_RESP: begin
        s_axi.bvalid = 1'b1;
        if (s_axi.bready) main_state_d = M_IDLE;
      end

      M_EVICT_SEND: begin
        m_axi.awaddr  = evict_addr_q;
        m_axi.awvalid = !aw_done_q;
        m_axi.wdata   = evict_data_q;
        m_axi.wstrb   = 4'hf;
        m_axi.wvalid  = !w_done_q;
        if ((aw_done_q || m_axi.awready) && (w_done_q || m_axi.wready))
          main_state_d = M_EVICT_RESP;
      end

      M_EVICT_RESP: begin
        m_axi.bready = 1'b1;
        if (m_axi.bvalid)
          main_state_d = (m_axi.bresp == 0) ? M_COH_REQ :
                         (write_q ? M_WRITE_RESP : M_READ_RESP);
      end

      M_COH_REQ: begin
        if (coh.grant) main_state_d = M_COH_APPLY;
      end

      M_COH_APPLY: begin
        if (grant_err_q) begin
          // Peer kept its dirty copy: fail this access without touching state.
          coh.complete = 1'b1;
          main_state_d = write_q ? M_WRITE_RESP : M_READ_RESP;
        end else if (req_cmd_q == COH_UPGRADE) begin
          coh.complete = 1'b1;
          main_state_d = M_WRITE_RESP;
        end else begin
          main_state_d = M_MEM_READ_ADDR;
        end
      end

      M_MEM_READ_ADDR: begin
        m_axi.araddr  = addr_q;
        m_axi.arvalid = 1'b1;
        if (m_axi.arready) main_state_d = M_MEM_READ_DATA;
      end

      M_MEM_READ_DATA: begin
        m_axi.rready = 1'b1;
        if (m_axi.rvalid) begin
          if (cacheable(addr_q)) coh.complete = 1'b1;
          main_state_d = write_q ? M_WRITE_RESP : M_READ_RESP;
        end
      end

      M_BYPASS_WRITE_SEND: begin
        m_axi.awaddr  = addr_q;
        m_axi.awvalid = !aw_done_q;
        m_axi.wdata   = wdata_q;
        m_axi.wstrb   = wstrb_q;
        m_axi.wvalid  = !w_done_q;
        if ((aw_done_q || m_axi.awready) && (w_done_q || m_axi.wready))
          main_state_d = M_BYPASS_WRITE_RESP;
      end

      M_BYPASS_WRITE_RESP: begin
        // Response is captured in resp_q and replayed from M_WRITE_RESP.
        m_axi.bready = 1'b1;
        if (m_axi.bvalid) main_state_d = M_WRITE_RESP;
      end

      default: main_state_d = M_IDLE;
    endcase

    // Snoop FSM is independent while the main FSM is waiting for coherence.
    unique case (snoop_state_q)
      S_IDLE: begin
        if (snoop_start)
          snoop_state_d = snoop_needs_wb ? S_WB_SEND : S_APPLY;
      end

      S_WB_SEND: begin
        m_axi.awaddr  = snoop_addr_q;
        m_axi.awvalid = !snoop_aw_done_q;
        m_axi.wdata   = snoop_data_q;
        m_axi.wstrb   = 4'hf;
        m_axi.wvalid  = !snoop_w_done_q;
        if ((snoop_aw_done_q || m_axi.awready) &&
            (snoop_w_done_q || m_axi.wready))
          snoop_state_d = S_WB_RESP;
      end

      S_WB_RESP: begin
        m_axi.bready = 1'b1;
        // Preserve dirty ownership and retry; never acknowledge a failed WB
        // as success. After the retry budget the snoop is refused (S_NACK).
        if (m_axi.bvalid)
          snoop_state_d = (m_axi.bresp == 0) ? S_APPLY :
                          (snoop_retry_q == RETRY_W'(WB_RETRY_LIMIT - 1)) ? S_NACK : S_WB_SEND;
      end

      S_APPLY: snoop_state_d = S_ACK;

      S_ACK: begin
        snoop_state_d = S_WAIT_DROP;
      end

      S_NACK: snoop_state_d = S_WAIT_DROP;

      S_WAIT_DROP: if (!coh.snoop_valid) snoop_state_d = S_IDLE;
      default: snoop_state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      main_state_q <= M_IDLE;
      snoop_state_q <= S_IDLE;
      addr_q <= '0;
      wdata_q <= '0;
      wstrb_q <= '0;
      resp_data_q <= '0;
      resp_q <= 2'b00;
      write_q <= 1'b0;
      req_cmd_q <= COH_GETS;
      grant_shared_q <= 1'b0;
      grant_err_q <= 1'b0;
      aw_hold_q <= 1'b0;
      w_hold_q <= 1'b0;
      aw_done_q <= 1'b0;
      w_done_q <= 1'b0;
      evict_addr_q <= '0;
      evict_data_q <= '0;
      snoop_addr_q <= '0;
      snoop_data_q <= '0;
      snoop_cmd_q <= SNOOP_READ_SHARED;
      snoop_hit_q <= 1'b0;
      snoop_aw_done_q <= 1'b0;
      snoop_w_done_q <= 1'b0;
      snoop_retry_q <= '0;
      hit_count_q <= '0;
      miss_count_q <= '0;
      writeback_count_q <= '0;
      invalidate_count_q <= '0;
      for (int i = 0; i < LINES; i++) begin
        // Invalid state hides uninitialized payload/tag after reset.
        line_state_q[i] <= MESI_INVALID;
      end
    end else begin
      main_state_q <= main_state_d;
      snoop_state_q <= snoop_state_d;

      if (main_state_q == M_IDLE && !coh.snoop_valid && snoop_state_q == S_IDLE) begin
        if (s_axi.awvalid && s_axi.awready) begin
          addr_q <= s_axi.awaddr;
          aw_hold_q <= 1'b1;
        end
        if (s_axi.wvalid && s_axi.wready) begin
          wdata_q <= s_axi.wdata;
          wstrb_q <= s_axi.wstrb;
          w_hold_q <= 1'b1;
        end

        if (s_axi.arvalid && s_axi.arready) begin
          addr_q <= s_axi.araddr;
          write_q <= 1'b0;
          resp_q <= 2'b00;
          if (cacheable(s_axi.araddr)) begin
            if ((accept_state != MESI_INVALID) && accept_line_tag == accept_tag) begin
              resp_data_q <= accept_data;
              hit_count_q <= hit_count_q + 1'b1;
            end else begin
              req_cmd_q <= COH_GETS;
              miss_count_q <= miss_count_q + 1'b1;
              if (accept_state == MESI_MODIFIED) begin
                evict_addr_q <= {accept_line_tag, accept_index, 2'b00};
                evict_data_q <= accept_data;
              end
            end
          end
        end

        if (write_pair_ready) begin
          addr_q <= effective_write_addr;
          wdata_q <= effective_write_data;
          wstrb_q <= effective_write_strb;
          write_q <= 1'b1;
          resp_q <= 2'b00;
          aw_hold_q <= 1'b0;
          w_hold_q <= 1'b0;
          if (cacheable(effective_write_addr)) begin
            if ((accept_state == MESI_MODIFIED ||
                 accept_state == MESI_EXCLUSIVE) && accept_line_tag == accept_tag) begin
              // The data merge goes through the shared data write port.
              line_state_q[accept_index] <= MESI_MODIFIED;
              hit_count_q <= hit_count_q + 1'b1;
            end else begin
              miss_count_q <= miss_count_q + 1'b1;
              if (accept_state == MESI_SHARED && accept_line_tag == accept_tag)
                req_cmd_q <= COH_UPGRADE;
              else
                req_cmd_q <= COH_GETM;
              if (accept_state == MESI_MODIFIED) begin
                evict_addr_q <= {accept_line_tag, accept_index, 2'b00};
                evict_data_q <= accept_data;
              end
            end
          end
        end
      end

      if (main_state_q == M_EVICT_SEND) begin
        if (m_axi.awvalid && m_axi.awready) aw_done_q <= 1'b1;
        if (m_axi.wvalid && m_axi.wready) w_done_q <= 1'b1;
      end
      if (main_state_q == M_EVICT_RESP && m_axi.bvalid && m_axi.bready) begin
        aw_done_q <= 1'b0;
        w_done_q <= 1'b0;
        if (m_axi.bresp == 0) begin
          writeback_count_q <= writeback_count_q + 1'b1;
          line_state_q[cpu_index] <= MESI_INVALID;
        end else begin
          resp_q <= m_axi.bresp;
          resp_data_q <= 0;
        end
      end

      if (main_state_q == M_BYPASS_WRITE_SEND) begin
        if (m_axi.awvalid && m_axi.awready) aw_done_q <= 1'b1;
        if (m_axi.wvalid && m_axi.wready) w_done_q <= 1'b1;
      end
      if (main_state_q == M_BYPASS_WRITE_RESP && m_axi.bvalid && m_axi.bready) begin
        aw_done_q <= 1'b0;
        w_done_q <= 1'b0;
        resp_q <= m_axi.bresp;
      end

      if (main_state_q == M_COH_REQ && coh.grant) begin
        grant_shared_q <= coh.grant_shared;
        grant_err_q <= coh.grant_err;
      end

      if (main_state_q == M_COH_APPLY && grant_err_q) begin
        resp_q <= 2'b10;
        resp_data_q <= '0;
      end

      if (main_state_q == M_COH_APPLY && req_cmd_q == COH_UPGRADE && !grant_err_q)
        line_state_q[cpu_index] <= MESI_MODIFIED;

      if (main_state_q == M_MEM_READ_DATA && m_axi.rvalid && m_axi.rready) begin
        resp_q <= m_axi.rresp;
        if (cacheable(addr_q) && m_axi.rresp == 2'b00) begin
          tag_q[cpu_index] <= cpu_tag;
          if (write_q) begin
            line_state_q[cpu_index] <= MESI_MODIFIED;
            resp_data_q <= '0;
          end else begin
            line_state_q[cpu_index] <= grant_shared_q ? MESI_SHARED : MESI_EXCLUSIVE;
            resp_data_q <= m_axi.rdata;
          end
        end else begin
          resp_data_q <= m_axi.rdata;
        end
      end

      if (snoop_start) begin
        snoop_addr_q <= coh.snoop_addr;
        snoop_cmd_q <= coh.snoop_cmd;
        snoop_hit_q <= ((line_state_q[coh.snoop_addr[INDEX_W+1:2]] != MESI_INVALID) &&
                        (tag_q[coh.snoop_addr[INDEX_W+1:2]] ==
                         coh.snoop_addr[31:INDEX_W+2]));
        snoop_data_q <= data_q[coh.snoop_addr[INDEX_W+1:2]];
        snoop_retry_q <= '0;
      end

      if (snoop_state_q == S_WB_SEND) begin
        if (m_axi.awvalid && m_axi.awready) snoop_aw_done_q <= 1'b1;
        if (m_axi.wvalid && m_axi.wready) snoop_w_done_q <= 1'b1;
      end
      if (snoop_state_q == S_WB_RESP && m_axi.bvalid && m_axi.bready) begin
        snoop_aw_done_q <= 1'b0;
        snoop_w_done_q <= 1'b0;
        if (m_axi.bresp == 0) writeback_count_q <= writeback_count_q + 1'b1;
        else snoop_retry_q <= snoop_retry_q + 1'b1;
      end

      if (snoop_apply) begin
        if (snoop_cmd_q == SNOOP_INVALIDATE) begin
          line_state_q[snoop_index] <= MESI_INVALID;
          invalidate_count_q <= invalidate_count_q + 1'b1;
          // A queued S->M upgrade no longer has valid data after a competing
          // writer invalidates it. Reload the word before merging byte stores.
          if(main_state_q==M_COH_REQ && req_cmd_q==COH_UPGRADE &&
             addr_q[31:2]==snoop_addr_q[31:2])req_cmd_q<=COH_GETM;
        end else begin
          line_state_q[snoop_index] <= MESI_SHARED;
        end
      end
    end
  end

  // Shared data-array write port. Conditions mirror the three original writes
  // exactly (same states, same hit/fill qualifiers, no write during reset).
  assign data_we_hit = (main_state_q == M_IDLE) && !coh.snoop_valid &&
                       (snoop_state_q == S_IDLE) && write_pair_ready &&
                       cacheable(effective_write_addr) &&
                       (accept_state == MESI_MODIFIED || accept_state == MESI_EXCLUSIVE) &&
                       (accept_line_tag == accept_tag);
  assign data_we_upgrade = (main_state_q == M_COH_APPLY) && (req_cmd_q == COH_UPGRADE) &&
                           !grant_err_q;
  assign data_we_fill = (main_state_q == M_MEM_READ_DATA) && m_axi.rvalid && m_axi.rready &&
                        cacheable(addr_q) && (m_axi.rresp == 2'b00);
  assign data_we = rst_ni && (data_we_hit || data_we_upgrade || data_we_fill);

  always_comb begin
    data_waddr = cpu_index;
    data_wdata = write_q ? merge_bytes(m_axi.rdata, wdata_q, wstrb_q) : m_axi.rdata;
    if (data_we_hit) begin
      data_waddr = accept_index;
      data_wdata = merge_bytes(accept_data, effective_write_data, effective_write_strb);
    end else if (data_we_upgrade) begin
      data_wdata = merge_bytes(data_q[cpu_index], wdata_q, wstrb_q);
    end
  end

  // No reset: the Invalid state hides uninitialized payload after reset.
  always_ff @(posedge clk_i)
    if (data_we) data_q[data_waddr] <= data_wdata;

`ifndef SYNTHESIS
  initial begin
    assert (LINES >= 2 && (LINES & (LINES - 1)) == 0)
      else $fatal(1, "MESI cache LINES must be a power of two");
    assert (WB_RETRY_LIMIT >= 1)
      else $fatal(1, "MESI cache WB_RETRY_LIMIT must be at least one");
  end

  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(main_axi_active && snoop_axi_active))
        else $error("MESI cache attempted two AXI operations at once");
      // Step 1 sharing preconditions: one data writer per cycle, and the
      // shared accept index selects the address of the channel being accepted.
      assert ($onehot0({data_we_hit, data_we_upgrade, data_we_fill}))
        else $error("MESI data array has more than one writer in a cycle");
      if (s_axi.arvalid && s_axi.arready)
        assert (accept_is_read) else $error("MESI accept index not on AR for a read accept");
      if (main_state_q == M_IDLE && !coh.snoop_valid && snoop_state_q == S_IDLE && write_pair_ready)
        assert (!accept_is_read) else $error("MESI accept index not on AW for a write accept");
      // Concurrent snoops must never target the word the main FSM is fetching.
      if (snoop_state_q != S_IDLE && main_axi_active && main_state_q == M_MEM_READ_DATA &&
          cacheable(addr_q))
        assert (snoop_addr_q[31:2] != addr_q[31:2])
          else $error("MESI snoop overlaps the in-flight miss address");
      // A refused snoop must leave the dirty owner untouched.
      if (snoop_state_q == S_NACK)
        assert (line_state_q[snoop_index] == MESI_MODIFIED && tag_q[snoop_index] == snoop_tag)
          else $error("MESI snoop NACK without a retained dirty line");
    end
  end
`endif
endmodule

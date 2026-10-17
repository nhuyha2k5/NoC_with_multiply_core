`timescale 1ns/1ps
// Four-cache MESI verification (Step 2): four mesi_dcache instances and the
// N-core coherence_manager on the 3x3 mesh. Caches sit at the corner nodes
// (0,0) (0,2) (2,0) (2,2) as planned for the 4-core SoC; the RAM endpoint is
// the centre node (1,1). Checks:
//  - per-cycle single-writer/multiple-reader invariant over all cache pairs
//    (valid at every cycle in this design: peers apply a snoop before they
//    acknowledge it and the requester changes state only after the grant);
//  - snoop fan-out: every transaction snoops each of the three peers exactly
//    once, never the requester, with the requester's address and command;
//  - one write invalidates all three sharers; GETS with sharers installs S;
//  - dirty intervention between every ordered pair of cores;
//  - migratory read-modify-write; 4-way concurrent byte-store races;
//  - reference-model random transfers; 4-core concurrent stress with per-byte
//    ownership and per-location coherence order;
//  - refused dirty write-back (transient and persistent) with four cores;
//  - reset in the middle of 4-core traffic, then full recovery.
// Run with -gEARLY_RELEASE=0 for the serialised manager.
module tb_mesi_coherence_4core #(
  parameter bit EARLY_RELEASE = 1'b1
);
  import coherence_pkg::*;
  localparam int N = 4;
  localparam int LINES = 8;
  localparam int TAG_W = 32 - $clog2(LINES) - 2;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  function automatic int node_of(input int c);
    case (c)
      0: return 0;   // (0,0)
      1: return 2;   // (0,2)
      2: return 6;   // (2,0)
      default: return 8; // (2,2)
    endcase
  endfunction

  // ---------------------------------------------------------------- fabric
  wire  [33:0] tx_flit[0:8];
  wire         tx_valid[0:8], tx_vc[0:8];
  wire  [1:0]  rx_credit[0:8];
  logic [33:0] rx_flit[0:8];
  logic        rx_valid[0:8], rx_vc[0:8];
  logic [1:0]  tx_credit[0:8];

  for (genvar n = 0; n < 9; n++) begin : g_tie
    if (n == 1 || n == 3 || n == 5 || n == 7) begin : g_unused
      assign tx_flit[n] = '0;
      assign tx_valid[n] = 1'b0;
      assign tx_vc[n] = 1'b0;
      assign rx_credit[n] = '0;
    end
  end

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni,
    .local_tx_flit_i(tx_flit), .local_tx_valid_i(tx_valid),
    .local_tx_vc_i(tx_vc), .local_tx_credit_o(tx_credit),
    .local_rx_flit_o(rx_flit), .local_rx_valid_o(rx_valid),
    .local_rx_vc_o(rx_vc), .local_rx_credit_i(rx_credit)
  );

  axi_lite_if ram_axi(clk_i, rst_ni);
  mesh_to_axi_lite #(.CURRENT_X(1), .CURRENT_Y(1)) u_ram_ni (
    .clk_i, .rst_ni, .rx_flit_i(rx_flit[4]), .rx_valid_i(rx_valid[4]), .rx_vc_i(rx_vc[4]),
    .rx_credit_o(rx_credit[4]), .tx_flit_o(tx_flit[4]), .tx_valid_o(tx_valid[4]),
    .tx_vc_o(tx_vc[4]), .tx_credit_i(tx_credit[4]), .m_axi(ram_axi)
  );
  axi_lite_ram #(.WORDS(256)) u_ram (.clk_i, .rst_ni, .s_axi(ram_axi));

  // ---------------------------------------------------------------- caches
  axi_lite_if  cpu_axi[N](clk_i, rst_ni);
  axi_lite_if  noc_axi[N](clk_i, rst_ni);
  coherence_if coh[N](clk_i, rst_ni);

  logic [N-1:0]       req_valid, complete, grant, snoop_valid, snoop_ack, snoop_hit, snoop_err;
  logic [N-1:0][1:0]  req_cmd;
  logic [N-1:0][31:0] req_addr;
  logic               grant_shared, grant_err, snoop_cmd;
  logic [31:0]        snoop_addr;
  logic [31:0]        hits[N], misses[N], wbs[N], invs[N];

  // Probes into each cache for the invariant and coverage monitors.
  mesi_state_e      st[N][LINES];
  logic [TAG_W-1:0] tg[N][LINES];
  logic [31:0]      dt[N][LINES];
  logic             fetching[N], snoop_during_fetch[N], install_skip[N];

  for (genvar g = 0; g < N; g++) begin : g_core
    localparam int NODE = node_of(g);
    mesi_dcache #(.LINES(LINES)) u_cache (
      .clk_i, .rst_ni, .s_axi(cpu_axi[g]), .m_axi(noc_axi[g]), .coh(coh[g]),
      .hit_count_o(hits[g]), .miss_count_o(misses[g]),
      .writeback_count_o(wbs[g]), .invalidate_count_o(invs[g])
    );
    axi_lite_to_mesh #(.CURRENT_X(2'(NODE / 3)), .CURRENT_Y(2'(NODE % 3))) u_ni (
      .clk_i, .rst_ni, .s_axi(noc_axi[g]),
      .tx_flit_o(tx_flit[NODE]), .tx_valid_o(tx_valid[NODE]), .tx_vc_o(tx_vc[NODE]),
      .tx_credit_i(tx_credit[NODE]), .rx_flit_i(rx_flit[NODE]),
      .rx_valid_i(rx_valid[NODE]), .rx_vc_i(rx_vc[NODE]), .rx_credit_o(rx_credit[NODE])
    );
    assign req_valid[g] = coh[g].req_valid;
    assign req_cmd[g]   = coh[g].req_cmd;
    assign req_addr[g]  = coh[g].req_addr;
    assign complete[g]  = coh[g].complete;
    assign snoop_ack[g] = coh[g].snoop_ack;
    assign snoop_hit[g] = coh[g].snoop_hit;
    assign snoop_err[g] = coh[g].snoop_err;
    assign coh[g].grant        = grant[g];
    assign coh[g].grant_shared = grant_shared;
    assign coh[g].grant_err    = grant_err;
    assign coh[g].snoop_valid  = snoop_valid[g];
    assign coh[g].snoop_cmd    = snoop_cmd;
    assign coh[g].snoop_addr   = snoop_addr;
    for (genvar i = 0; i < LINES; i++) begin : g_probe
      assign st[g][i] = u_cache.line_state_q[i];
      assign tg[g][i] = u_cache.tag_q[i];
      assign dt[g][i] = u_cache.data_q[i];
    end
    assign fetching[g] = u_cache.main_state_q inside {u_cache.M_MEM_READ_ADDR, u_cache.M_MEM_READ_DATA};
    assign snoop_during_fetch[g] = u_cache.snoop_start && u_cache.main_axi_active;
    assign install_skip[g] = u_cache.snoop_state_q == u_cache.S_APPLY && u_cache.main_install &&
                             u_cache.cpu_index == u_cache.snoop_index;
  end

  coherence_manager #(.N_CORES(N), .EARLY_RELEASE(EARLY_RELEASE)) u_manager (
    .clk_i, .rst_ni,
    .req_valid_i(req_valid), .req_cmd_i(req_cmd), .req_addr_i(req_addr), .complete_i(complete),
    .grant_o(grant), .grant_shared_o(grant_shared), .grant_err_o(grant_err),
    .snoop_valid_o(snoop_valid), .snoop_cmd_o(snoop_cmd), .snoop_addr_o(snoop_addr),
    .snoop_ack_i(snoop_ack), .snoop_hit_i(snoop_hit), .snoop_err_i(snoop_err)
  );

  // ---------------------------------------------------------------- drivers
  virtual axi_lite_if vcpu[N];
  initial begin
    vcpu[0] = cpu_axi[0]; vcpu[1] = cpu_axi[1]; vcpu[2] = cpu_axi[2]; vcpu[3] = cpu_axi[3];
    for (int c = 0; c < N; c++) idle(c);
  end

  function automatic void idle(input int c);
    vcpu[c].awaddr = '0; vcpu[c].awvalid = 1'b0; vcpu[c].wdata = '0; vcpu[c].wstrb = '0;
    vcpu[c].wvalid = 1'b0; vcpu[c].bready = 1'b0; vcpu[c].araddr = '0; vcpu[c].arvalid = 1'b0;
    vcpu[c].rready = 1'b0;
  endfunction

  task automatic cpu_read(input int c, input logic [31:0] addr, output logic [31:0] data,
                          input logic [1:0] expected_resp = 2'b00);
    virtual axi_lite_if v;
    v = vcpu[c];
    @(negedge clk_i);
    v.araddr = addr;
    v.arvalid = 1'b1;
    v.rready = 1'b1;
    do @(posedge clk_i); while (!v.arready);
    @(negedge clk_i);
    v.arvalid = 1'b0;
    v.araddr = $urandom;   // AXI: payload is don't-care once VALID is low
    while (!v.rvalid) @(posedge clk_i);
    data = v.rdata;
    assert (v.rresp == expected_resp)
      else $fatal(1, "CPU%0d read %h response %0d, expected %0d", c, addr, v.rresp, expected_resp);
    @(negedge clk_i);
    v.rready = 1'b0;
  endtask

  task automatic cpu_write(input int c, input logic [31:0] addr, input logic [31:0] data,
                           input logic [3:0] strb = 4'hf, input logic [1:0] expected_resp = 2'b00);
    virtual axi_lite_if v;
    bit aw_done, w_done;
    v = vcpu[c];
    aw_done = 0;
    w_done = 0;
    @(negedge clk_i);
    v.awaddr = addr;
    v.awvalid = 1'b1;
    v.wdata = data;
    v.wstrb = strb;
    v.wvalid = 1'b1;
    v.bready = 1'b1;
    while (!aw_done || !w_done) begin
      @(posedge clk_i);
      if (v.awvalid && v.awready) aw_done = 1;
      if (v.wvalid && v.wready) w_done = 1;
      @(negedge clk_i);
      if (aw_done) begin v.awvalid = 1'b0; v.awaddr = $urandom; end
      if (w_done) begin v.wvalid = 1'b0; v.wdata = $urandom; v.wstrb = 4'($urandom); end
    end
    while (!v.bvalid) @(posedge clk_i);
    assert (v.bresp == expected_resp)
      else $fatal(1, "CPU%0d write %h response %0d, expected %0d", c, addr, v.bresp, expected_resp);
    @(negedge clk_i);
    v.bready = 1'b0;
  endtask

  // State of word addr in cache c (Invalid if absent).
  function automatic mesi_state_e state_of(input int c, input logic [31:0] addr);
    int i;
    i = int'(addr[$clog2(LINES)+1:2]);
    if (st[c][i] != MESI_INVALID && tg[c][i] == addr[31:$clog2(LINES)+2]) return st[c][i];
    return MESI_INVALID;
  endfunction

  // ---------------------------------------------------------------- monitors
  int checked_cycles = 0, transactions = 0, grants_per_core[N];
  int ack_seen[N];
  int max_inflight = 0, inflight_ge2 = 0, inflight_ge3 = 0, inflight_4 = 0;
  int fetch_ge2 = 0, fetch_ge3 = 0, clean_snoop_during_fetch = 0, same_index_install = 0;
  int multi_peer_hits = 0, nacks = 0;
  initial for (int c = 0; c < N; c++) begin grants_per_core[c] = 0; ack_seen[c] = 0; end

  always @(negedge clk_i) begin
    if (!rst_ni) begin
      for (int c = 0; c < N; c++) ack_seen[c] = 0;
    end else begin
      int nf, ni, nh;
      checked_cycles++;
      // Single writer / multiple readers, and identical Shared copies.
      for (int i = 0; i < LINES; i++)
        for (int a = 0; a < N; a++)
          for (int b = a + 1; b < N; b++)
            if (st[a][i] != MESI_INVALID && st[b][i] != MESI_INVALID && tg[a][i] == tg[b][i]) begin
              assert (st[a][i] == MESI_SHARED && st[b][i] == MESI_SHARED)
                else $fatal(1, "MESI duplicate exclusive/dirty ownership (caches %0d/%0d index %0d)", a, b, i);
              assert (dt[a][i] == dt[b][i])
                else $fatal(1, "MESI shared copies differ (caches %0d/%0d index %0d)", a, b, i);
            end
      // Snoop fan-out: acks only for active snoops; at each grant every peer
      // acknowledged exactly once and the requester not at all.
      nh = 0;
      for (int h = 0; h < N; h++)
        if (snoop_ack[h]) begin
          assert (snoop_valid[h]) else $fatal(1, "MESI snoop ack without snoop (core %0d)", h);
          if (snoop_hit[h]) nh++;
          if (snoop_err[h]) nacks++;
          ack_seen[h]++;
        end
      for (int g = 0; g < N; g++)
        if (grant[g]) begin
          transactions++;
          grants_per_core[g]++;
          for (int h = 0; h < N; h++)
            assert (ack_seen[h] == ((h == g) ? 0 : 1))
              else $fatal(1, "MESI snoop fan-out wrong: requester %0d, core %0d acknowledged %0d snoops",
                          g, h, ack_seen[h]);
          assert (snoop_addr == req_addr[g])
            else $fatal(1, "MESI snoop address %h differs from request %h", snoop_addr, req_addr[g]);
          assert (snoop_cmd == ((req_cmd[g] == COH_GETS) ? SNOOP_READ_SHARED : SNOOP_INVALIDATE))
            else $fatal(1, "MESI snoop command does not match request %0d", req_cmd[g]);
          for (int h = 0; h < N; h++) ack_seen[h] = 0;
        end
      if (nh >= 2) multi_peer_hits++;
      // Concurrency coverage.
      ni = $countones(u_manager.inflight_q);
      nf = 0;
      for (int c = 0; c < N; c++) begin
        if (fetching[c]) nf++;
        if (snoop_during_fetch[c]) clean_snoop_during_fetch++;
        if (install_skip[c]) same_index_install++;
      end
      if (ni > max_inflight) max_inflight = ni;
      if (ni >= 2) inflight_ge2++;
      if (ni >= 3) inflight_ge3++;
      if (ni == 4) inflight_4++;
      if (nf >= 2) fetch_ge2++;
      if (nf >= 3) fetch_ge3++;
    end
  end

  // ---------------------------------------------------------------- tests
  logic [31:0] d;
  logic [31:0] reference_data[0:63];
  int wb_before_reset = 0, inv_before_reset = 0;

  task automatic all_read_shared(input logic [31:0] addr, input logic [31:0] expected);
    for (int c = 0; c < N; c++) begin
      cpu_read(c, addr, d);
      assert (d == expected) else $fatal(1, "CPU%0d read %h got %h expected %h", c, addr, d, expected);
    end
    for (int c = 0; c < N; c++)
      assert (state_of(c, addr) == MESI_SHARED)
        else $fatal(1, "CPU%0d not Shared after all cores read %h", c, addr);
  endtask

  // Concurrent stress: 24 words on 8 lines (conflict evictions). Core c owns
  // byte c of every word and writes increasing sequence numbers. It must read
  // back its own byte exactly and never see another core's byte go backwards
  // (per-location coherence order).
  int seq[N][24], seen[N][N][24];
  task automatic stress_core(input int c);
    logic [31:0] r, v;
    int w;
    r = 32'h13579bdf ^ (c * 32'h01234567);
    for (int t = 0; t < 1500; t++) begin
      r = r * 32'd1664525 + 32'd1013904223;
      w = int'((r >> 8) % 24);
      if (r[2]) begin
        seq[c][w]++;
        assert (seq[c][w] < 256) else $fatal(1, "Stress sequence overflow");
        cpu_write(c, 32'h20000200 + w * 4, 32'(seq[c][w]) << (8 * c), 4'b0001 << c);
      end else begin
        cpu_read(c, 32'h20000200 + w * 4, v);
        assert (int'(v[8*c +: 8]) == seq[c][w])
          else $fatal(1, "Core%0d lost its own store w=%0d got=%0d exp=%0d", c, w, v[8*c +: 8], seq[c][w]);
        for (int o = 0; o < N; o++)
          if (o != c) begin
            assert (int'(v[8*o +: 8]) >= seen[c][o][w])
              else $fatal(1, "Core%0d saw core%0d byte go backwards w=%0d", c, o, w);
            seen[c][o][w] = v[8*o +: 8];
          end
      end
      repeat (r[5:4]) @(negedge clk_i);
    end
  endtask

  task automatic random_traffic(input int c, input logic [31:0] seed);
    logic [31:0] r, x;
    r = seed;
    forever begin
      r = r * 32'd1664525 + 32'd1013904223;
      if (r[3]) cpu_write(c, 32'h20000100 + ((r >> 8) % 48) * 4, r ^ 32'h5a5a5a5a, r[7:4] | 4'b0001);
      else cpu_read(c, 32'h20000100 + ((r >> 8) % 48) * 4, x);
    end
  endtask

  initial begin
    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (3) @(posedge clk_i);

    // ---- E on a private read, S once shared, one write invalidates 3 sharers
    cpu_read(0, 32'h20000040, d);
    assert (d == 0 && state_of(0, 32'h20000040) == MESI_EXCLUSIVE) else $fatal(1, "Private read not Exclusive");
    cpu_read(1, 32'h20000040, d);
    assert (state_of(0, 32'h20000040) == MESI_SHARED && state_of(1, 32'h20000040) == MESI_SHARED)
      else $fatal(1, "E->S downgrade failed");
    cpu_read(2, 32'h20000040, d);
    cpu_read(3, 32'h20000040, d);
    assert (state_of(3, 32'h20000040) == MESI_SHARED) else $fatal(1, "GETS with three sharers did not install Shared");
    for (int w = 0; w < N; w++) begin
      int inv_before[N];
      all_read_shared(32'h20000040, w == 0 ? 32'h0 : 32'hc0de0000 + w - 1);
      for (int c = 0; c < N; c++) inv_before[c] = invs[c];
      cpu_write(w, 32'h20000040, 32'hc0de0000 + w);
      for (int c = 0; c < N; c++)
        if (c == w)
          assert (state_of(c, 32'h20000040) == MESI_MODIFIED) else $fatal(1, "Writer %0d not Modified", w);
        else begin
          assert (state_of(c, 32'h20000040) == MESI_INVALID)
            else $fatal(1, "Sharer %0d not invalidated by writer %0d", c, w);
          assert (invs[c] == inv_before[c] + 1)
            else $fatal(1, "Sharer %0d invalidated %0d times by one write", c, invs[c] - inv_before[c]);
        end
    end

    // ---- Dirty intervention between every ordered pair of cores
    for (int a = 0; a < N; a++)
      for (int b = 0; b < N; b++)
        if (a != b) begin
          logic [31:0] v;
          v = 32'h0d000000 | (a << 8) | b;
          cpu_write(a, 32'h20000060, v);
          cpu_read(b, 32'h20000060, d);
          assert (d == v) else $fatal(1, "Dirty intervention %0d->%0d returned %h expected %h", a, b, d, v);
          assert (state_of(a, 32'h20000060) == MESI_SHARED && state_of(b, 32'h20000060) == MESI_SHARED)
            else $fatal(1, "Dirty intervention %0d->%0d left wrong states", a, b);
        end

    // ---- Migratory read-modify-write by the four cores in turn
    cpu_write(0, 32'h20000068, 0);
    for (int k = 0; k < 100; k++) begin
      cpu_read(k % N, 32'h20000068, d);
      cpu_write(k % N, 32'h20000068, d + 1);
    end
    cpu_read(2, 32'h20000068, d);
    assert (d == 100) else $fatal(1, "Migratory counter %0d, expected 100", d);

    // ---- 4-way byte-store race on one Shared word (32 rounds)
    for (int t = 0; t < 32; t++) begin
      logic [31:0] init;
      init = 32'h01020304 * (t + 1);
      cpu_write(t % N, 32'h20000080, init);
      all_read_shared(32'h20000080, init);
      fork
        cpu_write(0, 32'h20000080, 32'h00000011, 4'b0001);
        cpu_write(1, 32'h20000080, 32'h00002200, 4'b0010);
        cpu_write(2, 32'h20000080, 32'h00330000, 4'b0100);
        cpu_write(3, 32'h20000080, 32'h44000000, 4'b1000);
      join
      for (int c = 0; c < N; c++) begin
        cpu_read(c, 32'h20000080, d);
        assert (d == 32'h44332211) else $fatal(1, "Concurrent MESI byte stores lost data: %h (round %0d)", d, t);
      end
    end

    // ---- Reference-model random transfers (sequential, byte strobes)
    for (int i = 0; i < 64; i++) begin reference_data[i] = 0; cpu_write(i % N, 32'h20000100 + i * 4, 0); end
    begin
      logic [31:0] r;
      int idx, c;
      r = 32'h0badc0de;
      for (int t = 0; t < 2000; t++) begin
        r = r * 32'd1664525 + 32'd1013904223;
        idx = int'((r >> 8) % 64);
        c = int'(r[5:4]);
        if (r[0]) begin
          logic [3:0] strb;
          logic [31:0] v;
          strb = r[3:1] == 0 ? 4'hf : {r[1], r[2], r[3], r[9]};
          if (strb == 0) strb = 4'b0100;
          v = r ^ 32'hdeadbeef;
          for (int b = 0; b < 4; b++) if (strb[b]) reference_data[idx][b*8 +: 8] = v[b*8 +: 8];
          cpu_write(c, 32'h20000100 + idx * 4, v, strb);
        end else begin
          cpu_read(c, 32'h20000100 + idx * 4, d);
          assert (d == reference_data[idx])
            else $fatal(1, "MESI random reference mismatch word %0d core %0d: %h vs %h", idx, c, d, reference_data[idx]);
        end
      end
      for (int i = 0; i < 64; i++) begin
        cpu_read(i % N, 32'h20000100 + i * 4, d);
        assert (d == reference_data[i]) else $fatal(1, "Final reference mismatch word %0d", i);
      end
    end

    // ---- Concurrent 4-core stress: 24 words on 8 lines (conflict evictions).
    // Core c owns byte c of every word and writes increasing sequence numbers.
    // Each core must read back its own byte exactly and never see another
    // core's byte go backwards (per-location coherence order).
    begin
      int tx_before;
      tx_before = transactions;
      for (int i = 0; i < 24; i++) begin
        for (int c = 0; c < N; c++) begin
          seq[c][i] = 0;
          for (int o = 0; o < N; o++) seen[c][o][i] = 0;
        end
        cpu_write(i % N, 32'h20000200 + i * 4, 0);
      end
      for (int cc = 0; cc < N; cc++) begin
        automatic int c = cc;
        fork
          stress_core(c);
        join_none
      end
      wait fork;
      for (int i = 0; i < 24; i++)
        for (int c = 0; c < N; c++) begin
          logic [31:0] expect_word;
          expect_word = {8'(seq[3][i]), 8'(seq[2][i]), 8'(seq[1][i]), 8'(seq[0][i])};
          cpu_read(c, 32'h20000200 + i * 4, d);
          assert (d == expect_word) else $fatal(1, "4-core stress final mismatch word %0d core %0d: %h vs %h", i, c, d, expect_word);
        end
      $display("MESI4_STRESS ops=6000 transactions=%0d max_inflight=%0d inflight_ge2=%0d inflight_ge3=%0d inflight_4=%0d fetch_ge2=%0d fetch_ge3=%0d clean_snoop_during_fetch=%0d same_index_install=%0d",
        transactions - tx_before, max_inflight, inflight_ge2, inflight_ge3, inflight_4, fetch_ge2, fetch_ge3,
        clean_snoop_during_fetch, same_index_install);
      if (EARLY_RELEASE)
        assert (max_inflight >= 3 && fetch_ge3 > 50 && clean_snoop_during_fetch > 100)
          else $fatal(1, "4-core overlapped-miss path not exercised (max_inflight=%0d fetch_ge3=%0d)", max_inflight, fetch_ge3);
    end

    // ---- Refused dirty write-back with four cores.
    // Make every peer hold a clean line at the victim's index first, so their
    // own evictions cannot fail while the backend is broken.
    for (int c = 1; c < N; c++) cpu_read(c, 32'h20000320, d);   // cores 1..3 clean at index 0
    cpu_write(0, 32'h20000300, 32'hcafef00d);
    // Transient failure: the owner retries, nobody is granted meanwhile.
    force u_ram.bresp_q = 2'b10;
    fork
      begin
        cpu_read(1, 32'h20000300, d);
        assert (d == 32'hcafef00d) else $fatal(1, "Snoop write-back retry corrupted data: %h", d);
      end
      begin
        repeat (100) @(negedge clk_i);
        assert (state_of(0, 32'h20000300) == MESI_MODIFIED && grant == 0)
          else $fatal(1, "Failed snoop write-back acknowledged before recovery");
        release u_ram.bresp_q;
      end
    join
    // Persistent failure, owner core 2 (a peer index above 1): every other
    // core's request gets SLVERR and the owner keeps its dirty line.
    cpu_write(2, 32'h20000300, 32'h0badf00d);
    assert (state_of(2, 32'h20000300) == MESI_MODIFIED) else $fatal(1, "NACK setup: core 2 not Modified");
    force u_ram.bresp_q = 2'b10;
    cpu_read(3, 32'h20000300, d, 2'b10);
    cpu_write(0, 32'h20000300, 32'h11111111, 4'hf, 2'b10);
    cpu_read(1, 32'h20000300, d, 2'b10);
    assert (state_of(2, 32'h20000300) == MESI_MODIFIED && dt[2][0] == 32'h0badf00d)
      else $fatal(1, "Refused snoop dropped or changed the dirty line");
    for (int c = 0; c < N; c++)
      if (c != 2)
        assert (state_of(c, 32'h20000300) == MESI_INVALID)
          else $fatal(1, "Core %0d installed a line after a coherence error", c);
    release u_ram.bresp_q;
    cpu_read(1, 32'h20000300, d);
    assert (d == 32'h0badf00d) else $fatal(1, "Recovery after NACK returned %h", d);
    cpu_write(0, 32'h20000300, 32'h22222222);
    cpu_read(3, 32'h20000300, d);
    assert (d == 32'h22222222) else $fatal(1, "Ownership transfer after NACK recovery failed");
    assert (nacks >= 3) else $fatal(1, "Expected three refused snoops, saw %0d", nacks);

    // ---- Reset in the middle of 4-core traffic, then full recovery.
    // Reset semantics: cache contents (including dirty data) are discarded,
    // RAM contents are kept, no transaction survives reset.
    wb_before_reset = wbs[0] + wbs[1] + wbs[2] + wbs[3];
    inv_before_reset = invs[0] + invs[1] + invs[2] + invs[3];
    begin
      fork
        random_traffic(0, 32'h11111111);
        random_traffic(1, 32'h22222222);
        random_traffic(2, 32'h33333333);
        random_traffic(3, 32'h44444444);
      join_none
      repeat (1500) @(negedge clk_i);
      disable fork;
      for (int c = 0; c < N; c++) idle(c);
      rst_ni = 1'b0;
      repeat (5) @(negedge clk_i);
      assert (u_manager.state_q == u_manager.IDLE && u_manager.inflight_q == 0 && grant == 0 && snoop_valid == 0)
        else $fatal(1, "Coherence manager not idle in reset");
      rst_ni = 1'b1;
      repeat (3) @(negedge clk_i);
      for (int c = 0; c < N; c++)
        for (int i = 0; i < LINES; i++)
          assert (st[c][i] == MESI_INVALID) else $fatal(1, "Cache %0d line %0d valid after reset", c, i);
      for (int i = 0; i < 48; i++) cpu_write(i % N, 32'h20000100 + i * 4, 32'h7e570000 + i);
      for (int a = 0; a < N; a++)
        for (int i = 0; i < 48; i += 5) begin
          cpu_read((a + 1) % N, 32'h20000100 + i * 4, d);
          assert (d == 32'h7e570000 + i) else $fatal(1, "Post-reset read word %0d returned %h", i, d);
        end
    end

    $display("MESI4_COVERAGE transactions=%0d grants=%0d/%0d/%0d/%0d multi_peer_hits=%0d nacks=%0d writebacks=%0d invalidates=%0d (before reset test; after: %0d/%0d) invariant_cycles=%0d",
      transactions, grants_per_core[0], grants_per_core[1], grants_per_core[2], grants_per_core[3],
      multi_peer_hits, nacks, wb_before_reset, inv_before_reset,
      wbs[0] + wbs[1] + wbs[2] + wbs[3], invs[0] + invs[1] + invs[2] + invs[3], checked_cycles);
    $display("TEST_PASS: 4-core MESI (EARLY_RELEASE=%0d): snoop fan-out to all 3 peers, per-cycle SWMR on 4 caches, 3-sharer invalidation, 12 dirty-intervention pairs, migratory RMW, 32 four-way byte-store races, 2000 reference transfers, 6000-op concurrent stress, NACK with 4 cores, reset mid-traffic",
      EARLY_RELEASE);
    $finish;
  end

  initial begin
    #20000000;
    $fatal(1, "Timeout waiting for 4-core MESI test");
  end
endmodule

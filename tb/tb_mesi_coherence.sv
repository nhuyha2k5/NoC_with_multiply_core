`timescale 1ns/1ps

module tb_mesi_coherence;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  axi_lite_if cpu0_axi(clk_i, rst_ni);
  axi_lite_if cpu1_axi(clk_i, rst_ni);
  axi_lite_if noc0_axi(clk_i, rst_ni);
  axi_lite_if noc1_axi(clk_i, rst_ni);
  axi_lite_if ram_axi(clk_i, rst_ni);
  coherence_if coh0(clk_i, rst_ni);
  coherence_if coh1(clk_i, rst_ni);

  logic [33:0] local_tx_flit[0:8], local_rx_flit[0:8];
  logic local_tx_valid[0:8], local_tx_vc[0:8];
  logic local_rx_valid[0:8], local_rx_vc[0:8];
  logic [1:0] local_tx_credit[0:8], local_rx_credit[0:8];
  logic [33:0] c0_tx_flit, c1_tx_flit, ram_tx_flit;
  logic c0_tx_valid, c1_tx_valid, ram_tx_valid;
  logic c0_tx_vc, c1_tx_vc, ram_tx_vc;
  logic [1:0] c0_rx_credit, c1_rx_credit, ram_rx_credit;
  logic [31:0] c0_hits, c0_misses, c0_writebacks, c0_invalidates;
  logic [31:0] c1_hits, c1_misses, c1_writebacks, c1_invalidates;

  always_comb begin
    for (int i = 0; i < 9; i++) begin
      local_tx_flit[i] = '0;
      local_tx_valid[i] = 1'b0;
      local_tx_vc[i] = 1'b0;
      local_rx_credit[i] = '0;
    end
    local_tx_flit[0] = c0_tx_flit;
    local_tx_valid[0] = c0_tx_valid;
    local_tx_vc[0] = c0_tx_vc;
    local_rx_credit[0] = c0_rx_credit;
    local_tx_flit[8] = c1_tx_flit;
    local_tx_valid[8] = c1_tx_valid;
    local_tx_vc[8] = c1_tx_vc;
    local_rx_credit[8] = c1_rx_credit;
    local_tx_flit[4] = ram_tx_flit;
    local_tx_valid[4] = ram_tx_valid;
    local_tx_vc[4] = ram_tx_vc;
    local_rx_credit[4] = ram_rx_credit;
  end

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni,
    .local_tx_flit_i(local_tx_flit), .local_tx_valid_i(local_tx_valid),
    .local_tx_vc_i(local_tx_vc), .local_tx_credit_o(local_tx_credit),
    .local_rx_flit_o(local_rx_flit), .local_rx_valid_o(local_rx_valid),
    .local_rx_vc_o(local_rx_vc), .local_rx_credit_i(local_rx_credit)
  );

  coherence_manager_2core u_manager (
    .clk_i, .rst_ni, .core0(coh0), .core1(coh1)
  );

  mesi_dcache #(.LINES(8)) u_cache0 (
    .clk_i, .rst_ni, .s_axi(cpu0_axi), .m_axi(noc0_axi), .coh(coh0),
    .hit_count_o(c0_hits), .miss_count_o(c0_misses),
    .writeback_count_o(c0_writebacks), .invalidate_count_o(c0_invalidates)
  );
  mesi_dcache #(.LINES(8)) u_cache1 (
    .clk_i, .rst_ni, .s_axi(cpu1_axi), .m_axi(noc1_axi), .coh(coh1),
    .hit_count_o(c1_hits), .miss_count_o(c1_misses),
    .writeback_count_o(c1_writebacks), .invalidate_count_o(c1_invalidates)
  );

  axi_lite_to_mesh #(.CURRENT_X(0), .CURRENT_Y(0)) u_ni0 (
    .clk_i, .rst_ni, .s_axi(noc0_axi),
    .tx_flit_o(c0_tx_flit), .tx_valid_o(c0_tx_valid), .tx_vc_o(c0_tx_vc),
    .tx_credit_i(local_tx_credit[0]), .rx_flit_i(local_rx_flit[0]),
    .rx_valid_i(local_rx_valid[0]), .rx_vc_i(local_rx_vc[0]),
    .rx_credit_o(c0_rx_credit)
  );
  axi_lite_to_mesh #(.CURRENT_X(2), .CURRENT_Y(2)) u_ni1 (
    .clk_i, .rst_ni, .s_axi(noc1_axi),
    .tx_flit_o(c1_tx_flit), .tx_valid_o(c1_tx_valid), .tx_vc_o(c1_tx_vc),
    .tx_credit_i(local_tx_credit[8]), .rx_flit_i(local_rx_flit[8]),
    .rx_valid_i(local_rx_valid[8]), .rx_vc_i(local_rx_vc[8]),
    .rx_credit_o(c1_rx_credit)
  );
  mesh_to_axi_lite #(.CURRENT_X(1), .CURRENT_Y(1)) u_ram_ni (
    .clk_i, .rst_ni, .rx_flit_i(local_rx_flit[4]),
    .rx_valid_i(local_rx_valid[4]), .rx_vc_i(local_rx_vc[4]),
    .rx_credit_o(ram_rx_credit), .tx_flit_o(ram_tx_flit),
    .tx_valid_o(ram_tx_valid), .tx_vc_o(ram_tx_vc),
    .tx_credit_i(local_tx_credit[4]), .m_axi(ram_axi)
  );
  axi_lite_ram #(.WORDS(256)) u_ram (.clk_i, .rst_ni, .s_axi(ram_axi));

  task automatic cpu0_read(input logic [31:0] addr, output logic [31:0] data,input logic[1:0] expected_resp=0);
    begin
      @(negedge clk_i);
      cpu0_axi.araddr = addr;
      cpu0_axi.arvalid = 1'b1;
      cpu0_axi.rready = 1'b1;
      do @(posedge clk_i); while (!cpu0_axi.arready);
      @(negedge clk_i);
      cpu0_axi.arvalid = 1'b0;
      cpu0_axi.araddr = $urandom; // AXI: payload is don't-care once VALID is low
      while (!cpu0_axi.rvalid) @(posedge clk_i);
      data = cpu0_axi.rdata;
      assert (cpu0_axi.rresp == expected_resp) else $fatal(1, "CPU0 read error");
      @(negedge clk_i);
      cpu0_axi.rready = 1'b0;
    end
  endtask

  task automatic cpu1_read(input logic [31:0] addr, output logic [31:0] data,input logic[1:0] expected_resp=0);
    begin
      @(negedge clk_i);
      cpu1_axi.araddr = addr;
      cpu1_axi.arvalid = 1'b1;
      cpu1_axi.rready = 1'b1;
      do @(posedge clk_i); while (!cpu1_axi.arready);
      @(negedge clk_i);
      cpu1_axi.arvalid = 1'b0;
      cpu1_axi.araddr = $urandom; // AXI: payload is don't-care once VALID is low
      while (!cpu1_axi.rvalid) @(posedge clk_i);
      data = cpu1_axi.rdata;
      assert (cpu1_axi.rresp == expected_resp) else $fatal(1, "CPU1 read response %0d, expected %0d", cpu1_axi.rresp, expected_resp);
      @(negedge clk_i);
      cpu1_axi.rready = 1'b0;
    end
  endtask

  task automatic cpu0_write(input logic [31:0] addr, input logic [31:0] data,input logic[3:0]strb=15,input logic[1:0] expected_resp=0);
    bit aw_done, w_done;
    begin
      aw_done = 0;
      w_done = 0;
      @(negedge clk_i);
      cpu0_axi.awaddr = addr;
      cpu0_axi.awvalid = 1'b1;
      cpu0_axi.wdata = data;
      cpu0_axi.wstrb = strb;
      cpu0_axi.wvalid = 1'b1;
      cpu0_axi.bready = 1'b1;
      while (!aw_done || !w_done) begin
        @(posedge clk_i);
        if (cpu0_axi.awvalid && cpu0_axi.awready) aw_done = 1;
        if (cpu0_axi.wvalid && cpu0_axi.wready) w_done = 1;
        @(negedge clk_i);
        if (aw_done) begin cpu0_axi.awvalid = 1'b0; cpu0_axi.awaddr = $urandom; end
        if (w_done) begin cpu0_axi.wvalid = 1'b0; cpu0_axi.wdata = $urandom; cpu0_axi.wstrb = 4'($urandom); end
      end
      while (!cpu0_axi.bvalid) @(posedge clk_i);
      assert (cpu0_axi.bresp == expected_resp) else $fatal(1, "CPU0 write response %0d, expected %0d", cpu0_axi.bresp, expected_resp);
      @(negedge clk_i);
      cpu0_axi.bready = 1'b0;
    end
  endtask

  task automatic cpu1_write(input logic [31:0] addr, input logic [31:0] data,input logic[3:0]strb=15,input logic[1:0] expected_resp=0);
    bit aw_done, w_done;
    begin
      aw_done = 0;
      w_done = 0;
      @(negedge clk_i);
      cpu1_axi.awaddr = addr;
      cpu1_axi.awvalid = 1'b1;
      cpu1_axi.wdata = data;
      cpu1_axi.wstrb = strb;
      cpu1_axi.wvalid = 1'b1;
      cpu1_axi.bready = 1'b1;
      while (!aw_done || !w_done) begin
        @(posedge clk_i);
        if (cpu1_axi.awvalid && cpu1_axi.awready) aw_done = 1;
        if (cpu1_axi.wvalid && cpu1_axi.wready) w_done = 1;
        @(negedge clk_i);
        if (aw_done) begin cpu1_axi.awvalid = 1'b0; cpu1_axi.awaddr = $urandom; end
        if (w_done) begin cpu1_axi.wvalid = 1'b0; cpu1_axi.wdata = $urandom; cpu1_axi.wstrb = 4'($urandom); end
      end
      while (!cpu1_axi.bvalid) @(posedge clk_i);
      assert (cpu1_axi.bresp == expected_resp) else $fatal(1, "CPU1 write response %0d, expected %0d", cpu1_axi.bresp, expected_resp);
      @(negedge clk_i);
      cpu1_axi.bready = 1'b0;
    end
  endtask

  logic [31:0] read_data;
  localparam logic [31:0] SHARED_WORD = 32'h2000_0040;
  logic [31:0] reference_data[0:63];
  logic [31:0] random_q=32'h12345678;
  int index;
  // Single-writer/multiple-reader invariant, checked on every cycle (not only
  // when both caches are idle): a line valid in both caches must be Shared in
  // both, with identical data. Concurrency is also measured.
  int both_busy_cycles=0,checked_cycles=0;
  // Coverage of the overlapped-miss path (manager EARLY_RELEASE).
  int both_fetching=0,clean_snoop_during_fetch=0,same_index_install=0;
  always @(negedge clk_i) if(rst_ni)begin
    checked_cycles++;
    if(u_cache0.main_state_q inside {u_cache0.M_MEM_READ_ADDR,u_cache0.M_MEM_READ_DATA} &&
       u_cache1.main_state_q inside {u_cache1.M_MEM_READ_ADDR,u_cache1.M_MEM_READ_DATA})both_fetching++;
    if((u_cache0.snoop_start && u_cache0.main_axi_active)||(u_cache1.snoop_start && u_cache1.main_axi_active))
      clean_snoop_during_fetch++;
    if((u_cache0.snoop_state_q==u_cache0.S_APPLY && u_cache0.main_install && u_cache0.cpu_index==u_cache0.snoop_index)||
       (u_cache1.snoop_state_q==u_cache1.S_APPLY && u_cache1.main_install && u_cache1.cpu_index==u_cache1.snoop_index))
      same_index_install++;
    if(u_cache0.main_state_q!=0 && u_cache1.main_state_q!=0)both_busy_cycles++;
    for(int i=0;i<8;i++) if(u_cache0.tag_q[i]==u_cache1.tag_q[i] &&
      u_cache0.line_state_q[i]!=coherence_pkg::MESI_INVALID && u_cache1.line_state_q[i]!=coherence_pkg::MESI_INVALID)begin
      assert(u_cache0.line_state_q[i]==coherence_pkg::MESI_SHARED && u_cache1.line_state_q[i]==coherence_pkg::MESI_SHARED)
        else $fatal(1,"MESI duplicate exclusive/dirty ownership");
      assert(u_cache0.data_q[i]==u_cache1.data_q[i])else $fatal(1,"MESI shared copies differ");
    end
  end

  initial begin
    cpu0_axi.awaddr='0; cpu0_axi.awvalid=0; cpu0_axi.wdata='0; cpu0_axi.wstrb='0;
    cpu0_axi.wvalid=0; cpu0_axi.bready=0; cpu0_axi.araddr='0; cpu0_axi.arvalid=0; cpu0_axi.rready=0;
    cpu1_axi.awaddr='0; cpu1_axi.awvalid=0; cpu1_axi.wdata='0; cpu1_axi.wstrb='0;
    cpu1_axi.wvalid=0; cpu1_axi.bready=0; cpu1_axi.araddr='0; cpu1_axi.arvalid=0; cpu1_axi.rready=0;

    repeat (5) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (3) @(posedge clk_i);

    cpu0_read(SHARED_WORD, read_data); // I -> E
    assert (read_data == 0) else $fatal(1, "Initial RAM value was not zero");
    cpu1_read(SHARED_WORD, read_data); // peer E -> S, requester I -> S
    assert (read_data == 0) else $fatal(1, "Shared read returned wrong value");

    cpu0_write(SHARED_WORD, 32'hA5A5_1234); // S -> M, invalidate core 1
    cpu0_read(SHARED_WORD, read_data);      // M hit
    assert (read_data == 32'hA5A5_1234) else $fatal(1, "Core 0 M hit failed");

    cpu1_read(SHARED_WORD, read_data); // core 0 M write-back/downgrade, both S
    assert (read_data == 32'hA5A5_1234)
      else $fatal(1, "Dirty intervention did not reach core 1");

    cpu1_write(SHARED_WORD, 32'h55AA_C33C); // invalidate core 0, become M
    cpu0_read(SHARED_WORD, read_data);       // force second dirty intervention
    assert (read_data == 32'h55AA_C33C)
      else $fatal(1, "Second MESI ownership transfer failed");

    assert (c0_hits > 0 && c0_misses > 0 && c1_misses > 0)
      else $fatal(1, "Cache hit/miss counters did not advance");
    assert ((c0_writebacks + c1_writebacks) >= 2)
      else $fatal(1, "Expected dirty MESI write-backs");
    assert ((c0_invalidates + c1_invalidates) >= 2)
      else $fatal(1, "Expected MESI invalidations");

    // Both harts upgrade the same S line simultaneously. The second must
    // reload after invalidation, otherwise it loses the first hart's byte.
    for(int t=0;t<32;t++)begin
      cpu0_write(32'h20000080,32'haabbccdd);
      cpu0_read(32'h20000080,read_data);cpu1_read(32'h20000080,read_data);
      fork
        cpu0_write(32'h20000080,32'h00000011,4'b0001);
        cpu1_write(32'h20000080,32'h00002200,4'b0010);
      join
      cpu0_read(32'h20000080,read_data);
      assert(read_data==32'haabb2211)else $fatal(1,"Concurrent MESI byte stores lost data: %h",read_data);
    end

    // Error injection: a failed dirty eviction must preserve the victim.
    cpu0_write(32'h20000300,32'hf00dcafe);
    force u_ram.bresp_q=2'b10;
    cpu0_read(32'h20000320,read_data,2'b10);
    cpu0_read(32'h20000300,read_data);
    assert(read_data==32'hf00dcafe)else $fatal(1,"Dirty data lost on failed writeback");
    release u_ram.bresp_q;
    cpu0_read(32'h20000320,read_data); // retry succeeds
    cpu1_read(32'h20000300,read_data);
    assert(read_data==32'hf00dcafe)else $fatal(1,"Dirty writeback recovery failed");
    cpu0_write(32'h20000300,32'hcafef00d);
    force u_ram.bresp_q=2'b10;
    fork
      begin
        cpu1_read(32'h20000300,read_data);
        assert(read_data==32'hcafef00d)else $fatal(1,"Snoop writeback retry corrupted data");
      end
      begin
        repeat(100)@(negedge clk_i);
        assert(u_cache0.line_state_q[0]==coherence_pkg::MESI_MODIFIED && !coh1.grant)
          else $fatal(1,"Failed snoop WB acknowledged before recovery");
        release u_ram.bresp_q;
      end
    join
    // Persistent backend failure: the owner retries a bounded number of times,
    // keeps its dirty line, and the requester receives SLVERR instead of hanging.
    cpu0_write(32'h20000300,32'h0badf00d);
    assert(u_cache0.line_state_q[0]==coherence_pkg::MESI_MODIFIED)else $fatal(1,"Owner not Modified before NACK test");
    force u_ram.bresp_q=2'b10;
    cpu1_read(32'h20000300,read_data,2'b10);
    assert(u_cache0.line_state_q[0]==coherence_pkg::MESI_MODIFIED && u_cache0.data_q[0]==32'h0badf00d)
      else $fatal(1,"Refused snoop dropped the dirty line");
    assert(u_cache1.line_state_q[0]==coherence_pkg::MESI_INVALID || u_cache1.tag_q[0]!=u_cache0.tag_q[0])
      else $fatal(1,"Requester installed a line after a coherence error");
    cpu1_write(32'h20000300,32'h11111111,4'hf,2'b10);
    assert(u_cache0.data_q[0]==32'h0badf00d)else $fatal(1,"Failed GETM changed owner data");
    release u_ram.bresp_q;
    cpu1_read(32'h20000300,read_data);
    assert(read_data==32'h0badf00d)else $fatal(1,"Recovery after NACK returned %h",read_data);
    cpu1_write(32'h20000300,32'h22222222);
    cpu0_read(32'h20000300,read_data);
    assert(read_data==32'h22222222)else $fatal(1,"Ownership transfer after NACK recovery failed");
    // A failed fill (RRESP error) must not touch the resident clean line that
    // shares the index: neither its data nor its state may change.
    cpu0_write(32'h20000180,32'h5eed1234);   // index 0, core0 Modified
    cpu1_read(32'h20000180,read_data);        // core0 downgrades to Shared (clean)
    assert(u_cache0.line_state_q[0]==coherence_pkg::MESI_SHARED)else $fatal(1,"Fill-error setup: line not Shared");
    force u_ram.rresp_q=2'b10;
    cpu0_read(32'h200001a0,read_data,2'b10);  // same index, different tag, fill fails
    release u_ram.rresp_q;
    assert(u_cache0.line_state_q[0]==coherence_pkg::MESI_SHARED && u_cache0.tag_q[0]==27'(32'h20000180>>5))
      else $fatal(1,"Fill error changed the resident line state/tag");
    cpu0_read(32'h20000180,read_data);
    assert(read_data==32'h5eed1234)else $fatal(1,"Fill error corrupted resident line data: %h",read_data);
    // Reproducible randomized ownership transfers and direct-map evictions.
    for(int i=0;i<64;i++)begin reference_data[i]=0;cpu0_write(32'h20000100+i*4,0);end
    for(int t=0;t<500;t++)begin
      random_q=random_q*32'd1664525+32'd1013904223;index=int'((random_q>>8)%64);
      if(random_q[0])begin
        reference_data[index]=random_q^32'hdeadbeef;
        if(random_q[1])cpu0_write(32'h20000100+index*4,reference_data[index]);
        else cpu1_write(32'h20000100+index*4,reference_data[index]);
      end else begin
        if(random_q[1])cpu0_read(32'h20000100+index*4,read_data);
        else cpu1_read(32'h20000100+index*4,read_data);
        assert(read_data==reference_data[index])else $fatal(1,"MESI random reference mismatch at %0d",index);
      end
    end
    for(int i=0;i<64;i++)begin cpu0_read(32'h20000100+i*4,read_data);assert(read_data==reference_data[i])else $fatal(1,"Final reference mismatch");end
    // Concurrent two-core stress: 24 words share 8 cache lines (conflict
    // evictions). Core0 owns bytes [1:0], core1 owns bytes [3:2] of each word and
    // writes increasing sequence numbers. Each core must read back its own
    // half exactly, and must never observe the other half going backwards
    // (per-location coherence order).
    begin
      int seq0[24],seq1[24],seen0[24],seen1[24];
      int busy_before;
      busy_before=both_busy_cycles;
      for(int i=0;i<24;i++)begin seq0[i]=0;seq1[i]=0;seen0[i]=0;seen1[i]=0;cpu0_write(32'h20000200+i*4,0);end
      fork
        begin : core0_stress
          logic [31:0] r,d;int w;r=32'h1357_9bdf;
          for(int t=0;t<1500;t++)begin
            r=r*32'd1664525+32'd1013904223;w=int'((r>>8)%24);
            if(r[2])begin seq0[w]++;cpu0_write(32'h20000200+w*4,32'(seq0[w]),4'b0011);end
            else begin
              cpu0_read(32'h20000200+w*4,d);
              assert(d[15:0]==16'(seq0[w]))else $fatal(1,"Core0 lost its own store w=%0d got=%h exp=%h",w,d[15:0],seq0[w]);
              assert(int'(d[31:16])>=seen0[w])else $fatal(1,"Core0 saw core1 half go backwards w=%0d",w);
              seen0[w]=d[31:16];
            end
            repeat(r[5:4])@(negedge clk_i);
          end
        end
        begin : core1_stress
          logic [31:0] r,d;int w;r=32'h2468_ace1;
          for(int t=0;t<1500;t++)begin
            r=r*32'd1664525+32'd1013904223;w=int'((r>>8)%24);
            if(r[2])begin seq1[w]++;cpu1_write(32'h20000200+w*4,32'(seq1[w])<<16,4'b1100);end
            else begin
              cpu1_read(32'h20000200+w*4,d);
              assert(d[31:16]==16'(seq1[w]))else $fatal(1,"Core1 lost its own store w=%0d got=%h exp=%h",w,d[31:16],seq1[w]);
              assert(int'(d[15:0])>=seen1[w])else $fatal(1,"Core1 saw core0 half go backwards w=%0d",w);
              seen1[w]=d[15:0];
            end
            repeat(r[5:4])@(negedge clk_i);
          end
        end
      join
      for(int i=0;i<24;i++)begin
        cpu0_read(32'h20000200+i*4,read_data);
        assert(read_data=={16'(seq1[i]),16'(seq0[i])})else $fatal(1,"Concurrent stress final mismatch word %0d",i);
        cpu1_read(32'h20000200+i*4,read_data);
        assert(read_data=={16'(seq1[i]),16'(seq0[i])})else $fatal(1,"Concurrent stress final mismatch (core1) word %0d",i);
      end
      assert(both_busy_cycles-busy_before>1000)else $fatal(1,"Stress did not overlap the two caches enough");
      $display("MESI_STRESS ops=3000 overlap_cycles=%0d invariant_cycles=%0d writebacks=%0d invalidates=%0d both_fetching=%0d clean_snoop_during_fetch=%0d same_index_install=%0d",
        both_busy_cycles-busy_before,checked_cycles,c0_writebacks+c1_writebacks,c0_invalidates+c1_invalidates,
        both_fetching,clean_snoop_during_fetch,same_index_install);
      if(u_manager.EARLY_RELEASE)
        assert(both_fetching>100 && clean_snoop_during_fetch>100)
          else $fatal(1,"Overlapped-miss path not exercised (both_fetching=%0d clean_snoop=%0d)",both_fetching,clean_snoop_during_fetch);
    end
    // Hold AR and AW/W concurrently: independent AXI channels must progress.
    fork
      cpu0_read(32'h20000040,read_data);
      cpu0_write(32'h20000044,32'h13579bdf);
    join
    cpu1_read(32'h20000044,read_data);
    assert(read_data==32'h13579bdf) else $fatal(1,"Concurrent AR/AW/W lost write");
    $display("TEST_PASS: MESI transitions, concurrent AR/AW/W, 32 byte-store races, 500 random transfers, 3000-op concurrent two-core stress, per-cycle SWMR invariant, fill-error isolation, bounded write-back retry with SLVERR and recovery");
    $finish;
  end

  initial begin
    #5000000;
    $fatal(1, "Timeout waiting for MESI coherence test");
  end
endmodule

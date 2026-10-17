`timescale 1ns/1ps
// System-level check of the 4-core node map and address decode without the
// CPUs: four AXI-Lite masters at the CPU corners (0,0) (0,2) (2,0) (2,2) drive
// the real non-CPU nodes of ibex_mesh_soc (peripheral node, DMA, 128 KB RAM,
// PLIC+CLINT+NoC control, accelerator). Checks:
//  - valid/invalid address table from every corner (DECERR/SLVERR edges);
//  - RAM 128 KB bounds, byte enables from several masters, concurrent traffic;
//  - mailbox slot h -> PLIC source -> context h, claim/clear/complete;
//  - test-and-set mutual exclusion with 4 concurrent masters;
//  - CLINT MSIP/MTIP per hart; UART bytes on the wire; GPIO edge IRQ;
//  - DMA and accelerator through their new nodes with PLIC completion IRQs;
//  - mixed concurrent traffic to every peripheral from all masters;
//  - DECERR inside the merged peripheral node (raw packet, unmapped slot);
//  - reset in the middle of 4-master traffic, then recovery.
module tb_soc_4core_map;
  import router_pkg::*;
  localparam int M = 4;
  localparam int CLOCK_HZ = 100_000_000;
  localparam int BAUD = 6_250_000;
  localparam int CLKS_PER_BIT = CLOCK_HZ / BAUD;
  logic clk_i=0,rst_ni=0;
  always #5 clk_i=~clk_i;

  function automatic int corner(input int m);
    case(m) 0:return 0; 1:return 2; 2:return 6; default:return 8; endcase
  endfunction
  function automatic logic [31:0] mailbox_slot(input int h);
    return h<2 ? 32'h30003000+4*h : 32'h30003010+4*(h-2);
  endfunction
  function automatic int mailbox_source(input int h);return h<2 ? 2+h : 7+h;endfunction

  // ------------------------------------------------------------- fabric
  logic [33:0] tx[0:8],rx[0:8];
  logic tv[0:8],tc[0:8],rv[0:8],rc[0:8];
  logic [1:0] credits[0:8],returns[0:8];
  logic [1439:0] router_flits,router_packets,router_stalls;
  logic [359:0] router_peaks;
  logic [1:0] qos_mode;logic qos_classes,qos_aging,counters_enable,counters_clear;
  logic [3:0] qos_age;logic [7:0] qos_weights,source_classes,dma_gap;
  mesh_3x3_vc mesh(.clk_i,.rst_ni,.local_tx_flit_i(tx),.local_tx_valid_i(tv),
    .local_tx_vc_i(tc),.local_tx_credit_o(credits),.local_rx_flit_o(rx),
    .local_rx_valid_o(rv),.local_rx_vc_o(rc),.local_rx_credit_i(returns),
    .flit_count_o(router_flits),.packet_count_o(router_packets),.stall_count_o(router_stalls),.fifo_peak_o(router_peaks),
    .qos_mode_i(qos_mode),.qos_classes_i(qos_classes),.qos_aging_i(qos_aging),.qos_age_i(qos_age),.qos_weights_i(qos_weights),
    .counters_enable_i(counters_enable),.counters_clear_i(counters_clear));

  axi_lite_if mst[M](clk_i,rst_ni);
  for(genvar g=0;g<M;g++)begin:g_m
    localparam int NODE=corner(g);
    axi_lite_bfm u_bfm(.clk_i,.axi(mst[g]));
    axi_lite_to_mesh #(.CURRENT_X(2'(NODE/3)),.CURRENT_Y(2'(NODE%3))) u_ni(.clk_i,.rst_ni,
      .qos_i(source_classes[2*(g%2)+:2]),.s_axi(mst[g]),
      .tx_flit_o(tx[NODE]),.tx_valid_o(tv[NODE]),.tx_vc_o(tc[NODE]),.tx_credit_i(credits[NODE]),
      .rx_flit_i(rx[NODE]),.rx_valid_i(rv[NODE]),.rx_vc_i(rc[NODE]),.rx_credit_o(returns[NODE]));
  end

  logic uart_tx,uart_irq,gpio_irq,dd,de,ad,ae;
  logic [M-1:0] mb,ext,timer,ipi;
  logic [7:0] gpio_in=8'h3c,gpio_out,gpio_oe;
  logic [16:1] sources;
  assign sources={6'b0,mb[3],mb[2],gpio_irq,ae,ad,de,dd,mb[1],mb[0],uart_irq};

  peripheral_node #(.CURRENT_X(0),.CURRENT_Y(1),.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.HARTS(M)) u_periph(
    .clk_i,.rst_ni,.uart_tx_o(uart_tx),.uart_irq_o(uart_irq),.gpio_i(gpio_in),.gpio_o(gpio_out),
    .gpio_oe_o(gpio_oe),.gpio_irq_o(gpio_irq),.mailbox_irq_o(mb),
    .noc_rx_flit_i(rx[1]),.noc_rx_valid_i(rv[1]),.noc_rx_vc_i(rc[1]),.noc_rx_credit_o(returns[1]),
    .noc_tx_flit_o(tx[1]),.noc_tx_valid_o(tv[1]),.noc_tx_vc_o(tc[1]),.noc_tx_credit_i(credits[1]));
  dma_node #(.CURRENT_X(1),.CURRENT_Y(0)) u_dma(.clk_i,.rst_ni,.qos_i(source_classes[5:4]),.issue_gap_i(dma_gap),
    .irq_done_o(dd),.irq_error_o(de),
    .noc_tx_flit_o(tx[3]),.noc_tx_valid_o(tv[3]),.noc_tx_vc_o(tc[3]),.noc_tx_credit_i(credits[3]),
    .noc_rx_flit_i(rx[3]),.noc_rx_valid_i(rv[3]),.noc_rx_vc_i(rc[3]),.noc_rx_credit_o(returns[3]));
  shared_ram_node #(.WORDS(32768)) u_ram(.clk_i,.rst_ni,
    .noc_tx_flit_o(tx[4]),.noc_tx_valid_o(tv[4]),.noc_tx_vc_o(tc[4]),.noc_tx_credit_i(credits[4]),
    .noc_rx_flit_i(rx[4]),.noc_rx_valid_i(rv[4]),.noc_rx_vc_i(rc[4]),.noc_rx_credit_o(returns[4]));
  interrupt_node #(.HARTS(M),.SOURCES(16),.LEGACY_TIMER(1'b0),.CURRENT_X(1),.CURRENT_Y(2)) u_irq(
    .clk_i,.rst_ni,.sources_i(sources),.external_irq_o(ext),.timer_irq_o(timer),.software_irq_o(ipi),
    .flits_i(router_flits),.packets_i(router_packets),.stalls_i(router_stalls),.peaks_i(router_peaks),
    .qos_mode_o(qos_mode),.qos_classes_o(qos_classes),.qos_aging_o(qos_aging),.qos_age_o(qos_age),.qos_weights_o(qos_weights),
    .source_classes_o(source_classes),.dma_gap_o(dma_gap),.counters_enable_o(counters_enable),.counters_clear_o(counters_clear),
    .noc_tx_flit_o(tx[5]),.noc_tx_valid_o(tv[5]),.noc_tx_vc_o(tc[5]),.noc_tx_credit_i(credits[5]),
    .noc_rx_flit_i(rx[5]),.noc_rx_valid_i(rv[5]),.noc_rx_vc_i(rc[5]),.noc_rx_credit_o(returns[5]));
  accelerator_node #(.CURRENT_X(2),.CURRENT_Y(1)) u_acc(.clk_i,.rst_ni,.qos_i(source_classes[7:6]),
    .irq_done_o(ad),.irq_error_o(ae),
    .noc_tx_flit_o(tx[7]),.noc_tx_valid_o(tv[7]),.noc_tx_vc_o(tc[7]),.noc_tx_credit_i(credits[7]),
    .noc_rx_flit_i(rx[7]),.noc_rx_valid_i(rv[7]),.noc_rx_vc_i(rc[7]),.noc_rx_credit_o(returns[7]));

  // Second, stand-alone peripheral node driven with raw packets: reaches the
  // node-local DECERR path, which the SoC address map never routes to.
  logic [33:0] raw_in_flit=0,raw_out_flit;
  logic raw_in_valid=0,raw_out_valid,raw_out_vc;
  logic [1:0] raw_in_credit,raw_out_credit=0;
  logic raw_tx_unused,raw_uirq,raw_girq;logic [M-1:0] raw_mb;logic [7:0] raw_go,raw_goe;
  peripheral_node #(.CURRENT_X(0),.CURRENT_Y(1),.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.HARTS(M)) u_periph_raw(
    .clk_i,.rst_ni,.uart_tx_o(raw_tx_unused),.uart_irq_o(raw_uirq),.gpio_i(8'h0),.gpio_o(raw_go),
    .gpio_oe_o(raw_goe),.gpio_irq_o(raw_girq),.mailbox_irq_o(raw_mb),
    .noc_rx_flit_i(raw_in_flit),.noc_rx_valid_i(raw_in_valid),.noc_rx_vc_i(1'b0),.noc_rx_credit_o(raw_in_credit),
    .noc_tx_flit_o(raw_out_flit),.noc_tx_valid_o(raw_out_valid),.noc_tx_vc_o(raw_out_vc),.noc_tx_credit_i(raw_out_credit));

  // ------------------------------------------------------------- helpers
  task automatic rd(input int m,input logic[31:0] a,output logic[31:0] d,input logic[1:0] e=0);
    case(m)
      0:g_m[0].u_bfm.read(a,d,e);
      1:g_m[1].u_bfm.read(a,d,e);
      2:g_m[2].u_bfm.read(a,d,e);
      default:g_m[3].u_bfm.read(a,d,e);
    endcase
  endtask
  task automatic wr(input int m,input logic[31:0] a,input logic[31:0] d,input logic[3:0] s=15,input logic[1:0] e=0);
    case(m)
      0:g_m[0].u_bfm.write(a,d,s,e);
      1:g_m[1].u_bfm.write(a,d,s,e);
      2:g_m[2].u_bfm.write(a,d,s,e);
      default:g_m[3].u_bfm.write(a,d,s,e);
    endcase
  endtask
  task automatic expect_rd(input int m,input logic[31:0] a,input logic[31:0] v,input string what);
    logic[31:0] d;
    rd(m,a,d);assert(d==v)else $fatal(1,"%s: master%0d read %h = %h, expected %h",what,m,a,d,v);
  endtask
  function automatic void idle_masters();
    for(int m=0;m<M;m++)begin
      case(m)
        0:begin mst[0].awvalid=0;mst[0].wvalid=0;mst[0].arvalid=0;mst[0].bready=0;mst[0].rready=0;end
        1:begin mst[1].awvalid=0;mst[1].wvalid=0;mst[1].arvalid=0;mst[1].bready=0;mst[1].rready=0;end
        2:begin mst[2].awvalid=0;mst[2].wvalid=0;mst[2].arvalid=0;mst[2].bready=0;mst[2].rready=0;end
        default:begin mst[3].awvalid=0;mst[3].wvalid=0;mst[3].arvalid=0;mst[3].bready=0;mst[3].rready=0;end
      endcase
    end
  endfunction
  task automatic settle;repeat(4)@(negedge clk_i);endtask

  // UART receiver (8N1).
  logic [7:0] uart_bytes[$];
  initial forever begin
    logic [7:0] ch;
    @(negedge uart_tx);
    repeat(CLKS_PER_BIT/2)@(posedge clk_i);
    if(uart_tx)continue;
    for(int b=0;b<8;b++)begin repeat(CLKS_PER_BIT)@(posedge clk_i);ch[b]=uart_tx;end
    repeat(CLKS_PER_BIT)@(posedge clk_i);
    assert(uart_tx)else $fatal(1,"UART stop bit missing");
    uart_bytes.push_back(ch);
  end

  // Raw packet to the stand-alone node; returns the response opcode/resp/data.
  // Response flits are captured every cycle and their credits returned.
  logic [33:0] raw_rx_q[$];
  always @(posedge clk_i) begin
    raw_out_credit <= 2'b00;
    if (raw_out_valid) begin
      assert(raw_out_vc)else $fatal(1,"Response not on VC1");
      raw_rx_q.push_back(raw_out_flit);
      raw_out_credit[raw_out_vc] <= 1'b1;
    end
  end
  task automatic raw_request(input logic[31:0] addr,input bit write,input logic[31:0] data,
                             output logic[2:0] opcode,output logic[1:0] resp,output logic[31:0] rdata);
    logic [33:0] head,h,tl;
    head=make_head(2'd0,2'd1,2'd1,2'd1,write?NOC_WRITE_REQ:NOC_READ_REQ,write?4'hf:4'h0);
    head[14:11]=4'd5;
    @(negedge clk_i);raw_in_flit=head;raw_in_valid=1;
    @(negedge clk_i);raw_in_flit={FLIT_BODY,addr};
    @(negedge clk_i);raw_in_flit={FLIT_TAIL,data};
    @(negedge clk_i);raw_in_valid=0;
    while(raw_rx_q.size()<2)@(negedge clk_i);
    h=raw_rx_q.pop_front();tl=raw_rx_q.pop_front();
    assert(h[33:32]==FLIT_HEAD && tl[33:32]==FLIT_TAIL && h[14:11]==4'd5)else $fatal(1,"Malformed raw response");
    opcode=h[23:21];resp=h[16:15];rdata=tl[31:0];
  endtask

  // ------------------------------------------------------------- tests
  logic [31:0] d;
  int holder=-1,lock_entries=0;
  task automatic lock_worker(input int m,input int iters);
    logic [31:0] v;
    for(int k=0;k<iters;k++)begin
      do rd(m,32'h3000700c,v);while(v!=0);   // lock 3: read 0 = acquired
      assert(holder==-1)else $fatal(1,"Test-and-set: master%0d entered while master%0d holds the lock",m,holder);
      holder=m;lock_entries++;
      rd(m,32'h20000400,v);
      repeat(m*3)@(negedge clk_i);
      wr(m,32'h20000400,v+1);
      holder=-1;
      wr(m,32'h3000700c,0);                  // release
    end
  endtask
  task automatic ram_worker(input int m,input int words);
    logic [31:0] v;
    for(int i=0;i<words;i++)wr(m,32'h20010000+m*'h4000+i*4,{8'(m),24'(i*7)});
    for(int i=0;i<words;i++)begin
      rd(m,32'h20010000+m*'h4000+i*4,v);
      assert(v=={8'(m),24'(i*7)})else $fatal(1,"RAM master%0d word %0d = %h",m,i,v);
    end
  endtask
  task automatic mixed_worker(input int m,input int iters);
    logic [31:0] v;
    for(int k=0;k<iters;k++)begin
      case((k+m)%6)
        0:begin rd(m,32'h30006000,v);assert(v==32'h4e4f4303)else $fatal(1,"Mixed: NoC ID");end
        1:begin rd(m,32'h30001004,v);assert(v==32'hff)else $fatal(1,"Mixed: GPIO OE");end
        2:begin wr(m,mailbox_slot(m),32'hb0000000+k);rd(m,mailbox_slot(m),v);
                assert(v==32'hb0000000+k)else $fatal(1,"Mixed: mailbox slot");end
        3:begin rd(m,32'h0c000000+4*(1+m),v);assert(v==m%8)else $fatal(1,"Mixed: PLIC priority %0d",v);end
        4:begin wr(m,32'h20000800+m*4,k);rd(m,32'h20000800+m*4,v);assert(v==k)else $fatal(1,"Mixed: RAM");end
        default:begin rd(m,32'h0200bff8,v);end
      endcase
    end
  endtask

  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;

    // ---- Address table from every corner ----
    for(int m=0;m<M;m++)begin
      rd(m,32'h20000000,d);
      rd(m,32'h2001fffc,d);
      rd(m,32'h20020000,d,3);            // above 128 KB
      rd(m,32'h20000002,d,3);            // misaligned
      rd(m,32'h1fffffc,d,3);
      rd(m,32'h02000000,d);              // CLINT msip0
      rd(m,32'h0200000c,d);              // msip3
      rd(m,32'h02000010,d,3);            // msip4 does not exist
      rd(m,32'h02004018,d);              // mtimecmp3 low
      rd(m,32'h02004020,d,3);            // mtimecmp4
      rd(m,32'h0200bff8,d);              // mtime
      rd(m,32'h0200c000,d,3);
      rd(m,32'h0c000040,d);              // PLIC priority 16
      rd(m,32'h0c000044,d,3);            // priority 17
      rd(m,32'h0c002180,d);              // enable ctx3
      rd(m,32'h0c203004,d);              // claim ctx3
      rd(m,32'h0c204004,d,3);            // ctx4
      rd(m,32'h30000004,d);              // UART status
      rd(m,32'h30000010,d,3);
      rd(m,32'h30001008,d);              // GPIO in
      rd(m,32'h30002000,d,3);            // old timer map removed
      rd(m,32'h30003014,d);              // mailbox slot 3
      rd(m,32'h30003018,d,3);
      rd(m,32'h30004010,d);              // DMA status
      rd(m,32'h30005014,d);              // accelerator status
      expect_rd(m,32'h30006000,32'h4e4f4303,"NoC control ID");
      rd(m,32'h30007040,d,3);            // lock 16 does not exist
      rd(m,32'h30008000,d,3);
      rd(m,32'h40000000,d,3);
      wr(m,32'h20020000,1,15,3);
      wr(m,32'h30002020,1,15,3);
      wr(m,32'h30003008,1,15,2);         // mailbox PENDING is read only
      wr(m,32'h0c000044,1,15,3);
    end

    // ---- RAM: bounds, byte enables from different masters ----
    wr(0,32'h2001fffc,32'hcafe0001);expect_rd(3,32'h2001fffc,32'hcafe0001,"Last RAM word");
    wr(1,32'h20000000,32'h11223344);
    wr(2,32'h20000000,32'h000000aa,4'b0001);
    wr(3,32'h20000000,32'h00bb0000,4'b0100);
    wr(0,32'h20000000,32'hcc000000,4'b1000);
    expect_rd(1,32'h20000000,32'hccbb33aa,"Byte enables from 3 masters");
    wr(2,32'h20000004,32'h55667788,4'b0000);
    expect_rd(0,32'h20000004,32'h0,"Zero strobe must not write");

    // ---- Concurrent RAM traffic, one region per master in the upper 64 KB ----
    fork ram_worker(0,64);ram_worker(1,64);ram_worker(2,64);ram_worker(3,64);join
    for(int m=0;m<M;m++)expect_rd((m+1)%M,32'h20010000+m*'h4000+63*4,{8'(m),24'(63*7)},"Cross-master RAM view");

    // ---- Mailbox slot h -> PLIC source -> context h ----
    for(int h=0;h<M;h++)begin wr(0,32'h0c000000+4*mailbox_source(h),2);wr(0,32'h0c002000+h*'h80,1<<mailbox_source(h));end
    for(int h=0;h<M;h++)begin
      wr((h+1)%M,mailbox_slot(h),32'h5e0d0000+h);
      settle;
      assert(mb[h] && ext==(4'b1<<h))else $fatal(1,"Mailbox slot %0d: mb=%b ext=%b",h,mb,ext);
      expect_rd(h,mailbox_slot(h),32'h5e0d0000+h,"Mailbox message");
      expect_rd(h,32'h0c200004+h*'h1000,mailbox_source(h),"Mailbox PLIC claim");
      wr(h,32'h3000300c,1<<h);                    // W1C
      wr(h,32'h0c200004+h*'h1000,mailbox_source(h));
      settle;assert(mb==0 && ext==0)else $fatal(1,"Mailbox clear/complete hart%0d",h);
    end
    wr(1,mailbox_slot(2),32'h1,4'b0000);settle;assert(mb==0)else $fatal(1,"Zero-strobe mailbox write raised IRQ");
    expect_rd(0,32'h30003008,0,"Mailbox PENDING");

    // ---- Test-and-set: semantics, then 4-master mutual exclusion ----
    expect_rd(0,32'h3000703c,0,"Lock 15 free -> acquired");
    expect_rd(1,32'h3000703c,1,"Lock 15 busy");
    wr(2,32'h3000703c,0);
    expect_rd(3,32'h3000703c,0,"Lock 15 released -> acquired again");
    wr(3,32'h3000703c,0);
    wr(0,32'h20000400,0);
    fork lock_worker(0,16);lock_worker(1,16);lock_worker(2,16);lock_worker(3,16);join
    expect_rd(2,32'h20000400,64,"Counter under test-and-set lock");

    // ---- CLINT per hart ----
    for(int h=0;h<M;h++)begin
      wr(h,32'h02000000+4*h,1);settle;assert(ipi==(4'b1<<h))else $fatal(1,"MSIP hart%0d: %b",h,ipi);
      wr(h,32'h02000000+4*h,0);
      wr(h,32'h02004000+8*h,0);wr(h,32'h02004004+8*h,0);settle;
      assert(timer==(4'b1<<h))else $fatal(1,"MTIP hart%0d: %b",h,timer);
      wr(h,32'h02004004+8*h,32'hffffffff);settle;assert(timer==0)else $fatal(1,"MTIP clear hart%0d",h);
    end

    // ---- UART on the wire, busy protection ----
    wr(2,32'h30000000,32'h41);
    wr(1,32'h30000000,32'h42,15,2);               // still shifting -> SLVERR
    do rd(3,32'h30000004,d);while(!d[1]);
    wr(1,32'h30000000,32'h0a);
    do rd(3,32'h30000004,d);while(!d[1]);
    repeat(2*CLKS_PER_BIT)@(negedge clk_i);
    assert(uart_bytes.size()==2 && uart_bytes[0]==8'h41 && uart_bytes[1]==8'h0a)
      else $fatal(1,"UART bytes on the wire: %0d",uart_bytes.size());

    // ---- GPIO outputs, input, rising edge -> PLIC source 8 -> context 3 ----
    wr(3,32'h30001000,32'h5a);wr(0,32'h30001004,32'hff);
    assert(gpio_out==8'h5a && gpio_oe==8'hff)else $fatal(1,"GPIO outputs");
    expect_rd(2,32'h30001008,32'h3c,"GPIO input");
    wr(3,32'h0c000020,5);wr(3,32'h0c002180,1<<8);
    wr(3,32'h30001010,1);wr(3,32'h3000100c,1);
    gpio_in[0]=1;settle;
    assert(gpio_irq && ext[3])else $fatal(1,"GPIO IRQ not routed to context 3");
    expect_rd(3,32'h0c203004,8,"GPIO claim");
    wr(3,32'h30001018,1);wr(3,32'h0c203004,8);settle;assert(!ext[3])else $fatal(1,"GPIO stale IRQ");

    // ---- DMA at (1,0) and accelerator at (2,1) with completion IRQs ----
    for(int i=0;i<16;i++)wr(1,32'h20008100+i*4,32'h12340000+i);
    for(int i=0;i<9;i++)begin wr(2,32'h20009000+i*4,i+1);wr(2,32'h20009400+i*4,(i/3==i%3));end
    wr(1,32'h0c000010,3);wr(1,32'h0c002080,1<<4);  // DMA done -> context 1
    wr(2,32'h0c000018,4);wr(2,32'h0c002100,1<<6);  // ACC done -> context 2
    wr(1,32'h30004000,32'h20008100);wr(1,32'h30004004,32'h20008500);wr(1,32'h30004008,64);wr(1,32'h30004014,3);
    wr(2,32'h30005000,32'h20009000);wr(2,32'h30005004,32'h20009400);wr(2,32'h30005008,32'h20009800);
    wr(2,32'h3000500c,3);wr(2,32'h30005018,3);
    fork wr(1,32'h3000400c,1);wr(2,32'h30005010,1);join
    do rd(1,32'h30004010,d);while(!d[1]);assert(!d[2])else $fatal(1,"DMA error");
    do rd(2,32'h30005014,d);while(!d[1]);assert(!d[2])else $fatal(1,"Accelerator error");
    settle;assert(ext[1] && ext[2])else $fatal(1,"Engine IRQs not on contexts 1/2: %b",ext);
    for(int i=0;i<16;i++)expect_rd(3,32'h20008500+i*4,32'h12340000+i,"DMA copy");
    for(int i=0;i<9;i++)expect_rd(0,32'h20009800+i*4,i+1,"Accelerator result");
    expect_rd(1,32'h0c201004,4,"DMA claim");wr(1,32'h30004010,6);wr(1,32'h0c201004,4);
    expect_rd(2,32'h0c202004,6,"Accelerator claim");wr(2,32'h30005014,6);wr(2,32'h0c202004,6);
    settle;assert(ext==0)else $fatal(1,"Engine IRQs not cleared");

    // ---- Mixed concurrent traffic to every target ----
    wr(0,32'h30001004,32'hff);
    for(int s=1;s<=4;s++)wr(0,32'h0c000000+4*s,(s-1)%8);
    fork mixed_worker(0,60);mixed_worker(1,60);mixed_worker(2,60);mixed_worker(3,60);join
    for(int h=0;h<M;h++)wr(h,32'h3000300c,32'hf);

    // ---- Node-local DECERR inside the merged peripheral node ----
    begin
      logic [2:0] op;logic [1:0] r;logic [31:0] v;
      raw_request(32'h30000004,0,0,op,r,v);
      assert(op==NOC_READ_RESP && r==0 && v[1])else $fatal(1,"Raw UART status: op=%0d resp=%0d",op,r);
      raw_request(32'h30005000,0,0,op,r,v);
      assert(op==NOC_ERROR_RESP && r==3)else $fatal(1,"Unmapped read in peripheral node: op=%0d resp=%0d",op,r);
      raw_request(32'h30009000,1,32'h1,op,r,v);
      assert(op==NOC_ERROR_RESP && r==3)else $fatal(1,"Unmapped write in peripheral node: op=%0d resp=%0d",op,r);
      raw_request(32'h30003010,1,32'h77,op,r,v);
      assert(op==NOC_WRITE_RESP && r==0 && raw_mb==4'b0100)else $fatal(1,"Raw mailbox write");
    end

    // ---- Reset in the middle of 4-master traffic, then recovery ----
    expect_rd(0,32'h30007000,0,"Lock 0 acquired before reset");
    wr(1,32'h02000004,1);wr(2,mailbox_slot(3),9);
    fork
      ram_worker(0,32);ram_worker(1,32);ram_worker(2,32);ram_worker(3,32);
    join_none
    repeat(300)@(negedge clk_i);
    disable fork;
    idle_masters();
    rst_ni=0;repeat(5)@(negedge clk_i);rst_ni=1;repeat(3)@(negedge clk_i);
    assert(ext==0 && timer==0 && ipi==0 && mb==0)else $fatal(1,"Interrupt state survived reset");
    expect_rd(1,32'h30007000,0,"Lock freed by reset");
    wr(1,32'h30007000,0);
    expect_rd(2,32'h30004010,0,"DMA status after reset");
    expect_rd(3,32'h30006008,32'h00310f05,"NoC policy after reset");
    expect_rd(0,32'h2001fffc,32'hcafe0001,"RAM keeps contents through reset");
    fork ram_worker(0,32);ram_worker(1,32);ram_worker(2,32);ram_worker(3,32);join

    $display("TEST_PASS: 4-core node map: address table from 4 corners, RAM 128 KB bounds and byte enables, concurrent RAM, mailbox->PLIC ctx0-3, test-and-set mutual exclusion (%0d critical sections), CLINT per hart, UART wire, GPIO IRQ ctx3, DMA (1,0) + accelerator (2,1) IRQs, mixed concurrent traffic, node-local DECERR, reset mid-traffic",
      lock_entries);
    $finish;
  end
  initial begin #20000000;$fatal(1,"4-core map test timeout");end
endmodule

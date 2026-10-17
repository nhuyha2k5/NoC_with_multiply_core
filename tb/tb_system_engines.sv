`timescale 1ns/1ps
module tb_system_engines;
  logic clk_i=0,rst_ni=0,measure=0;
  always #5 clk_i=~clk_i;
  logic [33:0] tx[0:8],rx[0:8];
  logic tv[0:8],tc[0:8],rv[0:8],rc[0:8];
  logic [1:0] credits[0:8],returns[0:8];
  logic [1439:0] router_flits,router_packets,router_stalls;
  logic [359:0] router_peaks;
  logic [1:0] qos_mode;logic qos_classes,qos_aging,counters_enable,counters_clear;
  logic [3:0] qos_age;logic [7:0] qos_weights,source_classes,dma_gap;
  axi_lite_if cpu0(clk_i,rst_ni),cpu1(clk_i,rst_ni);
  axi_lite_bfm host0(.clk_i,.axi(cpu0)),host1(.clk_i,.axi(cpu1));
  logic uart_tx,uart_irq,mb0,mb1,dd,de,ad,ae;
  logic [1:0] ext,timer,ipi;
  logic [7:0] gpio,gpio_oe;
  mesh_3x3_vc mesh(.clk_i,.rst_ni,.local_tx_flit_i(tx),.local_tx_valid_i(tv),
    .local_tx_vc_i(tc),.local_tx_credit_o(credits),.local_rx_flit_o(rx),
    .local_rx_valid_o(rv),.local_rx_vc_o(rc),.local_rx_credit_i(returns),
    .flit_count_o(router_flits),.packet_count_o(router_packets),.stall_count_o(router_stalls),.fifo_peak_o(router_peaks),
    .qos_mode_i(qos_mode),.qos_classes_i(qos_classes),.qos_aging_i(qos_aging),.qos_age_i(qos_age),.qos_weights_i(qos_weights),
    .counters_enable_i(counters_enable),.counters_clear_i(counters_clear));
  axi_lite_to_mesh #(.CURRENT_X(0),.CURRENT_Y(0)) ni0(.clk_i,.rst_ni,.qos_i(source_classes[1:0]),.s_axi(cpu0),
    .tx_flit_o(tx[0]),.tx_valid_o(tv[0]),.tx_vc_o(tc[0]),.tx_credit_i(credits[0]),
    .rx_flit_i(rx[0]),.rx_valid_i(rv[0]),.rx_vc_i(rc[0]),.rx_credit_o(returns[0]));
  axi_lite_to_mesh #(.CURRENT_X(2),.CURRENT_Y(2)) ni1(.clk_i,.rst_ni,.qos_i(source_classes[3:2]),.s_axi(cpu1),
    .tx_flit_o(tx[8]),.tx_valid_o(tv[8]),.tx_vc_o(tc[8]),.tx_credit_i(credits[8]),
    .rx_flit_i(rx[8]),.rx_valid_i(rv[8]),.rx_vc_i(rc[8]),.rx_credit_o(returns[8]));
  uart_node #(.CLOCK_HZ(1000000)) u_uart(.clk_i,.rst_ni,.uart_tx_o(uart_tx),.uart_irq_o(uart_irq),
    .noc_tx_flit_o(tx[1]),.noc_tx_valid_o(tv[1]),.noc_tx_vc_o(tc[1]),.noc_tx_credit_i(credits[1]),
    .noc_rx_flit_i(rx[1]),.noc_rx_valid_i(rv[1]),.noc_rx_vc_i(rc[1]),.noc_rx_credit_o(returns[1]));
  accelerator_node  u_accelerator(.clk_i,.rst_ni,.qos_i(source_classes[7:6]),.irq_done_o(ad),.irq_error_o(ae),
    .noc_tx_flit_o(tx[2]),.noc_tx_valid_o(tv[2]),.noc_tx_vc_o(tc[2]),.noc_tx_credit_i(credits[2]),
    .noc_rx_flit_i(rx[2]),.noc_rx_valid_i(rv[2]),.noc_rx_vc_i(rc[2]),.noc_rx_credit_o(returns[2]));
  gpio_node  u_gpio(.clk_i,.rst_ni,.gpio_i(8'h5a),.gpio_o(gpio),.gpio_oe_o(gpio_oe),
    .noc_tx_flit_o(tx[3]),.noc_tx_valid_o(tv[3]),.noc_tx_vc_o(tc[3]),.noc_tx_credit_i(credits[3]),
    .noc_rx_flit_i(rx[3]),.noc_rx_valid_i(rv[3]),.noc_rx_vc_i(rc[3]),.noc_rx_credit_o(returns[3]));
  shared_ram_node  u_shared_ram(.clk_i,.rst_ni,
    .noc_tx_flit_o(tx[4]),.noc_tx_valid_o(tv[4]),.noc_tx_vc_o(tc[4]),.noc_tx_credit_i(credits[4]),
    .noc_rx_flit_i(rx[4]),.noc_rx_valid_i(rv[4]),.noc_rx_vc_i(rc[4]),.noc_rx_credit_o(returns[4]));
  interrupt_node  u_interrupt(.clk_i,.rst_ni,.sources_i({1'b0,ae,ad,de,dd,mb1,mb0,uart_irq}),.external_irq_o(ext),.timer_irq_o(timer),.software_irq_o(ipi),
    .flits_i(router_flits),.packets_i(router_packets),.stalls_i(router_stalls),.peaks_i(router_peaks),
    .qos_mode_o(qos_mode),.qos_classes_o(qos_classes),.qos_aging_o(qos_aging),.qos_age_o(qos_age),.qos_weights_o(qos_weights),
    .source_classes_o(source_classes),.dma_gap_o(dma_gap),.counters_enable_o(counters_enable),.counters_clear_o(counters_clear),
    .noc_tx_flit_o(tx[5]),.noc_tx_valid_o(tv[5]),.noc_tx_vc_o(tc[5]),.noc_tx_credit_i(credits[5]),
    .noc_rx_flit_i(rx[5]),.noc_rx_valid_i(rv[5]),.noc_rx_vc_i(rc[5]),.noc_rx_credit_o(returns[5]));
  dma_node  u_dma(.clk_i,.rst_ni,.qos_i(source_classes[5:4]),.issue_gap_i(dma_gap),.irq_done_o(dd),.irq_error_o(de),
    .noc_tx_flit_o(tx[6]),.noc_tx_valid_o(tv[6]),.noc_tx_vc_o(tc[6]),.noc_tx_credit_i(credits[6]),
    .noc_rx_flit_i(rx[6]),.noc_rx_valid_i(rv[6]),.noc_rx_vc_i(rc[6]),.noc_rx_credit_o(returns[6]));
  mailbox_node  u_mailbox(.clk_i,.rst_ni,.irq_hart0_o(mb0),.irq_hart1_o(mb1),
    .noc_tx_flit_o(tx[7]),.noc_tx_valid_o(tv[7]),.noc_tx_vc_o(tc[7]),.noc_tx_credit_i(credits[7]),
    .noc_rx_flit_i(rx[7]),.noc_rx_valid_i(rv[7]),.noc_rx_vc_i(rc[7]),.noc_rx_credit_o(returns[7]));
  noc_endpoint_stats stats(.clk_i,.rst_ni,.enable_i(measure),.tx_flit_i(tx),.rx_flit_i(rx),
    .tx_valid_i(tv),.tx_vc_i(tc),.rx_valid_i(rv),.rx_vc_i(rc));
  int signed a[0:255],b[0:255],expected[0:255];
  int n;
  logic [31:0] d;
  string csv;
  task automatic prepare(input int size);
    n=size;
    for(int i=0;i<n*n;i++)begin
      a[i]=i%9-4;b[i]=(i*3)%7-3;
      host0.write('h20009000+i*4,a[i]);
      host0.write('h20009400+i*4,b[i]);
    end
    for(int r=0;r<n;r++)for(int c=0;c<n;c++)begin
      expected[r*n+c]=0;
      for(int k=0;k<n;k++)expected[r*n+c]+=a[r*n+k]*b[k*n+c];
    end
    for(int i=0;i<64;i++)host0.write('h20008100+i*4,'h12340000+i);
    host0.write('h30004000,'h20008100);host0.write('h30004004,'h20008500);
    host0.write('h30004008,256);host0.write('h30004014,3);
    host0.write('h30005000,'h20009000);host0.write('h30005004,'h20009400);
    host0.write('h30005008,'h20009800);host0.write('h3000500c,n);
    host0.write('h30005018,3);
  endtask
  task automatic wait_done(input logic[31:0]addr);
    logic[31:0]status;
    do begin host0.read(addr,status);assert(!status[2])else $fatal(1,"Engine error %h",addr);end
    while(!status[1]);
  endtask
  task automatic verify;
    for(int i=0;i<64;i++)begin
      host0.read('h20008500+i*4,d);
      assert(d==('h12340000+i))else $fatal(1,"DMA data word %d",i);
    end
    for(int i=0;i<n*n;i++)begin
      host0.read('h20009800+i*4,d);
      assert(d===32'(expected[i]))else $fatal(1,"Matrix %d got %h expected %h",i,d,expected[i]);
    end
    host0.read('h3000401c,d);assert(d==256)else $fatal(1,"DMA byte counter");
    host0.read('h30005020,d);assert(d==n*n*n)else $fatal(1,"MAC counter");
  endtask
  initial begin
    if(!$value$plusargs("CSV=%s",csv))csv="concurrent.csv";
    repeat(5)@(negedge clk_i);rst_ni=1;
    // Exact decode, byte strobes and independent AW/W order.
    host0.write('h20000000,'h11223344,15,0,-3);
    host0.write('h20000000,'h00aa0000,4,0,3);
    host0.read('h20000000,d);assert(d=='h11aa3344)else $fatal(1,"Byte merge");
    host0.read('h20010000,d,3);host0.write('h40000000,1,15,3);
    host0.write('h30001000,'h5a);host0.write('h30001004,'hff);
    assert(gpio=='h5a&&gpio_oe=='hff)else $fatal(1,"GPIO");
    host0.read('h30001008,d);assert(d=='h5a)else $fatal(1,"GPIO input");
    host0.write('h30001040,0,15,3);host0.read('h30001040,d,3);
    host0.write('h30001008,0,15,2);
    assert(gpio=='h5a)else $fatal(1,"Invalid GPIO alias changed output");
    host0.write('h30003000,123,0);host0.read('h30003008,d);
    assert(d==0)else $fatal(1,"Zero-strobe mailbox generated IRQ");
    host0.write('h30003040,123,15,3);host0.read('h30003040,d,3);
    prepare(3);
    host0.write('h3000400c,1);wait_done('h30004010);
    host0.write('h30005010,1);wait_done('h30005014);verify();
    host0.write('h30004010,6);host0.write('h30005014,6);
    // Concurrent accelerator + DMA + both host locations.
    prepare(8);
    host0.write('h0c000010,2);host0.write('h0c000018,3); // DMA source4, ACC source6
    host0.write('h0c002000,'h50);
    measure=1;
    fork
      begin
        host0.write('h3000400c,1);
        host0.write('h30005010,1);
        wait_done('h30004010);wait_done('h30005014);
      end
      begin
        logic[31:0]q;
        for(int i=0;i<80;i++)begin
          host1.write('h20000100+(i%16)*4,'h55aa0000+i);
          host1.read('h20000100+(i%16)*4,q);
          assert(q==('h55aa0000+i))else $fatal(1,"Background data");
        end
      end
    join
    measure=0;stats.report(csv);verify();
    assert(ext[0])else $fatal(1,"Engine IRQ not routed through PLIC");
    host0.read('h0c200004,d);assert(d==6)else $fatal(1,"Accelerator IRQ priority");
    host0.write('h30005014,6);host0.write('h0c200004,6);
    host0.read('h0c200004,d);assert(d==4)else $fatal(1,"DMA IRQ claim");
    host0.write('h30004010,6);host0.write('h0c200004,4);
    // Illegal alignment and size must fail without any memory transaction.
    host0.write('h30004000,'h20008101);host0.write('h3000400c,1);
    host0.read('h30004010,d);assert(d[2]&&!d[0])else $fatal(1,"DMA alignment accepted");
    host0.write('h30004010,6);host0.write('h30004000,'h20008000);
    host0.write('h30004004,'h20008004);host0.write('h30004008,16);
    host0.write('h3000400c,1);host0.read('h30004010,d);assert(d[2])else $fatal(1,"DMA overlap accepted");
    host0.write('h3000500c,0);host0.write('h30005010,1);
    host0.read('h30005014,d);assert(d[2]&&!d[0])else $fatal(1,"N=0 accepted");
    host0.write('h3000500c,17);host0.write('h30005010,1);
    host0.read('h30005014,d);assert(d[2])else $fatal(1,"N=17 accepted");
    // Size boundaries, busy register protection, and back-to-back restart.
    prepare(1);host0.write('h3000400c,1);host0.write('h30005010,1);
    wait_done('h30004010);wait_done('h30005014);verify();
    prepare(16);host0.write('h3000400c,1);
    host0.write('h30004004,'h20008800,15,2); // cannot change an active transfer
    host0.write('h30005010,1);host0.write('h3000500c,3,15,2);
    wait_done('h30004010);wait_done('h30005014);verify();
    host0.read('h3000501c,d);
    $display("ACC_METRIC n=16 cycles=%0d macs=4096",d);
    // DMA must not access coherent cache lines or wrap a large length.
    host0.write('h30004000,'h20000000);host0.write('h3000400c,1);
    host0.read('h30004010,d);assert(d==4)else $fatal(1,"DMA cacheable region accepted");
    host0.write('h30004000,'h20008100);host0.write('h30004008,'hfffffffc);
    host0.write('h3000400c,1);host0.read('h30004010,d);assert(d==4)else $fatal(1,"DMA overflow accepted");
    host0.write('h30004008,0);host0.write('h3000400c,1);
    host0.read('h30004010,d);assert(d==2)else $fatal(1,"Zero length DMA");
    host0.read('h3000401c,d);assert(d==0)else $fatal(1,"Zero length bytes counter");
    prepare(3);
    // Downstream read and write failures must finish with error, not done.
    force u_shared_ram.u_ram.rresp=2'b10;
    host0.write('h3000400c,1);repeat(100)@(negedge clk_i);
    do host0.read('h30004010,d);while(d[0]);
    assert(d==4 && de)else $fatal(1,"DMA read error propagation status=%h",d);
    host0.write('h30005010,1);repeat(100)@(negedge clk_i);
    host0.read('h30005014,d);assert(d==4 && ae)else $fatal(1,"Accelerator read error propagation");
    release u_shared_ram.u_ram.rresp;
    force u_shared_ram.u_ram.bresp=2'b10;
    host0.write('h3000400c,1);repeat(150)@(negedge clk_i);
    do host0.read('h30004010,d);while(d[0]);
    assert(d==4)else $fatal(1,"DMA write error propagation status=%h",d);
    release u_shared_ram.u_ram.bresp;
    // Reset in flight resets both endpoint state and engine state together.
    host0.write('h3000400c,1);host0.write('h30005010,1);
    // Reset cancels pending status and IRQ.
    @(negedge clk_i);rst_ni=0;repeat(3)@(negedge clk_i);rst_ni=1;
    host0.read('h30004010,d);assert(d==0)else $fatal(1,"DMA reset");
    host0.read('h30005014,d);assert(d==0)else $fatal(1,"Accelerator reset");
    host0.read('h30006000,d);assert(d==32'h4e4f4303)else $fatal(1,"NoC control ID");
    host0.read('h30006008,d);assert(d==32'h00310f05)else $fatal(1,"NoC policy reset");
    host0.write('h30006008,32'h00310b06);host0.read('h30006008,d);
    assert(d==32'h00310b06)else $fatal(1,"QoS policy write");
    assert(qos_aging)else $fatal(1,"Aging must stay enabled when bit 3 is clear");
    host0.write('h30006008,32'h00310b0e);host0.read('h30006008,d);
    assert(d==32'h00310b0e && !qos_aging)else $fatal(1,"QoS aging-disable bit not applied");
    host0.write('h30006008,32'h00310b06);
    assert(qos_aging)else $fatal(1,"QoS aging re-enable failed");
    host0.write('h30006008,0,15,2); // age and weights cannot be zero
    host0.write('h30006014,0);host0.read('h30006018,d);
    assert(d>0)else $fatal(1,"Router flit counter empty");
    host0.read('h3000601c,d);assert(d>0)else $fatal(1,"Router packet counter empty");
    host0.write('h30006004,4);repeat(3)@(negedge clk_i);
    host0.read('h30006018,d);assert(d==0)else $fatal(1,"Router counter clear");
    host0.write('h30006004,1);
    $display("TEST_PASS: mesh MMIO, DMA, matrix, PLIC, QoS policy and router counters");$finish;
  end
  initial begin #20000000;$fatal(1,"Concurrent mesh timeout");end
endmodule

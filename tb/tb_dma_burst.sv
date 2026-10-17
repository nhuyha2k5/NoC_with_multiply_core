`timescale 1ns/1ps
module tb_dma_burst;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  axi_lite_if axi(clk_i,rst_ni);axi_lite_bfm host(.clk_i,.axi);
  logic[33:0] tx[0:8],rx[0:8];logic tv[0:8],tvc[0:8],rv[0:8],rvc[0:8];
  logic[1:0] tc[0:8],rc[0:8];logic irq_done,irq_error;
  axi_lite_to_mesh ni(.clk_i,.rst_ni,.s_axi(axi),.tx_flit_o(tx[0]),.tx_valid_o(tv[0]),.tx_vc_o(tvc[0]),
    .tx_credit_i(tc[0]),.rx_flit_i(rx[0]),.rx_valid_i(rv[0]),.rx_vc_i(rvc[0]),.rx_credit_o(rc[0]));
  dma_node dma(.clk_i,.rst_ni,.irq_done_o(irq_done),.irq_error_o(irq_error),
    .noc_tx_flit_o(tx[6]),.noc_tx_valid_o(tv[6]),.noc_tx_vc_o(tvc[6]),.noc_tx_credit_i(tc[6]),
    .noc_rx_flit_i(rx[6]),.noc_rx_valid_i(rv[6]),.noc_rx_vc_i(rvc[6]),.noc_rx_credit_o(rc[6]));
  shared_ram_node ram(.clk_i,.rst_ni,.noc_tx_flit_o(tx[4]),.noc_tx_valid_o(tv[4]),.noc_tx_vc_o(tvc[4]),
    .noc_tx_credit_i(tc[4]),.noc_rx_flit_i(rx[4]),.noc_rx_valid_i(rv[4]),.noc_rx_vc_i(rvc[4]),.noc_rx_credit_o(rc[4]));
  for(genvar n=0;n<9;n++)if(n!=0&&n!=4&&n!=6)begin
    assign tx[n]=0;assign tv[n]=0;assign tvc[n]=0;assign rc[n]=0;
  end
  mesh_3x3_vc mesh(.clk_i,.rst_ni,.local_tx_flit_i(tx),.local_tx_valid_i(tv),.local_tx_vc_i(tvc),
    .local_tx_credit_o(tc),.local_rx_flit_o(rx),.local_rx_valid_o(rv),.local_rx_vc_o(rvc),.local_rx_credit_i(rc));
  logic[31:0] d,small_cycles,burst_cycles;
  task automatic configure(input logic[31:0] src,dst,input int bytes);
    host.write('h30004000,src);host.write('h30004004,dst);host.write('h30004008,32'(bytes));
  endtask
  task automatic finish(input bit expect_error=0);
    do host.read('h30004010,d);while(d[0]);
    assert(d[2]==expect_error&&d[1]!=expect_error)else $fatal(1,"DMA completion status %h",d);
  endtask
  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;
    host.write('h30004014,3);
    for(int i=0;i<301;i++)host.write('h20008ff0+i*4,32'habcdef00^32'(i*17));
    for(int mode=0;mode<2;mode++)begin
      host.write('h30004028,mode?16:1);
      configure('h20008ff0,'h2000a014,1204);host.write('h3000400c,1);finish();
      host.read('h30004018,d);if(mode)burst_cycles=d;else small_cycles=d;
      host.read('h3000401c,d);assert(d==1204)else $fatal(1,"DMA exact bytes");
      for(int i=0;i<301;i++)begin
        host.read('h2000a014+i*4,d);assert(d==(32'habcdef00^32'(i*17)))else $fatal(1,"DMA boundary word %0d",i);
      end
    end
    assert(burst_cycles<small_cycles)else $fatal(1,"Burst did not improve tested workload");
    $display("DMA_METRIC bytes=1204 burst1_cycles=%0d burst16_cycles=%0d",small_cycles,burst_cycles);
    configure('h20008ff0,'h2000a014,1204);host.write('h3000400c,1);host.write('h3000400c,2);finish(1);
    host.read('h30004024,d);assert(d==5)else $fatal(1,"Abort cause");
    configure('h20008ff0,'h2000a014,1204);host.write('h3000400c,1);finish();
    // Hold RAM address acceptance. Watchdog must report but retain busy until drain.
    host.write('h30004020,32);
    force ram.ram_axi.arready=0;
    host.write('h3000400c,1);repeat(100)@(negedge clk_i);
    host.read('h30004010,d);assert(d[2]&&d[0]&&!d[1])else $fatal(1,"Watchdog discarded live transaction");
    host.read('h30004024,d);assert(d==4)else $fatal(1,"Watchdog cause");
    release ram.ram_axi.arready;finish(1);
    host.write('h30004020,0);host.write('h3000400c,1);finish();
    host.write('h30004028,0,15,2);host.write('h30004028,17,15,2);
    $display("TEST_PASS: burst DMA page splitting, partial final burst, double buffering, abort/drain, watchdog and restart");$finish;
  end
  initial begin #5000000;$fatal(1,"DMA burst timeout");end
endmodule

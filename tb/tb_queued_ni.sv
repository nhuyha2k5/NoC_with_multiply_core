`timescale 1ns/1ps
module tb_queued_ni;
  import router_pkg::*;
  logic clk_i=0,rst_ni=0;always #5 clk_i=~clk_i;
  axi_lite_if axi(clk_i,rst_ni);
  axi_lite_bfm host(.clk_i,.axi);
  logic[33:0] tx,rx=0;logic tv,tvc,rv=0,ready=1;
  logic[1:0] rc,tc;
  logic[33:0] headers[64];int heads=0,tails=0,cycle=0;
  assign tc={1'b0,tv&&ready};
  axi_lite_to_mesh dut(.clk_i,.rst_ni,.s_axi(axi),.tx_ready_i(ready),
    .tx_flit_o(tx),.tx_valid_o(tv),.tx_vc_o(tvc),.tx_credit_i(tc),
    .rx_flit_i(rx),.rx_valid_i(rv),.rx_vc_i(1'b1),.rx_credit_o(rc));
  always @(negedge clk_i)begin cycle++;ready=(cycle%7!=2&&cycle%7!=3);end
  always @(posedge clk_i)if(rst_ni&&tv&&ready)begin
    if(tx[33:32]==FLIT_HEAD)begin headers[heads]=tx;heads++;end
    if(tx[33:32]==FLIT_TAIL)tails++;
  end
  task automatic response(input int h,input logic[31:0] value,input logic[1:0] code=0);
    logic[33:0] v;
    v=make_head(0,0,1,1,code==0?NOC_READ_RESP:NOC_ERROR_RESP,0);
    v[14:11]=headers[h][14:11];v[16:15]=code;
    @(negedge clk_i);rx=v;rv=1;
    @(negedge clk_i);rx={FLIT_TAIL,value};
    @(negedge clk_i);rv=0;
  endtask
  initial begin
    repeat(5)@(negedge clk_i);rst_ni=1;
    for(int batch=0;batch<8;batch++)begin
      // Fill all slots without accepting any response.
      for(int i=0;i<4;i++)begin
        @(negedge clk_i);axi.araddr='h20000000+i*4;axi.arvalid=1;
        do @(posedge clk_i);while(!axi.arready);
        @(negedge clk_i);axi.arvalid=0;
      end
      wait(tails==(batch+1)*4);
      assert(!axi.arready)else $fatal(1,"Outstanding capacity not enforced");
      // Reverse arrival order deliberately. Only oldest may retire on AXI.
      for(int i=3;i>=0;i--)response(batch*4+i,32'habc00000+batch*4+i);
      repeat(3)@(negedge clk_i);
      assert(axi.rvalid&&axi.rdata==32'habc00000+batch*4)else $fatal(1,"Reorder buffer failed");
      for(int i=0;i<4;i++)begin
        while(!axi.rvalid)@(negedge clk_i);
        repeat(3)begin
          @(negedge clk_i);
          assert(axi.rvalid&&axi.rdata==32'habc00000+batch*4+i&&axi.rresp==0)
            else $fatal(1,"R unstable/reordered under backpressure");
        end
        axi.rready=1;@(posedge clk_i);@(negedge clk_i);axi.rready=0;
      end
    end
    begin logic[31:0] d;host.read('hffff0000,d,3);host.read('h20000001,d,3);end
    // W-before-AW and nonzero response status propagated by tag.
    fork
      host.write('h20000000,'h1234,5,2,-4);
      begin wait(tails==33);response(32,2,2);end
    join
    assert(heads==33)else $fatal(1,"Local DECERR emitted network traffic");
    @(negedge clk_i);axi.araddr='h20000000;axi.arvalid=1;
    do @(posedge clk_i);while(!axi.arready);
    @(negedge clk_i);axi.arvalid=0;rst_ni=0;
    repeat(4)@(negedge clk_i);rst_ni=1;
    repeat(3)@(negedge clk_i);
    assert(!axi.rvalid&&!axi.bvalid&&axi.arready)else $fatal(1,"NI reset failed to discard epoch");
    $display("TEST_PASS: queued NI 4 outstanding, reversed responses, slot reuse, stalls, decode errors, skew and reset");$finish;
  end
  initial begin #200000;$fatal(1,"Queued NI timeout heads=%0d tails=%0d",heads,tails);end
endmodule

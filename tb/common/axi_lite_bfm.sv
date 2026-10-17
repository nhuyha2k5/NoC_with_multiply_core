module axi_lite_bfm(input logic clk_i, axi_lite_if.master axi);
  initial begin
    axi.awaddr=0;axi.awvalid=0;axi.wdata=0;axi.wstrb=0;axi.wvalid=0;axi.bready=0;
    axi.araddr=0;axi.arvalid=0;axi.rready=0;
  end
  task automatic write(input logic[31:0] addr,data,input logic[3:0] strb=15,
                       input logic[1:0] expected=0,input int skew=0);
    bit aw_done,w_done;
    aw_done=0;w_done=0;
    @(negedge clk_i);axi.awaddr=addr;axi.wdata=data;axi.wstrb=strb;
    axi.awvalid=(skew>=0);axi.wvalid=(skew<=0);axi.bready=0;
    repeat(skew<0?-skew:skew) begin
      @(posedge clk_i);if(axi.awvalid&&axi.awready)aw_done=1;if(axi.wvalid&&axi.wready)w_done=1;
      @(negedge clk_i);if(aw_done)axi.awvalid=0;if(w_done)axi.wvalid=0;
    end
    axi.awvalid=!aw_done;axi.wvalid=!w_done;
    while(!aw_done||!w_done)begin
      @(posedge clk_i);if(axi.awvalid&&axi.awready)aw_done=1;if(axi.wvalid&&axi.wready)w_done=1;
      @(negedge clk_i);if(aw_done)axi.awvalid=0;if(w_done)axi.wvalid=0;
    end
    while(!axi.bvalid)@(negedge clk_i);
    assert(axi.bresp===expected)else $fatal(1,"AXI B %h got %d expected %d",addr,axi.bresp,expected);
    repeat(2)begin @(posedge clk_i);assert(axi.bvalid&&axi.bresp===expected)else $fatal(1,"Unstable B under stall");end
    @(negedge clk_i);axi.bready=1;@(posedge clk_i);@(negedge clk_i);axi.bready=0;
  endtask
  task automatic read(input logic[31:0]addr,output logic[31:0]data,input logic[1:0]expected=0);
    @(negedge clk_i);axi.araddr=addr;axi.arvalid=1;axi.rready=0;
    do @(posedge clk_i);while(!axi.arready);
    @(negedge clk_i);axi.arvalid=0;
    while(!axi.rvalid)@(negedge clk_i);
    data=axi.rdata;
    assert(axi.rresp===expected)else $fatal(1,"AXI R %h got %d expected %d",addr,axi.rresp,expected);
    repeat(2)begin @(posedge clk_i);assert(axi.rvalid&&axi.rdata===data&&axi.rresp===expected)else $fatal(1,"Unstable R under stall");end
    @(negedge clk_i);axi.rready=1;@(posedge clk_i);@(negedge clk_i);axi.rready=0;
  endtask
endmodule

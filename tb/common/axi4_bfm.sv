module axi4_bfm(input logic clk_i,axi4_if.master axi);
  initial begin
    axi.awaddr=0;axi.awid=0;axi.awlen=0;axi.awsize=2;axi.awburst=1;axi.awlock=0;
    axi.awcache=0;axi.awprot=0;axi.awqos=0;axi.awvalid=0;
    axi.wdata=0;axi.wstrb=0;axi.wlast=0;axi.wvalid=0;axi.bready=0;
    axi.araddr=0;axi.arid=0;axi.arlen=0;axi.arsize=2;axi.arburst=1;axi.arlock=0;
    axi.arcache=0;axi.arprot=0;axi.arqos=0;axi.arvalid=0;axi.rready=0;
  end
  function automatic logic[31:0] value(input logic[31:0] seed,input int i);
    return seed^(32'h9e3779b9*32'(i));
  endfunction
  task automatic write(input logic[31:0] addr,input int beats,input logic[31:0] seed,
    input logic[3:0] id=0,input logic[1:0] expected=0,input bit partial=0,input bit bad_last=0);
    @(negedge clk_i);axi.awaddr=addr;axi.awid=id;axi.awlen=8'(beats-1);axi.awvalid=1;
    do @(posedge clk_i);while(!axi.awready);
    @(negedge clk_i);axi.awvalid=0;
    for(int i=0;i<beats;i++)begin
      repeat(i%3)@(negedge clk_i);
      axi.wvalid=1;axi.wdata=value(seed,i);axi.wstrb=partial?(i%2?4'ha:4'h5):4'hf;
      axi.wlast=(i==beats-1)^bad_last;
      do @(posedge clk_i);while(!axi.wready);
      @(negedge clk_i);axi.wvalid=0;
    end
    while(!axi.bvalid)@(negedge clk_i);
    repeat(5)begin
      assert(axi.bvalid&&axi.bid===id&&axi.bresp===expected)else $fatal(1,"Burst B status/ID/stability");
      @(negedge clk_i);
    end
    axi.bready=1;@(posedge clk_i);@(negedge clk_i);axi.bready=0;
  endtask
  task automatic send_read(input logic[31:0] addr,input int beats,input logic[3:0] id=0);
    @(negedge clk_i);axi.araddr=addr;axi.arid=id;axi.arlen=8'(beats-1);axi.arvalid=1;
    do @(posedge clk_i);while(!axi.arready);
    @(negedge clk_i);axi.arvalid=0;
  endtask
  task automatic receive_read(input int beats,input logic[3:0] id,output logic[31:0] result[256],
    input logic[1:0] expected=0);
    logic[31:0] held;
    for(int i=0;i<beats;i++)begin
      while(!axi.rvalid)@(negedge clk_i);
      held=axi.rdata;
      repeat(1+i%4)begin
        assert(axi.rvalid&&axi.rid===id&&axi.rresp===expected&&axi.rdata===held&&axi.rlast==(i==beats-1))
          else $fatal(1,"Burst R status/ID/LAST/stability beat %0d",i);
        @(negedge clk_i);
      end
      result[i]=held;axi.rready=1;@(posedge clk_i);@(negedge clk_i);axi.rready=0;
    end
  endtask
endmodule

// Two AXI-Lite read ports over one boot image: instruction fetch and CPU data.
// Both synchronous reads infer a true dual-port ROM. Writes return SLVERR.
module boot_rom_dual #(
  parameter int WORDS=4096,parameter string INIT_FILE="",
  localparam int IW=$clog2(WORDS)
)(input logic clk_i,rst_ni,axi_lite_if.slave instr,data);
  (* rom_style="block" *) logic[31:0] mem[0:WORDS-1];
  logic irv,drv,dbv,daw,dw;
  logic[31:0] idata,ddata;logic[1:0] irsp,drsp;
  initial begin
    for(int i=0;i<WORDS;i++)mem[i]=32'h13;
    if(INIT_FILE!="")$readmemh(INIT_FILE,mem);
  end
  assign instr.arready=rst_ni&&!irv;assign instr.rvalid=rst_ni&&irv;
  assign instr.rdata=idata;assign instr.rresp=irsp;
  // The instruction bridge is read-only; writes are never accepted here.
  assign instr.awready=0;assign instr.wready=0;assign instr.bvalid=0;assign instr.bresp=2;
  assign data.arready=rst_ni&&!drv;assign data.rvalid=rst_ni&&drv;
  assign data.rdata=ddata;assign data.rresp=drsp;
  assign data.awready=rst_ni&&!daw&&!dbv;assign data.wready=rst_ni&&!dw&&!dbv;
  assign data.bvalid=rst_ni&&dbv;assign data.bresp=2;
  always @(posedge clk_i)begin
    if(instr.arvalid&&instr.arready)idata<=mem[instr.araddr[2+:IW]];
    if(data.arvalid&&data.arready)ddata<=mem[data.araddr[2+:IW]];
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin irv<=0;drv<=0;dbv<=0;daw<=0;dw<=0;irsp<=0;drsp<=0;end
    else begin
      if(instr.arvalid&&instr.arready)begin irv<=1;irsp<=(instr.araddr<WORDS*4&&instr.araddr[1:0]==0)?0:3;end
      if(instr.rvalid&&instr.rready)irv<=0;
      if(data.arvalid&&data.arready)begin drv<=1;drsp<=(data.araddr<WORDS*4&&data.araddr[1:0]==0)?0:3;end
      if(data.rvalid&&data.rready)drv<=0;
      if(data.awvalid&&data.awready)daw<=1;
      if(data.wvalid&&data.wready)dw<=1;
      if(daw&&dw&&!dbv)begin daw<=0;dw<=0;dbv<=1;end
      if(data.bvalid&&data.bready)dbv<=0;
    end
  end
endmodule

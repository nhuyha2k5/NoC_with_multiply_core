// Four interleaved BRAM banks, independent pipelined read/write ports.
// One word/cycle/channel within a burst. Same-address simultaneous read/write
// is read-first in RTL; software must synchronize competing writers/readers.
module axi4_banked_ram #(
  parameter int WORDS=16384,BANKS=4,
  parameter logic[31:0] BASE_ADDR=32'h20000000,
  parameter string INIT_FILE="",
  localparam int BANK_W=$clog2(BANKS),
  localparam int ROW_W=$clog2(WORDS/BANKS)
)(input logic clk_i,rst_ni,axi4_if.slave s_axi);
  logic wa_active,ra_active,wlegal,rlegal,bvalid,rvalid,wbad;
  logic[31:0] wa,ra;
  logic[7:0] wlen,rlen,wn,rn;
  logic[3:0] wid,rid;
  logic[1:0] bresp,rresp;
  logic rlast;
  logic read_issue,write_issue;
  logic[BANK_W-1:0] read_bank;
  logic[31:0] bank_data[BANKS];
  wire[31:0] woffset=wa-BASE_ADDR,roffset=ra-BASE_ADDR;
  function automatic logic legal(input logic[31:0] a,input logic[7:0] len,
    input logic[2:0] size,input logic[1:0] burst,input logic lock);
    logic[32:0] finish;
    finish={1'b0,a}+(({25'b0,len}+33'd1)<<2);
    return a[1:0]==0&&size==2&&burst==1&&!lock&&a>=BASE_ADDR&&
      finish<=({1'b0,BASE_ADDR}+33'(WORDS*4))&&
      ({1'b0,a[11:0]}+(({5'b0,len}+13'd1)<<2)<=4096);
  endfunction
  assign s_axi.awready=rst_ni&&!wa_active&&!bvalid;
  assign s_axi.wready=rst_ni&&wa_active;
  assign s_axi.bvalid=rst_ni&&bvalid;
  assign s_axi.bresp=bresp;
  assign s_axi.bid=wid;
  assign s_axi.arready=rst_ni&&!ra_active&&!rvalid;
  assign s_axi.rvalid=rst_ni&&rvalid;
  assign s_axi.rdata=rresp==0?bank_data[read_bank]:32'b0;
  assign s_axi.rresp=rresp;
  assign s_axi.rid=rid;
  assign s_axi.rlast=rlast;
  assign write_issue=s_axi.wvalid&&s_axi.wready;
  assign read_issue=rst_ni&&ra_active&&(!rvalid||s_axi.rready);
  for(genvar b=0;b<BANKS;b++)begin:g_bank
    (* ram_style="block" *) logic[31:0] mem[0:WORDS/BANKS-1];
    logic[31:0] image[0:WORDS-1];
    initial begin
      for(int i=0;i<WORDS/BANKS;i++)mem[i]=0;
      if(INIT_FILE!="")begin
        $readmemh(INIT_FILE,image);
        for(int i=0;i<WORDS/BANKS;i++)mem[i]=image[i*BANKS+b];
      end
    end
    always @(posedge clk_i)begin
      if(write_issue&&wlegal&&woffset[2+:BANK_W]==BANK_W'(b))
        for(int byte_n=0;byte_n<4;byte_n++)if(s_axi.wstrb[byte_n])
          mem[woffset[2+BANK_W+:ROW_W]][byte_n*8+:8]<=s_axi.wdata[byte_n*8+:8];
      if(read_issue&&rlegal)bank_data[b]<=mem[roffset[2+BANK_W+:ROW_W]];
    end
  end
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      wa_active<=0;ra_active<=0;bvalid<=0;rvalid<=0;wbad<=0;
      wa<=0;ra<=0;wlen<=0;rlen<=0;wn<=0;rn<=0;wid<=0;rid<=0;
      wlegal<=0;rlegal<=0;bresp<=0;rresp<=0;rlast<=0;read_bank<=0;
    end else begin
      if(s_axi.awvalid&&s_axi.awready)begin
        wa_active<=1;wa<=s_axi.awaddr;wlen<=s_axi.awlen;wid<=s_axi.awid;wn<=0;wbad<=0;
        wlegal<=legal(s_axi.awaddr,s_axi.awlen,s_axi.awsize,s_axi.awburst,s_axi.awlock);
      end
      if(write_issue)begin
        if(s_axi.wlast!=(wn==wlen))wbad<=1;
        if(wn==wlen)begin
          wa_active<=0;bvalid<=1;
          bresp<=!wlegal?3:((wbad||!s_axi.wlast)?2:0);
        end else begin wn<=wn+1'b1;wa<=wa+4;end
      end
      if(s_axi.bvalid&&s_axi.bready)bvalid<=0;
      if(s_axi.arvalid&&s_axi.arready)begin
        ra_active<=1;ra<=s_axi.araddr;rlen<=s_axi.arlen;rid<=s_axi.arid;rn<=0;
        rlegal<=legal(s_axi.araddr,s_axi.arlen,s_axi.arsize,s_axi.arburst,s_axi.arlock);
      end
      if(s_axi.rvalid&&s_axi.rready)rvalid<=0;
      if(read_issue)begin
        rvalid<=1;read_bank<=roffset[2+:BANK_W];rresp<=rlegal?0:3;rlast<=rn==rlen;
        if(rn==rlen)ra_active<=0;
        else begin ra<=ra+4;rn<=rn+1'b1;end
      end
    end
  end
`ifndef SYNTHESIS
  initial assert(BANKS>=2&&(BANKS&(BANKS-1))==0&&WORDS>BANKS&&(WORDS&(WORDS-1))==0)
    else $fatal(1,"RAM geometry must use power-of-two banks/words");
`endif
endmodule

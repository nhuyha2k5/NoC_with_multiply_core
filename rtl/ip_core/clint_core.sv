// SiFive-CLINT-compatible timer and software-interrupt block (ACLINT MSWI +
// MTIMER layout). Offsets from the CLINT base (0x0200_0000 in the SoC):
//   0x0000 + 4*h      msip[h]      bit 0 R/W, bits 31:1 read as zero
//   0x4000 + 8*h      mtimecmp[h]  64 bit (low word, high word at +4)
//   0xBFF8            mtime        64 bit (low word, high word at +4)
// mtime counts clock cycles. MTIP[h] = (mtime >= mtimecmp[h]), unsigned, and
// is registered (one clock). Software masks MTIP with mie.MTIE and clears it
// by writing mtimecmp. Byte strobes are honoured; reserved offsets answer
// DECERR. Reset: mtime = 0, mtimecmp = all ones (no interrupt), msip = 0.
module clint_core #(parameter int HARTS=4)(
  input logic clk_i,rst_ni,wr_en_i,
  input logic [15:0] wr_offset_i,rd_offset_i,
  input logic [31:0] wr_data_i,
  input logic [3:0] wr_strb_i,
  output logic [31:0] rd_data_o,
  output logic [1:0] wr_resp_o,rd_resp_o,
  output logic [HARTS-1:0] timer_irq_o,software_irq_o
);
  logic [63:0] mtime_q,cmp_q[HARTS];
  logic [HARTS-1:0] msip_q;
  function automatic logic valid_offset(input logic [15:0] off);
    if(off[1:0]!=0)return 0;
    if(off<16'(4*HARTS))return 1;
    if(off>=16'h4000 && off<16'(16'h4000+8*HARTS))return 1;
    return off==16'hbff8 || off==16'hbffc;
  endfunction
  assign software_irq_o=msip_q;
  always_comb begin
    rd_data_o=0;
    wr_resp_o=valid_offset(wr_offset_i)?0:2'b11;
    rd_resp_o=valid_offset(rd_offset_i)?0:2'b11;
    for(int h=0;h<HARTS;h++)begin
      if(rd_offset_i==16'(4*h))rd_data_o={31'b0,msip_q[h]};
      if(rd_offset_i==16'(16'h4000+8*h))rd_data_o=cmp_q[h][31:0];
      if(rd_offset_i==16'(16'h4004+8*h))rd_data_o=cmp_q[h][63:32];
    end
    if(rd_offset_i==16'hbff8)rd_data_o=mtime_q[31:0];
    if(rd_offset_i==16'hbffc)rd_data_o=mtime_q[63:32];
  end
  always_ff @(posedge clk_i)
    if(!rst_ni)begin
      mtime_q<=0;msip_q<=0;timer_irq_o<=0;
      for(int h=0;h<HARTS;h++)cmp_q[h]<='1;
    end else begin
      mtime_q<=mtime_q+1'b1;
      for(int h=0;h<HARTS;h++)timer_irq_o[h]<=mtime_q>=cmp_q[h];
      if(wr_en_i && wr_resp_o==0)begin
        for(int h=0;h<HARTS;h++)begin
          if(wr_offset_i==16'(4*h) && wr_strb_i[0])msip_q[h]<=wr_data_i[0];
          for(int b=0;b<4;b++)if(wr_strb_i[b])begin
            if(wr_offset_i==16'(16'h4000+8*h))cmp_q[h][b*8+:8]<=wr_data_i[b*8+:8];
            if(wr_offset_i==16'(16'h4004+8*h))cmp_q[h][32+b*8+:8]<=wr_data_i[b*8+:8];
          end
        end
        for(int b=0;b<4;b++)if(wr_strb_i[b])begin
          if(wr_offset_i==16'hbff8)mtime_q[b*8+:8]<=wr_data_i[b*8+:8];
          if(wr_offset_i==16'hbffc)mtime_q[32+b*8+:8]<=wr_data_i[b*8+:8];
        end
      end
    end
`ifndef SYNTHESIS
  initial assert(HARTS>=1&&HARTS<=16)else $fatal(1,"CLINT supports 1..16 harts");
`endif
endmodule

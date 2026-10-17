// Hardware test-and-set lock bank (Ibex has no A extension), base 0x3000_7000.
// Lock i is the word at offset 4*i, i < LOCKS.
//   Read : returns the lock value before the read (0 = was free and is now
//          held by this reader, 1 = busy) and sets the lock. Acquire.
//   Write: with wstrb[0], sets the lock to wdata[0]; writing 0 releases.
// The register port serialises accesses, so two harts never both read 0.
// If a release and an acquire read hit one lock in the same cycle, the read
// sees the old (busy) value and the release wins, so the lock ends free and
// the reader retries. Reset frees every lock. Other offsets answer DECERR.
module axi_lite_tas #(parameter int LOCKS=16)(
  input logic clk_i,rst_ni,
  axi_lite_if.slave s_axi
);
  localparam int IDX_W=(LOCKS>1)?$clog2(LOCKS):1;
  logic wr,rd;logic[31:0] wa,wd,ra,rdata;logic[3:0] ws;logic[1:0] wresp,rresp;
  logic [LOCKS-1:0] lock_q;
  logic wvalid_off,rvalid_off;
  logic [IDX_W-1:0] widx,ridx;
  assign widx=wa[2+:IDX_W];
  assign ridx=ra[2+:IDX_W];
  assign wvalid_off=wa[31:12]==20'h30007 && wa[1:0]==0 && wa[11:2]<LOCKS;
  assign rvalid_off=ra[31:12]==20'h30007 && ra[1:0]==0 && ra[11:2]<LOCKS;
  assign wresp=wvalid_off?2'b00:2'b11;
  assign rresp=rvalid_off?2'b00:2'b11;
  assign rdata=rvalid_off?{31'b0,lock_q[ridx]}:32'b0;
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
    .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  always_ff @(posedge clk_i)
    if(!rst_ni)lock_q<='0;
    else begin
      if(rd && rvalid_off)lock_q[ridx]<=1'b1;
      if(wr && wvalid_off && ws[0])lock_q[widx]<=wd[0];
    end
`ifndef SYNTHESIS
  initial assert(LOCKS>=1&&LOCKS<=1024)else $fatal(1,"TAS supports 1..1024 locks");
`endif
endmodule

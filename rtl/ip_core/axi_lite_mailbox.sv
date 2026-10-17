// HARTS-slot mailbox. A message write with a nonzero strobe sets the target
// hart's level interrupt; software clears it through CLEAR (write 1 to clear).
// Offsets keep the original 2-hart layout:
//   0x00 slot 0, 0x04 slot 1, 0x08 PENDING (read only, write -> SLVERR),
//   0x0C CLEAR (reads 0), 0x10 + 4*(h-2) slot h for h >= 2.
module axi_lite_mailbox #(parameter int HARTS=2)(
 input logic clk_i,rst_ni,
 output logic [HARTS-1:0] irq_o,
 axi_lite_if.slave s_axi);
 logic[31:0] message_q[HARTS];logic[HARTS-1:0] pending_q;
 logic wr,rd;logic[31:0] wa,wd,ra,rdata;logic[3:0] ws;logic[1:0] wresp,rresp;
 int wslot,rslot;
 function automatic int slot_of(input logic [7:0] off);
   if(off==0)return 0;
   if(off==4)return 1;
   for(int h=2;h<HARTS;h++)if(off==8'(16+4*(h-2)))return h;
   return -1;
 endfunction
 assign irq_o=pending_q;
 always_comb begin
   wresp=0;rresp=0;rdata=0;
   wslot=slot_of(wa[7:0]);rslot=slot_of(ra[7:0]);
   if(wa[31:8]!=24'h300030 || wa[1:0]!=0 || (wslot<0 && wa[7:0]!=8 && wa[7:0]!=12))wresp=3;
   else if(wa[7:0]==8)wresp=2;
   if(ra[31:8]!=24'h300030 || ra[1:0]!=0 || (rslot<0 && ra[7:0]!=8 && ra[7:0]!=12))rresp=3;
   if(rslot>=0)rdata=message_q[rslot];
   else if(ra[7:0]==8)rdata=32'(pending_q);
 end
 axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
   .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
   .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
 always_ff @(posedge clk_i)
   if(!rst_ni)begin for(int h=0;h<HARTS;h++)message_q[h]<=0;pending_q<=0;end
   else if(wr && wresp==0)begin
     if(wslot>=0)begin
       for(int b=0;b<4;b++)if(ws[b])message_q[wslot][8*b+:8]<=wd[8*b+:8];
       if(|ws)pending_q[wslot]<=1;
     end
     if(wa[7:0]==12 && ws[0])pending_q<=pending_q & ~wd[HARTS-1:0];
   end
`ifndef SYNTHESIS
 initial assert(HARTS>=1&&HARTS<=8)else $fatal(1,"Mailbox supports 1..8 harts");
`endif
endmodule

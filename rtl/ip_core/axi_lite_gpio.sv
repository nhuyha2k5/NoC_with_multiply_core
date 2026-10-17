// Exact-decoded AXI4-Lite GPIO with byte writes and independent AW/W.
module axi_lite_gpio #(parameter int WIDTH=8)(
 input logic clk_i,rst_ni,input logic[WIDTH-1:0] gpio_i,
 output logic[WIDTH-1:0] gpio_o,gpio_oe_o,output logic irq_o,axi_lite_if.slave s_axi);
 logic wr,rd;logic[31:0] wa,wd,ra,rdata;logic[3:0] ws;
 logic[1:0] wresp,rresp;
 logic[WIDTH-1:0] previous,irq_enable,rising,falling,pending,events,clear_mask;
 assign events=((gpio_i&~previous)&rising)|((~gpio_i&previous)&falling);
 assign irq_o=|(pending&irq_enable);
 always_comb begin
   clear_mask=0;
   for(int i=0;i<WIDTH;i++)if(wr&&wresp==0&&wa[7:0]==24&&ws[i/8])clear_mask[i]=wd[i];
 end
 always_comb begin
   wresp=0;rresp=0;rdata=0;
   if(wa[31:8]!=24'h300010 || wa[1:0]!=0 || wa[7:0]>24)wresp=3;
   else if(wa[7:0]==8)wresp=2;
   if(ra[31:8]!=24'h300010 || ra[1:0]!=0 || ra[7:0]>24)rresp=3;
   case(ra[7:0])
     0:rdata=32'(gpio_o);4:rdata=32'(gpio_oe_o);8:rdata=32'(gpio_i);
     12:rdata=32'(irq_enable);16:rdata=32'(rising);20:rdata=32'(falling);24:rdata=32'(pending);
     default:;
   endcase
 end
 axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
   .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
   .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
 always_ff @(posedge clk_i)
   if(!rst_ni)begin gpio_o<=0;gpio_oe_o<=0;previous<=0;irq_enable<=0;rising<=0;falling<=0;pending<=0;end
   else begin
     previous<=gpio_i;pending<=(pending&~clear_mask)|events;
     if(wr && wresp==0)for(int i=0;i<WIDTH;i++)if(ws[i/8])begin
       if(wa[7:0]==0)gpio_o[i]<=wd[i];
       if(wa[7:0]==4)gpio_oe_o[i]<=wd[i];
       if(wa[7:0]==12)irq_enable[i]<=wd[i];
       if(wa[7:0]==16)rising[i]<=wd[i];
       if(wa[7:0]==20)falling[i]<=wd[i];
     end
   end
endmodule

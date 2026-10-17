// TX-only 8N1 UART with maskable completion interrupt (W1C pending).
module axi_lite_uart #(
  parameter int CLOCK_HZ=50_000_000,BAUD=115_200,
  localparam int CLKS_PER_BIT=(CLOCK_HZ/BAUD<1)?1:CLOCK_HZ/BAUD,
  localparam int BAUD_W=(CLKS_PER_BIT<=1)?1:$clog2(CLKS_PER_BIT)
)(
  input logic clk_i,rst_ni,
  output logic tx_o,irq_o,
  axi_lite_if.slave s_axi
);
  logic [9:0] shift_q;
  logic [3:0] bits_q;
  logic [BAUD_W-1:0] baud_q;
  logic busy_q,enable_q,pending_q,wr,rd;
  logic [31:0] wa,wd,ra,rdata;
  logic [3:0] ws;
  logic [1:0] wresp,rresp;
  assign tx_o=busy_q?shift_q[0]:1'b1;
  assign irq_o=enable_q&&pending_q;
  always_comb begin
    rdata=0;wresp=0;rresp=0;
    if(wa[31:4]!=28'h3000000||wa[1:0]!=0)wresp=3;
    if(ra[31:4]!=28'h3000000||ra[1:0]!=0)rresp=3;
    if(wa[3:0]==0&&busy_q)wresp=2;
    case(ra[3:0])
      4:rdata={30'b0,!busy_q,busy_q};
      8:rdata={31'b0,enable_q};
      12:rdata={31'b0,pending_q};
      default: ;
    endcase
  end
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
    .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  always_ff @(posedge clk_i)
    if(!rst_ni)begin shift_q<='1;bits_q<=0;baud_q<=0;busy_q<=0;enable_q<=0;pending_q<=0;end
    else begin
      if(wr&&wresp==0&&ws[0])case(wa[3:0])
        0:begin shift_q<={1'b1,wd[7:0],1'b0};bits_q<=0;baud_q<=0;busy_q<=1;end
        8:enable_q<=wd[0];
        12:if(wd[0])pending_q<=0;
        default: ;
      endcase
      if(busy_q)begin
        if(baud_q==CLKS_PER_BIT-1)begin
          baud_q<=0;shift_q<={1'b1,shift_q[9:1]};
          if(bits_q==9)begin busy_q<=0;pending_q<=1;end
          else bits_q<=bits_q+1'b1;
        end else baud_q<=baud_q+1'b1;
      end
    end
endmodule

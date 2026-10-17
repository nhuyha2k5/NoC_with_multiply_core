// Backward-compatible timer offsets plus hart1 compare and per-hart MSIP.
module timer_ipi_core(
  input logic clk_i,rst_ni,wr_en_i,
  input logic [7:0] wr_offset_i,rd_offset_i,
  input logic [31:0] wr_data_i,
  input logic [3:0] wr_strb_i,
  output logic [31:0] rd_data_o,
  output logic [1:0] wr_resp_o,rd_resp_o,timer_irq_o,software_irq_o
);
  logic [63:0] mtime_q,cmp_q[0:1];
  logic [1:0] enable_q,msip_q;
  function automatic logic valid_offset(input logic [7:0] off);
    return off==0||off==4||off==8||off==12||off==16||off==24||off==28||off==32||off==36;
  endfunction
  assign software_irq_o=msip_q;
  assign timer_irq_o[0]=enable_q[0] && mtime_q>=cmp_q[0];
  assign timer_irq_o[1]=enable_q[1] && mtime_q>=cmp_q[1];
  always_comb begin
    rd_data_o=0;wr_resp_o=valid_offset(wr_offset_i)?0:3;rd_resp_o=valid_offset(rd_offset_i)?0:3;
    case(rd_offset_i)
      0:rd_data_o=mtime_q[31:0];4:rd_data_o=mtime_q[63:32];
      8:rd_data_o=cmp_q[0][31:0];12:rd_data_o=cmp_q[0][63:32];
      16:rd_data_o={22'b0,timer_irq_o,6'b0,enable_q};
      24:rd_data_o=cmp_q[1][31:0];28:rd_data_o=cmp_q[1][63:32];
      32:rd_data_o={31'b0,msip_q[0]};36:rd_data_o={31'b0,msip_q[1]};
      default: ;
    endcase
  end
  always_ff @(posedge clk_i)
    if(!rst_ni) begin mtime_q<=0;cmp_q[0]<='1;cmp_q[1]<='1;enable_q<=0;msip_q<=0;end
    else begin
      mtime_q<=mtime_q+1'b1;
      if(wr_en_i && wr_resp_o==0) begin
        for(int b=0;b<4;b++) if(wr_strb_i[b]) case(wr_offset_i)
          0:mtime_q[b*8+:8]<=wr_data_i[b*8+:8];
          4:mtime_q[32+b*8+:8]<=wr_data_i[b*8+:8];
          8:cmp_q[0][b*8+:8]<=wr_data_i[b*8+:8];
          12:cmp_q[0][32+b*8+:8]<=wr_data_i[b*8+:8];
          24:cmp_q[1][b*8+:8]<=wr_data_i[b*8+:8];
          28:cmp_q[1][32+b*8+:8]<=wr_data_i[b*8+:8];
          default: ;
        endcase
        if(wr_strb_i[0]) case(wr_offset_i)
          16:enable_q<=wr_data_i[1:0];32:msip_q[0]<=wr_data_i[0];36:msip_q[1]<=wr_data_i[0];
          default: ;
        endcase
      end
    end
endmodule

// Memory-to-memory DMA for aligned, nonoverlapping noncacheable buffers.
module axi_lite_dma(
  input logic clk_i,rst_ni,
  axi_lite_if.slave s_axi,
  axi_lite_if.master m_axi,
  output logic irq_done_o,irq_error_o
);
  import router_pkg::*;
  typedef enum logic [2:0] {IDLE,READ_CMD,READ_RSP,WRITE_CMD,WRITE_RSP} state_t;
  state_t state_q;
  logic wr,rd,done_q,error_q;
  logic [31:0] wa,wd,ra,rdata,src_q,dst_q,len_q,offset_q,data_q,cycles_q,bytes_q;
  logic [3:0] ws;
  logic [1:0] irq_enable_q,wresp,rresp,rsp_resp;
  logic cmd_ready,rsp_valid;
  logic [31:0] rsp_data;
  logic config_valid,start;
  assign config_valid=engine_range(src_q,len_q)&&engine_range(dst_q,len_q)&&
    (({1'b0,src_q}+{1'b0,len_q}<={1'b0,dst_q})||
     ({1'b0,dst_q}+{1'b0,len_q}<={1'b0,src_q}));
  assign start=wr && wa[7:0]==12 && ws[0] && wd[0] && state_q==IDLE && wresp==0;
  assign irq_done_o=done_q&&irq_enable_q[0];
  assign irq_error_o=error_q&&irq_enable_q[1];
  always_comb begin
    rdata=0;wresp=0;rresp=0;
    if(wa[31:8]!=24'h300040 || wa[1:0]!=0 || wa[7:0]>28) wresp=3;
    if(ra[31:8]!=24'h300040 || ra[1:0]!=0 || ra[7:0]>28) rresp=3;
    if(wresp==0 && ((state_q!=IDLE && wa[7:0]<=12) || wa[7:0]>=24)) wresp=2;
    case(ra[7:0])
      0:rdata=src_q;4:rdata=dst_q;8:rdata=len_q;
      16:rdata={29'b0,error_q,done_q,(state_q!=IDLE)};
      20:rdata={30'b0,irq_enable_q};24:rdata=cycles_q;28:rdata=bytes_q;
      default: ;
    endcase
  end
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
    .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  axi_lite_word_master u_engine(.clk_i,.rst_ni,.m_axi,
    .cmd_valid_i(state_q==READ_CMD||state_q==WRITE_CMD),.cmd_ready_o(cmd_ready),
    .cmd_write_i(state_q==WRITE_CMD),.cmd_addr_i((state_q==WRITE_CMD?dst_q:src_q)+offset_q),
    .cmd_data_i(data_q),.rsp_valid_o(rsp_valid),.rsp_ready_i(1'b1),
    .rsp_data_o(rsp_data),.rsp_resp_o(rsp_resp));
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin
      state_q<=IDLE;src_q<=0;dst_q<=0;len_q<=0;offset_q<=0;data_q<=0;
      done_q<=0;error_q<=0;irq_enable_q<=0;cycles_q<=0;bytes_q<=0;
    end else begin
      if(state_q!=IDLE) cycles_q<=cycles_q+1'b1;
      if(wr && wresp==0) begin
        for(int b=0;b<4;b++) if(ws[b]) case(wa[7:0])
          0:src_q[b*8+:8]<=wd[b*8+:8];4:dst_q[b*8+:8]<=wd[b*8+:8];8:len_q[b*8+:8]<=wd[b*8+:8];
          default: ;
        endcase
        if(wa[7:0]==20 && ws[0]) irq_enable_q<=wd[1:0];
        if(wa[7:0]==16 && ws[0]) begin if(wd[1])done_q<=0;if(wd[2])error_q<=0;end
      end
      case(state_q)
        IDLE: if(start) begin
          done_q<=0;error_q<=0;offset_q<=0;bytes_q<=0;cycles_q<=0;
          if(len_q==0) done_q<=1;
          else if(!config_valid) error_q<=1;
          else state_q<=READ_CMD;
        end
        READ_CMD: if(cmd_ready) state_q<=READ_RSP;
        READ_RSP: if(rsp_valid) begin
          if(rsp_resp!=0) begin error_q<=1;state_q<=IDLE;end
          else begin data_q<=rsp_data;state_q<=WRITE_CMD;end
        end
        WRITE_CMD: if(cmd_ready) state_q<=WRITE_RSP;
        WRITE_RSP: if(rsp_valid) begin
          if(rsp_resp!=0) begin error_q<=1;state_q<=IDLE;end
          else begin
            bytes_q<=bytes_q+4;
            if(offset_q+4==len_q) begin done_q<=1;state_q<=IDLE;end
            else begin offset_q<=offset_q+4;state_q<=READ_CMD;end
          end
        end
        default: state_q<=IDLE;
      endcase
    end
  end
endmodule

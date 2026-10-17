// Signed 32-bit NxN matrix multiply, N=1..16, low 32 bits of 64-bit sum.
// A/B loaded once; one pipelined MAC launched per clock after preload.
module axi_lite_matrix_accelerator(
  input logic clk_i,rst_ni,
  axi_lite_if.slave s_axi,
  axi_lite_if.master m_axi,
  output logic irq_done_o,irq_error_o
);
  import router_pkg::*;
  typedef enum logic [3:0] {IDLE,A_CMD,A_RSP,B_CMD,B_RSP,PREP,STREAM,DRAIN,C_CMD,C_RSP} state_t;
  state_t state_q;
  logic wr,rd,done_q,error_q,start,config_valid;
  logic [31:0] wa,wd,ra,rdata,a_q,b_q,c_q,n_q,cycles_q,macs_q;
  logic [3:0] ws;
  logic [1:0] irq_enable_q,wresp,rresp,rsp_resp;
  logic cmd_ready,rsp_valid;
  logic [31:0] rsp_data,cmd_addr,bytes;
  logic [8:0] load_q;
  logic [8:0] matrix_words,a_index,b_index,c_index;
  logic [4:0] row_q,col_q,k_q;
  logic signed [31:0] a_mem[0:255],b_mem[0:255],op_a_q,op_b_q;
  logic signed [63:0] product_q,sum_q;
  logic product_valid_q;
  // Width-limited arithmetic: valid N is at most 16, never a 32x32 index multiply.
  assign matrix_words=9'(n_q[4:0])*9'(n_q[4:0]);
  assign a_index=9'(row_q)*9'(n_q[4:0])+9'(k_q);
  assign b_index=9'(k_q)*9'(n_q[4:0])+9'(col_q);
  assign c_index=9'(row_q)*9'(n_q[4:0])+9'(col_q);
  assign bytes={21'b0,matrix_words,2'b0};
  assign config_valid=n_q>0&&n_q<=16&&engine_range(a_q,bytes)&&engine_range(b_q,bytes)&&engine_range(c_q,bytes)&&
    (({1'b0,c_q}+bytes<={1'b0,a_q})||({1'b0,a_q}+bytes<={1'b0,c_q}))&&
    (({1'b0,c_q}+bytes<={1'b0,b_q})||({1'b0,b_q}+bytes<={1'b0,c_q}));
  assign start=wr&&wa[7:0]==16&&ws[0]&&wd[0]&&state_q==IDLE&&wresp==0;
  assign irq_done_o=done_q&&irq_enable_q[0];
  assign irq_error_o=error_q&&irq_enable_q[1];
  assign cmd_addr=state_q==C_CMD ? c_q+{21'b0,c_index,2'b0} :
    (state_q==B_CMD?b_q:a_q)+{21'b0,load_q,2'b0};
  always_comb begin
    rdata=0;wresp=0;rresp=0;
    if(wa[31:8]!=24'h300050||wa[1:0]!=0||wa[7:0]>32)wresp=3;
    if(ra[31:8]!=24'h300050||ra[1:0]!=0||ra[7:0]>32)rresp=3;
    if(wresp==0 && ((state_q!=IDLE&&wa[7:0]<=16) || wa[7:0]>=28))wresp=2;
    case(ra[7:0])
      0:rdata=a_q;4:rdata=b_q;8:rdata=c_q;12:rdata=n_q;
      20:rdata={29'b0,error_q,done_q,state_q!=IDLE};
      24:rdata={30'b0,irq_enable_q};28:rdata=cycles_q;32:rdata=macs_q;
      default: ;
    endcase
  end
  axi_lite_register_port u_regs(.clk_i,.rst_ni,.s_axi,.wr_en_o(wr),.rd_en_o(rd),
    .wr_addr_o(wa),.wr_data_o(wd),.wr_strb_o(ws),.rd_addr_o(ra),
    .rd_data_i(rdata),.wr_resp_i(wresp),.rd_resp_i(rresp));
  axi_lite_word_master u_engine(.clk_i,.rst_ni,.m_axi,
    .cmd_valid_i(state_q==A_CMD||state_q==B_CMD||state_q==C_CMD),.cmd_ready_o(cmd_ready),
    .cmd_write_i(state_q==C_CMD),.cmd_addr_i(cmd_addr),.cmd_data_i(sum_q[31:0]),
    .rsp_valid_o(rsp_valid),.rsp_ready_i(1'b1),.rsp_data_o(rsp_data),.rsp_resp_o(rsp_resp));
  // Buffers are not reset; they are completely loaded before computation.
  always @(posedge clk_i) begin
    if(rst_ni && rsp_valid && rsp_resp==0) begin
      if(state_q==A_RSP)a_mem[load_q[7:0]]<=rsp_data;
      if(state_q==B_RSP)b_mem[load_q[7:0]]<=rsp_data;
    end
  end
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin
      state_q<=IDLE;a_q<=0;b_q<=0;c_q<=0;n_q<=0;cycles_q<=0;macs_q<=0;
      done_q<=0;error_q<=0;irq_enable_q<=0;load_q<=0;row_q<=0;col_q<=0;k_q<=0;
      op_a_q<=0;op_b_q<=0;product_q<=0;sum_q<=0;product_valid_q<=0;
    end else begin
      if(state_q!=IDLE)cycles_q<=cycles_q+1'b1;
      if(wr&&wresp==0) begin
        for(int b=0;b<4;b++)if(ws[b])case(wa[7:0])
          0:a_q[b*8+:8]<=wd[b*8+:8];4:b_q[b*8+:8]<=wd[b*8+:8];
          8:c_q[b*8+:8]<=wd[b*8+:8];12:n_q[b*8+:8]<=wd[b*8+:8];default: ;
        endcase
        if(wa[7:0]==24&&ws[0])irq_enable_q<=wd[1:0];
        if(wa[7:0]==20&&ws[0])begin if(wd[1])done_q<=0;if(wd[2])error_q<=0;end
      end
      case(state_q)
        IDLE:if(start)begin
          done_q<=0;error_q<=0;load_q<=0;cycles_q<=0;macs_q<=0;
          row_q<=0;col_q<=0;k_q<=0;sum_q<=0;product_valid_q<=0;
          if(!config_valid)error_q<=1;else state_q<=A_CMD;
        end
        A_CMD:if(cmd_ready)state_q<=A_RSP;
        B_CMD:if(cmd_ready)state_q<=B_RSP;
        A_RSP,B_RSP:if(rsp_valid)begin
          if(rsp_resp!=0)begin error_q<=1;state_q<=IDLE;end
          else if(load_q+1==matrix_words)begin
            load_q<=0;state_q<=state_q==A_RSP?B_CMD:PREP;
          end else begin load_q<=load_q+1'b1;state_q<=state_q==A_RSP?A_CMD:B_CMD;end
        end
        PREP:begin
          op_a_q<=a_mem[a_index[7:0]];op_b_q<=b_mem[b_index[7:0]];
          k_q<=1;product_valid_q<=0;state_q<=STREAM;
        end
        STREAM:begin
          product_q<=op_a_q*op_b_q;product_valid_q<=1;
          if(product_valid_q)begin sum_q<=sum_q+product_q;macs_q<=macs_q+1'b1;end
          if(k_q<n_q)begin
            op_a_q<=a_mem[a_index[7:0]];op_b_q<=b_mem[b_index[7:0]];k_q<=k_q+1'b1;
          end else state_q<=DRAIN;
        end
        DRAIN:begin
          sum_q<=sum_q+product_q;macs_q<=macs_q+1'b1;product_valid_q<=0;state_q<=C_CMD;
        end
        C_CMD:if(cmd_ready)state_q<=C_RSP;
        C_RSP:if(rsp_valid)begin
          if(rsp_resp!=0)begin error_q<=1;state_q<=IDLE;end
          else if(row_q+1==n_q&&col_q+1==n_q)begin done_q<=1;state_q<=IDLE;end
          else begin
            k_q<=0;sum_q<=0;product_valid_q<=0;state_q<=PREP;
            if(col_q+1==n_q)begin col_q<=0;row_q<=row_q+1'b1;end else col_q<=col_q+1'b1;
          end
        end
        default:state_q<=IDLE;
      endcase
    end
  end
endmodule

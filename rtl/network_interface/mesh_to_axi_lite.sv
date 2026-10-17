// Parser, AXI executor and response serializer run independently.
module mesh_to_axi_lite #(
  parameter int FIFO_DEPTH=4,QUEUE_DEPTH=4,
  parameter logic [1:0] CURRENT_X=1,CURRENT_Y=1,
  localparam int CREDIT_W=$clog2(FIFO_DEPTH+1)
)(
  input logic clk_i,rst_ni,
  input logic tx_ready_i=1'b1,
  input logic [33:0] rx_flit_i,
  input logic rx_valid_i,rx_vc_i,
  output logic [1:0] rx_credit_o,
  output logic [33:0] tx_flit_o,
  output logic tx_valid_o,tx_vc_o,
  input logic [1:0] tx_credit_i,
  axi_lite_if.master m_axi
);
  import router_pkg::*;
  logic [33:0] flit,head_q,req_head,rsp_head;
  logic [31:0] addr_q,req_addr,req_data,rsp_data;
  logic flit_empty,flit_pop,req_full,req_empty,req_push,req_pop,rsp_full,rsp_empty,rsp_push,rsp_pop;
  logic [97:0] req;
  logic [65:0] rsp,rsp_input;
  logic [1:0] parse_q;
  typedef enum logic[2:0]{IDLE,RA,RD,WA,WB,ERROR_RESP} exec_t;
  exec_t exec_q;
  logic aw_done_q,w_done_q,tx_tail_q,tx_fire;
  logic [CREDIT_W-1:0] credit_q;
  logic [1:0] response;
  logic [33:0] response_head;
  vc_fifo #(.WIDTH(34),.DEPTH(FIFO_DEPTH)) u_rx(
    .clk_i,.rst_ni,.push_i(rx_valid_i&&!rx_vc_i),.data_i(rx_flit_i),
    .pop_i(flit_pop),.data_o(flit),.empty_o(flit_empty),.full_o(),.count_o());
  assign flit_pop=!flit_empty&&(parse_q!=2||!req_full);
  assign req_push=flit_pop&&parse_q==2&&flit[33:32]==FLIT_TAIL;
  vc_fifo #(.WIDTH(98),.DEPTH(QUEUE_DEPTH)) u_requests(
    .clk_i,.rst_ni,.push_i(req_push),.data_i({head_q,addr_q,flit[31:0]}),
    .pop_i(req_pop),.data_o(req),.empty_o(req_empty),.full_o(req_full),.count_o());
  assign {req_head,req_addr,req_data}=req;
  assign req_pop=rsp_push;
  vc_fifo #(.WIDTH(66),.DEPTH(QUEUE_DEPTH)) u_responses(
    .clk_i,.rst_ni,.push_i(rsp_push),.data_i(rsp_input),
    .pop_i(rsp_pop),.data_o(rsp),.empty_o(rsp_empty),.full_o(rsp_full),.count_o());
  assign {rsp_head,rsp_data}=rsp;
  assign m_axi.awaddr=req_addr;
  assign m_axi.awvalid=rst_ni&&exec_q==WA&&!aw_done_q;
  assign m_axi.wdata=req_data;
  assign m_axi.wstrb=req_head[20:17];
  assign m_axi.wvalid=rst_ni&&exec_q==WA&&!w_done_q;
  assign m_axi.bready=exec_q==WB&&!rsp_full;
  assign m_axi.araddr=req_addr;
  assign m_axi.arvalid=rst_ni&&exec_q==RA;
  assign m_axi.rready=exec_q==RD&&!rsp_full;
  assign response=exec_q==ERROR_RESP?2'b11:(exec_q==WB?m_axi.bresp:m_axi.rresp);
  always_comb begin
    response_head=make_head(req_head[27:26],req_head[25:24],CURRENT_X,CURRENT_Y,
      response!=0?NOC_ERROR_RESP:(exec_q==WB?NOC_WRITE_RESP:NOC_READ_RESP),0);
    response_head[16:15]=response;response_head[14:11]=req_head[14:11];
    response_head[2:1]=req_head[2:1];
  end
  assign rsp_input={response_head,exec_q==RD?m_axi.rdata:{30'b0,response}};
  assign rsp_push=(m_axi.rvalid&&m_axi.rready)||(m_axi.bvalid&&m_axi.bready)||
                  (exec_q==ERROR_RESP&&!rsp_full);
  assign tx_vc_o=1;
  assign tx_valid_o=rst_ni&&!rsp_empty&&credit_q!=0;
  assign tx_flit_o=tx_tail_q?{FLIT_TAIL,rsp_data}:rsp_head;
  assign tx_fire=tx_valid_o&&tx_ready_i;
  assign rsp_pop=tx_fire&&tx_tail_q;
  assign rx_credit_o={rx_valid_i&&rx_vc_i,flit_pop};
  always_ff @(posedge clk_i)begin
    if(!rst_ni)begin
      parse_q<=0;head_q<=0;addr_q<=0;exec_q<=IDLE;
      aw_done_q<=0;w_done_q<=0;tx_tail_q<=0;credit_q<=FIFO_DEPTH;
    end else begin
      if(flit_pop)case(parse_q)
        0:if(flit[33:32]==FLIT_HEAD)begin head_q<=flit;parse_q<=1;end
        1:begin addr_q<=flit[31:0];parse_q<=flit[33:32]==FLIT_BODY?2:0;end
        2:parse_q<=0;
        default:parse_q<=0;
      endcase
      case(exec_q)
        IDLE:if(!req_empty)begin
          if(req_head[23:21]==NOC_READ_REQ)exec_q<=RA;
          else if(req_head[23:21]==NOC_WRITE_REQ)exec_q<=WA;
          else exec_q<=ERROR_RESP;
        end
        RA:if(m_axi.arready)exec_q<=RD;
        WA:begin
          if(m_axi.awvalid&&m_axi.awready)aw_done_q<=1;
          if(m_axi.wvalid&&m_axi.wready)w_done_q<=1;
          if((aw_done_q||m_axi.awready)&&(w_done_q||m_axi.wready))exec_q<=WB;
        end
        default:;
      endcase
      if(rsp_push)begin exec_q<=IDLE;aw_done_q<=0;w_done_q<=0;end
      if(tx_fire)tx_tail_q<=!tx_tail_q;
      case({tx_credit_i[1],tx_fire})
        2'b10:credit_q<=credit_q+1'b1;
        2'b01:credit_q<=credit_q-1'b1;
        default:;
      endcase
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk_i)if(rst_ni)assert(credit_q<=FIFO_DEPTH)else $fatal(1,"Endpoint credit overflow");
`endif
endmodule

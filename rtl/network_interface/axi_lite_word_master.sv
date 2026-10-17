// One word command engine shared by DMA and accelerator.
module axi_lite_word_master (
  input logic clk_i,rst_ni,
  input logic cmd_valid_i,cmd_write_i,
  input logic [31:0] cmd_addr_i,cmd_data_i,
  output logic cmd_ready_o,rsp_valid_o,
  input logic rsp_ready_i,
  output logic [31:0] rsp_data_o,
  output logic [1:0] rsp_resp_o,
  axi_lite_if.master m_axi
);
  typedef enum logic [2:0] {IDLE,RA,RD,WA,WB,RESP} state_t;
  state_t state_q;
  logic [31:0] addr_q,data_q;
  logic aw_q,w_q;
  assign cmd_ready_o=state_q==IDLE;
  assign rsp_valid_o=state_q==RESP;
  assign m_axi.araddr=addr_q;
  assign m_axi.arvalid=state_q==RA;
  assign m_axi.rready=state_q==RD;
  assign m_axi.awaddr=addr_q;
  assign m_axi.awvalid=state_q==WA && !aw_q;
  assign m_axi.wdata=data_q;
  assign m_axi.wstrb=4'hf;
  assign m_axi.wvalid=state_q==WA && !w_q;
  assign m_axi.bready=state_q==WB;
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin state_q<=IDLE;addr_q<=0;data_q<=0;aw_q<=0;w_q<=0;rsp_data_o<=0;rsp_resp_o<=0;end
    else case(state_q)
      IDLE: if(cmd_valid_i) begin addr_q<=cmd_addr_i;data_q<=cmd_data_i;state_q<=cmd_write_i?WA:RA;aw_q<=0;w_q<=0;end
      RA: if(m_axi.arready) state_q<=RD;
      RD: if(m_axi.rvalid) begin rsp_data_o<=m_axi.rdata;rsp_resp_o<=m_axi.rresp;state_q<=RESP;end
      WA: begin
        if(m_axi.awready) aw_q<=1;
        if(m_axi.wready) w_q<=1;
        if((aw_q||m_axi.awready)&&(w_q||m_axi.wready)) state_q<=WB;
      end
      WB: if(m_axi.bvalid) begin rsp_data_o<=0;rsp_resp_o<=m_axi.bresp;state_q<=RESP;end
      RESP: if(rsp_ready_i) state_q<=IDLE;
      default: state_q<=IDLE;
    endcase
  end
endmodule

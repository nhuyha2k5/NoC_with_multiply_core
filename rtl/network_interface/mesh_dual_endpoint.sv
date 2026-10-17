// A node may be both MMIO slave (VC0 RX/VC1 TX) and memory master (vice versa).
module mesh_dual_endpoint #(
  parameter logic [1:0] CURRENT_X=0,CURRENT_Y=0
) (
  input logic clk_i,rst_ni,
  input logic [1:0] qos_i=1,
  input logic [33:0] noc_rx_flit_i,
  input logic noc_rx_valid_i,noc_rx_vc_i,
  output logic [1:0] noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o,
  output logic noc_tx_valid_o,noc_tx_vc_o,
  input logic [1:0] noc_tx_credit_i,
  axi_lite_if.master control_axi,
  axi_lite_if.slave memory_axi
);
  logic [33:0] req_flit,resp_flit;
  logic req_valid,resp_valid,unused0,unused1;
  logic [1:0] req_credit,resp_credit;
  axi_lite_to_mesh #(.CURRENT_X(CURRENT_X),.CURRENT_Y(CURRENT_Y)) u_master (
    .clk_i,.rst_ni,.qos_i,.tx_ready_i(!resp_valid),.s_axi(memory_axi),
    .tx_flit_o(req_flit),.tx_valid_o(req_valid),.tx_vc_o(unused0),
    .tx_credit_i({1'b0,noc_tx_credit_i[0]}),.rx_flit_i(noc_rx_flit_i),
    .rx_valid_i(noc_rx_valid_i&&noc_rx_vc_i),.rx_vc_i(1'b1),.rx_credit_o(req_credit)
  );
  mesh_to_axi_lite #(.CURRENT_X(CURRENT_X),.CURRENT_Y(CURRENT_Y)) u_slave (
    .clk_i,.rst_ni,.tx_ready_i(1'b1),.m_axi(control_axi),
    .tx_flit_o(resp_flit),.tx_valid_o(resp_valid),.tx_vc_o(unused1),
    .tx_credit_i({noc_tx_credit_i[1],1'b0}),.rx_flit_i(noc_rx_flit_i),
    .rx_valid_i(noc_rx_valid_i&&!noc_rx_vc_i),.rx_vc_i(1'b0),.rx_credit_o(resp_credit)
  );
  assign noc_tx_valid_o=resp_valid||req_valid;
  assign noc_tx_vc_o=resp_valid;
  assign noc_tx_flit_o=resp_valid?resp_flit:req_flit;
  assign noc_rx_credit_o=req_credit|resp_credit;
endmodule

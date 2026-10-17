module accelerator_node #(parameter logic [1:0] CURRENT_X=0,CURRENT_Y=2)(
  input logic clk_i,rst_ni,
  input logic [1:0] qos_i=1,
  output logic irq_done_o,irq_error_o,
  input logic [33:0] noc_rx_flit_i,
  input logic noc_rx_valid_i,noc_rx_vc_i,
  output logic [1:0] noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o,
  output logic noc_tx_valid_o,noc_tx_vc_o,
  input logic [1:0] noc_tx_credit_i
);
  axi_lite_if control_axi(clk_i,rst_ni),memory_axi(clk_i,rst_ni);
  mesh_dual_endpoint #(.CURRENT_X(CURRENT_X),.CURRENT_Y(CURRENT_Y)) u_endpoint(
    .clk_i,.rst_ni,.qos_i,.noc_rx_flit_i,.noc_rx_valid_i,.noc_rx_vc_i,.noc_rx_credit_o,
    .noc_tx_flit_o,.noc_tx_valid_o,.noc_tx_vc_o,.noc_tx_credit_i,.control_axi,.memory_axi);
  axi_lite_matrix_accelerator u_ip(.clk_i,.rst_ni,.s_axi(control_axi),.m_axi(memory_axi),.irq_done_o,.irq_error_o);
endmodule

module mailbox_node #(
  parameter logic [1:0] CURRENT_X = 2'd2,
  parameter logic [1:0] CURRENT_Y = 2'd1
) (
  input logic clk_i, input logic rst_ni,
  output logic irq_hart0_o, output logic irq_hart1_o,
  input logic [33:0] noc_rx_flit_i, input logic noc_rx_valid_i, input logic noc_rx_vc_i,
  output logic [1:0] noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o, output logic noc_tx_valid_o, output logic noc_tx_vc_o,
  input logic [1:0] noc_tx_credit_i
);
  axi_lite_if endpoint_axi(clk_i, rst_ni);
  mesh_to_axi_lite #(.CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y)) u_endpoint (
    .clk_i, .rst_ni, .rx_flit_i(noc_rx_flit_i), .rx_valid_i(noc_rx_valid_i),
    .rx_vc_i(noc_rx_vc_i), .rx_credit_o(noc_rx_credit_o), .tx_flit_o(noc_tx_flit_o),
    .tx_valid_o(noc_tx_valid_o), .tx_vc_o(noc_tx_vc_o), .tx_credit_i(noc_tx_credit_i),
    .m_axi(endpoint_axi)
  );
  logic [1:0] irq;
  axi_lite_mailbox #(.HARTS(2)) u_mailbox (
    .clk_i, .rst_ni, .irq_o(irq), .s_axi(endpoint_axi)
  );
  assign irq_hart0_o = irq[0];
  assign irq_hart1_o = irq[1];
endmodule

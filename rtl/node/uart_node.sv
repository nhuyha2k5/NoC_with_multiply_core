module uart_node #(
  parameter logic [1:0] CURRENT_X = 2'd0,
  parameter logic [1:0] CURRENT_Y = 2'd1,
  parameter int CLOCK_HZ = 50_000_000,
  parameter int BAUD = 115_200
) (
  input logic clk_i, input logic rst_ni,
  output logic uart_tx_o, output logic uart_irq_o,
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
  axi_lite_uart #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) u_uart (
    .clk_i, .rst_ni, .tx_o(uart_tx_o), .irq_o(uart_irq_o), .s_axi(endpoint_axi)
  );
endmodule

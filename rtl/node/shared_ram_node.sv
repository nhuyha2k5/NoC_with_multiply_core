// Shared-memory node at mesh coordinate (1,1).
module shared_ram_node #(
  parameter int WORDS = 16384,
  parameter string INIT_FILE = ""
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [33:0] noc_rx_flit_i,
  input  logic        noc_rx_valid_i,
  input  logic        noc_rx_vc_i,
  output logic [1:0]  noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o,
  output logic        noc_tx_valid_o,
  output logic        noc_tx_vc_o,
  input  logic [1:0]  noc_tx_credit_i
);
  axi4_if ram_axi(clk_i, rst_ni);

  mesh_to_axi4 #(.CURRENT_X(1), .CURRENT_Y(1)) u_endpoint (
    .clk_i,
    .rst_ni,
    .rx_flit_i(noc_rx_flit_i),
    .rx_valid_i(noc_rx_valid_i),
    .rx_vc_i(noc_rx_vc_i),
    .rx_credit_o(noc_rx_credit_o),
    .tx_flit_o(noc_tx_flit_o),
    .tx_valid_o(noc_tx_valid_o),
    .tx_vc_o(noc_tx_vc_o),
    .tx_credit_i(noc_tx_credit_i),
    .m_axi(ram_axi)
  );

  axi4_banked_ram #(.WORDS(WORDS), .INIT_FILE(INIT_FILE)) u_ram (
    .clk_i,
    .rst_ni,
    .s_axi(ram_axi)
  );
endmodule

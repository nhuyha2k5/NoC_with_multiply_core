// Fmax harness for the NoC alone: mesh_3x3_vc with every local port and the
// QoS configuration registered, so all timed paths are register to register
// (as in the SoC, where NIs and noc_control drive the mesh from registers).
// Router counters stay live outputs so their logic is not optimised away.
module noc_fmax_wrap (
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic [33:0]  tx_flit_i [0:8],
  input  logic         tx_valid_i[0:8],
  input  logic         tx_vc_i   [0:8],
  output logic [1:0]   tx_credit_o[0:8],
  output logic [33:0]  rx_flit_o [0:8],
  output logic         rx_valid_o[0:8],
  output logic         rx_vc_o   [0:8],
  input  logic [1:0]   rx_credit_i[0:8],
  input  logic [1:0]   qos_mode_i,
  input  logic         qos_classes_i,
  input  logic         qos_aging_i,
  input  logic [3:0]   qos_age_i,
  input  logic [7:0]   qos_weights_i,
  input  logic         counters_enable_i,
  input  logic         counters_clear_i,
  output logic [1439:0] flit_count_o,
  output logic [1439:0] packet_count_o,
  output logic [1439:0] stall_count_o,
  output logic [359:0]  fifo_peak_o
);
  logic [33:0] tx_flit_q[0:8], rx_flit_d[0:8];
  logic        tx_valid_q[0:8], tx_vc_q[0:8], rx_valid_d[0:8], rx_vc_d[0:8];
  logic [1:0]  tx_credit_d[0:8], rx_credit_q[0:8];
  logic [1:0]  qos_mode_q;
  logic        qos_classes_q, qos_aging_q, counters_enable_q, counters_clear_q;
  logic [3:0]  qos_age_q;
  logic [7:0]  qos_weights_q;
  logic        rst_q;

  always_ff @(posedge clk_i) begin
    rst_q <= rst_ni;
    qos_mode_q <= qos_mode_i;
    qos_classes_q <= qos_classes_i;
    qos_aging_q <= qos_aging_i;
    qos_age_q <= qos_age_i;
    qos_weights_q <= qos_weights_i;
    counters_enable_q <= counters_enable_i;
    counters_clear_q <= counters_clear_i;
    for (int n = 0; n < 9; n++) begin
      tx_flit_q[n]   <= tx_flit_i[n];
      tx_valid_q[n]  <= tx_valid_i[n];
      tx_vc_q[n]     <= tx_vc_i[n];
      rx_credit_q[n] <= rx_credit_i[n];
      tx_credit_o[n] <= tx_credit_d[n];
      rx_flit_o[n]   <= rx_flit_d[n];
      rx_valid_o[n]  <= rx_valid_d[n];
      rx_vc_o[n]     <= rx_vc_d[n];
    end
  end

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni(rst_q),
    .qos_mode_i(qos_mode_q), .qos_classes_i(qos_classes_q), .qos_aging_i(qos_aging_q),
    .qos_age_i(qos_age_q), .qos_weights_i(qos_weights_q),
    .counters_enable_i(counters_enable_q), .counters_clear_i(counters_clear_q),
    .flit_count_o, .packet_count_o, .stall_count_o, .fifo_peak_o,
    .local_tx_flit_i(tx_flit_q), .local_tx_valid_i(tx_valid_q),
    .local_tx_vc_i(tx_vc_q), .local_tx_credit_o(tx_credit_d),
    .local_rx_flit_o(rx_flit_d), .local_rx_valid_o(rx_valid_d),
    .local_rx_vc_o(rx_vc_d), .local_rx_credit_i(rx_credit_q)
  );
endmodule

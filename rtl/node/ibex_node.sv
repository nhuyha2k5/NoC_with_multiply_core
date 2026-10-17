// Complete compute node: one Ibex core, local boot ROM and AXI/NoC NI.
module ibex_node #(
  parameter logic [1:0] CURRENT_X = 2'd0,
  parameter logic [1:0] CURRENT_Y = 2'd0,
  parameter logic [31:0] HART_ID = 32'd0,
  parameter string ROM_INIT_FILE = ""
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [1:0]  qos_i=2,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  input  logic        irq_software_i = 1'b0,
  coherence_if.cache  coherence,
  output logic [31:0] debug_pc_o,
  output logic [31:0] cache_hit_count_o,
  output logic [31:0] cache_miss_count_o,
  output logic [33:0] noc_tx_flit_o,
  output logic        noc_tx_valid_o,
  output logic        noc_tx_vc_o,
  input  logic [1:0]  noc_tx_credit_i,
  input  logic [33:0] noc_rx_flit_i,
  input  logic        noc_rx_valid_i,
  input  logic        noc_rx_vc_i,
  output logic [1:0]  noc_rx_credit_o
);
  ibex_axi_tile #(
    .CURRENT_X(CURRENT_X),
    .CURRENT_Y(CURRENT_Y),
    .HART_ID(HART_ID),
    .ROM_INIT_FILE(ROM_INIT_FILE)
  ) u_tile (
    .clk_i,
    .rst_ni,
    .qos_i,
    .irq_timer_i,
    .irq_external_i,
    .irq_software_i,
    .coherence,
    .debug_pc_o,
    .cache_hit_count_o,
    .cache_miss_count_o,
    .noc_tx_flit_o,
    .noc_tx_valid_o,
    .noc_tx_vc_o,
    .noc_tx_credit_i,
    .noc_rx_flit_i,
    .noc_rx_valid_i,
    .noc_rx_vc_i,
    .noc_rx_credit_o
  );
endmodule

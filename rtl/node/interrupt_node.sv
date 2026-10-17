// PLIC + timer (CLINT or legacy) + NoC control behind one mesh endpoint.
module interrupt_node #(
  parameter int HARTS=2,
  parameter int SOURCES=8,
  parameter bit LEGACY_TIMER=1'b1,
  parameter logic [1:0] CURRENT_X=1,CURRENT_Y=2
)(
  input logic clk_i,rst_ni,
  input logic [SOURCES:1] sources_i,
  output logic [HARTS-1:0] external_irq_o,timer_irq_o,software_irq_o,
  input logic[1439:0] flits_i='0,packets_i='0,stalls_i='0,
  input logic[359:0] peaks_i='0,
  output logic[1:0] qos_mode_o,output logic qos_classes_o,qos_aging_o,
  output logic[3:0] qos_age_o,output logic[7:0] qos_weights_o,source_classes_o,dma_gap_o,
  output logic counters_enable_o,counters_clear_o,
  input logic [33:0] noc_rx_flit_i,
  input logic noc_rx_valid_i,noc_rx_vc_i,
  output logic [1:0] noc_rx_credit_o,
  output logic [33:0] noc_tx_flit_o,
  output logic noc_tx_valid_o,noc_tx_vc_o,
  input logic [1:0] noc_tx_credit_i
);
  axi_lite_if control_axi(clk_i,rst_ni);
  mesh_to_axi_lite #(.CURRENT_X(CURRENT_X),.CURRENT_Y(CURRENT_Y)) u_endpoint(
    .clk_i,.rst_ni,.m_axi(control_axi),.rx_flit_i(noc_rx_flit_i),.rx_valid_i(noc_rx_valid_i),
    .rx_vc_i(noc_rx_vc_i),.rx_credit_o(noc_rx_credit_o),.tx_flit_o(noc_tx_flit_o),
    .tx_valid_o(noc_tx_valid_o),.tx_vc_o(noc_tx_vc_o),.tx_credit_i(noc_tx_credit_i));
  axi_lite_interrupts #(.HARTS(HARTS),.SOURCES(SOURCES),.LEGACY_TIMER(LEGACY_TIMER)) u_ip(
    .clk_i,.rst_ni,.sources_i,.external_irq_o,.timer_irq_o,
    .software_irq_o,.s_axi(control_axi),.flits_i,.packets_i,.stalls_i,.peaks_i,
    .qos_mode_o,.qos_classes_o,.qos_aging_o,.qos_age_o,.qos_weights_o,.source_classes_o,.dma_gap_o,
    .counters_enable_o,.counters_clear_o);
endmodule

// Four-Ibex coherent SoC on a fixed 3x3 VC mesh.
//
// Node map (index = x*3+y):
//   (0,0) Ibex 0      (0,1) peripherals: UART, GPIO, mailbox, test-and-set
//   (0,2) Ibex 1      (1,0) DMA
//   (1,1) shared RAM 128 KB
//   (1,2) PLIC (4 contexts, 16 sources) + CLINT + NoC control
//   (2,0) Ibex 2      (2,1) matrix accelerator   (2,2) Ibex 3
// Every CPU sits at a corner, two hops from the RAM node.
//
// PLIC sources: 1 UART, 2/3 mailbox->hart0/1, 4/5 DMA done/error,
// 6/7 accelerator done/error, 8 GPIO, 9/10 mailbox->hart2/3, 11-16 unused.
// QoS source classes (NoC control SOURCE_CLASSES): [1:0] harts 0 and 2,
// [3:2] harts 1 and 3, [5:4] DMA, [7:6] accelerator.
module ibex_mesh_soc #(
  parameter string ROM0_INIT_FILE = "",
  parameter string ROM1_INIT_FILE = "",
  parameter string ROM2_INIT_FILE = "",
  parameter string ROM3_INIT_FILE = "",
  parameter int CLOCK_HZ = 50_000_000,
  parameter int UART_BAUD = 115_200,
  parameter int RAM_WORDS = 32768
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [7:0]  gpio_i,
  output logic [7:0]  gpio_o,
  output logic [7:0]  gpio_oe_o,
  output logic        uart_tx_o,
  output logic [31:0] debug_pc0_o,
  output logic [31:0] debug_pc1_o,
  output logic [31:0] debug_pc2_o,
  output logic [31:0] debug_pc3_o,
  output logic [31:0] cache0_hits_o,
  output logic [31:0] cache0_misses_o,
  output logic [31:0] cache1_hits_o,
  output logic [31:0] cache1_misses_o,
  output logic [31:0] cache2_hits_o,
  output logic [31:0] cache2_misses_o,
  output logic [31:0] cache3_hits_o,
  output logic [31:0] cache3_misses_o
);
  localparam int HARTS = 4;
  localparam int SOURCES = 16;

  function automatic int cpu_node(input int h);
    case (h)
      0: return 0;
      1: return 2;
      2: return 6;
      default: return 8;
    endcase
  endfunction

  logic [33:0] node_tx_flit[0:8], node_rx_flit[0:8];
  logic        node_tx_valid[0:8], node_tx_vc[0:8];
  logic        node_rx_valid[0:8], node_rx_vc[0:8];
  logic [1:0]  node_tx_credit[0:8], node_rx_credit[0:8];

  logic uart_irq, gpio_irq;
  logic [HARTS-1:0] mailbox_irq, timer_irq, external_irq, software_irq;
  logic dma_done_irq, dma_error_irq, acc_done_irq, acc_error_irq;
  logic [SOURCES:1] irq_sources;
  logic [1:0] qos_mode; logic qos_classes, qos_aging;
  logic [3:0] qos_age; logic [7:0] qos_weights, source_classes, dma_gap;
  logic counters_enable, counters_clear;
  logic [1439:0] router_flits, router_packets, router_stalls;
  logic [359:0] router_peaks;
  logic [31:0] debug_pc[HARTS], cache_hits[HARTS], cache_misses[HARTS];

  assign irq_sources = {6'b0, mailbox_irq[3], mailbox_irq[2], gpio_irq, acc_error_irq, acc_done_irq,
                        dma_error_irq, dma_done_irq, mailbox_irq[1], mailbox_irq[0], uart_irq};

  mesh_3x3_vc u_mesh (
    .clk_i, .rst_ni,
    .qos_mode_i(qos_mode), .qos_classes_i(qos_classes), .qos_aging_i(qos_aging), .qos_age_i(qos_age),
    .qos_weights_i(qos_weights),
    .counters_enable_i(counters_enable), .counters_clear_i(counters_clear),
    .flit_count_o(router_flits), .packet_count_o(router_packets), .stall_count_o(router_stalls),
    .fifo_peak_o(router_peaks),
    .local_tx_flit_i(node_tx_flit), .local_tx_valid_i(node_tx_valid),
    .local_tx_vc_i(node_tx_vc), .local_tx_credit_o(node_tx_credit),
    .local_rx_flit_o(node_rx_flit), .local_rx_valid_o(node_rx_valid),
    .local_rx_vc_o(node_rx_vc), .local_rx_credit_i(node_rx_credit)
  );

  // ------------------------------------------------------------- CPUs + MESI
  coherence_if coh[HARTS](clk_i, rst_ni);
  logic [HARTS-1:0]       coh_req_valid, coh_complete, coh_grant, coh_snoop_valid;
  logic [HARTS-1:0]       coh_snoop_ack, coh_snoop_hit, coh_snoop_err;
  logic [HARTS-1:0][1:0]  coh_req_cmd;
  logic [HARTS-1:0][31:0] coh_req_addr;
  logic                   coh_grant_shared, coh_grant_err, coh_snoop_cmd;
  logic [31:0]            coh_snoop_addr;

  for (genvar h = 0; h < HARTS; h++) begin : g_cpu
    localparam int NODE = cpu_node(h);
    localparam string ROM = (h == 0) ? ROM0_INIT_FILE : (h == 1) ? ROM1_INIT_FILE :
                            (h == 2) ? ROM2_INIT_FILE : ROM3_INIT_FILE;
    ibex_node #(
      .CURRENT_X(2'(NODE / 3)), .CURRENT_Y(2'(NODE % 3)), .HART_ID(32'(h)), .ROM_INIT_FILE(ROM)
    ) u_cpu (
      .qos_i(source_classes[2*(h%2) +: 2]),
      .clk_i, .rst_ni, .irq_timer_i(timer_irq[h]), .irq_software_i(software_irq[h]),
      .irq_external_i(external_irq[h]), .coherence(coh[h]),
      .debug_pc_o(debug_pc[h]), .cache_hit_count_o(cache_hits[h]),
      .cache_miss_count_o(cache_misses[h]),
      .noc_tx_flit_o(node_tx_flit[NODE]), .noc_tx_valid_o(node_tx_valid[NODE]),
      .noc_tx_vc_o(node_tx_vc[NODE]), .noc_tx_credit_i(node_tx_credit[NODE]),
      .noc_rx_flit_i(node_rx_flit[NODE]), .noc_rx_valid_i(node_rx_valid[NODE]),
      .noc_rx_vc_i(node_rx_vc[NODE]), .noc_rx_credit_o(node_rx_credit[NODE])
    );
    assign coh_req_valid[h] = coh[h].req_valid;
    assign coh_req_cmd[h]   = coh[h].req_cmd;
    assign coh_req_addr[h]  = coh[h].req_addr;
    assign coh_complete[h]  = coh[h].complete;
    assign coh_snoop_ack[h] = coh[h].snoop_ack;
    assign coh_snoop_hit[h] = coh[h].snoop_hit;
    assign coh_snoop_err[h] = coh[h].snoop_err;
    assign coh[h].grant        = coh_grant[h];
    assign coh[h].grant_shared = coh_grant_shared;
    assign coh[h].grant_err    = coh_grant_err;
    assign coh[h].snoop_valid  = coh_snoop_valid[h];
    assign coh[h].snoop_cmd    = coh_snoop_cmd;
    assign coh[h].snoop_addr   = coh_snoop_addr;
  end

  coherence_manager #(.N_CORES(HARTS)) u_coherence_manager (
    .clk_i, .rst_ni,
    .req_valid_i(coh_req_valid), .req_cmd_i(coh_req_cmd), .req_addr_i(coh_req_addr),
    .complete_i(coh_complete),
    .grant_o(coh_grant), .grant_shared_o(coh_grant_shared), .grant_err_o(coh_grant_err),
    .snoop_valid_o(coh_snoop_valid), .snoop_cmd_o(coh_snoop_cmd), .snoop_addr_o(coh_snoop_addr),
    .snoop_ack_i(coh_snoop_ack), .snoop_hit_i(coh_snoop_hit), .snoop_err_i(coh_snoop_err)
  );

  assign debug_pc0_o = debug_pc[0];
  assign debug_pc1_o = debug_pc[1];
  assign debug_pc2_o = debug_pc[2];
  assign debug_pc3_o = debug_pc[3];
  assign cache0_hits_o = cache_hits[0];
  assign cache1_hits_o = cache_hits[1];
  assign cache2_hits_o = cache_hits[2];
  assign cache3_hits_o = cache_hits[3];
  assign cache0_misses_o = cache_misses[0];
  assign cache1_misses_o = cache_misses[1];
  assign cache2_misses_o = cache_misses[2];
  assign cache3_misses_o = cache_misses[3];

  // ------------------------------------------------------------- other nodes
  peripheral_node #(
    .CURRENT_X(0), .CURRENT_Y(1), .CLOCK_HZ(CLOCK_HZ), .BAUD(UART_BAUD), .GPIO_WIDTH(8), .HARTS(HARTS)
  ) u_peripheral_node (
    .clk_i, .rst_ni, .uart_tx_o, .uart_irq_o(uart_irq),
    .gpio_i, .gpio_o, .gpio_oe_o, .gpio_irq_o(gpio_irq), .mailbox_irq_o(mailbox_irq),
    .noc_rx_flit_i(node_rx_flit[1]), .noc_rx_valid_i(node_rx_valid[1]),
    .noc_rx_vc_i(node_rx_vc[1]), .noc_rx_credit_o(node_rx_credit[1]),
    .noc_tx_flit_o(node_tx_flit[1]), .noc_tx_valid_o(node_tx_valid[1]),
    .noc_tx_vc_o(node_tx_vc[1]), .noc_tx_credit_i(node_tx_credit[1])
  );

  dma_node #(.CURRENT_X(1), .CURRENT_Y(0)) u_dma (
    .clk_i, .rst_ni, .qos_i(source_classes[5:4]), .issue_gap_i(dma_gap),
    .irq_done_o(dma_done_irq), .irq_error_o(dma_error_irq),
    .noc_rx_flit_i(node_rx_flit[3]), .noc_rx_valid_i(node_rx_valid[3]), .noc_rx_vc_i(node_rx_vc[3]),
    .noc_rx_credit_o(node_rx_credit[3]), .noc_tx_flit_o(node_tx_flit[3]),
    .noc_tx_valid_o(node_tx_valid[3]), .noc_tx_vc_o(node_tx_vc[3]), .noc_tx_credit_i(node_tx_credit[3])
  );

  shared_ram_node #(.WORDS(RAM_WORDS)) u_ram_node (
    .clk_i, .rst_ni,
    .noc_rx_flit_i(node_rx_flit[4]), .noc_rx_valid_i(node_rx_valid[4]),
    .noc_rx_vc_i(node_rx_vc[4]), .noc_rx_credit_o(node_rx_credit[4]),
    .noc_tx_flit_o(node_tx_flit[4]), .noc_tx_valid_o(node_tx_valid[4]),
    .noc_tx_vc_o(node_tx_vc[4]), .noc_tx_credit_i(node_tx_credit[4])
  );

  interrupt_node #(
    .HARTS(HARTS), .SOURCES(SOURCES), .LEGACY_TIMER(1'b0), .CURRENT_X(1), .CURRENT_Y(2)
  ) u_interrupt_node (
    .clk_i, .rst_ni, .sources_i(irq_sources), .timer_irq_o(timer_irq),
    .external_irq_o(external_irq), .software_irq_o(software_irq),
    .flits_i(router_flits), .packets_i(router_packets), .stalls_i(router_stalls), .peaks_i(router_peaks),
    .qos_mode_o(qos_mode), .qos_classes_o(qos_classes), .qos_aging_o(qos_aging), .qos_age_o(qos_age),
    .qos_weights_o(qos_weights), .source_classes_o(source_classes), .dma_gap_o(dma_gap),
    .counters_enable_o(counters_enable), .counters_clear_o(counters_clear),
    .noc_rx_flit_i(node_rx_flit[5]), .noc_rx_valid_i(node_rx_valid[5]),
    .noc_rx_vc_i(node_rx_vc[5]), .noc_rx_credit_o(node_rx_credit[5]),
    .noc_tx_flit_o(node_tx_flit[5]), .noc_tx_valid_o(node_tx_valid[5]),
    .noc_tx_vc_o(node_tx_vc[5]), .noc_tx_credit_i(node_tx_credit[5])
  );

  accelerator_node #(.CURRENT_X(2), .CURRENT_Y(1)) u_accelerator (
    .clk_i, .rst_ni, .qos_i(source_classes[7:6]),
    .irq_done_o(acc_done_irq), .irq_error_o(acc_error_irq),
    .noc_rx_flit_i(node_rx_flit[7]), .noc_rx_valid_i(node_rx_valid[7]), .noc_rx_vc_i(node_rx_vc[7]),
    .noc_rx_credit_o(node_rx_credit[7]), .noc_tx_flit_o(node_tx_flit[7]),
    .noc_tx_valid_o(node_tx_valid[7]), .noc_tx_vc_o(node_tx_vc[7]), .noc_tx_credit_i(node_tx_credit[7])
  );
endmodule

// Ibex RV32IMC tile with local instruction ROM and AXI data/NoC path.
module ibex_axi_tile #(
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
  logic instr_req, instr_gnt, instr_rvalid, instr_err;
  logic [31:0] instr_addr, instr_rdata;
  logic data_req, data_gnt, data_rvalid, data_we, data_err;
  logic [3:0] data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;
  logic rom_gnt,rom_rvalid,rom_err,cache_gnt,cache_rvalid,cache_err;
  logic [31:0] rom_rdata,cache_rdata;
  logic data_is_rom;

  axi_lite_if instr_axi(clk_i, rst_ni);
  axi_lite_if rom_data_axi(clk_i,rst_ni);
  axi_lite_if data_cpu_axi(clk_i, rst_ni);
  axi_lite_if data_noc_axi(clk_i, rst_ni);

  assign debug_pc_o = instr_addr;

  ibex_top #(
    .RV32M(ibex_pkg::RV32MFast),
    .RV32B(ibex_pkg::RV32BNone),
    .RV32ZC(ibex_pkg::RV32Zca),
    .RegFile(ibex_pkg::RegFileFPGA),
    .BranchTargetALU(1'b1),
    .WritebackStage(1'b1),
    .BranchPredictor(1'b1),
    // Instructions come from a private low-latency ROM. The coherent cache is
    // therefore placed only on the shared data path.
    .ICache(1'b0),
    .SecureIbex(1'b0)
  ) u_ibex (
    .clk_i, .rst_ni,
    .test_en_i(1'b0), .scan_rst_ni(1'b1),
    .ram_cfg_icache_tag_i(prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
    .ram_cfg_rsp_icache_tag_o(),
    .ram_cfg_icache_data_i(prim_ram_1p_pkg::RAM_1P_CFG_DEFAULT),
    .ram_cfg_rsp_icache_data_o(),
    .hart_id_i(HART_ID), .boot_addr_i(32'h0000_0000),
    .instr_req_o(instr_req), .instr_gnt_i(instr_gnt),
    .instr_rvalid_i(instr_rvalid), .instr_addr_o(instr_addr),
    .instr_rdata_i(instr_rdata), .instr_rdata_intg_i('0), .instr_err_i(instr_err),
    .data_req_o(data_req), .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid),
    .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
    .data_wdata_o(data_wdata), .data_wdata_intg_o(),
    .data_rdata_i(data_rdata), .data_rdata_intg_i('0), .data_err_i(data_err),
    .irq_software_i, .irq_timer_i, .irq_external_i,
    .irq_fast_i('0), .irq_nm_i(1'b0),
    .scramble_key_valid_i(1'b0), .scramble_key_i('0), .scramble_nonce_i('0),
    .scramble_req_o(), .debug_req_i(1'b0), .crash_dump_o(), .double_fault_seen_o(),
    .fetch_enable_i(ibex_pkg::IbexMuBiOn),
    .mcounteren_writable_i(ibex_pkg::IbexMuBiOn),
    .alert_minor_o(), .alert_major_internal_o(), .alert_major_bus_o(), .core_sleep_o(),
    .lockstep_cmp_en_o(),
    .data_req_shadow_o(), .data_we_shadow_o(), .data_be_shadow_o(),
    .data_addr_shadow_o(), .data_wdata_shadow_o(), .data_wdata_intg_shadow_o(),
    .instr_req_shadow_o(), .instr_addr_shadow_o()
  );

  ibex_to_axi_lite u_instr_bridge (
    .clk_i, .rst_ni, .req_i(instr_req), .we_i(1'b0), .be_i(4'b0),
    .addr_i(instr_addr), .wdata_i(32'b0), .gnt_o(instr_gnt),
    .rvalid_o(instr_rvalid), .rdata_o(instr_rdata), .err_o(instr_err),
    .m_axi(instr_axi)
  );

  boot_rom_dual #(.WORDS(4096), .INIT_FILE(ROM_INIT_FILE)) u_boot_rom (
    .clk_i, .rst_ni, .instr(instr_axi),.data(rom_data_axi)
  );
  assign data_is_rom=data_addr<32'h4000;
  assign data_gnt=rom_gnt|cache_gnt;
  assign data_rvalid=rom_rvalid|cache_rvalid;
  assign data_err=(rom_rvalid&&rom_err)||(cache_rvalid&&cache_err);
  assign data_rdata=rom_rvalid?rom_rdata:cache_rdata;
  ibex_to_axi_lite u_rom_data_bridge(
    .clk_i,.rst_ni,.req_i(data_req&&data_is_rom),.we_i(data_we),.be_i(data_be),
    .addr_i(data_addr),.wdata_i(data_wdata),.gnt_o(rom_gnt),.rvalid_o(rom_rvalid),
    .rdata_o(rom_rdata),.err_o(rom_err),.m_axi(rom_data_axi));

  ibex_to_axi_lite u_data_bridge (
    .clk_i, .rst_ni, .req_i(data_req&&!data_is_rom), .we_i(data_we), .be_i(data_be),
    .addr_i(data_addr), .wdata_i(data_wdata), .gnt_o(cache_gnt),
    .rvalid_o(cache_rvalid), .rdata_o(cache_rdata), .err_o(cache_err),
    .m_axi(data_cpu_axi)
  );

  mesi_dcache #(.LINES(128)) u_dcache (
    .clk_i,
    .rst_ni,
    .s_axi(data_cpu_axi),
    .m_axi(data_noc_axi),
    .coh(coherence),
    .hit_count_o(cache_hit_count_o),
    .miss_count_o(cache_miss_count_o),
    .writeback_count_o(),
    .invalidate_count_o()
  );

  axi_lite_to_mesh #(.CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y)) u_noc_master (
    .clk_i, .rst_ni, .qos_i, .s_axi(data_noc_axi),
    .tx_flit_o(noc_tx_flit_o), .tx_valid_o(noc_tx_valid_o), .tx_vc_o(noc_tx_vc_o),
    .tx_credit_i(noc_tx_credit_i),
    .rx_flit_i(noc_rx_flit_i), .rx_valid_i(noc_rx_valid_i), .rx_vc_i(noc_rx_vc_i),
    .rx_credit_o(noc_rx_credit_o)
  );
endmodule

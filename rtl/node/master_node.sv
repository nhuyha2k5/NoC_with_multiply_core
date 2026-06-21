`timescale 1ns/1ps

module master_node #(
    parameter DATA_WIDTH = 34,
    parameter CURRENT_X  = 2'd0,
    parameter CURRENT_Y  = 2'd0,
    parameter PRIORITY   = 1'b0,
    parameter ROM_FILE   = ""  // ĐƯỜNG DẪN FILE .HEX NẠP VÀO ĐÂY
)(
    input  wire clk,
    input  wire rst_n,
    
    // ==========================================
    // CHIÊU TRÒ ÉP QUARTUS GIỮ LẠI CPU
    // ==========================================
    output wire [31:0] debug_pc,
    output wire [31:0] debug_alu,

    // ==========================================
    // 4 CỔNG GIAO TIẾP MẠNG (ROUTER)
    // ==========================================
    input  wire [DATA_WIDTH-1:0] n_flit_in, input wire n_valid_in, output wire n_credit_out,
    output wire [DATA_WIDTH-1:0] n_flit_out, output wire n_valid_out, input wire n_credit_in,

    input  wire [DATA_WIDTH-1:0] s_flit_in, input wire s_valid_in, output wire s_credit_out,
    output wire [DATA_WIDTH-1:0] s_flit_out, output wire s_valid_out, input wire s_credit_in,

    input  wire [DATA_WIDTH-1:0] e_flit_in, input wire e_valid_in, output wire e_credit_out,
    output wire [DATA_WIDTH-1:0] e_flit_out, output wire e_valid_out, input wire e_credit_in,

    input  wire [DATA_WIDTH-1:0] w_flit_in, input wire w_valid_in, output wire w_credit_out,
    output wire [DATA_WIDTH-1:0] w_flit_out, output wire w_valid_out, input wire w_credit_in
);

    // Dây tín hiệu chung của CPU
    wire [31:0] instr_addr, instr_rdata;
    wire        data_req, data_we;
    wire [31:0] data_addr, data_wdata, data_rdata;
    wire        stall_cpu;
    wire [2:0]  store_sel, load_sel;

    // Gán tín hiệu ra chân Debug để Quartus không dám cắt CPU
    assign debug_pc  = instr_addr;
    assign debug_alu = data_addr;

    // ---------------------------------------------------------
    // 1. CPU RISC-V TỰ CHẾ
    // ---------------------------------------------------------
    Top_module_riscV_noc u_cpu (
        .clk(clk), .rst_n(rst_n), .start(1'b1),
        .DataOrReg(1'b0), .check_address(32'd0), .value(),
        
        // Cổng lấy lệnh
        .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata),
        
        // Cổng truy cập dữ liệu
        .mem_req_o(data_req), .mem_we_o(data_we),
        .mem_store_sel_o(store_sel), .mem_load_sel_o(load_sel),
        .mem_addr_o(data_addr), .mem_wdata_o(data_wdata),
        .mem_rdata_i(data_rdata), .stall_external(stall_cpu)
    );

    // ---------------------------------------------------------
    // 2. BRIDGE CPU -> OBI
    // ---------------------------------------------------------
    wire        noc_req, noc_gnt, noc_rvalid, noc_we;
    wire [3:0]  noc_be;
    wire [31:0] noc_addr, noc_wdata, noc_rdata;
    
    wire        local_req, local_gnt, local_rvalid, local_we;
    wire [3:0]  local_be;
    wire [31:0] local_addr, local_wdata, local_rdata;

    cpu_obi_bridge u_bridge (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(data_req), .cpu_we(data_we), .cpu_addr(data_addr), .cpu_wdata(data_wdata),
        .cpu_store_sel(store_sel), .cpu_stall(stall_cpu), .cpu_rdata(data_rdata),
        
        // Nhánh xuất ra Mạng NoC
        .noc_req(noc_req), .noc_gnt(noc_gnt), .noc_we(noc_we), .noc_be(noc_be), 
        .noc_addr(noc_addr), .noc_wdata(noc_wdata), .noc_rvalid(noc_rvalid), .noc_rdata(noc_rdata),
        
        // Nhánh xuất ra RAM cục bộ
        .local_req(local_req), .local_gnt(local_gnt), .local_we(local_we), .local_be(local_be), 
        .local_addr(local_addr), .local_wdata(local_wdata), .local_rvalid(local_rvalid), .local_rdata(local_rdata)
    );

    // ---------------------------------------------------------
    // 3. TRUE DUAL-PORT RAM (Lệnh + Dữ liệu cục bộ)
    // ---------------------------------------------------------
    ram_obi #(
        .MEM_SIZE_BYTES(4096),
        .INIT_FILE(ROM_FILE)  // NHẬN FILE MÃ LỆNH TỪ PARAMETER
    ) u_local_data_ram (
        .clk(clk), .rst_n(rst_n),
        
        // PORT A: Phục vụ đọc lệnh cho CPU
        .req_a_i(1'b1),           // CPU luôn fetch lệnh
        .gnt_a_o(),               // Không cần chặn CPU
        .we_a_i(1'b0),            // Chỉ đọc
        .be_a_i(4'b1111),         // Đọc nguyên Word (32 bit)
        .addr_a_i(instr_addr),    // Nối với PC
        .wdata_a_i(32'd0),
        .rvalid_a_o(),
        .rdata_a_o(instr_rdata),  // Trả mã lệnh về CPU

        // PORT B: Phục vụ đọc/ghi dữ liệu từ Bridge
        .req_b_i(local_req), .gnt_b_o(local_gnt), .we_b_i(local_we), .be_b_i(local_be),
        .addr_b_i(local_addr), .wdata_b_i(local_wdata), .rvalid_b_o(local_rvalid), .rdata_b_o(local_rdata)
    );

    // ---------------------------------------------------------
    // 4. MASTER NETWORK INTERFACE (Giao tiếp mạng)
    // ---------------------------------------------------------
    wire [DATA_WIDTH-1:0] l_flit_tx, l_flit_rx;
    wire l_valid_tx, l_valid_rx, l_credit_tx, l_credit_rx;

    master_ni #(
        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y), .PRIORITY(PRIORITY)
    ) u_master_ni (
        .clk(clk), .rst_n(rst_n),
        .obi_req(noc_req), .obi_gnt(noc_gnt), .obi_we(noc_we), .obi_be(noc_be),
        .obi_addr(noc_addr), .obi_wdata(noc_wdata), .obi_rvalid(noc_rvalid), .obi_rdata(noc_rdata),
        .tx_flit(l_flit_tx), .tx_valid(l_valid_tx), .tx_credit(l_credit_tx),
        .rx_flit(l_flit_rx), .rx_valid(l_valid_rx), .rx_credit(l_credit_rx)
    );

    // ---------------------------------------------------------
    // 5. ROUTER NODE
    // ---------------------------------------------------------
    router_top #(
        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y)
    ) u_router (
        .clk(clk), .rst_n(rst_n),
        
        // Cổng Local (Nối vào NI)
        .l_flit_in(l_flit_tx), .l_valid_in(l_valid_tx), .l_credit_out(l_credit_tx),
        .l_flit_out(l_flit_rx), .l_valid_out(l_valid_rx), .l_credit_in(l_credit_rx),
        
        // 4 Cổng lân cận (Nối ra chân chip)
        .n_flit_in(n_flit_in), .n_valid_in(n_valid_in), .n_credit_out(n_credit_out),
        .n_flit_out(n_flit_out), .n_valid_out(n_valid_out), .n_credit_in(n_credit_in),
        
        .s_flit_in(s_flit_in), .s_valid_in(s_valid_in), .s_credit_out(s_credit_out),
        .s_flit_out(s_flit_out), .s_valid_out(s_valid_out), .s_credit_in(s_credit_in),
        
        .e_flit_in(e_flit_in), .e_valid_in(e_valid_in), .e_credit_out(e_credit_out),
        .e_flit_out(e_flit_out), .e_valid_out(e_valid_out), .e_credit_in(e_credit_in),
        
        .w_flit_in(w_flit_in), .w_valid_in(w_valid_in), .w_credit_out(w_credit_out),
        .w_flit_out(w_flit_out), .w_valid_out(w_valid_out), .w_credit_in(w_credit_in)
    );

endmodule
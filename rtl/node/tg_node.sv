`timescale 1ns/1ps
module tg_node #(
    parameter DATA_WIDTH = 34,
    parameter CURRENT_X  = 2'd0,
    parameter CURRENT_Y  = 2'd0,
    parameter PRIORITY   = 1'b0,
    parameter DEST_X     = 2'd2,
    parameter DEST_Y     = 2'd2,
    parameter LOAD_FACTOR = 10,
    parameter WRITE_PROB = 50
)(
    input  logic clk,
    input  logic rst_n,
    // Cổng mạng N/S/E/W
    input  logic [DATA_WIDTH-1:0] n_flit_in, input logic n_valid_in, output logic n_credit_out,
    output logic [DATA_WIDTH-1:0] n_flit_out, output logic n_valid_out, input logic n_credit_in,
    input  logic [DATA_WIDTH-1:0] s_flit_in, input logic s_valid_in, output logic s_credit_out,
    output logic [DATA_WIDTH-1:0] s_flit_out, output logic s_valid_out, input logic s_credit_in,
    input  logic [DATA_WIDTH-1:0] e_flit_in, input logic e_valid_in, output logic e_credit_out,
    output logic [DATA_WIDTH-1:0] e_flit_out, output logic e_valid_out, input logic e_credit_in,
    input  logic [DATA_WIDTH-1:0] w_flit_in, input logic w_valid_in, output logic w_credit_out,
    output logic [DATA_WIDTH-1:0] w_flit_out, output logic w_valid_out, input logic w_credit_in
);
    // OBI signals
    logic obi_req, obi_gnt, obi_rvalid, obi_we;
    logic [3:0] obi_be;
    logic [31:0] obi_addr, obi_wdata, obi_rdata;

    // Local signals
    logic [DATA_WIDTH-1:0] l_flit_tx, l_flit_rx;
    logic l_valid_tx, l_valid_rx, l_credit_tx, l_credit_rx;

    // 1. Traffic Generator
    traffic_gen #(
        .DEST_X(DEST_X), .DEST_Y(DEST_Y),
        .LOAD_FACTOR(LOAD_FACTOR), .WRITE_PROB(WRITE_PROB)
    ) u_tg (
        .clk(clk), .rst_n(rst_n),
        .obi_req(obi_req), .obi_gnt(obi_gnt), .obi_we(obi_we), .obi_be(obi_be),
        .obi_addr(obi_addr), .obi_wdata(obi_wdata), .obi_rvalid(obi_rvalid), .obi_rdata(obi_rdata)
    );

    // 2. Master NI (Đã hàn dây chuẩn obi_*)
    master_ni #(
        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y), .PRIORITY(PRIORITY)
    ) u_master_ni (
        .clk(clk), .rst_n(rst_n),
        .obi_req(obi_req), .obi_gnt(obi_gnt), .obi_we(obi_we), .obi_be(obi_be), 
        .obi_addr(obi_addr), .obi_wdata(obi_wdata), .obi_rvalid(obi_rvalid), .obi_rdata(obi_rdata),
        .tx_flit(l_flit_tx), .tx_valid(l_valid_tx), .tx_credit(l_credit_tx),
        .rx_flit(l_flit_rx), .rx_valid(l_valid_rx), .rx_credit(l_credit_rx)
    );

    // 3. Router
    router_top #(
        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(CURRENT_X), .CURRENT_Y(CURRENT_Y)
    ) u_router (
        .clk(clk), .rst_n(rst_n),
        .l_flit_in(l_flit_tx), .l_valid_in(l_valid_tx), .l_credit_out(l_credit_tx),
        .l_flit_out(l_flit_rx), .l_valid_out(l_valid_rx), .l_credit_in(l_credit_rx),
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
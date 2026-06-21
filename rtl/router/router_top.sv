`timescale 1ns/1ps
module router_top #(
    parameter DATA_WIDTH = 34,
    parameter CURRENT_X  = 2'd0,
    parameter CURRENT_Y  = 2'd0
)(
    input  logic clk,
    input  logic rst_n,

    // 0. PORT LOCAL 
    input  logic [DATA_WIDTH-1:0] l_flit_in,
    input  logic                  l_valid_in,
    output logic                  l_credit_out, 
    output logic [DATA_WIDTH-1:0] l_flit_out,
    output logic                  l_valid_out,
    input  logic                  l_credit_in,  

    // 1. PORT NORTH
    input  logic[DATA_WIDTH-1:0] n_flit_in,
    input  logic                  n_valid_in,
    output logic                  n_credit_out,
    output logic [DATA_WIDTH-1:0] n_flit_out,
    output logic                  n_valid_out,
    input  logic                  n_credit_in,

    // 2. PORT SOUTH 
    input  logic[DATA_WIDTH-1:0] s_flit_in,
    input  logic                  s_valid_in,
    output logic                  s_credit_out,
    output logic [DATA_WIDTH-1:0] s_flit_out,
    output logic                  s_valid_out,
    input  logic                  s_credit_in,

    // 3. PORT EAST
    input  logic [DATA_WIDTH-1:0] e_flit_in,
    input  logic                  e_valid_in,
    output logic                  e_credit_out,
    output logic [DATA_WIDTH-1:0] e_flit_out,
    output logic                  e_valid_out,
    input  logic                  e_credit_in,
    // 4. PORT WEST
    input  logic [DATA_WIDTH-1:0] w_flit_in,
    input  logic                  w_valid_in,
    output logic                  w_credit_out,
    output logic [DATA_WIDTH-1:0] w_flit_out,
    output logic                  w_valid_out,
    input  logic                  w_credit_in
);

    // 1. Dữ liệu từ Input Port đi ra (Chuẩn bị vào MUX)
    logic [DATA_WIDTH-1:0] flit_from_L, flit_from_N, flit_from_S, flit_from_E, flit_from_W;
    
    // 2. Xin đường (Route_Req) từ Input Port gửi tới 5 Arbiter
    logic [4:0] req_from_L, req_from_N, req_from_S, req_from_E, req_from_W;
    
    // 3. Cờ báo hiệu Tail (Mở khóa Wormhole) từ Input Port gửi tới Arbiter
    logic tail_from_L, tail_from_N, tail_from_S, tail_from_E, tail_from_W;
    
    //Khai báo dây nhận tín hiệu ưu tiên động từ 5 Input Port 
    logic prio_from_L, prio_from_N, prio_from_S, prio_from_E, prio_from_W;

    // 4. Quyền đi (Grant) từ Arbiter gửi ngược lại Input Port và MUX
    logic [4:0] grant_L, grant_N, grant_S, grant_E, grant_W;

    // 5. Trạng thái Credit (Còn chỗ) từ Output Port gửi ngược lại Arbiter
    logic credit_ok_L, credit_ok_N, credit_ok_S, credit_ok_E, credit_ok_W;

    // 6. BÓ CÁP TỔNG 170-BIT (Nối vào cổng data_in của 5 cái MUX)
    logic [(5*DATA_WIDTH)-1 : 0] all_data_flat;
    // Thứ tự ghép bit:[4:West, 3:East, 2:South, 1:North, 0:Local]
    assign all_data_flat = {flit_from_W, flit_from_E, flit_from_S, flit_from_N, flit_from_L};


    

    input_port #(.current_x(CURRENT_X), .current_y(CURRENT_Y)) in_port_L (
        .clk(clk), .rst_n(rst_n),
        .flit_in(l_flit_in), .valid_in(l_valid_in), .credit_out(l_credit_out),
        .flit_out(flit_from_L), .valid_out(), .port_req(req_from_L), .is_tail(tail_from_L),
        .is_prio(prio_from_L), 
        .pop_en(grant_L[0] | grant_N[0] | grant_S[0] | grant_E[0] | grant_W[0]) 
    );

    input_port #(.current_x(CURRENT_X), .current_y(CURRENT_Y)) in_port_N (
        .clk(clk), .rst_n(rst_n),
        .flit_in(n_flit_in), .valid_in(n_valid_in), .credit_out(n_credit_out),
        .flit_out(flit_from_N), .valid_out(), .port_req(req_from_N), .is_tail(tail_from_N),
        .is_prio(prio_from_N), 
        .pop_en(grant_L[1] | grant_N[1] | grant_S[1] | grant_E[1] | grant_W[1]) 
    );

    input_port #(.current_x(CURRENT_X), .current_y(CURRENT_Y)) in_port_S (
        .clk(clk), .rst_n(rst_n),
        .flit_in(s_flit_in), .valid_in(s_valid_in), .credit_out(s_credit_out),
        .flit_out(flit_from_S), .valid_out(), .port_req(req_from_S), .is_tail(tail_from_S),
        .is_prio(prio_from_S), 
        .pop_en(grant_L[2] | grant_N[2] | grant_S[2] | grant_E[2] | grant_W[2]) 
    );

    input_port #(.current_x(CURRENT_X), .current_y(CURRENT_Y)) in_port_E (
        .clk(clk), .rst_n(rst_n),
        .flit_in(e_flit_in), .valid_in(e_valid_in), .credit_out(e_credit_out),
        .flit_out(flit_from_E), .valid_out(), .port_req(req_from_E), .is_tail(tail_from_E),
        .is_prio(prio_from_E),
        .pop_en(grant_L[3] | grant_N[3] | grant_S[3] | grant_E[3] | grant_W[3]) 
    );

    input_port #(.current_x(CURRENT_X), .current_y(CURRENT_Y)) in_port_W (
        .clk(clk), .rst_n(rst_n),
        .flit_in(w_flit_in), .valid_in(w_valid_in), .credit_out(w_credit_out),
        .flit_out(flit_from_W), .valid_out(), .port_req(req_from_W), .is_tail(tail_from_W),
        .is_prio(prio_from_W), 
        .pop_en(grant_L[4] | grant_N[4] | grant_S[4] | grant_E[4] | grant_W[4]) 
    );

    // Tín hiệu kết nối từ MUX sang Output Port
    logic [DATA_WIDTH-1:0] mux_data_L, mux_data_N, mux_data_S, mux_data_E, mux_data_W;
    logic                  mux_valid_L, mux_valid_N, mux_valid_S, mux_valid_E, mux_valid_W;
    
    // Gom tín hiệu is_tail của 5 cổng thành mảng 5-bit để đưa vào Arbiter
    logic [4:0] all_tails;
    assign all_tails = {tail_from_W, tail_from_E, tail_from_S, tail_from_N, tail_from_L};

    //  Bó các tín hiệu ưu tiên động thành mảng 5-bit (Đồng bộ thứ tự bit với chân .req)
    logic [4:0] all_priorities;
    assign all_priorities = {prio_from_W, prio_from_E, prio_from_S, prio_from_N, prio_from_L};


    

    // NGÕ RA 0: LOCAL (Hướng ra Ibex)
    arbiter arb_L (
        .clk(clk), .rst_n(rst_n),
        .req({req_from_W[0], req_from_E[0], req_from_S[0], req_from_N[0], req_from_L[0]}), 
        .req_priority(all_priorities),
        .tail_flag(all_tails), .credit_ok(credit_ok_L), .grant(grant_L)
    );
    crossbar_switch #(.data_width(DATA_WIDTH)) mux_L (
        .grant(grant_L), .data_in(all_data_flat), .data_out(mux_data_L), .valid_out(mux_valid_L)
    );
    output_port #(.data_width(DATA_WIDTH), .fifo_depth(4)) out_L (
        .clk(clk), .rst_n(rst_n), .data_in(mux_data_L), .valid_in(mux_valid_L),
        .data_out(l_flit_out), .valid_out(l_valid_out), .credit_in(l_credit_in), .credit_ok(credit_ok_L)
    );

    // NGÕ RA 1: NORTH
    arbiter arb_N (
        .clk(clk), .rst_n(rst_n),
        .req({req_from_W[1], req_from_E[1], req_from_S[1], req_from_N[1], req_from_L[1]}), 
        .req_priority(all_priorities), 
        .tail_flag(all_tails), .credit_ok(credit_ok_N), .grant(grant_N)
    );
    crossbar_switch #(.data_width(DATA_WIDTH)) mux_N (
        .grant(grant_N), .data_in(all_data_flat), .data_out(mux_data_N), .valid_out(mux_valid_N)
    );
    output_port #(.data_width(DATA_WIDTH), .fifo_depth(4)) out_N (
        .clk(clk), .rst_n(rst_n), .data_in(mux_data_N), .valid_in(mux_valid_N),
        .data_out(n_flit_out), .valid_out(n_valid_out), .credit_in(n_credit_in), .credit_ok(credit_ok_N)
    );

    // NGÕ RA 2: SOUTH
    arbiter arb_S (
        .clk(clk), .rst_n(rst_n),
        .req({req_from_W[2], req_from_E[2], req_from_S[2], req_from_N[2], req_from_L[2]}), 
        .req_priority(all_priorities), 
        .tail_flag(all_tails), .credit_ok(credit_ok_S), .grant(grant_S)
    );
    crossbar_switch #(.data_width(DATA_WIDTH)) mux_S (
        .grant(grant_S), .data_in(all_data_flat), .data_out(mux_data_S), .valid_out(mux_valid_S)
    );
    output_port #(.data_width(DATA_WIDTH), .fifo_depth(4)) out_S (
        .clk(clk), .rst_n(rst_n), .data_in(mux_data_S), .valid_in(mux_valid_S),
        .data_out(s_flit_out), .valid_out(s_valid_out), .credit_in(s_credit_in), .credit_ok(credit_ok_S)
    );

    // NGÕ RA 3: EAST
    arbiter arb_E (
        .clk(clk), .rst_n(rst_n),
        .req({req_from_W[3], req_from_E[3], req_from_S[3], req_from_N[3], req_from_L[3]}), 
        .req_priority(all_priorities), 
        .tail_flag(all_tails), .credit_ok(credit_ok_E), .grant(grant_E)
    );
    crossbar_switch #(.data_width(DATA_WIDTH)) mux_E (
        .grant(grant_E), .data_in(all_data_flat), .data_out(mux_data_E), .valid_out(mux_valid_E)
    );
    output_port #(.data_width(DATA_WIDTH), .fifo_depth(4)) out_E (
        .clk(clk), .rst_n(rst_n), .data_in(mux_data_E), .valid_in(mux_valid_E),
        .data_out(e_flit_out), .valid_out(e_valid_out), .credit_in(e_credit_in), .credit_ok(credit_ok_E)
    );

    // NGÕ RA 4: WEST
    arbiter arb_W (
        .clk(clk), .rst_n(rst_n),
        .req({req_from_W[4], req_from_E[4], req_from_S[4], req_from_N[4], req_from_L[4]}), 
        .req_priority(all_priorities),
        .tail_flag(all_tails), .credit_ok(credit_ok_W), .grant(grant_W)
    );
    crossbar_switch #(.data_width(DATA_WIDTH)) mux_W (
        .grant(grant_W), .data_in(all_data_flat), .data_out(mux_data_W), .valid_out(mux_valid_W)
    );
    output_port #(.data_width(DATA_WIDTH), .fifo_depth(4)) out_W (
        .clk(clk), .rst_n(rst_n), .data_in(mux_data_W), .valid_in(mux_valid_W),
        .data_out(w_flit_out), .valid_out(w_valid_out), .credit_in(w_credit_in), .credit_ok(credit_ok_W)
    );

endmodule 
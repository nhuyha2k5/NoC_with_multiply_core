`timescale 1ns/1ps

module slave_ni #(
    parameter DATA_WIDTH = 34,
    parameter CURRENT_X  = 2'd2,
    parameter CURRENT_Y  = 2'd2,
    parameter MEM_DEPTH  = 1024
)(
    input  logic clk,
    input  logic rst_n,

    // =======================================================
    // GIAO DIỆN NoC (Nối vào cổng LOCAL của Router_Top)
    // =======================================================
    input  logic [DATA_WIDTH-1:0] rx_flit,
    input  logic                  rx_valid,
    output logic                  rx_credit,

    output logic [DATA_WIDTH-1:0] tx_flit,
    output logic                  tx_valid,
    input  logic                  tx_credit 
);

    // =======================================================
    // KHAI BÁO STATE (ĐẶT Ở ĐẦU FILE ĐỂ TRÁNH LỖI BIÊN DỊCH)
    // =======================================================
    // FSM Nhận (RX)
    typedef enum logic [2:0] {RX_IDLE, RX_BODY_WRITE, RX_TAIL_WRITE, RX_TAIL_READ, RX_WAIT_READ, RX_WAIT_READ_2} rx_state_t;
    rx_state_t rx_state, rx_next;

    // FSM Gửi (TX)
    typedef enum logic [1:0] {TX_IDLE, TX_HEAD, TX_TAIL} tx_state_t;
    tx_state_t tx_state, tx_next;

    // =======================================================
    // KHỐI 1: BỘ NHỚ RAM NỘI BỘ
    // =======================================================
    logic [31:0] memory [0:MEM_DEPTH-1];
    
    // ĐÃ SỬA: Khởi tạo RAM bằng 0 lúc mới chạy mô phỏng
    initial begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            memory[i] = 32'd0;
        end
    end
    
    logic        mem_we;
    logic [31:0] mem_addr; 
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    logic [3:0]  mem_be;

    // ĐÃ SỬA: Mask địa chỉ để tránh tràn mảng (Chỉ lấy 10 bit từ bit 2 -> 11)
    wire [9:0] word_addr;
    assign word_addr = mem_addr[11:2];

    // RAM đồng bộ (cần 1 chu kỳ để nhả dữ liệu)
    always_ff @(posedge clk) begin
        if (mem_we) begin
            if (mem_be[0]) memory[word_addr][7:0]   <= mem_wdata[7:0];
            if (mem_be[1]) memory[word_addr][15:8]  <= mem_wdata[15:8];
            if (mem_be[2]) memory[word_addr][23:16] <= mem_wdata[23:16];
            if (mem_be[3]) memory[word_addr][31:24] <= mem_wdata[31:24];
        end
        mem_rdata <= memory[word_addr];
    end

    // =======================================================
    // KHỐI 2: QUẢN LÝ LUỒNG TX (Credit)
    // =======================================================
    logic [2:0] tx_credit_count;
    logic       can_send;
    assign can_send = (tx_credit_count > 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_credit_count <= 3'd4;
        end else begin
            case ({tx_credit, (tx_valid && can_send)})
                2'b10: tx_credit_count <= tx_credit_count + 1'b1;
                2'b01: tx_credit_count <= tx_credit_count - 1'b1;
                default: tx_credit_count <= tx_credit_count;
            endcase
        end
    end

    // =======================================================
    // KHỐI 3: RX FSM (Nhận gói tin)
    // =======================================================
    logic [1:0] saved_src_x, saved_src_y;
    logic       saved_we;
    logic       tx_start_resp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            saved_src_x <= 2'b00; saved_src_y <= 2'b00;
            saved_we <= 1'b0; mem_be <= 4'd0; mem_addr <= 32'd0;
        end else begin
            rx_state <= rx_next;
            
            // Lưu thông tin từ Head Flit
            if (rx_state == RX_IDLE && rx_valid && rx_flit[33:32] == 2'b01) begin
                saved_src_x <= rx_flit[27:26];
                saved_src_y <= rx_flit[25:24];
                saved_we    <= rx_flit[23];
                mem_be      <= rx_flit[22:19];
            end

            // Lưu địa chỉ từ Body Flit (chỉ cho lệnh Ghi)
            if (rx_state == RX_BODY_WRITE && rx_valid && rx_flit[33:32] == 2'b00) begin
                mem_addr <= rx_flit[31:0];
            end

            // Lưu địa chỉ từ Tail Flit cho lệnh Đọc
            if (rx_state == RX_TAIL_READ && rx_valid && rx_flit[33:32] == 2'b10) begin
                mem_addr <= rx_flit[31:0];
            end
        end
    end

    always_comb begin
        rx_next = rx_state;
        rx_credit = 1'b0;
        mem_we = 1'b0;
        mem_wdata = 32'd0;
        tx_start_resp = 1'b0;

        case (rx_state)
            RX_IDLE: begin
                if (rx_valid && rx_flit[33:32] == 2'b01) begin
                    rx_credit = 1'b1;
                    if (rx_flit[23] == 1'b1) 
                        rx_next = RX_BODY_WRITE; // Lệnh Ghi
                    else 
                        rx_next = RX_TAIL_READ;  // Lệnh Đọc
                end
            end

            RX_BODY_WRITE: begin
                if (rx_valid && rx_flit[33:32] == 2'b00) begin
                    rx_credit = 1'b1;
                    rx_next = RX_TAIL_WRITE;
                end
            end

            RX_TAIL_WRITE: begin
                if (rx_valid && rx_flit[33:32] == 2'b10) begin
                    rx_credit = 1'b1;
                    mem_wdata = rx_flit[31:0];
                    mem_we = 1'b1;
                    rx_next = RX_IDLE;
                end
            end

            RX_TAIL_READ: begin
                if (rx_valid && rx_flit[33:32] == 2'b10) begin
                    rx_credit = 1'b1;
                    rx_next = RX_WAIT_READ; 
                end
            end

            RX_WAIT_READ: begin
                // Chờ RAM 1 nhịp để lấy dữ liệu
                rx_next = RX_WAIT_READ_2; 
            end

            RX_WAIT_READ_2: begin
                // RAM đã xuất dữ liệu ổn định, đợi TX rảnh để kích hoạt
                if (tx_state == TX_IDLE) begin
                    tx_start_resp = 1'b1;
                    rx_next = RX_IDLE;
                end
            end
        endcase
    end

    // =======================================================
    // KHỐI 4: TX FSM (Gửi phản hồi Đọc)
    // =======================================================
    logic [31:0] saved_rdata;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            saved_rdata <= 32'd0;
        end else begin
            tx_state <= tx_next;
            if (tx_start_resp) begin
                saved_rdata <= mem_rdata;
            end
        end
    end

    always_comb begin
        tx_next = tx_state;
        tx_flit = 34'd0;
        tx_valid = 1'b0;

        case (tx_state)
            TX_IDLE: begin
                if (tx_start_resp) begin
                    tx_next = TX_HEAD;
                end
            end

            TX_HEAD: begin
                if (can_send) begin
                    tx_valid = 1'b1;
                    // Đổi vai trò: Gửi về đích là Src cũ, Src mới là tọa độ của Slave này
                    tx_flit = {2'b01, saved_src_x, saved_src_y, CURRENT_X, CURRENT_Y, 1'b0, 4'd0, 19'd0};
                    tx_next = TX_TAIL;
                end
            end

            TX_TAIL: begin
                if (can_send) begin
                    tx_valid = 1'b1;
                    tx_flit = {2'b10, saved_rdata};
                    tx_next = TX_IDLE;
                end
            end
        endcase
    end

endmodule
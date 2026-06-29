`timescale 1ns/1ps

module traffic_gen #(
    parameter DEST_X      = 2'd2,
    parameter DEST_Y      = 2'd2,
    parameter LOAD_FACTOR = 10,   // số chu kỳ giữa các request
    parameter WRITE_PROB  = 50    // % xác suất ghi (0-100)
)(
    input  logic clk,
    input  logic rst_n,
    // OBI interface
    output logic        obi_req,
    input  logic        obi_gnt,
    output logic        obi_we,
    output logic [3:0]  obi_be,
    output logic [31:0] obi_addr,
    output logic [31:0] obi_wdata,
    input  logic        obi_rvalid,
    input  logic [31:0] obi_rdata
);

    typedef enum logic [1:0] {IDLE, SEND, WAIT_GRANT, WAIT_RVALID} state_t;
    state_t state, next_state;

    logic [31:0] seed, addr_counter;
    
    // TỐI ƯU 1: Dùng biến đếm nhỏ 16-bit thay cho 32-bit
    logic [15:0] delay_cnt; 

    // =======================================================
    // TỐI ƯU 2: Loại bỏ phép `% LOAD_FACTOR` bằng Wrap-around Counter
    // =======================================================
    logic request_trigger;
    assign request_trigger = (delay_cnt == 0);

    // =======================================================
    // TỐI ƯU 3: Loại bỏ phép `% 100` bằng Hằng số thời điểm biên dịch
    // =======================================================
    // Thay vì chia ở phần cứng, ta bắt Quartus tự tính phép chia này MỘT LẦN 
    // lúc biên dịch để tạo ra một hằng số. 
    // 7-bit của LFSR có giá trị từ 0-127. Ta quy đổi tỷ lệ % từ thang 100 sang thang 128.
    localparam THRESHOLD = (WRITE_PROB * 128) / 100; 

    logic rand_we;
    // Chỉ cần 1 bộ so sánh 7-bit cực kỳ nhỏ gọn!
    assign rand_we = (seed[6:0] < THRESHOLD);

    logic [31:0] rand_addr;
    // Ép tọa độ Đích vào đúng bit [13:12] và [9:8] để Master NI đọc được
assign rand_addr = (DEST_X << 12) | (DEST_Y << 8) | ((addr_counter & 32'h3F) << 2);


    // =======================================================
    // --- Khối always_ff chính ---
    // =======================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            delay_cnt <= 0;
            seed <= 32'h12345678;
            addr_counter <= 0;                    
        end else begin
            state <= next_state;
            
            // LFSR tạo số ngẫu nhiên
            seed <= {seed[30:0], seed[31] ^ seed[21] ^ seed[1] ^ seed[0]};

            // TỐI ƯU 1 (Tiếp): Đếm quay vòng thay vì đếm tiến vô hạn
            if (delay_cnt >= LOAD_FACTOR - 1) begin
                delay_cnt <= 0;
            end else begin
                delay_cnt <= delay_cnt + 1;
            end

            // Tăng địa chỉ
            if (state == IDLE && request_trigger) begin
                addr_counter <= addr_counter + 1;
            end
        end
    end

    // =======================================================
    // --- FSM (logic tổ hợp) ---
    // =======================================================
    always_comb begin
        next_state = state;
        obi_req   = 1'b0;
        obi_we    = 1'b0;
        obi_be    = 4'b1111;
        obi_addr  = 32'd0;
        obi_wdata = 32'd0;

        case (state)
            IDLE: begin
                if (request_trigger) begin
                    obi_req    = 1'b1;
                    obi_we     = rand_we;
                    obi_addr   = rand_addr;
                    obi_wdata  = seed;
                    next_state = WAIT_GRANT;
                end
            end
            WAIT_GRANT: begin
                obi_req   = 1'b1;
                obi_we    = rand_we;
                obi_addr  = rand_addr;
                obi_wdata = seed;
                
                if (obi_gnt) begin
                    // Phân luồng chờ tùy theo Đọc hay Ghi
                    if (rand_we) next_state = IDLE;         // Ghi xong -> Đi tiếp luôn
                    else         next_state = WAIT_RVALID;  // Đọc -> Phải chờ dữ liệu trả về
                end
            end
            WAIT_RVALID: begin
                if (obi_rvalid) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
endmodule
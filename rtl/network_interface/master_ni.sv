`timescale 1ns/1ps
module master_ni #(
    parameter DATA_WIDTH = 34,
    parameter CURRENT_X  = 2'd0, 
    parameter CURRENT_Y  = 2'd0,  
    parameter PRIORITY   = 1'b0   // Nếu có nhiều NI trên cùng 1 Node, PRIORITY=0 sẽ được ưu tiên cấp gnt trước
)(
    input  logic clk,
    input  logic rst_n,

    // =======================================================
    // GIAO DIỆN OBI (Nối trực tiếp vào CPU Ibex)
    // =======================================================
    input  logic        obi_req,
    output logic        obi_gnt,
    input  logic        obi_we,
    input  logic [3:0]  obi_be,      // Byte Enable (Rất quan trọng)
    input  logic [31:0] obi_addr,
    input  logic [31:0] obi_wdata,
    
    output logic        obi_rvalid,
    output logic [31:0] obi_rdata,

    // =======================================================
    // GIAO DIỆN NOC (Nối vào cổng LOCAL của Router_Top)
    // =======================================================
    // TX: Bơm vào Router
    output logic [DATA_WIDTH-1:0] tx_flit,
    output logic                  tx_valid,
    input  logic                  tx_credit,  // Router báo: "Còn chỗ"
    
    // RX: Lấy từ Router ra
    input  logic [DATA_WIDTH-1:0] rx_flit,
    input  logic                  rx_valid,
    output logic                  rx_credit   // Báo Router: "Đã nuốt xong"
);

    // =======================================================
    // KHỐI 1: BỘ DỊCH ĐỊA CHỈ (Address Decoder)
    // =======================================================
    // Tái sử dụng cách dịch địa chỉ cực hay của bạn: 
    // Lấy trực tiếp các bit [27:26] và [25:24] từ địa chỉ
    logic [1:0] dest_x, dest_y;
		assign dest_x = obi_addr[13:12]; 
		assign dest_y = obi_addr[9:8];

    // =======================================================
    // KHỐI 2: QUẢN LÝ LUỒNG TX (Credit Manager)
    // =======================================================
    logic [2:0] tx_credit_count;
    logic       can_send;
    
    assign can_send = (tx_credit_count > 0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_credit_count <= 3'd4; // Giả sử FIFO của Router sâu 4
        end else begin
            case ({tx_credit, (tx_valid && can_send)})
                2'b10: tx_credit_count <= tx_credit_count + 1'b1; // Router nhả 1 chỗ
                2'b01: tx_credit_count <= tx_credit_count - 1'b1; // Mình bơm 1 flit
                default: tx_credit_count <= tx_credit_count;      // Cùng tăng cùng giảm hoặc đứng im
            endcase
        end
    end


    // =======================================================
    // KHỐI 3: TX PACKETIZER (FSM Đóng gói gửi đi)
    // =======================================================
    typedef enum logic [1:0] {TX_IDLE, TX_HEAD, TX_BODY, TX_TAIL} tx_state_t;
    tx_state_t tx_state, tx_next;

    // Các thanh ghi chốt (Latch) tín hiệu OBI
    logic [31:0] saved_addr, saved_wdata;
    logic        saved_we;
    logic [3:0]  saved_be;
    logic [1:0]  saved_dest_x, saved_dest_y;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            saved_addr <= 32'd0; saved_wdata <= 32'd0;
            saved_we <= 1'b0; saved_be <= 4'd0;
            saved_dest_x <= 2'd0; saved_dest_y <= 2'd0;
        end else begin
            tx_state <= tx_next;
            // CHỈ CHỐT DỮ LIỆU KHI BẮT TAY THÀNH CÔNG (Tránh bug mất data)
            if (obi_req && obi_gnt) begin
                saved_addr <= obi_addr;
                saved_wdata <= obi_wdata;
                saved_we <= obi_we;
                saved_be <= obi_be;
                saved_dest_x <= dest_x;
                saved_dest_y <= dest_y;
            end
        end
    end

    always_comb begin
        tx_next = tx_state;
        tx_flit = 34'd0;
        tx_valid = 1'b0;
        obi_gnt = 1'b0;

        case (tx_state)
            TX_IDLE: begin
                // Bắt tay với CPU: Báo gnt=1 nếu mạng đang rảnh và FSM đang ở IDLE
                if (obi_req && can_send) begin
                    obi_gnt = 1'b1; 
                    tx_next = TX_HEAD;
                end
            end

            TX_HEAD: begin
                if (can_send) begin
                    tx_valid = 1'b1;
                    // Cấu trúc Head Flit:
                    // Cấu trúc Head Flit:
                    // [33:32]=01(Head) | [31:30]=DestX | [29:28]=DestY | [27:26]=SrcX | [25:24]=SrcY | [23]=WE | [22:19]=BE | [18]=PRIO | [17:0]=Trống
                    tx_flit = {2'b01, saved_dest_x, saved_dest_y, CURRENT_X, CURRENT_Y, saved_we, saved_be, PRIORITY, 18'd0}; 
                    
                    if (saved_we) 
                        tx_next = TX_BODY; // Lệnh Ghi -> Chuyển sang bơm Body (Địa chỉ)
                    else 
                        tx_next = TX_TAIL; // Lệnh Đọc -> Chuyển sang bơm Tail (Địa chỉ) 
                end
            end

            TX_BODY: begin
                if (can_send) begin
                    tx_valid = 1'b1;
                    tx_flit = {2'b00, saved_addr}; // 2'b00 = Body Flit, chứa Address
                    tx_next = TX_TAIL;
                end
            end

            TX_TAIL: begin
                if (can_send) begin
                    tx_valid = 1'b1;
                    if (saved_we) 
                        tx_flit = {2'b10, saved_wdata}; // Nếu Ghi: Tail chứa Data
                    else
                        tx_flit = {2'b10, saved_addr};  // Nếu Đọc: Tail chứa Address
                    
                    tx_next = TX_IDLE; // Xong 1 giao dịch,  nghỉ
                end
            end
        endcase
    end


    // =======================================================
    // KHỐI 4: RX DEPACKETIZER (FSM Tháo gói phản hồi)
    // =======================================================
    // Lệnh Đọc sẽ nhận về 2 Flit: Head Flit -> Tail Flit (Chứa Dữ liệu rdata)
    typedef enum logic {RX_IDLE, RX_GET_TAIL} rx_state_t;
    rx_state_t rx_state, rx_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_state <= RX_IDLE;
        else        rx_state <= rx_next;
    end

    always_comb begin
        rx_next = rx_state;
        rx_credit = 1'b0;
        obi_rvalid = 1'b0;
        obi_rdata = 32'd0;

        case (rx_state)
            RX_IDLE: begin
                // Đứng chờ Head Flit (Type = 2'b01) từ mạng
                if (rx_valid && rx_flit[33:32] == 2'b01) begin
                    rx_credit = 1'b1; 
                    rx_next = RX_GET_TAIL;
                end
            end

            RX_GET_TAIL: begin
                // Đứng chờ Tail Flit (Type = 2'b10) từ mạng
                if (rx_valid && rx_flit[33:32] == 2'b10) begin
                    rx_credit = 1'b1;
                    obi_rdata = rx_flit[31:0]; // Móc cục data đưa cho CPU
                    obi_rvalid = 1'b1;         // Bật cờ OBI rvalid cho CPU đi tiếp
                    rx_next = RX_IDLE;
                end
            end
        endcase
    end

endmodule
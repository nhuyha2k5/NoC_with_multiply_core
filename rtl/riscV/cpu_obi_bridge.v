`timescale 1ns/1ps

module cpu_obi_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // --- Giao diện phía CPU ---
    input  wire        cpu_req,
    input  wire        cpu_we,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [2:0]  cpu_store_sel,
    output reg         cpu_stall,     
    output wire [31:0] cpu_rdata,     

    // --- Giao diện phía OBI (Master NI) ---
    output reg         noc_req,       
    input  wire        noc_gnt,
    output reg         noc_we,        
    output reg  [3:0]  noc_be,        
    output reg  [31:0] noc_addr,      
    output reg  [31:0] noc_wdata,     
    input  wire        noc_rvalid,
    input  wire [31:0] noc_rdata,

    // --- Giao diện phía Local RAM (ram_obi) ---
    output reg         local_req,     
    input  wire        local_gnt,
    output reg         local_we,      
    output reg  [3:0]  local_be,      
    output reg  [31:0] local_addr,    
    output reg  [31:0] local_wdata,   
    input  wire        local_rvalid,
    input  wire [31:0] local_rdata
);

    // 1. Chuyển Store Sel sang Byte Enable
    reg [3:0] be_gen;
    always @(*) begin
        case (cpu_store_sel)
            3'b010: be_gen = 4'b1111;                         // SW
            3'b001: be_gen = (cpu_addr[1]) ? 4'b1100 : 4'b0011; // SH
            3'b000: begin                                     // SB
                case (cpu_addr[1:0])
                    2'b00: be_gen = 4'b0001;
                    2'b01: be_gen = 4'b0010;
                    2'b10: be_gen = 4'b0100;
                    2'b11: be_gen = 4'b1000;
                endcase
            end
            default: be_gen = 4'b1111;
        endcase
    end

    // 2. FSM (State Machine) quản lý giao dịch OBI
    localparam IDLE        = 2'b00;
    localparam WAIT_GNT    = 2'b01;
    localparam WAIT_RVALID = 2'b10;

    reg [1:0] state, next_state;
    reg [31:0] saved_addr, saved_wdata;
    reg        saved_we;
    reg [3:0]  saved_be;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            saved_addr <= 32'd0; saved_wdata <= 32'd0;
            saved_we <= 1'b0; saved_be <= 4'd0;
        end else begin
            state <= next_state;
            if (state == IDLE && cpu_req) begin
                saved_addr <= cpu_addr;
                saved_wdata <= cpu_wdata;
                saved_we <= cpu_we;
                saved_be <= be_gen;
            end
        end
    end

    // 3. Tín hiệu cấp quyền và trả lời được chọn dựa trên bit địa chỉ thứ 31
    wire is_noc = saved_addr[31]; // 1 là NoC, 0 là Local RAM
    wire gnt    = is_noc ? noc_gnt : local_gnt;
    wire rvalid = is_noc ? noc_rvalid : local_rvalid;
    wire [31:0] rdata = is_noc ? noc_rdata : local_rdata;

    always @(*) begin
        next_state = state;
        cpu_stall = 1'b1;  // Mặc định stall CPU

        // Outputs mặc định
        noc_req = 1'b0; local_req = 1'b0;
        noc_we = 1'b0; local_we = 1'b0;
        noc_addr = 32'd0; local_addr = 32'd0;
        noc_wdata = 32'd0; local_wdata = 32'd0;
        noc_be = 4'd0; local_be = 4'd0;

        case (state)
            IDLE: begin
                if (cpu_req) begin
                    // Bật req cho nhánh tương ứng
                    if (is_noc) begin
                        noc_req = 1'b1; noc_we = saved_we; noc_addr = saved_addr; noc_wdata = saved_wdata; noc_be = saved_be;
                    end else begin
                        local_req = 1'b1; local_we = saved_we; local_addr = saved_addr; local_wdata = saved_wdata; local_be = saved_be;
                    end
                    next_state = WAIT_GNT;
                end else begin
                    cpu_stall = 1'b0;
                end
            end

            WAIT_GNT: begin
                // Giữ nguyên req đang chờ
                if (is_noc) begin
                    noc_req = 1'b1; noc_we = saved_we; noc_addr = saved_addr; noc_wdata = saved_wdata; noc_be = saved_be;
                end else begin
                    local_req = 1'b1; local_we = saved_we; local_addr = saved_addr; local_wdata = saved_wdata; local_be = saved_be;
                end
                
                if (gnt) begin
                    if (saved_we) begin 
                        next_state = IDLE;
                        cpu_stall = 1'b0;   // ĐÃ SỬA: Thả stall ngay khi ghi xong để CPU chạy tiếp
                    end else begin 
                        next_state = WAIT_RVALID; // Đọc thì vẫn phải chờ dữ liệu
                    end
                end
            end

            WAIT_RVALID: begin
                if (rvalid) begin
                    cpu_stall = 1'b0; // Nhận đủ dữ liệu, thả stall
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Trả về dữ liệu cho CPU nếu là đọc
    assign cpu_rdata = rdata; 
endmodule
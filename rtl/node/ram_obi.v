`timescale 1ns/1ps

module ram_obi #(
    parameter MEM_SIZE_BYTES = 1024, // Dung lượng RAM (Byte)
    parameter INIT_FILE = ""         // Đường dẫn file .hex
)(
    input  wire        clk,
    input  wire        rst_n,

    // PORT A: Dành cho Instruction Fetch (CHỈ ĐỌC)
    input  wire        req_a_i,
    output wire        gnt_a_o,
    input  wire        we_a_i,
    input  wire [3:0]  be_a_i,
    input  wire [31:0] addr_a_i,
    input  wire [31:0] wdata_a_i,
    output reg         rvalid_a_o,
    output reg  [31:0] rdata_a_o,

    // PORT B: Dành cho Load/Store (ĐỌC VÀ GHI CÓ BYTE-ENABLE)
    input  wire        req_b_i,
    output wire        gnt_b_o,
    input  wire        we_b_i,
    input  wire [3:0]  be_b_i,
    input  wire [31:0] addr_b_i,
    input  wire [31:0] wdata_b_i,
    output reg         rvalid_b_o,
    output reg  [31:0] rdata_b_o
);

    // Tính toán kích thước và độ rộng địa chỉ
    localparam MEM_WORDS = MEM_SIZE_BYTES / 4;
    localparam ADDR_WIDTH = (MEM_WORDS > 0) ? $clog2(MEM_WORDS) : 1;
    
    // =======================================================
    // [THẦN CHÚ] Ép Quartus sử dụng khối Embedded RAM phần cứng
    // =======================================================
    (* ramstyle = "no_rw_check, M10K" *) reg [31:0] mem [0:MEM_WORDS-1];

    // Nạp file hex (nếu có), nếu không thì gán 0
    integer i;
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (i = 0; i < MEM_WORDS; i = i + 1) begin
                mem[i] = 32'd0;
            end
        end
    end

    // Địa chỉ Word (chuyển từ Byte sang Word)
    wire [ADDR_WIDTH-1:0] word_addr_a;
    wire [ADDR_WIDTH-1:0] word_addr_b;
    
    assign word_addr_a = addr_a_i[ADDR_WIDTH+1:2];
    assign word_addr_b = addr_b_i[ADDR_WIDTH+1:2];

    // Cấp quyền Grant (OBI protocol)
    assign gnt_a_o = req_a_i;
    assign gnt_b_o = req_b_i;

    // =======================================================
    // PORT A (Chỉ Đọc - Cấu trúc chuẩn BRAM)
    // =======================================================
    always @(posedge clk) begin
        if (req_a_i) begin
            rdata_a_o <= mem[word_addr_a];
        end else begin
            rdata_a_o <= 32'd0;
        end
    end

    // =======================================================
    // PORT B (Đọc & Ghi chuẩn hóa tương thích BRAM)
    // =======================================================
    always @(posedge clk) begin
        if (req_b_i) begin
            // Cấu trúc ghi từng byte gộp chung được Quartus hỗ trợ để infer Byte-enable RAM
            if (we_b_i) begin
                if (be_b_i[0]) mem[word_addr_b][7:0]   <= wdata_b_i[7:0];
                if (be_b_i[1]) mem[word_addr_b][15:8]  <= wdata_b_i[15:8];
                if (be_b_i[2]) mem[word_addr_b][23:16] <= wdata_b_i[23:16];
                if (be_b_i[3]) mem[word_addr_b][31:24] <= wdata_b_i[31:24];
            end
            
            // Đọc chuẩn Old-Data (Read-During-Write trả về giá trị cũ/mới tùy cấu hình cứng)
            // Việc loại bỏ "rdata_b_o <= wdata_b_i" sẽ giúp giải phóng hàng ngàn LEs.
            rdata_b_o <= mem[word_addr_b];
        end
    end

    // =======================================================
    // TÍN HIỆU PHẢN HỒI (Valid)
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_a_o <= 1'b0;
            rvalid_b_o <= 1'b0;
        end else begin
            rvalid_a_o <= req_a_i;
            rvalid_b_o <= req_b_i;
        end
    end

endmodule
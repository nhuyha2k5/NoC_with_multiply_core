// MEM_WB Pipeline Register (Memory to Write Back)
// Lưu trữ dữ liệu giữa giai đoạn MEM và WB trong pipeline 5 tầng

module MEM_WB (
    input wire        clk,
    input wire        rst_n,
    // MEM_WB không cần stall hoặc flush vì là stage cuối cùng
    
    // Đầu vào từ MEM stage
    input wire [31:0] mem_pc_plus4,     // PC + 4 từ MEM stage
    input wire [31:0] mem_alu_result,   // Kết quả từ ALU
    input wire [31:0] mem_mem_data,     // Dữ liệu đọc từ bộ nhớ
    input wire [4:0]  mem_rd,           // Chỉ số thanh ghi đích
    
    // Tín hiệu điều khiển từ MEM stage
    input wire        mem_regWrite,     // Ghi vào Register File
    input wire [1:0]  mem_write_back,   // Chọn dữ liệu ghi lại
    
    // Đầu ra tới WB stage
    output reg [31:0] wb_pc_plus4,
    output reg [31:0] wb_alu_result,
    output reg [31:0] wb_mem_data,
    output reg [4:0]  wb_rd,
    
    // Tín hiệu điều khiển ra
    output reg        wb_regWrite,
    output reg [1:0]  wb_write_back
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khởi tạo tất cả register khi reset
            wb_pc_plus4   <= 32'h0000_0004;
            wb_alu_result <= 32'h0000_0000;
            wb_mem_data   <= 32'h0000_0000;
            wb_rd         <= 5'b0_0000;
            
            // Tín hiệu điều khiển mặc định
            wb_regWrite   <= 1'b0;
            wb_write_back <= 2'b00;
        end
        else begin
            // Luôn cập nhật dữ liệu từ MEM stage (stage cuối không bị stall/flush)
            wb_pc_plus4   <= mem_pc_plus4;
            wb_alu_result <= mem_alu_result;
            wb_mem_data   <= mem_mem_data;
            wb_rd         <= mem_rd;
            
            // Cập nhật tín hiệu điều khiển
            wb_regWrite   <= mem_regWrite;
            wb_write_back <= mem_write_back;
        end
    end

endmodule

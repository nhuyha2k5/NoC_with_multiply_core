// IF_ID Pipeline Register (Instruction Fetch to Instruction Decode)
// Lưu trữ dữ liệu giữa giai đoạn IF và ID trong pipeline 5 tầng

module IF_ID (
    input wire        clk,
    input wire        rst_n,
    input wire        stall,      // Tín hiệu dừng pipeline (hazard từ Hazard Unit)
    input wire        flush,      // Tín hiệu xóa dữ liệu (khi có branch/jump)
    
    // Đầu vào từ IF stage
    input wire [31:0] if_pc,      // Program Counter từ IF stage
    input wire [31:0] if_pc_plus4,// PC + 4 từ IF stage
    input wire [31:0] if_instr,   // Instruction từ Instruction Memory
    
    // Đầu ra tới ID stage
    output reg [31:0] id_pc,      // Program Counter cho ID stage
    output reg [31:0] id_pc_plus4,// PC + 4 cho ID stage
    output reg [31:0] id_instr    // Instruction cho ID stage
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khởi tạo toàn bộ register khi reset
            id_pc      <= 32'h0000_0000;
            id_pc_plus4 <= 32'h0000_0004;
            id_instr   <= 32'h0000_0013;  // NOP (addi x0, x0, 0)
        end
        else if (flush) begin
            // Xóa dữ liệu khi có branch/jump được thực thi
            id_pc      <= 32'h0000_0000;
            id_pc_plus4 <= 32'h0000_0004;
            id_instr   <= 32'h0000_0013;  // NOP
        end
        else if (!stall) begin
            // Cập nhật dữ liệu từ IF stage khi không bị stall
            id_pc      <= if_pc;
            id_pc_plus4 <= if_pc_plus4;
            id_instr   <= if_instr;
        end
        // Nếu stall = 1, giữ nguyên giá trị cũ
    end

endmodule

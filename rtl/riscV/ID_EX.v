// ID_EX Pipeline Register (Instruction Decode to Execute)
// Lưu trữ dữ liệu giữa giai đoạn ID và EX trong pipeline 5 tầng

module ID_EX (
    input wire        clk,
    input wire        rst_n,
    input wire        stall,      // Tín hiệu dừng pipeline (hazard)
    input wire        flush,      // Tín hiệu xóa dữ liệu (branch/jump)
    
    // Đầu vào từ ID stage
    input wire [31:0] id_pc,      // Program Counter từ ID stage
    input wire [31:0] id_pc_plus4,// PC + 4 từ ID stage
    input wire [31:0] id_rs1_data,// Dữ liệu từ Register File (rs1)
    input wire [31:0] id_rs2_data,// Dữ liệu từ Register File (rs2)
    input wire [31:0] id_imm,     // Immediate value (đã mở rộng)
    input wire [4:0]  id_rd,      // Chỉ số thanh ghi đích (rd)
    input wire [4:0]  id_rs1,     // Chỉ số thanh ghi nguồn 1 (rs1)
    input wire [4:0]  id_rs2,     // Chỉ số thanh ghi nguồn 2 (rs2)
    
    // Tín hiệu điều khiển từ Control Unit
    input wire        id_regWrite,    // Ghi vào Register File
    input wire [2:0]  id_imm_sel,     // Chọn loại immediate
    input wire        id_alu_srcA,    // Chọn toán hạng A của ALU
    input wire        id_alu_srcB,    // Chọn toán hạng B của ALU
    input wire [10:0]  id_alu_ctrl,    // Điều khiển ALU
    input wire        id_branch,      // Tín hiệu branch
    input wire [2:0]  id_bropcode,    // Opcode cho branch
    input wire [1:0]  id_jump,        // Tín hiệu jump
    input wire [2:0]  id_load_sel,    // Chọn loại load
    input wire [2:0]  id_store_sel,   // Chọn loại store
    input wire        id_memWrite,    // Ghi vào bộ nhớ dữ liệu
    input wire [1:0]  id_write_back,  // Chọn dữ liệu ghi lại
    
    // Đầu ra tới EX stage
    output reg [31:0] ex_pc,
    output reg [31:0] ex_pc_plus4,
    output reg [31:0] ex_rs1_data,
    output reg [31:0] ex_rs2_data,
    output reg [31:0] ex_imm,
    output reg [4:0]  ex_rd,
    output reg [4:0]  ex_rs1,
    output reg [4:0]  ex_rs2,
    
    // Tín hiệu điều khiển ra
    output reg        ex_regWrite,
    output reg [2:0]  ex_imm_sel,
    output reg        ex_alu_srcA,
    output reg        ex_alu_srcB,
    output reg [10:0]  ex_alu_ctrl,
    output reg        ex_branch,
    output reg [2:0]  ex_bropcode,
    output reg [1:0]  ex_jump,
    output reg [2:0]  ex_load_sel,
    output reg [2:0]  ex_store_sel,
    output reg        ex_memWrite,
    output reg [1:0]  ex_write_back
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khởi tạo tất cả register khi reset
            ex_pc       <= 32'h0000_0000;
            ex_pc_plus4 <= 32'h0000_0004;
            ex_rs1_data <= 32'h0000_0000;
            ex_rs2_data <= 32'h0000_0000;
            ex_imm      <= 32'h0000_0000;
            ex_rd       <= 5'b0_0000;
            ex_rs1      <= 5'b0_0000;
            ex_rs2      <= 5'b0_0000;
            
            // Tín hiệu điều khiển mặc định
            ex_regWrite <= 1'b0;
            ex_imm_sel  <= 3'b000;
            ex_alu_srcA <= 1'b0;
            ex_alu_srcB <= 1'b0;
            ex_alu_ctrl <= 11'b000_0000_0000;
            ex_branch   <= 1'b0;
            ex_bropcode <= 3'b000;
            ex_jump     <= 2'b00;
            ex_load_sel <= 3'b000;
            ex_store_sel<= 3'b000;
            ex_memWrite <= 1'b0;
            ex_write_back <= 2'b00;
        end
        else if (flush) begin
            // Xóa dữ liệu khi có branch/jump được thực thi
            ex_pc       <= 32'h0000_0000;
            ex_pc_plus4 <= 32'h0000_0004;
            ex_rs1_data <= 32'h0000_0000;
            ex_rs2_data <= 32'h0000_0000;
            ex_imm      <= 32'h0000_0000;
            ex_rd       <= 5'b0_0000;
            ex_rs1      <= 5'b0_0000;
            ex_rs2      <= 5'b0_0000;
            
            // Tín hiệu điều khiển bị xóa (NOP)
            ex_regWrite <= 1'b0;
            ex_imm_sel  <= 3'b000;
            ex_alu_srcA <= 1'b0;
            ex_alu_srcB <= 1'b0;
            ex_alu_ctrl <= 11'b000_0000_0000;
            ex_branch   <= 1'b0;
            ex_bropcode <= 3'b000;
            ex_jump     <= 2'b00;
            ex_load_sel <= 3'b000;
            ex_store_sel<= 3'b000;
            ex_memWrite <= 1'b0;
            ex_write_back <= 2'b00;
        end
        else if (!stall) begin
            // Cập nhật dữ liệu từ ID stage khi không bị stall
            ex_pc       <= id_pc;
            ex_pc_plus4 <= id_pc_plus4;
            ex_rs1_data <= id_rs1_data;
            ex_rs2_data <= id_rs2_data;
            ex_imm      <= id_imm;
            ex_rd       <= id_rd;
            ex_rs1      <= id_rs1;
            ex_rs2      <= id_rs2;
            
            // Cập nhật tín hiệu điều khiển
            ex_regWrite <= id_regWrite;
            ex_imm_sel  <= id_imm_sel;
            ex_alu_srcA <= id_alu_srcA;
            ex_alu_srcB <= id_alu_srcB;
            ex_alu_ctrl <= id_alu_ctrl;
            ex_branch   <= id_branch;
            ex_bropcode <= id_bropcode;
            ex_jump     <= id_jump;
            ex_load_sel <= id_load_sel;
            ex_store_sel<= id_store_sel;
            ex_memWrite <= id_memWrite;
            ex_write_back <= id_write_back;
        end
        // Nếu stall = 1, giữ nguyên giá trị cũ
    end

endmodule

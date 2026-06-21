module control_unit (
    input wire [6:0] opcode,
    input wire [2:0] funct3,
    input wire [6:0] funct7, // funct7[5] là bit thứ 30 của lệnh

    output reg        regWrite_D,   // Cho phép ghi vào Reg File
    output reg [2:0]  imm_sel,      // Chọn kiểu mở rộng hằng số
    output reg        alu_srcA_D,   // Chọn đầu vào A cho ALU (0: rs1, 1: PC)
    output reg        alu_srcB_D,   // Chọn đầu vào B cho ALU (0: rs2, 1: Imm)
    output reg [10:0]  alu_ctrl,     // 10-bit One-hot điều khiển phép toán ALU
    output reg        branch_D,     // Báo hiệu lệnh rẽ nhánh (đi vào bộ dự đoán)
    output reg [2:0]  bropcode,     // Loại rẽ nhánh (BEQ, BNE, BLT...)
    output reg [1:0]  jump_D,       // Loại nhảy (00: No, 01: JAL, 10: JALR)
    output reg [2:0]  load_sel_D,   // Kiểu Load (LB, LH, LW...)
    output reg [2:0]  store_sel_D,  // Kiểu Store (SB, SH, SW)
    output reg        memWrite_D,   // Cho phép ghi bộ nhớ
    output reg [1:0]  write_back_D, // Chọn kết quả về WB (00:ALU, 01:Mem, 10:PC+4)
    output reg        uses_rs1_D,   // Lệnh hiện tại có dùng rs1
    output reg        uses_rs2_D    // Lệnh hiện tại có dùng rs2
);

    // Định nghĩa hằng số ALU One-hot
localparam ALU_ADD  = 11'b00000000001;
localparam ALU_SUB  = 11'b00000000010;
localparam ALU_SLL  = 11'b00000000100;
localparam ALU_SLT  = 11'b00000001000;
localparam ALU_SLTU = 11'b00000010000;
localparam ALU_XOR  = 11'b00000100000;
localparam ALU_SRL  = 11'b00001000000;
localparam ALU_SRA  = 11'b00010000000;
localparam ALU_OR   = 11'b00100000000;
localparam ALU_AND  = 11'b01000000000;
localparam ALU_LUI  = 11'b10000000000; // Mã mới: Bit thứ 11

    always @(*) begin
        // --- Mặc định ---
        regWrite_D = 0; imm_sel = 3'b000; alu_srcA_D = 0; alu_srcB_D = 0;
        alu_ctrl = ALU_ADD; branch_D = 0; bropcode = 3'b000; jump_D = 2'b00;
        load_sel_D = 3'b010; store_sel_D = 3'b010; memWrite_D = 0; write_back_D = 2'b00;
        uses_rs1_D = 1'b0; uses_rs2_D = 1'b0;

        case (opcode)
            // 1. LUI (Load Upper Immediate)
            7'b0110111: begin
                regWrite_D = 1; imm_sel = 3'b011; alu_srcB_D = 1;
                alu_ctrl = ALU_LUI; // Gán mã 11-bit mới
                write_back_D = 2'b00;
            end

            // 2. AUIPC (Add Upper Imm to PC)
            7'b0010111: begin
                regWrite_D = 1; imm_sel = 3'b011; alu_srcA_D = 1; alu_srcB_D = 1;
                alu_ctrl = ALU_ADD; // PC + Imm
                write_back_D = 2'b00;
            end

            // 3. JAL (Jump and Link)
            7'b1101111: begin
                regWrite_D = 1; imm_sel = 3'b100; jump_D = 2'b01;
                write_back_D = 2'b10; // Lưu PC+4 vào rd
            end

            // 4. JALR (Jump and Link Register)
            7'b1100111: begin
                regWrite_D = 1; imm_sel = 3'b000; jump_D = 2'b10;
                alu_srcB_D = 1; alu_ctrl = ALU_ADD; // rs1 + Imm
                write_back_D = 2'b10;
                uses_rs1_D = 1'b1;
            end

            // 5-10. BRANCH (6 lệnh: BEQ, BNE, BLT, BGE, BLTU, BGEU)
            7'b1100011: begin
                branch_D = 1; imm_sel = 3'b010; bropcode = funct3;
                alu_ctrl = (funct3[2:1] == 2'b11) ? ALU_SLTU : ALU_SUB; 
                uses_rs1_D = 1'b1; uses_rs2_D = 1'b1;
            end

            // 11-15. LOAD (5 lệnh: LB, LH, LW, LBU, LHU)
            7'b0000011: begin
                regWrite_D = 1; imm_sel = 3'b000; alu_srcB_D = 1;
                alu_ctrl = ALU_ADD; load_sel_D = funct3; write_back_D = 2'b01;
                uses_rs1_D = 1'b1;
            end

            // 16-18. STORE (3 lệnh: SB, SH, SW)
            7'b0100011: begin
                memWrite_D = 1; imm_sel = 3'b001; alu_srcB_D = 1;
                alu_ctrl = ALU_ADD; store_sel_D = funct3;
                uses_rs1_D = 1'b1; uses_rs2_D = 1'b1;
            end

            // 19-27. I-Type ALU (9 lệnh: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            7'b0010011: begin
                regWrite_D = 1; alu_srcB_D = 1; imm_sel = 3'b000;
                uses_rs1_D = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = ALU_ADD;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                endcase
            end

            // 28-37. R-Type ALU (10 lệnh: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            7'b0110011: begin
                regWrite_D = 1; alu_srcB_D = 0;
                uses_rs1_D = 1'b1; uses_rs2_D = 1'b1;
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b001: alu_ctrl = ALU_SLL;
                    3'b010: alu_ctrl = ALU_SLT;
                    3'b011: alu_ctrl = ALU_SLTU;
                    3'b100: alu_ctrl = ALU_XOR;
                    3'b101: alu_ctrl = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110: alu_ctrl = ALU_OR;
                    3'b111: alu_ctrl = ALU_AND;
                endcase
            end
        endcase
    end
endmodule
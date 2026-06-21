module imm_extend (
    input wire [31:0] instr,      // Nhận toàn bộ lệnh 32-bit
    input wire [2:0]  imm_sel,    // Tín hiệu chọn từ Control Unit (3 bit)
    output reg [31:0] imm_ext     // Kết quả hằng số đã mở rộng 32-bit
  );

  always @(*)
  begin
    case (imm_sel)
      // I-type
      3'b000: imm_ext = {{20{instr[31]}}, instr[31:20]};
      // S-type
      3'b001: imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      // B-type:
      3'b010: imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
      // U-type:
      3'b011: imm_ext = {instr[31:12], 12'b0};
      // J-type:
      3'b100: imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
      default:
        imm_ext = 32'b0;
    endcase
  end

endmodule

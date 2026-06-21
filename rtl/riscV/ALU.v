module ALU (
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [10:0]  alu_ctrl, // 10 bit theo đồ án
    output reg [31:0] result,
    output wire       zero
);
    always @(*) begin
        case (alu_ctrl)
            11'b00000000001: result = a + b;                   // Bit 0: ADD
            11'b00000000010: result = a - b;                   // Bit 1: SUB
            11'b00000000100: result = a << b[4:0];             // Bit 2: SLL
            11'b00000001000: result = ($signed(a) < $signed(b)); // Bit 3: SLT
            11'b00000010000: result = (a < b);                 // Bit 4: SLTU
            11'b00000100000: result = a ^ b;                   // Bit 5: XOR
            11'b00001000000: result = a >> b[4:0];             // Bit 6: SRL
            11'b00010000000: result = $signed(a) >>> b[4:0];    // Bit 7: SRA
            11'b00100000000: result = a | b;                   // Bit 8: OR
            11'b01000000000: result = a & b;                   // Bit 9: AND
            11'b10000000000: result = b;                      // ALU_LUI: Lấy thẳng giá trị b (Imm)
            default: result = 32'b0;
        endcase
    end
    assign zero = (result == 32'b0);
endmodule
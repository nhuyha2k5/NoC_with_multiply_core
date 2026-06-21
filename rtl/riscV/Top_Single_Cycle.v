
// ... thêm các file khác nếu cần

module Top_Single_Cycle (
    input wire        clk,
    input wire        rst_n,
    input wire        start,

    // Cổng nạp chương trình từ bên ngoài (testbench)
    input wire        inst_we,
    input wire [31:0] inst_addr,
    input wire [31:0] inst_data,

    // Đầu ra debug
    output wire [31:0] pc,
    output wire [31:0] instr
);

    // --- Giao tiếp giữa các khối ---
    wire [31:0] imm_ext;
    wire [31:0] rd1;
    wire [31:0] rd2;
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_result;
    wire [31:0] mem_read_data;
    wire [31:0] wb_data;
    wire [31:0] pc_plus_4;
    wire [31:0] pc_branch;
    wire [31:0] pc_jalr;
    wire [31:0] pc_next;
    wire        zero;
    wire        stall = 1'b0; // Single-cycle không cần hazard stall

    wire        regWrite_D;
    wire [2:0]  imm_sel;
    wire        alu_srcA_D;
    wire        alu_srcB_D;
    wire [10:0]  alu_ctrl;
    wire        branch_D;
    wire [2:0]  bropcode;
    wire [1:0]  jump_D;
    wire [2:0]  load_sel_D;
    wire [2:0]  store_sel_D;
    wire        memWrite_D;
    wire [1:0]  write_back_D;

    // --- Program Counter ---
    Program_Counter pc_reg (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .stall(stall),
        .pc_next(pc_next),
        .pc_out(pc)
    );

    // --- Instruction Memory ---,
    instruction_memory instr_mem (
        .clk(clk),
        .rst_n(rst_n), 
        .we(inst_we),
        .addr_ext(inst_addr),
        .din_ext(inst_data),
        .pc(pc),
        .instr(instr)
    );

    // --- Control Unit ---
    control_unit cu (
        .opcode(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7(instr[31:25]),
        .regWrite_D(regWrite_D),
        .imm_sel(imm_sel),
        .alu_srcA_D(alu_srcA_D),
        .alu_srcB_D(alu_srcB_D),
        .alu_ctrl(alu_ctrl),
        .branch_D(branch_D),
        .bropcode(bropcode),
        .jump_D(jump_D),
        .load_sel_D(load_sel_D),
        .store_sel_D(store_sel_D),
        .memWrite_D(memWrite_D),
        .write_back_D(write_back_D)
    );

    // --- Immediate Extend ---
    imm_extend imm_gen (
        .instr(instr),
        .imm_sel(imm_sel),
        .imm_ext(imm_ext)
    );

    // --- Register File ---
    Register_File regfile (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write(regWrite_D),
        .rs1(instr[19:15]),
        .rs2(instr[24:20]),
        .rd(instr[11:7]),
        .wd(wb_data),
        .rd1(rd1),
        .rd2(rd2),
        .debug_addr(5'b0),
        .debug_val()
    );

    // --- ALU ---
    assign alu_a = (alu_srcA_D == 1'b1) ? pc : rd1;
    assign alu_b = (alu_srcB_D == 1'b1) ? imm_ext : rd2;

    ALU alu_unit (
        .a(alu_a),
        .b(alu_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(zero)
    );

    // --- Data Memory ---
    data_memory dmem (
        .clk(clk),
        .mem_write(memWrite_D),
        .addr(alu_result),
        .write_data(rd2),
        .load_sel(load_sel_D),
        .store_sel(store_sel_D),
        .read_data(mem_read_data),
        .debug_addr(10'b0),
        .debug_val()
    );

    // --- Write-back ---
    assign wb_data = (write_back_D == 2'b00) ? alu_result :
                     (write_back_D == 2'b01) ? mem_read_data :
                     (write_back_D == 2'b10) ? pc_plus_4 :
                     32'b0;

    // --- Compute next PC ---
    assign pc_plus_4 = pc + 32'd4;
    assign pc_branch = pc + imm_ext;
    assign pc_jalr   = alu_result; // ALU computes rs1 + imm cho JALR

    wire equal         = (rd1 == rd2);
    wire less_signed   = ($signed(rd1) < $signed(rd2));
    wire less_unsigned = (rd1 < rd2);

    wire branch_taken = branch_D && (
        (bropcode == 3'b000 && equal)       || // BEQ
        (bropcode == 3'b001 && !equal)      || // BNE
        (bropcode == 3'b100 && less_signed) || // BLT
        (bropcode == 3'b101 && !less_signed) || // BGE
        (bropcode == 3'b110 && less_unsigned) || // BLTU
        (bropcode == 3'b111 && !less_unsigned)   // BGEU
    );

    assign pc_next = (jump_D == 2'b01) ? pc_branch :
                     (jump_D == 2'b10) ? pc_jalr   :
                     (branch_taken)      ? pc_branch :
                     pc_plus_4;

endmodule
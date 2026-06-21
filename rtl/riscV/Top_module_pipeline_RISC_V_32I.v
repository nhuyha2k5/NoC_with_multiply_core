module Top_module_pipeline_RISC_V_32I (
    input wire        clk,
    input wire        rst_n,
    input wire        start,
    input wire        DataOrReg,
    input wire [31:0] check_address,
    output wire [31:0] value,
    input wire [31:0] instruction,
    input wire [31:0] address
);
    // =========================
    // IF stage
    // =========================
    wire [31:0] pc_F;
    wire [31:0] pc4_F;
    wire [31:0] instr_F;
    wire [31:0] predicted_pc_next_F;
    wire [31:0] pc_restore_E;
    wire        pred_taken_F;
    wire        bpu_flush_E;

    wire        stall_pc_hazard;
    wire        stall_if_id_hazard;
    wire        flush_id_ex_hazard;
    wire        flush_if_id_hazard;

    wire [31:0] pc_next_F = bpu_flush_E ? pc_restore_E : predicted_pc_next_F;
    wire        stall_pc_total = stall_pc_hazard | (~start);
    wire        stall_if_id_total = stall_if_id_hazard | (~start);
    wire        flush_if_id_total = flush_if_id_hazard | bpu_flush_E;
    wire        flush_id_ex_total = flush_id_ex_hazard | bpu_flush_E;
    wire        stall_id_ex_total = ~start;

    assign pc4_F = pc_F + 32'd4;

    Program_Counter pc_reg (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .stall(stall_pc_total),
        .pc_next(pc_next_F),
        .pc_out(pc_F)
    );

    instruction_memory imem (
        .clk(clk),
        .rst_n(rst_n),
        .we(~start),
        .addr_ext(address),
        .din_ext(instruction),
        .pc(pc_F),
        .instr(instr_F)
    );

    // =========================
    // IF/ID register
    // =========================
    wire [31:0] pc_D;
    wire [31:0] pc4_D;
    wire [31:0] instr_D;

    IF_ID if_id_reg (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_if_id_total),
        .flush(flush_if_id_total),
        .if_pc(pc_F),
        .if_pc_plus4(pc4_F),
        .if_instr(instr_F),
        .id_pc(pc_D),
        .id_pc_plus4(pc4_D),
        .id_instr(instr_D)
    );

    // =========================
    // ID stage
    // =========================
    wire [31:0] rs1_data_D;
    wire [31:0] rs2_data_D;
    wire [31:0] imm_D;

    wire        regWrite_D;
    wire [2:0]  imm_sel_D;
    wire        alu_srcA_D;
    wire        alu_srcB_D;
    wire [10:0] alu_ctrl_D;
    wire        branch_D;
    wire [2:0]  bropcode_D;
    wire [1:0]  jump_D;
    wire [2:0]  load_sel_D;
    wire [2:0]  store_sel_D;
    wire        memWrite_D;
    wire [1:0]  write_back_D;
    wire        uses_rs1_D;
    wire        uses_rs2_D;

    wire [31:0] wb_data;
    wire [31:0] regfile_debug_val;
    wire        wb_regWrite;
    wire [4:0]  wb_rd;

    control_unit cu (
        .opcode(instr_D[6:0]),
        .funct3(instr_D[14:12]),
        .funct7(instr_D[31:25]),
        .regWrite_D(regWrite_D),
        .imm_sel(imm_sel_D),
        .alu_srcA_D(alu_srcA_D),
        .alu_srcB_D(alu_srcB_D),
        .alu_ctrl(alu_ctrl_D),
        .branch_D(branch_D),
        .bropcode(bropcode_D),
        .jump_D(jump_D),
        .load_sel_D(load_sel_D),
        .store_sel_D(store_sel_D),
        .memWrite_D(memWrite_D),
        .write_back_D(write_back_D),
        .uses_rs1_D(uses_rs1_D),
        .uses_rs2_D(uses_rs2_D)
    );

    imm_extend imm_gen (
        .instr(instr_D),
        .imm_sel(imm_sel_D),
        .imm_ext(imm_D)
    );

    Register_File regfile (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write(wb_regWrite),
        .rs1(instr_D[19:15]),
        .rs2(instr_D[24:20]),
        .rd(wb_rd),
        .wd(wb_data),
        .rd1(rs1_data_D),
        .rd2(rs2_data_D),
        .debug_addr(check_address[4:0]),
        .debug_val(regfile_debug_val)
    );

    // =========================
    // ID/EX register
    // =========================
    wire [31:0] pc_E;
    wire [31:0] pc4_E;
    wire [31:0] rs1_data_E;
    wire [31:0] rs2_data_E;
    wire [31:0] imm_E;
    wire [4:0]  rd_E;
    wire [4:0]  rs1_E;
    wire [4:0]  rs2_E;
    wire        regWrite_E;
    wire [2:0]  imm_sel_E;
    wire        alu_srcA_E;
    wire        alu_srcB_E;
    wire [10:0] alu_ctrl_E;
    wire        branch_E;
    wire [2:0]  bropcode_E;
    wire [1:0]  jump_E;
    wire [2:0]  load_sel_E;
    wire [2:0]  store_sel_E;
    wire        memWrite_E;
    wire [1:0]  write_back_E;
    ID_EX id_ex_reg (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_id_ex_total),
        .flush(flush_id_ex_total),
        .id_pc(pc_D),
        .id_pc_plus4(pc4_D),
        .id_rs1_data(rs1_data_D),
        .id_rs2_data(rs2_data_D),
        .id_imm(imm_D),
        .id_rd(instr_D[11:7]),
        .id_rs1(instr_D[19:15]),
        .id_rs2(instr_D[24:20]),
        .id_regWrite(regWrite_D),
        .id_imm_sel(imm_sel_D),
        .id_alu_srcA(alu_srcA_D),
        .id_alu_srcB(alu_srcB_D),
        .id_alu_ctrl(alu_ctrl_D),
        .id_branch(branch_D),
        .id_bropcode(bropcode_D),
        .id_jump(jump_D),
        .id_load_sel(load_sel_D),
        .id_store_sel(store_sel_D),
        .id_memWrite(memWrite_D),
        .id_write_back(write_back_D),
        .ex_pc(pc_E),
        .ex_pc_plus4(pc4_E),
        .ex_rs1_data(rs1_data_E),
        .ex_rs2_data(rs2_data_E),
        .ex_imm(imm_E),
        .ex_rd(rd_E),
        .ex_rs1(rs1_E),
        .ex_rs2(rs2_E),
        .ex_regWrite(regWrite_E),
        .ex_imm_sel(imm_sel_E),
        .ex_alu_srcA(alu_srcA_E),
        .ex_alu_srcB(alu_srcB_E),
        .ex_alu_ctrl(alu_ctrl_E),
        .ex_branch(branch_E),
        .ex_bropcode(bropcode_E),
        .ex_jump(jump_E),
        .ex_load_sel(load_sel_E),
        .ex_store_sel(store_sel_E),
        .ex_memWrite(memWrite_E),
        .ex_write_back(write_back_E)
    );

    // =========================
    // EX stage + forwarding
    // =========================
    wire [1:0] forwardA;
    wire [1:0] forwardB;

    wire [31:0] mem_alu_result_M;
    wire [4:0]  mem_rd_M;
    wire        mem_regWrite_M;
    wire [31:0] mem_read_data_M;
    wire [31:0] pc4_M;
    wire [1:0]  write_back_M;
    wire [31:0] dmem_debug_val;

    wire [31:0] mem_forward_data_M = (write_back_M == 2'b00) ? mem_alu_result_M :
                                     (write_back_M == 2'b01) ? mem_read_data_M :
                                     (write_back_M == 2'b10) ? pc4_M :
                                     32'b0;

    Forwarding_Unit fwd_unit (
        .id_ex_rs1(rs1_E),
        .id_ex_rs2(rs2_E),
        .ex_mem_rd(mem_rd_M),
        .ex_mem_regWrite(mem_regWrite_M),
        .mem_wb_rd(wb_rd),
        .mem_wb_regWrite(wb_regWrite),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    wire [31:0] ex_rs1_fwd = (forwardA == 2'b01) ? mem_forward_data_M :
                             (forwardA == 2'b10) ? wb_data :
                             rs1_data_E;
    wire [31:0] ex_rs2_fwd = (forwardB == 2'b01) ? mem_forward_data_M :
                             (forwardB == 2'b10) ? wb_data :
                             rs2_data_E;

    wire [31:0] alu_a_E = alu_srcA_E ? pc_E : ex_rs1_fwd;
    wire [31:0] alu_b_E = alu_srcB_E ? imm_E : ex_rs2_fwd;
    wire [31:0] alu_result_E;
    ALU alu (
        .a(alu_a_E),
        .b(alu_b_E),
        .alu_ctrl(alu_ctrl_E),
        .result(alu_result_E),
        .zero()
    );

    wire equal_E         = (ex_rs1_fwd == ex_rs2_fwd);
    wire less_signed_E   = ($signed(ex_rs1_fwd) < $signed(ex_rs2_fwd));
    wire less_unsigned_E = (ex_rs1_fwd < ex_rs2_fwd);

    wire branch_taken_E = branch_E && (
        (bropcode_E == 3'b000 && equal_E)         ||
        (bropcode_E == 3'b001 && !equal_E)        ||
        (bropcode_E == 3'b100 && less_signed_E)   ||
        (bropcode_E == 3'b101 && !less_signed_E)  ||
        (bropcode_E == 3'b110 && less_unsigned_E) ||
        (bropcode_E == 3'b111 && !less_unsigned_E)
    );

    wire is_jump_E = (jump_E != 2'b00);
    wire [31:0] jump_target_E = (jump_E == 2'b10) ? {alu_result_E[31:1], 1'b0} : (pc_E + imm_E);
    wire [31:0] pc_target_E = is_jump_E ? jump_target_E : (pc_E + imm_E);

    // =========================
    // Branch Prediction Unit
    // =========================
    Branch_Prediction_Unit bpu (
        .clk(clk),
        .rst_n(rst_n),
        .branch_E(branch_E),
        .jump_E(is_jump_E),
        .branch(branch_taken_E),
        .pc_F(pc_F),
        .pc_D(pc_D),
        .pc_E(pc_E),
        .pc_target(pc_target_E),
        .pc_next(predicted_pc_next_F),
        .pc_restore(pc_restore_E),
        .flush(bpu_flush_E),
        .taken_F(pred_taken_F)
    );

    Hazard_Unit hazard_unit (
        .if_id_rs1(instr_D[19:15]),
        .if_id_rs2(instr_D[24:20]),
        .if_id_uses_rs1(uses_rs1_D),
        .if_id_uses_rs2(uses_rs2_D),
        .id_ex_rd(rd_E),
        .id_ex_wb_sel(write_back_E),
        .branch_mispredicted(bpu_flush_E),
        .stall_pc(stall_pc_hazard),
        .stall_if_id(stall_if_id_hazard),
        .flush_id_ex(flush_id_ex_hazard),
        .flush_if_id(flush_if_id_hazard)
    );

    // =========================
    // EX/MEM register
    // =========================
    wire [31:0] rs2_data_M;
    wire [2:0]  load_sel_M;
    wire [2:0]  store_sel_M;
    wire        memWrite_M;

    EX_MEM ex_mem_reg (
        .clk(clk),
        .rst_n(rst_n),
        .flush(1'b0),
        .ex_pc_plus4(pc4_E),
        .ex_alu_result(alu_result_E),
        .ex_rs2_data(ex_rs2_fwd),
        .ex_rd(rd_E),
        .ex_regWrite(regWrite_E),
        .ex_load_sel(load_sel_E),
        .ex_store_sel(store_sel_E),
        .ex_memWrite(memWrite_E),
        .ex_write_back(write_back_E),
        .mem_pc_plus4(pc4_M),
        .mem_alu_result(mem_alu_result_M),
        .mem_rs2_data(rs2_data_M),
        .mem_rd(mem_rd_M),
        .mem_regWrite(mem_regWrite_M),
        .mem_load_sel(load_sel_M),
        .mem_store_sel(store_sel_M),
        .mem_memWrite(memWrite_M),
        .mem_write_back(write_back_M)
    );

    // =========================
    // MEM stage + MEM/WB
    // =========================
    data_memory dmem (
        .clk(clk),
        .mem_write(memWrite_M),
        .addr(mem_alu_result_M),
        .write_data(rs2_data_M),
        .load_sel(load_sel_M),
        .store_sel(store_sel_M),
        .read_data(mem_read_data_M),
        .debug_addr(check_address[11:2]),
        .debug_val(dmem_debug_val)
    );

    wire [31:0] pc4_W;
    wire [31:0] alu_result_W;
    wire [31:0] mem_data_W;
    wire [1:0]  write_back_W;

    MEM_WB mem_wb_reg (
        .clk(clk),
        .rst_n(rst_n),
        .mem_pc_plus4(pc4_M),
        .mem_alu_result(mem_alu_result_M),
        .mem_mem_data(mem_read_data_M),
        .mem_rd(mem_rd_M),
        .mem_regWrite(mem_regWrite_M),
        .mem_write_back(write_back_M),
        .wb_pc_plus4(pc4_W),
        .wb_alu_result(alu_result_W),
        .wb_mem_data(mem_data_W),
        .wb_rd(wb_rd),
        .wb_regWrite(wb_regWrite),
        .wb_write_back(write_back_W)
    );

    assign wb_data = (write_back_W == 2'b00) ? alu_result_W :
                     (write_back_W == 2'b01) ? mem_data_W :
                     (write_back_W == 2'b10) ? pc4_W :
                     32'b0;

   
    assign value = DataOrReg ? dmem_debug_val : regfile_debug_val;
endmodule

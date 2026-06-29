`timescale 1ns/1ps

module tb_master_slave_direct;
    logic clk;
    logic rst_n;
    wire [31:0] pc_00;

    // =======================================================
    // DÂY NỐI TRỰC TIẾP MASTER (Cổng East) <-> SLAVE (Cổng West)
    // =======================================================
    wire [33:0] link_m2s_flit;
    wire        link_m2s_valid;
    wire        link_s2m_credit;

    wire [33:0] link_s2m_flit;
    wire        link_s2m_valid;
    wire        link_m2s_credit;

    // Dây giám sát xem Master có gửi nhầm cổng khác không
    wire m_valid_n, m_valid_s, m_valid_w;
    wire [33:0] m_flit_n, m_flit_s, m_flit_w;

    // =======================================================
    // 1. KHỞI TẠO MASTER TẠI TỌA ĐỘ (0,0)
    // =======================================================
    master_node #(
        .DATA_WIDTH(34), .CURRENT_X(2'd0), .CURRENT_Y(2'd0),
        .ROM_FILE("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master0.hex") 
    ) u_master (
        .clk(clk), .rst_n(rst_n),
        .debug_pc(pc_00), .debug_alu(),
        
        // Khóa các cổng không dùng (Ép valid = 0, credit = 0 để an toàn)
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(1'b0),
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(1'b0),
        .w_flit_in('0), .w_valid_in(1'b0), .w_credit_in(1'b0),
        
        // Bắt tín hiệu ngõ ra của các cổng này để debug
        .n_flit_out(m_flit_n), .n_valid_out(m_valid_n), .n_credit_out(),
        .s_flit_out(m_flit_s), .s_valid_out(m_valid_s), .s_credit_out(),
        .w_flit_out(m_flit_w), .w_valid_out(m_valid_w), .w_credit_out(),

        // CỔNG EAST: Nối dây xuất dữ liệu sang cổng WEST của Slave
        .e_flit_out(link_m2s_flit), .e_valid_out(link_m2s_valid), .e_credit_in(link_s2m_credit),
        .e_flit_in(link_s2m_flit),  .e_valid_in(link_s2m_valid),  .e_credit_out(link_m2s_credit)
    );

    // =======================================================
    // 2. KHỞI TẠO SLAVE TẠI TỌA ĐỘ (1,1)
    // =======================================================
    slave_node #(
        .DATA_WIDTH(34), .CURRENT_X(2'd1), .CURRENT_Y(2'd1), .MEM_DEPTH(1024)
    ) u_slave (
        .clk(clk), .rst_n(rst_n),
        
        // Khóa các cổng không dùng
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(1'b0),
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(1'b0),
        .e_flit_in('0), .e_valid_in(1'b0), .e_credit_in(1'b0),
        
        // CỔNG WEST: Nối dây nhận dữ liệu từ cổng EAST của Master
        .w_flit_in(link_m2s_flit),  .w_valid_in(link_m2s_valid),  .w_credit_out(link_s2m_credit),
        .w_flit_out(link_s2m_flit), .w_valid_out(link_s2m_valid), .w_credit_in(link_m2s_credit)
    );

    // Xung nhịp 50MHz
    always #10 clk = ~clk;

    // =======================================================
    // KHỞI ĐỘNG HỆ THỐNG
    // =======================================================
    initial begin
        clk = 0;
        rst_n = 0;
        #105;      // Đổi thành 105ns để tránh lỗi trùng sườn xung nhịp (Race condition)
        rst_n = 1; 

        $display("\n=======================================================");
        $display("   [UNIT TEST] Ket noi truc tiep Master(0,0) -> Slave(1,1)");
        $display("=======================================================");
    end

    // ---------------------------------------------------------
    // THEO DÕI MASTER GỬI & SLAVE NHẬN
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if ($time < 500) begin
                $display("Time: %0t ns | PC_00: %h", $time, pc_00);
            end

            // NẾU ROUTER ĐẨY ĐÚNG CỔNG EAST
            if (link_m2s_valid) begin
                $display("\n[%0t ns] 🚀 [MASTER_EAST] Ban Flit dung tuyen! Payload: 0x%h", $time, link_m2s_flit[31:0]);
            end
            
            // NẾU ROUTER ĐẨY NHẦM SANG CỔNG SOUTH (Phát hiện thuật toán Y-X)
            if (m_valid_s) begin
                $display("\n[%0t ns] ❌ [LỖI ĐỊNH TUYẾN] Router day goi tin sang cong SOUTH (Nam) thay vi EAST (Dong)! Payload: 0x%h", $time, m_flit_s[31:0]);
            end

            if (u_slave.u_slave_ni.rx_valid) begin
                $display("[%0t ns] 🏁 [SLAVE_CORE] Da luu Flit vao RAM! Payload: 0x%h", $time, u_slave.u_slave_ni.rx_flit[31:0]);
            end
        end
    end

    // ---------------------------------------------------------
    // KẾT THÚC VÀ ĐỌC RAM
    // ---------------------------------------------------------
    initial begin
        #50000; 
        
        $display("\n=======================================================");
        $display("   KIEM TRA DU LIEU TRONG RAM CUA SLAVE");
        
        // CHÚ Ý: BẠN PHẢI SỬA CHỮ "mem" Ở DƯỚI ĐÂY THÀNH TÊN MẢNG RAM THỰC TẾ TRONG CODE CỦA BẠN
        // Ví dụ: u_slave_ni.u_local_data_ram.mem[0]
        // Nếu không ModelSim sẽ báo lỗi Fatal ngay khi bấm chạy.
        $display("RAM[0]  = 0x%h", u_slave.u_slave_ni.memory[0]);
        $display("RAM[64] = 0x%h", u_slave.u_slave_ni.memory[64]); 
        
        $display("=======================================================\n");
        $stop;
    end
endmodule
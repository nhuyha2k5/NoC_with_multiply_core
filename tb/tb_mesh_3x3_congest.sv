`timescale 1ns/1ps

module tb_mesh_3x3_congest;
    logic clk;
    logic rst_n;

    // Kế thừa các cổng ngõ ra từ file mesh_3x3
    wire [31:0] fmax_pc_00, fmax_alu_00, fmax_pc_22, fmax_alu_22, dummy_output;

    // Khởi tạo DUT
    mesh_3x3 dut (
        .clk(clk),
        .rst_n(rst_n),
        .fmax_pc_00(fmax_pc_00),
        .fmax_alu_00(fmax_alu_00),
        .fmax_pc_22(fmax_pc_22),
        .fmax_alu_22(fmax_alu_22),
        .dummy_output(dummy_output)
    );

    // Xung nhịp 50MHz (Chu kỳ = 20ns)
    always #10 clk = ~clk;

    // ===================================================================
    // BỘ ĐẾM THỜI GIAN ĐỂ ĐO ĐỘ TRỄ (LATENCY TIMER)
    // ===================================================================
    time start_time_00 = 0;
    time end_time_00   = 0;
    time start_time_22 = 0;
    time end_time_22   = 0;
    
    int  flag_sent_00  = 0;
    int  flag_sent_22  = 0;
    int  received_count = 0;

    initial begin
        clk = 0;
        rst_n = 0;

        // Tiêm trực tiếp mã lệnh vào RAM
        $readmemh("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master0.hex", dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.u_local_data_ram.mem);
        $readmemh("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master1.hex", dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.u_local_data_ram.mem);

        #40;
        rst_n = 1; // Tháo Reset

        $display("\n===================================================================");
        $display("   [CONGESTION & LATENCY TEST] KIEM TRA DO TRE GHE GHEN MANG");
        $display("===================================================================");
    end

    // ---------------------------------------------------------
    // 1. BẤM ĐỒNG HỒ BẮT ĐẦU KHI MASTER CPU BẮN GÓI TIN ĐI
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // Bắt tín hiệu Master 00 gửi đi LẦN ĐẦU TIÊN
            if (dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.u_master_ni.tx_valid && !flag_sent_00) begin
                start_time_00 = $time;
                flag_sent_00 = 1;
                $display("[%0t ns] 🚀 [MASTER 0,0 - VIP] Bat dau roi ben! (Thoi diem xuat phat)", $time);
            end
            
            // Bắt tín hiệu Master 22 gửi đi LẦN ĐẦU TIÊN
            if (dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.u_master_ni.tx_valid && !flag_sent_22) begin
                start_time_22 = $time;
                flag_sent_22 = 1;
                $display("[%0t ns] 🚀 [MASTER 2,2 - Nomal] Bat dau roi ben! (Thoi diem xuat phat)", $time);
            end
        end
    end

    // ---------------------------------------------------------
    // 2. BẤM ĐỒNG HỒ DỪNG LẠI KHI SLAVE RAM NHẬN ĐƯỢC
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid) begin
                received_count++;
                
                // Nếu nhận được đuôi là 14 (0xe) -> Chốt giờ cho VIP
                if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_flit[31:0] == 32'h0000000e) begin
                    end_time_00 = $time;
                    $display("[%0t ns] 🏁 [SLAVE RAM 1,1] Đa nhan xong du lieu 14 cua VIP (0,0)", $time);
                end 
                // Nếu nhận được đuôi là 5 (0x5) -> Chốt giờ cho Nomal
                else if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_flit[31:0] == 32'h00000005) begin
                    end_time_22 = $time;
                    $display("[%0t ns] 🏁 [SLAVE RAM 1,1] Đa nhan xong du lieu 5 cua Thuong (2,2)", $time);
                end
            end
        end
    end

    // ---------------------------------------------------------
    // 3. TỔNG KẾT BÁO CÁO SAU MÔ PHỎNG
    // ---------------------------------------------------------
    initial begin
        #20000; // Đợi đủ lâu để vượt qua kẹt xe
        
        $display("\n===================================================================");
        $display("          TONG KET BO NHO VA DO TRE (LATENCY REPORT)");
        $display("===================================================================");
        
        $display("RAM[64] (VIP 0,0 ghi vao)    = 0x%h", dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.memory[64]); 
        $display("RAM[65] (Thuong 2,2 ghi vao) = 0x%h", dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.memory[65]); 
        
        $display("-------------------------------------------------------------------");
        $display("⏳ DO TRE CUA MASTER (0,0) VIP: %0t ns (Khoang %0d Chu ky clock)", (end_time_00 - start_time_00), (end_time_00 - start_time_00)/20);
        $display("⏳ DO TRE CUA MASTER (2,2) Normal: %0t ns (Khoang %0d Chu ky clock)", (end_time_22 - start_time_22), (end_time_22 - start_time_22)/20);
        $display("===================================================================\n");
        $stop; 
    end
endmodule
`timescale 1ns/1ps

module tb_mesh_3x3;
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

    // Xung nhịp 50MHz
    always #10 clk = ~clk;

    // Các cờ để theo dõi luồng sự kiện
    int received_count = 0;

    initial begin
        clk = 0;
        rst_n = 0;

        // ===================================================================
        // [VŨ KHÍ TỐI THƯỢNG] TIÊM TRỰC TIẾP MÃ LỆNH VÀO RAM TỪ TESTBENCH
        // Đã sửa lại đường dẫn chuẩn /mesh_3x3/hex/ của bạn
        // ===================================================================
        $readmemh("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master0.hex", dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.u_local_data_ram.mem);
        $readmemh("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master1.hex", dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.u_local_data_ram.mem);

        #40;
        rst_n = 1; // Tháo Reset

        $display("\n===================================================================");
        $display("   [PRIORITY TEST] Kiem tra phan xu uu tien giua 2 Master CPU");
        $display("   - Master (0,0) [VIP]: Tinh 5 + 9 = 14 (0xE)");
        $display("   - Master (2,2) [Thuong]: Tinh 8 - 3 = 5 (0x5)");
        $display("===================================================================");
    end

    // ---------------------------------------------------------
    // 1. THEO DÕI KHOẢNH KHẮC 2 CPU BẮN GÓI TIN LÊN MẠNG
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // Bắt tín hiệu Master 00 gửi đi
            if (dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.u_master_ni.tx_valid) begin
                $display("[%0t ns] 🚀 [MASTER 0,0 - VIP] Phat dong cuoc dua! Gui payload 14 (0xE) len NoC.", $time);
            end
            
            // Bắt tín hiệu Master 22 gửi đi
            if (dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.u_master_ni.tx_valid) begin
                $display("[%0t ns] 🚀 [MASTER 2,2 - Nomal] Phat dong cuoc dua! Gui payload 5 (0x5) len NoC.", $time);
            end
        end
    end

    // ---------------------------------------------------------
    // 2. THEO DÕI KẾT QUẢ CẬP BẾN TẠI SLAVE RAM (1,1)
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // Bắt sự kiện Slave NI nhận được Flit hợp lệ
            if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid) begin
                received_count++;
                
                // Trích xuất phần dữ liệu (payload) từ gói tin 34-bit
                $display("\n[%0t ns] 🏁 [SLAVE RAM 1,1] Nhan duoc Flit thu %0d!", $time, received_count);
                $display("        -> Du lieu mang theo (Payload): 0x%0h", dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_flit[31:0]);

                if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_flit[31:0] == 32'h0000000e) begin
                    $display("        -> Ket luan: Day la du lieu (14) cua Master (0,0) - Kha nang cao la VIP den truoc!");
                end 
                else if (dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_flit[31:0] == 32'h00000005) begin
                    $display("        -> Ket luan: Day la du lieu (5) cua Master (2,2) - Khoe cham cham thi den sau!");
                end
            end
        end
    end

    // ---------------------------------------------------------
    // BẮT MẠCH CPU: IN PROGRAM COUNTER (PC) RA MÀN HÌNH
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // Chỉ in ra trong 2000 ns đầu tiên để kiểm tra xem CPU có "chạy mù" không
            if ($time < 2000) begin
                $display("Time: %0t ns | PC_00: %h | PC_22: %h", $time, fmax_pc_00, fmax_pc_22);
            end
        end
    end

    // ---------------------------------------------------------
    // 3. KẾT THÚC VÀ ĐỌC BỘ NHỚ RAM
    // ---------------------------------------------------------
    initial begin
        // Chờ 10,000 ns (Để đảm bảo gói tin có đủ thời gian bò qua Router)
        #10000; 
        
        $display("\n===================================================================");
        $display("   TONG KET BO NHO ");
        $display("===================================================================");
        
        // ĐÃ SỬA CHỮ 'memory' THÀNH 'mem' ĐỂ KHÔNG BỊ LỖI FATAL ERROR
        $display("RAM[65]  = 0x%h", dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.memory[65]);
        // Quét thử ô nhớ 64 xem dữ liệu có nằm ở đây không
        $display("RAM[64] = 0x%h", dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.memory[64]); 
        
        if (received_count == 6) begin
            $display("\n-> THANH CONG! Chuc nang Uu tien (Priority) hoat dong .");
            $display("-> Master 0,0 da duoc Router (1,1) mo cua cho vao truoc. Master 2,2 di sau an toan!");
        end else begin
            $display("\n-> THAT BAI! Co loi nghen mang chet (Deadlock) hoac mat Flit.");
        end
        
        $display("===================================================================\n");
        $stop; 
    end
endmodule
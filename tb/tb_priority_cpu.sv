`timescale 1ns/1ps

module tb_priority_cpu;
    logic clk, rst_n;
    wire [31:0] fmax_pc_00, fmax_alu_00, fmax_pc_22, fmax_alu_22, dummy_output;

    mesh_3x3 dut (
        .clk(clk),
        .rst_n(rst_n),
        .fmax_pc_00(fmax_pc_00),
        .fmax_alu_00(fmax_alu_00),
        .fmax_pc_22(fmax_pc_22),
        .fmax_alu_22(fmax_alu_22),
        .dummy_output(dummy_output)
    );

    always #10 clk = ~clk;

    // Biến trạng thái
    int pc_00_changed = 0;
    int pc_22_changed = 0;
    int mem_req_00 = 0;
    int mem_req_22 = 0;

    initial begin
        clk = 0; rst_n = 0;
        #40; rst_n = 1;
        $display("=== DEBUG: TEST PRIORITY (CPU MASTER) ===");
        $display("Node 00: PRIORITY=1, Node 22: PRIORITY=0");

        // 1. Chờ 100 chu kỳ cho CPU khởi động
        repeat(100) @(posedge clk);

        // 2. Kiểm tra PC của CPU node 00 và 22
        if (dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.debug_pc != 32'h0) begin
            $display("[OK] Node 00 PC da thay doi: %h", dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.debug_pc);
            pc_00_changed = 1;
        end else begin
            $display("[LOI] Node 00 PC van la 0 -> CPU khong chay!");
        end

        if (dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.debug_pc != 32'h0) begin
            $display("[OK] Node 22 PC da thay doi: %h", dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.debug_pc);
            pc_22_changed = 1;
        end else begin
            $display("[LOI] Node 22 PC van la 0 -> CPU khong chay!");
        end

        // Nếu CPU không chạy → dừng ngay
        if (!pc_00_changed || !pc_22_changed) begin
            $display("=== DUNG MO PHONG: CPU KHONG HOAT DONG ===");
            $display("Kiem tra file .hex hoac reset.");
            $finish;
        end

        // 3. Chờ CPU phát ra mem_req_o (yêu cầu truy xuất bộ nhớ)
        fork
            begin : wait_req_00
                wait (dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.mem_req_o == 1'b1);
                $display("[OK] Node 00 phat ra mem_req_o vao: %0t ns", $realtime);
                mem_req_00 = 1;
            end
            begin : wait_req_22
                wait (dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.mem_req_o == 1'b1);
                $display("[OK] Node 22 phat ra mem_req_o vao: %0t ns", $realtime);
                mem_req_22 = 1;
            end
        join

        // 4. Chờ Master NI tạo flit (tx_valid)
        fork
            begin : wait_tx_00
                @(posedge dut.MESH_X[0].MESH_Y[0].NODE_CPU_00.u_master0.u_master_ni.tx_valid);
                $display("[OK] Node 00 master_ni tx_valid len cao vao: %0t ns", $realtime);
            end
            begin : wait_tx_22
                @(posedge dut.MESH_X[2].MESH_Y[2].NODE_CPU_22.u_master1.u_master_ni.tx_valid);
                $display("[OK] Node 22 master_ni tx_valid len cao vao: %0t ns", $realtime);
            end
        join

        // 5. Chờ Slave nhận gói (rx_valid) – timeout 500us
        fork
            begin : wait_rx
                @(posedge dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid);
                $display("[OK] Slave nhan goi thu nhat vao: %0t ns", $realtime);
            end
            begin : timeout_rx
                #500000; // 500 us
                $display("[LOI] Khong nhan duoc goi nao tu CPU sau 500 us!");
                $finish;
            end
        join

        // Nếu đã nhận được gói, kết thúc mô phỏng
        $display("=== DA NHAN DUOC GOI, KET THUC MO PHONG ===");
        #200;
        $finish;
    end
endmodule
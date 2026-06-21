`timescale 1ns/1ps

module tb_mesh_3x3_latency;
    logic clk;
    logic rst_n;

    // Các cổng ngõ ra từ mesh_3x3
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

    // Tạo xung nhịp 50 MHz (chu kỳ 20 ns)
    always #10 clk = ~clk;

    // Biến đo thời gian
    realtime send_time, receive_time, latency_ns;

    initial begin
        clk = 0;
        rst_n = 0;
        #40;
        rst_n = 1; // Kích hoạt reset

        $display("[LATENCY TEST] Bắt đầu kiểm tra độ trễ truyền dẫn...");
        $display("Nguồn gửi: TG tại node (0,1)");
        $display("Đích nhận: Slave RAM tại node (1,1)");

        // Chờ một vài chu kỳ để hệ thống ổn định sau reset
        repeat(10) @(posedge clk);

        // =========================================================
        // Đo latency cho gói tin đầu tiên từ TG (0,1) đến Slave (1,1)
        // =========================================================
        fork
            begin
                // Chờ cạnh lên của tx_valid từ Master NI của TG (0,1)
                // Đường dẫn: dut.MESH_X[0].MESH_Y[1].NODE_TG.u_tg.u_master_ni.tx_valid
                @(posedge dut.MESH_X[0].MESH_Y[1].NODE_TG.u_tg.u_master_ni.tx_valid);
                send_time = $realtime;
                $display("[SOURCE TG(0,1)] TX_VALID lên mức cao lúc: %0t ns", send_time);
            end

            begin
                // Chờ cạnh lên của rx_valid từ Slave NI của Slave (1,1)
                // Đường dẫn: dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid
                @(posedge dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid);
                receive_time = $realtime;
                $display("[DEST SLAVE(1,1)] RX_VALID lên mức cao lúc: %0t ns", receive_time);
            end
        join

        // Tính toán độ trễ
        latency_ns = receive_time - send_time;
        $display("=================================================");
        $display(" KẾT QUẢ ĐO ĐỘ TRỄ (LATENCY): %0f ns", latency_ns);
        $display(" Tương đương khoảng: %0d chu kỳ xung nhịp (20 ns)", latency_ns / 20);
        $display("=================================================");

        // Chờ một chút rồi kết thúc mô phỏng
        #200;
        $finish;
    end
endmodule
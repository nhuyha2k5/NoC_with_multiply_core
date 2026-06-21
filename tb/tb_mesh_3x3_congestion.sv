timescale 1ns/1ps

module tb_mesh_3x3_congestion;
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

    always #10 clk = ~clk; // 50 MHz

    realtime send_time[0:19], receive_time[0:19];
    int send_idx = 0, rcv_idx = 0;
    int packet_to_capture = 20;

    initial begin
        clk = 0; rst_n = 0;
        #40; rst_n = 1;
        $display("=== BAT DAU TEST NGHEN MANG ===");
        
        // 1. Cho mang chay on dinh 100ns
        #100;

        // 2. EP NGHEN TRONG 200ns (Mo phong FIFO day)
        $display(">>> Bat dau ep credit_ok = 0 trong 200ns (Nghen xay ra)");
        force dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_router.out_L.credit_ok = 1'b0;
        #200; // Giu nghen trong 200ns

        // 3. THA NGHEN (Release) - Quan trong nhat de khong bi Deadlock
        release dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_router.out_L.credit_ok;
        $display(">>> Da release credit_ok. Luong luu thong duoc noi lai.");
        
        // 4. Tiep tuc cho 100ns de duong duoc khai thong
        #100;

        // 5. BAT DAU DO LATENCY BINH THUONG
        $display("--- Bat dau do latency sau khi da het nghen ---");
        fork : send_process
            forever @(posedge dut.MESH_X[0].MESH_Y[1].NODE_TG.u_tg.u_master_ni.tx_valid) begin
                if (send_idx < packet_to_capture) begin
                    send_time[send_idx] = $realtime;
                    send_idx++;
                end
            end
        join_none

        fork : receive_process
            forever @(posedge dut.MESH_X[1].MESH_Y[1].NODE_RAM_11.u_slave.u_slave_ni.rx_valid) begin
                if (rcv_idx < packet_to_capture) begin
                    receive_time[rcv_idx] = $realtime;
                    rcv_idx++;
                end
            end
        join_none

        // Cho den khi nhan du 20 goi
        wait (rcv_idx >= packet_to_capture);
        disable send_process;
        disable receive_process;

        $display("--- LATENCY CUA %d GOI ---", packet_to_capture);
        for (int i = 0; i < packet_to_capture; i++) begin
            $display("Goi %2d: %0f ns", i, receive_time[i] - send_time[i]);
        end
        $display("Do tre trung binh: %0f ns", 
                 (receive_time[packet_to_capture-1] - send_time[0]) / packet_to_capture);
        
        #200;
        $finish;
    end
endmodule
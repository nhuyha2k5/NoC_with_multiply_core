`timescale 1ns/1ps

module tb_tg_slave;

    logic clk;
    logic rst_n;
    parameter DATA_WIDTH = 34;

    // Dây cáp nối 2 Node
    logic [DATA_WIDTH-1:0] tg_to_slave_flit, slave_to_tg_flit;
    logic tg_to_slave_valid, slave_to_tg_valid;
    logic tg_to_slave_credit, slave_to_tg_credit;

    // Xung nhịp 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 1. Khởi tạo Node Xả rác (Traffic Generator) ở tọa độ (0,0) bắn vào đích (2,2)
    tg_node #(
        .DATA_WIDTH(DATA_WIDTH),
        .CURRENT_X(2'd0), .CURRENT_Y(2'd0),
        .DEST_X(2'd2), .DEST_Y(2'd2),
        .LOAD_FACTOR(10), .WRITE_PROB(50) // Cứ 10 chu kỳ bắn 1 lệnh, 50% Ghi/50% Đọc
    ) u_tg_node (
        .clk(clk), .rst_n(rst_n),
        
        // Cắm dây ra cổng East
        .e_flit_out(tg_to_slave_flit), .e_valid_out(tg_to_slave_valid), .e_credit_in(tg_to_slave_credit),
        .e_flit_in(slave_to_tg_flit),  .e_valid_in(slave_to_tg_valid),  .e_credit_out(slave_to_tg_credit),
        
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(),
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(),
        .w_flit_in('0), .w_valid_in(1'b0), .w_credit_in()
    );

    // 2. Khởi tạo Slave Node ở tọa độ (2,2)
    slave_node #(
        .DATA_WIDTH(DATA_WIDTH),
        .CURRENT_X(2'd2), .CURRENT_Y(2'd2)
    ) u_slave_node (
        .clk(clk), .rst_n(rst_n),
        
        // Cắm dây ra cổng West (nhận từ TG)
        .w_flit_in(tg_to_slave_flit),   .w_valid_in(tg_to_slave_valid),   .w_credit_out(tg_to_slave_credit),
        .w_flit_out(slave_to_tg_flit),  .w_valid_out(slave_to_tg_valid),  .w_credit_in(slave_to_tg_credit),
        
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(),
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(),
        .e_flit_in('0), .e_valid_in(1'b0), .e_credit_in()
    );

    // Kịch bản chạy Test
    initial begin
        rst_n = 0;
        #20 rst_n = 1;

        $display("=== test traffic generate ===");

        // Theo dõi luồng gửi từ TG sang Slave
        forever begin
            @(posedge clk);
            if (tg_to_slave_valid) begin
                if (tg_to_slave_flit[33:32] == 2'b01) 
                    $display("[TG ban] HEAD Flit -> WE: %b, Dest: (%0d,%0d)", tg_to_slave_flit[23], tg_to_slave_flit[31:30], tg_to_slave_flit[29:28]);
                else if (tg_to_slave_flit[33:32] == 2'b00) 
                    $display("         BODY Flit -> Addr: %h", tg_to_slave_flit[31:0]);
                else if (tg_to_slave_flit[33:32] == 2'b10) 
                    $display("         TAIL Flit -> Data: %h", tg_to_slave_flit[31:0]);
            end
            
            // Theo dõi luồng phản hồi từ Slave về TG
            if (slave_to_tg_valid) begin
                if (slave_to_tg_flit[33:32] == 2'b01) 
                    $display("[Slave Phan hoi] HEAD Flit");
                else if (slave_to_tg_flit[33:32] == 2'b10) 
                    $display("                 TAIL Flit -> RData: %h", slave_to_tg_flit[31:0]);
            end
        end
    end

    // Dừng sau 1000 ns
    initial begin
        #1000;
        $display("=== HOAN THANH ===");
        $stop;
    end

endmodule
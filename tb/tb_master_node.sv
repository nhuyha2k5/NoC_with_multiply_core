`timescale 1ns/1ps

module tb_master_node;
    logic clk;
    logic rst_n;
    
    // Tín hiệu debug từ CPU
    wire [31:0] pc_debug;
    wire [31:0] alu_debug;

    // Cổng xuất dữ liệu ra mạng (chắc chắn đi hướng EAST)
    wire [33:0] east_flit;
    wire        east_valid;

    // =======================================================
    // 1. KHỞI TẠO MASTER NODE CÔ LẬP
    // Truyền thẳng đường dẫn file HEX vào tham số ROM_FILE của bạn!
    // =======================================================
    master_node #(
        .DATA_WIDTH(34), 
        .CURRENT_X(2'd0), 
        .CURRENT_Y(2'd0),
        .ROM_FILE("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master0.hex") // ĐƯỜNG DẪN FILE CỦA BẠN
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .debug_pc(pc_debug), .debug_alu(alu_debug),
        
        // Cấp Credit = 1 cho tất cả các cổng để Router không bị kẹt
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(1'b1),
        .n_flit_out(),  .n_valid_out(),    .n_credit_out(),
        
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(1'b1),
        .s_flit_out(),  .s_valid_out(),    .s_credit_out(),
        
        // Theo dõi cổng EAST (Vì đích là Node 1,1 nên gói tin sẽ đi qua hướng này)
        .e_flit_in('0), .e_valid_in(1'b0), .e_credit_in(1'b1),
        .e_flit_out(east_flit), .e_valid_out(east_valid), .e_credit_out(),
        
        .w_flit_in('0), .w_valid_in(1'b0), .w_credit_in(1'b1),
        .w_flit_out(),  .w_valid_out(),    .w_credit_out()
    );

    // Xung nhịp 50MHz
    always #10 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        
        // Tháo Reset cho CPU bắt đầu chạy
        #40;
        rst_n = 1;

        $display("\n=======================================================");
        $display("   [ISOLATION TEST] Kiem tra doc lap Khoi MASTER (0,0)");
        $display("=======================================================\n");
    end

    // ---------------------------------------------------------
    // THEO DÕI NHỊP ĐẬP CỦA CPU (In PC để xem có dừng ở 0x18 không)
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && $time <= 400) begin
            $display("Time: %0t ns | PC: %h | ALU_ADDR: %h", $time, pc_debug, alu_debug);
        end
    end

    // ---------------------------------------------------------
    // THEO DÕI QUÁ TRÌNH XUẤT GÓI TIN RA ROUTER
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // Kiểm tra xem Network Interface có đóng gói được Flit không
            if (dut.u_master_ni.tx_valid) begin
                $display("\n[%0t ns] [INTERNAL] Network Interface da dong goi xong! Payload: 0x%h", $time, dut.u_master_ni.tx_flit[31:0]);
            end
            
            // Kiểm tra xem Router có đẩy Flit ra khỏi Node thành công không
            if (east_valid) begin
                $display("[%0t ns] 🚀 [ROUTER] Da xuat Flit ra cong EAST vao mang NoC! Payload: 0x%h\n", $time, east_flit[31:0]);
            end
        end
    end

    // ---------------------------------------------------------
    // KẾT THÚC MÔ PHỎNG
    // ---------------------------------------------------------
    initial begin
        #2000;
        $display("=======================================================");
        $display("   KET THUC BAI TEST ISOLATION");
        $display("=======================================================\n");
        $stop;
    end
endmodule
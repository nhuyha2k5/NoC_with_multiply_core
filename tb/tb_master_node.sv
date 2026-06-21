`timescale 1ns/1ps

module tb_master_node;

    // 1. Khai bao tin hieu co ban
    logic clk;
    logic rst_n;
    parameter DATA_WIDTH = 34;

    // Tin hieu Debug ep Quartus giu CPU
    logic [31:0] debug_pc;
    logic [31:0] debug_alu;

    // Tin hieu mang xuat ra tu Master Node (de quan sat)
    logic [DATA_WIDTH-1:0] n_flit_out, s_flit_out, e_flit_out, w_flit_out;
    logic n_valid_out, s_valid_out, e_valid_out, w_valid_out;
    logic n_credit_out, s_credit_out, e_credit_out, w_credit_out;

    // 2. Khoi tao xung nhip 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 3. Khoi tao Master Node tai toa do (0,0)
    master_node #(
        .DATA_WIDTH(DATA_WIDTH),
        .CURRENT_X(2'd0), .CURRENT_Y(2'd0),
        .ROM_FILE("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code.hex") 
    ) u_master (
        .clk(clk), .rst_n(rst_n),
        
        // Noi day Debug ra ngoai
        .debug_pc(debug_pc), 
        .debug_alu(debug_alu),

        // Cac cong IN (Nhan tu mang): Noi dat vi khong co ai gui toi
        // Cac day credit_in cap muc 1 (Luon cho phep Master gui di)
        .n_flit_in('0), .n_valid_in(1'b0), .n_credit_in(1'b1),
        .s_flit_in('0), .s_valid_in(1'b0), .s_credit_in(1'b1),
        .e_flit_in('0), .e_valid_in(1'b0), .e_credit_in(1'b1),
        .w_flit_in('0), .w_valid_in(1'b0), .w_credit_in(1'b1),

        // Cac cong OUT (Gui ra mang): Loi ra de quan sat
        .n_flit_out(n_flit_out), .n_valid_out(n_valid_out), .n_credit_out(n_credit_out),
        .s_flit_out(s_flit_out), .s_valid_out(s_valid_out), .s_credit_out(s_credit_out),
        .e_flit_out(e_flit_out), .e_valid_out(e_valid_out), .e_credit_out(e_credit_out),
        .w_flit_out(w_flit_out), .w_valid_out(w_valid_out), .w_credit_out(w_credit_out)
    );

    // 4. Kich ban Test: Khoi dong va Theo doi
    initial begin
        // Reset ban dau
        rst_n = 0;
        #20 rst_n = 1;

        $display("=== HE THONG MASTER NODE KHOI DONG ===");

        // Vong lap giam sat CPU va Mang
        forever begin
            @(posedge clk);
            
            // Theo doi PC dang chay lenh o dia chi nao
            $display("Time: %0t | PC (Instr Addr): %h | ALU Addr: %h", $time, debug_pc, debug_alu);

            // Bat song neu Master co gui goi tin ra cong East
            if (e_valid_out) begin
                if (e_flit_out[33:32] == 2'b01)
                    $display("  -> [Cong EAST] HEAD Flit: %h", e_flit_out);
                else if (e_flit_out[33:32] == 2'b00)
                    $display("  -> [Cong EAST] BODY Flit: %h", e_flit_out);
                else if (e_flit_out[33:32] == 2'b10)
                    $display("  -> [Cong EAST] TAIL Flit: %h", e_flit_out);
            end
            
            // Bat song neu Master co gui goi tin ra cong South
            if (s_valid_out) begin
                if (s_flit_out[33:32] == 2'b01)
                    $display("  -> [Cong SOUTH] HEAD Flit: %h", s_flit_out);
                else if (s_flit_out[33:32] == 2'b00)
                    $display("  -> [Cong SOUTH] BODY Flit: %h", s_flit_out);
                else if (s_flit_out[33:32] == 2'b10)
                    $display("  -> [Cong SOUTH] TAIL Flit: %h", s_flit_out);
            end
        end
    end

    // 5. Ket thuc mo phong sau 500ns (50 chu ky)
    initial begin
        #500;
        $display("=== KET THUC MO PHONG MASTER NODE ===");
        $stop;
    end

endmodule
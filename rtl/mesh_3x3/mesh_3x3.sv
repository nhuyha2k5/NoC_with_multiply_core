`timescale 1ns/1ps

module mesh_3x3 #(
    parameter DATA_WIDTH = 34
)(
    input  wire clk,
    input  wire rst_n,

    output wire [31:0] fmax_pc_00,
    output wire [31:0] fmax_alu_00,
    output wire [31:0] fmax_pc_22,
    output wire [31:0] fmax_alu_22,
    output wire [31:0] dummy_output
);

    // =======================================================
    // 1. MẢNG DÂY KẾT NỐI (Giữ nguyên mảng dữ liệu)
    // =======================================================
    wire [DATA_WIDTH-1:0] n_flit_out [0:2][0:2];
    wire                  n_valid_out[0:2][0:2];
    wire                  n_credit_out[0:2][0:2];

    wire [DATA_WIDTH-1:0] s_flit_out [0:2][0:2];
    wire                  s_valid_out[0:2][0:2];
    wire                  s_credit_out[0:2][0:2];

    wire [DATA_WIDTH-1:0] e_flit_out [0:2][0:2];
    wire                  e_valid_out[0:2][0:2];
    wire                  e_credit_out[0:2][0:2];

    wire [DATA_WIDTH-1:0] w_flit_out [0:2][0:2];
    wire                  w_valid_out[0:2][0:2];
    wire                  w_credit_out[0:2][0:2];

    // Mảng dây Debug PC/ALU để gán ra ngoài
    wire [31:0] pc_debug  [0:2][0:2];
    wire [31:0] alu_debug [0:2][0:2];

    // =======================================================
    // 2. KHỞI TẠO 9 NODE BẰNG GENERATE BLOCK (TỐC ĐỘ BIÊN DỊCH X10)
    // =======================================================
    // Mạch sẽ tự động quét tọa độ (x,y) và tự động nối dây hoàn hảo
    // Đảm bảo không bao giờ bị đấu nhầm dây gây treo máy.
    genvar x, y;
    generate
        for (x = 0; x < 3; x = x + 1) begin : MESH_X
            for (y = 0; y < 3; y = y + 1) begin : MESH_Y

                // --- Tự động xác định dây đầu vào từ các Node hàng xóm ---
                wire [DATA_WIDTH-1:0] in_n_f = (y == 0) ? '0   : s_flit_out[x][y-1];
                wire                  in_n_v = (y == 0) ? 1'b0 : s_valid_out[x][y-1];
                wire                  in_n_c = (y == 0) ? 1'b1 : s_credit_out[x][y-1];

                wire [DATA_WIDTH-1:0] in_s_f = (y == 2) ? '0   : n_flit_out[x][y+1];
                wire                  in_s_v = (y == 2) ? 1'b0 : n_valid_out[x][y+1];
                wire                  in_s_c = (y == 2) ? 1'b1 : n_credit_out[x][y+1];

                wire [DATA_WIDTH-1:0] in_w_f = (x == 0) ? '0   : e_flit_out[x-1][y];
                wire                  in_w_v = (x == 0) ? 1'b0 : e_valid_out[x-1][y];
                wire                  in_w_c = (x == 0) ? 1'b1 : e_credit_out[x-1][y];

                wire [DATA_WIDTH-1:0] in_e_f = (x == 2) ? '0   : w_flit_out[x+1][y];
                wire                  in_e_v = (x == 2) ? 1'b0 : w_valid_out[x+1][y];
                wire                  in_e_c = (x == 2) ? 1'b1 : w_credit_out[x+1][y];

                // --- Phân bổ Node tương ứng với tọa độ (x,y) ---
                
                // 1. CPU MASTER TẠI (0,0)
                if (x == 0 && y == 0) begin : NODE_CPU_00
                    master_node #(
                        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(2'd0), .CURRENT_Y(2'd0), .PRIORITY(1'b1vs),
                        .ROM_FILE("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master0.hex")
                    ) u_master0 (
                        .clk(clk), .rst_n(rst_n),
                        .debug_pc(pc_debug[x][y]), .debug_alu(alu_debug[x][y]),
                        .n_flit_in(in_n_f), .n_valid_in(in_n_v), .n_credit_in(in_n_c),
                        .n_flit_out(n_flit_out[x][y]), .n_valid_out(n_valid_out[x][y]), .n_credit_out(n_credit_out[x][y]),
                        .s_flit_in(in_s_f), .s_valid_in(in_s_v), .s_credit_in(in_s_c),
                        .s_flit_out(s_flit_out[x][y]), .s_valid_out(s_valid_out[x][y]), .s_credit_out(s_credit_out[x][y]),
                        .e_flit_in(in_e_f), .e_valid_in(in_e_v), .e_credit_in(in_e_c),
                        .e_flit_out(e_flit_out[x][y]), .e_valid_out(e_valid_out[x][y]), .e_credit_out(e_credit_out[x][y]),
                        .w_flit_in(in_w_f), .w_valid_in(in_w_v), .w_credit_in(in_w_c),
                        .w_flit_out(w_flit_out[x][y]), .w_valid_out(w_valid_out[x][y]), .w_credit_out(w_credit_out[x][y])
                    );
                end
                
                // 2. CPU MASTER TẠI (2,2)
                else if (x == 2 && y == 2) begin : NODE_CPU_22
                    master_node #(
                        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(2'd2), .CURRENT_Y(2'd2), .PRIORITY(1'b0),
                        .ROM_FILE("D:/project_verilog/noc_riscV/rtl/mesh_3x3/hex/code_master1.hex")
                    ) u_master1 (
                        .clk(clk), .rst_n(rst_n),
                        .debug_pc(pc_debug[x][y]), .debug_alu(alu_debug[x][y]),
                        .n_flit_in(in_n_f), .n_valid_in(in_n_v), .n_credit_in(in_n_c),
                        .n_flit_out(n_flit_out[x][y]), .n_valid_out(n_valid_out[x][y]), .n_credit_out(n_credit_out[x][y]),
                        .s_flit_in(in_s_f), .s_valid_in(in_s_v), .s_credit_in(in_s_c),
                        .s_flit_out(s_flit_out[x][y]), .s_valid_out(s_valid_out[x][y]), .s_credit_out(s_credit_out[x][y]),
                        .e_flit_in(in_e_f), .e_valid_in(in_e_v), .e_credit_in(in_e_c),
                        .e_flit_out(e_flit_out[x][y]), .e_valid_out(e_valid_out[x][y]), .e_credit_out(e_credit_out[x][y]),
                        .w_flit_in(in_w_f), .w_valid_in(in_w_v), .w_credit_in(in_w_c),
                        .w_flit_out(w_flit_out[x][y]), .w_valid_out(w_valid_out[x][y]), .w_credit_out(w_credit_out[x][y])
                    );
                end
                
                // 3. RAM TRUNG TÂM TẠI (1,1)
                else if (x == 1 && y == 1) begin : NODE_RAM_11
                    slave_node #(
                        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(2'd1), .CURRENT_Y(2'd1), .MEM_DEPTH(1024)
                    ) u_slave (
                        .clk(clk), .rst_n(rst_n),
                        .n_flit_in(in_n_f), .n_valid_in(in_n_v), .n_credit_in(in_n_c),
                        .n_flit_out(n_flit_out[x][y]), .n_valid_out(n_valid_out[x][y]), .n_credit_out(n_credit_out[x][y]),
                        .s_flit_in(in_s_f), .s_valid_in(in_s_v), .s_credit_in(in_s_c),
                        .s_flit_out(s_flit_out[x][y]), .s_valid_out(s_valid_out[x][y]), .s_credit_out(s_credit_out[x][y]),
                        .e_flit_in(in_e_f), .e_valid_in(in_e_v), .e_credit_in(in_e_c),
                        .e_flit_out(e_flit_out[x][y]), .e_valid_out(e_valid_out[x][y]), .e_credit_out(e_credit_out[x][y]),
                        .w_flit_in(in_w_f), .w_valid_in(in_w_v), .w_credit_in(in_w_c),
                        .w_flit_out(w_flit_out[x][y]), .w_valid_out(w_valid_out[x][y]), .w_credit_out(w_credit_out[x][y])
                    );
                    assign pc_debug[x][y] = 32'b0;
                    assign alu_debug[x][y] = 32'b0;
                end
                
                // 4. 6 NODE TRAFFIC GENERATOR CÒN LẠI
                else begin : NODE_TG
                    // Nạp các thông số cũ đúng với vị trí (x,y)
                    localparam L_FACT = (x==0 && y==1) ? 10 :
                                        (x==0 && y==2) ? 12 :
                                        (x==1 && y==0) ? 16 :
                                        (x==1 && y==2) ? 8  :
                                        (x==2 && y==0) ? 20 :
                                        (x==2 && y==1) ? 10 : 10;

                    localparam W_PROB = (x==0 && y==1) ? 50 :
                                        (x==0 && y==2) ? 30 :
                                        (x==1 && y==0) ? 50 :
                                        (x==1 && y==2) ? 80 :
                                        (x==2 && y==0) ? 20 :
                                        (x==2 && y==1) ? 60 : 50;

                    tg_node #(
                        .DATA_WIDTH(DATA_WIDTH), .CURRENT_X(x), .CURRENT_Y(y), .PRIORITY(1'b0),
                        .DEST_X(2'd1), .DEST_Y(2'd1), .LOAD_FACTOR(L_FACT), .WRITE_PROB(W_PROB)
                    ) u_tg (
                        .clk(clk), .rst_n(rst_n),
                        .n_flit_in(in_n_f), .n_valid_in(in_n_v), .n_credit_in(in_n_c),
                        .n_flit_out(n_flit_out[x][y]), .n_valid_out(n_valid_out[x][y]), .n_credit_out(n_credit_out[x][y]),
                        .s_flit_in(in_s_f), .s_valid_in(in_s_v), .s_credit_in(in_s_c),
                        .s_flit_out(s_flit_out[x][y]), .s_valid_out(s_valid_out[x][y]), .s_credit_out(s_credit_out[x][y]),
                        .e_flit_in(in_e_f), .e_valid_in(in_e_v), .e_credit_in(in_e_c),
                        .e_flit_out(e_flit_out[x][y]), .e_valid_out(e_valid_out[x][y]), .e_credit_out(e_credit_out[x][y]),
                        .w_flit_in(in_w_f), .w_valid_in(in_w_v), .w_credit_in(in_w_c),
                        .w_flit_out(w_flit_out[x][y]), .w_valid_out(w_valid_out[x][y]), .w_credit_out(w_credit_out[x][y])
                    );
                    assign pc_debug[x][y] = 0;
                    assign alu_debug[x][y] = 32'b0;
                end
            end
        end
    endgenerate

    // =======================================================
    // 3. GÁN NGÕ RA DEBUG ĐỂ QUARTUS KHÔNG XÓA MẠCH
    // =======================================================
    assign fmax_pc_00  = pc_debug[0][0];
    assign fmax_alu_00 = alu_debug[0][0];
    assign fmax_pc_22  = pc_debug[2][2];
    assign fmax_alu_22 = alu_debug[2][2];

    assign dummy_output = w_flit_out[0][0][31:0] ^ e_flit_out[2][2][31:0] ^ n_flit_out[1][0][31:0] ^ s_flit_out[1][2][31:0];

endmodule
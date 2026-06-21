`timescale 1ns/1ps

module ram_obi #(
    parameter int MEM_SIZE_BYTES = 1024,
    parameter string INIT_FILE = ""
)(
    input  logic        clk,
    input  logic        rst_n,

    // PORT A
    input  logic        req_a_i,
    output logic        gnt_a_o,
    input  logic        we_a_i,
    input  logic [3:0]  be_a_i,
    input  logic [31:0] addr_a_i,
    input  logic [31:0] wdata_a_i,
    output logic        rvalid_a_o,
    output logic [31:0] rdata_a_o,

    // PORT B
    input  logic        req_b_i,
    output logic        gnt_b_o,
    input  logic        we_b_i,
    input  logic [3:0]  be_b_i,
    input  logic [31:0] addr_b_i,
    input  logic [31:0] wdata_b_i,
    output logic        rvalid_b_o,
    output logic [31:0] rdata_b_o
);

    localparam MEM_WORDS = MEM_SIZE_BYTES / 4;
    localparam ADDR_WIDTH = $clog2(MEM_WORDS);
    
    // Ép Vivado sử dụng Block RAM
    (* ram_style = "block" *) logic [31:0] mem [0:MEM_WORDS-1];

    // Khởi tạo an toàn
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (int i = 0; i < MEM_WORDS; i = i + 1) begin
                mem[i] = 32'd0;
            end
        end
    end

    logic [ADDR_WIDTH-1:0] word_addr_a;
    logic [ADDR_WIDTH-1:0] word_addr_b;
    
    assign word_addr_a = addr_a_i[ADDR_WIDTH+1:2];
    assign word_addr_b = addr_b_i[ADDR_WIDTH+1:2];

    assign gnt_a_o = req_a_i;
    assign gnt_b_o = req_b_i;

    // =======================================================
    // PORT A (Chỉ Đọc)
    // =======================================================
    always_ff @(posedge clk) begin
        if (req_a_i) begin
            rdata_a_o <= mem[word_addr_a];
        end else begin
            rdata_a_o <= 32'd0;
        end
    end

    // =======================================================
    // PORT B (Ghi thủ công bằng Byte-Enable, Write-First)
    // =======================================================
    always_ff @(posedge clk) begin
        if (req_b_i) begin
            // Viết rõ ràng từng Byte theo chuẩn Vivado BRAM
            if (we_b_i && be_b_i[0]) mem[word_addr_b][7:0]   <= wdata_b_i[7:0];
            if (we_b_i && be_b_i[1]) mem[word_addr_b][15:8]  <= wdata_b_i[15:8];
            if (we_b_i && be_b_i[2]) mem[word_addr_b][23:16] <= wdata_b_i[23:16];
            if (we_b_i && be_b_i[3]) mem[word_addr_b][31:24] <= wdata_b_i[31:24];
            
            // Đọc Write-First
            if (we_b_i && (be_b_i != 4'b0000)) begin
                rdata_b_o <= wdata_b_i; 
            end else begin
                rdata_b_o <= mem[word_addr_b];
            end
        end
    end

    // =======================================================
    // TÍN HIỆU PHẢN HỒI
    // =======================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_a_o <= 1'b0;
            rvalid_b_o <= 1'b0;
        end else begin
            rvalid_a_o <= req_a_i;
            rvalid_b_o <= req_b_i;
        end
    end

endmodule
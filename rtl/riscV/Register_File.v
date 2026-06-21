module Register_File (
    input wire clk,
    input wire rst_n,        // Tín hiệu reset hệ thống (tích cực mức thấp)
    input wire reg_write,    // Tín hiệu cho phép ghi từ tầng WB
    input wire [4:0] rs1,    // Địa chỉ nguồn 1 (từ tầng ID)
    input wire [4:0] rs2,    // Địa chỉ nguồn 2 (từ tầng ID)
    input wire [4:0] rd,     // Địa chỉ đích (từ tầng WB)
    input wire [31:0] wd,    // Dữ liệu ghi (từ tầng WB)
    output wire [31:0] rd1,  // Dữ liệu đọc ra 1
    output wire [31:0] rd2,  // Dữ liệu đọc ra 2
    input wire [4:0] debug_addr,
    output wire [31:0] debug_val
);
    reg [31:0] rf [31:0];
   integer i;

    // Logic Ghi dữ liệu và Reset
    always @(posedge clk or negedge rst_n) begin 
		
        if (!rst_n) begin
            // Khi reset, đưa tất cả 32 thanh ghi về giá trị 0
            for (i = 0; i < 32; i = i + 1) begin
                rf[i] <= 32'b0;
            end
          
        end 
        else if (reg_write && (rd != 5'b00000)) begin
            // Chỉ ghi khi có tín hiệu cho phép và không phải ghi vào thanh ghi x0
            rf[rd] <= wd;
        end
    end

    // Logic Đọc dữ liệu (Không đồng bộ - Asynchronous Read)
    // Theo kiến trúc RISC-V: thanh ghi x0 luôn luôn trả về giá trị 0
    assign rd1 = (reg_write && (rd == rs1) && (rs1 != 5'b0)) ? wd :
                 ((rs1 == 5'b0) ? 32'b0 : rf[rs1]);
    assign rd2 = (reg_write && (rd == rs2) && (rs2 != 5'b0)) ? wd :
                 ((rs2 == 5'b0) ? 32'b0 : rf[rs2]);
    assign debug_val = (debug_addr == 5'b0) ? 32'b0 : rf[debug_addr];

endmodule
// Forwarding Unit - Xử lý Data Hazards bằng cách forward dữ liệu
// Chuyển tiếp kết quả từ pipeline stage sau về stage trước

module Forwarding_Unit (
    // Đầu vào từ ID/EX stage (instruction đang thực thi)
    input wire [4:0]  id_ex_rs1,        // rs1 của instruction trong EX stage
    input wire [4:0]  id_ex_rs2,        // rs2 của instruction trong EX stage

    // Đầu vào từ EX/MEM stage (stage trước)
    input wire [4:0]  ex_mem_rd,        // rd của instruction trong MEM stage
    input wire        ex_mem_regWrite,  // regWrite của instruction trong MEM stage

    // Đầu vào từ MEM/WB stage (stage trước nữa)
    input wire [4:0]  mem_wb_rd,        // rd của instruction trong WB stage
    input wire        mem_wb_regWrite,  // regWrite của instruction trong WB stage

    // Đầu ra - Forwarding control cho ALU inputs
    output reg [1:0]  forwardA,         // 00=no forward, 01=EX/MEM, 10=MEM/WB
    output reg [1:0]  forwardB          // 00=no forward, 01=EX/MEM, 10=MEM/WB
);

    // Forwarding logic cho rs1 (forwardA)
    always @(*) begin
        // Priority: EX/MEM trước (gần nhất), rồi MEM/WB
        if (ex_mem_regWrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) begin
            // Forward từ EX/MEM stage
            forwardA = 2'b01;
        end
        else if (mem_wb_regWrite && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) begin
            // Forward từ MEM/WB stage
            forwardA = 2'b10;
        end
        else begin
            // Không forward, dùng dữ liệu từ register file
            forwardA = 2'b00;
        end
    end

    // Forwarding logic cho rs2 (forwardB)
    always @(*) begin
        // Priority: EX/MEM trước (gần nhất), rồi MEM/WB
        if (ex_mem_regWrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) begin
            // Forward từ EX/MEM stage
            forwardB = 2'b01;
        end
        else if (mem_wb_regWrite && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            // Forward từ MEM/WB stage
            forwardB = 2'b10;
        end
        else begin
            // Không forward, dùng dữ liệu từ register file
            forwardB = 2'b00;
        end
    end

endmodule

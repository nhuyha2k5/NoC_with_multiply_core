module Program_Counter (
    input wire clk,
    input wire rst_n,
    input wire start,         // Tín hiệu cho phép vi xử lý hoạt động (Trang 27)
    input wire stall,         // Tín hiệu dừng từ Hazard Unit (khi gặp Load Hazard)
    input wire [31:0] pc_next,// Địa chỉ tiếp theo (từ khối Branch Prediction hoặc bộ cộng)
    output reg [31:0] pc_out  // Địa chỉ hiện tại đưa tới bộ nhớ lệnh
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khi reset, đưa địa chỉ về 0
            pc_out <= 32'h0000_0000;
        end 
        else if (start && !stall) begin
            // Chỉ cập nhật địa chỉ mới khi:
            // 1. Hệ thống đã nhấn START
            // 2. Không bị STALL (không có xung đột dữ liệu)
            pc_out <= pc_next;
        end
        // Nếu start = 0 hoặc stall = 1, pc_out sẽ giữ nguyên giá trị cũ (đứng yên)
    end

endmodule
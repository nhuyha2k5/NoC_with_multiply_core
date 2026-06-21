module Hazard_Unit (
    // Tín hiệu đầu vào từ các tầng
    input wire [4:0] if_id_rs1,     // rs1 của lệnh đang ở tầng ID
    input wire [4:0] if_id_rs2,     // rs2 của lệnh đang ở tầng ID
    input wire       if_id_uses_rs1,// Lệnh ID có thực sự dùng rs1
    input wire       if_id_uses_rs2,// Lệnh ID có thực sự dùng rs2
    input wire [4:0] id_ex_rd,      // rd của lệnh đang ở tầng EX
    input wire [1:0] id_ex_wb_sel,  // write_back_sel của EX (nếu = 2'b01 nghĩa là lệnh Load)
    
    // Tín hiệu từ khối so sánh Branch ở tầng EX (để kiểm tra xem có đoán sai không)
    input wire       branch_mispredicted, // Bằng 1 nếu kết quả nhảy thực tế khác với dự đoán

    // Tín hiệu đầu ra điều khiển Pipeline
    output reg       stall_pc,      // Dừng PC (không nạp lệnh mới)
    output reg       stall_if_id,   // Dừng thanh ghi IF/ID (giữ nguyên lệnh hiện tại)
    output reg       flush_id_ex,   // Xóa thanh ghi ID/EX (chèn bong bóng)
    output reg       flush_if_id    // Xóa IF/ID (khi rẽ nhánh sai)
);

    always @(*) begin
        // Khởi tạo mặc định: Không stall, không flush
        stall_pc    = 1'b0;
        stall_if_id = 1'b0;
        flush_id_ex = 1'b0;
        flush_if_id = 1'b0;

        // 1. Xử lý Control Hazard (Đoán sai rẽ nhánh)
        // Nếu tầng EX phát hiện rẽ nhánh thực tế khác với dự đoán
        if (branch_mispredicted) begin
            flush_if_id = 1'b1; // Xóa lệnh đang lấy (Fetch)
            flush_id_ex = 1'b1; // Xóa lệnh đang giải mã (Decode)
        end
        
        // 2. Xử lý Load-Use Data Hazard
        // Nếu lệnh trước đó (đang ở EX) là lệnh Load (id_ex_wb_sel == 2'b01)
        // và thanh ghi đích của nó trùng với thanh ghi nguồn của lệnh hiện tại (đang ở ID)
        else if ((id_ex_wb_sel == 2'b01) && 
                 (id_ex_rd != 5'b0) && 
                 ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                  (if_id_uses_rs2 && (id_ex_rd == if_id_rs2)))) begin
            stall_pc    = 1'b1; // Dừng nạp PC
            stall_if_id = 1'b1; // Dừng thay đổi IF_ID
            flush_id_ex = 1'b1; // Biến lệnh ID_EX hiện tại thành NOP (bubble)
        end
    end
endmodule
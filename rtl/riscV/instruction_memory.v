module instruction_memory (
    input wire clk,
    input wire rst_n,        // Tín hiệu reset (active low)
    input wire we,            // Tín hiệu cho phép nạp lệnh từ bên ngoài (khi start=0)
    input wire [31:0] addr_ext, // Địa chỉ nạp lệnh từ bên ngoài
    input wire [31:0] din_ext,  // Dữ liệu lệnh nạp từ bên ngoài
    input wire [31:0] pc,       // Địa chỉ từ Program Counter của CPU
    output wire [31:0] instr    // Lệnh xuất ra cho CPU thực thi
);
    // Khởi tạo bộ nhớ 1024 dòng (4KB), mỗi dòng 32-bit
    reg [31:0] mem [0:128];
    integer i;
    // Ghi lệnh vào bộ nhớ (quá trình nạp chương trình)
    always @(posedge clk or negedge rst_n) begin
	 
        if (!rst_n) begin
            // Khi reset, xóa sạch bộ nhớ về 0 (lệnh NOP)
            for (i = 0; i < 128; i = i + 1) begin
                mem[i] <= 32'h00000013; // 0x00000013 là lệnh ADDI x0, x0, 0 (NOP trong RISC-V)
            end
        end 
        else if (we)
            mem[addr_ext[11:2]] <= din_ext;
    end

    // Đọc lệnh dựa trên PC (Đọc không đồng bộ để tầng Fetch lấy lệnh ngay)
    // addr[11:2] vì địa chỉ RISC-V nhảy mỗi lần 4 đơn vị (byte-aligned)
    assign instr = mem[pc[11:2]];

endmodule
module data_memory (
    input wire clk,
    input wire mem_write,       // Tín hiệu memWrite_D từ Control Unit
    input wire [31:0] addr,     // Địa chỉ từ ALU
    input wire [31:0] write_data, // Dữ liệu từ thanh ghi nguồn 2 (rs2)
    input wire [2:0] load_sel,  // load_sel_D: 000-LB, 001-LH, 010-LW, 100-LBU, 101-LHU
    input wire [2:0] store_sel, // store_sel_D: 000-SB, 001-SH, 010-SW
    output reg [31:0] read_data, // Dữ liệu trả về cho CPU
    input wire [9:0] debug_addr,
    output wire [31:0] debug_val
);
    // Khai báo bộ nhớ 4KB (1024 dòng x 32 bit)
    reg [31:0] ram [0:128];

    // --- LOGIC GHI (STORE) ---
    // Sử dụng addr[11:2] để chọn dòng (Word)
    // Sử dụng addr[1:0] để chọn vị trí ghi trong Word
    always @(posedge clk) begin
        if (mem_write) begin
            case (store_sel)
                3'b000: begin // SB: Ghi 1 byte vào bất kỳ vị trí nào (0, 1, 2, 3)
                    case (addr[1:0])
                        2'b00: ram[addr[11:2]][7:0]   <= write_data[7:0];
                        2'b01: ram[addr[11:2]][15:8]  <= write_data[7:0];
                        2'b10: ram[addr[11:2]][23:16] <= write_data[7:0];
                        2'b11: ram[addr[11:2]][31:24] <= write_data[7:0];
                    endcase
                end

                3'b001: begin // SH: Ghi 2 byte, mặc định địa chỉ chẵn (chỉ xét bit addr[1])
                    if (addr[1] == 1'b0) // Vị trí 0 (byte 0, 1)
                        ram[addr[11:2]][15:0]  <= write_data[15:0];
                    else                 // Vị trí 2 (byte 2, 3)
                        ram[addr[11:2]][31:16] <= write_data[15:0];
                end

                3'b010: begin // SW: Ghi cả 4 byte (Word)
                    ram[addr[11:2]] <= write_data;
                end
            endcase
        end
    end

    // --- LOGIC ĐỌC (LOAD) ---
    wire [31:0] raw_word = ram[addr[11:2]]; // Đọc nguyên dòng 32-bit lên trước
    reg [7:0]  byte_to_load;
    reg [15:0] half_to_load;

    always @(*) begin
        // 1. Logic chọn Byte (hỗ trợ bất kỳ địa chỉ nào từ 0-3)
        case (addr[1:0])
            2'b00: byte_to_load = raw_word[7:0];
            2'b01: byte_to_load = raw_word[15:8];
            2'b10: byte_to_load = raw_word[23:16];
            2'b11: byte_to_load = raw_word[31:24];
        endcase

        // 2. Logic chọn Half-word (mặc định địa chỉ chẵn, bỏ qua addr[0])
        half_to_load = (addr[1] == 1'b0) ? raw_word[15:0] : raw_word[31:16];

        // 3. Logic xuất dữ liệu cuối cùng kèm mở rộng dấu/không dấu
        case (load_sel)
            3'b000: read_data = {{24{byte_to_load[7]}}, byte_to_load}; // LB: Mở rộng dấu
            3'b001: read_data = {{16{half_to_load[15]}}, half_to_load};// LH: Mở rộng dấu
            3'b010: read_data = raw_word;                               // LW: Word
            3'b100: read_data = {24'b0, byte_to_load};                 // LBU: Mở rộng zero
            3'b101: read_data = {16'b0, half_to_load};                 // LHU: Mở rộng zero
            default: read_data = raw_word;
        endcase
    end

    assign debug_val = ram[debug_addr];

endmodule



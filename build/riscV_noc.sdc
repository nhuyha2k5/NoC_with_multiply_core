# 1. Tạo xung clock chính với tần số mong muốn (Ví dụ: 80 MHz -> Chu kỳ là 12.5 ns)
# Nếu muốn test 70 MHz thì đổi 12.5 thành 14.28
create_clock -name main_clk -period 12.5 [get_ports clk]

# 2. Tự động tính toán các thông số clock bên trong (nếu mạch có dùng PLL)
derive_pll_clocks

# 3. Yêu cầu bộ phân tích thời gian tính toán độ lệch xung (Clock Uncertainty)
derive_clock_uncertainty
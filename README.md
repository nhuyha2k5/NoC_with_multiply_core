# 🖥️ Thiết Kế Hệ Thống Network on Chip (NoC) Tích Hợp Multiply Core

Dự án thiết kế và hiện thực hóa mạng NoC (Network-on-Chip) kiến trúc 2x3 Mesh dành cho hệ thống đa lõi (Multiply Core). Mục tiêu cốt lõi của hệ thống là xây dựng một mạng lưới truyền tin tốc độ cao, thay thế hoàn toàn các chuẩn bus truyền thống, từ đó tăng cường hiệu năng xử lý chung và giải quyết bài toán thắt nút cổ chai dữ liệu trong SoC.

---

## 🌟 Tổng Quan Kiến Trúc
![Sơ đồ tổng quan kiến trúc NoC 3x3 Mesh]

<img width="824" height="626" alt="image" src="https://github.com/user-attachments/assets/860e6f49-94cd-4e81-ab64-8f365c806efa" />


Kiến trúc hệ thống sử dụng cấu trúc liên kết (Topology) dạng Mesh 3x3 bao gồm 9 node, được phân bổ như sau:
*   **Node (0,0) và Node (2,2):** Được tích hợp CPU, đảm nhiệm vai trò tính toán chính. CPU sử dụng là kiến trúc RISC-V 32-bit với pipeline 5 tầng (IF, ID, EX, MEM, WB).
*   **Node (1,1):** Đóng vai trò lưu trữ bộ nhớ dùng chung (Shared RAM đồng bộ, dung lượng 1024x32-bit).
*   **Các Node còn lại:** Được kết nối với bộ tạo lưu lượng (Traffic Generator) để phát sinh các gói tin giả lập, phục vụ cho việc kiểm tra và đánh giá tình trạng nghẽn mạng.

Hệ thống sử dụng chuẩn **Open Bus Interface (OBI)** để giao tiếp giữa CPU và NoC. Đây là tiêu chuẩn mở, tối ưu cho RISC-V với các đặc điểm: tách biệt pha (Phase Separation), đường ống hóa (Pipelined) và không dồn kênh (Unmultiplexed).

---

## ⚙️ Thiết Kế Chi Tiết Các Khối (Core Modules)

### 1. Khối Router (Bộ định tuyến)

<img width="1422" height="682" alt="image" src="https://github.com/user-attachments/assets/ded041ae-0287-470e-b9f2-295e987526ba" />


Lõi Router bao gồm 4 khối chức năng chính:
*   **Input Port (Cổng vào):** Tiếp nhận dữ liệu, tích hợp bộ đệm FIFO và bộ giải mã định tuyến XY.
*   **Priority Arbiter (Bộ trọng tài):** Phân xử và cấp quyền ưu tiên luồng tin theo thuật toán Priority Round Robin.
*   **Crossbar Switch (Ma trận chuyển mạch):** Đóng cắt mạch và điều hướng chuẩn xác luồng dữ liệu từ cổng vào ra cổng ra.
*   **Output Port (Cổng ra):** Xuất dữ liệu và giao tiếp kiểm soát luồng với Router kế tiếp.

### 2. Network Interface (Giao diện mạng)
![Sơ đồ Master_NI ]
<img width="1609" height="706" alt="image" src="https://github.com/user-attachments/assets/3a41fd77-96ea-48b6-b589-b5d736844886" />
![Sơ đồ Slave_NI ]
<img width="1327" height="725" alt="image" src="https://github.com/user-attachments/assets/81ca4f75-12a2-43dd-b4d8-339940bec5b6" />


*   **Master_NI (Cầu nối CPU - NoC):** Ánh xạ bộ nhớ linh hoạt bằng cách trích xuất tọa độ đích từ địa chỉ CPU. Bao gồm FSM TX Packetizer (đóng gói lệnh OBI thành các Flit 34-bit: Head, Body, Tail) và RX Depacketizer (giải nén gói tin phản hồi để trả dữ liệu cho CPU).
*   **Slave_NI (Shared RAM Node):** Quản lý mảng RAM nội bộ. Hỗ trợ ghi dữ liệu chi tiết đến từng Byte. Khối TX FSM của Slave chỉ kích hoạt khi cần trả kết quả dữ liệu cho lệnh Đọc (tự động đảo chiều định tuyến bơm ngược vào NoC).
*   **CPU OBI Bridge (Trạm phân luồng):** Đóng vai trò như "cảnh sát giao thông". CPU không cần biết về NoC; Bridge sẽ đọc địa chỉ (`cpu_addr`) để quyết định cất vào RAM nội bộ hay đẩy ra mạng qua Master NI thông qua 3 trạng thái FSM: IDLE, WAIT_GNT, WAIT_RVALID.

---

## 🧠 Các Thuật Toán Tích Hợp

*   **Định tuyến XY (XY Routing):** Gói tin di chuyển triệt để theo trục ngang (X) trước, sau đó mới rẽ sang trục dọc (Y), đảm bảo 100% không bao giờ xảy ra bế tắc mạng (Deadlock-free).
*   **Chuyển mạch lỗ sâu (Wormhole Switching):** Gói tin được băm nhỏ thành các Flit (Head, Body, Tail) nối đuôi nhau luồn lách đi theo, giúp độ trễ truyền tải siêu thấp và cho phép sử dụng FIFO cực nhỏ.
*   **Kiểm soát luồng tín nhiệm (Credit-based Flow Control):** Dựa vào "điểm tín nhiệm" báo về từ số ô trống của bộ đệm đích để quyết định gửi, đảm bảo 100% không rơi vãi gói tin (Drop-free).

---

## 📊 Kết Quả Thực Thi & Đánh Giá

Hệ thống được thiết kế và tổng hợp thành công trên phần mềm **Quartus II (FPGA Cyclone II - EP2C50F672C6)**.

| Tiêu chí Đánh giá | Kết quả Đạt được | Ghi chú |
| :--- | :--- | :--- |
| **Tần số Fmax** | 53.08 MHz | Vượt mục tiêu PPA ban đầu (>50MHz) |
| **Tài nguyên Logic** | 32,272 LEs | Đạt mức tối ưu với 22,850 combinational và 22,378 registers |
| **Kiểm tra Priority** | Thành công | Master VIP (0,0) được cấp quyền vào trước, Master Normal (2,2) đi sau |
| **Độ trễ (Latency)** | 5 chu kỳ (VIP) vs 8 chu kỳ (Normal) | VIP mất 100,000 ns; Normal mất 160,000 ns khi kiểm tra nghẽn mạng |

---

## 🚀 Hướng Phát Triển Tương Lai

*   Nâng cấp bộ vi xử lý sang nhân Ibex (RISC-V) chuẩn công nghiệp.
*   Tích hợp bộ nhớ đệm cục bộ (L1 Cache) và Kênh ảo (Virtual Channels - VC) cho Router.
*   Tích hợp giao thức đồng bộ bộ nhớ đệm (Cache Coherence - MESI).
*   Tối ưu hóa phần cứng để đạt Fmax > 100MHz và giảm tổng tài nguyên logic xuống < 25,000 LEs.

---

## 🔗 Thông Tin  Dự Án

*   **Sinh viên thực hiện:** Hà Y Như Ý (23521843)
*   **Giảng viên hướng dẫn:** ThS. Tạ Trí Đức
*   **Đơn vị:** Khoa Kỹ thuật Máy tính (CE-UIT)

# Quad-Ibex MESI / AXI4 burst / NoC mesh 3x3

Project độc lập. Source Ibex và các dependency của lowRISC nằm trong `third_party/ibex`; project không gọi source bên ngoài.

SoC có 4 Ibex RV32IMC với D-cache MESI, PLIC 4 context × 16 nguồn, CLINT chuẩn, mailbox 4 slot, khóa test-and-set phần cứng, DMA, accelerator nhân ma trận, firmware C 4 hart và testbench tự kiểm.

## Các node (từ 16/10/2026)

| Tọa độ | IP |
|---|---|
| (0,0) | Ibex hart0 + MESI cache + ROM riêng |
| (0,1) | Node ngoại vi gộp: UART TX 8N1, GPIO 8 bit, mailbox 4 slot, 16 khóa test-and-set |
| (0,2) | Ibex hart1 + MESI cache + ROM riêng |
| (1,0) | DMA memory-to-memory (AXI4 burst) |
| (1,1) | Shared RAM 128 KiB (4 bank) |
| (1,2) | PLIC 4 context × 16 nguồn + CLINT (`0x0200_0000`) + NoC control |
| (2,0) | Ibex hart2 + MESI cache + ROM riêng |
| (2,1) | Accelerator ma trận signed32, N=1..16 |
| (2,2) | Ibex hart3 + MESI cache + ROM riêng |

Memory map và quyết định thiết kế: [docs/implementation_plan.md](docs/implementation_plan.md) (Bước 3–4). Bản 2 core cũ còn trong snapshot `build/before_step2_20261016_092925.zip`.

Mesh giữ nguyên 3x3: XY, wormhole, 2 VC, credit flow control, round-robin/response priority/weighted VC/aging, traffic class cấu hình qua MMIO (POLICY bit 3 tắt aging để làm thí nghiệm đối chứng). Aging vẫn tăng khi output hết credit, nên luồng ưu tiên cao không bỏ đói được luồng thấp khi nghẽn. Packet ownership riêng từng output VC; VC1 có thể vượt qua VC0 đang hết credit. Đường MMIO là AXI4-Lite; NI CPU hỗ trợ bốn giao dịch outstanding có tag. Đường DMA ↔ RAM dùng AXI4 profile 32-bit, INCR burst 1..16 beat, ID và WSTRB từng beat. Bộ đếm flit/packet/stall theo router/output và đỉnh occupancy theo router/input được đọc qua `0x30006000`.

## Chạy lại

Cần Questa/vlog/vsim, FuseSoC; Vivado 2025.2 để implementation. Script build firmware có tham số `-Toolchain` chỉ tới thư mục RISC-V GCC (mặc định toolchain đã tìm thấy trên máy này).

```powershell
cd D:\project_verilog\NoC_with_multiply_core-main\Noc_new
.\scripts\run_all.ps1 -QuickBenchmark
# Đủ 120 cấu hình traffic, 3 seeds; ghi vào thư mục riêng:
.\scripts\run_noc_benchmark.ps1 -RunTag current
# Synthesis + place/phys-opt/route, không tạo bitstream hay nạp board:
.\scripts\run_post_route.ps1 -ClockHz 100000000
```

Log/CSV được giữ trong `build/rtl_regression`, `build/verification`, `build/upgrade_tests`, `build/firmware_sim`, `build/baseline_<RunTag>`. Fail nếu thiếu TEST_PASS, có Error/Fatal hoặc process lỗi; không chỉ dựa vào exit code simulator.

XPR tạo trong `build/vivado_upgrade/local_ibex_mesh_soc_2.0.xpr`. Checkpoint/report mới trong `reports/post_route_upgrade_<Hz>` hoặc `reports/post_route_<ReportTag>_<Hz>`; báo cáo `reports/post_route_<Hz>` không có tag là baseline cũ. Chạy script setup lại khi sửa RTL vì FuseSoC tạo bản sao source trong build.

## Phạm vi cần nói đúng khi báo cáo

- AXI4 dataplane là subset được giới hạn công khai: 32-bit, aligned INCR burst 1..16 beat; không hỗ trợ mọi SIZE/BURST/LOCK hay cache-coherent AXI. Xem `docs/axi_burst_protocol.md`.
- MESI là mô hình snoop broadcast cho 4 CPU: mỗi cache có 128 line một word; control plane riêng; manager snoop đồng thời 3 peer.
  - Miss khác word của các core có thể chồng lên nhau, tối đa 4 giao dịch đang bay (`EARLY_RELEASE`).
  - Writeback lỗi kéo dài trả SLVERR thay vì treo.
  - Không phải AXI ACE/CHI và chưa có chứng minh formal đầy đủ.
- DMA/accelerator chỉ truy cập vùng uncached `0x20008000..0x2000BFFF`; không phải coherent I/O.
- UART chỉ có TX, chưa có RX/FIFO. Không có MMU/Linux, debug/JTAG hoàn chỉnh hoặc scatter-gather DMA.
- Testbench tự kiểm đã bao phủ:
  - reset, backpressure, burst, IRQ 2 và 4 hart, node map 4 core;
  - MESI 2 và 4 cache: stress đồng thời, bất biến mỗi chu kỳ, mutation test;
  - firmware 4 hart và benchmark 1/2/4 hart.

  Đây chưa phải sign-off UVM hay formal.
- Post-route của bản 2 core (VC707, 100 MHz):
  - 08/10: 71.243 LUT, WNS +0,308 ns;
  - 15/10, sau khi tối ưu cache: 37.798 LUT, WNS +0,134 ns.

  Kết quả bản 4 core: [docs/resource_timing_comparison.md](docs/resource_timing_comparison.md).

Báo cáo hiện hành (RTL 08/10/2026): [kết quả bước 1–2: sửa lỗi, kiểm chứng, song song, timing](docs/bao_cao_buoc1_2_20261008.md) · [lập luận không deadlock](docs/deadlock_freedom.md) · [đánh giá và so sánh](docs/danh_gia_noc_va_so_sanh_20261008.md).
Tài liệu lịch sử (26/09, một số mô tả đã lỗi thời): [tổng quan](docs/bao_cao_tong_quan.md), [kiểm chứng](docs/bao_cao_ket_qua_kiem_chung.md).

# Cấu trúc RTL

```text
rtl/
├── board/
│   └── vc707_top.sv
├── cache/
│   ├── coherence_pkg.sv
│   ├── coherence_manager_2core.sv
│   └── mesi_dcache.sv
├── mesh_3x3/
│   ├── mesh_3x3_vc.sv
│   └── ibex_mesh_soc.sv
├── network_interface/
│   ├── axi_lite_if.sv
│   ├── coherence_if.sv
│   ├── ibex_to_axi_lite.sv
│   ├── axi_lite_to_mesh.sv
│   └── mesh_to_axi_lite.sv
├── node/
│   ├── ibex_node.sv
│   ├── shared_ram_node.sv
│   ├── uart_node.sv
│   ├── gpio_node.sv
│   ├── timer_node.sv
│   └── mailbox_node.sv
├── riscV/
│   └── ibex_axi_tile.sv
├── router/
│   ├── router_pkg.sv
│   ├── vc_fifo.sv
│   ├── input_port_vc.sv
│   ├── packet_arbiter.sv
│   └── router_vc.sv
└── ip_core/
    ├── axi_lite_rom.sv
    ├── axi_lite_ram.sv
    ├── axi_lite_uart.sv
    ├── axi_lite_gpio.sv
    ├── axi_lite_timer.sv
    └── axi_lite_mailbox.sv
```

Source `ibex_top` và toàn bộ lowRISC primitive dependency nằm trong `third_party/ibex`. Thứ tự biên dịch chính thức nằm trong `ibex_mesh_soc.core`.

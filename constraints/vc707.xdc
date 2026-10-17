## Xilinx VC707 (XC7VX485T-2FFG1761C)

## 200 MHz LVDS system clock
set_property PACKAGE_PIN E19 [get_ports SYSCLK_P]
set_property PACKAGE_PIN E18 [get_ports SYSCLK_N]
set_property IOSTANDARD LVDS [get_ports {SYSCLK_P SYSCLK_N}]
create_clock -name sys_clk_200mhz -period 5.000 [get_ports SYSCLK_P]

## CPU reset pushbutton SW8, active high
set_property PACKAGE_PIN AV40 [get_ports CPU_RESET]
set_property IOSTANDARD LVCMOS18 [get_ports CPU_RESET]

## Eight DIP switches
set_property PACKAGE_PIN AV30 [get_ports {GPIO_DIP_SW[0]}]
set_property PACKAGE_PIN AY33 [get_ports {GPIO_DIP_SW[1]}]
set_property PACKAGE_PIN BA31 [get_ports {GPIO_DIP_SW[2]}]
set_property PACKAGE_PIN BA32 [get_ports {GPIO_DIP_SW[3]}]
set_property PACKAGE_PIN AW30 [get_ports {GPIO_DIP_SW[4]}]
set_property PACKAGE_PIN AY30 [get_ports {GPIO_DIP_SW[5]}]
set_property PACKAGE_PIN BA30 [get_ports {GPIO_DIP_SW[6]}]
set_property PACKAGE_PIN BB31 [get_ports {GPIO_DIP_SW[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {GPIO_DIP_SW[*]}]

## Eight user LEDs
set_property PACKAGE_PIN AM39 [get_ports {GPIO_LED[0]}]
set_property PACKAGE_PIN AN39 [get_ports {GPIO_LED[1]}]
set_property PACKAGE_PIN AR37 [get_ports {GPIO_LED[2]}]
set_property PACKAGE_PIN AT37 [get_ports {GPIO_LED[3]}]
set_property PACKAGE_PIN AR35 [get_ports {GPIO_LED[4]}]
set_property PACKAGE_PIN AP41 [get_ports {GPIO_LED[5]}]
set_property PACKAGE_PIN AP42 [get_ports {GPIO_LED[6]}]
set_property PACKAGE_PIN AU39 [get_ports {GPIO_LED[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {GPIO_LED[*]}]

## FPGA TX -> Silicon Labs CP2103 USB/UART bridge
set_property PACKAGE_PIN AU33 [get_ports USB_UART_TX]
set_property IOSTANDARD LVCMOS18 [get_ports USB_UART_TX]

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

## DIP/reset buttons are asynchronous, not clocked external interfaces.
set_false_path -from [get_ports {GPIO_DIP_SW[*]}] -to [get_cells -hier -filter {NAME =~ *dip_meta_q_reg*}]
set_false_path -from [get_ports CPU_RESET]
## LED/UART outputs are not synchronous board receivers. Bound internal output
## paths with a 2 ns budget against the generated SoC clock, not the 200 MHz input.
set soc_clock [get_clocks -of_objects [get_pins u_clock_mmcm/CLKOUT0]]
set_output_delay -clock $soc_clock -max 2.0 [get_ports {GPIO_LED[*] USB_UART_TX}]
set_output_delay -clock $soc_clock -min 0.0 [get_ports {GPIO_LED[*] USB_UART_TX}]

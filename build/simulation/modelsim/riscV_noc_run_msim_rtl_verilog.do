transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/node {D:/project_verilog/noc_riscV/rtl/node/ram_obi.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/Top_module_riscV_noc.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/Register_File.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/Program_Counter.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/MEM_WB.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/imm_extend.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/IF_ID.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/ID_EX.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/Hazard_Unit.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/Forwarding_Unit.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/EX_MEM.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/cpu_obi_bridge.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/control_unit.v}
vlog -vlog01compat -work work +incdir+D:/project_verilog/noc_riscV/rtl/riscV {D:/project_verilog/noc_riscV/rtl/riscV/ALU.v}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/mesh_3x3 {D:/project_verilog/noc_riscV/rtl/mesh_3x3/mesh_3x3.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/node {D:/project_verilog/noc_riscV/rtl/node/master_node.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/node {D:/project_verilog/noc_riscV/rtl/node/slave_node.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/node {D:/project_verilog/noc_riscV/rtl/node/tg_node.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/node {D:/project_verilog/noc_riscV/rtl/node/traffic_gen.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/network_interface {D:/project_verilog/noc_riscV/rtl/network_interface/slave_ni.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/network_interface {D:/project_verilog/noc_riscV/rtl/network_interface/master_ni.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/xy_routing.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/router_top.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/output_port.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/input_port.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/fifo_buffer.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/crossbar_switch.sv}
vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/rtl/router {D:/project_verilog/noc_riscV/rtl/router/arbiter.sv}

vlog -sv -work work +incdir+D:/project_verilog/noc_riscV/build/../tb {D:/project_verilog/noc_riscV/build/../tb/tb_mesh_3x3_latency.sv}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneii_ver -L rtl_work -L work -voptargs="+acc"  tb_mesh_3x3_latency

add wave *
view structure
view signals
run -all

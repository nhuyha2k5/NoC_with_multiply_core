# Out-of-context synthesis of one module for quick LUT/FF/timing estimates.
# Usage: vivado -mode batch -source scripts/ooc/ooc_synth.tcl -tclargs <out_dir> <top> <file1.sv> <file2.sv>
# Example (one D-cache): -tclargs build/ooc/cache dcache_ooc_wrap rtl/cache/mesi_dcache.sv scripts/ooc/dcache_ooc_wrap.sv
set R [file normalize [file join [file dirname [info script]] ../..]]
set out [lindex $argv 0]
set top [lindex $argv 1]
file mkdir $out
read_verilog -sv [list $R/rtl/router/router_pkg.sv $R/rtl/cache/coherence_pkg.sv $R/rtl/network_interface/axi_lite_if.sv \
  $R/rtl/network_interface/coherence_if.sv [lindex $argv 2] [lindex $argv 3]]
synth_design -top $top -part xc7vx485tffg1761-2 -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period 10.0 [get_ports clk_i]
report_utilization -file $out/util.rpt
report_utilization -hierarchical -file $out/util_hier.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
puts "OOC_DONE $top"

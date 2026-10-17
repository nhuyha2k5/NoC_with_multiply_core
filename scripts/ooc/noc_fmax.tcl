# NoC-alone Fmax: out-of-context synthesis + place + route of noc_fmax_wrap
# (mesh_3x3_vc with registered boundary) on XC7VX485T-2.
# Usage: vivado -mode batch -source scripts/ooc/noc_fmax.tcl -tclargs <out_dir> <period_ns>
# Fmax = 1000 / (period - WNS) MHz from the post-route register-to-register paths.
# Unregistered top-level port paths have no I/O delay and are unconstrained by
# design (the harness registers every port), so they do not enter WNS.
set R [file normalize [file join [file dirname [info script]] ../..]]
set out [file normalize [lindex $argv 0]]
set period [lindex $argv 1]
file mkdir $out
read_verilog -sv [list $R/rtl/router/router_pkg.sv $R/rtl/router/vc_fifo.sv $R/rtl/router/input_port_vc.sv \
  $R/rtl/router/packet_arbiter.sv $R/rtl/router/router_vc.sv $R/rtl/mesh_3x3/mesh_3x3_vc.sv \
  $R/scripts/ooc/noc_fmax_wrap.sv]
synth_design -top noc_fmax_wrap -part xc7vx485tffg1761-2 -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name clk -period $period [get_ports clk_i]
report_utilization -file $out/util_synth.rpt
report_timing_summary -max_paths 10 -file $out/timing_synth.rpt
set synth_wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
opt_design
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
report_utilization -file $out/util_route.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $out/util_hier_route.rpt
report_timing_summary -max_paths 10 -file $out/timing_route.rpt
report_timing -delay_type max -max_paths 10 -file $out/critical_paths.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set fmax [expr {1000.0 / ($period - $wns)}]
set f [open $out/result.txt w]
puts $f "period_ns=$period\nsynth_wns_ns=$synth_wns\nroute_wns_ns=$wns\nroute_whs_ns=$whs\nfmax_mhz=[format %.1f $fmax]"
close $f
puts "NOC_FMAX period=$period synth_wns=$synth_wns route_wns=$wns whs=$whs fmax_mhz=[format %.1f $fmax]"

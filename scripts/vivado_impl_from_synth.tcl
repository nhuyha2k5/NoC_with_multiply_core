# Re-run implementation from an existing post_synth.dcp with chosen directives.
# Usage:
#   vivado -mode batch -source scripts/vivado_impl_from_synth.tcl -tclargs \
#     <post_synth.dcp> <out_dir> <place_directive> <route_directive> ?<clock_hz>?
# Used for timing-closure sweeps without repeating synthesis. Reports match
# scripts/vivado_post_route.tcl so scripts/summarize_postroute.py works on them.
if {[llength $argv]<4} {error "Usage: post_synth.dcp out_dir place_directive route_directive ?clock_hz?"}
set dcp [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set place_dir [lindex $argv 2]
set route_dir [lindex $argv 3]
set hz 100000000
if {[llength $argv]>4} {set hz [lindex $argv 4]}
file mkdir $out
open_checkpoint $dcp
opt_design -directive Explore
place_design -directive $place_dir
phys_opt_design -directive AggressiveExplore
route_design -directive $route_dir
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $out post_route.dcp]
report_utilization -file [file join $out utilization_route.rpt]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out utilization_hier_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $out timing_route.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $out critical_paths.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc_route.rpt]
report_methodology -file [file join $out methodology.rpt]
set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set critical_drc [llength [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set reqp_1839 [llength [get_drc_violations -quiet -filter {NAME =~ "REQP-1839*"}]]
set drc_warnings [llength [get_drc_violations -quiet -filter {SEVERITY == "Warning"}]]
set f [open [file join $out result.txt] w]
puts $f "clock_hz=$hz\nsetup_slack_ns=$setup_slack\nhold_slack_ns=$hold_slack\ncritical_drc=$critical_drc\nreqp_1839=$reqp_1839\ndrc_warnings=$drc_warnings\nplace_directive=$place_dir\nroute_directive=$route_dir"
close $f
puts "IMPL_COMPLETE place=$place_dir route=$route_dir setup=$setup_slack hold=$hold_slack"

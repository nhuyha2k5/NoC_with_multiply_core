if {[llength $argv]<3} {error "Usage: project.xpr reports firmware-directory ?clock-hz?"}
set xpr [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set fw [file normalize [lindex $argv 2]]
set hz 100000000
if {[llength $argv]>3} {set hz [lindex $argv 3]}
file mkdir $out
open_project $xpr
set includes {}
foreach dir [get_property include_dirs [get_filesets sources_1]] {
  lappend includes [file normalize [file join [file dirname $xpr] $dir]]
}
set_property include_dirs $includes [get_filesets sources_1]
foreach hart {0 1 2 3} {
  set img [file join $fw core$hart.mem]
  add_files -norecurse $img
  set_property file_type {Memory Initialization Files} [get_files $img]
}
set_property generic [list CLOCK_HZ=$hz ROM0_INIT_FILE=[file join $fw core0.mem] ROM1_INIT_FILE=[file join $fw core1.mem] ROM2_INIT_FILE=[file join $fw core2.mem] ROM3_INIT_FILE=[file join $fw core3.mem]] [get_filesets sources_1]
update_compile_order -fileset sources_1
# Keep the generated project in place. Vivado save_project_as rewrites relative
# include directories against the new project directory even when normalized.
synth_design -top vc707_top -part xc7vx485tffg1761-2 -flatten_hierarchy rebuilt
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization -file [file join $out utilization_synth.rpt]
report_timing_summary -file [file join $out timing_synth.rpt]
opt_design -directive Explore
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $out post_route.dcp]
report_utilization -file [file join $out utilization_route.rpt]
# Per-block resources (router, NI, cache, CPU, IP) for the resource breakdown.
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $out utilization_hier_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $out timing_route.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $out critical_paths.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc_route.rpt]
report_power -file [file join $out power_route.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_methodology -file [file join $out methodology.rpt]
set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
set critical_drc [llength [get_drc_violations -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]
set reqp_1839 [llength [get_drc_violations -quiet -filter {NAME =~ "REQP-1839*"}]]
set drc_warnings [llength [get_drc_violations -quiet -filter {SEVERITY == "Warning"}]]
set f [open [file join $out result.txt] w]
puts $f "clock_hz=$hz\nsetup_slack_ns=$setup_slack\nhold_slack_ns=$hold_slack\ncritical_drc=$critical_drc\nreqp_1839=$reqp_1839\ndrc_warnings=$drc_warnings"
close $f
puts "POST_ROUTE_COMPLETE clock=$hz setup=$setup_slack hold=$hold_slack"
if {$setup_slack>=0 && $hold_slack>=0 && $critical_drc==0} {
  puts "POST_ROUTE_TIMING_PASS"
} else {
  puts "POST_ROUTE_TIMING_NOT_CLOSED"
}
close_project

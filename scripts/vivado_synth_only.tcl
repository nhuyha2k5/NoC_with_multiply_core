# Run synthesis in the current Vivado process. This avoids the Windows
# launch_runs helper and does not start implementation or bitstream generation.
if {[llength $argv] < 2} {
  error "Usage: vivado_synth_only.tcl <project.xpr> <report-directory>"
}

set xpr_path  [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]

if {![file exists $xpr_path]} {
  error "Vivado project does not exist: $xpr_path"
}

file mkdir $report_dir
open_project $xpr_path
update_compile_order -fileset sources_1

synth_design -top vc707_top -part xc7vx485tffg1761-2 -flatten_hierarchy rebuilt

write_checkpoint -force [file join $report_dir vc707_post_synth.dcp]
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 \
  -file [file join $report_dir timing_synth.rpt]
report_drc -file [file join $report_dir drc_synth.rpt]

puts "SYNTHESIS_PASS: vc707_top"
puts "REPORT_DIRECTORY: $report_dir"
close_project

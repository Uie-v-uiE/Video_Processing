# Full flow: create PL project + synth + impl + bitstream
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado]
set proj_name zynq_video_pipeline
set part xc7z020clg484-2

create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom process/bilin axi hdmi top} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] {
    lappend rtl_files $f
  }
}
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]
set_property top pl_demo_top [current_fileset]
update_compile_order -fileset sources_1

# synth
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "SYNTH FAILED"
  exit 1
}
puts "SYNTH DONE"

# impl + bit
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "IMPL FAILED"
  puts [get_property STATUS [get_runs impl_1]]
  exit 1
}

set bit [file join $proj_dir ${proj_name}.runs impl_1 pl_demo_top.bit]
set outdir [file join $root build]
file mkdir $outdir
file copy -force $bit [file join $outdir video_pipeline.bit]
puts "BIT: [file join $outdir video_pipeline.bit]"

# timing summary
open_run impl_1
report_timing_summary -file [file join $outdir timing_summary.rpt]
puts "TIMING REPORT: [file join $outdir timing_summary.rpt]"
puts "BUILD OK"



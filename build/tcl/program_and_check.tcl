# Program FPGA and report timing path
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build video_pipeline.bit]
set rpt [file join $root build timing_summary.rpt]

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAMMED $dev with $bit"

# quick timing path from last impl if project exists
set xpr [file join $root vivado zynq_video_pipeline.xpr]
if {[file exists $xpr]} {
  open_project $xpr
  open_run impl_1
  report_timing_summary -file $rpt
  puts "=== CRITICAL PATHS ==="
  foreach p [get_timing_paths -max_paths 5 -nworst 1] {
    puts "WNS=[get_property SLACK $p]  FROM=[get_property FROM $p]  TO=[get_property TO $p]"
  }
}
puts "DONE"


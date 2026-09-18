# Validate CDC constraints on existing routed design + regenerate reports
set root "D:/Xilinx/Prj/ADD/Video_Pipeline-main"
set outdir [file join $root build]
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys

open_project [file join $proj_dir ${proj_name}.xpr]
open_run impl_1

# Apply the same async groups used in XDC (clocks now all exist)
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]

report_timing_summary -file [file join $outdir timing_summary.rpt]
report_power -file [file join $outdir power.rpt]
report_utilization -file [file join $outdir utilization.rpt]

puts "==== CLOCK LIST ===="
foreach c [get_clocks] {
  puts [format "  %-16s period=%s" [get_property NAME $c] [get_property PERIOD $c]]
}
puts "CDC CONSTRAINTS APPLIED"
puts "REPORTS: timing_summary.rpt power.rpt utilization.rpt"

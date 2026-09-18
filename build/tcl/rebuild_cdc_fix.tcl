# Re-impl with refreshed XDC (disable incremental synth reference)
set root "D:/Xilinx/Prj/ADD/Video_Pipeline-main"
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set outdir [file join $root build]

# After synth, re-read XDC with clocks present, then impl
# (full rebuild with FIFO BRAM fix + CDC XDC)
set inc [file join $proj_dir ${proj_name}.srcs utils_1 imports synth_1 system_top.dcp]
if {[file exists $inc]} {
  file delete -force $inc
  puts "Deleted incremental checkpoint $inc"
}

open_project [file join $proj_dir ${proj_name}.xpr]
set xdc [file join $root src constraints rk_zynq7020.xdc]
set_property target_constrs_file $xdc [get_filesets constrs_1]

set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
}
lappend rtl_files [file join $root src rtl top pl_video_top.v]
lappend rtl_files [file join $root src rtl top system_top.v]
add_files -norecurse $rtl_files
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "SYNTH FAILED"
  exit 1
}

set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "IMPL FAILED"
  exit 1
}

set bit [file join $proj_dir ${proj_name}.runs impl_1 system_top.bit]
if {![file exists $bit]} {
  set bit [lindex [glob -nocomplain [file join $proj_dir ${proj_name}.runs impl_1 *.bit]] 0]
}
file copy -force $bit [file join $outdir system.bit]
open_run impl_1
report_timing_summary -file [file join $outdir timing_summary.rpt]
report_utilization -file [file join $outdir utilization.rpt]
report_power -file [file join $outdir power.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]
puts "BIT: [file join $outdir system.bit]"
puts "XSA: [file join $outdir system.xsa]"
puts "SYSTEM BUILD DONE"

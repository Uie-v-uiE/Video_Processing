# Incremental rebuild after timing/power/host optimizations
set root [file normalize [file join [file dirname [info script]] .. ..]]   ;# 仓库根自适应（原来硬编码 D:/Xilinx/Prj/ADD/... 那个路径已不存在）
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set outdir [file join $root build]

open_project [file join $proj_dir ${proj_name}.xpr]

# refresh constraints + RTL
set xdc [file join $root src constraints rk_zynq7020.xdc]
add_files -fileset constrs_1 -norecurse $xdc
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
  puts "SYNTH FAILED [get_property STATUS [get_runs synth_1]]"
  exit 1
}

# power-oriented impl options
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE false [get_runs impl_1]

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
  puts "IMPL FAILED [get_property STATUS [get_runs impl_1]]"
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
report_clock_utilization -file [file join $outdir clock_util.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]

# extract key numbers for OPTIMIZATION_LOG
set ts [open [file join $outdir timing_summary.rpt] r]
set timing_blob [read $ts]
close $ts
puts "==== TIMING EXTRACT ===="
foreach pat {
  {WNS.*}
  {TNS.*}
  {clk_fpga_0.*}
  {eth_rxc.*}
  {sys_clk.*}
} {
  # printed via report already
}
puts "BIT: [file join $outdir system.bit]"
puts "XSA: [file join $outdir system.xsa]"
puts "POWER: [file join $outdir power.rpt]"
puts "SYSTEM BUILD DONE"

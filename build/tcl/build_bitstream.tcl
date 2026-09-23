# Synthesize + implement + bitstream
# Usage: vivado -mode batch -source tcl/build_bitstream.tcl
# Optional arg: pl|system (default pl)

set mode "pl"
if {[llength $argv] > 0} { set mode [lindex $argv 0] }

set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado]
set proj_name zynq_video_pipeline
set xpr [file join $proj_dir ${proj_name}.xpr]

open_project $xpr

if {$mode eq "pl"} {
  set_property top pl_demo_top [current_fileset]
} else {
  set_property top system_top [current_fileset]
}
update_compile_order -fileset sources_1

# Launch runs
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit [file join $proj_dir ${proj_name}.runs impl_1 ${mode}.bit]
# actual name uses top
if {$mode eq "pl"} {
  set bit [file join $proj_dir ${proj_name}.runs impl_1 pl_demo_top.bit]
} else {
  set bit [file join $proj_dir ${proj_name}.runs impl_1 system_top.bit]
}

puts "BITSTREAM: $bit"

# Copy to output/
set outdir [file join $root build]
file mkdir $outdir
file copy -force $bit [file join $outdir video_pipeline.bit]

if {$mode eq "system"} {
  set xsa [file join $outdir system.xsa]
  write_hw_platform -fixed -include_bit -force -file $xsa
  puts "XSA: $xsa"
}

puts "DONE"


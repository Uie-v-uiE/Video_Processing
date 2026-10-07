# build/gen_bit.tcl
# 作用: 生成 .bit 与 .xsa（含 hwh），并把两者归档到 board/
# 前置条件: 工程已建好且实现跑到 route_design 或更后（impl.tcl / build.tcl）
# 产出物: board/system.bit、board/system.xsa（VP_BIT_DIR 可改目录，验证时用别的目录免得覆盖在板那一版）
# 关键参数: VP_PROJ_SUBDIR、VP_BIT_DIR；若 impl_1 里还没有 bit，本脚本会补跑到 write_bitstream
# 退出码: 0=两份产物都落盘 非 0=工程缺失或产物缺失
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_subdir vivado_system
if {[info exists ::env(VP_PROJ_SUBDIR)] && $::env(VP_PROJ_SUBDIR) ne ""} { set proj_subdir $::env(VP_PROJ_SUBDIR) }
set xpr [file join $root $proj_subdir zynq_video_sys.xpr]
if {![file exists $xpr]} { puts "NO_PROJECT $xpr"; exit 1 }
set board [file join $root board]
if {[info exists ::env(VP_BIT_DIR)] && $::env(VP_BIT_DIR) ne ""} { set board [file normalize [file join $root $::env(VP_BIT_DIR)]] }
file mkdir $board
set runs [file join $root $proj_subdir zynq_video_sys.runs impl_1]
open_project $xpr
if {![file exists [file join $runs system_top.bit]]} {
  launch_runs impl_1 -to_step write_bitstream -jobs 4
  wait_on_run impl_1
}
open_run impl_1
if {![file exists [file join $runs system_top.bit]]} {
  write_bitstream -force [file join $runs system_top.bit]
}
write_hw_platform -fixed -include_bit -force -file [file join $board system.xsa]
file copy -force [file join $runs system_top.bit] [file join $board system.bit]
close_project
set ok 1
foreach f {system.bit system.xsa} {
  if {![file exists [file join $board $f]]} { puts "ARTIFACT_MISSING $f"; set ok 0 }
}
puts "ARCHIVE_DIR $board"
if {!$ok} { exit 1 }

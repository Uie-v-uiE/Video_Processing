# build/impl.tcl
# 作用: 在综合结果之上单独跑实现（布局布线到 route_design），可单独执行；比特流由 gen_bit.tcl 负责
# 前置条件: 综合已完成（synth.tcl 或 build.tcl 的前半）
# 产出物: <工程目录>/zynq_video_sys.runs/impl_1/ 的布线结果与 runme.log
# 关键参数: VP_PROJ_SUBDIR；IMPL_STRATEGY 只设已存在 run 的 strategy 属性（不改脚本，产物要自己带出身）
# 退出码: 0=实现跑到 100% 非 0=工程缺失或实现未完成
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_subdir vivado_system
if {[info exists ::env(VP_PROJ_SUBDIR)] && $::env(VP_PROJ_SUBDIR) ne ""} { set proj_subdir $::env(VP_PROJ_SUBDIR) }
set xpr [file join $root $proj_subdir zynq_video_sys.xpr]
if {![file exists $xpr]} { puts "NO_PROJECT $xpr"; exit 1 }
open_project $xpr
if {[info exists ::env(IMPL_STRATEGY)] && $::env(IMPL_STRATEGY) ne ""} {
  if {[catch {set_property -dict [list strategy $::env(IMPL_STRATEGY)] [get_runs impl_1]} e]} {
    puts "BUILD_STRATEGY_REJECTED $::env(IMPL_STRATEGY) : $e"
    exit 1
  }
}
puts "BUILD_STRATEGY [get_property STRATEGY [get_runs impl_1]]"
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set st [get_property PROGRESS [get_runs impl_1]]
puts "IMPL_PROGRESS $st"
if {$st ne "100%"} { puts "IMPL_FAILED [get_property STATUS [get_runs impl_1]]"; exit 1 }
close_project

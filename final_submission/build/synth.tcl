# build/synth.tcl
# 作用: 只对已建好的工程跑综合，可单独执行（改完 RTL 想先看网表与告警时用它，不必等实现）
# 前置条件: 已跑过 create_project.tcl 或 add_sources.tcl；工程文件存在
# 产出物: <工程目录>/zynq_video_sys.runs/synth_1/ 的综合结果与 runme.log
# 关键参数: VP_PROJ_SUBDIR 指定工程目录（分步验证时指到别处，别覆盖正式工程）
# 退出码: 0=综合 100% 非 0=工程缺失或综合未收敛完成
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_subdir vivado_system
if {[info exists ::env(VP_PROJ_SUBDIR)] && $::env(VP_PROJ_SUBDIR) ne ""} { set proj_subdir $::env(VP_PROJ_SUBDIR) }
set xpr [file join $root $proj_subdir zynq_video_sys.xpr]
if {![file exists $xpr]} { puts "NO_PROJECT $xpr"; exit 1 }
open_project $xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set st [get_property PROGRESS [get_runs synth_1]]
puts "SYNTH_PROGRESS $st"
if {$st ne "100%"} { puts "SYNTH_FAILED [get_property STATUS [get_runs synth_1]]"; exit 1 }
close_project

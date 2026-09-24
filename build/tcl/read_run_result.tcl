# build/tcl/read_run_result.tcl —— 把 `.runs/impl_1` **现在**这份实现结果的三个数抄出来（不重建、不改产物）
#
#   vivado -mode batch -nojournal -source build/tcl/read_run_result.tcl
#
# 为什么单独要一个：`sweep_impl_strategy.tcl` 每换一个策略都要 5~8 分钟重跑实现，
# 而"报告那一行写错了参数"这种失败会发生在**实现已经跑完之后** —— 没有这个只读工具，
# 就只能把 5~8 分钟白烧一遍（2026-09-25 真踩：`report_timing_summary -check_summary_only`
# 在 2025.2.1 不存在，脚本在 open_run 之后当场挂掉，PostRoutePhysOpt 那一跑的数就这么丢了）。
#
# 可选参数（环境变量）：
#   READ_STRAT_RESTORE=<策略名>  读完后把 impl_1 的 strategy 属性改回去（扫描脚本被打断时用）
set root [file normalize [file join [file dirname [info script]] .. ..]]
set proj [file join $root vivado_system zynq_video_sys.xpr]
if {![file exists $proj]} { puts "MISSING $proj"; exit 1 }
open_project $proj
puts "CURRENT_STRATEGY [get_property STRATEGY [get_runs impl_1]]"
puts "RUN_STATUS [get_property STATUS [get_runs impl_1]] PROGRESS [get_property PROGRESS [get_runs impl_1]]"
open_run impl_1
set out [file join $root build read_run_timing.rpt]
report_timing_summary -file $out -max_paths 3
puts "WROTE: $out"
set fd [open $out r]; set txt [read $fd]; close $fd
if {[regexp -- {\s+(-?[0-9]+\.[0-9]+)\s+-?[0-9]+\.[0-9]+\s+(\d+)\s+\d+\s+(-?[0-9]+\.[0-9]+)} $txt -> wns fem whs]} {
    puts "READ_RESULT WNS=$wns WHS=$whs fail_setup_endpoints=$fem"
} else { puts "READ_RESULT 解析不到 Design Timing Summary 那一行 —— 报告格式变了？" }
if {[string match "*All user specified timing constraints are met*" $txt]} { puts "ALL_CONSTRAINTS_MET YES" } else { puts "ALL_CONSTRAINTS_MET NO" }
catch {puts "TOTAL_POWER_W [format %.3f [get_property TOTAL_POWER [get_power]]]"}
close_design
if {[info exists ::env(READ_STRAT_RESTORE)] && $::env(READ_STRAT_RESTORE) ne ""} {
    set_property strategy $::env(READ_STRAT_RESTORE) [get_runs impl_1]
    puts "STRATEGY_RESTORED_TO [get_property STRATEGY [get_runs impl_1]]"
}
puts "READ RUN RESULT DONE"
exit 0

# build/tcl/sweep_impl_strategy.tcl — 实现策略扫描（同一份网表，逐个策略重跑实现并汇总时序）
#
#   vivado -mode batch -nojournal -log build/sweep.log -source build/tcl/sweep_impl_strategy.tcl
#
# 前提：build_system_axigpio.tcl 已经跑过一次（本脚本复用 vivado_system/zynq_video_sys.xpr，
# 只重跑 impl_1，不重建 BD、不重跑综合 —— 一次完整重建约 15 分钟，单个策略约 5-8 分钟）。
#
# 为什么需要它：第五版把 Slice 占用从 99.92% 降到 18%，布局器突然有了大量余量，
# 于是"时序还剩多少"主要由**实现策略**而不是 RTL 决定。改 RTL 之前先用数据确认这一点。
#
# 输出：build/sweep_summary.txt（每行：策略 WNS WHS 失败端点 是否全约束满足 功耗）
#       build/sweep_<策略>_timing.rpt（逐策略留档）
# 环境变量 SWEEP_STRATS 可覆盖策略列表（逗号或空格分隔）。
#
# 注意：2025.2.1 对本器件**不支持** Flow_PerfOptimized_high / Performance_RetimingTDM 等
# 名字（set_property strategy 会直接报错），下面的清单是试探出来的可用集合。

set root [file normalize [file join [file dirname [info script]] .. ..]]
set proj [file join $root vivado_system zynq_video_sys.xpr]
if {![file exists $proj]} { puts "MISSING $proj  -- 先跑 build_system_axigpio.tcl"; exit 1 }
open_project $proj

set strats {Performance_Explore Performance_ExplorePostRoutePhysOpt \
            Performance_ExploreWithRemap Performance_ExtraTimingOpt Performance_BalanceSLRs}
if {[info exists ::env(SWEEP_STRATS)] && $::env(SWEEP_STRATS) ne ""} {
    set strats [split [string map {, " "} $::env(SWEEP_STRATS)] " "]
}
set out [file join $root build "sweep_summary_[clock format [clock seconds] -format %Y%m%d_%H%M].txt"]
# ⚠ 输出文件名带时间戳，**不再覆盖** build/sweep_summary.txt —— 那份是 V7.4 的历史凭据，
#   `report/CHANGELOG_V7.md:199` 与 `OVERNIGHT_LOG.md:527` 都按名字引它（引的就是"只完成 1/5 策略就中断"这件事）。
set fh [open $out w]
puts $fh "# 实现策略扫描（同一份网表，逐策略重跑 impl_1）—— [clock format [clock seconds]]"
puts $fh "# 用法：SWEEP_STRATS=\"A B C\" vivado -mode batch -source build/tcl/sweep_impl_strategy.tcl"
puts $fh "# 注意：跑完后 vivado_system 里 impl_1 的 strategy 属性会停在**最后一个被扫的策略**，"
puts $fh "#       下一次完整构建会重写它；但在那之前不要拿 .runs 里的 dcp 当交付件。"
puts $fh "strategy\tWNS\tWHS\tfail_endpoints\tall_constraints_met\ttotal_power_W"
set orig_strat [get_property STRATEGY [get_runs impl_1]]

foreach s $strats {
    puts "########## SWEEP $s ##########"
    if {[catch {
        reset_run impl_1
        set_property strategy $s [get_runs impl_1]
        launch_runs impl_1 -to_step write_bitstream -jobs 4
        wait_on_run impl_1
    } err]} {
        puts "SWEEP $s FAILED: $err"
        puts $fh "$s\tERROR\t-\t-\t-\t-"
        continue
    }
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        puts "SWEEP $s INCOMPLETE [get_property STATUS [get_runs impl_1]]"
        puts $fh "$s\tINCOMPLETE\t-\t-\t-\t-"
        continue
    }
    open_run impl_1
    # 只从报告文本取数：属性名跨版本不稳，文本解析最可靠
    set trpt [file join $root build "sweep_${s}_timing.rpt"]
    report_timing_summary -file $trpt -max_paths 3 -check_summary_only
    set fd [open $trpt r]; set txt [read $fd]; close $fd
    # Design Timing Summary 表头之后的第一行数字：WNS TNS 失败端点 总端点 WHS ...
    set wns "-" ; set whs "-" ; set fem "-"
    if {[regexp -- {\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+(\d+)\s+(\d+)\s+(-?[0-9]+\.[0-9]+)} $txt -> w1 t1 f1 e1 h1]} {
        set wns $w1; set fem $f1; set whs $h1
    }
    set met "NO"; if {[string match "*All user specified timing constraints are met*" $txt]} { set met "YES" }
    set pwr "-"
    catch {set pwr [format %.3f [get_property TOTAL_POWER [get_power]]]}
    close_design
    puts "SWEEP $s WNS=$wns WHS=$whs fail_endpoints=$fem all_met=$met power=$pwr"
    puts $fh "$s\t$wns\t$whs\t$fem\t$met\t$pwr"
}
close $fh
# 把 strategy 属性放回扫描前的值：.runs 里最后一次实现的结果还在，但**下一次构建**不会再
# 悄悄继承最后一个被扫的策略 —— "数字变了但没人改代码"是最难查的那一类。
catch {set_property strategy $orig_strat [get_runs impl_1]}
puts "SWEEP DONE -> $out"
puts "STRATEGY_RESTORED_TO $orig_strat"
exit 0

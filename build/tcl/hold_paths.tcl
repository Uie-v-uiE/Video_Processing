# build/tcl/hold_paths.tcl —— 深度优化那一轮（任务 #46）的第一个问题：**WHS 那 0.0x ns 到底压在哪几条路径上？**
#
#   vivado -mode batch -nojournal -source build/tcl/hold_paths.tcl
#
# 为什么要单独写这个：门禁念的是 `timing_summary.rpt` 里的**一个数字**（WHS），
# 而"这个数字能不能被修、修它会付出什么"必须有**路径级**的答案 —— 不然"深度优化时序"
# 就只能靠换策略碰运气。r51→r56 六版的 WHS 是 +0.048/+0.019/+0.054/+0.012/+0.012/+0.019，
# 来回跳说明它从来没被"修"过，只是每次布局的运气。
#
# 只读：开已布线的 dcp、出报告，不动任何产物（`build/system.bit` 与冻结件不受影响）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set impl_dir [file join $root vivado_system zynq_video_sys.runs impl_1]
set dcp ""
foreach p [list [file join $impl_dir system_top_routed.dcp] \
               [file join $impl_dir system_top_demaged_routed.dcp]] {
    if {[file exists $p]} { set dcp $p; break }
}
if {$dcp eq ""} {
    set c [catch {exec find $impl_dir -maxdepth 1 -name "*routed*.dcp"} r]
    if {!$c} { set dcp [lindex [split [string trim $r] \n] end] }
}
if {$dcp eq "" || ![file exists $dcp]} { puts "NO_DCP（在 $impl_dir 找 *routed*.dcp 没有；构建还在跑？）"; exit 1 }
puts "DCP: $dcp"
open_checkpoint $dcp

set out [file join $root build hold_paths.rpt]
# min（hold）路径：取最差的 20 条，每条只报最坏的那一个端点。
# 为什么是 20 不是一：WHS 是"全局最小裕量"，一次 P&R 里挤在 0.01~0.03 ns 的往往是一族同形状的
# 路径，只看第一条会把"这是一族还是一个孤点"这个关键区别抹掉。
report_timing -delay_type min -nworst 1 -max_paths 20 -file $out
puts "WROTE: $out"

# 顺手把 setup 侧最差的也抄一份口径给对照（不覆盖任何历史件）：这一轮要同时看两端。
set out2 [file join $root build setup_paths.rpt]
report_timing -delay_type max -nworst 1 -max_paths 6 -file $out2
puts "WROTE: $out2"
puts "HOLD PATHS DONE"

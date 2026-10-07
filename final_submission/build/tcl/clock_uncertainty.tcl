# 用途：只读：把"约束里写了"与"工具真的用了"分清楚
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行）
# build/tcl/clock_uncertainty.tcl —— 只读：把"约束里写了"与"工具真的用了"分清楚。
#
#   vivado -mode batch -nojournal -source build/tcl/clock_uncertainty.tcl
#
# 为什么单开这一个：`report/known_issues.md` 里那条"念 WHS 必须带口径"说的是
# `src/constraints/rk_zynq7020.xdc:50` 那句 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`。
# 但**写了不等于生效**——同一个 XDC 文件 51-56 行那笔旧账就是教训：把 `get_clocks` 取不到的
# `clk_fpga_0` 并进 `set_clock_groups` 之后**整条命令静默不生效**，连 eth_rxc/sys_clk 一起废掉，
# 现场只留一句 warning。所以这句话要么拿报告钉住，要么不许写。
#
# 怎么钉：2026-09-30 试过 `report_clock_timing -type uncertainty`，这个版本的 7 系列批处理里
# **没有这条命令**（`invalid command name "report_clock_timing"`）。能直接看见不确定度的地方是
# `report_timing -delay_type min` 的报告头：`Requirement` 与 `- clock uncertainty` 那两行写着
# 工具在这次检查里到底扣了多少。开的是**已布线 dcp**，不重跑任何步骤、不动任何产物。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp ""
foreach p [list [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp] \
               [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_demaged_routed.dcp]] {
    if {[file exists $p]} { set dcp $p; break }
}
if {$dcp eq ""} { puts "NO_DCP（去看实现跑完了没有）"; exit 1 }
puts "DCP: $dcp"
open_checkpoint $dcp

puts "GET_CLOCKS_eth_rxc: [get_clocks -quiet eth_rxc]"
puts "GET_CLOCKS_clk_fpga_0: [get_clocks -quiet clk_fpga_0]"

set out [file join $root build clock_uncertainty.rpt]
set fh [open $out w]
puts $fh "# clock_uncertainty —— 最差 hold 路径的报告头（要求项里看得见不确定度扣了多少）"
puts $fh "# DCP: $dcp"
puts $fh "# XDC 那句：set_clock_uncertainty -hold 0.800 \[get_clocks eth_rxc\]"
puts $fh ""
puts $fh "## (a) 全设计最差那条 min 路径（2026-09-30 实测它在 clk_fpga_0，不在 eth_rxc ⇒ 不吃那句 0.800）"
puts $fh [report_timing -delay_type min -max_paths 1 -nworst 1 -return_string]
puts $fh ""
puts $fh "## (b) `eth_rxc` 自己最差那条 min 路径（这一条才该看得见 0.800 的要求项）"
if {[catch {report_timing -delay_type min -max_paths 1 -nworst 1 -from [get_clocks eth_rxc] -return_string} e]} {
    puts $fh "REPORT_FAILED: $e"
} else {
    puts $fh [report_timing -delay_type min -max_paths 1 -nworst 1 -from [get_clocks eth_rxc] -return_string]
}
close $fh
puts "WROTE: $out"

# 直接在控制台把关键几行抄出来，省得下一步又去猜报告里叫什么名字
proc head {tag r} {
    foreach line [split $r \n] {
        set t [string trim $line]
        if {[string match "Slack*" $t] || [string match "Requirement*" $t] ||
            [string match "*uncertainty*" $t] || [string match "Data Path Requirement*" $t] ||
            [string match "Source:*" $t] || [string match "Destination:*" $t]} { puts "$tag> $t" }
    }
}
head "GLOB" [report_timing -delay_type min -max_paths 1 -nworst 1 -return_string]
if {![catch {report_timing -delay_type min -max_paths 1 -nworst 1 -from [get_clocks eth_rxc] -return_string} r2]} {
    head "ETHRXC" $r2
} else {
    puts "ETHRXC> 取不到：$r2"
}
puts "CLOCK_UNCERTAINTY DONE"

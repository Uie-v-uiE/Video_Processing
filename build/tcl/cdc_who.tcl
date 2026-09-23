# build/tcl/cdc_who.tcl — 回答一个问题：**是哪几个寄存器**让 cdc.rpt 里那一行变 Critical 的？
#
#   vivado -mode batch -nojournal -source build/tcl/cdc_who.tcl
#
# 为什么需要：`report_cdc` 的汇总表只给"源钟→目的钟 + 端点数"，改完 RTL 只知道行数变了，
# 不知道是谁。#27 的门禁在 `clkout0_1 → clk_fpga_0` 这一行上报红（5 端点 / 2 unsafe，
# 而 #23~#25 同一行是 Info / 3 端点 / 0 unsafe），必须先回答"那 2 个 unsafe 是谁"再谈修。
# 做法：读已布线的 dcp，出 -details 报告（每条违规带起点/终点寄存器名）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set impl_dir [file join $root vivado_system zynq_video_sys.runs impl_1]
# 名字不要写死：`-to_step write_bitstream` 产出的 dcp 叫 system_top_routed.dcp，
# 而策略/版本不同时会变成 `*impl_1_routed.dcp`；而且 `create_project -force` 会把整个
# runs 目录删掉重建 —— 构建进行到这 20 分钟之外来跑本脚本，就会撞 NO_DCP（#28 时踩过）。
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

set out [file join $root build cdc_details.rpt]
report_cdc -details -file $out
puts "WROTE: $out"

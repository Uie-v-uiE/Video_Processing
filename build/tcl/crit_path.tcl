# build/tcl/crit_path.tcl —— 最差几条 setup 路径**落在哪条线上**：一行一条，直接读得完
#
#   vivado -mode batch -nojournal -source build/tcl/crit_path.tcl
#
# 为什么要它（`report_timing_summary.rpt` 已经给了 WNS，还差什么）：门禁念的是一个数字，
# 而"这个数字归谁、修它会付出什么"需要**路径级**的答案。#105 那一族就是靠这个看出来的：
# 16 个失败端点全部是 `u_cdc/wbin_reg → u_lm/drop_words_reg[*]/CE` 同一条锥，
# 于是"复制高扇出（max_fanout）"这种猜测可以被一次构建否掉（r83→r84 就是这么归因的）。
# 与两个近亲的分工：`hold_paths.tcl` 出的是 hold 侧的**整份** report_timing 文件，
# 本脚本出的是 setup 侧的**摘要**（每条路径一行：slack / 时钟组 / 起点 / 终点 / 级数 / 布线占比）。
#
# 只读：开已布线的 dcp、出报告，不动任何产物（`build/system.bit` 与冻结件不受影响）。
#
# ⚠ 2026-09-29 重写。旧版第一行是 `open_project D:/Software/Xiaomi_MiMo/...` —— **另一台机器、另一个工程**
#   的绝对路径，而且 `foreach p \` 那种 `$p` 被吞成了一个反斜杠（多半是哪次 heredoc 事故），
#   所以它其实从来没跑起来过；`report/study/` 里三处记着"文件本身已损坏"。现在仓库根自适应、
#   并且这条脚本自己跑通一次才算数（见文件末的 WROTE/打印）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set impl_dir [file join $root vivado_system zynq_video_sys.runs impl_1]
set dcp ""
foreach p [list [file join $impl_dir system_top_routed.dcp] \
               [file join $impl_dir system_top_demaged_routed.dcp]] {
    if {[file exists $p]} { set dcp $p; break }
}
if {$dcp eq ""} { puts "NO_DCP（在 $impl_dir 找 *routed*.dcp 没有；构建还在跑？）"; exit 1 }
puts "DCP: $dcp"
open_checkpoint $dcp

set raw [file join $root build crit_paths_raw.rpt]
# -nworst 1 = 每条路径只报最坏那一个端点（不然 8 条里会重复数同一条锥的兄弟端点）；
# -max_paths 8 = 一屏读得完，而且 #105 那种"一族"从第 2 条就看得出是不是同一条。
report_timing -delay_type max -nworst 1 -max_paths 8 -file $raw

set out [file join $root build crit_paths.txt]
set fh [open $out w]
# ⚠ 这个文件的表头**故意只写 ASCII**：Vivado 的 tclsh 里 `puts` 用的是系统编码（这台机器 cp936），
# 往 UTF-8 的文档/报告里写中文会变成半截字节（2026-09-29 第一次跑出来就是这样，`cat` 全是乱码）。
# 台架判据标签改 ASCII 是同一课，这里照做。
puts $fh "# worst setup paths (source: $raw)"
puts $fh "# slack | clock_group | data_path_delay | logic_levels | start -> end"
set f [open $raw r]
set lines [read $f]
close $f

# 解析按**前缀逐行认领**（regexp），不靠"第几行是什么"：`report_timing` 一个块里的行序是
# Slack / (clock edge info) / Source / (cell info) / Destination / Path Group / Path Type /
# Requirement / Data Path Delay / Logic Levels，按位置取号会把 Path Type 当 Logic Levels 读。
# 也**不用 elseif 链**：Tcl 的 `} elseif {` 必须与条件同串，昨天就是在这里炸的
# （`invalid command name "elseif"`），而独立 `if` 逐行匹配对这段代码没有任何代价。
set slack ""; set grp ""; set src ""; set dst ""; set lv ""; set dly ""; set have 0
foreach line [split $lines \n] {
    set t [string trim $line]
    if {[regexp {^Slack .*:\s*(-?[0-9.]+ns)} $t -> v]} {
        if {$have} {
            puts $fh "$slack | [string trim $grp] | $dly | $lv | $src -> $dst"
        }
        set have 1; set slack $v; set grp ""; set src ""; set dst ""; set lv ""; set dly ""
        continue
    }
    if {[regexp {^Source:\s*(\S+)}      $t -> v]} { set src $v }
    if {[regexp {^Destination:\s*(\S+)} $t -> v]} { set dst $v }
    if {[regexp {^Path Group:\s*(\S+)}  $t -> v]} { set grp $v }
    if {[regexp {^Logic Levels:\s*(\d+)} $t -> v]} { set lv $v }
    if {[regexp {^Data Path Delay:\s*(\S+)} $t -> v]} { set dly $v }
}
if {$have} { puts $fh "$slack | [string trim $grp] | $dly | $lv | $src -> $dst" }
close $fh
puts "WROTE: $out"
# 一屏摘要直接打到 stdout：夜里读日志的人不必再去开 60KB 的原报告。
set f [open $out r]
while {[gets $f line] >= 0} { puts "  $line" }
close $f
exit 0

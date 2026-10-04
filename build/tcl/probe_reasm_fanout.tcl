# 用途：只读探针：量 r107 那一刀对它**自己的目标族**做了什么
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/probe_reasm_fanout.tcl —— 只读探针：量 r107 那一刀对它**自己的目标族**做了什么
#   为什么需要它：链子的 r107_fanout_verdict.txt 只列全设计最差 10 条，而这一刀的判据是
#   "u_reasm 这一族的 route 占比 + 那根使能网络的扇出"（#121/#175）。这一族在 r107 里已经
#   **不在最差 10 条里**了，所以"它现在是多少"必须单独问一次，不能用"没进前十"含糊带过。
#   对比基准 r106（build/r106_critpath_console.txt 第 103..108 行）：这一族是
#   off_reg[12]/C -> rows_hit_reg[*]/CE，0.723 ns，5 级，route 占 81.25 %，最差 8 条里占 6 条。
#   绝对 WNS 差值按规矩 35 不算收益也不算损失，所以这里量的是族级读数，不是全局 WNS。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
puts "DCP: $dcp"
open_checkpoint $dcp

# ---- A. 这一族现在的最差 slack（起点沿用 r106 最差那条的 off_reg[12]，终点整片 rows_hit）----
puts "=== A family worst slack: u_reasm/off_reg[12] -> u_reasm/rows_hit_reg[*] ==="
set froms [get_cells -quiet {u_eth/u_reasm/off_reg[12]}]
set tos   [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}]
puts "  SETS from=[llength $froms] to=[llength $tos]  (to is expected = rows_hit width; 0 means a wrong name)"
if {[llength $froms] > 0 && [llength $tos] > 0} {
    set rpt [file join $root "build/r107_probe_reasm.rpt"]
    report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 3 -file $rpt
    set fh [open $rpt r]
    set txt [read $fh]
    close $fh
    foreach line [split $txt "\n"] {
        set t [string trim $line]
        if {[string match "Slack*" $t] || [string match "Data Path Delay*" $t] \
            || [string match "Logic Levels*" $t] || [string match "Source:*" $t] \
            || [string match "Destination:*" $t] || [string match "Path Group:*" $t]} {
            puts "  $t"
        }
    }
} else {
    puts "  SKIP A: empty collection (B still runs)"
}

# ---- B. 这一族里扇出最大的网络（r106 的那根是 fo=316 的使能广播）----
puts "=== B top-6 fanout nets inside u_eth/u_reasm ==="
set cells [get_cells -quiet u_eth/u_reasm/*]
puts "  CELLS in this family: [llength $cells]"
array set best ""
foreach c $cells {
    foreach p [get_pins -of_objects $c] {
        set n [get_nets -of_objects $p]
        if {$n eq ""} continue
        if {[info exists best($n)]} continue
        set best($n) [llength [get_pins -of_objects $n]]
    }
}
set pairs {}
foreach n [array names best] { lappend pairs [list $best($n) $n] }
set pairs [lsort -decreasing -integer -index 0 $pairs]
set i 0
foreach pr $pairs {
    if {$i >= 6} break
    puts "  fo=[format %5d [lindex $pr 0]]  [lindex $pr 1]"
    incr i
}
puts "  NETS counted in B: [llength $pairs]  (floor: 0 means B idled)"
exit 0

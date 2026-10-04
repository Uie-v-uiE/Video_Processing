# 用途：只读探针：r112 这一族的族级读数（不覆盖 r107 那份件）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/probe_reasm_fanout_r112.tcl —— 只读探针：r112 这一族的族级读数（不覆盖 r107 那份件）
#
#   VP_VIVADO_BIN=... "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_reasm_fanout_r112.tcl
#
# 为什么要单独问一次（沿用 probe_reasm_fanout.tcl 的理由，#121/#175 的口径）：
#   链子只会念"全设计最差 6 条"，而这一族（rows_hit 的 CE 广播）在 r109/r110/r112 三次构建里
#   分别在 0.605 / >1.174（不进前六）/ 0.445 —— **同一份 RTL**（6730dd9 只改了 icmp_tx.v 与
#   key_debounce.v，没碰 frame_reasm.v / rx_par.v）。所以"它现在到底是多少"必须族级单独量，
#   并且要量它的物理跨度：如果最差那条的起点与终点隔着几十个 CLB，那这一刀就是布局问题不是逻辑问题。
# 规矩 35：绝对 WNS 差既不叫收益也不叫损失，所以这里出的是族级数 + 跨度，不是全局 WNS。
# 只读：开已布线的 dcp、出报告到 build/r112_probe_reasm.rpt，不动任何产物。
# 运行时 puts 标签一律 ASCII（CJK 在 Vivado Tcl 的 puts 里会污染 grep 与命令替换）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
puts "DCP: $dcp"
open_checkpoint $dcp

# ---- A. 这一族现在的最差 slack：两个起点各问一次（不写循环，上一版 foreach 参数个数写错了，
#        Vivado 报 "invalid command name {cur u_eth/...}" 且什么都没量到就交卷）----
set tos [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}]
puts "  SETS to(rows_hit)=[llength $tos] (expected = rows_hit width; 0 means a wrong name)"
foreach frompat {u_eth/u_rx_par/p_eof_reg {u_eth/u_reasm/off_reg\[12\]}} {
    set tag [string map {/ _ \[ _ \] _} $frompat]
    set froms [get_cells -quiet $frompat]
    puts "=== A\[$tag\] $frompat -> u_eth/u_reasm/rows_hit_reg\[*\] ==="
    puts "  SETS from=[llength $froms]"
    if {[llength $froms] == 0 || [llength $tos] == 0} { puts "  SKIP A\[$tag\]: empty collection"; continue }
    set rpt [file join $root "build/r112_probe_reasm_$tag.rpt"]
    report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 3 -file $rpt
    set fh [open $rpt r]; set txt [read $fh]; close $fh
    foreach line [split $txt "\n"] {
        set t [string trim $line]
        if {[string match "Slack*" $t] || [string match "Data Path Delay*" $t] \
            || [string match "Logic Levels*" $t] || [string match "Source:*" $t] \
            || [string match "Destination:*" $t] || [string match "Path Group:*" $t]} {
            puts "  $t"
        }
    }
    puts "  RPT: $rpt"
}

# ---- B. 这一族里扇出最大的网络（r106 的那根是 fo=316 的使能广播）----
puts "=== B top-6 fanout nets inside u_eth/u_reasm ==="
set cells [get_cells -quiet u_eth/u_reasm/*]
puts "  CELLS in u_reasm: [llength $cells]"
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

# ---- C. 物理跨度：起点寄存器与整片 rows_hit 各自落在哪个 SLICE ----
# 这一栏是给"下一刀换物理手段 (#252)"落凭据的：route 占 84 % 的路，逻辑只有 4 级，
# 如果起点与终点隔着几十个 CLB 列，那减逻辑级数不可能救它，只有布局（Pblock / 近邻）能救。
puts "=== C placement spread ==="
set pf [get_cells -quiet u_eth/u_rx_par/p_eof_reg]
set pr [get_pins -quiet u_eth/u_rx_par/p_eof_reg/Q]
set net [get_nets -of_objects $pr]
puts "  p_eof_reg SITE = [get_property SITE $pf]"
puts "  p_eof net PINS = [llength [get_pins -of_objects $net]]"
set sites {}
foreach c [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}] {
    lappend sites [get_property SITE $c]
}
puts "  rows_hit sites = $sites"
set rpsites {}
foreach c [get_cells -quiet {u_eth/u_rx_par/*_reg*}] {
    if {[llength $rpsites] >= 400} break
    lappend rpsites [get_property SITE $c]
}
puts "  rx_par site samples ([llength $rpsites]) head = [lrange $rpsites 0 7]"
set rxcells [get_cells -quiet u_eth/u_rx_par/*]
puts "  CELLS in u_rx_par: [llength $rxcells]"
exit 0

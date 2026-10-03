# build/tcl/r115_option_a_probe.tcl —— 把"路 (a)"量到能拍板的程度（只读，不改任何被跟踪件）
#
# 背景（00:01 的读数，件 build/evidence/r115_c2_scratch/io_probe_console.txt）：
#   副本树（IDDR+fabric 已搬到派生钟 mmcm_clk0）在 ±0.5 窗下终态 WHS = −2.126，
#   而那条 I/O 路的 `Clock Uncertainty` 只剩 0.166 —— 因为 `set_clock_uncertainty -hold 0.800`
#   点的是主钟 `eth_rxc`，**派生钟没被覆盖**（#305）。
#   ⇒ "路 (a)" = 先让三条约束都覆盖派生钟（窗用手册 Table 60 的真数），再看这一族还剩多少差额。
#   这一支把这三步**在同一块已布线 DCP 上**逐层量出来：每加一层就报一次，读数差就是那一层的代价/收益。
#     L0 构建时生效的 ±0.5 窗（既成事实）
#     L1 换成真窗 min 1.000 / max 2.600（Table 60 并集）
#     L2 再给派生钟补上 0.800 的 hold 不确定度（= 把 #305 丢掉的覆盖面装回去）
#     L3 对照：把不确定度也补到主钟已经有的情况下（eth_rxc 本来就有），确认没有重复计
# ⚠ 只读：约束只活在会话里，DCP 不回写，主树与副本树的 src/ 都不动。
set root [file normalize [file join [file dirname [info script]] .. ..]]
# 同一套分层要量两块 DCP，否则"加 MMCM 到底赚了多少"没有同尺子的对照：
#   副本树（有 MMCM，目的地是派生钟 mmcm_clk0） ← 默认
#   主  树（无 MMCM，目的地就是主钟 eth_rxc）   ← VP_OA_DCP=<主树 dcp> VP_OA_DST=eth_rxc
if {[info exists ::env(VP_OA_DCP)]} { set dcp $::env(VP_OA_DCP) } else {
    set dcp [file normalize [file join $root .. c2_scratch_1003 vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
}
if {[info exists ::env(VP_OA_DST)]} { set dst $::env(VP_OA_DST) } else { set dst mmcm_clk0 }
set out  [file join $root build evidence r115_c2_scratch]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp
puts "OA_TARGET dcp=$dcp dst_clock=$dst"

set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set gclk  [get_clocks -quiet $dst]
set mclk  [get_clocks -quiet eth_rxc]
puts "OBJS ports=[llength $ports] mmcm_clk0=[llength $gclk] eth_rxc=[llength $mclk]"
if {[llength $ports] == 0 || [llength $gclk] == 0 || [llength $mclk] == 0} {
    puts "REFUSE: 有对象取不到（空集不许当 0 用）"; exit 4
}

proc rep {tag f dt} {
    file delete -force $f
    report_timing -delay_type $dt -from [get_ports -quiet {eth_rxd[*] eth_rx_ctl}] \
        -to [get_clocks $::dst] -nworst 1 -max_paths 2 -file $f
    set h [open $f r]; set t [read $h]; close $h
    set s [regexp -all -inline {Slack \([A-Z]+\) :\s+\S+} $t]
    puts "STAGE $tag slack=[join $s { ; }]"
    foreach ln [split $t "\n"] {
        if {[regexp {^\s+(Requirement|Clock Path Skew|Clock Uncertainty|Data Path Delay|Slack):} $ln]} {
            puts "STAGE $tag | [string trim $ln]"
        }
    }
}

rep L0 [file join $out oa_${dst}_L0_built_window.txt] min
puts "L1: 换真窗 min 1.000 / max 2.600（两沿）"
foreach {o v} {-min 1.000 -max 2.600} {
    set e no-error
    catch {set_input_delay -clock eth_rxc     $o $v $ports} e; puts "L1-RISE$o rc=$e"
    set e no-error
    catch {set_input_delay -clock eth_rxc -clock_fall $o $v $ports} e; puts "L1-FALL$o rc=$e"
}
rep L1 [file join $out oa_${dst}_L1_true_window.txt] min
puts "L2: 给派生钟补 hold 不确定度（一条命令一个对象，绝不并名）"
set e no-error
catch {set_clock_uncertainty -hold 0.800 $gclk} e
puts "L2-SET gclk rc=$e"
rep L2 [file join $out oa_${dst}_L2_true_window_plus_unc.txt] min
rep L2s [file join $out oa_${dst}_L2_setup.txt] max
puts "OADOONE"
exit 0

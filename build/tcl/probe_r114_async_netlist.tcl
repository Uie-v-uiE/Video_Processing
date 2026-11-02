# 用途：只读探针：ASYNC_REG 属性到底有没有活到网表里
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/probe_r114_async_netlist.tcl —— 只读探针：ASYNC_REG 属性到底有没有活到网表里
#
# 为什么要有这一把（2026-10-03，r114 §一 那一刀的**网表侧**凭据）：
#   `build/scan_async_reg_coverage.py` 判的是 **RTL 文本**里那四颗格雷码寄存器标了没有（改前 A2 RED，
#   件 build/evidence/r113_async_reg_scan.txt）。文本绿不等于工具认账：`report_methodology` 的
#   TIMING-10「Missing property on synchronizer」才是工具自己的说法——现在它是 **1 条**
#   （件 build/evidence/r113_methodology_baseline.rpt 的 SUMMARY 行 + `Checks found: 446`）。
#   这一把量两件事：① 那四颗 FF 在优化后的网表里叫什么、`ASYNC_REG` 属性是什么值；
#   ② TIMING-10 的计数离不离开 1。属性不该改网表结构 ⇒ 名册差分归链子后面的读数，不归这里。
#
# ⚠ 形状全部实测，不许猜：
#   * 实例路径从 RTL 量出来：`eth_udp_video_top.v:298` 里 dc_fifo 的实例名是 **u_cdc**，
#     顶层 `u_eth` 是 eth_udp_video_top 的实例名——但**寄存器名会不会带 `_reg` 后缀**没验过，
#     所以两种写法都查一遍，找回哪个算哪个（找回 0 个不是"属性丢了"，是"名字猜错了"，必须分开念）。
#   * 对象查找沿用 #286 的教训：**不带 `-hier` 的分层路径**才可用，`-filter NAME == {…}` 恒空。
#   * `report_methodology` 的计数只认 SUMMARY 表那一行（整文件 grep 会把每类多算一次，栽过）。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {![file exists $dcp]} { puts "REFUSE: no dcp: $dcp"; exit 1 }
set label "na"
if {[info exists ::env(VP_LABEL)]} { set label $::env(VP_LABEL) }
open_checkpoint $dcp
puts "ASYNCNET label=$label dcp=$dcp state=[get_property STATE [current_design]]"

# ⚠ 名字**不许猜**：第一版这里写死 `u_eth/u_cdc/wgray_s0_reg`，实测 found=0
#   （件 build/evidence/r114_async_netlist_pre_console.txt）。真正住在网表里的名字来自
#   `report_cdc` 自己的说法：`build/cdc_details.rpt` 里 CDC-5 那两行的引脚是
#   `u_eth/u_cdc/wgray_reg[13:0]/C` 与 `u_eth/u_cdc/rgray_reg[13:0]/C` ⇒ 综合把
#   `wgray_s0/s1` 这两条**向量**并成了 `wgray_reg[..]` 一族的命名。
#   所以这里改成"在 u_cdc 底下把所有带 gray 的单元问出来"，逐颗念 ASYNC_REG 的值——
#   名字对不对、有几颗、属性是什么，三个数分开报，空集绝不写成"属性丢了"。
set gray [get_cells -quiet u_eth/u_cdc/*gray*]
set n [llength $gray]
set ffs {}
foreach c $gray {
    if {[string match "FD*" [get_property REF_NAME $c]]} { lappend ffs $c }
}
set nf [llength $ffs]
set marked 0
foreach c $ffs {
    set p [get_property ASYNC_REG $c]
    if {$p eq "TRUE" || $p eq "1" || $p eq "true"} { incr marked }
}
puts "ASYNCNET_CELLS gray_cells=$n gray_ff=$nf marked_true=$marked (n=0 是名字/层次猜错，不是属性丢了)"
foreach c [lrange $ffs 0 5] {
    puts "FFLINE cell=$c ref=[get_property REF_NAME $c] ASYNC_REG=[get_property ASYNC_REG $c]"
}
# ⚠ `get_cells` 只收**一个**位置参数模式：写成 `get_cells a* b*` 会报
#   [Common 17-165] Too many positional options（2026-10-03 18:34 实测；那份控制台随后被同一路径的
#   下一次运行覆盖了——探针输出写死路径会把上一份唯一快照抹掉，见 ISSUES #287 第 3 条 ⇒ 这条形状事实的
#   持久记录在 ISSUES #287，不在那份 .txt）
#   ⇒ 多模式必须分几次查，再自己并起来。
set alt1 [get_cells -quiet u_eth/u_cdc/*s0_reg*]
set alt2 [get_cells -quiet u_eth/u_cdc/*s1_reg*]
puts "ALT_LOOKUP s0_reg_style=[llength $alt1] s1_reg_style=[llength $alt2] (RTL 里那两个名字的带位写法找回几颗)"

# 工具自己的说法：TIMING-10 还剩几条（只读，写到 $root 下面——Vivado 的 /tmp 不是 bash 的 /tmp）
set mout [file join $root "build/probe_asyncnet_${label}.rpt"]
catch {report_methodology -quiet -file $mout} errm
puts "METH_ERR=$errm EXISTS=[file exists $mout]"
if {[file exists $mout]} {
    set fh [open $mout r]; set txt [read $fh]; close $fh
    set total ""
    foreach line [split $txt "\n"] {
        if {[regexp {Checks found:\s+(\d+)} $line -> n]} { set total $n }
        if {[regexp {\|\s*TIMING-10\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*(\d+)\s*\|} $line -> sev desc cnt]} {
            puts "METHROW check=TIMING-10 sev=[string trim $sev] count=$cnt"
        }
    }
    puts "METH_SUMMARY checks_found=$total"
}
exit 0

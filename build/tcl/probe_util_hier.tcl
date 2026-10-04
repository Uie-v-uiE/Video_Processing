# 用途：read-only: which module owns the LUT change on the built design?
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 3=REFUSE
# build/tcl/probe_util_hier.tcl -- read-only: which module owns the LUT change on the built design?
#   为什么要它：r110 把 frame_reasm 的新行谓词独热化之后，`build/utilization.rpt` 是**扁平汇总**，
#   看不出 -243 个 LUT 落在谁身上；而"没归到模块的量不写进首页"是本仓的规矩（#246）。
#   这份探针只开 DCP、只出报告，不改任何源。标签一律 ASCII（Vivado Tcl 按系统代码页读文件，
#   CJK 出现在 puts 里会坏命令替换 —— 记忆里记过一整族）。
#   用法：vivado -mode batch -nojournal -source build/tcl/probe_util_hier.tcl
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
set rpt  [file join $root "build/util_hier_probe.rpt"]
if {![file exists $dcp]} { puts "REFUSE: no dcp $dcp"; exit 1 }
# 覆盖前先把**上一轮那份**按它自己的 mtime 归档（#254 第 3① 条：r112 这轮起探针时，盘上那份正是 r110 的
# 逐层数，手工 cp 抢在覆盖前 1 秒才救回来。机制落成代码，不靠记性）。
# ⚠ 这里的 -format 要写成带 % 的普通串并**加花括号**：Vivado 的 Tcl 不认 `-format %F_%T`（不加花括号时
#   它打出字面量 `%F_08:42:25`，凭据 build/evidence/r112_util_hier_console.txt 的 DCP_MTIME 行）。
if {[file exists $rpt]} {
    set prev [file join $root "build/evidence/util_hier_prev_[clock format [file mtime $rpt] -format {%Y%m%d_%H%M}].rpt"]
    file rename -force $rpt $prev
    puts "ARCHIVED_PREV $prev"
    if {![file exists $prev]} { puts "REFUSE: 归档失败（旧件不见了）"; exit 3 }
}
open_checkpoint $dcp
# 这份 DCP 是哪一轮的：报它自己的 mtime，与 build/evidence 里的 md5 配对来认定出身
puts "DCP_MTIME [clock format [file mtime $dcp] -format {%Y-%m-%d_%H:%M:%S}]"
report_utilization -hierarchical -hierarchical_depth 3 -file $rpt
if {![file exists $rpt]} { puts "REFUSE: report_utilization wrote nothing"; exit 1 }
puts "WROTE $rpt"
# 直接把关心的几行念出来，省得再 grep（模块名是 u_reasm / u_icmp / u_osd / u_lm）
set fh [open $rpt r]
set txt [read $fh]
close $fh
set want 0
foreach line [split $txt "\n"] {
    set t [string trim $line]
    if {[regexp {(u_reasm|u_icmp|u_osd|u_lm|u_crc_rx)} $t]} { set want 1 }
    if {$want} { puts "HIER> [string range $t 0 118]" }
    if {$want && $t eq ""} { set want 0 }
}
exit 0

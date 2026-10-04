# build/tcl/probe_r119_xdc_loads.tcl —— 只读探针（v3）：候选 XDC 真 load 之后，窗到底挂没挂上？
#
# 为什么要第三版：
#   v1 想用属性读"端口上有没有 output delay"，结果 got=0（件 build/evidence/r119_xdc_loads_probe.txt）；
#      那个属性路径在本工具上读空——读空不等于没挂上（这一族错的第 N 次，ISSUES #334）。
#   v2 改问工具行为（load 前后各跑一次 report_timing -to 看 Path Group），但匹配器写的是
#      [string match "Path Group:*" $l] 而报告里这些行**前面有空格**，于是六行里只有一行命中，
#      看起来像"数据没有"——又是尺子的形状没量就下结论。v3 先 trim 再比，并把整份报告里
#      含 "Path Group" / "Slack" / "output delay" 的行**原样打印**，让人能自己核对。
# 不改设计、不 place/route、不写工程文件。跑法见 build/evidence/r119_ser_clock_probe.txt 头部同一条命令。
set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {$dcp eq "" || ![file exists $dcp]} { puts "PROBE-REFUSE VP_DCP=$dcp"; exit 3 }
set xdc ""
if {[info exists ::env(VP_XDC)]} { set xdc $::env(VP_XDC) }
if {$xdc eq ""} { set xdc src/constraints/r119_hdmi_source_window.xdc }

open_checkpoint $dcp

proc dump {tag pps} {
    global TMPRPT
    foreach pp $pps {
        set nm [get_property NAME $pp]
        if {[file exists $TMPRPT]} { file delete -force $TMPRPT }
        set rc [catch {report_timing -to $pp -max_paths 1 -nworst 1 -delay_type max -file $TMPRPT} e]
        if {$rc != 0 || ![file exists $TMPRPT] || [file size $TMPRPT] == 0} {
            puts "$tag| $nm | rc=$rc msg=$e NOT_MEASURED"
            continue
        }
        set f [open $TMPRPT r]; set txt [read $f]; close $f
        file delete -force $TMPRPT
        set found ""
        foreach l [split $txt "\n"] {
            set s [string trim $l]
            if {[string match "Path Group*" $s] || [string match "Slack*" $s] ||
                [string match "*output delay*" $s] || [string match "Requirement*" $s]} {
                append found "«$s» "
            }
        }
        if {$found eq ""} { set found "NONE_FOUND NOT_MEASURED" }
        puts "$tag| $nm | $found"
    }
}

set TMPRPT "vivado_system/.r119_probe_tmp.rpt"   ;# Vivado 的 /tmp 与 bash 的 /tmp 不是同一个，写进被 .gitignore 的工程生成目录
set pps [get_ports -quiet {tmds_data_p\[0\] tmds_data_p\[1\] tmds_data_p\[2\] tmds_clk_p}]
puts "PORTS_FOUND=[llength $pps]"
dump BEFORE $pps

set rc [catch {read_xdc $xdc} e]
puts "READ_XDC rc=$rc msg=$e"
# 解析期警告会在这里露出来：v2 那版 .xdc 写了 if/puts，被报 Designutils 20-1307 后**整块跳过**，
# 守卫变成"防呆失效且不报错"。现在 .xdc 是纯 SDC，期望这里**没有** 20-1307。
dump AFTER $pps
puts "PROBE5-DONE"
exit 0

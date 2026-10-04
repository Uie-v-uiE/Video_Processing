# build/tcl/probe_clock_networks.tcl -- 只读：把每条时钟的**名字/周期/来源脚**打出来。
# 为什么要它：要给 TMDS 输出写钟↔数据窗，`set_output_delay -clock <谁>` 必须落在实现网表里
# 真存在的时钟对象上；而"这个设计里有哪些时钟、它们从哪个 pin 出来"只能问工具（记忆里那一族
# 按记忆写属性名/列序的错已经付过三次学费）。本脚本不 place、不 route、不改属性。
set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {$dcp eq "" || ![file exists $dcp]} { puts "PROBE-REFUSE VP_DCP=$dcp"; exit 3 }
open_checkpoint $dcp
set out "build/evidence/r119_clock_networks.rpt"
if {[file exists $out]} { file delete -force $out }
set rc [catch {report_clock_networks -file $out} e]
puts "CLOCKNET rc=$rc msg=$e"
if {$rc == 0 && [file exists $out]} {
    set f [open $out r]; set txt [read $f]; close $f
    set n 0
    foreach l [split $txt "\n"] {
        set t [string trim $l]
        if {$t eq ""} continue
        incr n
        if {$n <= 40} { puts "CN| [string map {\t { }} $l]" }
    }
    puts "CN_TOTAL_LINES $n"
}
puts "PROBE3-DONE"
exit 0

# 用途：read out the two r116 cuts on the shipped routed DCP
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/r116_verdict_probe.tcl -- read out the two r116 cuts on the shipped routed DCP
# ASCII-only (ISSUES #307: CJK comments have killed a Vivado Tcl parse mid-proc before).
# One line per criterion, verdict/worst number as the LAST field.
#   V1 mechanism: the window is really attached -> the 5 RGMII inputs get a FINITE slack and an
#      "Input Delay:" line. Without a window those paths read "Slack: inf / Path Group: (none)",
#      which is exactly what H5 calls "unconstrained is not met".
#   V2 debt: check_timing must stop naming the eth_rxd/eth_rx_ctl ports.
#   V3 the I/O family's own numbers -- what the tap retune 26 -> 31 was supposed to move.
#   V4 per-clock rows, so no domain can slip from MET to violated while everyone looks at the
#      headline (H2).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out [file join $root build evidence r116]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp
set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set clk   [get_clocks -quiet eth_rxc]
puts "VP_OBJS ports=[llength $ports] clocks=[llength $clk]"
if {[llength $ports] != 5 || [llength $clk] != 1} { puts "REFUSE object counts"; exit 4 }

foreach {dt suf} {min HOLD max SETUP} {
    set f [file join $out "r116_io_${suf}.rpt"]
    catch {file delete -force $f}
    report_timing -delay_type $dt -from $ports -to $clk -nworst 1 -max_paths 3 -file $f
    set h [open $f r]; set t [read $h]; close $h
    set s [regexp -all -inline {Slack(?: \([A-Z]+\))?\s*:\s+\S+} $t]
    set g [regexp -all -inline {Path Group:\s+\S+} $t]
    set d [regexp -all -inline {Input Delay:\s+\S+} $t]
    set worst "NA"
    foreach ln $s {
        if {[regexp {(-?[0-9.]+)ns} $ln -> v]} {
            if {$worst eq "NA"} { set worst $v } elseif {$v < $worst} { set worst $v }
        }
    }
    puts "V1V3 $suf n=[llength $s] worst=$worst groups=[join $g { | }] indelay=[join $d { | }]"
}

set ct [file join $out r116_check_timing.txt]
catch {file delete -force $ct}
check_timing -verbose -file $ct
set h [open $ct r]; set ctx [read $h]; close $h
set neth [regexp -all -inline {eth_rx} $ctx]
puts "V2 CHECK_TIMING eth_rx_hits=[llength $neth]"

set sm [file join $out r116_timing_summary.txt]
catch {file delete -force $sm}
report_timing_summary -file $sm
set h [open $sm r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {$s eq ""} continue
    foreach c {eth_rxc clk_fpga_0 sys_clk clkout0_1} {
        if {[string match "$c *" $s]} { puts "V4 ROW $c |$s" }
    }
}
puts "R116PROBEDONE"
exit 0

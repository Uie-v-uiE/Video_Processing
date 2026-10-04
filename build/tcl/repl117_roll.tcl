# 用途：fast-lane roll: replicate ONE broadcast net (clk_fpga_0's worst family)
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/repl117_roll.tcl -- fast-lane roll: replicate ONE broadcast net (clk_fpga_0's worst family)
#
# Why this net, from the reports (not from a guess): r116's per-clock probe says the worst
# clk_fpga_0 paths are
#   Source      u_pl/u_arb/owner_eth_reg/C
#   Destination u_pl/u_bilin/u_fb/hi_reg_8/WEA[0]        (1 logic level, route 6.871 ns = 93.4 %)
#   Destination u_pl/u_bilin/u_fb/lo_reg_0_33/ADDRARDADDR[3]
# i.e. a single arbiter flag broadcasting across the die into the bilinear frame buffer's
# LUTRAM control pins. report/timing/limit_audit_r116.md judged this domain "NOT at its physical
# limit" precisely because 1 logic level cannot be a device limit -- the wire is.
#
# So the lever is replication of that one net, NOT a pblock around u_fb (a box cannot shorten a
# source that lives outside it; pb117_roll.tcl's PB_EXISTING_BOX came back empty anyway, which is
# the ruler's account, not the design's).
#
# Single variable vs the control roll build/evidence/r117_fb_pblock/A (which reproduced the
# official r116 roster digit-for-digit): pre-route phys_opt with -force_replication_on_nets.
# Net objects are recovered ONLY by plain hierarchical path + a NAME equality check
# (filters with == on NAME/FULL_NAME read empty in this Vivado -- env account).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_opt.dcp]]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
if {[info exists ::env(RP_MODE)]} { set mode $::env(RP_MODE) } else { set mode repl }
if {[info exists ::env(RP_OUT)]}  { set out  $::env(RP_OUT) } else { set out [file join $root build/evidence/r117_repl] }
if {[info exists ::env(RP_NET)]}  { set netname $::env(RP_NET) } else { set netname u_pl/u_arb/owner_eth_reg }
file mkdir $out
puts "RPROLL mode=$mode net=$netname dcp=$dcp out=$out"
open_checkpoint $dcp

set n [get_nets -quiet $netname]
puts "RP_NET_found=[llength $n]"
if {[llength $n] == 0} { puts "RP-REFUSE net not found by path"; exit 4 }
foreach x $n { puts "RP_NET name=[get_property NAME $x] fo=[get_property FANOUT $x]" }
set targets $n

place_design
if {$mode eq "repl"} {
    set e no-error
    catch {phys_opt_design -placement_opt -skeleton_clustering -retime -force_replication_on_nets $targets} e
    puts "RP_PHYSOPT rc=$e"
}
route_design
report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out util.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]

# mechanism read-back: did replication actually happen, and did the broadcast fanout drop?
# 复制出来的 FF 叫什么、有几颗：这是"机制到底动没动"的凭据。过滤只用位置式 glob
# （`-filter {NAME =~ ...}` 在这台 Vivado 上读空，环境账里已经栽过三次）。
set all [get_cells -quiet -hier *replica*]
set mine 0
foreach x $all { if {[string match *owner_eth* [get_property NAME $x]]} { incr mine } }
puts "RP_REPLICA_CELLS=$mine (all_replicas=[llength $all])"
foreach x [get_nets -quiet $netname] { puts "RP_NET_AFTER name=[get_property NAME $x] fo=[get_property FANOUT $x]" }

set h [open [file join $out timing_summary.rpt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {$s eq ""} continue
    foreach c {clk_fpga_0 clkout0_1 eth_rxc sys_clk} {
        if {[lindex $s 0] eq $c} { puts "ROW $c |$s" }
    }
}
puts "RPDONE mode=$mode out=$out"
exit 0

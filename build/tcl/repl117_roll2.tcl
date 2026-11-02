# 用途：same single-variable roll as repl117_roll.tcl, with the net
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/repl117_roll2.tcl -- same single-variable roll as repl117_roll.tcl, with the net
# lookup FIXED.
#
# Why a new file instead of editing the old one:
#   repl117_roll.tcl died at 02:39:43 with `RP_NET_found=0 / RP-REFUSE net not found by path`.
#   The cause is mine and it is a name-vs-kind error, not a design fact: `u_pl/u_arb/owner_eth_reg`
#   is the *cell* named in the timing report's Source column (a flop -- it has a /C pin), and I
#   handed that path to `get_nets`. The net driven by that flop has its own auto-generated name.
#   Fix: resolve the flop, take its Q pin, and ask for the net attached to that pin
#   (`get_nets -of [get_pins <cell>/Q]`). The old script and its console stay on disk as the
#   tool-side account (ISSUES), so nothing here silently rewrites history.
#
# Everything else is byte-for-byte the same variable as the control roll
# (build/evidence/r117_fb_pblock/A, which reproduced the official r116 roster digit-for-digit):
#   open opt.dcp -> place_design -> [repl only: phys_opt ... -force_replication_on_nets $targets]
#   -> route_design -> reports -> per-clock ROW lines.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_opt.dcp]]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
if {[info exists ::env(RP_MODE)]} { set mode $::env(RP_MODE) } else { set mode repl }
if {[info exists ::env(RP_OUT)]}  { set out  $::env(RP_OUT) } else { set out [file join $root build/evidence/r117_repl2] }
if {[info exists ::env(RP_CELL)]} { set cellpath $::env(RP_CELL) } else { set cellpath u_pl/u_arb/owner_eth_reg }
file mkdir $out
puts "RPROLL2 mode=$mode cell=$cellpath dcp=$dcp out=$out"
open_checkpoint $dcp

# --- resolve the broadcast net through the flop's Q pin (one positional path, no -filter) ---
set c [get_cells -quiet $cellpath]
puts "RP_CELL_found=[llength $c]"
if {[llength $c] == 0} { puts "RP-REFUSE cell not found by path"; exit 4 }
puts "RP_CELL name=[get_property NAME $c] ref=[get_property REF_NAME $c] pins=[get_property PINS $c]"
set p [get_pins -quiet [join "$cellpath/Q" ""]]
if {[llength $p] == 0} { set p [get_pins -quiet $c/Q] }
puts "RP_PIN_found=[llength $p]"
if {[llength $p] == 0} { puts "RP-REFUSE Q pin not found"; exit 4 }
set n [get_nets -quiet -of $p]
puts "RP_NET_found=[llength $n]"
if {[llength $n] == 0} { puts "RP-REFUSE net behind Q is empty"; exit 4 }
set netname [get_property NAME $n]
puts "RP_NET name=$netname fo=[get_property FANOUT $n] pincount=[get_property PIN_COUNT $n]"
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
# glob is positional (`-filter {NAME =~ ...}` reads empty on this Vivado -- env account).
set all [get_cells -quiet -hier *replica*]
set mine 0
set minenames {}
foreach x $all {
    if {[string match *owner_eth* [get_property NAME $x]]} {
        incr mine
        if {$mine <= 6} { lappend minenames [get_property NAME $x] }
    }
}
puts "RP_REPLICA_CELLS=$mine (all_replicas=[llength $all])"
foreach m $minenames { puts "RP_REPLICA $m" }
foreach x [get_nets -quiet $netname] { puts "RP_NET_AFTER name=[get_property NAME $x] fo=[get_property FANOUT $x]" }
# the worst path of the family, so the reader can see whether the wire got shorter
report_timing -delay_type max -from $c -nworst 3 -max_paths 3 -file [file join $out worst_from_cell.rpt]
set h [open [file join $out worst_from_cell.rpt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {[regexp {^(Slack|Data Path Delay|Logic Levels|Source:|Destination:)} $s]} { puts "WP $s" }
}

set h [open [file join $out timing_summary.rpt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {$s eq ""} continue
    foreach c2 {clk_fpga_0 clkout0_1 eth_rxc sys_clk} {
        if {[lindex $s 0] eq $c2} { puts "ROW $c2 |$s" }
    }
}
puts "RPDONE2 mode=$mode out=$out"
exit 0

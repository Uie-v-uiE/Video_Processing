# build/tcl/repl117_roll3.tcl -- D1 fast-lane roll, attempt 3 of this one cut (H7 limit).
#
# Attempt 1 (repl117_roll.tcl, 02:39) died with RP_NET_found=0: I handed `get_nets` a *cell* path.
# Attempt 2 (repl117_roll2.tcl, 02:48) resolved a net, but `phys_opt_design` answered
#   ERROR: [Common 17-170] Unknown option '-skeleton_clustering'
# so it never replicated -- and it resolved the WRONG net: the driver-side lookup answered
# `u_pl/u_arb/dbg_src[0]` (7 pins) while the routed path table names the 5.690 ns segment as
# `u_pl/u_row/hi_reg_0[0]` (239 pins, agrees with the load-side lookup and with the literal-name
# lookup -- see build/evidence/r117_d0/nethelp_console.txt: AGREE load_vs_name=1).
# Both attempts were failures of my tool use, not of the design, and they are recorded as ISSUES
# entries rather than quietly overwritten.
#
# Option set is now measured, not remembered (build/evidence/r117_d0/nethelp_console.txt,
# PO_OPTION_COUNT=31): present = -force_replication_on_nets, -fanout_opt, -critical_cell_opt,
# -placement_opt, -retime, -directive, ...; absent = -skeleton_clustering, -rewire,
# -replication_count, -cell_opt, -shift_registers, -hold_buffer_insertion, -aggressive_replication.
#
# Single variable vs control roll A (build/evidence/r117_fb_pblock/A, which reproduced the official
# r116 roster digit-for-digit): pre-route phys_opt that FORCES replication of that one broadcast net.
# Nothing else is changed: same opt.dcp, same place_design, same route_design, same reports.
#
# Why this net is the right target (evidence, not preference): the r116 roster's clk_fpga_0 setup
# row is 1.976 ns slack on a 10 ns period, and the path table splits it as
#   logic 0.484 ns (6.6 %) | route 6.871 ns (93.4 %), of which 5.690 ns is THIS 239-pin net,
#   loads spread over 99 distinct tiles including a sink at SLICE_X88Y7 while the driver sits at
#   SLICE_X43Y79. That is FANOUT + distance, which is exactly what driver replication addresses and
#   exactly what a pblock around the destination does not.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_opt.dcp]]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
if {[info exists ::env(RP_MODE)]} { set mode $::env(RP_MODE) } else { set mode repl }
if {[info exists ::env(RP_OUT)]}  { set out  $::env(RP_OUT) } else { set out [file join $root build/evidence/r117_repl3/B] }
if {[info exists ::env(RP_NETPATH)]} { set netpath $::env(RP_NETPATH) } else { set netpath {u_pl/u_row/hi_reg_0[0]} }
file mkdir $out
puts "RPROLL3 mode=$mode net=$netpath dcp=$dcp out=$out"
open_checkpoint $dcp

# --- resolve the broadcast net two independent ways and require agreement (empty set is never OK) ---
set byname [get_nets -quiet $netpath]
puts "R3_BYNAME found=[llength $byname]"
set byload [get_nets -quiet -of [get_pins -quiet u_pl/u_row/hi_reg_4_i_1/I3]]
puts "R3_BYLOAD found=[llength $byload]"
if {[llength $byname] == 0 || [llength $byload] == 0} { puts "R3-REFUSE a lookup came back empty"; exit 4 }
set nb [get_property NAME $byname]; set nl [get_property NAME $byload]
puts "R3_AGREE name=[get_property NAME $byname] load=[get_property NAME $byload] same=[expr {$nb eq $nl}]"
if {$nb ne $nl} { puts "R3-REFUSE the two lookups disagree"; exit 4 }
set targets $byname
set pins_before [llength [get_pins -quiet -of $targets]]
puts "R3_BEFORE pins=$pins_before"

place_design
if {$mode eq "repl"} {
    set e no-error
    catch {phys_opt_design -force_replication_on_nets $targets} e
    puts "R3_PHYSOPT rc=$e"
}
route_design
report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out util.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]

# --- mechanism read-back: replicas must EXIST or the verdict is MECHANISM_INERT, not "no gain" ---
set all [get_cells -quiet -hier *replica*]
set mine 0
foreach x $all { if {[string match *hi_reg_0* [get_property NAME $x]]} { incr mine } }
set pins_after [llength [get_pins -quiet -of $targets]]
puts "R3_REPLICA_CELLS=$mine (all_replicas=[llength $all])"
puts "R3_AFTER pins=$pins_after  (before=$pins_before)"
if {$mine == 0 && $pins_after == $pins_before} { puts "R3_MECHANISM_INERT" }

# --- per-domain roster rows, same ruler as control A ---
set h [open [file join $out timing_summary.rpt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {$s eq ""} continue
    foreach c2 {clk_fpga_0 clkout0_1 eth_rxc sys_clk} {
        if {[lindex $s 0] eq $c2} { puts "ROW $c2 |$s" }
    }
}
# the worst clk_fpga_0 path in this roll, so the reader can see whether the 5.690 ns segment moved
set f [file join $out worst_clk_fpga_0_setup.rpt]
file delete -force $f
report_timing -delay_type max -from [get_clocks clk_fpga_0] -to [get_clocks clk_fpga_0] \
    -max_paths 1 -input_pins -nets -file $f
set h [open $f r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {[regexp {^(Slack|Data Path Delay|Logic Levels|Source:|Destination:|net \()} $s]} { puts "WPS3 $s" }
}
puts "RPDONE3 mode=$mode out=$out"
exit 0

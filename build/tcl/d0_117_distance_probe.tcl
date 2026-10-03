# build/tcl/d0_117_distance_probe.tcl -- D0 read-only probe: is clk_fpga_0's worst path a DISTANCE
# problem, a CONGESTION problem, or neither?
#
# Why this probe exists before any further cut:
#   The r116 roster says clk_fpga_0's worst setup path is
#     dest u_pl/u_bilin/u_fb/hi_reg_8/WEA[0], data 7.355 ns with route 6.871 ns (93.4 %),
#     1 LUT level (docs/timing/limit_audit_r116.md judged this domain "NOT at its physical limit"
#     for exactly that reason: a 1-level path that spends 6.9 ns on the wire is placement, not device).
#   The audit then scheduled "a pblock around u_fb" as r117's first cut WITHOUT measuring the
#   distance -- and a box cannot shorten a source that lives outside it, which is why the earlier
#   pb117_roll.tcl was refused. Before paying 8 minutes for another roll, measure the three things
#   that decide whether ANY placement lever exists:
#     (a) physical coordinates of source and destination tiles, and their Manhattan span in CLBs;
#     (b) the die size, so the span can be stated as a fraction of the device;
#     (c) how the router actually spent the 6.871 ns (report_design_analysis -routes / -congestion).
#   If the two cells are close, the wire is not "far" -- it is congested/detoured, and a pblock is
#   the wrong tool. If the span is a large fraction of the die, placement IS the lever, and the
#   right cut is a box containing BOTH the arbiter and u_fb (not u_fb alone).
#
# Read-only: opens the already-routed official r116 DCP, writes reports into build/evidence/r117_d0,
# never touches src/, never writes a checkpoint.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out  [file join $root build evidence r117_d0]
if {![file exists $dcp]} { puts "REFUSE no routed dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp

set src_name u_pl/u_arb/owner_eth_reg
set dst_name {u_pl/u_bilin/u_fb/hi_reg_8}

# ---- (1) the real worst path of this clock, straight out of the tool, not from a note ---------
set f [file join $out worst_clk_fpga_0_setup.rpt]
file delete -force $f
report_timing -delay_type max -from [get_clocks clk_fpga_0] -to [get_clocks clk_fpga_0] \
    -nworst 5 -max_paths 5 -input_pins -nets -file $f
set h [open $f r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {[regexp {^(Slack|Data Path Delay|Logic Levels|Source:|Destination:|Requirement|Clock Path Skew|Clock Uncertainty|Path Group|Data Arrival Time|Source Clock|Destination Clock)} $s]} {
        puts "WPS $s"
    }
}

# ---- (2) physical location of the two cells: tile name + RLOC (SLICE_XnYm) --------------------
foreach c $src_name {
    set o [get_cells -quiet $c]
    puts "LOC_cell=$c found=[llength $o]"
    if {[llength $o] == 0} { continue }
    puts "LOC_REF   [get_property REF_NAME $o]"
    puts "LOC_TILE  [get_property LOC $o]"
    puts "LOC_RLOC  [get_property RLOC $o]"
    puts "LOC_PTYPE [get_property PARENT_TYPE $o]"
    set sp $o
}
foreach c $dst_name {
    set o [get_cells -quiet $c]
    puts "LOC_cell=$c found=[llength $o]"
    if {[llength $o] == 0} { continue }
    puts "LOC_REF   [get_property REF_NAME $o]"
    puts "LOC_TILE  [get_property LOC $o]"
    puts "LOC_RLOC  [get_property RLOC $o]"
    set dp $o
}

# ---- (3) how big is the device, so the span is a fraction and not a bare number ---------------
puts "DEV_PART [get_property PART [current_design]]"
set pr [get_sites -quiet SLICE_X0Y0]
puts "DEV_SITE0Y0_found=[llength $pr]"
# max RLOC of the design's placed instances: read the two operands off the same ruler
set sxl -1; set syl -1; set sxh -1; set syh -1
foreach {c} [list $sp $dp] {
    if {![info exists c] || [llength $c] == 0} continue
    set r [get_property RLOC $c]
    if {[regexp {SLICE_X(\d+)Y(\d+)} $r -> x y]} {
        puts "SPAN_ROW cell=$c x=$x y=$y"
    }
}
# die extent from the placer database: cheapest honest way is the QoR summary's placement range
set qf [file join $out qor_suggestions.rpt]
file delete -force $qf
catch {report_qor_suggestions -max_rank 8 -file $qf} rc
puts "QOR_REPORT rc=$rc file=$qf"
if {[file exists $qf]} {
    set h [open $qf r]; set q [read $h]; close $h
    set n 0
    foreach ln [split $q "\n"] {
        set s [string trim $ln]
        if {$s eq ""} continue
        if {[regexp {^(REASON|SUGGESTION|SITE RANGES|SLICE_X|Current Design Timing|Design Status)} $s]} {
            incr n
            if {$n <= 40} { puts "QOR $s" }
        }
    }
    puts "QOR_ROWS=$n"
}

# ---- (4) congestion around the two cells ------------------------------------------------------
set cf [file join $out congestion.rpt]
file delete -force $cf
set e no-error
catch {report_design_analysis -congestion -file $cf} e
puts "CONG rc=$e"
if {[file exists $cf]} {
    set h [open $cf r]; set q [read $h]; close $h
    puts "CONG_HEAD [lindex [split $q \n\n] 0]"
}
set rf [file join $out routes.rpt]
file delete -force $rf
set e no-error
catch {report_design_analysis -routes -from $sp -to $dp -file $rf} e
puts "ROUTES rc=$e"
if {[file exists $rf]} {
    set h [open $rf r]; set q [read $h]; close $h
    foreach ln [split $q "\n"] {
        set s [string trim $ln]
        if {$s eq ""} continue
        if {[regexp {^(Route|Length|Delay|Net|Src|Dest|Hop)} $s]} { puts "RTE $s" }
    }
}

# ---- (5) the netlist-level truth about that one net: pin count (drives the FANOUT verdict) ----
set q [get_pins -quiet $src_name/Q]
puts "SRC_PIN_found=[llength $q]"
if {[llength $q] > 0} {
    set n [get_nets -quiet -of $q]
    puts "SRC_NET [get_property NAME $n] pincount=[get_property PIN_COUNT $n] fanout=[get_property FANOUT $n]"
    set i 0
    foreach p [get_pins -quiet -of $n] {
        incr i
        if {$i <= 12} { puts "LOAD $i $p" }
    }
    puts "LOAD_TOTAL=$i"
}
puts "D0DONE"
exit 0

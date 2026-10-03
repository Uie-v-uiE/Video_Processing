# build/tcl/r115_window_true_probe.tcl -- measure the DATASHEET window on the shipped routed DCP
#
# ALL-ASCII FILE ON PURPOSE. Earlier revisions of this probe carried CJK comments; one of them
# killed the script inside `rowline` (Vivado decodes a .tcl under the system codepage, and a
# mis-decoded lead byte can swallow a following brace/quote). The repo rule was "ASCII only in
# puts labels, CJK fine in comments" -- this file is the counter-example, so the whole file is
# ASCII now. See ISSUES #307.
#
# Why (2026-10-04 00:3x-00:4x): the +/-0.500 window used by r114 came from the WRONG row of
# RTL8211F-CG Table 60 (TskewT = transmitter output skew, "without delay integrated"). Sourced
# facts (build/evidence/r115_rtl8211f_delay_source.txt):
#   * schematic p8 (ZYNQ7020-F+V1.1): R57 4.7K pulls PHY1_RXD0 up to PHY1_IODVDD, R59 4.7K pulls
#     PHY1_RXD1 up to PHY1_IODVDD (PHY2 mirrors it: R72/R73)
#   * datasheet Table 10 (p23): RXD0=RXDLY, RXD1=TXDLY; Table 11 (p23) / Table 6 (p16):
#     "1: Add 2ns delay to RXC for RXD latching (via 4.7k-ohm to DVDD_RG)"
#   => RXC is delayed ~2 ns INSIDE the PHY, so RXD transitions arrive BEFORE the capture edge.
#      The Table 60 row names are from the PHY's side, not ours: "transmitter" = PHY output =
#      OUR RX path; "receiver" = PHY input = OUR TX path. For eth_rxd/eth_rx_ctl the rows are
#        TsetupT (Data to Clock Output Setup at transmitter, delay integrated) min 1.2 typ 2 ns
#        TholdT  (Clock to Data Output Hold  at transmitter, delay integrated) min 1.2 typ 2 ns
#      -> the transition sits [1.2, 2.8] ns before its capture edge (the two sum to the 4 ns
#         half-cycle and both have min 1.2). TskewR (1/1.8/2.6, note "PCB delay >1.5 <2.0 ns")
#         is the OTHER direction (our TXD/TXC toward the PHY) and must not be used here.
# Vivado measures set_input_delay from the LAUNCH edge and checks setup at launch+period, so
# "data 1.2..2.8 ns before its capture edge" is the SAME statement as "data 5.2..6.8 ns after the
# previous rising edge". Both spellings are measured, each with and without the -clock_fall pair,
# so the shape of the check is read from the tool instead of argued from memory.
#
# Two ruler-side traps already paid for here:
#   1) `set_input_delay -min -2.800 ...` on the Tcl command line reads "-2.800" as another
#      switch => "Too many positional options", no window is applied, every report says inf.
#      Fix: write the window into an XDC and source it -- that is also how it enters a build.
#   2) report_timing_summary has no -check_timing_override option (that run died at exit 170).
# Read-only: the DCP is never written back; constraints live in this session + scratch XDC files.
set root [file normalize [file join [file dirname [info script]] .. ..]]
if {[info exists ::env(VP_WT_DCP)]} { set dcp $::env(VP_WT_DCP) } else {
    set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
}
set out [file join $root build evidence r115_window]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp
puts "WT_DCP $dcp"

set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set clk   [get_clocks -quiet eth_rxc]
puts "WT_OBJS ports=[llength $ports] clocks=[llength $clk]"
if {[llength $ports] == 0 || [llength $clk] == 0} { puts "REFUSE empty object set"; exit 4 }

# first non-separator line after a table header
proc numline {tag f hdr} {
    set h [open $f r]; set t [read $h]; close $h
    set lines [split $t "\n"]
    for {set i 0} {$i < [llength $lines]} {incr i} {
        if {[string first $hdr [lindex $lines $i]] >= 0} {
            for {set j [expr {$i + 1}]} {$j < [llength $lines] && $j <= $i + 4} {incr j} {
                set s [string trim [lindex $lines $j]]
                if {$s eq ""} continue
                if {[regexp {^[-[:space:]]+$} $s]} continue
                puts "STAGE $tag ${hdr}_NUM $s"
                return
            }
            puts "STAGE $tag ${hdr}_NUM NO_DATA_ROW"
            return
        }
    }
    puts "STAGE $tag ${hdr}_NUM NO_HEADER"
}

# the per-clock row: this round judges by clock, not by the global WNS
proc rowline {tag f pat} {
    set h [open $f r]; set t [read $h]; close $h
    set n 0
    foreach ln [split $t "\n"] {
        set s [string trim $ln]
        if {$s eq ""} continue
        # NOT lindex: a summary line can contain an unbalanced brace and lindex then throws
        # (that is what killed this probe twice). string match on the leading token is safe.
        if {[string equal $s $pat] || [string match "$pat *" $s]} {
            incr n
            if {$n > 3} break
            puts "STAGE $tag ROW |$s"
        }
    }
    if {$n == 0} { puts "STAGE $tag ROW NO_ROW pat=$pat" }
}

proc stage {tag} {
    global out ports clk
    foreach {dt suf} {min HOLD max SETUP} {
        set f [file join $out "wt_${tag}_${suf}.txt"]
        file delete -force $f
        report_timing -delay_type $dt -from $ports -to $clk -nworst 1 -max_paths 2 -file $f
        set h [open $f r]; set t [read $h]; close $h
        set s [regexp -all -inline {Slack(?: \([A-Z]+\))?\s*:\s+\S+} $t]
        puts "STAGE $tag $suf slack=[join $s { ; }]"
        set n 0
        foreach ln [split $t "\n"] {
            if {[regexp {^\s+(Slack|Requirement|Input Delay|Path Group|Clock Path Skew|Clock Uncertainty|Data Path Delay):} $ln]} {
                incr n
                if {$n > 14} break
                puts "STAGE $tag $suf |[string trim $ln]"
            }
        }
    }
    set f [file join $out "wt_${tag}_summary.txt"]
    file delete -force $f
    report_timing_summary -file $f
    numline $tag $f "WNS(ns)"
    rowline $tag $f eth_rxc
}

# one window = one scratch XDC. The port pattern is put in braces from a variable so the file
# really contains {eth_rxd[*] eth_rx_ctl}: writing "...\[\*\]..." leaves the backslashes in the
# file, the pattern then matches nothing, the window hangs on nothing and the report still looks
# clean. The written file is read back and printed, and the pattern is counted, for that reason.
proc setw {mn mx fall {tag x}} {
    global out
    set pat {eth_rxd[*] eth_rx_ctl}
    set f [file join $out "wt_${tag}.xdc"]
    set h [open $f w]
    puts $h "set_input_delay -clock eth_rxc -min $mn -max $mx \[get_ports {$pat}\]"
    if {$fall} {
        puts $h "set_input_delay -clock eth_rxc -clock_fall -min $mn -max $mx -add_delay \[get_ports {$pat}\]"
    }
    close $h
    set h [open $f r]; set body [read $h]; close $h
    puts "XDC $tag [string trim [join [split $body \n] { || }]]"
    # braced literal, not $pat: an unquoted list becomes TWO positional patterns and Vivado's
    # parser rejects that ("Too many positional options") -- the same trap as the negative -min.
    set nports [llength [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]]
    if {$nports != 5} { puts "REFUSE matched=$nports want=5"; return "REFUSE_PORT_PATTERN" }
    # source is the wrong door: this Vivado's set_input_delay takes ONE objects argument, and a
    # 5-element port list splices into 5 positional args -> "Too many positional options".
    # read_xdc is the door the build itself uses, so the syntax check happens under the same
    # parser that will see the file when it is really adopted.
    set e no-error
    catch {read_xdc -unmerged $f} e
    return $e
}

stage W0_none
puts "W1 rc=[setw -2.800 -1.200 0 W1]"
stage W1_rise_neg
puts "W2 rc=[setw 5.200 6.800 0 W2]"
stage W2_rise_pos
puts "W3 rc=[setw 5.200 6.800 1 W3]"
stage W3_both_pos
puts "W4 rc=[setw -2.800 -1.200 1 W4]"
stage W4_both_neg
puts "WTDONE"
exit 0

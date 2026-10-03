# build/tcl/r115_window_probe2.tcl -- the datasheet window, measured, plus the IDELAY tap curve
#
# ASCII-only file (see ISSUES #307). Three parser shapes were paid for before this version:
#   * set_input_delay takes -min OR -max in ONE command, never both -- the combined form dies
#     with "Too many positional options when parsing '<the ports>'", which blames the port list
#     and not the flags (ISSUES #308).
#   * report_timing_summary has no -check_timing_override; read_xdc has no -unmerged.
#   * `source` is the right door for a scratch XDC.
# Window numbers: RTL8211F-CG Table 60 rows TsetupT / TholdT (min 1.2 typ 2 ns) with RXDLY strap
# pulled up by R57/R59 on this board -> the transition sits [1.2, 2.8] ns BEFORE its capture edge.
# Two spellings are measured because Vivado references set_input_delay to the LAUNCH edge and
# checks setup at launch+period: same-edge (-2.800/-1.200) and period-shifted (5.200/6.800) are
# the same physical statement; which one the tool turns into a *sensible pair of checks* is a
# fact about the tool, so it is read, not argued.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out [file join $root build evidence r115_window]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp

set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set clk   [get_clocks -quiet eth_rxc]
puts "WP2_OBJS ports=[llength $ports] clocks=[llength $clk]"
if {[llength $ports] != 5 || [llength $clk] != 1} { puts "REFUSE object counts"; exit 4 }

proc rep2 {tag} {
    global out ports clk
    foreach {dt suf} {min HOLD max SETUP} {
        set f [file join $out "w2_${tag}_${suf}.txt"]
        file delete -force $f
        report_timing -delay_type $dt -from $ports -to $clk -nworst 1 -max_paths 1 -file $f
        set h [open $f r]; set t [read $h]; close $h
        set s [regexp -all -inline {Slack(?: \([A-Z]+\))?\s*:\s+\S+} $t]
        set r [regexp -all -inline {Requirement:\s+\S+ns\s+\([^\)]*\)} $t]
        puts "W2STAGE $tag $suf slack=[join $s { }] req=[join $r { }]"
    }
}

# one window = 2 (or 4) XDC lines: -min and -max are SEPARATE commands
proc setw {tag mn mx fall} {
    global out
    set f [file join $out "w2_${tag}.xdc"]
    set h [open $f w]
    foreach {o v} [list -min $mn -max $mx] {
        puts $h "set_input_delay -clock eth_rxc $o $v \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
    }
    if {$fall} {
        foreach {o v} [list -min $mn -max $mx] {
            puts $h "set_input_delay -clock eth_rxc -clock_fall $o $v -add_delay \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
        }
    }
    close $h
    set body [read [open $f r]]
    close [open $f r]
    puts "W2XDC $tag lines=[llength [split [string trim $body] \n]]"
    set e no-error
    catch {source $f} e
    puts "W2SET $tag rc=$e"
}

proc taps {tag} {
    global out
    set cells [get_cells -quiet {u_eth/u_rgmii/u_rgmii_rx/u_delay_rx_ctrl \
                                 u_eth/u_rgmii/u_rgmii_rx/rxdata_bus\[*\].u_delay_rxd}]
    puts "TAP $tag cells=[llength $cells]"
    if {[llength $cells] != 5} { puts "TAP $tag REFUSE cell count"; return }
    foreach t $tag {
        set e no-error
        catch {set_property IDELAY_VALUE $t $cells} e
        puts "TAP set=$t rc=$e readback=[get_property IDELAY_VALUE [lindex $cells 0]]"
        if {[string match "ERROR*" $e]} continue
        rep2 "tap$t"
    }
}

rep2 W0_none
setw W1 -2.800 -1.200 0
rep2 W1_rise_neg
setw W2 5.200 6.800 0
rep2 W2_rise_pos
setw W3 5.200 6.800 1
rep2 W3_both_pos
setw W4 -2.800 -1.200 1
rep2 W4_both_neg
# tap curve under the spelling that produced a finite, sensible pair of checks
taps {0 8 16 20 26 31}
set f [file join $out w2_summary_final.txt]
file delete -force $f
report_timing_summary -file $f
puts "WP2DONE"
exit 0

# 用途：the spelling the tool's own edge pairing asks for, swept over taps
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/r115_window_probe3.tcl -- the spelling the tool's own edge pairing asks for, swept over taps
#
# probe2 (件 build/evidence/r115_window/probe2_console.txt) read out the tool's model:
#   * for an IDDR D pin, setup is checked launch-rising -> capture-FALLING (Requirement 4.000,
#     "fall@4 - rise@0"), and hold against the SAME rising edge (Requirement 0.000).
#   * so set_input_delay must be measured from the edge that LAUNCHES, and the data captured at
#     fall@4 is the transition that sits between rise@0 and fall@4.
#   * the two spellings tried there (-2.800/-1.200 and 5.200/6.800) are the same statement shifted
#     by a FULL period; neither is what the half-period pairing asks for.
# Physical window: RXDLY is on (R57/R59 4.7K to IODVDD), the PHY delays RXC ~2 ns, so the
# transition is [1.2, 2.8] ns before its capture edge == [1.2, 2.8] ns after the launching edge.
# That is W5 = -min 1.200 -max 2.800. This probe measures W5 and sweeps IDELAY_VALUE, because
# `set_property IDELAY_VALUE` was proven to take effect on the routed DCP (probe2 readback 0..31).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out [file join $root build evidence r115_window]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
open_checkpoint $dcp
set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set clk   [get_clocks -quiet eth_rxc]
puts "WP3_OBJS ports=[llength $ports] clocks=[llength $clk]"
if {[llength $ports] != 5 || [llength $clk] != 1} { puts "REFUSE object counts"; exit 4 }
set cells [get_cells -quiet u_eth/u_rgmii/u_rgmii_rx/*u_delay*]
puts "WP3_IDDR_IDELAY cells=[llength $cells]"
if {[llength $cells] != 5} { puts "REFUSE idelay cell count"; exit 4 }

proc rep3 {tag} {
    global out ports clk
    foreach {dt suf} {min HOLD max SETUP} {
        set f [file join $out "w3_${tag}_${suf}.txt"]
        file delete -force $f
        report_timing -delay_type $dt -from $ports -to $clk -nworst 1 -max_paths 1 -file $f
        set h [open $f r]; set t [read $h]; close $h
        set s [regexp -all -inline {Slack(?: \([A-Z]+\))?\s*:\s+\S+} $t]
        set d [regexp -all -inline {Data Path Delay:\s+\S+} $t]
        set k [regexp -all -inline {Clock Path Skew:\s+\S+} $t]
        set c [regexp -all -inline {Clock Uncertainty:\s+\S+} $t]
        puts "W3S $tag $suf [join $s { }] [join $d { }] [join $k { }] [join $c { }]"
    }
}
proc setwin {mn mx} {
    global out
    set f [file join $out w3_win.xdc]
    set h [open $f w]
    puts $h "set_input_delay -clock eth_rxc -min $mn \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
    puts $h "set_input_delay -clock eth_rxc -max $mx \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
    puts $h "set_input_delay -clock eth_rxc -clock_fall -min $mn -add_delay \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
    puts $h "set_input_delay -clock eth_rxc -clock_fall -max $mx -add_delay \[get_ports {eth_rxd\[*\] eth_rx_ctl}\]"
    close $h
    set e no-error
    catch {source $f} e
    puts "W3WIN mn=$mn mx=$mx rc=$e"
}
setwin 1.200 2.800
foreach t {0 4 8 12 16 20 24 26 28 31} {
    set e no-error
    catch {set_property IDELAY_VALUE $t $cells} e
    set rb [get_property IDELAY_VALUE [lindex $cells 0]]
    rep3 "tap$t"
    puts "W3TAP set=$t rb=$rb rc=$e"
}
# and the same sweep with the 0.800 hold band removed, to separate "the design" from "my band"
# set the band to 0 rather than "remove" it: remove_clock_uncertainty is not a command in this
# version, and a 0.000 hold band is the same statement in a form the report can show back to me
# (the Clock Uncertainty column in the lines below is the proof the band actually moved).
set e no-error
catch {set_clock_uncertainty -hold 0.000 $clk} e
puts "W3BANDBLANK rc=$e"
foreach t {0 12 26 31} {
    catch {set_property IDELAY_VALUE $t $cells} e
    rep3 "noband_tap$t"
    puts "W3TAP noband set=$t rb=[get_property IDELAY_VALUE [lindex $cells 0]]"
}
puts "WP3DONE"
exit 0

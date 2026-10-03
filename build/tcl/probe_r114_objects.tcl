# build/tcl/probe_r114_objects.tcl -- read-only object discovery for the r114 I/O + async-bound cut.
#   Why: writing `set_output_delay -clock <clk>` / `create_generated_clock -source <pin>` needs the *real* object
#     names on this netlist, and r113 never asked. Guessing a pin name produces CRITICAL WARNING
#     [Constraints 18-513] "contains no valid startpoints" -- an *empty* constraint that still lets the build
#     finish (that exact failure mode is already documented at src/constraints/rk_zynq7020.xdc:52-55).
#   Also settles two open questions with measurements instead of prose:
#     * `report_methodology` has NO `-rules` option in 2025.2.1 -- it is `-checks` (the first probe died on
#       `Unknown option '-rules'`, ISSUES-side note; help output is copied below so nobody re-guesses).
#     * whether `link_design -dcp ... -xdc ...` is the right way to A/B a constraint change on the fast lane.
#   Runtime labels stay ASCII (see probe_timing_roster.tcl's header for why).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

puts "CLOCKS_LIST=[join [get_property NAME [get_clocks -quiet *]] ,]"

## ---- which clock drives each debt face, and what pins drive the two output clocks ----
foreach p {tmds_clk_p tmds_clk_n eth_tx_clk eth_tx_ctl {led[0]} {eth_rxd[0]} eth_rx_ctl} {
    set po [get_ports -quiet $p]
    if {$po eq ""} { puts "PORT|name=$p|MISSING"; continue }
    puts "PORT|name=[get_property NAME $po]|dir=[get_property DIR $po]|LOC=[get_property LOC $po]|SLEW=[get_property SLEW $po]|IOSTANDARD=[get_property IOSTANDARD $po]"
    set drivers ""
    catch {set drivers [get_property NAME [get_pins -quiet -of_objects [get_nets -quiet -of_objects $po]]]} ed
    puts "  DRIVERS=$drivers"
}

## ---- the ODDR / buffer cells that actually launch the two source-synchronous output clocks ----
# Property names are only used where they were already proven to exist in this tool (REF_NAME, NAME, DIR, LOC).
# The scan is deliberately narrow: every `-hier` query here is answered by a -filter, because an unfiltered
# `get_pins -hier` over this netlist (14154 LUT / 8188 FF) turns a 3 minute probe into a 20 minute one.
set n 0
foreach c [get_cells -quiet -hier -filter {REF_NAME eq ODDR}] {
    set nm [get_property NAME $c]
    if {$n < 200 && ([string match *tmds* $nm] || [string match *tx_clk* $nm] || [string match *txd* $nm])} {
        puts "ODDRCELL|name=$nm"
        # the C pin of the ODDR that launches the clock output is what a generated clock must hang on
        foreach q [get_pins -quiet -of_objects $c] {
            if {[get_property DIRECTION $q] ne "I"} { continue }
            if {![string match */C [file tail $q]]} { continue }
            set net [get_nets -quiet -of_objects $q]
            set clks ""
            if {$net ne ""} { set clks [get_property NAME [get_clocks -quiet -of_objects $net]] }
            puts "  ODDRC|pin=$q|net=[expr {$net eq "" ? "none" : [get_property NAME $net]}]|clocks=[join $clks ,]"
        }
    }
    set n [expr {$n + 1}]
}
puts "ODDRCELL_COUNT=$n"
foreach c [get_cells -quiet -hier -filter {NAME =~ *tx_clk*}] {
    puts "TXCLK_CELL|name=[get_property NAME $c]|ref=[get_property REF_NAME $c]"
}

## ---- current exception inventory, so "how many bounds exist" is a count not a feeling ----
set fp [get_false_paths -quiet]
puts "EXC|false_paths=[llength $fp]"
foreach e $fp { puts "  FALSEPATH|[get_property OBJECT_CLASS $e]|[join [get_property FROM $e] ,]|[join [get_property TO $e] ,]" }
set md [get_max_delays -quiet]
puts "EXC|max_delays=[llength $md]"
set od [get_output_delays -quiet]
puts "EXC|output_delays=[llength $od]"
set id [get_input_delays -quiet]
puts "EXC|input_delays=[llength $id]"
puts "EXC|clock_groups=[llength [get_clock_groups -quiet *]]"

## ---- report_methodology's real shape: -checks, and the TIMING-18 count from its own SUMMARY table ----
set mh [file join $root "build/methodology_all.rpt"]
file delete -force $mh
set merr ""
catch {report_methodology -file $mh} merr
puts "METH|rc_msg=$merr|file=$mh|bytes=([file size $mh])"
if {[file exists $mh]} {
    set fh [open $mh r]; set t [read $fh]; close $fh
    foreach line [split $t "\n"] {
        set l [string trim $line]
        if {[regexp {^(TIMING-1[0-9]|TIMING-[0-9]+|STDREC-[0-9]+|SLSN-[0-9]+|UTIM-6|CLOCK3-[0-9]+)\s+(\d+)\s*$} $l]} {
            puts "METHROW|$l"
        }
        if {[regexp {^Checks found\s*:\s*(\d+)} $l -> n]} { puts "METH_CHECKS_FOUND=$n" }
    }
}
## ---- does the fast lane accept a swapped XDC on the synthesized netlist? measure, don't assume ----
set hl ""
catch {set hl [help link_design]} eh
puts "LINK_DESIGN_HELP_BEGIN"
puts $hl
puts "LINK_DESIGN_HELP_END|rc_msg=$eh"
puts "R114_OBJECT_PROBE_DONE"

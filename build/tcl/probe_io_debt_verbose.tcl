# build/tcl/probe_io_debt_verbose.tcl -- read-only probe on the routed dcp. Two questions, both left open by
#   r113 and both named in build/r114_batch_plan.md:
#   (A) section 二.1: the I/O debt has THREE different counts from THREE different tools (check_timing says
#       5 inputs + 6 outputs, my src/host/check_io_timing_coverage.py counts 2/7 ports = 5/12 pins, and
#       report_methodology counts TIMING-18 = 7). UG949's rule is that every I/O either carries a delay
#       constraint or carries an exception whose reason is written down -- so the authoritative thing to fix
#       against is the tool's own *named* list. This is the first time -verbose is asked (r113's build was in
#       flight, so I refused to open a second Vivado). It prints raw text; the counting stays in the python ruler.
#   (B) section 三's ⚠ line: `set_max_fanout` does not exist in 2025.2.1 (ISSUES #264), and whether the
#       MAX_FANOUT *property* exists on nets/cells was never measured. list_property answers that without
#       guessing; the answer decides whether "official MAX_FANOUT" can be cited at all.
#   Shape lessons baked in: runtime labels are ASCII (Vivado reads this file under the system codepage; a CJK
#   puts label once broke command substitution and turned the console binary for grep); guards are separate
#   steps because `expr` here forbids inline `info exists`; net/cell names carry [n] which are glob classes, so
#   filters use `eq`, never patterns.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set md5_pre ""
catch {set md5_pre ""} err0

## ---- (A1) check_timing -verbose: the tool's own named list ----
set ct [file join $root "build/check_timing_verbose.rpt"]
file delete -force $ct
set cterr ""
catch {check_timing -verbose -file $ct} cterr
puts "IODEBT|check_timing|rc_msg=$cterr"
puts "IODEBT|check_timing|file=$ct"
if {![file exists $ct]} { puts "IODEBT|FATAL|no report written"; exit 1 }
set fh [open $ct r]; set txt [read $fh]; close $fh
puts "IODEBT|check_timing|bytes=[file size $ct]"

# One machine-readable line per sentence that names an object, so the python ruler can diff names instead of
# counting. The verbose form is "Type", "Object"/"Pin"/"Port" plus the offending clock -- we only extract the
# port names here, and deliberately do NOT reinterpret the counts (rule: three sources keep three names).
set n_in 0
set n_out 0
set names ""
foreach line [split $txt "\n"] {
    set l [string trim $line]
    if {[regexp {input delay} $l] || [regexp {An input delay is missing} $l]} {
        if {[regexp {on\s+(\S+)} $l -> p]} {
            lappend names "IN:$p"
            set n_in [expr {$n_in + 1}]
        }
    } elseif {[regexp {output delay} $l] || [regexp {An output delay is missing} $l]} {
        if {[regexp {on\s+(\S+)} $l -> p]} {
            lappend names "OUT:$p"
            set n_out [expr {$n_out + 1}]
        }
    }
}
puts "IODEBT|check_timing_verbose|input_sentences=$n_in|output_sentences=$n_out"
foreach x $names { puts "IONAME|$x" }

## ---- (A2) report_methodology TIMING-18: the same debt in the methodology voice ----
set m18 [file join $root "build/methodology_timing18.rpt"]
file delete -force $m18
set merr ""
catch {report_methodology -rules TIMING-18 -file $m18} merr
puts "IODEBT|methodology_TIMING-18|rc_msg=$merr|file=$m18|bytes=([file size $m18])"
if {[file exists $m18]} {
    set fh2 [open $m18 r]; set t2 [read $fh2]; close $fh2
    set c [llength [regexp -all -inline {TIMING-18#[0-9]+} $t2]]
    puts "IODEBT|methodology_TIMING-18|detail_headings=$c"
    foreach line [split $t2 "\n"] {
        if {[regexp {delay is missing on\s+(\S+)\s+relative to.*of\s+(.*)$} [string trim $line] -> p cl]} {
            puts "M18NAME|$p|clock=[string trim $cl]"
        }
    }
}

## ---- (A3) what the port set actually looks like, so a pin-vs-port unit error cannot repeat (ISSUES #267) ----
# Vivado's -direction values are the literals in / out / inout -- NOT i/o/io. A wrong one here returns nothing
# and would make the buckets look empty instead of wrong, so each count is printed next to its own query.
set pins_in  [get_ports -quiet -direction in]
set pins_out [get_ports -quiet -direction out]
set pins_io  [get_ports -quiet -direction inout]
puts "IODEBT|ports|in=[llength $pins_in]|out=[llength $pins_out]|inout=[llength $pins_io]|total=[llength [get_ports -quiet *]]"
# differential: which top-level ports carry NO constraint and NO exception at all (that is the real debt face).
# Every query sits in a catch because a nonexistent sub-command must not kill a probe that costs minutes:
# the answer we want is "0", not a stack trace.
set uncons 0
foreach p [get_ports -quiet *] {
    set nm [get_property NAME $p]
    set c 0
    catch {set c [llength [get_input_delays -quiet -of_objects $p]]} e1
    set d 0
    catch {set d [llength [get_output_delays -quiet -of_objects $p]]} e1b
    set exc 0
    catch {set exc [llength [get_false_paths -quiet -to $p]]} e2
    set excf 0
    catch {set excf [llength [get_false_paths -quiet -from $p]]} e3
    set excm 0
    catch {set excm [llength [get_max_delays -quiet -to $p]]} e4
    catch {set excm [expr {$excm + [llength [get_max_delays -quiet -from $p]]}]} e5
    if {$c == 0 && $d == 0 && $exc == 0 && $excf == 0 && $excm == 0} {
        puts "UNCONSTRAINED_PORT|$nm|dir=[get_property DIR $p]"
        set uncons [expr {$uncons + 1}]
    }
}
puts "IODEBT|unconstrained_ports=$uncons"

## ---- (B) MAX_FANOUT: measured, not guessed ----
set one_net [lindex [get_nets -quiet -limit 1 *] 0]
if {$one_net eq ""} { puts "MAXFAN|FATAL|no nets"; exit 1 }
set netprops [list_property $one_net]
set nethits [lsearch -all -inline -exact $netprops *FANOUT*]
puts "MAXFAN|net_props=[join $nethits ,]"
set one_cell [lindex [get_cells -quiet -limit 1 -hier *] 0]
set cellhits ""
if {$one_cell ne ""} {
    set cellprops [list_property $one_cell]
    set cellhits [lsearch -all -inline -exact $cellprops *FANOUT*]
}
puts "MAXFAN|cell_props=[join $cellhits ,]"
set one_pin [lindex [get_pins -quiet -limit 1 -hier *] 0]
set pinhits ""
if {$one_pin ne ""} {
    set pprops [list_property $one_pin]
    set pinhits [lsearch -all -inline -exact $pprops *FANOUT*]
}
puts "MAXFAN|pin_props=[join $pinhits ,]"
# current value on the two known broadcast nets, so "did the lever move it" is a count not a feeling
foreach nm {rok4[51]_i_1_n_0} {
    set nn [get_nets -quiet -filter [list NAME eq $nm]]
    if {$nn eq ""} { puts "MAXFAN|net=$nm|MISSING" } else {
        puts "MAXFAN|net=$nm|FANOUT_CURRENT=([get_property FANOUT $nn])|MAX_FANOUT_PROP=([catch {get_property MAX_FANOUT $nn} v; set v])"
    }
}
puts "IO_DEBT_PROBE_DONE"

# 用途：read-only "ALL clocks, not just the worst path" roster.
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/probe_timing_roster.tcl -- read-only "ALL clocks, not just the worst path" roster.
#   Why (2026-10-03, user's ask: 别只追最差的那条，改时序要看全局): build/tcl/crit_path.tcl ranks the whole
#     design, so it always shows the same headline clock (eth_rxc) and hides what the other domains did.
#     The documented method (UG949-style) is per-clock / per-path-group first, then logic; a round that moves
#     one domain up and two domains down is NOT a gain, and only a roster shows that. This probe costs a few
#     minutes on the routed dcp and no rebuild, so "look at the whole picture" is cheap.
#   Shape lessons already baked in (do not "improve" them back):
#     * `-of_objects [get_clocks X]` refuses BOTH -delay_type and -max_paths ([Vivado 12-1365]); the working
#       shape is `-from $cl -to $cl` (same as build/tcl/probe_clk_worst.tcl).
#     * Runtime labels stay ASCII: Vivado Tcl reads this file under the system codepage, and a CJK puts label
#       broke command substitution once and made the console binary for grep.
#     * `expr` here forbids `info exists` inline (see the environment notes), so guards are separate steps.
#   Usage: VP_LABEL=<id> [VP_N=<k>] vivado -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl
#     rows:  ROSTER|<setup|hold>|clk=...|period=...|slack=...|margin_pct=...|levels=...|route_pct=...|dest=...
#            FANOUT|fo=<n>|cell=...           DESIGN|wns=...|whs=...           ROSTER_ROWS=<n>
set root [file normalize [file join [file dirname [info script]] .. ..]]
set label "roster"
if {[info exists ::env(VP_LABEL)]} { set label $::env(VP_LABEL) }
set n 2
if {[info exists ::env(VP_N)]} { set n $::env(VP_N) }
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set all [get_clocks -quiet *]
set nrows 0
puts "CLOCKS_TOTAL=[llength $all]"
foreach c $all {
    set nm  [get_property NAME $c]
    set per [get_property PERIOD $c]
    if {$per eq ""} { set per 0 }
    foreach kind {setup hold} {
        set dt max
        if {$kind eq "hold"} { set dt min }
        set one [file join $root "build/roster_${label}_${nm}_${kind}.rpt"]
        file delete -force $one
        catch {report_timing -delay_type $dt -nworst 1 -max_paths $n -from $c -to $c -file $one} err
        set slack ""
        set levels ""
        set route ""
        set dest ""
        if {[file exists $one]} {
            set fh [open $one r]
            set txt [read $fh]
            close $fh
            foreach line [split $txt "\n"] {
                set t [string trim $line]
                if {$slack eq "" && [string match "Slack*" $t]} {
                    set slack [string trim [lindex [split $t ":"] 1]]
                }
                if {[string match "Logic Levels*" $t]} { set levels [string trim [lindex [split $t ":"] 1]] }
                if {$route eq "" && [string match "Data Path Delay*" $t]} {
                    # MEASURED shape: `Data Path Delay:  3.498ns  (logic 0.655ns (18.725%)  route 2.843ns (81.275%))`
                    #   -- the percentage sits INSIDE parentheses, so the first version of this line
                    #   #   {route\s+([0-9.]+)ns\s+([0-9.]+)%} never matched and every ROSTER row carried an
                    #   #   EMPTY route_pct (r113 after-roster rows show `route_pct=`). Match the parens.
                    if {[regexp {route\s+([0-9.]+)ns\s*\(\s*([0-9.]+)%\s*\)} $t -> rns rpct]} { set route $rpct }
                }
                if {$dest eq "" && [string match "Destination:*" $t]} {
                    set dest [string trim [lindex [split $t ":"] 1]]
                }
            }
        }
        if {$slack eq ""} { set slack NOWRITE }
        # A missing column must read NA, not empty: the diff tool's D5 asks for "no empty readings", and a
        #   blank silently means both "this clock has no path" and "my regex missed a real report line" --
        #   those two are different claims and have to look different on disk.
        if {$levels eq ""} { set levels NA }
        if {$route eq ""} { set route NA }
        if {$dest eq ""} { set dest NA }
        set pct "NA"
        if {$per > 0 && $slack ne "NOWRITE"} {
            set sv 0.0
            set got [catch {scan $slack "%f" sv} e]
            if {$got == 0} { set pct [format "%.2f" [expr {100.0 * $sv / $per}]] }
        }
        puts "ROSTER|$kind|clk=$nm|period=$per|slack=$slack|margin_pct=$pct|levels=$levels|route_pct=$route|dest=$dest"
        incr nrows
    }
}

set wns "NA"
set whs "NA"
catch {
    set p [get_timing_paths -delay_type max -nworst 1 -max_paths 1]
    if {[llength $p] > 0} { set wns [get_property SLACK [lindex $p 0]] }
}
catch {
    set p [get_timing_paths -delay_type min -nworst 1 -max_paths 1]
    if {[llength $p] > 0} { set whs [get_property SLACK [lindex $p 0]] }
}
puts "DESIGN|wns=$wns|whs=$whs"

# Design-wide fanout list: the documented global lever for a route-dominated broadcast is MAX_FANOUT /
#   QoR "propagate max fanout" suggestions (UG949 timing closure; AMD adaptive-support article 9410) --
#   and you cannot pick a number without naming the nets.
#   MEASURED 2026-10-03 (build/evidence/r113_help_fanout_console.txt, from this very Vivado 2025.2.1):
#     * `help report_design_analysis` has NO -fanout mode. Its modes are -complexity / -congestion / -timing /
#       -routes / -logic_level_distribution / -routed_vs_estimated / -qor_summary; the only fanout-ish option
#       is -av_fanout_greater_than (a Rent-exponent analysis threshold, not a net list).
#       That is why the first two roster runs wrote an EMPTY file: the command I guessed did not exist, the
#       catch swallowed it, and D6 went red on MY tool while the design was innocent.
#     * The right command is `report_high_fanout_nets` (categories Report, Timing; works on an implemented
#       design), options used here: -file / -max_nets / -fanout_greater_than / -quiet.
#   Because the COLUMN ORDER of that text report has not been measured yet, rows are parsed position-free:
#     the fanout is the first strictly-integer token >= MINFO, the name is the first token that is not a
#     number and contains a hierarchy character. Whatever the parser does, the raw report head is printed as
#     FANOUT_HEAD so the shape is on the record, and FANOUT_ROWS counts rows PARSED (0 stays visible/red).
set frpt [file join $root "build/roster_${label}_fanout.rpt"]
file delete -force $frpt
set minfo 60
if {[info exists ::env(VP_MINFO)]} { set minfo $::env(VP_MINFO) }
set ferr "no-error"
catch {report_high_fanout_nets -quiet -max_nets 40 -fanout_greater_than $minfo -file $frpt} ferr
puts "FANOUT_ERR=$ferr"
puts "FANOUT_EXISTS=[file exists $frpt]"
set shown 0
if {[file exists $frpt]} {
    set fh [open $frpt r]; set txt [read $fh]; close $fh
    set lines [split $txt "\n"]
    set i 0
    foreach ln $lines {
        if {$i < 30} { puts "FANOUT_HEAD|$ln"; incr i } else { break }
    }
    foreach line $lines {
        set t [string trim $line]
        if {$t eq ""} { continue }
        set fo ""
        set nm ""
        foreach tok [split $t] {
            if {[string is integer -strict $tok]} {
                if {$fo eq "" && $tok >= $minfo} { set fo $tok }
            } elseif {$nm eq "" && ([string first "/" $tok] >= 0 || [string first "_" $tok] >= 0)} {
                set nm $tok
            }
        }
        if {$fo ne "" && $nm ne ""} {
            # No get_nets existence check here on purpose: net names carry [n] bit indices, which are GLOB
            #   classes for get_nets, so an unescaped lookup would reject the very biggest broadcasts and
            #   quietly return FANOUT_ROWS=0 again. The probe only inventories; resolution with a bracket-safe
            #   the `==` operator (NOT `eq`, which is a syntax error here) happens in build/tcl/mf114_roll.tcl, where an empty set must stop the roll.
            puts "FANOUT|fo=$fo|net=$nm"
            incr shown
            if {$shown >= 20} { break }
        }
    }
}
# QoR suggestions: UG949's own workflow is "ask the tool, then review the list" -- this is the *global*
#   suggestion roster (MAX_FANOUT propagation, clock-buffer/hold fixes, etc.). It is captured as rows so a
#   round's plan can be driven by the tool's list instead of only by my reading of the worst path.
#   Both commands are wrapped: if this Vivado build lacks them the probe says so instead of dying.
set srpt [file join $root "build/roster_${label}_qor.rpt"]
file delete -force $srpt
catch {report_qor_suggestions -max_candidates 12 -file $srpt} serr
catch {write_qor_suggestions -force -file [file join $root "build/roster_${label}_qor.rqs"]} werr
puts "QOR_ERR=$serr WRITE_ERR=$werr EXISTS=[file exists $srpt]"
if {[file exists $srpt]} {
    set fh [open $srpt r]; set txt [read $fh]; close $fh
    foreach line [split $txt "\n"] {
        set t [string trim $line]
        # 机器行只挑"建议"那一类：形如 `Suggestion #1: ...` / `... MAX_FANOUT ...`
        if {[regexp {^Suggestion.*} $t m]} { puts "QORSUG|$m" }
        if {[regexp {^(.*MAX_FANOUT.*)$} $t m]} { puts "QORHINT|$m" }
    }
}
puts "QOR_DONE=1"

puts "FANOUT_ROWS=$shown"
puts "ROSTER_ROWS=$nrows"
exit 0

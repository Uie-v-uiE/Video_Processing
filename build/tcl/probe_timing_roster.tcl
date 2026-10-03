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
                    if {[regexp {route\s+([0-9.]+)ns\s+([0-9.]+)%} $t -> rns rpct]} { set route $rpct }
                }
                if {$dest eq "" && [string match "Destination:*" $t]} {
                    set dest [string trim [lindex [split $t ":"] 1]]
                }
            }
        }
        if {$slack eq ""} { set slack NOWRITE }
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
#   ⚠ 第一版这里加了 `-limit 12 -interval 4`，结果**文件根本没写出来**（r113 首跑：FANOUT_ROWS=0，
#     差分那侧 D6 判红）。所以现在用最素的调用，并且把错误文本与报告头 20 行念出来 ——
#     "命令跑成功但产物是空的"这件事必须自己说，不许靠下游猜。
set frpt [file join $root "build/roster_${label}_fanout.rpt"]
file delete -force $frpt
catch {report_design_analysis -fanout -quiet -file $frpt} ferr
puts "FANOUT_ERR=$ferr"
puts "FANOUT_EXISTS=[file exists $frpt]"
set shown 0
if {[file exists $frpt]} {
    set fh [open $frpt r]; set txt [read $fh]; close $fh
    set lines [split $txt "\n"]
    set i 0
    foreach ln $lines {
        if {$i < 20} { puts "FANOUT_HEAD|$ln"; incr i } else { break }
    }
    foreach line $lines {
        set t [string trim $line]
        if {[regexp {^([0-9]+)\s+([A-Za-z_/][\w/\[\].-]*)} $t -> fo cell]} {
            if {$fo > 50} { puts "FANOUT|fo=$fo|cell=$cell"; incr shown }
        } elseif {[regexp {\s([0-9]+)\s+([A-Za-z_/][\w/\[\].-]*)\s*$} $t -> fo cell]} {
            if {$fo > 50} { puts "FANOUT|fo=$fo|cell=$cell"; incr shown }
        }
        if {$shown >= 12} { break }
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

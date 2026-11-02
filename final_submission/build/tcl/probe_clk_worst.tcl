# build/tcl/probe_clk_worst.tcl -- read-only "worst paths of ONE clock" probe.
#   Why this exists (2026-10-02, batched-round rule): crit_path.tcl sorts the whole design, so a clock whose
#   slack is second-best (clkout0_1: 20 ns period, ~5.7 % margin) never shows up there -- yet THAT is the cone
#   a per-clock cut has to aim at. Asking the DCP directly costs ~3 minutes and no rebuild, so a timing
#   iteration does not have to pay an hour of bench for a reading (user's ask: 仿真不要每次几小时).
#   Feed it with env vars (no braces -- env values arrive as literal characters, see probe_cone_slack.tcl):
#     VP_CLK   = clock name as report_timing knows it (e.g. clkout0_1)
#     VP_LABEL = short ASCII id for the output file build/probe_clk_<label>.rpt
#     VP_N     = optional number of paths, default 6
#   Runtime labels stay ASCII: Vivado Tcl reads this file under the system codepage and a CJK puts label can
#   break command substitution (build/r107_reasm_probe.txt section 4).
set root [file normalize [file join [file dirname [info script]] .. ..]]
foreach v {VP_CLK VP_LABEL} {
    if {![info exists ::env($v)]} { puts "REFUSE: env $v is not set"; exit 1 }
}
set clk   $::env(VP_CLK)
set label $::env(VP_LABEL)
set n     6
if {[info exists ::env(VP_N)]} { set n $::env(VP_N) }
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
puts "CLK: $clk  LABEL: $label  N: $n"
puts "DCP: $dcp"
open_checkpoint $dcp

set cl [get_clocks -quiet $clk]
if {[llength $cl] == 0} { puts "REFUSE: clock $clk not found in this checkpoint"; exit 1 }
puts "CLOCK period=[get_property period $cl] ns  waveform=[get_property waveform $cl]"

set rpt [file join $root "build/probe_clk_${label}.rpt"]
# ⚠ `-of_objects [get_clocks ...]` refuses BOTH `-delay_type` and `-max_paths`
#   (ERROR: [Vivado 12-1365], twice on the first run of this probe -- and the REFUSE floor below caught it
#   instead of printing an empty verdict, which is the whole point of having it). The shape that works here is
#   the one build/tcl/clock_uncertainty.tcl:38-41 already uses: `-from/-to [get_clocks X]`, which is exactly
#   the intra-clock path set this probe is meant to rank.
catch {report_timing -delay_type max -nworst 1 -max_paths $n -from $cl -to $cl -file $rpt} err
if {![file exists $rpt]} { puts "REFUSE: report_timing wrote nothing ($err)"; exit 1 }
set fh [open $rpt r]
set txt [read $fh]
close $fh
set hits 0
set cur ""
foreach line [split $txt "\n"] {
    set t [string trim $line]
    if {[string match "Slack*" $t] || [string match "Data Path Delay*" $t] || [string match "Logic Levels*" $t]
        || [string match "Source:*" $t] || [string match "Destination:*" $t]} {
        puts "  $t"
        if {[string match "Slack*" $t]} { incr hits }
    }
}
puts "PATHS printed: $hits  (floor: 0 means report_timing gave nothing for clock $clk)"
if {$hits == 0} { puts "REFUSE: zero paths -- this clock was not measured"; exit 1 }
exit 0

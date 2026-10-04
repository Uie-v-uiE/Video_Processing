# 用途：read-only A/B probe for ONE cone between two endpoint sets.
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/probe_cone_slack.tcl -- read-only A/B probe for ONE cone between two endpoint sets.
#   Why a second probe: build/tcl/probe_reasm_fanout.tcl is hard-wired to the u_reasm family. r108 cuts
#   the icmp_tx IP-checksum cone, so the same discipline (ask the *same* start/endpoint pair on both
#   trees, never the global WNS delta) needs a parameterised version instead of a copy per round.
#   Feed it with env vars:
#     VP_FROM = cell pattern of the startpoints   (e.g. u_eth/u_icmp/u_icmp_tx/ip_head_reg*)
#     VP_TO   = cell pattern of the endpoints     (e.g. u_eth/u_icmp/u_icmp_tx/check_buffer_reg*)
#     VP_LABEL= short ASCII id used in the print
#   Two quoting traps the SETS floor below already paid for (it refused twice):
#     - do NOT wrap the patterns in braces when passing them through the environment -- braces are Tcl
#       syntax, so as env values they arrive as literal characters and match nothing;
#     - for a 2-D array reg (ip_head_reg[4][19]) the wildcard goes at the END (..._reg*), not [...].
#   Runtime labels are ASCII on purpose (Vivado Tcl reads this file under the system codepage; CJK in a
#   puts label can break command substitution -- see build/r107_reasm_probe.txt section 4).
set root [file normalize [file join [file dirname [info script]] .. ..]]
foreach v {VP_FROM VP_TO VP_LABEL} {
    if {![info exists ::env($v)]} { puts "REFUSE: env $v is not set"; exit 1 }
}
set from_pat $::env(VP_FROM)
set to_pat   $::env(VP_TO)
set label    $::env(VP_LABEL)
set dcp      [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
puts "LABEL: $label"
puts "DCP: $dcp"
open_checkpoint $dcp

set froms [get_cells -quiet $from_pat]
set tos   [get_cells -quiet $to_pat]
puts "SETS from=[llength $froms] to=[llength $tos]  (a 0 here means the pattern matched nothing -- the probe would then prove nothing)"
if {[llength $froms] == 0 || [llength $tos] == 0} { puts "REFUSE: empty endpoint collection, refusing to print an empty verdict"; exit 1 }

set rpt [file join $root "build/probe_cone_${label}.rpt"]
report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 5 -file $rpt
set fh [open $rpt r]
set txt [read $fh]
close $fh
set hits 0
foreach line [split $txt "\n"] {
    set t [string trim $line]
    if {[string match "Slack*" $t] || [string match "Data Path Delay*" $t] || [string match "Logic Levels*" $t]
        || [string match "Source:*" $t] || [string match "Destination:*" $t]} {
        puts "  $t"
        if {[string match "Slack*" $t]} { incr hits }
    }
}
puts "PATHS printed: $hits  (floor: 0 means report_timing gave nothing for this cone)"
if {$hits == 0} { puts "REFUSE: zero paths -- this cone was not measured"; exit 1 }
exit 0

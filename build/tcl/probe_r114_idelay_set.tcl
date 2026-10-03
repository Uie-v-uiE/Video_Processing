# build/tcl/probe_r114_idelay_set.tcl -- 只问一件事：已实现的网表上 IDELAY_VALUE 改不改得动（决定扫档走快车道还是走重建）
#   前一支探针死在这里：`-filter {REF_NAME eq IDELAYE2}` 报
#   ERROR [Common 17-263] syntax error ... at position '9'（件 build/evidence/r114_idelay_prop_console4.txt）。
#   同一个错误形状还解释了 r114 扇出复制那支脚本为什么一直 MF-REFUSE "名册没认出网"——它用的也是 `NAME eq {...}`。
#   ⇒ 本文件只用 `==`，并且不把这个结论外推到没验过的属性名。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no opt dcp"; exit 1 }
open_checkpoint $dcp

set cells [get_cells -quiet -hier -filter {REF_NAME == IDELAYE2}]
puts "IDELAY_N=[llength $cells]"
if {[llength $cells] == 0} { puts "VERDICT=no_cells"; exit 1 }
set c [lindex $cells 0]
puts "TARGET=[get_property NAME $c]|LOC=[get_property LOC $c]|OLD=([get_property IDELAY_VALUE $c])"
set listed [lsearch -exact [list_property $c] IDELAY_VALUE]
puts "IS_LISTED_PROPERTY=[expr {$listed >= 0}]"
set vv ""
catch {set vv [list_property_value IDELAY_VALUE $c]} evv
puts "VALID_VALUES=($vv)|rc=$evv"
set err ""
catch {set_property IDELAY_VALUE 18 $c} err
puts "SET_TRY|rc=($err)|read_back=([get_property IDELAY_VALUE $c])"
if {$err eq "" && [get_property IDELAY_VALUE $c] == 18} {
    puts "VERDICT=post_synth_settable=YES"
} else {
    puts "VERDICT=post_synth_settable=NO"
}
set f "/tmp/kx/r114_idelay_hold_after.rpt"
file delete -force $f
set e2 ""
catch {report_timing -delay_type min -nworst 1 -max_paths 1 -from eth_rxc -to eth_rxc -file $f} e2
set slack NA
if {[file exists $f]} {
    set fh [open $f r]; set t [read $fh]; close $fh
    if {[regexp {Slack\s+\((MET|VIOLATED)\)\s*:\s*(-?[0-9]+\.[0-9]+)\s*ns} $t -> a b]} { set slack "$a/$b" }
    if {[regexp {(u_[^\s]*|eth[^\s]*)} [lindex [regexp -all -inline -- {\S+} [regsub -all {\s+} [lindex [split $t "\n"] 0] " "]] 0] m]} {}
    set dest NA
    if {[regexp {Destination:\s+(\S+)} $t -> d]} { set dest $d }
    puts "HOLD_ROW|slack=$slack|dest=$dest|rc=$e2"
} else {
    puts "HOLD_ROW|slack=NA|no_report|rc=$e2"
}
puts "IDELAY_SET_PROBE_DONE"

# 用途：fast-lane roll with an ENV-CONFIGURABLE pblock target
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/pb117_roll.tcl -- fast-lane roll with an ENV-CONFIGURABLE pblock target
#
# Why a v3 instead of reusing pb113_roll2.tcl: (a) that file hardcodes its target to
# u_eth/u_rx_par + u_eth/u_reasm, i.e. the eth_rxc family, while r116's global limit audit
# (report/timing/limit_audit_r116.md) points at a DIFFERENT domain -- clk_fpga_0's worst path is
# 1 logic level with 93.6 % route delay into u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0], which is a
# placement/distance artefact, not a device limit; (b) pb113_roll2.tcl may be in flight and we
# never edit a script a running instance is executing.
#
# Env: PB_MODE=none|pblock  PB_TARGET=<tcl list of instance paths>  PB_OUT=<dir>
# Same discipline as the r113 rolls: start from impl_1/system_top_opt.dcp, plain place+route,
# skip phys_opt, artefacts only under PB_OUT (nothing in the project is written).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE no such dcp: $dcp"; exit 1 }
if {[info exists ::env(PB_MODE)]} { set mode $::env(PB_MODE) } else { set mode none }
if {[info exists ::env(PB_OUT)]}  { set out  $::env(PB_OUT)   } else { set out [file join $root build/tmp_r117_roll] }
if {[info exists ::env(PB_TARGET)]} { set target $::env(PB_TARGET) } else { set target {u_pl/u_bilin/u_fb} }
file mkdir $out
puts "R117ROLL mode=$mode target=$target dcp=$dcp out=$out"
open_checkpoint $dcp

if {$mode eq "pblock"} {
    set targets [get_cells -quiet [list $target]]
    puts "PB_TARGETS=[llength $targets] (expect 1)"
    if {[llength $targets] == 0} { puts "PB-REFUSE empty target collection"; exit 4 }
    # where is that instance today? the rectangle must follow the real placement, not a guess
    set box [get_property INST_UTILIZATION_AREA.BOX [get_cells -quiet $target]]
    set site [get_property SITE [get_cells -quiet "$target/*"] ]
    puts "PB_EXISTING_BOX=$box first_site=$site"
    create_pblock PB_FB
    set pb [get_pblocks PB_FB]
    add_cells_to_pblock $pb [get_cells -quiet -hier [list $target]]
    if {$box eq ""} { puts "PB-REFUSE could not read the existing box"; exit 4 }
    set e no-error
    catch {resize_pblock $pb -add $box} e
    puts "PB_RESIZE rc=$e box=$box"
    if {![string match "no-error" $e]} { exit 4 }
    puts "PB_CELLS=[llength [get_cells -quiet -of_objects $pb]]"
}

opt_design
place_design
route_design
report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out util.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
set h [open [file join $out timing_summary.rpt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {$s eq ""} continue
    foreach c {clk_fpga_0 clkout0_1 eth_rxc sys_clk} {
        if {[lindex $s 0] eq $c} { puts "ROW $c |$s" }
    }
}
puts "ROLLDONE mode=$mode out=$out"
exit 0

# 用途：补 B1 缺的两块（选项形状按 A2 实测过的那批写）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE
# build/tcl/r115_baseline_fix.tcl —— 补 B1 缺的两块（选项形状按 A2 实测过的那批写）
#
# 上一支 `r115_baseline_probe.tcl` 的两处失败（件 build/evidence/r115_baseline_probe_console.txt）：
#   1) `report_timing_summary -extended -numeric_summary` → `[Common 17-170] Unknown option '-extended'`
#      —— A2 的 `help report_timing_summary` 实测选项集里**没有**这两个（有 -check_timing_verbose /
#      -delay_type / -setup / -hold / -nworst / -max_paths / -unique_pins / -path_type / -input_pins），
#      逐时钟那张表本来就在普通汇总里，不需要 -to（`-to` 也不是它的选项，第二次实测）。
#   2) `get_ports -direction {in*}` → `[Common 17-170] Unknown option '-direction'`
#      —— 方向要按**属性**读（get_property DIRECTION），不是开关。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
set out [file join $root "build/evidence/r115_base"]
if {![file exists $dcp]} { puts "REFUSE no dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp

proc w {tag cmd} {
    set root [file normalize [file join [file dirname [info script]] .. ..]]
    set f [file join $root "build/evidence/r115_base/$tag.txt"]
    catch {file delete -force $f}
    set e none
    set code [catch {eval $cmd -file $f} e]
    set sz -1
    if {[file exists $f]} { set sz [file size $f] }
    puts "FIXREP tag=$tag code=$code size=$sz err=$e"
}
w timing_summary         {report_timing_summary -quiet}
w timing_summary_verbose {report_timing_summary -quiet -check_timing_verbose}
w timing_summary_setup   {report_timing_summary -quiet -setup -nworst 5 -max_paths 5}
w timing_summary_hold    {report_timing_summary -quiet -hold -nworst 5 -max_paths 5}

foreach c [get_clocks -quiet *] {
    set e none
    if {[catch {get_property DIRECTION $c} d]} { set d NA }
    puts "CLKROW clk=[get_property NAME $c]|period=[get_property PERIOD $c]|src=[get_property SOURCE_PINS $c]|generated=[get_property IS_GENERATED $c]|waved=[get_property WAVEFORM $c]|type=$d"
}
set n_in 0; set n_out 0; set n_iodly_ok 0
foreach p [get_ports -quiet *] {
    set dir ""
    catch { set dir [get_property DIRECTION $p] }
    if {$dir eq "input" || $dir eq "inout"} { incr n_in }
    if {$dir eq "output"} { incr n_out }
}
puts "IO ports_total=[llength [get_ports -quiet *]] inputs=$n_in outputs=$n_out"
# 有没有"某个端口被 input/output delay 约束过"的对象侧查询命令？A2 的候选在这试一次，失败就如实念 NA
foreach q {get_input_delays get_output_delays} {
    set e none
    set code [catch {eval $q -quiet [list [lindex [get_ports -quiet *] 0]]} r]
    puts "QUERY cmd=$q code=$code result_len=[expr {$code==0 ? [llength $r] : -1}] err=$e"
    if {$code == 0} { incr n_iodly_ok }
}
puts "QUERY_USABLE=$n_iodly_ok/2（0 ⇒ I/O 覆盖只能走 check_timing/-verbose 与约束文本那两把尺子，别发明第三把）"
puts "FIX_DONE"
exit 0

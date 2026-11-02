# build/tcl/probe_ser_clock.tcl -- 只读：TMDS 串行器的 CLK 脚到底属于哪条时钟网络
# 为什么还要问一次：r119 的候选约束要写 `set_output_delay -clock <对象>`，这个对象必须是实现网表里
# 真存在的时钟；`report_clock_networks` 只列了 3 条**主**时钟（件 build/evidence/r119_clock_networks.rpt），
# 串行器挂在 MMCM 派生钟上，所以必须直接问 pin。读空一律打 NOT_MEASURED，不许当作"没有时钟"。
set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {$dcp eq "" || ![file exists $dcp]} { puts "PROBE-REFUSE VP_DCP=$dcp"; exit 3 }
open_checkpoint $dcp
foreach pin {u_pl/u_dvi/u_ser_clk/u_master/CLK u_pl/u_dvi/u_ser0/u_master/CLK u_pl/u_dvi/u_ser1/u_master/CLK u_pl/u_dvi/u_ser2/u_master/CLK u_pl/hb_reg\[22\]/C} {
    set p [get_pins -quiet $pin]
    if {[llength $p] == 0} { puts "SERCLK| $pin | NO_SUCH_PIN NOT_MEASURED"; continue }
    set rc [catch {set cl [get_clocks -quiet -of_objects $p]} e]
    if {$rc != 0} { puts "SERCLK| $pin | query_rc=$rc msg=$e NOT_MEASURED"; continue }
    if {[llength $cl] == 0} { puts "SERCLK| $pin | EMPTY NOT_MEASURED"; continue }
    foreach c $cl { puts "SERCLK| $pin | clock=[get_property NAME $c] period=[get_property PERIOD $c]" }
}
puts "PROBE4-DONE"
exit 0

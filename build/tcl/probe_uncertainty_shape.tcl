# 用途：只读探针：不确定度在**开着的检查点**上到底怎么读回来
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=非 0 分支（该文件 exit 4 那一行）
# build/tcl/probe_uncertainty_shape.tcl —— 只读探针：不确定度在**开着的检查点**上到底怎么读回来
#
# 为什么要量（2026-10-03 21:56 实测，件 build/evidence/r113_uncertainty_console.txt 那份被本轮跑覆盖前的最后读数）：
#   `build/tcl/probe_uncertainty_uniform.tcl:40` 用
#     set nset [llength [set_clock_uncertainty -hold $BAND [get_clocks *]]]
#   数"落上了几条"，念回来 `UNC_APPLIED=0` 而 `UNC_ERR=0` —— 也就是**命令成功、返回的却不是对象列表**，
#   于是自己的守卫 `if {$nset == 0} exit 4` 把一次正当的体检判成了"没有变量"。
#   这与今晚在网对象上栽的那两处同族：`-filter NAME ==` 对网恒空、`report_*` 的返回是**报告路径字符串**
#   而不是对象（件 build/evidence/probe_mf114_netname_console.txt、ISSUES #286）。
# 所以这里把三件事一次问清楚，全部是**实测**、不猜：
#   S1 `list_property [get_clocks <一个钟>]` 里到底有没有不确定度那一类属性、叫什么；
#   S2 `set_clock_uncertainty` 的返回值是什么（类型/长度）；
#   S3 打完带之后，用什么**读得回来**（属性？`report_clocks` 的某一列？`get_timing_uncertainty`？）。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE no dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set c [get_clocks -quiet clk_fpga_0]
puts "S0 clock_objs=[llength $c] name=[get_property NAME $c]"
puts "S1_PROPS_ALL: [list_property [get_clocks -quiet clk_fpga_0]]"
puts "S1_MATCH_UNCERT: [list_property [get_clocks -quiet clk_fpga_0] *UNCERT*]"
puts "S1_BASELINE: [get_property *UNCERT* [get_clocks -quiet clk_fpga_0]]"

set r ""
set e none
catch { set r [set_clock_uncertainty -hold 0.800 [get_clocks clk_fpga_0]] } e
puts "S2_RET_len=[llength $r] ERR=$e"
set n ""
catch { set n [llength [report_clocks]] } en2
puts "S3_report_clocks_ret_len=$n"
puts "S3_AFTER: [get_property *UNCERT* [get_clocks -quiet clk_fpga_0]]"
set f [file join $root "build/probe_unc_shape_report.txt"]
catch {report_clocks -quiet -file $f} erc
puts "S3_REPORT_ERR=$erc EXISTS=[file exists $f]"
if {[file exists $f]} {
    set fh [open $f r]; set t [read $fh]; close $fh
    set lines [split $t "\n"]
    set i 0
    foreach ln $lines {
        incr i
        if {[string match "*ncertaint*" $ln] || [string match "*UNC*" $ln]} { puts "S4_LINE$i|$ln" }
    }
    puts "S4_HEADS: [lrange $lines 14 24]"
}
exit 0

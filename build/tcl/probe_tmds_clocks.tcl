# build/tcl/probe_tmds_clocks.tcl — 只读探针：TMDS 输出脚到底挂在哪条时钟上
#
# 为什么需要它：HDMI 源端的钟↔数据窗（0.20 Tcharacter，见 report/io/hdmi_cts_source_window.md 表 #1）
# 要写成 set_output_delay，参考时钟必须是**实现网表里真实存在的那个时钟对象**；按记忆里的名字写
# 就会造出一条静默落空的约束（这个仓库已经有过三次"过滤器读空"的错结论）。
#
# 用法（从仓库根）：
#   VP_DCP=build/vivado_system/system_top.runs/impl_1/system_top_opt.dcp \
#   "$VP_VIVADO_BIN/vivado" -mode batch -nojournal -source build/tcl/probe_tmds_clocks.tcl
# 本脚本**不改任何东西**：不 place、不 route、不写属性，只读表。
# 运行期字符串一律 ASCII（GBK 控制台会把 CJK 的 puts 变成二进制，见记忆）。

set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {$dcp eq "" || ![file exists $dcp]} {
    puts "PROBE-REFUSE no DCP given \(VP_DCP=$dcp\) — 先确认 opt.dcp 的路径，不要靠猜"
    exit 3
}
open_checkpoint $dcp

puts "CLOCKS_COUNT [llength [get_clocks -quiet]]"
# 属性名一律用 catch 兜住再打印：这台机器上 `PERF.ACTUAL_PERIOD` **不存在**
# （第一次跑就是被它打断的，件 build/evidence/r119_tmds_clock_probe.txt 的 ERROR [Common 17-54]），
# 而一个报错把整支探针杀掉，正好会制造"读不到 = 探针没跑"的那种误判。
foreach c [get_clocks -quiet] {
    set nm [get_property NAME $c]
    set rr [catch {set pd [get_property PERIOD $c]} pe]
    if {$rr != 0} { set pd "PROP_ERR:$pe" }
    set sr [catch {set src [get_property SRC_TYPE $c]} se]
    if {$sr != 0} { set src "PROP_ERR:$se" }
    puts "CLK| $nm | period=$pd | src=$src"
}

puts "PORTS_WITH_CLOCK"
foreach p [get_ports -quiet {tmds_clk_p tmds_clk_n tmds_data_p[*] tmds_data_n[*] led[*]}] {
    set pc [get_property CLOCK $p]
    set nm [get_property NAME $p]
    puts "PORT| $nm | clock=$pc"
}
puts "PROBE-DONE"
exit 0

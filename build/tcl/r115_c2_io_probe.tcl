# build/tcl/r115_c2_io_probe.tcl —— 把 C2 之后那条 I/O hold 路**逐段**问出来（S1 为什么还差 −2.126）
# 作用: 在 C2 副本树的已布线 DCP 上，对 eth_rxd[*]/eth_rx_ctl → mmcm_clk0 的 hold 路按 ±0.500 窗与 Table 60 真窗各报一次，并抠出 Slack 与逐段延迟行
# 前置条件: 仓库根同级的副本树 c2_scratch_1003 里 vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp 存在（缺 ⇒ puts REFUSE 并 exit 1）；端口或 mmcm_clk0 取到空集 ⇒ puts REFUSE 并 exit 4
# 产出物: build/evidence/r115_c2_scratch/io_hold_built_window.txt、io_hold_true_window.txt、io_setup_true_window.txt；stdout 的 IO_PORTS= / IO-STAGE / IO-<tag>|Slack… / TW-SET-* rc= / IODONE 行
# 关键参数: 无命令行参数、无 env 读取；真窗数值写死（set_input_delay -min 1.000 / -max 2.600，正负沿各一条），查询对象名册也写死在本文件
#
# 23:56 的判定（件 build/evidence/r115_c2_scratch/ 的 C2V 行）：
#   S2 机制 GREEN（副本树 mmcm=1 / iddr=5 / bufg=1，主树 mmcm=0 且正对照当场红）
#   S1 RED：设计级 WHS = −2.126，仍有 **5** 个 I/O hold 失败端点（r114 同窗是 −2.885）
#   ⇒ 相移只买到 +0.759 ns，不是我按 DCD 5.008 算的 5.000 ns。**为什么**这一问必须量，不许圆场。
# 另外 S5 发现 fabric 已经搬到派生钟 `mmcm_clk0` 上（`-from eth_rxc -to eth_rxc` 现在**没有路径**，
#   这就是 S3 的"配对失效"），所以这一支查的是**正确的对象**：
#   `-from <输入端口> -to <mmcm_clk0>`，并且两把尺子各报一次：
#     ① 构建时用的 ±0.500 窗（既成事实的那次布线）
#     ② 手册 Table 60 的真窗（min 1.000 / max 2.600）
# 运行时 puts 标签一律 ASCII。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file normalize [file join $root .. c2_scratch_1003 vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out  [file join $root build evidence r115_c2_scratch]
if {![file exists $dcp]} { puts "REFUSE no dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp

set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
set dst   [get_clocks -quiet mmcm_clk0]
puts "IO_PORTS=[llength $ports] dst_clocks=[llength $dst]"
if {[llength $ports] == 0 || [llength $dst] == 0} { puts "REFUSE: 查询对象是空集（正对照都没了）"; exit 4 }

proc dump {tag f} {
    set h [open $f r]; set t [read $h]; close $h
    set sl [regexp -all -inline {Slack \([^)]*\)\s+\S+} $t]
    puts "IO-$tag slacklines=[llength $sl]"
    foreach s $sl { puts "IO-$tag | $s" }
    foreach ln [split $t "\n"] {
        if {[regexp {^\s+(Clock Path Skew|Destination Clock Delay|Source Clock Delay|Clock Uncertainty|Data Path Delay|Requirement|Logic Levels):} $ln m]} {
            puts "IO-$tag| [string trim $ln]"
        }
    }
}

puts "IO-STAGE built_in_window (±0.500，构建时生效的那把)"
set f1 [file join $out io_hold_built_window.txt]
file delete -force $f1
report_timing -delay_type min -from $ports -to $dst -nworst 1 -max_paths 6 -file $f1
dump built $f1

puts "IO-STAGE true_window (Table 60: min 1.000 / max 2.600)"
set e no-error
catch {set_input_delay -clock eth_rxc -min 1.000 $ports} e
puts "TW-SET-MIN rc=$e"
set e no-error
catch {set_input_delay -clock eth_rxc -max 2.600 $ports} e
puts "TW-SET-MAX rc=$e"
set e no-error
catch {set_input_delay -clock eth_rxc -clock_fall -min 1.000 $ports} e
puts "TW-SET-MIN-FALL rc=$e"
set e no-error
catch {set_input_delay -clock eth_rxc -clock_fall -max 2.600 $ports} e
puts "TW-SET-MAX-FALL rc=$e"
set f2 [file join $out io_hold_true_window.txt]
file delete -force $f2
report_timing -delay_type min -from $ports -to $dst -nworst 1 -max_paths 6 -file $f2
dump true $f2
set f3 [file join $out io_setup_true_window.txt]
file delete -force $f3
report_timing -delay_type max -from $ports -to $dst -nworst 1 -max_paths 6 -file $f3
dump setup $f3
puts "IODONE"
exit 0

# 用途：r115 夜：把"四个域的 hold 余量能不能互相比"这件事量出来（#265/#295）
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/r115_uncertainty_hold.tcl —— r115 夜：把"四个域的 hold 余量能不能互相比"这件事量出来（#265/#295）
#
# 为什么要这一支（提示词 §4 E2 的 G1 口径依赖它）：
#   名册里现在**只有 eth_rxc 带 hold 不确定度**（src/constraints/rk_zynq7020.xdc:50 那行 `set_clock_uncertainty -hold 0.800`），
#   其余三个域的 WHS 是"没有垫"的数 ⇒ 四行 hold 是**两把尺子**，G1 的 hold 那一半判定是软的（ISSUES #265/#295）。
#
# 为什么以前问不出来（#295 量到的三条工具形状，这里全部绕开）：
#   * 时钟对象**没有** `*UNCERT*` 属性（CLASS/FILE_NAME/…/WAVEFORM/WEIGHT 那串里没有）⇒ `get_property HOLD_UNCERTAINTY` 恒空；
#   * `set_clock_uncertainty` **不返回**对象列表 ⇒ "我给了几个钟"只能自己数；
#   * ⇒ **唯一的读回路是报告正文里那行 `Clock Uncertainty: 0.800ns`**（#295 的结论原样落实在这一支里）。
#
# 做法（纯只读，不改工程、不写 XDC、不重布）：
#   打开**正式构建的已布线 DCP** → 逐域读域内 min 路径的 `Clock Uncertainty:` 行（BEFORE）
#   → 在会话里给另外三个域加同一条 0.800 的 hold 带（一条命令一个钟，绝不把多个名字并进一条
#     ——`get_clocks` 取不到任何一个就会让**整条命令空转**，rk_zynq7020.xdc:43-46 的旧账）
#   → 再逐域读一次（AFTER）+ 出一份 hold 汇总（给名册用）。
# ⚠ 这不是采纳：约束只活在这一次 Tcl 会话里，DCP 不回写，工程里一个字没动。
#   它的产出只有一个问题："如果四个域都垫 0.800，各域的 WHS 会变成多少？"
# 运行时 puts 标签一律 ASCII（Vivado Tcl 按系统代码页读 UTF-8，中文标签会让输出对 grep 变二进制）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
set out  [file join $root "build/evidence/r115_unc"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
file mkdir $out
puts "DCP $dcp"
open_checkpoint $dcp

set clks {eth_rxc sys_clk clk_fpga_0 clkout0_1}

proc unc_of {c tag} {
    # 返回该域域内 min 路径报告里的 Clock Uncertainty 读数（NA = 读不到，绝不返回 0）
    set f [file join [pwd] "r115_unc_[set tag]_[set c].rpt"]
    file delete -force $f
    set ferr no-error
    if {[catch {report_timing -delay_type min -from [get_clocks $c] -to [get_clocks $c] \
                    -nworst 1 -max_paths 1 -file $f} ferr]} {
        puts "UNC-ERR clock=$c tag=$tag err=$ferr"
        return NA
    }
    if {![file exists $f]} { puts "UNC-ERR clock=$c tag=$tag nofile"; return NA }
    set h [open $f r]; set t [read $h]; close $h
    file delete -force $f
    if {[regexp {Clock Uncertainty:\s+([0-9.]+)ns} $t -> v]} { return $v }
    # 该域没有域内 min 路径（report_timing 会打印 "All timing constraints for this clock were met"? 不，那是 summary）
    # ⇒ 读不到就报 NA，并念出正文第一行，方便判断是"没有路径"还是"报告换了形状"
    set first ""
    foreach l [split $t "\n"] { if {[string match "*Slack*" $l]} { set first $l; break } }
    puts "UNC-NOMATCH clock=$c tag=$tag firstslackline=\[$first\]"
    return NA
}

foreach c $clks { puts "UNC_BEFORE clock=$c value=[unc_of $c before]" }

set applied 0
foreach c {sys_clk clk_fpga_0 clkout0_1} {
    set e no-error
    if {[catch {set_clock_uncertainty -hold 0.800 [get_clocks $c]} e]} {
        puts "UNC-SET clock=$c FAILED err=$e"
    } else {
        incr applied
        puts "UNC-SET clock=$c ok"
    }
}
puts "UNC_APPLIED n=$applied (of 3 targets; eth_rxc 已经有 0.800 不动它)"
if {$applied != 3} { puts "REFUSE: 三个目标没全设上，AFTER 的差分没有意义"; exit 4 }

foreach c $clks { puts "UNC_AFTER clock=$c value=[unc_of $c after]" }

report_timing_summary -delay_type min -file [file join $out summary_hold_after.txt]
catch {check_timing -verbose -file [file join $out check_timing_verbose.txt]} cterr
puts "CHECKTIMING_ERR=$cterr"
puts "UNCDONE"
exit 0

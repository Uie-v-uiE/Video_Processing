# build/tcl/r124_tiers_probe.tcl —— 只读"多档名册"探针：把每个时钟前 12 档念出来（r118 那份约束集）
#
# 依赖：Vivado 2025.2.1 批处理模式（本机 `<Vivado>/bin/vivado.bat`，不在 PATH）；工程
#        `vivado_system/zynq_video_sys.xpr` 与它的 `synth_1`（必须已 100 % 完成，本探针不重综合）；
#        磁盘余量够放一次实现产物（约 1.5 GB）。
# 用法："<Vivado>/bin/vivado.bat" -mode batch -nojournal -log <目录>/r124_tiers_console.txt \
#          -source build/tcl/r124_tiers_probe.tcl        （从仓库根起，约 10–20 分钟）
# 参数：
#   | 参数 | 作用 |
#   | --- | --- |
#   | 环境变量 `VP_OUTDIR` | 探针件的落点；未设则用仓库同级 `delivery_review_20261005/local_docs/`（探针件不进交付树） |
#   | 环境变量 `VP_TIERS_FORCE` | 设为 `1` 时即使约束集与 r118 不一致也继续跑（默认不一致就 REFUSE，防止把候选版念成 r118） |
#   | 环境变量 `VP_TIERS_REPORT_ONLY` | 设为 `1` 时不 reset/launch 实现，直接读已 Complete 的那一跑（route_design 已完成时用，省 7 分钟） |
#
# 为什么要它：r118 归档下来的档位只有 4 条（`build/evidence/r118_after.txt`）与每域 1 条
#   （`build/timing_summary.rpt` 的 Timing Details 是默认档数），于是"发侧那一族搬走之后 eth_rxc
#   接棒的是谁、后面还有几档"这个问题**没有件**。今天第一次试探针失败，原因是单独
#   `open_checkpoint` 综合网表会把 BD 里的 IP 当黑盒（DRC INBB-3 六条）——所以必须从工程走。
#
# 准入门（决定这份读数能不能被引用）：
#   ① 实现期约束集必须正好是 r118 那两份（`rk_zynq7020.xdc` + `clock_groups_impl.xdc`）；
#      任何候选窗件/异步 max_delay 件挂在 fileset 里都先摘掉（**不保存工程**，不改仓库里的 .xdc 内容）。
#   ② 重跑完成后，四个域的 intra 读数要与 r118 一字不差：
#      eth_rxc 0.739 / clk_fpga_0 1.850 / sys_clk 14.876 / clkout0_1 3.630（端点 4835/15721/323/30179）。
#      复现 ⇒ 这份档位表就是 r118 的；不复现 ⇒ 它只是"族序"参考，ns 一律不许引用。
#
# 运行时标签保持 ASCII：Vivado Tcl 按系统码页读 .tcl，CJK 的 puts 标签会破坏命令替换、
# 并把控制台变成 grep 眼里的二进制（见 build/r107_reasm_probe.txt 第 4 节）。CJK 只写在注释里。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set xpr  [file join $root "vivado_system/zynq_video_sys.xpr"]
if {![file exists $xpr]} { puts "REFUSE: no project at $xpr"; exit 1 }

set outdir [file normalize [file join $root ".." "delivery_review_20261005" "local_docs"]]
if {[info exists ::env(VP_OUTDIR)]} { set outdir [file normalize $::env(VP_OUTDIR)] }
if {![file exists $outdir]} { file mkdir $outdir }
puts "PROBE root=$root"
puts "PROBE outdir=$outdir"

open_project $xpr

# --- 准入门 ①：实现期约束集必须等于 r118 那两份 -------------------------------------------
set want [list "src/constraints/rk_zynq7020.xdc" "src/constraints/clock_groups_impl.xdc"]
set banned [list "r119_hdmi_source_window.xdc" "r119b_hdmi_tp1_pinclk.xdc" "r116_rgmii_input_window.xdc" \
                 "r114_io_async.xdc" "r115_io_window_candidate.xdc" "r114_io_varianta_rise_only.xdc" \
                 "r114_io_variantb_phy_delay.xdc"]
set have [list]
foreach f [get_files -of [get_filesets constrs_1]] { lappend have [file tail $f] }
puts "FILESET before: $have"
set removed [list]
foreach f [get_files -of [get_filesets constrs_1]] {
    set tail [file tail $f]
    set hit 0
    foreach b $banned { if {$tail eq $b} { set hit 1 } }
    if {$hit} { remove_files $f; lappend removed $tail }
}
puts "FILESET removed_candidates: $removed"
set after [list]
foreach f [get_files -of [get_filesets constrs_1]] { lappend after [file tail $f] }
puts "FILESET after: $after"
set ok1 1
foreach w $want {
    set base [file tail $w]; set seen 0
    foreach a $after { if {$a eq $base} { set seen 1 } }
    if {!$seen} { puts "REFUSE: r118 constraint missing from fileset: $base"; set ok1 0 }
}
if {[llength $after] != [llength $want]} { puts "REFUSE: impl constraint count [llength $after] != 2"; set ok1 0 }
if {!$ok1 && ![info exists ::env(VP_TIERS_FORCE)]} { close_project; exit 1 }
if {!$ok1} { puts "FORCE: VP_TIERS_FORCE set, continuing with a mismatched constraint set" }

# --- 重跑实现（只到 route_design，不写 bitstream；不动 synth_1） ------------------------------
# VP_TIERS_REPORT_ONLY=1 时跳过实现：route_design 已经 Complete 的那一跑直接读，不再花 7 分钟重布重绕。
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "REFUSE: synth_1 not 100%"; close_project; exit 1 }
if {![info exists ::env(VP_TIERS_REPORT_ONLY)]} {
    reset_run impl_1
    launch_runs impl_1 -to_step route_design
    wait_on_run impl_1
}
set st [get_property STATUS [get_runs impl_1]]
puts "RUN_STATUS impl_1: $st"
if {![string match "route_design Complete*" $st]} { puts "REFUSE: impl_1 did not reach route_design completion"; close_project; exit 1 }

open_run impl_1
report_timing_summary -file [file join $outdir "r124_tiers_summary.rpt"] -max_paths 12 -nworst 12
proc tiers_digest {path tag} {
    if {![file exists $path]} { puts "TIERS $tag MISSING"; return }
    set fh [open $path r]
    set txt [read $fh]
    close $fh
    set n 0
    set sl {}
    foreach line [split $txt "\n"] {
        if {[regexp {^  Slack \((MET|VIOLATED)\) :\s+(-?[0-9.]+)ns} $line -> v sv]} {
            incr n
            lappend sl $sv
        } elseif {[regexp {^Slack \((MET|VIOLATED)\) :\s+(-?[0-9.]+)ns} $line -> v sv]} {
            incr n
            lappend sl $sv
        }
    }
    if {$n == 0} { puts "TIERS $tag distinct=0 (no path block parsed)"; return }
    puts "TIERS $tag distinct=$n first=[lindex $sl 0] last=[lindex $sl end]"
}

foreach clk {eth_rxc clk_fpga_0 sys_clk clkout0_1} {
    set cobj [get_clocks -quiet $clk]
    if {[llength $cobj] == 0} { puts "SKIP: no clock object named $clk"; continue }
    puts "CLOCK_OBJ $clk -> [get_property NAME $cobj]"
    # -nworst 1 是这里的规矩（同 build/tcl/c2_scratch_probe.tcl:60）：nworst>1 会把同一个端点
    # 的上升/下降沿组合念成好几条，看着像 12 档其实只有 1 档。
    report_timing -delay_type max -nworst 1 -max_paths 12 -from $cobj -to $cobj \
        -file [file join $outdir "r124_tiers_${clk}_setup.rpt"]
    report_timing -delay_type min -nworst 1 -max_paths 12 -from $cobj -to $cobj \
        -file [file join $outdir "r124_tiers_${clk}_hold.rpt"]
    tiers_digest [file join $outdir "r124_tiers_${clk}_setup.rpt"] "$clk/setup"
    tiers_digest [file join $outdir "r124_tiers_${clk}_hold.rpt"] "$clk/hold"
}
# 准入门 ② 的机读部分：把 intra 表原样抄进日志，回来用 bash 比对 r118 那一版
puts "GATE2 intra rows (compare against build/timing_summary.rpt):"
set fh [open [file join $outdir "r124_tiers_intra.txt"] w]
set sh [open [file join $outdir "r124_tiers_summary.rpt"] r]
set sm [read $sh]
close $sh
foreach line [split $sm "\n"] {
    if {[regexp {^(clk_fpga_0|eth_rxc|sys_clk|clkout0_1|clkout1_1|clkout2|clkfbout|clkfbout_1)\s+-?[0-9.]} $line]} {
        puts $fh $line
    }
}
close $fh
puts "PROBE DONE"
close_project
exit 0

# build/tcl/probe_rgmii_capture_clock.tcl —— C2 那一刀在**网表层**的机制凭据（G7 的可替身）
#
# 为什么要有这一支（不是拿报告当装饰）：
#   本机 xsim **没有 UNISIM 行为库**（件 `sim/prim/MMCME2_BASE.v` 文件头记着 2026-09-25 的实测：
#   `xelab` 报 `Module <MMCME2_BASE> not found`），而 `sim/prim/` 里**没有** IDDR / IDELAYE2 / IDELAYCTRL 的占位件
#   （23:36 实测 `ls sim/prim/` 只有 MMCME2_BASE.v 与 unisims_sim.v）。
#   并且那只 MMCM 占位件自己明写"**不能验相位**（PHASE 一律 0）"。
#   ⇒ 结论：这一刀改的就是**采样相位**，现有仿真台架**看不见它**。
#     硬编一个"能跑但看不到改动"的台架来交 G7，就是造一条恒绿的尺子（附录 1：空集/零样本不许算通过）。
#   所以这一刀的 G7 替身是**网表读数**：MMCM 在不在、相位参数是不是那个值、BUFG 还是不是同一只。
#
# 正对照（必须能红，规矩 46）：拿**主树**当前已布线的 DCP 跑一次，期望 RED（那里没有 MMCM）；
#   拿**副本树** C2 那一滚的 DCP 跑一次，期望 GREEN。两端都要打印计数，不许打印"看起来对"。
# 用法（两个 DCP 各一次）：
#   vivado -mode batch -nojournal -source build/tcl/probe_rgmii_capture_clock.tcl   # 默认主树，期望 RED
#   VP_C2_DCP=<dcp路径> VP_C2_WANT=green vivado -mode batch -nojournal -source 同上
set root [file normalize [file join [file dirname [info script]] .. ..]]
if {[info exists ::env(VP_C2_DCP)]} { set dcp $::env(VP_C2_DCP) } else {
    set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
}
if {[info exists ::env(VP_C2_WANT)]} { set want $::env(VP_C2_WANT) } else { set want red }
if {![file exists $dcp]} { puts "PBC-REFUSE no such dcp: $dcp"; exit 2 }
open_checkpoint $dcp

set hier "u_eth/u_rgmii/u_rgmii_rx"
# 查找形状用 r114 量过的写法（`-hier` + NAME 通配 + REF_NAME 分类），**不用** `-of`：
# `-hier` 与 `-of` 的组合在本机没有验过，拿没验过的语法做凭据探针本身就是风险（#301 那三处同族错）。
set all_in_hier [get_cells -quiet -hier -filter "NAME =~ *${hier}*"]
set n_all [llength $all_in_hier]
set n_mmcm 0; set n_bufg 0; set n_iddr 0; set n_idel 0
set mmcm_cells {}
foreach c $all_in_hier {
    switch -- [get_property REF_NAME $c] {
        MMCME2_BASE -
        MMCME2_ADV -
        PLLE2_BASE -
        PLLE2_ADV   { incr n_mmcm; lappend mmcm_cells $c }
        BUFG        { incr n_bufg }
        IDDR        { incr n_iddr }
        IDELAYE2    { incr n_idel }
        default     { }
    }
}
puts "PBC_COUNT hier=$hier cells_in_hier=$n_all mmcm=$n_mmcm bufg=$n_bufg iddr=$n_iddr idelaye2=$n_idel"

# 相位参数：两种写法都试（CONFIG.* 与裸名），读不到就念 NA 并说明它**不参与判定**
set phase NA
foreach m $mmcm_cells {
    foreach p {CONFIG.CLKOUT0_PHASE CLKOUT0_PHASE} {
        set e no-error
        if {![catch {set v [get_property $p $m]} e] && $v ne "" && $v ne "0"} { set phase $v; break }
    }
    if {$phase ne "NA"} { break }
}
puts "PBC_PHASE CLKOUT0_PHASE=$phase （INFO：读不到不判红，机制凭据是上面那一行计数）"

# 判定：期望 green 时必须有 MMCM、IDDR 还是那 5 颗、BUFG 仍在（同树这个既得成果不能丢）
set verdict RED
if {$n_mmcm >= 1 && $n_iddr == 5 && $n_bufg >= 1} { set verdict GREEN }
puts "PBC-VERDICT want=$want got=$verdict"
if {$want eq "green" && $verdict ne "GREEN"} { puts "PBCFAIL"; exit 3 }
if {$want eq "red"   && $verdict ne "RED"}    { puts "PBCFAIL 正对照没红：这条尺子看不见改动"; exit 3 }
puts "PBCDONE"
exit 0

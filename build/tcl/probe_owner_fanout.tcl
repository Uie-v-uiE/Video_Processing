# build/tcl/probe_owner_fanout.tcl -- read-only: who does u_arb/owner_eth_reg drive, and how wide?
# Why: r132's worst clk_fpga_0 setup path starts at u_pl/u_arb/owner_eth_reg/C and is 1 logic level
#      with 92.7 % routing, so the candidate cut is "replicate this flag". The replication hook needs
#      BOTH the net name and one load pin, and it aborts unless two independent lookups agree --
#      so read them from the netlist instead of guessing.
# Usage: VP_VIVADO_BIN=<bin>/vivado -mode batch -nojournal -source build/tcl/probe_owner_fanout.tcl
# 作用: 在已布线成品上读 `u_pl/u_arb/owner_eth_reg` 到底驱动谁、那只网络几个负载（臂 C 起飞前的前提核查）。
# 输入: 无命令行参数；不读 env，DCP 路径写死在下面。
# 输出: stdout 的 OWNERDRV| / OWNERNET|name=…|loads=… / LOAD| / OWNERPEERS| 行；
#       调用方 tee 到 `build/evidence/r132_owner_fanout.txt`（每只网络最多列 6 个负载，计数看 loads=）。
# 产出物: 本件不落文件、不改设计（`close_design` 收尾），所以重复跑不产生差异。
# 前置条件: 仓库根下 `vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp` 在（缺 ⇒ REFUSE 并 exit 1）。
# 关键参数: 驱动脚用 `get_pins -quiet -hier -filter {NAME =~ *u_arb/owner_eth_reg*/Q}`——
#           `-hier` 必须有，不带它在这棵树上量到 0 个引脚（那是假阴性，见 ISSUES #493 同族）；
#           负载用 `get_pins -of $net -filter {DIRECTION == IN}` 数；
#           顺带 probe `owner_sd_reg`/`owner_test_reg`/`owner_reg` 三只同域旗标，防工具改名扑空。
#           高扇出**名册**不是这支探针打的，是 `build/tcl/probe_timing_roster.tcl` 的
#           `report_high_fanout_nets` 那一段（件 `build/evidence/r132_after_roster_probefmt.txt` 的 FANOUT| 行）。
# 退出码: 0=跑完；1=没有 DCP。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set drv [get_pins -quiet -hier -filter {NAME =~ *u_arb/owner_eth_reg*/Q}]
puts "OWNERDRV pins=[llength $drv]"
foreach p $drv { puts "OWNERDRV|pin=$p" }
set nets [get_nets -quiet -of $drv]
foreach n $nets {
  set lo [get_pins -quiet -of $n -filter {DIRECTION == IN}]
  puts "OWNERNET|name=[get_property NAME $n]|loads=[llength $lo]"
  set i 0
  foreach p $lo {
    incr i
    if {$i > 6} break
    puts "  LOAD|$p"
  }
}
# also the other two owner flags in the same arbiter, in case the tool renamed them
foreach q {owner_sd_reg owner_test_reg owner_reg} {
  set d2 [get_pins -quiet -filter {NAME =~ *u_arb/*$q*/Q}]
  puts "OWNERPEERS|probe=$q|pins=[llength $d2]"
}
close_design
exit 0

# build/tcl/pb113_roll.tcl —— r113 物理单变量实验的一"滚"（#253/#252 的 ②）
#
#   PB_MODE=none   PB_OUT=/tmp/kx/pb113/A  vivado -mode batch -nojournal -source build/tcl/pb113_roll.tcl
#   PB_MODE=pblock PB_OUT=/tmp/kx/pb113/B  ...
#
# 为什么要它：这一族（`p_eof → u_reasm/rows_hit_reg[*]/CE`）三次构建读出 2.006 / >1.174 / 0.445 ns，
#   逻辑级数一直是 4，route 一直占 81~84 %，而 r110→r112 之间它的 RTL 一个字节没动（#253）⇒
#   这不是算术问题，是**距离**问题：起点 SLICE_X57Y34（u_rx_par，343 cells，落在 X55~X67），
#   终点整片 rows_hit 在 SLICE_X28Y34~X31Y35（u_reasm，1377 cells）。凭据 `build/r112_reasm_probe.txt`。
# 纪律（#223）：**只动一个变量** = 有没有那块 Pblock。两个 roll 都从同一份
#   `vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp` 起跑，都用裸 `place_design`/`route_design`
#   （不带 directive，两边一致），都**跳过 phys_opt**（#94 已量过：零违反设计上 post-route phys_opt 结构性空转，
#   两 roll 一起省掉不改变对照）。
# 不写盘上任何被跟踪件：产物全部落 $PB_OUT（默认 /tmp/kx/pb113/）。构建产物（runs 目录里的 dcp/bit）一个字节的碰不到。
# ⚠ 计数地板：Pblock 里 cell 数或 site 数为 0 ⇒ PB-REFUSE 并 exit 4 —— 不然"空 Pblock"会伪装成"加了 Pblock 也没差别"。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换，已栽过）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
# ⚠ 第一版在这里写的是 `set mode [expr {info exists ::env(PB_MODE) ? ... : "none"}]`，
#   Vivado 的 Tcl 直接报 `invalid bareword "info" in expression` 就退出了（凭据：
#   build/evidence/r113_pblock_ab.txt 里那条 ABORT——地板抓到了断链，没有伪造对照）。改成 if/else。
if {[info exists ::env(PB_MODE)]} { set mode $::env(PB_MODE) } else { set mode none }
if {[info exists ::env(PB_OUT)]}  { set out  $::env(PB_OUT)  } else { set out [file join $root "build/tmp_r113_roll"] }
file mkdir $out
puts "ROLL mode=$mode dcp=$dcp out=$out"
open_checkpoint $dcp

if {$mode eq "pblock"} {
    create_pblock PB_ETH
    set pb [get_pblocks PB_ETH]
    set targets [get_cells -quiet [list u_eth/u_rx_par u_eth/u_reasm]]
    puts "PB_TARGETS=[llength $targets] (expect 2: rx_par + reasm; 0 means a wrong name)"
    if {[llength $targets] == 0} { puts "PB-REFUSE: empty target collection"; exit 4 }
    add_cells_to_pblock $pb $targets
    # 矩形挑在两个模块之间偏 rx_par 一侧：X40~X66（rows_hit 现在在 X28~X31，硬把它们拽到收包这一侧）。
    # 列 27 × 行 33 ≈ 891 个 slice ≈ 7100 logic cells 容量，要装的是 343+1377=1720 cells。
    if {[catch {resize_pblock $pb -add {CLBLM_L_X40Y20:CLBLM_R_X66Y52}} e]} {
        puts "PB-REFUSE: resize failed: $e"; exit 4
    }
    puts "PB_CELLS=[llength [get_cells -quiet -of_objects $pb]]"
    puts "PB_RANGE=[get_property RANGE $pb]"
    # PB_SITES 只**报数不当门**：`get_sites -of_objects` 对 pblock 的支持我还没实测过，
    # 拿它当硬地板会把一次合法的实验误判成"空 Pblock"（假拒绝）。真正的地板是 PB_CELLS 和 RANGE。
    puts "PB_SITES=[llength [get_sites -quiet -of_objects $pb]] (advisory)"
    if {[llength [get_cells -quiet -of_objects $pb]] == 0} { puts "PB-REFUSE: pblock holds 0 cells"; exit 4 }
    if {[get_property RANGE $pb] eq ""} { puts "PB-REFUSE: pblock has no RANGE (resize didn't take)"; exit 4 }
}

set t0 [clock seconds]
place_design
puts "PLACE_WALL=[expr ([clock seconds]-$t0)/60]m"
set t1 [clock seconds]
route_design
puts "ROUTE_WALL=[expr ([clock seconds]-$t1)/60]m"

report_timing_summary -file [file join $out timing_summary.rpt]
report_timing -delay_type max -nworst 1 -max_paths 6 -file [file join $out setup_paths.rpt]
report_utilization -file [file join $out util.rpt]
report_route_status -file [file join $out route_status.rpt]

# 族级读数（这一刀的判据本身，不是全局 WNS）
set tos [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}]
set froms [get_cells -quiet u_eth/u_rx_par/p_eof_reg]
puts "FAM_SETS from=[llength $froms] to=[llength $tos]"
if {[llength $froms] > 0 && [llength $tos] > 0} {
    report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 2 \
        -file [file join $out family.rpt]
} else {
    puts "FAM-SKIP: empty collection (family.rpt not written)"
}

# 落点跨度（同一个变量下要看得见"距离有没有真的缩短"）
puts "SITE p_eof_reg = [get_property SITE [get_cells -quiet u_eth/u_rx_par/p_eof_reg]]"
set sites {}
foreach c [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}] { lappend sites [get_property SITE $c] }
puts "SITES rows_hit = $sites"
puts "ROLLDONE mode=$mode"
exit 0

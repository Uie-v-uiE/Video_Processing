# 用途：与 pb113_roll.tcl 同一件事，只多一个"site 矩形写法自取"的小循环
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/pb113_roll2.tcl —— 与 pb113_roll.tcl 同一件事，只多一个"site 矩形写法自取"的小循环。
#   为什么要 v2：`get_site_types` 在这个 Vivado 里**不存在**（凭据 /tmp/kx/sitetypes.txt：
#   `invalid command name "get_site_types"`），所以 7 系的 Pblock 矩形到底该写
#   CLBLM_L_X40Y20:CLBLM_R_X66Y52 还是 SLICE_X40Y20:SLICE_X66Y52，我不靠猜——
#   逐个 `catch` 试，第一个不报错的就用，并把"用了哪个"打进日志（这条本身是判据的一部分）。
#   ⚠ 不直接改 pb113_roll.tcl：roll A 正在执行那份件（#251 的教训：别动在飞的那份）。
# 其余口径与 pb113_roll.tcl 完全一致：同一份 opt.dcp、裸 place/route、跳过 phys_opt、产物只落 $PB_OUT。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
if {[info exists ::env(PB_MODE)]} { set mode $::env(PB_MODE) } else { set mode none }
if {[info exists ::env(PB_OUT)]}  { set out  $::env(PB_OUT)  } else { set out [file join $root "build/tmp_r113_roll"] }
file mkdir $out
puts "ROLL2 mode=$mode dcp=$dcp out=$out"
open_checkpoint $dcp

if {$mode eq "pblock"} {
    create_pblock PB_ETH
    set pb [get_pblocks PB_ETH]
    set targets [get_cells -quiet [list u_eth/u_rx_par u_eth/u_reasm]]
    puts "PB_TARGETS=[llength $targets] (expect 2)"
    if {[llength $targets] == 0} { puts "PB-REFUSE: empty target collection"; exit 4 }
    add_cells_to_pblock $pb $targets
    set ok ""
    foreach cand {SLICE_X40Y20:SLICE_X66Y52
                  CLBLM_L_X40Y20:CLBLM_R_X66Y52
                  SLICEL_X40Y20:SLICEM_X66Y52
                  CLBLL_L_X40Y20:CLBLM_R_X66Y52} {
        if {![catch {resize_pblock $pb -add $cand}]} { set ok $cand; break }
        puts "PB_TRY_REJECTED $cand"
    }
    if {$ok eq ""} { puts "PB-REFUSE: 四种矩形写法全被拒"; exit 4 }
    puts "PB_RANGE_USED $ok"
    puts "PB_CELLS=[llength [get_cells -quiet -of_objects $pb]] (这是**被加进去的实例数**，不是叶子数)"
    # ⚠ 上一版在这里用 `[get_property RANGE $pb] eq ""` 当硬地板，结果**误拒**了一次合法的实验：
    #   这个属性在 2025.2.1 上是空串（凭据 /tmp/kx/pb113/B_roll_console.txt 的 `PB_RANGE=` 空行 +
    #   `PB-REFUSE: pblock has no RANGE`，而 resize 本身是成功的，工具只提示"范围已按 tile 对齐"）。
    #   教训与 #12 同族：**检查器自己的存在性测试要用真的取得到的东西喂它**，属性名猜错就等于把真状态当假状态。
    #   现在改成量"真生效"：place 之后数目标里每个有 SITE 的 cell 是否落在 Pblock 的 site 集内。
    set psites [get_sites -quiet -of_objects $pb]
    puts "PB_SITES=[llength $psites]"
    foreach s $psites { set INSITE($s) 1 }
    set XLO 38; set XHI 68; set YLO 18; set YHI 54   ;# 40~66/20~52 按 tile 对齐后的放宽窗（方法 2 才用）
}

# 变量放在环境里，一个脚本能跑任意"单变量滚"：
#   PB_MODE=none/pblock   加不加那块 Pblock（roll A / roll B）
#   PLACE_DIR / ROUTE_DIR 实现指令名，空 = 裸命令（roll C：只换指令，不动 Pblock）
#   ⚠ roll B 实测**没做成单变量**：`Place 30-439` 警告 carry chain 半在块内半在块外，
#      我的落点地板量到 `PB_CONTAIN total=1716 inside=1461` ⇒ 255 个 cell 跑到块外，
#      脚本按 REFUSE 交红（凭据 /tmp/kx/pb113/B_roll_console.txt）。这块 Pblock 的**表达式**不成立，
#      不等于"Pblock 这条路不成立"——要修就得把共享 carry chain 的 `u_rx_mac` 一起收进来（下一滚）。
if {[info exists ::env(PLACE_DIR)] && $::env(PLACE_DIR) ne ""} { set pd $::env(PLACE_DIR) } else { set pd "" }
if {[info exists ::env(ROUTE_DIR)] && $::env(ROUTE_DIR) ne ""} { set rd $::env(ROUTE_DIR) } else { set rd "" }
puts "VARS place_directive={$pd} route_directive={$rd} pblock={$mode}"

set t0 [clock seconds]
if {$pd eq ""} { place_design } else { place_design -directive $pd }
puts "PLACE_WALL=[expr ([clock seconds]-$t0)/60]m"
if {$mode eq "pblock"} {
    set tot 0; set inside 0; set bad ""
    foreach c [get_cells -hier -quiet -filter "NAME =~ u_eth/u_reasm/* || NAME =~ u_eth/u_rx_par/*"] {
        set s [get_property SITE $c]
        if {$s eq ""} continue
        incr tot
        if {[info exists INSITE($s)]} { incr inside; continue }
        if {[llength $psites] == 0 && [regexp {_X(\d+)Y(\d+)$} $s -> x y]
            && $x >= $XLO && $x <= $XHI && $y >= $YLO && $y <= $YHI} { incr inside; continue }
        if {[llength $bad] < 6} { lappend bad "$c=$s" }
    }
    puts "PB_METHOD sites_membership=[expr {[llength $psites] > 0 ? 1 : 0}]"
    puts "PB_CONTAIN total=$tot inside=$inside outside_list=[join $bad ,]"
    if {$tot == 0} { puts "PB-REFUSE: 目标里一个带 SITE 的 cell 都没数到（探针空转，不许当通过）"; exit 4 }
    if {$inside != $tot} { puts "PB-REFUSE: Pblock 没真兜住（$tot 个里 [expr {$tot-$inside}] 个在外）"; exit 4 }
}
set t1 [clock seconds]
if {$rd eq ""} { route_design } else { route_design -directive $rd }
puts "ROUTE_WALL=[expr ([clock seconds]-$t1)/60]m"

report_timing_summary -file [file join $out timing_summary.rpt]
report_timing -delay_type max -nworst 1 -max_paths 6 -file [file join $out setup_paths.rpt]
report_utilization -file [file join $out util.rpt]
report_route_status -file [file join $out route_status.rpt]

set tos [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}]
set froms [get_cells -quiet u_eth/u_rx_par/p_eof_reg]
puts "FAM_SETS from=[llength $froms] to=[llength $tos]"
if {[llength $froms] > 0 && [llength $tos] > 0} {
    report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 2 \
        -file [file join $out family.rpt]
} else {
    puts "FAM-SKIP: empty collection (family.rpt not written)"
}
puts "SITE p_eof_reg = [get_property SITE [get_cells -quiet u_eth/u_rx_par/p_eof_reg]]"
set sites {}
foreach c [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}] { lappend sites [get_property SITE $c] }
puts "SITES rows_hit = $sites"
puts "ROLLDONE mode=$mode"
exit 0

# build/tcl/mf114_roll.tcl —— r114 物理单变量实验的一"滚"：广播网该不该被复制驱动
#
#   MF_MODE=none MF_OUT=/tmp/kx/mf114/A  vivado -mode batch -nojournal -source build/tcl/mf114_roll.tcl
#   MF_MODE=repl MF_OUT=/tmp/kx/mf114/B  ...
#
# 为什么是这一刀（全局口径，不是"追最差那条"）：
#   `report/TIMING_GLOBAL.md` 第 2/3 节量出来的事实是——最差那族 route 占 84~94 %、级数只有 4~6，
#   再砍逻辑没有物理依据；而名册里点名的广播（r112：`rok4[51]_i_1_n_0` fo=305、`u_reasm/wr_en_reg_1` fo=547）
#   正是官方文档给的那类抓手（UG949 Timing Closure；AMD 自适应支持文章 9410《Suggestions for high fanout
#   signals》把"高扇出网络复制/限制扇出"排在逻辑重写**之前**）。
#
# ⚠ 2026-10-03 实测改口（这是这一版脚本存在的全部理由，凭据 build/evidence/r113_help_fanout2_console.txt）：
#   * `set_max_fanout` **在本工具里不存在**：`help set_max_fanout` 回
#     `ERROR: [Common 17-25] No topics matched 'set_max_fanout'`。前两版这一滚写的是 `set_max_fanout $lim $objs`，
#     跑起来只会在 catch 里失败 ⇒ 两滚"一样"是假的（我凭 ISE 时代的记忆发明的命令名，又一例"形状要量不许猜"）。
#   * `create_qor_suggestion`、`get_properties` 同样不存在（build/evidence/r113_help_fanout3_console.txt）。
#   * 真正存在的杠杆是 `phys_opt_design` 的旗标（同一份 help 里读到的原文）：
#       -fanout_opt                 "Do cell-duplication based optimization on high-fanout timing critical nets"
#       -force_replication_on_nets  "Force replication optimization on nets"
#       -critical_cell_opt          "Replicates cells on timing critical nets to..."
#     且 help 明说复制出来的对象名字带 `_replica` ⇒ **"机制动没动"是可以数的**（正对照必须能红，规矩 45/46）。
#   所以这一滚的**唯一变量**改成：布线前的那一次 phys_opt 有没有带 `-force_replication_on_nets`。
#
# 流程与纪律（#223 单变量）：两滚都从同一份 `impl_1/system_top_opt.dcp` 起跑，
#   都用裸 `place_design` → `phys_opt_design` → `route_design`（不带 directive，两边一致；
#   正式构建里 `system_top_physopt.dcp` 存在 ⇒ 官方流程本来就跑 phys_opt，A 滚因此不是"半个流程"）。
#   不碰任何被跟踪件，也不碰 runs 目录的产物；全部落 $MF_OUT。
# ⚠ 计数地板：认到的高扇出网数 0 ⇒ MF-REFUSE exit 4（"空集"会伪装成"加了也看不出差别"，规矩 46）。
# ⚠ 网对象的找回只认 `get_nets -quiet <分层路径>` 这一种形式，并且找回后再做一次 NAME 字面相等核对
#   （`-filter "NAME == {…}"` / `FULL_NAME` / `-hier + 短名` 三种形式在 2026-10-03 实测**全部恒空**，
#   凭据 build/evidence/probe_mf114_netname_console.txt；上一版就是栽在这里，41 行名册一行都没认下来）。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换，栽过两次）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
if {[info exists ::env(MF_MODE)]} { set mode $::env(MF_MODE) } else { set mode none }
if {[info exists ::env(MF_OUT)]}  { set out  $::env(MF_OUT)  } else { set out [file join $root "build/tmp_r114_roll"] }
if {[info exists ::env(MF_MINFO)]} { set minfo $::env(MF_MINFO) } else { set minfo 200 }
if {$mode eq "mf"} { set mode repl }
file mkdir $out
puts "ROLL mode=$mode minfo=$minfo dcp=$dcp out=$out"
open_checkpoint $dcp

# ---- 名册：布线前把扇出排行问出来（两边都问，A 也留一份"抓手名册"给差分用） ----
set frpt [file join $out fanout_before.rpt]
file delete -force $frpt
set ferr no-error
catch {report_high_fanout_nets -quiet -max_nets 40 -fanout_greater_than $minfo -file $frpt} ferr
puts "FANOUT_ERR=$ferr EXISTS=[file exists $frpt]"
if {[file exists $frpt]} {
    set fh0 [open $frpt r]; set h0 [read $fh0]; close $fh0
    set hi 0
    foreach hl [split $h0 "\n"] {
        if {$hi < 25} { puts "FANOUT_HEAD|$hl"; incr hi } else { break }
    }
}

# ---- 候选网：按**实测形状**解析（2026-10-03 18:11 那份真报告钉住的三列布局，
#      凭据 build/evidence/probe_mf114_netname_console.txt 的 FANOUT_HEAD 行）：
#        | u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk |   2546 | BUFG |
#   上一版是"位置无关地扫 token"，结果把报告头的 `| Command : report_high_fanout_nets ...
#   -fanout_greater_than 200 ... |` 也读成了一条网（fo=200 net=report_high_fanout_nets）。
#   现在只认"trim 后以 | 开头、以 | 结尾、切出正好 3 格、第 2 格是纯整数"的行 ⇒ 表头与 Command 行天然出局。
proc fan_rows {path minfo} {
    set rows {}
    if {![file exists $path]} { return $rows }
    set fh [open $path r]; set txt [read $fh]; close $fh
    foreach line [split $txt "\n"] {
        set t [string trim $line]
        if {[string index $t 0] ne "|" || [string index $t end] ne "|"} { continue }
        set cells {}
        foreach c [split $t "|"] { lappend cells [string trim $c] }
        if {[llength $cells] != 5} { continue }          ;# 首尾各一个空格子 ⇒ 3 数据格 = 5 段
        lassign [lreplace $cells 0 0] nm fo drv
        if {$nm eq "" || $fo eq ""} { continue }
        if {![string is integer -strict $fo]} { continue }  ;# 表头行 "Fanout" 在这里出局
        if {$fo < $minfo} { continue }
        if {[string first " " $nm] >= 0} { continue }       ;# 网名不含空格 ⇒ 含空格的是散文行
        lappend rows [list $fo $nm $drv]
    }
    return $rows
}

# ---- 网对象怎么找：三条都量过（probe_mf114_netname_console.txt），只有 F0 能用 ----
#   F2 `-filter "NAME == {全名}"` **恒 0**，哪怕 get_property NAME 打出来的就是那一串全名；
#   F3 `-filter "FULL_NAME == {全名}"` 也 0（网的 FULL_NAME 属性在这份 dcp 里是**空**）；
#   F4 `-hier -filter "NAME == {短名}"` 同样 0。
#   能用的只有 F0：`get_nets -quiet <分层路径>`——带 `/` 的模式按路径匹配，`[n]` 也没被当字符类
#   （A[2] 那条找回的对象 NAME 就是字面量 `u_pl/u_bilin/A[2]`），负对照 NO_SUCH_NET 回 0。
#   ⚠ 但"找回来 1 个"不等于"找回来的是**那一个**"⇒ 拿回对象后再做一次字符串相等核对，
#     核对不过的逐条点名（rule 46：计数要说清是"比过的"还是"过了的"）。
proc net_by_name {nm} {
    set c [get_nets -quiet $nm]
    if {[llength $c] != 1} { return {} }
    if {[string compare [get_property NAME $c] $nm] != 0} { return {} }
    return $c
}
set targets {}
set n_skipped_clock 0
set n_skipped_name 0
foreach row [fan_rows $frpt $minfo] {
    lassign $row fo nm drv
    # BUFG/MMCM 驱动的网是时钟网：复制驱动对它们不是抓手（而且会让整条 phys_opt 命令一起失败），
    # 只留在名册里做差分，不进 B 滚的变量。
    if {$drv eq "BUFG" || $drv eq "BUFH" || [string match "*MMCM*" $drv] || [string match "*PLL*" $drv]} {
        incr n_skipped_clock
        puts "MFROW|fo=$fo|net=$nm|drv=$drv|role=roster_only_clock_net"
        continue
    }
    if {[llength [net_by_name $nm]] == 0} {
        incr n_skipped_name
        puts "CAND-SKIP fo=$fo net=$nm (get_nets 按路径没找回、或找回的对象 NAME 字面不等)"
        continue
    }
    lappend targets $nm
    puts "MFROW|fo=$fo|net=$nm|drv=$drv|role=target"
}
set nb [llength $targets]
puts "BIG_NETS=$nb roster_skipped_clock=$n_skipped_clock roster_skipped_name=$n_skipped_name (from $frpt)"
if {$nb == 0} { puts "MF-REFUSE: 名册有行但一个网对象都没认下来（断的是对象查找/驱动类型，不是报告排版）"; exit 4 }

# 干跑开关：MF_DRY=1 时只量"名册解析 + 网对象能不能找回"这一层就收工（约 2 分钟），
# 不烧两滚各 8~10 分钟。上一轮的 MF-REFUSE 就是这一层断的，先用最便宜的一次构建验它。
if {[info exists ::env(MF_DRY)] && $::env(MF_DRY) eq "1"} { puts "DRYDONE targets=$nb"; exit 0 }

# ---- 两滚共同的第一步 ----
set t0 [clock seconds]
place_design
puts "PLACE_WALL=[expr ([clock seconds]-$t0)/60]m"

# ---- 唯一的变量：布线前这一次 phys_opt 带不带 -force_replication_on_nets ----
# ⚠ 网对象在 place 之后**重新**按名字取一次（放线可能重命名），取不到的逐条点名并报数——
#   "B 滚 nets=0" 与 "B 滚根本没跑" 必须能分开（rule 46：计数要说清是比过的还是过了的）。
set netobjs {}
set miss_after_place {}
foreach nm $targets {
    set c [net_by_name $nm]
    if {[llength $c] == 0} { lappend miss_after_place $nm } else { set netobjs [concat $netobjs $c] }
}
puts "NETOBJS got=[llength $netobjs] missing_after_place=[llength $miss_after_place]"
foreach nm $miss_after_place { puts "NETOBJ-MISS net=$nm" }
if {$mode eq "repl"} {
    if {[llength $netobjs] == 0} { puts "MF-REFUSE: 名字认到了但网对象集合是空"; exit 4 }
    if {[catch {phys_opt_design -force_replication_on_nets $netobjs} e]} {
        puts "MF-REFUSE: phys_opt_design -force_replication_on_nets failed: $e"; exit 4
    }
    puts "MF_APPLIED nets=[llength $netobjs] (phys_opt -force_replication_on_nets)"
} else {
    if {[catch {phys_opt_design} e]} { puts "MF-REFUSE: control-roll phys_opt failed: $e"; exit 4 }
    puts "MF_APPLIED none (control roll: plain phys_opt_design)"
}
# 机制到底动没动：help 说复制对象带 _replica ⇒ 数得出来（正对照不许恒等）。
# 两种数法都念：`NAME =~` 过滤器在别的属性上恒空过（ nets 的 NAME 就是那个形状），所以不能只信它。
set reps [get_cells -quiet -hier *_replica*]
set reps_f [get_cells -quiet -hier -filter {NAME =~ *_replica*}]
puts "REPLICA_CELLS=[llength $reps]"
puts "REPLICA_CELLS_FILTER=[llength $reps_f]"
foreach r [lrange $reps 0 9] { puts "REPLICA|$r" }

set t1 [clock seconds]
route_design
puts "ROUTE_WALL=[expr ([clock seconds]-$t1)/60]m"

report_timing_summary -file [file join $out timing_summary.rpt]
report_timing -delay_type max -nworst 1 -max_paths 8 -file [file join $out setup_paths.rpt]
report_timing -delay_type min -nworst 1 -max_paths 4 -file [file join $out hold_paths.rpt]
report_utilization -file [file join $out util.rpt]
report_route_status -file [file join $out route_status.rpt]
# r115 加的两行（提示词 §4 E1 的名册有 13 列，其中两列来自 check_timing；
# 没有这两行，任何快车道滚都造不出一张合法名册，只能造出一张"少列的表"——那是假的基线。
# -verbose 是指定的口径：只有它把没约束的端口逐条点名（§2 A3 要求逐端口归因）。
catch {check_timing -verbose -file [file join $out check_timing_verbose.txt]} ce
puts "CHECKTIMING_ERR=$ce EXISTS=[file exists [file join $out check_timing_verbose.txt]]"
# §7 L1 的延迟分解要用级数分布，两滚都留一份（不是只给 B）。
catch {report_design_analysis -logic_level_distribution -file [file join $out da_levels.rpt]} dl
puts "DA_LEVELS_ERR=$dl EXISTS=[file exists [file join $out da_levels.rpt]]"
set frpt2 [file join $out fanout_after.rpt]
set ferr2 no-error
catch {report_high_fanout_nets -quiet -max_nets 40 -fanout_greater_than $minfo -file $frpt2} ferr2
puts "FANOUT2_ERR=$ferr2 EXISTS=[file exists $frpt2]"
foreach row [fan_rows $frpt2 $minfo] {
    lassign $row fo nm
    puts "MFROWAFTER|fo=$fo|net=$nm"
}

# ---- 目标族的直接读数（eth_rxc 那条 CE 广播锥）：它动了没有是收益侧，名册是代价侧 ----
set tos [get_cells -quiet {u_eth/u_reasm/rows_hit_reg[*]}]
set froms [get_cells -quiet u_eth/u_rx_par/p_eof_reg]
puts "FAM_SETS from=[llength $froms] to=[llength $tos]"
if {[llength $froms] > 0 && [llength $tos] > 0} {
    report_timing -from $froms -to $tos -delay_type max -nworst 1 -max_paths 2 -file [file join $out family.rpt]
} else {
    puts "FAM-SKIP: empty collection (family.rpt not written)"
}
puts "ROLLDONE mode=$mode"
exit 0

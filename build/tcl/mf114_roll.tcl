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
# ⚠ 网名里的 `[n]` 是 get_nets 的 GLOB 类字符 ⇒ 一律 `-filter {NAME == {…}}` 做字符串相等（**`eq` 在本版本会报 [Common 17-263] 语法错**，见 2026-10-03 的实测）。
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

# ---- 候选网：位置无关地解析（列序没实测过 ⇒ 只认"第一个整数 token + 第一个含 / 或 _ 的名字 token"） ----
proc fan_rows {path minfo} {
    set rows {}
    if {![file exists $path]} { return $rows }
    set fh [open $path r]; set txt [read $fh]; close $fh
    foreach line [split $txt "\n"] {
        set t [string trim $line]
        if {$t eq ""} { continue }
        set fo ""
        set nm ""
        foreach tok [split $t] {
            if {[string is integer -strict $tok]} {
                if {$fo eq "" && $tok >= $minfo} { set fo $tok }
            } elseif {$nm eq "" && ([string first "/" $tok] >= 0 || [string first "_" $tok] >= 0)} {
                set nm $tok
            }
        }
        if {$fo ne "" && $nm ne ""} { lappend rows [list $fo $nm] }
    }
    return $rows
}
set targets {}
foreach row [fan_rows $frpt $minfo] {
    lassign $row fo nm
    set n [get_nets -quiet -filter "NAME == {$nm}"]
    if {[llength $n] > 0} {
        lappend targets $nm
        puts "CAND fo=$fo net=$nm hit=[llength $n]"
        puts "MFROW|fo=$fo|net=$nm"
    } else {
        puts "CAND-SKIP fo=$fo net=$nm (no net with this exact NAME)"
    }
}
set nb [llength $targets]
puts "BIG_NETS=$nb (from $frpt)"
if {$nb == 0} { puts "MF-REFUSE: 扇出名册里没认出任何 fo>=$minfo 的网（报告形状或工具版本不符，这一滚没有变量可加）"; exit 4 }

# ---- 两滚共同的第一步 ----
set t0 [clock seconds]
place_design
puts "PLACE_WALL=[expr ([clock seconds]-$t0)/60]m"

# ---- 唯一的变量：布线前这一次 phys_opt 带不带 -force_replication_on_nets ----
set netobjs {}
foreach nm $targets { set netobjs [concat $netobjs [get_nets -quiet -filter "NAME == {$nm}"]] }
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
# 机制到底动没动：help 说复制对象带 _replica ⇒ 数得出来（正对照不许恒等）
set reps [get_cells -hier -filter {NAME =~ *_replica*} -quiet]
puts "REPLICA_CELLS=[llength $reps]"
foreach r [lrange $reps 0 9] { puts "REPLICA|$r" }

set t1 [clock seconds]
route_design
puts "ROUTE_WALL=[expr ([clock seconds]-$t1)/60]m"

report_timing_summary -file [file join $out timing_summary.rpt]
report_timing -delay_type max -nworst 1 -max_paths 8 -file [file join $out setup_paths.rpt]
report_timing -delay_type min -nworst 1 -max_paths 4 -file [file join $out hold_paths.rpt]
report_utilization -file [file join $out util.rpt]
report_route_status -file [file join $out route_status.rpt]
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

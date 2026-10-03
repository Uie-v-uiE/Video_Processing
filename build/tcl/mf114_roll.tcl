# build/tcl/mf114_roll.tcl —— r114 物理单变量实验的一"滚"：高扇出广播该不该被 set_max_fanout 拆开
#
#   MF_MODE=none MF_OUT=/tmp/kx/mf114/A  vivado -mode batch -nojournal -source build/tcl/mf114_roll.tcl
#   MF_MODE=mf   MF_OUT=/tmp/kx/mf114/B  ...
#
# 为什么是这一刀（全局口径，不是"追最差那条"）：
#   `report/TIMING_GLOBAL.md` 第 2/3 节量出来的事实是——最差那族 route 占 84~94 %、级数只有 4~6，
#   再砍逻辑没有物理依据；而名册里点名的两处广播（r112：`rok4[51]_i_1_n_0` fo=305、
#   `u_reasm/wr_en_reg_1` fo=547）正是官方文档给的那类抓手：UG949 的 timing closure 与 AMD 自适应支持
#   文章 9410 都把"高扇出网络复制/限制扇出"列为**先于**逻辑重写的动作。
#   这一滚的变量只有一个：布线前有没有对这些网加 `set_max_fanout`。
# 判读口径（写死在驱动脚本里，不在这里判）：**逐时钟名册差分**，不是全局 WNS 的绝对差（rule 35）。
#   目标是 eth_rxc 那一族抬起来，代价必须让其它三域与它们的 hold 一起被看见（D1/D3 会抓）。
# 纪律（#223）：两个 roll 都从同一份 `vivado_system/.../impl_1/system_top_opt.dcp` 起跑，
#   都用裸 place_design/route_design（不带 directive，两边一致），都跳过 phys_opt
#   （#94 量过：零违反设计上 post-route phys_opt 结构性空转，两边一起省掉不改变对照）。
# 不碰任何被跟踪件，也不碰 runs 目录的产物；全部落 $MF_OUT（默认 build/tmp_r114_roll）。
# ⚠ 计数地板：匹配到的高扇出网数 0 ⇒ MF-REFUSE exit 4——"空集"会伪装成"加了也看不出差别"（规矩 46）。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换，栽过两次）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
if {[info exists ::env(MF_MODE)]} { set mode $::env(MF_MODE) } else { set mode none }
if {[info exists ::env(MF_OUT)]}  { set out  $::env(MF_OUT)  } else { set out [file join $root "build/tmp_r114_roll"] }
if {[info exists ::env(MF_LIMIT)]} { set lim $::env(MF_LIMIT) } else { set lim 96 }
file mkdir $out
puts "ROLL mode=$mode limit=$lim dcp=$dcp out=$out"
open_checkpoint $dcp

# 名册：布线前先把扇出排行问出来（两边都问，这样 A 也留下一份"抓手名册"给 diff 用）
#   MEASURED 2026-10-03（build/evidence/r113_help_fanout_console.txt）：`report_design_analysis` **没有 -fanout 模式**，
#     所以前两版这里写出来的文件是空的（r113 首跑 FANOUT_ROWS=0，被名册差分 D6 抓住）。
#     正确的命令是 `report_high_fanout_nets`（Report/Timing 类，可对已实现设计跑），这里用 -file/-max_nets/
#     -fanout_greater_than/-quiet。文本列序还没实测 ⇒ 解析不认列位置，只认"第一个整数 token + 第一个含 / 或 _ 的
#     名字 token"，并且把报告头 25 行原样念出来留证。
set frpt [file join $out fanout_before.rpt]
file delete -force $frpt
set minfo 200
if {[info exists ::env(MF_MINFO)]} { set minfo $::env(MF_MINFO) }
set ferr no-error
catch {report_high_fanout_nets -quiet -max_nets 40 -fanout_greater_than $minfo -file $frpt} ferr
puts "FANOUT_ERR=$ferr EXISTS=[file exists $frpt]"
if {[file exists $frpt]} {
    set fh [open $frpt r]; set htxt [read $fh]; close $fh
    set hi 0
    foreach hl [split $htxt "\n"] {
        if {$hi < 25} { puts "FANOUT_HEAD|$hl"; incr hi } else { break }
    }
}

# 被点名的广播：从报告文本里挑（不猜 get_nets -filter 的属性名——属性名猜错会让集合变空，
#   而空集跑出来的"两滚一样"是假对照，规矩 46）。名字里带 [n] 位下标，那是 GLOB 类字符，
#   所以认名字一律用 `-filter {NAME eq ...}` 做字符串相等，不用裸 pattern。
set targets {}
if {[file exists $frpt]} {
    set fh [open $frpt r]; set txt [read $fh]; close $fh
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
        if {$fo eq "" || $nm eq ""} { continue }
        set n [get_nets -quiet -filter "NAME eq {$nm}"]
        if {[llength $n] == 0} { set n [get_pins -quiet -filter "NAME eq {$nm}"] }
        if {[llength $n] > 0} {
            lappend targets $nm
            puts "CAND fo=$fo obj=$nm hit=[llength $n]"
            puts "MFROW|fo=$fo|net=$nm"
        } else {
            puts "CAND-SKIP fo=$fo obj=$nm (no net/pin with this exact NAME)"
        }
    }
}
set nb [llength $targets]
puts "BIG_NETS=$nb (from $frpt)"
if {$nb == 0} { puts "MF-REFUSE: 扇出名册里没认出任何 fo>=200 的对象（报告形状或工具版本不符，这一滚没有变量可加）"; exit 4 }

if {$mode eq "mf"} {
    set objs {}
    set nn 0
    set pn 0
    foreach nm $targets {
        set n [get_nets -quiet -filter "NAME eq {$nm}"]
        if {[llength $n] > 0} { incr nn } else { set n [get_pins -quiet -filter "NAME eq {$nm}"]; incr pn [llength $n] }
        set objs [concat $objs $n]
    }
    puts "MF_OBJS nets=$nn pins=$pn total=[llength $objs]"
    if {[llength $objs] == 0} { puts "MF-REFUSE: 名字认到了但对象集合是空"; exit 4 }
    if {[catch {set_max_fanout $lim $objs} e]} { puts "MF-REFUSE: set_max_fanout failed: $e"; exit 4 }
    puts "MF_APPLIED objs=[llength $objs] limit=$lim"
    # 约束真落上了没有：把第一个对象的 MAX_FANOUT 属性读回来（"写了但工具没吃"是这类实验最常见的假绿）
    set probe [lindex $objs 0]
    set mf ""
    catch { set mf [get_property MAX_FANOUT $probe] }
    puts "MF_PROBE obj=$probe MAX_FANOUT=$mf"
    if {$mf eq ""} { puts "MF-WARN: MAX_FANOUT 属性读不回（不影响这一滚已经生效的约束；差集由名册差分兜）" }
} else {
    puts "MF_APPLIED none (control roll)"
}

set t0 [clock seconds]
place_design
puts "PLACE_WALL=[expr ([clock seconds]-$t0)/60]m"
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
if {[file exists $frpt2]} {
    set fh2 [open $frpt2 r]; set t2 [read $fh2]; close $fh2
    foreach line [split $t2 "\n"] {
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
        if {$fo ne "" && $nm ne ""} { puts "MFROWAFTER|fo=$fo|net=$nm" }
    }
}

# 目标族的直接读数（eth_rxc 那条 CE 广播锥）——它动了没有是这一刀的收益侧，名册是代价侧
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

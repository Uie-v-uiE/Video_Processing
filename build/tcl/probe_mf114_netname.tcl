# build/tcl/probe_mf114_netname.tcl —— 只读探针：扇出名册里那一列字符串，到底能不能变成网对象
#
# 为什么量这个（2026-10-03 18:11 实测，凭据 /tmp/kx/mf114/A/roll_console.txt）：
#   `report_high_fanout_nets` 的表头是 `| Net Name | Fanout | Driver Type |`，
#   行是 `| u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk |   2546 | BUFG |` ⇒ **解析器认得出名字和扇出**，
#   但 41 行全部 `CAND-SKIP ... (no net with this exact NAME)` ⇒ 断的是**对象查找**，不是尺子的读表层。
#   （所以 mf114_roll.tcl 里那句"报告形状或工具版本不符"的 REFUSE 文案本身是错的诊断。）
#
# 待验的假设：Vivado 网对象的 `NAME` 属性是**短名**，层次全名在 `FULL_NAME`。
#   这条**没实测过 ⇒ 现在量**，形式并排念，不许猜哪一种：
#     F0 get_nets $nm                        （非 -hier）
#     F1 get_nets -hier $nm                  （-hier 通配 ⇒ 名字里的 [n] 会被当字符类）
#     F2 -filter "NAME == {全名}"
#     F3 -filter "FULL_NAME == {全名}"
#     F4 -hier -filter "NAME == {短名}"
#   每种都带**负对照**（故意查一个不存在的名字，必须回 0）。
# 第二段量"扇出这个数在对象侧有没有出处"：网对象的 FANOUT 属性 / IN 引脚计数，与报告行两个来源对照（rule 46）。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换，栽过两次）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp
puts "DESIGN=[current_design]"

# 名册里的真名 + 不存在的负对照。带 [n] 的必须在内——它就是那条 CE 广播。
set names {
    u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk
    u_eth/u_saver/wptr_reg[5]
    u_eth/u_reasm/rok4[51]_i_1_n_0
    u_pl/u_bilin/A[2]
    NO_SUCH_NET_should_be_zero
}
foreach nm $names {
    set short [file tail $nm]
    set f2 "NAME == {$nm}"
    set f3 "FULL_NAME == {$nm}"
    set f4 "NAME == {$short}"
    set n0 [get_nets -quiet $nm]
    set n1 [get_nets -quiet -hier $nm]
    set n2 [get_nets -quiet -filter $f2]
    set n3 [get_nets -quiet -filter $f3]
    set n4 [get_nets -quiet -hier -filter $f4]
    puts "PROBE net=$nm F0_plain=[llength $n0] F1_hier=[llength $n1] F2_NAMEfull=[llength $n2] F3_FULLNAME=[llength $n3] F4_NAMEshort_hier=[llength $n4]"
    set pick ""
    foreach c [list $n0 $n1 $n3 $n4] { if {[llength $c] == 1} { set pick $c; break } }
    if {$pick ne ""} {
        puts "  OBJ NAME=[get_property NAME $pick] FULL=[get_property FULL_NAME $pick] DRVTYPE=[get_property DRIVER_TYPE $pick]"
        puts "  LOADS_IN=[llength [get_pins -quiet -of $pick -filter {DIRECTION == IN}]] PINS_ALL=[llength [get_pins -quiet -of $pick]]"
    }
}

# 网对象到底有哪些可过滤属性（只列名字，别猜）+ 扇出这一列在对象侧的出处
set wild [get_nets -quiet -hier gmii_rx_cl*]
puts "WILD gmii_rx_cl* = [llength $wild]"
if {[llength $wild] >= 1} {
    puts "PROPS: [list_property [lindex $wild 0]]"
    puts "FANOUTPROP [lindex $wild 0] = [get_property FANOUT [lindex $wild 0]]"
}
set t0 [clock seconds]
set all [get_nets -quiet *]
set fos [get_property FANOUT $all]
set cnt 0
set nonempty 0
foreach nn $all f $fos {
    if {$f eq ""} continue
    incr nonempty
    if {$f >= 200} {
        incr cnt
        if {$cnt <= 12} { puts "PROPFO|fo=$f|net=[get_property FULL_NAME $nn]" }
    }
}
puts "OBJSCAN nets=[llength $all] fanout_prop_nonempty=$nonempty ge200=$cnt t=[expr ([clock seconds]-$t0)]s"
exit 0

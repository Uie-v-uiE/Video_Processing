# build/tcl/probe_r114_idelay_prop.tcl -- 读实：IDELAY_VALUE 能不能在**已综合的网表**上直接改（决定快车道能不能扫档）
#
#   为什么先问这个而不是直接开扫：扫 IDELAY_VALUE 有三条路，成本差 10 倍以上——
#     ① 改 RTL 参数 → 正式一轮 = 构建 + 31 支车道 + 顶层台架（70–128 分钟/档）；
#     ② 在 `system_top_opt.dcp` 上 set_property IDELAY_VALUE → 快车道（7–9 分钟/档）；
#     ③ 什么也不改、只是重新布线（8 分钟）——那扫的是骰子不是档位，不算实验。
#   ②只在"这个属性真的可以吃下去、并且会进时序模型"时成立。这个工具里我已经被"凭记忆写命令/属性"
#   坑过三次（set_max_fanout、get_false_paths、report_methodology -rules），所以先花 3 分钟量形状。
#   运行时标签一律 ASCII（Vivado Tcl 按系统码页读 .tcl，栽过两次）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no opt dcp: $dcp"; exit 1 }
open_checkpoint $dcp

# REF_NAME eq IDELAYE2 数到 0（本件第一次跑实测），所以先按**名字**找、再把它的类型属性念出来：
#   primitives 的 REF_NAME 在这个版本里未必等于库里写的那个字样，硬猜就会把"我的过滤器错了"
#   当成"设计里没有这颗单元"（规矩 46：解析断了要能看出来，不许伪装成空集）。
set cells [get_cells -quiet -hier -filter {NAME =~ *elay*}]
foreach c [get_cells -quiet -hier -filter {NAME =~ *IDELAY*}] { lappend cells $c }
# 上一行原本直接 puts，遇到过滤器语法错就整支脚本死掉。这里改成 catch 并把错误念出来：
#   -quiet 会把"我的过滤器写错了"伪装成"设计里没有这颗单元"（本件里 ODDR_COUNT=0 / IDELAY_BY_REF=0
#   两次都是这个假象，真正的原因是 filter 里的 `eq` 在这类属性上不是合法操作符）。
set f1 ""
catch {set f1 [get_cells -quiet -hier -filter {REF_NAME == IDELAYE2}]} ef1
puts "IDELAY_BY_REF_eq=$f1|filter_rc_eq=$ef1"
set f2 ""
catch {set f2 [get_cells -quiet -hier -filter {REF_NAME eq IDELAYE2}]} ef2
puts "IDELAY_BY_REF_word=$f2|filter_rc_word=$ef2"
foreach c [get_cells -quiet -hier -filter {NAME =~ *elay*}] {
    if {0} { puts "CANDIDATE|name=[get_property NAME $c]|REF_NAME=($c; get_property REF_NAME $c)|IS_PRIMITIVE=[get_property IS_PRIMITIVE $c]|CELLTYPE=($c; get_property CELLTYPE $c)"
}
puts "IDELAY_COUNT=[llength $cells]"
set first ""
# 第一次跑把 set 测在了**最后一个候选**上，而那个是 u_idelay_clkgen/u_mmcm（名字里也有 elay）——
# 于是 "does not have a property IDELAY_VALUE" 报的是 MMCM，不是我要问的对象。
# 现在只认 LOC 以 IDELAY_ 开头的那种（真 IOB delay），别的候选一律不碰。
foreach c $cells {
    if {[string match IDELAY_* [get_property LOC $c]]} { set first $c }
    puts "IDELAY_CELL|name=[get_property NAME $c]|loc=[get_property LOC $c]|VALUE=([catch {get_property IDELAY_VALUE $c} v; set v])|REF=([get_property REF_NAME $c])"
}
if {$first eq ""} { puts "IDELAY_REFUSE: no IDELAYE2 in netlist"; exit 1 }

puts "PROPS_begin"
foreach p [lsort [list_property $first]] {
    if {[string match *DELAY* $p] || [string match *VALUE* $p] || [string match *TAP* $p]} { puts "PROP|$p" }
}
puts "PROPS_end"
set settable [lsearch -exact [list_property $first] IDELAY_VALUE]
puts "IDELAY_VALUE_IS_LISTED_PROPERTY=[expr {$settable >= 0}]"
puts "VALID_VALUES=[join [list_property_value IDELAY_VALUE $first] ,]"

set oldv [get_property IDELAY_VALUE $first]
puts "OLD_VALUE=$oldv"
set err ""
catch {set_property IDELAY_VALUE 18 $first} err
puts "SET_TRY|rc_msg=$err|read_back=([get_property IDELAY_VALUE $first])"
if {$err ne ""} {
    puts "VERDICT|post_synth_property=NO（②不成立，只能走①改 RTL 参数）"
} else {
    if {[get_property IDELAY_VALUE $first] == 18} {
        puts "VERDICT|post_synth_property=YES（②成立：可以在 opt.dcp 上扫档）"
    } else {
        puts "VERDICT|post_synth_property=SET_BUT_NOT_APPLIED（写了但读回不是 18）"
    }
}
# 写进去之后，时序模型有没有真的跟着动：拿那 5 个 IDDR 的 D 脚路径看一眼 hold 的差值方向
set tt1 ""
catch {set tt1 [report_timing -delay_type min -nworst 1 -max_paths 1 -from eth_rxc -to eth_rxc -return_string]} e1
if {$tt1 eq ""} {
    set f "/tmp/kx/r114_idelay_hold.rpt"
    catch {report_timing -delay_type min -nworst 1 -max_paths 1 -from eth_rxc -to eth_rxc -file $f} e2
    if {[file exists $f]} { set fh [open $f r]; set tt1 [read $fh]; close $fh }
}
set slack NA
if {[regexp {Slack\s+\((MET|VIOLATED)\)\s*:\s*(-?[0-9]+\.[0-9]+)\s*ns} $tt1 -> a b]} { set slack "$a/$b" }
puts "HOLD_AFTER_SET|slack=$slack|rc_msg=$e1$e2"
puts "IDELAY_PROP_PROBE_DONE"

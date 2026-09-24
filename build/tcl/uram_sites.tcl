# build/tcl/uram_sites.tcl —— 在**已布局布线**的 dcp 上数站点：这颗 7020 到底有没有 URAM288 站点
#
#   vivado -mode batch -nojournal -source build/tcl/uram_sites.tcl
#
# 为什么又开一个脚本：`build/tcl/uram_presence.tcl` 里三道问法有两道被自己的阳性对照证伪了 ——
#   * `get_lib_cells -regexp` 在只有综合态的工程管理上查不到任何东西（连 `RAMB36E1`/`FDRE` 都返回 0）；
#   * `get_sites -filter {TYPE == "RAMB36"}` 在同样条件下也返回 0，而 7020 明知有 140 个 BRAM tile。
#   ⇒ 这两条"0"都**不能当结论用**（对照没过，问法就是坏的）。
#   只有"例化一次"那道是有对照且能判别对错的：`RAMB36E1` 通过、`URAM1240` 失败、`URAM288` 通过
#   ⇒ 至少说明 7 系库里有 `URAM288` 这个原语、没有 UltraScale+ 的 `URAM1240`。
# 站点数得有物理数据库才查得到 ⇒ 只能在**已布线的 dcp** 上做，所以要趁一次完整构建刚跑完的时候做。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set impl_dir [file join $root vivado_system zynq_video_sys.runs impl_1]
set dcp ""
foreach p [list [file join $impl_dir system_top_routed.dcp]] {
    if {[file exists $p]} { set dcp $p; break }
}
if {$dcp eq ""} {
    set c [catch {exec find $impl_dir -maxdepth 1 -name "*routed*.dcp"} r]
    if {!$c} { set dcp [lindex [split [string trim $r] \n] end] }
}
if {$dcp eq "" || ![file exists $dcp]} { puts "NO_DCP（构建还在跑？或已被下一次构建覆盖）"; exit 1 }
puts "DCP $dcp  mtime [clock format [file mtime $dcp]]"
open_checkpoint $dcp
# 阳性对照必须在同一个环境里通过，否则下面的数字不作数
puts "SITES_RAMB36   [llength [get_sites -quiet -filter {TYPE == \"RAMB36\"}]]   ;# 期望 140（对照）"
puts "SITES_DSP48E1  [llength [get_sites -quiet -filter {TYPE == \"DSP48E1\"}]]  ;# 对照"
puts "SITES_URAM288  [llength [get_sites -quiet -filter {TYPE == \"URAM288\"}]]  ;# 这就是问句"
puts "SITES_IOB      [llength [get_sites -quiet -filter {TYPE == \"IOB\"}]]      ;# 对照（应有几百）"
# 换个问法交叉验证：把所有 site 类型列出来，看里面有没有含 URAM 字样的
set t [lsort -unique [get_property TYPE [get_sites -quiet]]]
puts "SITE_TYPE_COUNT [llength $t]"
set hit {}
foreach x $t { if {[string match -case *URAM* $x]} { lappend hit $x } }
if {[llength $hit] == 0} { puts "SITE_TYPES_WITH_URAM none" } else { puts "SITE_TYPES_WITH_URAM $hit" }
puts "URAM SITES DONE"
exit 0

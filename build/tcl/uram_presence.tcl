# build/tcl/uram_presence.tcl —— 一个更基本的问题：**这颗 xc7z020 到底有没有 UltraRAM 站点？**
#
#   vivado -mode batch -nojournal -source build/tcl/uram_presence.tcl
#
# 为什么要单独问这句（`report/CONTEST_CHECKLIST.md` 第 3 项欠了两年的账）：
# 清单里写"9 块 UltraRAM 换掉 48 块 BRAM"是**算出来**的，还写"要真量需例化 `URAM1240`" ——
# 而 `URAM1240` 是 UltraScale+ 的原语。**如果这颗器件根本没有 UltraRAM，那整个方向从一开始就不成立**，
# 而这个问题不需要查手册，工具自己能回答。
#
# 三道互相独立的问法（任何一道给出确定答案就够，全跑是因为便宜）：
#   Q1 器件的 unisim 库里有没有 `URAM288`/`URAM288E`（7 系的 UltraRAM 原语名）
#   Q2 `report_utilization` 的"可用资源"里有没有 UltraRAM 这一行（有站点才会列）
#   Q3 直接例化一次，看工具是"找不到元件"还是"能例化但端口不对"
# 只读、临时工程建在 build/uram_probe/ 下，跑完可以整个删掉（不进冻结件，凭据是控制台日志）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set part xc7z020clg484-1
set dir [file join $root build uram_probe prj_presence]
file mkdir [file join $root build uram_probe]
create_project -force presence $dir -part $part

# Q1：先把综合库加载起来（`synth_design` 会带 unisims），再用 get_lib_cells 问
set vf [file join $root build uram_probe presence_top.v]
set f [open $vf w]
puts $f {module presence_top(input clk); wire w; reg r; always @(posedge clk) r <= ~r; endmodule}
close $f
read_verilog $vf
synth_design -top presence_top -part $part
# ⚠ 先做**阳性对照**：这个问法必须能找到"我们明知存在"的东西（`RAMB36E1` 有 140 个站点、`FDRE` 遍地都是）。
#    对照失败就说明问法本身不对（库名/正则不匹配），那"找不到 URAM"就不能当结论用 ——
#    与"永远不会红的判据不是判据"是同一条纪律。
set pc_ramb [get_lib_cells -quiet -regexp {(^|/)RAMB36E1$}]
set pc_fdre [get_lib_cells -quiet -regexp {(^|/)FDRE$}]
puts "Q0_positive_control RAMB36E1=[llength $pc_ramb] FDRE=[llength $pc_fdre]（都该 >0，否则下面的 0 不算数）"
puts "Q1_URAM288  [llength [get_lib_cells -quiet -regexp {(^|/)URAM288$}]]"
puts "Q1_URAM288E [llength [get_lib_cells -quiet -regexp {(^|/)URAM288E$}]]"
puts "Q1_URAM1240 [llength [get_lib_cells -quiet -regexp {(^|/)URAM1240$}]]  ;# 已知是 UltraScale+ 的原语，这里 0 是**方法自校**：说明问法对任何族都不会瞎报"
set any [get_lib_cells -quiet -regexp {.*URAM.*}]
puts "Q1_any_URAM_count [llength $any]"
if {[llength $any] > 0} { puts "Q1_any_URAM_first4 $any" } else { puts "Q1_any_URAM_first4 NONE" }

# Q2：utilization 报告里列不列 UltraRAM（只有器件有站点才会出现在 AVAILABLE 一栏）
set ur [file join $root build uram_probe presence_util.rpt]
report_utilization -file $ur
set fd [open $ur r]; set txt [read $fd]; close $fd
set hits [regexp -all -inline {URAM[^|\r\n]*} $txt]
puts "Q2_util_rows [llength $hits]"
foreach h $hits { puts "Q2_row  $h" }

# Q3：直接例化一次。同样带对照：明知存在的 `RAMB36E1` 与明知属于另一族的 `URAM1240` 一起跑，
#     否则"报找不到"既可能意味着"这颗器件没有"、也可能只是"例化写法本身有问题"。
foreach cell {RAMB36E1 URAM288 URAM288E URAM1240} {
    set vf2 [file join $root build uram_probe inst_$cell.v]
    set f2 [open $vf2 w]
    puts $f2 "module inst_[string tolower $cell](); $cell u(); endmodule"
    close $f2
    if {[catch {
        read_verilog $vf2
        synth_design -top inst_[string tolower $cell] -part $part
    } e]} {
        puts "Q3_$cell ERROR [string map {\n " " \r ""} $e]"
    } else {
        puts "Q3_$cell 例化通过（这颗器件有这个原语）"
    }
}
# Q4：**站点级**的正面回答 —— 原语存在于库里 ≠ 这颗器件有站点。
#     直接数器件上的 site。（第一版这里写成 `get_sites -type` 被工具拒了：这个子命令没有 `-type`，
#     要写 `-filter {TYPE == "..."} ` —— 记下来，免得下次又猜。）
#     阳性对照取两个明知存在的类型：RAMB36（7020 该是 140 个 tile，与我们 utilization 里
#     "92 / 65.71 % ⇒ 总共 140"独立对上）与 DSP48E1；问句是 URAM288。
foreach t {RAMB36 DSP48E1 URAM288} {
    set n [llength [get_sites -quiet -filter "TYPE == \"$t\""]]
    puts "Q4_sites_$t $n"
}
set f4 [open [file join $root build uram_probe site_types.txt] w]
puts $f4 [join [lsort -unique [get_property TYPE [get_sites -quiet -filter "INT_SITE_TYPE != \"\""]]] \n]
close $f4
close_project
puts "URAM PRESENCE DONE"
exit 0

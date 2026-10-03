# build/tcl/probe_site_types.tcl —— 只读：这块器件上 CLB 类 site 的**真实名字**
#   为什么单独问一次：pb113_roll.tcl 的 resize_pblock 该写 {CLBLM_L_X40Y20:CLBLM_R_X66Y52}
#   还是 {SLICE_X40Y20:SLICE_X66Y52} 我不确定（7 系与 UltraScale 写法不同），猜错就让 roll B 白跑十来分钟。
#   这里 40 秒出答案：列类型名 + 每种取 4 个真 site 名。装不装得下由 place_design 自己裁决（布不通会明确报错），
#   Pblock 有没有真生效由 pb113_roll.tcl 里的 PB_CELLS / PB_RANGE 两个地板管。
# 运行时标签全 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换）。
set_part xc7z020clg484-2
set all [get_site_types -quiet]
puts "SITE_TYPES_TOTAL=[llength $all]"
if {[llength $all] == 0} { puts "REFUSE: 一个 site 类型都取不到（set_part 没成？）"; exit 2 }
set clb [lsearch -all -inline -regexp $all {(?i)(slice|clb)}]
puts "SITE_TYPES_CLB=[join $clb { }]"
foreach t $clb {
    set s [get_sites -quiet -of_objects [get_site_types $t]]
    puts "TYPE $t COUNT=[llength $s] SAMPLE=[join [lrange $s 0 3] { }]"
}
exit 0

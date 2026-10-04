# 用途：read health lanes 0..9 under live traffic, then restore GPIO_0
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完
# build/tcl/r116_lane_read2.tcl -- read health lanes 0..9 under live traffic, then restore GPIO_0
#
# v2 的原因：v1 想 `expr {0 + [mrd ...]}`，但 **xsdb 的 mrd 是把值打印到 stdout、并不返回字符串**
# ⇒ `can't use non-numeric string as operand of "+"`。这一版不解析：
# 低 25 位是 02:04 手工读到的 `0x000F5000 & 0x07FFFFFF = 0x00F5000`（lane 位当时就是 0），
# 结尾把整字原样写回，所以 src_sel / 阈值 / 特效一位都不会被踩。
connect -host localhost -port 3121
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
if {[info exists ::env(VP_LOW25)]} {
    set low [expr {0 + $::env(VP_LOW25)}]
} else {
    puts "LANEREAD_NEED_LOW25_PRINT_ONLY:"
    mrd -force 0x41200000
    puts "LANEREAD_DONE_NO_WRITE"
    exit 0
}
puts "LANEREAD_LOW25=[format 0x%07X $low]"
for {set L 0} {$L <= 9} {incr L} {
    mwr -force 0x41200000 [format 0x%08X [expr {$low | ($L << 27)}]]
    after 150
    puts "LANE$L_VALUE:"
    mrd -force 0x41210000
}
mwr -force 0x41200000 [format 0x%08X $low]
after 150
puts "RESTORED_GPIO0:"
mrd -force 0x41200000
puts "LANEREAD_DONE"
exit 0

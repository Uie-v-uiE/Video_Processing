# build/tcl/r116_lane_read.tcl -- read the PL link-health lanes over JTAG, preserving GPIO_0
#
# Why hand-rolled: src/host/health_read.mjs 的辅助脚本 data/measured/health_cur.tcl 在这台机器上
# 不存在（它报"读不到 GPIO_0 的当前值"），而 V6（板侧唯一真判据）要的是**流量在跑的时候**
# 的 drop_words / 错误计数 —— 早先 board_verify 读到的 drop_words=0 是在 eth_live=0 时读的，
# 那是一个零样本通过（老规矩：零样本分支会假装绿）。
#
# 硬件接口（见 src/host/health_read.mjs 文件头）：GPIO_0 的 bit[31:27] 是 lane 号，GPIO_1 是数据。
# 这里只改那 5 位、读完把原值写回去 ⇒ src_sel/阈值/特效不受影响。
connect -host localhost -port 3121
targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}
set raw [string trim [mrd -force 0x41200000]]
set v   [expr {0 + $raw}]
set low [expr {$v & 0x07FFFFFF}]
puts "LANEREAD_GPIO0=$raw low25=0x[format %07X $low]"
for {set L 0} {$L <= 9} {incr L} {
    mwr -force 0x41200000 [format 0x%08X [expr {$low | ($L << 27)}]]
    after 150
    puts "LANE$L=[string trim [mrd -force 0x41210000]]"
}
mwr -force 0x41200000 [format 0x%08X $v]
after 150
puts "LANEREAD_RESTORED=[string trim [mrd -force 0x41200000]]"
puts "LANEREAD_DONE"
exit 0

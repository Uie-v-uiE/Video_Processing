# 作用: 列出 hw_server 当前看得见的 JTAG target 与 device，用来区分"线缆没插"和"板子没上电"
# 前置条件: hw_server 在跑（-allow_non_jtag 也连）； vivado -mode batch -source 本文件
# 产出物: stdout 的 TARGETS 与 DEVICES 两段清单
# 关键参数: 无命令行参数
# 退出码: connect_hw_server/open_hw_target 失败时由 Vivado 报错退出（非 0）
# List JTAG devices
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
puts "=== TARGETS ==="
foreach t [get_hw_targets] { puts "  $t" }
puts "=== DEVICES ==="
foreach d [get_hw_devices] {
  puts "  $d  PART=[get_property PART $d]  IDCODE=[get_property IDCODE $d]"
}

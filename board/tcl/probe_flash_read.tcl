# board/tcl/probe_flash_read.tcl —— 只读探针：program_flash 在 hw_manager 里到底存不存在、`-read` 支持哪些写法
# 作用/产出/退出码：探的是命令口在不在；产出只有 `-log` 指的那份日志，连不上硬件打 `REFUSE` 并 `exit 2`，探完 `exit 0`。
#
# 为什么单独一支：2025.2.1 的 `help program_flash` 在**没连硬件**的批处理里直接报
# `ERROR: [Common 17-25] No topics matched`（实测 `.../Temp/hp.log`），那既不能证明命令不存在，
# 也不能证明 `-read` 可用。而"擦之前先把 QSPI 备份成文件"这一步的全部前提就是这条口存在——
# 不能靠猜去赌一块启动介质不可逆的板子。
#
# 跑法（从仓库根）：
#   "<Vivado>/bin/vivado.bat" -mode batch -nojournal -log board/measured/probe_flash_read.log \
#     -source board/tcl/probe_flash_read.tcl
#
# 这一支**只**做 open_hw_manager / connect_hw_server / open_hw_target + 打印，没有 program_flash、
# 没有 erase、没有 rst、没有 mwr —— 对板子零副作用（与 build/tcl/scan_jtag.tcl 同一口径）。
open_hw_manager
if {[catch {connect_hw_server -url localhost:3121} err]} { puts "REFUSE connect_hw_server: $err"; exit 2 }
if {[catch {open_hw_target} err]} { puts "REFUSE open_hw_target: $err"; close_hw_server; exit 2 }

puts "PROBE_HW_TARGET [current_hw_target]"
foreach d [get_hw_devices] {
  # DESCRIPTION 不是每种 hw_device 都带（arm_dap_0 上报 44-56），逐属性 catch，读不到留空。
  set de ""
  catch { set de [get_property DESCRIPTION $d] }
  puts "  DEV [get_property NAME $d] | DESC $de"
}

puts "PROBE_HAS_PROGRAM_FLASH [llength [info commands program_flash]]"
if {[llength [info commands program_flash]] == 0} {
  puts "VERDICT program_flash 不在这一支里：读回得换路（hw_cfgmem 没有 READ 属性，见 flash_qspi_7.log 的 CFGMEM_PROPS 那一行）"
  close_hw_target
  exit 3
}
set hr [catch {help program_flash} htxt]
puts "PROBE_HELP_RC $hr"
puts "----- help program_flash 原文 -----"
puts $htxt
puts "----- 结尾 -----"
close_hw_target
exit 0

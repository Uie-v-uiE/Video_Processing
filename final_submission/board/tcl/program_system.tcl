# 用途：root 要回退**两级**（脚本在 build/tcl/ 下）：早先它在 scripts/ 时 ../ 是对的，
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# Program system.bit (PL+PS netlist)
# root 要回退**两级**（脚本在 build/tcl/ 下）：早先它在 scripts/ 时 ../ 是对的，
# 搬进 build/tcl/ 后就成了 build/build/xxx —— 只在板前才暴露，见 report/log/issues.md #22 的补记。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set bit [file join $root build system.bit]
if {![file exists $bit]} {
  set bit [file join $root build video_pipeline.bit]
}
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAMMED $dev with $bit"
puts "Next: download PS elf via Vitis JTAG"


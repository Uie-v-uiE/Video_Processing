# 用途：JTAG-driven system reset (no hand needed)
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 3=非 0 分支（该文件 exit 3 那一行）
# build/tcl/r116_jtag_recover.tcl -- JTAG-driven system reset (no hand needed)
#
# Why: after program_pl the A9 cores still report "Running" over JTAG, but the console answers
# zero bytes to `stat` through the proven transport (board/scripts/uart_cmd_script.ps1) -- i.e. the app is
# spinning against a PL that was reprogrammed underneath it (the known AXI-wedge failure mode).
# A JTAG system reset is a strictly smaller action than the flash that is already pre-authorised,
# so recovery does not need the user's hand.
puts "RECOVER_BEGIN [clock format [clock seconds]]"
connect -host localhost -port 3121
set sel [catch {targets -set -nocase -filter {name =~ "*APU*"}} e]
puts "APU_SELECT rc=$sel err=$e"
if {$sel != 0} { puts "RECOVER_REFUSE no APU target"; exit 3 }
set r [catch {rst -system} e]
puts "RST_SYSTEM rc=$r err=$e"
after 8000
set t [catch {targets -set -nocase -filter {name =~ "*Cortex-A9*#0*"}} e2]
puts "AFTER_CORE0 rc=$t err=$e2"
after 2000
puts "TARGETS_AFTER:"
puts [targets]
puts "RECOVER_DONE [clock format [clock seconds]]"
exit 0

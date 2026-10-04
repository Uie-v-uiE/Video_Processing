# 用途：仓库根自适应：本文件在 board/ 下，根 = 上一级
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
connect
proc okmsg {v} { if {$v eq ""} { return "ok" } ; return $v }
# 仓库根自适应：本文件在 board/ 下，根 = 上一级。原来这两条路径是硬编码的绝对路径，
# 换一台机器/换一个目录就必然"写了没反应"——与 build/tcl 那两条同一课。
set root [file normalize [file join [file dirname [info script]] ..]]
targets -set 1
catch {rst -system} e; puts "RST: [okmsg $e]"
after 2500
source [file join $root build ps7_init.tcl]
catch {ps7_init} e2; puts "PS7_INIT: [okmsg $e2]"
catch {ps7_post_config} e3; puts "POST_CFG: [okmsg $e3]"
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e4; puts "STOP: [okmsg $e4]"
puts "PC_BEFORE_DOW: [rrd pc]"
catch {dow [file join $root build ps_app.elf]} e5; puts "DOW: [okmsg $e5]"
puts "PC_AFTER_DOW: [rrd pc]"
catch {con} e6; puts "CON: [okmsg $e6]"
after 4000
catch {stop} e7
puts "PC_AFTER_4S: [rrd pc]"
catch {con} e8; puts "RESUME: [okmsg $e8]"
puts "FLOW_DONE"
exit

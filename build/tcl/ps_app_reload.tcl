# build/tcl/ps_app_reload.tcl — 只重启 Cortex-A9、重下 PS app，**不动 PL 配置**
#
#   cmd //c "D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat build/tcl/ps_app_reload.tcl"
#   或  xsdb.bat build/tcl/ps_app_reload.tcl <别的.elf>
#
# 为什么不用 board/boot27c.tcl：它第一步就是 `rst -system`，会把已经配好的 bit 冲掉，
# 于是每次换 app 都得重跑 program_pl（~1 min）+ 重设 GPIO + 重推流。换 app 只需要复位核，
# `rst -processor` 只复位 Cortex-A9 ⇒ 位流、AXI GPIO 控制字、正在跑的视频流全部保留。
#
# 判据（都打在 stdout 上）：
#   PC_BEFORE_CON  必须是 0x00000000（ELF 入口 = app_entry，先开 VFP 再进 _start）
#   3 秒后 PC      不能停在 0x4（那是 Undefined 向量 = 又 trap 了），要落在 .text 中段
#   CPSR 低位      0x13 = Supervisor；0x1b = Undefined 就是没修上
#   串口           看到 [BOOT] 横幅才算真的跑进 main（board/uart_cap_once.ps1）
set root [file normalize [file join [file dirname [info script]] .. ..]]
set elf [expr {[llength $argv] > 0 ? [lindex $argv 0] : [file join $root build ps_app.elf]}]
if {![file exists $elf]} { puts "NO_ELF: $elf"; exit 1 }
puts "ELF: $elf"

catch {connect -host localhost -port 3121} ce
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {rst -processor} e1
puts "RST_PROC: [expr {$e1 eq {} ? {ok} : $e1}]"
catch {dow $elf} e2
puts "DOW: [expr {$e2 eq {} ? {ok} : $e2}]"
puts "PC_BEFORE_CON: [rrd pc]"
catch {con} e3
puts "CON: [expr {$e3 eq {} ? {ok} : $e3}]"
after 3000
catch {stop} e4
# 只采核对得上的寄存器：xsdb 没有 cpacr/sctlr 这两个寄存器名（"no register match"），
# 所以 #42 的判据是"横幅出来了 + 核停在 SVC 模式的 .text 里"，不是 CPACR 回读。
foreach r {pc cpsr lr sp} {
    if {[catch {rrd $r} v]} { puts "$r: READ_FAIL $v" } else { puts "$r: $v" }
}
# 上面那次 stop 只是采寄存器；不 re-con 核就停在断点上，串口命令发进去没人应
# （第一次试就中了这个坑：CAPTURED_LEN 0 看起来像"app 没跑"，其实是"核被我们停着"）。
catch {con} e5
puts "RESUME: [expr {$e5 eq {} ? {ok} : $e5}]"
puts "FLOW_DONE"
exit 0

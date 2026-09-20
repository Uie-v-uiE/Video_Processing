# build/tcl/ps_jtag_boot.tcl — 没有 Vitis/FSBL 时，用 JTAG 把 PS 拉起来（DDR + FCLK_CLK0）
#
#   xsdb.bat build/tcl/ps_jtag_boot.tcl [path/to/ps7_init.tcl]
#   或  set PS7_INIT=<path>; xsdb.bat build/tcl/ps_jtag_boot.tcl
#
# ps7_init.tcl 由 Vitis 平台生成（platform/hw/ps7_init.tcl）；仓库里没有平台工程，
# 所以这里必须显式给路径。正常交付流程仍然应该用 FSBL/ELF 启动：只有 FSBL 会写
# SLCR 里 FPGA_FCM*（HP 通道缓冲）一类的寄存器，ps7_init 的 tcl 版本不含这些写入。
#
# 顺序：ps_jtag_boot → program_pl → set_src → 推流 → 回读。

set root [file normalize [file join [file dirname [info script]] .. ..]]
set psinit ""
if {[info exists ::env(PS7_INIT)]} { set psinit $::env(PS7_INIT) }
if {$psinit eq "" && [llength $argv] > 0} { set psinit [lindex $argv 0] }
if {$psinit eq ""} {
    foreach f [glob -nocomplain [file join $root * platform * hw ps7_init.tcl]] { set psinit $f }
}
if {$psinit eq "" || ![file exists $psinit]} {
    puts "NO ps7_init.tcl — 传路径：xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>"
    exit 1
}
puts "PS7_INIT_FILE: $psinit"

catch {connect -host localhost -port 3121} ce
puts "CONNECT: $ce"

# DAP 卡住时（APB AP transaction error）先做一次系统复位
targets -set 1
catch {rst -system} e1
puts "RST_SYSTEM: [expr {$e1 eq {} ? {ok} : $e1}]"
after 3000

source $psinit
targets -set 1
catch {ps7_init} e2
puts "PS7_INIT: [expr {$e2 eq {} ? {ok} : $e2}]"
catch {ps7_post_config} e3
puts "PS7_POST_CONFIG: [expr {$e3 eq {} ? {ok} : $e3}]"

# 自检：DDR 能写能读 + FCLK 域可访问
targets -set -filter {name =~ "*#0"}
catch {stop}
mwr -force 0x10000000 0x5A5AA5A5
puts "DDR_ECHO: [mrd -force 0x10000000 1]"
catch {con}
puts "PS BOOT STEP DONE — 下一步 build/tcl/program_pl.tcl 配 PL"
exit 0

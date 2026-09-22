# build/tcl/ps_jtag_boot.tcl — 没有 Vitis/FSBL 时，用 JTAG 把 PS 拉起来（DDR + FCLK_CLK0）
#
#   xsdb.bat build/tcl/ps_jtag_boot.tcl [path/to/ps7_init.tcl]
#   或  set PS7_INIT=<path>; xsdb.bat build/tcl/ps_jtag_boot.tcl
#
# ps7_init.tcl 由 Vitis/构建生成；仓库里不放平台工程，但 **build/system.xsa 里就带着它**
# （xsa 是 zip，条目名 ps7_init.tcl）。所以这里的顺序是：
#   1) 环境变量 PS7_INIT / 命令行参数显式给的路径
#   2) 已经解出来的 build/ps7_init.tcl
#   3) 从 build/system.xsa 里自动解出来（下面用 powershell 的单条目解包，Windows 自带，
#      不引入 python/unzip 依赖）—— 这一条是 2026-09-23 补的：之前只有 1)/2)，
#      而 2) 依赖一个"曾经手工存在过"的目录，明早第 2 步会直接 exit 1 卡在看不懂的报错上。
# 正常交付流程仍然应该用 FSBL/ELF 启动：只有 FSBL 会写 SLCR 里 FPGA_FCM*（HP 通道缓冲）
# 一类的寄存器，ps7_init 的 tcl 版本不含这些写入。
#
# 顺序：ps_jtag_boot → program_pl → set_src → 推流 → 回读。

set root [file normalize [file join [file dirname [info script]] .. ..]]
set psinit ""
if {[info exists ::env(PS7_INIT)]} { set psinit $::env(PS7_INIT) }
if {$psinit eq "" && [llength $argv] > 0} { set psinit [lindex $argv 0] }
if {$psinit eq ""} {
    foreach f [glob -nocomplain [file join $root * platform * hw ps7_init.tcl]] { set psinit $f }
}
set xsa   [file join $root build system.xsa]
set outit [file join $root build ps7_init.tcl]
if {$psinit eq "" || ![file exists $psinit]} {
    if {[file exists $outit]} {
        set psinit $outit
    } elseif {[file exists $xsa]} {
        set ps1 [file join $root build _extract_ps7_init.ps1]
        set fh [open $ps1 w]
        puts $fh "Add-Type -AssemblyName System.IO.Compression.FileSystem"
        puts $fh "\$z = [System.IO.Compression.ZipFile]::OpenRead('$xsa')"
        puts $fh "\$e = \$z.GetEntry('ps7_init.tcl')"
        puts $fh "[System.IO.Compression.ZipFileExtensions]::ExtractToFile(\$e, '$outit', \$true)"
        puts $fh "\$z.Dispose()"
        puts $fh "if (Test-Path '$outit') { Write-Output OK }"
        close $fh
        catch {exec powershell -NoProfile -ExecutionPolicy Bypass -File $ps1} res
        file delete -force $ps1
        puts "AUTO-EXTRACT ps7_init.tcl from system.xsa: [string trim $res]"
        if {[file exists $outit]} { set psinit $outit }
    }
}
if {$psinit eq "" || ![file exists $psinit]} {
    puts "NO ps7_init.tcl — 传路径：xsdb.bat build/tcl/ps_jtag_boot.tcl <ps7_init.tcl>"
    puts "   （或确认 $xsa 存在，本脚本会自动从里面解出来）"
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

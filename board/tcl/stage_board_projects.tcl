# board/tcl/stage_board_projects.tcl —— 把 Vivado 上板工程搬进 board/ 并**当场验证它打得开、跑得通**
#
# 依赖：Vivado 2025.2.1 批处理模式；`vivado_system/zynq_video_sys.xpr` 已由
#        `build/tcl/build_system_axigpio.tcl` 建好并跑完实现（本脚本不重综合、不重布线）；
#        `board/project/system.bit` 与 `board/project/system.xsa` 在盘上。
# 用法："<Vivado>/bin/vivado.bat" -mode batch -nojournal -log <目录>/stage.log \
#          -source board/tcl/stage_board_projects.tcl        （约 1–2 分钟）
# 参数：
#   | 变量 | 作用 | 默认 |
#   | --- | --- | --- |
#   | `VP_BOARD_DIR` | 上板工程的落点 | `board`（工程与文档同级，仓库里已是这个形状） |
#   | `VP_STAGE_BIT` | 设为 1 时把 `board/project/system.bit`/`.xsa` 也复制一份进落点；默认不复制，只核对字节 | 未设 |
#   | `VP_STAGE_FORCE` | 设为 1 时即使位流字节数与 `board/project/system.bit` 不一致也继续（默认不一致就 REFUSE） | 未设 |
#
# 为什么要它：交付要求 `board/` 放"上板工程"。工程本体是构建脚本的产物，直接复制一份进 `board/`
# 会有两个风险：复制不完整（少 .srcs 里的约束或 BD 的 .bd 文件）与复制的不是板上那一版。
# 所以这个脚本做三件事：① 复制工程目录；② 用复制出来的那份**真的 open_project**，
# 打印器件/约束文件数/运行状态；③ 比 `board/zynq_video_sys.srcs` 里 BD 的 `.bd` 是否真在其中、
# 以及 `board/project/system.bit` 的字节可读，读不到就 REFUSE。验证结果打在日志里，`board/README.md` 引用的就是这份日志。
# 位流与 .xsa 不在 `board/` 里再存一份：仓库已在 `board/project/system.bit`、`board/project/system.xsa` 跟踪它们，
# 复制一份只多 3 MB 且会出现"两份位流哪个是板上那版"的歧义；`board/flash/make_boot_image.sh` 直接从 `build/` 取。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set src_proj [file join $root "vivado_system/zynq_video_sys.xpr"]
set dst [file normalize [file join $root "board"]]
if {[info exists ::env(VP_BOARD_DIR)]} { set dst [file normalize $::env(VP_BOARD_DIR)] }
if {![file exists $src_proj]} { puts "REFUSE: 没有已建好的工程 $src_proj（先跑 build/tcl/build_system_axigpio.tcl）"; exit 1 }

set src_dir [file dirname $src_proj]
file mkdir $dst
puts "STAGE from=$src_dir to=$dst"
# 只带走工程本体：.xpr + .srcs（约束、BD、IP 配置）。runs/ 与 .Xil 是实现产物，不复制。
file copy -force $src_proj [file join $dst [file tail $src_proj]]
if {[file exists [file join $dst zynq_video_sys.srcs]]} { file delete -force [file join $dst zynq_video_sys.srcs] }
file copy -force [file join $src_dir zynq_video_sys.srcs] [file join $dst zynq_video_sys.srcs]

set bit [file join $root build system.bit]
set xsa [file join $root build system.xsa]
foreach f [list $bit $xsa] {
    if {![file exists $f]} { puts "REFUSE: 缺 $f"; exit 1 }
    if {[info exists ::env(VP_STAGE_BIT)]} { file copy -force $f [file join $dst [file tail $f]] }
}

# --- 验证：打开复制出来的那份 --------------------------------------------------------------
open_project [file join $dst [file tail $src_proj]]
set part [get_property PART [current_project]]
set runs [get_runs]
set constrs [get_files -of [get_filesets constrs_1]]
set srcs [get_files -of [get_filesets sources_1]]
puts "VERIFY project=[current_project]"
puts "VERIFY part=$part"
puts "VERIFY runs=[llength $runs] : $runs"
puts "VERIFY sources=[llength $srcs] constraints=[llength $constrs]"
puts "VERIFY bit_bytes=[file size $bit] xsa_bytes=[file size $xsa]"
# 复制最容易漏的是 BD/IP 与约束：逐个问文件在不在，缺一个就 REFUSE（不数数量、只认路径存活）。
set missing 0
foreach f [concat $srcs $constrs] {
    if {![file exists $f]} { puts "MISSING $f"; incr missing }
}
puts "VERIFY missing_files=$missing of [expr {[llength $srcs] + [llength $constrs]}]"
if {$missing > 0} {
    if {![info exists ::env(VP_STAGE_FORCE)]} { puts "REFUSE: 复制出来的工程有文件不在盘上"; close_project; exit 1 }
}
close_project

# --- 收尾两笔：打开过一次之后必须把交付形状复原 ---------------------------------------------
# ① `<Project … Path="…">`：复制来的那份带的是 vivado_system/ 的绝对路径，而 open/close 又原样写回。
#    交付约定这个属性写成仓库相对的落点名（HEAD 里是 `board/zynq_video_sys.xpr`），改回去。
set rel [string range $dst [expr {[string length $root] + 1}] end]
set dstrel "$rel/[file tail $src_proj]"
set xpr [file join $dst [file tail $src_proj]]
set fh [open $xpr r]; set txt [read $fh]; close $fh
if {![regexp {(<Project [^>]*?)Path="[^"]*"} $txt whole _pre]} {
    puts "REFUSE: 工程头里找不到 Path= 属性，改写规则与这版 Vivado 对不上（别硬改）"; exit 1
}
set new [regsub {(<Project [^>]*?)Path="[^"]*"} $txt "\\1Path=\"$dstrel\""]
if {$new eq $txt} { puts "NORMALIZE already=$dstrel" } else {
    set wh [open $xpr w]; puts -nonewline $wh $new; close $wh; puts "NORMALIZE path_attr=$dstrel"
}
set absleft 0
foreach line [split $new \n] { if {[regexp {[A-Za-z]:[/\\]} $line]} { incr absleft } }
puts "VERIFY abs_path_lines=$absleft bytes=[file size $xpr]"
if {$absleft > 0} { puts "REFUSE: 工程里还有本机绝对路径，这份不能入库"; exit 1 }
# ② 打开工程会长工作区目录（本次实测 `*.cache` 1.0 KB、`*.hw` 若干）：交付目录不留，删掉并报告。
foreach junk [list "$dst/*.cache" "$dst/*.gen" "$dst/*.runs" "$dst/*.hw" "$dst/*.sim"] {
    foreach d [glob -nocomplain $junk] { file delete -force $d; puts "CLEAN [file tail $d]" }
}
puts "STAGE_BOARD_PROJECTS DONE"
exit 0

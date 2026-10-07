# build/r129_open_check.tcl —— 只读探针：本机路径占位符化之后，Vivado 工程还打得开吗
#
# 为什么要跑：r129 把 `vivado_system/` 与 `vitis/` 两棵里 175 份生成件正文的本机绝对路径
# 换成了占位符（`build/r129_path_sanitize.mjs`），其中包含工程头 `<Project … Path="…">`
# ——按仓库自己的约定写成仓库相对落点名（与 `board/tcl/stage_board_projects.tcl` 第 66-75 行同一做法）。
# 改的是**能打开的那份东西**，所以必须用 Vivado 本身证明一次，而不是靠"应该没事"。
#
# 用法（约 1–3 分钟）：
#   "<Vivado>/bin/vivado.bat" -mode batch -nojournal -log <目录>/r129_open.log \
#     -source build/r129_open_check.tcl
# 判定（都打在日志里，逐条要读）：
#   OPEN ok=<器件>                     工程开得了
#   VERIFY sources=<n> constrs=<n>     源件与约束的条数（对照 board/README.md 记的 86 + 2）
#   VERIFY missing_files=0 of <n>      没有文件指到盘外（这一条是 stage_board_projects 的同一条判据）
#   VERIFY runs=<n>                    run 条数（对照记录的 14）
#   VERIFY abs_path_lines=<n>          工程头归一化之后自己数还剩几行带盘符（要求 0）
#   CLOSE no-write                     只 close_project，不落任何写回，探针不改工程
set root [file normalize [file join [file dirname [info script]] ..]]
set xpr $root/vivado_system/zynq_video_sys.xpr
if {![file exists $xpr]} { puts "REFUSE: no $xpr"; exit 1 }
if {[catch {open_project $xpr} e]} { puts "REFUSE: open_project failed: $e"; exit 1 }
puts "OPEN ok=[current_project]"
set srcs [get_files -of_objects [get_filesets sources_1]]
set cons [get_files -of_objects [get_filesets constrs_1]]
puts "VERIFY sources=[llength $srcs] constrs=[llength $cons]"
set miss 0
foreach f [concat $srcs [get_files -of_objects [get_filesets constrs_1]]] {
  if {![file exists $f]} { incr miss; puts "MISSING $f" }
}
puts "VERIFY missing_files=$miss of [expr {[llength $srcs] + [llength $cons]}]"
puts "VERIFY runs=[llength [get_runs]]"
set fh [open $xpr r]; set txt [read $fh]; close $fh
set abs 0
foreach line [split $txt \n] { if {[regexp {[A-Za-z]:[/\\]} $line]} { incr abs } }
puts "VERIFY abs_path_lines=$abs"
close_project
puts "CLOSE no-write"
puts "DONE r129_open_check"

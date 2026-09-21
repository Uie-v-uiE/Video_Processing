# build/tcl/report_mem_hier.tcl — 层次化资源报告（回答「BRAM 被谁吃掉了」）
#
#   vivado -mode batch -nojournal -log build/report_mem_hier.log \
#          -source build/tcl/report_mem_hier.tcl
#
# 打开已完成的 impl_1（没有则退回 synth_1），输出 build/util_hier.rpt。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set proj [file join $root vivado_system zynq_video_sys.xpr]
if {![file exists $proj]} { puts "MISSING $proj"; exit 1 }
open_project $proj
set opened 0
catch {open_run impl_1} e
if {[string match *error* [string tolower $e]]} {
  catch {open_run synth_1} e2
  if {![string match *error* [string tolower $e2]]} { set opened 1 }
} else { set opened 1 }
if {!$opened} { puts "NO RUN TO OPEN: $e"; exit 1 }
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $root build util_hier.rpt]
puts "HIER: [file join $root build util_hier.rpt]"
exit 0

# build/report.tcl
# 作用: 导出资源占用与时序等工具原始报告到 build/report/（交付要求 §4.4 的归档位置）
# 前置条件: impl_1 已跑完（route_design 或 write_bitstream 完成）
# 产出物: build/report/ 下 timing_summary.rpt、utilization.rpt、cdc.rpt、methodology.rpt、
#         power.rpt、route_status.rpt、clock_util.rpt（后五份缺了不判失败，与主脚本同一口径）
# 关键参数: VP_PROJ_SUBDIR；VP_OUTDIR 覆盖归档目录（默认 build/report）
# 退出码: 0=时序与资源两份必备报告已落盘 非 0=工程缺失或必备报告没写出来
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_subdir vivado_system
if {[info exists ::env(VP_PROJ_SUBDIR)] && $::env(VP_PROJ_SUBDIR) ne ""} { set proj_subdir $::env(VP_PROJ_SUBDIR) }
set xpr [file join $root $proj_subdir zynq_video_sys.xpr]
if {![file exists $xpr]} { puts "NO_PROJECT $xpr"; exit 1 }
set outdir [file join $root build report]
if {[info exists ::env(VP_OUTDIR)] && $::env(VP_OUTDIR) ne ""} { set outdir [file normalize [file join $root $::env(VP_OUTDIR)]] }
file mkdir $outdir
open_project $xpr
open_run impl_1
report_timing_summary -file [file join $outdir timing_summary.rpt]
report_utilization -file [file join $outdir utilization.rpt]
catch {report_cdc -file [file join $outdir cdc.rpt]}
catch {report_methodology -file [file join $outdir methodology.rpt]}
catch {report_power -file [file join $outdir power.rpt]}
catch {report_route_status -file [file join $outdir route_status.rpt]}
catch {report_clock_utilization -file [file join $outdir clock_util.rpt]}
close_project
set ok 1
foreach f {timing_summary.rpt utilization.rpt} {
  if {![file exists [file join $outdir $f]]} { puts "REPORT_MISSING $f"; set ok 0 }
}
puts "REPORT_DIR $outdir"
if {!$ok} { exit 1 }

# 只读：量 8 个 TMDS 输出脚（含 LED）的 clock-to-pin "Data Path Delay"，先按原件形状解析
# 形状凭据：build/evidence/r119_shape_*.txt 第 22 行原文
#   `  Data Path Delay:        2.033ns  (logic 2.032ns (99.951%)  route 0.001ns (0.049%))`
set dcp "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"
if {![file exists $dcp]} { puts "PROBE-REFUSE"; exit 3 }
open_checkpoint $dcp
set rpt "vivado_system/.r119_tmp.rpt"
foreach p {tmds_clk_p tmds_clk_n tmds_data_p\[0\] tmds_data_n\[0\] tmds_data_p\[1\] tmds_data_n\[1\] tmds_data_p\[2\] tmds_data_n\[2\] led\[0\] led\[1\]} {
  set o [get_ports -quiet $p]
  if {$o eq ""} { puts "PIN| $p | PORT_NOT_FOUND NOT_MEASURED"; continue }
  foreach dt {max min} {
    if {[file exists $rpt]} { file delete -force $rpt }
    set rc [catch {report_timing -to $o -delay_type $dt -max_paths 1 -nworst 1 -file $rpt} e]
    if {$rc != 0 || ![file exists $rpt] || [file size $rpt] == 0} { puts "PIN| $p | $dt rc=$rc NOT_MEASURED"; continue }
    set f [open $rpt r]; set txt [read $f]; close $f
    if {![regexp {(?m)^\s*Data Path Delay:\s*([0-9.]+)ns} $txt -> dly]} { puts "PIN| $p | $dt NO_FIELD NOT_MEASURED"; continue }
    puts "PIN| $p | $dt | data_path_delay=${dly}ns"
  }
}
puts "CLKINFO| clkout1_1 period=[get_property PERIOD [get_clocks -quiet clkout1_1]]"
puts "PROBE-SKEW-DONE"
exit 0

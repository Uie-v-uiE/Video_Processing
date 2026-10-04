# 只读：把 -to 输出脚的报告原样落盘，先量形状再写解析（P04 铁律 9）
set dcp "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"
if {![file exists $dcp]} { puts "REFUSE no dcp"; exit 3 }
open_checkpoint $dcp
foreach p {tmds_clk_p tmds_data_p\[0\] led\[0\]} {
  set o [get_ports -quiet $p]
  if {$o eq ""} { puts "NOPORT $p"; continue }
  set f "build/evidence/r119_shape_[string map {\[ _ \] _} $p].txt"
  report_timing -to $o -delay_type max -max_paths 1 -nworst 1 -file $f
  puts "WROTE $f size=[file size $f]"
  report_timing -to $o -delay_type min -max_paths 1 -nworst 1 -append -file $f
}
exit 0

# 只读：把 -to 输出脚的报告原样落盘，先量形状再写解析（P04 铁律 9）
# 作用: 对 tmds_clk_p / tmds_data_p[0] / led[0] 各做一次 -to 端点的 max 与 min 路径报告，原样存成证据件供解析器对形状
# 前置条件: 仓库根下 vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp 已存在（缺 ⇒ puts "REFUSE no dcp" 并 exit 3），build/evidence/ 可写
# 产出物: build/evidence/r119_shape_tmds_clk_p.txt、r119_shape_tmds_data_p_0.txt、r119_shape_led_0.txt（每份 = max 报告 + -append 的 min 报告），stdout 每份一行 WROTE <件> size=
# 关键参数: 无命令行参数、无 env 读取；DCP 路径与端口名册写死在本文件里
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

# ooc_newmods.tcl — 新模块的 out-of-context 综合 + **真实时序**预检。
#
# 为什么值得单独有这么一个脚本：V7.6 第一次全流程 L3 里 WNS 掉到 −6.765（19 个
# 违例端点），根因是 OSD 里 32bit 十进制除法拉出的 45 级组合链。发现它要花一次
# 15 分钟的构建；而这三个模块单独 OOC 只要 1~2 分钟。
# 时钟按各自真实域给：link_monitor 吃 125 MHz eth_rxc，snap_cross/osd_overlay 吃
# 50 MHz 像素时钟。跑法：
#   vivado -mode batch -nojournal -log build/ooc_newmods.log -source build/tcl/ooc_newmods.tcl
# 判据：log 里每条 `Slack (...)` 都必须 ≥ 0（grep "Slack" build/ooc_newmods.log）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
create_project ooc_check [file join $root vivado_ooc] -part xc7z020clg484-2 -force
read_verilog [file join $root src rtl eth link_monitor.v]
read_verilog [file join $root src rtl eth snap_cross.v]
read_verilog [file join $root src rtl video osd_overlay.v]

foreach {m port period} {
  link_monitor  clk     8.0
  snap_cross    dst_clk 20.0
  osd_overlay   clk     20.0
} {
  puts "==== OOC $m  (clock port $port, period ${period} ns) ===="
  if {[catch {synth_design -top $m -mode out_of_context -part xc7z020clg484-2} e]} {
    puts "SYNTH_FAIL $m : $e"
    continue
  }
  create_clock -name ooc_clk -period $period [get_ports $port]
  # 不给输入/输出延迟的话，OOC 里全是 IN2REG 路径、slack 恒为 inf，等于没测。
  # 3 ns 输入延迟模拟「上一级触发器的时钟网络 + Q→布线」，和真设计里
  # lm_pix/x_d11 这类同域寄存器驱动的场合接近。
  # 本流程里没有 remove_from_collection / filter / get_object_name 这些 proc，
  # 直接拿对象名字串排掉时钟口（否则 set_input_delay 会打在 create_clock 的口上）。
  set clkobj [get_ports $port]
  set din {}
  foreach pp [all_inputs] {
    if {$pp ne $clkobj} { lappend din $pp }
  }
  set_input_delay  -clock ooc_clk -max 3.0 $din
  set_output_delay -clock ooc_clk -max 1.0 [all_outputs]
  set_input_delay  -clock ooc_clk -min 0.0 $din
  set_output_delay -clock ooc_clk -min 0.0 [all_outputs]
  puts [report_timing -max_paths 4 -nworst 2 -delay_type max -return_string]
}
report_utilization -file [file join $root build ooc_util.rpt]
puts "OOC SYNTH DONE"
catch {close_project}
exit

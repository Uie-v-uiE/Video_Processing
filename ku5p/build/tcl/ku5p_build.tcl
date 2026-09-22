# ku5p/build/tcl/ku5p_build.tcl —— 把 Zynq 版以太网栈综合/实现到 UltraScale+
#
#   vivado -mode batch -nojournal -log ku5p/build/ku5p_synth.log -source ku5p/build/tcl/ku5p_build.tcl
#   带 KU5P_SYNTH_ONLY=1 时只跑综合（几分钟），用来快速验证"能不能过"；不带则一路到布线 + 报告。
#
# 与 Zynq 版 build_system_axigpio.tcl 的根本差别：这里**没有 BD、没有 PS、没有厂商 IP**。
# 加进来的 .v 与 Zynq 工程共用同一批文件（不复制、不改写），只有 RGMII IO 那一层
# （gmii_to_rgmii / rgmii_rx / rgmii_tx）换成 UltraScale+ 版本；因此必须把 7 系列那三份
# 排除在文件列表之外 —— 否则同名模块冲突，而且顶层 eth_udp_video_top 会把它们拉回来。
set root [file normalize [file join [file dirname [info script]] .. .. ..]]
set pdir [file join $root ku5p vivado_ku5p]
set outd [file join $root ku5p build]
file mkdir $outd

create_project ku5p_eth $pdir -part xcku5p-ffvb676-2-i -force
set_property target_language Verilog [current_project]

set eth_keep {arp.v arp_rx.v arp_tx.v icmp.v icmp_rx.v icmp_tx.v udp.v udp_rx.v
              udp_rx_parser.v udp_tx.v eth_ctrl.v frame_reasm.v sync_fifo.v dc_fifo.v
              crc32_d8.v link_monitor.v snap_cross.v gmii_rx_mac.v}
foreach f $eth_keep {
  set p [file join $root src rtl eth $f]
  if {[file exists $p]} { add_files -norecurse $p } else { puts "WARN missing $p" }
}
add_files -norecurse [file join $root src rtl video frame_buffer_w64.v]
add_files -norecurse [file join $root src rtl video fb_pack.v]
foreach f [glob -nocomplain [file join $root ku5p src rtl *.v]] { add_files -norecurse $f }
add_files -fileset constrs_1 -norecurse [file join $root ku5p src constraints ku5p_rk_xcku5p_f.xdc]
set_property top ku5p_eth_top [current_fileset]
update_compile_order -fileset sources_1

if {[catch {synth_design -top ku5p_eth_top -part xcku5p-ffvb676-2-i} e]} {
  puts "SYNTH FAILED: $e"; exit 1
}
puts "SYNTH OK"
report_utilization -file [file join $outd ku5p_util_synth.rpt]
if {[info exists ::env(KU5P_SYNTH_ONLY)]} { exit 0 }

opt_design
place_design
phys_opt_design
route_design
# 存一份已布线的 checkpoint：不存的话批处理进程一退出，第二天的任何
# "再看一眼那条保持余量很小的路径"都得从综合重跑（这次就吃了这个亏）。
write_checkpoint -force [file join $outd ku5p_routed.dcp]
report_timing_summary -file [file join $outd ku5p_timing.rpt]
# 汇总里只有 WHS 的数字，看不出是哪条路径 ⇒ 最坏 min/max 各出 4 条明细
report_timing -delay_type min -max_paths 4 -nworst 2 -sort_by group   -file [file join $outd ku5p_hold.rpt]
report_timing -delay_type max -max_paths 4 -nworst 2 -sort_by group   -file [file join $outd ku5p_setup.rpt]
report_utilization    -file [file join $outd ku5p_util.rpt]
report_methodology    -file [file join $outd ku5p_methodology.rpt]
report_cdc            -file [file join $outd ku5p_cdc.rpt]
report_route_status   -file [file join $outd ku5p_route_status.rpt]
write_bitstream -force [file join $outd ku5p_eth.bit]
puts "KU5P BUILD DONE"

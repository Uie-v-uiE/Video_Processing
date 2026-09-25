# micro_rd.tcl —— 只 place+route 帧缓存读口这一条路，回答双线性能不能上板。
#
# 跑法（一次一个 MODE；三个 MODE 的日志分别落 build/micro_rd/m<MODE>.log）：
#   MODE=2 vivado -mode batch -nojournal -log build/micro_rd/m2.log -source build/tcl/micro_rd.tcl
# 判据与"为什么这不算门禁"写在 build/micro_rd/README.md。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set mode  1
if {[info exists ::env(MODE)]} { set mode $::env(MODE) }
set dir   [file join $root build micro_rd]
set gen   [file join $dir gen]
file mkdir $gen

# 顶层参数没有可靠的批处理覆盖手段 ⇒ 直接给每个 MODE 生成一个薄壳顶层（十行，不骗人）
set top "micro_rd_m$mode"
set fh  [open [file join $gen "$top.v"] w]
puts $fh "`timescale 1ns/1ps"
puts $fh "module $top (input wire sys_clk, input wire rst_n, output wire \[31:0\] acc, output wire \[15:0\] rd_now);"
puts $fh "  micro_fb_rd #(.MODE($mode)) u_dut (.sys_clk(sys_clk), .rst_n(rst_n), .acc(acc), .rd_now(rd_now));"
puts $fh "endmodule"
close $fh

create_project micro_rd_m$mode [file join $dir proj_m$mode] -part xc7z020clg484-2 -force
read_verilog [file join $dir micro_fb_rd.v]
read_verilog [file join $root src rtl clocks clk_gen.v]
read_verilog [file join $root src rtl video frame_buffer_w64.v]
read_verilog [file join $gen "$top.v"]

# 只有一个约束：入口 50 MHz。clk_gen 里的 MMCME2_BASE 会自己推出 50/250/200 三条派生钟，
# 所以 4 ns 那条要求是**工具自己算出来的**，不是我手写 create_clock 定的 —— 这一点很重要：
# 手写 250 MHz 会和真实设计里的相位关系不一致，量出来的数就不能比。
set xdc [file join $gen "$top.xdc"]
set fh [open $xdc w]
puts $fh "create_clock -period 20.000 -name sys_clk \[get_ports sys_clk\]"
close $fh
add_files -fileset constrs_1 -norecurse $xdc
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

if {[catch {synth_design -top $top -part xc7z020clg484-2} e]} { puts "SYNTH_FAIL $e"; exit 1 }
puts "==== SYNTH OK (MODE $mode) ===="
report_utilization -file [file join $dir util_m$mode.rpt]
# BRAM 数量要当场看：探针必须复刻"读地址扇出到整个帧缓存"这件事，
# 否则 MODE 之间的差没有资格外推到 build#15。实测这一份 frame_buffer_w64(512×300) 是 21 个 tile
# （旧笔记里的"80 个 tile"是当年那一版阵列组织，与今天的模块不同源 —— 已在结论里改口）。
catch {puts [report_utilization -hierarchical -return_string]}

if {[catch {opt_design} e]}    { puts "OPT_FAIL $e"; exit 1 }
if {[catch {place_design} e]}  { puts "PLACE_FAIL $e"; exit 1 }
if {[catch {phys_opt_design -directive AggressiveReplication} e]} { puts "PHYSOPT_SKIP $e" }
if {[catch {route_design} e]}  { puts "ROUTE_FAIL $e"; exit 1 }

puts "==== TIMING SUMMARY (MODE $mode) ===="
puts [report_timing_summary -delay_type max -max_paths 10 -return_string]
puts "==== 最差 12 条（全文，含起止点与布线占比）===="
puts [report_timing -delay_type max -max_paths 12 -nworst 2 -return_string]

# 点名那条路：mux → RAMB36 的读地址脚。探针的全部意义就是这一条。
set apins [get_pins -hier -filter {NAME =~ *ADDRARDADDR*}]
puts "==== ADDRARDADDR 引脚数 = [llength $apins] ===="
if {[llength $apins] > 0} {
  puts [report_timing -to $apins -delay_type max -max_paths 6 -nworst 3 -return_string]
}
close_project
exit

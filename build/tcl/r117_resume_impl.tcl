# build/tcl/r117_resume_impl.tcl -- 只重启实现阶段（synth_1 的结果留着复用），把修好的钩子跑完。
#
# 为什么不是整条链子重来（2026-10-04 04:01，ISSUES #327）：
#   第一版钩子把 Tcl `catch` 的返回值当哨兵字符串用了（`catch {...} e` 之后比 `$e ne "no-error"`），
#   成功时 e 是返回码 "0" ⇒ 一次**成功的** phys_opt 被判成失败，`error` 把官方 impl run 打死。
#   被打死之前切割本身已经成立（`impl_1/runme.log`：pins_before=239 -> pins_after=1、replica_cells=10）。
#   综合网表没被碰（`system_top_opt.dcp` 03:58 那份就是本轮要的），所以重跑的只有实现段；
#   约束、part、策略、钩子路径一律不动 ⇒ 与整条链重来相比这是**同一棵树、同一条尺子**，只是省下综合。
#
# ASCII-only puts（Vivado Tcl 在系统代码页下读 UTF-8，中文 puts 会把控制台变成二进制——环境账里栽过）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set xpr  $::env(VP_XPR)
set hook [file normalize [file join $root build tcl r117_post_place_hook.tcl]]
if {![file exists $xpr]} { puts "RESUME-REFUSE no project $xpr"; exit 1 }
if {![file exists $hook]} { puts "RESUME-REFUSE no hook $hook"; exit 1 }
open_project $xpr
# 重新钉一遍钩子（幂等）：属性本来就在 run 上，这里写出来是为了让日志里有据可查
set_property STEPS.PLACE_DESIGN.TCL.POST $hook [get_runs impl_1]
puts "RESUME hook=$hook"
puts "RESUME hook_prop_now=[get_property STEPS.PLACE_DESIGN.TCL.POST [get_runs impl_1]]"
reset_run impl_1
set bit [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top.bit]]
file delete -force $bit
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
puts "RESUME impl_status=$st progress=$pr"
puts "RESUME bit_exists=[file exists $bit]"
close_project
if {$st ne "write_bitstream Complete!"} { puts "RESUME-FAIL status=$st"; exit 3 }
puts "RESUME-DONE"

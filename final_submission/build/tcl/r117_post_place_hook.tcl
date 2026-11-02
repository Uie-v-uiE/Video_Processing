# 用途：implementation-stage hook (adopted cut C9).
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/tcl/r117_post_place_hook.tcl -- implementation-stage hook (adopted cut C9).
#
# Wired in by build/tcl/build_system_axigpio.tcl as
#   set_property STEPS.PLACE_DESIGN.TCL.POST <this file> [get_runs impl_1]
# so it runs exactly where the D1 fast-lane roll ran it: after place_design, before route_design.
#
# WHAT IT DOES: force-replicate ONE broadcast net, `u_pl/u_row/hi_reg_0[0]`.
# WHY (all from reports, see report/timing/limit_audit_r116.md and build/evidence/r117_d0/):
#   r116's worst clk_fpga_0 setup path is 1.976 ns slack with data 7.355 ns, of which
#   route = 6.871 ns (93.419 %) and 5.690 ns of that sits on THIS net alone
#   (report row `net (fo=269, routed) 5.690  u_pl/u_row/hi_reg_0[0]`), whose 239 pins live
#   in u_pl/u_row and are spread over 99 distinct tiles. Root-cause label: FANOUT.
#   Control roll A (no phys_opt) reproduced r116's official roster digit for digit, so the
#   single-variable comparison is legitimate; noise_ns on this tool = 0.000 (r115 blank rolls).
# WHAT THE MEASURED WIN WAS (build/evidence/r117_repl3/b_console.txt, same opt.dcp, one variable):
#   clk_fpga_0 1.976 -> 2.009 (rel margin 19.76 -> 20.09 %), endpoints 15721 -> 15731 (+10 = the
#   10 replica cells, which is the closure equation that proves the mechanism moved);
#   clkout0_1 3.698 -> 3.885; sys_clk 14.876 -> 15.174; eth_rxc UNCHANGED at -0.846/-0.870;
#   all four hold numbers unchanged (0.053 / 0.059 / 0.222 / -0.870) -> no hold erosion.
#
# NOTHING HERE LOOSENS A CONSTRAINT (H1): it adds 10 flip-flops and re-assigns loads.
set hook_net  {u_pl/u_row/hi_reg_0[0]}
set hook_load u_pl/u_row/hi_reg_4_i_1/I3

set byname [get_nets -quiet $hook_net]
set byload [get_nets -quiet -of [get_pins -quiet $hook_load]]
set nb [expr {[llength $byname] ? [get_property NAME $byname] : "EMPTY"}]
set nl [expr {[llength $byload] ? [get_property NAME $byload] : "EMPTY"}]
set pb [expr {[llength $byname] ? [llength [get_pins -quiet -of $byname]] : 0}]
puts "R117HOOK byname=$nb byload=$nl pins_before=$pb"

# Two independent lookups must name the same object. If they do not, the net was renamed by this
# run's synthesis and replicating "whatever matches the string" would silently change WHAT the cut
# is aimed at -- so this aborts the run instead of continuing with a different meaning
# (prompt H4/G12: a report that does not match the tree is worse than no report).
if {[llength $byname] == 0 || [llength $byload] == 0 || $nb ne $nl} {
    error "R117HOOK-REFUSE net identity failed (byname=$nb byload=$nl) -- cut C9 cannot be attributed"
}

# FIX 2026-10-04 04:01 (ISSUES #327): the first version of these two lines read
#   set e no-error ; catch {phys_opt_design ...} e ; if {$e ne "no-error"} { error ... }
# Tcl's `catch var` puts the RETURN CODE in var (0 on success), not a sentinel string, so the
# successful phys_opt run looked like a failure and `error` killed the whole official impl run --
# after the cut had already worked (runme.log: pins_before=239 -> pins_after=1, replica_cells=10).
# A bookkeeping bug in a checker must not be allowed to destroy the thing it measures, so the
# idiom is now the documented one: capture rc and msg separately and gate on rc.
set rc [catch {phys_opt_design -force_replication_on_nets $byname} emsg]
set pins_after [expr {[llength [get_nets -quiet $nb]] ? [llength [get_pins -quiet -of [get_nets -quiet $nb]]] : 0}]
set reps [llength [get_cells -quiet -hier *replica*]]
puts "R117HOOK phystopt_rc=$rc msg=$emsg net=$nb pins_after=$pins_after replica_cells=$reps"
if {$rc != 0} { error "R117HOOK-FAILED phys_opt_design rc=$rc: $emsg" }

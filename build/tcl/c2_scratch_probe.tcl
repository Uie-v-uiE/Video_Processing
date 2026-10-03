# build/tcl/c2_scratch_probe.tcl —— 读 C2 证伪件的那一滚产物（丢弃副本树，不碰主树）
#
# 跑法（在**主仓库根**下）：
#   VP_VIVADO_BIN=/d/Software/Vivado/2025.2.1/Vivado/bin \
#   vivado -mode batch -nojournal -source build/tcl/c2_scratch_probe.tcl
# 输入是副本树实现完成的 DCP；输出全部落在 build/evidence/r115_c2_scratch/（被跟踪，负结果也留）。
# 判据按 docs/timing/rgmii_window_model.md §4 的 S1..S5 预先登记，这里只**出数**，判定在差分脚本与文档里做。
# 运行时 puts 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep，栽过两次）。
set scratch [file normalize [file join [file dirname [info script]] .. .. .. c2_scratch_1003]]
set dcp [file join $scratch "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
set out [file normalize [file join [file dirname [info script]] .. evidence r115_c2_scratch]]
if {![file exists $dcp]} {
    # 名字可能随 BD 工程名变，兜一次底：把 impl_1 目录里现有的 *_routed.dcp 都念出来再退出
    set dir [file dirname $dcp]
    puts "REFUSE: no such dcp: $dcp"
    if {[file isdirectory $dir]} {
        foreach f [glob -nocomplain -directory $dir *.dcp] { puts "DCP-CANDIDATE $f" }
    } else { puts "NO-SUCH-DIR $dir" }
    exit 1
}
file mkdir $out
puts "PROBE dcp=$dcp out=$out"
open_checkpoint $dcp

# S5：钟对象清单（派生钟的**实名**必须在这里出现，不许靠记忆写）
# ⚠ 时钟对象只有这些属性（2026-10-03 实测：CLASS FILE_NAME INPUT_JITTER IS_GENERATED IS_PROPAGATED
#   IS_USER_GENERATED IS_VIRTUAL LINE_NUMBER MODULE NAME PERIOD SOURCE_PINS SYSTEM_JITTER WAVEFORM WEIGHT）
#   ⇒ **没有 MASTER**，写它会当场 [Common 17-54]。派生关系用 IS_GENERATED + FILE_NAME/LINE_NUMBER 定位。
set cl [get_clocks -quiet *]
puts "CLOCKS_N=[llength $cl]"
foreach c $cl {
    puts [format "CLKROW name=%s period=%s generated=%s xdc=%s:%s" \
        [get_property NAME $c] [get_property PERIOD $c] \
        [get_property IS_GENERATED $c] [get_property FILE_NAME $c] [get_property LINE_NUMBER $c]]
}

report_timing_summary -file [file join $out timing_summary.txt]
catch {check_timing -verbose -file [file join $out check_timing_verbose.txt]} ct
puts "CHECKTIMING_ERR=$ct"
catch {report_clock_networks -file [file join $out clock_networks.txt]} cn
puts "CLOCKNET_ERR=$cn"
catch {report_clock_utilization -file [file join $out clock_utilization.txt]} cu
puts "CLOCKUTIL_ERR=$cu"
catch {report_utilization -file [file join $out utilization.txt]} ur
puts "UTIL_ERR=$ur"
catch {report_methodology -file [file join $out methodology.txt]} rm
puts "METHODOLOGY_ERR=$rm"
catch {report_exceptions -file [file join $out exceptions.txt]} re
puts "EXC_ERR=$re"

# S1/S3 的逐域读数：eth_rxc 的 setup 与 hold 各一条（落点必须是 u_iddr_*，否则窗没进检查）
foreach {dt tag} {max setup min hold} {
    set f [file join $out "rt_eth_rxc_${tag}.txt"]
    set e no-error
    if {[catch {report_timing -delay_type $dt -from [get_clocks eth_rxc] -to [get_clocks eth_rxc] \
                     -nworst 1 -max_paths 3 -file $f} e]} {
        puts "RT_ERR tag=$tag err=$e"
    } else { puts "RT_OK tag=$tag exists=[file exists $f]" }
}
# 设计级 hold 头条（S1 的 WHS 与 I/O 失败端点数从这里取，名册差分也用它）
report_timing_summary -delay_type min -file [file join $out summary_hold.txt]
report_timing_summary -delay_type max -file [file join $out summary_setup.txt]
puts "PROBEDONE"
exit 0

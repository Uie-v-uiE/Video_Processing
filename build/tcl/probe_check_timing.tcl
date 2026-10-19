# build/tcl/probe_check_timing.tcl -- read-only: the current build's own check_timing -verbose.
# Why: build/roster/roster_r118.tsv's io_unconstrained_ports column is defined as "check_timing 的
#   HIGH 两类之和（端口对象单位）" (see that file's header), and the only artifact behind it was
#   r114's. A roster for r132 cannot be produced without re-running it on the routed dcp.
# Read-only: opens the checkpoint, prints two reports, never writes the design or the runs dir.
# Usage: VP_VIVADO_BIN=<dir>/vivado -mode batch -nojournal -source build/tcl/probe_check_timing.tcl
#        [VP_DCP=<path>] [VP_OUT=<file>]
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {[info exists ::env(VP_DCP)] && $::env(VP_DCP) ne ""} { set dcp $::env(VP_DCP) }
set out [file join $root "build/evidence/r132_check_timing_verbose.txt"]
if {[info exists ::env(VP_OUT)] && $::env(VP_OUT) ne ""} { set out $::env(VP_OUT) }
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp
# check_timing -verbose 的正文是**打印**出来的，返回值是空串（2026-10-20 实测：
# puts $fh [check_timing -verbose] 只写出 196 字节的头，CATCH: 为空 ⇒ 名册表那列 ROSTERFAIL）。
# 仓库里另外两支探针（build/tcl/c2_scratch_probe.tcl:42、build/tcl/mf114_roll.tcl:176）用的是
# -file 这一形，照它来；写不出正文就报 PROBE-EMPTY 并以 4 收尾，不交一份空件给下游。
set tmp "${out}.raw"
catch {check_timing -verbose -file $tmp} err
if {![file exists $tmp] || [file size $tmp] == 0} { puts "PROBE-EMPTY rc=0 err=$err"; exit 4 }
set rh [open $tmp r]; set body [read $rh]; close $rh
file delete -force $tmp
set fh [open $out w]
puts $fh "# source dcp: $dcp"
puts $fh "# command: check_timing -verbose   (run read-only on the routed design; body via -file)"
puts $fh "# body bytes=[string length $body] CATCH:$err"
puts $fh $body
flush $fh
close $fh
if {![regexp {There are \d+ input ports with no input delay specified} $body]} {
  puts "PROBE-NO-PATTERN 正文里没有名册表要的那两句"; exit 4
}
puts "CHECKTIMING-WRITTEN $out bytes=[file size $out]"
exit 0

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
set fh [open $out w]
puts $fh "# source dcp: $dcp"
puts $fh "# command: check_timing -verbose   (run read-only on the routed design)"
flush $fh
catch {puts $fh [check_timing -verbose]} err
puts $fh "CATCH:$err"
flush $fh
close $fh
puts "CHECKTIMING-WRITTEN $out"
exit 0

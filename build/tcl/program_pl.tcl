# build/tcl/program_pl.tcl — scan the JTAG chain and program build/system.bit into the PL
#
#   vivado -mode batch -nojournal -source build/tcl/program_pl.tcl
#
# hw_server must be reachable (Vivado's Auto Connect starts one; or run
# `hw_server` manually).  Order matters: bring the PS up first
# (ps_jtag_boot.tcl), then program the PL, then write the AXI GPIO (set_src.tcl).

set root [file normalize [file join [file dirname [info script]] .. ..]]
# VP_BIT 可以指向别处的位流（隔离滚一轮的产物拿去做板上对照时用），不设就是 build/system.bit
set bit  [file join $root build system.bit]
if {[info exists ::env(VP_BIT)] && $::env(VP_BIT) ne ""} { set bit [file normalize $::env(VP_BIT)] }
if {![file exists $bit]} { puts "NO BIT $bit"; exit 1 }

open_hw_manager
connect_hw_server -allow_non_jtag
puts "URL=[current_hw_server]"
open_hw_target
puts "=== DEVICES ==="
foreach d [get_hw_devices] { puts "  [get_property NAME $d] PART=[get_property PART $d]" }

set dev [lindex [get_hw_devices -filter {PART =~ "xc7z020*"}] 0]
if {$dev eq ""} { puts "NO xc7z020 IN CHAIN"; close_hw_target; exit 1 }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED $dev <- $bit"
close_hw_target
close_hw_manager
exit 0

# build/tcl/probe_owner_fanout.tcl -- read-only: who does u_arb/owner_eth_reg drive, and how wide?
# Why: r132's worst clk_fpga_0 setup path starts at u_pl/u_arb/owner_eth_reg/C and is 1 logic level
#      with 92.7 % routing, so the candidate cut is "replicate this flag". The replication hook needs
#      BOTH the net name and one load pin, and it aborts unless two independent lookups agree --
#      so read them from the netlist instead of guessing.
# Usage: VP_VIVADO_BIN=<bin>/vivado -mode batch -nojournal -source build/tcl/probe_owner_fanout.tcl
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set drv [get_pins -quiet -hier -filter {NAME =~ *u_arb/owner_eth_reg*/Q}]
puts "OWNERDRV pins=[llength $drv]"
foreach p $drv { puts "OWNERDRV|pin=$p" }
set nets [get_nets -quiet -of $drv]
foreach n $nets {
  set lo [get_pins -quiet -of $n -filter {DIRECTION == IN}]
  puts "OWNERNET|name=[get_property NAME $n]|loads=[llength $lo]"
  set i 0
  foreach p $lo {
    incr i
    if {$i > 6} break
    puts "  LOAD|$p"
  }
}
# also the other two owner flags in the same arbiter, in case the tool renamed them
foreach q {owner_sd_reg owner_test_reg owner_reg} {
  set d2 [get_pins -quiet -filter {NAME =~ *u_arb/*$q*/Q}]
  puts "OWNERPEERS|probe=$q|pins=[llength $d2]"
}
close_design
exit 0

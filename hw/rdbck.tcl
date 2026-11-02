# board/rdbck.tcl — xsdb read-only AXI GPIO_0 readback
# Used by board/scripts/board_flash.sh after the three-step JTAG chain.
# The old copy was pruned from the package while board_flash.sh still called it,
# and xsdb returns 0 for a missing script, so the readback step looked green.
connect
targets -set -filter {name =~ "*APU*"}
puts "GPIO@0x41200000 = [mrd -force 0x41200000]"
exit

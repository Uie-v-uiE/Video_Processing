# scratch probe: discover the Vivado Tcl shapes needed to program a QSPI cfgmem
# run: vivado.bat -mode batch -nojournal -log probe_cfgmem.log -source probe_cfgmem.tcl
open_hw
set rc [catch {connect_hw_server -url localhost:3121} err]
puts "CONNECT rc=$rc err=$err"
set r2 [catch {open_hw_target} err2]
puts "TARGET rc=$r2 err=$err2"
puts "DEVICES: [get_hw_devices]"
set pl [get_hw_devices xc7z020*]
puts "PL_LIST: $pl"
if {$pl ne ""} {
    current_hw_device [lindex $pl 0]
    set r3 [catch {refresh_hw_device -update_hw_probes false [current_hw_device]} e3]
    puts "REFRESH rc=$r3"
    puts "CURDEV: [current_hw_device]"
    set r4 [catch {get_cfgmems *} cm]
    puts "GET_CFGMEMS rc=$r4 n=[expr {$r4==0 ? [llength $cm] : -1}]"
    set r5 [catch {get_cfgmem_parts *} cmp)
    puts "GET_CFGMEM_PARTS rc=$r5"
    set r6 [catch {get_hw_busbars} bb]
    puts "BUSBARS rc=$r6 list=$bb"
    set r7 [catch {get_cfgmems *25q256*} m2]
    puts "MATCH25Q256 rc=$r7 list=$m2"
    set r8 [catch {get_cfgmems *w25q*} m3]
    puts "MATCHW25Q rc=$r8 list=$m3"
}
close_hw_target
disconnect_hw_server
exit 0

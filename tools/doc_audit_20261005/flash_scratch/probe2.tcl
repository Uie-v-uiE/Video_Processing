open_hw
catch {connect_hw_server -url localhost:3121}
catch {open_hw_target}
current_hw_device [get_hw_devices xc7z020_1]
refresh_hw_device -update_hw_probes false [current_hw_device]
puts "CMDCMD: [info commands *cfgmem*]"
puts "PROGP: [info commands *program_hw*]"
set r1 [catch {get_cfgmem_parts *} m1]
puts "PARTS rc=$r1 n=[expr {$r1==0?[llength $m1]:-1}]"
set r2 [catch {get_cfgmem_parts *25q256*} m2]
puts "P25Q256 rc=$r2 list=$m2"
set r3 [catch {get_hw_busbars} bb]
puts "BUSBARS rc=$r3 n=[expr {$r3==0?[llength $bb]:-1}]"
exit 0

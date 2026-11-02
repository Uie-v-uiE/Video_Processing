open_hw
catch {connect_hw_server -url localhost:3121}
catch {open_hw_target}
current_hw_device [get_hw_devices xc7z020_1]
set p0 [lindex [get_cfgmem_parts *25q256*] 0]
puts "P0 $p0"
puts "PROPS [lsort [list_property $p0]]"
foreach pr [list_property $p0] { puts "VAL $pr = [get_property $pr $p0]" }
set all [get_cfgmem_parts *]
puts "ALLN [llength $all]"
exit 0

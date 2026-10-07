open_hw
catch {connect_hw_server -url localhost:3121}
catch {open_hw_target}
current_hw_device [get_hw_devices xc7z020_1]
set n 0
foreach p [get_cfgmem_parts *] { if {[string match *zynq7000* [get_property COMPATIBLE_PARTS $p]]} { incr n; if {$n <= 40} { puts "OK7 $p" } } }
puts "TOTAL_ZYNQ7000 $n"
foreach p [get_cfgmem_parts *25q256*] { if {[string match *zynq7000* [get_property COMPATIBLE_PARTS $p]]} { puts "WINBOND256 $p" } }
foreach p [get_cfgmem_parts *n25q*] { if {[string match *zynq7000* [get_property COMPATIBLE_PARTS $p]]} { puts "MICRON_N25Q $p" } }
exit 0

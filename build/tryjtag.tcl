open_hw_manager
catch {connect_hw_server -allow_non_jtag -url localhost:3121} e
puts "CONN: $e"
puts "=== TARGETS ==="
foreach t [get_hw_targets] { puts "T $t  DESC=[get_property DESC $t]  STATUS=[get_property STATUS $t]" }
catch {open_hw_target} e2
puts "OPEN: $e2"
foreach d [get_hw_devices] { puts "D $d [get_property PART $d]" }
catch {close_hw_target}
catch {disconnect_hw_server}
exit 0

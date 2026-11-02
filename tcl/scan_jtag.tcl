# List JTAG devices
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
puts "=== TARGETS ==="
foreach t [get_hw_targets] { puts "  $t" }
puts "=== DEVICES ==="
foreach d [get_hw_devices] {
  puts "  $d  PART=[get_property PART $d]  IDCODE=[get_property IDCODE $d]"
}

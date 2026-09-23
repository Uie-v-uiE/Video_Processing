# Program FPGA with JTAG (select xc7z020, not arm_dap)
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build video_pipeline.bit]

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
if {$dev eq ""} {
  puts "ERROR: xc7z020 not found. Devices: [get_hw_devices]"
  exit 1
}
current_hw_device $dev
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAMMED $dev with $bit"


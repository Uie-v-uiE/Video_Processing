# Program system.bit (PL+PS netlist)
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build system.bit]
if {![file exists $bit]} {
  set bit [file join $root build video_pipeline.bit]
}
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
puts "PROGRAMMED $dev with $bit"
puts "Next: download PS elf via Vitis JTAG"


# Behavioral simulation via xsim CLI
# Usage: vivado -mode batch -source sim/run_sim.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root vivado_sim]
file mkdir $work
cd $work

set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
}

set tb_list {
  tb_proc_gray
  tb_timing
  tb_uart_decode_bits
  tb_rotate_mapper
  tb_rotate_window
  tb_zoom_mapper
  tb_crc32
  tb_sync_fifo
  tb_udp_reasm
  tb_udp_parser
  tb_eth_video
}
set tb_files {}
foreach tb $tb_list {
  lappend tb_files [file join $root sim ${tb}.v]
}

puts "INFO: xvlog ..."
if {[catch {exec xvlog {*}$rtl_files {*}$tb_files} msg]} {
  puts $msg
}

set pass 0
set fail 0
foreach tb $tb_list {
  puts "INFO: xelab $tb"
  if {[catch {exec xelab -debug typical $tb -s ${tb}_snap} msg]} {
    puts "ELAB-FAIL $tb"
    puts $msg
    incr fail
    continue
  }
  puts "INFO: xsim $tb"
  catch {exec xsim ${tb}_snap -R} msg
  puts $msg
  if {[string match "*FAIL*" $msg]} {
    puts "RESULT FAIL $tb"
    incr fail
  } elseif {[string match "*PASS*" $msg]} {
    puts "RESULT PASS $tb"
    incr pass
  } else {
    puts "RESULT UNKNOWN $tb"
    incr fail
  }
}

puts "SIM-SUMMARY pass=$pass fail=$fail"
puts "SIM-FINISHED"


connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
puts "GROUP1:"
catch {rrd cp15 1} r1; puts $r1
puts "HELP_RWR:"
catch {help rwr} h; puts $h
exit

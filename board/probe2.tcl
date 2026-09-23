connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
puts "CP15_DUMP:"
catch {rrd cp15} r
puts $r
puts "HELP:"
catch {help wrd} h
puts $h
exit

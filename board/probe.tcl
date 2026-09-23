connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
puts "REGS:"
catch {rrd} r
puts $r
exit

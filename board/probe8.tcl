connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
puts "UND_LR: [rrd und lr]"
puts "UND_SPSR: [rrd und spsr]"
puts "MON_LR: [rrd mon lr]"
puts "ABT_LR: [rrd abt lr]"
puts "CPSR: [rrd cpsr]"
exit

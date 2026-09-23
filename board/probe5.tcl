connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
puts "GROUPS: [rrd]"
foreach g {sys cpsr usr} { puts "G($g): [catch {rrd $g} vv err] -> $vv" }
exit

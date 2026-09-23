connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
foreach q {cpacr "cp15 cpacr" "cp15 1 cpacr"} {
  puts "TRY {$q} => [catch {rrd $q} v err] : $v"
}
puts "G1: [rrd cp15 1]"
catch {rwr cpacr 0x00300000} w1
puts "WRITE_TRY1: [expr {$w1 eq {} ? {ok} : $w1}]"
puts "G1_AFTER: [rrd cp15 1]"
exit

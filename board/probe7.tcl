connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
set sc [expr {[rrd cp15 sctlr] | 0x400}]
foreach cmd {
  "rwr cp15 cpacr 0x00300000"
  "rwr cp15 sctlr $sc"
} { puts "TRY: $cmd => [catch {uplevel 1 $cmd} ee] [expr {$ee eq {} ? {ok} : $ee}]" }
puts "AFTER: [rrd cp15 1]"
exit

connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e
foreach form {
  {rwr cp15 1 cpacr 0x00300000}
  {rwr "cp15 1" cpacr 0x00300000}
  {rwr cp15.cpacr 0x00300000}
  {putregs cp15 1 cpacr 0x00300000}
} { set cmd $form; puts "TRY: $cmd => [catch {uplevel 1 $cmd} ee] [expr {$ee eq {} ? {ok} : $ee}]" }
puts "NOW: [rrd cp15 1]"
exit

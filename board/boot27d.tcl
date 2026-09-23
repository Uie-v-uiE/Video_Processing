connect
proc okmsg {v} { if {$v eq ""} { return "ok" } ; return $v }
targets -set 1
catch {rst -system} e; puts "RST: [okmsg $e]"
after 2500
source {D:/Xilinx/Prj/pro/Video_Processing/build/ps7_init.tcl}
catch {ps7_init} e2; puts "PS7_INIT: [okmsg $e2]"
catch {ps7_post_config} e3; puts "POST_CFG: [okmsg $e3]"
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
catch {stop} e4
puts "CPACR_BEFORE: [format %08x [rrd cp15 1 cpacr]]"
rwr cp15 1 cpacr 0x00300000
set sc [expr {[rrd cp15 1 sctlr] | 0x400}]
rwr cp15 1 sctlr $sc
puts "CPACR_AFTER: [format %08x [rrd cp15 1 cpacr]] SCTLR_AFTER: [format %08x [rrd cp15 1 sctlr]]"
catch {dow {D:/Xilinx/Prj/pro/Video_Processing/build/ps_app.elf}} e5; puts "DOW: [okmsg $e5]"
catch {con} e6; puts "CON: [okmsg $e6]"
after 5000
catch {stop} e7
puts "PC_AFTER_5S: [rrd pc]"
catch {con} e8
puts "FLOW_DONE"
exit

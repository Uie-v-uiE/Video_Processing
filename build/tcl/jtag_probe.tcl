# build/tcl/jtag_probe.tcl —— 只回答一件事：JTAG 这条路现在能不能读 PS 侧地址。
#   cmd //c "<Vitis>/bin/xsdb.bat build/tcl/jtag_probe.tcl"
# 为什么要有它：geom_check.mjs 报"读不到 CFG_DATA0(0x41220000)"，但那句到底是 **通路断了**、
#   **目标选错** 还是 **端口被另一个会话占着**，从它自己的输出分不开（同一族教训：先确认尺子在说哪一段）。
#   目标选择那一行照抄 build/tcl/ps_app_reload.tcl:21 的写法，不自己发明语法。
catch {connect -host localhost -port 3121} ce
puts "CONNECT: $ce"
puts "--- targets ---"
catch {targets} tr
puts $tr
puts "--- pick A9 #0 ---"
catch {targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}} pe
puts "PICK: $pe"
catch {stop} s0
after 150
catch {mrd -force 0x41220000 1} v err
catch {puts "STOPPED: $s0"}
catch {con} c1
puts "MRD=$v ERR=$err"

set root "D:/Xilinx/Prj/ADD/Video_Pipeline-main"
set work "$root/vivado_sim"
file mkdir $work
cd $work
set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
}
puts "INFO: xvlog zoom only"
if {[catch {exec xvlog {*}$rtl_files [file join $root sim tb_zoom_mapper.v]} msg]} {
  puts $msg
}
puts "INFO: xelab"
if {[catch {exec xelab -debug typical tb_zoom_mapper -s tb_zoom_mapper_snap} msg]} {
  puts $msg
  exit 1
}
puts "INFO: xsim"
catch {exec xsim tb_zoom_mapper_snap -R} msg
puts $msg
if {[string match "*PASS tb_zoom_mapper*" $msg]} {
  puts "RESULT PASS tb_zoom_mapper"
} else {
  puts "RESULT FAIL tb_zoom_mapper"
}
puts "ZOOM-SIM-DONE"

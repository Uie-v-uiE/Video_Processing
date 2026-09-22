set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root vivado_sim]
file mkdir $work
cd $work
set rtl {}
foreach f {
  src/rtl/eth/axi_frame_saver.v
  src/rtl/axi/axi_frame_writer.v
} {
  lappend rtl [file join $root $f]
}
lappend rtl [file join $root sim tb_saver_writer.v]
catch {exec xvlog {*}$rtl} msg
puts $msg
catch {exec xelab -debug typical tb_saver_writer -s tb_saver_writer_snap} msg
puts $msg
catch {exec xsim tb_saver_writer_snap -R} msg
puts $msg

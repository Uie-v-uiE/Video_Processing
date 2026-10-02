# OOC utilization probe for ONE module (read-only w.r.t. the repo: runs inside a copy tree).
# tclargs: <dir_with_the_.v_files> <top_module> <out_report>
# Labels here must stay ASCII: Vivado Tcl reads this file under the system codepage, and a CJK
# puts label breaks `$(...)` in the caller and turns the console binary for grep.
set src [lindex $argv 0]
set top [lindex $argv 1]
set out [lindex $argv 2]
set files [glob -directory $src -type f *.v]
puts "OOC-READ [llength $files] files from $src top=$top"
read_verilog -quiet $files
synth_design -mode out_of_context -top $top -part xc7z020clg484-2
report_utilization -file $out
puts "OOC-DONE $out"

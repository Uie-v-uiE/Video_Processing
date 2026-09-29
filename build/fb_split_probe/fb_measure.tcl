# 一次综合一个 top（FB_TOP 给名字，FB_VLOG 给文件），念出 tile / LUT / FF 三个数。
# tile 数是判据；LUT/FF 是这次"换"的代价，两边都要看见才算数。
set part xc7z020clg484-2
set top $::env(FB_TOP)
set vlog $::env(FB_VLOG)
read_verilog $vlog
synth_design -top $top -part $part
set rpt [report_utilization -return_string]
set tiles 0; set cells 0; set lut 0; set ff 0
if {[regexp -line {^\| *Block RAM Tile *\| *([0-9]+)} $rpt _ n1]} { set tiles $n1 }
if {[regexp -line {^\| *RAMB36/FIFO\* *\| *([0-9]+)} $rpt _ n2]}   { set cells $n2 }
if {[regexp -line {^\| *CLB LUTs\*? *\| *([0-9]+)} $rpt _ n3]}     { set lut $n3 }
if {[regexp -line {^\| *LUT as Memory *\| *([0-9]+)} $rpt _ n4]}   { set lut $lut }
if {[regexp -line {^\| *CLB Registers *\| *([0-9]+)} $rpt _ n5]}   { set ff $n5 }
if {[regexp -line {^\| *Register as Flip Flop *\| *([0-9]+)} $rpt _ n6]} { set ff $n6 }
puts "RESULT $top tile=$tiles ramb36fifo=$cells lut=$lut ff=$ff"
set fh [open "fb_result_$top.txt" w]
puts $fh "RESULT $top tile=$tiles ramb36fifo=$cells lut=$lut ff=$ff"
close $fh

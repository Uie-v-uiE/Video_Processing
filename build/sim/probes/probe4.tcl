# 用途：第二个读口要不要额外 BRAM
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/sim/probes/probe4.tcl — 第二个读口要不要额外 BRAM？（见 dpfb.v 头部的问题）
set dir [file normalize [file join [file dirname [info script]] .]]
create_project dpfbtest $dir -part xc7z020clg484-2 -force
add_files [file join $dir dpfb.v]
update_compile_order -fileset sources_1

foreach v {dp_v0 dp_v1 dp_v2 dp_v3} {
    if {[catch {synth_design -top $v -part xc7z020clg484-2 -mode out_of_context} err]} {
        puts "PROBE $v SYNTH_FAIL : $err"
        continue
    }
    set remb [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
    set remb18 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
    set lut [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
    set ff  [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
    puts "PROBE $v RAMB36=$remb RAMB18=$remb18 LUT=$lut FF=$ff"
}
puts "PROBE DONE"

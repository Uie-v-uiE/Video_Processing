# tmp_ramtest/probe2.tcl — 逐个综合 frame_buffer 变体，只看 RAMB36/RAMB18/LUT/FF 数
set dir [file normalize [file join [file dirname [info script]] .]]
create_project fbtest $dir -part xc7z020clg484-2 -force
add_files [file join $dir fbtest.v]
update_compile_order -fileset sources_1
foreach v {fb_v5 fb_v0} {
    if {[catch {synth_design -top $v -part xc7z020clg484-2 -mode out_of_context} err]} {
        puts "FBPROBE $v SYNTH_FAIL"
        continue
    }
    set b36 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
    set b18 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
    set lut [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
    set ff  [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
    puts "FBPROBE $v RAMB36=$b36 RAMB18=$b18 LUT=$lut FF=$ff"
}
puts "FBPROBE DONE"

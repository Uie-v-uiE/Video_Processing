# tmp_ramtest/probe.tcl — per-variant inference probe.
# Which coding shape lets Vivado map a 512x64 packer FIFO onto distributed RAM?
set dir [file normalize [file join [file dirname [info script]] .]]
create_project ramtest $dir -part xc7z020clg484-2 -force
add_files [file join $dir ramtest.v]
update_compile_order -fileset sources_1

foreach v {fifo_v1 fifo_v2 fifo_v3 fifo_v4 fifo_v5} {
    if {[catch {synth_design -top $v -part xc7z020clg484-2 -mode out_of_context} err]} {
        puts "PROBE $v SYNTH_FAIL"
        continue
    }
    set ff   [llength [get_cells -hierarchical -filter {REF_NAME =~ FD*}]]
    set lutm [llength [get_cells -hierarchical -filter {REF_NAME =~ RAM*}]]
    set remb [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]]
    puts "PROBE $v FF=$ff LUTRAM=$lutm BRAM=$remb"
}
puts "PROBE DONE"

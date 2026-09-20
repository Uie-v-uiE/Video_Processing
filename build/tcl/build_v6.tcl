# build/tcl/build_v6.tcl — V6.x design → bit + XSA + reports, from this repo.
#
#   vivado -mode batch -nojournal -log build/build_v6.log -source build/tcl/build_v6.tcl
#   vivado -mode batch -source build/tcl/build_v6.tcl -tclargs D:/path/to/existing.xpr
#
# Without an argument it creates the block-design project first
# (build_system_axigpio.tcl: PS7 + M_AXI_GP0 + AXI GPIO + external HP0), then
# makes sure the source fileset is exactly src/rtl/**, then runs synthesis,
# implementation and bitstream, and writes:
#   build/system.bit  build/system.xsa
#   build/timing_summary.rpt  build/utilization.rpt  build/cdc.rpt  build/methodology.rpt
#
# Provenance: the shipped build/system.bit was produced by this same flow on the
# author's machine against a pre-existing .xpr (equivalent to passing one here).
# V6 points the design at src/rtl/**, drops dangling hand-off paths, dedupes the
# XDC, and clears the stale incremental checkpoint.

set root     [file normalize [file join [file dirname [info script]] .. ..]]
set out      [file join $root build]
set part     xc7z020clg484-2
set xpr_arg  [expr {[llength $argv] > 0 ? [lindex $argv 0] : {}}]
set proj_dir [file join $root vivado_system]
set xpr      [file join $proj_dir zynq_video_sys.xpr]
file mkdir $out

if {$xpr_arg ne ""} {
    set xpr [file normalize $xpr_arg]
    open_project $xpr
} elseif {![file exists $xpr]} {
    close_project
    source [file join $root build tcl build_system_axigpio.tcl]
    open_project $xpr
} else {
    open_project $xpr
}
set fs [current_fileset]

# --- V6 source swap: the design must come from src/rtl/** -------------------
# The hand-off project referenced rtl trees that no longer exist; remove any
# source whose path is outside src/rtl, then (re)add the repo copy.
set stale [get_files -of_objects $fs -filter {NAME =~ *.v}]
set removed 0
foreach f $stale {
    set p [file normalize [get_property NAME $f]]
    if {[string first [file normalize [file join $root src rtl]] $p] != 0} {
        remove_files $f
        incr removed
    }
}
puts "OUTSIDE_SRC_RTL_REMOVED=$removed"

set added 0
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
    foreach f [glob -nocomplain [file join $root src rtl $d *.v]] {
        if {[get_files -quiet [file tail $f] -of_objects $fs] eq ""} {
            add_files -norecurse $f
            incr added
        }
    }
}
foreach f [list [file join $root src rtl top pl_video_top.v] [file join $root src rtl top system_top.v]] {
    if {[get_files -quiet [file tail $f] -of_objects $fs] eq ""} { add_files -norecurse $f; incr added }
}
puts "ADDED=$added"

# --- constraints: exactly one active rk_zynq7020.xdc ------------------------
set xdc [file join $root src constraints rk_zynq7020.xdc]
foreach f [get_files -of_objects [get_filesets constrs_1]] {
    if {[file tail [get_property NAME $f]] eq "rk_zynq7020.xdc"
        && [file normalize [get_property NAME $f]] ne [file normalize $xdc]} {
        puts "DROP_DUP_XDC [get_property NAME $f]"
        remove_files $f
    }
}
if {[get_files -quiet rk_zynq7020.xdc -of_objects [get_filesets constrs_1]] eq ""} {
    add_files -fileset constrs_1 -norecurse $xdc
}
set_property target_constrs_file $xdc [get_filesets constrs_1]

set_property top system_top $fs
update_compile_order -fileset $fs
puts "TOP=[get_property top $fs] PART=[get_property part [current_project]]"
foreach f [lsort [get_property NAME [get_files -of_objects $fs]]] { puts "  SRC $f" }
if {[info exists ::env(V6_DRY)]} { puts "DRY OK"; close_project; exit 0 }

# the incremental checkpoint belongs to a deleted tree
set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "BUILD FAILED at synthesis"; close_project; exit 1 }

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "BUILD FAILED at implementation"; close_project; exit 1 }

set bit [lindex [glob -nocomplain [file join $proj_dir zynq_video_sys.runs impl_1 system_top.bit]] 0]
file copy -force $bit [file join $out system.bit]
write_hw_platform -fixed -include_bit -force -file [file join $out system.xsa]
puts "BIT: [file join $out system.bit]"
puts "XSA: [file join $out system.xsa]"

catch {open_run impl_1}
catch {report_timing_summary -file [file join $out timing_summary.rpt]}
catch {report_utilization     -file [file join $out utilization.rpt]}
catch {report_cdc             -file [file join $out cdc.rpt]}
catch {report_methodology     -file [file join $out methodology.rpt]}
catch {close_project}
puts "BUILD OK"
exit 0

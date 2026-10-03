set root [file normalize [file join [file dirname [info script]] .. ..]]
open_project [file join $root vivado_system zynq_video_sys.xpr]
set r [get_runs impl_1]
foreach p {STEPS.PLACE_DESIGN.TCL.POST STEPS.PLACE_DESIGN.IS_ENABLED STEPS.PLACE_DESIGN.TCL.PRE} {
    set e no-error
    set v ""
    catch {set v [get_property $p $r]} e
    puts "PP_PROP $p rc=$e value=$v"
}
exit 0

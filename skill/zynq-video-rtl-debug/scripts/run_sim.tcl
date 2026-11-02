# run_sim.tcl — self-contained xsim runner for the project_handoff workspace.
#
# Compiles rtl_base + rtl_fix + sim/tb_*.v (rtl_fix_v4 intentionally excluded)
# and runs each testbench, printing one RESULT line per TB.
#
# Usage (from the workspace root):
#   vivado.bat -mode batch -nojournal -log sim_work/xsim.log -source <this file>
# Env overrides:
#   SIM_WS   workspace root (default: derived from this script's location)
#   SIM_TB   space/comma list of TB module names to run (default: all sim/tb_*.v)
#   SIM_ONLY compile only, run no TB

set script_dir [file normalize [file dirname [info script]]]
if {[info exists ::env(SIM_WS)]} {
    set ws [file normalize $::env(SIM_WS)]
} else {
    set ws [file normalize [file join $script_dir .. .. .. ..]]
}

set base   [file join $ws rtl_base]
set fix    [file join $ws rtl_fix]
set simdir [file join $ws sim]
set work   [file join $ws sim_work]

puts "WS: $ws"
foreach d [list $base $fix $simdir] {
    if {![file isdirectory $d]} { puts "FATAL missing $d"; exit 1 }
}

# modules rtl_fix re-implements on top of base
set overridden {eth_udp_video_top.v frame_reasm.v axi_frame_saver.v}
# historical variants: not instantiated by the design, but they DO compile and
# tb_v5_saver exercises axi_frame_saver_burst, so keep them in the sim set
set excluded {}

file mkdir $work
cd $work
catch {exec cmd /c rmdir /s /q xsim.dir}

set rtl {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
    foreach f [glob -nocomplain [file join $base $d *.v]] {
        if {[lsearch -exact $overridden [file tail $f]] >= 0} { continue }
        lappend rtl $f
    }
}
foreach f [glob -nocomplain [file join $fix *.v]] {
    if {[lsearch -exact $excluded [file tail $f]] >= 0} { continue }
    lappend rtl $f
}

set tbs [glob -nocomplain [file join $simdir tb_*.v]]
puts "xvlog rtl=[llength $rtl] tb=[llength $tbs]"

set sources {}
foreach f [concat $rtl $tbs] { lappend sources [file normalize $f] }
if {[catch {eval exec xvlog $sources} msg]} {
    puts "XVLOG FAILED"
    puts $msg
    exit 1
}
puts "XVLOG OK"

if {[info exists ::env(SIM_ONLY)]} { exit 0 }

set want {}
if {[info exists ::env(SIM_TB)]} {
    foreach t [split [string map {, " "} $::env(SIM_TB)] " "] {
        if {$t ne ""} { lappend want $t }
    }
}
# 传给 xsim 的 plusargs，例如 SIM_ARGS="+W_LAT=0 +COPY_CYC=67200"
# （xsim 只认 --testplusarg key=value，不认裸的 +key=value）
set simargs {}
if {[info exists ::env(SIM_ARGS)]} {
    foreach a [split [string map {, " "} $::env(SIM_ARGS)] " "] {
        if {$a eq ""} { continue }
        lappend simargs --testplusarg [string map {+ ""} $a]
    }
}
puts "SIM_ARGS: $simargs"

foreach tf $tbs {
    set tb [file rootname [file tail $tf]]
    if {[llength $want] > 0 && [lsearch -exact $want $tb] < 0} { continue }
    puts "==== $tb ===="
    if {[catch {exec xelab -debug typical $tb -s $tb} msg]} {
        puts "RESULT $tb ELAB_FAIL"
        puts [lindex [split [string trim $msg] \n] end]
        continue
    }
    if {[catch {eval exec xsim $tb -R $simargs} msg]} { puts $msg }
    if {[info exists ::env(SIM_VERBOSE)]} {
        foreach line [split $msg \n] { puts "  | [string trim $line]" }
    }
    set hits {}
    foreach line [split $msg \n] {
        if {[string match *PASS* $line] || [string match *FAIL* $line]} {
            lappend hits [string trim $line]
        }
    }
    foreach h [lrange $hits end-9 end] { puts "  $h" }
    set verdict NO_ASSERT
    if {[llength $hits] > 0} {
        set verdict PASS
        foreach h $hits { if {[string match *FAIL* $h]} { set verdict FAIL; break } }
    }
    puts "RESULT $tb $verdict"
}
puts "SIM DONE"
exit 0

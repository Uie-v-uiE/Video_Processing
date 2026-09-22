# sim/run_sim.tcl — self-contained xsim runner for the competition repo layout.
#
# Compiles every RTL module under src/rtl plus every sim/tb_*.v, then runs each
# testbench and prints one RESULT line per TB.  Repo-relative: run it from anywhere.
#
#   vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl
#
# Env overrides:
#   SIM_TB    comma/space list of TB module names to run (default: all)
#   SIM_ONLY  set to 1 to compile only
#   SIM_VERBOSE  set to 1 to echo the whole simulation transcript
#   SIM_ARGS  plusargs for xsim, e.g. "+FULL" or "+W_LAT=0 +COPY_CYC=67200"
#
# History: this is the V6 runner.  The V5 tree used to live in rtl_base/ +
# rtl_fix/ with an `overridden` filter that kept the fixed copy of
# eth_udp_video_top.v / frame_reasm.v; in this layout those files are simply the
# fixed ones, so the filter is gone.  Superseded modules (axi_frame_saver.v,
# axi_frame_writer.v) stay in the tree and still have their own testbenches.

set ws [file normalize [file join [file dirname [info script]] ..]]
set rtl_dir [file join $ws src rtl]
set simdir  [file join $ws sim]
set work    [file join $ws sim_work]

puts "WS: $ws"
foreach d [list $rtl_dir $simdir] {
    if {![file isdirectory $d]} { puts "FATAL missing $d"; exit 1 }
}

file mkdir $work
cd $work
catch {exec cmd /c rmdir /s /q xsim.dir}

set rtl {}
foreach f [glob -nocomplain [file join $rtl_dir *.v]] { lappend rtl $f }
foreach d [glob -nocomplain -directory $rtl_dir *] {
    if {![file isdirectory $d]} { continue }
    foreach f [glob -nocomplain [file join $d *.v]] { lappend rtl $f }
    foreach s [glob -nocomplain [file join $d * *.v]] { lappend rtl $s }
}
set rtl [lsort -unique $rtl]

set tbs [lsort [glob -nocomplain [file join $simdir tb_*.v]]]
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
# xsim only accepts plusargs as --testplusarg key=value (a bare +key=value is rejected)
set simargs {}
if {[info exists ::env(SIM_ARGS)]} {
    foreach a [split [string map {, " "} $::env(SIM_ARGS)] " "] {
        if {$a eq ""} { continue }
        lappend simargs --testplusarg [string map {+ ""} $a]
    }
}
puts "SIM_ARGS: $simargs"

set npass 0
set nfail 0
foreach tf $tbs {
    set tb [file rootname [file tail $tf]]
    if {[llength $want] > 0 && [lsearch -exact $want $tb] < 0} { continue }
    puts "==== $tb ===="
    if {[catch {eval exec xelab {-debug typical} $tb -s $tb} msg]} {
        puts "RESULT $tb ELAB_FAIL"
        puts [lindex [split [string trim $msg] \n] end]
        incr nfail
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
    # NO_ASSERT 过去被计入 pass：一个"什么都没断言"的测试台不该算过。
    # 现在 NO_ASSERT 与 FAIL 同等对待（跑不到最后断言的台架以前会悄悄绿）。
    set verdict FAIL
    if {[llength $hits] > 0} {
        set verdict PASS
        foreach h $hits { if {[string match *FAIL* $h]} { set verdict FAIL; break } }
    } else {
        puts "  (没有 PASS/FAIL 断言行 —— 判为失败)"
    }
    puts "RESULT $tb $verdict"
    if {$verdict eq "FAIL" || $verdict eq "ELAB_FAIL"} { incr nfail } else { incr npass }
}
puts "SIM DONE pass=$npass fail=$nfail"
exit 0

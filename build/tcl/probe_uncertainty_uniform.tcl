# build/tcl/probe_uncertainty_uniform.tcl -- READ-ONLY "同一严口径"的 hold 体检，开 routed dcp，不改网表。
#   Why (2026-10-03, the user's "别只追最差那条，要看全局"): src/constraints/rk_zynq7020.xdc:50 carries exactly
#     ONE uncertainty line -- `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`. The other three domains
#     have none. That makes the four per-domain WHS numbers in the roster NOT comparable to each other:
#     eth_rxc's 0.050 already includes 0.800 ns of self-imposed pessimism while clk_fpga_0's 0.056 / clkout0_1's
#     0.059 / sys_clk's 0.133 include none. Saying "hold 四域都差不多" would be an artifact of the constraint,
#     not of the design.
#   This probe measures the answer instead of arguing about it: read each clock's worst hold BEFORE, apply the
#     same -hold band to every clock, read AFTER.
#   ⚠ What this is NOT: applying uncertainty after routing only re-computes margins, it does NOT re-run
#     place/route, so "after" is a *what-if under a uniform pessimism model*, not a re-optimised design. The
#     driver prints that sentence so nobody reads a negative number as "the board is broken".
#   Runtime labels stay ASCII (CJK in a Vivado puts label broke command substitution once).
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no such dcp: $dcp"; exit 1 }
open_checkpoint $dcp

set BAND 0.800
if {[info exists ::env(VP_BAND)]} { set BAND $::env(VP_BAND) }

set all [get_clocks -quiet *]
puts "CLOCKS_TOTAL=[llength $all]"
if {[llength $all] == 0} { puts "REFUSE: no clocks in the checkpoint"; exit 1 }

# ---- BEFORE: worst hold per clock ----
array set before {}
foreach c $all {
    set nm [get_property NAME $c]
    set slack "NA"
    catch {
        set p [get_timing_paths -delay_type min -nworst 1 -max_paths 1 -from $c -to $c]
        if {[llength $p] > 0} { set slack [get_property SLACK [lindex $p 0]] }
    }
    set before($nm) $slack
}

# ---- the single variable: one uniform -hold band on every clock ----
set nset 0
catch { set nset [llength [set_clock_uncertainty -hold $BAND [get_clocks *]]] } uerr
puts "UNC_APPLIED=$nset"
puts "UNC_ERR=$uerr"
if {$nset == 0} { puts "REFUSE: set_clock_uncertainty 一条也没落上（这一体检没有变量）"; exit 4 }
# 读回来：属性必须真在时钟上（"写了但工具没吃"是这类实验最常见的假绿）
set probeclk [lindex $all 0]
set readback ""
catch { set readback [get_property HOLD_UNCERTAINTY $probeclk] }
puts "UNC_READBACK clk=[get_property NAME $probeclk] hold_uncertainty=$readback"

# ---- AFTER ----
set nrow 0
set nneg 0
foreach c $all {
    set nm [get_property NAME $c]
    set slack "NA"
    catch {
        set p [get_timing_paths -delay_type min -nworst 1 -max_paths 1 -from $c -to $c]
        if {[llength $p] > 0} { set slack [get_property SLACK [lindex $p 0]] }
    }
    set b "NA"
    if {[info exists before($nm)]} { set b $before($nm) }
    puts "UNC|clk=$nm|whs_before=$b|whs_after=$slack"
    incr nrow
    if {$slack ne "NA" && $slack < 0} {
        puts "UNC_NEG clk=$nm slack=$slack"
        incr nneg
    }
}
# setup 侧顺带念一句（同一批路径的最大 slack 不应该因为 -hold 带而变；变了就说明口径没隔离干净）
set sw "NA"
catch {
    set p [get_timing_paths -delay_type max -nworst 1 -max_paths 1]
    if {[llength $p] > 0} { set sw [get_property SLACK [lindex $p 0]] }
}
puts "UNC_DESIGN_SETUP=$sw"
puts "UNC_ROWS=$nrow"
puts "UNC_NEG_COUNT=$nneg"
puts "UNC_DONE=1"
exit 0

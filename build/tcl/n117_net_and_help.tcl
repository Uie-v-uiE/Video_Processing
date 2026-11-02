# 用途：two things the replication cut still needs before it can be
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/n117_net_and_help.tcl -- two things the replication cut still needs before it can be
# paid for, both read-only and both cheap:
#
#  (A) the REAL option set of `phys_opt_design` on this Vivado (prompt A2: "凡是你记忆里
#      '应该支持'的选项，先用 help 证实，写不出来的选项视为不存在"). I skipped that rule and
#      paid for it twice: repl117_roll.tcl (02:39) and roll2 (02:48) both passed
#      `-skeleton_clustering`, which 2025.2.1 rejects with [Common 17-170] -- so the
#      "replication roll" never replicated anything. A negative result from that roll would have
#      been a verdict on my typo, not on the design. This dump is the credential for the next roll.
#
#  (B) the identity of the net that actually carries the 5.690 ns of route delay. The routed DCP's
#      own path table (build/evidence/r117_d0/worst_clk_fpga_0_setup.rpt) says:
#        SLICE_X43Y79 FDCE (Prop_fdce_C_Q) 0.379  u_pl/u_arb/owner_eth_reg/Q
#        net (fo=269, routed) 5.690  -> u_pl/u_row/hi_reg_0[0]   <- 269 loads, 5.69 ns
#        SLICE_X88Y7  LUT6 (Prop_lut6_I3_O) 0.105  u_pl/u_row/hi_reg_4_i_1
#        net (fo=2, routed) 1.181        u_pl/u_bilin/u_fb/hi_reg_8_0[0]
#        RAMB36_X3Y1  RAMB36E1            u_pl/u_bilin/u_fb/hi_reg_8/WEA[0]
#      while `get_nets -of [get_pins u_pl/u_arb/owner_eth_reg/Q]` answered
#      `u_pl/u_arb/dbg_src[0]` with 6 pins. Those two readings cannot describe the same wire, so the
#      object I would have handed to -force_replication_on_nets was the wrong one -- the mechanism
#      would have been aimed at a 6-pin net while the debt sits on a 269-pin one. Resolve the same
#      net from the LOAD side and by literal name, and require the three answers to agree before
#      any roll is paid for. Root cause stays FANOUT, and the X43 -> X88 -> RAMB36_X3 span is why
#      replication (not a pblock around the destination) is the lever.
set root [file normalize [file join [file dirname [info script]] .. ..]]
set out  [file join $root build evidence r117_d0]
file mkdir $out

# ---- (A) real option set: print help, then test each candidate option against it ----
set r ""
set e no-error
catch {set r [help phys_opt_design]} e
puts "HELP_RC=$e"
set opts {}
foreach ln [split $r "\n"] {
    if {[regexp {^\s*(-\w+)} $ln -> o]} { lappend opts $o }
}
puts "PO_OPTION_COUNT=[llength $opts]"
foreach o {-force_replication_on_nets -replication_count -skeleton_clustering -placement_opt
           -rewire -retime -critical_cell_opt -cell_opt -shift_registers -hold_buffer_insertion
           -fanout_opt -aggressive_replication} {
    set hit [expr {[lsearch -exact $opts $o] >= 0}]
    puts "PO_OPT $o present=$hit"
}

# ---- (B) net identity, resolved three ways ----
set dcp [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
if {![file exists $dcp]} { puts "REFUSE no dcp"; exit 1 }
open_checkpoint $dcp

proc netinfo {tag obj} {
    upvar 1 opts opts
    set n [get_nets -quiet -of $obj]
    foreach x $n {
        puts "$tag name=[get_property NAME $x] pins=[llength [get_pins -quiet -of $x]]"
    }
    return $n
}

set drv [get_pins -quiet u_pl/u_arb/owner_eth_reg/Q]
puts "DRV_pin_found=[llength $drv]"
set a [netinfo NET_FROM_DRIVER $drv]
set ld [get_pins -quiet u_pl/u_row/hi_reg_4_i_1/I3]
puts "LOAD_pin_found=[llength $ld]"
set b [netinfo NET_FROM_LOAD $ld]
set c [get_nets -quiet {u_pl/u_row/hi_reg_0[0]}]
puts "NET_BY_NAME found=[llength $c]"
foreach x $c { puts "NET_BY_NAME name=[get_property NAME $x] pins=[llength [get_pins -quiet -of $x]]" }

# agree / disagree, printed as data (a set that is empty is never read as "fine")
set na {} ; foreach x $a { lappend na [get_property NAME $x] }
set nb {} ; foreach x $b { lappend nb [get_property NAME $x] }
set nc {} ; foreach x $c { lappend nc [get_property NAME $x] }
puts "AGREE driver_vs_load=[expr {$na eq $nb}] load_vs_name=[expr {$nb eq $nc}]"
puts "NAMES driver=[join $na ,] load=[join $nb ,] byname=[join $nc ,]"

# where do the loads live? (hierarchy groups, counted, not guessed)
set tgt {}
if {[llength $b]} { set tgt $b } elseif {[llength $c]} { set tgt $c } elseif {[llength $a]} { set tgt $a }
if {[llength $tgt] == 0} { puts "NETID-REFUSE all three lookups empty"; exit 4 }
foreach x $tgt {
    puts "TARGET name=[get_property NAME $x] pins=[llength [get_pins -quiet -of $x]]"
    set hier {}
    foreach p [get_pins -quiet -of $x] {
        set nm [get_property NAME $p]
        set parts [split $nm /]
        lappend hier "[lindex $parts 0]/[lindex $parts 1]"
    }
    foreach h [lsort -unique $hier] {
        set k 0
        foreach g $hier { if {$g eq $h} { incr k } }
        puts "HIERGROUP $h = $k"
    }
}
foreach cell {u_pl/u_arb/owner_eth_reg u_pl/u_row/hi_reg_4_i_1 u_pl/u_bilin/u_fb/hi_reg_8} {
    set o [get_cells -quiet $cell]
    if {[llength $o]} { puts "TILE $cell [get_property LOC $o] ref=[get_property REF_NAME $o]" }
}
# every hi_reg_* load tile, so the "spread" claim has an operand instead of an adjective
set tiles {}
foreach p [get_pins -quiet -of $tgt] {
    set cl [get_cells -quiet -of $p]
    if {[llength $cl] == 0} continue
    lappend tiles [get_property LOC $cl]
}
set uniq {}
foreach t $tiles { if {[lsearch -exact $uniq $t] < 0} { lappend uniq $t } }
puts "LOAD_TILE_UNIQUE=[llength $uniq]"
set i 0
foreach t $uniq { incr i; if {$i <= 10} { puts "LOAD_TILE $i $t" } }
puts "NETHelpDONE"
exit 0

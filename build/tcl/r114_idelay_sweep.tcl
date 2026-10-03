# build/tcl/r114_idelay_sweep.tcl -- 带真实到达窗的口径下扫 IDELAY_VALUE，找 RGMII 收口的眼心（任务 #193 / ISSUES #275 #278）
#
#   为什么能在快车道扫（先量过再立项，不是猜）：`build/tcl/probe_r114_idelay_set.tcl` 实测
#     IDELAY_N=5、TARGET=.../rxdata_bus[0].u_delay_rxd、OLD=(26)、IS_LISTED_PROPERTY=1、
#     VALID_VALUES=0..31、SET_TRY rc=() read_back=(18) ⇒ VERDICT=post_synth_settable=YES
#     （件 build/evidence/r114_idelay_set_console.txt）⇒ 改这一档**不需要重新综合**，
#     每一档 = 重开同一份 `system_top_opt.dcp` + set_property + source 候选约束 + place/phys_opt/route（约 9 分钟/档）。
#   基线读数（同一份 dcp、同一套命令、tap=26）：`eth_rxc` setup 0.424 MET、hold **−2.885 VIOLATED、5 个失败端点**，
#     落点 `u_iddr_rx_ctl/D`（2 级、走线 0.000 %）；其余三域全 MET（件 build/evidence/r114_io_roll_console5.txt）。
#   ⚠ 这不是"把 hold 修绿"的实验，是"眼心在哪里"的实验：判据是**逐钟名册差分**——
#     `eth_rxc` 的 fail_hold 数与 WHS，加上其余三域不许被挤（1.155 / 4.206 / 14.109 setup，0.058 / 0.064 / 0.133 hold）。
#     只念一个头条 WNS 是这轮开始时被明确否掉的做法。
#   过滤器一律用 `==`：`-filter {NAME eq {...}}` 在本版本会报 [Common 17-263] 语法错（件
#     build/evidence/r114_idelay_prop_console4.txt），而 `-quiet` 会把这种失败伪装成"0 个对象"。
#   运行时标签 ASCII。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
set xdc [file join $root "src/constraints/r114_io_async.xdc"]
if {[info exists ::env(IO_XDC)]} { set xdc $::env(IO_XDC) }
puts "SWEEP|xdc=$xdc"
if {![file exists $dcp]} { puts "REFUSE: no opt dcp"; exit 1 }
if {![file exists $xdc]} { puts "REFUSE: no candidate xdc"; exit 1 }
set out "/tmp/kx/r114sweep"
if {[info exists ::env(IO_OUT)]} { set out $::env(IO_OUT) }
file mkdir $out
set taps {0 13 31}
if {[info exists ::env(SWEEP_TAPS)]} { set taps [split $::env(SWEEP_TAPS) ,] }
set headlines {eth_rxc clk_fpga_0 clkout0_1 sys_clk}

set out_dir $out
proc holdrow {tag} {
    global out_dir
    set f "$out_dir/hold_${tag}.rpt"
    file delete -force $f
    set e ""
    catch {report_timing -delay_type min -nworst 3 -max_paths 3 -from eth_rxc -to eth_rxc -file $f} e
    set sl {}
    set ds {}
    if {[file exists $f]} {
        set fh [open $f r]; set t [read $fh]; close $fh
        foreach m [regexp -all -inline -- {Slack\s+\((MET|VIOLATED)\)\s*:\s*(-?[0-9]+\.[0-9]+)\s*ns} $t] {
            lappend sl [lindex $m 2]
        }
        foreach m [regexp -all -inline -- {Destination:\s+(\S+)} $t] {
            lappend ds [lindex $m 1]
        }
    }
    puts "HOLDWorst|$tag|slacks=[join $sl ,]|dests=[join $ds ,]|rc=$e"
}

foreach tap $taps {
    puts "SWEEP|tap=$tap|phase=open"
    open_checkpoint $dcp
    set cells [get_cells -quiet -hier -filter {REF_NAME == IDELAYE2}]
    set n [llength $cells]
    if {$n == 0} { puts "SWEEP_REFUSE|tap=$tap|no IDELAYE2 cells（尺子断了，不当 0 档念）"; exit 4 }
    set_property IDELAY_VALUE $tap $cells
    set back {}
    foreach c $cells { lappend back [get_property IDELAY_VALUE $c] }
    puts "SWEEP|tap=$tap|cells=$n|read_back=[join $back ,]"
    set se ""
    catch {source $xdc} se
    puts "SWEEP|tap=$tap|xdc_rc=($se)"
    place_design
    phys_opt_design
    route_design
    set f "$out/sum_tap$tap.rpt"
    file delete -force $f
    catch {report_timing_summary -file $f -max_paths 1} e
    set wns NA; set whs NA; set fs NA; set fh2 NA
    if {[file exists $f]} {
        set fh [open $f r]; set txt [read $fh]; close $fh
        set rows [split $txt "\n"]; set hdr -1
        for {set i 0} {$i < [llength $rows]} {incr i} {
            if {[string first "WNS(ns)" [lindex $rows $i]] >= 0} { set hdr $i; break }
        }
        if {$hdr >= 0} {
            set vrow ""
            for {set j [expr {$hdr + 1}]} {$j < [llength $rows]} {incr j} {
                set l [string trim [lindex $rows $j]]
                if {$l eq "" || [string match "-*" $l]} { continue }
                set vrow $l; break
            }
            set flds [regexp -all -inline -- {\S+} $vrow]
            if {[llength $flds] >= 8} {
                set wns [lindex $flds 0]; set fs [lindex $flds 2]
                set whs [lindex $flds 4]; set fh2 [lindex $flds 6]
            }
        }
    }
    puts "SWEEPHEAD|tap=$tap|wns=$wns|whs=$whs|fail_setup=$fs|fail_hold=$fh2"
    foreach c $headlines {
        if {[get_clocks -quiet $c] eq ""} { puts "SWEEPROW|tap=$tap|clk=$c|MISSING"; continue }
        set per [get_property PERIOD [get_clocks $c]]
        foreach kind {setup hold} {
            set dt max
            if {$kind eq "hold"} { set dt min }
            set g "$out/rt_tap${tap}_${c}_${kind}.rpt"
            file delete -force $g
            catch {report_timing -delay_type $dt -nworst 1 -max_paths 1 -from $c -to $c -file $g} err
            set slack NA; set st NA; set dest NA
            if {[file exists $g]} {
                set gh [open $g r]; set gt [read $gh]; close $gh
                if {[regexp {Slack\s+\((MET|VIOLATED)\)\s*:\s*(-?[0-9]+\.[0-9]+)\s*ns} $gt -> a b]} { set st $a; set slack $b }
                if {[regexp {Destination:\s+(\S+)} $gt -> d]} { set dest $d }
            }
            puts "SWEEPROW|tap=$tap|clk=$c|kind=$kind|period=$per|slack=$slack|state=$st|dest=$dest"
        }
    }
    holdrow $tap
    close_project
}
puts "SWEEP_DONE taps=$taps"

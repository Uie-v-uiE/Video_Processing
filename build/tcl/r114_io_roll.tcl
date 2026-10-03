# build/tcl/r114_io_roll.tcl —— r114 I/O + 异步界那一刀的快车道单变量 A/B（一次进程里跑两滚）
#
#   IO_OUT=/tmp/kx/r114io  vivado -mode batch -nojournal -source build/tcl/r114_io_roll.tcl
#
# 为什么要这一滚（而不是直接开正式构建）：这两组约束都会**改变时序分析的边界**，
#   而"改了之后别的域怎么样"今天是能算的：同一份 `impl_1/system_top_opt.dcp` 重跑 place+route
#   约 7–9 分钟一滚，且这台机器上放置是确定的（r110 量过：同一份 dcp 重跑逐位复现正式构建的数）。
#   正式一轮 = 构建 + 31 支车道 + 顶层台架（70–128 分钟）。先用 16 分钟知道代价，再决定要不要付 2 小时。
#
# 唯一变量：B 滚多 source 了 src/constraints/r114_io_async.xdc（RGMII 收口 ±0.5 ns 输入窗 +
#   四条跨域 set_max_delay -datapath_only）。两滚的 place/phys_opt/route 命令完全一致、都不带 directive。
#
# 形状都是量出来的，不是记忆（每条都有件）：
#   * 时钟对象名来自 build/evidence/r114_objects_probe_console.txt 的 CLOCKS_LIST
#     = clk_fpga_0, sys_clk, eth_rxc, clkfbout, clkfbout_1, clkout0_1, clkout1_1, clkout2。
#   * `set_input_delay` / `set_max_delay` 的旗标来自 build/evidence/r114_help_probe_console.txt
#     （这一版没有 -setup/-hold，也没有 -clock_edges ⇒ DDR 第二沿只能再写一条 -clock_fall）。
#   * `report_methodology` 没有 `-rules`，只有 `-checks`（第一支探针死在 `Unknown option '-rules'`）。
#   * `get_false_paths` **不存在**（探针死在 line 55，件 build/evidence/r114_objects_probe_console.txt 尾部）
#     ⇒ 这里数异常一律用 `get_timing_exceptions`，并按 TYPE 分类打印。
# ⚠ 运行时标签 ASCII；网名里 [n] 是 GLOB 类字符 ⇒ 需要点名的地方用 `-filter {NAME eq {…}}`。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set out "/tmp/kx/r114io"
if {[info exists ::env(IO_OUT)]} { set out $::env(IO_OUT) }
if {![info exists ::env(IO_TMP)]} { set ::env(IO_TMP) $out }
file mkdir $out
set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp"]
if {![file exists $dcp]} { puts "REFUSE: no opt dcp: $dcp"; exit 1 }
set xdc [file join $root "src/constraints/r114_io_async.xdc"]
if {![file exists $xdc]} { puts "REFUSE: no candidate xdc: $xdc"; exit 1 }

set headlines {eth_rxc clk_fpga_0 clkout0_1 sys_clk}

proc debt {} {
    #     "There are 5 input ports with no input delay specified. (HIGH)"
    #     "There are 6 ports with no output delay specified. (HIGH)"
    #     "There are 2 input ports with no input delay but user has a false path constraint. (MEDIUM)"
    #     "There are 6 ports with no output delay but user has a false path constraint (MEDIUM)"
    global ::env
    set tmp [file join $::env(IO_TMP) "debt_[clock clicks -milliseconds].rpt"]
    file delete -force $tmp
    set e ""
    catch {check_timing -verbose -file $tmp} e
    set hi_in -1; set hi_out -1; set md_in -1; set md_out -1
    if {[file exists $tmp]} {
        set fh [open $tmp r]; set t [read $fh]; close $fh
        if {[regexp {There are (\d+) input ports with no input delay specified} $t -> n]} { set hi_in $n }
        if {[regexp {There are (\d+) ports with no output delay specified} $t -> n]} { set hi_out $n }
        if {[regexp {There are (\d+) input ports with no input delay but user has a false path} $t -> n]} { set md_in $n }
        if {[regexp {There are (\d+) ports with no output delay but user has a false path} $t -> n]} { set md_out $n }
    }
    set exc NA; set dm NA; set grp NA
    set ef [file join $::env(IO_TMP) "exc_[clock clicks -milliseconds].rpt"]
    file delete -force $ef
    set e4 ""
    catch {report_exceptions -file $ef} e4
    if {[file exists $ef]} {
        set fh2 [open $ef r]; set et [read $fh2]; close $fh2
        set exc [llength [regexp -all -inline -- {(?m)^\d+\s+\S} $et]]
        set dm [llength [regexp -all -inline -- {-datapath_only} $et]]
        set grp [llength [regexp -all -inline {clock_groups} $et]]
    }
    return "no_in=$hi_in|no_out=$hi_out|fp_in=$md_in|fp_out=$md_out|exc_rows=$exc|datapath_only_hits=$dm|clock_group_rows=$grp|rc_msg=$e$e4"
}

proc roster {tag outdir} {
    foreach c $::headlines {
        if {[get_clocks -quiet $c] eq ""} { puts "IROW|$tag|clk=$c|MISSING"; continue }
        set per [get_property PERIOD [get_clocks $c]]
        foreach kind {setup hold} {
            set dt max
            if {$kind eq "hold"} { set dt min }
            set f [file join $outdir "rt_${tag}_${c}_${kind}.rpt"]
            file delete -force $f
            catch {report_timing -delay_type $dt -nworst 1 -max_paths 1 -from $c -to $c -file $f} err
            set slack NA; set st NA; set levels NA; set route NA; set dest NA
            if {[file exists $f]} {
                set fh [open $f r]; set txt [read $fh]; close $fh
                if {[regexp {Slack\s+\((MET|VIOLATED)\)\s*:\s*(-?[0-9]+\.[0-9]+)\s*ns} $txt -> a b]} { set st $a; set slack $b }
                if {[regexp {Logic Levels:\s+(\d+)} $txt -> L]} { set levels $L }
                if {[regexp {route\s+([0-9.]+)ns\s*\(\s*([0-9.]+)%\s*\)} $txt -> r p]} { set route $p }
                if {[regexp {Destination:\s+(\S+)} $txt -> d]} { set dest $d }
            }
            puts "IROW|$tag|clk=$c|kind=$kind|period=$per|slack=$slack|state=$st|levels=$levels|route_pct=$route|dest=$dest"
        }
    }
    #   WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns) THS Failing ...
    set f [file join $outdir "sum_${tag}.rpt"]
    file delete -force $f
    catch {report_timing_summary -file $f -max_paths 1} e
    set wns NA; set whs NA; set fin NA; set fip NA; set lines 0
    if {[file exists $f]} {
        set fh [open $f r]; set txt [read $fh]; close $fh
        set rows [split $txt "
"]
        set hdr -1
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
            set flds [regexp -all -inline {\S+} $vrow]
            set lines [llength $flds]
            if {[llength $flds] >= 8} {
                set wns [lindex $flds 0]; set fin [lindex $flds 2]
                set whs [lindex $flds 4]; set fip [lindex $flds 6]
            }
        }
    }
    puts "IHEAD|$tag|wns=$wns|whs=$whs|fail_setup=$fin|fail_hold=$fip|fields=$lines"
}

## ============================ A 滚：不加新约束 ============================
puts "ROLL|mode=base|open=$dcp"
open_checkpoint $dcp
puts "DEBT|base|[debt]"
roster base $out
place_design
phys_opt_design
route_design
puts "DEBT|base_after_route|[debt]"
roster base_route $out
if {![info exists ::env(IO_TMP)]} { set ::env(IO_TMP) $out }
file mkdir $out/base
catch {write_checkpoint -force $out/base/routed.dcp} ew
close_project

## ============================ B 滚：同一份 dcp + 候选 XDC ============================
puts "ROLL|mode=io|open=$dcp"
open_checkpoint $dcp
set src_err ""
catch {source $xdc} src_err
puts "XDC_SOURCE|rc_msg=$src_err"
puts "DEBT|io_before|[debt]"
roster io_pre $out
place_design
phys_opt_design
route_design
puts "DEBT|io_after_route|[debt]"
roster io_route $out
if {![info exists ::env(IO_TMP)]} { set ::env(IO_TMP) $out }
file mkdir $out/io
catch {write_checkpoint -force $out/io/routed.dcp} ew2
puts "IO_ROLL_DONE"

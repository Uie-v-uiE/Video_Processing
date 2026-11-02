# 用途：只读探针：把 r117 官方构建的 I/O 侧与 check_timing 读数问回来
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完 1=REFUSE 4=REFUSE
# build/tcl/r117_io_probe.tcl -- 只读探针：把 r117 官方构建的 I/O 侧与 check_timing 读数问回来。
#
# 为什么还要这一支：链子跑的 `probe_timing_roster.tcl` 与 `pre_readings.sh` 给的是**逐时钟名册**，
# 而 E1 那张表（`roster_roundNNN.tsv`）有两列是债务列（`unconstrained_endpoints` /
# `io_unconstrained_ports`），它们的**唯一合法来源**是 `check_timing -verbose` 自己那几行
# （提示词附录 1 的量纲红线：check_timing 数端口类对象、report_methodology 数 checks/pins，
# 两种量纲永不相减）。另外 V1/V2 那两条判据（I/O 路必须仍是"有限 slack + Input Delay 行"、
# 未约束端口仍是 6）也要重新问一次，不然 r117 的这两条只是"照抄 r116"。
#
# ⚠ 只读：开的是已布线 DCP，不回写、不改约束、不动 src/。标签一律 ASCII（Vivado Tcl 按系统
#    代码页读 UTF-8，中文 puts 会把控制台变成二进制——环境账里栽过）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file normalize [file join $root vivado_system zynq_video_sys.runs impl_1 system_top_routed.dcp]]
set out  [file join $root build evidence r117]
if {![file exists $dcp]} { puts "R117PROBE-REFUSE no routed dcp $dcp"; exit 1 }
file mkdir $out
open_checkpoint $dcp
puts "R117PROBE dcp=$dcp"

check_timing -verbose -file [file join $out r117_check_timing.txt]
set h [open [file join $out r117_check_timing.txt] r]; set t [read $h]; close $h
foreach ln [split $t "\n"] {
    set s [string trim $ln]
    if {[regexp {^ ?There are [0-9]+ (input|output|pins|ports)} $s]} { puts "CT $s" }
    if {[regexp {^[0-9]+\. checking} $s]} { puts "CTROW $s" }
}

# I/O 族两条最差路（hold/setup），与 r116 同一把尺：同一份报告命令、同一组端口、同一个目的钟
set ports [get_ports -quiet {eth_rxd[*] eth_rx_ctl}]
puts "R117PROBE ports=[llength $ports]"
if {[llength $ports] == 0} { puts "R117PROBE-REFUSE no eth ports"; exit 4 }
foreach {dt f} {min r117_io_HOLD.rpt max r117_io_SETUP.rpt} {
    set e no-error
    catch {report_timing -delay_type $dt -from $ports -to [get_clocks -quiet eth_rxc] \
        -nworst 1 -max_paths 2 -file [file join $out $f]} e
    puts "R117IO $f rc=$e"
    if {[file exists [file join $out $f]]} {
        set h2 [open [file join $out $f] r]; set t2 [read $h2]; close $h2
        foreach ln [split $t2 "\n"] {
            set s [string trim $ln]
            if {[regexp {^(Slack|Input Delay|Path Type|Data Path Delay|Logic Levels|Source|Destination):} $s]} { puts "IOLINE $f |$s" }
        }
    }
}
# 时钟域汇总（防"名册与官方件不是同一把尺"）：WNS/WHS 两行照抄
report_timing_summary -delay_type max -max_paths 1 -file [file join $out r117_timing_setup_only.txt]
report_timing_summary -delay_type min -max_paths 1 -file [file join $out r117_timing_hold_only.txt]
set h3 [open [file join $out r117_timing_setup_only.txt] r]; set t3 [read $h3]; close $h3
set n 0
foreach ln [split $t3 "\n"] {
    set s [string trim $ln]
    if {[regexp {^\s*-?[0-9]+\.[0-9]+\s+-?[0-9]+\.[0-9]+\s+[0-9]+\s+[0-9]+} $s]} {
        incr n
        if {$n <= 3} { puts "SUMLINE $n |$s" }
    }
}
puts "R117PROBE_DONE sum_rows=$n"
exit 0

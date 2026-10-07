# 用途：read-only probe of xsdb target SELECTION.
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完
# build/tcl/probe_target_select.tcl -- read-only probe of xsdb target SELECTION.
# Why: ps_jtag_boot.tcl selects with a hardcoded index (`targets -set 1`). After the user's
# cold power cycle hw_server re-enumerated the chain as 1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020,
# and the fixed index now dies inside tid2ctx. This probe only CONNECTS and tries the name-filter
# forms; it never runs rst, ps7_init, program, mwr, stop or con.
# Runtime strings ASCII-only (GBK console trap).
catch {connect -host localhost -port 3121} ce
puts "CONNECT: $ce"
foreach pat {APU "xc7z020" "*#0" "*#1" PS7} {
    set rc [catch {targets -set -filter [format {name =~ "%s"} $pat]} em]
    if {$rc == 0} {
        puts "SEL pattern=$pat rc=$rc"
    } else {
        puts "SEL pattern=$pat rc=$rc msg=$em"
    }
}
set rcidx1 [catch {targets -set 1} emi]
puts "IDX1 rc=$rcidx1 msg=$emi"
set rcidx2 [catch {targets -set 2} emj]
puts "IDX2 rc=$rcidx2 msg=$emj"
exit 0

# build/tcl/probe_tmds_launch_clock.tcl — 只读探针：TMDS 输出是由**哪条时钟**发出的
# 作用: 对每个 TMDS 输出脚（外加 led[0] 做正对照）跑一次 -to 端点路径报告，从报告文本里念出 Clock:/Source:/Destination: 那几行，绕开 port 上的 CLOCK 属性
# 前置条件: 环境变量 VP_DCP 指向一个存在的 checkpoint（用法里是 vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp），在仓库根起 vivado -mode batch；缺或不存在 ⇒ puts PROBE-REFUSE 并 exit 3
# 产出物: stdout 每端口一行 LAUNCH2| <port> | <时钟行拼接> 加收尾 PROBE2-DONE；中间件 build/evidence/r119_launch_tmp.rpt 读完即删，不留下
# 关键参数: 环境变量 VP_DCP（必填，唯一的输入）；无命令行参数；端口名册与临时报告名写死在本文件
#
# 为什么还要第二次探针：第一次（probe_tmds_clocks.tcl，件 build/evidence/r119_tmds_clock_probe.txt）
# 读到 `PORT| tmds_* | clock=` **全空**，而 `CLOCK` 这个属性在 **port 对象**上本来就不是"驱动时钟"
# （那是 pin/net 的概念）。按记忆里那一族教训（过滤器读空 ≠ 没有），**不能**据此写约束，
# 也不能据此说"没有时钟"。这里改用工具自己的路径报告：给每个端口做一次 -to 端点的路径报告，
# 路径头部会自己念出时钟名。
#
# 用法（仓库根）：
#   VP_DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp \
#   "$VP_VIVADO_BIN/vivado" -mode batch -nojournal -source build/tcl/probe_tmds_launch_clock.tcl
# 只读：不 place、不 route、不 set 任何属性。运行期字符串一律 ASCII。

set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp $::env(VP_DCP) }
if {$dcp eq "" || ![file exists $dcp]} { puts "PROBE-REFUSE VP_DCP=$dcp"; exit 3 }
open_checkpoint $dcp

foreach p {tmds_clk_p tmds_data_p\[0\] tmds_data_p\[1\] tmds_data_p\[2\] led\[0\]} {
    set obj [get_ports -quiet $p]
    if {[llength $obj] == 0} { puts "LAUNCH| $p | NO_SUCH_PORT NOT_MEASURED"; continue }
    # 注意：Vivado 的 Tcl 里**没有** `tempname`（第一次跑就是死在它上面：invalid command name "tempname"，
    # 件 build/evidence/r119_tmds_launch_probe.txt），所以报告写进 build/evidence/ 下的固定名字，逐个覆盖。
    set out "build/evidence/r119_launch_tmp.rpt"
    if {[file exists $out]} { file delete -force $out }
    set rc [catch {report_timing -to $obj -max_paths 1 -nworst 1 -setup -file $out} e]
    if {$rc != 0 || ![file exists $out] || [file size $out] == 0} {
        puts "LAUNCH| $p | rc=$rc msg=$e NOT_MEASURED"
        continue
    }
    set f [open $out r]; set txt [read $f]; close $f
    file delete -force $out
    set found ""
    foreach l [split $txt "\n"] {
        set t [string trim $l]
        # 第一次跑我的匹配写的是 "Clock *"（Clock 后面直接跟空格），而 Vivado 打的是 "Clock:  xxx"，
        # 于是四行全被漏掉、看起来像"这端口没有时钟"。匹配按实际形状重写：前缀带冒号。
        if {[string match "Clock:*" $t] || [string match "Path Group:*" $t] ||
            [string match "Source:*" $t] || [string match "Destination:*" $t] ||
            [string match "Source Clock:*" $t] || [string match "Destination Clock:*" $t]} {
            append found "[string map {\t { }} $t] || "
        }
    }
    if {$found eq ""} { set found "(报告里连 Clock:/Source:/Destination: 都没有 ⇒ NOT_MEASURED)" }
    puts "LAUNCH2| $p | $found"
}
puts "PROBE2-DONE"
exit 0

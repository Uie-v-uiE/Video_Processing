# build/tcl/r115_baseline_probe.tcl —— 阶段 B1：在**未修改的树**上把基线花名册需要的全量报告问出来（只读）
#
# 谁规定的：`report/timing/README.md` §0/§3（那份是用户 2026-10-03 夜给的"时序一轮收敛到极限"提示词）。
# 纪律：
#   * 只读——不 set_property、不 edit、不写 runs 目录，所有产物落 build/evidence/r115_base/；
#   * 每一条命令的**选项形状**都是 2026-10-03 用 `help` 量过的（见同目录 help_shapes.txt 与 ISSUES #263/#264），
#     没量过的选项一律不写（`report_design_analysis -fanout` 不存在、`set_max_fanout` 不存在、
#     `get_false_paths`/`get_clock_groups` 不是命令）；
#   * `-quiet` 会把坏选项吞成空文件 ⇒ 每条命令的 catch 返回串都要打印（凡空集/空文件必须有 rc，见附录 1）；
#   * puts 标签全 ASCII。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dcp  [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
set out  [file join $root "build/evidence/r115_base"]
if {![file exists $dcp]} { puts "REFUSE: no dcp $dcp"; exit 1 }
file mkdir $out
puts "BASE dcp=$dcp"
open_checkpoint $dcp
puts "BASE design=[current_design] state=[get_property STATE [current_design]]"

# 每个报告都走同一个小工具：打印 catch 的 rc + 文件是否真存在 + 字节数（空文件不许冒充"报告有了"）
proc rep {tag args} {
    set root [file normalize [file join [file dirname [info script]] .. ..]]
    set out  [file join $root "build/evidence/r115_base"]
    set f [file join $out "$tag.txt"]
    catch {file delete -force $f}
    set e none
    set cmd "report_$args"
    set code [catch {eval $cmd -file $f} e]
    set sz -1
    if {[file exists $f]} { set sz [file size $f] }
    puts "REPT tag=$tag code=$code size=$sz err=$e"
    if {$code != 0 || $sz <= 0} { puts "REPT-BAD tag=$tag —— 这一份没有内容，不许被下游当成凭据" }
}
# B1 点名的清单，一条不落（顺序 = 提示词里的顺序）
rep timing_summary    timing_summary -extended -numeric_summary
rep setup_nworst      timing -delay_type max -nworst 10 -unique_pins -max_paths 10
rep hold_nworst       timing -delay_type min -nworst 10 -unique_pins -max_paths 10
rep check_timing      timing
rep methodology       methodology
rep high_fanout       high_fanout_nets -max_nets 60
rep clock_interaction clock_interaction
rep da_complexity     design_analysis -complexity
rep da_congestion     design_analysis -congestion
rep da_timing         design_analysis -timing
rep da_routes         design_analysis -routes
rep da_levels         design_analysis -logic_level_distribution
rep da_routed_vs_est  design_analysis -routed_vs_estimated
rep da_qor            design_analysis -qor_summary
rep utilization       utilization
rep route_status      route_status
rep exceptions        exceptions
rep clock_networks    clock_networks
rep clock_utilization clock_utilization
# check_timing 的"点名版"：只有 -verbose 会念出端口名（今天量的形状）
set f [file join $out "check_timing_verbose.txt"]
catch {file delete -force $f}
set e none
set code [catch {check_timing -verbose -file $f} e]
puts "REPT tag=check_timing_verbose code=$code exists=[expr {[file exists $f] ? 1 : 0}] err=$e"
# 每条时钟的"被约束端点数"要用的原始表：Clock Summary + Intra Clock Table 都在 timing_summary 里，
# 但 B2 要 per-clock 的 total endpoints，所以再单独问一次逐时钟（report_timing_summary -clock 不支持 ⇒ 用 -to）
set clks [get_clocks -quiet *]
puts "CLOCKS_N=[llength $clks]"
foreach c $clks {
    set nm [get_property NAME $c]
    set per [get_property PERIOD $c]
    set src "user"
    if {[get_property IS_GENERATED $c]} { set src "generated" }
    set pin [get_property SOURCE_PINS $c]
    puts "CLKROW clk=$nm|period=$per|src=$src|generated=[get_property IS_GENERATED $c]|source_pins=$pin"
    set f2 [file join $out "clk_${nm}_summary.txt"]
    set e2 none
    set code2 [catch {report_timing_summary -quiet -delay_type all -to [get_clocks $nm] -file $f2} e2]
    set sz2 -1
    if {[file exists $f2]} { set sz2 [file size $f2] }
    puts "CLOCKSUM clk=$nm code=$code2 size=$sz2 err=$e2"
    # 该钟域里被工具真正算路径的端点数（Intra Clock Table 那一行的 Total Endpoints 由解析器读）
    set p [get_timing_paths -quiet -delay_type max -nworst 1 -max_paths 1 -from [get_clocks $nm] -to [get_clocks $nm]]
    puts "CLOCKPATH clk=$nm setup_paths_found=[llength $p]"
}
# I/O 端口的"被点名"账：**只数端口对象**（附录 1 量纲红线：check_timing 数端口类、
#   report_methodology 数 checks/pins、RTL 端口表数 bit —— 三个单位永不相减）。
#   "哪个端口有没有 delay 约束"这件事仓库里已经有专门一把尺子（src/host 的 check_io_timing_coverage.py，
#   I1..I9），这里不重做也不发明命令（get_timings/get_buffers 都不是本工具的命令，写上去只会让探针死在半路）。
puts "IO total_ports=[llength [get_ports -quiet *]] inputs=[llength [get_ports -quiet -direction {in*}]] outputs=[llength [get_ports -quiet -direction {out*}]]"
foreach p [get_ports -quiet -direction {in*}] {
    if {[llength [get_input_delays -quiet -of $p]] > 0} { continue }
    puts "INPORT_NO_DELAY name=$p"
}
foreach p [get_ports -quiet -direction {out*}] {
    if {[llength [get_output_delays -quiet -of $p]] > 0} { continue }
    puts "OUTPORT_NO_DELAY name=$p"
}
puts "IO_UNCONSTRAINED_COUNTS in_no_delay=[sizeof_collection [get_ports -quiet -direction {in*}]] 是上限，逐条点名的行才是数"
puts "BASEPROBE_DONE"
exit 0

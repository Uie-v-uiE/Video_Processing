# build/tcl/r115_help_shapes.tcl —— 阶段 A2：把"我打算解析/打算写的每条命令"的**真实选项集**打印存档
#
# 为什么必须先跑这支（提示词 §2 A2 + 附录 1）：`-quiet` 会把坏选项吞成空文件，`catch` 会把不存在的
# 命令吞成"0 个对象"——今天夜里已经栽过两次（`report_timing_summary -extended` 未知选项 ⇒ 基线件差一点
# 是空的；`-to [get_clocks]` 未知选项 ⇒ 逐时钟那份没写出来）。凡是记忆里"应该支持"的选项，
# 先用 help 证实；写不出来的选项视为不存在。
# 探针**不开 design**（约 40 s 一批），所以这里只做 `help`，不查对象。
foreach c {
    report_timing_summary report_timing report_io report_exceptions report_high_fanout_nets
    report_methodology report_cdc report_design_analysis report_clock_interaction
    report_clock_networks report_clock_utilization report_utilization report_route_status
    check_timing create_clock create_generated_clock set_input_delay set_output_delay
    get_ports get_input_delays get_output_delays get_clocks get_pins list_property report_parameter
    set_clock_groups set_clock_uncertainty set_max_delay set_data_check set_bus_skew
    set_false_path set_multicycle_path report_qor_suggestions create_pblock
    phys_opt_design place_design route_design report_timing -help
} {
    set name [lindex [split $c " "] 0]
    set e none
    set code [catch {help $name} h]
    puts "HELPCMD name=$name code=$code"
    if {$code == 0} {
        foreach ln [split $h "\n"] {
            set t [string trim $ln]
            if {$t eq ""} continue
            if {[string match "-*" $t] || [string match "*--*" $t]} { puts "OPT|$name|$t" }
        }
    } else {
        puts "OPT-NONE $name err=$h"
    }
}
# 报告形状类的"选项里到底有没有我要的那个开关"，逐条给结论（人读，机器读上面的 OPT| 行）
foreach pair {report_timing_summary -unique_pins} {
    puts "CHECK_PAIR $pair"
}
puts "HELPSHAPES_DONE"
exit 0

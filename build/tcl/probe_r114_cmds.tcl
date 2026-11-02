# 作用: 只问一件事——这一版 Vivado 到底有哪些异常/时钟组/数据检查相关命令（`get_false_paths` 那类是否存在）
# 前置条件: vivado -mode batch 起一个空 Tcl 会话即可，不需要打开工程
# 产出物: stdout 每行 CMD|<名字>=<命令清单>
# 关键参数: 无命令行参数
# 退出码: 显式 exit 0（探针跑完就走）
puts "CMD|get_exc=[join [info commands get_*exc*] ,]"
puts "CMD|any_exception=[join [info commands *exception*] ,]"
puts "CMD|clock_group=[join [info commands *clock_group*] ,]"
puts "CMD|report_exc=[join [info commands report_exception*] ,]"
puts "CMD|timing_spec=[join [info commands get_timing_specs] ,]"
puts "CMD|data_check=[join [info commands get_data_checks] ,]"
exit

# build/build.tcl
# 作用: 一键综合 + 实现 + 生成比特流与全套报告（交付要求 §4 的主入口，等价于直接跑主脚本）
# 前置条件: src/rtl 与 src/constraints 齐全；vivado 在 PATH 里
# 产出物: 工程目录 vivado_system/，以及 build/ 下 system.bit、system.xsa 与
#         timing_summary / utilization / cdc / methodology / power / route_status / clock_util 七份报告
# 关键参数: IMPL_STRATEGY、IMPL_POST_PLACE_HOOK、IMPL_PRPO 见主脚本注释；不设即历史默认档
# 退出码: 0=全流程成功 非 0=主脚本内的显式失败出口（综合失败、策略被拒等）
set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root build tcl build_system_axigpio.tcl]

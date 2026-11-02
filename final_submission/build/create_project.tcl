# build/create_project.tcl
# 作用: 建工程——器件型号 xc7z020clg484-2、工程名与目录映射；随后导入 RTL / IP / 约束，停在综合之前
# 前置条件: src/rtl 与 src/constraints 齐全；vivado 在 PATH 里
# 产出物: 工程目录（默认 vivado_system/，可用 VP_PROJ_SUBDIR 指到别处）与其中的 sources_1 / constrs_1 / run 列表
# 关键参数: VP_STOP_AT=project 由本入口设置；VP_PROJ_SUBDIR、VP_OUTDIR 透传给主脚本
# 退出码: 0=工程建好 非 0=主脚本内 exit 1（建工程失败）
set root [file normalize [file join [file dirname [info script]] ..]]
set ::env(VP_STOP_AT) project
source [file join $root build tcl build_system_axigpio.tcl]

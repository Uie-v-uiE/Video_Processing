# build/add_sources.tcl
# 作用: 把 RTL / IP / 约束导入工程并停在综合之前。建工程与导源在主脚本里是同一个阶段
#       （BD 不存在时源文件无处可挂），因此本入口与 create_project.tcl 共用第一段，源清单只有一份
# 前置条件: 同 create_project.tcl
# 产出物: 工程文件里的 sources_1 / constrs_1、时钟与约束的 used_in_* 属性、run 列表
# 关键参数: VP_STOP_AT=project；VP_PROJ_SUBDIR、VP_OUTDIR 透传
# 退出码: 0=源与约束齐 非 0=主脚本 exit 1
set root [file normalize [file join [file dirname [info script]] ..]]
set ::env(VP_STOP_AT) project
source [file join $root build tcl build_system_axigpio.tcl]

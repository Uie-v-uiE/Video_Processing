# 作用: 只读探针——把 impl_1 的 PLACE_DESIGN 前/后钩子文件与启用位读出来打印，确认 post-place hook 挂没挂上
# 前置条件: build/vivado_system/zynq_video_sys.xpr 已存在；用 vivado -mode batch -source 跑
# 产出物: stdout 的属性读数（脚本不写任何文件）
# 关键参数: 无命令行参数；工程路径按本文件位置推到仓库根
# 退出码: open_project 取不到工程时由 Vivado 报错退出（非 0）
set root [file normalize [file join [file dirname [info script]] .. ..]]
open_project [file join $root vivado_system zynq_video_sys.xpr]
set r [get_runs impl_1]
foreach p {STEPS.PLACE_DESIGN.TCL.POST STEPS.PLACE_DESIGN.IS_ENABLED STEPS.PLACE_DESIGN.TCL.PRE} {
    set e no-error
    set v ""
    catch {set v [get_property $p $r]} e
    puts "PP_PROP $p rc=$e value=$v"
}
exit 0

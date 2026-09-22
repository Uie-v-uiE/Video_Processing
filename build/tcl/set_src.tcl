# set_src.tcl — 通过 JTAG 写 AXI GPIO(0x41200000) 选显示源/特效
#   [16]   src_sel   0=SRC0 彩条  1=SRC1 视频
#   [4:0]  effect_en
#   [15:8] threshold
# 用法：
#   xsdb.bat build_tcl/set_src.tcl            → SRC1 视频、特效关闭
#   改 SRC_VAL 为 16'h00000000 可回 SRC0
# bit16 = src_sel(1 = DDR 帧)，bit17 = zoom_en，bit19 = bilin_en。
# V7.7 起 zoom_en 不再是 RTL 里的常数 1'b1（原来是硬绑，ZOOM0/ZOOM1 是死命令），
# 所以这里必须显式把 bit17 写 1，否则"上电即呼吸缩放"的观感会随这次解绑一起丢掉。
# V7.8 起 bit19 = 右窗双线性插值；这里写 1 保持"默认就是插值"的观感，
# 要现场 A/B 用串口命令 BILIN0 / BILIN1（比重新下 bit 快得多，也不会改到别的位）。
# 注意：本脚本是**整字覆盖**，bit18（发布脉冲）会被写成 0 —— 那只是多/少一次发布，
# 不影响画质；PS 应用下一次 ctrl_apply() 会把它按自己的状态摆回去。
set SRC_VAL 0x000B0000

catch {connect -host localhost -port 3121}
targets -set -filter {name =~ "*#0"}
catch {stop}
mwr -force 0x41200000 $SRC_VAL
puts "GPIO 0x41200000 = [mrd -force 0x41200000 1]"
catch {con}
exit 0

# set_src.tcl — 通过 JTAG 写 AXI GPIO(0x41200000) 选显示源/特效
#   [16]   src_sel   0=SRC0 彩条  1=SRC1 视频
#   [4:0]  effect_en
#   [15:8] threshold
# 用法：
#   xsdb.bat build_tcl/set_src.tcl            → SRC1 视频、特效关闭
#   改 SRC_VAL 为 16'h00000000 可回 SRC0
# bit16 = src_sel(1 = DDR 帧)，bit17 = zoom_en。
# V7.7 起 zoom_en 不再是 RTL 里的常数 1'b1（原来是硬绑，ZOOM0/ZOOM1 是死命令），
# 所以这里必须显式把 bit17 写 1，否则"上电即呼吸缩放"的观感会随这次解绑一起丢掉。
set SRC_VAL 0x00030000

catch {connect -host localhost -port 3121}
targets -set -filter {name =~ "*#0"}
catch {stop}
mwr -force 0x41200000 $SRC_VAL
puts "GPIO 0x41200000 = [mrd -force 0x41200000 1]"
catch {con}
exit 0

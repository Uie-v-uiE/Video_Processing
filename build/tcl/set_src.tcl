# set_src.tcl — 通过 JTAG 写 AXI GPIO(0x41200000) 选显示源/特效
#   [16]   src_sel   0=SRC0 彩条  1=SRC1 视频
#   [4:0]  effect_en
#   [15:8] threshold
# 用法：
#   xsdb.bat build_tcl/set_src.tcl            → SRC1 视频、特效关闭
#   改 SRC_VAL 为 16'h00000000 可回 SRC0
set SRC_VAL 0x00010000

catch {connect -host localhost -port 3121}
targets -set -filter {name =~ "*#0"}
catch {stop}
mwr -force 0x41200000 $SRC_VAL
puts "GPIO 0x41200000 = [mrd -force 0x41200000 1]"
catch {con}
exit 0

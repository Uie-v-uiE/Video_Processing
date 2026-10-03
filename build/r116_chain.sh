#!/usr/bin/env bash
# build/r116_chain.sh —— r116 整轮链：两刀
#   刀 1  src/constraints/r116_rgmii_input_window.xdc 进构建（只加严：5 个 RGMII 输入第一次被检查）
#   刀 2  src/rtl/top/system_top.v 的 IDELAY_VALUE 26 -> 31（真窗下 0..31 扫出来的 min(hold,setup) 最大点）
# 出处与判据全部在 docs/timing/rgmii_window_model.md §7.5 与 build/evidence/r115_window/。
#
# 本轮的"改前红"不是猜的：同一把尺子（同一份窗、同一只已布线 DCP）扫出来的曲线在
# probe3_console.txt 里 —— tap26 hold −1.185 / setup −0.386；tap31 hold −0.870 / setup −0.846。
# 所以刀 2 的预期是"把这一族的最差格从 −1.185 抬到 ≈ −0.87"，不是"抬绿"。
# 绿不绿由构建自己说：下面 V3 直接把 I/O 族的读数抓出来。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}"
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
NN=116
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE: 没有 Vivado（VP_VIVADO_BIN='$V'）"; exit 2; }

# ---- 改前：钉树指纹 + 把 r114 那份名册钉成基线 ------------------------------------------
bash build/rtl_fingerprint.sh | tee "build/evidence/r${NN}_tree_fp.txt"
FP=$(grep -a '^rtl=' "build/evidence/r${NN}_tree_fp.txt" | cut -d= -f2)
[ -n "$FP" ] || { say "REFUSE: 指纹取不到（空指纹不许当凭据）"; exit 3; }
say "本轮树指纹 rtl=$FP"

say "构建开始（刀 1 输入窗 + 刀 2 IDELAY=31）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B）—— 断链"; exit 1; }
say "构建完成 rc=$B"

# ---- 判读：① 窗真的挂上了吗（机制侧，不看 slack）-----------------------------------------
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/r116_verdict_probe.tcl \
    > "build/r${NN}_verdict_console.txt" 2>&1; say "verdict probe rc=$?"

say "链结束：判读见 build/evidence/r${NN}_verdict.txt 与名册差分"

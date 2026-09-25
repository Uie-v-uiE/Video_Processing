#!/bin/bash
# C1i 的"判据自己也要被量"测试（仓库规矩：每条判据要有它自己的反例）。
#
# 为什么值得单独一个脚本：`tb_v98_top_seam` 一份要跑 ~4 分钟，手工"改→跑→看→改回来"
# 极容易把顶层留在改坏的状态里过夜。这里用 trap 保证**无论中途出什么错都把源码还原**，
# 并且在跑之前先确认没有构建在跑（构建期间不许动 src/ 是硬规矩）。
#
# 期望（这两条都必须成立，否则 C1i 只是"写了没验"）：
#   ① 相位改回第 3 级 ⇒ C1i 与 C1c **同时**红（证明它真的在看那条路，不是顺带绿）
#   ② 改回第 2 级     ⇒ 两条一起绿（今天的基线，凭据 build/tb_v98_r63_bilin.txt）
ROOT=/d/Xilinx/Prj/pro/Video_Processing
TOP=$ROOT/src/rtl/top/pl_video_top.v
cd "$ROOT" || exit 1

if tasklist //FI "IMAGENAME eq vivado.exe" 2>/dev/null | grep -qi vivado.exe; then
  echo "有 vivado.exe 在跑 ⇒ 构建期间不许改 src/，先停这个脚本"; exit 1
fi

cp "$TOP" /tmp/pl_video_top.keep
restore() { cp /tmp/pl_video_top.keep "$TOP"; echo "已还原顶层（md5 见下）"; md5sum "$TOP"; }
trap restore EXIT

echo "=== 步骤 1：把三个相位量从 [2] 改成 [3]（故意的反例）==="
sed -i 's/\.col0(~x_d\[2\]\[0\]), \.row0(~y_d\[2\]\[0\]), \.pair_odd(y_d\[2\]\[1\])/.col0(~x_d[3][0]), .row0(~y_d[3][0]), .pair_odd(y_d[3][1])/' "$TOP"
grep -n "\.col0(~x_d\[3\]\[0\])" "$TOP" | head -2
sed -i 's/\.req_vld(de_d\[2\]), \.oob_in(oob)/.req_vld(de_d[3]), .oob_in(oob)/' "$TOP"
grep -n "\.req_vld(de_d\[3\])" "$TOP" | head -2

echo "=== 步骤 2：跑 tb_v98，期望 C1i 与 C1c 同时红 ==="
bash sim/run_one.sh tb_v98_top_seam 2>&1 | grep -aE "C1i|C1c |RESULT|XVLOG|XELAB|^ERROR" | head -8

#!/usr/bin/env bash
# build/r132_arm_d.sh —— 臂 D（改写）：不在构建上再试第三种窗形状，而是把**正确量纲**的那一问
# 在现版成品上重问一遍。
#
# 为什么换做法：2026-10-20 这一轮看到臂 A 的 clkout1_1 setup −5.408 ns 后，我先写了一版
# "把 20 ns 参考钟打在 tmds_clk_p 上"的新候选件，准备再滚一次构建。查账本才发现这条路
# 2026-10-04 已经走过并判完：`src/constraints/r119b_hdmi_tp1_pinclk.xdc` 就是那个形状，
# 件 `build/evidence/r119_xdc_loads_probe4_pinclk.txt` 给出 −4.897/−4.873/−4.890 ns；
# `report/timing/debt_ledger.md` 追加一节与 ISSUES #335 把结论写死：规范那条是 **skew**
# （两脚到达时刻之差的上限），`set_output_delay` 是**采样窗**，两者不同量纲 ⇒ 负数是量纲错，
# 不是设计时序债，也不许靠放宽窗把它变绿。所以第三种形状不加（加了只会多一份会漂的副本），
# 现版要复核这笔债，就把逐脚 clock-to-pin 的问法在现版 routed dcp 上重跑一次。
#
# 判据（与 r119 那轮同一条，出处 report/io/hdmi_cts_source_window.md 表行 #1/#2）；
# 由 build/r132_pin_skew_judge.mjs 落成一格一行，J1–J5 与本节 D1–D3 的对应：
#   D1 互对（data 相对 tmds_clk_p）最差值 <= 0.20 Tcharacter = 4.000 ns ⇒ J2（max 角）+ J3（min 角）
#   D2 对内（同一对 p/n 之间）最差值 <= 0.15 Tbit = 0.300 ns                ⇒ J4
#   D3 每个脚都要真出数：缺任何一脚、任一角都报 NOT_MEASURED，不许当通过   ⇒ J1；上限不许手抄   ⇒ J5
# r119 那轮的读数：互对 0.065 ns、对内 0.001 ns（件 build/evidence/r119_pin_skew_probe*.txt）；
# 新尺子先在 r119 那份件上复现出这两个数，再去吃现版的探针件（复现件在 r132_arm_d_selftest.txt）。
set -u
cd "$(dirname "$0")/.." || exit 1
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then echo "REFUSE: 已经有 Vivado 在飞"; exit 2; fi
if tasklist 2>/dev/null | grep -qiE "^xsimk?\.exe"; then echo "REFUSE: 台架 xsim 还在跑"; exit 2; fi
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp
[ -f "$DCP" ] || { echo "REFUSE: 没有 $DCP（探针读的就是板上那一版的路由）"; exit 2; }
echo "[armD $(date '+%H:%M:%S')] bit=$(md5sum < build/system.bit | cut -c1-12) 探针=build/tcl/probe_tmds_pin_skew.tcl"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_tmds_pin_skew.tcl \
    > build/r132_pin_skew_console.txt 2>&1; rc=$?
grep -a '^PIN|\|^CLKINFO|\|PROBE-REFUSE\|PROBE-SKEW-DONE' build/r132_pin_skew_console.txt \
    > build/evidence/r132_pin_skew_probe.txt
echo "[armD] probe rc=$rc  rows=$(grep -ac '^PIN|' build/evidence/r132_pin_skew_probe.txt)  未量到=$(grep -ac '^PIN|.*NOT_MEASURED' build/evidence/r132_pin_skew_probe.txt)"
node build/r132_pin_skew_judge.mjs | tee build/evidence/r132_arm_d_verdict.txt; jrc=${PIPESTATUS[0]}
# 尺子的红能力每次现跑都自证一遍：造 6 条畸形必须 6 条动红，否则这次判定不算数
node build/r132_pin_skew_judge.mjs --self --probe build/evidence/r119_pin_skew_probe2.txt \
    | tee build/evidence/r132_arm_d_selftest.txt; src=$?
echo "[armD] judge rc=$jrc selftest rc=$src"
[ "$jrc" = 0 ] || { echo "臂 D 判定不是 PASS（rc=$jrc），非零收尾"; exit 1; }
[ "$src" = 0 ] || { echo "臂 D 的尺子红能力没自证（rc=$src），非零收尾"; exit 1; }
exit 0

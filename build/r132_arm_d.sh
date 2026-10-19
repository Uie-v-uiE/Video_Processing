#!/usr/bin/env bash
# build/r132_arm_d.sh —— 臂 D：把 HDMI 源端窗按**正确参考对象**再量一次（r119 那版绑错了钟）
#
# 为什么还要第三臂：VP_R119_TMDS_WINDOW=1 那一轮（件 build/evidence/r132_tmdswindow_*）把 clkout1_1
# 从"无同沿路径"量成 setup -5.408 / hold -1.923 ns，但违例里 Clock Path Skew 单独占 -3.300 ns，
# Requirement 恰好等于一个 4 ns 位周期 —— 那是参考钟对象错了（拿内部串行钟当连接器上的钟），
# 不是对外窗真的差 5.4 ns。规范给的 0.20 Tcharacter 以连接器上的 20 ns 钟为参考，
# 所以候选件的第二版把 create_clock 定义在输出端口 tmds_clk_p 上（src/constraints/r132_hdmi_source_window_v2.xdc）。
#
# 判据沿用 build/r132_timing_round.sh 头部的 P1..P4：声明行在位、八对名册逐格对 r132 基线不劣化、
# clkout1_1 这一族要真量出数（红也是结论）、资源四项念出来。
set -u
cd "$(dirname "$0")/.." || exit 1
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}
[ -x "$V/xvlog" ] || { echo "REFUSE: VP_VIVADO_BIN 里没有 xvlog：$V"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then echo "REFUSE: 已经有 Vivado 在飞"; exit 2; fi
if tasklist 2>/dev/null | grep -qiE "^xsimk?\.exe"; then echo "REFUSE: 台架 xsim 还在跑"; exit 2; fi
BASE=build/evidence/r132_after_roster_probefmt.txt
[ -s "$BASE" ] || { echo "REFUSE: 基线名册不在"; exit 2; }
LOG=build/r132_arm_d.log
OUT=build/isolated_r132_tmv2
say(){ printf '[armD %s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

say "起飞：VP_R132_TMDS_V2=1 → $OUT"
( export VP_R132_TMDS_V2=1 OUT="$OUT"; bash build/roll_isolated.sh ) >> "$LOG" 2>&1; rc=$?
say "roll rc=$rc"
CON="$OUT/build_console.txt"
[ -s "$CON" ] || { say "NOT PROVEN：没有构建控制台"; exit 1; }
grep -qa "SYSTEM BUILD DONE" "$CON" || say "NOT PROVEN：控制台没有 SYSTEM BUILD DONE"
say "声明行：$(grep -ao 'VP_R132_TMDS_V2 [a-zA-Z]*' "$CON" | head -1)"
dcp=$(ls "$OUT"/vivado_proj/*.runs/impl_1/system_top_routed.dcp 2>/dev/null | head -1)
[ -n "$dcp" ] || { say "NOT PROVEN：没有 routed dcp"; exit 1; }
VP_DCP="$dcp" VP_LABEL=r132_tmv2 VP_N=4 "$V/vivado.bat" -mode batch -nojournal \
    -source build/tcl/probe_timing_roster.tcl > build/r132_tmv2_roster_console.txt 2>&1
say "probe rc=$?"
grep -a '^ROSTER|\|^FANOUT|\|^DESIGN|\|^ROSTER_ROWS' build/r132_tmv2_roster_console.txt > build/evidence/r132_tmv2_roster.txt
say "名册 rows=$(grep -ac '^ROSTER|' build/evidence/r132_tmv2_roster.txt)"
bash build/timing_roster_diff.sh "$BASE" build/evidence/r132_tmv2_roster.txt > build/evidence/r132_tmv2_diff_vs_r132.txt 2>&1
say "差分 rc=$?"
rpt=$(ls "$OUT"/timing_summary.rpt 2>/dev/null | head -1)
[ -n "$rpt" ] && cp "$rpt" build/evidence/r132_tmv2_timing_summary.rpt && say "时序摘要已归档"
ut=$(ls "$OUT"/utilization.rpt 2>/dev/null | head -1)
[ -n "$ut" ] && cp "$ut" build/evidence/r132_tmv2_utilization.rpt && say "资源报告已归档"
[ -s build/evidence/r132_tmv2_roster.txt ] || { say "臂 D 没出名册，非零收尾"; exit 1; }
exit 0

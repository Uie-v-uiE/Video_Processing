#!/usr/bin/env bash
# build/r113_chain2.sh —— r113 断点续跑：构建已经过了（12:05），从"上电值重判"接着往下走。
#
# 为什么断：链子在构建后的第一判据上自己断了 —— W2 要"三颗都在"，而网表里 `key_prev_reg`
#   **r112 未修那份就已经是 NO_CELL**（对照 `build/evidence/r113_ff_init.txt`）⇒ 那是我对网表的过期假设，
#   不是修复没上。重推期望之后（见 check_powup_init.sh 里那段注释）：
#   真网表 r113 = W1/W2/W3/W4/W5 全 GREEN（key_stable/sync0/sync1 的 INIT 已经是 1'b1），
#   同一把尺子吃 r112 未修的探针文本 = 三条 RED。⇒ #256 的"最后一环（带常量复位再综合，那个 1 进不进位流）"当场闭掉。
# 这一支还顺手把新落的名册三把接进来：跑一次 probe_timing_roster（改后），与 r112 基线名册做逐域差分。
#   这一步正是"改时序要看全局"的落地件——本轮 WNS 动了没有、其它三域有没有被牺牲，都由差分念，不由我说。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=113
say() { printf '[chain2 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE no Vivado"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then
    say "REFUSE: 已有 Vivado 在飞（名册探针要独占）"; exit 2
fi
PROBE_TXT=build/evidence/r${NN}_ff_init_probe.txt
[ -f "$PROBE_TXT" ] || { say "REFUSE no $PROBE_TXT（探针文本没了就得重问 open_checkpoint）"; exit 2; }
say "身份 bit=$(md5sum < build/system.bit | cut -c1-12) probe=$(md5sum < "$PROBE_TXT" | cut -c1-12)"

# ① 上电值：吃已归档的探针文本重判（同一把尺子、同一份件，不重开 Vivado）
if ROUND=r${NN} bash build/check_powup_init.sh --parse < "$PROBE_TXT" > "build/r${NN}_powup_rejudge.txt" 2>&1; then
    say "上电值判绿（件 build/r${NN}_powup_rejudge.txt）"
else
    say "上电值判红 —— 断链"; grep -a '^POWUP' "build/r${NN}_powup_rejudge.txt" | sed 's/^/[powup] /'
    exit 1
fi
grep -a '^POWUP' "build/r${NN}_powup_rejudge.txt" | sed 's/^/[powup] /'

# ② 只读探针（全局最差 / hold / 每时钟 / 锥）
say "只读探针"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl   > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl  > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=r113_after bash build/pre_readings.sh r113_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$?（对照 build/evidence/r113_before.txt 与 r112_setup_paths_baseline.rpt）"

# ③ 名册：改后那一版（逐时钟 setup+hold + 扇出 + 设计级），然后与 r112 基线逐域差分
say "名册探针 probe_timing_roster.tcl"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl > "build/r${NN}_roster_console.txt" 2>&1; RC=$?
grep -a '^ROSTER|' "build/r${NN}_roster_console.txt" > "build/evidence/r${NN}_after_roster.txt"
grep -a '^FANOUT|' "build/r${NN}_roster_console.txt" >> "build/evidence/r${NN}_after_roster.txt"
grep -a '^DESIGN|' "build/r${NN}_roster_console.txt" >> "build/evidence/r${NN}_after_roster.txt"
NR=$(grep -ac '^ROSTER|' "build/evidence/r${NN}_after_roster.txt" || echo 0)
say "roster rc=$RC rows=$NR（探针自己念 ROSTER_ROWS=$(grep -ao 'ROSTER_ROWS=[0-9]*' "build/r${NN}_roster_console.txt" | tail -1)）"
if [ "$NR" -ge 8 ]; then
    bash build/timing_roster_diff.sh build/evidence/r113_before_roster.txt build/evidence/r${NN}_after_roster.txt \
        > "build/evidence/r${NN}_roster_diff.txt" 2>&1
    say "名册差分落 build/evidence/r${NN}_roster_diff.txt：$(grep -a '^ROSTERDIFF-SUMMARY' "build/evidence/r${NN}_roster_diff.txt")"
    grep -a '^ROSTERDIFF' "build/evidence/r${NN}_roster_diff.txt" | sed 's/^/[roster] /'
else
    say "⚠ 名册行数 $NR < 8：这一轮的逐域代价**没法判**（不许拿全局 WNS 代替，记进 ISSUES）"
fi

# ④ 快车道（31 支）
say "快车道"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L 绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt") 挡=$(grep -c 'LANE BLOCKED' "build/r${NN}_lane_after.txt")"
grep -a "LANE-SUMMARY" "build/r${NN}_lane_after.txt"

# ⑤ 顶层台架 + rim（一轮只付这一次）
say "顶层台架（实测约 70–128 分钟）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; say "tb_v98 rc=$?"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# ⑥ 门禁（两跑要逐字节一致）
say "门禁"
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}.txt" "/tmp/kx/g_r${NN}2.txt" \
    && say "门禁两跑逐字节一致 rc=$G" || say "⚠ 门禁两跑不一致（D1c 读盘上那份，#242 第 1 条）——写回后重跑直到一致"
cp -f "/tmp/kx/g_r${NN}2.txt" "build/r${NN}_gates.txt"
say "绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "链2结束：采纳走 build/r113_adopt_checklist.md 的六步"

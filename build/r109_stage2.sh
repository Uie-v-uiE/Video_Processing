#!/usr/bin/env bash
# build/r109_stage2.sh —— 把 r109 那条链的**台架阶段**重跑一遍。
#   为什么需要它：00:05 那一次链子的台架阶段被**我自己的另一支 xsim**挡住了 —— 我在链子的探针阶段还
#   并发跑了 `build/f2e_preverify.sh`（拷贝树的差分预验），`sim/run_one.sh` 的"已有 xsim 在跑"守卫
#   于是把快车道、顶层台架、边缘条带全部挡成 rc=2/rc=3。守卫work得很好（`LANE-REFUSE` 说得清清楚楚，
#   没有把 20 支挡门读成 20 支判红），但结论是：**构建与只读探针是真的跑完了，台架阶段一份都没跑**。
#   ⚠ 这条教训要钉住：链子在飞期间，我不许再起第二支 xsim —— 预验要么排在链子之前，要么等它结束。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=109
say() { printf '[stage2 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# 门口验现场：有活的 xsim 就直接不起飞（否则整条阶段又会被挡成一片 rc=3）
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    say "STAGE2-REFUSE: 已经有 xsim 在跑，这一支阶段跑下去只会得到一片"被挡在门外"。先弄清是谁的再杀。"
    exit 2
fi

say "快车道（分钟级，逐刀等价性）"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L 绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt") 挡=$(grep -c 'LANE BLOCKED' "build/r${NN}_lane_after.txt")"
grep -a "LANE-SUMMARY" "build/r${NN}_lane_after.txt"

say "顶层台架 tb_v98_top_seam（实测约 127 分钟，一轮只付这一次）—— C5c 与新增的 C12a/C12b/C12c/C12pre 都在这一份 log 里"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; R=$?
say "顶层台架 rc=$R（0=绿 3=判红 2=REFUSE 4=认不出判定）"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"

say "边缘条带台架 + 报告"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

say "门禁（两步：先 /tmp 再 cp 到位，#229）"
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G —— 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
# 第二跑：doc_currency 的 D1b/D1c 读的就是刚写下的这份，需要一次收敛（首轮自红是文档化的形状）
bash build/gates.sh > "/tmp/kx/g_r${NN}_2.txt" 2>&1; G2=$?
say "门禁第二跑 rc=$G2 绿=$(grep -c ' PASS$' "/tmp/kx/g_r${NN}_2.txt") 红=$(grep -c ' FAIL$' "/tmp/kx/g_r${NN}_2.txt")"
diff -q "/tmp/kx/g_r${NN}.txt" "/tmp/kx/g_r${NN}_2.txt" >/dev/null && say "两跑逐字节一致" || say "两跑不一致 —— 逐行 diff 之后才能念结论"
say "阶段结束（采纳判读看 build/r${NN}_lane_after.txt / r${NN}_tb98_console.txt / r${NN}_gates.txt 与 build/r${NN}_clk01_probe_console.txt）"

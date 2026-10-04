#!/bin/bash
# build/r98_chain.sh —— r98 这一夜的"构建完 → 台架 → 门禁 → 试冻结"自动接上（无人值守段）。
#
# 为什么要它：tb_v98 一跑就是 2 小时，人守着就是等着犯错（历史上"gates 全绿 + 顶层台架红着"
# 同时成立的那几天就是断在这里）。这一段只做四件事，每一步都把 console 落到 build/ 里，
# **不改任何 src/rtl**（改源是下一轮的事），也不写文档。
#
#   用法：nohup bash build/r98_chain.sh > /tmp/kx/r98_chain_console.txt 2>&1 &
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
export VP_VIVADO_BIN="${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}"
NN=98
WRAP=/tmp/kx/r${NN}_wrap.log
step() { echo "==== $(date -Iseconds) $*"; }

# ① 等构建：只认成功 token，不认退出码（历史上两条 sibling 脚本 die 在 add_files 却退 0）
step "等 r98 构建落位（盯 $WRAP 的 SYSTEM BUILD DONE）"
for i in $(seq 1 240); do
    if grep -aq "SYSTEM BUILD DONE" "$WRAP" 2>/dev/null; then step "构建完成"; break; fi
    if grep -aq "^ERROR" "$WRAP" 2>/dev/null; then step "构建里有 ERROR，链停在这里，不后台改任何东西"; exit 1; fi
    sleep 30
done
grep -aq "SYSTEM BUILD DONE" "$WRAP" || { step "等构建超时（2 小时），链停在这里"; exit 1; }

# ② 边缘条带台架 + 它的凭据（门禁 15b 认这一份）
step "跑 tb_edge_rim"
bash build/sim/run_one.sh tb_edge_rim > "build/r${NN}_tb_edge_rim_console.txt" 2>&1
RIMRC=$?
step "tb_edge_rim rc=$RIMRC，出报告"
ROUND=$NN bash build/rim_report.sh > "build/r${NN}_rim_report_step.txt" 2>&1

# ③ 顶层整屏台架（2 小时那一支）+ 门禁第 15 项要的报告
step "跑 tb_v98_top_seam（约 2 小时）"
bash build/sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1
TBRC=$?
step "tb_v98 rc=$TBRC，出报告"
bash build/tb98_report.sh > "build/r${NN}_tb98_report_step.txt" 2>&1

# ④ 门禁 + 试冻结（红就照红，别把红的东西冻结下来）
step "门禁 20 项 → build/r${NN}_gates.txt"
bash build/gates.sh > "build/r${NN}_gates.txt" 2>&1
GRC=$?     # ⚠ 必须先存：下一行是 step（另一个命令），$? 到那里就不是门禁的了——今晚我自己撞过两次
step "门禁 rc=$GRC（明细行：$(grep -ac ' PASS$' build/r${NN}_gates.txt) 绿 / $(grep -ac ' FAIL$' build/r${NN}_gates.txt) 红）"
step "试冻结（C5c 还红着的话这里必须 REFUSE）"
bash build/freeze_evidence.sh $NN > "build/r${NN}_freeze_attempt.txt" 2>&1
step "链尾状态：$(tail -1 build/r${NN}_gates.txt | tr -d '\r')"
step "没做的：L1 全量回归（命令我没在 build/ 里找着，不猜）、上板与板级复验、重导提交包 —— 都留给人做"

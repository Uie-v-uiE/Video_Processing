#!/bin/bash
# 用途：build/r99_chain.sh —— r99 这一轮的"构建 → 台架 → 门禁 → 试冻结"无人值守段
# 输入：命令行参数
# 输出：stdout
# 退出码：1=ERROR 2=非 0 分支（该文件 exit 2 那一行）
# build/r99_chain.sh —— r99 这一轮的"构建 → 台架 → 门禁 → 试冻结"无人值守段。
#
# 与 build/r98_chain.sh 的差别只有两处，都是 r98 那一跑撞出来的：
#   ① 构建由本脚本自己起（r98 是人在前面手动起、链在后面等）；
#   ② rim 报告的 ROUND 传 `r${NN}` 而不是裸数字 —— r98 传的是 `98`，产出的 `tb_edge_rim_98.txt`
#      门禁按 `tb_edge_rim_r*.txt` 取不到，退回去念了 r97 那份，红得看着合理其实找错文件（ISSUES #211）。
#
# 这一段不改任何 src/rtl，也不写文档；红就照红。
#   用法：nohup bash build/r99_chain.sh > /tmp/kx/r99_chain_console.txt 2>&1 &
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
export VP_VIVADO_BIN="${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}"
NN=101
WRAP=/tmp/kx/r${NN}_wrap.log
step() { echo "==== $(date -Iseconds) $*"; }

mkdir -p /tmp/kx
# ① 起构建。成功只认 token，不认退出码（两条 sibling 脚本历史上 die 在 add_files 却退 0）。
step "起 r${NN} 构建（build/tcl/build_system_axigpio.tcl）"
( cd build/tcl && "$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build_system_axigpio.tcl ) \
    > "$WRAP" 2>&1 &
BUILD_PID=$!
step "构建 pid=$BUILD_PID，日志 $WRAP"

# ② 等构建落位（最多 3 小时）
for i in $(seq 1 360); do
    if grep -aq "SYSTEM BUILD DONE" "$WRAP" 2>/dev/null; then step "构建完成"; break; fi
    if grep -aq "^ERROR" "$WRAP" 2>/dev/null; then
        step "构建里有 ERROR，链停在这里，不动任何东西"; exit 1
    fi
    sleep 30
done
grep -aq "SYSTEM BUILD DONE" "$WRAP" || { step "等构建超时（3 小时），链停在这里"; exit 1; }

# ③ 边缘条带台架 + 它的凭据（门禁 15b 认这一份）
step "跑 tb_edge_rim"
bash build/sim/run_one.sh tb_edge_rim > "build/r${NN}_tb_edge_rim_console.txt" 2>&1
RIMRC=$?
step "tb_edge_rim rc=$RIMRC，出报告"
ROUND=r${NN} bash build/rim_report.sh > "build/r${NN}_rim_report_step.txt" 2>&1

# ④ 顶层整屏台架（2 小时那一支）+ 门禁第 15 项要的报告
step "跑 tb_v98_top_seam（约 2 小时）"
bash build/sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1
TBRC=$?
step "tb_v98 rc=$TBRC，出报告"
bash build/tb98_report.sh > "build/r${NN}_tb98_report_step.txt" 2>&1

# ⑤ 门禁 + 试冻结
step "门禁 20 项 → build/r${NN}_gates.txt"
bash build/gates.sh > "build/r${NN}_gates.txt" 2>&1
GRC=$?     # 必须先存：下一行是 step，$? 到那里就不是门禁的了
step "门禁 rc=$GRC（明细行：$(grep -ac ' PASS$' build/r${NN}_gates.txt) 绿 / $(grep -ac ' FAIL$' build/r${NN}_gates.txt) 红）"
step "试冻结（C5c 还红着的话这里必须 REFUSE）"
bash build/freeze_evidence.sh $NN > "build/r${NN}_freeze_attempt.txt" 2>&1
step "#209 的账：r99 的 cdc.rpt 与采纳版(r75)的 Critical 配对差集必须为空，且不再有 CDC-10 行"
step "链尾状态：$(tail -1 build/r${NN}_gates.txt | tr -d '\r')"
step "没做的：L1 全量回归、上板与板级复验、重导提交包、文档数字刷新 —— 都留给人做"

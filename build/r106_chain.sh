#!/usr/bin/env bash
# build/r106_chain.sh —— r106 这一轮的后续链（等构建 → 时序探针 → 顶层台架+报告 → 边缘台架+报告 → 门禁）
#
# 为什么要它（规矩 24(e)）：构建 25 分钟、顶层台架 100 分钟，逐步轮询会把预算烧在等待上；
# 把整条链编成一个后台实例，每一步都**用退出码/标记文件判定**，不靠人（也不靠我）临场读字符串。
# 关键守卫：
#   ① 必须等到 `SYSTEM BUILD DONE` 才继续 —— 否则后面的门禁会读到**上一版**的报告；
#   ② 构建失败（`VIVADO_EXIT` 非 0）立刻断链，不产任何凭据；
#   ③ 台架与报告的顺序：报告脚本读的是 run.log，所以先 run_one 再 report；
#   ④ 门禁输出落到 build/r106_gates.txt —— D1b/D1c 认的就是"戳着板上那块 bit 的那一份 rNN_gates.txt"。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
CON=build/r106_build_console.txt
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

for i in $(seq 1 100); do
    grep -q "SYSTEM BUILD DONE" "$CON" 2>/dev/null && break
    grep -q "^VIVADO_EXIT=[1-9]" "$CON" 2>/dev/null && { say "构建失败（VIVADO_EXIT 非 0）—— 断链，不产凭据"; exit 1; }
    sleep 30
done
grep -q "SYSTEM BUILD DONE" "$CON" || { say "等不到构建完成 —— 断链"; exit 1; }
say "构建完成，开始只读时序探针"

"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  > build/r106_critpath_console.txt 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl > build/r106_holdpath_console.txt 2>&1; say "hold_paths rc=$?"

bash sim/run_one.sh tb_v98_top_seam > build/r106_tb98_console.txt 2>&1; R=$?
say "顶层台架 rc=$R（3=判红，0=绿；C8c 八档的读数就在同一份 log 里）"
bash build/tb98_report.sh > build/r106_tb98report_console.txt 2>&1; say "tb98_report rc=$?"

bash sim/run_one.sh tb_edge_rim > build/r106_rim_console.txt 2>&1; say "边缘条带台架 rc=$?"
ROUND=r106 bash build/rim_report.sh > build/r106_rimreport_console.txt 2>&1; say "rim_report rc=$?"

bash build/gates.sh > build/r106_gates.txt 2>&1; G=$?
say "门禁 rc=$G —— 末行：$(tail -1 build/r106_gates.txt | cut -c1-120)"
say "链结束"

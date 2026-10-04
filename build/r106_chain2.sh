#!/usr/bin/env bash
# build/r106_chain2.sh —— 接上被我自己撞掉的那两步（顶层台架/边缘台架在 12:25 都吃了 rc=2 REFUSE）
#
# 为什么要有"等 xsim 死透"这一道：run_one.sh 的并发守卫就是照 `/tmp/kx/<tb>.run` 的活体判的，
# 上一轮我在同一时刻跑 12 支台架的复查批，正好把链子里这两步挡掉了（#173 记的那次自伤）。
# 所以这一步的判据是"进程表里没有 xsim.exe / xsimk.exe"，不是我睡够几分钟。
set -u
cd "$(dirname "$0")/.."
say() { printf '[chain2 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
alive() { tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -c "^xsim.exe"; }
alivek() { tasklist //FI "IMAGENAME eq xsimk.exe" 2>/dev/null | grep -c "^xsimk.exe"; }

for i in $(seq 1 260); do
    [ "$(alive)" = 0 ] && [ "$(alivek)" = 0 ] && break
    sleep 30
done
[ "$(alive)" = 0 ] && [ "$(alivek)" = 0 ] || { say "等不到 xsim 退出（>130 分钟）—— 断链，不产凭据"; exit 1; }
say "xsim 已退出，开始顶层台架报告"

bash build/tb98_report.sh > build/r106b_tb98report_console.txt 2>&1; say "tb98_report rc=$?（新报告应盖 tb_md5=1c0c56bae0e0）"

bash build/sim/run_one.sh tb_edge_rim > build/r106b_rim_console.txt 2>&1; say "边缘条带台架 rc=$?（3=判红 2=REFUSE 0=绿）"
ROUND=r106 bash build/rim_report.sh > build/r106b_rimreport_console.txt 2>&1; say "rim_report rc=$?"

bash build/gates.sh > build/r106_gates.txt 2>&1; G=$?
say "门禁 rc=$G —— 末行：$(tail -1 build/r106_gates.txt | cut -c1-160 | iconv -f UTF-8 -t UTF-8//IGNORE)"
say "链2结束"

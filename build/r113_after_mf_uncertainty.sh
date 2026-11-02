#!/usr/bin/env bash
# 用途：把 #265 那支"同一严口径 hold 体检"排到复制 A/B 之后
# 输入：命令行参数
# 输出：build/evidence/r113_uncertainty_run.txt
# 退出码：3=非 0 分支（该文件 exit 3 那一行）
# build/r113_after_mf_uncertainty.sh —— 把 #265 那支"同一严口径 hold 体检"排到复制 A/B 之后
#
#   为什么要串在 A/B 之后而不是并行：这台机 15.7 G 内存，开 routed dcp 的 Vivado 报告作业要 2~3 G，
#   两个 Vivado 抢内存 + 抢实现线程会把两边的墙钟与结论一起弄脏（前一支排期脚本
#   `build/r113_after_chain_experiments.sh` 已经在跑名册重取与 set… 也就是 #264 的复制 A/B）。
#   所以这里的"轮到我了"条件是**两条**：`build/evidence/r114_mf/verdict.txt` 出现（上一支真的判完了）
#   **且** 没有 vivado/xsim 在飞。只问进程会被"上一支结束、下一支还没起"的空隙骗到（同一坑第二犯）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
VERDICT=build/evidence/r114_mf/verdict.txt
say() { printf '[un %s] %s\n' "$(date +%m-%d_%H:%M:%S)" "$*"; }
deadline=$(( $(date +%s) + 6*3600 ))
say "等上一支排期判完（$VERDICT 出现）且机器空，最长 6 小时"
while : ; do
    if [ -f "$VERDICT" ] && ! tasklist 2>/dev/null | grep -qiE '^(xsim|xsimk|vivado)\.exe'; then
        say "两条都成立：verdict 在盘上，且没有 vivado/xsim 在飞"; break
    fi
    say "还在等：verdict=$([ -f "$VERDICT" ] && echo yes || echo no) 进程=$(tasklist 2>/dev/null | grep -aiE '^(xsim|xsimk|vivado)\.exe' | awk '{print $1}' | sort -u | tr '\n' ' ')"
    if [ "$(date +%s)" -gt "$deadline" ]; then say "TIMEOUT: 没等到，不硬抢"; exit 3; fi
    sleep 60
done
bash build/uncertainty_uniform_ab.sh > build/evidence/r113_uncertainty_run.txt 2>&1
RC=$?
say "体检 rc=$RC"
say "  逐域读数：$(grep -a '^UNC|' build/evidence/r113_uncertainty_console.txt | tr '\n' ' ')"
say "  判据：$(grep -a '^UNCCHK' build/evidence/r113_uncertainty_run.txt | grep -av 'SUMMARY' | tr '\n' ';')"
say "  结论：$(grep -a '^UNCCHK-SUMMARY' build/evidence/r113_uncertainty_run.txt | tail -1)"
say "  口径提醒：after 是同一悲观带下的 what-if（没重跑布线），负余量是发现、不是红"
exit $RC

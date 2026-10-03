#!/usr/bin/env bash
# build/r117_wait_both.sh —— 等两件东西回来：r117 复制滚的判读件、r116 的门禁件。
# 只等不判：读数一律由件本身给（提示词 §7 L2：负结果也是产出物，先把件拿回来再说话）。
set -u
cd "$(dirname "$0")/.."
for i in $(seq 1 240); do
    a=0; b=0
    [ -s build/evidence/r117_repl3/B/timing_summary.rpt ] && a=1
    [ -s build/r116_gates.txt ] && b=1
    if [ $a -eq 1 ] && [ $b -eq 1 ]; then break; fi
    sleep 30
done
echo "WAIT_DONE $(date +%H:%M:%S) repl3=$a gates=$b"
echo "--- repl3 mechanism ---"
grep -a "^R3_\|^WPS3" build/evidence/r117_repl3/B_console.txt 2>/dev/null | tail -12
echo "--- repl3 rows vs control A rows ---"
grep -a "^ROW " build/evidence/r117_repl3/B_console.txt 2>/dev/null | head -8
grep -a "^ROW " build/evidence/r117_fb_pblock/A/roll_console.txt 2>/dev/null | head -8
echo "--- gates tail ---"
grep -a -E " PASS$| FAIL$|门禁|SUMMARY" build/r116_gates.txt 2>/dev/null | tail -30

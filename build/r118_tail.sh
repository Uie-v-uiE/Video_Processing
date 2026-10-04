#!/usr/bin/env bash
# build/r118_tail.sh —— 板已经刷好并复验过（见 build/evidence/r118_board/board_now.txt），
# 这一支只做剩下的四步：改口（带三道尺子）→ 最终门禁两跑 → 重导提交包 → 提交并推送。
# 每一步不过就硬停，不带未核过的首页往下走。
set -u
cd "$(dirname "$0")/.."
say(){ printf '[tail %s] %s
' "$(date +%H:%M:%S)" "$*" | tee -a build/r118_finish_console.txt; }
VP_CLAIM=24,23,1 python build/r118_rotate.py > build/evidence/r118_board/rotate_console.txt 2>&1
R=$?
say "rotate rc=$R $(grep -a 'ROTATE-APPLY\|MARKER\|CLAIM\|RULER\|NOTE' build/evidence/r118_board/rotate_console.txt | tr '
' ' ')"
if [ "$R" != 0 ]; then say "停：改口没过尺子，不跑最终门禁、不提交"; exit 4; fi
say "最终门禁两跑"
bash build/gates.sh > /tmp/kx/ga.txt 2>&1
A=$?
bash build/gates.sh > /tmp/kx/gb.txt 2>&1
B=$?
if cmp -s /tmp/kx/ga.txt /tmp/kx/gb.txt; then ID=identical; else ID=different; fi
cp -f /tmp/kx/ga.txt build/r118_gates_final.txt
G=$(grep -c " PASS$" build/r118_gates_final.txt)
RED=$(grep -c " FAIL$" build/r118_gates_final.txt)
say "最终门禁 rcA=$A rcB=$B 两跑=$ID 绿=$G 红=$RED 红项：$(grep -a ' FAIL$' build/r118_gates_final.txt | tr '
' '|')"
say "重导提交包"
bash build/make_submission.sh > /tmp/kx/sub.txt 2>&1
S=$?
N=$(find ../submission -type f 2>/dev/null | wc -l)
say "make_submission rc=$S 盘上文件数=$N"
if [ "$RED" = 1 ] && [ "$ID" = identical ] && [ "$S" = 0 ]; then
    say "条件满足：落提交并推送"
    python build/r118_commit.py >> build/r118_finish_console.txt 2>&1
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if git push origin main > /tmp/kx/push.txt 2>&1; then say "PUSH-OK try=$i"; break; fi
        say "push try=$i 失败：$(tail -1 /tmp/kx/push.txt)"
        sleep 40
    done
    say "$(git status -sb | head -1)"
else
    say "不提交：最终门禁红数不是 1、或两跑不一致、或提交包导出失败 —— 交回人判断"
fi
say "TAIL END"

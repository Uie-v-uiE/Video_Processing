#!/usr/bin/env bash
# build/r118_tail3.sh —— r118 最后一段：改口后的门禁两跑 → 重导提交包 → 流水补记 → 提交并推送。
# 门禁不过（红数 != 1 或两跑不一致）就把首页三件套 checkout 回去：不带未核过的句子过夜。
set -u
cd "$(dirname "$0")/.."
say(){ printf "[t3 %s] %s
" "$(date +%H:%M:%S)" "$*" | tee -a build/r118_finish_console.txt; }
[ -f build/r117_docrotated.marker ] || { say '停：没有改口标记，不跑最终门禁'; exit 4; }
say '最终门禁两跑（文档已冻结）'
bash build/gates.sh > /tmp/kx/fA.txt 2>&1
A=$?
bash build/gates.sh > /tmp/kx/fB.txt 2>&1
B=$?
if cmp -s /tmp/kx/fA.txt /tmp/kx/fB.txt; then ID=identical; else ID=different; fi
G=$(grep -c ' PASS$' /tmp/kx/fA.txt); R=$(grep -c ' FAIL$' /tmp/kx/fA.txt)
say '最终门禁 rcA=$A rcB=$B 两跑=$ID 绿=$G 红=$R 红项：$(grep -a " FAIL$" /tmp/kx/fA.txt | tr "
" "|")'
if [ "$R" != 1 ] || [ "$ID" != identical ]; then
    say '门禁不吻合：回退首页三件套，不改口不提交（板上仍是 r118，读数以件为准）'
    git checkout -- README.md readme.en.md data/metrics.csv
    say 'TAIL3 END (reverted)'; exit 5
fi
cp -f /tmp/kx/fA.txt build/r118_gates_final.txt
cp -f /tmp/kx/fA.txt build/r118_gates.txt
bash build/make_submission.sh > /tmp/kx/sub3.txt 2>&1
S=$?
say 'make_submission rc=$S 盘上文件数='$(find ../submission -type f 2>/dev/null | wc -l)
python build/r118_commit.py >> build/r118_finish_console.txt 2>&1
for i in 1 2 3 4 5 6 7 8; do
    if git push origin main > /tmp/kx/push3.txt 2>&1; then say "PUSH-OK try=$i"; break; fi
    say "push try=$i 失败：$(tail -1 /tmp/kx/push3.txt)"; sleep 35
done
say "$(git status -sb | head -1)"
say 'TAIL3 END'

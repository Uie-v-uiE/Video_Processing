#!/usr/bin/env bash
# 用途：破掉 D1c 的自指：先改口，再定版一份能让首页吻合的门禁件，然后两跑核对
# 输入：命令行参数
# 输出：stdout
# 退出码：4=非 0 分支（该文件 exit 4 那一行）
# build/r118_final.sh —— 破掉 D1c 的自指：先改口，再定版一份能让首页吻合的门禁件，然后两跑核对。
set -u
cd "$(dirname "$0")/.."
O=build/evidence/r118_board
VP_CLAIM=24,23,1 python build/r118_rotate.py > $O/rotate_final.txt 2>&1; R=$?
echo rotate_rc=$R marker=$([ -f build/r117_docrotated.marker ] && echo YES || echo NO)
if [ $R -ne 0 ]; then echo STOP_rotate; exit 4; fi
bash build/gates.sh > $O/g1.txt 2>&1
cp -f $O/g1.txt build/r118_gates.txt
bash build/gates.sh > $O/g2.txt 2>&1
bash build/gates.sh > $O/g3.txt 2>&1
ID=$(cmp -s $O/g2.txt $O/g3.txt && echo identical || echo different)
G2=$(grep -c ' PASS$' $O/g2.txt); R2=$(grep -c ' FAIL$' $O/g2.txt)
echo gates2_3=$ID green=$G2 red=$R2
grep -a ' FAIL$' $O/g2.txt
if [ "$R2" = 1 ] && [ "$ID" = identical ]; then
    cp -f $O/g2.txt build/r118_gates.txt; cp -f $O/g2.txt build/r118_gates_final.txt
    bash build/make_submission.sh > $O/sub.txt 2>&1; S=$?
    echo package_rc=$S files=$(find ../submission -type f 2>/dev/null | wc -l)
    python build/r118_commit.py > $O/commit.txt 2>&1; echo commit_rc=$?
    tail -3 $O/commit.txt
    for i in 1 2 3 4 5; do git push origin main > $O/push.txt 2>&1 && { echo PUSH-OK; break; }; sleep 25; done
    git status -sb | head -1
    echo FINAL-END
else
    echo NOT_YET: 门禁红数或两跑不吻合，回退首页并保留标记之外的一切
    rm -f build/r117_docrotated.marker
    git checkout -- README.md README_EN.md data/metrics.csv
    echo FINAL-END-REVERTED
fi

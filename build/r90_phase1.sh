#!/bin/bash
# 用途：等当前这一跑 tb_v98 结束，并立刻给它出一份**只对"拆分布尔树那一版"有效**的中期报告
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 4=非 0 分支（该文件 exit 4 那一行）
# build/r90_phase1.sh —— 等当前这一跑 tb_v98 结束，并立刻给它出一份**只对"拆分布尔树那一版"有效**的中期报告。
#
# 为什么要等：`build/sim/run_one.sh` 的门口规矩是"同一时刻只能有一个 xsim 写 run.log"，
# 而现在这一跑是 r89/r90 判定"三块拆分本身有没有把功能弄坏"的唯一凭据 —— 它跑完之前
# 动 `src/rtl` 会让这份报告的 `rtl_md5` 与树里的现值对不上（那是规矩，不是猜测）。
# 所以：先把这一跑收进报告，再由人决定下一步改哪一行。
#
# 跑法：bash build/r90_phase1.sh        （最长等 3 小时，超时不硬收）
set -u
cd "$(dirname "$0")/.." || exit 1
LOG=build/r90_phase1.log
SRC=/tmp/kx/tb_v98_top_seam.run/run.log

echo "[phase1] start $(date '+%F %T')" >> "$LOG"
n=0
while tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; do
    sleep 30
    n=$((n + 1))
    if [ $((n % 10)) -eq 0 ]; then
        nl=$(grep -acE "^(PASS|FAIL)" "$SRC" 2>/dev/null)
        [ -z "$nl" ] && nl=0
        echo "[phase1] 还在跑：已等 $((n / 2)) 分钟，判据行数=$nl" >> "$LOG"
    fi
    if [ $n -gt 360 ]; then
        echo "[phase1] GIVE UP：等了 3 小时 xsim 还在，不产出报告（$(date '+%F %T')）" >> "$LOG"
        exit 4
    fi
done
echo "[phase1] xsim 已退出 $(date '+%F %T')，收报告" >> "$LOG"
bash build/tb98_report.sh >> "$LOG" 2>&1
rc=$?
cp build/tb_v98_report.txt build/r90_splitonly_tb98.txt
echo "[phase1] rc=$rc  已另存 build/r90_splitonly_tb98.txt" >> "$LOG"
grep -acE "^(PASS|FAIL)" build/r90_splitonly_tb98.txt >> "$LOG" 2>/dev/null
grep -aE "^FAIL|RESULT" build/r90_splitonly_tb98.txt >> "$LOG" 2>&1
echo "[phase1] READY_FOR_NEXT_EDIT $(date '+%F %T')" >> "$LOG"

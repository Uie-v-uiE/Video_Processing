#!/bin/bash
# build/rim_report.sh —— 把边缘条带台架 `tb_edge_rim` 的 console 收成门禁第 16 项要的凭据。
#
#   bash build/rim_report.sh [那份 run.log]        # 默认 /tmp/kx/tb_edge_rim.run/run.log
#
# 为什么单开一个脚本（`tb98_report.sh` 不是同一件事）：门禁那两项认的是**三份 md5 + 一行汇总**，
# 而 md5 必须取自"跑的那一天"留下的 `prov.txt`（`build/sim/run_one.sh` 在编译**之前**写的）。
# 事后拿现树重算再盖到旧日志上，正是这一项要防的那件事（#88 的教训：
# "gates 14/14 与唯一例化顶层的台架红了几天同时成立"）。
# 输出按轮次号命名 `build/tb_edge_rim_rNN.txt`，门禁自己取 `sort -V` 的最新一份。
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC=${1:-/tmp/kx/tb_edge_rim.run/run.log}
ROUND=${ROUND:-r90}
# #211：轮次号必须是 `rNN`。r98 那一跑链里传的是裸数字 `98`，于是产出 `tb_edge_rim_98.txt`——
# 门禁按 `tb_edge_rim_r*.txt` + `sort -V` 取最新，看不见这份新凭据，退回去读了 `tb_edge_rim_r97.txt`，
# 报出来的是"RTL 不符（报告=45e09e8b3b9d 当前=8fa1b046461a）"这种**看着合理但其实找错文件**的红。
# 这里宁可拒绝执行：静默把 98 补成 r98 会让调用方的错误继续存在到下一次。
case "$ROUND" in
    r[0-9]*) ;;
    *) echo "FATAL ROUND 必须是 rNN 形状（当前='$ROUND'），否则产出的文件名门禁取不到：见 ISSUES #211"; exit 2;;
esac
OUT=$ROOT/build/tb_edge_rim_${ROUND}.txt
cd "$ROOT" || exit 2
[ -f "$SRC" ] || { echo "FATAL 读不到 $SRC"; exit 2; }
PROV=$(dirname "$SRC")/prov.txt
if [ -f "$PROV" ]; then
    TOP=$(sed -n 's/^top_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    TB=$(sed -n 's/^tb_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    RTL=$(sed -n 's/^rtl_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    WHEN=$(sed -n 's/^date=\(.*\)$/\1/p' "$PROV" | head -1)
else
    echo "REFUSE: 没有 $PROV —— 这一跑不是 run_one.sh 起的，出处认不了，不出报告"
    exit 3
fi
{
    echo "fpver=$(sed -n 's/^fpver=\(.*\)$/\1/p' "$PROV" | head -1)"
    echo "top_md5=$TOP"
    echo "tb_md5=$TB"
    echo "rtl_md5=$RTL"
    echo "date=$WHEN"
    grep -aE "^(PASS |FAIL |RESULT |D[0-9]|R[0-9]|INFO )" "$SRC"
} > "$OUT"
echo "WROTE $OUT ($(grep -ac '' "$OUT") 行) rtl_md5=$RTL"
tail -2 "$OUT"

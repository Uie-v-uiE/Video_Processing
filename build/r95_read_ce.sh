#!/bin/bash
# 用途：r95 那两个"读报告"的函数的**正控制**（改尺子先给自己的尺子跑一遍）
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=REFUSE
# build/r95_read_ce.sh —— r95 那两个"读报告"的函数的**正控制**（改尺子先给自己的尺子跑一遍）。
# 为什么单独一个文件：这两个函数是采纳判据的唯一入口，它们读错行 = 整轮判定作废。
# 第一版我自己写的正则在 r94 的 timing_summary.rpt 上读出 `-0.490 u_pl/u_bilin/u_fb/lo_reg_0_63`
# —— 那是路径表里的一行而不是摘要行；换成 r91 那份被验证过的正则之后这条才立得住（见 ISSUES #163 同族）。
set -u
cd "$(dirname "$0")/.." || exit 1
SRC=build/r95_timing_round.sh
T=${1:-build/timing_summary.rpt}        # 默认拿 r94 的正式报告当已知答案
U=${2:-build/utilization.rpt}
[ -f "$T" ] && [ -f "$U" ] || { echo "REFUSE: 报告不在（$T / $U）"; exit 2; }

# 把被测函数从脚本里抠出来定义进本 shell（**不复制实现**，复制就会漂）
eval "$(sed -n '/^read_timing() {/,/^}/p;/^read_bram() {/,/^}/p' "$SRC")"

fail=0
row=$(read_timing "$T")
bram=$(read_bram "$U")
echo "read_timing -> [$row]"
echo "read_bram   -> [$bram]"
set -- $row
[ $# -eq 7 ] || { echo "FAIL 字段数：期望 7，实得 $#"; fail=1; }
for v in "$@"; do
    if [ -z "$v" ]; then echo "FAIL 有一个字段读空"; fail=1
    else case "$v" in *[!0-9.?|+-]*) echo "FAIL 字段不像数：$v"; fail=1;; esac; fi
done
# 已知的 r94 期望值（只有拿默认报告时才钉死；换报告就只判形状）
if [ "$T" = "build/timing_summary.rpt" ]; then
    [ "$1" = "0.553" ] && [ "$2" = "0.049" ] && [ "$3" = "0" ] && [ "$5" = "50883" ] \
        || { echo "FAIL 设计行不等于 r94 的已知数（WNS=$1 WHS=$2 失败=$3 总数=$5）"; fail=1; }
    [ "$6" = "0.553" ] && [ "$7" = "0.049" ] \
        || { echo "FAIL eth_rxc 行不等于 r94 的已知数（$6 / $7）"; fail=1; }
    [ "$bram" = "95" ] || { echo "FAIL BRAM 期望 95，实得 [$bram]"; fail=1; }
fi
# 阴性对照：报告不存在时必须返回空串，**不许把"读不到"当"读到 0"**
if [ -n "$(read_timing build/no_such_report.rpt)" ]; then echo "FAIL 缺报告却读出了数"; fail=1; fi
if [ -n "$(read_bram build/no_such_report.rpt)" ]; then echo "FAIL 缺报告却读出了 BRAM"; fail=1; fi

if [ $fail -eq 0 ]; then echo "VERDICT r95_read_ce PASS（形状 + r94 已知数 + 缺报告三条都过）"
else echo "VERDICT r95_read_ce FAIL"; fi
exit $fail

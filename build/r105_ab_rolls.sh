#!/bin/bash
# 用途：r105 时序 A/B：把 #141 那一刀的"+0.204 ns"对着**放置抖动**量到底
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=REFUSE
# r105 时序 A/B：把 #141 那一刀的"+0.204 ns"对着**放置抖动**量到底。
#
# 为什么要它：r104 采纳 #141 之后，`build/isolated_r104_141` 那次隔离 roll 读到 WNS 0.812，
# 而正式 r103 是 0.608。按规矩 35，一次构建的 WNS 绝对差不算收益——同一条路的放置抖动
# 实测摆过 0.4 ns，0.204 落在里面。要判"#141 到底有没有用"，唯一诚实的做法是
# **同一棵树滚多次**看散布，再用**只回退一个文件**的树滚同样次数。两版只差
# `src/rtl/eth/icmp_tx.v`（`git diff --name-only 54346ae HEAD -- src/rtl` 实测就这一条），
# 所以这是干净的单变量 A/B。
#
# 只写隔离目录，正式 build/ 那套产物一字不动（继承 roll_isolated.sh 的规矩）。
# 有一处 trap 把 icmp_tx.v 还原成 HEAD 的内容并核对，绝不把树留在中间态。
#
# 跑法：
#   DRY=1 bash build/r105_ab_rolls.sh          # 只走守卫与还原，不起 Vivado（先证明通道是通的）
#   bash build/r105_ab_rolls.sh                # post/pre 各两轮，约 60 分钟
#   ROLLS=1 bash build/r105_ab_rolls.sh        # 每种一轮
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
F=src/rtl/eth/icmp_tx.v
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN=$V
RES=$ROOT/build/r105_ab_results.txt
ROLLS=${ROLLS:-2}
DRY=${DRY:-}

norm() { tr -d '\r' | md5sum | cut -c1-12; }          # 内容指纹，不含行尾（规矩 38）
MD_POST=$(git show HEAD:$F | norm)
MD_PRE=$(git show 54346ae:$F | norm)
MD_NOW=$(norm < "$ROOT/$F")
echo "post(#141，应等 HEAD)=$MD_POST  pre(=54346ae，r103 那一版)=$MD_PRE  树里现在是=$MD_NOW"
[ "$MD_POST" != "$MD_PRE" ] || { echo "REFUSE: 两版内容相同，这一刀已经被合并或撤掉了，滚它没有对照意义"; exit 1; }
[ "$MD_NOW" = "$MD_POST" ] || { echo "REFUSE: 树里的 $F 不是 HEAD 那一版（$MD_NOW），先查清楚再滚"; exit 1; }
[ -x "$V/xvlog" ] || { echo "REFUSE: 找不到 xvlog（VP_VIVADO_BIN=$V）"; exit 2; }
if [ -z "$DRY" ]; then
    n=$(tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -ac "xsim.exe" || true)
    [ "${n:-0}" = "0" ] || { echo "REFUSE: 有 $n 个 xsim 在跑，别与台架抢树"; exit 1; }
fi

restore() {
    git show HEAD:$F > "$ROOT/$F"
    back=$(norm < "$ROOT/$F")
    echo "还原 $F → norm md5=$back（应为 $MD_POST）"
    [ "$back" = "$MD_POST" ] || { echo "FATAL: 没还原成 HEAD 那一版，树留在中间态，手工检查 $F"; exit 1; }
}
trap restore EXIT

wns() { grep -m1 -aE "^ *[0-9]+\.[0-9]+ +[0-9]+\.[0-9]+" "$1" | awk '{print "WNS="$1" TNS="$2" failEP="$3" totEP="$4}'; }

: > "$RES"
for i in $(seq 1 "$ROLLS"); do
    for var in post pre; do
        if [ "$var" = pre ]; then want=$MD_PRE; git show 54346ae:$F > "$ROOT/$F";
        else want=$MD_POST; git show HEAD:$F > "$ROOT/$F"; fi   # post 也必须**主动装树**：
        #   第一版这里只核对不写，于是 pre 跑完树还停在 pre 版，下一轮 post 的守卫立刻 REFUSE
        #   （09:11 真的 REFUSE 了一次，守住了"不拿错树去滚"——守卫是对的，缺的是这一行写入）。
        got=$(norm < "$ROOT/$F")
        [ "$got" = "$want" ] || { echo "REFUSE: $var 轮装树失败 got=$got want=$want，不滚"; exit 1; }
        OUT=build/r105ab_${var}_$i
        echo "=== $(date +%F_%H:%M:%S) $var 第 $i 轮 源=$got → $OUT${DRY:+  [DRY]}" | tee -a "$RES"
        if [ -n "$DRY" ]; then
            echo "    DRY：跳过 Vivado（只证明装树/核对/还原这条通道）" | tee -a "$RES"
            continue
        fi
        OUT=$OUT bash build/roll_isolated.sh 2>&1 | tail -3 | tee -a "$RES"
        if [ -s "$ROOT/$OUT/timing_summary.rpt" ]; then
            echo "    $var#$i  $(wns "$ROOT/$OUT/timing_summary.rpt")  bit=$(md5sum "$ROOT/$OUT/system.bit" 2>/dev/null | cut -c1-12)" | tee -a "$RES"
        else
            echo "    $var#$i  NO REPORT —— 别读数，先看 $OUT/build_console.txt" | tee -a "$RES"
        fi
    done
done
restore
trap - EXIT
echo "ROLLS DONE $(date +%F_%H:%M:%S)  结果在 $RES"

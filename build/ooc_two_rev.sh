#!/bin/bash
# 用途：单个模块的"改前 vs 改后"OOC 综合归因（拷贝树，只读，不动 src/）
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 1=FAIL 2=REFUSE
# build/ooc_two_rev.sh —— 单个模块的"改前 vs 改后"OOC 综合归因（拷贝树，只读，不动 src/）
# 为什么要有它：r110 那笔 −243 LUT 归不到模块，就是因为只有平铺 utilization（见 #246/#250 与
# build/evidence/r110_attrib.txt）。这把尺子把"某一把刀自己值多少 LUT/FF"直接量出来。
# 用法：bash build/ooc_two_rev.sh <改前 revision 或 BASE=HEAD^> <仓内相对路径 .v> <top 模块名> [标签]
#   前提：该模块**自包含**（不例化别的模块）——脚本会先数一遍带名端口连接，非 0 就 REFUSE，
#   否则 OOC 里那些子模块变黑盒，量出来的数与"设计里这一层"完全不是一回事。
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
V=${VP_VIVADO_BIN:-}
[ -f "$V/vivado.bat" ] || { echo "OOC-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin"; exit 2; }
REVA=${1:-HEAD^}; PATHV=${2:?用法: ooc_two_rev.sh <revA> <path.v> <top> [标签]}
TOP=${3:?要给 top 模块名}; TAG=${4:-$(basename "$PATHV" .v)}
W=/tmp/kx/ooc_$TAG; rm -rf "$W"; mkdir -p "$W/A" "$W/B"
git show "$REVA:$PATHV" > "$W/A/mod.v" 2>/dev/null || { echo "OOC-REFUSE: $REVA:$PATHV 取不出来"; exit 2; }
[ -f "$PATHV" ] || { echo "OOC-REFUSE: 工作树里没有 $PATHV"; exit 2; }
cp "$PATHV" "$W/B/mod.v"
NB=$(grep -acE "\.\w+ *\(" "$W/A/mod.v"); NB2=$(grep -acE "\.\w+ *\(" "$W/B/mod.v")
[ "$NB" -eq 0 ] && [ "$NB2" -eq 0 ] || { echo "OOC-REFUSE: 该模块有带名例化（A=$NB B=$NB2）⇒ 单模块 OOC 会把它变黑盒，量不得"; exit 2; }
cmp -s "$W/A/mod.v" "$W/B/mod.v" && { echo "OOC-SAME: 两腿文件一模一样，量它没意义"; exit 0; }

run() {   # $1=腿目录
    local d="$W/$1/run"; mkdir -p "$d"
    ( cd "$d" && "$V/vivado" -mode batch -nojournal -log viv.log \
        -source "$ROOT/build/tcl/ooc_util_probe.tcl" \
        -tclargs "$(cygpath -m "$W/$1")" "$TOP" "$(cygpath -m "$d/util.rpt")" > console.txt 2>&1 )
    [ -s "$d/util.rpt" ] || { echo "OOC FAIL: $1 腿没出报告（$d/viv.log）"; exit 1; }
    awk -F'|' -v leg="$1" '/Slice LUTs|Slice Registers/ {gsub(/[^0-9]/,"",$3); if ($3!="") printf "OOC %s %s=%s\n", leg, $1, $3}' "$d/util.rpt" \
        | sed 's/  */ /g'
    grep -aE "Slice LUTs|Slice Registers" "$d/util.rpt" | head -2
}
echo "# OOC 归因  模块=$TOP  改前=$REVA  改后=工作树（$PATHV）  标签=$TAG"
run A; run B
# 取数只从 **util.rpt 的行**取（不从被 sed 改过的摘要行取——上一版就是这么炸的：
# `awk '/LUTs/{print $3}'` 拿到的是 `LUTs*`，第 37 行的算术直接语法错）。
gn() { awk -F'|' -v re="$2" '$0 ~ re { c=$3; gsub(/[^0-9]/,"",c); if (c!="") { print c; exit } }' "$1"; }
LA=$(gn "$W/A/run/util.rpt" "Slice LUTs"); LB=$(gn "$W/B/run/util.rpt" "Slice LUTs")
RA=$(gn "$W/A/run/util.rpt" "Slice Registers"); RB=$(gn "$W/B/run/util.rpt" "Slice Registers")
for x in "$LA" "$LB" "$RA" "$RB"; do
  case "$x" in ""|*[!0-9]*) echo "OOC-FAIL: 取数不是纯数字（'$x'）—— 报告形状变了，别算差"; exit 1;; esac
done
echo "OOC $TOP 改前: LUT=$LA FF=$RA     改后: LUT=$LB FF=$RB"
echo "OOC-DELTA $TOP: LUT $LA→$LB（$((LB-LA))）  FF $RA→$RB（$((RB-RA))）"
echo "口径：OOC 的绝对数不等于设计内该层的数（设计里有跨层优化与复制），这里只念**同一把刀自己的差**。"
echo "设计内逐层数另走 build/tcl/probe_util_hier.tcl（report_utilization -hierarchical）。"

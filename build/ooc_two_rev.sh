#!/bin/bash
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
A=$(run A); B=$(run B); printf '%s\n%s\n' "$A" "$B"
LA=$(echo "$A" | awk '/LUTs/{print $3}'); LB=$(echo "$B" | awk '/LUTs/{print $3}')
RA=$(echo "$A" | awk '/Registers/{print $3}'); RB=$(echo "$B" | awk '/Registers/{print $3}')
for x in "$LA" "$LB" "$RA" "$RB"; do [ -n "$x" ] || { echo "OOC FAIL: 数字没解析出来（形状变了，别蒙）"; exit 1; }; done
echo "OOC-DELTA $TOP: LUT $LA→$LB（$((LB-LA))）  FF $RA→$RB（$((RB-RA))）"
echo "口径：OOC 的绝对数不等于设计内该层的数（设计里有跨层优化与复制），这里只念**同一把刀自己的差**。"

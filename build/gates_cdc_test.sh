#!/bin/bash
# build/gates_cdc_test.sh —— **门禁第 6 项自己的判据**（"检查器也要有反例"，见 skill/ 与学习文档 §十二）。
#
#   bash build/gates_cdc_test.sh
#
# 为什么需要这一份：第 6 项从 r56 起多了一条"Unsafe 端点数不许增长"的判红，
# 而这条判红的**输入**是工具报告 + 一个基线文本文件 —— 也就是说它可以被"改基线里的一个数字"
# 轻易糊过去。ISSUES #65 的教训正是"落在已有配对上的退化，配对集合看不见"，
# 所以这条新判据必须能当场演示**它什么时候会红**。
#
# 五个 case，前三个动 `cdc.rpt`（工具那一侧），后两个动基线（我们自己那一侧）：
#   T1 真·历史件：r55 冻结目录里那份 cdc.rpt（`clk_fpga_0>clkout0_1` 的 unsafe = 3，基线 1）⇒ 必须红
#   T2 反例的反例：把同一份报告里那个 3 改回 1（= r56 修好之后的形状）⇒ 必须绿
#      —— 没有 T2，一条"永远红"的判据和一条真判据长得一模一样
#   T3 老本行：凭空多一条 Critical 配对 ⇒ 必须红（第 6 项最初就是为这个写的）
#   T4 基线坏了（某行不是三列）⇒ 必须红，不许"少一列就当成 0"
#   T5 基线文件不存在 ⇒ 必须红（原来只 WARN，等于没门禁还打印 PASS 形状的行）
#
# 退出码：五个 case 全部符合预期才 0。
set -u
cd "$(dirname "$0")/.." || exit 2
SRC=build/frozen_r55_deadcdc
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[ -f "$SRC/cdc.rpt" ] || { echo "FATAL 找不到 $SRC/cdc.rpt —— 冻结件被移动了？"; exit 2; }
for f in timing_summary.rpt utilization.rpt power.rpt methodology.rpt route_status.rpt cdc.rpt system.bit; do
    cp "$SRC/$f" "$TMP/" || { echo "FATAL 拷 $f 失败"; exit 2; }
done

verdict() {   # verdict <门禁输出文件> -> 第 6 项那行尾巴上的 PASS/FAIL
    printf '%s\n' "$1" | grep -a "cdc.rpt Critical 行" | grep -oa "PASS\|FAIL" | tail -1
}
run() {       # run <报告目录> [CDCBASE=...]
    CDCBASE=${2:-build/CDC_BASELINE.txt} bash build/gates.sh "$1" 2>&1
}
npass=0; nfail=0
chk() {       # chk <名字> <期望 PASS/FAIL> <实际> <附加说明>
    if [ "$2" = "$3" ]; then echo "  PASS $1（判据=$3，期望=$2）$4"; npass=$((npass+1));
    else                    echo "  FAIL $1（判据=$3，期望=$2）$4"; nfail=$((nfail+1)); fi
}

# T1：真实的 r55 历史件 —— unsafe 3 > 基线 1
out=$(run "$TMP"); chk T1 FAIL "$(verdict "$out")" "r55 的 cdc.rpt 必须被新判据抓住"
printf '%s\n' "$out" | grep -a "Unsafe 端点增长" | head -1 | sed 's/^/        证据: /'

# T2：同一份报告，把那一行的 unsafe 改回 1（= r56 修好后的形状）
awk '{ if ($1=="Critical" && $2=="clk_fpga_0" && $3=="clkout0_1") $(NF-2)=1; print }' \
    "$TMP/cdc.rpt" > "$TMP/cdc_fixed.rpt" && mv "$TMP/cdc_fixed.rpt" "$TMP/cdc.rpt"
out=$(run "$TMP"); chk T2 PASS "$(verdict "$out")" "改回 1 之后必须绿 —— 否则这是一条永远红的判据"

# T3：多一条配对（工具那一侧最坏的形状）
{ cat "$TMP/cdc.rpt"; echo 'Critical  clk_pix_fake      axi_fake            No Common Primary Clock  Asynch Clock Groups  9 8 1 0 0'; } > "$TMP/cdc_new.rpt" \
    && mv "$TMP/cdc_new.rpt" "$TMP/cdc.rpt"
out=$(run "$TMP"); chk T3 FAIL "$(verdict "$out")" "新增配对必须红（第 6 项最初的目的）"

# T4：基线某行少一列 —— 不许当成 0 混过去
grep -v '^#' build/CDC_BASELINE.txt | sed 's/^clk_fpga_0>clkout0_1 17 1$/clk_fpga_0>clkout0_1 17/' \
    > "$TMP/base_2col.txt"
out=$(run "$TMP" "$TMP/base_2col.txt"); chk T4 FAIL "$(verdict "$out")" "基线坏了必须红，不是静默按 0 算"

# T5：基线根本不存在
out=$(run "$TMP" "$TMP/no_such_file.txt"); chk T5 FAIL "$(verdict "$out")" "没有基线 = 没有门禁 ⇒ 判红（原来只 WARN）"

echo "GATES-CDC-TEST: pass=$npass fail=$nfail"
[ "$nfail" = 0 ] || exit 1

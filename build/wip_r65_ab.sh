#!/bin/bash
# build/wip_r65_ab.sh —— 把"开了布线后物理综合"的那次构建与对照那次，按 `report/OPTIMIZATION_LOG.md` §5
# 的四条判据摆成一张表，并给出**机械的**采纳结论。
#
# 为什么要有这个脚本而不是"看完报告自己判断"：§5 的采纳规则写的是"eth_rxc 与 clkout0_1 两组**同时**不退步"，
# 而人读两份 timing_summary 时最容易犯的错是只念 Design Timing Summary 那一个数（§4 的教训：那一个数会换裁判）。
# ⇒ 把规则写死在这里，结论就与"当时谁在看"无关。
#
# 用法：bash build/wip_r65_ab.sh [新报告目录=build] [对照目录=build/evidence_r64b]
# ⚠ 只看门禁已有的行 + 新加的分组块，不重复实现任何解析（解析器只有一份 ⇒ 不会与 gates.sh 漂移）。
set -u
NEW=${1:-build}; REF=${2:-build/evidence_r64b}
# 构建期间不要念报告（与 wip_flash_r63.sh 同一道闸：那时读到的是上一版的数，七项照样全绿）。
# 要**故意**拿它做逻辑自检（读归档目录、与正在跑的构建无关），显式给 AB_FORCE=1，且这里会把话说明白。
if tasklist //FI "IMAGENAME eq vivado.exe" 2>/dev/null | grep -qi "vivado.exe"; then
    if [ "${AB_FORCE:-0}" = "1" ]; then
        echo "WARN vivado.exe 在跑：这份结论里 $NEW 可能还是**上一版**的报告（自检归档目录时用 AB_FORCE=1）"
    else
        echo "REFUSE_vivado_running 构建还在跑 ⇒ 现在读到的报告可能不是这一版的"
        exit 3
    fi
fi
grab() { # grab <目录> → 把 gates.sh 的相关行原样抄进三张表
    bash build/gates.sh "$1" 2>&1 || true
}
NEW_OUT=$(grab "$NEW"); REF_OUT=$(grab "$REF")
row() { # row <输出> <前缀> [字段号=3] → gates.sh 的 say 行里"实测"那一列
    # ⚠ 两种读法都会让这一格变成**空**，而空值喂给 awk 就是 0 ⇒ "没退步"的假绿，比读错列更坏：
    #   ① `say` 打出来的行以两个空格开头 ⇒ 不先抹行首空格，index($0,p)==1 永远不成立；
    #   ② 表头名字里带空格时它会占掉前几列（"WNS (ns)"→值在 $3，"Slice LUT / 占比"→$5，"失败 setup 端点"→$4）。
    #   所以数值列一律显式给字段号，且下面 AB_EMPTY 这道闸不许静默放行。
    echo "$1" | awk -v p="$2" -v k="${3:-3}" '{sub(/^ +/,"")} index($0,p)==1 {print $k; exit}'
}
grp() { # grp <输出> <组名> → "0.314/0.051"（setup/hold，来自 gates.sh 的分组块）
    # 块里一行的形状是 `  <组> setup <s>ns (失败端点 <n>)   hold <h>ns [←…]` ⇒ $3=setup、$7=hold
    echo "$1" | awk -v g="$2" '$1==g {split($3,a,"ns"); split($7,b,"ns"); print a[1]"/"b[1]; exit}'
}
fail_ep() { echo "$1" | awk '/失败 setup 端点/{print $4; exit}'; }
fail_hd() { echo "$1" | awk '/失败 hold 端点/{print $4; exit}'; }
# 自检：任何一格读成空 ⇒ 解析与 gates.sh 对不上（报告版式变了），当场停手，不拿空值判"没退步"。
for v in "$(row "$NEW_OUT" "WNS (ns)")" "$(row "$REF_OUT" "WNS (ns)")" \
         "$(row "$NEW_OUT" "Dynamic (W)")" "$(fail_ep "$NEW_OUT")" "$(fail_hd "$NEW_OUT")" \
         "$(grp "$NEW_OUT" eth_rxc)" "$(grp "$NEW_OUT" clkout0_1)" \
         "$(grp "$REF_OUT" eth_rxc)" "$(grp "$REF_OUT" clkout0_1)"; do
    [ -n "$v" ] || { echo "AB_EMPTY 有一格读成空 ⇒ 解析器与 gates.sh 的输出对不上，拒绝下结论"; exit 4; }
done

echo "== A/B：$NEW（新）对 $REF（对照）"
printf "  %-24s %-18s %-18s\n" 项 新 对照
for g in eth_rxc clkout0_1 clk_fpga_0; do
    printf "  %-24s %-18s %-18s\n" "组 setup/hold ($g)" "$(grp "$NEW_OUT" $g)" "$(grp "$REF_OUT" $g)"
done
printf "  %-24s %-18s %-18s\n" "门禁 WNS (ns)" "$(row "$NEW_OUT" "WNS (ns)")" "$(row "$REF_OUT" "WNS (ns)")"
printf "  %-24s %-18s %-18s\n" "门禁 WHS (ns)" "$(row "$NEW_OUT" "WHS (ns)")" "$(row "$REF_OUT" "WHS (ns)")"
printf "  %-24s %-18s %-18s\n" "失败 setup 端点" "$(fail_ep "$NEW_OUT")" "$(fail_ep "$REF_OUT")"
printf "  %-24s %-18s %-18s\n" "失败 hold 端点" "$(fail_hd "$NEW_OUT")" "$(fail_hd "$REF_OUT")"
printf "  %-24s %-18s %-18s\n" "Dynamic (W)" "$(row "$NEW_OUT" "Dynamic (W)")" "$(row "$REF_OUT" "Dynamic (W)")"
printf "  %-24s %-18s %-18s\n" "Slice LUT" "$(row "$NEW_OUT" "Slice LUT" 5)" "$(row "$REF_OUT" "Slice LUT" 5)"
printf "  %-24s %-18s %-18s\n" "BRAM (tile)" "$(row "$NEW_OUT" "BRAM (tile/%)")" "$(row "$REF_OUT" "BRAM (tile/%)")"

# 判据（§5）：① 两个竞争组都不许退步；② 至少一个组真的变好（否则多跑的布线后综合是白花构建时间）；
# ③ 失败端点两边都必须 0。WHS/功耗只报不判（功耗涨了要在结论里点名，不许只报时序收益）。
awk -v n="$(grp "$NEW_OUT" eth_rxc)" -v r="$(grp "$REF_OUT" eth_rxc)" \
    -v n2="$(grp "$NEW_OUT" clkout0_1)" -v r2="$(grp "$REF_OUT" clkout0_1)" \
    -v fen="$(fail_ep "$NEW_OUT")" -v fhn="$(fail_hd "$NEW_OUT")" \
    -v dyn="$(row "$NEW_OUT" "Dynamic (W)")" -v dynr="$(row "$REF_OUT" "Dynamic (W)")" '
function s(x) { split(x, a, "/"); return a[1]+0 }
BEGIN {
    bad=0; gain=0
    if (s(n)  < s(r)  - 0.001) { printf "  判红：eth_rxc 退步 %s → %s\n", r, n; bad=1 } else if (s(n)  > s(r)  + 0.001) gain=1
    if (s(n2) < s(r2) - 0.001) { printf "  判红：clkout0_1 退步 %s → %s\n", r2, n2; bad=1 } else if (s(n2) > s(r2) + 0.001) gain=1
    if (fen != "0" || fhn != "0") { printf "  判红：新构建还有失败端点（setup=%s hold=%s）\n", fen, fhn; bad=1 }
    if (!gain) print "  没收益：两个竞争组都没变好 ⇒ 这一档不值得占默认（构建时间白花）"
    if (dyn != "" && dynr != "" && dyn+0 > dynr+0 + 0.0005)
        printf "  点名：Dynamic 从 %s W 涨到 %s W（+%d mW）—— 复制高扇出驱动的价格，不许只报时序收益\n", dynr, dyn, (dyn-dynr)*1000
    print (bad ? "AB: REFUSE（保持默认关）" : (gain ? "AB: ADOPT（可把 IMPL_PRPO 设成默认开）" : "AB: REFUSE（无收益）"))
}'

#!/bin/bash
# build/rim_gate_ce.sh —— 门禁 15b（边缘条带 tb_edge_rim）自己的反例对照
#
# 为什么要有这个文件：本仓的规矩是"每条判据都要能红"（`#78`/`#88` 那几课）。
# 15b 是新加的，它读一份带 md5 头部的报告 —— 而"读报告"的判据最容易变成摆设：
# 头部字段名写错、grep 词太宽、忘了"RESULT PASS 但中间有 FAIL"这一族，它就一直绿。
# 五条对照：四条必须红 + 一条**必须绿**（拿盘上那份真报告当正对照，
# 否则一个"永远红"的判据也会被误当成"有牙齿"）。
#
#   bash build/rim_gate_ce.sh          # 全部跑完，最后一行 CE: 全绿 / CE: 有红
set -u
cd "$(dirname "$0")/.." || exit 2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RTL=$(bash build/rtl_fingerprint.sh | sed -n 's/^rtl=//p')
TBM=$(bash build/rtl_fingerprint.sh sim/tb_edge_rim.v | cut -c1-12)
REAL=$(ls -1 build/tb_edge_rim_r*.txt 2>/dev/null | sort -V | tail -1)
[ -n "$REAL" ] || { echo "CE: 盘上没有 build/tb_edge_rim_rNN.txt —— 先跑台架留凭据，反例没法谈正对照"; exit 1; }

head2() { printf 'top_md5=%s\ntb_md5=%s\nrtl_md5=%s\ndate=ce\n' \
                  "$(bash build/rtl_fingerprint.sh | sed -n 's/^top=//p')" "$1" "$2"; }

mk() { # mk <文件> <tb_md5> <rtl_md5> <正文>
    head2 "$2" "$3" > "$1"
    printf '%s\n' "$4" >> "$1"
}

GOOD_BODY='PASS R0 ruler integrity: 4 frames per run, all four stages share one de
PASS R1 interior == the definition at the measured latency
PASS R2/D1 left column == clamp-to-edge and responds to its neighbour (golden judged 52)
PASS R3 top row == clamp-to-edge (judged 52)
PASS R4/D2 last column == clamp-to-edge and responds (golden judged 52)
PASS R5/D3 screen row 0 == its own window, no stale row (golden judged 52)
RESULT tb_edge_rim PASS'

mk "$TMP/stale_rtl.txt"  "$TBM" "000000000000000000000000" "$GOOD_BODY"
mk "$TMP/no_result.txt"  "$TBM" "$RTL" "PASS R2/D1 left column == clamp-to-edge"
mk "$TMP/hidden_fail.txt" "$TBM" "$RTL" "FAIL R3 top row NOT clamp-to-edge (bad=52 n3=52)
$GOOD_BODY"
mk "$TMP/three_rims.txt" "$TBM" "$RTL" "PASS R0 ruler integrity: 4 frames per run, all four stages share one de
PASS R2/D1 left column == clamp-to-edge and responds to its neighbour (golden judged 52)
PASS R4/D2 last column == clamp-to-edge and responds (golden judged 52)
PASS R5/D3 screen row 0 == its own window, no stale row (golden judged 52)
RESULT tb_edge_rim PASS"
mk "$TMP/stale_tb.txt" "ffffffffffffffffffffffff" "$RTL" "$GOOD_BODY"

declare -A WANT=( [stale_rtl]=红 [no_result]=红 [hidden_fail]=红 [three_rims]=红 [stale_tb]=红 [real]=绿 )

echo "== 15b 的反例（RIM_REPORT 指向临时件，门禁只比它）=="
fail=0
for k in stale_rtl no_result hidden_fail three_rims stale_tb real; do
    if [ "$k" = real ]; then f="$REAL"; else f="$TMP/$k.txt"; fi
    OUT=$(RIM_REPORT="$f" bash build/gates.sh 2>&1 | grep -a "边缘条带 tb_edge_rim")
    # `say` 的格式是"名字 实测 判据 判决"，判决在**行尾**；不能拿"这一行里有没有 FAIL 字样"当判决
    # （真报告那行的实测里就带着 "FAIL行=0"，一 grep 就把它读成红了 —— 第一版就是这么误判 5 条）。
    V=$(printf '%s\n' "$OUT" | awk 'NF{print $NF}' | tail -1)
    if [ "$V" = FAIL ]; then got=红; elif [ "$V" = PASS ]; then got=绿; else got=没打印; fi
    exp=${WANT[$k]}
    if [ "$got" = "$exp" ]; then
        echo "  PASS $k -> $got（期望 $exp）"
    else
        echo "  FAIL $k -> $got（期望 $exp）：$OUT"; fail=1
    fi
done

# 正对照还有一条：把**真**报告的 rtl_md5 改掉，必须红（证明它真的在比这个字段，而不是摆设）
if [ "$fail" = 0 ]; then echo "CE: 全绿（5 条红 + 1 条绿）"; exit 0; else echo "CE: 有红 —— 15b 这把判据不成立"; exit 1; fi

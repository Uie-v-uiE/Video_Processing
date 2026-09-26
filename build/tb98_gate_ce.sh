#!/bin/bash
# build/tb98_gate_ce.sh —— 门禁第 15 项（顶层台架报告）自己的反例测试
#
#   bash build/tb98_gate_ce.sh          # 五条都要对，最后打印 CE: PASS / CE: FAIL
#
# 为什么必须有它（仓库老规矩："判据要有自己的测试"，#57/#60 那一族）：
#   第 15 项判的是"一份报告是不是**当前这份顶层**跑出来的、里面有没有红项、有没有跑完"。
#   这三条里任何一条在脚本里写歪（比如 `grep -q RESULT` 匹配到了表头、或者 md5 变量拼错），
#   症状都是"永远绿" —— 而那正是 #88 那几天"gates 14/14 与顶层台架红着同时成立"的形状。
#   所以这里造五份报告：一份应该绿（P），四份应该红（A 指纹不符 / B 没跑完 / C 有红项 / D 文件不存在）。
#   P 那份是**合成的**：它只用来证明"合格形状的报告会被判绿"，真凭据由
#   `bash build/tb98_report.sh` 从真实 run.log 生成，两件事不互相冒充。
set -u
cd "$(dirname "$0")/.." || exit 2
TMP=$(mktemp -d)
TOP=$(md5sum src/rtl/top/pl_video_top.v | cut -c1-12)
TB=$(md5sum sim/tb_v98_top_seam.v | cut -c1-12)
HDR="# provenance top_md5=$TOP tb_md5=$TB date=ce-synthetic src=$TMP"
GOOD="$TMP/p.txt";     printf '%s\nPASS C1c x\nPASS C3c y\nRESULT tb_v98_top_seam PASS\n' "$HDR" > "$GOOD"
BADMD5="$TMP/a.txt";   printf '%s\nPASS C1c x\nRESULT tb_v98_top_seam PASS\n' \
                            "${HDR/top_md5=$TOP/top_md5=deadbeef0000}" > "$BADMD5"
NOEND="$TMP/b.txt";    printf '%s\nPASS C1c x\n' "$HDR" > "$NOEND"
WITHFAIL="$TMP/c.txt"; printf '%s\nPASS C1c x\nFAIL C3c panel edges match definition\nRESULT tb_v98_top_seam FAIL nfail=1\n' "$HDR" > "$WITHFAIL"
MISSING="$TMP/d_none.txt"

want() { # want <名字> <报告路径> <期望 PASS|FAIL>
    local name=$1 file=$2 exp=$3 line got
    line=$(TB98_REPORT="$file" bash build/gates.sh 2>/dev/null | grep -a "顶层台架 tb_v98" | head -1)
    # 取**最后一列**而不是 `case *$exp*`：C 那一例的明细里本来就有 "FAIL行=1" 这样的字样，
    # 拿子串判会把它自己的红项当成判据的红 —— 差一位就测不出"判据根本没看那份报告"。
    got=$(printf '%s\n' "$line" | awk '{print $NF}')
    if [ "$got" = "$exp" ]; then echo "  ok   $name → $got（$(echo "$line" | cut -c1-56)…）"
    else echo "  BAD  $name 期望 $exp，实得 [$got] / 整行：$line"; FAILS=$((FAILS+1)); fi
}
FAILS=0
echo "门禁第 15 项的反例（当前 top_md5=$TOP tb_md5=$TB）："
want "P 合格报告"        "$GOOD"    PASS
want "A 顶层指纹不符"    "$BADMD5"  FAIL
want "B 没有跑完"        "$NOEND"   FAIL
want "C 报告里有红项"    "$WITHFAIL" FAIL
want "D 报告不存在"      "$MISSING" FAIL
rm -rf "$TMP"
if [ "$FAILS" = 0 ]; then echo "CE: PASS（五条全对）"; exit 0; else echo "CE: FAIL（$FAILS 条不对）"; exit 1; fi

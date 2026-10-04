#!/bin/bash
# build/r94_verdict_ce.sh —— #104（run_one.sh 缺统一 RESULT token）的**改前对照**。
#
# 病：`build/sim/run_one.sh` 只认两种判定形状 —— `RESULT <tb>` 与 `^(PASS|FAIL) <tb>( ALL)?$`。
# 台架 `tb_v94_zoom_sel` 打的是 `TB RESULT PASS` / `TB RESULT FAIL` ⇒ 两条都不命中 ⇒ 输出
# `NO-VERDICT-LINE … || FAIL 行数=0`，**而它自己可以是红的**。今天（12:33 那次变异对照）就现场撞见：
# `build/r94_rotfit_mutation.txt` 明明有 3 行 FAIL，VERDICT 行却写着"FAIL 行数=0"。
# 这就是"能让一个真红变成绿"的尺子形状，所以它先要有自己的可跑对照，再动 run_one.sh。
#
# 本脚本**不改 run_one.sh**：把候选解析器写成函数，拿三份**真实**日志喂它，判它必须
# ① 认绿、② 认红、③ 对真的没判定行的台架仍然报 NO-VERDICT（不许把"没数"当 PASS —— 空判过不了）。
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0

# ---- 候选解析器（与将来要写进 run_one.sh 的那几行同形）----
verdict() {  # $1=tb 名  $2=日志
    local TB=$1 L=$2 V
    V=$(grep -a "RESULT $TB" "$L" | tail -1)
    [ -n "$V" ] || V=$(grep -aE "^(PASS|FAIL) $TB( ALL)?$" "$L" | tail -1)
    # 新增的形状：`TB RESULT PASS|FAIL`（tb_v94 那一族）。⚠ 必须**先看日志里有没有本台架的名字**再认它：
    #   这一条是我自己写的对照脚本抓出来的（第一版没有这层限定 ⇒ 拿 tb_v94 的日志问 tb_no_such_bench
    #   也回答 PASS —— 一个过期日志就能冒充当前判定，正是"真红变绿"的形状）。
    if [ -z "$V" ] && grep -qa "$TB" "$L"; then
        V=$(grep -aE "^[[:space:]]*(TB )?RESULT[[:space:]]+(PASS|FAIL)" "$L" | tail -1)
    fi
    [ -n "$V" ] || V="NO-VERDICT-LINE"
    printf '%s' "$V"
}
nf() { grep -ac '^ *FAIL' "$1"; }

chk() { # $1=说明 $2=期望 3=实得
    if [ "$2" = "$3" ]; then echo "  ok   $1 => $3"; else echo "  FAIL $1 => 期望[$2] 实得[$3]"; fail=$((fail + 1)); fi
}

echo "== verdict 解析器的三形状对照（三份真实日志）=="
V1=$(verdict tb_v94_zoom_sel build/r94_rotfit_after.txt)
V2=$(verdict tb_v94_zoom_sel build/r94_rotfit_mutation.txt)
V3=$(verdict tb_no_such_bench build/r94_rotfit_after.txt)
F2=$(nf build/r94_rotfit_mutation.txt)
F1=$(nf build/r94_rotfit_after.txt)
case "$V1" in *PASS*) chk "绿日志被认成判定（不是 NO-VERDICT）" PASS PASS;; *) chk "绿日志被认成判定" PASS "$V1";; esac
case "$V2" in *FAIL*) chk "红日志被认成判定（这就是今天的漏网之鱼）" FAIL FAIL;; *) chk "红日志被认成判定" FAIL "$V2";; esac
chk "红日志的 FAIL 行数不是 0（今天写的是 0）" 3 "$F2"
chk "绿日志的 FAIL 行数是 0" 0 "$F1"
chk "不存在的台架仍然报 NO-VERDICT（不许把没数当 PASS）" NO-VERDICT-LINE "$V3"

echo "== 结果 =="
if [ "$fail" -eq 0 ]; then echo "VERDICT tb_verdict_shape PASS（候选解析器覆盖三种形状）"
else echo "VERDICT tb_verdict_shape FAIL（$fail 条不符）"; fi
exit $fail

#!/bin/bash
# 用途：#166 的对照实验：`build/sim/run_one.sh --verdict` 这条尺子**自己**能不能被喂出正确答案
# 输入：命令行参数
# 输出：stdout
# 退出码：0=跑完 1=非 0 分支（该文件 exit 1 那一行）
# build/run_one_ce.sh —— #166 的对照实验：`build/sim/run_one.sh --verdict` 这条尺子**自己**能不能被喂出正确答案。
#
# 为什么单独一个脚本（本项目的规矩：判据要能红，检查器也要有自己的测试）：
#   r62 那天一支真红的台架被 `run_one.sh` 报成 `NO-VERDICT-LINE || FAIL 行数=0` ——
#   两个原因叠在一起：判定形状漏了 `TB RESULT PASS|FAIL` 那一族，FAIL 计数只认顶格的 `^FAIL`
#   而十二支台架打的是 `  FAIL <名字>`。"红"与"没数"长得一模一样，比没有数更危险（#163/#164 同一族）。
#   修复之后必须能**当场**证明：同一个形状的老问题现在答对了，而兜底没有变成"谁都能冒充"。
#
# 八条（都离线、不起 xsim、几秒跑完）：
#   1 绿日志 → rc 0，FAIL 行数=0
#   2 顶格 FAIL + `RESULT … FAIL` → rc 3，FAIL 行数=1
#   3 缩进 FAIL + `TB RESULT FAIL`（#166 原形状）→ rc 3，FAIL 行数=1     ← 旧实现这里是 4 + 0
#   4 一条判定都没有 → rc 4 且念 NO-VERDICT
#   5 别人日志里有一行 `TB RESULT PASS`，但**不含本台架的名字** → 必须 rc 4  ← 兜底不许替陌生人答复
#   6 收尾行**带字段**（`FAIL tb_demo errors=1`，tb_v90_latency 那一族）→ 必须 rc 3   ← #104 尾账
#   7 名字相近的别人的红（`FAIL tb_demo2 errors=1`）不许替 tb_demo 答复 → 必须 rc 4    ← 6 的反配对
#   8 顶格的 `PASS tb_demo c1`（一条判据的形状）不许冒充判定 → 必须 rc 4      ← 放宽只给 FAIL 的理由
set -u
cd "$(dirname "$0")/.." || exit 1
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT

# $1=日志文件 $2=期望 rc $3=说明；退出码累加到 BAD
ce() {
    bash build/sim/run_one.sh --verdict tb_demo "$1" > "$1.out" 2>&1; local rc=$?
    local want=$2
    if [ "$rc" = "$want" ]; then echo "  ok   $3：rc=$rc（$(tail -1 "$1.out")）"
    else echo "  BAD  $3：rc=$rc 期望 $want（$(tail -1 "$1.out")）"; BAD=$((BAD + 1)); fi
}
BAD=0

printf 'PASS c1 alpha\nPASS c2 beta\nRESULT tb_demo PASS\n' > "$D/green.log"
ce "$D/green.log" 0 '1 绿日志'

printf 'FAIL c1 alpha\nPASS c2 beta\nRESULT tb_demo FAIL (1 errors)\n' > "$D/red.log"
ce "$D/red.log" 3 '2 顶格 FAIL 判红'

# tb_v94 那一族：每条判据打 `  FAIL <名字>`（两个空格），结尾打 `TB RESULT FAIL`（没有台架名），
# 台架名出现在别的行里（这里用 xvlog/elab 的回显形状）⇒ 兜底**允许**认这一行。
printf 'PASS tb_demo c1\n  FAIL T8b rot clamp\nTB RESULT FAIL\n' > "$D/indent.log"
ce "$D/indent.log" 3 '3 缩进 FAIL + TB RESULT（#166 的原形状）'

printf 'INFO nothing decided here\n  PASS c1\n' > "$D/nodict.log"
ce "$D/nodict.log" 4 '4 没有判定行'

# ⚠ 这条是"兜底不能变陌生人代答"的正控制：日志里有一行 `TB RESULT PASS`，
#   但那份日志里**从没出现过 tb_demo**（它是别的台架的过期日志）⇒ 必须还是 NO-VERDICT。
printf '  PASS c1\n  PASS c2\nTB RESULT PASS\n' > "$D/stranger.log"
ce "$D/stranger.log" 4 '5 别人的过期日志不许替本台架答复'

# 6 = #104 尾账补的那一种形状：台架收尾那一行**带字段**（没有 RESULT 行）。
#    旧实现在这里给 rc=4「认不出判定」，而红就在下一行写着 ⇒ 链里只能看见"没数"、看不见"红了"。
printf '  FAIL T17a collided commit\nPASS c2\nFAIL tb_demo errors=1\n' > "$D/suffix.log"
ce "$D/suffix.log" 3 '6 收尾行带字段（FAIL tb_demo errors=1）必须认成红'
grep -aq 'NO-VERDICT' "$D/suffix.log.out" && { echo "  BAD  6 那条还念 NO-VERDICT"; BAD=$((BAD + 1)); }

# 7 = 6 的反配对：名字只是**相近**的别人的红（tb_demo2）不许替 tb_demo 答复。
#    少了这一条，6 的放宽就可能是"任何带 tb_demo 子串的行都算本台架判定"——那比原洞更坏（#163 那一课）。
printf '  PASS c1\nFAIL tb_demo2 errors=1\n' > "$D/nearmiss.log"
ce "$D/nearmiss.log" 4 '7 相近名字的别人的红不许替本台架答复（6 的反配对）'

# 8 = 放宽只给 FAIL 的**反证**：`PASS tb_demo c1` 是"一条判据"的形状（判据名跟在台架名后面），
#    它绝不能被当成本台架的判定 —— 那样一支从没跑完的台架会自己报"通过"。
printf 'PASS tb_demo c1\nPASS tb_demo c2\n' > "$D/percrit.log"
ce "$D/percrit.log" 4 '8 顶格的 PASS 判据行不许冒充判定（放宽只给 FAIL 的理由）'

grep -aq 'NO-VERDICT' "$D/nodict.log.out" || { echo "  BAD  4 那条没念 NO-VERDICT"; BAD=$((BAD + 1)); }
N=$(sed -n 's/.*FAIL 行数=\([0-9]*\).*/\1/p' "$D/indent.log.out" | head -1)
[ "$N" = 1 ] || { echo "  BAD  3 那条数到的 FAIL 行数=$N（期望 1 —— 缩进行必须算进去）"; BAD=$((BAD + 1)); }

if [ "$BAD" = 0 ]; then echo "SELF PASS run_one --verdict（八条对照都按期望动）"; exit 0
else echo "SELF FAIL run_one --verdict（$BAD 条不符）"; exit 1; fi

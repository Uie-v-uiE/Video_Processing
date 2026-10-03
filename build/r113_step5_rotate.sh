#!/usr/bin/env bash
# build/r113_step5_rotate.sh —— 采纳第⑤步的驱动器（两段式：先改口，人补两句，再重跑门禁到一致）
#
# 为什么两段而不是一气跑完：门禁 24 项里**包含** `doc_currency` 与 `metric_recheck`，
#   而 D1c 那把要读盘上那份 `rNN_gates.txt` 里"门禁 N 项 X 绿 / Y 红"这句去对账 ⇒
#   这句与"刷板时刻"那句**必须人写**（语义句，脚本不代劳），写完再重跑门禁才会收敛。
#   顺序错了就会拿到一个假的一致（#242 那一课的变体）。
#
# 用法：
#   bash build/r113_step5_rotate.sh            # 第 1 段：机械 + 手写规则改口，然后打印"还差哪两句"
#   bash build/r113_step5_rotate.sh --gates    # 第 2 段：重跑门禁两跑到逐字节一致，写回 r113_gates.txt，三把尺子复看
# 纪律：只在链子停下之后跑（没有 xsim/vivado 在飞，且门禁件已在盘上）。
set -u
cd "$(dirname "$0")/.."
GATES=build/r113_gates.txt
say() { printf '[s5 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$GATES" ] || { say "REFUSE: 还没有 $GATES（链子第⑥步没跑完）"; exit 2; }
if tasklist 2>/dev/null | grep -qiE '^(xsim|xsimk|vivado)\.exe'; then
    say "REFUSE: 台架/构建还在飞（同一时刻改文档会让门禁两跑不一致）"; exit 2
fi

if [ "${1:-}" = "--gates" ]; then
    say "第 2 段：重跑门禁两遍"
    bash build/gates.sh > /tmp/kx/s5_g1.txt 2>&1; R1=$?
    cp -f /tmp/kx/s5_g1.txt "$GATES"
    bash build/gates.sh > /tmp/kx/s5_g2.txt 2>&1; R2=$?
    if ! cmp -s /tmp/kx/s5_g1.txt /tmp/kx/s5_g2.txt; then
        say "⚠ 两跑不一致（还有句子在动）；diff 前 20 行"
        diff /tmp/kx/s5_g1.txt /tmp/kx/s5_g2.txt | head -20
        exit 1
    fi
    cp -f /tmp/kx/s5_g2.txt "$GATES"
    say "两跑逐字节一致 rc=$R1/$R2"
    GP=$(grep -c ' PASS$' "$GATES"); GF=$(grep -c ' FAIL$' "$GATES")
    say "门禁现状：$((GP+GF)) 项 ${GP} 绿 / ${GF} 红"
    grep -a ' FAIL$' "$GATES" | sed 's/^/[s5]   红: /'
    say "三把尺子复看"
    node src/host/metric_recheck.mjs 2>&1 | tail -1
    node src/host/doc_currency_check.mjs 2>&1 | grep -a 'CURRENCY\|盘上没有' | tail -3
    node src/host/line_cite_check.mjs 2>&1 | tail -1
    node src/host/doc_enc_check.mjs 2>&1 | tail -1
    say "STEP5-GATES-DONE 之后：采纳笔（含 bit/xsa）→ 三步 JTAG 刷板 → board_verify --round=r113 → 回填刷板时刻 → 试冻结 → make_submission → push"
    exit 0
fi

GP=$(grep -c ' PASS$' "$GATES"); GF=$(grep -c ' FAIL$' "$GATES")
say "第 1 段：改口。改口前门禁件是 $((GP+GF)) 项 ${GP} 绿 / ${GF} 红（这几条红是"改口之前必然红"）"
grep -a ' FAIL$' "$GATES" | sed 's/^/[s5]   红: /'
say "1) rotate_from_metric --apply"
node build/rotate_from_metric.mjs --apply 2>&1 | tail -3
say "2) r113_rotate_docs --apply（49 条规则）"
node build/r113_rotate_docs.mjs --apply 2>&1 | tail -2
NEW=$((GP+GF))
say "3) 要人写的两句（写完再跑 `bash build/r113_step5_rotate.sh --gates`）："
say "   ① README.md 与任何引用它的句子：『门禁 24 项 23 绿 / 1 红』→ 按新门禁件的实际读数改（本轮跑完第 2 段会打印『$NEW 项 …』的真数；四处句子 + metrics.csv 要同一笔）"
say "   ② 身份句『板上这一版 r113（bit b94f4da6cdff，刷板时刻待回填）』→ 三步 JTAG 刷完后回填时刻（这一条第 2 段之前不必写，别提前填假时间）"
say "STEP5-ROTATED 等人工补句子"
exit 0

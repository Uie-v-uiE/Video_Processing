#!/usr/bin/env bash
# build/r117_post.sh —— r117 判读之后的"机械半成品"：把 E1 表、I/O 复核读数、改口清单三件自动生成，
# 人只做判断（要不要采纳、文案怎么写），不做抄数。
#
# 为什么必须有这一支：最后那一轮我最容易犯的错就是"把快车道滚 B 的数抄进交付文档"（提示词
# rule 44：'now/current' 的基线必须是件）。所以这份脚本只从**官方构建之后**的报告里取数，
# 并把 `metric_recheck` 的 RED 清单原样落成改口清单——文档里哪个数还没跟上，由尺子点名，不由我记得。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
say(){ printf '[r117post %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r117_post_console.txt; }

for i in $(seq 1 400); do
    [ -s build/r117_verdict.txt ] && break
    sleep 30
done
[ -s build/r117_verdict.txt ] || { say "等不到 build/r117_verdict.txt —— 什么都不做"; exit 1; }
say "判读件到位，先等 90 s 让名册/差分/快车道三份件写完"; sleep 90

# 1) I/O 与 check_timing 复核（只读探针，E1 的两个债务列只能来自这里）
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/r117_io_probe.tcl \
    > build/r117_io_probe_console.txt 2>&1; say "io probe rc=$?"
grep -a "^CT \|^CTROW\|^IOLINE\|^R117PROBE" build/r117_io_probe_console.txt | head -40

# 2) E1 花名册（官方件 → 13 列），两端分别是 r116 与 r117，差值与 verdict 由生成器算
python build/r115_roster_build.py build/timing_summary.rpt build/evidence/r117/r117_check_timing.txt \
    build/evidence/r117_roster_e1.tsv r117 > build/r117_roster_build_console.txt 2>&1
say "roster build rc=$? $(tail -1 build/r117_roster_build_console.txt)"
python build/r115_round_roster.py build/evidence/r116_roster_e1.tsv build/evidence/r117_roster_e1.tsv \
    docs/timing/roster_round117.tsv \
    "A=build/evidence/r116_roster_e1.tsv（r116 官方件）；B=build/evidence/r117_roster_e1.tsv（r117 官方件，来源 build/timing_summary.rpt + build/evidence/r117/r117_check_timing.txt）。本轮问题只有一个：C9 这一刀有没有让任何一格变差（G1），以及 eth_rxc 两格是否逐格不动（它不吃这一刀）。基线对照仍在 docs/timing/roster_round116.tsv" \
    > build/r117_round_roster_console.txt 2>&1
say "E1 表 rc=$? $(grep -a 'ROUND written' build/r117_round_roster_console.txt | head -1)"

# 3) 改口清单：尺子点名，不靠记忆
node src/host/metric_recheck.mjs > build/r117_rotation_checklist.txt 2>&1
say "metric_recheck 红=$(grep -a -c '^RED ' build/r117_rotation_checklist.txt) $(grep -a '数字对账' build/r117_rotation_checklist.txt | tail -1)"
node src/host/doc_currency_check.mjs >> build/r117_rotation_checklist.txt 2>&1
say "doc_currency $(grep -a 'CURRENCY' build/r117_rotation_checklist.txt | tail -1)"
grep -a "^RED " build/r117_rotation_checklist.txt | head -30

# 4) 一块"到这里就交给人"的汇总
{
    echo "r117 post done $(date '+%F %T')"
    echo "verdict:      build/r117_verdict.txt"
    echo "E1 表:        docs/timing/roster_round117.tsv"
    echo "改口清单:      build/r117_rotation_checklist.txt（RED 行 = 交付文档还没跟上的数）"
    echo "I/O 复核:     build/evidence/r117/{r117_check_timing.txt,r117_io_HOLD.rpt,r117_io_SETUP.rpt}"
    echo "板侧（若已刷）: build/evidence/r117_board/BOARD_NOW.txt"
} > build/r117_post_done.txt
say "写在 build/r117_post_done.txt"

#!/usr/bin/env bash
# build/r117_pair_fix.sh —— 把 r117 官方名册**换回同一把生成器**再差分一次（对 r114）。
#
# 为什么要有这一支（2026-10-04 03:56 预跑发现的，不是我读判读时才发现的）：
#   `build/r117b_chain.sh` 里我把对照写成 `build/evidence/r114_after_roster.txt`，
#   但那份是 **roster_from_summary.sh** 的产物：只有 4 个有 intra 路径的钟、字段带 `endpoints=/src=`、
#   没有 FANOUT 节；而 r117 那份来自 `probe_timing_roster.tcl`（8 个钟、带 levels/route/dest）。
#   `build/timing_roster_diff.sh` 的口径闸门正好管这个（时钟名单要一致、扇出节要同有同无），
#   拿这两份相减 = REFUSE（我已经在盘上验证过：`ROSTERDIFF-SHAPE clocks_A=[4 个] clocks_B=[8 个] … result=REFUSE`）。
#   ⇒ 这正是 ISSUES #291/#293 那一族的复发：**混口径不是代价，是尺子断**。
#
# 修法不是放宽闸门（那是第二次错），而是**把两侧都用同一个过滤器从各自的探针原始件里取出来**：
#   A = build/evidence/r114_roster_rf_console.txt（r114 官方构建那晚探针的原始控制台，未被过滤）
#   B = build/r117_roster_console.txt（本轮链子写的探针控制台原文）
#   过滤器 = grep '^ROSTER|' 与 '^FANOUT|'（两行形状都留，D6 才有东西可数）。
#   对照验证：同一过滤器配 r116 的原文，`pairs=16 fanout_rows=20 D6 GREEN`，
#   而 D1/D3 红 2 格 = r116 那次**已知**的输入窗代价（不是本轮引入的）。
#
# 链子里那一跑的原样保留（它的 REFUSE 是这一条账的凭据，不改写、不删）。
set -u
cd "$(dirname "$0")/.."
A=build/evidence/r114_after_roster_probefmt.txt
B=build/evidence/r117_after_roster_probefmt.txt
OUT=build/evidence/r117_roster_diff_vs_r114.txt

grep -a '^ROSTER|\|^FANOUT|' build/evidence/r114_roster_rf_console.txt > "$A"
[ -s build/r117_roster_console.txt ] || { echo "PAIRFIX-REFUSE 没有 build/r117_roster_console.txt（本轮探针还没跑完，不猜）"; exit 2; }
grep -a '^ROSTER|\|^FANOUT|' build/r117_roster_console.txt > "$B"

ra=$(grep -ac '^ROSTER|' "$A"); rb=$(grep -ac '^ROSTER|' "$B")
fa=$(grep -ac '^FANOUT|' "$A"); fb=$(grep -ac '^FANOUT|' "$B")
echo "PAIRFIX-INPUT a_rows=$ra a_fanout=$fa b_rows=$rb b_fanout=$fb"
[ "$ra" = "$rb" ] || { echo "PAIRFIX-REFUSE 两侧名册行数不同（$ra vs $rb）⇒ 还是一把尺子吗？先停下查"; exit 3; }

bash build/timing_roster_diff.sh "$A" "$B" > "$OUT" 2>&1
R=$?
grep -a '^ROSTERDIFF D\|^ROSTERDIFF-SUMMARY\|^ROSTERDIFF-ROW' "$OUT" | head -30
echo "PAIRFIX done rc=$R out=$OUT"
exit $R

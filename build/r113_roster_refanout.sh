#!/usr/bin/env bash
# build/r113_roster_refanout.sh —— 重跑一次名册探针，把 D6 那个"工具红"改成有凭据的读数
#
# 为什么要这一支：r113 的名册差分（build/evidence/r113_roster_diff.txt）里 D1..D5 全绿、
#   唯独 `D6_fanout_inventory fanout_rows=0` 判红。查下来红在我的尺子上，不在设计上：
#   `help report_design_analysis` 在这台 2025.2.1 里**没有 -fanout 模式**（实测凭据
#   build/evidence/r113_help_fanout_console.txt），前两版探针调它 ⇒ catch 吞掉错误 ⇒ 报告文件根本没写 ⇒
#   行数为 0。正确命令是 `report_high_fanout_nets`。
#
# 纪律：
#   * 只读——开 routed dcp 出报告，不改网表、不写 runs 目录、不碰 src/；
#   * 不覆盖上一份快照（rule 17）：产物一律用 `_rf` 后缀的新名字，原来那两份 r113_after_roster.txt /
#     r113_roster_diff.txt 留在盘上，读的是"同一份 dcp 两次探针"的差别；
#   * 没有别的 Vivado 在飞才起飞（并发会拖慢实现线程）；台架 xsim 在跑时不要起这一支（内存只有 15.7 G）。
#
# 用法：bash build/r113_roster_refanout.sh
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
say() { printf '[rf %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE no Vivado (VP_VIVADO_BIN=$V)"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then
    say "REFUSE: 已经有 Vivado 在飞"; exit 2
fi
if tasklist 2>/dev/null | grep -qiE "^xsimk?\.exe"; then
    say "REFUSE: 台架 xsim 还在跑（这台机器 15.7 G 内存，开 routed dcp 会挤它）"; exit 2
fi
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp
[ -f "$DCP" ] || { say "REFUSE no $DCP"; exit 2; }
say "bit=$(md5sum < build/system.bit | awk '{print substr($1,1,12)}')（探针读的就是这一版的路由）"

CON=build/evidence/r113_roster_rf_console.txt
RO=build/evidence/r113_after_roster_rf.txt
VP_LABEL=r113rf "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl > "$CON" 2>&1
RC=$?
say "probe rc=$RC"
grep -a '^ROSTER|'  "$CON" >  "$RO"
grep -a '^FANOUT|'  "$CON" >> "$RO"
grep -a '^DESIGN|'  "$CON" >> "$RO"
# 原始报告留一份可跟踪的 .txt（*.log 被 .gitignore 挡住，evidence 必须是 .txt）
cp -f build/roster_r113rf_fanout.rpt build/evidence/r113_fanout_raw.txt 2>/dev/null \
    || say "WARN: 没有 build/roster_r113rf_fanout.rpt（FANOUT_EXISTS 那一行会说明原因）"
NR=$(grep -ac '^ROSTER|' "$RO")
NF=$(grep -ac '^FANOUT|' "$RO")
say "rows roster=$NR fanout=$NF"
say "探针自己的计数：$(grep -ao 'FANOUT_ROWS=[0-9]*' "$CON" | tail -1) $(grep -ao 'ROSTER_ROWS=[0-9]*' "$CON" | tail -1) $(grep -a '^FANOUT_EXISTS=' "$CON" | tail -1) $(grep -a '^FANOUT_ERR=' "$CON" | tail -1)"
bash build/timing_roster_diff.sh build/evidence/r113_before_roster.txt "$RO" \
    > build/evidence/r113_roster_diff_rf.txt 2>&1
say "差分落 build/evidence/r113_roster_diff_rf.txt"
grep -a '^ROSTERDIFF' build/evidence/r113_roster_diff_rf.txt | sed 's/^/[rf] /'
grep -aq '^ROSTERDIFF-SUMMARY.*GREEN' build/evidence/r113_roster_diff_rf.txt
RC2=$?
say "名册差分 result=$([ $RC2 -eq 0 ] && echo GREEN || echo RED)（D1..D5 上一版已绿，这一支只验 D6 是不是我的工具）"
exit $RC2

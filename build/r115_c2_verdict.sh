#!/usr/bin/env bash
# build/r115_c2_verdict.sh —— C2（捕获钟挪早）证伪滚的**判定器**：S1..S5 一条一行，判定在最后一列
#
# 判据是 23:31 预先登记在 report/timing/rgmii_window_model.md §4 的，结果出来之后不许改口径（提示词 §6）。
#   S1 关住窗：`eth_rxc` 域 hold 的 WHS ≥ 0 **且** I/O hold 失败端点 = 0（改前 −2.885/−2.522 是红）
#   S2 机制：副本树网表里 MMCM ≥ 1 且 IDDR 仍 5 颗且 BUFG 仍在；主树同一把尺子必须报 0（正对照，规矩 46）
#   S3 名册：其余三域不许从 MET 掉进违例；`eth_rxc` 的 setup 不许变差
#   S4 债务方向：io_unconstrained_ports 应从 11 降到 6（这一刀只消输入侧 5 口）
#   S5 钟身份：派生钟的实名要出现在 CLKROW 里；**改名会让名册配对失效**，那要单列成 S5，不许混进 S3 的 RED
# ⚠ 这一轮**不采纳**：没有顶层台架、没有上板、没有批准人。S1–S5 全绿只等于"值得进正式一轮"。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?VP_VIVADO_BIN 必须给（见 report/build.md）}
SCR=/d/Xilinx/Prj/pro/c2_scratch_1003
EV=build/evidence/r115_c2_scratch
SDCP="$SCR/vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"
MDCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp
R=0
say() { printf '[c2v %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
line() { printf 'C2V %-14s %-46s %s %s\n' "$1" "$2" "$3" "$4" | tee -a "$EV/driver.log"; [ "$4" = RED ] && R=1; return 0; }
[ -f "$SDCP" ] || { say "REFUSE 副本树没有已布线 DCP：$SDCP（那一滚还没跑完或失败了）"; exit 2; }
if tasklist 2>/dev/null | grep -qiE '^vivado\.exe'; then say "REFUSE 已有 Vivado 在飞"; exit 2; fi
mkdir -p "$EV"
: > "$EV/driver.log"   # tee -a 会追加：上一轮的 C2V 行不许混进这一轮的凭据头（同 #298 那条）

say "① 出报告（副本树 DCP，只读）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/c2_scratch_probe.tcl > "$EV/probe_console.txt" 2>&1
say "② 网表机制尺：主树（期望 RED）+ 副本树（期望 GREEN）"
VP_C2_WANT=red "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_rgmii_capture_clock.tcl \
    > "$EV/pbc_main_red.txt" 2>&1
VP_C2_WANT=green VP_C2_DCP="$SDCP" "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_rgmii_capture_clock.tcl \
    > "$EV/pbc_scratch_green.txt" 2>&1

# ---- S2 机制 + 正对照 ----
mm_scr=$(grep -a "^PBC_COUNT" "$EV/pbc_scratch_green.txt" | sed -n 's/.*mmcm=\([0-9]*\).*/\1/p')
mm_main=$(grep -a "^PBC_COUNT" "$EV/pbc_main_red.txt" | sed -n 's/.*mmcm=\([0-9]*\).*/\1/p')
idr=$(grep -a "^PBC_COUNT" "$EV/pbc_scratch_green.txt" | sed -n 's/.*iddr=\([0-9]*\).*/\1/p')
bf=$(grep -a "^PBC_COUNT" "$EV/pbc_scratch_green.txt" | sed -n 's/.*bufg=\([0-9]*\).*/\1/p')
ph=$(grep -a "^PBC_PHASE" "$EV/pbc_scratch_green.txt" | sed -n 's/.*=\(.*\)$/\1/p')
ctl=$(grep -ac "PBC-VERDICT want=red got=RED" "$EV/pbc_main_red.txt")
if [ "${mm_scr:-0}" -ge 1 ] && [ "$idr" = 5 ] && [ "${bf:-0}" -ge 1 ] && [ "$ctl" = 1 ]; then
    line S2_mechanism "scratch mmcm=$mm_scr iddr=$idr bufg=$bf phase=[$ph] | 主树 mmcm=${mm_main:-NA} 正对照红=$ctl" \
        "≥1 / 5 / ≥1 且主树必须红" GREEN
else
    line S2_mechanism "scratch mmcm=${mm_scr:-NA} iddr=${idr:-NA} bufg=${bf:-NA} 正对照红=$ctl 主树mmcm=${mm_main:-NA}" \
        "≥1 / 5 / ≥1 且主树必须红" RED
fi

# ---- 先把名册造出来（S1 要读它的 eth_rxc 域 hold，S3/S4 也用它）----
python build/r115_roster_build.py "$EV/timing_summary.txt" "$EV/check_timing_verbose.txt" \
       "$EV/roster_scratch.tsv" c2scratch > "$EV/roster_build_console.txt" 2>&1
cat "$EV/roster_build_console.txt"

# ---- S1 关住窗 ----
# 设计级 hold 头条（件 $EV/summary_hold.txt 的第一条数行；列序取自该报告自己的表头
#   WHS(ns) THS(ns) THS Failing Endpoints THS Total Endpoints WPWS …）
s1=$(awk '/^\s+-?[0-9]+\.[0-9]+\s+-?[0-9]+\.[0-9]+/ {print $1, $3; exit}' "$EV/summary_hold.txt" 2>/dev/null)
whs=${s1%% *}; failh=${s1##* }
eth_whs=$(grep -a "^eth_rxc" "$EV/roster_scratch.tsv" 2>/dev/null | awk -F'\t' '{print $7}')
if [ -n "$whs" ] && awk -v x="$whs" 'BEGIN{exit !(x>=0)}' && [ "${failh:-1}" = 0 ]; then
    line S1_window_closed "design WHS=$whs io_fail_endpoints=$failh eth_rxc 域 whs=${eth_whs:-NA}" \
        "WHS>=0 且 I/O 失败端点=0（改前 -2.885）" GREEN
else
    line S1_window_closed "design WHS=${whs:-NA} io_fail_endpoints=${failh:-NA} eth_rxc 域=${eth_whs:-NA}" \
        "WHS>=0 且 I/O 失败端点=0" RED
fi

# ---- S5 钟身份（改名不是失败，是必须知道的事实）----
gen=$(grep -ac "generated=1" "$EV/probe_console.txt" 2>/dev/null)
rows=$(grep -a "^CLKROW" "$EV/probe_console.txt" | sed -n 's/^CLKROW name=\([^ ]*\).*/\1/p' | tr '\n' ' ')
line S5_clock_identity "generated=$gen clocks=[$rows]" "派生钟必须点名" INFO
printf '%s\n' "$rows" > "$EV/clock_names_scratch.txt"

# ---- S3 名册八对（表已在 S1 之前造好，这里只做差分）----
if [ -s "$EV/roster_scratch.tsv" ]; then
    dif=$(python build/r115_roster_build.py --diff report/timing/roster_baseline.tsv "$EV/roster_scratch.tsv" 2>&1)
    printf '%s\n' "$dif" > "$EV/roster_diff_vs_baseline.txt"
    pres=$(printf '%s\n' "$dif" | grep -ac "	presence	")
    mred=$(printf '%s\n' "$dif" | awk -F'\t' '$NF=="RED" && $2!="presence"{n++} END{print n+0}')
    sm=$(printf '%s\n' "$dif" | grep -a "ROSTERDIFF-SUMMARY" | tail -1)
    if [ "$pres" -gt 0 ]; then
        line S3_roster "presence_changed=$pres margin_red=$mred | $sm" \
            "钟改名 ⇒ 配对失效，S3 判不了（按 S5 处理，不许当绿也不许当红）" INFO
    elif [ "$mred" = 0 ]; then
        line S3_roster "margin_red=0 | $sm" "其余域不许变差" GREEN
    else
        line S3_roster "margin_red=$mred | $sm" "其余域不许变差" RED
    fi
else
    line S3_roster "roster 造不出来（见 roster_build_console.txt）" "有表才能比" RED
fi

# ---- S4 债务方向 ----
io=$(awk -F'\t' 'NR>1 && $1!~/^#/ && $1!="clock"{print $13; exit}' "$EV/roster_scratch.tsv" 2>/dev/null)
ue=$(awk -F'\t' 'NR>1 && $1!~/^#/ && $1!="clock"{print $12; exit}' "$EV/roster_scratch.tsv" 2>/dev/null)
if [ "${io:-99}" -le 6 ] && [ "${ue:-99}" = 0 ]; then
    line S4_debt "io_unconstrained=$io unconstrained_endpoints=$ue" "11 → 6 且端点仍 0" GREEN
else
    line S4_debt "io_unconstrained=${io:-NA} endpoints=${ue:-NA}" "11 → 6 且端点仍 0" RED
fi

{
  echo "# r115 C2 证伪滚判定头 —— 生成 $(date '+%F %T')"
  echo "# 主树 DCP=$MDCP  副本树 DCP=$SDCP"
  grep -a "^C2V " "$EV/driver.log" 2>/dev/null
} > "$EV/verdict_header.txt"
say "verdict rc=$R（S1–S5 只决定值不值得进正式一轮，不构成交付/采纳依据）"
exit $R

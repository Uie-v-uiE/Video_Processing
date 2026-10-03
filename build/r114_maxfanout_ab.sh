#!/usr/bin/env bash
# build/r114_maxfanout_ab.sh —— r114 的第一刀候选：高扇出广播加 set_max_fanout，值不值
#
# 这条链只做一件事：**同一份 opt.dcp 滚两遍**（A 不加约束 / B 加），然后用逐时钟名册差分来判，
# 而不是拿全局 WNS 的绝对差说事（rule 35）。约 2 × (place+route) ≈ 15~20 分钟，比一整轮构建+台架便宜一个数量级
# （记忆 line：这条快车道在这台工具上是确定性的，放置能逐位复现正式构建的数字）。
#
# 为什么要先问"扇出"这一刀：`report/TIMING_GLOBAL.md` 第 2/3 节量到的事实是
#   最差那族 route 占 84~94 %、逻辑级数只有 4~6 ⇒ 再改 RTL 没有物理依据；
#   而名册点名了两处广播（r112 实测 `rok4[51]_i_1_n_0` fo=305、`u_reasm/wr_en_reg_1` fo=547）。
#   官方口径正是把"高扇出网络的复制/扇出上限"排在逻辑重写**之前**
#   （UG949 Timing Closure；AMD 自适应支持文章 9410 Suggestions for high fanout signals）。
#
# 判读（每条一行，末列是判定）：
#   V1 两滚都跑完（ROLLDONE 各一次）
#   V2 B 滚的 MAX_FANOUT 真落到网上（roll 脚本里已有硬地板，这里核对那份日志）
#   V3 收益侧：目标族（u_rx_par/p_eof → u_reasm/rows_hit[*]/CE）的最差 slack 比 A 提升 >= +0.100 ns
#   V4 代价侧：**逐时钟名册差分 D1..D6 全绿**（任何其它域从 MET 掉进违例、或相对余量掉过 25 % 都判红）
#   V5 资源侧：LUT/FF 的增量念出来并设上限（复制扇出是要花单元的，白拿不算收益）
# 结论口径：V3 与 V4 同时绿 = 采纳候选；任一红 = 量过并否决，记进 ISSUES，不动主 XDC。
#
# 用法（必须在**没有别的 Vivado 在飞**的时候跑）：
#   bash build/r114_maxfanout_ab.sh                # 两轮都跑（约 15~20 分钟）
#   ONLY=B bash build/r114_maxfanout_ab.sh         # 只补跑某一滚
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
OUTDIR=build/evidence/r114_mf
GAIN_MIN=${GAIN_MIN:-0.100}
LUT_CAP=${LUT_CAP:-600}
mkdir -p "$OUTDIR" /tmp/kx
say() { printf '[mf %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE no Vivado (VP_VIVADO_BIN=$V)"; exit 2; }
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp
[ -f "$DCP" ] || { say "REFUSE no $DCP（这一轮的构建还没跑到 opt.dcp？）"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then
    say "REFUSE: 已经有 Vivado 在飞（这条实验要独占实现线程，并发会把两滚都拖慢并污染计时）"
    exit 2
fi

roll() { # $1=mode $2=dir
    say "roll $1 -> $2"
    MF_MODE=$1 MF_OUT=$2 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/mf114_roll.tcl \
        > "$2/roll_console.txt" 2>&1
    local rc=$?
    grep -a "ROLLDONE" "$2/roll_console.txt" >/dev/null || { say "roll $1 没跑完 rc=$rc（见 $2/roll_console.txt）"; return 1; }
    return 0
}

A=/tmp/kx/mf114/A; B=/tmp/kx/mf114/B
mkdir -p $A $B
[ "${ONLY:-A}" = "B" ] || roll none $A || exit 1
[ "${ONLY:-B}" = "A" ] || roll mf    $B || exit 1
for d in $A $B; do
    cp -f "$d/timing_summary.rpt" "$OUTDIR/$(basename $d)_timing_summary.rpt" 2>/dev/null
    cp -f "$d/util.rpt"           "$OUTDIR/$(basename $d)_util.rpt" 2>/dev/null
    cp -f "$d/family.rpt"         "$OUTDIR/$(basename $d)_family.rpt" 2>/dev/null
done

# 名册：两滚各自从自己的 timing_summary 长出（同一个转换器、同一口径，才许相减）
bash build/roster_from_summary.sh "$OUTDIR/A_timing_summary.rpt" > "$OUTDIR/roster_A.txt" 2>&1
bash build/roster_from_summary.sh "$OUTDIR/B_timing_summary.rpt" > "$OUTDIR/roster_B.txt" 2>&1
# 扇出名册也补进去：`timing_roster_diff.sh` 的 D6 判的是"抓手名册不许为空"，
#   而 roster_from_summary 只从时序报告长行（扇出不在里面）⇒ 这一列由滚自己的 fanout_after.rpt 供。
for d in A B; do
    grep -aoE '^ *[0-9]{3,} +[A-Za-z_/][A-Za-z0-9_/]*' "/tmp/kx/mf114/$d/fanout_after.rpt" 2>/dev/null \
      | awk '{printf "FANOUT|fo=%s|obj=%s\n", $1, $2}' >> "$OUTDIR/roster_$d.txt"
done
VERDICT="$OUTDIR/verdict.txt"
{
  say "==== r114 set_max_fanout A/B 判读 ===="
  grep -a "BIG_NETS=\|MF_APPLIED\|MF_PROBE\|PLACE_WALL\|ROUTE_WALL" $A/roll_console.txt | sed 's/^/[A] /'
  grep -a "BIG_NETS=\|MF_APPLIED\|MF_PROBE\|PLACE_WALL\|ROUTE_WALL" $B/roll_console.txt | sed 's/^/[B] /'
} > "$VERDICT"

R=0
line() { printf 'MFDIFF %-20s %-26s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }

# V1
na=$(grep -ac "ROLLDONE" $A/roll_console.txt); nb=$(grep -ac "ROLLDONE" $B/roll_console.txt)
line V1_both_rolls "A=$na B=$nb" "want 1/1" $([ "$na" = 1 ] && [ "$nb" = 1 ] && echo GREEN || echo RED)
# V2：B 滚必须真的把约束加上了（`MF_APPLIED objs=<非零>`），A 滚必须明确"没加"
applied=$(grep -a "MF_APPLIED objs=" $B/roll_console.txt | tail -1)
control=$(grep -a "MF_APPLIED none" $A/roll_console.txt | tail -1)
objs_n=$(printf '%s' "$applied" | sed -n 's/.*objs=\([0-9]\+\).*/\1/p')
line V2_variable_applied "B_objs=${objs_n:-0} A_control=${control:+seen}" "B_objs>=1" \
    $([ "${objs_n:-0}" -ge 1 ] && [ -n "$control" ] && echo GREEN || echo RED)

slack_of() { # 取一份 family.rpt 里第一条 Slack 的数值
    grep -aoE "Slack[^:]*: *-?[0-9]+\.[0-9]+" "$1" 2>/dev/null | head -1 | grep -oE -- "-?[0-9]+\.[0-9]+" | head -1
}
sa=$(slack_of "$OUTDIR/A_family.rpt"); sb=$(slack_of "$OUTDIR/B_family.rpt")
delta=$(awk -v a="${sa:-0}" -v b="${sb:-0}" 'BEGIN{printf "%.3f", b-a}')
line V3_family_gain "A=${sa:-NA} B=${sb:-NA} d=${delta}" "gain>=+${GAIN_MIN}ns" \
    $(awk -v d="$delta" -v m="$GAIN_MIN" 'BEGIN{print (d+0>=m+0)?"GREEN":"RED"}')

# V4：名册差分（这把尺子判的是**其它域**，正是"别一根筋"那一条）
DIFFOUT=$(bash build/timing_roster_diff.sh "$OUTDIR/roster_A.txt" "$OUTDIR/roster_B.txt" 2>&1)
cat <<<"$DIFFOUT" >> "$VERDICT"
dred=$(printf '%s\n' "$DIFFOUT" | grep -c ' RED$')
ndiff=$(printf '%s\n' "$DIFFOUT" | grep -c '^ROSTERDIFF-ROW ')
line V4_roster_no_cost "diff_rows=$ndiff red=$dred" "red=0" $([ "$dred" = 0 ] && [ "$ndiff" -ge 8 ] && echo GREEN || echo RED)

# V5：资源代价（复制高扇出是要花 LUT 的）
lut_a=$(grep -aoE "Slice LUTs[^0-9]*[0-9]+" "$OUTDIR/A_util.rpt" | grep -oE "[0-9]+" | tail -1)
lut_b=$(grep -aoE "Slice LUTs[^0-9]*[0-9]+" "$OUTDIR/B_util.rpt" | grep -oE "[0-9]+" | tail -1)
d_lut=$(( ${lut_b:-0} - ${lut_a:-0} ))
line V5_lut_cost "A=${lut_a:-NA} B=${lut_b:-NA} d=$d_lut" "abs<=${LUT_CAP}" \
    $([ "${lut_a:-0}" -gt 0 ] && [ "$d_lut" -ge -$LUT_CAP ] && [ "$d_lut" -le $LUT_CAP ] && echo GREEN || echo RED)

VERDICT_TXT=DECLINE
if [ $R -eq 0 ]; then VERDICT_TXT="ADOPT_CANDIDATE"; fi
{
  printf 'MF-SUMMARY gain=%s cost_red=%s lut_delta=%s verdict=%s\n' "$delta" "$dred" "$d_lut" "$VERDICT_TXT"
  printf '# 口径：收益只认目标族自己动没动（A/B 同一份 opt.dcp），代价认**逐时钟名册**；\n'
  printf '# 头条 WNS 的绝对差不算收益也不算损失（rule 35）。两个都必须绿才算采纳候选。\n'
} >> "$VERDICT"
say "判读落 $VERDICT"
tail -12 "$VERDICT"
exit $R

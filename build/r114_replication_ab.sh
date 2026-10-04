#!/usr/bin/env bash
# 用途：广播网"复制驱动"值不值：同一份 opt.dcp 滚两遍，变量只有一个
# 输入：命令行参数、build/tcl/mf114_roll.tcl
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=REFUSE
# build/r114_replication_ab.sh —— 广播网"复制驱动"值不值：同一份 opt.dcp 滚两遍，变量只有一个
#
# 变量（2026-10-03 实测后定稿，凭据 build/evidence/r113_help_fanout2_console.txt）：
#   A 滚 = place_design → phys_opt_design → route_design
#   B 滚 = place_design → phys_opt_design **-force_replication_on_nets {那些网}** → route_design
#   ⚠ 为什么不是 set_max_fanout：那条命令在本工具里**不存在**（help 回 No topics matched），
#     前两版这个脚本就是写给它'set_max_fanout $lim $objs'，跑起来只会在 catch 里失败，
#     两滚"没差别"会变成假结论。杠杆名是从 help 原文里读出来的，不是猜的。
#
# 判读（每条一行，末列是判定；顺序就是"先证机制能动，再谈收益"）：
#   V1  两滚都跑完（ROLLDONE 各一次）
#   V2  变量真落上了：B 有 MF_APPLIED nets>=1，A 有 MF_APPLIED none（对照必须明确"没加"）
#   V2b 机制动了（正对照，规矩 45/46）：B 的 REPLICA_CELLS 必须 **大于** A 的
#   V2c 机制动了的第二个独立读数（不同来源）：名册里至少一个网的扇出在 B 比 A **低**
#   V3  收益侧：目标族（u_rx_par/p_eof → u_reasm/rows_hit[*]/CE）最差 slack 提升 >= +0.100 ns
#   V4  代价侧：**逐时钟名册差分 D1..D6 全绿**（任何其它域从 MET 掉进违例、或相对余量掉过 25 % 都判红）
#   V5  资源侧：|ΔLUT| <= 600（复制是要花单元的，白拿不算收益）
# 结论口径：V2b/V2c 任一红 ⇒ verdict=MECHANISM_INERT（"这一刀没打到东西"，不写成"时序收益不成立"）；
#   机制绿之后才由 V3+V4+V5 决定 ADOPT_CANDIDATE / DECLINE。头条 WNS 的绝对差只念不判（rule 35）。
#
# 用法（必须没有别的 Vivado 在飞）：
#   bash build/r114_replication_ab.sh              # 两滚都跑（约 2 x 8~10 分钟）
#   ONLY=B bash build/r114_replication_ab.sh       # 只补跑某一滚
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
OUTDIR=build/evidence/r114_mf
GAIN_MIN=${GAIN_MIN:-0.100}
LUT_CAP=${LUT_CAP:-600}
MINFO=${MINFO:-200}
mkdir -p "$OUTDIR" /tmp/kx
say() { printf '[mf %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---- 尺子自己的对照（规矩：检查器要带自己的测试；这里测的是"网→扇出相减"那一层会不会因为
#      方括号被当正则而把下降判没）。两条都必须动：正对照点名的网给 203，负对照恒 0。 ----
fan_extract() { # $1 = 一份滚日志；出 "fo<TAB>net"
    grep -a '^MFROWAFTER|' "$1" \
      | awk -F"|" '{fo="";nm="";for(i=2;i<=NF;i++){if($i ~ /^fo=/)fo=substr($i,4);if($i ~ /^net=/)nm=substr($i,5)}; if(fo!=""&&nm!="")print fo"\t"nm}'
}
fan_drop() { # $1 = A 表 $2 = B 表
    awk -F"\t" 'NR==FNR{a[$2]=$1;next} ($2 in a){d=a[$2]-$1; if(d>best){best=d; nm=$2}} END{printf "%s %d\n", (nm==""?"NA":nm), best+0}' "$1" "$2"
}
if [ "${1:-}" = "--self" ]; then
    S=/tmp/kx/mf_self; mkdir -p $S
    printf 'MFROWAFTER|fo=305|net=rok4[51]_i_1_n_0\nMFROWAFTER|fo=547|net=u_reasm/wr_en_reg_1\n' > $S/a.log
    printf 'MFROWAFTER|fo=102|net=rok4[51]_i_1_n_0\nMFROWAFTER|fo=547|net=u_reasm/wr_en_reg_1\n' > $S/b.log
    fan_extract $S/a.log > $S/a.tsv; fan_extract $S/b.log > $S/b.tsv
    nrows=$(grep -c . $S/a.tsv)
    read -r sn sd <<<"$(fan_drop $S/a.tsv $S/b.tsv)"
    read -r wn wd <<<"$(fan_drop $S/a.tsv $S/a.tsv)"
    SR=0
    pl() { printf 'MFSELF %-22s %-34s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && SR=1; return 0; }
    pl T1_rows_parsed "rows=$nrows" "want 2" $([ "$nrows" = 2 ] && echo GREEN || echo RED)
    pl T2_positive_control "net=$sn drop=$sd" "rok4[51]_i_1_n_0 / 203" \
        $([ "$sn" = 'rok4[51]_i_1_n_0' ] && [ "$sd" = 203 ] && echo GREEN || echo RED)
    pl T3_negative_control "net=$wn drop=$wd" "NA / 0" $([ "$wn" = NA ] && [ "$wd" = 0 ] && echo GREEN || echo RED)
    printf 'MFSELF-SUMMARY rows=%d result=%s\n' "$nrows" "$([ $SR -eq 0 ] && echo GREEN || echo RED)"
    exit $SR
fi
[ -f "$V/vivado.bat" ] || { say "REFUSE no Vivado (VP_VIVADO_BIN=$V)"; exit 2; }
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp
[ -f "$DCP" ] || { say "REFUSE no $DCP（这一轮的构建还没跑到 opt.dcp？）"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then
    say "REFUSE: 已经有 Vivado 在飞（这条实验要独占实现线程，并发会把两滚都拖慢并污染计时）"
    exit 2
fi

roll() { # $1=mode $2=dir
    say "roll $1 -> $2"
    MF_MODE=$1 MF_OUT=$2 MF_MINFO=$MINFO "$V/vivado.bat" -mode batch -nojournal -source build/tcl/mf114_roll.tcl \
        > "$2/roll_console.txt" 2>&1
    local rc=$?
    grep -a "ROLLDONE" "$2/roll_console.txt" >/dev/null || { say "roll $1 没跑完 rc=$rc（见 $2/roll_console.txt）"; return 1; }
    return 0
}

A=/tmp/kx/mf114/A; B=/tmp/kx/mf114/B
mkdir -p $A $B
[ "${ONLY:-A}" = "B" ] || roll none $A || exit 1
[ "${ONLY:-B}" = "A" ] || roll repl $B || exit 1
for d in $A $B; do
    cp -f "$d/timing_summary.rpt" "$OUTDIR/$(basename $d)_timing_summary.rpt" 2>/dev/null
    cp -f "$d/util.rpt"           "$OUTDIR/$(basename $d)_util.rpt" 2>/dev/null
    cp -f "$d/family.rpt"         "$OUTDIR/$(basename $d)_family.rpt" 2>/dev/null
done

# 名册：两滚各自从自己的 timing_summary 长出（同一个转换器、同一口径，才许相减）
bash build/roster_from_summary.sh "$OUTDIR/a_timing_summary.rpt" > "$OUTDIR/roster_a.txt" 2>&1
bash build/roster_from_summary.sh "$OUTDIR/b_timing_summary.rpt" > "$OUTDIR/roster_b.txt" 2>&1
#   抓手名册由滚自己打的机器行供（report_design_analysis 没有 -fanout 模式，#263 已实测）
for d in A B; do
    grep -a '^MFROWAFTER|' "/tmp/kx/mf114/$d/roll_console.txt" 2>/dev/null \
      | sed 's/^MFROWAFTER|fo=/FANOUT|fo=/' >> "$OUTDIR/roster_$d.txt"
    say "roster_$d fanout_rows=$(grep -ac '^FANOUT|' "$OUTDIR/roster_$d.txt")"
done

VERDICT="$OUTDIR/verdict.txt"
{
  say "==== r114 复制驱动 A/B 判读 ===="
  grep -a "BIG_NETS=\|MF_APPLIED\|REPLICA_CELLS=\|PLACE_WALL\|ROUTE_WALL" $A/roll_console.txt | sed 's/^/[A] /'
  grep -a "BIG_NETS=\|MF_APPLIED\|REPLICA_CELLS=\|PLACE_WALL\|ROUTE_WALL" $B/roll_console.txt | sed 's/^/[B] /'
} > "$VERDICT"

R=0
MECH=0
line() { printf 'MFDIFF %-22s %-30s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }

# V1
na=$(grep -ac "ROLLDONE" $A/roll_console.txt); nb=$(grep -ac "ROLLDONE" $B/roll_console.txt)
line V1_both_rolls "A=$na B=$nb" "want 1/1" $([ "$na" = 1 ] && [ "$nb" = 1 ] && echo GREEN || echo RED)

# V2 变量
applied=$(grep -a "MF_APPLIED nets=" $B/roll_console.txt | tail -1)
control=$(grep -a "MF_APPLIED none" $A/roll_console.txt | tail -1)
objs_n=$(printf '%s' "$applied" | sed -n 's/.*nets=\([0-9]\+\).*/\1/p')
line V2_variable_applied "B_nets=${objs_n:-0} A_control=${control:+seen}" "B_nets>=1 且 A 明确没加" \
    $([ "${objs_n:-0}" -ge 1 ] && [ -n "$control" ] && echo GREEN || echo RED)

# V2b 机制：复制对象数必须不等（相等 = 这一刀没打到东西）
ra=$(grep -ao 'REPLICA_CELLS=[0-9]*' $A/roll_console.txt | tail -1 | grep -o '[0-9]*$')
rb=$(grep -ao 'REPLICA_CELLS=[0-9]*' $B/roll_console.txt | tail -1 | grep -o '[0-9]*$')
if [ -n "$ra" ] && [ -n "$rb" ] && [ "$rb" -gt "$ra" ]; then M2B=GREEN; MECH=$((MECH+1)); else M2B=RED; fi
line V2b_replicas_moved "A_replica=${ra:-NA} B_replica=${rb:-NA}" "B>A" $M2B

# V2c 机制的第二个独立读数：同一张名册里，至少一个网的扇出在 B 更低（来源与 V2b 不同）
#   ⚠ 网名带 `[51]` 这类字符，绝不能拿它当 grep/awk 的**正则**用（`[51]` 会被读成字符类，
#     "找不到"就成了假的下降）。这里先把两份"网→扇出"表落成 TSV，再按名字做**字符串**键相减。
for d in A B; do
    fan_extract "/tmp/kx/mf114/$d/roll_console.txt" > "/tmp/kx/mf114/${d}_after.tsv"
    say "$d after-fanout rows=$(grep -c . "/tmp/kx/mf114/${d}_after.tsv")"
done
read -r nm_best best_delta <<<"$(fan_drop "/tmp/kx/mf114/A_after.tsv" "/tmp/kx/mf114/B_after.tsv")"
if [ "${best_delta:-0}" -gt 0 ]; then M2C=GREEN; MECH=$((MECH+1)); else M2C=RED; fi
line V2c_fanout_dropped "net=${nm_best:-NA} drop=${best_delta:-0}" "至少一个网扇出下降" $M2C


slack_of() { grep -aoE "Slack[^:]*: *-?[0-9]+\.[0-9]+" "$1" 2>/dev/null | head -1 | grep -oE -- "-?[0-9]+\.[0-9]+" | head -1; }
sa=$(slack_of "$OUTDIR/a_family.rpt"); sb=$(slack_of "$OUTDIR/b_family.rpt")
delta=$(awk -v a="${sa:-0}" -v b="${sb:-0}" 'BEGIN{printf "%.3f", b-a}')
line V3_family_gain "A=${sa:-NA} B=${sb:-NA} d=${delta}" "gain>=+${GAIN_MIN}ns" \
    $(awk -v d="$delta" -v m="$GAIN_MIN" 'BEGIN{print (d+0>=m+0)?"GREEN":"RED"}')

# V4 名册差分（这把尺子判的是**其它域**，正是"别一根筋"那一条）
DIFFOUT=$(bash build/timing_roster_diff.sh "$OUTDIR/roster_a.txt" "$OUTDIR/roster_b.txt" 2>&1)
printf '%s\n' "$DIFFOUT" >> "$VERDICT"
dred=$(printf '%s\n' "$DIFFOUT" | grep -c ' RED$')
ndiff=$(printf '%s\n' "$DIFFOUT" | grep -c '^ROSTERDIFF-ROW ')
line V4_roster_no_cost "diff_rows=$ndiff red=$dred" "red=0 且 rows>=8" \
    $([ "$dred" = 0 ] && [ "$ndiff" -ge 8 ] && echo GREEN || echo RED)

# V5 资源代价
lut_a=$(grep -aoE "Slice LUTs[^0-9]*[0-9]+" "$OUTDIR/a_util.rpt" | grep -oE "[0-9]+" | tail -1)
lut_b=$(grep -aoE "Slice LUTs[^0-9]*[0-9]+" "$OUTDIR/b_util.rpt" | grep -oE "[0-9]+" | tail -1)
d_lut=$(( ${lut_b:-0} - ${lut_a:-0} ))
line V5_lut_cost "A=${lut_a:-NA} B=${lut_b:-NA} d=$d_lut" "abs<=${LUT_CAP}" \
    $([ "${lut_a:-0}" -gt 0 ] && [ "$d_lut" -ge -$LUT_CAP ] && [ "$d_lut" -le $LUT_CAP ] && echo GREEN || echo RED)

if [ $MECH -lt 2 ]; then
    VERDICT_TXT=MECHANISM_INERT
elif [ $R -eq 0 ]; then VERDICT_TXT=ADOPT_CANDIDATE
else VERDICT_TXT=DECLINE; fi
{
  printf 'MF-SUMMARY mech=%d/2 gain=%s cost_red=%s lut_delta=%s verdict=%s\n' "$MECH" "$delta" "$dred" "$d_lut" "$VERDICT_TXT"
  printf '# 口径：先证机制能动（V2b 复制对象数、V2c 网扇出，两个不同来源），再谈收益（V3 目标族）与代价（V4 逐时钟名册、V5 资源）；\n'
  printf '# 头条 WNS 的绝对差不算收益也不算损失（rule 35）。机制没动 ⇒ 这一刀没打到东西，不许写成"时序收益不成立"。\n'
} >> "$VERDICT"
say "判读落 $VERDICT"
tail -14 "$VERDICT"
exit $R

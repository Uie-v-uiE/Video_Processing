#!/usr/bin/env bash
# build/r115_fanout_ab.sh —— 提示词 §5 D1 + §4 C 的 C1 号切割：高扇出广播该不该被 phys_opt 复制驱动
#
# 唯一变量：布线前那一次 phys_opt_design 带不带 `-force_replication_on_nets <名册里的广播网>`。
#   A 滚 = mode=none（普通 phys_opt），B 滚 = mode=repl（带复制）。
#   两滚都从**同一份** `impl_1/system_top_opt.dcp`（r114 的，树 fp 在每次起跑前重新取）出发 ⇒
#   这是提示词 §1 H3 要的同 DCP 反事实，不是跨构建比较。
#
# 为什么排第一（§4 D 的分数口径）：名册里 rel_margin 最小的域是 eth_rxc（0.0924），
#   而 `report/TIMING_GLOBAL.md` §2/§3 量到的事实是那一族的 route 占 84~94 %、级数只有 4~6 ⇒
#   LOGIC 标签的刀没有物理依据，FANOUT 标签的刀有官方依据（UG949 + AMD 自适应支持文章 9410）。
#   上一轮（r114）这一滚死在"网对象取不到"（MF-REFUSE exit 4），尺子已按实测形状修好并干跑验过
#   （凭据 build/evidence/r114_mf_dry_console.txt），今晚是**这支脚本**第一次真正跑通。
# ⚠ 但别把这一跑读成"复制驱动第一次被试"：同一杠杆在 r114 已由 `build/r114_replication_ab.sh` 判负
#   （ISSUES #288：机制 0→296、`eth_rxc` hold 0.050→0.035）。两支尺子 agree 只加**可信度**，不加**样本数**
#   ⇒ §7 L2 的"3 条互相独立候选"不许把它数成两条。
#
# 判定（一条一行，判定在最后一列；计数是"做过多少次比较"，G9）：
#   F1 两滚都跑到 ROLLDONE
#   F2 两滚输入同一份 dcp（md5 两端相等）且树指纹相同（H4：起跑前取 fp）
#   F3 机制动没动：B 滚的 REPLICA_CELLS 严格大于 A 滚，否则 **MECHANISM_INERT**
#        （提示词附录 1 明说：机制没动就不许汇报"没有收益"，要汇报"机制未触发"）
#   F4 目标网扇出真的降了：逐条比 fanout_before/after 里同名网的扇出（B 应下降）
#   F5 名册差分：A vs B 逐域 rel_margin_setup / rel_margin_hold / 两列债务 ⇒ G1+G2，
#        两端都来自同一份尺子（python build/r115_roster_build.py --diff），噪声底 noise_ns=0.000
#        是 22:43 空白双滚量出来的（件 /tmp/kx/r115_noise/noise.txt）
#   F6 route_status = successful 且无 Place 30-439（G5）
#   F7 利用率没越界（G6）：B 滚 LUT/FF 相对 A 滚的增量必须逐条念出来（复制是要花单元的）
# ⚠ 不写被跟踪件，除非最后一步（evidence 目录）；不碰 runs 目录；已有产物先归档再跑，不覆盖（rule 17）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?VP_VIVADO_BIN 必须给（见 report/BUILD.md）}
[ -f "$V/vivado.bat" ] || { echo "[fanab] REFUSE Vivado bin 不存在: $V"; exit 2; }
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_opt.dcp
W=/tmp/kx/r115_fan
EV=build/evidence/r115_fanout_ab
R=0
say() { printf '[fanab %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
# 每条判定既上屏也落 $W/driver.log（tee）：上一版在这里读驱动自己的 stdout 快照，
# 那是拿管道缓冲当凭据（附录 1：轮询工具自己的工作目录）。
line() { printf 'FANAB %-24s %-40s %s %s\n' "$1" "$2" "$3" "$4" | tee -a "$W/driver.log"; [ "$4" = RED ] && R=1; return 0; }
[ -f "$DCP" ] || { say "REFUSE 没有 $DCP"; exit 2; }
if tasklist 2>/dev/null | grep -qiE '^vivado\.exe'; then say "REFUSE 已有 Vivado 在飞（H4：不许在构建进行中动源）"; exit 2; fi
mkdir -p "$W" "$EV"
: > "$W/driver.log"   # tee -a 会追加：上一秒那条"目录不存在就 RED"的账不许混进这一轮的凭据头
# rule 17：这个脚本的输出目录如果上一轮还在，先按 mtime 归档，别把唯一的快照盖掉。
# ⚠ --analyze 模式绝不能归档：它就是要读盘上那两滚。
if [ "${1:-}" != "--analyze" ]; then
    for d in A B; do
        [ -d "$W/$d" ] && mv "$W/$d" "$W/$d.prev.$(date +%H%M%S)"
    done
fi
MD=$(md5sum < "$DCP" | cut -c1-12)
FP=$(bash build/rtl_fingerprint.sh | tr '\n' ' ')
say "dcp md5=$MD  tree fp=$FP"
if [ "${1:-}" != "--analyze" ]; then
for m in none repl; do
    d=A; [ "$m" = repl ] && d=B
    # 目录必须由**驱动**先建：重定向 `> $W/$d/roll_console.txt` 在 Vivado 起来之前就发生，
    # 而 Tcl 里的 `file mkdir $out` 要晚一步才执行 ⇒ 上一版两个滚都在 0 秒内 RED（没烧一分钟 GPU 时间，
    # 是 bash 的 "No such file or directory"）。这是尺子的账，不是设计的账。
    mkdir -p "$W/$d"
    say "滚 $d (mode=$m) 起跑"
    MF_MODE=$m MF_OUT=$W/$d MF_MINFO=200 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/mf114_roll.tcl \
        > "$W/$d/roll_console.txt" 2>&1
    say "滚 $d rc=$?"
done
fi
hdr() { awk '/^\s+[0-9-]+\.[0-9]+\s+[0-9-]+\.[0-9]+/ {print $1, $5, $3, $7; exit}' "$1/timing_summary.rpt" 2>/dev/null; }
rep() { grep -a -m1 "^REPLICA_CELLS=" "$1/roll_console.txt" | cut -d= -f2; }
fa() { grep -a -m1 "FANOUT2_ERR=" "$1/roll_console.txt"; }
nA=$(hdr $W/A); nB=$(hdr $W/B)
rA=$(rep $W/A); rB=$(rep $W/B)
dA=$(grep -ac "^ROLLDONE" $W/A/roll_console.txt); dB=$(grep -ac "^ROLLDONE" $W/B/roll_console.txt)
# ^ 锚点必须有：批处理模式会把脚本自身**回显**一遍（`# puts "ROLLDONE mode=…"`），
# 不加行首锚点时两滚各数到 2，"want 1/1" 就把两条成功跑成判红（23:08 实测，尺子的账）。
line F1_both_rolls "A=$dA B=$dB" "want 1/1" $([ "$dA" = 1 ] && [ "$dB" = 1 ] && echo GREEN || echo RED)
m1=$(grep -a -m1 "^ROLL mode=" $W/A/roll_console.txt | sed -n 's/.*dcp=\([^ ]*\).*/\1/p')
m2=$(grep -a -m1 "^ROLL mode=" $W/B/roll_console.txt | sed -n 's/.*dcp=\([^ ]*\).*/\1/p')
same=$( [ -n "$m1" ] && [ "$m1" = "$m2" ] && echo yes || echo no )
line F2_same_inputs "dcp_md5=$MD dcp_line_equal=$same" "两滚同一份 dcp 同一棵树 fp" \
     $([ "$same" = yes ] && echo GREEN || echo RED)
# F3 机制：复制对象数必须**变多**才算动了。整数比较（rule：循环计数器是整数，别用字符串）。
if [ -z "$rA" ] || [ -z "$rB" ]; then
    line F3_mechanism "A=[$rA] B=[$rB]" "读数缺失=尺子断了" RED
elif [ "$rB" -gt "$rA" ]; then
    line F3_mechanism "A=$rA B=$rB" "_replica 变多 ⇒ 机制动了" GREEN
else
    line F3_mechanism "A=$rA B=$rB" "MECHANISM_INERT 不许写成没有收益" INFO
fi
# F4 目标网扇出：同名网在 B 滚 after 里的扇出应低于 A 滚 after。
# 逻辑放在 build/r115_fanout_cmp.py（它带自己的 --self 四条对照；heredoc 里塞 Python 今天炸过一次）。
f4=$(python build/r115_fanout_cmp.py "$W/A/fanout_after.rpt" "$W/B/fanout_after.rpt" 2>&1)
line F4_fanout_dropped "$f4" "B 滚同名网扇出应低于 A 滚" \
     $(case "$f4" in *lower=[1-9]*) echo GREEN;; NOOVERLAP*) echo RED;; *) echo INFO;; esac)
# F5 名册差分（H3 合法：两端同 DCP 同尺子；G1+G2 一次跑完 8 域 × 4 列）
python build/r115_roster_build.py "$W/A/timing_summary.rpt" "$W/A/check_timing_verbose.txt" "$W/roster_A.tsv" laneA >/dev/null 2>&1
python build/r115_roster_build.py "$W/B/timing_summary.rpt" "$W/B/check_timing_verbose.txt" "$W/roster_B.tsv" laneB >/dev/null 2>&1
if [ -s "$W/roster_A.tsv" ] && [ -s "$W/roster_B.tsv" ]; then
    difflines=$(python build/r115_roster_build.py --diff "$W/roster_A.tsv" "$W/roster_B.tsv" 2>&1)
    sm=$(printf '%s\n' "$difflines" | grep -a "ROSTERDIFF-SUMMARY" | tail -1)
    nred=$(printf '%s\n' "$difflines" | awk -F '\t' '$NF=="RED"{n++} END{print n+0}')
    line F5_roster_diff "$sm" "A vs B 逐域 G1+G2（noise_ns=0.000）" \
         $([ "$nred" -eq 0 ] && echo GREEN || echo RED)
    printf '%s\n' "$difflines" > "$W/roster_diff.txt"
else
    okA=missing; okB=missing
    [ -s "$W/roster_A.tsv" ] && okA=ok
    [ -s "$W/roster_B.tsv" ] && okB=ok
    line F5_roster_diff "roster_A=$okA roster_B=$okB" "名册造不出来" RED
fi
# F6 布线状态（G5）：**report_route_status 的文件里没有 "successful" 这个词**（23:09 实测形状），
# 它是一张净计数表 ⇒ 判据只能按形状写成"路由错误 0 且 全布净数 == 可布净数 且 > 0"。
# （上一版 grep "Successful" 恒 0，把两条成功跑判成 RED；那句 "completed successfully" 只在控制台的 INFO 里。）
p30=$(grep -ac "Place 30-439" $W/A/roll_console.txt $W/B/roll_console.txt 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
eA=$(grep -a "routing errors" $W/A/route_status.rpt 2>/dev/null | tr -cd '0-9')
eB=$(grep -a "routing errors" $W/B/route_status.rpt 2>/dev/null | tr -cd '0-9')
fA=$(grep -a "fully routed" $W/A/route_status.rpt 2>/dev/null | tr -cd '0-9')
rA=$(grep -a "routable nets" $W/A/route_status.rpt 2>/dev/null | tr -cd '0-9')
fB=$(grep -a "fully routed" $W/B/route_status.rpt 2>/dev/null | tr -cd '0-9')
rB=$(grep -a "routable nets" $W/B/route_status.rpt 2>/dev/null | tr -cd '0-9')
g6=RED
if [ "$eA" = 0 ] && [ "$eB" = 0 ] && [ -n "$fA" ] && [ "$fA" = "$rA" ] && [ -n "$fB" ] && [ "$fB" = "$rB" ] \
   && [ "$p30" = 0 ]; then g6=GREEN; fi
line F6_route_status "A[err=$eA full/rout=$fA/$rA] B[err=$eB full/rout=$fB/$rB] place30439=$p30" \
     "err=0 且 fully==routable 且无 Place 30-439" "$g6"
# F7 资源增量（只念不判：复制驱动必然吃单元，越界才是红）
ffA=$(awk -F'|' '/Register as Flip Flop/{print $3; exit}' $W/A/util.rpt 2>/dev/null | tr -d ' ')
ffB=$(awk -F'|' '/Register as Flip Flop/{print $3; exit}' $W/B/util.rpt 2>/dev/null | tr -d ' ')
luA=$(awk -F'|' '/LUT as Logic/{print $3; exit}' $W/A/util.rpt 2>/dev/null | tr -d ' ')
luB=$(awk -F'|' '/LUT as Logic/{print $3; exit}' $W/B/util.rpt 2>/dev/null | tr -d ' ')
line F7_utilization "FF A=$ffA B=$ffB (+$(( ${ffB:-0} - ${ffA:-0} ))) LUT A=$luA B=$luB (+$(( ${luB:-0} - ${luA:-0} )))" \
     "增量按实例归因：复制驱动必吃 FF/LUT" INFO
{
    echo "# r115 FANOUT A/B 件 —— dcp md5=$MD tree fp=$FP  噪声底 noise_ns=0.000（/tmp/kx/r115_noise/noise.txt）"
    grep -a "^FANAB " "$W/driver.log" 2>/dev/null
} > "$EV/verdict_header.txt"
cp "$W/roster_A.tsv" "$W/roster_B.tsv" "$W/roster_diff.txt" "$EV/" 2>/dev/null
cp "$W/A/timing_summary.rpt" "$EV/A_timing_summary.txt" 2>/dev/null
cp "$W/B/timing_summary.rpt" "$EV/B_timing_summary.txt" 2>/dev/null
cp "$W/A/fanout_before.rpt" "$W/B/fanout_after.rpt" "$EV/" 2>/dev/null
for d in A B; do grep -aE "^(ROLL|REPLICA_CELLS|BIG_NETS|NETOBJS|MF_APPLIED|FANOUT2_ERR|CHECKTIMING_ERR|DA_LEVELS_ERR|PLACE_WALL|ROUTE_WALL|ROLLDONE)" "$W/$d/roll_console.txt" > "$EV/${d}_keylines.txt" 2>/dev/null; done
say "verdict rc=$R  件在 $EV"
exit $R

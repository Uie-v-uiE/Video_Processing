#!/usr/bin/env bash
# 用途：名册对名册：这一轮**每个时钟域**各自动了多少，而不是只看那条头条 WNS
# 输入：命令行参数
# 输出：stdout
# 退出码：2=REFUSE 3=非 0 分支（该文件 exit 3 那一行）
# build/timing_roster_diff.sh —— 名册对名册：这一轮**每个时钟域**各自动了多少，而不是只看那条头条 WNS
#
# 为什么要这一把（2026-10-03，用户那句"别这么一根筋"的直接后果）：
#   `crit_path.tcl` 只把全设计最差的那条排第一 ⇒ 每轮看到的都是同一个 eth_rxc，
#   其它三个域是涨是跌没人念。规矩 35 早就说过"全局 WNS 的绝对差不算收益也不算损失"，
#   但那只挡住了"拿差值吹收益"，没挡住"把一个域改坏了而头条没动"。
#   这一把逐域配对比较，判的是：有没有哪个域从 MET 变成违例、有没有哪个域的**相对余量**掉了两成以上。
# 数据来源：`build/tcl/probe_timing_roster.tcl`（只读开 routed dcp，几分钟，不重建）。
# 用法：
#   bash build/timing_roster_diff.sh build/evidence/r113_before_roster.txt build/evidence/r113_after_roster.txt
#   bash build/timing_roster_diff.sh --self      # 十一条对照：坏的要红、好的要绿、GAIN 行的形状要算一条、
#                                                # 两侧口径不一致要 REFUSE、两侧都 NOWRITE 不许当成丢读数
set -u
LOST_PCT=${LOST_PCT:-25}          # 相对余量掉多少百分比算代价（同域内 slack/period 之比）
FLOOR_PAIRS=${FLOOR_PAIRS:-8}     # 至少要配上的 (时钟,类型) 对数：4 个域 × setup/hold
mkdir -p /tmp/kx

row() { printf 'ROSTERDIFF %-22s %-18s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }
R=0

if [ "${1:-}" = "--self" ]; then
    mk() { # 生成一份名册文本
        printf '%s\n' \
"ROSTER|setup|clk=eth_rxc|period=8.000|slack=0.445|margin_pct=5.56|levels=6|route_pct=88.1|dest=u_a/b_reg" \
"ROSTER|hold|clk=eth_rxc|period=8.000|slack=0.050|margin_pct=0.63|levels=2|route_pct=70.0|dest=u_a/c_reg" \
"ROSTER|setup|clk=clk_fpga_0|period=10.000|slack=1.135|margin_pct=11.35|levels=9|route_pct=82.0|dest=u_d/e_reg" \
"ROSTER|hold|clk=clk_fpga_0|period=10.000|slack=0.056|margin_pct=0.56|levels=3|route_pct=64.0|dest=u_d/f_reg" \
"ROSTER|setup|clk=clkout0_1|period=20.000|slack=4.467|margin_pct=22.34|levels=12|route_pct=76.0|dest=u_g/h_reg" \
"ROSTER|hold|clk=clkout0_1|period=20.000|slack=0.059|margin_pct=0.30|levels=4|route_pct=60.0|dest=u_g/i_reg" \
"ROSTER|setup|clk=sys_clk|period=20.000|slack=14.463|margin_pct=72.32|levels=5|route_pct=55.0|dest=u_j/k_reg" \
"ROSTER|hold|clk=sys_clk|period=20.000|slack=0.133|margin_pct=0.67|levels=2|route_pct=50.0|dest=u_j/l_reg" \
"FANOUT|fo=305|cell=u_pl/u_reasm/rows_hit_reg_51__i_1" \
"DESIGN|wns=0.445|whs=0.050" \
"ROSTER_ROWS=8"
    }
    chk() { # $1=A $2=B $3=期望 $4=标签
        printf '%s\n' "$1" > /tmp/kx/rd_a.txt; printf '%s\n' "$2" > /tmp/kx/rd_b.txt
        local got
        got=$(bash build/timing_roster_diff.sh /tmp/kx/rd_a.txt /tmp/kx/rd_b.txt 2>/dev/null \
              | grep -a '^ROSTERDIFF-SUMMARY' | tail -1 | sed 's/.*result=//' | tr -d '\r')
        if [ "$got" = "$3" ]; then say "SELF $4 expected=$3 got=$got PASS"; else say "SELF $4 expected=$3 got=$got FAIL"; return 1; fi
    }
    say() { printf '%s\n' "$*"; }
    base=$(mk)
    r=0
    # 1) 一模一样必须绿（尺子不能只会判红）
    a=$(mk); chk "$base" "$a" GREEN control_identical || r=1
    # 2) 头条没动、但 clkout0_1 掉成违例 ⇒ 必须红（这正是"只看最差那条"会漏的那一类）
    a=$(mk | sed 's/slack=4.467|margin_pct=22.34/slack=-0.200|margin_pct=-2.00/'); chk "$base" "$a" RED control_other_domain_violates || r=1
    # 3) 头条没动、某个域的相对余量掉三成 ⇒ 必须红（代价要被看见）
    a=$(mk | sed 's/slack=1.135|margin_pct=11.35/slack=0.600|margin_pct=6.00/'); chk "$base" "$a" RED control_margin_loss || r=1
    # 4) 所有域都变好 ⇒ 必须绿（不能把改进判成代价）
    a=$(mk | sed -e 's/slack=0.445|margin_pct=5.56/slack=0.900|margin_pct=11.25/' -e 's/slack=1.135|margin_pct=11.35/slack=1.600|margin_pct=16.00/'); chk "$base" "$a" GREEN control_all_improve || r=1
    # 5) 名册残缺 ⇒ 必须红：空转的尺子不许念绿。
    #    ⚠ 这条以前是 `head -3`（把后面几路钟整路删掉），但 19:24 加了"时钟名单必须一致"这道闸之后，
    #    整路删除会变成 REFUSE 而不是 RED——那是对的（整路消失是**两侧不是一个口径**，不是代价），
    #    所以这里换成"只删 sys_clk 的 hold 那一行"：时钟名单还在、配对数从 8 掉到 7 ⇒ 走 D2 的地板。
    a=$(printf '%s\n' "$base" | grep -av '^ROSTER|hold|clk=sys_clk'); chk "$base" "$a" RED control_scope_floor || r=1
    # 6) **收益行的形状**也是判据（rule 39：标签与单位是判据的一部分）：
    #    `+-31.7%绝对` 那种"双符号 + 错单位"复现出来就判红。这条是 2026-10-03 复制驱动 A/B
    #    第一次念出 GAIN 行才发现的（ISSUES #289）。
    mkdir -p /tmp/kx
    gfix=$(printf '%s\n' "$base" | sed -e 's/slack=0.445|margin_pct=5.56/slack=0.900|margin_pct=11.25/' \
                                     -e 's/slack=1.135|margin_pct=11.35/slack=1.600|margin_pct=16.00/')
    printf '%s\n' "$base" > /tmp/kx/rd_a.txt; printf '%s\n' "$gfix" > /tmp/kx/rd_b.txt
    gl=$(bash build/timing_roster_diff.sh /tmp/kx/rd_a.txt /tmp/kx/rd_b.txt 2>/dev/null | grep -a '^ROSTERDIFF-GAIN' | head -1)
    if printf '%s' "$gl" | grep -q -- '+-'; then
        say "SELF control_gain_line_shape got=$gl want=无双符号 FAIL"; r=1
    elif ! printf '%s' "$gl" | grep -q '相对余量+'; then
        say "SELF control_gain_line_shape got=$gl want=单位写成 相对余量+ FAIL"; r=1
    else
        say "SELF control_gain_line_shape got=$gl PASS"
    fi
    # 7) 同一把生成器的探针名册**本来就带散文与 NOWRITE 行** ⇒ 不许因此拒绝比较（假拒绝挡掉正当实验，
    #    这是我自己第一版闸门犯过的错，见文件内注）：只把 slack 写成散文、数值不变 ⇒ 必须照常 GREEN
    a=$(mk | sed 's/slack=0.445|/slack=0.445ns  (required time - arrival time)|/'); chk "$base" "$a" GREEN control_prose_allowed || r=1
    # 7b) B 侧扇出节整节缺失（= 另一把生成器，`roster_from_summary.sh` 那种）⇒ 必须 REFUSE
    a=$(mk | grep -av '^FANOUT|'); chk "$base" "$a" REFUSE control_fanout_parity || r=1
    # 8) B 侧整路钟不见（名单不一致）⇒ 必须 REFUSE（这既不是代价也不是收益，是两侧不是一个口径）
    a=$(printf '%s\n' "$base" | grep -av 'clk=sys_clk'); chk "$base" "$a" REFUSE control_clock_inventory || r=1
    # 9) 两侧都 NOWRITE（MMCM 反馈钟/辅助输出本来就没有 endpoint）⇒ 不许当成"读数变空"
    both=$(printf '%s\n' "$base" | grep -av '^DESIGN|')$'\n'"ROSTER|setup|clk=clkfbout|period=20.000|slack=NOWRITE|margin_pct=NA|levels=NA|route_pct=NA|dest=NA"
    both="$both"$'\n'"ROSTER|hold|clk=clkfbout|period=20.000|slack=NOWRITE|margin_pct=NA|levels=NA|route_pct=NA|dest=NA"
    printf '%s\n' "$base" > /dev/null; chk "$both" "$both" GREEN control_both_nowrite || r=1
    # 10) A 有读数、B 变 NOWRITE ⇒ 必须红（这才是 D5 该抓的那一类）
    a=$(printf '%s\n' "$base" | sed 's/slack=0.050|/slack=NOWRITE|/'); chk "$base" "$a" RED control_a_has_b_empty || r=1
    [ $r -eq 0 ] && say "SELF timing_roster_diff 对照 11/11 全过 PASS" || say "SELF timing_roster_diff FAIL"
    exit $r
fi

A=${1:-}
B=${2:-}
[ -f "$A" ] || { echo "ROSTERDIFF-SUMMARY result=REFUSE（没有改前名册 $A；先跑 probe_timing_roster.tcl）"; exit 2; }
[ -f "$B" ] || { echo "ROSTERDIFF-SUMMARY result=REFUSE（没有改后名册 $B）"; exit 2; }

# ---- 两边必须是**同一把生成器、同一套时钟**才许相减（rule 51：操作数要同单位同形状）----
# 2026-10-03 19:20 踩过：拿 r113 那份由 `probe_timing_roster.tcl` 生成的名册（slack 字段带
# "1.135ns  (required time - arrival time)" 这种散文、里面有 clkfbout 这一路钟）去减
# 由 `roster_from_summary.sh` 生成的干净名册 ⇒ D3 一口气数出 big_loss=8、D6 念 fanout_rows=0，
# 看着像"别的域被挤坏了"，其实两侧根本不是一个口径。件（已改名，别再当裁决读）
# build/evidence/r114_roster_diff_shape_mismatch_do_not_read_as_verdict.txt。
# 闸门只管**口径**（时钟名单 + 扇出节的有无），**不管 slack 字段长什么样**：探针那份本来就带散文
# （`slack=1.850ns  (required time - arrival time)`）与 `NOWRITE` 行，awk 取前导数就够用。
# 第一版我把"必须纯数"也写进闸门，结果把**合法的同口径配对**一起判成 REFUSE——
# "假拒绝挡掉正当实验"是 [[env-vivado-tcl-pblock-traps]] 里 `get_property RANGE` 那一课，又踩了一遍。
clks_a=$(grep -a '^ROSTER|' "$A" | sed -n 's/^ROSTER|[a-z]*|clk=\([^|]*\)|.*/\1/p' | sort -u | tr '\n' ' ')
clks_b=$(grep -a '^ROSTER|' "$B" | sed -n 's/^ROSTER|[a-z]*|clk=\([^|]*\)|.*/\1/p' | sort -u | tr '\n' ' ')
fo_a=$(grep -ac '^FANOUT|' "$A"); fo_b=$(grep -ac '^FANOUT|' "$B")
# 2026-10-05（D1 逼出来的修法）：**"B 多出一颗钟"不是口径不一致，而是这一轮把那条路从"没人检查"
#   变成了"有窗可检查"**（TMDS `clkout1_1` 在基线那份里没有行，绑上 `set_output_delay` 之后才出现）。
#   原来一律 REFUSE 会把正当实验挡回去（同上面注释里"假拒绝"那一课）。现在分成三种：
#     · A 里的钟在 B 里**消失** = 真口径不一致 ⇒ REFUSE（整路消失不可能是代价）；
#     · B 多出的钟**setup/hold 两行齐** = 新纳入检查的路，单独打印 `ROSTERDIFF-NEWTIMED` 让人看见，不挡；
#     · B 多出的钟只有半行 = 不是同一把生成器 ⇒ REFUSE。
missing_in_b=""
for c in $clks_a; do printf '%s ' "$clks_b" | grep -q "$c " || missing_in_b="$missing_in_b $c"; done
extra_in_b=""
for c in $clks_b; do printf '%s ' "$clks_a" | grep -q "$c " || extra_in_b="$extra_in_b $c"; done
half_new=""
for c in $extra_in_b; do
    ns=$(grep -ac "^ROSTER|setup|clk=$c|" "$B"); nh=$(grep -ac "^ROSTER|hold|clk=$c|" "$B")
    if [ "$ns" -ge 1 ] && [ "$nh" -ge 1 ]; then
        printf 'ROSTERDIFF-NEWTIMED clk=%s setup_rows=%s hold_rows=%s（这一轮新纳入检查的路，不参与差分）\n' "$c" "$ns" "$nh"
    else
        half_new="$half_new $c"
    fi
done
fan_mismatch=no
if { [ "$fo_a" -gt 0 ] && [ "$fo_b" -eq 0 ]; } || { [ "$fo_a" -eq 0 ] && [ "$fo_b" -gt 0 ]; }; then fan_mismatch=yes; fi
if [ -n "$missing_in_b" ] || [ -n "$half_new" ] || [ "$fan_mismatch" = "yes" ]; then
    printf 'ROSTERDIFF-SHAPE clocks_A=[%s] clocks_B=[%s] fanout_rows=%s/%s\n' "$clks_a" "$clks_b" "$fo_a" "$fo_b"
    echo "ROSTERDIFF-SHAPE 消失的钟=[${missing_in_b# }] 只有半行的新钟=[${half_new# }] 扇出节一边有一边无=$fan_mismatch"
    echo 'ROSTERDIFF-SHAPE 口径：两侧要同一把生成器——A 的钟不许在 B 消失、新钟要 setup+hold 齐、扇出节要同有同无（不同口径相减出来的不是代价，是尺子断）'
    echo "ROSTERDIFF-SUMMARY a=$A b=$B result=REFUSE"
    exit 3
fi

field() { printf '%s\n' "$1" | sed -n "s/.*$2=\([^|]*\).*/\1/p" | head -1 | tr -d '\r'; }
lookup() { # $1=文件 $2=时钟 $3=类型
    grep -a "^ROSTER|$3|clk=$2|" "$1" | head -1
}

clks=$(grep -a '^ROSTER|' "$A" | sed -n 's/^ROSTER|[a-z]*|clk=\([^|]*\)|.*/\1/p' | sort -u)
pairs=0
new_viol=0
big_loss=0
empty_b=0
loss_list=""
gain_list=""
for c in $clks; do
    for k in setup hold; do
        ra=$(lookup "$A" "$c" "$k"); rb=$(lookup "$B" "$c" "$k")
        [ -n "$ra" ] || continue
        [ -n "$rb" ] || { big_loss=$((big_loss+1)); loss_list="$loss_list ${c}/$k:MISSING"; continue; }
        pairs=$((pairs+1))
        sa=$(field "$ra" slack); sb=$(field "$rb" slack)
        pa=$(field "$ra" margin_pct); pb=$(field "$rb" margin_pct)
        # D5 的口径修正（2026-10-03 20:2x，r114 名册第一次按同口径配对跑出来才发现）：
        # 以前只要 **B 侧**这一格是 NOWRITE/空就计数，可 MMCM 的反馈钟与辅助输出（clkfbout/clkfbout_1/
        # clkout1_1/clkout2）本来就**两侧都**NOWRITE（这些钟没有 endpoint 是正常的），于是合法配对
        # 被念成 `empty_in_B=8 RED`。真正要抓的是"A 有读数、B 变成空"＝改后丢了可读的东西。
        case "$sa" in
            ''|NOWRITE) a_has=0 ;;
            *) case "$sa" in [0-9]*) a_has=1 ;; -[0-9]*) a_has=1 ;; *) a_has=0 ;; esac ;;
        esac
        case "$sb" in
            ''|NOWRITE) b_has=0 ;;
            *) case "$sb" in [0-9]*) b_has=1 ;; -[0-9]*) b_has=1 ;; *) b_has=0 ;; esac ;;
        esac
        if [ "$a_has" = 1 ] && [ "$b_has" = 0 ]; then empty_b=$((empty_b+1)); fi
        # 从 MET 变成违例（只算 setup 的新违例；hold 的负值同判）
        neg=$(awk -v x="$sb" 'BEGIN{ if (x+0 < 0) print 1; else print 0 }')
        wasneg=$(awk -v x="$sa" 'BEGIN{ if (x+0 < 0) print 1; else print 0 }')
        [ "$neg" = 1 ] && [ "$wasneg" = 0 ] && new_viol=$((new_viol+1))
        # 相对余量代价：同域 slack/period 之比掉过 LOST_PCT%
        dl=$(awk -v a="$pa" -v b="$pb" 'BEGIN{ if (a+0 <= 0) { print "NA"; exit } printf "%.1f", 100.0*((a+0)-(b+0))/(a+0) }')
        worse=$(awk -v d="$dl" 'BEGIN{ if (d=="NA") print 0; else if (d+0 > 0) print 1; else print 0 }')
        over=$(awk -v d="$dl" -v t="$LOST_PCT" 'BEGIN{ if (d=="NA") print 0; else if (d+0 > t+0) print 1; else print 0 }')
        [ "$over" = 1 ] && big_loss=$((big_loss+1))
        if [ "$worse" = 1 ]; then loss_list="$loss_list ${c}/$k:${sa}->${sb}(相对余量-${dl}%)"; fi
        if [ "$dl" != "NA" ]; then
            better=$(awk -v d="$dl" 'BEGIN{ if (d+0 < 0) print 1; else print 0 }')
            # ⚠ 这里以前印的是 `+${dl}%绝对`：dl 本身是负数 ⇒ 印出 `+-31.7%`（双符号），
            #   而且这个数是**相对余量的变化百分比**，与 COST 那一行的口径一模一样，
            #   却标成"绝对"（2026-10-03 r114 复制驱动 A/B 第一次念出来才发现，ISSUES #289）。
            #   现在与 COST 对称：`slack_a->slack_b(相对余量+X%)`，X 取正。
            if [ "$better" = 1 ]; then
                gp=$(awk -v d="$dl" 'BEGIN{ printf "%.1f", 0-(d+0) }')
                gain_list="$gain_list ${c}/$k:${sa}->${sb}(相对余量+${gp}%)"
            fi
        fi
        printf 'ROSTERDIFF-ROW %s/%s slack %s->%s margin_pct %s->%s\n' "$c" "$k" "$sa" "$sb" "$pa" "$pb"
    done
done

# 头条那一条按 rule 35 只念不判
sa=$(field "$(grep -a '^DESIGN|' "$A" | head -1)" wns); sb=$(field "$(grep -a '^DESIGN|' "$B" | head -1)" wns)
printf 'ROSTERDIFF-HEADLINE wns %s->%s（绝对差不算收益也不算损失，rule 35）\n' "$sa" "$sb"
fa=$(grep -ac '^FANOUT|' "$A"); fb=$(grep -ac '^FANOUT|' "$B")

row D1_no_new_violation "new=$new_viol" "expect=0" $([ "$new_viol" -eq 0 ] && echo GREEN || echo RED)
row D2_pairs_compared "pairs=$pairs" "floor>=$FLOOR_PAIRS" $([ "$pairs" -ge "$FLOOR_PAIRS" ] && echo GREEN || echo RED)
row D3_margin_cost "big_loss=$big_loss" "lost>${LOST_PCT}%的域数=0" $([ "$big_loss" -eq 0 ] && echo GREEN || echo RED)
row D4_hold_covered "hold_pairs=$(printf '%s\n' "$clks" | while read -r c; do [ -n "$(lookup "$A" "$c" hold)" ] && echo x; done | grep -c x)" "want>=2" $([ "$(printf '%s\n' "$clks" | while read -r c; do [ -n "$(lookup "$A" "$c" hold)" ] && echo x; done | grep -c x)" -ge 2 ] && echo GREEN || echo RED)
row D5_no_empty_readings "empty_in_B=$empty_b" "expect=0" $([ "$empty_b" -eq 0 ] && echo GREEN || echo RED)
row D6_fanout_inventory "fanout_rows=$fb" "want>=1" $([ "$fb" -ge 1 ] && echo GREEN || echo RED)

[ -n "$loss_list" ] && printf 'ROSTERDIFF-COST 变差的域:%s\n' "$loss_list"
[ -n "$gain_list" ] && printf 'ROSTERDIFF-GAIN 变好的域:%s\n' "$gain_list"
printf 'ROSTERDIFF-SUMMARY a=%s b=%s judged=6 pairs=%d result=%s\n' "$A" "$B" "$pairs" "$([ $R -eq 0 ] && echo GREEN || echo RED)"
exit $R

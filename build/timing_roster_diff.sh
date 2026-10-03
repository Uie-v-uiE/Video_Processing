#!/usr/bin/env bash
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
#   bash build/timing_roster_diff.sh --self      # 四条对照：尺子必须既能让坏的判红、也能让好的判绿
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
    # 5) 名册残缺（只配到 2 对）⇒ 必须红：空转的尺子不许念绿
    a=$(printf '%s\n' "$base" | head -3); chk "$base" "$a" RED control_scope_floor || r=1
    [ $r -eq 0 ] && say "SELF timing_roster_diff 对照 5/5 全过 PASS" || say "SELF timing_roster_diff FAIL"
    exit $r
fi

A=${1:-}
B=${2:-}
[ -f "$A" ] || { echo "ROSTERDIFF-SUMMARY result=REFUSE（没有改前名册 $A；先跑 probe_timing_roster.tcl）"; exit 2; }
[ -f "$B" ] || { echo "ROSTERDIFF-SUMMARY result=REFUSE（没有改后名册 $B）"; exit 2; }

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
        if [ "$sb" = "NOWRITE" ] || [ -z "$sb" ]; then empty_b=$((empty_b+1)); fi
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
            [ "$better" = 1 ] && gain_list="$gain_list ${c}/$k:+${dl}%绝对"
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

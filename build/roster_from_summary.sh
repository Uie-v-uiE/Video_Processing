#!/usr/bin/env bash
# build/roster_from_summary.sh —— 把 `report_timing_summary` 的**逐时钟表**转成名册行（不用开 Vivado）
#
# 为什么要这一把：`probe_timing_roster.tcl` 问的是改后那一版（还能带级数/route%/锥终点），
#   而"改前"那一版的 routed dcp **每轮构建都被覆盖**（r108 就吃过这个亏，见 #230）。
#   好在 `timing_summary.rpt` 的 Intra Clock Table 里有每个时钟各自的 WNS/WHS 与端点数，
#   而这份报告每轮都被归档 ⇒ 改前名册可以从报告里长回来，不必拿全局 WNS 说事（rule 35）。
# 口径：转换出来的行 levels/route_pct/dest 一律 NA —— 那三列只有探针给得出，缺就明说缺，不编。
# 用法：
#   bash build/roster_from_summary.sh build/evidence/r112_bit/timing_summary.rpt > build/evidence/r113_before_roster.txt
#   bash build/roster_from_summary.sh --self
set -u
mkdir -p /tmp/kx
row() { printf 'ROSTERFROMSUM %-24s %-16s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }
R=0

if [ "${1:-}" = "--self" ]; then
    printf '%s\n' "# fixture" > /tmp/kx/rs_a.rpt
    # 拿归档件当正对照：真实存在、且必须能转出 eth_rxc 0.445 / 0.050 那两个数
    real=build/evidence/r112_bit/timing_summary.rpt
    if [ -f "$real" ]; then
        all=$(bash build/roster_from_summary.sh "$real" 2>/dev/null)
        n=$(printf '%s\n' "$all" | grep -c '^ROSTER|')
        s=$(printf '%s\n' "$all" | grep -a '^ROSTER|setup|clk=eth_rxc|' | sed -n 's/.*slack=\([^|]*\).*/\1/p')
        h=$(printf '%s\n' "$all" | grep -a '^ROSTER|hold|clk=eth_rxc|' | sed -n 's/.*slack=\([^|]*\).*/\1/p')
        # 周期钉真值：eth_rxc 是 125 MHz RGMII ⇒ 8.000 ns。这一条专防"周期列取错一格"那种
        # 全都自洽但整张表都错的事故（slack 与 margin 会一起跟着错，只有钉住外部真值才抓得住）。
        p=$(printf '%s\n' "$all" | grep -a '^ROSTER|setup|clk=eth_rxc|' | sed -n 's/.*period=\([^|]*\).*/\1/p')
        ok=GREEN
        [ "$n" -ge 8 ] || ok=RED
        [ "$s" = "0.445" ] || ok=RED
        [ "$h" = "0.050" ] || ok=RED
        [ "$p" = "8.000" ] || ok=RED
        printf 'SELF fixture_real rows=%s eth_rxc_setup=%s eth_rxc_hold=%s eth_rxc_period=%s %s\n' "$n" "$s" "$h" "$p" "$ok"
        [ "$ok" = GREEN ] || exit 1
        # 变异对照：把那一行删掉 ⇒ 必须少一行（尺子不是把整份报告原样吐出来就算数）
        grep -v "^eth_rxc " "$real" > /tmp/kx/rs_mut.rpt
        n2=$(bash build/roster_from_summary.sh /tmp/kx/rs_mut.rpt 2>/dev/null | grep -c '^ROSTER|')
        ok2=RED; [ "$n2" -eq $((n-2)) ] && ok2=PASS   # 只该少这一个时钟的两行，少更多=整份没读进去
        printf 'SELF fixture_mutation rows=%s->%s %s\n' "$n" "$n2" "$ok2"
        [ "$ok2" = PASS ] || exit 1
        echo "SELF roster_from_summary judged=2 result=PASS"
        exit 0
    fi
    echo "SELF roster_from_summary result=REFUSE（没有归档的 timing_summary.rpt 可问）"
    exit 2
fi

SRC=${1:-}
[ -f "$SRC" ] || { echo "ROSTERFROMSUM-SUMMARY result=REFUSE（文件不存在：$SRC）"; exit 2; }

# 周期表：Clock Summary 里 `create_clock -period 8.000 -name eth_rxc` 这类行
# 周期从同一份报告的 Clock Summary 拿：`clk_fpga_0  {0.000 5.000}  10.000  100.000`
# （早先这里去 grep XDC 里的 `-period ... -name ...`，而归档的是**报告**不是 XDC ⇒ 一条也没抓到，
#   period 全成 NA、相对余量那条判据空转 —— 计数地板把这件事照出来了，见 --self）
grep -aE '^ *[A-Za-z_][A-Za-z0-9_]* +\{[0-9. ]+\} +[0-9.]+' "$SRC" \
  | awk '{gsub(/[{}]/,""); printf "%s %s %s\n", $1, $4, $5}' > /tmp/kx/rs_per.txt
# 周期列取错一次过：`clk_fpga_0  0.000 5.000  10.000  100.000` 里 $3 是**波形下降沿**不是周期
#   （$4 才是 Period(ns)）。所以这一把自己带一条交叉核对：周期 × 频率 ≈ 1000，两个操作数来自
#   同一张表的不同列（rule 46：一条形状行的两个操作数不许同源）。
PER_BAD=$(awk '{ if ($3+0 > 0) { d = ($2+0)*($3+0); if (d < 990 || d > 1010) b++ } else b++; n++ }
                END { printf "%d/%d bad=%d", n, n, b+0 }' /tmp/kx/rs_per.txt)
PER_N=$(awk 'END{print NR+0}' /tmp/kx/rs_per.txt)
PER_BADN=$(printf '%s' "$PER_BAD" | sed 's/.*bad=//')

# 一趟扫完：先读周期表，再读 Intra Clock Table；行数和行本身来自同一次扫描（不另起一个解析器）
awk 'FNR==NR { per[$1]=$2; nper++; next }
     /^ *[a-zA-Z_][A-Za-z0-9_]* +[0-9.-]+ +[0-9.-]+ +[0-9]+ +[0-9]+ +[0-9.-]+ +[0-9.-]+ +[0-9]+ +[0-9]+/ {
        if (index($0, ">") > 0) next
        clk=$1; wns=$2; whs=$6; ends_setup=$5; ends_hold=$9
        if (clk == "Design") { printf "DESIGN|wns=%s|whs=%s\n", wns, whs; next }
        p = (clk in per) ? per[clk] : "NA"
        m_s = "NA"; m_h = "NA"
        if (p != "NA" && p+0 > 0) { m_s = sprintf("%.2f", 100*wns/p); m_h = sprintf("%.2f", 100*whs/p) }
        printf "ROSTER|setup|clk=%s|period=%s|slack=%s|margin_pct=%s|levels=NA|route_pct=NA|dest=NA|endpoints=%s|src=timing_summary\n", clk, p, wns, m_s, ends_setup
        printf "ROSTER|hold|clk=%s|period=%s|slack=%s|margin_pct=%s|levels=NA|route_pct=NA|dest=NA|endpoints=%s|src=timing_summary\n", clk, p, whs, m_h, ends_hold
        c++
     }
     END { printf "SCANROWS %d %d\n", c+0, nper+0 }' /tmp/kx/rs_per.txt "$SRC" > /tmp/kx/rs_out.txt
grep -a '^ROSTER|' /tmp/kx/rs_out.txt
grep -a '^DESIGN|' /tmp/kx/rs_out.txt
set -- $(grep -a '^SCANROWS ' /tmp/kx/rs_out.txt | awk '{print $2, $3}')
n=${1:-0}; nper=${2:-0}

row S1_clock_rows "rows=$((n*2))" "floor>=8" $([ $((n*2)) -ge 8 ] && echo GREEN || echo RED)
row S2_period_known "periods=$nper" "want>=2" $([ "$nper" -ge 2 ] && echo GREEN || echo RED)
row S3_margin_computed "na_margin=$(grep -ac 'margin_pct=NA' /tmp/kx/rs_out.txt)" "want=0" \
    $([ "$(grep -ac 'margin_pct=NA' /tmp/kx/rs_out.txt)" -eq 0 ] && echo GREEN || echo RED)
row S4_period_freq_crosscheck "$PER_BAD" "bad=0" $([ "${PER_BADN:-1}" -eq 0 ] && [ "$PER_N" -ge 2 ] && echo GREEN || echo RED)
printf 'ROSTERFROMSUM-SUMMARY src=%s clock_rows=%d periods=%d result=%s\n' "$SRC" "$n" "$PER_N" "$([ $R -eq 0 ] && echo GREEN || echo RED)"
exit $R

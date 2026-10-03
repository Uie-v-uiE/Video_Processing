#!/usr/bin/env bash
# build/uncertainty_uniform_ab.sh —— "同一严口径"的 hold 体检：四域的 hold 余量到底可不可比
#
# 立案理由（这不是我又发明一条规矩，是把 already 存在的不对称量出来）：
#   `src/constraints/rk_zynq7020.xdc:50` 全工程只有这一行不确定度：
#     `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
#   其余三个域一条都没有 ⇒ 名册里那四个 WHS（0.050 / 0.056 / 0.059 / 0.133）**不是同一把尺量出来的**：
#   eth_rxc 那 0.050 里已经扣掉自加的 0.800，别的域一分没扣。
#   于是"四域 hold 都差不多"这句话是约束口径造出来的假象。依据不靠文档措辞背书：
#   UG949 有 "Additional Uncertainty" 与 "Relaxing the Setup Requirement While Keeping Hold Unchanged"
#   两节（页名可查，正文要 JS 抓不到，所以不引用原句），而**可比性本身就是算术**——同一条带不给全部时钟，
#   四个 WHS 就是两种口径把同一条带子给到每个时钟，才是"全局"的读法。
#   纯算术先念一句（这一句现在就能核对，不用跑工具）：0.056-0.800、0.059-0.800、0.133-0.800 全为负。
#
# 判读（每条一行，末列是判定；红只允许出现在**工具/口径**上，负余量是发现不是红）：
#   U1_rows_pers_domain   逐时钟 UNC 行数 >= 4（地板，空转会伪装成"没问题"）
#   U2_headline_complete  四个头条域的 before/after 都不许是 NA
#   U3_band_applied       UNC_APPLIED>=1 且 HOLD_UNCERTAINTY 读得回来（写了但工具没吃 = 假绿）
#   U4_setup_isolated     加 -hold 带之后设计级 setup 仍等于归档 timing_summary 里的 WNS
#                         （两个操作数**来自不同源**：探针自己念的 vs 归档件，对不上就是探针改了别的口径）
#   U5_neg_consistency    负余量的"个数"与逐条点名的行数一致（数得出才许说"有几域翻负"）
# 结论口径：本探针**不改设计、不重跑布线**，所以 after 是"同一悲观带下的 what-if"，
#   不许写成"板子 hold 坏了"；它回答的只有一个问题：现在的四域 hold 余量是不是同一口径。
#
# 用法：VP_SRC=<console.txt> bash build/uncertainty_uniform_ab.sh    # 只判一份现成产物
#       bash build/uncertainty_uniform_ab.sh                         # 起 Vivado 跑一遍再判
#       bash build/uncertainty_uniform_ab.sh --self                  # 尺子自己的对照（不起 Vivado）
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:?VP_VIVADO_BIN 必须给（本机 Vivado 的 bin 目录，写法见 report/BUILD.md；不把某台机器的路径写死进交付脚本）}
WNS_REF=${WNS_REF:-build/timing_summary.rpt}
HEADLINES=${HEADLINES:-"eth_rxc clk_fpga_0 clkout0_1 sys_clk"}
BAND=${BAND:-0.800}
R=0
row() { printf 'UNCCHK %-22s %-40s %s %s\n' "$1" "$2" "$3" "$4"; [ "$4" = RED ] && R=1; return 0; }
judge() { # $1 = console 文件
    local SRC="$1"
    local nrow applied readback sw neg_rows neg_printed
    nrow=$(grep -ao 'UNC_ROWS=[0-9]*' "$SRC" | tail -1 | grep -o '[0-9]*$')
    applied=$(grep -ao 'UNC_APPLIED=[0-9]*' "$SRC" | tail -1 | grep -o '[0-9]*$')
    readback=$(grep -a '^UNC_READBACK' "$SRC" | tail -1 | sed -n 's/.*hold_uncertainty=\(.*\)/\1/p')
    sw=$(grep -ao 'UNC_DESIGN_SETUP=[0-9.-]*' "$SRC" | tail -1 | grep -o '[0-9.-]*$')
    neg_rows=$(grep -a '^UNC|' "$SRC" | awk -F'|' '{for(i=2;i<=NF;i++) if($i ~ /^whs_after=-/) c++} END{print c+0}')
    neg_printed=$(grep -ac '^UNC_NEG ' "$SRC")
    row U1_rows_pers_domain "rows=${nrow:-NA}" "floor>=4" $([ "${nrow:-0}" -ge 4 ] && echo GREEN || echo RED)
    local miss="" c
    for c in $HEADLINES; do
        local ln
        ln=$(grep -a "^UNC|clk=$c|" "$SRC" | tail -1)
        case "$ln" in
            *whs_before=NA*|*whs_after=NA*|'') miss="$miss $c" ;;
        esac
    done
    row U2_headline_complete "missing=${miss:-none}" "四域都要有数" $([ -z "$miss" ] && echo GREEN || echo RED)
    # U3：带子必须**真落上**。两个证据：applied>=1，且至少一个域的 after 比 before 小。
    #   （属性名 HOLD_UNCERTAINTY 我**没验过**，所以探针把读回结果念出来但**不参与判定**——
    #    "写了但工具没吃"这件事由 before/after 自己说，不许靠一个可能拼错的属性名。）
    local moved
    moved=$(grep -a '^UNC|' "$SRC" | awk -F"|" '{b="";a2="";for(i=2;i<=NF;i++){ \
        if($i ~ /^whs_before=/){b=$i; sub(/^whs_before=/,"",b)}; \
        if($i ~ /^whs_after=/){a2=$i; sub(/^whs_after=/,"",a2)}}; \
        if(b!="NA"&&a2!="NA"&&b!=""&&a2!=""&&(a2+0)<(b+0)) c++} END{print c+0}')
    local ok3=GREEN
    [ "${applied:-0}" -ge 1 ] || ok3=RED
    [ "${moved:-0}" -ge 1 ] || ok3=RED
    row U3_band_applied "applied=${applied:-0} moved=${moved:-0} readback=${readback:-none}" "applied>=1 且 moved>=1" $ok3

    # U4/U6：与**归档的** timing_summary 比（两个操作数来自不同源：探针自己念的 vs 归档件的那一行）
    #   真实形状（build/timing_summary.rpt:149-151，小写 (ns)）：
    #     | Design Timing Summary / 分隔线 / 表头 / 破折号行 / 数值行
    #     数值行第 1 个字段是 WNS、第 5 个是 WHS ⇒ 取"表头之后第一个字段数 >= 12 且首字段是数"的那一行。
    local ref ref_w
    read -r ref ref_w <<<"$(awk '/Design Timing Summary/{f=1;next} f && NF>=12 && $1 ~ /^-?[0-9]+\.[0-9]+$/ {print $1, $5; exit}' "$WNS_REF" 2>/dev/null)"
    local d
    d=$(awk -v a="${sw:-9}" -v b="${ref:-9}" 'BEGIN{v=a-b; if(v<0)v=-v; printf "%.3f", v}')
    row U4_setup_isolated "probe=$sw ref_wns=${ref:-NA} absd=$d" "absd<=0.001ns" \
        $(awk -v x="${d:-9}" 'BEGIN{print (x+0<=0.001)?"GREEN":"RED"}')
    # eth_rxc 的 before 必须等于归档 WHS（同一份设计、不同工具入口；对不上说明读错了 dcp）
    local eb
    eb=$(grep -a '^UNC|clk=eth_rxc|' "$SRC" | tail -1 | grep -o 'whs_before=[0-9.-]*' | grep -o '[0-9.-]*$')
    local d2
    d2=$(awk -v a="${eb:-9}" -v b="${ref_w:-9}" 'BEGIN{v=a-b; if(v<0)v=-v; printf "%.3f", v}')
    row U6_same_design "probe_eth_rxc_whs=${eb:-NA} ref_whs=${ref_w:-NA} absd=$d2" "absd<=0.001ns" \
        $(awk -v x="${d2:-9}" 'BEGIN{print (x+0<=0.001)?"GREEN":"RED"}')
    row U5_neg_consistency "counted=$neg_rows printed=$neg_printed" "两数相等" \
        $([ "$neg_rows" = "$neg_printed" ] && echo GREEN || echo RED)
    printf 'UNCCHK-SUMMARY src=%s band=%s neg_domains=%s result=%s\n' "$SRC" "$BAND" "$neg_rows" "$([ $R -eq 0 ] && echo GREEN || echo RED)"
    printf '# 口径：after 是"同一悲观带下的 what-if"（没重跑布线），负余量是发现、不是红；红只允许出现在工具/口径上。\n'
    return $R
}
if [ "${1:-}" = "--self" ]; then
    S=/tmp/kx/unc_self; mkdir -p $S/ref
    # 对照用的"归档件"必须按**真实形状**写（build/timing_summary.rpt:145-151），否则测的是我自己的桩而不是尺子
    cat > "$S/ref/t.txt" <<'EOF'
| Design Timing Summary
| ---------------------
--------------------------------------------------------------------------------

    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------
      0.445        0.000                      0                51135        0.050        0.000                      0                51135        0.264        0.000                       0                 12634
EOF
    cat > "$S/good.txt" <<'EOF'
CLOCKS_TOTAL=6
UNC_APPLIED=6
UNC_ERR=no-error
UNC_READBACK clk=eth_rxc hold_uncertainty=0.800
UNC|clk=eth_rxc|whs_before=0.050|whs_after=-0.750
UNC|clk=clk_fpga_0|whs_before=0.056|whs_after=-0.744
UNC|clk=clkout0_1|whs_before=0.059|whs_after=-0.741
UNC|clk=sys_clk|whs_before=0.133|whs_after=-0.667
UNC|clk=clkfbout_1|whs_before=NA|whs_after=NA
UNC|clk=clkout1_1|whs_before=NA|whs_after=NA
UNC_NEG clk=eth_rxc slack=-0.750
UNC_NEG clk=clk_fpga_0 slack=-0.744
UNC_NEG clk=clkout0_1 slack=-0.741
UNC_NEG clk=sys_clk slack=-0.667
UNC_DESIGN_SETUP=0.445
UNC_ROWS=6
UNC_NEG_COUNT=4
UNC_DONE=1
EOF
    # 每条对照都用 sed 从 good.txt 派生**一处**改动（改动点按内容认，不按行号认 —— 规矩 43）
    grep -vE '^UNC\|clk=(clk_fpga_0|clkout0_1|sys_clk)\||^UNC_NEG' "$S/good.txt" > "$S/trunc.txt"                  # 只剩一域 ⇒ U1 地板与 U2 缺域**两条一起红**（同一个根：名册残缺）
    sed 's/^UNC_APPLIED=6/UNC_APPLIED=0/; s/hold_uncertainty=0.800/hold_uncertainty=/' "$S/good.txt" > "$S/noapplied.txt"
    grep -v '^UNC_NEG clk=sys_clk' "$S/good.txt" > "$S/mismatch.txt"                                                 # 计数与点名不一致 ⇒ U5 该红
    sed 's/^UNC_DESIGN_SETUP=0.445/UNC_DESIGN_SETUP=0.999/' "$S/good.txt" > "$S/wrongsetup.txt"                       # ⇒ U4 该红
    sed 's/^UNC|clk=eth_rxc|whs_before=0.050/UNC|clk=eth_rxc|whs_before=0.450/' "$S/good.txt" > "$S/wrongdesign.txt" # ⇒ U6 该红（读错 dcp）
    # nochange：把每行的 after 改成与 before 同数 ⇒ "写了带子但一个数都没动" ⇒ U3 该红
    sed -e 's/whs_before=0.050|whs_after=-0.750/whs_before=0.050|whs_after=0.050/' \
        -e 's/whs_before=0.056|whs_after=-0.744/whs_before=0.056|whs_after=0.056/' \
        -e 's/whs_before=0.059|whs_after=-0.741/whs_before=0.059|whs_after=0.059/' \
        -e 's/whs_before=0.133|whs_after=-0.667/whs_before=0.133|whs_after=0.133/' \
        -e '/^UNC_NEG/d' -e 's/^UNC_NEG_COUNT=4/UNC_NEG_COUNT=0/' "$S/good.txt" > "$S/nochange.txt"
    export WNS_REF=$S/ref/t.txt
    SR=0
    run() { # $1=fixture $2=expect
        local rc
        judge "$S/$1.txt" > "$S/$1.out" 2>&1; rc=$?
        printf 'SELF %-16s expect=%s got=%s\n' "$1" "$2" "$([ $rc -eq 0 ] && echo GREEN || echo RED)"
        grep -a ' RED$' "$S/$1.out" | sed 's/^/      /'
        if [ "$2" = GREEN ] && [ $rc -ne 0 ]; then SR=1; fi
        if [ "$2" = RED ] && [ $rc -eq 0 ]; then SR=1; fi
    }
    run good GREEN
    run trunc RED
    run noapplied RED
    run mismatch RED
    run wrongsetup RED
    run wrongdesign RED
    run nochange RED
    echo "UNCSELF result=$([ $SR -eq 0 ] && echo GREEN || echo RED)"
    exit $SR
fi
CON=${VP_SRC:-}
if [ -z "$CON" ]; then
    if tasklist 2>/dev/null | grep -qiE '^(vivado)\.exe'; then
        printf '[unc] REFUSE: 已经有 Vivado 在飞\n'; exit 2
    fi
    if tasklist 2>/dev/null | grep -qiE '^xsimk?\.exe'; then
        printf '[unc] REFUSE: 台架 xsim 还在跑（开 routed dcp 会挤它）\n'; exit 2
    fi
    # ⚠ 输出件名**按轮号走**，不许写死上一轮的名字：2026-10-03 21:56 这一跑就是把
    #   `build/evidence/r113_uncertainty_console.txt` 原地覆盖了（那份从来没进 git、也没被任何文档引用，
    #   所以没有丢失凭据——但同一个毛病今天已经栽第三次，见 ISSUES #295 第 3 条）。
    UNC_NN=${VP_UNC_NN:-$(date +%Y%m%d_%H%M)}
    CON=build/evidence/r${UNC_NN}_uncertainty_console.txt
    if [ -f "$CON" ] && git ls-files --error-unmatch "$CON" >/dev/null 2>&1; then
        printf '[unc] REFUSE: %s 是被跟踪的上一轮快照，不给覆盖（换 VP_UNC_NN）
' "$CON"; exit 2
    fi
    VP_BAND=$BAND "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_uncertainty_uniform.tcl > "$CON" 2>&1
    printf '[unc] probe rc=%s\n' "$?"
    cp -f "$CON" "build/evidence/r${UNC_NN}_uncertainty_raw.txt" 2>/dev/null || true
fi
grep -a '^UNC|' "$CON"
judge "$CON"
exit $?

#!/bin/bash
# build/gates.sh —— 一条命令读回"门禁七项"，并和阈值比。
#
#   bash build/gates.sh                 # 读 build/ 里当前这套报告（= 最近一次构建）
#   bash build/gates.sh build/frozen_r19_arb   # 读某一组成套冻结件
#
# 数字全部来自 Vivado 报告本身，不重新跑构建；退出码：全绿 0，任何一项红 1。
# 阈值口径与 report/OVERNIGHT_LOG.md §1 的门禁表一致（**不要因为某项红了就改这里的阈值**）。
set -u
D=${1:-build}
pick() { [ -f "$D/$1" ] && echo "$D/$1" || echo "$D/../$1"; }   # 冻结目录里缺的文件回落到 build/
T=$(pick timing_summary.rpt); U=$(pick utilization.rpt)
P=$(pick power.rpt);          M=$(pick methodology.rpt)
R=$(pick route_status.rpt);   C=$(pick cdc.rpt)

for f in "$T" "$U" "$P" "$R"; do
    [ -f "$f" ] || { echo "FATAL 缺报告：$f"; exit 2; }
done
echo "报告目录：$D"
# 新鲜度提醒（2026-09-23 差点踩的坑：构建还在跑就念门禁，念到的是**上一版**的数字，七项照样全绿）。
# 一次构建里 bit 与报告只差几十秒（bit 先写），所以判据是"相差超过 10 分钟就当它不是一套"。
bit="$D/system.bit"; [ -f "$bit" ] || bit=build/system.bit
if [ -f "$bit" ]; then
    age=$(( $(stat -c %Y "$T") - $(stat -c %Y "$bit") ))
    [ "$age" -lt 0 ] && age=$(( -age ))
    echo "新鲜度：system.bit $(stat -c %y "$bit" | cut -c1-19) / timing $(stat -c %y "$T" | cut -c1-19)"
    [ "$age" -le 600 ] || echo "        WARN 两者相差 $((age/60)) 分钟 ⇒ 可能不是同一套产物（等构建结束，或按 md5 核对冻结目录）"
    # 另一面：产物之间一致，但**整批都比 RTL 旧** —— 那就是"改完没重跑"，念到的是上一版。
    # （2026-09-24 真踩过：构建还在跑，我先跑了一次门禁，全套报告都是 30 分钟前的、七项全绿。）
    # 只对 build/ 这份"活目录"检查：冻结目录按定义就是历史产物，源码必然更新，报出来是噪声。
    if [ "$D" = "build" ]; then
        newer=$(find src/rtl -name '*.v' -newer "$bit" 2>/dev/null | head -3)
        [ -z "$newer" ] || echo "        WARN 有 RTL 源比 system.bit 新 ⇒ 这份产物不含这些改动："$(echo $newer | tr '\n' ' ')
    fi
fi

# 1) WNS / WHS / 失败端点：Design Timing Summary 的第一行数据
#    （直接认那一行的形状：0.598 0.000 0 23424 0.043 0.000 0 23424 …，比按标题数段落稳）
read -r wns whs tnsfail whsfail eps <<<"$(awk '
  /^[ ]*[-+]?[0-9]+\.[0-9]+[ ]+[0-9]+\.[0-9]+[ ]+[0-9]+[ ]+[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+/ && !d {
      printf "%s %s %s %s %s", $1, $5, $3, $7, $8; d=1 }' "$T")"
[ -n "${wns:-}" ] || { echo "FATAL 读不到 timing summary"; exit 2; }
# 2) 资源（"Slice LUTs" 已是 Logic+Memory 之和；FS='|' 时行首有个空字段，
#    所以列序是 $2=名字 $3=Used $4=Fixed $5=Prohibited $6=Available $7=Util%）
bram=$(awk -F'|' '/Block RAM Tile/{gsub(/ /,"",$3); print $3; exit}' "$U")
bramp=$(awk -F'|' '/Block RAM Tile/{gsub(/ /,"",$7); print $7; exit}' "$U")
lut=$(awk -F'|' '/Slice LUTs/{gsub(/ /,"",$3); print $3; exit}' "$U")
lutp=$(awk -F'|' '/Slice LUTs/{gsub(/ /,"",$7); print $7; exit}' "$U")
reg=$(awk -F'|' '/Slice Registers/{gsub(/ /,"",$3); print $3; exit}' "$U")
# 3) 功耗（Analyze Power/Dynamic）
dyn=$(awk -F'|' '/Dynamic \(W\)/{gsub(/ /,"",$3); print $3; exit}' "$P")
# 4) 方法学 Critical 数
crit=$(grep -ac "CRITICAL WARNING" "$M" 2>/dev/null); crit=${crit:-0}
# 5) 布线：有路由错误的网线数（那一行是 "... :   0 :"，取最后一个纯数字字段）
rerr=$(grep -a "nets with routing errors" "$R" | grep -oE '[0-9]+' | tail -1); rerr=${rerr:-NA}
# 6) CDC Critical 行 —— **与基线的"行集合"比，不与一个写死的数字比**。
#    为什么改（#26 的实录）：原来这项写死"4 行以内算过"，而我给 dbg_src 加了一对
#    像素域→axi 的同步器，Critical 从上一版的 3 行变成 4 行，脚本照样打印 PASS ——
#    **门禁把自己要挡的东西漏掉了**。现在认"新增了哪几条 src→dst 配对"，
#    条数变少也不算改进（少了的原因没查清之前，只报出来不记账，见 §10 U14）。
# 环境变量 CDCBASE 可覆盖：为了让"这条判据本身能不能红"有一份可跑的测试
# （`build/gates_cdc_test.sh` 要喂它一份故意改坏的基线，而不许去动仓库里那份真的）。
CDCBASE=${CDCBASE:-build/CDC_BASELINE.txt}
# 端点数取"倒数第 5 个字段"、unsafe 取"倒数第 3 个"，而不是固定列号：CDC Type 的 token 数会变
# （"No Common Primary Clock" 4 个、"Safely Timed" 2 个），写死列号会读成 0 或读成别的列。
# 末五列永远是 Endpoints / Safe / Unsafe / Unknown / No-ASYNC_REG ⇒ 从尾巴数才稳。
rows() { awk '/^Critical/{print $2">"$3, $(NF-4), $(NF-2)}' "$1" 2>/dev/null | sort; }   # "配对 端点数 unsafe"
cur=$(rows "$C")
base=''
cdcc=$(printf '%s\n' "$cur" | grep -c '[^ ]'); cdcc=${cdcc:-0}
newrows='' gone='' epgrow='' ugrow='' nbase=0
if [ -f "$CDCBASE" ]; then
    # 基线必须是整齐的三列。坏一行就当这一项**没门禁**，直接判红 ——
    # 静默把缺的第三列当 0，等于"谁都能靠删一个数字让 CDC 变绿"。
    base=$(grep -v '^#' "$CDCBASE" | awk 'NF>0{if (NF!=3) {print "  BADLINE"; exit} } NF==3{print $1,$2,$3}' | sort)
    if printf '%s\n' "$base" | grep -q BADLINE; then
        echo "        FATAL $CDCBASE 有行不是『配对 端点数 unsafe』三列 ⇒ 这一项不敢判绿"
        base=$(printf '%s\n' "$base" | grep -v BADLINE)
        cdc_base_broken=1
    else
        cdc_base_broken=0
    fi
    base=$(printf '%s\n' "$base" | grep -v BADLINE)
    nbase=$(printf '%s\n' "$base" | grep -c '[^ ]'); nbase=${nbase:-0}
    newrows=$(comm -13 <(printf '%s\n' "$base" | awk '{print $1}') <(printf '%s\n' "$cur" | awk '{print $1}'))
    gone=$(comm -23 <(printf '%s\n' "$base" | awk '{print $1}') <(printf '%s\n' "$cur" | awk '{print $1}'))
    # 同一条配对的端点数变大 = 这条跨域上又挂了寄存器 —— 只提示（加一级仲裁寄存就会 +1，
    # 判红会让人去绕开门禁）。但 **unsafe 数变大不是中性事件**，那是"这条跨域上又多了一处
    # 没被 ASYNC_REG/握手保护住的采样点"，判红（ISSUES #65：V8-5 的 CDC-11 就是这么躲过第 6 项的）。
    # join 出来的字段序：$1=配对 $2=基线端点 $3=基线unsafe $4=本版端点 $5=本版unsafe
    epgrow=$(join <(printf '%s\n' "$base") <(printf '%s\n' "$cur") 2>/dev/null \
             | awk '$2+0 != $4+0 && $4+0 > $2+0 {printf "%s(%s→%s) ", $1, $2, $4}')
    ugrow=$(join <(printf '%s\n' "$base") <(printf '%s\n' "$cur") 2>/dev/null \
             | awk '$5+0 > $3+0 {printf "%s(unsafe %s→%s) ", $1, $3, $5}')
else
    echo "        WARN 没有 $CDCBASE —— CDC 这项退化成"只把数字摆出来"，不比等于没门禁"
    cdc_base_broken=1
fi
cdc_ok=1
[ -n "$newrows" ] && cdc_ok=0
[ -n "$newrows" ] && echo "        新增 Critical 配对：$(printf '%s ' $newrows)  ⇒ 这一项判红"
[ "$cdc_base_broken" = 1 ] && cdc_ok=0
[ -n "$gone" ]    && echo "        基线里有而本版没有：$(printf '%s ' $gone)（原因未查证，不算改进）"
# 端点数增长只提示不判红：真正的新危险是"多一条跨域配对"和"某条配对的 unsafe 变多"，
# 前者一直是判红项，后者从 r56 起也是（见上面 #65 的理由）。
[ -n "$epgrow" ]  && echo "        同配对端点数增长：$epgrow（记录用，不判红）"
[ -n "$ugrow" ]   && cdc_ok=0
[ -n "$ugrow" ]   && echo "        Unsafe 端点增长：$ugrow  ⇒ 这一项判红（#65）"

# 自检：解析不出来的项一律当失败（"检查器自己也要有判据"，见学习文档 §十二）
for v in wns whs tnsfail whsfail eps bram bramp lut lutp reg dyn crit rerr cdcc; do
    eval "x=\$$v"
    case "$x" in ""|NA) echo "FATAL 解析不到 \$v —— 报告格式变了？不要拿空值当 0 判绿"; exit 2;; esac
done
[[ "$wns$whs$bramp$lutp" =~ ^[0-9.+\-]+$ ]] || { echo "FATAL 数字字段解析异常: $wns|$whs|$bramp|$lutp"; exit 2; }
pass=1
say() { # say <名字> <实测> <判据文本> <0/1>
    printf "  %-22s %-12s %-28s %s\n" "$1" "$2" "$3" "$([ "$4" = 1 ] && echo PASS || { echo FAIL; })"
    [ "$4" = 1 ] || pass=0
}
echo "门禁七项："
say "WNS (ns)"        "$wns"  ">= 0"            $(awk -v v="$wns" 'BEGIN{print (v+0>=0)?1:0}')
say "失败 setup 端点"   "$tnsfail" "== 0"           $([ "$tnsfail" -eq 0 ] && echo 1 || echo 0)
say "WHS (ns)"        "$whs"  ">= 0"            $(awk -v v="$whs" 'BEGIN{print (v+0>=0)?1:0}')
say "失败 hold 端点"    "$whsfail" "== 0"           $([ "$whsfail" -eq 0 ] && echo 1 || echo 0)
say "BRAM (tile/%)"   "$bram/$bramp%" "<= 97%"    $(awk -v v="$bramp" 'BEGIN{print (v+0<=97)?1:0}')
say "Slice LUT / 占比"  "$lut/$lutp%" "<= 98%"      $(awk -v v="$lutp" 'BEGIN{print (v+0<=98)?1:0}')
say "Slice 寄存器"     "$reg"  "记录用（无阈值）"   1
say "Dynamic (W)"     "$dyn"  "与前次同量级"      1
say "methodology CRIT" "$crit" "== 0"            $([ "$crit" -eq 0 ] && echo 1 || echo 0)
say "布线错误网线"      "$rerr" "== 0"            $([ "$rerr" -eq 0 ] && echo 1 || echo 0)
say "cdc.rpt Critical 行" "$cdcc" "基线 $nbase 行，配对不新增、unsafe 不增长" "$cdc_ok"
# 8) 端口宽度不匹配的**端口连接**警告（Synth 8-689）—— #57 的教训：
#    system_top 里 `wire [5:0] dbg_src` 接在 8 bit 的端口上，综合只给这么一条警告，
#    lane30 的模式高位就被静默吞掉（读出来永远 0/1），而七项门禁当时全绿。
#    工具早就把 file:line 报出来了，没人读警告 ⇒ 把它变成门禁项。
BLOG=$(ls -t "$D"/log_*system*.txt 2>/dev/null | head -1)
# 先认"与这套报告同一次构建"的凭据文件（构建脚本自己写的 width_warnings.txt）；
# 找不到才回落到最新日志 —— 回落时必须**点名它是回落**：2026-09-24 就出现过
# 报告是 r48 的、日志却是红掉的 r49 的，那一刻这一项"绿"得毫无意义。
if [ -f "$D/width_warnings.txt" ] || [ -f "$D/../width_warnings.txt" ]; then
    WF=$(pick width_warnings.txt)
    W689=$(awk '{print $1}' "$WF")
    say "端口宽度警告 8-689" "$W689" "== 0（凭据 $(basename "$WF")，同一次构建）" \
        $([ "$W689" = "0" ] && echo 1 || echo 0)
elif [ -z "$BLOG" ]; then
    say "端口宽度警告 8-689" "NOLOG" "无凭据=未验" 0
else
    W689=$(grep -ac "Synth 8-689" "$BLOG" || true)
    [ -z "$W689" ] && W689=NA
    say "端口宽度警告 8-689" "$W689" "== 0（⚠ 回落：$(basename "$BLOG")，未与报告绑定）" \
        $([ "$W689" = "0" ] && echo 1 || echo 0)
fi
[ "$W689" != "0" ] && grep -a "Synth 8-689" "$BLOG" 2>/dev/null | sed 's/^/        /' | head -6

# 13) 多驱动 net（Synth 8-6859 / 8-6858）—— #61 的教训（2026-09-24 深夜）。
#     一个 reg 的复位被我同时写进两个 always 块 ⇒ 综合**保留常量那一侧、忽略逻辑那一侧**，
#     bit 里那根旗标恒为 0；而仿真按"进程后写覆盖"，台架 56 条全绿。
#     这类"仿真绿、硬件不动"的差别不会出现在任何时序/资源报告里，只能读综合的 CRITICAL WARNING。
#     凭据文件与 8-689 同一处生成（build/multi_driven.txt），一起进冻结目录。
if [ -f "$D/multi_driven.txt" ] || [ -f "$D/../multi_driven.txt" ]; then
    MF=$(pick multi_driven.txt)
    MD=$(awk '{print $1}' "$MF")
    say "多驱动 net 8-685x" "$MD" "== 0（凭据 $(basename "$MF")，同一次构建）" \
        $([ "$MD" = "0" ] && echo 1 || echo 0)
elif [ -z "$BLOG" ]; then
    say "多驱动 net 8-685x" "NOLOG" "无凭据=未验" 0
else
    MD=$(grep -ac "multi-driven net" "$BLOG" || true)
    [ -z "$MD" ] && MD=NA
    say "多驱动 net 8-685x" "$MD" "== 0（⚠ 回落：$(basename "$BLOG")，未与报告绑定）" \
        $([ "$MD" = "0" ] && echo 1 || echo 0)
fi
[ "${MD:-0}" != "0" ] && grep -a "multi-driven net" "$BLOG" 2>/dev/null | sed 's/^/        /' | head -6

# 14) 顶层接线（端口名对得上、输入都没悬空）—— V8-5 的教训（2026-09-25 凌晨）。
#     为什么单独一项：`pl_video_top` / `system_top` **没有任何台架例化**（今晚 grep 确认），
#     所以"改了子模块端口、顶层忘了连"这类错 L1 全量 57 条一条都不会红，
#     只能等 25 分钟的构建 —— 今晚 osd_overlay 换端口就踩在这个空档上。
#     判据脚本自己有反例：拿两份故意改坏的拷贝跑，必须分别报"连了不存在的端口"和"输入没连"
#     （见 report/OVERNIGHT_LOG.md §33 与 skill/ 那条"判据要有自己的测试"）。
#     r52 加宽到第三条**位宽**（`dbg_lat` 从 5 口变 6 口时想到的：#57 那类"高位被一根窄线吞掉"
#     名字对得上、仿真与综合都不报，只有把两头量出来才看得见）。反例两份 + 一份负对照，
#     凭据 `build/ports_check_width_ce.txt`。
#     历史冻结件里没有 ports_check.txt ⇒ 这一项对它们**跳过而不是判红**：
#     这一项是拿"当前源码树"跑的，历史包没有对应的树，红一个没有意义的红只会让人去关门禁。
if [ "$D" = "build" ]; then
    python build/check_ports.py > build/ports_check.txt 2>&1; PCEXIT=$?
    PCTXT=$(tail -1 build/ports_check.txt)
    say "顶层接线（端口名/悬空输入/位宽）" "$PCTXT" "violations=0（凭据 build/ports_check.txt，当场跑）" \
        $([ "$PCEXIT" = 0 ] && echo 1 || echo 0)
    grep -v "^CHECK PORTS\|^  skipped" build/ports_check.txt 2>/dev/null | sed 's/^/        /' | head -8
else
    PCF=$(pick ports_check.txt)
    if [ -f "$PCF" ]; then
        grep -q "violations=0" "$PCF" && say "顶层接线（端口名/悬空输入/位宽）" "$(cat "$PCF")" "violations=0" 1 \
            || say "顶层接线（端口名/悬空输入/位宽）" "$(cat "$PCF")" "violations=0" 0
    else
        echo "  n/a  顶层接线 —— 该冻结件早于第 14 项，没有对应的 ports_check 凭据（不判红，见上面注释）"
    fi
fi
echo
echo "端点总数 $eps；CDC 现在按 build/CDC_BASELINE.txt 的**配对集合**判，功耗仍要人比有没有变差。"
if [ "$pass" = 1 ]; then echo "GATES: ALL PASS"; exit 0; else echo "GATES: 有红项 —— 不采纳，保留上一版"; exit 1; fi

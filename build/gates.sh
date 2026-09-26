#!/bin/bash
# build/gates.sh —— 一条命令读回门禁清单，并和阈值比。
#   条数会随教训增长（2026-09-23 那会儿是"七项"；r70 起 **15 项** = 第 15 项顶层台架
#   `tb_v98` 的报告必须与当前顶层同一次跑，出处 #88/#92；今天再加两项：**16 = PS 心跳与
#   停心跳的约定**（#94）、**17 = 手写件的编码**（COMMANDS §5 曾被 cp936 打坏一整段）、
#   **18 = 文档时效**（README/PERF_REPORT 把 build#23 念成"当前默认"整整五十版）
#   ⇒ 这里**不再写死条数**，以本文件里 `say` 的调用次数为准。
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
# ⚠ 2026-09-25 r60 红过一次"门禁自己没牙"：TNS 在违例时是**负数**（-6.457），
#    而原来的式子只给 WNS/WHS 留了符号位、TNS 那两列没留 ⇒ awk 不匹配 ⇒
#    脚本打印 `FATAL 读不到 timing summary` 然后 exit 2。停下来是对的（没把自己判绿），
#    但它把最该看见的数字（WNS −0.482 / 19 个失败端点）换成了"读不到"这句话。
#    现在四列数字都允许带符号，而且**读不到时把候选行原样打出来**——
#    尺子读不懂被测对象，必须说"我读的是这一行"，不许只说"读不到"。
read -r wns whs tnsfail whsfail eps <<<"$(awk '
  /^[ ]*[-+]?[0-9]+\.[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+[ ]+[0-9]+[ ]+[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+/ && !d {
      printf "%s %s %s %s %s", $1, $5, $3, $7, $8; d=1 }' "$T")"
if [ -z "${wns:-}" ]; then
  echo "FATAL 读不到 timing summary 的那一行数字。报告里最像的三行是："
  grep -aE '^[ ]*[-+]?[0-9]+\.[0-9]+[ ]+[-+]?[0-9]+\.[0-9]+' "$T" | head -3 | sed 's/^/    /'
  exit 2
fi
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
echo "门禁清单（逐项，条数以本文件 say 调用为准）："
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
# 14) WNS/WHS 的**归属组**（记录用，绝不判红）—— 2026-09-26 的教训，出处 `report/OPTIMIZATION_LOG.md` §4。
#     上表念的是 Design Timing Summary 里那**一个**数，而它由两条互不相干、都属"布线主导"的路径轮流决定：
#     125 MHz ETH 组（`u_cdc/wbin→BRAM ENARDEN`、`u_lm/ms32→gap_min`）对上 50 MHz 像素组（`u_pipe→u_osd` 字形）。
#     同一套约束三次构建 WNS = 0.918 / 0.807 / 0.314，只抄那一个数就会误判成"某次改动拖慢了设计"
#     （r64b 的 0.314 与双线性**无因果**：ETH 域一行 RTL 没动）⇒ 分组数才是可比的量。
#     判据不变（还是上表那一项），这一块只负责"把话说清是谁"；From!=To 的跨组路径不在这里，
#     读不到分组行时明说"未验"，不许把空表当成通过。
echo "分组最差（记录用；判据仍是上表的 WNS/WHS）："
GRP=$(awk '
  /^From Clock:/ {from=$3}
  /^  To Clock:/ {to=$3}
  /^Setup :/ && from!="" && from==to {v=$8; gsub(/ns,?/,"",v); print from"|"v"|"$3"|setup"}
  /^Hold  :/ && from!="" && from==to {v=$8; gsub(/ns,?/,"",v); print from"|"v"||hold"}
' "$T")
[ -n "$GRP" ] || echo "  n/a 读不到 From==To 分组行 ⇒ 这一项未验（不当 0、也不当通过）"
echo "$GRP" | awk -F'|' -v wns="$wns" '
  $4=="setup" {sup[$1]=$2; sf[$1]=$3; next}
  $4=="hold"  {hol[$1]=$2}
  END {for (g in sup) {own=""; if (sup[g]==wns) {own="   ← 门禁 WNS 就是这一组"; hit=1}
        h=(hol[g]==""?"NA":hol[g]"ns");
        print sprintf("  %-12s setup %-8s (失败端点 %s)   hold %-8s%s", g, sup[g]"ns", sf[g], h, own)}
        if (!hit) print "  ⚠ 门禁 WNS 不来自任何 From==To 组 ⇒ 它是跨时钟组/IO 路径，去报告里认那一组"}' | sort

echo
# 15) 顶层台架（`tb_v98_top_seam` 的 C0/C1/C2/C3）—— #88 留下的那一半，2026-09-26 补上。
#     缺口原来长这样：`pl_video_top` 唯一的台架一次要跑 40+ 帧（八档缩放扫描）≈ 75 分钟，
#     放进"构建完就读"的门禁里没人会等 ⇒ 于是第 1~14 项**不含任何顶层内容级判据**，
#     #88 那几天"gates 14/14"与"唯一例化顶层的台架红着"是**同时成立**的两件事。
#     折衷：门禁不跑它，但**必须**认一份与当前顶层同一次跑出来的报告 ——
#     `build/tb_v98_report.txt` 头部两枚 md5（顶层源 + 台架源）与树里的现值必须对得上，
#     并且正文里既没有 `FAIL ` 行、又有一行 `RESULT tb_v98_top_seam PASS`（两条都要：
#     只有后一条时，"跑挂了、什么都没判"也能伪装成绿 —— 本项目为这类"空集上成立"记过几次账）。
#     反例（判据自己的测试，凭据 `build/tb98_gate_ce.txt`）：
#       A. 头部 `top_md5` 改成不相干的 12 位 ⇒ 这一项必须红，且说的是"报告与当前顶层不是同一次跑"；
#       B. 把 RESULT 行删掉 ⇒ 必须红（跑完这件事要有证据）；
#       C. 造一份"有 RESULT PASS 但也有一行 FAIL"的报告 ⇒ 必须红（红项不许被汇总行盖掉）。
if [ "$D" = "build" ]; then
    TB98=${TB98_REPORT:-build/tb_v98_report.txt}   # 反例脚本用这个变量指到临时报告上
    if [ -f "$TB98" ]; then
        TOPWANT=$(md5sum src/rtl/top/pl_video_top.v | cut -c1-12)
        TBWANT=$(md5sum sim/tb_v98_top_seam.v | cut -c1-12)
        RTLWANT=$(find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
        TOPYES=$(sed -n 's/.*top_md5=\([0-9a-f]*\).*/\1/p' "$TB98" | head -1)
        TBYES=$(sed -n 's/.* tb_md5=\([0-9a-f]*\).*/\1/p' "$TB98" | head -1)
        RTLYES=$(sed -n 's/.* rtl_md5=\([0-9a-f]*\).*/\1/p' "$TB98" | head -1)
        NFAIL=$(grep -ac "^FAIL " "$TB98")
        DONE=$(grep -ac "^RESULT tb_v98_top_seam PASS$" "$TB98")
        # 台架"跑完了并且自己判红"与"跑挂了什么都没判"是**两件不同的事**，念成一句话就会把人
        # 支去重跑一次 75 min 的台架（而真正该做的是读那三行 FAIL 的数）。汇总行里有 FAIL 就直说。
        RFIN=$(grep -ac "^RESULT tb_v98_top_seam FAIL" "$TB98")
        OK=1
        WHY=""
        [ "$TOPYES" = "$TOPWANT" ] || { OK=0; WHY="$WHY顶层 md5 不符($TOPYES!=$TOPWANT：改过 pl_video_top，报告与当前树不是同一次跑) "; }
        # 顶层之外的那一路也必须对得上：r72 改的是四个窗口级，`pl_video_top.v` 一个字节没动，
        # 只比顶层 md5 的话 r71 的旧报告能原样冒充今天的凭据（今天就差一点撞上）。
        if [ "$RTLYES" != "$RTLWANT" ]; then
            OK=0; WHY="${WHY}RTL 合指纹不符(${RTLYES:-报告头部没有 rtl_md5 字段——那是加这枚指纹之前的旧报告}!=$RTLWANT：改过 src/rtl 里顶层之外的文件，这份报告不算当前树) ";
        fi
        [ "$TBYES" = "$TBWANT" ]   || { OK=0; WHY="$WHY台架 md5 不符($TBYES!=$TBWANT：改过 tb_v98，复跑) "; }
        [ "$NFAIL" = "0" ]         || { OK=0; WHY="$WHY报告里有 $NFAIL 行 FAIL "; }
        [ "$DONE" = "1" ]          || { OK=0; WHY="$WHY没有 RESULT…PASS 汇总行（$([ "$RFIN" -gt 0 ] && echo "台架跑完了、是它自己判红的，先读 FAIL 那几行的数" || echo "台架没跑完或中途退出")） "; }
        say "顶层台架 tb_v98" "top=$TOPYES FAIL行=$NFAIL" "同一次跑且无 FAIL" $OK
        [ -n "$WHY" ] && echo "        ——$WHY"
    else
        say "顶层台架 tb_v98" "缺 build/tb_v98_report.txt" "必须先跑 tb98_report.sh" 0
        echo "        —— 生成：bash sim/run_one.sh tb_v98_top_seam && bash build/tb98_report.sh"
    fi
else
    echo "  n/a  顶层台架 tb_v98 —— 历史冻结件不带与它同一次跑的顶层 md5，不判红（同第 14 项的口径）"
fi

# ---- 16：#94 固件那一半的约定（心跳节拍 / 超时余量 / 收心跳的调用点 / 恢复键）----
# 为什么进门禁：这一半没有台架也没有板级判据 —— 它钉的是"三处源码之间的约定还成立"，
# 而这种约定在下一次改动时最容易悄悄断（`ps_hb_check.mjs` 自己带四条变异对照，红不红得起来它自己交代）。
HBOUT=$(node src/host/ps_hb_check.mjs --self 2>&1); HBRCC=$?
HBRED=$(printf '%s\n' "$HBOUT" | grep -c "^  FAIL")
say "PS 心跳约定 ps_hb" "rc=$HBRCC 红行=$HBRED" "--self 全绿(条数以脚本为准)" \
    $([ "$HBRCC" = 0 ] && [ "$HBRED" = 0 ] && echo 1 || echo 0)
printf '%s\n' "$HBOUT" | tail -6 | sed 's/^/        /'

# ---- 17：手写件的编码（`report/COMMANDS.md` 第 5 节曾经被 cp936 打坏一整段，位流/台架/门禁一个都没红）----
# 坏掉的不是硬件，是"演示时念给自己听的那份清单"，而那份要给评审看 ⇒ 判据要能自己跑。
# --self 那一路是它自己的反例（造三条坏行必须抓到三条），没有这一段就等于"绿给绿的人看"。
node src/host/doc_enc_check.mjs --self > /tmp/docenc_self.$$.txt 2>&1; DOCRC1=$?
# ⚠ 退出码**不能从管道里取**：`SUM=$(node … | head -1); RC=$?` 拿到的是 `head` 的 0，
#   于是判据红着这一项也绿（第 18 项今天就是这么被抓出来的——见下面那条双向验证）。
DOCOUT=$(node src/host/doc_enc_check.mjs 2>&1); DOCRC2=$?
DOCSUM=$(printf '%s\n' "$DOCOUT" | head -1)
DOCRED=$(printf '%s\n' "$DOCOUT" | tail -n +2 | grep -c .)
say "手写件编码 doc_enc" "$(printf '%s' "$DOCSUM" | cut -c1-24) 坏行=$DOCRED" "self 抓到 3/3 且全树干净" \
    $([ "$DOCRC1" = 0 ] && [ "$DOCRC2" = 0 ] && echo 1 || echo 0)
if [ "$DOCRC2" != 0 ]; then
    printf '%s\n' "$DOCOUT" | sed -n '2,9p' | sed 's/^/        /'
fi
[ "$DOCRC1" = 0 ] || { echo "        —— doc_enc 的 --self 反例不成立（判据抓不到造出来的坏行）："; sed 's/^/        /' /tmp/docenc_self.$$.txt; }
rm -f /tmp/docenc_self.$$.txt

# ---- 18：文档时效（README 把 build#23 念成"当前默认 bit"、还说 bilin 不在主线，整整五十版；
#      PERF_REPORT §3 同病。这类错不改任何行为，坏的是"念给评审听的那一句"⇒ 判据要自己跑。）----
# 三条：D1 不许把带编号的旧构建说成"当前/默认"；D2 点名的冻结目录必须在盘上；
# D3 首页念的"门禁全绿 = rNN"必须等于 build/*gates*.txt 里编号最大且 ALL PASS 的那一套
# ⇒ 下一次冻结成功时这一项会自己红，逼着回头改首页（今天不写下来，明天就会再忘一次）。
node src/host/doc_currency_check.mjs --self > /tmp/cur_self.$$.txt 2>&1; CURRC1=$?
CUROUT=$(node src/host/doc_currency_check.mjs 2>&1); CURRC2=$?
CURSUM=$(printf '%s\n' "$CUROUT" | head -1)
CURROWS=$(printf '%s\n' "$CUROUT" | grep -c ' D[123] ')
say "文档时效 doc_cur" "$(printf '%s' "$CURSUM" | cut -c1-20) 红行=$CURROWS" "self 变异 3+对照 2 且全树 0 条" \
    $([ "$CURRC1" = 0 ] && [ "$CURRC2" = 0 ] && echo 1 || echo 0)
if [ "$CURRC2" != 0 ]; then
    printf '%s\n' "$CUROUT" | grep ' D[123] ' | sed -n '1,8p' | sed 's/^/        /'
fi
[ "$CURRC1" = 0 ] || { echo "        —— doc_currency 的 --self 反例不成立（该红的没红）："; sed 's/^/        /' /tmp/cur_self.$$.txt; }
rm -f /tmp/cur_self.$$.txt

echo "端点总数 $eps；CDC 现在按 build/CDC_BASELINE.txt 的**配对集合**判，功耗仍要人比有没有变差。"
if [ "$pass" = 1 ]; then echo "GATES: ALL PASS"; exit 0; else echo "GATES: 有红项 —— 不采纳，保留上一版"; exit 1; fi

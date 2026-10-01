#!/bin/bash
# build/gates.sh —— 一条命令读回门禁清单，并和阈值比。
#   条数会随教训增长（2026-09-23 那会儿是"七项"；r70 起 **15 项** = 第 15 项顶层台架
#   `tb_v98` 的报告必须与当前顶层同一次跑，出处 #88/#92；16 = PS 心跳与停心跳的约定（#94）、
#   17 = 手写件的编码（COMMANDS §5 曾被 cp936 打坏一整段）、18 = 文档时效（README/PERF_REPORT
#   把 build#23 念成"当前默认"整整五十版）、**19 = 排练脚本必须等于讲稿抽出来的那一份**、
#   **20 = 交付文档的行号锚点（D5）**与 **21 = 首页与指标表的数字对账（D6）**（#219：这两把尺子
#   此前一直是我**手工**跑的，而门禁件上写的"N 项全判定"并不含它们 ⇒ 文档随 RTL 漂移时门禁不红）
#   ⇒ 这里**不再写死条数**，以本文件里 `say` 的调用次数为准。
#
#   bash build/gates.sh                 # 读 build/ 里当前这套报告（= 最近一次构建）
#   bash build/gates.sh build/frozen_r19_arb   # 读某一组成套冻结件
#
# ⚠ **不要把本脚本的输出直接重定向成它自己要读的那份 `build/rNN_gates.txt`**（2026-09-27 r74 那天我自己踩的）：
#   `bash build/gates.sh > build/r74_gates.txt` 会在**第一项判据跑之前**就把那个文件截断，
#   而第 18 项（`doc_currency_check`）恰恰要拿"盘上最新且 ALL PASS 的那一份 `rNN_gates.txt`"当基准
#   ⇒ 它读到的是半空的文件，于是判"首页念 r74、最新全绿的还是 r69"红两条，第 15 项跟着白跑。
#   正确姿势两步：`bash build/gates.sh > /tmp/kx/g.txt 2>&1` 跑完，全绿之后再 `cp` 到位（要留旧份就先留备份）。
#   这一类"自己把自己刚要读的凭据毁掉"的写法在本仓出现过三次（#69 的 rc 被管道吃、#88 的报告出处、这次），
#   共同点是**判据读的与被判的是同一个对象**——加判据时先问一句：它读的文件是谁写的、什么时候写。
#
# 数字全部来自 Vivado 报告本身，不重新跑构建；退出码：全绿 0，任何一项红 1。
# 阈值口径与 report/log/OVERNIGHT_LOG.md §1 的门禁表一致（**不要因为某项红了就改这里的阈值**）。
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
    # 身份行（2026-09-30，checker 审计 F2 的根因）：以前门禁件只打 mtime、从不打这三件产物的 md5，
    # 于是 `build/make_submission.sh` 想按"板上那一版"的身份挑一份门禁报告配对时**永远挑不到**
    # （它 `grep -q "$BIT12" *gates*.txt` 恒假 ⇒ 交付包自己在 MANIFEST 里写「这一版不作交付」，
    #  而导出器还是 exit 0）。mtime 只说明"同一天"，md5 才说明"同一套"。
    echo "身份：system.bit md5=$(md5sum "$bit" | cut -c1-12)"
    [ -f "$D/system.xsa" ] && echo "      system.xsa md5=$(md5sum "$D/system.xsa" | cut -c1-12)"
    [ -f "$D/ps_app.elf" ] && echo "      ps_app.elf md5=$(md5sum "$D/ps_app.elf" | cut -c1-12)"
    [ -f "$D/ps_app.elf" ] || echo "      ps_app.elf 不在 $D（这一版没重编应用 ⇒ 无身份可打）"
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

# #209 加的第二把尺子。只与手写的 CDC_BASELINE.txt（r23 年份）比，会放过"以前报过、后来消失、
# 现在又长回来"这一类：r98 的 `eth_rxc>clkout0_1` 就同时满足"基线里认识"与"上一版采纳的报告里没有"。
# 所以对照物再加一份——**上一版被采纳的 cdc.rpt**（冻结目录里那份），本版有而它没有的 Critical 配对判红。
CDCADOPT=${CDCADOPT:-build/evidence_r75/cdc.rpt}
if [ -f "$CDCADOPT" ]; then
    adopt=$(rows "$CDCADOPT" | awk '{print $1}' | sort -u)
    fresh=$(comm -13 <(printf '%s\n' "$adopt") <(printf '%s\n' "$cur" | awk '{print $1}' | sort -u))
    if [ -n "$fresh" ]; then
        cdc_ok=0
        echo "        比上一版采纳（$CDCADOPT）多出的 Critical 配对：$(printf '%s ' $fresh)  ⇒ 判红（#209）"
    else
        echo "        与上一版采纳的 Critical 配对集合一致（对照 $CDCADOPT）"
    fi
else
    echo "        FATAL 取不到采纳版 $CDCADOPT —— 这一项少了一把尺子，不敢判绿"
    cdc_ok=0
fi

# 自检：解析不出来的项一律当失败（"检查器自己也要有判据"，见学习文档 §十二）
for v in wns whs tnsfail whsfail eps bram bramp lut lutp reg dyn crit rerr cdcc; do
    eval "x=\$$v"
    case "$x" in ""|NA) echo "FATAL 解析不到 \$v —— 报告格式变了？不要拿空值当 0 判绿"; exit 2;; esac
done
[[ "$wns$whs$bramp$lutp" =~ ^[0-9.+\-]+$ ]] || { echo "FATAL 数字字段解析异常: $wns|$whs|$bramp|$lutp"; exit 2; }
pass=1
# 这一版之前缺的东西：`say` 只数红绿，而脚本里还有四类"这一项今天没法判"的 `n/a` 分支
# （历史冻结件不带同一次跑的顶层/RTL md5、读不到 CDC 分组行……）。它们**不判红是对的**，
# 但结尾那句 `GATES: ALL PASS` 会连着两条 n/a 一起念出去 —— 于是"两支主台架都没跑"的一版
# 也能拿到 ALL PASS，而 `freeze_evidence.sh` 只 grep 这一行。同一个坑本仓记过五次
# （判据静默不执行 / 检查器的作用范围会悄悄漂），这次把范围打在结论里。
NSAY=0
NNA=0
say() { # say <名字> <实测> <判据文本> <0/1>
    printf "  %-22s %-12s %-28s %s\n" "$1" "$2" "$3" "$([ "$4" = 1 ] && echo PASS || { echo FAIL; })"
    NSAY=$((NSAY+1))
    [ "$4" = 1 ] || pass=0
}
naa() { # 一条"今天未判"的说明：照旧不判红，但计入结尾的范围声明
    echo "  n/a  $*"
    NNA=$((NNA+1))
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
if [ -f "$M" ]; then say "methodology CRIT" "$crit" "== 0" $([ "$crit" -eq 0 ] && echo 1 || echo 0)
else naa "methodology CRIT —— $M 不在这套目录里 ⇒ 这一项没门禁（#164：过去空结果被当合法的 0 念成 PASS）"; fi
say "布线错误网线"      "$rerr" "== 0"            $([ "$rerr" -eq 0 ] && echo 1 || echo 0)
if [ -f "$C" ]; then say "cdc.rpt Critical 行" "$cdcc" "基线 $nbase 行，配对不新增、unsafe 不增长" "$cdc_ok"
else naa "cdc.rpt Critical 行 —— $C 不在这套目录里 ⇒ 这一项没门禁（#164 同族，空集合不是通过）"; fi
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
#     （见 report/log/OVERNIGHT_LOG.md §33 与 skill/ 那条"判据要有自己的测试"）。
#     r52 加宽到第三条**位宽**（`dbg_lat` 从 5 口变 6 口时想到的：#57 那类"高位被一根窄线吞掉"
#     名字对得上、仿真与综合都不报，只有把两头量出来才看得见）。反例两份 + 一份负对照，
#     凭据 `build/ports_check_width_ce.txt`。
#     历史冻结件里没有 ports_check.txt ⇒ 这一项对它们**跳过而不是判红**：
#     这一项是拿"当前源码树"跑的，历史包没有对应的树，红一个没有意义的红只会让人去关门禁。
if [ "$D" = "build" ]; then
    python build/check_ports.py --dup > build/ports_check.txt 2>&1; PCEXIT=$?
    PCTXT=$(tail -1 build/ports_check.txt)
    # 计数地板（#194 的后半）：这一项原来**只看退出码**，于是"什么都没查"也能绿。地板判据抽在
    # `build/ports_floor.sh`（反例 `build/ports_floor_ce.sh` 跑的就是那一份，不是我在这里另抄一遍）。
    FLMSG=$(bash build/ports_floor.sh "$PCTXT"); FLOK=$?
    say "顶层接线（端口名/悬空输入/位宽）" "$PCTXT｜$FLMSG" \
        "violations=0 且扫描面不塌（凭据 build/ports_check.txt，当场跑）" \
        $([ "$PCEXIT" = 0 ] && [ "$FLOK" = 0 ] && echo 1 || echo 0)
    grep -v "^CHECK PORTS\|^  skipped" build/ports_check.txt 2>/dev/null | sed 's/^/        /' | head -8
else
    PCF=$(pick ports_check.txt)
    if [ -f "$PCF" ]; then
        grep -q "violations=0" "$PCF" && say "顶层接线（端口名/悬空输入/位宽）" "$(cat "$PCF")" "violations=0" 1 \
            || say "顶层接线（端口名/悬空输入/位宽）" "$(cat "$PCF")" "violations=0" 0
    else
        naa "顶层接线 —— 该冻结件早于第 14 项，没有对应的 ports_check 凭据（不判红，见上面注释）"
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
[ -n "$GRP" ] || naa "读不到 From==To 分组行 ⇒ 这一项未验（不当 0、也不当通过）"
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
        eval "$(bash build/rtl_fingerprint.sh)"    # fpver/files/top/rtl —— 指纹定义只有一处
        TOPWANT=$top
        RTLWANT=$rtl
        TBWANT=$(bash build/rtl_fingerprint.sh sim/tb_v98_top_seam.v | cut -c1-12)
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
        # #166：这一项读的就是"判定形状 + FAIL 计数"，而这两件事都由 `sim/run_one.sh --verdict` 定义
        #       ⇒ 那把尺子自己的五条对照（含"别人的过期日志不许替本台架答复"）不过，本项的判定就不可信：
        #       症状是"红被念成没数"，而门禁会把整项念成 PASS。让尺子的健康度绑在它支撑的那一项上。
        if ! bash build/run_one_ce.sh > "/tmp/run_one_ce.gate.$$.txt" 2>&1; then
            OK=0; WHY="$WHY判定解析器自己的对照不过(#166，见 /tmp/run_one_ce.gate.*) ";
        fi
        # 指纹这把尺子自己也上对照（#202）：换行编码不变性、改内容必须动、扫描面、桥接表逐行复算。
        if ! bash build/rtl_fingerprint.sh --self > "/tmp/fp_self.gate.$$.txt" 2>&1; then
            OK=0; WHY="$WHY源码指纹尺子自己的对照不过(#202，见 /tmp/fp_self.gate.*) ";
        fi
        MATCH_LOG=""
        mcheck() { # $1 中文名 $2 kind $3 报告里的值 $4 当前值 $5 路径(可空)
            # ⚠ $5 必须写成本地默认值：门禁跑在 `set -u` 下，而 "$5" 处在这个函数唯一的
            #   命令替换里 ⇒ 未报错时只有那个**子 shell** 退出，本项照常把 m 当空串念成"过了"。
            #   这就是第 15 项的反例 E/F 当场抓到的形状（#203：判据没执行却报 PASS）。
            local m pw=${5:-}
            m=$(bash build/rtl_fingerprint.sh --match "$2" "$3" "$4" "$pw")
            MATCH_LOG="$MATCH_LOG ${m:-ERR}"
            # 只认 fresh/bridge 两种答案；空串/ERR/no 一律红 —— "尺子没答"不等于"答了且过了"
            if [ "$m" != "fresh" ] && [ "$m" != "bridge" ]; then
                OK=0; WHY="$WHY$1 不符(报告=$3 当前=$4 判定=${m:-空}：改过$1，这份报告不算当前树；桥接表里也没有 $3) "
            fi
        }
        mcheck "顶层" file "$TOPYES" "$TOPWANT" src/rtl/top/pl_video_top.v
        # 顶层之外的那一路也必须对得上：r72 改的是四个窗口级，`pl_video_top.v` 一个字节没动，
        # 只比顶层 md5 的话 r71 的旧报告能原样冒充今天的凭据（今天就差一点撞上）。
        mcheck "RTL" rtl "$RTLYES" "$RTLWANT"
        mcheck "台架" file "$TBYES" "$TBWANT" sim/tb_v98_top_seam.v
        [ "$NFAIL" = "0" ]         || { OK=0; WHY="$WHY报告里有 $NFAIL 行 FAIL "; }
        # 计数地板（#194 那条"第 14 项只看退出码，instances=0 也绿"的同族）：三枚指纹都**必须被判定过**。
        # 今天我自己写的 mcheck 少传一个参数，`set -u` 只让命令替换那个子 shell 退出，
        # RTL 那一枚就这么"没查"而本项照报 PASS —— 是反例 E/F 把它揪出来的，地板让它下次不必等反例。
        NJ=$(echo $MATCH_LOG | wc -w)
        [ "$NJ" = "3" ] || { OK=0; WHY="$WHY指纹判定只有 $NJ/3 枚（少一枚就是那一枚根本没执行，不许当过了） "; }
        [ "$DONE" = "1" ]          || { OK=0; WHY="$WHY没有 RESULT…PASS 汇总行（$([ "$RFIN" -gt 0 ] && echo "台架跑完了、是它自己判红的，先读 FAIL 那几行的数" || echo "台架没跑完或中途退出")） "; }
        say "顶层台架 tb_v98" "top=$TOPYES FAIL行=$NFAIL 指纹(norm1):$(echo $MATCH_LOG)" "同一次跑且无 FAIL" $OK
        [ -n "$WHY" ] && echo "        ——$WHY"
    else
        say "顶层台架 tb_v98" "缺 build/tb_v98_report.txt" "必须先跑 tb98_report.sh" 0
        echo "        —— 生成：bash sim/run_one.sh tb_v98_top_seam（从 #166 起：**退出码 3 = 台架判红**，1 = 编译失败，4 = 认不出判定）&& bash build/tb98_report.sh"
    fi
else
    naa "顶层台架 tb_v98 —— 历史冻结件不带与它同一次跑的顶层 md5，不判红（同第 14 项的口径）"
fi

# ---- 15b：#97 边缘条带那把尺子（窗口级的"值"与"陈旧行"，C2/C3/C4 三把位置尺子看不见它）----
# 为什么进门禁：这一族的红是**屏上一条带**，不是任何计数器；四个窗口级共用同一套旗标，
# 而下一次动窗口级的人只看得到 tb_v89/tb_v92 那两把"位置"尺子 —— 它们对边缘的内容不敏感。
# 判据与第 15 项同一形状：认 md5（整个 src/rtl 的合指纹 + 台架自己），正文不许有 FAIL 行，
# 必须有汇总行，而且**四条圈的覆盖地板**（n2..n5 ≥ 20）要在报告里看得见——
# 空集上的 PASS 正是这把尺子自己红过的形状（见 ISSUES #97 第一节）。
if [ "$D" = "build" ]; then
    if [ -n "${RIM_REPORT:-}" ]; then RIM=$RIM_REPORT; else RIM=$(ls -1 build/tb_edge_rim_r*.txt 2>/dev/null | sort -V | tail -1); fi
    if [ -n "$RIM" ]; then
        RTLWANT=$(bash build/rtl_fingerprint.sh | sed -n 's/^rtl=//p')
        TBWANT=$(bash build/rtl_fingerprint.sh sim/tb_edge_rim.v | cut -c1-12)
        RTLYES=$(sed -n 's/^rtl_md5=\([0-9a-f]*\).*/\1/p' "$RIM" | head -1)
        TBYES=$(sed -n 's/^tb_md5=\([0-9a-f]*\).*/\1/p' "$RIM" | head -1)
        NFAIL=$(grep -ac "^FAIL" "$RIM")
        DONE=$(grep -ac "^RESULT tb_edge_rim PASS$" "$RIM")
        FLOOR=$(grep -acE "^PASS R[2-5]" "$RIM")
        OK=1; WHY=""
        RIM_LOG=""
        rcheck() { # $1 中文名 $2 kind $3 报告值 $4 当前值 $5 路径(可空) —— 同 mcheck，$5 要有默认值
            local m pw=${5:-}
            m=$(bash build/rtl_fingerprint.sh --match "$2" "$3" "$4" "$pw")
            RIM_LOG="$RIM_LOG ${m:-ERR}"
            if [ "$m" != "fresh" ] && [ "$m" != "bridge" ]; then
                OK=0; WHY="${WHY}$1 不符(报告=$3 当前=$4 判定=${m:-空}：改过$1，这份 rim 报告不算当前树；桥接表里也没有 $3) "
            fi
        }
        rcheck "RTL" rtl "$RTLYES" "$RTLWANT"
        rcheck "台架" file "$TBYES" "$TBWANT" sim/tb_edge_rim.v
        [ "$NFAIL" = "0" ] || { OK=0; WHY="${WHY}报告里有 $NFAIL 行 FAIL "; }
        [ "$DONE" = "1" ] || { OK=0; WHY="${WHY}没有 RESULT tb_edge_rim PASS 汇总行 "; }
        [ "$FLOOR" = "4" ] || { OK=0; WHY="${WHY}四条圈只绿了 $FLOOR/4 条（少一条就是那一族的判据没跑或被地板挡下） "; }
        NJR=$(echo $RIM_LOG | wc -w)
        [ "$NJR" = "2" ] || { OK=0; WHY="${WHY}指纹判定只有 $NJR/2 枚（少一枚就是那一枚没执行） "; }
        say "边缘条带 tb_edge_rim" "$(basename "$RIM") rtl=$RTLYES FAIL行=$NFAIL 指纹(norm1):$(echo $RIM_LOG)" "同一次跑、无 FAIL、四条圈齐" $OK
        [ -n "$WHY" ] && echo "        ——$WHY"
    else
        say "边缘条带 tb_edge_rim" "缺 build/tb_edge_rim_rNN.txt" "必须先跑并留凭据" 0
        echo "        —— 生成：bash sim/run_one.sh tb_edge_rim && ROUND=rNN bash build/rim_report.sh"
        echo "           ⚠ #179：`ROUND` **必须给** —— 那个脚本自带默认 r90，不给就把今天的数写成一份名字叫 r90 的假凭据，"
        echo "              而本项按 sort -V 取最新那份，于是读到的是上一轮的件（红在出身，不在设计）。"
    fi
else
    naa "边缘条带 tb_edge_rim —— 历史冻结件不带与它同一次跑的 RTL 合指纹，不判红（同第 15 项的口径）"
fi

# ---- 16：#94 固件那一半的约定（心跳节拍 / 超时余量 / 收心跳的调用点 / 恢复键）----
# 为什么进门禁：这一半没有台架也没有板级判据 —— 它钉的是"三处源码之间的约定还成立"，
# 而这种约定在下一次改动时最容易悄悄断（`ps_hb_check.mjs` 自己带四条变异对照，红不红得起来它自己交代）。
HBOUT=$(node src/host/ps_hb_check.mjs --self 2>&1); HBRCC=$?
HBRED=$(printf '%s\n' "$HBOUT" | grep -c "^  FAIL")
say "PS 心跳约定 ps_hb" "rc=$HBRCC 红行=$HBRED" "--self 全绿(条数以脚本为准)" \
    $([ "$HBRCC" = 0 ] && [ "$HBRED" = 0 ] && echo 1 || echo 0)
printf '%s\n' "$HBOUT" | tail -6 | sed 's/^/        /'

# ---- 17：手写件的编码（`docs/COMMANDS.md` 第 5 节曾经被 cp936 打坏一整段，位流/台架/门禁一个都没红）----
# 坏掉的不是硬件，是"演示时念给自己听的那份清单"，而那份要给评审看 ⇒ 判据要能自己跑。
# --self 那一路是它自己的反例（造三条坏行必须抓到三条），没有这一段就等于"绿给绿的人看"。
node src/host/doc_enc_check.mjs --self > /tmp/docenc_self.$$.txt 2>&1; DOCRC1=$?
# ⚠ 退出码**不能从管道里取**：`SUM=$(node … | head -1); RC=$?` 拿到的是 `head` 的 0，
#   于是判据红着这一项也绿（第 18 项今天就是这么被抓出来的——见下面那条双向验证）。
DOCOUT=$(node src/host/doc_enc_check.mjs 2>&1); DOCRC2=$?
# ⚠ `cut -c` 是**按字节**切的，中文标题被从中间切断就会在门禁件里留下半个 UTF-8 序列——
#   那份 `rNN_gates.txt` 从此被 grep 当二进制文件（本轮就撞上一次：`grep -a` 才读得出来），
#   而交付包里凡是"看起来像二进制"的凭据都没法用文本工具复核。切完再让 iconv 把尾巴那截废字节丢掉。
DOCSUM=$(printf '%s\n' "$DOCOUT" | head -1 | cut -c1-24 | iconv -f UTF-8 -t UTF-8//IGNORE)
DOCRED=$(printf '%s\n' "$DOCOUT" | tail -n +2 | grep -c .)
say "手写件编码 doc_enc" "$DOCSUM 坏行=$DOCRED" "self 抓到 3/3 且全树干净" \
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
CURSUM=$(printf '%s\n' "$CUROUT" | head -1 | cut -c1-20 | iconv -f UTF-8 -t UTF-8//IGNORE)
CURROWS=$(printf '%s\n' "$CUROUT" | grep -cE ' D[123]b? ')
# D1b 的空转地板：这一层判的是"板态身份句念的轮号 == 这块 bit 的门禁身份行"。
# 交付文档里**至少**要有中英各一句这样的身份句（README 首页那两行），抓到 0 句就说明
# 要么句子被改成了别的写法、要么形状漂了——两种都是尺子在空转（#194/#219 同族）。
CURCLAIMS=$(printf '%s\n' "$CUROUT" | sed -n 's/.*抓到 \([0-9][0-9]*\) 句.*/\1/p' | head -1)
say "文档时效 doc_cur" "$CURSUM 红行=$CURROWS 身份句=${CURCLAIMS:-空}" \
    "self 变异 5（含 D1b 身份句 2）+ 对照 4 全过、全树 0 条、身份句抓到 >= 2" \
    $([ "$CURRC1" = 0 ] && [ "$CURRC2" = 0 ] && [ "${CURCLAIMS:-0}" -ge 2 ] && echo 1 || echo 0)
if [ "$CURRC2" != 0 ]; then
    printf '%s\n' "$CUROUT" | grep -E ' D[123]b? ' | sed -n '1,8p' | sed 's/^/        /'
fi
[ "${CURCLAIMS:-0}" -ge 2 ] || echo "        —— D1b 只抓到 ${CURCLAIMS:-0} 句板态身份句（地板 2）：这一层正在空转，去 README 首页看那两行还在不在。"
[ "$CURRC1" = 0 ] || { echo "        —— doc_currency 的 --self 反例不成立（该红的没红）："; sed 's/^/        /' /tmp/cur_self.$$.txt; }
rm -f /tmp/cur_self.$$.txt

# ---- 19：演示排练脚本必须等于讲稿抽出来的那一份（2026-09-27 加，起因是今晚自己差点造出来）----
# `board/demo_rehearsal.txt` 是**照着敲进板子**的那一份，而它是从 `report/DEMO_SCRIPT.md` 的代码块
# 抽出来的（`src/host/demo_cmds.mjs --emit`）。讲稿改了而这份没重抽 ⇒ 排练与演示用的是两套东西，
# 症状恰好是 #67 那一族（"清单里有、板上没有"）：台上敲一条不存在的写法，或者少演一条改过的。
# 今晚改讲稿次序（第 9 幕拔卡）时我是**手工**比了一遍才敢说"49/49 那条仍然成立" ——
# 手工比一次的事后必然有一次不比，所以把它变成一项。
# 反向对照（证明这条比较不是恒真）：拿抽出来的那份**去掉最后一行**去比，必须判成不同。
node src/host/demo_cmds.mjs --emit /tmp/rehearsal_fresh.txt > /tmp/emit_note.$$.txt 2>&1; EMT1=$?
if [ "$EMT1" = 0 ]; then
    if diff -q <(sed 's/\r$//' board/demo_rehearsal.txt) <(sed 's/\r$//' /tmp/rehearsal_fresh.txt) >/dev/null; then
        EMSAME=1; EMROWS=0
    else
        EMSAME=0; EMROWS=$(diff <(sed 's/\r$//' board/demo_rehearsal.txt) <(sed 's/\r$//' /tmp/rehearsal_fresh.txt) | grep -c '^[<>]')
    fi
    # 变异对照：少一行必须"不相同"（否则这条比较是摆设）
    diff -q <(sed 's/\r$//' /tmp/rehearsal_fresh.txt) <(sed '$d' /tmp/rehearsal_fresh.txt) >/dev/null \
        && EMMUT=0 || EMMUT=1
else
    EMSAME=0; EMROWS="?"; EMMUT=0
fi
say "排练脚本=讲稿抽取 rehearsal" "差异行=$EMROWS 变异对照=$([ "$EMMUT" = 1 ] && echo 能红 || echo 恒真)" \
    "改讲稿不重抽 ⇒ 这一项红；少一行必须判成不同（对照）" \
    $([ "$EMSAME" = 1 ] && [ "$EMMUT" = 1 ] && echo 1 || echo 0)
[ "$EMSAME" = 1 ] || { echo "        —— 盘上那份是旧的：跑 \`node src/host/demo_cmds.mjs --emit\` 重抽再提交。"; }
rm -f /tmp/rehearsal_fresh.txt /tmp/emit_note.$$.txt

# ---- 20：交付文档的行号引用必须落在代码锚点上（D5 / D5b / D5d；2026-10-02 加，起因 ISSUES #122 → #208 → #219）----
# 为什么现在才进门禁：这把尺子 r87 起就在跑，但**一直是我手工跑的**，而 #219 查出门禁件上那句
# "20 项全判定"里并不含它，也不含 D6 ⇒ "文档同步"的机器部分有个洞：改了 RTL 的行号、没改文档，
# 门禁不红，要等下一次有人想起来手动跑一下。洞补上之后，首页与 KNOWN_ISSUES 里那句"不含 D5/D6"要跟着改口。
# ⚠ 计数地板（锚点命中 >= 300）不是装饰：一把**扫不到任何引用**的尺子也报"硬错 0 条"，
#   那是空转不是绿（同第 14 项 #194 的教训，规矩是"判据不许靠没人反对变绿"）。
node src/host/line_cite_check.mjs --self > /tmp/d5_self.$$.txt 2>&1; D5RC1=$?
D5OUT=$(node src/host/line_cite_check.mjs 2>&1); D5RC2=$?
D5TOK=$(printf '%s\n' "$D5OUT" | grep -c '^D5: CLEAN')
D5HIT=$(printf '%s\n' "$D5OUT" | sed -n '1s/.*命中 \([0-9][0-9]*\) 条.*/\1/p')
D5CAND=$(printf '%s\n' "$D5OUT" | sed -n '1s/.*候选 \([0-9][0-9]*\) 条.*/\1/p')
say "文档行号锚点 doc_cite" "命中=${D5HIT:-空} 候选=${D5CAND:-空}" "self 13 条对照全过、硬错 0、命中 >= 300" \
    $([ "$D5RC1" = 0 ] && [ "$D5RC2" = 0 ] && [ "$D5TOK" = 1 ] && [ "${D5HIT:-0}" -ge 300 ] && echo 1 || echo 0)
if [ "$D5RC2" != 0 ]; then
    printf '%s\n' "$D5OUT" | sed -n '/硬错（必定是坏引用）/,$p' | grep '^  ' | sed -n '1,8p' | sed 's/^/        /'
fi
[ "$D5RC1" = 0 ] || { echo "        —— line_cite 的 --self 反例不成立（ planted 的坏引用没红，或好引用被误报）："; sed 's/^/        /' /tmp/d5_self.$$.txt | tail -8; }
rm -f /tmp/d5_self.$$.txt

# ---- 21：首页与指标表里"点名报告"的每个数，必须等于那份报告现在说的（D6；同上起因 #120/#213/#159）----
# 这一项进门禁的当口就抓到了真错：首页功耗行还写着 2.212 W / 52.6 °C、占用行写着 14333 / 8079，
# 而 r104 的 `build/power.rpt` 与 `build/utilization.rpt` 是 2.211 / 52.5 与 14334 / 8127
# —— r103→r104 那一轮只同步了 `data/metrics.csv`，首页四格漏了（**改前红不是我造的**）。
node src/host/metric_recheck.mjs --self > /tmp/d6_self.$$.txt 2>&1; D6RC1=$?
D6OUT=$(node src/host/metric_recheck.mjs 2>&1); D6RC2=$?
D6RED=$(printf '%s\n' "$D6OUT" | grep -c '^RED')
D6CNT=$(printf '%s\n' "$D6OUT" | sed -n 's/.*判 \([0-9][0-9]*\) 个数.*/\1/p' | tail -1)
D6FRONT=$(printf '%s\n' "$D6OUT" | grep -c '^OK  row=README')
say "数字对账 metric" "判=${D6CNT:-空} 首页=${D6FRONT:-空} 红=$D6RED" "self（csv fixture + 首页假数）全过、红 0、判 >= 30 个数、首页 >= 20 个" \
    $([ "$D6RC1" = 0 ] && [ "$D6RC2" = 0 ] && [ "$D6RED" = 0 ] && [ "${D6CNT:-0}" -ge 30 ] && [ "${D6FRONT:-0}" -ge 20 ] && echo 1 || echo 0)
if [ "$D6RC2" != 0 ] || [ "$D6RED" != 0 ]; then
    printf '%s\n' "$D6OUT" | grep '^RED' | sed -n '1,8p' | sed 's/^/        /'
fi
[ "$D6RC1" = 0 ] || { echo "        —— metric_recheck 的 --self 反例不成立（该红的没红，或首页那层在空转）："; sed 's/^/        /' /tmp/d6_self.$$.txt | tail -6; }
rm -f /tmp/d6_self.$$.txt

echo "端点总数 $eps；CDC 现在按 build/CDC_BASELINE.txt 的**配对集合**判，功耗仍要人比有没有变差。"
# 结尾必须把**范围**一起念出来：判定 $NSAY 项、未判 $NNA 项。
# `GATES: ALL PASS` 这一行只有在"没有一项是因为缺席而没判"时才允许出现 ——
# `freeze_evidence.sh` 就 grep 这个串，所以有 n/a 时换成 `GATES: PARTIAL`，它自然拒绝冻结这一版。
if [ "$pass" = 0 ]; then
    echo "GATES: 有红项（判定 $NSAY 项）—— 不采纳，保留上一版"; exit 1
elif [ "$NNA" != 0 ]; then
    echo "GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行），这一版不作\"过门禁\""; exit 1
else
    echo "GATES: ALL PASS（$NSAY 项全部判定）"; exit 0
fi

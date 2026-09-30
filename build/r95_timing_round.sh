#!/bin/bash
# build/r95_timing_round.sh —— r95：把"时序还能不能更好"这个问题问到**不能再优化**为止。
#
# 与前几轮的分工：
#   r91 量过实现策略（两滚，hold 没动 ⇒  measured and declined）；
#   r90 量过"拿 BRAM 换 setup"（否决）与 Pblock（#146，不采纳）；
#   §二.1 欠的那一侧是**物理**：最差那两条路径 route 占 60~67 %，高扇出网络 fo=96/17。
#   ⇒ 这一轮的对象就一条：**布线后物理综合（post-route phys_opt，IMPL_PRPO=1，AggressiveExplore）**，
#     它是构建脚本里已经装好、但历史上从没被正式滚过的那一档（默认关）。
#   再补一滚 `Performance_ExploreWithHierarchy`（r91 只滚过 Explore / ExtraTimingOpt，没滚过这一档），
#   这样"策略"与"物理"两档各留一个实测数，而不是靠一次运气。
#
# ⚠ 规矩 35：一次构建的绝对 delta **既不算收益也不算损失**（同一条路实测摆过 0.4 ns）。
#   所以门槛是"能不能**采纳**"，不是"有没有提升"；两滚都不达门槛就写"量过并否决"，
#   并把 §二.1 那句"还欠物理那一侧"改成"物理那一侧已量过"。
#   ⚠ phys_opt **会动物理结果、可能复制高扇出驱动** ⇒ 网表与资源数会变，所以采纳的前提是
#     整屏台架 + 板级复验都重跑，不是只看报告。
#
# 跑法：VP_VIVADO_BIN=<Vivado>/bin bash build/r95_timing_round.sh
# 产物只落 build/isolated_r95_*，build/ 里那套被文档点名的件一个不碰（走 build/roll_isolated.sh）。
set -u
cd "$(dirname "$0")/.." || exit 1
V=${VP_VIVADO_BIN:-}
[ -x "$V/xvlog" ] || { echo "REFUSE: 没设 VP_VIVADO_BIN 或里面没有 xvlog（当前 [$V]）"; exit 2; }
pgrep -fa xsim.exe >/dev/null 2>&1 && { echo "REFUSE: 有 xsim 在跑，先让 r94 的台架链结束（CPU 抢用会让两边都判不准）"; exit 3; }

SUM=build/r95_timing_summary.txt
LOG=build/r95_timing_round.log
BASE_WNS=0.553; BASE_WHS=0.049          # r94 板上这一版：build/timing_summary.rpt（12:53 那次构建）

# 采纳门槛：**跑之前**写进 SUMMARY，不是看完数字再挑（r91 就是这么立的）
{ echo "# r95 采纳门槛（写在任何一滚开跑之前，$(date '+%F %H:%M:%S' 2>/dev/null)）"
  echo "#   全设计 WNS >= +0.65 ns   （比 r94 的 +0.553 好出一个**明显大于 0.4 ns 摆幅**的量）"
  echo "#   全设计 WHS >= +0.15 ns   （历史六版在 +0.012..+0.060 之间跳，带内不算数）"
  echo "#   失败 setup/hold 端点 = 0；且 BRAM 不得 > 95 tile（#4 那档门禁上限）"
  echo "#   三条任何一条不满足 => 不采纳，写'量过并否决'"
  echo ""
} >> "$SUM"

say() { echo "[r95 $(date '+%F %H:%M:%S' 2>/dev/null)] $*" | tee -a "$LOG"; }

# 从一滚的 timing_summary.rpt 取设计行与 eth_rxc 行。**行正则原样抄 r91 那份被验证过的尺子**
# （自己新写的第一版在 r94 的报告上读出了 `-0.490 u_pl/u_bilin/u_fb/lo_reg_0_63` —— 那是路径表里
#  的一行，不是摘要行：正控制一跑就把它抓住了）。输出：`WNS WHS 失败setup 失败hold 总端点 eth_wNS eth_wHS`
read_timing() {
    local f=$1 row eth
    [ -f "$f" ] || { echo ""; return; }
    row=$(awk '/Design Timing Summary/{want=1}
               want && /^ *[-+]?[0-9]+\.[0-9]+ +[+-]?[0-9]*\.?[0-9]+ +[0-9]+ +[0-9]+ +[-+]?[0-9]+\.[0-9]+/{print; exit}' "$f")
    [ -z "$row" ] && { echo ""; return; }
    # 只认 Intra Clock Table 那一行的形状（Clock Summary 里也有一行 `eth_rxc {0.000 8.000} …`，先撞上就会误读）
    eth=$(awk '/^eth_rxc +[-+]?[0-9]+\.[0-9]+ +[-+]?[0-9.]+ +[0-9]+ +[0-9]+ +[-+]?[0-9]+\.[0-9]+/{print; exit}' "$f")
    # 设计行字段：1=WNS 2=TNS 3=TNS失败端点 4=TNS总端点 5=WHS 6=THS 7=THS失败端点 8=THS总端点
    awk -v r="$row" -v e="$eth" 'BEGIN{
        split(r,a," "); split(e,b," ");
        ew=(b[1]=="eth_rxc"?b[2]:"?"); eh=(b[1]=="eth_rxc"?b[6]:"?");
        printf("%s %s %s %s %s %s %s", a[1], a[5], a[3], a[7], a[4], ew, eh);
    }'
}
read_bram() {   # utilization.rpt 里 `| Block RAM Tile | 95 | ...` ⇒ 按 | 切之后数**第 3 段**（第一版数了 $2 读出 "BlockRAMTile"）
    local f=$1
    [ -f "$f" ] || { echo ""; return; }
    awk -F'|' '/Block RAM Tile/{gsub(/[ ,]/,"",$3); print $3; exit}' "$f" 2>/dev/null
}

roll() {   # $1=目录名 $2=额外环境（逗号分隔 KEY=VAL）
    local name=$1 envs=$2 out
    out=build/isolated_$name
    say "开滚 $name -> $out（$envs）"
    # 把 KEY=VAL 串变成前缀赋值
    ( env ${envs//,/ } OUT="$out" bash build/roll_isolated.sh ) >> "$LOG" 2>&1
    local t; t=$(read_timing "$out/timing_summary.rpt")
    if [ -z "$t" ]; then
        say "$name：**读不到 timing_summary 的设计行** —— 不判采纳，先看 $out/build_console.txt 有没有 SYSTEM BUILD DONE"
        echo "$name READ_FAILED" >> "$SUM"
        return 1
    fi
    set -- $t                       # $1=WNS $2=WHS $3=失败setup $4=失败hold $5=总端点 $6/7=eth_rxc WNS/WHS
    local wns=$1 whs=$2 fep=$3 fep_h=$4 tep=$5
    local eth; eth="$6 / $7"
    local bram; bram=$(read_bram "$out/utilization.rpt")
    say "$name：WNS $wns / WHS $whs / 失败 setup $fep、hold $fep_h（共 $tep）/ eth_rxc $eth / BRAM $bram tile"
    # 采纳判定：门槛三项 + BRAM 上限。比较用 awk（bash 的 [ ] 不认小数）
    local ok
    ok=$(awk -v w="$wns" -v h="$whs" -v f="$fep" -v fh="$fep_h" -v b="$bram" 'BEGIN{
        if (w>=0.65 && h>=0.15 && f+0==0 && fh+0==0 && b+0<=95) print "ADOPT"; else print "DECLINE"}')
    echo "$name WNS=$wns WHS=$whs fep=$fep fep_hold=$fep_h endpoints=$tep eth_rxc=$eth BRAM=$bram VERDICT=$ok" >> "$SUM"
    say "$name 判定：$ok（门槛见本文件顶部）"
    [ "$ok" = "ADOPT" ]
}

say "基线（r94，正式件 build/system.bit md5=a1465f29c9e4）：WNS $BASE_WNS / WHS $BASE_WHS / 0 / 50883"
echo "baseline_r94 WNS=$BASE_WNS WHS=$BASE_WHS endpoints=50883 bit=a1465f29c9e4" >> "$SUM"

roll r95_postroute_physopt IMPL_PRPO=1
A=$?
roll r95_explor_withhier IMPL_STRATEGY=Performance_ExploreWithHierarchy
B=$?
say "两滚结束：phys_opt=$([ $A -eq 0 ] && echo ADOPT || echo DECLINE)，ExploreWithHierarchy=$([ $B -eq 0 ] && echo ADOPT || echo DECLINE)"
say "DONE —— 谁被采纳由人读 $SUM 那两行来定；不采纳也要把这一节落进 docs/OPTIMIZATION_LOG.md"

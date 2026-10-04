#!/bin/bash
# 用途：r91：最后一轮时序，先动**实现策略**这一档，不动 RTL
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=REFUSE
# build/r91_strategy_round.sh —— r91：最后一轮时序，先动**实现策略**这一档，不动 RTL。
#
# 为什么从这一档开始：`src/constraints/*.xdc` 里没有任何 `set_input_delay`（已 grep 证实），
# 所以 RGMII 收口"采样点落在眼图哪里"从来不在时序报告的管辖范围内 —— 把 5 个 IDDR 从 BUFIO
# 改到 BUFG（ISSUES #57 那条结构修法）在报告里只会看到内部路径变好，看不到外部采样窗变坏，
# 只有真板子知道。夜里没有人看屏幕，所以先做**唯一还能白拿的那一档**：
# 板上那一份用的是 `Vivado Implementation Defaults`（见 build/r8*_build_console.txt 里
# `BUILD_STRATEGY` 那行），历史上扫过策略但没被采纳，而且那之后的 RTL 已经变了好几版。
#
# 判据（同尺子：RTL 与 XDC 一个字节不改，`set_clock_uncertainty -hold 0.800 eth_rxc` 不变）：
#   基线 = 板上那一版：全设计 WNS +0.516 / WHS +0.051、失败端点 0 / 50885；
#   eth_rxc 0.516/0.051、clkout0_1 1.177/0.059、clk_fpga_0 1.643/0.051。
#   采纳门槛写在纸上，不是临场挑的：
#     WHS(全设计) >= +0.15 ns（历史六版 WHS 在 +0.012..+0.054 之间跳，0.04 的带内不算数），
#     且 WNS(全设计) >= +0.40 ns（不比基线差出一个噪声带），
#     且失败 setup/hold 端点 = 0。
#   三条里任何一条不满足就不采纳（规矩 35：一次构建的绝对 delta 不承诺结果，所以要两滚同向才算）。
#
# 跑法：VP_VIVADO_BIN=<Vivado>/bin bash build/r91_strategy_round.sh
#       产物只落 build/isolated_r91_*，build/ 里那套被文档点名的件一个不碰。
set -u
cd "$(dirname "$0")/.." || exit 1
[ -n "${VP_VIVADO_BIN:-}" ] || { echo "REFUSE: 没设 VP_VIVADO_BIN"; exit 2; }
[ -x "$VP_VIVADO_BIN/xvlog" ] || { echo "REFUSE: VP_VIVADO_BIN 里没有 xvlog：$VP_VIVADO_BIN"; exit 2; }

SUM=build/r91_strategy_summary.txt
LOG=build/r91_strategy_round.log
STRATS=${STRATS:-Performance_Explore Performance_ExtraTimingOpt}

say() { echo "[r91 $(date '+%F %H:%M:%S')] $*" | tee -a "$LOG"; }

# 从一跑的 timing_summary.rpt 里取"Design Timing Summary 那一行"和 eth_rxc 那一行。
# 取不到就返回空串，让调用方判红 —— 不要拿 0 当"读到了 0"。
# 字段号是数出来的（表头 WNS TNS FEP TEP WHS THS FEP2 TEP2 …），改报告格式就要重来：
#   1=设计 WNS 2=TNS 3=TNS 失败端点 4=TNS 总端点 5=设计 WHS 8=THS 总端点
read_timing() {
    local f=$1 row eth
    [ -f "$f" ] || { echo ""; return; }
    row=$(awk '/Design Timing Summary/{want=1}
               want && /^ *[-+]?[0-9]+\.[0-9]+ +[+-]?[0-9]*\.?[0-9]+ +[0-9]+ +[0-9]+ +[-+]?[0-9]+\.[0-9]+/{print; exit}' "$f")
    [ -z "$row" ] && { echo ""; return; }
    # 只认 Intra Clock Table 那一行的形状（名字后紧跟 5 个数）：
    # Clock Summary 里也有一行 `eth_rxc {0.000 8.000} …`，先撞上它就会把 "{0.000" 当 WNS。
    eth=$(awk '/^eth_rxc +[-+]?[0-9]+\.[0-9]+ +[-+]?[0-9.]+ +[0-9]+ +[0-9]+ +[-+]?[0-9]+\.[0-9]+/{print; exit}' "$f")
    # eth_rxc 行字段：1=名字 2=WNS 3=TNS 4=TNS失败 5=TNS总 6=WHS
    awk -v r="$row" -v e="$eth" 'BEGIN{
        split(r,a," "); split(e,b," ");
        printf("design WNS=%s WHS=%s fail_ep=%s total_ep=%s | eth_rxc WNS=%s WHS=%s",
               a[1], a[5], a[3], a[4], (b[1]=="eth_rxc"?b[2]:"?"), (b[1]=="eth_rxc"?b[6]:"?"));
    }'
}

echo "# r91 实现策略轮 —— $(date '+%F %H:%M') —— 同 RTL 同 XDC，只换策略" > "$SUM"
echo "# 门槛：WHS>=+0.15 且 WNS>=+0.40 且失败端点=0；两滚同向才算" >> "$SUM"
echo "# 基线（板上那一版，IMPL_STRATEGY=Vivado Implementation Defaults）：design WNS=+0.516 WHS=+0.051 fail_ep=0 total_ep=50885 | eth_rxc WNS=+0.516 WHS=+0.051" >> "$SUM"

for s in $STRATS; do
    ISO=build/isolated_r91_$(echo "$s" | tr 'A-Z' 'a-z' | sed 's/performance_//')
    say "滚一轮：strategy=$s -> $ISO"
    rm -rf "$ISO"
    OUT="$ISO" IMPL_STRATEGY="$s" bash build/roll_isolated.sh >> "$LOG" 2>&1
    rc=$?
    grep -qa "SYSTEM BUILD DONE" "$ISO/build_console.txt" 2>/dev/null \
        || { say "NOT PROVEN：$ISO 控制台里没有 SYSTEM BUILD DONE（rc=$rc），这一档没有数"; echo "$s NOT_DONE" >> "$SUM"; continue; }
    line=$(read_timing "$ISO/timing_summary.rpt")
    [ -z "$line" ] && { say "读不到 timing_summary.rpt 的那一行，这一档不算"; echo "$s NO_TIMING_READ" >> "$SUM"; continue; }
    echo "$s  $line" >> "$SUM"
    say "$s  $line"
done

say "两滚结束，汇总在 $SUM"
echo "R91 STRATEGY ROUND DONE" >> "$LOG"

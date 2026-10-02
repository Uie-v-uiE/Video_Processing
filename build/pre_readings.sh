#!/usr/bin/env bash
# build/pre_readings.sh —— 构建**之前**把"改前读数"问回来的那一步，做成一条命令（原来是我手工跑两次）。
#
# 为什么要脚本化（2026-10-03，用户要求"别每次花几小时仿真"的直接后果）：
#   收益的口径是"同一条端点对/同一个时钟自己动没动"（r107 定下、rule 35 兜着），
#   而 `vivado_system/.../system_top_routed.dcp` **一次构建就被覆盖**。
#   r108 那一轮我差点因为忘了在覆盖前问回来而只能拿全局 WNS 说事（见记忆与 ISSUES #230 的"改前读数"那笔）。
#   所以：每轮起飞之前先跑这一支，读数落成被跟踪的件；构建之后再跑一次同样的命令做对照。
#
# 用法：
#   bash build/pre_readings.sh r110_before        # 只读当前 DCP，落 build/evidence/r110_before.txt
#   CONE=1 bash build/pre_readings.sh r110_after  # 额外问一把指定的锥（需 export VP_FROM / VP_TO）
# 每条判据一行；退出码 0=三份时钟都问到了、2=前置坏了（没有 DCP / 没有 Vivado / 标签没给）、
# 3=有一腿一条路径都没打到（"空读数"不许当读数用 —— rule 46 的形状）。
set -u
cd "$(dirname "$0")/.."
LABEL=${1:?用法: bash build/pre_readings.sh <标签>，例如 r110_before}
V=${VP_VIVADO_BIN:-}
[ -f "$V/xvlog" ] || { echo "PR-REFUSE: 先设 VP_VIVADO_BIN=<Vivado>/bin（当前 '$V'）"; exit 2; }
export VP_VIVADO_BIN="$V"
DCP=vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp
[ -f "$DCP" ] || { echo "PR-REFUSE: 没有 $DCP（这一轮还没构建过？）"; exit 2; }

OUT=build/evidence/${LABEL}.txt
mkdir -p build/evidence
{
  echo "# 改前/改后读数 $LABEL  生成 $(date '+%F %H:%M:%S')"
  echo "# DCP：$DCP  mtime=$(date -r "$DCP" '+%F %H:%M:%S')"
  echo "# 位流身份：$( [ -f build/system.bit ] && md5sum build/system.bit | cut -c1-12 || echo '(build/system.bit 不在，用报告时间戳当身份)' )"
  echo "# 口径：判的是**同一个时钟 / 同一条锥**自己动没动；全局 WNS 的绝对差不算收益也不算损失（rule 35）。"
} > "$OUT"

fail=0
for clk in eth_rxc clk_fpga_0 clkout0_1; do
    # 台架名里的 .rpt 会被下一腿覆盖 ⇒ 每腿各留一份控制台，读数以摘要行进 $OUT
    VP_CLK=$clk VP_LABEL=${LABEL}_$clk VP_N=4 \
        "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_clk_worst.tcl \
        > "build/${LABEL}_${clk}_probe_console.txt" 2>&1
    rc=$?
    echo "----- 时钟 $clk（rc=$rc）-----" >> "$OUT"
    grep -aE "CLOCK period|Slack \(|Source:|Destination:|Data Path Delay|Logic Levels|PATHS printed|REFUSE" \
        "build/${LABEL}_${clk}_probe_console.txt" | grep -av "^#" >> "$OUT"
    n=$(grep -ac "PATHS printed: [1-9]" "build/${LABEL}_${clk}_probe_console.txt")
    echo "PROBE clock=$clk 打到路径的地板检查=$([ "$n" = 1 ] && echo OK || echo EMPTY) rc=$rc" | tee -a "$OUT"
    [ "$n" = 1 ] || fail=1
done

if [ "${CONE:-0}" = 1 ]; then
    : "${VP_FROM:?CONE=1 需要 export VP_FROM（不带花括号，见 probe_cone_slack.tcl 文件头）}"
    : "${VP_TO:?CONE=1 需要 export VP_TO}"
    "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_cone_slack.tcl \
        > "build/${LABEL}_cone_console.txt" 2>&1
    rc=$?
    echo "----- 锥 $VP_FROM → $VP_TO（rc=$rc）-----" >> "$OUT"
    grep -aE "LABEL|SETS|Slack \(|Source:|Destination:|Data Path Delay|Logic Levels|PATHS printed|REFUSE" \
        "build/${LABEL}_cone_console.txt" | grep -av "^#" >> "$OUT"
    n=$(grep -ac "PATHS printed: [1-9]" "build/${LABEL}_cone_console.txt")
    echo "PROBE cone 打到路径的地板检查=$([ "$n" = 1 ] && echo OK || echo EMPTY) rc=$rc" | tee -a "$OUT"
    [ "$n" = 1 ] || fail=1
fi

echo "PROBE-SUMMARY label=$LABEL 落件=$OUT fail=$fail" | tee -a "$OUT"
[ "$fail" = 0 ] || { echo "PROBE 结论：至少有一腿是**空读数** —— 这份件不能当改前/改后凭据用（先看 REFUSE/SETS 那两行）"; exit 3; }
echo "PROBE 结论：三份时钟（与可选的锥）都打到了路径，可以起飞构建了；构建后用同一个脚本换标签再跑一次做对照"
exit 0

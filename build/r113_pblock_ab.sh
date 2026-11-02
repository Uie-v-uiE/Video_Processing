#!/usr/bin/env bash
# 用途：r113 物理单变量 A/B（#253/#252 的 ②）：同一份 opt.dcp，唯一变量 = 有没有那块 Pblock
# 输入：命令行参数
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 2=非 0 分支（该文件 exit 2 那一行）
# build/r113_pblock_ab.sh —— r113 物理单变量 A/B（#253/#252 的 ②）：同一份 opt.dcp，唯一变量 = 有没有那块 Pblock。
#
#   bash build/r113_pblock_ab.sh          # 两滚约 25 分钟；产物只落临时目录，盘上被跟踪件一个字节都不碰
#
# 为什么不消 RTL 而消布局：这一族三次构建读 2.006 / >1.174 / 0.445 ns，级数一直 4，route 一直 81~84 %，
#   而 r110→r112 之间它的 RTL 没动（凭据 build/r112_reasm_probe.txt + git show --stat 6730dd9）⇒ 逻辑侧没有可切的了。
# 纪律（#223）：单变量。两滚都用裸 place_design/route_design、都跳过 phys_opt（#94：零违反设计上它结构性空转）。
# 规矩 35：念的是**同族自己的 route 时间与落点跨度**，全局 WNS 的绝对差本身既不叫收益也不叫损失。
# 地板：任一 roll 没跑到 ROLLDONE ⇒ 不产对照；每条判据都数"比较做了几次"，取不到数就 ABORT-NOVERDICT，不蒙。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
D=/tmp/kx/pb113
# 用 roll2 而不是 roll.tcl：v1 的矩形写法 `CLBLM_L_X40Y20:CLBLM_R_X66Y52` 被工具明确拒了
#   （凭据 /tmp/kx/pb113/B_roll_console.txt：`ERROR: [Vivado 12-28489] pblock resize has invalid range`——
#   CLBLM_* 是 UltraScale 的名字，7 系要 SLICE_*），而 v1 没有"逐个试"的循环。
#   A/B 的单变量性由件证明：`diff` 两份脚本只落在 pblock 分支与标签行上（跑完落到
#   build/evidence/r113_roll_scripts_diff.txt，判读时先看它）。
TCL=build/tcl/pb113_roll2.tcl
mkdir -p "$D/A" "$D/B" || { echo "ABORT: 建不了 $D"; exit 1; }
say() { echo "[pb113 $(date +%H:%M:%S)] $*"; }
ONLY=${1:-}

for pair in "none A" "pblock B"; do
  set -- $pair; MODE=$1; L=$2
  [ "$ONLY" = "--only-B" ] && [ "$L" = A ] && { say "跳过 roll A（--only-B，沿用它已完成的产物）"; continue; }
  WOUT=$(cygpath -w "$D/$L")
  say "roll $L（PB_MODE=$MODE）开始，输出 $D/$L"
  PB_MODE=$MODE PB_OUT="$WOUT" "$V/vivado.bat" -mode batch -nojournal \
      -source "$TCL" > "$D/${L}_roll_console.txt" 2>&1
  RC=$?
  grep -aq "ROLLDONE" "$D/${L}_roll_console.txt" \
      || { say "ABORT: roll $L 没跑到 ROLLDONE（rc=$RC）—— 断链，不产对照"; exit 1; }
  say "roll $L 完成 rc=$RC  PB: $(grep -a '^PB_' "$D/${L}_roll_console.txt" | tr '\n' ' ')"
done

num() { grep -a "$2" "$1" | head -1 | awk "{print \$$3}"; }

echo "# r113 物理单变量 A/B  A=不加 Pblock  B=加 Pblock（同一份 system_top_opt.dcp，裸 place/route，无 phys_opt）"
for L in A B; do
  F="$D/$L/family.rpt"; T="$D/$L/timing_summary.rpt"; R="$D/$L/route_status.rpt"
  for f in "$F" "$T" "$R"; do [ -s "$f" ] || { echo "ABORT-NOVERDICT: $L 缺 $f"; exit 2; }; done
  NB=$(grep -ac "^Slack (" "$F")
  [ "$NB" -ge 1 ] || { echo "ABORT-NOVERDICT: $L family.rpt 解析出 0 条 Slack（尺子空转）"; exit 2; }
  FAM=$(num "$F" "^Slack (" 4)
  # 数字行的位置是实测出来的：report_timing_summary 里 "Design Timing Summary" 之后第 7 行才是数（第 5 行是表头）。
  SUM=$(grep -aA6 "Design Timing Summary" "$T" | sed -n '7p')
  WNS=$(echo "$SUM" | awk '{print $1}'); FAIL=$(echo "$SUM" | awk '{print $3}'); EP=$(echo "$SUM" | awk '{print $4}')
  case "$WNS$FAIL$EP" in *[!0-9.]*|"") echo "ABORT-NOVERDICT: $L 的 WNS/失败端点/总端点 取不到纯数字（读到 '$SUM'）"; exit 2;; esac
  # route_status.rpt 的形状（实测 build/route_status.rpt）是 `# of …............ :  20907 :`，
  # 我第一版按 "Route Timing Met" 去 grep 取到空串——空串不能当"没问题"，所以现在取不到数就 REFUSE。
  ERR=$(grep -aoE "# of nets with routing errors\.* *: *[0-9]+" "$R" | grep -aoE "[0-9]+$" | head -1)
  FULL=$(grep -aoE "# of fully routed nets\.* *: *[0-9]+" "$R" | grep -aoE "[0-9]+$" | head -1)
  case "$ERR$FULL" in *[!0-9]*|"") echo "ABORT-NOVERDICT: $L 的 route_status 取不到纯数字（ERR='$ERR' FULL='$FULL'）"; exit 2;; esac
  [ "$ERR" = 0 ] || echo "  ⚠ ROUTE-ERRORS $L：有 $ERR 根网布不通（Pblock 让设计不可布，这一滚的数不能用）"
  echo "  $L[$( [ $L = A ] && echo none || echo pblock )] 族 slack=${FAM}ns（family.rpt 里 Slack 条数=$NB）" \
       "全设计 WNS=${WNS}ns 失败端点=${FAIL}/总端点=${EP} 全布通网数=${FULL} 布线错误=${ERR}"
  echo "     落点：$(grep -a '^SITE p_eof_reg\|^SITES rows_hit' "$D/${L}_roll_console.txt" | tr '\n' ' ')"
done
echo "# 判读口径：①B 的族 slack 明显大于 A ⇒ 距离被真的缩短，Pblock 这一刀成立；"
echo "#           ②同时看 B 的全设计 WNS 与失败端点——Pblock 的代价通常落在**别的**路径上（拥挤），只看这一族会骗人；"
echo "#           ③A 与本次 r112 正式构建（0.445 ns）的差 = 同一份输入的放置散布旁证，不当收益。"

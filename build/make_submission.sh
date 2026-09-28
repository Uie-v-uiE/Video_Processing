#!/usr/bin/env bash
# make_submission.sh — 从当前 git 跟踪集导出一份可直接交给评委的提交目录。
#
# 为什么以 `git ls-files` 为唯一入口：仓库里绝大多数的垃圾（vivado.log、xsim.dir/、
# .Xil/、study/、各处 dfx_runtime.txt）本来就被 .gitignore 挡住，跟着跟踪集走就自动
# 不会带出来；剩下的都是"曾经提交过、后来没人引用"的东西，用下面的 PRUNE 名单显式列。
#
# 用法：bash build/make_submission.sh [--dry]
#   不带 --dry 会重建 ../submission/（先删后写，所以是幂等的）。
#   只删自己生成的目录，绝不碰仓库内容。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(cd "$REPO/.." && pwd)/submission"
DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

# ---- PRUNE：仓库里跟踪着、但提交包不需要带的文件（每条都要能说出为什么不带）----
# 1) 一次性修复脚本：只修当年那一版 BD/顶层，没人再调用，别人照着跑只会困惑。
# 2) 重复/未引用的串口捕获：同一份内容有多份字节相同的副本，或没有任何文档引用。
# 3) Vivado 自动生成、且没人引用的 leftovers。
# 注意：build/tcl/rebuild_cdc_fix.tcl 在 report/BUILD.md 里有名字，保留；
#       sim/tb_v5_saver.v 虽然测的是未例化的老 saver，但它是 DDR 打包器改动的
#       复验工具（见 ISSUES 与优化清单），保留。
PRUNE_LIST=(
  "build/tcl/apply_cdc_report.tcl"
  "build/tcl/fix_bd_and_top.tcl"
  "build/tcl/rebuild_opt.tcl"
  "build/tcl/rebuild_zoom_out.tcl"
  "tight_setup_hold_pins.txt"
)

# 未引用且重复的上板捕获（字节相同的副本 + 没有任何 .md/.sh/.mjs 点名的 send_*.txt）
PRUNE_GLOBS=(
  "board/send_*.txt"
  "board/uart_50_soak2.txt"
  "board/uart_soak_A2.txt"
  "board/hw_server_scan2.log"
  "report/hw_server_scan2.log"
)
# 这些 send_/uart_ 捕获是门禁或文档点名的，PRUNE_GLOBS 命中也不删
KEEP_LIST=(
  "board/cmd_battery_v81.txt"
  "board/demo_rehearsal.txt"
)

is_kept() {
  local f="$1" k
  for k in "${KEEP_LIST[@]}"; do [ "$f" = "$k" ] && return 0; done
  return 1
}

# ---- 1. 用 git archive 把跟踪集解出来（不依赖工作区里的未提交改动）----
COMMIT="$(git -C "$REPO" rev-parse --short HEAD)"
DIRTY="$(git -C "$REPO" status --porcelain | wc -l)"
TMP="$OUT.tmp"

if [ "$DRY" = "1" ]; then
  echo "DRY RUN：只打印会带哪些、会删哪些，不动磁盘"
  mkdir -p "$TMP" && rm -rf "$TMP"/*
  git -C "$REPO" archive --format=tar HEAD | tar -x -C "$TMP"
else
  rm -rf "$OUT" "$TMP"
  mkdir -p "$TMP"
  git -C "$REPO" archive --format=tar HEAD | tar -x -C "$TMP"
fi

# ---- 2. 删 PRUNE ----
cd "$TMP"
removed=0
for f in "${PRUNE_LIST[@]}"; do
  if [ -e "$f" ]; then echo "  删 $f"; rm -f "$f"; removed=$((removed+1)); fi
done
for g in "${PRUNE_GLOBS[@]}"; do
  for f in $g; do
    [ -e "$f" ] || continue
    if is_kept "$f"; then echo "  保留（点名引用）$f"; continue; fi
    echo "  删 $f"; rm -f "$f"; removed=$((removed+1))
  done
done

# ---- 3. 目录对照表 + 清单（赛程 §3.3.5.4 要求"采用其他组织方式须给出对照"）----
files="$(find . -type f | wc -l)"
cat > MANIFEST.txt <<EOF
导出时间: $(date '+%Y-%m-%d %H:%M:%S')
来源仓库: $REPO
来源提交: $COMMIT (工作区未提交改动 $DIRTY 条)
文件数  : $files（删除 $removed 条之后）
生成脚本: build/make_submission.sh（可重跑；PRUNE 名单在脚本里，逐条带理由）

目录对照（赛程推荐结构 -> 本仓库）
  README.md      -> README.md（中文）+ README.en.md（英文）
  src/           -> src/rtl/**  RTL；src/ps/**  ARM 裸机固件；src/host/**  PC 侧工具与自检脚本
  sim/           -> sim/        台架与两个 runner；台架报告在 build/tb_*_r*.txt
  build/         -> build/       构建与门禁脚本、tcl/、evidence/ 与 rNN 留档
  board/         -> board/       上板说明、串口捕获、验收表
  data/          -> data/        golden/ 参考图、measured/ 实测数据
  skill/         -> skill/       大模型协作沉淀的技能包（README.md 为总说明）
  report/        -> report/      设计报告 + 大模型协作记录 + ISSUES/OVERNIGHT_LOG 追加式历史
EOF

echo
echo "导出提交 $COMMIT，$files 个文件，删 $removed 个"
if [ "$DRY" = "1" ]; then
  echo "DRY RUN：$TMP 留着，自己看过再 rm -rf"
  exit 0
fi
mv "$TMP" "$OUT"
echo "-> $OUT"

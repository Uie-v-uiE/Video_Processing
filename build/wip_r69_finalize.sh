#!/bin/bash
# build/wip_r69_finalize.sh —— 等 r69 构建收尾 → 跑门禁 → 把 CDC 那一笔单独拎出来打印。**不刷板**。
#
# 为什么要"等标记"而不是"看进程没了就跑"（#24(e)、以及 §19 那次真踩过的坑）：
#   构建还在写报告时读 build/*.rpt，念到的是**上一版**的数字而七项照样全绿。
#   所以唯一的放行条件是 `^SYSTEM BUILD DONE` 真的出现在 console 里（构建脚本最后一行才打它）。
#   进程消失但没有这个标记 = 构建死在半路 ⇒ 直接红着退出，不去读那套旧报告。
# 故意不做的事：不冻结 evidence、不刷板。门禁 rc 与 CDC 那一行要先有人（我）读过一遍，
#   因为 r69 唯一的新跨域面就是 gamma 那条 ASYNC_REG 链加宽 8 位，而 #71 已经红过一次同一种加宽。
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
cd "$ROOT" || exit 1
CON=build/r69_build_console.txt
MAXMIN=${1:-90}
t0=$(date +%s)

while true; do
  if grep -aq "^SYSTEM BUILD DONE" "$CON" 2>/dev/null; then
    echo "MARK: SYSTEM BUILD DONE 出现在 $CON"
    break
  fi
  if ! tasklist //FI "IMAGENAME eq vivado.exe" 2>/dev/null | grep -qi "vivado.exe"; then
    echo "ABORT: vivado.exe 已经不在了，但 console 里没有 SYSTEM BUILD DONE ⇒ 构建死在半路，"
    echo "       这套 build/*.rpt 还是上一版的，不许拿去判绿"
    exit 3
  fi
  if [ $(( ($(date +%s) - t0) / 60 )) -ge "$MAXMIN" ]; then
    echo "ABORT: 等了 ${MAXMIN} 分钟还没有收尾标记，人工来看一眼"; exit 4
  fi
  sleep 30
done

echo "=== 门禁（原始输出留在 build/r69_gates.txt）==="
bash build/gates.sh > build/r69_gates.txt 2>&1
rc=$?
cat build/r69_gates.txt
echo "GATES_RC=$rc"

echo "=== 这一版唯一的新跨域面：CDC 那一行要逐字读过（#71 的教训）==="
echo "--- 基线 CDC_BASELINE.txt:"
grep -v '^#' build/CDC_BASELINE.txt | grep -v '^[[:space:]]*$'
echo "--- 本版 cdc.rpt 的 Critical/Warning 行（End Safe Unsafe Unknown NoASYNC）:"
grep -a "^Critical\|^Warning" build/cdc.rpt
echo "--- 与 r68 那份的差（只看 clk_fpga_0>clkout0_1 那一行）:"
echo "r68: $(grep -a '^Critical.*clk_fpga_0 *clkout0_1' build/evidence_r68/cdc.rpt)"
echo "r69: $(grep -a '^Critical.*clk_fpga_0 *clkout0_1' build/cdc.rpt)"
exit $rc

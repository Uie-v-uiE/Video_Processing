#!/bin/bash
# build/wip_r71_finalize.sh —— 等 r71 构建收尾 → 生成"与当前树同一次跑"的顶层台架报告 → 跑门禁。
#
# 为什么把台架排在门禁**前面**：门禁第 15 项判的是"`build/tb_v98_report.txt` 是不是当前这份顶层
# 跑出来的"（`prov.txt` 里的 top_md5/tb_md5）。顶层从 r70 起改过（#92 三笔 + #94 的 src_life），
# 所以不重生成这份报告，第 15 项必红 —— 而红着念一遍等于没念（#88 那几天就是"gates 全绿 +
# 顶层台架红着"）。
#
# 为什么等标记而不是"看进程没了就跑"：构建还在写报告时读 build/*.rpt，念到的是**上一版**的数字
# 而各项照样全绿。唯一放行条件是 `^SYSTEM BUILD DONE` 真的出现在 console 里（脚本最后一行才打它）。
# 进程消失但没有这个标记 = 构建死在半路 ⇒ 直接红着退出，不许拿旧报告判绿。
#
# 故意不做的事：不冻结 evidence、不刷板。门禁 rc、CDC 那一行、以及第 15 项的 md5 对账
# 要先有人（我）读过一遍再动手（r71 唯一的新跨域面是 src_life 吃 `new_tog` —— 它**不该**新增
# 任何异步配对，cdc.rpt 若因此多出一行就是接错了，见 pl_video_top.v 那段注释）。
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
cd "$ROOT" || exit 1
CON=${CON:-/tmp/kx/r71_wrap.log}
MAXMIN=${1:-90}
t0=$(date +%s)

if [ ! -f "$CON" ]; then
    echo "ABORT: 找不到构建 console（$CON）—— 不要把 CON 指到一个空文件上然后等标记"
    exit 2
fi

while true; do
  if grep -aq "^SYSTEM BUILD DONE" "$CON" 2>/dev/null; then
    echo "MARK: SYSTEM BUILD DONE 出现在 $CON"
    cp -f "$CON" build/r71_build_console.txt 2>/dev/null
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

echo "=== 顶层台架报告（第 15 项的出处；这份要等 build 结束再起，否则抢核拖慢两边）==="
if [ "${SKIP_TB:-0}" = 1 ]; then
    # 什么时候用 SKIP_TB=1：已经有一轮 tb_v98 在跑（同一个 /tmp/kx/tb_v98_top_seam.run 目录，
    # 再起一次会 rm -rf xsim.dir 把在跑的那轮踩掉）。那就等它自己收尾，然后只收报告不再编译。
    TBLOG=${TB_LOG:-/tmp/kx/tb_v98_top_seam.run/run.log}
    echo "等在前面的那一轮：$TBLOG"
    t0b=$(date +%s)
    while ! grep -aq "^RESULT tb_v98_top_seam" "$TBLOG" 2>/dev/null; do
        if [ $(( ($(date +%s) - t0b) / 60 )) -ge "${MAXMIN_TB:-120}" ]; then
            echo "ABORT: 等了 ${MAXMIN_TB:-120} 分钟那轮台架还没出 RESULT —— 人工来看一眼，"
            echo "       不要拿上一版的报告去喂第 15 项"
            exit 5
        fi
        sleep 30
    done
    grep -a "^RESULT\|^FAIL " "$TBLOG" | tail -6
    bash build/tb98_report.sh > build/r71_tb98_report_wrap.txt 2>&1
    echo "tb98_report rc=$? —— 报告头三行："
    head -4 build/tb_v98_report.txt
else
bash sim/run_one.sh tb_v98_top_seam > build/r71_tb98_console.txt 2>&1
echo "run_one rc=$?"
bash build/tb98_report.sh > build/r71_tb98_report_wrap.txt 2>&1
echo "tb98_report rc=$? —— 报告头三行："
head -4 build/tb_v98_report.txt
fi

echo "=== 门禁（原始输出留在 build/r71_gates.txt）==="
bash build/gates.sh > build/r71_gates.txt 2>&1
rc=$?
cat build/r71_gates.txt
echo "GATES_RC=$rc"

echo "=== 本版新增的跨域面只有一处：src_life 吃 u_pub 的 new_tog（像素域内部）"
echo "--- 期望：cdc.rpt 的 Critical 行数与基线**一样**，且不出现新的 (axi_clk ↔ clk_pix) 配对"
grep -ac "^Critical" build/cdc.rpt
grep -a "^Critical\|^Warning" build/cdc.rpt | head -12
exit $rc

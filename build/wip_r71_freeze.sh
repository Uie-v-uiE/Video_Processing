#!/bin/bash
# build/wip_r71_freeze.sh —— 把 r71 这一成套凭据收进 build/evidence_r71/，并生成 MANIFEST.md5。
#
# 什么时候能跑（两道硬门）：
#   1) `build/r71_gates.txt` 里必须是 `GATES: ALL PASS` —— 红着的一版不配有自己的证据目录
#      （"红 = 没做完"，把红的东西冻结下来等于给下一轮留一个"看起来有凭据"的坑）；
#   2) `build/tb_v98_report.txt` 的 top_md5 必须还等于当前顶层的 md5 —— 门禁第 15 项判的就是这个，
#      冻结之后再改顶层，这份 evidence 就变成"上一版的照片挂在这一版的名下"。
# 为什么要有 MANIFEST.md5：现场只认 md5 不认文件名（`build/evidence_r*` 里同名的位流有好几份），
# 而"板上跑的到底是哪一版"是眼睛判据能不能算数的前提（`report/DEMO_SCRIPT.md` 第 0 步那条）。
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
cd "$ROOT" || exit 1
D=build/evidence_r71

if [ ! -f build/r71_gates.txt ] || ! grep -q "^GATES: ALL PASS" build/r71_gates.txt; then
    echo "REFUSE：r71 门禁不是 ALL PASS，不冻结。"
    [ -f build/r71_gates.txt ] && grep -a "FAIL\|——" build/r71_gates.txt | head -8
    exit 1
fi
TOPWANT=$(md5sum src/rtl/top/pl_video_top.v | cut -c1-12)
TOPYES=$(sed -n 's/.*top_md5=\([0-9a-f]*\).*/\1/p' build/tb_v98_report.txt | head -1)
if [ "$TOPYES" != "$TOPWANT" ]; then
    echo "REFUSE：tb_v98 报告（top_md5=$TOPYES）与当前顶层（$TOPWANT）不是同一次跑 —— 先重跑台架"
    exit 1
fi

mkdir -p "$D"
# 三件成品（位流/xsa/elf）+ 七份报告 + 两份台架与门禁 + 端口/宽度/多驱自检
for f in system.bit system.xsa ps_app.elf timing_summary.rpt utilization.rpt power.rpt \
         route_status.rpt methodology.rpt cdc.rpt multi_driven.txt width_warnings.txt \
         ports_check.txt tb_v98_report.txt r71_gates.txt r71_build_console.txt \
         r71_tb98_report_wrap.txt r71_tb98_console.txt; do
    [ -f "build/$f" ] && cp -f "build/$f" "$D/$f"
done
# 这几份是"这一轮跑台架时的现场"，不在 build/ 里而在 /tmp（run_one 的工作目录）
[ -f /tmp/kx/tb_v98_top_seam.run/run.log ] && cp -f /tmp/kx/tb_v98_top_seam.run/run.log "$D/r71_tb_v98_run.log"
[ -f /tmp/kx/tb_v98_top_seam.run/prov.txt ] && cp -f /tmp/kx/tb_v98_top_seam.run/prov.txt "$D/r71_tb98_prov.txt"
[ -f /tmp/kx/r71_finalize.log ] && cp -f /tmp/kx/r71_finalize.log "$D/r71_finalize.log"
# **L1 全量回归的原始日志也要进这一套**：门禁第 15 项只盯顶层台架那一份报告，其余台架红着
# 门禁可以全绿（2026-09-26 一天之内撞见两次：`tb_link_monitor` 与 `tb_v98` 都曾静默红过）。
# 所以冻结件里必须留一份"这一版下所有台架各自的 RESULT 行"，否则下一轮无法回答
# "r71 当时到底跑过哪些判据"。
[ -f /tmp/kx/r71_l1.log ] && cp -f /tmp/kx/r71_l1.log "$D/r71_l1_regress.txt"
# 顶层台架里"C2SHAPE / C2IBAD"那几行是 #92 残余那一格的唯一原始读数，单独抽一份免得埋在 60 KB 日志里
grep -a "^C2SHAPE\|^C2 row\|^C2IBAD\|^C2BLK" "$D/r71_tb_v98_run.log" > "$D/r71_c2_shape.txt" 2>/dev/null
L1P=$(grep -ac '^RESULT .* PASS' "$D/r71_l1_regress.txt" 2>/dev/null || echo 0)
L1F=$(grep -ac '^RESULT .* FAIL' "$D/r71_l1_regress.txt" 2>/dev/null || echo 0)

( cd build
  # ⚠ 只列"成套"那几件（三件成品 + 报告），不列 evidence 目录自己 —— 否则 MANIFEST 要包含自己的 md5。
  md5sum system.bit system.xsa ps_app.elf timing_summary.rpt utilization.rpt power.rpt \
         route_status.rpt methodology.rpt cdc.rpt tb_v98_report.txt r71_gates.txt 2>/dev/null ) > "$D/MANIFEST.md5"
{
  echo "# r71 evidence —— 生成于 $(date -Iseconds)"
  echo "# 顶层 $TOPWANT（门禁第 15 项按这一个数对账）"
  echo "#"
  echo "# 板上跑法只有 JTAG：build/tcl/ps_jtag_boot.tcl（先 ps7_init → 编 PL → 下 elf → con）"
  echo "# **不写 QSPI/SPI flash**（2025.2.1 的写入路径未验），也不碰 FT2232 EEPROM。"
  echo "#"
  echo "# 机器判据：门禁 16 项（build/gates.sh，第 15 项 = 本目录 r71_tb98_report 出处、"
  echo "#            第 16 项 = PS 侧心跳/残包约定 src/host/ps_hb_check.mjs --self）"
  echo "#            串口电池 97 条 + geom 8 条（board/cmd_battery_v81.txt + src/host/uart_cmd_check.mjs）"
  echo "#"
  echo "# 还欠眼睛/手的（这一版由用户签，见 board/README.md 对应行）："
  echo "#   第 30 项 #92 边缘那条带（r70 已判则沿用其结论）；第 31 项 #94 拔卡/暂停不丢画/sd remount（要一只手）；"
  echo "#   第 29 项 bilin A/B 的观感；#93 旋转大角度两条（用户 2026-09-26 明确'先放着最后再修'）"
} >> "$D/MANIFEST.md5"

echo "=== $D"
ls -1 "$D" | tr '\n' ' '; echo
echo "=== MANIFEST.md5"
cat "$D/MANIFEST.md5"

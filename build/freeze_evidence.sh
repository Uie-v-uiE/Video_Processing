#!/bin/bash
# build/freeze_evidence.sh <NN> —— 把第 NN 次构建的成套凭据收进 build/evidence_rNN/，并生成 MANIFEST.md5。
#
# 为什么要有 MANIFEST.md5：现场只认 md5 不认文件名（`build/evidence_r*` 里同名的位流有好几份），
# 而"板上跑的到底是哪一版"是眼睛判据能不能算数的前提（`report/DEMO_SCRIPT.md` 第 0 步那条）。
#
# 两道硬门（"红 = 没做完"，把红的东西冻结下来等于给下一轮留一个"看起来有凭据"的坑）：
#   1) `build/rNN_gates.txt` 里必须是 `GATES: ALL PASS`；
#   2) `build/tb_v98_report.txt` 的 **两枚**指纹（`top_md5` 与 `rtl_md5`）都必须还等于当前树：
#      只比顶层是不够的——r72 改的是四个窗口级，`pl_video_top.v` 一字未动，
#      那份 r71 的旧报告本来能原样冒充 r72 的凭据（门禁第 15 项的 E/F 两个反例就是这件事）。
#
#   用法：bash build/freeze_evidence.sh 72
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
cd "$ROOT" || exit 1
NN=${1:-}
case "$NN" in (''|*[!0-9]*) echo "用法: bash build/freeze_evidence.sh <构建编号，如 72>"; exit 2;; esac
D=build/evidence_r$NN
GT=build/r${NN}_gates.txt
TMP=$(mktemp -d)

if [ ! -f "$GT" ] || ! grep -q "^GATES: ALL PASS" "$GT"; then
    echo "REFUSE：$GT 不是 ALL PASS，不冻结。"
    [ -f "$GT" ] && grep -a "FAIL\|——" "$GT" | head -8
    exit 1
fi
TOPWANT=$(md5sum src/rtl/top/pl_video_top.v | cut -c1-12)
TOPYES=$(sed -n 's/.*top_md5=\([0-9a-f]*\).*/\1/p' build/tb_v98_report.txt | head -1)
RTLWANT=$(find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
RTLYES=$(sed -n 's/.* rtl_md5=\([0-9a-f]*\).*/\1/p' build/tb_v98_report.txt | head -1)
if [ "$TOPYES" != "$TOPWANT" ] || [ "$RTLYES" != "$RTLWANT" ]; then
    echo "REFUSE：tb_v98 报告(top=$TOPYES rtl=$RTLYES)与当前树(top=$TOPWANT rtl=$RTLWANT)不是同一次跑"
    echo "        ⇒ 先重跑：bash sim/run_one.sh tb_v98_top_seam && bash build/tb98_report.sh"
    exit 1
fi
NG=$(grep -acE ' (PASS|FAIL)$' "$GT")

mkdir -p "$D"
# 三件成品（位流/xsa/elf）+ 七份 Vivado 报告 + 三份自检 + 台架与门禁
for f in system.bit system.xsa ps_app.elf timing_summary.rpt utilization.rpt power.rpt \
         route_status.rpt methodology.rpt cdc.rpt clock_util.rpt multi_driven.txt \
         width_warnings.txt ports_check.txt tb_v98_report.txt r${NN}_gates.txt; do
    [ -f "build/$f" ] && cp -f "build/$f" "$D/$f"
done
# 构建与台架的**原始 console**（今天它们在 /tmp，不在 build/）
cp -f /tmp/kx/r${NN}_wrap.log        "$D/r${NN}_build_console.txt" 2>/dev/null
cp -f /tmp/kx/r${NN}_tb98_console.txt "$D/r${NN}_tb98_console.txt" 2>/dev/null
cp -f /tmp/kx/tb_v98_top_seam.run/run.log "$D/r${NN}_tb_v98_run.log" 2>/dev/null
cp -f /tmp/kx/tb_v98_top_seam.run/prov.txt "$D/r${NN}_tb98_prov.txt" 2>/dev/null
# L1 全量回归：门禁第 15 项只盯顶层台架那一份，其余台架红着门禁也能全绿（今天撞见两次），
# 所以冻结件里必须留"这一版下所有台架各自的结论行"。
cp -f /tmp/kx/r${NN}_l1.log "$D/r${NN}_l1_regress.txt" 2>/dev/null
grep -a "^C2SHAPE\|^C2 row\|^C2IBAD\|^C2BLK\|^OBS lastcol\|^ID " \
     "$D/r${NN}_tb_v98_run.log" > "$D/r${NN}_c2_shape.txt" 2>/dev/null
L1P=0; L1F=0
[ -f "$D/r${NN}_l1_regress.txt" ] && { L1P=$(grep -ac '^RESULT .* PASS' "$D/r${NN}_l1_regress.txt");
                                       L1F=$(grep -ac '^RESULT .* FAIL' "$D/r${NN}_l1_regress.txt"); }
GITHEAD=$(git rev-parse --short HEAD 2>/dev/null || echo 未知)
( cd build
  md5sum system.bit system.xsa ps_app.elf timing_summary.rpt utilization.rpt power.rpt \
         route_status.rpt methodology.rpt cdc.rpt tb_v98_report.txt r${NN}_gates.txt 2>/dev/null ) > "$D/MANIFEST.md5"
{
  echo "# r$NN evidence —— 生成于 $(date -Iseconds)   git=$GITHEAD"
  echo "# 指纹：顶层 $TOPWANT / 整个 src/rtl $RTLWANT（门禁第 15 项按这两枚对账）"
  echo "#"
  echo "# 板上跑法只有 JTAG：build/tcl/ps_jtag_boot.tcl（先 ps7_init → 编 PL → 下 elf → con）"
  echo "# **不写 QSPI/SPI flash**（2025.2.1 的写入路径未验），也不碰 FT2232 EEPROM。"
  echo "#"
  echo "# 机器判据：门禁 $NG 行明细（$GT）；L1 全量台架 PASS=$L1P FAIL=$L1F（r${NN}_l1_regress.txt）"
  echo "#           顶层台架逐列读数见 r${NN}_c2_shape.txt（C2SHAPE / C2IBAD / ID / OBS lastcol）"
  echo "#"
  echo "# 还欠眼睛/手的（这一版由用户签，见 board/README.md 对应行）："
  echo "#   第 30 项 #92 边缘那条带；第 31 项 #94 拔卡/暂停不丢画/sd remount（要一只手）；"
  echo "#   第 29 项 bilin A/B 的观感；#93 旋转大角度两条（用户 2026-09-26 明确"先放着最后再修"）"
} >> "$D/MANIFEST.md5"
rm -rf "$TMP"
echo "=== $D"
ls -1 "$D" | tr '\n' ' '; echo
echo "=== MANIFEST.md5 尾部"
tail -12 "$D/MANIFEST.md5"

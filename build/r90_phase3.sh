#!/bin/bash
# 用途：phase2 之后自动走完这一轮的收尾：判定 → 采纳 → 补长台架 → 门禁 → 上板 → 总账
# 输入：命令行参数、build/tcl/program_pl.tcl
# 输出：build/r90_rim_console.txt、build/r90_gates.txt、build/evidence/r90_flash_1_psboot.txt
# 退出码：1=非 0 分支（该文件 exit 1 那一行） 5=非 0 分支（该文件 exit 5 那一行） 6=FAIL
# build/r90_phase3.sh —— phase2 之后自动走完这一轮的收尾：判定 → 采纳 → 补长台架 → 门禁 → 上板 → 总账。
#
# 门槛写在纸面上，不是我临场挑的（#149/#150 定的）：
#   eth_rxc WNS >= 0.45 ns、最差路径级数 <= 6、顶层台架 FAIL 行 <= 1（那一条是已知的 C5c / #98）。
# 不满足就**不动 build/**、不刷板**，把数字留在日志里交给人看（规矩 35：一次构建不承诺门禁结果）。
#
# 需要的环境：VP_VIVADO_BIN=<Vivado>/bin、VP_XSDB=<Vitis>/bin/xsdb.bat
# 跑法：bash build/r90_phase3.sh        （它自己会等 phase2）
set -u
cd "$(dirname "$0")/.." || exit 1
LOG=build/r90_phase3.log
ISO=build/isolated_lenm1
DEC=build/r90_lenm1_decision.txt
say() { echo "[p3 $(date '+%F %H:%M:%S')] $*" >> "$LOG"; }
die() { say "STOP: $*"; exit 1; }

[ -n "${VP_VIVADO_BIN:-}" ] || die "没设 VP_VIVADO_BIN"
[ -x "$VP_VIVADO_BIN/xvlog" ] || die "VP_VIVADO_BIN 里没有 xvlog：$VP_VIVADO_BIN"
[ -n "${VP_XSDB:-}" ] || die "没设 VP_XSDB（上板三步要用 Vitis 的 xsdb.bat）"
# 上板那一步在三小时之后才用到这个路径：**现在就判**，别让人等到那时才发现变量写错。
[ -f "$VP_XSDB" ] || die "VP_XSDB 指向的文件不存在：$VP_XSDB"

# ---- 0) 等 phase2 结束（DONE 或 STOP 都算结束）
n=0
while ! grep -qaE "\] DONE|STOP:" build/r90_phase2.log 2>/dev/null; do
    sleep 30; n=$((n + 1))
    [ $n -gt 480 ] && die "等了 4 小时 phase2 还没结束（看 build/r90_phase2.log）"
done
grep -qa "STOP:" build/r90_phase2.log && { say "phase2 停了，本轮不采纳：$(grep -a 'STOP:' build/r90_phase2.log | tail -1)"; exit 5; }
say "phase2 DONE，开始收尾"

# ---- 1) 判定
[ -f "$DEC" ] || die "判定文件 $DEC 不在"
WNS=$(sed -n 's/.*eth_rxc WNS *: *\([-+0-9.]*\).*/\1/p' "$DEC" | head -1)
LEV=$(sed -n 's/.*最差路径级数 *: *\([0-9]*\).*/\1/p' "$DEC" | head -1)
NFAIL=$(sed -n 's/.*顶层台架 *: *FAIL 行=\([0-9]*\).*/\1/p' "$DEC" | head -1)
BRAM=$(sed -n 's/.*RAMB36 单元 *: *\([0-9]*\).*/\1/p' "$DEC" | head -1)
say "判定输入：WNS=$WNS 级数=$LEV tb_v98 FAIL 行=$NFAIL RAMB36=$BRAM"
awk -v w="$WNS" -v l="$LEV" -v f="$NFAIL" 'BEGIN{exit !(w+0>=0.45 && l+0<=6 && f+0<=1)}' \
  || { say "不达标（门槛 WNS>=0.45 / 级数<=6 / FAIL<=1）⇒ 不采纳、不刷板，等人判"; exit 6; }
say "达标 ⇒ 采纳 $ISO"

# ---- 2) 采纳：位流/XSA 与六份实现报告落回 build/（板级 elf 不动，本轮没改 PS）
cp "$ISO/system.bit" build/system.bit || die "拷位流失败"
cp "$ISO/system.xsa" build/system.xsa || die "拷 XSA 失败"
for r in timing_summary utilization power cdc methodology route_status clock_util; do
    [ -f "$ISO/$r.rpt" ] && cp "$ISO/$r.rpt" "build/$r.rpt"
done
cp "$ISO/crit_paths.txt" build/crit_paths.txt
cp "$ISO/crit_paths_raw.rpt" build/crit_paths_raw.rpt 2>/dev/null
say "已采纳：bit md5=$(md5sum build/system.bit | cut -c1-12)  BRAM=$BRAM  WNS=$WNS"

# ---- 3) 补两条长台架里 phase2 没跑的那一条（门禁第 16 项要它与当前树同一次跑）
bash build/sim/run_one.sh tb_edge_rim > build/r90_rim_console.txt 2>&1
grep -aq "RESULT tb_edge_rim PASS" build/r90_rim_console.txt \
  || say "注意：边缘条带台架没打出 PASS，门禁第 16 项会红，先看 build/r90_rim_console.txt"
ROUND=r90 bash build/rim_report.sh >> "$LOG" 2>&1 || say "rim_report 没出件"

# ---- 4) 门禁（红项不隐藏：把尾部与所有红行抄进日志）
bash build/gates.sh > build/r90_gates.txt 2>&1
say "gates rc=$?  尾部：$(tail -2 build/r90_gates.txt | tr '\n' ' ')"
grep -a "红\|FAIL\|REFUSE" build/r90_gates.txt | head -12 >> "$LOG"

# ---- 5) 上板（用户已授权刷板；**只走 JTAG**，本工程的脚本从不写 QSPI/SPI flash）
TS=$(date +%m%d_%H%M)
"$VP_XSDB" build/tcl/ps_jtag_boot.tcl > "build/evidence/r90_flash_1_psboot.txt" 2>&1
say "flash 1/3 ps_jtag_boot rc=$?"
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl > "build/evidence/r90_flash_2_program_pl.txt" 2>&1
say "flash 2/3 program_pl rc=$? bit=$(grep -aoE 'Bitstream.*bytes|DONE' build/evidence/r90_flash_2_program_pl.txt | tail -1)"
"$VP_XSDB" build/tcl/ps_app_reload.tcl > "build/evidence/r90_flash_3_app_reload.txt" 2>&1
say "flash 3/3 ps_app_reload rc=$?"
sleep 8
bash build/board_verify.sh --battery --geom > "build/evidence/r90_board_verify.txt" 2>&1
say "board_verify rc=$?  红步数：$(grep -acE '\[RED\]|FAIL' build/evidence/r90_board_verify.txt)"
tail -4 "build/evidence/r90_board_verify.txt" >> "$LOG"
say "上板时间戳目录留档 $TS（本轮号 r90）"

# ---- 6) 总账（三行结论，明早只看这一块）
{
  echo "r90 收尾总账  $(date '+%F %T')"
  echo "  采纳      : YES  bit md5 $(md5sum build/system.bit | cut -c1-12)（来源 $ISO）"
  echo "  时序      : eth_rxc WNS $WNS ns，最差路径级数 $LEV（采纳基线 0.516 / 4 级）"
  echo "  资源      : RAMB36 $BRAM 单元（采纳基线 93）"
  echo "  台架      : tb_v98 FAIL 行 $NFAIL；边缘条带 $(grep -a '^RESULT' build/tb_edge_rim_r90.txt 2>/dev/null | tail -1)"
  echo "  门禁      : $(grep -aE '全部判定|红项|PASS|FAIL' build/r90_gates.txt | tail -2 | tr '\n' ' ')"
  echo "  上板      : $(grep -aE 'RESULT|红' build/evidence/r90_board_verify.txt | tail -2 | tr '\n' ' ')"
} > build/r90_summary.txt
say "DONE 见 build/r90_summary.txt"

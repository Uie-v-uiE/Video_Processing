#!/bin/bash
# build/r90_phase2.sh —— r90 这一轮的自动部分：先拿**未修改的树**做等价性锚，再落"资源换时序"那一刀，
# 然后滚一轮构建 + 复跑顶层台架，最后写一份判定文件让人（明早的我）只看结论。
#
# 顺序是判据的一部分，不能换：
#   锚（老树全绿）→ 尺子自己有没有牙（变异对照必须只红 D 一条）→ 改 RTL → 改后仍全绿 →
#   隔离构建 → 路径级读数 → 顶层台架 → 判定文件。
# 任何一步不满足就停在那里，**不带病往下跑**。
#
# 需要的环境：VP_VIVADO_BIN=<Vivado>/bin（脚本里没有第二套说法）。
# 跑法：bash build/r90_phase2.sh        （后台跑，日志 build/r90_phase2.log）
set -u
cd "$(dirname "$0")/.." || exit 1
LOG=build/r90_phase2.log
RUN=/tmp/kx
BENCH=tb_icmp_rx_len
TOPB=tb_v98_top_seam
ISO=build/isolated_lenm1
PY=$(command -v python || command -v python3)
say() { echo "[p2 $(date '+%H:%M:%S')] $*" >> "$LOG"; }
die() { say "STOP: $*"; exit 1; }

[ -n "${VP_VIVADO_BIN:-}" ] || die "没设 VP_VIVADO_BIN"
[ -x "$VP_VIVADO_BIN/xvlog" ] || die "VP_VIVADO_BIN 里没有 xvlog：$VP_VIVADO_BIN"
[ -n "$PY" ] || die "找不到 python"
[ -f build/r90_phase1.log ] || die "phase1 还没开始（build/r90_phase1.log 不在）"

# ---------------------------------------------------------------- 0) 等上一跑台架结束
n=0
while tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; do
    sleep 30; n=$((n + 1))
    [ $n -gt 400 ] && die "等了 3 小时 上一跑 xsim 还在"
done
grep -aq "READY_FOR_NEXT_EDIT" build/r90_phase1.log || say "注意：phase1 没写 READY 标记，继续（它那份报告已另存）"
say "xsim 空闲，开始"

# ---------------------------------------------------------------- 1) 锚：未修改的树必须全绿
bash build/sim/run_one.sh $BENCH > build/r90_icmp_pre.log 2>&1
grep -aq "RESULT $BENCH PASS" build/r90_icmp_pre.log \
  || { say "锚红了，把 FAIL 行抄在这里："; grep -a "FAIL" build/r90_icmp_pre.log | head -8 >> "$LOG"; die "锚（老树）不绿，说明我的期望值写错了，不是 RTL 的问题"; }
say "1) 锚 OK：老树 $BENCH 全绿（判据行数=$(grep -acE '^\[tb_icmp_rx_len.v\] PASS' build/r90_icmp_pre.log)）"

# ---------------------------------------------------------------- 2) 尺子的牙：变异对照只该红 D 一条
cp sim/$BENCH.v /tmp/$BENCH.v.bak || die "备份台架失败"
sed -i "s/if ((n % 2) == 1) s32 = s32 + {8'h00, pay\[n-1\]};/if ((n % 2) == 1) s32 = s32 + {pay[n-1], 8'h00};/" sim/$BENCH.v
grep -aq "{pay\[n-1\], 8'h00}" sim/$BENCH.v || die "变异没落上（sed 模式失效），不动下一步"
bash build/sim/run_one.sh $BENCH > build/r90_icmp_mut.log 2>&1
NF=$(grep -acE "\] FAIL " build/r90_icmp_mut.log)
TAGS=$(grep -aE "\] FAIL " build/r90_icmp_mut.log | sed -E 's/.*\] FAIL ([A-Za-z0-9_]+).*/\1/' | sort -u | tr '\n' ' ')
cp /tmp/$BENCH.v.bak sim/$BENCH.v
[ "$(md5sum < sim/$BENCH.v)" = "$(md5sum < /tmp/$BENCH.v.bak)" ] || die "台架恢复后 md5 不一致，先人工看"
[ "$NF" -ge 1 ] || die "变异对照没红 ⇒ 这条判据没有牙（D 判不了东西）"
[ "$TAGS" = "D_checksum_pairs " ] || die "变异红了不止 D 一条：[$TAGS]，判据之间不独立，先归因"
say "2) 尺子有牙：把奇数尾字节放错半字 → 红 $NF 行，全部是 D_checksum_pairs"

# ---------------------------------------------------------------- 3) 落那一刀（六处精确替换，改不动就停）
cp src/rtl/eth/icmp_rx.v /tmp/icmp_rx.v.pre_edit
"$PY" build/r90_patch_icmp.py >> "$LOG" 2>&1 || die "补丁 REFUSE，见上面；树未改动"
say "3) RTL 已改：+16 FF(len-1 寄存) +1 FF(数据窗旗标)，数据相里两条借位链都没了"

# ---------------------------------------------------------------- 4) 改后必须仍全绿
bash build/sim/run_one.sh $BENCH > build/r90_icmp_post.log 2>&1
grep -aq "RESULT $BENCH PASS" build/r90_icmp_post.log \
  || { say "改后红了，FAIL 行："; grep -a "FAIL" build/r90_icmp_post.log | head -12 >> "$LOG"
       cp /tmp/icmp_rx.v.pre_edit src/rtl/eth/icmp_rx.v
       die "已把 icmp_rx.v 回退到改前（逐字节从 /tmp 恢复）"; }
say "4) 改后全绿：等价性由 A..J 十条 x 15 包钉住"

# ---------------------------------------------------------------- 5) 隔离构建（不碰 build/ 那套）
OUT=$ISO bash build/roll_isolated.sh > build/r90_iso_console.txt 2>&1
grep -aq "SYSTEM BUILD DONE" $ISO/build_console.txt || die "隔离构建没有 SYSTEM BUILD DONE，别看数字"
say "5) 隔离构建完成 $ISO bit=$(md5sum $ISO/system.bit | cut -c1-12)"
cp build/crit_paths.txt $ISO/crit_paths_prev.txt 2>/dev/null
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl > build/r90_critpath_console.txt 2>&1
cp build/crit_paths.txt $ISO/crit_paths.txt
say "6) 路径级读数（新）："
tail -n +1 $ISO/crit_paths.txt >> "$LOG"

# ---------------------------------------------------------------- 7) 顶层台架 + 判定文件
bash build/sim/run_one.sh $TOPB > build/r90_tb98_console.txt 2>&1
bash build/tb98_report.sh >> "$LOG" 2>&1
cp build/tb_v98_report.txt build/r90_final_tb98.txt
WNS=$(awk '/^eth_rxc/{print $2}' $ISO/timing_summary.rpt | head -1)
LEV=$(head -3 $ISO/crit_paths.txt | tail -1 | sed -E 's/.*\| ([0-9]+) \|.*/\1/')
BRAM=$(awk '/RAMB36\/FIFO/{print $2}' $ISO/utilization.rpt | head -1)
NFAIL=$(grep -acE "^FAIL " build/r90_final_tb98.txt)
RES=$(grep -aE "^RESULT tb_v98_top_seam" build/r90_final_tb98.txt | tail -1)
{
  echo "r90 len-1 寄存那一刀的判定  $(date '+%F %T')"
  echo "  隔离产物      : $ISO  bit=$(md5sum $ISO/system.bit | cut -c1-12)"
  echo "  eth_rxc WNS   : $WNS   (采纳基线 0.516 / 只拆分不修 0.232)"
  echo "  最差路径级数  : $LEV   (基线 4 / 只拆分不修 9)"
  echo "  RAMB36 单元   : $BRAM  (基线 93 / 拆分 88)"
  echo "  顶层台架      : FAIL 行=$NFAIL  $RES"
  echo "  这一步只出数，**采纳与否由人判**（规矩 35：一次构建的数字不承诺门禁结果）"
} > build/r90_lenm1_decision.txt
say "7) 判定文件 build/r90_lenm1_decision.txt 已写"
say "DONE"

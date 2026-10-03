#!/usr/bin/env bash
# build/r116_stage2.sh —— 构建完之后剩下的那一半，交给一个看门狗自己走（夜里没有人敲第二条命令）。
# 前置：build/r116_chain.sh 在飞；它跑完会留下 build/evidence/r116/r116_io_HOLD.rpt。
# 判据与采纳规则写在 build/r116_batch_plan.md 第二节；这里只负责"把每条判据的件问回来"。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
export VP_XSDB=${VP_XSDB:-"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"}
NN=116
MARK=build/evidence/r$NN/r116_io_HOLD.rpt
say() { printf '[stage2 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---- 0. 等构建（最多 220 分钟；到点就走，不无限等）------------------------------------
for i in $(seq 1 220); do
    [ -f "$MARK" ] && break
    sleep 60
done
[ -f "$MARK" ] || { say "等不到 $MARK —— 构建那一半没走完，stage2 不产凭据"; exit 1; }
say "构建判读件到位（$MARK），开始 stage2"
grep -a "^V1V3\|^V2 \|^V4 ROW\|^VP_OBJS" build/evidence/r$NN/../r${NN}_verdict_console.txt 2>/dev/null | head -20

# ---- 1. 逐时钟名册：必须与 r114 那份**同一个生成器**（混口径会被 REFUSE，#291/#293）------
VP_LABEL=r${NN}_after VP_N=4 "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_timing_roster.tcl \
    > "build/r${NN}_roster_console.txt" 2>&1; say "roster probe rc=$?"
grep -a "^ROSTER|" "build/r${NN}_roster_console.txt" > "build/evidence/r${NN}_after_roster.txt"
say "名册行数=$(grep -c '^ROSTER|' build/evidence/r${NN}_after_roster.txt)（r114 那份=$(grep -c '^ROSTER|' build/evidence/r114_after_roster.txt)）"
bash build/timing_roster_diff.sh build/evidence/r114_after_roster.txt "build/evidence/r${NN}_after_roster.txt" \
    > "build/evidence/r${NN}_roster_diff.txt" 2>&1; say "名册差分 rc=$?"
grep -a "^ROSTERDIFF\|SUMMARY" "build/evidence/r${NN}_roster_diff.txt" | head -24

# ---- 2. 改后读数（与 r114_before/r114_after 同一把尺子）--------------------------------
VP_LABEL=r${NN}_after bash build/pre_readings.sh r${NN}_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$? —— build/evidence/r${NN}_after.txt"

# ---- 3. 快车道（分钟级，31 支）----------------------------------------------------------
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L $(grep -a 'LANE-SUMMARY' "build/r${NN}_lane_after.txt" | tail -1)"

# ---- 4. 顶层台架（一轮只付这一次）--------------------------------------------------------
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; say "tb_v98 rc=$?"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "tb_edge_rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# ---- 5. 门禁（先 /tmp 再 cp，两跑要逐字节一致）-------------------------------------------
mkdir -p /tmp/kx
bash build/gates.sh > "/tmp/kx/g_r$NN.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r$NN.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r$NN-2.txt" 2>&1
cmp -s "/tmp/kx/g_r$NN.txt" "/tmp/kx/g_r$NN-2.txt" && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑不一致（写回后再跑一遍）"
cp -f "/tmp/kx/g_r$NN-2.txt" "build/r${NN}_gates.txt"
say "门禁 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "stage2 结束：判读抓手 = V1 有限 slack / V2 eth_rx 命中数 / V3 I/O 最差格 / V4 名册差分 / 门禁红条清单"

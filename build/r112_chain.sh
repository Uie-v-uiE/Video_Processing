#!/usr/bin/env bash
# build/r112_chain.sh —— 第三捆（刀 A：key_debounce 上电武装门 #247/#250；刀 B：icmp_tx 校验和累加器 32→20）的整轮链。
# 与 r110_chain 的差别：
#   ① 改前读数问的是**盘上那份 r110**（已采纳、在板上跑着的那一版），并且先把 `build/setup_paths.rpt`
#      钉成 `build/evidence/r110_setup_paths_baseline.rpt` —— 收益口径是"同一条锥自己动没动"，
#      没有钉住的基线就只能拿全局 WNS 说事（#242 第 3 条）。
#   ② 台架清单从 28 支涨到 31 支（新增 tb_v111_key_boot / tb_v112_tx_bytes；tb_v112_ip_csum 不入车道，见 #250）。
# 纪律照旧：构建/台架在飞不动 `src/rtl`/`sim`；门禁先 /tmp 再 cp 到位、两跑逐字节一致（#229/#242）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=112
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE: 没有 Vivado（VP_VIVADO_BIN='$V'）"; exit 2; }

# ① 改前基线：先把 r110 那份最差路径报告钉成件（构建会覆盖 build/setup_paths.rpt）
if [ -f build/setup_paths.rpt ] && ! cmp -s build/setup_paths.rpt build/evidence/r110_setup_paths_baseline.rpt; then
    cp -f build/setup_paths.rpt build/evidence/r110_setup_paths_baseline.rpt
    say "改前基线钉好：build/evidence/r110_setup_paths_baseline.rpt（md5 $(md5sum < build/evidence/r110_setup_paths_baseline.rpt | cut -c1-12)）"
fi
if [ -f vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp ]; then
    VP_LABEL=r112_before bash build/pre_readings.sh r112_before > "build/r${NN}_pre_readings_console.txt" 2>&1
    say "改前读数 rc=$? —— 落 build/evidence/r112_before.txt"
else
    say "没有 DCP 可问改前读数（跳过；构建后只能拿本轮自己的读数）"
fi

say "构建开始（刀 A + 刀 B）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }

# ② 综合告警名册 + 资源行（刀 B 少了 12 个 FF、刀 A 多了 2×22 ⇒ 净账在这份件里念）
{
  echo "# r${NN} 综合告警名册（种类数与身份都要与 r110 那份比，不许增加）"
  grep -aoE "Synth 8-[0-9]+" "build/r${NN}_build_console.txt" | sort | uniq -c | sort -rn
  echo "## 资源行"
  grep -aE "Slice LUTs|Slice Registers|Block RAM Tile|DSPs" build/utilization.rpt | head -4
} > "build/evidence/r${NN}_synth_roster.txt" 2>&1
say "告警名册与资源行落 build/evidence/r${NN}_synth_roster.txt"

say "只读探针（全局最差 / hold / 每时钟 / 锥）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=r112_after bash build/pre_readings.sh r112_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$? —— 与 build/evidence/r112_before.txt / r110_setup_paths_baseline.rpt 逐条对着念"

say "快车道（30 支，分钟级）"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L 绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt") 挡=$(grep -c 'LANE BLOCKED' "build/r${NN}_lane_after.txt")"
grep -a "LANE-SUMMARY" "build/r${NN}_lane_after.txt"

say "顶层台架（实测约 70–128 分钟，一轮只付这一次）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; say "tb_v98 rc=$?"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

say "门禁（先 /tmp 再 cp，两跑要逐字节一致）"
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}.txt" "/tmp/kx/g_r${NN}2.txt" \
    && say "门禁两跑逐字节一致 rc=$G" || say "⚠ 门禁两跑**不一致**（D1c 读的是盘上那份，见 #242 第 1 条）——写回后再跑一遍直到一致"
cp -f "/tmp/kx/g_r${NN}2.txt" "build/r${NN}_gates.txt"
say "绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "链结束：判读抓手 = 那条 0.713 ns / 6×CARRY4 的自己动没动（对照 build/evidence/r110_setup_paths_baseline.rpt）；采纳走六步清单"

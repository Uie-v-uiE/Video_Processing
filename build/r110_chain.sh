#!/usr/bin/env bash
# build/r110_chain.sh —— 第二捆（#174 gapclr 同拍 + #177 死代码 + #158 截断行判据 + 可选刀 4）的整轮链。
#
# 与 r109 那支的**唯一结构差别**：开头多了一步 `build/pre_readings.sh`——
#   在构建**覆盖 DCP 之前**把改前读数问回来落成件（收益口径是"同一条锥/同一个时钟自己动没动"，
#   而 r108 那一轮我差点因为忘了这一步只能拿全局 WNS 说事）。
#   ⚠ 所以这一支必须在真树里**已经落完刀但还没构建**的状态下起飞；改前读数那一步如果落在构建之后就是废的。
# 其余纪律照旧：构建/台架在飞期间不动 `src/rtl`/`sim`（#234：链子里也别再起第二支 xsim）；
# 门禁先落 /tmp 再 cp 到位（#229）；快车道判逐刀等价性，顶层台架一轮只付一次。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=110
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ① 改前读数（DCP 还是上一轮那一版 ⇒ 现在不问，构建完就问不回来了）
if [ -f vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp ]; then
    VP_LABEL=${LABEL_BEFORE:-r110_before} bash build/pre_readings.sh "${LABEL_BEFORE:-r110_before}" \
        > "build/r${NN}_pre_readings_console.txt" 2>&1
    say "改前读数 rc=$? —— 落 build/evidence/${LABEL_BEFORE:-r110_before}.txt（空读数会让这一步红）"
else
    say "没有 DCP 可问改前读数（第一次跑？），跳过这一步，构建后只能拿本轮自己的读数当基线"
fi

say "构建开始（第二捆：#174 gapclr + #177 死代码 + #158 判据 + 可选刀 4）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }

# ② 死代码那一刀的专属凭据：告警名册（种类数与身份都要比对，#124/#177 的口径）
{
  echo "# r${NN} 综合告警名册（判 #177：8-3848 fifo_tx_data 要消失、split_ctrl 的 8-3332 归零、"
  echo "#   udp_tx 那 7 条 FSM_onehot 必须还在、8-7137 仍为 19、Synth 8-xxxx 的种类数不许增加）"
  grep -aoE "Synth 8-[0-9]+" "build/r${NN}_build_console.txt" | sort | uniq -c | sort -rn
  echo "## 8-3332 按模块"; grep -aoE "Synth 8-3332\] Sequential element \([^)]+\) is unused and will be removed from module [a-zA-Z0-9_]+" "build/r${NN}_build_console.txt" | sed -E 's/.*from module //' | sort | uniq -c | sort -rn
  echo "## 8-3848 逐条";   grep -aE "Synth 8-3848" "build/r${NN}_build_console.txt" | head -6
  echo "## 资源（Slice Registers 应下降，见 build/evidence/r109_deadunit_roster.txt 的 FF −14 预期）"
  grep -aE "Slice LUTs|Slice Registers|Block RAM Tile|DSPs" build/utilization.rpt | head -4
} > "build/evidence/r${NN}_deadcode_proof.txt" 2>&1
say "死代码名册落 build/evidence/r${NN}_deadcode_proof.txt"

say "只读探针（全局最差 / hold / 每时钟 / 锥）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=${LABEL_AFTER:-r110_after} bash build/pre_readings.sh "${LABEL_AFTER:-r110_after}" \
    > "build/r${NN}_post_readings_console.txt" 2>&1; say "改后读数 rc=$? —— 与 build/evidence/${LABEL_BEFORE:-r110_before}.txt 逐条对着念"

say "快车道（分钟级；#174 的 tb_link_monitor 必须整支绿，F2e A/B 与 F2a–F2d 都在里面）"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L 绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt") 挡=$(grep -c 'LANE BLOCKED' "build/r${NN}_lane_after.txt")"
grep -a "LANE-SUMMARY" "build/r${NN}_lane_after.txt"

say "顶层台架（实测约 127 分钟，一轮只付这一次）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; say "tb_v98 rc=$?"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

say "门禁（先 /tmp 再 cp，#229；两跑要逐字节一致）"
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G —— 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "链结束（采纳判读走 build/r109_adoption_checklist.md，把 r109 换成 r${NN}；板子要先断电重上）"

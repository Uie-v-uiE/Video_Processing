#!/usr/bin/env bash
# build/r113_chain.sh —— r113 整轮链：带 #256 的上电值修复（key_debounce 声明初值）+ r112 那两刀。
# 与 r112_chain 的差别（只两条，别的话都照旧）：
#   ① 构建后**先问位流上电值再付台架的钱**：`build/check_powup_init.sh` 判红就断链。
#      理由：这一轮的存在意义就是那颗 INIT 从 0 变 1；它没变的话，后面 70–128 分钟的顶层台架
#      和门禁只是给一版"修没修上都一样"的位流做公证（规矩：红 = 未完成，不要往下烧）。
#   ② 改前基线钉的是**盘上那份 r112**（897fa9d93956 的门禁身份），车道条数真值 31。
# 纪律照旧：构建/台架在飞不动 `src/rtl`/`sim`；门禁先 /tmp 再 cp 到位、两跑逐字节一致（#229/#242）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=113
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE: 没有 Vivado（VP_VIVADO_BIN='$V'）"; exit 2; }

# ① 改前基线：把 r112 那份最差路径报告钉成件（构建会覆盖 build/setup_paths.rpt）
if [ -f build/setup_paths.rpt ] && ! cmp -s build/setup_paths.rpt build/evidence/r112_setup_paths_baseline.rpt; then
    cp -f build/setup_paths.rpt build/evidence/r112_setup_paths_baseline.rpt
    say "改前基线钉好：build/evidence/r112_setup_paths_baseline.rpt（md5 $(md5sum < build/evidence/r112_setup_paths_baseline.rpt | cut -c1-12)）"
fi
if [ -f vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp ]; then
    VP_LABEL=r113_before bash build/pre_readings.sh r113_before > "build/r${NN}_pre_readings_console.txt" 2>&1
    say "改前读数 rc=$? —— 落 build/evidence/r113_before.txt"
else
    say "没有 DCP 可问改前读数（跳过；构建后只能拿本轮自己的读数）"
fi

say "构建开始（#256 上电值修复 + 刀 A 武装门 + 刀 B 校验和 20 位）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }

# ② 这一轮的第一判据：位流上电值（open_checkpoint 问 INIT，台架看不见这一位）
say "上电值对账（check_powup_init.sh，只读 open_checkpoint）"
ROUND=r${NN} bash build/check_powup_init.sh > "build/r${NN}_powup_console.txt" 2>&1; W=$?
grep -a '^POWUP ' "build/r${NN}_powup_console.txt" | sed 's/^/[powup] /'
if [ $W -ne 0 ]; then
    say "上电值判红（rc=$W）—— 断链：这一版没把 #256 修上，不许再付台架的钱，也不许上板"
    exit 1
fi
say "上电值判绿：key_stable 的位流 INIT 已经是 1'b1（对照 build/evidence/r113_ff_init.txt 里 r112 的 1'b0）"

# ③ 综合告警名册 + 资源行（修复只改 INIT 属性，逻辑不该动 ⇒ 净账在这份件里念）
{
  echo "# r${NN} 综合告警名册（种类数与身份都要与 r112 那份比，不许增加）"
  grep -aoE "Synth 8-[0-9]+" "build/r${NN}_build_console.txt" | sort | uniq -c | sort -rn
  echo "## 资源行"
  grep -aE "Slice LUTs|Slice Registers|Block RAM Tile|DSPs" build/utilization.rpt | head -4
} > "build/evidence/r${NN}_synth_roster.txt" 2>&1
say "告警名册与资源行落 build/evidence/r${NN}_synth_roster.txt"

say "只读探针（全局最差 / hold / 每时钟 / 锥）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=r113_after bash build/pre_readings.sh r113_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$? —— 与 build/evidence/r113_before.txt / r112_setup_paths_baseline.rpt 逐条对着念"

say "快车道（31 支，分钟级）"
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
say "链结束：判读抓手 = ①上电值那颗（$([ $W -eq 0 ] && echo 已绿 || echo 红)）②那条 0.445 ns / 6×CARRY4 的自己动没动（对照 build/evidence/r112_setup_paths_baseline.rpt）；采纳走六步清单"

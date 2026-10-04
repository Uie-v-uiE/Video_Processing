#!/usr/bin/env bash
# build/r114_chain.sh —— r114 整轮链：只带两刀（#262 的 ASYNC_REG 属性 + #257 尾的 hb_gone 声明初值）。
# 与 r113_chain 的差别（三条，别的话照旧）：
#   ① 第一判据从"位流上电值"换成**两把静态尺子**：`scan_async_reg_coverage.py` 的 SYNCREG-SUMMARY
#      必须 result=GREEN（pairs>=2 / missing=0 / ghosts=0 / edges>=2），
#      `scan_dead_reset_init.py` 的 SCAN_SUMMARY 必须 result=CLEAN（init_miss_total=0）。
#      这两把**构建前也跑一次**（它们只读 RTL 文本，红绿与 DCP 无关）——改前红的凭据已在
#      build/evidence/r113_async_reg_scan.txt（A2 RED）与 scan_dead_reset_init 的 init_miss=1，
#      构建前那次是"确认改前状态已经不存在了"，构建后那次是"进链子的账"。
#   ② 这两刀都是**属性/初值级**，预期时序中性 ⇒ 本轮的判据重心是名册八对逐格差分，
#      不是头条 WNS（rule 35：WNS 的绝对差既不算收益也不算损失）。
#   ③ 改前基线钉的是盘上那份 r113（bit b94f4da6cdff 的门禁身份），车道条数真值 31。
# 不进本轮的（口径在 build/r114_batch_plan.md §十二）：RGMII 输入窗那三份 XDC（#275/#282/#285
#   量到 eth_rxc hold -2.885，采纳它 = 明知违例还上板）、四条 set_max_delay -datapath_only
#   （#276 叠在异步组上不产生新异常行）、复制驱动那一刀（等 A/B 真裁决）。
# 纪律照旧：构建/台架在飞不动 `src/rtl`/`sim`；门禁先 /tmp 再 cp 到位、两跑逐字节一致（#229/#242）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
# 一次性把 xsdb 也带上：#273 栽过——分离式链子里没人导 VP_XSDB，board_verify 到那一步才 REFUSE。
# 路径是盘上验过的（2026-10-03 18:3x `find -maxdepth 3 -name xsdb.bat` 有两个：Vitis/bin 与 Vivado/bin；
# 用 Vitis 那一个，与 report/build.md 的说法一致），不是猜的。
export VP_XSDB=${VP_XSDB:-"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"}
NN=114
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE: 没有 Vivado（VP_VIVADO_BIN='$V'）"; exit 2; }

# ① 本轮的存在意义：两把静态尺子（构建前）
sync_pre() { python build/scan_async_reg_coverage.py 2>&1 | tee "build/evidence/r${NN}_async_reg_$1.txt" | grep -a '^SYNCREG'; }
drst_pre() { python build/scan_dead_reset_init.py      2>&1 | tee "build/evidence/r${NN}_dead_reset_$1.txt" | grep -a '^SCAN_SUMMARY'; }
say "尺子 1/2（改前树，ASYNC_REG 覆盖）"; sync_pre pre
say "尺子 2/2（改前树，死复位初值）";     drst_pre pre
grep -a "result=GREEN" "build/evidence/r${NN}_async_reg_pre.txt" >/dev/null \
    || { say "ASYNC_REG 尺子没绿 —— 断链（这一版根本没把 #262 打上）"; exit 1; }
grep -a "result=CLEAN" "build/evidence/r${NN}_dead_reset_pre.txt" >/dev/null \
    || { say "死复位初值尺子没 CLEAN —— 断链（#257 尾没修上）"; exit 1; }

# ② 改前基线：把 r113 那份最差路径报告钉成件（构建会覆盖 build/setup_paths.rpt）
if [ -f build/setup_paths.rpt ] && ! cmp -s build/setup_paths.rpt build/evidence/r113_setup_paths_baseline.rpt; then
    cp -f build/setup_paths.rpt build/evidence/r113_setup_paths_baseline.rpt
    say "改前基线钉好：build/evidence/r113_setup_paths_baseline.rpt"
fi
if [ -f vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp ]; then
    VP_LABEL=r114_before bash build/pre_readings.sh r114_before > "build/r${NN}_pre_readings_console.txt" 2>&1
    say "改前读数 rc=$? —— 落 build/evidence/r114_before.txt"
else
    say "没有 DCP 可问改前读数（跳过；构建后只能拿本轮自己的读数）"
fi

say "构建开始（#262 ASYNC_REG + #257 尾 hb_gone 初值，两刀都是属性/初值级）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }

# ③ 网表侧的 ASYNC_REG：属性有没有活到优化后（report_methodology 的 TIMING-10 计数是代价面）
{
  echo "# r${NN} 综合告警名册（种类数与身份都要与 r113 那份比，不许增加）"
  grep -aoE "Synth 8-[0-9]+" "build/r${NN}_build_console.txt" | sort | uniq -c | sort -rn
  echo "## 资源行"
  grep -aE "Slice LUTs|Slice Registers|Block RAM Tile|DSPs" build/utilization.rpt | head -4
} > "build/evidence/r${NN}_synth_roster.txt" 2>&1
say "告警名册与资源行落 build/evidence/r${NN}_synth_roster.txt"

say "只读探针（全局最差 / hold / 每时钟 / 锥 / ASYNC_REG 落网表）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=r114_after bash build/pre_readings.sh r114_after > "build/r${NN}_post_readings_console.txt" 2>&1
say "改后读数 rc=$? —— 与 build/evidence/r114_before.txt / r113_setup_paths_baseline.rpt 逐条对着念"
# 网表侧那把：属性在不在优化后的 FF 上 + TIMING-10 还剩几条（改前 1 条，凭据 r113_async_reg_scan.txt）
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_r114_async_netlist.tcl \
    > "build/r${NN}_async_netlist_console.txt" 2>&1; say "probe_r114_async_netlist rc=$?"

say "快车道（31 支，分钟级）"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L 绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt") 挡=$(grep -c 'LANE BLOCKED' "build/r${NN}_lane_after.txt")"
grep -a "LANE-SUMMARY" "build/r${NN}_lane_after.txt"

say "顶层台架（实测约 70–128 分钟，一轮只付这一次）"
bash build/sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; say "tb_v98 rc=$?"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
bash build/sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "rim rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

say "门禁（先 /tmp 再 cp，两跑要逐字节一致）"
mkdir -p /tmp/kx
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
bash build/gates.sh > "/tmp/kx/g_r${NN}2.txt" 2>&1
cmp -s "/tmp/kx/g_r${NN}.txt" "/tmp/kx/g_r${NN}2.txt" \
    && say "门禁两跑逐字节一致 rc=$G" || say "门禁两跑**不一致**（D1c 读的是盘上那份，见 #242 第 1 条）——写回后再跑一遍"
cp -f "/tmp/kx/g_r${NN}2.txt" "build/r${NN}_gates.txt"
say "绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
# 构建后再跑一次两把尺子（进链子的账，与改前那份并排放）
sync_pre post > /dev/null; drst_pre post > /dev/null
say "尺子复跑：$(grep -a '^SYNCREG-SUMMARY' "build/evidence/r${NN}_async_reg_post.txt") | $(grep -a '^SCAN_SUMMARY' "build/evidence/r${NN}_dead_reset_post.txt")"
say "链结束：判读抓手 = ①两把静态尺子 pre/post 都绿 ②名册八对逐格差分（其它域不许从 MET 掉进违例）③TIMING-10 计数离开 1"

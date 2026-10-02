#!/usr/bin/env bash
# build/r109_chain.sh —— r109 批次轮：**一次构建同时回答三件事**（用户明确要求别再逐刀付几小时台架）
#   ① #167/#98：帧头那 6 行的"每帧换角"错拍 —— 改 `rot_fs_tog` 的翻转拍点 + 顶层台架新增 C12a/b/c 三条；
#   ② #105：`clkout0_1` 那 23 级 OSD 读侧锥 —— 在源头把"屏上给人读的数"寄存一拍（同 r60 的 pct_q 手法）；
#   ③ #176：两把纯静态尺子（pipe_len / temp_formula）已接进门禁 ⇒ 本轮门禁是 **24 项**，
#      首页那句"22 项 21 绿 / 1 红"的**改口与计数轮换放在采纳那一笔提交里**（#229/#226 的规矩：
#      门禁条数本身就是被判的数，构建在飞时不许动它）。
#
# 台架这一侧分成两段，这是本脚本与 r108 那支唯一的结构差别：
#   快车道 `build/timing_lane.sh`（实测单元级 15~19 秒一支，全部约 10 分钟）——逐刀等价性；
#   顶层台架 `tb_v98_top_seam`（约 100 分钟）——**一轮只付一次**，采纳前的门禁凭据。
# 其余纪律照旧：构建在飞期间不动 `src/rtl`/`sim`；门禁**先落 /tmp 再 cp 到位**（#229）；台架一次一支（#173）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=109
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

say "构建开始（r109 批次：换角拍点 + OSD 源头寄存 + 门禁两项）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }
say "构建完成，开始只读探针（全局最差 / hold / 两个锥）"

"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  \
    > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl \
    > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"

# #105 的那把刀就量在它自己的时钟上：`-from/-to [get_clocks clkout0_1]`（`-of_objects` 与
# `-max_paths`/`-delay_type` 互斥，见 build/tcl/probe_clk_worst.tcl 文件头）。
VP_CLK=clkout0_1 VP_LABEL=r${NN}clk01 VP_N=8 \
    "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_clk_worst.tcl \
    > "build/r${NN}_clk01_probe_console.txt" 2>&1; say "clkout0_1 探针 rc=$?"
# 换角拍点这一刀改的是控制通路，不给它量锥；但它必须不影响 `eth_rxc` 那条绝对最差 —— 由 crit_path 兜。

say "快车道台架（分钟级，逐刀等价性；顶层台架不在里面）"
bash build/timing_lane.sh > "build/r${NN}_lane_after.txt" 2>&1; L=$?
say "快车道 rc=$L（0=全绿 2=前置坏 3=有真红 1=清单没跑齐）绿=$(grep -c 'LANE GREEN' "build/r${NN}_lane_after.txt") 红=$(grep -c 'LANE RED' "build/r${NN}_lane_after.txt")"

say "顶层台架 tb_v98_top_seam（约 100 分钟，链子里唯一在跑的 xsim，一轮只付这一次）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; R=$?
say "顶层台架 rc=$R（3=判红 0=绿；C5c 与新增的 C12a/b/c 读数在同一份 log 里）"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"

bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "边缘条带台架 rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# 门禁：先 /tmp，跑完再 cp 到位（D1b/D1c 读的就是这份，边写边读会读到截断的 —— #229）
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G —— 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt") 末行：$(tail -1 "build/r${NN}_gates.txt" | cut -c1-100 | iconv -f UTF-8 -t UTF-8//IGNORE)"
say "链结束（采纳、首页 24 项改口、刷板与文档同步都要人先看 r${NN}_lane_after / r${NN}_clk01_probe / 门禁之后再判）"

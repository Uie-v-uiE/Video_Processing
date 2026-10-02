#!/usr/bin/env bash
# build/r107_chain.sh —— r107 这一轮（只带 frame_reasm 分组这一刀）：构建 → 只读时序探针 →
# 顶层台架 + 报告 → 边缘条带台架 + 报告 → 门禁 → 扇出/走线判据落文件。
#
# 这一版把上一程踩过的三脚都写进来了：
#   ① 门禁**先落 /tmp 再 cp 到位**（gates.sh 文件头 15-18 行早就写了这个姿势；上一轮我把 stdout
#      直接重定向进它自己要读的那份基准件，第一跑读到被截断的文件 ⇒ D1c 判不了，#229）；
#   ② 台架一次只跑一支、且链子里不并发（#173：我同时跑复查批把链子里两步挡成 rc=2）；
#   ③ 构建在飞期间不许动 src/rtl —— 这条链跑完之前我只做只读与文档侧的事。
# 判据（#121 定的那条 + #175 写死的口径）：**这一族的 route 占比降没降、那根使能网络的 fo 从 316
# 掉到多少**；绝对 WNS 的差值不作为收益或损失（规矩 35）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
NN=107
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

say "构建开始（只带 frame_reasm 分组这一刀）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }
say "构建完成，开始只读时序探针"

"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  \
    > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl \
    > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"

# 扇出/走线判据：最差一族的前几条路径 + 每条里最贵的几根网络（fo 与 route 占比一起看）
{
  echo "# r107 扇出刀判据（#121/#175）：看这一族的 route 占比与那根使能网络的 fo，不看绝对 WNS 差值"
  echo "## crit_paths.txt 前 10 条"
  sed -n '1,12p' build/crit_paths.txt
  echo "## 全局读数（timing_summary Design Timing Summary）"
  awk '/Design Timing Summary/{f=1} f&&/^ *-?[0-9.]+ +[0-9.]/{print; exit}' build/timing_summary.rpt
  echo "## 最差那条路的 logic/route 分配与逐网络走线（fo= 就是扇出）"
  awk '/Slack \(MET\)/{c++} c==1{print} c==2{exit}' build/setup_paths.rpt \
      | grep -E "Data Path Delay|Logic Levels|fo=[0-9]+, routed" | head -14
} > "build/r${NN}_fanout_verdict.txt" 2>&1
say "扇出判据落 build/r${NN}_fanout_verdict.txt"

say "顶层台架（约 100 分钟，链子里唯一在跑的 xsim）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; R=$?
say "顶层台架 rc=$R（3=判红 0=绿；C8c 八档读数在同一份 log 里）"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"

bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "边缘条带台架 rc=$?"
ROUND=$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# 门禁：两步。先 /tmp，跑完再 cp 到位（D1b/D1c 读的就是这份，边写边读会读到截断的）
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G —— 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt") 末行：$(tail -1 "build/r${NN}_gates.txt" | cut -c1-100 | iconv -f UTF-8 -t UTF-8//IGNORE)"
say "链结束（采纳与文档同步要人看 build/r${NN}_fanout_verdict.txt 与门禁之后再做）"

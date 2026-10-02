#!/usr/bin/env bash
# build/r108_chain.sh —— r108 这一轮（只带 icmp_tx 的 IP 首部校验和拆两拍这一刀）。
# 形状照 build/r107_chain.sh（那三脚已经踩过：门禁两步落盘、台架不并发、构建期不动 src/rtl）。
#
# 两条与 r107 不同的地方：
#   ① 门口先验"树上确实有这一刀"（build/r108_apply_csum.mjs --check 过 + cnt == 5'd4 在），
#      否则直接断链 —— 防的是"报了 r108 的数其实建的还是 r107 的树"（规矩 42：先只读执行再说）。
#   ② 判据用 build/tcl/probe_cone_slack.tcl 量**同一个锥的两端**（ip_head_reg[*] -> check_buffer_reg[*]）
#      在改前/改后各是多少；这一步必须在构建**之前**把基线落盘（构建会覆盖 system_top_routed.dcp），
#      所以基线由人先在 r107 的 DCP 上跑一次，本链只跑"改后"那一半并把两份并排打出来。
#   绝对 WNS 的差值仍不作为收益或损失（规矩 35）；能写的是这个锥的级数、logic/route 分配与它的 slack。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
NN=108
say() { printf '[chain %s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---- 0. 门口守卫：这一刀必须在树上，且基线探针必须已经落盘 ----
node build/r108_apply_csum.mjs --check > "/tmp/kx/r108_check.txt" 2>&1 \
    || { say "断链：apply --check 没过（/tmp/kx/r108_check.txt）—— 树上不是这一刀"; exit 1; }
grep -q "cnt == 5'd4" src/rtl/eth/icmp_tx.v \
    || { say "断链：src/rtl/eth/icmp_tx.v 里没有拆开的第 4 拍"; exit 1; }
[ -f build/r${NN}_cone_before.txt ] \
    || { say "断链：没有 build/r${NN}_cone_before.txt（改前基线要在构建前、在上一版 DCP 上先跑出来）"; exit 1; }
md5sum src/rtl/eth/icmp_tx.v src/rtl/eth/frame_reasm.v | sed 's/^/  树指纹：/'
say "守卫通过，开始构建（只带 icmp_tx 校验和拆两拍这一刀）"

# ---- 1. 构建 ----
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/build_system_axigpio.tcl \
    > "build/r${NN}_build_console.txt" 2>&1; B=$?
grep -q "SYSTEM BUILD DONE" "build/r${NN}_build_console.txt" \
    || { say "构建没跑完（rc=$B，日志 build/r${NN}_build_console.txt）—— 断链，不产凭据"; exit 1; }
grep -q "^VIVADO_EXIT=[1-9]" "build/r${NN}_build_console.txt" \
    && { say "Vivado 退出码非 0 —— 断链，不产凭据"; exit 1; }
say "构建完成，开始只读时序探针"

# ---- 2. 只读探针：报告 + 同一个锥的两端 ----
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/crit_path.tcl  \
    > "build/r${NN}_critpath_console.txt" 2>&1; say "crit_path rc=$?"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/hold_paths.tcl \
    > "build/r${NN}_holdpath_console.txt" 2>&1; say "hold_paths rc=$?"
VP_LABEL=r108a VP_FROM=u_eth/u_icmp/u_icmp_tx/ip_head_reg* \
VP_TO=u_eth/u_icmp/u_icmp_tx/check_buffer_reg* \
    "$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_cone_slack.tcl \
    > "build/r${NN}_cone_after.txt" 2>&1; say "锥探针（改后）rc=$? -> build/r${NN}_cone_after.txt"
{ echo "# r108 锥级对账：同一个锥（ip_head_reg[*] -> check_buffer_reg[*]）改前 / 改后各是多少"
  echo "## 改前（在 r107 的 routed DCP 上跑的基线）"
  grep -aE "^(LABEL|SETS|PATHS|  (Slack|Source|Destination|Data Path Delay|Logic Levels))" "build/r${NN}_cone_before.txt"
  echo "## 改后（本轮构建出的 routed DCP）"
  grep -aE "^(LABEL|SETS|PATHS|  (Slack|Source|Destination|Data Path Delay|Logic Levels))" "build/r${NN}_cone_after.txt"
} > "build/r${NN}_cone_verdict.txt" 2>&1
say "锥级对账落 build/r${NN}_cone_verdict.txt"

# ---- 3. 扇出/走线判据（照 r107 那三段）----
{
  echo "# r108 校验和刀判据（#178）：看这个锥自己的级数与 logic/route 分配，不看绝对 WNS 差值"
  echo "## crit_paths.txt 前 12 行"
  sed -n '1,12p' build/crit_paths.txt
  echo "## 全局读数（timing_summary Design Timing Summary）"
  awk '/Design Timing Summary/{f=1} f&&/^ *-?[0-9.]+ +[0-9.]/{print; exit}' build/timing_summary.rpt
  echo "## 最差那条路的 logic/route 分配与逐网络走线"
  awk '/Slack \(MET\)/{c++} c==1{print} c==2{exit}' build/setup_paths.rpt \
      | grep -E "Data Path Delay|Logic Levels|fo=[0-9]+, routed" | head -14
} > "build/r${NN}_fanout_verdict.txt" 2>&1
say "扇出判据落 build/r${NN}_fanout_verdict.txt"

# ---- 4. 台架（一次一支，链子里不并发）----
say "顶层台架（约 100 分钟，链子里唯一在跑的 xsim）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; R=$?
say "顶层台架 rc=$R（3=判红 0=绿）"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"
# 这一刀的收/发两端都要过：ICMP 应答器的台架 + 收包链
bash sim/run_one.sh tb_icmp_ping0 > "build/r${NN}_bench_tb_icmp_ping0.txt" 2>&1; say "tb_icmp_ping0 rc=$?"
bash sim/run_one.sh tb_v795_rx_chain > "build/r${NN}_bench_tb_v795_rx_chain.txt" 2>&1; say "tb_v795_rx_chain rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "边缘条带台架 rc=$?"
ROUND=r$NN bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# ---- 5. 门禁：两步（先 /tmp 再 cp，D1b/D1c 读的就是这份）----
bash build/gates.sh > "/tmp/kx/g_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G —— 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt") 末行：$(tail -1 "build/r${NN}_gates.txt" | cut -c1-100 | iconv -f UTF-8 -t UTF-8//IGNORE)"
say "链结束（采纳与文档同步要人看 build/r${NN}_cone_verdict.txt 与门禁之后再做）"

#!/usr/bin/env bash
# build/r108_stage2.sh —— 把 r108 链子里被 rc=2 顶掉的那几步重跑一遍。
# 根因：链子是从 nohup 的壳里起来的，VP_VIVADO_BIN 没导出 ⇒ sim/run_one.sh 报「找不到 xvlog」，
# 于是 tb_v98 / tb_icmp_ping0 / tb_v795_rx_chain / tb_edge_rim 全部 REFUSE（构建与只读探针不受影响，
# 它们的锥级 A/B 已经落盘）。两条链子脚本现在都自带 export，这条是补当轮的账。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_VIVADO_BIN="$V"
NN=108
say() { printf '[stage2 %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -d "$V" ] || { say "断链：没有 $V"; exit 1; }
tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe" && { say "断链：已经有 xsim 在跑（它会写同一份 run.log）"; exit 1; }

say "顶层台架（约 100 分钟）"
bash sim/run_one.sh tb_v98_top_seam > "build/r${NN}_tb98_console.txt" 2>&1; R=$?
say "tb_v98 rc=$R（0=绿 3=判红 2=REFUSE 1=编译失败 4=不认形状）"
bash build/tb98_report.sh > "build/r${NN}_tb98report_console.txt" 2>&1; say "tb98_report rc=$?"

bash sim/run_one.sh tb_icmp_ping0 > "build/r${NN}_bench_tb_icmp_ping0.txt" 2>&1; say "tb_icmp_ping0 rc=$?"
bash sim/run_one.sh tb_v795_rx_chain > "build/r${NN}_bench_tb_v795_rx_chain.txt" 2>&1; say "tb_v795_rx_chain rc=$?"
bash sim/run_one.sh tb_udp_reasm > "build/r${NN}_bench_tb_udp_reasm.txt" 2>&1; say "tb_udp_reasm rc=$?"
bash sim/run_one.sh tb_edge_rim > "build/r${NN}_rim_console.txt" 2>&1; say "tb_edge_rim rc=$?"
ROUND=r${NN} bash build/rim_report.sh > "build/r${NN}_rimreport_console.txt" 2>&1; say "rim_report rc=$?"

# 门禁两步：先 /tmp 再 cp（D1c 读的就是这份基准件）。文档还没同步，第一跑预期会带 2 条文档红。
bash build/gates.sh > "/tmp/kx/g1_r${NN}.txt" 2>&1; G=$?
cp -f "/tmp/kx/g1_r${NN}.txt" "build/r${NN}_gates.txt"
say "门禁 rc=$G 绿=$(grep -c ' PASS$' "build/r${NN}_gates.txt") 红=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")"
say "stage2 结束（采纳段自己会等这个标记）"

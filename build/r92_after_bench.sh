#!/bin/bash
# build/r92_after_bench.sh —— 等 `tb_v98` 那一跑结束，然后自动出**这一版**的门禁报告。
#
# 为什么要它：门禁第 15/16 项认的是"与当前 `src/rtl` 同一次跑"的台架报告（#88 立的规矩），
# 而 `tb_v98` 这一跑在 r92 之后要 1~2 小时。人不可能守着看，所以把"等完→出报告→跑门禁"
# 这一步交给脚本，但**只让它写报告，不做采纳决定**：红项与是否刷板仍由人读那一行来判。
#
# 跑法：nohup bash build/r92_after_bench.sh > build/r92_after_bench.log 2>&1 &
set -u
cd "$(dirname "$0")/.." || exit 1
say() { echo "[after $(date '+%F %H:%M:%S')] $*"; }
die() { say "STOP: $*"; exit 1; }

[ -n "${VP_VIVADO_BIN:-}" ] || die "没设 VP_VIVADO_BIN（门禁里的台架项要 xvlog）"
[ -f build/r92_bench_chain.log ] || die "build/r92_bench_chain.log 不在，链根本没起"

n=0
while ! grep -q "BENCH CHAIN DONE" build/r92_bench_chain.log; do
    sleep 30; n=$((n + 1))
    [ $((n % 20)) -eq 0 ] && say "还在跑：已等 $((n / 2)) 分钟，tb_v98 判据行数=$(grep -acE '^(PASS|FAIL)' /tmp/kx/tb_v98_top_seam.run/run.log 2>/dev/null)"
    [ $n -gt 400 ] && die "等了 3 小时 20 分还没结束，不产出（看 build/r92_bench_chain.log）"
done
say "台架链结束，先看两份报告本身"
grep -aE "RESULT|rtl=" build/tb_edge_rim_r92.txt 2>/dev/null | tail -2
grep -aE "^FAIL|RESULT" build/tb_v98_report.txt 2>/dev/null | tail -3
# 门禁用的是 xsim 之外的只读检查 + 报告核对；确认没有活的 xsim 再跑，免得两份日志混一起
tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe" && die "还有活的 xsim，门禁先不跑（规矩：一份 run.log 只许一个写者）"
bash build/gates.sh > build/r92_gates.txt 2>&1
rc=$?
say "门禁退出码 rc=$rc（报告 build/r92_gates.txt）"
tail -3 build/r92_gates.txt
say "DONE —— 只出报告，不代替人做采纳与刷板决定"

#!/bin/bash
# build/r94_bench_chain.sh —— r94 这一版的台架链：整屏（tb_v98）→ 边缘条带（tb_edge_rim）→ 门禁。
# 与 r92 那份同形（那是被验证过的脚手架，不重造），差别只有两处：
#   ① 这一轮不必再等"构建是否结束"（构建已在 12:53 出 bit，见 build/r94_build_console.txt）；
#   ② 结束后把 gates 的退出码与红项数一起打在日志最后一行，方便只读一行就判。
# ⚠ 只做"跑 + 出报告"，**不做采纳决定**：红项与是否刷板仍由人读那一行来判（本项目的规矩）。
set -u
cd "$(dirname "$0")/.." || exit 1
# ⚠ #179：`build/rim_report.sh` 的输出名是 `tb_edge_rim_r${ROUND}.txt`，而它**自带默认值 ROUND=r90**。
#   今天这条链第②步调它的时候没给 ROUND ⇒ r94 那一跑的内容被写成了"r90 的凭据"，
#   而门禁第 16 项按 `sort -V | tail -1` 取到的是 r92 那份 ⇒ 红在"报告与树不同源"。
#   红得对，但那一句说的是我的链，不是设计。⇒ 轮次号必须由调用方给，脚本末尾还要断言件真的留下了。
ROUND=${ROUND:-REFUSE}
[ "$ROUND" = REFUSE ] && { echo "STOP: 必须给 ROUND=rNN（不给就会落到 rim_report.sh 的默认标签上 —— #179）"; exit 1; }
say() { echo "[chain $(date '+%F %H:%M:%S')] $*"; }
die() { say "STOP: $*"; exit 1; }
[ -n "${VP_VIVADO_BIN:-}" ] || die "没设 VP_VIVADO_BIN"
# 规矩：一份 run.log 只许一个写者；有活的 xsim 就先停下（TaskStop 会留下孤儿 xsim/xsimk）
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    die "还有活的 xsim.exe，先清掉再起链"
fi

say "① tb_v98_top_seam（整屏逐像素 + 旋转维度，这一跑 1~2 小时）"
bash sim/run_one.sh tb_v98_top_seam > build/r94_tb_v98_console.txt 2>&1 || die "tb_v98 跑失败（看 build/r94_tb_v98_console.txt）"
bash build/tb98_report.sh > build/r94_tb98_report_step.txt 2>&1 || say "tb98_report.sh 退出码非 0（红项本来就会让它非 0，不当作链断）"

say "② tb_edge_rim（边缘条带那一族）"
bash sim/run_one.sh tb_edge_rim > build/r94_edge_rim_console.txt 2>&1 || die "tb_edge_rim 跑失败"
ROUND=$ROUND bash build/rim_report.sh > build/r94_rim_report_step.txt 2>&1 || say "rim_report.sh 退出码非 0"
# ⚠ #179 的另一半：**跑了不等于留了件**。断言本轮那份件在盘上、且它的 rtl_md5 就是当前树 ——
#   不相符就说"链没留件"（CHAIN_MISSING_ARTIFACT）并退出非零，别让"没留件"长得像"台架红"。
RTLNOW=$(find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
RIMFILE=build/tb_edge_rim_${ROUND}.txt
[ -f "$RIMFILE" ] || { say "CHAIN_MISSING_ARTIFACT：$RIMFILE 不在盘上（rim_report.sh 没写成 / ROUND 给错）"; exit 1; }
RIMRTL=$(sed -n 's/^rtl_md5=\([0-9a-f]*\).*/\1/p' "$RIMFILE" | head -1)
[ "$RIMRTL" = "$RTLNOW" ] || { say "CHAIN_MISSING_ARTIFACT：$RIMFILE 的 rtl_md5=$RIMRTL != 当前树 $RTLNOW"; exit 1; }
say "② 凭据就位：$RIMFILE rtl_md5=$RIMRTL（= 当前树）"

say "③ 门禁（20 项）"
bash build/gates.sh > build/r94_gates.txt 2>&1
rc=$?
say "门禁退出码 rc=$rc"
grep -aE "^ *\[红\]|红项|GATES" build/r94_gates.txt | tail -6
say "BENCH CHAIN DONE"

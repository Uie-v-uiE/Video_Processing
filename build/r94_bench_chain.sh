#!/bin/bash
# build/r94_bench_chain.sh —— 台架链：模块级快台架 → 整屏（tb_v98）→ 边缘条带（tb_edge_rim）→ 门禁。
# 名字里的 r94 是**出生轮**（文件名不改，改会让交付文档那一堆引用跟着动），
# 产物名从 r96 起一律由 `ROUND` 派生（`build/${ROUND}_*.txt`）—— 上一版把 r96 那一跑也写进
# `build/r94_*` 的话，"凭据属于哪一版"就只剩靠人记住了（#179 是同一族的教训）。
# 与 r92 那份同形（那是被验证过的脚手架，不重造），差别只有两处：
#   ① 不必再等"构建是否结束"（构建已在 12:53 出 bit，见 build/r94_build_console.txt）；
#   ② 结束后把 gates 的退出码与红项数一起打在日志最后一行，方便只读一行就判。
# ⚠ 只做"跑 + 出报告"，**不做采纳决定**：红项与是否刷板仍由人读那一行来判（本项目的规矩）。
set -u
cd "$(dirname "$0")/.." || exit 1
# ⚠ #179：`build/rim_report.sh` 的输出名是 `tb_edge_rim_${ROUND}.txt`，而它**自带默认值 ROUND=r90**。
#   今天这条链第②步调它的时候没给 ROUND ⇒ r94 那一跑的内容被写成了"r90 的凭据"，
#   而门禁第 16 项按 `sort -V | tail -1` 取到的是 r92 那份 ⇒ 红在"报告与树不同源"。
#   红得对，但那一句说的是我的链，不是设计。⇒ 轮次号必须由调用方给，脚本末尾还要断言件真的留下了。
# ⚠ ROUND 带 `r` 前缀（`ROUND=r96`），因为 rim_report.sh 的默认值就是 `r90` 这个形状。
ROUND=${ROUND:-REFUSE}
[ "$ROUND" = REFUSE ] && { echo "STOP: 必须给 ROUND=rNN（不给就会落到 rim_report.sh 的默认标签上 —— #179）"; exit 1; }
say() { echo "[chain $(date '+%F %H:%M:%S')] $*"; }
die() { say "STOP: $*"; exit 1; }
[ -n "${VP_VIVADO_BIN:-}" ] || die "没设 VP_VIVADO_BIN"
# 规矩：一份 run.log 只许一个写者；有活的 xsim 就先停下（TaskStop 会留下孤儿 xsim/xsimk）
if tasklist //FI "IMAGENAME eq xsim.exe" 2>/dev/null | grep -qi "xsim.exe"; then
    die "还有活的 xsim.exe，先清掉再起链"
fi
# ⚠ 链必须在**构建结束之后**起：台架读的是当前 src/rtl，而第③步门禁读 `build/` 里的
#   timing/methodology 报告 —— 构建没落地就起链，那一轮的 gates 里装的是上一轮的数。
#   `gates.sh:46` 会 WARN"有 RTL 源比 system.bit 新"，但"WARN 着把 rNN 的凭据写出来"正是 #179 的形状。
NEWER=$(find src/rtl -name '*.v' -newer build/system.bit 2>/dev/null | head -3)
[ -n "$NEWER" ] && die "build/system.bit 不比 RTL 新，构建还没落地：$(echo $NEWER | tr '\n' ' ')（等 SYSTEM BUILD DONE 再起链）"

# ⓪ 模块级快台架（秒级）：#170/#171/#174/#176 这几把尺子从落地起就只有"我今天手动跑过一次"这个凭据，
#     没有复跑机制就会烂在 sim/ 里（#103 那一族"判据没有牙"的另一半）。链里最便宜的一步先跑，
#     后面的整屏要跑 1~2 小时，不该被一把快尺子拖住。
say "⓪ 模块级台架（tb_writer_abort / tb_commit_strobe / tb_v94_zoom_sel / tb_src_arb_why）"
for TB in tb_writer_abort tb_commit_strobe tb_v94_zoom_sel tb_src_arb_why; do
    bash build/sim/run_one.sh "$TB" > "build/${ROUND}_${TB}_console.txt" 2>&1; RC0=$?
    case $RC0 in
      0) say "   $TB 绿";;
      3) say "   $TB 判红（rc=3）—— 不断链；读 build/${ROUND}_${TB}_console.txt 的 FAIL 行";;
      *) die "   $TB 没跑成（rc=$RC0，看 build/${ROUND}_${TB}_console.txt）";;
    esac
done

say "① tb_v98_top_seam（整屏逐像素 + 旋转维度，这一跑 1~2 小时）"
# ⚠ #166 之后 `build/sim/run_one.sh` **用退出码表达判定**：0 绿 / 1 编译或例化失败 / 2 REFUSE /
#   3 判红 / 4 认不出判定行。链只在 1/2/4 断；**3 不断链** —— 红是这一轮要的结论
#   （`C5c`/#98 那条从 r77 起就故意留着，让"唯一剩下的红"永远是同一条），
#   把它当"链断了"来处理等于把结论当成故障。
bash build/sim/run_one.sh tb_v98_top_seam > build/${ROUND}_tb_v98_console.txt 2>&1; RC1=$?
case $RC1 in
  0) say "① 绿";;
  3) say "① 判红（rc=3）—— 不断链，红项交给第③步门禁记账（读 build/${ROUND}_tb_v98_console.txt 里的 FAIL 行）";;
  *) die "① 没跑成（rc=$RC1，看 build/${ROUND}_tb_v98_console.txt）";;
esac
bash build/tb98_report.sh > build/${ROUND}_tb98_report_step.txt 2>&1 || say "tb98_report.sh 退出码非 0（红项本来就会让它非 0，不当作链断）"

say "② tb_edge_rim（边缘条带那一族）"
bash build/sim/run_one.sh tb_edge_rim > build/${ROUND}_edge_rim_console.txt 2>&1; RC2=$?
case $RC2 in
  0) say "② 绿";;
  3) say "② 判红（rc=3）—— 不断链，交给第③步门禁记账";;
  *) die "② 没跑成（rc=$RC2，看 build/${ROUND}_edge_rim_console.txt）";;
esac
ROUND=$ROUND bash build/rim_report.sh > build/${ROUND}_rim_report_step.txt 2>&1 || say "rim_report.sh 退出码非 0"
# ⚠ #179 的另一半：**跑了不等于留了件**。断言本轮那份件在盘上、且它的 rtl_md5 就是当前树 ——
#   不相符就说"链没留件"（CHAIN_MISSING_ARTIFACT）并退出非零，别让"没留件"长得像"台架红"。
RTLNOW=$(find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
RIMFILE=build/tb_edge_rim_${ROUND}.txt
[ -f "$RIMFILE" ] || { say "CHAIN_MISSING_ARTIFACT：$RIMFILE 不在盘上（rim_report.sh 没写成 / ROUND 给错）"; exit 1; }
RIMRTL=$(sed -n 's/^rtl_md5=\([0-9a-f]*\).*/\1/p' "$RIMFILE" | head -1)
[ "$RIMRTL" = "$RTLNOW" ] || { say "CHAIN_MISSING_ARTIFACT：$RIMFILE 的 rtl_md5=$RIMRTL != 当前树 $RTLNOW"; exit 1; }
say "② 凭据就位：$RIMFILE rtl_md5=$RIMRTL（= 当前树）"

say "③ 门禁（20 项）"
bash build/gates.sh > build/${ROUND}_gates.txt 2>&1
rc=$?
say "门禁退出码 rc=$rc"
grep -aE "^ *\[红\]|红项|GATES" build/${ROUND}_gates.txt | tail -6
say "BENCH CHAIN DONE"

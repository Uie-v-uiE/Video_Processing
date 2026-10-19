#!/usr/bin/env bash
# build/r132_after.sh —— 主链子落地之后的三件收尾（都只读，不起构建）：
#   1) 现版本自己的 check_timing -verbose（名册表 io_unconstrained_ports 那列唯一缺的输入件）
#   2) 由它 + 现版 timing_summary 生成 build/roster/roster_r132.tsv，并与冻结的 r118 表相减
#   3) 臂 D：逐脚 clock-to-pin 离散 + 新尺子的红能力自证
# 为什么要排成一条：这三件都要占 Vivado 或 CPU，主链子在飞的时候插进去会把读数挤成半件。
set -u
cd "$(dirname "$0")/.." || exit 1
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}
LOG=build/r132_after.log
say(){ printf '[r132after %s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then say "REFUSE: 还有 Vivado 在飞"; exit 2; fi
if tasklist 2>/dev/null | grep -qiE "^xsimk?\.exe"; then say "REFUSE: 台架 xsim 还在跑"; exit 2; fi

say "1) check_timing -verbose（现版 routed dcp，只读）"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/probe_check_timing.tcl >> "$LOG" 2>&1
p1=$?
say "   probe rc=$p1 件=$(wc -c < build/evidence/r132_check_timing_verbose.txt 2>/dev/null) 字节 HIGH=$(grep -ac 'HIGH' build/evidence/r132_check_timing_verbose.txt 2>/dev/null) 正文两句=$(grep -acE 'There are [0-9]+ (input|output) ports' build/evidence/r132_check_timing_verbose.txt 2>/dev/null)"

say "2) roster_r132.tsv（输入=build/timing_summary.rpt + 上面那份 check_timing）"
python build/r115_roster_build.py build/timing_summary.rpt \
       build/evidence/r132_check_timing_verbose.txt build/roster/roster_r132.tsv r132 >> "$LOG" 2>&1
p2=$?
say "   生成 rc=$p2 行数=$(grep -acv '^#' build/roster/roster_r132.tsv 2>/dev/null)"
python build/r115_roster_build.py --diff build/roster/roster_r118.tsv \
       build/roster/roster_r132.tsv > build/evidence/r132_roster_tsv_diff.txt 2>&1
p3=$?
say "   对 r118 相减 rc=$p3 判定行=$(grep -acE 'ROSTER|DIFF|G[0-9]|PASS|FAIL|NOT_MEASURED' build/evidence/r132_roster_tsv_diff.txt) 收尾=$(grep -ac 'ROSTERDIFF-SUMMARY' build/evidence/r132_roster_tsv_diff.txt) 读到的 verdict=$(grep -ao 'verdict=[A-Z]*' build/evidence/r132_roster_tsv_diff.txt | tail -1)"
# 相减这把尺子的 rc=1 意思是"判红"，不是"没跑成"：只要它打出 SUMMARY 行，就算量到了。
# 把红当成失败会让这条链每次真出结论时都假装失败；反过来把没跑成当成就更糟。
if [ "$p3" != 0 ] && [ "$(grep -ac 'ROSTERDIFF-SUMMARY' build/evidence/r132_roster_tsv_diff.txt)" = 0 ]; then
  say "   相减既没红也没绿：没有 SUMMARY 行 ⇒ 这一件算没量到"; p3=9
fi

say "3) 臂 D：逐脚 clock-to-pin 离散 + 尺子自证"
bash build/r132_arm_d.sh >> "$LOG" 2>&1
p4=$?
say "   armD rc=$p4"
say "三件收尾结束。判定要逐格念 r132_roster_tsv_diff.txt 与 r132_arm_d_verdict.txt，别只看 rc。"
# 上一版这里直接 exit 0，结果 1) 写出一份 196 字节的空正文、2) ROSTERFAIL 而链子照样"成功"——
# 静默的"跑过了"是最坏的一种假绿，所以这一步现在逐件判：任何一件不是 0 就以非零收尾。
FAILS=0
for pair in "1p-checktiming:$p1" "2p-roster-build:$p2" "3p-roster-diff:$p3" "4p-armD:$p4"; do
  k=${pair#*:}; n=${pair%%:*}
  [ "$k" = 0 ] || { echo "STEP NOT PROVEN: $n rc=$k"; FAILS=$((FAILS+1)); }
done
[ "$FAILS" = 0 ] || { say "$FAILS 件没量到 —— 收尾链以非零码结束"; exit 1; }
exit 0

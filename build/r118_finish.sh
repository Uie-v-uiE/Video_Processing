#!/usr/bin/env bash
# build/r118_finish.sh —— r118 的收尾：刷板 → 改口 → 最终门禁两跑 → 重导提交包 → 提交并推送。
#
# 为什么要有这一支、而不是让链子自己判采纳：链子那一次门禁是 **3 条红**——
#   1 条是声明过的 C5c（顶层台架），另外 2 条是**文档时效**（doc_cur / metric）：
#   首页还写着 r116 的数，而盘上的报告已经是 r118 的了。
#   发布判据 B4 说的是"非文档类的设计红"，不是"文档还没跟上"。
#   ⇒ 顺序必须是：先用 r118 位流把板子刷过并复验，再改口，再用**改口之后的门禁**当交付件。
#   链子在 04:43 被我停在这里（它按红数=3 会回刷 r114，那是把"文档没改完"误读成"设计判负"）。
#
# 每一步的"不过"都是硬停：板侧没过不改口；改口没过三道尺子不跑最终门禁；
# 最终门禁不是"1 红且两跑逐字节一致"就不提交、不重导包后的提交动作。
set -u
cd "$(dirname "$0")/.."
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
D=build/evidence/r118_board
mkdir -p "$D" build/evidence/r118_bit
say(){ printf '[fin %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a build/r118_finish_console.txt; }

BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
[ -s "$BIT" ] || { say "停：没有 r118 位流（不猜）"; exit 2; }
cp -f "$BIT" build/evidence/r118_bit/system.bit
md5sum "$BIT" | cut -c1-12 > build/evidence/r118_bit/md5.txt
XSA=$(ls -1 vivado_system/zynq_video_sys.runs/impl_1/*.xsa 2>/dev/null | head -1)
if [ -n "$XSA" ]; then cp -f "$XSA" build/evidence/r118_bit/system.xsa; fi
say "r118 位流已存档 md5=$(cat build/evidence/r118_bit/md5.txt)；起飞：三步 JTAG 刷板 + 50 s 真实流量 + 两次健康读数"

bash build/r116_bit_cycle.sh r118build build/evidence/r118_bit/system.bit > "$D/bitcycle_console.txt" 2>&1
RC=$?
bash build/board_verify.sh --geom --battery --round=r118 > "$D/board_verify_console.txt" 2>&1
BV=$?
{
  printf "板上现在 = r118（刷入 %s，bit_cycle rc=%s board_verify rc=%s）\n" "$(date "+%F %T")" "$RC" "$BV"
  printf "B1 严格名册：%s\n" "$(grep -a "^B1 pairs_compared" build/evidence/r118_strict_b1.txt)"
  printf "刷板前那一次门禁：绿=%s 红=%s（其中 2 条是文档时效，改口后由最终两跑复验）\n" \
     "$(grep -c " PASS$" build/r118_gates.txt)" "$(grep -c " FAIL$" build/r118_gates.txt)"
} > "$D/BOARD_NOW.txt"
say "bit_cycle rc=$RC board_verify rc=$BV；件 $D/BOARD_NOW.txt"
if [ "$RC" != 0 ] || [ "$BV" != 0 ]; then say "停：板侧没过——不带着未复验的板改口"; exit 3; fi

say "改口：首页/英文首页/metrics 从件里取数；写进文档的门禁读数 = 24 项 23 绿 / 1 红，由下面的最终两跑验证（不符则 D1c 自己判红）"
VP_CLAIM=24,23,1 python build/r118_rotate.py > "$D/rotate_console.txt" 2>&1
ROT=$?
say "rotate rc=$ROT $(grep -a "ROTATE-APPLY\|MARKER\|CLAIM\|BOARD-SIDE" "$D/rotate_console.txt" | tr "\n" " ")"
if [ "$ROT" != 0 ]; then say "停：改口没过三道尺子（件 $D/rotate_console.txt）；不跑最终门禁、不提交"; exit 4; fi

say "最终门禁两跑"
bash build/gates.sh > /tmp/kx/g_r118F.txt 2>&1
A=$?
bash build/gates.sh > /tmp/kx/g_r118F2.txt 2>&1
B=$?
if cmp -s /tmp/kx/g_r118F.txt /tmp/kx/g_r118F2.txt; then ID=identical; else ID=different; fi
cp -f /tmp/kx/g_r118F.txt build/r118_gates_final.txt
G=$(grep -c " PASS$" build/r118_gates_final.txt)
RED=$(grep -c " FAIL$" build/r118_gates_final.txt)
say "最终门禁 绿=$G 红=$RED 两跑=$ID rcA=$A rcB=$B"
say "红项清单：$(grep -a " FAIL$" build/r118_gates_final.txt | tr "\n" "|")"

say "重导提交包"
bash build/make_submission.sh > /tmp/kx/sub_r118.txt 2>&1
S=$?
say "make_submission rc=$S 盘上文件数=$(find ../submission -type f 2>/dev/null | wc -l)"

if [ "$RED" = 1 ] && [ "$ID" = identical ] && [ "$S" = 0 ]; then
    say "条件满足：落提交并推送"
    python build/r118_commit.py
    for i in 1 2 3 4 5 6 7 8; do
        if git push origin main > /tmp/p6.log 2>&1; then say "PUSH-OK try=$i"; break; fi
        say "push try=$i 失败：$(tail -1 /tmp/p6.log)"
        sleep 40
    done
    say "$(git status -sb | head -1)"
else
    say "不提交：最终门禁红数不是 1、或两跑不一致、或提交包导出失败——交回人判断"
fi
say "FINISH END"

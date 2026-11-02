#!/bin/bash
# 用途：链子跑完后，把"刀 4① 到底有没有抓手"这一条**机械化**读出来并落一份件
# 输入：命令行参数
# 输出：stdout
# 退出码：2=非 0 分支（该文件 exit 2 那一行）
# build/r110_verdict.sh —— 链子跑完后，把"刀 4① 到底有没有抓手"这一条**机械化**读出来并落一份件
# 只读：不写 src/rtl、不动 sim、不跑 xsim/vivado，只对已生成的报告做 grep。
# 判据（写死在这里，不许迁就结果）：
#   基线 = build/evidence/r109_setup_paths_baseline.rpt（r109 原件的逐字节副本）
#   本轮 = build/setup_paths.rpt（r110 构建覆盖后的那份）
#   看两件事：① 终点是 rows_hit_*[/CE] 的那族里，**最后一跳驱动网的 fo** 与 ② 该条路径的 Data Path Delay/route 占比。
#   fo 从 316 降下来（且不是靠把路径挪到别的族去）⇒ 有抓手；仍是 316 ⇒ 综合把独热又折回广播网，回退刀 4。
cd "$(dirname "$0")/.." || exit 2
NEW=build/setup_paths.rpt
OLD=build/evidence/r109_setup_paths_baseline.rpt
OUT=build/r110_verdict.txt
[ -f "$NEW" ] || { echo "REFUSE: 没有 $NEW（链子还没跑完？）"; exit 2; }
[ -f "$OLD" ] || { echo "REFUSE: 基线件 $OLD 不在，无法比"; exit 2; }
{
  echo "== r110 刀 4① 抓手判读 $(date '+%F %H:%M:%S') =="
  echo "基线件 $OLD md5=$(md5sum "$OLD" | cut -c1-12)   本轮件 $NEW md5=$(md5sum "$NEW" | cut -c1-12)"
  for f in "$OLD" "$NEW"; do
    echo "---- $(basename "$f") ----"
    # 第一条 setup 路径的摘要 + 它最后三跳的网（fo 就在网的行上）
    awk '/^Slack \(/{c++} c==1{print} c==2{exit}' "$f" | grep -aE "^Slack|Source:|Destination:|Data Path Delay|Logic Levels" | cut -c1-118
    awk '/^Slack \(/{c++} c==1{print} c==2{exit}' "$f" | grep -a "net (fo=" | tail -3 | cut -c1-118
    echo "  全文件里 fo 最大的三根网（谁在广播一眼可见）："
    grep -ao "net (fo=[0-9]*" "$f" | sed 's/net (fo=//' | sort -rn | uniq -c | head -3 | sed 's/^/    fo=/'
    echo "  含 rows_hit 的 CE 终点出现次数：$(grep -ac "rows_hit_reg\[.*\]/CE" "$f")"
  done
  echo "== 结论口径（不猜，两条都要看）=="
  echo "  1) 上面「本轮件」的最后一条若仍是 fo=316 ⇒ 独热被综合折回广播网 ⇒ 回退 frame_reasm.v 那一刀；"
  echo "  2) fo 明显下降且 Data Path Delay/route 占比同降 ⇒ 有抓手，采纳时把这组数写进 metrics/首页；"
  echo "  3) 若最差族整个换人（终点不再是 rows_hit）⇒ 那是**归属变了**，首页的归属句要重写而不是换数字（规矩 46），"
  echo "     并且收益不能算在这一刀头上（规矩 35：绝对值差不是收益）。"
} > "$OUT" 2>&1
echo "写好了 $OUT"
iconv -f UTF-8 -t UTF-8//IGNORE < "$OUT" | tail -26

#!/bin/bash
# build/tb98_report.sh —— 把 tb_v98 的 console 收成门禁第 15 项要的凭据
#
#   bash build/tb98_report.sh [那份 run.log]        # 默认 /tmp/kx/tb_v98_top_seam.run/run.log
#
# 为什么要有"头部两枚 md5"这件事（2026-09-26，#92 修完顶层那天想的）：
#   `tb_v98_top_seam` 一次要跑 40+ 帧（八档缩放扫描）≈ 75 分钟，塞进"构建完就读"的门禁里
#   没有人会等 ⇒ 于是门禁第 1~14 项从来不含顶层台架，而 #88 的真实教训正是
#   **"gates 14/14 与唯一例化顶层的台架红了几天同时成立"**。
#   把这个缺口叫"跳过"还不够 —— 一份**上一版顶层**跑出来的 PASS 报告会伪装成今天的凭据。
#   所以报告的头部钉住 `pl_video_top.v` 与本台架各自的 md5，门禁拿树里的现值比：
#   对不上就是"改过顶层，这份不算数"（本仓的规矩：认 md5，不认文件名）。
set -u
ROOT=/d/Xilinx/Prj/pro/Video_Processing
SRC=${1:-/tmp/kx/tb_v98_top_seam.run/run.log}
OUT=$ROOT/build/tb_v98_report.txt
cd "$ROOT" || exit 2
[ -f "$SRC" ] || { echo "FATAL 读不到 $SRC"; exit 2; }
# 出处取自**跑的那天**留下的 `prov.txt`（由 `sim/run_one.sh` 在编译前写），不是现在树里的 md5：
# 事后算一遍再把指纹盖到旧日志上，正是这一项要防的那件事。
PROV=$(dirname "$SRC")/prov.txt
if [ -f "$PROV" ]; then
    TOP=$(sed -n 's/^top_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    TB=$(sed -n 's/^tb_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    RTL=$(sed -n 's/^rtl_md5=\(.*\)$/\1/p' "$PROV" | head -1)
    WHEN=$(sed -n 's/^date=\(.*\)$/\1/p' "$PROV" | head -1)
else
    TOP=UNKNOWN; TB=UNKNOWN; RTL=UNKNOWN; WHEN="无 prov.txt（这份 run 早于出处机制，或不是 run_one.sh 跑的）"
fi
{
    echo "# provenance top_md5=$TOP tb_md5=$TB rtl_md5=$RTL date=$WHEN src=$SRC"
    grep -a "^\(PASS \|FAIL \|RESULT \|C2 table\|C2 row\|C2BLK\|C2SHAPE\|C2IBAD\|C4 \|C4RUN \|C9\|P1 \|INFO \)" "$SRC"
} > "$OUT"
# C9 一族（#103 的尺子）的**原始读数行**必须在报告里：`C9a/C9b/C9e` 那三条
# 判据的绿与红全靠那几个数（窗内整行、de 沿、近黑格、最暗列），只留 PASS 行等于
# 让下一个人没法复核。以前白名单里没有 C9 ⇒ 报告里只有结论没有数。
#
# 空报告不许算绿：跑挂了的台架可能一条 PASS 都没打出来，那时 `RESULT` 那一行也不会有 ⇒
# 门禁判"必须有 RESULT ... PASS 且没有任何 FAIL 行"，两条都在报告正文上。
echo "WROTE $OUT  ($(grep -ac '' "$OUT") 行) top_md5=$TOP rtl_md5=$RTL tb_md5=$TB"
tail -3 "$OUT"

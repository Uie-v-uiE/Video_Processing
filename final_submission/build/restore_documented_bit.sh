#!/bin/bash
# 用途：断电重上之后，把板子恢复到**文档里那一版**（首页点名的 rNN + bit md5）
# 输入：命令行参数、board/tcl/program_pl.tcl
# 输出：stdout
# 退出码：0=跑完 2=非 0 分支（该文件 exit 2 那一行）
# build/restore_documented_bit.sh —— 断电重上之后，把板子恢复到**文档里那一版**（首页点名的 rNN + bit md5）
#
# 为什么要有它：2026-10-03 凌晨板子断电重上后，我手工做了这件事，过程里发现三个只有踩过才知道的点：
#   ① 断电后 `board/project/system.bit` 这个**交付位流位置**已经被下一轮构建覆盖（当晚是未采纳的 r109），
#      所以"刷板上那一版"不能默认刷 board/project/system.bit（#240）；
#   ② 已采纳那轮的位流在 git 里（采纳那笔提交 board/project/system.bit），要用 `git log --grep` 找到那笔再 `git show` 取回；
#   ③ `board_verify.sh --round=` **必须给新标签**，给 `--round=r108` 会去覆盖已被 md5 封存的 r108 原始串口回显。
# 本脚本把三点固化，且落刀前先核对 md5，对不上就 REFUSE。
#
# 用法：bash build/restore_documented_bit.sh [--dry]
#   --dry 只念不做（找位流、比 md5、打印将要跑的三步，不碰板子）
cd "$(dirname "$0")/.." || exit 2
DRY=; [ "${1:-}" = "--dry" ] && DRY=1     # 先认 --dry：没有它才要求 VP_XSDB/VP_VIVADO_BIN
X="${VP_XSDB:-}"; V="${VP_VIVADO_BIN:-}"
[ -n "$X" ] || [ -n "$DRY" ] || { echo "REFUSE: 设 VP_XSDB=<Vitis>/bin/xsdb.bat"; exit 2; }
[ -n "$V" ] || [ -n "$DRY" ] || { echo "REFUSE: 设 VP_VIVADO_BIN=<Vivado>/bin"; exit 2; }
[ -n "$X" ] && [ ! -f "$X" ] && { echo "REFUSE: 找不到 xsdb（$X；.bat 在 MSYS 下没有可执行位，别用 -x 判）"; exit 2; }

# ---- 0) 树必须空着：链子在飞时不许刷板（刷板会动 hw_server/JTAG，与台架无关但会把人搞混） ----
if [ -z "$DRY" ]; then
    tasklist 2>/dev/null | grep -qi "xsim\.exe"   && { echo "REFUSE: xsim.exe 活着（台架/构建链在飞）"; exit 2; }
    tasklist 2>/dev/null | grep -qi "vivado\.exe" && { echo "REFUSE: vivado.exe 活着（构建/探针在飞）"; exit 2; }
fi

# ---- 1) 首页那句身份：板上这一版 rNN + bit md5 前 12 位 ----
LINE=$(grep -m1 "板上这一版 r1[0-9][0-9]" README.md 2>/dev/null)
[ -n "$LINE" ] || { echo "REFUSE: README.md 里找不到『板上这一版 rNN』那一句 —— 首页形状变了，先读实"; exit 2; }
RR=$(printf '%s' "$LINE" | grep -o "r1[0-9][0-9]" | head -1)
BM=$(printf '%s' "$LINE" | grep -o "bit [0-9a-f]\{12\}" | head -1 | cut -d" " -f2)
[ -n "$RR" ] && [ -n "$BM" ] || { echo "REFUSE: 轮号/bit md5 没同时读出来（RR='$RR' BM='$BM'）"; exit 2; }
echo "文档态：板上这一版 $RR，bit md5 前 12 位 $BM"
NOW=$(md5sum board/project/system.bit 2>/dev/null | cut -c1-12)
echo "当前 board/project/system.bit = ${NOW:-读不到}（被下一轮构建覆盖过就是常态，见 #240）"

# ---- 2) 在 git 历史里找那一版的位流 ----
C=$(git log --format=%H -20 -- board/project/system.bit | while read h; do
        m=$(git show "$h:board/project/system.bit" 2>/dev/null | md5sum | cut -c1-12)
        [ "$m" = "$BM" ] && { echo "$h"; break; }
    done)
[ -n "$C" ] || { echo "REFUSE: git 历史里 20 笔内没有 md5=$BM 的 board/project/system.bit ⇒ 那一版没把位流提交进去（这是另一笔债，先别刷）"; exit 2; }
echo "找到：$C（$(git log -1 --format='%cd %s' --date=format:'%m-%d %H:%M' "$C" | iconv -f UTF-8 -t UTF-8//IGNORE | cut -c1-60)…）"
OUT="build/system_${RR}_restore.bit"
if [ -z "$DRY" ]; then
    git show "$C:board/project/system.bit" > "$OUT" || { echo "REFUSE: 取回位流失败"; exit 2; }
    GOT=$(md5sum "$OUT" | cut -c1-12)
    [ "$GOT" = "$BM" ] || { rm -f "$OUT"; echo "REFUSE: 取回的位流 md5=$GOT 对不上首页的 $BM"; exit 2; }
    echo "OK 取回 $OUT（md5 $GOT 与首页一致）"
else
    echo "DRY 将取回 $OUT 并核对 md5"
    exit 0
fi

# ---- 3) 三步链（顺序不能换：ps_jtag_boot → program_pl → ps_app_reload）----
TS=$(date +%m%d_%H%M); LOG="build/restore_${RR}_${TS}_console.txt"
echo "步骤 1/3 ps_jtag_boot（凭据看 DDR_ECHO 是不是 5A5AA5A5）"
cmd //c "$X board/tcl/ps_jtag_boot.tcl" > "$LOG" 2>&1 || { echo "REFUSE: ps_jtag_boot 失败，见 $LOG"; exit 2; }
grep -a "DDR_ECHO" "$LOG" | tail -1
echo "步骤 2/3 program_pl（VP_BIT=$OUT）"
VP_BIT="$OUT" "$V/vivado.bat" -mode batch -nojournal -source board/tcl/program_pl.tcl >> "$LOG" 2>&1 || { echo "REFUSE: program_pl 失败，见 $LOG"; exit 2; }
grep -a "PROGRAMMED" "$LOG" | tail -1
echo "步骤 3/3 ps_app_reload（ELF 不可重编：没有 arm-none-eabi-gcc，读 DOW:/PC_BEFORE_CON 两行）"
cmd //c "$X board/tcl/ps_app_reload.tcl" >> "$LOG" 2>&1 || { echo "REFUSE: ps_app_reload 失败，见 $LOG（别只看 tail，DOW 那行可能在上面）"; exit 2; }
grep -a "^DOW:\|^PC_BEFORE_CON:\|^ELF:" "$LOG" | tail -3

# ---- 4) 复验：--round 用新标签，绝不覆盖已封存的 rNN_serial_raw ----
TAG="${RR}re$(date +%H%M)"
echo "复验：board_verify --geom --round=$TAG（不是 --round=$RR，那个会覆盖被 md5 封住的旧凭据）"
VP_XSDB="$X" VP_VIVADO_BIN="$V" bash build/board_verify.sh --geom --round="$TAG" > "build/restore_${RR}_${TS}_verify.txt" 2>&1
RC=$?
tail -2 "build/restore_${RR}_${TS}_verify.txt" | iconv -f UTF-8 -t UTF-8//IGNORE
echo "RESULT restore_documented_bit rc=$RC 轮=$RR bit=$BM 凭据=build/restore_${RR}_${TS}_console.txt + _verify.txt"
[ "$RC" = 0 ] || echo "板级复验判红/挡：这不等于『刷坏了』——读上面两份件再判（geom 的空捕获与 COM6 被占用长得一样）"
exit $RC

#!/usr/bin/env bash
# build/r117_board.sh —— 链子跑完判读之后，把 r117 的位流刷上板并做板级复验（夜里无人敲第二条命令）。
#
# 为什么要等 `build/r117_gates.txt` 才动板：门禁里有一批会占 COM6/xsdb 的检查器
# （#220 之后 board_verify 自己也要留串口件），与刷板/读数同时跑就会撞串口 ⇒ 出现"看着像板子坏了"
# 的假红（环境账里那条 COM6 UnauthorizedAccessException 的同一类）。⇒ 顺序是硬的，不是客气。
#
# 为什么要"先 rst -system 再 program_pl"、为什么必须带流读数：都写在 build/r116_bit_cycle.sh 头部
# （#315 刷板把控制台弄哑、#316 零样本通过不算测过）。这一支只是把它按 r117 再跑一遍。
#
# 判负怎么办：本脚本**不替人做采纳决定**。它把"板上现在是哪一颗 bit"写进 BOARD_NOW.txt，
# 早上（或下一轮）若判负，一条命令回刷 r116：
#   VP_BIT=build/evidence/r116_bit/system.bit bash build/r116_bit_cycle.sh r116back
set -u
cd "$(dirname "$0")/.."
export VP_XSDB=${VP_XSDB:-"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"}
D=build/evidence/r117_board; mkdir -p "$D"
say(){ printf '[r117board %s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$D/board.log"; }

# ---- 0. 等 r117 的门禁两跑落地（最多 160 分钟）----
for i in $(seq 1 320); do
    [ -s build/r117_gates.txt ] && break
    sleep 30
done
[ -s build/r117_gates.txt ] || { say "等不到 build/r117_gates.txt —— 不动板（链子可能中断，不猜）"; exit 1; }
say "r117 门禁件到位；等 120 s 让第二跑与拷贝落定"; sleep 120

# ---- 1. 判读摘要进日志（不重判，只把链子写的抄一份到板侧目录，方便一次看完）----
[ -s build/r117_verdict.txt ] && cp -f build/r117_verdict.txt "$D/verdict_copy.txt"
say "判读件：build/r117_verdict.txt（复制进 $D/verdict_copy.txt）"

# ---- 2. 采用工件：位流 + XSA 连同身份一起存档（提示词 §5 adoption）----
BIT=vivado_system/zynq_video_sys.runs/impl_1/system_top.bit
XSA_DIR=vivado_system/zynq_video_sys.runs/impl_1
mkdir -p build/evidence/r117_bit
cp -f "$BIT" build/evidence/r117_bit/system.bit
XSA=$(ls -1 $XSA_DIR/*.xsa 2>/dev/null | head -1)
[ -n "$XSA" ] && cp -f "$XSA" build/evidence/r117_bit/system.xsa
M=$(md5sum build/evidence/r117_bit/system.bit | cut -c1-12)
printf '%s\n' "$M" > build/evidence/r117_bit/md5.txt
say "r117 位流已存档 build/evidence/r117_bit/，md5=$M"

# ---- 3. 三步链刷板 + 50 s 真实流量 + 两次健康读数 ----
say "起飞 bit_cycle（标签 r117build，位流 = build/evidence/r117_bit/system.bit）"
bash build/r116_bit_cycle.sh r117build build/evidence/r117_bit/system.bit \
    > "$D/bitcycle_console.txt" 2>&1
RC=$?
say "bit_cycle rc=$RC（件 build/evidence/r116_board/cycle_r117build.log）"

# ---- 4. 板级复验（几何 + 串口电池）----
say "board_verify --geom --battery --round=r117"
bash build/board_verify.sh --geom --battery --round=r117 > "$D/board_verify_console.txt" 2>&1
BV=$?
say "board_verify rc=$BV PASS=$(grep -ac 'PASS' "$D/board_verify_console.txt") 判红=$(grep -acE '^\[FAIL\]|FAIL ' "$D/board_verify_console.txt")"

# ---- 5. 板上现在是哪一颗：一句话写清楚，避免"板与仓库不同步"没人知道 ----
{
    printf '板上现在 = r117（bit %s，刷入 %s）\n' "$M" "$(date '+%F %T')"
    printf '仓库交付位 = 见 build/evidence/r116_bit/md5.txt（r116）与 build/evidence/r117_bit/md5.txt（r117）\n'
    printf '若 r117 判负，回刷 r116 一条命令：VP_BIT=build/evidence/r116_bit/system.bit bash build/r116_bit_cycle.sh r116back\n'
    printf 'bit_cycle rc=%s board_verify rc=%s\n' "$RC" "$BV"
} > "$D/BOARD_NOW.txt"
say "写在 $D/BOARD_NOW.txt"
say "结束：早上要看的三件 = build/r117_verdict.txt / build/r117_gates.txt / $D/BOARD_NOW.txt"

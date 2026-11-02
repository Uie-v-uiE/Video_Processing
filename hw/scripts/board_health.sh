#!/bin/bash
# 作用：只读地给板子拍一张健康快照 —— 串口三问 + JTAG 回读 + 异常向量，一把跑完并落一份带身份的件
# 前置条件：板子上电、USB-C 已插、COM6 没有被别的终端占住、本机 hw_server 在跑；VP_XSDB 指到 <Vitis>/bin/xsdb.bat
# 输入：无位置参数；开关见下面"关键参数"
# 产出物：board/measured/health_<YYYYMMDD_HHMM>.txt（同一份内容也打 stdout）
# 关键参数（全部用环境变量传，脚本里不写死任何机器路径）：
#   VP_XSDB   <Vitis>/bin/xsdb.bat 的绝对路径，必填；不给就 REFUSE 并 exit 2（口径同 build/board_verify.sh:118）
#   VP_PORT   串口号，默认 COM6（板载 FT4232 的 B 通道，见 board/hardware_setup.md）
#   VP_SEC    串口捕获的秒数，默认 8
#   VP_OUT_DIR 落件目录，默认 board/measured
#   实跑过两遍：board/measured/health_20261005_1025.txt（HEALTH: RED，红在最后一判）与
#           board/measured/health_20261005_1031.txt（HEALTH: GREEN，四判全过）—— 同一块板、同一版三件套。
#           红的那一份留着不删：它就是"pub= 这个活位会把 no-perturb 判据弄红"这条修正的现场凭据。
# 退出码：0=三段都拿到读数（末行 HEALTH: GREEN）；1=至少一段没拿到（末行 HEALTH: RED 并点名是哪段）；2=REFUSE
#
# 这支脚本什么都不写：不 rst、不 dow、不 mwr，也不往串口发会改板上控制字的命令。
# 三段用的是 board/ 里已经在跑的单步工具（board/scripts/uart_cap_once.ps1、board/tcl/rdddr.tcl、board/tcl/pswhy.tcl），
# 这里只负责按顺序跑、判每一段有没有真的拿到数、以及把"这份数出自哪一版三件套"写在同一件里。
# 为什么末行要有总判定、为什么件名不能带轮号：build/board_verify.sh 头部 #179 与 #273 那两条教训。
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 2

say() { printf '%s\n' "$*"; }
VP_XSDB=${VP_XSDB:-}
VP_PORT=${VP_PORT:-COM6}
VP_SEC=${VP_SEC:-8}
VP_OUT_DIR=${VP_OUT_DIR:-board/measured}

if [ ! -f "$VP_XSDB" ]; then
  say "REFUSE: 找不到 xsdb（当前 VP_XSDB=[$VP_XSDB]）。设 VP_XSDB=<Vitis>/bin/xsdb.bat 再跑。"
  say "        工具在 Vivado 安装树里，只是不在 PATH 上：find <安装根> -maxdepth 3 -name xsdb.bat 先定位再传进来。"
  exit 2
fi
mkdir -p "$VP_OUT_DIR" || exit 2
STAMP=$(date +%Y%m%d_%H%M)
OUT="$VP_OUT_DIR/health_${STAMP}.txt"

# 三段缓冲到临时件，最后一次性落盘：中途任何一段挂掉，盘上都不会留下一份"缺了后两段"的假快照
# TMPW 是同一个目录的 Windows 写法 —— powershell 不认 /tmp/... 这种 MSYS 路径，
# 串口捕获件必须由 uart_cap_once.ps1 自己写出来，所以这条路得换写法。
TMP=$(mktemp -d 2>/dev/null) || exit 2
TMPW=$(cygpath -w "$TMP") || exit 2
trap 'rm -rf "$TMP"' EXIT

# ---- 0) 身份：这份快照绑定的是哪一版三件套 ----
{
  say "==== IDENTITY ===="
  say "RUN_AT      $(date '+%Y-%m-%d %H:%M:%S')"
  say "HOST        ${COMPUTERNAME:-$(uname -n)}  PWD=$PWD"
  say "GIT_HEAD    $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  for f in board/project/system.bit board/project/system.xsa board/project/ps_app.elf; do
    if [ -f "$f" ]; then say "MD5_12      $(md5sum "$f" | cut -c1-12)  $f"
    else say "MD5_12      MISSING     $f"; fi
  done
} > "$TMP/id.txt"

# ---- 1) 串口：只发不改态的三条，收尾那条与开头那条必须逐字相同 ----
# uart_cap_once.ps1 的 -Cmds 按 [,\s]+ 拆词，所以这里只放不带空格的命令（带空格的走 board/scripts/uart_cmd_script.ps1）
PSPORT=$(powershell -NoProfile -ExecutionPolicy Bypass -File board/scripts/uart_cap_once.ps1 \
  -Port "$VP_PORT" -Seconds "$VP_SEC" -Drain -Cmds "stat,temp,stat" \
  -Out "$TMPW\\serial.txt" 2>&1)
{
  say "==== SERIAL (port=$VP_PORT seconds=$VP_SEC cmds=stat,temp,stat) ===="
  say "$PSPORT"
  say "-- raw capture --"
  cat "$TMP/serial.txt" 2>/dev/null
} > "$TMP/serial.log"

# ---- 2) JTAG 回读：AXI GPIO 控制字 + DDR 头 8 个字（rdddr.tcl 里全是 mrd） ----
"$VP_XSDB" -quiet board/tcl/rdddr.tcl > "$TMP/jtag.txt" 2>&1

# ---- 3) 异常向量：核停在哪儿、是不是 trap 进 Undefined 了（pswhy.tcl 只 stop/rrd/mrd/con） ----
"$VP_XSDB" -quiet board/tcl/pswhy.tcl > "$TMP/why.txt" 2>&1

# ---- 判：每一段单独判，红的话点名是哪段 ----
NRED=0
S_SERIAL=0; S_JTAG=0; S_WHY=0
grep -aq 'SENT 3/3' "$TMP/serial.log" && grep -aq '\[STAT\]' "$TMP/serial.log" && S_SERIAL=1
grep -aq 'GPIO = ' "$TMP/jtag.txt" && grep -aq 'DDR  head:' "$TMP/jtag.txt" && S_JTAG=1
grep -aq 'UndefinedExceptionAddr' "$TMP/why.txt" && grep -aq 'DataAbortAddr' "$TMP/why.txt" && S_WHY=1
# 首末两条 STAT 必须一致：这条脚本自己不能改变板子的状态。
# 但 `pub=` 不能算进去 —— 它是数据通路每发布一帧翻转一次的活位（2026-10-05 10:25 第一次实跑就是
# 被它判红的：首末两条只差 pub=1 / pub=0，其余逐字相同）。判"没改动板子"要比的是控制位，不是活位。
norm_stat() { sed 's/pub=[01]/pub=?/' ; }
FIRST_STAT=$(grep -a '^\[STAT\]' "$TMP/serial.txt" 2>/dev/null | head -1 | norm_stat)
LAST_STAT=$(grep -a '^\[STAT\]' "$TMP/serial.txt" 2>/dev/null | tail -1 | norm_stat)
S_SAME=0; [ -n "$FIRST_STAT" ] && [ "$FIRST_STAT" = "$LAST_STAT" ] && S_SAME=1

{
  cat "$TMP/id.txt"
  cat "$TMP/serial.log"
  say "==== JTAG READBACK (board/tcl/rdddr.tcl, mrd only) ===="
  cat "$TMP/jtag.txt"
  say "==== CORE VECTORS (board/tcl/pswhy.tcl) ===="
  cat "$TMP/why.txt"
  say "==== VERDICT ===="
  say "serial(SENT 3/3 且有 [STAT]) = $S_SERIAL"
  say "jtag(GPIO 与 DDR 头都读到)   = $S_JTAG"
  say "vectors(三条异常向量都在)     = $S_WHY"
  say "no-perturb(首末 STAT 除 pub= 外同)  = $S_SAME"
} > "$OUT"

cat "$OUT"
for x in $S_SERIAL $S_JTAG $S_WHY $S_SAME; do [ "$x" = 1 ] || NRED=$((NRED + 1)); done
if [ "$NRED" = 0 ]; then
  say "HEALTH: GREEN  件=$OUT"
  exit 0
fi
say "HEALTH: RED  没拿到的段数=$NRED  件=$OUT"
say "        串口段没数 ⇒ 先确认 COM6 没被占住（board/hardware_setup.md）；JTAG 段没数 ⇒ 先确认 hw_server 在听 3121。"
exit 1

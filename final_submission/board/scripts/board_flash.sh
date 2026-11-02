#!/bin/bash
# 作用：把仓库里这一版三件套放到板上 —— 起 PS、配 PL、下应用，按顺序一把跑完，末尾回读一次 GPIO 证明 PL 真的上了
# 前置条件：板子上电、USB-C 已插、本机 hw_server 在跑；VP_XSDB 与 VP_VIVADO_BIN 两个环境变量都指到真实存在的位置
# 输入：位置参数只有一个开关 --check（只做前置检查与只读扫链，不碰板子）
# 产出物：board/measured/flash_<YYYYMMDD_HHMM>.txt（同一份内容也打 stdout）
# 关键参数（全用环境变量传，脚本里不写死任何机器路径）：
#   VP_XSDB        <Vitis>/bin/xsdb.bat 的绝对路径，必填
#   VP_VIVADO_BIN  <Vivado>/bin 的绝对路径，必填（这一步的 program_pl 走 vivado 而不是 xsdb）
#   VP_BIT         位流路径，透传给 board/tcl/program_pl.tcl；不设就是 board/project/system.bit
#   VP_ELF         应用路径，透传给 board/tcl/ps_app_reload.tcl；不设就是 board/project/ps_app.elf
#   VP_OUT_DIR     落件目录，默认 board/measured
# 实跑过两遍（2026-10-05，板子就是那一版 r118 三件套）：
#   board/measured/flash_20261005_1026.txt  = --check，FLASH: GREEN，没有任何写动作
#   board/measured/flash_20261005_1030.txt  = 三步全跑，FLASH: GREEN，
#       里面留着 RST_SYSTEM/PS7_INIT/DDR_ECHO=5A5AA5A5/PROGRAMMED xc7z020_1/DOW: ok 与末尾的 GPIO 回读
# 退出码：0=三步全 rc=0 且回读到 GPIO；1=某一步 rc 非 0（末行 FLASH: RED 点名第几步）；2=REFUSE
#
# 顺序不能换，而且这一支会真的动硬件：
#   ps_jtag_boot.tcl 里第一步就是 rst -system —— 它会把已经配好的位流冲掉，所以之后必须重下 bit；
#   program_pl 之前下应用是下不进去的（PL 的 AXI 从机还不存在）；
#   ps_app_reload.tcl 只 rst -processor，因此"换了 app 不想重刷 PL"时单独跑那一步就够（见 board/README.md 第 2 节）。
# 这三条都写在被调的那三支 .tcl 自己的文件头里，这里不重复一遍口径，只把顺序固定下来。
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 2

say() { printf '%s\n' "$*"; }
VP_XSDB=${VP_XSDB:-}
VP_VIVADO_BIN=${VP_VIVADO_BIN:-}
VP_OUT_DIR=${VP_OUT_DIR:-board/measured}
BIT=${VP_BIT:-board/project/system.bit}
ELF=${VP_ELF:-board/project/ps_app.elf}
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

# ---- 前置检查：工具、三件套、串口占用；任何一项不在就 REFUSE，绝不"少了工具还往下跑" ----
MISS=""
[ -f "$VP_XSDB" ] || MISS="$MISS xsdb(VP_XSDB=$VP_XSDB)"
[ "$CHECK_ONLY" = 1 ] || { [ -d "$VP_VIVADO_BIN" ] || MISS="$MISS VP_VIVADO_BIN=$VP_VIVADO_BIN"; }
[ -f "$BIT" ] || MISS="$MISS $BIT"
[ -f "$ELF" ] || MISS="$MISS $ELF"
[ -f board/tcl/ps_jtag_boot.tcl ] || MISS="$MISS board/tcl/ps_jtag_boot.tcl"
[ -f board/tcl/program_pl.tcl ] || MISS="$MISS board/tcl/program_pl.tcl"
[ -f board/tcl/ps_app_reload.tcl ] || MISS="$MISS board/tcl/ps_app_reload.tcl"
if [ -n "$MISS" ]; then
  say "REFUSE: 缺$MISS"
  say "        工具在 Vivado/Vitis 安装树里、不在 PATH 上：先 find <安装根> -maxdepth 3 -name xsdb.bat 定位，再用环境变量传进来。"
  exit 2
fi

mkdir -p "$VP_OUT_DIR" || exit 2
STAMP=$(date +%Y%m%d_%H%M)
OUT="$VP_OUT_DIR/flash_${STAMP}.txt"
TMP=$(mktemp -d 2>/dev/null) || exit 2
# 2>/dev/null 是必要的：vivado/xsdb 会往 TMPDIR 里留下几个自己还握着的临时文件，
# 退出时那一句 rm 会甩出 "Device or resource busy"。它不是这一跑的失败，
# 混在末尾的总判定下面会被读成失败，所以把这条噪音压掉，判据只看各步的 rc 与那三行读数。
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

{
  say "==== IDENTITY ===="
  say "RUN_AT      $(date '+%Y-%m-%d %H:%M:%S')  mode=$([ "$CHECK_ONLY" = 1 ] && echo check-only || echo FLASH)"
  say "GIT_HEAD    $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  for f in "$BIT" "$ELF" board/project/system.xsa; do
    [ -f "$f" ] && say "MD5_12      $(md5sum "$f" | cut -c1-12)  $f" || say "MD5_12      MISSING     $f"
  done
  say "TOOL        xsdb=$VP_XSDB"
  say "TOOL        vivado_bin=${VP_VIVADO_BIN:-（--check：这一步不需要）}"
} > "$TMP/head.txt"

# ---- 0) 只读扫链：hw_server 看不看得见 PS 那颗 A9，这一条对板子没有任何副作用 ----
# 用 board/tcl/scan_jtag.tcl：它只做 open_hw_manager / connect_hw_server / open_hw_target + 打印清单，
# 没有 rst/con/mwr，所以 --check 真的不碰板子。
# 上一版这里写的是 build/tcl/r116_jtag_health.tcl —— 仓库里从来没有这个文件，xsdb 直接报
# "couldn't read file"，而判据抓的两个标记（JTAG_TARGETS_END / APU_SELECT rc=0）其实出自
# r116_jtag_recover.tcl，那支是**发系统复位**的：既指错文件，又把"复位"藏进只读路径里（台账 #405）。
# 现在：被调文件不在就 REFUSE（缺件不是红，是没量过），并且把"比了几次"念出来。
SCAN_TCL=board/tcl/scan_jtag.tcl
if [ ! -f "$SCAN_TCL" ]; then
  say "REFUSE: 扫链要调的 $SCAN_TCL 不在仓库里 ⇒ 这一项什么都没查，不判红也不判绿"; exit 2
fi
"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source "$SCAN_TCL" > "$TMP/scan.txt" 2>&1
SCAN_TGT="$(grep -c '^  localhost:' "$TMP/scan.txt" || true)"; SCAN_TGT="${SCAN_TGT:-0}"
SCAN_APU="$(grep -cE 'arm_dap|xc7z020' "$TMP/scan.txt" || true)"; SCAN_APU="${SCAN_APU:-0}"
say "扫链（只读）：线缆 target=$SCAN_TGT 条、链上器件行=$SCAN_APU（要 ≥2：arm_dap + xc7z020）"
SCAN_OK=0; [ "$SCAN_APU" -ge 2 ] && SCAN_OK=1

RC1=1; RC2=1; RC3=1; RB=1
if [ "$CHECK_ONLY" = 0 ]; then
  say "STEP 1/3 ps_jtag_boot （xsdb：rst -system + ps7_init + DDR 自检；会冲掉 PL 上现有的位流）"
  "$VP_XSDB" -quiet board/tcl/ps_jtag_boot.tcl > "$TMP/s1.txt" 2>&1; RC1=$?
  sed 's/^/  /' "$TMP/s1.txt"
  say "STEP 2/3 program_pl （vivado：把 $BIT 配进 PL）"
  if [ "$BIT" = "board/project/system.bit" ]; then
    "$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source board/tcl/program_pl.tcl > "$TMP/s2.txt" 2>&1; RC2=$?
  else
    VP_BIT="$BIT" "$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source board/tcl/program_pl.tcl > "$TMP/s2.txt" 2>&1; RC2=$?
  fi
  sed 's/^/  /' "$TMP/s2.txt"
  say "STEP 3/3 ps_app_reload （xsdb：rst -processor + dow $ELF + con）"
  "$VP_XSDB" -quiet board/tcl/ps_app_reload.tcl "$ELF" > "$TMP/s3.txt" 2>&1; RC3=$?
  sed 's/^/  /' "$TMP/s3.txt"
  # 回读一次控制字：PL 没配上时这条 mrd 取不到数，所以它是"三步真的都落地了"的最短判据
  "$VP_XSDB" -quiet board/rdbck.tcl > "$TMP/rb.txt" 2>&1; RB=$?
fi

FAIL=""
addfail() { FAIL="${FAIL}$(printf '\n%s' "        $1")"; }
[ "$SCAN_OK" = 1 ] || addfail "扫链没看见 APU/PL（器件行=$SCAN_APU，期望 ≥2；明细 $TMP/scan.txt）"
if [ "$CHECK_ONLY" = 0 ]; then
  [ "$RC1" = 0 ] || addfail "第1步 ps_jtag_boot rc=$RC1"
  [ "$RC2" = 0 ] || addfail "第2步 program_pl rc=$RC2"
  [ "$RC3" = 0 ] || addfail "第3步 ps_app_reload rc=$RC3"
  [ "$RB" = 0 ] || addfail "回读 GPIO rc=$RB"
  # 三条内容判据：不看"有没有跑完"，看每一步该留下的那行读数在不在。
  # DDR_ECHO 那行的空格数是 xsdb 的 mrd 排版（地址后一到多个空格），所以判 [[:space:]]+ 而不是一个字面空格
  # ——2026-10-05 10:27 第一次实跑就是被这个字面空格判红的，三步 rc 全是 0。
  grep -aqE 'DDR_ECHO: 10000000:[[:space:]]+5A5AA5A5' "$TMP/s1.txt" || addfail "没读到 DDR_ECHO=5A5AA5A5"
  grep -aq 'PROGRAMMED' "$TMP/s2.txt" || addfail "program_pl 没打 PROGRAMMED"
  grep -aq 'DOW: ok' "$TMP/s3.txt" || addfail "应用没 dow 进去"
fi

{
  cat "$TMP/head.txt"
  say "==== STEP 0 JTAG SCAN (read-only) ===="
  cat "$TMP/scan.txt"
  say "scan sees a Cortex-A9 target = $SCAN_OK"
  if [ "$CHECK_ONLY" = 0 ]; then
    say "==== STEPS 1-3 rc ===="
    say "rc ps_jtag_boot=$RC1  rc program_pl=$RC2  rc ps_app_reload=$RC3  rc readback_gpio=$RB"
    say "==== STEP 1 ps_jtag_boot (board/tcl/ps_jtag_boot.tcl) ===="
    cat "$TMP/s1.txt"
    say "==== STEP 2 program_pl (board/tcl/program_pl.tcl, bit=$BIT) ===="
    cat "$TMP/s2.txt"
    say "==== STEP 3 ps_app_reload (board/tcl/ps_app_reload.tcl, elf=$ELF) ===="
    cat "$TMP/s3.txt"
    say "==== READBACK (board/rdbck.tcl) ===="
    cat "$TMP/rb.txt"
  else
    say "CHECK ONLY —— 没有对板子做任何写动作（下一步去掉 --check 才会真的刷）"
  fi
} > "$OUT"

cat "$OUT"
if [ -z "$FAIL" ]; then
  say "FLASH: GREEN  件=$OUT"
  [ "$CHECK_ONLY" = 1 ] && say "FLASH: 这只是前置检查（--check）。板上状态没有被这一跑改动。"
  exit 0
fi
say "FLASH: RED —— 没过的项目：$FAIL"
say "        件=$OUT"
say "        只有扫链那项红 ⇒ 先看板子供电与 hw_server（netstat -an -p TCP | grep 3121），别先看代码。"
exit 1

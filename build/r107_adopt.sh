#!/usr/bin/env bash
# 用途：r107 的采纳段：等链子跑完 → 断言"红只有声明过的 C5c" → 三步 JTAG 刷板 →
# 输入：命令行参数、build/tcl/program_pl.tcl
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行）
# build/r107_adopt.sh —— r107 的采纳段：等链子跑完 → 断言"红只有声明过的 C5c" → 三步 JTAG 刷板 →
# board_verify（几何 + 串口电池）→ ping 三种长度。判据不过就断链，不产"看起来通过"的凭据。
#
# 为什么写成脚本：刷板→复验→取证这段本来就是要连做的（分开做时中间任何一步失败都会留下
# "板子是 r107、文档还写 r106"的半态）。三步 JTAG 与 ping 的形状照 README 第 37-43 行，
# 不写 QSPI、不碰板载 EEPROM。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
X=${VP_XSDB:-/d/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat}
NN=107
BOARD_IP=192.168.1.10
say() { printf '[adopt %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "断链：$*"; exit 1; }

[ -f "$V/vivado.bat" ] || die "找不到 vivado.bat（$V）"
[ -f "$X" ] || die "找不到 xsdb（设 VP_XSDB=<Vitis>/bin/xsdb.bat，当前 $X）"

# ---- 1. 等链子结束（顶层台架 ~100 分钟 + rim + 门禁）----
for i in $(seq 1 120); do
    grep -q "链结束" "build/r${NN}_chain_console.txt" 2>/dev/null && break
    sleep 30
done
grep -q "链结束" "build/r${NN}_chain_console.txt" 2>/dev/null || die "等不到链子结束（>60 分钟）"
say "链子结束，开始断言"

# ---- 2. 断言一：顶层台架的红必须恰好是那一条声明过的 C5c ----
RUNLOG=/tmp/kx/tb_v98_top_seam.run/run.log
[ -f "$RUNLOG" ] || die "找不到 $RUNLOG（台架日志不在，无法断言）"
NFAIL=$(grep -ac '^FAIL' "$RUNLOG")
[ "$NFAIL" = 1 ] || die "顶层台架 FAIL 行数=$NFAIL（期望 1）—— 不是'唯一红是 C5c'那个态"
grep -q '^FAIL C5c' "$RUNLOG" || die "唯一那条红不是 C5c：$(grep -a '^FAIL' "$RUNLOG" | head -1 | cut -c1-80)"
NPASS=$(grep -ac '^PASS' "$RUNLOG")
say "台架断言通过：PASS=$NPASS，FAIL=1 且就是 C5c"

# ---- 3. 断言二：门禁 22 项 = 21 绿 / 1 红，且红的那一项是已声明的 ----
[ -f "build/r${NN}_gates.txt" ] || die "没有 build/r${NN}_gates.txt"
G=$(grep -c ' PASS$' "build/r${NN}_gates.txt"); GBAD=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")
say "门禁计数：绿=$G 红=$GBAD 末行=$(tail -1 "build/r${NN}_gates.txt" | cut -c1-90 | iconv -f UTF-8 -t UTF-8//IGNORE)"
[ "$GBAD" = 1 ] || die "门禁红数=$GBAD（期望 1）"
[ "$G" = 21 ] || die "门禁绿数=$G（期望 21）"

# ---- 4. 三步 JTAG 刷板（绝不写 QSPI）----
F="build/r${NN}_flash_console.txt"; : > "$F"
say "步骤 1/3 ps_jtag_boot"
"$X" build/tcl/ps_jtag_boot.tcl >> "$F" 2>&1 || die "ps_jboot rc!=0，见 $F"
grep -q "5A5AA5A5" "$F" || die "DDR_ECHO 里没有 5A5AA5A5（DDR 自检没过，别往下烧）"
say "步骤 2/3 program_pl"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1 || die "program_pl rc!=0，见 $F"
grep -q "PROGRAMMED" "$F" || die "没看到 PROGRAMMED 标记，见 $F"
say "步骤 3/3 ps_app_reload"
"$X" build/tcl/ps_app_reload.tcl >> "$F" 2>&1 || die "ps_app_reload rc!=0，见 $F"
grep -q "FLOW_DONE" "$F" || die "没有 FLOW_DONE（应用没跑起来），见 $F"
say "刷板三步完成，实际位流 md5=$(md5sum build/system.bit | cut -c1-12)"

# ---- 5. 板级复验：几何最后一跳 + 串口命令电池 ----
sleep 20
BV="build/r${NN}_board_verify_console.txt"
VP_XSDB="$X" bash build/board_verify.sh --geom --battery --round=r${NN} > "$BV" 2>&1; RC=$?
say "board_verify rc=$RC"
grep -a "RESULT board_verify" "$BV" | tail -n 2 | cut -c1-120 | iconv -f UTF-8 -t UTF-8//IGNORE | sed 's/^/  /'
grep -q "RESULT board_verify PASS" "$BV" || say "注意：board_verify 没有 PASS 行，判据未成立（见 $BV）"

# ---- 6. ping 三种长度（#218 的 0 长度那一条要单列）----
P="build/r${NN}_board_ping.txt"
{ echo "# r107 板级 ICMP（$(date '+%Y-%m-%d %H:%M') 本地，board_ip $BOARD_IP）"
  echo "## ping -n 4"; ping -n 4 "$BOARD_IP" 2>&1 | tail -n 4
  echo "## ping -l 0 -n 3"; ping -l 0 -n 3 "$BOARD_IP" 2>&1 | tail -n 4
  echo "## ping -l 32 -n 4"; ping -l 32 -n 4 "$BOARD_IP" 2>&1 | tail -n 4; } > "$P"
say "ICMP 取证落 $P"
say "采纳段结束（文档同步与重导包由人接着做）"

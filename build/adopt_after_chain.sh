#!/usr/bin/env bash
# 用途：采纳段（轮号由 VP_ADOPT_NN 给，默认 107）：
# 输入：命令行参数、build/tcl/program_pl.tcl
# 输出：stdout
# 退出码：1=非 0 分支（该文件 exit 1 那一行）
# build/adopt_after_chain.sh —— 采纳段（轮号由 VP_ADOPT_NN 给，默认 107）：
# 等链子跑完 → 三条断言 → 三步 JTAG 刷板 → board_verify（几何 + 串口电池）→ ping 三种长度。
# 断言不过就断链，不产"看起来通过"的凭据。r107 那一程它是 build/r107_adopt.sh，通用化后给后续轮复用。
#
# 为什么值得脚本化：刷板→复验→取证这段本来就要连做，分开做时中间任何一步失败都会留下
# "板子已经是新一轮、文档还写上一轮"的半态。三步 JTAG 的形状照 README 第 37-43 行；
# 本工程**绝不向 QSPI/SPI flash 写入**，也不碰板载 EEPROM。
set -u
cd "$(dirname "$0")/.."
V="${VP_VIVADO_BIN:?要先设 VP_VIVADO_BIN=<Vivado>/bin 再跑（见 report/build.md；包里的脚本一律不写死绝对路径）}"
X="${VP_XSDB:?还要设 VP_XSDB=<Vitis>/bin/xsdb.bat（Vitis 在 Vivado 安装树里面）}"
NN=${VP_ADOPT_NN:-107}
TB=${VP_ADOPT_TB:-tb_v98_top_seam}
BOARD_IP=192.168.1.10
say() { printf '[adopt %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { say "断链：$*"; exit 1; }

[ -f "$V/vivado.bat" ] || die "找不到 vivado.bat（$V；注意 .bat 在 MSYS 下没有可执行位，别用 -x 判）"
[ -f "$X" ] || die "找不到 xsdb（设 VP_XSDB=<Vitis>/bin/xsdb.bat，当前 $X）"

# ---- 1. 等链子结束 ----
# ⚠ 标记不止一个来源（r109 撞上的）：整轮链 `build/rNN_chain.sh` 打的是"链结束"，
#   而**补救阶段** `build/rNN_stage2.sh` 打的是"阶段结束"。上一版这里只认"链结束"，
#   于是台架明明跑完了、这一支还是会等满 100 分钟再 die —— 所以两个文件、两个标记都认。
for i in $(seq 1 200); do
    grep -qs "链结束\|阶段结束" "build/r${NN}_chain_console.txt" "build/r${NN}_stage2_console.txt" && break
    sleep 30
done
grep -qs "链结束\|阶段结束" "build/r${NN}_chain_console.txt" "build/r${NN}_stage2_console.txt" \
    || die "等不到链子/阶段结束（>100 分钟）：build/r${NN}_chain_console.txt 与 build/r${NN}_stage2_console.txt 里都没有结束标记"
say "链子/阶段结束，开始断言"

# ---- 2. 断言一：顶层台架的红必须恰好是那一条声明过的 C5c ----
RUNLOG=/tmp/kx/$TB.run/run.log
[ -f "$RUNLOG" ] || die "找不到 $RUNLOG（台架日志不在，无法断言）"
NFAIL=$(grep -ac '^FAIL' "$RUNLOG")
NPASS=$(grep -ac '^PASS' "$RUNLOG")
[ "$NPASS" -ge 100 ] || die "台架 PASS 行只有 $NPASS（地板 100）—— 这一跑很可能半路停了"
[ "$NFAIL" = 1 ] || die "顶层台架 FAIL 行数=$NFAIL（期望 1）—— 不是'唯一红是 C5c'那个态"
grep -q '^FAIL C5c' "$RUNLOG" || die "唯一那条红不是 C5c：$(grep -a '^FAIL' "$RUNLOG" | head -1 | cut -c1-80)"
# 新鲜度断言（r108 这一程想出来的）：run.log 有可能是上一轮留下的——上一轮照样是 PASS=157/FAIL=1，
# 光看它会误判成"这一轮也过了"。以门禁自己核对的树指纹为准：本轮的台架项必须写着 指纹(norm1):fresh，
# 而且那份 run.log 必须比**本轮的构建**新（锚点用构建控制台：它在构建结束时定格，之后的台架一定比它新）。
GB=$(grep " 顶层台架" "build/r${NN}_gates.txt" 2>/dev/null | head -1)
case "$GB" in
    *"指纹(norm1):fresh"*) say "新鲜度：门禁台架项认的是本轮树指纹（fresh）" ;;
    *) die "门禁台架项没有 指纹(norm1):fresh —— 报告不是这棵树的：$GB" ;;
esac
if [ -f build/r${NN}_build_console.txt ]; then
    [ "$RUNLOG" -nt build/r${NN}_build_console.txt ] || die "run.log 不比本轮构建控制台新 —— 那是上一轮留下的旧日志"
fi
say "台架断言通过：PASS=$NPASS，FAIL=1 且就是 C5c"

# ---- 3. 断言二：门禁的红只允许"台架 + 还没同步的文档两类" ----
[ -f "build/r${NN}_gates.txt" ] || die "没有 build/r${NN}_gates.txt"
G=$(grep -c ' PASS$' "build/r${NN}_gates.txt"); GBAD=$(grep -c ' FAIL$' "build/r${NN}_gates.txt")
# 采纳前台页与 metrics.csv 还没换数，D1c/D6 必然红 —— 那是"还没同步"，不是"判据不过"。
# ⚠ **这里不写死"21 绿 / 1 红"**（上一版写死了）：门禁条数会随教训涨（r109 起是 **24 项**，
#   第 22/23 项是新接的 pipe_len / temp_formula），写死就会在下一轮自己把自己判死。
#   同步之后要收敛成什么，由这份件自己算：**红 1（声明过的 C5c）、绿 = 判定条数 - 1**，
#   而首页那句"门禁 N 项 …"由 D1c 逐条对回本件（#229 的两个自洽解就在这）。
BADNAMES=$(grep ' FAIL$' "build/r${NN}_gates.txt" | sed 's/^ *//' | cut -d' ' -f1-2 | paste -sd'|' -)
NSAY=$(( G + GBAD ))
say "门禁当前绿=$G 红=$GBAD（判定 $NSAY 项），红项=$BADNAMES；同步后应剩 绿=$((NSAY - 1)) / 红=1"
[ "$GBAD" -le 3 ] || die "门禁红数=$GBAD（>3 就不是'台架 + 未同步的文档'这一组了）"
case "$BADNAMES" in
    *数字对账*|*文档时效*) : ;;   # 允许：还没换数的文档项
esac
for nm in $(grep ' FAIL$' "build/r${NN}_gates.txt" | sed 's/^ *//' | cut -d' ' -f1); do
    case "$nm" in
        顶层台架|文档时效|数字对账|边缘条带) ;;
        *) die "门禁里出现了不在允许集合内的红项：$nm" ;;
    esac
done

# ---- 4. 三步 JTAG 刷板 ----
F="build/r${NN}_flash_console.txt"; : > "$F"
say "步骤 1/3 ps_jtag_boot"
"$X" build/tcl/ps_jtag_boot.tcl >> "$F" 2>&1 || die "ps_jtag_boot rc!=0，见 $F"
grep -q "5A5AA5A5" "$F" || die "DDR_ECHO 里没有 5A5AA5A5（DDR 自检没过，不往下烧）"
say "步骤 2/3 program_pl"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1 || die "program_pl rc!=0，见 $F"
grep -q "PROGRAMMED" "$F" || die "没看到 PROGRAMMED 标记，见 $F"
say "步骤 3/3 ps_app_reload"
"$X" build/tcl/ps_app_reload.tcl >> "$F" 2>&1 || die "ps_app_reload rc!=0，见 $F"
grep -q "FLOW_DONE" "$F" || die "没有 FLOW_DONE（应用没跑起来），见 $F"
FLASH_AT=$(date '+%Y-%m-%d %H:%M')
say "刷板三步完成，实际位流 md5=$(md5sum build/system.bit | cut -c1-12)，刷板时刻 $FLASH_AT"

# ---- 5. 板级复验 ----
sleep 20
BV="build/r${NN}_board_verify_console.txt"
VP_XSDB="$X" bash build/board_verify.sh --geom --battery --round=r${NN} > "$BV" 2>&1; RC=$?
say "board_verify rc=$RC"
grep -aE "RESULT (board_verify|PASS geom_check|PASS uart_cmd_check)|degC" "$BV" | tail -n 6 | cut -c1-150
grep -q "RESULT board_verify PASS" "$BV" || say "注意：board_verify 没有 PASS 行 ⇒ 判据未成立（见 $BV），别接着同步文档"

# ---- 6. ICMP 三种长度（零长度那条是 #218 的板级判据）----
P="build/r${NN}_board_ping.txt"
{ echo "# r${NN} 板级 ICMP（${FLASH_AT} 之后，${BOARD_IP}，板上 bit $(md5sum build/system.bit | cut -c1-12)）"
  echo "## ping -n 4"; ping -n 4 "$BOARD_IP" 2>&1 | tail -n 3
  echo "## ping -l 0 -n 3（#218 的零长度那一条）"; ping -l 0 -n 3 "$BOARD_IP" 2>&1 | tail -n 3
  echo "## ping -l 32 -n 4"; ping -l 32 -n 4 "$BOARD_IP" 2>&1 | tail -n 3; } > "$P"
iconv -f GBK -t UTF-8 "$P" > /tmp/ping.$$ 2>/dev/null && cp -f /tmp/ping.$$ "$P" || true
rm -f /tmp/ping.$$
say "ICMP 取证落 $P（已 GBK→UTF-8，否则被跟踪件对 grep 是二进制）"
say "采纳段结束（文档同步 + 门禁两步重跑 + 重导包 + 推送由人接着做）"

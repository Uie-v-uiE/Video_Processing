#!/usr/bin/env bash
# build/r132_timing_round.sh —— r132 这一轮的时序补账：三条臂各跑一次隔离构建，读数全部落盘
#
# 为什么要这一轮（起飞前登记，不接受事后改口径）：
#   ① 现版只有 r118 的名册，逐域名册整份重导是台账 #479 末段挂着的那笔债；
#   ② 报告 4.1 第 1 条写着"屏这一路的对外时序还没有结论、250 MHz 串行域不设检查项"，
#      而候选约束件 `src/constraints/r119_hdmi_source_window.xdc` 的注释自己说"缺的是一次量名册的构建"；
#   ③ 报告 4.2 念的"RGMII 输入窗一挂整个时钟域全红"用的是 r114 的数（WHS −2.885 / THS −14.344），
#      现版 RTL 已经变了好几版，这句话该有现版的读数；
#   ④ 现版 clk_fpga_0 最差那条是 `u_pl/u_arb/owner_eth_reg/C → u_bilin/u_fb/…ADDRARDADDR[7]`，
#      1 级逻辑、布线占 92.71 % ⇒ 根因是这只旗标的扇出与摆放。r117 对另一只广播网
#      （u_pl/u_row/hi_reg_0[0]）做过强制复制，赢一格、输四格而判负；同样的刀换到现版这只网上
#      没量过。
#
# 三条臂（一次只动一个变量，RTL 与现行约束一个字节不改；隔离构建，build/ 里被文档点名的产物不碰）：
#   A tmdswindow  VP_R119_TMDS_WINDOW=1
#   B rgmiiwindow VP_R116_IO_WINDOW=1
#   C ownerrep    IMPL_POST_PLACE_HOOK=build/tcl/r117_post_place_hook.tcl + VP_HOOK_NET=u_pl/u_arb/owner_eth_reg
#
# 判据（每条臂都念，判定按严格的那把）：
#   P1 机构在位：构建控制台里必须出现该臂的 loaded/hook 声明行；没出现 ⇒ 这一臂判 NOT PROVEN，不念数
#   P2 名册八对（4 域 × setup/hold）逐格对 r132 基线：margin_pct 不许变小（严格 B1）
#   P3 该臂要量的东西真量到了：A 要 clkout1_1 的 I/O 或同域读数 + 全设计 WNS/WHS/失败端点；
#      B 要 eth_rxc 的 hold 与 I/O 端点红数；C 要 clk_fpga_0 的 setup 与端点数（复制单元应当 +N）
#   P4 资源账：LUT/FF/BRAM/DSP 与基线的差要念出来；C 允许 FF 增加（复制单元），其余不许动
#   采纳门槛：只有 P2 全过且 P3 显示该域确实变好的臂才进采纳评估，且要第二滚同向（规矩 35）；
#   A/B 是"把欠账量出来"的臂，判语按量到的数写，红也是结论，不为了绿而摘约束（H1）。
set -u
cd "$(dirname "$0")/.." || exit 1
V=${VP_VIVADO_BIN:?需要显式给 Vivado bin 目录}
[ -x "$V/xvlog" ] || { echo "REFUSE: VP_VIVADO_BIN 里没有 xvlog：$V"; exit 2; }
if tasklist 2>/dev/null | grep -qiE "^vivado\.exe"; then echo "REFUSE: 已经有 Vivado 在飞"; exit 2; fi
if tasklist 2>/dev/null | grep -qiE "^xsimk?\.exe"; then echo "REFUSE: 台架 xsim 还在跑（15.7 G 内存）"; exit 2; fi
BASE=build/evidence/r132_after_roster_probefmt.txt
[ -s "$BASE" ] || { echo "REFUSE: 基线名册不在（先跑 r132 roster probe）"; exit 2; }
LOG=build/r132_timing_round.log
say(){ printf '[r132round %s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

arm(){
  name=$1; shift
  OUT=build/isolated_r132_$name
  say "=== 臂 $name 起飞：$* → $OUT"
  # 不用 `env K=V cmd`：这台机器 PATH 上的 env 是 ~/.local/bin/env 一个会把命令吞掉的替身
  # （实测 `env FOO=1 bash x.sh` 什么都不跑还返回 0）。改成子 shell 里 export。
  ( for kv in "$@"; do export "${kv?}" ; done
    export OUT="$OUT"
    bash build/roll_isolated.sh ) >> "$LOG" 2>&1; rc=$?
  say "roll rc=$rc"
  CON="$OUT/build_console.txt"
  [ -s "$CON" ] || { say "$name NOT PROVEN：没有构建控制台，别看数"; return 1; }
  grep -qa "SYSTEM BUILD DONE" "$CON" || { say "$name NOT PROVEN：控制台里没有 SYSTEM BUILD DONE"; }
  say "$name 声明行：$(grep -ao 'VP_R116_IO_WINDOW [a-z]*\|VP_R119_TMDS_WINDOW [a-z]*\|BUILD_POST_PLACE_HOOK.*hook[^ ]*\|R117HOOK[^ ]*' "$CON" | head -2 | tr '\n' ' ')"
  dcp=$(ls "$OUT"/vivado_proj/*.runs/impl_1/system_top_routed.dcp 2>/dev/null | head -1)
  [ -n "$dcp" ] || { say "$name NOT PROVEN：隔离目录里没有 routed dcp"; return 1; }
  VP_DCP="$dcp" VP_LABEL="r132_$name" VP_N=4 "$V/vivado.bat" -mode batch -nojournal \
      -source build/tcl/probe_timing_roster.tcl > "build/r132_${name}_roster_console.txt" 2>&1
  say "$name probe rc=$?"
  grep -a '^ROSTER|\|^FANOUT|\|^DESIGN|\|^ROSTER_ROWS' "build/r132_${name}_roster_console.txt" \
      > "build/evidence/r132_${name}_roster.txt"
  say "$name 名册 rows=$(grep -ac '^ROSTER|' "build/evidence/r132_${name}_roster.txt")"
  bash build/timing_roster_diff.sh "$BASE" "build/evidence/r132_${name}_roster.txt" \
      > "build/evidence/r132_${name}_diff_vs_r132.txt" 2>&1
  say "$name 差分(25% 门槛那把) rc=$? 判定行=$(grep -ac 'ROSTERDIFF-ROW\|D[0-9]' "build/evidence/r132_${name}_diff_vs_r132.txt")"
  rpt=$(ls "$OUT"/timing_summary.rpt "$OUT"/*timing_summary*.rpt 2>/dev/null | head -1)
  if [ -n "$rpt" ]; then
    cp "$rpt" "build/evidence/r132_${name}_timing_summary.rpt"
    say "$name 时序摘要已归档：$(md5sum < "$rpt" | cut -c1-12)"
  else
    say "$name NOT PROVEN：隔离目录里没有 timing_summary.rpt"
  fi
  ut=$(ls "$OUT"/utilization.rpt "$OUT"/*utilization*.rpt 2>/dev/null | head -1)
  [ -n "$ut" ] && cp "$ut" "build/evidence/r132_${name}_utilization.rpt" && say "$name 资源报告已归档"
  return 0
}

say "基线 = r132 现版名册（$(md5sum < "$BASE" | cut -c1-12)，八对读数见 build/evidence/r132_after_roster_probefmt.txt）"
arm tmdswindow    VP_R119_TMDS_WINDOW=1
arm rgmiiwindow   VP_R116_IO_WINDOW=1
# 臂 C（复制 owner_eth 这只"高扇出旗标"）不起飞——它的前提已被净表读数否掉：
#   u_pl/u_arb/owner_eth_reg/Q 驱动的网络是 u_pl/u_arb/dbg_src[0]，负载 5 个
#   （凭据 build/evidence/r132_owner_fanout.txt；report_high_fanout_nets 的名册里 r132 与 r118
#    两轮都没有 owner 这一条，榜首是 2546 负载的 gmii_rx_clk）。
#   5 负载的旗标做复制不会改变布线距离，所以这一臂要量的东西不成立；省下的一次构建记在这儿，
#   免得下次又有人去跑它。报告里"高扇出旗标的复制与摆放"那句按这条读数改口。
say "臂 C 判 NOT RUN：前提被净表读数否掉（owner_eth 扇出 5，不是高扇出广播网）"
say "三条臂跑完。判定要逐格念 build/evidence/r132_*_diff_vs_r132.txt 与两份摘要，别只看 rc。"
# 有一条臂没量到就以非零码收尾：静默的"跑过了"是最坏的一种假绿
FAILS=0
for n in tmdswindow rgmiiwindow; do
  [ -s "build/evidence/r132_${n}_roster.txt" ] || { echo "ARM NOT PROVEN: $n"; FAILS=$((FAILS+1)); }
done
[ "$FAILS" = 0 ] || { say "$FAILS 条臂没量到 —— 链子以非零码收尾"; exit 1; }
exit 0

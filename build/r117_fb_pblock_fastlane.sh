#!/usr/bin/env bash
# build/r117_fb_pblock_fastlane.sh —— clk_fpga_0 那把"未到极限"的刀，先用快车道预验（8~9 分钟/滚，两滚）
# 靶子来自 report/timing/limit_audit_r116.md：最差路 1 级逻辑 / 93.6 % 布线 ⇒ 是"离得远"不是"器件慢"。
# 判据（成对，H3 合法：同一份 opt.dcp、同一个工具、只差这一块 Pblock）：
#   P1 机制：B 滚必须有 PB_RESIZE rc=no-error + PB_CELLS>0（否则 MECHANISM_INERT，不许写成"没收益"）
#   P2 收益：clk_fpga_0 的 WNS 在 B 滚必须严格优于 A 滚，且**相对余量**要报出来（10 ns 周期）
#   P3 代价：另外三域（eth_rxc/clkout0_1/sys_clk）任何一格从 MET 掉进违例 ⇒ 判负（H2）
#   P4 代价：route 失败/未收敛 ⇒ 直接判负
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
W=build/evidence/r117_fb_pblock; mkdir -p "$W/A" "$W/B"; : > "$W/driver.log"
say(){ printf '[fbpb %s] %s\n' "$(date +%H:%M:%S)" "$*"; tee -a "$W/driver.log"; }
[ -f "$V/vivado.bat" ] || { say "REFUSE no vivado"; exit 2; }
for m in none pblock; do
    d=A; [ "$m" = pblock ] && d=B
    say "滚 $d (mode=$m) 起跑"
    PB_MODE=$m PB_OUT="$W/$d" PB_TARGET='u_pl/u_bilin/u_fb' \
      "$V/vivado.bat" -mode batch -nojournal -source build/tcl/pb117_roll.tcl \
      > "$W/$d/roll_console.txt" 2>&1
    say "滚 $d rc=$? ROLLDONE=$(grep -ac '^ROLLDONE' "$W/$d/roll_console.txt")"
done
row(){ grep -a "^ROW $2 |" "$W/$1/roll_console.txt" | head -1 | cut -d'|' -f2 | awk '{print $1, $5}'; }
for c in clk_fpga_0 eth_rxc clkout0_1 sys_clk; do
    a=$(row A $c); b=$(row B $c)
    say "域 $c  A=[$a]  B=[$b]"
done
say "MECHANISM: $(grep -a -m1 '^PB_RESIZE' "$W/B/roll_console.txt") / $(grep -a -m1 '^PB_CELLS' "$W/B/roll_console.txt")"
say "判读：P2/P3 由上面四行逐域念；两滚都要有 ROLLDONE，缺一个就是尺子的账不是设计的账"

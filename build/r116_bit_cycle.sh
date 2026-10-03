#!/usr/bin/env bash
# build/r116_bit_cycle.sh —— 刷某一份位流 + 推 50 秒真实流量 + 读硬件健康计数（A/B 对照用）
#
#   用法：bash build/r116_bit_cycle.sh <标签> [位流路径]
#   不给位流就是 build/system.bit（当前出货那份）。
#
# 为什么要"先 rst -system 再 program_pl"：#315 量到 **app 在跑的时候重刷 PL 会把控制台弄哑**
# （JTAG 里两个 A9 还显示 Running，但串口一个字节都不回）。所以每一轮都从系统复位起手。
# 为什么必须带流读数：#316 量到 drop_words=0 在 eth_live=0 时是零样本通过，不算测过。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
export VP_XSDB=${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}
X="$VP_XSDB"
LBL=${1:?用法: bit_cycle <标签> [位流]}
BIT=${2:-}
D=build/evidence/r116_board; mkdir -p "$D"
F="$D/cycle_$LBL.log"; : > "$F"
say(){ printf '[%s %s] %s\n' "$LBL" "$(date +%H:%M:%S)" "$*" | tee -a "$F"; }
[ -f "$X" ] || { say "REFUSE no xsdb"; exit 2; }

say "0) JTAG rst -system（先把可能楔住的 app 放开）"
"$X" build/tcl/r116_jtag_recover.tcl >> "$F" 2>&1; say "recover rc=$?"
sleep 3
say "1) ps_jtag_boot"
"$X" build/tcl/ps_jtag_boot.tcl >> "$F" 2>&1; say "boot rc=$?"
grep -q 5A5AA5A5 "$F" || { say "REFUSE DDR_ECHO 没过"; exit 3; }
say "2) program_pl ${BIT:-build/system.bit}"
if [ -n "$BIT" ]; then VP_BIT="$BIT" "$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1
else "$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1; fi
say "pl rc=$? PROGRAMMED=$(grep -ac PROGRAMMED "$F")"
grep -q PROGRAMMED "$F" || { say "REFUSE 没烧进去"; exit 4; }
say "3) ps_app_reload"
"$X" build/tcl/ps_app_reload.tcl >> "$F" 2>&1; say "app rc=$? FLOW_DONE=$(grep -ac FLOW_DONE "$F")"
sleep 5
say "4) 起流 50 s（512x300@60 ≈ 147 Mbps，不限速）"
nohup python src/host/video_sender.py --demo --seconds 50 --fps 60 --pace-mbps 0 --no-ping \
    > "$D/sender_$LBL.log" 2>&1 &
SPID=$!
sleep 12
node src/host/health_read.mjs --json > "$D/health_${LBL}_a.json" 2>/dev/null; say "读 A rc=$?"
sleep 18
node src/host/health_read.mjs --json > "$D/health_${LBL}_b.json" 2>/dev/null; say "读 B rc=$?"
wait $SPID 2>/dev/null
say "5) 摘要"
node -e '
const fs=require("fs");
for (const t of ["a","b"]) {
  const f=process.argv[1]+"_"+t+".json";
  try { const j=JSON.parse(fs.readFileSync(f,"utf8")); const ss=j.src_state||{};
    const g=k=>{const m=JSON.stringify(j).match(new RegExp("\""+k+"\"\\\\s*:\\\\s*([^,}]+)"));return m?m[1]:"?";};
    console.log(`  ${t}: eth_live=${ss.eth_live} owner_eth=${ss.owner_eth} drop_words=${j.drop_words} pkt_err=${g("pkt_err")} frames_bad=${g("frames_bad")} drop_seen=${g("drop_seen")}`);
  } catch(e){ console.log("  "+t+" NO_JSON "+e.message.slice(0,50)); }
}' "$D/health_${LBL}" 2>&1 | tee -a "$F"
say "done"

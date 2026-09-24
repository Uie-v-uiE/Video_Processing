#!/bin/bash
# build/board_verify.sh —— 板子上电、三件套刷好之后，一条命令跑完"机器能判的那一半"验收。
#
#   bash build/board_verify.sh              # 只跑不需要推流的那几项（读回口 + 开机自检）
#   bash build/board_verify.sh --stream     # 再加：推流 → 仲裁交接 → 停流交回（要 ~2 min）
#   bash build/board_verify.sh --battery    # 再加：串口命令电池（51 条，会改板上控制字并复原）
#
# 为什么要这个脚本：这些判据以前是我半夜手敲一串命令跑的，**别人复现不了**（比赛要审"他人能否复现"）。
# 现在把顺序、判据、以及"每一项看哪一行输出"固定在一个文件里，跑完把日志留在 build/evidence/。
#
# 不做什么：不刷板子。三件套（bit/xsa/elf）的下载顺序见 README.md「板上跑法」，
# 那一步会动硬件，故意留给人（或我）一条一条确认。脚本开头会把三件 md5 打出来，便于和
# build/frozen_*/MANIFEST.md 对账。
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT=$PWD
OUT=build/evidence/verify_$(date +%m%d_%H%M)
mkdir -p build/evidence
LOG=$OUT.txt
XSDB='"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"'

DO_STREAM=0; DO_BATT=0        # `set -u` 在下面，未初始化就直接引用会退出
# 两个开关可以任意顺序、任意组合（原来是"只认前两个参数"，写 --stream --battery 会把 battery 吃掉）
for a in "$@"; do
  case "$a" in
    --stream)  DO_STREAM=1 ;;
    --battery) DO_BATT=1 ;;
    -h|--help) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "忽略未知参数：$a（可用：--stream --battery --help）" >&2 ;;
  esac
done

echo "== board_verify $(date '+%F %T') ==" | tee "$LOG"
echo "工作目录：$ROOT" | tee -a "$LOG"
echo "-- 三件套（请与 build/frozen_*/MANIFEST.md 对账）--" | tee -a "$LOG"
for f in build/system.bit build/system.xsa build/ps_app.elf; do
  if [ -f "$f" ]; then echo "  $f  md5=$(md5sum "$f" | cut -c1-8)  $(stat -c %y "$f" | cut -c1-16)" | tee -a "$LOG"
  else echo "  $f  缺失" | tee -a "$LOG"; fi
done

echo "-- 1) 串口现在在说什么（活着、在播、没报错）--" | tee -a "$LOG"
# ⚠ 第一版这里想抓的是 [BOOT]/[CFG]/[TEMP] 那几行横幅 —— 抓不到：**横幅只在 app 被下载的那一刻打一次**。
#    单独开捕获只会看到 [SD] 的周期回声。要看横幅就一边重下 app 一边抓（r54 实测可用的两行）：
#      (powershell -File board/uart_cap_once.ps1 -Port COM6 -Seconds 14 -Out build/uart_r54_boot.txt &)
#      sleep 2; xsdb.bat build/tcl/ps_app_reload.tcl
powershell -NoProfile -ExecutionPolicy Bypass -File board/uart_cap_once.ps1 \
  -Port COM6 -Seconds 4 -Out "$OUT.boot.txt" >/dev/null 2>&1
for pat in '\[SD\] frame' '\[SD\] play refused' '\[SD\] mount failed' '\[TEMP!\]' '!!'; do
  hit=$(grep -a -m1 "$pat" "$OUT.boot.txt" 2>/dev/null || true)
  echo "  $pat → ${hit:-（没有这行）}" | tee -a "$LOG"
done

echo "-- 2) 读回口：health_read（lane0..9 + 23..31）--" | tee -a "$LOG"
node src/host/health_read.mjs --json > "$OUT.health.json" 2>"$OUT.health.err"
if [ -s "$OUT.health.json" ]; then
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const ok = (k, v) => console.log(`  ${k} → ${v}`);
    ok("lane30 src_state", JSON.stringify(j.src_state));
    ok("lane23 zoom", JSON.stringify(j.zoom));
    ok("lat.osd_ms_matches_tot", j.lat && j.lat.osd_ms_matches_tot);
    ok("drop_words", j.drop_words);
  ' "$OUT.health.json" 2>&1 | tee -a "$LOG"
else
  echo "  health_read 没有输出（hw_server 没起？A9 没在跑？）：$(head -2 "$OUT.health.err")" | tee -a "$LOG"
fi

if [ "$DO_STREAM" = 1 ]; then
  # arb_handover_test 自己会 spawn video_sender（参数 IP/SPORT/FPS 在它内部），所以这里不再另起推流；
  # 一次跑完 PRE→STREAM→AFTER→RESTART 四个阶段，约 40 s + 采样，八条判据打在 stdout。
  echo "-- 3) 仲裁交接八条（脚本内部会自己开关推流；含新的 V7 原因位自洽）--" | tee -a "$LOG"
  node src/host/arb_handover_test.mjs 2>&1 | tee "$OUT.arb.txt" | tail -22 | tee -a "$LOG"
  grep -a "arb_handover_last.json" "$OUT.arb.txt" >/dev/null 2>&1 || true
  cp -f build/evidence/arb_handover_last.json "$OUT.arb.json" 2>/dev/null || \
    cp -f /tmp/arb_handover_last.json "$OUT.arb.json" 2>/dev/null || true
fi

if [ "$DO_BATT" = 1 ]; then
  echo "-- 4) 串口命令电池（51 条 + 初末态必须相同）--" | tee -a "$LOG"
  node src/host/uart_cmd_check.mjs --port COM6 2>&1 | tail -25 | tee -a "$LOG"
fi

echo "== 日志留在 $LOG ==" | tee -a "$LOG"

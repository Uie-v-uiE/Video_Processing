#!/usr/bin/env bash
# build/r116_flash_experiment.sh —— 把 r116 这一版当**极限判据的实验件**刷上板（不是采纳）。
# 三步与采纳链完全同一套脚本、同一套标记（DDR_ECHO / PROGRAMMED / FLOW_DONE），
# 差别只在：采纳链要求门禁先全绿，而这一版的 I/O 族是**声明过的红**，
# 所以走这一支独立的实验刷板，判据是 1000M 实流量的 bad / drop_words（板侧唯一真判据）。
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
X=${VP_XSDB:-"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"}
F=build/r116_flash_console.txt; : > "$F"
say(){ printf '[flash %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f "$X" ] || { say "REFUSE 没有 xsdb：$X"; exit 2; }
say "位流身份 md5=$(md5sum build/system.bit | cut -c1-12) mtime=$(date -r build/system.bit '+%H:%M')"
say "步骤 1/3 ps_jtag_boot"
"$X" build/tcl/ps_jtag_boot.tcl >> "$F" 2>&1; say "ps_jtag_boot rc=$?"
grep -q "5A5AA5A5" "$F" || { say "REFUSE DDR_ECHO 没过（不往下烧）"; exit 3; }
say "步骤 2/3 program_pl"
"$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1; say "program_pl rc=$?"
grep -q "PROGRAMMED" "$F" || { say "REFUSE 没看到 PROGRAMMED"; exit 4; }
say "步骤 3/3 ps_app_reload"
"$X" build/tcl/ps_app_reload.tcl >> "$F" 2>&1; say "ps_app_reload rc=$?"
grep -q "FLOW_DONE" "$F" || { say "REFUSE 没有 FLOW_DONE（应用没跑起来）"; exit 5; }
say "三步完成，开始 board_verify --geom --battery --round=r116"
VP_VIVADO_BIN="$V" VP_XSDB="$X" bash build/board_verify.sh --geom --battery --round=r116 \
    > build/r116_board_verify_console.txt 2>&1; say "board_verify rc=$?"
grep -a -E "BV-SUMMARY|RESULT|bad|drop_words|FAIL" build/r116_board_verify_console.txt | tail -20
say "实验刷板结束"

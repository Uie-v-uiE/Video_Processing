#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
V=${VP_VIVADO_BIN:-/d/Software/Vivado/2025.2.1/Vivado/bin}
X=${VP_XSDB:-"D:/Software/Vivado/2025.2.1/Vitis/bin/xsdb.bat"}
F=build/r116_recover_console.txt; : > "$F"
say(){ printf '[rec %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
say "1) JTAG rst -system"; "$X" build/tcl/r116_jtag_recover.tcl >> "$F" 2>&1; say "recover rc=$?"
grep -a "RST_SYSTEM\|RECOVER_REFUSE\|TARGETS_AFTER" -A3 "$F" | tail -8
sleep 3
say "2) ps_jtag_boot"; "$X" build/tcl/ps_jtag_boot.tcl >> "$F" 2>&1; say "boot rc=$? DDR_ECHO=$(grep -ac 5A5AA5A5 "$F")"
grep -q "5A5AA5A5" "$F" || { say "REFUSE DDR_ECHO"; exit 3; }
say "3) program_pl"; "$V/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl >> "$F" 2>&1; say "pl rc=$? PROGRAMMED=$(grep -ac PROGRAMMED "$F")"
say "4) ps_app_reload"; "$X" build/tcl/ps_app_reload.tcl >> "$F" 2>&1; say "app rc=$? FLOW_DONE=$(grep -ac FLOW_DONE "$F")"
sleep 6
say "5) serial probe"; powershell -NoProfile -ExecutionPolicy Bypass -File build/probe_com6.ps1 2>&1 | head -6
say "done"

#!/bin/bash
# 作用：一条命令把 Vivado 工程与 Vitis 平台在 board/ 下重建出来（把 build_system_axigpio.tcl 的两个
#      环境变量收在这里，省得每个人自己记 VP_PROJ_SUBDIR / VP_OUTDIR / VP_VITIS_WS 怎么配）。
# 输入：可选第一个参数 = Vitis server 端口（默认 8901）；环境变量 VP_VIVADO_BIN、VP_VITIS_BIN 指到
#      各自 bin 目录（缺 VP_VIVADO_BIN 直接 REFUSE，不猜路径）。
# 输出：vivado_system/ 工程目录与 build/ 下的 system.bit / system.xsa / 各报告（VP_OUTDIR 默认 board/project）；
#      Vitis 平台 workspace 在 board/vitis_ws/（36 MB 级，.gitignore 挡住，不入库也不随包）；
#      stdout 每条命令一行结论，末尾 REBUILD_ALL_DONE 或 REBUILD_ALL_FAIL <阶段>。
# 退出码：0=两步都成；2=缺 VP_VIVADO_BIN；1=任一步失败。
set -u
cd "$(dirname "$0")/../.." || exit 2
V="${VP_VIVADO_BIN:-}"
[ -n "$V" ] || { echo "REFUSE: 要先设 VP_VIVADO_BIN=<Vivado>/bin（写法见 report/build.md §1）"; exit 2; }
PORT="${1:-8901}"
OUT="${VP_OUTDIR:-board/project}"
SUB="${VP_PROJ_SUBDIR:-board/vivado_system}"

echo "[1/2] Vivado：工程建在 $SUB，产物落 $OUT"
mkdir -p "$OUT"
VP_PROJ_SUBDIR="$SUB" VP_OUTDIR="$OUT" "$V/vivado.bat" -mode batch -nojournal \
  -log "$OUT/rebuild_console.log" -source build/tcl/build_system_axigpio.tcl || { echo "REBUILD_ALL_FAIL vivado"; exit 1; }
grep -a "timing constraints are met" "$OUT/timing_summary.rpt" >/dev/null 2>&1 \
  && echo "  时序：All user specified timing constraints are met." \
  || echo "  时序：报告里没念到那句结论，去看 $OUT/timing_summary.rpt"

if [ -n "${VP_VITIS_BIN:-}" ]; then
  echo "[2/2] Vitis：起 server 在端口 $PORT，再跑 board/scripts/rebuild_vitis.py"
  ( nohup "$VP_VITIS_BIN/vitis-server" --port "$PORT" > "$OUT/vitis_server.log" 2>&1 & )
  sleep 12
  VP_VITIS_WS="$PWD/board/vitis_ws" "$VP_VITIS_BIN/vitis.bat" -s board/scripts/rebuild_vitis.py "$PORT" \
    || { echo "REBUILD_ALL_FAIL vitis"; exit 1; }
  grep -qa "VITIS_REBUILD_DONE" "$OUT/vitis_server.log" 2>/dev/null || true
else
  echo "[2/2] Vitis：跳过（没设 VP_VITIS_BIN；平台那一步的跑法见 board/scripts/rebuild_vitis.py 头部）"
fi
echo "REBUILD_ALL_DONE"

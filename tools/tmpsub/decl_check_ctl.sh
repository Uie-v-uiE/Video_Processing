#!/usr/bin/env bash
# 一次性对照器：把导出器 §3.11d 的那段循环原样搬出来，指到"任意一份 MANIFEST 文本"上跑。
# 用法： bash /d/Xilinx/Prj/pro/tmpsub/decl_check_ctl.sh <MANIFEST 文件>
# 退出码：0=未点名 0；1=有未点名层。只是对照，不写任何东西。
set -uo pipefail
M="$1"
[ -f "$M" ] || { echo "REFUSE 清单不在 $M"; exit 2; }
UNDECL=""; DECL_N=0
for d in */ ; do
  dn="${d%/}"
  DECL_N=$((DECL_N+1))
  grep -qF -- "$dn/" "$M" || UNDECL="$UNDECL $dn/"
done
for d in */*/ ; do
  n=$(find "$d" -type f 2>/dev/null | wc -l)
  [ "$n" -ge 300 ] || continue
  DECL_N=$((DECL_N+1))
  grep -qF -- "$(basename "$d")" "$M" || UNDECL="$UNDECL $d($n 支)"
done
echo "核到 $DECL_N 层；未点名=$( [ -n "$UNDECL" ] && echo "$UNDECL" || echo 0 )"
[ -n "$UNDECL" ] && exit 1
exit 0

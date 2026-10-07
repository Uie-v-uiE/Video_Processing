#!/usr/bin/env bash
# Prj/pro/md2pdf_run.sh —— 一份交付文档从 .md 到 A4 PDF 的两步流水线，包成可重跑的一条命令。
# 为什么要有这一支：PDF/ 那几份是 headless Edge 从 HTML 印出来的，以前手敲两步；
# 源文档一改（今天 16:40 那笔把 OSD 那句改对）PDF 就悄悄变旧，而没有任何尺子读 PDF 的正文。
# 用法：bash md2pdf_run.sh <in.md> <out.pdf> [标题]     （中间 HTML 落 in.md 同目录同名 .html）
# 判据：产物 PDF 存在且 >10 KB，**而且字节摘要必须与开跑前那份不同**（见下面的 REFUSE 5）；
#       stdout 打 PDF字节 / PAGES / 页面尺寸（pypdf 现读）
set -uo pipefail
IN="${1:?用法: bash md2pdf_run.sh <in.md> <out.pdf> [标题]}"
OUTPDF="${2:?要一个 .pdf 输出路径}"
TITLE="${3:-$(basename "$IN" .md)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -f "$EDGE" ] || { echo "REFUSE 找不到 Edge：$EDGE"; exit 2; }
[ -f "$IN" ] || { echo "REFUSE 读不到源文档：$IN"; exit 2; }

# 输出路径一律先绝对化：2026-10-07 18:58 就是栽在这里——传相对路径时 Edge **不报错也不写文件**
# （`--print-to-pdf=PDF\x.pdf` 它按自己的 cwd 解，解不到就什么都不做），EDGE_RC 仍是 0，
# 而下一行的"PDF > 10 KB"读的是**旧的产物**，于是一句"重印过了"是假的。
OUTDIR_ABS="$(cd "$(dirname "$OUTPDF")" 2>/dev/null && pwd)" || { echo "REFUSE 输出目录不存在：$(dirname "$OUTPDF")"; exit 2; }
OUTABS="$OUTDIR_ABS/$(basename "$OUTPDF")"
INABS="$(cd "$(dirname "$IN")" && pwd)/$(basename "$IN")"
MD5_BEFORE=$( [ -f "$OUTABS" ] && md5sum "$OUTABS" | cut -c1-12 || echo NONE )
MD5_SRC_BEFORE=$(md5sum "$INABS" | cut -c1-12)

# HTML 名字跟着 PDF 输出走（host-guide.pdf ⇄ host-guide.html），不再跟着源文件名，
# 免得一次重印在 PDF/ 里长出第二种拼法（今天 18:58 那次就同时留下 host-guide.html 与 host_guide.html）。
TMPHTML="$OUTDIR_ABS/$(basename "$OUTABS" .pdf).html"
node "$HERE/md2pdf.mjs" "$INABS" "$TMPHTML" "$TITLE" || { echo "REFUSE md2pdf 失败"; exit 3; }
# Edge 是 Windows 程序：HTML 与 PDF 两个路径都要给 Windows 形状，URL 用 file:///C:/…
WINHTML="$(cygpath -w "$TMPHTML" | tr '\\' '/')"
WINPDF="$(cygpath -w "$OUTABS")"
"$EDGE" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
  --print-to-pdf="$WINPDF" "file:///$WINHTML" > /dev/null 2>&1
echo "EDGE_RC=$? PDF字节=$(wc -c < "$OUTABS" 2>/dev/null || echo 0) 源=$INABS HTML=$TMPHTML"
[ "$(wc -c < "$OUTABS" 2>/dev/null || echo 0)" -gt 10000 ] || { echo "REFUSE PDF 太小 ⇒ 这一版不算产出"; exit 4; }
MD5_AFTER=$(md5sum "$OUTABS" | cut -c1-12)
if [ "$MD5_AFTER" = "$MD5_BEFORE" ]; then
  echo "REFUSE 产物字节摘要没变（$MD5_BEFORE → $MD5_AFTER）⇒ Edge 其实没重写这一份，别念成'已重印'"
  echo "        源文档摘要 $MD5_SRC_BEFORE，目标 $OUTABS"
  exit 5
fi
echo "重印成立：$MD5_BEFORE → $MD5_AFTER（源摘要 $MD5_SRC_BEFORE）"
PYTHONIOENCODING=utf-8 python - "$OUTABS" <<'PY'
import sys
try:
    from pypdf import PdfReader
except Exception as e:
    print("PAGES=NOT_MEASURED (pypdf 不可读:", e, ")"); sys.exit(0)
r = PdfReader(sys.argv[1])
bb = r.pages[0].mediabox
print(f"PAGES={len(r.pages)} 页面尺寸mm={round(float(bb.width)/72*25.4,1)}x{round(float(bb.height)/72*25.4,1)}")
PY

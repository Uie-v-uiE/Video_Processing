import os
# -*- coding: utf-8 -*-
"""把原理图/手册 PDF 的一页按点坐标裁成可读小图（4x 渲染）。

为什么要有它：`Read` 工具读 PDF 要 poppler（本机没装），而 pypdfium2 的 `search()` 对某些
词（例如 `PHY1_RXD0`）明明文本流里有却说没有 —— 于是**不再跟接口较劲**：先用文本层拿到一个
已知命中的坐标，再按坐标裁邻域用眼睛读。r116 的 RGMII strap 就是这么读出来的。

用法：python build/render_sch_crop.py <页码> <x0> <y0> <x1> <y1> <输出名>
      （坐标是 PDF 点，y 从下往上；输出落 build/evidence/r115_sch_p<页>/<输出名>.png）
"""
import sys

import pypdfium2 as pdfium

PDF = os.environ.get("VP_PDF", "")  # 原理图 PDF 在本机的位置，交付包里不写死
if not PDF:
    raise SystemExit("需要环境变量 VP_PDF（原理图 PDF 的路径）")
page = int(sys.argv[1])
x0, y0, x1, y1 = [float(v) for v in sys.argv[2:6]]
name = sys.argv[6]
SCALE = 4.0

doc = pdfium.PdfDocument(PDF)
p = doc[page - 1]
img = p.render(scale=SCALE).to_pil()
W, H = img.width, img.height
px0 = max(0, int(x0 * SCALE)); px1 = min(W, int(x1 * SCALE))
py0 = max(0, int(H - y1 * SCALE)); py1 = min(H, int(H - y0 * SCALE))
out = "build/evidence/r115_sch_p%d/%s.png" % (page, name)
img.crop((px0, py0, px1, py1)).save(out)
print("CROP page=%d pt=%.0f,%.0f..%.0f,%.0f px=%d,%d..%d,%d size=%dx%d -> %s"
      % (page, x0, y0, x1, y1, px0, py0, px1, py1, px1 - px0, py1 - py0, out))

# -*- coding: utf-8 -*-
"""把原理图第 8 页（PHY 那页）**渲染成图片**，好让人（和我）用眼睛看 strap 电阻接到哪。

为什么走这条路（00:18）：`system_top.v:113-117` 已经写明**本工程不碰 MDIO**（`eth_mdio = 1'bz`、`eth_mdc = 0`）
⇒ PL 侧那只 RTL8211F 的工作模式**完全由板上 strap 决定**，寄存器也读不到；
而 `docs/timing/rgmii_window_model.md` §7.3 那个窗模型的唯一未知量就是
`TXDLY/RXDLY`（第 23/24 脚，与 RXD1/RXD0 复用）复位时被什么拉着。
文本抽取只能看到引脚名与一堆位号，看不到"谁接谁"——**这类图必须用眼睛读**。

`Read` 工具读 PDF 要 poppler（本机没有），但它能读 PNG ⇒ 用 pypdfium2 渲染。
分左/右两半各渲一张，缩放到能看清 4.7K 上拉/下接到哪个网络为止。
"""
import os
import sys

import pypdfium2 as pdfium

PDF = os.environ.get("VP_PDF", "")  # 原理图 PDF 在本机的位置，交付包里不写死
if not PDF:
    raise SystemExit("需要环境变量 VP_PDF（原理图 PDF 的路径）")
OUTDIR = "build/evidence/r115_sch_p8"
PAGE = 8                     # 1-based：PHY 那一页
SCALE = 4.0                  # 288 dpi

os.makedirs(OUTDIR, exist_ok=True)
doc = pdfium.PdfDocument(PDF)
page = doc[PAGE - 1]
w, h = page.get_size()         # pt
bmp = page.render(scale=SCALE)
img = bmp.to_pil()
print("PAGE_PX=%dx%d" % (img.width, img.height))
half = img.width // 2
paths = []
for name, box in (("left", (0, 0, half, img.height)), ("right", (half, 0, img.width, img.height))):
    p = os.path.join(OUTDIR, "p8_%s.png" % name)
    img.crop(box).save(p)
    paths.append(p)
    print("WROTE %s %dx%d" % (p, img.crop(box).width, img.crop(box).height))
# 再各切上下两半，供"看不清就放大"的下一步用
for name, box in (("tl", (0, 0, half, img.height // 2)), ("bl", (0, img.height // 2, half, img.height)),
                  ("tr", (half, 0, img.width, img.height // 2)), ("br", (half, img.height // 2, img.width, img.height))):
    p = os.path.join(OUTDIR, "p8_%s.png" % name)
    img.crop(box).save(p)
    paths.append(p)
print("PARTS=%d" % len(paths))

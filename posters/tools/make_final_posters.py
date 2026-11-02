# -*- coding: utf-8 -*-
"""Fill the AMD poster template in place; do not move or restyle its layout."""
import os
from copy import deepcopy

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE_TYPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt
from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
TPL = r"D:\Software\QQ\QQ_File\AMD_poster_template (1).pptx"
OUT = os.path.join(ROOT, "submission", "deliverables")
ASSETS = os.path.join(ROOT, "records", "design", "assets", "template_poster")
LOGO = os.path.join(ROOT, "records", "design", "assets", "hut_emblem.png")

DARK = RGBColor(0x1F, 0x2A, 0x44)
GRAY = RGBColor(0x2B, 0x2B, 0x2B)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
RED = RGBColor(0xB9, 0x1C, 0x1C)
BLUE = RGBColor(0x1F, 0x4E, 0x79)
CN_FONT = "Microsoft YaHei"
EN_FONT = "Calibri"


def by_id(slide, sid):
    for sh in slide.shapes:
        if sh.shape_id == sid:
            return sh
    raise KeyError(sid)


def set_text(shape, paras, font=CN_FONT, align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, margins=(0.02, 0.01, 0.02, 0.01), line=1.0):
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left, tf.margin_top, tf.margin_right, tf.margin_bottom = [Inches(m) for m in margins]
    for i, (text, size, bold, color) in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.line_spacing = line
        p.space_before = Pt(0)
        p.space_after = Pt(1)
        r = p.add_run()
        r.text = text
        r.font.name = font
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.color.rgb = color
        rPr = r._r.get_or_add_rPr()
        ea = rPr.find("{http://schemas.openxmlformats.org/drawingml/2006/main}ea")
        if ea is None:
            from pptx.oxml.ns import qn
            ea = rPr.makeelement(qn("a:ea"), {})
            rPr.append(ea)
        ea.set("typeface", font)


def add_box(slide, left, top, width, height):
    tb = slide.shapes.add_textbox(Inches(left), Inches(top), Inches(width), Inches(height))
    return tb


def replace_pic(slide, shape, path):
    left, top, width, height = shape.left, shape.top, shape.width, shape.height
    sp = shape._element
    sp.getparent().remove(sp)
    return slide.shapes.add_picture(path, left, top, width=width, height=height)


def fit_image(src, dst, w, h):
    im = Image.open(src).convert("RGB")
    im = ImageOps.fit(im, (int(w), int(h)), Image.LANCZOS)
    im.save(dst, quality=94)
    return dst


def remove_shape(shape):
    sp = shape._element
    sp.getparent().remove(sp)


def set_master_copyright(prs, text):
    for sh in prs.slides[0].slide_layout.slide_master.shapes:
        if sh.has_text_frame and "Copyright" in sh.text:
            set_text(sh, [(text, 10, False, GRAY)])
            return


def build(lang):
    cn = lang == "cn"
    font = CN_FONT if cn else EN_FONT
    prs = Presentation(TPL)
    s = prs.slides[0]
    set_master_copyright(prs, "版权所有 2026" if cn else "Copyright 2026")

    # Remove template instruction notes.
    for sid in [48, 49, 50, 51, 52, 53, 54, 55, 56]:
        try:
            remove_shape(by_id(s, sid))
        except KeyError:
            pass

    # Title
    if cn:
        title_paras = [("多源视频同帧对照处理系统", 20, True, DARK),
                       ("基于 Zynq-7020 的全硬件视频通路与可观测性设计", 14.5, False, DARK)]
    else:
        title_paras = [("One Frame, Two Truths", 20, True, DARK),
                       ("A Multi-Source Video Node on Zynq-7020", 20, True, DARK)]
    set_text(by_id(s, 9), title_paras, font=font, line=0.95)
    by_id(s, 9).height = Inches(0.72)

    # Team and school (template positions unchanged).
    set_text(by_id(s, 29), [("王旭 · Uie_Team" if cn else "Wang Xu · Uie_Team", 9.5, True, DARK)], font=font, align=PP_ALIGN.LEFT)
    if cn:
        school = "指导老师：Tan Huisheng · Liang Jiaojiao\n湖南工业大学 · 湖南省\n平台：RK-ZYNQ7020-F / xc7z020clg484-2"
    else:
        school = "Advisors: Tan Huisheng · Liang Jiaojiao\nHunan University of Technology, Hunan Province\nPlatform: RK-ZYNQ7020-F / xc7z020clg484-2"
    set_text(by_id(s, 31), [(school, 8.0, False, GRAY)], font=font, line=0.95)
    by_id(s, 31).width = Inches(2.55)
    by_id(s, 31).height = Inches(0.98)

    # Section headers: horizontal ones translated; vertical template labels stay.
    set_text(by_id(s, 8), [("作品介绍" if cn else "INTRODUCTION", 19, True, WHITE)], font=font, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    set_text(by_id(s, 43), [("系统架构" if cn else "SYSTEM ARCHITECTURE", 13, True, DARK)], font=font, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    set_text(by_id(s, 11), [("典型应用场景" if cn else "Typical application case", 11.5, True, DARK)], font=font)

    # Left intro text, above the strip.
    if cn:
        intro = ("远程视频节点通常只有一根网线，没有 PC。操作者需要知道画面是否收到、处理是否生效、延迟多大。"
                 "本作品在 Zynq-7020 上完成全硬件处理：512×300 视频经千兆网口输入，整帧满足提交条件后写入 DDR；"
                 "显示侧读回同一帧，左侧原图、右侧处理结果。")
    else:
        intro = ("Remote video nodes usually have one Ethernet cable and no PC. The operator needs to know whether the "
                 "frame arrived, whether processing took effect, and how old the picture is. This node performs the path "
                 "on one Zynq-7020: a 512×300 stream enters through GbE, whole frames are committed after three conditions, "
                 "and both panes read back the same frame.")
    set_text(by_id(s, 7), [(intro, 8.8 if cn else 8.2, False, GRAY)], font=font, line=0.98)

    # Application and key issues at the template's left text positions.
    app = ("广播、安防和工业视觉的现场监测：现场没有采集设备时，一根网线可同时传输画面、处理结果和链路状态。" if cn else
           "Confidence monitoring for broadcast, security and industrial vision: one cable carries the picture, processing result and link status.")
    b = add_box(s, 0.25, 3.90, 3.90, 0.62)
    set_text(b, [(app, 9.2, False, GRAY)], font=font, line=0.98)
    key = ("关键技术问题\n"
           "1. 千兆 UDP 重组：按帧内偏移重组，字节数、行覆盖和坏包计数同时满足才提交。\n"
           "2. 同帧对照：两侧共用几何运算和 15 拍效果链，竖缝逐像素选择。\n"
           "3. 状态监测：作废帧、缺行数、帧间隔和时延可通过串口、遥测和 GPIO 读取。\n"
           "4. 存储：DDR 乒乓帧缓存 + 板载测试图卡。" if cn else
           "Key technical issues addressed\n"
           "1. GbE UDP reassembly: offset-based reassembly; commit only when bytes, row coverage and bad-packet count pass.\n"
           "2. Same-frame comparison: both panes share geometry and a fixed 15-cycle effect chain; the seam selects per pixel.\n"
           "3. Status monitoring: aborts, missing rows, frame gaps and latency are readable through serial, telemetry and GPIO.\n"
           "4. Storage: DDR ping-pong frame buffer + on-board test card.")
    b = add_box(s, 0.25, 4.62, 3.90, 1.95)
    parts = key.split("\n")
    paras = [(parts[0], 10.2, True, DARK)]
    for line in parts[1:]:
        paras.append((line, 8.8, False, GRAY))
    set_text(b, paras, font=font, line=0.97)

    # Center cards: template card positions/shapes retained.
    ingress = ("接收与缓存\n1. RGMII → MAC → UDP 过滤 → 按偏移重组；\n2. 字节、行覆盖和坏包计数同时满足才提交；\n3. PL 作为 AXI HP0 主设备写入 DDR 乒乓缓存。" if cn else
               "Ingress & storage\n1. RGMII → MAC → UDP filter → offset reassembly;\n2. Commit only when bytes, row coverage and bad-packet count pass;\n3. PL writes DDR ping-pong as AXI HP0 master.")
    display = ("显示与处理\n1. 显示侧读回整帧，经几何、双线性和六级效果；\n2. 同帧对照：左原图右处理图，竖缝逐像素选择；\n3. OSD + HDMI 1024×600，状态经串口/遥测/GPIO 回读。" if cn else
               "Display & processing\n1. Read back the frame; geometry, bilinear and six-stage effects;\n2. Same-frame comparison: left original, right processed, per-pixel seam;\n3. OSD + HDMI 1024×600; status via serial/telemetry/GPIO.")
    for sid, text in [(46, ingress), (45, display)]:
        sh = by_id(s, sid)
        parts = text.split("\n")
        paras = [(parts[0], 9.8, True, DARK)]
        for line in parts[1:]:
            paras.append((line, 8.2, False, GRAY))
        set_text(sh, paras, font=font, line=0.92)

    # Right column: innovation points and result, in the template's existing text block.
    right = ("创新设计\n"
             "1. 同帧对照：两侧共用几何运算、行标签和 15 拍效果链，比较的是同一帧。\n"
             "2. 提交条件与状态监测：字节数、行覆盖和坏包计数同时满足才提交；作废帧、缺行数和帧间隔可解释。\n"
             "结果\n"
             "RGMII → HDMI 全部在 PL 内，PS 仅控制；1024×600 @ 59.5 Hz。\n"
             "时序：WNS 1.368 / WHS 0.048 ns，失败端点 0。\n"
             "8 秒推流 241 帧 = 30.01 fps；自检 22.2/0/18.9 PASS。\n"
             "串口 105 条 PASS；QSPI 启动通过。\n"
             "展望：DDR 瓦片缓存 / 1080p 链路 / RGMII 眼图 / 远程升级。" if cn else
             "CREATIVE DESIGN\n"
             "1. Same-frame comparison: both panes share geometry, row labels and the fixed 15-cycle chain; the seam compares one frame.\n"
             "2. Commit conditions + status monitoring: bytes, row coverage and bad-packet count must pass; aborts, missing rows and frame gaps explain failures.\n"
             "RESULT\n"
             "RGMII → HDMI entirely in PL; PS only control. 1024×600 @ 59.5 Hz.\n"
             "Timing: WNS 1.368 / WHS 0.048 ns, zero failures.\n"
             "8 s stream: 241 frames @ 30.01 fps; selftest 22.2/0/18.9 PASS.\n"
             "UART 105 commands PASS; QSPI boot validated.\n"
             "Next: DDR tile cache / 1080p link / RGMII eye diagram / remote update.")
    sh = by_id(s, 41)
    parts = right.split("\n")
    paras = []
    for line in parts:
        if line in ("创新设计", "结果", "CREATIVE DESIGN", "RESULT"):
            paras.append((line, 10.4, True, RED))
        else:
            paras.append((line, 8.8, False, GRAY))
    set_text(sh, paras, font=font, line=0.94)

    # Platform caption under the product photo.
    plat = "系统测试 · 系统输出" if cn else "On-board test · system output"
    set_text(by_id(s, 30), [(plat, 8.2, False, GRAY)], font=font, align=PP_ALIGN.CENTER)
    by_id(s, 30).left = Inches(10.98)
    by_id(s, 30).width = Inches(2.30)
    by_id(s, 30).top = Inches(1.70)
    by_id(s, 30).height = Inches(0.28)

    # Replace template pictures at the same positions/sizes.
    replace_pic(s, by_id(s, 42), os.path.join(ASSETS, "poster_split_strip.png"))
    replace_pic(s, by_id(s, 44), os.path.join(ASSETS, "poster_arch_cn_pad.png" if cn else "poster_arch_en_pad.png"))
    replace_pic(s, by_id(s, 40), LOGO)
    replace_pic(s, by_id(s, 47), os.path.join(ASSETS, "poster_board_thumb.jpg"))

    out = os.path.join(OUT, f"poster_{lang}_editable.pptx")
    prs.save(out)
    print("WROTE", out)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    build("cn")
    build("en")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

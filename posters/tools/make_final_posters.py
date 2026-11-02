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
    by_id(s, 11).top = Inches(4.38)

    # Left intro text, above the image.
    if cn:
        intro = ("远程视频节点通常只有一根网线，没有 PC。操作者需要同时知道：画面收到没有、处理生效没有、画面多旧。"
                 "本作品在一颗 Zynq-7020 上给出全部答案：512×300 RGB565 从千兆网口输入，三闸整帧提交，两侧读回同一帧，"
                 "竖缝是逐像素决定而不是两张截图。")
    else:
        intro = ("Remote video nodes usually have one Ethernet cable and no PC. The operator must know whether the frame "
                 "arrived, whether processing took effect, and how old the picture is. This node answers all three on one "
                 "Zynq-7020: 512×300 RGB565 enters GbE, whole frames pass a three-condition commit, both panes read back the "
                 "same frame, and the seam selects per pixel.")
    set_text(by_id(s, 7), [(intro, 8.4 if cn else 7.8, False, GRAY)], font=font, line=0.97)

    # Application and key issues below the 16:9 image.
    app = ("广播、安防、工业视觉的现场监测：没有采集设备时，一根网线同时带回画面、处理结果和链路状态；"
           "同帧对照可用于算法验收与故障定位。" if cn else
           "Confidence monitoring for broadcast, security and industrial vision: one cable carries the picture, processing "
           "result and link status; same-frame comparison supports algorithm acceptance and fault isolation.")
    b = add_box(s, 0.25, 4.65, 3.90, 0.58)
    set_text(b, [(app, 8.8, False, GRAY)], font=font, line=0.98)
    key = ("关键技术问题\n"
           "1. 千兆 UDP 重组：按帧内偏移拼帧，整帧字节、行覆盖位图、无坏包三闸同时成立才提交。\n"
           "2. 同帧 A/B：两窗共用几何、行标签和固定 15 拍效果链，竖缝逐列二选一。\n"
           "3. 可观测：作废帧、缺行数、pane_bad、link 帧间隔经串口/UDP/GPIO 回读。\n"
           "4. 存储与片源：DDR3 乒乓缓存；UDP / SD 回放 / 板载图卡三路片源。\n"
           "5. 启动与测试：QSPI 固化断电自启；UART 命令电池 105 条。" if cn else
           "Key technical issues addressed\n"
           "1. GbE UDP reassembly: offset reassembly; commit only when bytes, row coverage and no-bad-packet gates all pass.\n"
           "2. Same-frame A/B: both panes share geometry, row labels and the fixed 15-cycle chain; seam selects per column.\n"
           "3. Observability: aborts, missing rows, pane_bad and link gaps via serial/UDP/GPIO.\n"
           "4. Storage & sources: DDR3 ping-pong; UDP / SD playback / on-board test card.\n"
           "5. Boot & test: QSPI cold boot; 105-command UART battery.")
    b = add_box(s, 0.25, 5.35, 3.90, 1.55)
    parts = key.split("\n")
    paras = [(parts[0], 9.6, True, DARK)]
    for line in parts[1:]:
        paras.append((line, 8.0, False, GRAY))
    set_text(b, paras, font=font, line=0.94)

    # Center cards: template card positions/shapes retained.
    ingress = ("接收与缓存\n1. RGMII + MAC + UDP 过滤，按帧内偏移重组；\n2. 三闸提交：整帧字节、行覆盖位图、无坏包；\n3. DDR3 乒乓缓存，AXI HP0 64 位突发；\n4. 三路片源：UDP / SD 回放 / 板载图卡；\n5. 整帧收满才切换显示，坏包/缺行作废；\n6. 输入带宽约 74 Mb/s。" if cn else
               "Ingress & storage\n1. RGMII + MAC + UDP filter, offset reassembly;\n2. Three gates: bytes, row-coverage bitmap, no bad packet;\n3. DDR3 ping-pong, AXI HP0 64-bit bursts;\n4. Three sources: UDP / SD playback / on-board test card;\n5. Switch only after a whole frame; bad packet/missing row abort;\n6. Input bandwidth about 74 Mb/s.")
    display = ("显示与处理\n1. 8 档缩放 + 0–359° 旋转 + 双线性；\n2. 六级效果链，延迟恒 15 拍；\n3. 同帧 A/B 竖缝，逐列选择；\n4. 五行 OSD + HDMI 1024×600；\n5. 串口/UDP/GPIO 回读同一组计数。" if cn else
               "Display & processing\n1. 8-step zoom + 0–359° rotation + bilinear;\n2. Six-stage effect chain, fixed 15-cycle latency;\n3. Same-frame A/B seam, per-column selection;\n4. Five-line OSD + HDMI 1024×600;\n5. Serial/UDP/GPIO read the same counters.")
    for sid, text in [(46, ingress), (45, display)]:
        sh = by_id(s, sid)
        parts = text.split("\n")
        paras = [(parts[0], 9.8, True, DARK)]
        for line in parts[1:]:
            paras.append((line, 8.8, False, GRAY))
        set_text(sh, paras, font=font, line=0.94)

    # Right column: innovation points and result, in the template's existing text block.
    right = ("创新设计\n"
             "1. 同帧 A/B：两窗共用几何、行标签与 15 拍链，缝上比较同一帧。\n"
             "2. 三闸提交：字节、行覆盖、坏包同时成立才提交，半帧不上屏。\n"
             "3. 可证伪仪表：pane_bad、link 帧间隔、1/100 丢包可打红。\n"
             "4. 全 PL + QSPI：收/显/效果/OSD 全在 PL，断电自启。\n"
             "结果\n"
             "WNS 1.368 / WHS 0.048 ns，0 违例；LUT 28.13%，BRAM 70.00%。\n"
             "8 s 241 帧 = 30.01 fps；自检 22.2/0/18.9；UART 105 条 PASS。\n"
             "1024×600 @ 59.5 Hz，74 Mb/s；效果链恒 15 拍；QSPI 启动通过。\n"
             "展望\n"
             "DDR 瓦片缓存提升分辨率；压缩/升级链路支持 1080p；补 RGMII 眼图与远程升级。" if cn else
             "CREATIVE DESIGN\n"
             "1. Same-frame A/B: both panes share geometry, row labels and the 15-cycle chain; the seam compares one frame.\n"
             "2. Three-gate commit: bytes, row coverage and no bad packet commit together; a half frame never reaches the screen.\n"
             "3. Falsifiable meters: pane_bad, link gaps and 1/100 packet loss turn the instrument red.\n"
             "4. All-PL + QSPI: receive/display/effects/OSD in PL; cold boot from QSPI.\n"
             "RESULT\n"
             "WNS 1.368 / WHS 0.048 ns, zero violations; LUT 28.13%, BRAM 70.00%.\n"
             "8 s: 241 frames = 30.01 fps; selftest 22.2/0/18.9; UART 105 commands PASS.\n"
             "1024×600 @ 59.5 Hz, 74 Mb/s; fixed 15-cycle chain; QSPI boot validated.\n"
             "NEXT\n"
             "DDR tile cache for higher resolution; compression/link upgrade for 1080p; RGMII eye diagram and remote update.")
    sh = by_id(s, 41)
    parts = right.split("\n")
    paras = []
    for line in parts:
        if line in ("创新设计", "结果", "展望", "CREATIVE DESIGN", "RESULT", "NEXT"):
            paras.append((line, 10.2, True, RED))
        else:
            paras.append((line, 8.4, False, GRAY))
    set_text(sh, paras, font=font, line=0.93)

    # Caption under the board+screen photo.
    plat = "系统输出 · 上板实测" if cn else "System output · on-board test"
    set_text(by_id(s, 30), [(plat, 8.2, False, GRAY)], font=font, align=PP_ALIGN.CENTER)
    by_id(s, 30).left = Inches(10.98)
    by_id(s, 30).width = Inches(2.30)
    by_id(s, 30).top = Inches(1.70)
    by_id(s, 30).height = Inches(0.28)

    # Left: one 16:9 split image, not a wide strip.
    pic = replace_pic(s, by_id(s, 42), os.path.join(ROOT, "records", "design", "assets", "poster_frame_split.png"))
    pic.left = Inches(0.55); pic.top = Inches(2.65); pic.width = Inches(2.90); pic.height = Inches(1.63)

    # Center: detailed 4x3 architecture diagram.
    replace_pic(s, by_id(s, 44), os.path.join(ASSETS, "arch_v3_zh.png" if cn else "arch_v3_en.png"))
    replace_pic(s, by_id(s, 40), LOGO)
    # Right top: previous board+screen photo, already close to the template aspect.
    replace_pic(s, by_id(s, 47), os.path.join(ROOT, "records", "design", "poster_bi", "assets", "overview.jpg"))

    # Bottom-left test/performance line, as in the previous poster.
    foot = ("测试：UART 命令电池(105) · link selftest · 遥测监听　|　性能：30.01 fps　|　素材：可商用风景视频" if cn else
            "Test: UART battery (105) · link selftest · telemetry listen　|　Performance: 30.01 fps　|　Asset: royalty-free scenery")
    b = add_box(s, 0.28, 7.22, 8.30, 0.22)
    set_text(b, [(foot, 8.4, False, GRAY)], font=font)

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

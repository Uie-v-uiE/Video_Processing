# -*- coding: utf-8 -*-
"""Build separate Chinese and English posters from the template-based deck."""
import os
from copy import deepcopy

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
SRC = os.path.join(ROOT, "submission", "deliverables", "poster_final.pptx")
OUT_DIR = os.path.join(ROOT, "submission", "deliverables")
CN_ARCH = os.path.join(ROOT, "records", "design", "assets", "poster_arch_cn.png")
LOGO = os.path.join(ROOT, "records", "design", "assets", "hut_emblem.png")

CN = RGBColor(0x1F, 0x2A, 0x44)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
GRAY = RGBColor(0x33, 0x33, 0x33)
RED = RGBColor(0xB9, 0x1C, 0x1C)
BLUE = RGBColor(0x1F, 0x4E, 0x79)


def shape_by_id(slide, sid):
    for sh in slide.shapes:
        if sh.shape_id == sid:
            return sh
    raise KeyError(sid)


def set_text(shape, paras, font="Microsoft YaHei", align=PP_ALIGN.LEFT,
             anchor=MSO_ANCHOR.TOP, margins=(0, 0, 0, 0), line=1.0):
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
        p.space_after = Pt(2)
        r = p.add_run()
        r.text = text
        r.font.name = font
        r.font.size = Pt(size)
        r.font.bold = bold
        r.font.color.rgb = color
        # East Asian font
        rPr = r._r.get_or_add_rPr()
        ea = rPr.find("{http://schemas.openxmlformats.org/drawingml/2006/main}ea")
        if ea is None:
            from pptx.oxml.ns import qn
            ea = rPr.makeelement(qn("a:ea"), {})
            rPr.append(ea)
        ea.set("typeface", font)


def replace_picture(slide, shape, path):
    left, top, width, height = shape.left, shape.top, shape.width, shape.height
    sp = shape._element
    sp.getparent().remove(sp)
    pic = slide.shapes.add_picture(path, left, top, width=width, height=height)
    return pic


def bring_front(shape):
    sp = shape._element
    parent = sp.getparent()
    parent.remove(sp)
    parent.append(sp)


def main():
    prs = Presentation(SRC)
    cn = prs.slides[0]
    en = prs.slides[1]

    # ---------------- Chinese ----------------
    set_text(shape_by_id(cn, 2), [("版权所有 2026", 10, False, GRAY)])
    set_text(shape_by_id(cn, 3), [("多源视频同帧对照处理系统\n基于 Zynq-7020 的全硬件视频通路与可观测性设计", 22, True, CN)], line=0.95)
    team4 = shape_by_id(cn, 4)
    team4.left = Inches(8.72); team4.top = Inches(0.12); team4.width = Inches(1.62); team4.height = Inches(1.34)
    set_text(team4, [
        ("团队：Uie_Team", 9, False, GRAY),
        ("队员：王旭（Wang Xu）", 9, False, GRAY),
        ("指导老师：Tan Huisheng · Liang Jiaojiao", 8.3, False, GRAY),
        ("湖南工业大学 · 湖南省", 8.5, True, CN),
        ("平台：RK-ZYNQ7020-F · xc7z020clg484-2 · Vivado/Vitis 2025.2.1", 7.0, False, GRAY),
    ], line=0.95)
    # Move the product photo and caption right to make room for the school emblem.
    photo = shape_by_id(cn, 6)
    photo.left = Inches(10.78); photo.top = Inches(0.14); photo.width = Inches(2.48); photo.height = Inches(1.24)
    cap = shape_by_id(cn, 7)
    cap.left = Inches(10.78); cap.top = Inches(1.40); cap.width = Inches(2.48); cap.height = Inches(0.22)
    set_text(cap, [("作品实物（系统输出画面）", 9, False, GRAY)], align=PP_ALIGN.CENTER)
    set_text(shape_by_id(cn, 8), [("作品介绍", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    set_text(shape_by_id(cn, 14), [("系统架构", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    set_text(shape_by_id(cn, 17), [("创新设计", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)
    set_text(shape_by_id(cn, 20), [("结果", 20, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE)

    set_text(shape_by_id(cn, 9), [(
        "远程视频节点通常只有一根网线，没有 PC。操作者需要同时知道三件事：画面是否收到、处理是否生效、画面延迟多大。"
        "本作品在 Zynq-7020 上完成全硬件处理：512×300 RGB565 视频从千兆网口输入，整帧满足提交条件后写入 DDR 乒乓缓存；"
        "显示侧读回同一帧，左侧显示原图，右侧显示处理结果，竖缝逐像素选择。", 11, False, GRAY)], line=1.05)
    set_text(shape_by_id(cn, 10), [("典型应用场景", 12.5, True, CN)])
    set_text(shape_by_id(cn, 11), [(
        "广播、安防和工业视觉的现场监测：现场没有采集设备时，一根网线可同时传输画面、处理结果和链路状态。", 11, False, GRAY)])
    set_text(shape_by_id(cn, 12), [("关键技术问题", 12.5, True, CN)])
    set_text(shape_by_id(cn, 13), [
        ("1. 千兆 UDP 重组：按帧内偏移重组，字节数、行覆盖和坏包计数同时满足才提交。", 10.5, False, GRAY),
        ("2. 同帧对照：原图和处理图共用几何运算和 15 拍效果链，竖缝逐像素选择。", 10.5, False, GRAY),
        ("3. 状态监测：作废帧、缺行数、帧间隔和时延可通过串口、遥测和 GPIO 读取。", 10.5, False, GRAY),
        ("4. 存储：DDR 乒乓帧缓存 + 板载测试图卡。", 10.5, False, GRAY),
    ], line=1.0)
    set_text(shape_by_id(cn, 16), [
        ("1. 千兆 UDP 接收与重组：RGMII → MAC → UDP 过滤 → 整帧提交；", 11, False, GRAY),
        ("2. DDR 乒乓缓存：PL 作为 AXI HP0 主设备写入双缓冲；", 11, False, GRAY),
        ("3. 几何引擎：0.25–2.00 八档缩放 + 0–359° 旋转 + 双线性插值；", 11, False, GRAY),
        ("4. 15 拍效果链：灰度/反色/模糊/锐化/Sobel/二值化/腐蚀膨胀，延迟恒定；", 11, False, GRAY),
        ("5. 同帧对照：左侧原图、右侧处理图，竖缝逐像素选择；", 11, False, GRAY),
        ("6. OSD 与状态回读：串口、遥测和 GPIO 读取同一组计数。", 11, False, GRAY),
    ], line=1.0)
    # CN creative boxes: replace rich text with two-level paragraphs
    box1 = shape_by_id(cn, 18)
    set_text(box1, [("1. 同帧对照", 13.5, True, RED),
                    ("两侧共用几何运算、行标签和固定 15 拍效果链，比较的是同一帧，而不是两张截图。", 11.5, False, GRAY)], line=1.0)
    box2 = shape_by_id(cn, 19)
    set_text(box2, [("2. 提交条件与状态监测", 13.5, True, RED),
                    ("字节数、行覆盖和坏包计数同时满足才提交；作废帧、缺行数和帧间隔可解释，1/100 丢包即可复现异常。", 11.5, False, GRAY)], line=1.0)
    set_text(shape_by_id(cn, 21), [
        ("RGMII → HDMI 全部在 PL 内完成，PS 仅负责控制；1024×600 @ 59.5 Hz。", 9.2, False, GRAY),
        ("时序：WNS 1.368 / WHS 0.048 ns，失败端点 0。", 9.2, False, GRAY),
        ("8 秒推流 241 帧 = 30.01 fps；自检 22.2/0/18.9 PASS。", 9.2, False, GRAY),
        ("串口 105 条 PASS；QSPI 启动通过。", 9.2, False, GRAY),
        ("展望：DDR 瓦片缓存 / 1080p 链路 / RGMII 眼图 / 远程升级。", 9.2, False, GRAY),
    ], line=0.9)
    res = shape_by_id(cn, 21)
    res.left = Inches(9.04); res.top = Inches(6.34); res.width = Inches(3.28); res.height = Inches(1.12)
    set_text(shape_by_id(cn, 23), [(
        "测试工具：串口命令测试(105) · 链路自检 · 遥测监听　|　性能：30.01 fps 满帧率　|　素材：可商用风景视频", 9.5, False, GRAY)])

    # Chinese architecture image
    replace_picture(cn, shape_by_id(cn, 15), CN_ARCH)

    # Make the school emblem visible and bring it to front.
    logo = shape_by_id(cn, 5)
    logo.left = Inches(10.36); logo.top = Inches(0.10); logo.width = Inches(0.38); logo.height = Inches(0.39)
    bring_front(logo)
    amd = shape_by_id(cn, 22)
    amd.left = Inches(12.50); amd.top = Inches(7.20); amd.width = Inches(0.65); amd.height = Inches(0.15)

    # ---------------- English ----------------
    set_text(shape_by_id(en, 2), [("Copyright 2026", 10, False, GRAY)])
    set_text(shape_by_id(en, 3), [("One Frame, Two Truths\nA Multi-Source Video Node on Zynq-7020", 22, True, CN)], line=0.95)
    team4 = shape_by_id(en, 4)
    team4.left = Inches(8.72); team4.top = Inches(0.12); team4.width = Inches(1.62); team4.height = Inches(1.34)
    set_text(team4, [
        ("Team: Uie_Team", 9, False, GRAY),
        ("Member: Wang Xu", 9, False, GRAY),
        ("Advisors: Tan Huisheng · Liang Jiaojiao", 8.3, False, GRAY),
        ("Hunan University of Technology, Hunan Province", 8.3, True, CN),
        ("Platform: RK-ZYNQ7020-F · xc7z020clg484-2 · Vivado/Vitis 2025.2.1", 7.0, False, GRAY),
    ], font="Calibri", line=0.95)
    photo = shape_by_id(en, 6)
    photo.left = Inches(10.78); photo.top = Inches(0.14); photo.width = Inches(2.48); photo.height = Inches(1.24)
    cap = shape_by_id(en, 7)
    cap.left = Inches(10.78); cap.top = Inches(1.40); cap.width = Inches(2.48); cap.height = Inches(0.22)
    set_text(cap, [("On-board test · system output frame", 9, False, GRAY)], align=PP_ALIGN.CENTER, font="Calibri")
    set_text(shape_by_id(en, 8), [("INTRODUCTION", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, font="Calibri")
    set_text(shape_by_id(en, 14), [("SYSTEM ARCHITECTURE", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, font="Calibri")
    set_text(shape_by_id(en, 17), [("CREATIVE DESIGN", 19, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, font="Calibri")
    set_text(shape_by_id(en, 20), [("RESULT", 20, True, WHITE)], align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, font="Calibri")

    set_text(shape_by_id(en, 9), [(
        "Remote video nodes usually have one Ethernet cable and no PC. The operator needs to know whether the frame arrived, "
        "whether processing took effect, and how old the picture is. This node performs the complete path on one Zynq-7020: "
        "a 512×300 RGB565 stream enters through GbE, whole frames are committed after three conditions, both panes read back "
        "the same frame, and the seam selects the original or processed pixel.", 11, False, GRAY)], font="Calibri", line=1.05)
    set_text(shape_by_id(en, 10), [("Typical application case", 12.5, True, CN)], font="Calibri")
    set_text(shape_by_id(en, 11), [(
        "Confidence monitoring for broadcast, security and industrial vision: one cable carries the picture, processing result "
        "and link status.", 11, False, GRAY)], font="Calibri")
    set_text(shape_by_id(en, 12), [("Key technical issues addressed", 12.5, True, CN)], font="Calibri")
    set_text(shape_by_id(en, 13), [
        ("1. GbE UDP reassembly: offset-based reassembly; commit only when bytes, row coverage and bad-packet count pass.", 10.5, False, GRAY),
        ("2. Same-frame comparison: both panes share geometry and a fixed 15-cycle effect chain; the seam selects per pixel.", 10.5, False, GRAY),
        ("3. Status monitoring: aborts, missing rows, frame gaps and latency are readable through serial, telemetry and GPIO.", 10.5, False, GRAY),
        ("4. Storage: DDR ping-pong frame buffer + on-board test card.", 10.5, False, GRAY),
    ], font="Calibri", line=1.0)
    set_text(shape_by_id(en, 16), [
        ("1. GbE UDP reception & reassembly: RGMII → MAC → UDP filter → whole-frame commit;", 11, False, GRAY),
        ("2. DDR ping-pong buffer: PL as AXI HP0 master, double-buffered;", 11, False, GRAY),
        ("3. Geometry engine: 0.25–2.00× zoom (8 steps) + 0–359° rotation + bilinear;", 11, False, GRAY),
        ("4. 15-cycle effect chain: gray/invert/blur/sharpen/Sobel/binary/erode-dilate, constant latency;", 11, False, GRAY),
        ("5. Same-frame comparison: left original, right processed, per-pixel seam;", 11, False, GRAY),
        ("6. OSD + status readback: serial, telemetry and GPIO read the same counters.", 11, False, GRAY),
    ], font="Calibri", line=1.0)
    box1 = shape_by_id(en, 18)
    set_text(box1, [("1. Same-frame comparison", 13.5, True, RED),
                    ("Both panes share geometry, row labels and the fixed 15-cycle chain — the seam compares one frame, not two screenshots.", 11.5, False, GRAY)], font="Calibri", line=1.0)
    box2 = shape_by_id(en, 19)
    set_text(box2, [("2. Commit conditions + status monitoring", 13.5, True, RED),
                    ("Bytes, row coverage and bad-packet count must pass together; aborts, missing rows and frame gaps explain failures at 1/100 drops.", 11.5, False, GRAY)], font="Calibri", line=1.0)
    set_text(shape_by_id(en, 21), [
        ("RGMII → HDMI entirely in PL; PS only control. 1024×600 @ 59.5 Hz.", 9.2, False, GRAY),
        ("Timing: WNS 1.368 / WHS 0.048 ns, zero failures.", 9.2, False, GRAY),
        ("8 s stream: 241 frames @ 30.01 fps; selftest 22.2/0/18.9 PASS.", 9.2, False, GRAY),
        ("UART 105 commands PASS; QSPI boot validated.", 9.2, False, GRAY),
        ("Next: DDR tile cache / 1080p link / RGMII eye diagram / remote update.", 9.2, False, GRAY),
    ], font="Calibri", line=0.9)
    res = shape_by_id(en, 21)
    res.left = Inches(9.04); res.top = Inches(6.34); res.width = Inches(3.28); res.height = Inches(1.12)
    set_text(shape_by_id(en, 23), [(
        "Test tools: UART battery (105) · link selftest · telemetry listen　|　Performance: 30.01 fps　|　Asset: royalty-free scenery video", 9.5, False, GRAY)], font="Calibri")

    logo = shape_by_id(en, 5)
    logo.left = Inches(10.36); logo.top = Inches(0.10); logo.width = Inches(0.38); logo.height = Inches(0.39)
    bring_front(logo)
    amd = shape_by_id(en, 22)
    amd.left = Inches(12.50); amd.top = Inches(7.20); amd.width = Inches(0.65); amd.height = Inches(0.15)

    os.makedirs(OUT_DIR, exist_ok=True)
    dual = os.path.join(OUT_DIR, "poster_editable_cn_en.pptx")
    prs.save(dual)
    print("WROTE", dual)

    # Split into one-slide editable decks.
    def split(src, idx, out):
        p = Presentation(src)
        ids = list(p.slides._sldIdLst)
        for j, sid in enumerate(ids):
            if j != idx:
                p.slides._sldIdLst.remove(sid)
        p.save(out)
        print("WROTE", out)
    split(dual, 0, os.path.join(OUT_DIR, "poster_cn_editable.pptx"))
    split(dual, 1, os.path.join(OUT_DIR, "poster_en_editable.pptx"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

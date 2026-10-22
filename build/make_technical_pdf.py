# -*- coding: utf-8 -*-
"""Render report/design-report.md into technical_document.pdf with ReportLab.

The DOCX is the editable deliverable; this renderer keeps the PDF independent
of Microsoft Word and uses real text tables with repeated headers.
"""
import html
import os
import re
import sys
import time

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, Image, KeepTogether,
                                PageBreak, PageTemplate, Paragraph,
                                Preformatted, Spacer, Table, TableStyle)
from reportlab.platypus.flowables import HRFlowable

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "report", "design-report.md")
OUT = os.path.join(ROOT, "technical_document.pdf")

pdfmetrics.registerFont(TTFont("Song", "C:/Windows/Fonts/simsun.ttc", subfontIndex=0))
pdfmetrics.registerFont(TTFont("Hei", "C:/Windows/Fonts/simhei.ttf"))
pdfmetrics.registerFont(TTFont("Mono", "C:/Windows/Fonts/consola.ttf"))
pdfmetrics.registerFontFamily("Song", normal="Song", bold="Hei", italic="Song", boldItalic="Hei")

DARK = colors.HexColor("#1F3A5F")
GRAY = colors.HexColor("#666666")
GRID = colors.HexColor("#BFBFBF")
HEAD_BG = colors.HexColor("#E8EEF7")
CODE_BG = colors.HexColor("#F4F5F7")

BODY = ParagraphStyle("Body", fontName="Song", fontSize=10.5, leading=16.2,
                      firstLineIndent=21, alignment=TA_LEFT, spaceAfter=5)
BULLET = ParagraphStyle("Bullet", parent=BODY, firstLineIndent=0, leftIndent=14,
                        bulletIndent=0, spaceAfter=2)
H1 = ParagraphStyle("H1", fontName="Hei", fontSize=15, leading=22, textColor=DARK,
                    spaceBefore=12, spaceAfter=6, keepWithNext=1)
H1_ABSTRACT = ParagraphStyle("H1Abstract", parent=H1, alignment=TA_CENTER, spaceBefore=16)
H2 = ParagraphStyle("H2", fontName="Hei", fontSize=12.5, leading=18, textColor=DARK,
                    spaceBefore=9, spaceAfter=4, keepWithNext=1)
H3 = ParagraphStyle("H3", fontName="Hei", fontSize=11, leading=16,
                    textColor=colors.HexColor("#333333"), spaceBefore=7, spaceAfter=3,
                    keepWithNext=1)
CAPTION = ParagraphStyle("Caption", fontName="Song", fontSize=9, leading=12,
                         textColor=GRAY, alignment=TA_CENTER, spaceAfter=6)
CODE = ParagraphStyle("Code", fontName="Mono", fontSize=8.5, leading=11,
                      backColor=CODE_BG, borderColor=colors.HexColor("#E0E0E0"),
                      borderWidth=0.5, borderPadding=5, spaceBefore=2, spaceAfter=8)
CELL = ParagraphStyle("Cell", fontName="Song", fontSize=8.5, leading=11,
                      wordWrap="CJK", alignment=TA_LEFT)
CELL_H = ParagraphStyle("CellH", parent=CELL, fontName="Hei", alignment=TA_CENTER)
QUOTE = ParagraphStyle("Quote", parent=BODY, leftIndent=12, textColor=GRAY, firstLineIndent=0)


def md_inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    def code_font(m):
        code = m.group(1)
        name = "Song" if re.search(r"[\u4e00-\u9fff]", code) else "Mono"
        return '<font name="%s" size="8.5">%s</font>' % (name, code)
    text = re.sub(r"`([^`]+)`", code_font, text)
    return text


def split_table_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [p.strip().replace("\\|", "|") for p in re.split(r"(?<!\\)\|", line)]


def is_sep_row(line):
    cells = split_table_row(line)
    return all(re.fullmatch(r":?-{2,}:?", c.replace(" ", "")) for c in cells if c != "")


def col_widths(ncol, avail):
    if ncol == 2:
        frac = [0.38, 0.62]
    elif ncol == 3:
        frac = [0.22, 0.28, 0.50]
    elif ncol == 4:
        frac = [0.21, 0.27, 0.25, 0.27]
    elif ncol == 5:
        frac = [0.16, 0.20, 0.19, 0.20, 0.25]
    else:
        frac = [1.0 / ncol] * ncol
    return [avail * f for f in frac]


def make_table(rows):
    ncol = max(len(r) for r in rows)
    rows = [r + [""] * (ncol - len(r)) for r in rows]
    data = []
    for i, row in enumerate(rows):
        data.append([Paragraph(md_inline(c), CELL_H if i == 0 else CELL) for c in row])
    t = Table(data, colWidths=col_widths(ncol, 16.2 * cm), repeatRows=1, splitByRow=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("GRID", (0, 0), (-1, -1), 0.5, GRID),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return [t, Spacer(1, 6)]


def make_figure(src, caption):
    path = os.path.join(ROOT, src)
    if not os.path.exists(path):
        path = os.path.join(ROOT, "report", src)
    if not os.path.exists(path):
        return [Paragraph("[missing figure: %s]" % src, CAPTION)]
    iw, ih = PILImage.open(path).size
    max_w = 16.2 * cm
    max_h = 12.5 * cm
    w = max_w
    h = w * ih / iw
    if h > max_h:
        h = max_h
        w = h * iw / ih
    img = Image(path, width=w, height=h)
    return [KeepTogether([Spacer(1, 4), img, Paragraph(md_inline(caption), CAPTION)])]


def parse(lines):
    flow = []
    i = 0
    n = len(lines)
    title = subtitle = None
    while i < n:
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("# ") and title is None:
            title = line[2:].strip()
            i += 1
            continue
        if line.startswith("## ") and subtitle is None and title is not None:
            subtitle = line[3:].strip()
            i += 1
            continue
        if line.startswith("### "):
            flow.append(Paragraph(md_inline(line[4:].strip()), H3))
            i += 1
            continue
        if line.startswith("## "):
            text = line[3:].strip()
            if text == "摘要":
                flow.append(Paragraph(md_inline(text), H1_ABSTRACT))
            else:
                if text.startswith("附录") or text.startswith("2 系统总体方案"):
                    flow.append(PageBreak())
                flow.append(Paragraph(md_inline(text), H1))
            i += 1
            continue
        if line == "---":
            flow.append(PageBreak())
            i += 1
            continue
        if line.startswith("```"):
            i += 1
            code = []
            while i < n and not lines[i].strip().startswith("```"):
                code.append(lines[i].rstrip("\n"))
                i += 1
            if i < n:
                i += 1
            flow.append(Preformatted("\n".join(code), CODE))
            continue
        m = re.match(r"!\[(.*?)\]\((.*?)\)", line)
        if m:
            flow.extend(make_figure(m.group(2), m.group(1)))
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rowline = lines[i].strip()
                if not is_sep_row(rowline):
                    rows.append(split_table_row(rowline))
                i += 1
            if rows:
                flow.extend(make_table(rows))
            continue
        if line.startswith("- "):
            while i < n and lines[i].strip().startswith("- "):
                flow.append(Paragraph(md_inline(lines[i].strip()[2:].strip()), BULLET, bulletText="•"))
                i += 1
            continue
        if re.match(r"^\d+\.\s", line):
            while i < n and re.match(r"^\d+\.\s", lines[i].strip()):
                txt = re.sub(r"^\d+\.\s+", "", lines[i].strip())
                num = re.match(r"^(\d+)\.", lines[i].strip()).group(1) + "."
                flow.append(Paragraph(md_inline(txt), BULLET, bulletText=num))
                i += 1
            continue
        if line.startswith("> "):
            flow.append(Paragraph(md_inline(line[2:].strip()), QUOTE))
            i += 1
            continue
        flow.append(Paragraph(md_inline(line), BODY))
        i += 1
    return title, subtitle, flow


def cover(title, subtitle, flow):
    out = [Spacer(1, 5.4 * cm)]
    out.append(Paragraph("设 计 报 告", ParagraphStyle(
        "Kicker", fontName="Hei", fontSize=10.5, leading=16, textColor=DARK,
        alignment=TA_CENTER)))
    out.append(Spacer(1, 0.4 * cm))
    out.append(Paragraph(html.escape(title), ParagraphStyle(
        "CoverTitle", fontName="Hei", fontSize=24, leading=34, textColor=DARK,
        alignment=TA_CENTER)))
    out.append(Spacer(1, 0.25 * cm))
    out.append(Paragraph(html.escape(subtitle), ParagraphStyle(
        "CoverSub", fontName="Hei", fontSize=13, leading=20,
        textColor=colors.HexColor("#333333"), alignment=TA_CENTER)))
    out.append(HRFlowable(width="58%", thickness=2, color=DARK, spaceBefore=14, spaceAfter=14,
                          hAlign="CENTER"))
    out.append(Paragraph("AMD FPGA 创新设计大赛 · 初级组 · 自命题赛道", ParagraphStyle(
        "CoverLine", fontName="Song", fontSize=9.5, leading=14, textColor=GRAY,
        alignment=TA_CENTER)))
    out.append(Spacer(1, 0.8 * cm))
    return out + flow


def main():
    with open(SRC, encoding="utf-8") as f:
        lines = f.read().splitlines()
    title, subtitle, flow = parse(lines)
    if not title or not subtitle:
        print("missing title/subtitle")
        return 1
    content = cover(title, subtitle, flow)

    frame = Frame(2.3 * cm, 2.0 * cm, A4[0] - 4.6 * cm, A4[1] - 4.2 * cm, id="normal")

    def decorate(canvas, doc):
        page = canvas.getPageNumber()
        if page == 1:
            return
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(GRAY)
        canvas.drawRightString(A4[0] - 2.3 * cm, A4[1] - 1.45 * cm,
                               "Multi-Source Video Processing System")
        canvas.setStrokeColor(colors.HexColor("#C9D0D9"))
        canvas.setLineWidth(0.5)
        canvas.line(2.3 * cm, A4[1] - 1.62 * cm, A4[0] - 2.3 * cm, A4[1] - 1.62 * cm)
        canvas.setFont("Helvetica", 9)
        canvas.drawCentredString(A4[0] / 2, 1.25 * cm, str(page - 1))
        canvas.restoreState()

    tmp = OUT + ".tmp%d" % os.getpid()
    doc = BaseDocTemplate(tmp, pagesize=A4, leftMargin=2.3 * cm, rightMargin=2.3 * cm,
                          topMargin=2.2 * cm, bottomMargin=2.0 * cm,
                          title=title, subject=subtitle, author="")
    doc.addPageTemplates([PageTemplate(id="main", frames=[frame], onPage=decorate)])
    doc.build(content)

    for _ in range(20):
        try:
            os.replace(tmp, OUT)
            break
        except PermissionError:
            time.sleep(0.5)
    else:
        print("could not replace %s; left %s" % (OUT, tmp))
        return 1
    print("WROTE %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())

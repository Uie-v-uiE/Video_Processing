# build/clock_io_delay_scan2.py —— 第二遍：换个关键词找 **I/O 钟网络的延迟数字**（第一遍按 "bufio" 找，
# 命中的全是 UG472 的定性叙述；真正的 ns/ps 数在 UG471 的 SelectIO AC 表里，而那些表不一定写 "BUFIO"）。
# 用法：python build/clock_io_delay_scan2.py
import io
import os
import re

import pypdfium2 as pdfium

BASE = "D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册"
FILES = [os.path.join(BASE, n) for n in ("ug471_7Series_SelectIO.pdf", "ug472_7Series_Clocking.pdf")]
# 数字 + 单位（ns/ps），且这一行或相邻两行里有 clock/skew/delay/buffer 才要
NUMPS = re.compile(r"\b\d{1,5}(?:\.\d+)?\s*(?:ns|ps)\b", re.I)
CTX = re.compile(r"clock|skew|delay|buffer|jitter|dcd|io[br]", re.I)


def grab(path, out):
    if not os.path.exists(path):
        out.append("MISSING " + path)
        return
    doc = pdfium.PdfDocument(path)
    out.append("=" * 78)
    out.append("FILE %s pages=%d" % (os.path.basename(path), len(doc)))
    n = 0
    for i in range(len(doc)):
        t = doc[i].get_textpage().get_text_range()
        lines = [l.strip() for l in t.split("\n") if l.strip()]
        keep = []
        for j, l in enumerate(lines):
            if NUMPS.search(l) and CTX.search(l):
                keep.append(j)
        if not keep:
            continue
        # 只报"看起来像 I/O 钟网络/缓冲"的页：整页要有 clock + (input|output|io) 的痕迹
        low = t.lower()
        if "clock" not in low:
            continue
        if not any(k in low for k in ("io clock", "input clock", "output clock", "clock timing",
                                      "iob", "dedicated", "source-synchronous", "i/obclk")):
            continue
        n += 1
        if n > 14:
            continue
        out.append("-- PDF page %d（%d 行候选）--" % (i + 1, len(keep)))
        idxs = sorted(set(sum([[max(0, j - 2), j - 1, j, j + 1, min(len(lines) - 1, j + 2)] for j in keep], [])))
        for j in idxs:
            out.append("   | %s" % lines[j][:168])
    out.append("PAGES_WITH_CANDIDATES=%d" % n)


def main():
    out = []
    for p in FILES:
        grab(p, out)
    txt = "\n".join(out)
    dst = "build/evidence/r117/bufio_delay_scan2.txt"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    io.open(dst, "w", encoding="utf-8", newline="\n").write(txt + "\n")
    print("WROTE %s lines=%d" % (dst, txt.count("\n") + 1))
    for l in txt.split("\n"):
        if NUMPS.search(l):
            print(l.encode("ascii", "replace").decode("ascii")[:168])


if __name__ == "__main__":
    main()

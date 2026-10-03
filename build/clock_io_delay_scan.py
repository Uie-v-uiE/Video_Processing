# build/clock_io_delay_scan.py —— 把"换短钟（BUFIO）到底能省多少、角间差还剩多少"这句话的**器件侧出处**找回来。
#
# 为什么要这一支（提示词 §7 L1 + 交付文 TIMING_GLOBAL.md 第 7 节）：
#   r116 把 `eth_rxc` 那 5 格证成"当前结构下无解"的全部依据是**报告自己的数**：
#   慢角 DCD 5.008 / 快角 DCD 1.597 ⇒ 角间差 3.411 ns，而数据侧只有 0.467 ns。
#   下一轮唯一的出口是把 IDDR 的捕获钟换成 I/O 专用短钟（BUFIO），但那一刀的可关区间
#   吊在一个**没量过的假设**上（"专用走线 ≈ 0.5 / 0.2 ns"）。
#   官方手册里本来就该有这个数（7-series 的 Clocking / SelectIO 资源手册给 I/O 钟网络的延迟与偏差），
#   所以先把本机 PDF 扫一遍，能拿到就把假设换成引用；拿不到就在文档里明写"仍是假设、不许当结论"。
#
# 用法：python build/clock_io_delay_scan.py [pdf路径 ...]
import io
import os
import re
import sys

import pypdfium2 as pdfium

BASE = "D:/Xilinx/Resource/Reference Material/6-Xilinx Zynq系列部分官方手册"
DEFAULT = [
    os.path.join(BASE, "ug472_7Series_Clocking.pdf"),
    os.path.join(BASE, "ug471_7Series_SelectIO.pdf"),
]
# 只关心这些词附近的行；命中的行连页号一起打出来（页号=PDF 物理页，正文页另说）
KEYS = ("bufio", "buflr", "bufr", "iob", "clock network", "insertion", "skew", "delay", "ns", "ps")
NUM = re.compile(r"(\d+(?:\.\d+)?)\s*(?:ns|ps)\b", re.I)


def scan(path, out):
    if not os.path.exists(path):
        out.append("MISSING %s" % path)
        return 0
    doc = pdfium.PdfDocument(path)
    hits = 0
    out.append("=" * 78)
    out.append("FILE %s pages=%d" % (os.path.basename(path), len(doc)))
    for i in range(len(doc)):
        t = doc[i].get_textpage().get_text_range()
        low = t.lower()
        if "bufio" not in low:
            continue
        lines = [l.strip() for l in t.split("\n") if l.strip()]
        keep = []
        for j, l in enumerate(lines):
            ll = l.lower()
            if ("bufio" in ll) or (("skew" in ll or "delay" in ll or "insertion" in ll) and NUM.search(l)):
                keep.append((j, l))
        if not keep:
            continue
        hits += 1
        out.append("-- PDF page %d (命中 %d 行) --" % (i + 1, len(keep)))
        # 打印命中行 + 前后各一行，表格里的数字常常在下一行
        idxs = sorted(set([j for j, _ in keep] + [j + 1 for j, _ in keep] + [j - 1 for j, _ in keep]))
        for j in idxs:
            if 0 <= j < len(lines):
                out.append("   | %s" % lines[j][:170])
    return hits


def main(argv):
    files = argv[1:] or DEFAULT
    out = []
    for p in files:
        out.append("scanning %s" % p)
        scan(p, out)
    txt = "\n".join(out)
    dst = "build/evidence/r117/bufio_delay_scan.txt"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    io.open(dst, "w", encoding="utf-8", newline="\n").write(txt + "\n")
    print("WROTE %s lines=%d" % (dst, txt.count("\n") + 1))
    # 控制台只打含 ns/ps 的行（Windows 控制台是 GBK，中文与 U+2212 都可能炸）
    for l in txt.split("\n"):
        if NUM.search(l):
            print(l.encode("ascii", "replace").decode("ascii")[:170])


if __name__ == "__main__":
    main(sys.argv)

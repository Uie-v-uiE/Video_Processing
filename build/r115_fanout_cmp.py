#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""build/r115_fanout_cmp.py —— FANOUT 那一刀的 F4 判据：同名网在 B 滚的扇出有没有真的降。

为什么单独一个文件而不是塞进 shell 的 heredoc：今天已经栽过一次
"heredoc 往 Python 字符串里写真换行 ⇒ 文件语法坏掉"（r115 名册生成器的第一版），
而且这段逻辑需要自己的对照（--self）：它必须**能变红**，否则 F4 是一条不会咬的尺子
（规矩 46：每个新判据配一条已知红/已知绿的样例工件各跑一次）。

形状按 2026-10-03 实测的 report_high_fanout_nets 表体读：
    | u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk |   2546 | BUFG |
认不出的行直接跳过；两边没有同名网时输出 NOOVERLAP（那是"没比成"，不是"没差别"）。
"""
from __future__ import print_function
import io
import sys


def rows(path):
    out = {}
    try:
        txt = io.open(path, encoding="utf-8", errors="replace").read()
    except (IOError, OSError):
        return out
    for line in txt.splitlines():
        # 真实行形状（2026-10-03 实测，凭据 build/evidence/r115_base/high_fanout.txt）：
        #   | u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk |   2546 | BUFG |
        # split("|") 的第一段是**空串**（行首就有竖线）⇒ 名字在 [1]、扇出在 [2]。
        # 第一版按 [0]/[1] 取，--self 立刻把它咬红（四个对照里两个 FAIL），这正是对照存在的理由。
        c = [x.strip() for x in line.split("|")]
        if len(c) < 4:
            continue
        if not c[2].isdigit() or not c[1]:
            continue
        out[c[1]] = int(c[2])
    return out


def cmp_(pa, pb):
    a, b = rows(pa), rows(pb)
    both = sorted(set(a) & set(b))
    if not both:
        return "NOOVERLAP a=%d b=%d" % (len(a), len(b)), 0
    lower = [n for n in both if b[n] < a[n]]
    same = [n for n in both if b[n] == a[n]]
    higher = [n for n in both if b[n] > a[n]]
    detail = " ".join("%s:%d->%d" % (n, a[n], b[n]) for n in lower[:3])
    return ("cmp=%d lower=%d equal=%d higher=%d %s" % (len(both), len(lower), len(same),
                                                       len(higher), detail)), len(lower)


def selftest():
    import os
    import tempfile
    d = tempfile.mkdtemp(prefix="r115fancmp_")
    pa = os.path.join(d, "a.rpt")
    pb = os.path.join(d, "b.rpt")
    pc = os.path.join(d, "c.rpt")
    with io.open(pa, "w", encoding="utf-8", newline="\n") as f:
        f.write("| u_eth/a | 300 | LUT2 |\n| u_eth/b | 120 | FDRE |\n| junk row | notanint | x |\n")
    with io.open(pb, "w", encoding="utf-8", newline="\n") as f:
        f.write("| u_eth/a | 210 | LUT2 |\n| u_eth/b | 120 | FDRE |\n")
    with io.open(pc, "w", encoding="utf-8", newline="\n") as f:
        f.write("| totally/different | 999 | LUT2 |\n")
    r = 0
    # 1) B 降了一格 ⇒ lower=1（能绿的对照）
    s, n = cmp_(pa, pb)
    ok = (n == 1 and "lower=1" in s and "equal=1" in s and "cmp=2" in s)
    print("SELFCMP %s want=lower1/equal1/cmp2 got=%s %s" % ("drop_and_equal", s, "PASS" if ok else "FAIL"))
    r = r or (0 if ok else 1)
    # 2) 没有同名网 ⇒ NOOVERLAP（"没比成"必须和"比了没差别"分开）
    s, n = cmp_(pa, pc)
    ok = s.startswith("NOOVERLAP") and n == 0
    print("SELFCMP %s want=NOOVERLAP got=%s %s" % ("no_overlap", s, "PASS" if ok else "FAIL"))
    r = r or (0 if ok else 1)
    # 3) 完全相同 ⇒ lower=0（这条是"机制未触发"那一侧，不许被读成降了）
    s, n = cmp_(pa, pa)
    ok = ("lower=0" in s) and ("cmp=2" in s) and n == 0
    print("SELFCMP %s want=lower0/cmp2 got=%s %s" % ("identical", s, "PASS" if ok else "FAIL"))
    r = r or (0 if ok else 1)
    # 4) 文件不存在 ⇒ 空集走 NOOVERLAP，不是一片绿
    s, n = cmp_(os.path.join(d, "missing.rpt"), pb)
    ok = s.startswith("NOOVERLAP")
    print("SELFCMP %s want=NOOVERLAP got=%s %s" % ("missing_file", s, "PASS" if ok else "FAIL"))
    r = r or (0 if ok else 1)
    print("SELFCMPRESULT %s" % ("GREEN" if r == 0 else "RED"))
    return r


def main(argv):
    if len(argv) == 2 and argv[1] == "--self":
        return selftest()
    if len(argv) < 3:
        raise SystemExit(__doc__)
    s, _ = cmp_(argv[1], argv[2])
    print(s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

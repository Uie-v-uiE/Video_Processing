#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""build/r115_round_roster.py —— 提示词 §4 E1：`roster_roundNNN.tsv`（与基线同形状 + *_delta + verdict）。

为什么不是"基线 vs 本轮"直接相减：本轮（r115 夜）**没有正式构建**——唯一变量的两滚都从同一份
`system_top_opt.dcp` 起跑（快车道 D1）。基线名册来自**正式构建的已布线 DCP**，与快车道滚**跨构建**，
按 §1 H3 不许拿它的差值当进度。所以这张表的差值列是 **B − A（同 DCP，H3 合法）**，
而"本轮 vs 基线"那一栏只照抄基线的头条四个数并标 `NOT_COMPARABLE_H3`。
这不是绕开 B3（差值两端必须是两个有指纹的工件）：A 与 B 各自的 tsv 都在 `build/evidence/r115_fanout_ab/` 里有 md5。

形状：13 列（B2 原样）→ A 滚的读数填这 13 列，之后依次是
    b_<13 列名>          B 滚同列读数
    rel_margin_setup_delta / rel_margin_hold_delta   （B−A，§4 E2 的口径）
    unconstrained_delta / io_unconstrained_delta     （B−A，G2 的方向）
    verdict                                            （GREEN / RED，按 G1+G2）
另加一行表头注释把 baseline 摆进来当**跨构建对照**（只念不判）。

--self 三条对照（G10：每条新增门禁项自己要有能红的测试）：
  1) A 与 B 完全相同 ⇒ 每行 GREEN、四个 delta 全 0（能绿）
  2) 注入"某域 hold 相对余量变小" ⇒ 那一行 RED，而且**只有那一行**RED
  3) 注入"B 少了一个时钟" ⇒ 那一行 RED(presence)
"""
from __future__ import print_function

import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r115_roster_build import COLS, EXTRA, METRICS, read_tsv  # noqa: E402

REL = ("rel_margin_setup", "rel_margin_hold")


def _f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def join(a, b):
    """返回 (rows, reds)：rows 是已经排好序的 dict 列表，reds 是被判红的 (clock, reason)。"""
    A, B = read_tsv(a), read_tsv(b)
    keys = sorted(set(list(A.keys()) + list(B.keys())))
    rows, reds = [], []
    for k in keys:
        if k not in A or k not in B:
            reds.append((k, "presence"))
            src = A.get(k) or B.get(k)
            rb = dict(src)
            rb["verdict"] = "RED"
            for m in ("rel_margin_setup", "rel_margin_hold", "unconstrained_endpoints", "io_unconstrained_ports"):
                rb[m + "_delta"] = "NA"
            rows.append((k, A.get(k, {}), B.get(k, {}), rb))
            continue
        ra, rb = dict(A[k]), dict(B[k])
        verdict = "GREEN"
        for m in METRICS:
            va, vb = _f(ra.get(m)), _f(rb.get(m))
            if va is None or vb is None:
                ra[m + "_delta"] = "NA"
                continue
            d = vb - va
            ra[m + "_delta"] = "%+.6f" % d
            if m in REL:
                if d < 0:
                    verdict = "RED"
                    reds.append((k, m))
            else:
                if d > 0:
                    verdict = "RED"
                    reds.append((k, m))
        ra["verdict"] = verdict
        rows.append((k, A[k], B[k], ra))
    return rows, reds


HEAD_EXTRA = (["b_" + c for c in (COLS + EXTRA)] +
              [m + "_delta" for m in METRICS] + ["verdict"])


def write_round(a, b, out, baseline_note):
    rows, reds = join(a, b)
    made = sum(1 for _, _, _, r in rows for m in METRICS if r.get(m + "_delta", "NA") != "NA")
    with io.open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(u"# r115 轮名册（E1）。差值列 = B − A，两端同 DCP（H3 合法）；噪声底 noise_ns=0.000（B4，件 /tmp/kx/r115_noise/noise.txt）\n")
        f.write(u"# " + baseline_note + u"\n")
        f.write(u"# 口径 rel_margin_* = wns_* / period_ns（§4 E2）；判定列按 G1（相对余量不许变小）+ G2（两列债务不许变大）\n")
        f.write(u"# 附加列 intra_endpoint_total 与它前面的 13 列同名前缀 b_ 表示 B 滚读数\n")
        f.write("\t".join(COLS + EXTRA + HEAD_EXTRA) + "\n")
        for k, ra, rb, rr in rows:
            left = [str(ra.get(c, "NA")) for c in (COLS + EXTRA)]
            right = [str(rb.get(c, "NA")) for c in (COLS + EXTRA)]
            deltas = [str(rr.get(m + "_delta", "NA")) for m in METRICS]
            f.write("\t".join(left + right + deltas + [rr.get("verdict", "NA")]) + "\n")
    verdict = "GREEN" if not reds else "RED"
    # both_NA 从**两端各自的读数**算（不是从 delta 那一格反推：单侧 NA 与双侧 NA 在 delta 上都写成 NA，
    # 反推会把"丢读数"读成"从来就没有数"——同族错见 #293 的 D5）。
    both_na = sum(1 for _, ra_, rb_, _ in rows for m in METRICS
                  if str(ra_.get(m, "NA")) == "NA" and str(rb_.get(m, "NA")) == "NA")
    single_na = sum(1 for _, ra_, rb_, _ in rows for m in METRICS
                    if (str(ra_.get(m, "NA")) == "NA") != (str(rb_.get(m, "NA")) == "NA"))
    print("ROUND written=%s rows=%d comparisons_made=%d both_NA=%d single_NA=%d reds=%d verdict=%s"
          % (out, len(rows), made, both_na, single_na, len(reds), verdict))
    for k, m in reds:
        print("ROUND-RED %s %s" % (k, m))
    return 0 if not reds else 1


def selftest():
    d = tempfile.mkdtemp(prefix="r115round_")
    from r115_roster_build import HEADER
    fix = ("# fixture\n" + HEADER + "\n"
           "eth_rxc\t8.000\tsrc\t0.739\t0.000\t0\t0.052\t0.000\t0\t0.092375\t0.006500\t0\t11\t4835\n"
           "sys_clk\t20.000\tsrc\t14.876\t0.000\t0\t0.222\t0.000\t0\t0.743800\t0.011100\t0\t11\t323\n")
    io.open(os.path.join(d, "a.tsv"), "w", encoding="utf-8", newline="\n").write(fix)
    outs = []
    # 1) 相同 ⇒ 全绿
    io.open(os.path.join(d, "same.tsv"), "w", encoding="utf-8", newline="\n").write(fix)
    buf = io.open(os.path.join(d, "o1.txt"), "w", encoding="utf-8")
    import contextlib
    with contextlib.redirect_stdout(buf):
        rc1 = join_and_report(os.path.join(d, "a.tsv"), os.path.join(d, "same.tsv"), os.path.join(d, "r1.tsv"))
    buf.close()
    t1 = io.open(os.path.join(d, "r1.tsv"), encoding="utf-8").read()
    ok1 = rc1 == 0 and "GREEN" in io.open(os.path.join(d, "o1.txt"), encoding="utf-8").read() and t1.count("\tGREEN") == 2
    print("SELFROUND identical want=GREENx2 rc=%d %s" % (rc1, "PASS" if ok1 else "FAIL"))
    outs.append(ok1)
    # 2) 注入 hold 变差 ⇒ 恰好一行红
    bad = fix.replace("0.222\t0.000\t0\t0.743800\t0.011100", "0.022\t0.000\t0\t0.743800\t0.001100")
    io.open(os.path.join(d, "bad.tsv"), "w", encoding="utf-8", newline="\n").write(bad)
    with contextlib.redirect_stdout(io.open(os.path.join(d, "o2.txt"), "w", encoding="utf-8")):
        rc2 = join_and_report(os.path.join(d, "a.tsv"), os.path.join(d, "bad.tsv"), os.path.join(d, "r2.tsv"))
    l2 = io.open(os.path.join(d, "o2.txt"), encoding="utf-8").read()
    ok2 = rc2 == 1 and "sys_clk rel_margin_hold" in l2 and l2.count("ROUND-RED") == 1
    print("SELFROUND injected_hold want=1 RED(sys_clk) rc=%d %s" % (rc2, "PASS" if ok2 else "FAIL"))
    outs.append(ok2)
    # 3) 少一个时钟 ⇒ presence 红
    gone = "\n".join([l for l in fix.splitlines() if not l.startswith("eth_rxc")]) + "\n"
    io.open(os.path.join(d, "gone.tsv"), "w", encoding="utf-8", newline="\n").write(gone)
    with contextlib.redirect_stdout(io.open(os.path.join(d, "o3.txt"), "w", encoding="utf-8")):
        rc3 = join_and_report(os.path.join(d, "a.tsv"), os.path.join(d, "gone.tsv"), os.path.join(d, "r3.tsv"))
    l3 = io.open(os.path.join(d, "o3.txt"), encoding="utf-8").read()
    ok3 = rc3 == 1 and "eth_rxc presence" in l3
    print("SELFROUND dropped_clock want=RED(presence) rc=%d %s" % (rc3, "PASS" if ok3 else "FAIL"))
    outs.append(ok3)
    print("SELFROUNDRESULT %s" % ("GREEN" if all(outs) else "RED"))
    return 0 if all(outs) else 1


def join_and_report(a, b, out):
    return write_round(a, b, out, "baseline 对照见 report/timing/roster_baseline.tsv（跨构建，NOT_COMPARABLE_H3）")


def main(argv):
    if len(argv) == 2 and argv[1] == "--self":
        return selftest()
    if len(argv) < 4:
        raise SystemExit(__doc__)
    return write_round(argv[1], argv[2], argv[3], argv[4] if len(argv) > 4 else "baseline=report/timing/roster_baseline.tsv")


if __name__ == "__main__":
    sys.exit(main(sys.argv))

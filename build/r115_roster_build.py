#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""build/r115_roster_build.py —— 提示词 §3 B2 / §4 E1：把「一行一个时钟域」的花名册生成器与判定器写成一件工具。

为什么是脚本而不是手抄表：B3 规定此后每一轮的差值只能引用**有指纹的工件**，而「我记得基线是多少」
是提示词点名的失败形状；同时 G9 要求判定器自己报「做了多少次比较」，只有代码能老实数这个数。

三种用法：
  python build/r115_roster_build.py <timing_summary.txt> <check_timing_verbose.txt> <out.tsv> <label>
  python build/r115_roster_build.py --diff <baseline.tsv> <round.tsv>
  python build/r115_roster_build.py --self        # G10：这条判定器自己要能变红

列（ASCII 表头，按 §3 B2 原样，不改名）：
  clock period_ns src wns_setup tns_setup nfp_setup wns_hold tns_hold nfp_hold
  rel_margin_setup rel_margin_hold unconstrained_endpoints io_unconstrained_ports

两份报告的**真实形状**（2026-10-03 22:34 从 build/evidence/r115_base/timing_summary.txt 量的）：
  Clock Summary 行        sys_clk   {0.000 10.000}   20.000   100.000
  Intra Clock Table 表头  Clock WNS TNS TNS-Failing TNS-Total WHS THS THS-Failing THS-Total ...
  有 intra 路径的行        eth_rxc  0.739  0.000  0  4835  0.052  0.000  0  4835 ...
  没有 intra 路径的行      「  clkfbout」—— 只有名字，字段全空。
  第一版按「名字 + {波形}」的正则去切 Intra 行，一行都没匹配上 ⇒ ROSTERFAIL 解析出 0 行；
  而周期这一列在 Intra Clock Table 里**根本没有**，只能从 Clock Summary 取。形状要测不要猜。
"""
import contextlib
import io
import os
import re
import sys
import tempfile
import time

COLS = ("clock period_ns src wns_setup tns_setup nfp_setup wns_hold tns_hold nfp_hold "
        "rel_margin_setup rel_margin_hold unconstrained_endpoints io_unconstrained_ports").split()
# 提示词把 13 列的名字钉死了 ⇒ 一个字不改；但 §4 D 的打分要"按该域端点数加权"，
# 那个数在报告里叫 TNS Total Endpoints，不能塞进 unconstrained_endpoints（那是另一种量纲）。
# ⇒ 作为**附加列**放在 13 列之后，并在表头注释里写清它是附加的。
EXTRA = ["intra_endpoint_total"]
HEADER = "\t".join(COLS + EXTRA)
# 差分器实际逐项比较的列 = 判定表的全部口径（G1 两列 + G2 两列）。
# 必须是**模块级常量**：--self 的"做了多少次比较"要按它算，写在函数里会让对照和尺子各有一份清单
# （清单漂移正是 G9 要防的形状）。
METRICS = ("rel_margin_setup", "rel_margin_hold", "unconstrained_endpoints", "io_unconstrained_ports")

SUMMARY_ROW = re.compile(r"^(?P<clk>\S+)\s+\{(?P<wf>[0-9. ]+)\}\s+(?P<period>[0-9.]+)\s+(?P<freq>[0-9.]+)")
NA_ROW = dict((k, "NA") for k in ("wns_setup", "tns_setup", "nfp_setup", "n_total_setup",
                                  "wns_hold", "tns_hold", "nfp_hold", "n_total_hold"))


def num(tok):
    try:
        return float(tok)
    except Exception:
        return None


def read(path):
    return io.open(path, encoding="utf-8", errors="replace").read()


STOPS = ("Inter Clock Table", "Clock Network Summary", "Clock Tables", "Intra Clock Table Summary",
         "Timing Constraints", "Other Path Groups", "Summary By Clock", "Timing Details", "Clock Sequences")


def block(txt, title):
    # 22:38 第三次纠错：报告里标题下面**两条**下划线（`| ----` 与 `-----`），中间还夹一个空行，
    # 所以"截到第一个空行为止"的写法只截到一条虚线 ⇒ 解析出 0 行。改成**按下一节的标题切**，
    # 并对区间里的虚线/表头行做前缀过滤（附录 1：跳过破折号行必须是前缀判断）。
    i = txt.find(title)
    if i < 0:
        raise SystemExit("ROSTERFAIL 找不到表格 %r" % title)
    body = txt[i + len(title):]
    cut = len(body)
    for s in STOPS:
        j = body.find(s)
        if 0 <= j < cut:
            cut = j
    return body[:cut]


def parse_clock_summary(path):
    per = {}
    for line in block(read(path), "Clock Summary").splitlines():
        mm = SUMMARY_ROW.match(line.strip())
        if mm:
            per[mm.group("clk")] = (float(mm.group("period")), mm.group("wf").strip())
    if not per:
        raise SystemExit("ROSTERFAIL Clock Summary 解析出 0 个时钟（%s）" % path)
    return per


def parse_intra(path):
    rows = {}
    for line in block(read(path), "Intra Clock Table").splitlines():
        t = line.strip()
        if not t or t.startswith("Clock ") or set(t) <= set("-"):
            continue
        f = t.split()
        if not re.match(r"^[A-Za-z_][\w\/]*$", f[0]):
            continue                          # 报告边框的 "|" 之类不是时钟名（22:37 实测多出的假行）
        if len(f) == 1:                       # 只有名字 = 这个域没有 intra 路径（真话，不是失败）
            rows[f[0]] = dict(NA_ROW)
            rows[f[0]]["n_total_setup"] = "0"
            rows[f[0]]["n_total_hold"] = "0"
            continue
        if len(f) < 9 or num(f[1]) is None:
            continue
        rows[f[0]] = dict(wns_setup=f[1], tns_setup=f[2], nfp_setup=f[3], n_total_setup=f[4],
                          wns_hold=f[5], tns_hold=f[6], nfp_hold=f[7], n_total_hold=f[8])
    if not rows:
        raise SystemExit("ROSTERFAIL Intra Clock Table 解析出 0 行（%s）" % path)
    return rows


def parse_io_debt(path):
    """check_timing 的**端口类**计数（附录 1 量纲红线：只数端口对象，不与 methodology 的 checks/pins 相减）。

    第二个返回值才是 §3 B2 的 `unconstrained_endpoints`：check_timing 自己那行
    `There are N pins that are not constrained for maximum delay.`（22:40 实测本设计是 **0**，
    同族还有 `…due to constant clock` 也是 0）。这是工具的正牌"没被约束算到的端点"计数，
    设计级一个数，逐行重复填。
    """
    txt = read(path)
    hi_in = re.search(r"There are (\d+) input ports with no input delay specified", txt)
    hi_out = re.search(r"There are (\d+) ports with no output delay specified", txt)
    if not hi_in or not hi_out:
        raise SystemExit("ROSTERFAIL check_timing 里没念到 no-input/no-output-delay 两句（%s）" % path)
    nopin = re.search(r"There are (\d+) pins that are not constrained for maximum delay\.", txt)
    if not nopin:
        raise SystemExit("ROSTERFAIL check_timing 里没念到『pins that are not constrained for maximum delay』"
                         "这一句 —— unconstrained_endpoints 没有出处就不许填（%s）" % path)
    return (int(hi_in.group(1)) + int(hi_out.group(1)), int(hi_in.group(1)),
            int(hi_out.group(1)), int(nopin.group(1)))


def src_of(clk):
    if clk in ("sys_clk", "eth_rxc"):
        return "create_clock(XDC)"
    if clk == "clk_fpga_0":
        return "PS7_FCLKCLK0(BD)"
    return "MMCM_generated"


def build(ts, ck, out, label):
    intra = parse_intra(ts)
    per = parse_clock_summary(ts)
    n_io, nin, nout, n_uncons = parse_io_debt(ck)
    rows = []
    for clk in sorted(set(list(intra.keys()) + list(per.keys()))):
        d = intra.get(clk, dict(NA_ROW))
        p = per.get(clk, (None, ""))[0]
        ws, wh = num(d["wns_setup"]), num(d["wns_hold"])
        rows.append([clk, ("%g" % p) if p else "NA", src_of(clk), d["wns_setup"], d["tns_setup"], d["nfp_setup"],
                     d["wns_hold"], d["tns_hold"], d["nfp_hold"],
                     ("%.6f" % (ws / p)) if (ws is not None and p) else "NA",
                     ("%.6f" % (wh / p)) if (wh is not None and p) else "NA",
                     str(n_uncons), str(n_io), d.get("n_total_setup", "NA")])
    if not rows:
        raise SystemExit("ROSTERFAIL 拼出 0 行")
    dn = os.path.dirname(out)
    if dn:
        os.makedirs(dn, exist_ok=True)
    with io.open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("# label=%s built=%s src_reports=%s,%s\n" % (label, time.strftime("%Y-%m-%d %H:%M:%S"), ts, ck))
        f.write("# 口径 rel_margin_* = wns_* / period_ns（§4 E2 强制）；"
                "io_unconstrained_ports = check_timing 的 HIGH 两类之和（端口对象单位：输入 %d + 输出 %d）\n" % (nin, nout))
        f.write("# unconstrained_endpoints = check_timing 自己那行『pins that are not constrained for maximum "
                "delay』（设计级一个数，逐行重复填，22:40 实测 0）\n")
        f.write("# 附加列 intra_endpoint_total = 该域在 Intra Clock Table 里的 TNS Total Endpoints，"
                "只给 §4 D 的加权用（13 列的名字与顺序按 B2 原样，没动）\n")
        f.write(HEADER + "\n")
        for r in rows:
            f.write("\t".join(str(x) for x in r) + "\n")
    print("ROSTER-BUILT label=%s rows=%d io_unconstrained_ports=%d out=%s" % (label, len(rows), n_io, out))
    return 0


def read_tsv(p):
    head = None
    rows = {}
    for line in read(p).splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        cells = line.split("\t")
        if cells[0] == "clock":
            head = cells
            continue
        if head:
            rows[cells[0]] = dict(zip(head, cells))
    if not head or not rows:
        raise SystemExit("ROSTERFAIL %s 没有表头或 0 行" % p)
    return rows


def diff(base, rnd):
    A, B = read_tsv(base), read_tsv(rnd)
    keys = sorted(set(list(A.keys()) + list(B.keys())))
    made = 0
    red = 0
    na = 0
    print("ROSTERDIFF clock\tmetric\tbase\tround\tdelta\tverdict")
    for k in keys:
        if k not in A or k not in B:
            made += 1
            red += 1
            print("ROSTERDIFF %s\tpresence\t%s\t%s\tNA\tRED" % (k, "A" if k in A else "-", "B" if k in B else "-"))
            continue
        for m in METRICS:
            a, b = A[k].get(m, "NA"), B[k].get(m, "NA")
            made += 1
            if a == "NA" and b == "NA":
                # 两侧都没有这个读数 = 这个域本来就不算 intra 路径（clkfbout 一族），不是变差。
                # 以前它被单侧 NA 的分支一起判红 ⇒ 任何一轮都被四行"从来就没有数"的域假判红
                # （与今天 D5 的 both-NOWRITE 是同族错，见 ISSUES #293）。
                na += 1
                print("ROSTERDIFF %s\t%s\tNA\tNA\tNA\tNA" % (k, m))
                continue
            if a == "NA" or b == "NA":
                red += 1
                print("ROSTERDIFF %s\t%s\t%s\t%s\tNA\tRED" % (k, m, a, b))
                continue
            af, bf = float(a), float(b)
            dv = bf - af
            if m.startswith("rel_margin"):
                v = "GREEN" if dv >= 0 else "RED"          # G1
            else:
                v = "GREEN" if dv <= 0 else "RED"          # G2
            if v == "RED":
                red += 1
            print("ROSTERDIFF %s\t%s\t%.6f\t%.6f\t%+.6f\t%s" % (k, m, af, bf, dv, v))
    print("ROSTERDIFF-SUMMARY comparisons_made=%d both_NA=%d red=%d verdict=%s"
          % (made, na, red, "GREEN" if red == 0 else "RED"))
    return 0 if red == 0 else 1


FIX = ("# fixture\n" + HEADER + "\n"
       "eth_rxc\t8.000\tsrc\t0.739\t0.000\t0\t0.052\t0.000\t0\t0.092375\t0.006500\t0\t11\t4835\n"
       "sys_clk\t20.000\tsrc\t14.876\t0.000\t0\t0.222\t0.000\t0\t0.743800\t0.011100\t0\t11\t323\n")


def selftest():
    """G10：判定器自己要能变红，而且红**恰好**落在被注入的那一格（多咬一处 = 尺子在别处也失控）。"""
    d = tempfile.mkdtemp(prefix="r115roster_")
    base = os.path.join(d, "b.tsv")
    same = os.path.join(d, "s.tsv")
    bad = os.path.join(d, "x.tsv")
    gone = os.path.join(d, "g.tsv")
    for p in (base, same):
        io.open(p, "w", encoding="utf-8", newline="\n").write(FIX)
    # 两侧都有一行"从来就没有数"的域（clkfbout 一族）⇒ 不许判红，但必须被数进 both_NA（G10 对既有绿也有红的双向对照）
    nA = os.path.join(d, "nA.tsv")
    nB = os.path.join(d, "nB.tsv")
    withna = FIX.rstrip("\n") + "\nclkfbout\t20\tMMCM_generated\tNA\tNA\tNA\tNA\tNA\tNA\tNA\tNA\t0\t11\t0\n"
    for p in (nA, nB):
        io.open(p, "w", encoding="utf-8", newline="\n").write(withna)
    # G2 方向的对照：某个域的 io_unconstrained_ports 变大 ⇒ 必须红（覆盖变差不是收益）
    grew = os.path.join(d, "w.tsv")
    io.open(grew, "w", encoding="utf-8", newline="\n").write(FIX.replace("0\t11\t4835", "0\t13\t4835"))
    io.open(bad, "w", encoding="utf-8", newline="\n").write(FIX.replace(
        "0.052\t0.000\t0\t0.092375\t0.006500", "0.012\t0.000\t0\t0.092375\t0.001500"))
    io.open(gone, "w", encoding="utf-8", newline="\n").write(
        "\n".join([l for l in FIX.splitlines() if not l.startswith("sys_clk")]) + "\n")
    r = 0
    cases = (("identical_must_be_green", base, same, "GREEN", None),
             ("injected_hold_loss_must_be_red", base, bad, "RED", ("eth_rxc", "rel_margin_hold")),
             ("io_debt_grew_must_be_red", base, grew, "RED", ("eth_rxc", "io_unconstrained_ports")),
             ("dropped_clock_must_be_red", base, gone, "RED", ("sys_clk", "presence")))
    for tag, a, b, want, only in cases:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = diff(a, b)
        got = "GREEN" if rc == 0 else "RED"
        reds = [tuple(l.split("\t")[1:3]) for l in buf.getvalue().splitlines() if l.endswith("\tRED")]
        # 注意：行形状是 `ROSTERDIFF <clock>\t<metric>\t...`，第 0 段含时钟名
        reds = [(l.split("\t")[0].split()[-1], l.split("\t")[1])
                for l in buf.getvalue().splitlines() if l.endswith("\tRED")]
        ok = (got == want)
        if want == "RED":
            ok = ok and len(reds) == 1 and reds[0] == only
        print("SELF %s want=%s got=%s red=%s %s" % (tag, want, got, reds, "PASS" if ok else "FAIL"))
        if not ok:
            r = 1
    # 4) both-NA 的一行：必须绿，而且必须被 both_NA 数到（数不到=它在别处会被当成差值）
    #    期望值**从夹具自己算**，不写死数字：写死过一次（both_NA=3）在列语义变化后把对照咬红，
    #    那是尺子的账不是设计的账（同族教训见 ISSUES #293）。
    hdr = [l for l in FIX.splitlines() if not l.startswith("#")][0].split("\t")
    nrow = [l for l in withna.splitlines() if l.startswith("clkfbout")][0].split("\t")
    cell = dict(zip(hdr, nrow))
    exp_na = sum(1 for m in METRICS if cell[m] == "NA")
    exp_cmp = len([l for l in withna.splitlines()
                   if not l.startswith("#") and l.split("\t")[0] != "clock"]) * len(METRICS)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = diff(nA, nB)
    out = buf.getvalue().splitlines()
    sm = [l for l in out if l.startswith("ROSTERDIFF-SUMMARY")]
    want = "GREEN/both_NA=%d/cmp=%d" % (exp_na, exp_cmp)
    got = "none"
    if sm:
        kv = dict(x.split("=") for x in sm[0].split()[1:])
        got = "both_NA=%s/cmp=%s" % (kv.get("both_NA"), kv.get("comparisons_made"))
    # 被数进 both_NA 的行必须**就是**那一行那两列，否则计数器在别处也会走（G9）
    na_rows = [(l.split("\t")[0].split()[-1], l.split("\t")[1])
               for l in out if l.startswith("ROSTERDIFF ") and l.endswith("\tNA\tNA\tNA\tNA")]
    ok = rc == 0 and sm and ("both_NA=%d " % exp_na) in sm[0] and ("comparisons_made=%d " % exp_cmp) in sm[0]
    ok = ok and len(na_rows) == exp_na and all(c == "clkfbout" for c, _ in na_rows)
    print("SELF both_NA_must_be_green_and_counted want=%s got=%s rows=%s %s"
          % (want, got, na_rows, "PASS" if ok else "FAIL"))
    if not ok:
        r = 1
    print("SELFRESULT %s" % ("GREEN" if r == 0 else "RED"))
    return r


def main(argv):
    if len(argv) > 1 and argv[1] == "--self":
        return selftest()
    if len(argv) > 1 and argv[1] == "--diff":
        if len(argv) < 4:
            raise SystemExit(__doc__)
        return diff(argv[2], argv[3])
    if len(argv) < 5:
        raise SystemExit(__doc__)
    return build(argv[1], argv[2], argv[3], argv[4])


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python
# build/check_io_timing_coverage.py —— 把"其他地方的时序"（I/O 约束欠账）变成逐端口、可对账的一张清单
#
# 为什么要这一把（2026-10-03，用户"改时序也要考虑其他地方"那一问的直接后果）：
#   `check_timing` 每轮只给**计数**（r112：no_input_delay 7、no_output_delay 12），
#   而我在文档里只抄过一次数字。计数会随端口增删自己变，没人盯 ⇒ 一条新出厂接口可以
#   静悄悄地"到达/驱动时刻被当理想"，而屏上一切照旧。这一把把它变成点名 + 判据。
# 三端对齐（规矩 46：一条形状行的两个操作数不许同源）：
#   A 源码端：`system_top` 的端口表 + `src/constraints/*.xdc` 里点到名的端口 ⇒ 每个用户端口的状态
#      TIMED(有 set_input/output_delay) / FALSEPATH(set_false_path) / BARE(什么都没给)
#   B 报告端：归档的 `timing_summary.rpt` 里 check_timing 那四个数
#   C 基线端：钉死的一组基准计数（上一版采纳件读出来的），只许变小不许变大
# 判据（每条一行、末列是判定）：
#   I1 输入侧对账：源码数出来的"裸输入位数" == 报告的 HIGH 输入数   ← 这一条两边同源不同法，能撞
#   I2 假路侧对账：源码数出来的"假路输入位数" == 报告的 MEDIUM 输入数（key1_n/key2_n=2）
#   I3 输出侧覆盖：任何用户输出/双向端口都不许是 BARE —— 要么给 set_output_delay，要么写带理由的豁免
#   I4 基线不涨：报告的四个数任何一项都不许多于基线（新接口进来就红）
#   I5 计数地板：被数到的用户端口位数 >= 20 且报告四项都解析到（空转不许当绿）
#   I6 豁免反买通：豁免表每条必须有 >=30 字的理由，且被豁免的端口必须在 RTL 里真存在
# 用法：
#   python build/check_io_timing_coverage.py build/evidence/r112_bit/timing_summary.rpt
#   python build/check_io_timing_coverage.py --self
import io, re, sys, os

RTL = "src/rtl/top/system_top.v"
XDCS = ["src/constraints/rk_zynq7020.xdc", "src/constraints/clock_groups_impl.xdc"]
# 基线端：r112 归档件（bit 897fa9d93956）实测的四个数；改基线要在同一笔里说明为什么
BASELINE = {"in_bare": 5, "in_fp": 2, "out_bare": 6, "out_fp": 6}
# （原来这里还有一条 GAP_OUT_BARE = 6："源码位数 12 减报告 6 等于 6"——那是**位数减端口对象数**的量纲错，
#  差值被钉成常量后它永远绿，什么也没对账。现在由 I7_unit_reconcile 取代：必须存在一个单位让四个桶全等于报告。）
# 豁免表随尺子走（规矩 44）。每条格式：端口名模式|理由（不许"临时/先这样"这类空话）
EXEMPT = [
    ("DDR_*", "连到 BD 里的 processing system（PS 硬块），Vivado 不把 PS 硬块引脚当用户 fabric 的 I/O 检查"),
    ("FIXED_IO_*", "同上：PS 硬块的固定外设引脚（MIO/电源轨），由 PS 内部时序管，不属于这一把尺子的射程"),
    ("sys_clk", "它是 create_clock 的对象（20 ns），时钟端口本身不参与 no_input_delay 检查"),
    ("eth_rxc", "它是 create_clock 的对象（RGMII 的 8 ns 时钟）；这一路真正的账是 IDDR 采样窗，见 #46/#57 的实测"),
]

def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read()

def port_table():
    """顶层端口：[(name, direction, bits)]，bits 由声明的位宽展开（报告数的是**位/管脚**，不是名字）。"""
    src = read(RTL)
    m = re.search(r"\bmodule\s+system_top[\s\S]*?\);", src)
    body = m.group(0) if m else ""
    out, seen = [], set()
    for d, width, nm in re.findall(
            r"\b(input|output|inout)\s+(?:wire\s+)?(?:reg\s+)?(?:(\[[0-9:]+\])\s*)?([A-Za-z_]\w*)", body):
        if nm in seen:
            continue
        seen.add(nm)
        bits = 1
        if width:
            hh, ll = re.findall(r"\d+", width)
            bits = abs(int(hh) - int(ll)) + 1
        out.append((nm, d, bits))
    return out

def bd_ports():
    src = read(RTL)
    m = re.search(r"design_1_wrapper\s+u_bd\s*\(([\s\S]*?)\n\s*\);", src)
    if not m:
        return set()
    return set(re.findall(r"\.\w+\s*\(\s*([A-Za-z_]\w*)\s*\)", m.group(1)))

def xdc_names(xdc_list):
    idl, odt, clk, fp = set(), set(), set(), set()
    for f in xdc_list:
        if not os.path.exists(f):
            continue
        for line in read(f).splitlines():
            line = re.sub(r"#.*", "", line)
            if not line.strip():
                continue
            def names(seg):
                s = re.sub(r"\[[^\]]*\]", " ", seg)
                return re.findall(r"[A-Za-z_]\w*", re.sub(r"[{}]", " ", s))
            for key, tgt in (("set_input_delay", idl), ("set_output_delay", odt),
                             ("create_clock", clk), ("set_false_path", fp)):
                if re.match(r"\s*" + key, line):
                    for g in re.findall(r"\[get_ports\s+([^\]]*)\]", line):
                        tgt.update(names(g))
                    break
    return idl, odt, clk, fp

def report_counts(path):
    t = read(path)
    def g(pat):
        m = re.search(pat, t)
        return int(m.group(1)) if m else None
    return {
        "in_bare":  g(r"There are (\d+) input ports with no input delay specified"),
        "in_fp":    g(r"There are (\d+) input ports with no input delay but user has a false path"),
        "out_bare": g(r"There are (\d+) ports with no output delay specified"),
        "out_fp":   g(r"There are (\d+) ports with no output delay but user has a false path"),
    }

def match_any(nm, pats):
    for p in pats:
        if p.endswith("*") and nm.startswith(p[:-1]):
            return True
        if p == nm:
            return True
    return False

def classify(xdc_list=None, exempt_extra=None):
    xdc_list = xdc_list or XDCS
    idl, odt, clk, fp = xdc_names(xdc_list)
    bdp = bd_ports()
    exempts = list(EXEMPT)
    if exempt_extra:
        nm, _, why = exempt_extra.partition("|")
        exempts.append((nm, why))
    pat_names = [p for p, _ in exempts]
    rows = []
    c = dict(in_bare=0, in_fp=0, out_bare=0, out_fp=0, timed=0, user_bits=0, ports=0)
    for nm, d, bits in port_table():
        if nm in bdp or match_any(nm, ["DDR_", "FIXED_IO_"]):
            rows.append((nm, d, bits, "PS_INTERNAL")); continue
        if nm in clk:
            rows.append((nm, d, bits, "CLOCK_SRC")); continue
        exempted = match_any(nm, pat_names)
        c["ports"] += 1
        if exempted:
            rows.append((nm, d, bits, "EXEMPT")); continue
        c["user_bits"] += bits
        if d == "input":
            if nm in idl:
                st = "TIMED"; c["timed"] += bits
            elif nm in fp:
                st = "FALSEPATH"; c["in_fp"] += bits
            else:
                st = "BARE"; c["in_bare"] += bits
        else:
            if nm in odt:
                st = "TIMED"; c["timed"] += bits
            elif nm in fp:
                st = "FALSEPATH"; c["out_fp"] += bits
            else:
                st = "BARE"; c["out_bare"] += bits
        rows.append((nm, d, bits, st))
    return rows, c, exempts

def run(sumf, xdc_list=None, exempt_extra=None, baseline=None):
    baseline = baseline or BASELINE
    rows, c, exempts = classify(xdc_list, exempt_extra)
    rep = report_counts(sumf) if os.path.exists(sumf) else {k: None for k in BASELINE}
    judged = []
    def j(tag, got, want, ok):
        judged.append((tag, got, want, "GREEN" if ok else "RED"))
    j("I1_in_reconcile", "src_in_pins=%d" % c["in_bare"], "report=%s" % rep["in_bare"],
      c["in_bare"] == rep["in_bare"])
    j("I2_falsepath_in", "src_in_fp_pins=%d" % c["in_fp"], "report=%s" % rep["in_fp"],
      c["in_fp"] == rep["in_fp"])
    bare_out = [nm for nm, d, b, st in rows if st == "BARE" and d != "input"]
    j("I3_output_covered", "bare_out_ports=%d" % len(bare_out), "want=0", len(bare_out) == 0)
    grew = [k for k in BASELINE if rep[k] is not None and rep[k] > baseline[k]]
    j("I4_baseline_no_growth", "report=%s" % ",".join("%s:%s" % (k, rep[k]) for k in BASELINE),
      "must_not_exceed=%s" % ",".join(str(baseline[k]) for k in BASELINE), not grew)
    floor_ok = c["user_bits"] >= 20 and all(rep[k] is not None for k in BASELINE)
    j("I5_scope_floor", "user_bits=%d ports=%d" % (c["user_bits"], c["ports"]), "bits>=20 report 4/4", floor_ok)
    all_names = set(nm for nm, d, b, st in rows)
    bad = [p for p, why in exempts if len(why.strip()) < 30]
    ghost = [p for p, why in exempts if not any(nm == p or (p.endswith("*") and nm.startswith(p[:-1]))
                                                for nm in all_names)]
    j("I6_exempt_integrity", "exempt=%d" % len(exempts), "no_reason=%s ghost=%s" %
      (",".join(bad) or "none", ",".join(ghost) or "none"), not bad and not ghost)
    # I7：两边的**单位**必须能对上，否则这条判据就是拿位数减端口对象数（原来的写法正是这样，
    #   还把差值钉成常量 6 ⇒ 它绿得毫无意义：一个我自己造出来的量纲差，被当成"已对账"）。
    #   现在改成正经的两读法：把源码侧按 pins（位数=引脚数）与 ports（顶层端口对象数）各算一遍，
    #   只要**存在一个单位**让四个桶全等于报告里的四个数，I7 才绿；两个单位都对不上就红，
    #   并明确写出"要先问 check_timing -verbose"（#259 欠的就是那份带名字的清单）。
    src = {"pins": (c["in_bare"], c["in_fp"], c["out_bare"], c["out_fp"])}
    src_ports = dict(in_bare=0, in_fp=0, out_bare=0, out_fp=0)
    for nm, d, b, st in rows:
        if st in ("BARE", "FALSEPATH", "TIMED"):
            key = ("in_" if d == "input" else "out_") + ("bare" if st == "BARE" else "fp")
            if st in ("BARE", "FALSEPATH"):
                src_ports[key] += 1
    src["ports"] = (src_ports["in_bare"], src_ports["in_fp"], src_ports["out_bare"], src_ports["out_fp"])
    rep4 = tuple(rep[k] for k in BASELINE)
    ok_units = [u for u in ("pins", "ports") if all(rep[k] is not None for k in BASELINE)
                and src[u] == rep4]
    j("I7_unit_reconcile", "src_pins=%s src_ports=%s report=%s" %
      ("/".join(str(x) for x in src["pins"]), "/".join(str(x) for x in src["ports"]),
       "/".join("NA" if x is None else str(x) for x in rep4)),
      "one_unit_must_match(in_bare/in_fp/out_bare/out_fp)", bool(ok_units))
    verdict = "GREEN" if all(x[3] == "GREEN" for x in judged) else "RED"
    summary = ("IODEBT-SUMMARY report=%s src_in_bare=%d src_in_fp=%d src_out_bare=%d src_out_fp=%d "
               "rep_in_bare=%s rep_in_fp=%s rep_out_bare=%s rep_out_fp=%s "
               "user_bits=%d judged=%d bare_in=[%s] bare_out=[%s] result=%s"
               % (sumf, c["in_bare"], c["in_fp"], c["out_bare"], c["out_fp"],
                  rep["in_bare"], rep["in_fp"], rep["out_bare"], rep["out_fp"],
                  c["user_bits"], len(judged),
                  " ".join(nm for nm, d, b, st in rows if st == "BARE" and d == "input"),
                  " ".join(nm for nm, d, b, st in rows if st == "BARE" and d != "input"),
                  verdict))
    return {"rows": rows, "judged": judged, "summary": summary, "verdict": verdict, "counts": c, "rep": rep}

def make_variant(drop_patterns, append_lines):
    src = read(XDCS[0])
    out = [ln for ln in src.splitlines() if not any(re.match(p, ln) for p in drop_patterns)]
    out.extend(append_lines)
    p = "/tmp/kx/iodebt_variant.xdc"
    io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    return p

def main():
    argv = sys.argv[1:]
    if "--self" in argv:
        rest = [a for a in argv if a != "--self"]
        sumf = rest[0] if rest else "build/evidence/r112_bit/timing_summary.rpt"
        r = 0
        base = run(sumf)
        print("SELF baseline_verdict=%s counts_in_bare=%d in_fp=%d out_bare=%d out_fp=%d user_bits=%d"
              % (base["verdict"], base["counts"]["in_bare"], base["counts"]["in_fp"],
                 base["counts"]["out_bare"], base["counts"]["out_fp"], base["counts"]["user_bits"]))
        # 对照 1：输入侧对账这条必须**能绿**（源码数出来 5 位、报告也是 5 ⇒ 不是把把红的那种尺子）
        ok = base["judged"][0][3] == "GREEN"
        print("SELF control_input_reconcile %s result=%s" % (base["judged"][0], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 2：删掉 key1_n 的 false path ⇒ in_fp 少一位、in_bare 多一位 ⇒ I1/I2 必须撞
        v2 = run(sumf, xdc_list=[make_variant([r"^\s*set_false_path\s+-from\s+\[get_ports\s+key1_n\]"], [])])
        ok = v2["judged"][1][3] == "RED" and v2["judged"][0][3] == "RED"
        print("SELF mutation_drop_false_path %s %s result=%s" % (v2["judged"][0], v2["judged"][1], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 3：给 eth_rx_ctl 补一条 set_input_delay ⇒ 源码端 in_bare 变 4、报告仍是 5 ⇒ I1 必须红
        v3 = run(sumf, xdc_list=[make_variant([], ["set_input_delay -clock eth_rxc 2.000 [get_ports eth_rx_ctl]"])])
        ok = v3["judged"][0][3] == "RED"
        print("SELF mutation_add_input_delay %s result=%s" % (v3["judged"][0], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 4：现场加一条没理由的豁免 ⇒ I6 必须红（反买通）
        v4 = run(sumf, exempt_extra="tmds_data_p|")
        ok = v4["judged"][5][3] == "RED"
        print("SELF mutation_reasonless_exempt %s result=%s" % (v4["judged"][5], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 5：豁免一个 RTL 里根本不存在的名字 ⇒ I6 也必须红（豁免不许空挂）
        v5 = run(sumf, exempt_extra="not_a_port_xyz|这条是编的名字，用来验尺子会不会让幽灵豁免蒙过去")
        ok = v5["judged"][5][3] == "RED"
        print("SELF mutation_ghost_exempt %s result=%s" % (v5["judged"][5], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 6：真件上 I7 必须红——**单位对不上就是没对账**，不许把它糊成绿
        ok = base["judged"][6][3] == "RED"
        print("SELF control_unit_unresolved_on_real %s result=%s" % (base["judged"][6], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 7（正对照，必须能绿）：造一份"四个桶 = 源码侧 pins 读数"的报告 ⇒ I7 必须绿。
        #   没有这一条，I7 就退化成了"永远红的装饰"（规矩：能判红的判据也要能判绿）。
        cc = base["counts"]
        fake = "/tmp/kx/iodebt_fake_summary.rpt"
        io.open(fake, "w", encoding="utf-8", newline="\n").write(
            "5. checking no_input_delay (%d)\n"
            " There are %d input ports with no input delay specified. (HIGH)\n"
            " There are %d input ports with no input delay but user has a false path constraint. (MEDIUM)\n"
            "6. checking no_output_delay (%d)\n"
            " There are %d ports with no output delay specified. (HIGH)\n"
            " There are %d ports with no output delay but user has a false path\n"
            % (cc["in_bare"] + cc["in_fp"], cc["in_bare"], cc["in_fp"],
               cc["out_bare"] + cc["out_fp"], cc["out_bare"], cc["out_fp"]))
        v7 = run(fake)
        ok = v7["judged"][6][3] == "GREEN"
        print("SELF control_unit_reconcile_positive %s result=%s" % (v7["judged"][6], "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        print("SELF check_io_timing_coverage judged=%d controls=7 result=%s"
              % (len(base["judged"]), "PASS" if r == 0 else "FAIL"))
        return r

    sumf = argv[0] if argv else "build/evidence/r112_bit/timing_summary.rpt"
    if not os.path.exists(sumf):
        print("IODEBT-SUMMARY result=REFUSE no_report=%s" % sumf)
        return 2
    res = run(sumf)
    for nm, d, b, st in res["rows"]:
        print("IODEBT-PORT %-16s %-7s bits=%-3d %s" % (nm, d, b, st))
    for x in res["judged"]:
        print("IODEBT %-22s %-22s %s %s" % x)
    print(res["summary"])
    return 0 if res["verdict"] == "GREEN" else 1

if __name__ == "__main__":
    sys.exit(main())

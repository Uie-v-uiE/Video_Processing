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
#   I7 verbose 件自对账（2026-10-05 D3 收的尾）：`check_timing -verbose` 里每一段"There are N …"
#      必须等于它下面点名的行数，且小标题总数必须等于 HIGH+MEDIUM 两段点名数之和
#   I10 名字级两向对账：工具那份 HIGH 名单与我从 RTL+XDC 推出的那份，输入侧集合相等、
#      输出侧无幽灵名、且我判 BARE 的每一个都被工具点名（差分负端按实测口径除外）
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
DEFAULT_SUM = os.environ.get("IODEBT_SUM", "build/reports/build_timing_summary.rpt")
METH = os.environ.get("IODEBT_METH", "build/reports/methodology.rpt")
# 第三个来源：report_methodology 的 TIMING-18 **明细**会自己点名引脚（2026-10-03 实测：
#   eth_rx_ctl + eth_rxd[0..3] 五个输入、led[0]/led[1] 两个输出），这是 check_timing 那种"只给计数"
#   拿不到的东西，所以输入侧能做**名字级**对账，输出侧能做"点名集合是不是我分类的子集"。
# 豁免表随尺子走（规矩 44）。每条格式：端口名模式|理由（不许"临时/先这样"这类空话）
EXEMPT = [
    ("DDR_*", "连到 BD 里的 processing system（PS 硬块），Vivado 不把 PS 硬块引脚当用户 fabric 的 I/O 检查"),
    ("FIXED_IO_*", "同上：PS 硬块的固定外设引脚（MIO/电源轨），由 PS 内部时序管，不属于这一把尺子的射程"),
    ("sys_clk", "它是 create_clock 的对象（20 ns），时钟端口本身不参与 no_input_delay 检查"),
    ("eth_rxc", "它是 create_clock 的对象（RGMII 的 8 ns 时钟）；这一路真正的账是 IDDR 采样窗，见 #46/#57 的实测"),
    # 2026-10-05（用户：按 D→C→B 把对外时序量一遍）——D2：三组"没有外部时序接口"的输出，逐条给可核的理由。
    # 判据 I6 会检查：理由 >=30 字、被豁免的端口必须在 RTL 里真存在；`led`/`eth_mdc`/`eth_mdio` 三条都有出处的行号。
    ("led", "收端是板上的 LED，`rk_zynq7020.xdc:10-11` 是 LVCMOS33 直驱，无接收时钟、无对外时序界 ⇒ `set_output_delay` 没有参考对象；驱动源是心跳位 `pl_video_top.v:1039` 与 `:1042` 的寄存输出，代价只有肉眼看到的呼吸节奏，不是时序"),
    ("eth_mdc", "顶层把它钉成常量 0：`system_top.v:117` 的 `assign eth_mdc = 1'b0;` ⇒ 不存在寄存器到管脚的路径可分析；PHY 工作模式由板上 strap 决定（`system_top.v:114` 的注释记着综合告警 `Synth 8-3917` 的出处）"),
    ("eth_mdio", "顶层是高阻：`system_top.v:116` 的 `assign eth_mdio = 1'bz;` ⇒ fabric 既不驱动也不采样，管理接口在本设计里未接；把它当时序端口检查会造出一条根本不存在的违例"),
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

VERBOSE = os.environ.get("IODEBT_VERBOSE", "build/reports/check_timing_verbose.rpt")
# 2026-10-05（D3，用 `-verbose` 的名字级清单收 #259 的尾）：
#   先前这里写着"小标题与明细是两个**单位**"，那句是**我读错了**。逐行数过那份件之后实情是
#   同一个单位（端口对象）、不同**射程**：
#     `checking no_input_delay (7)`  = HIGH 点了 5 个名（eth_rx_ctl、eth_rxd[0..3]）
#                                    + MEDIUM 点了 2 个名（key1_n、key2_n）= 7
#     `checking no_output_delay (12)` = HIGH 6 个名（led[0]、led[1]、tmds_clk_p、tmds_data_p[0..2]）
#                                     + MEDIUM 6 个名（eth_rst_n、eth_tx_ctl、eth_txd[0..3]）= 12
#   所以小标题 = 两个严重度之和，明细行只报其中一个严重度；把 12−6=6 钉成常量仍然错（那是我自己
#   造的差值，#251 同族），但现在判绿靠的是三段计数与三段点名行数逐段相等，不是扣常数。
# Vivado 在这份名单里的两条口径（是从那份件里读出来的，不是猜的；动它们必须同时改那份件的读法）：
#   ① 差分对只报 `_p` 那一半：tmds_clk_n / tmds_data_n[*] 端口在 RTL 里存在，名单里没有；
#   ② 恒 0 与高阻的输出不被点名：eth_mdc（`system_top.v:117` 常量 0）、eth_mdio（`:116` 高阻）
#      都不在名单里。**这是从这份名单反推的口径，不是手册条文**，所以下面只把它当作
#      "它们不许出现在方向一的等式里"用，不用它去解释任何计数。
#   ③ `eth_tx_clk` 既不在 HIGH 也不在 MEDIUM（它在 clock_groups 里当时钟对象）。
CLOCK_OUTPUTS = ("eth_tx_clk",)

def verbose_lists(path):
    """`check_timing -verbose` -> {check: {total, bare:[names], fp:[names], declared_*}}；
    文件不在就返回 None（判据要红，不许空绿）。"""
    if not os.path.exists(path):
        return None
    t = read(path)
    out = {}
    cur = None
    for line in t.splitlines():
        m = re.match(r"\s*\d+\.\s+checking (\w+)", line)
        if m:
            # 任何 checking 段都重置游标：目录区（文件前半那份"5. checking … (7)"索引）与正文段
            # 用同一形状的小标题，不重置就会把下一段（multiple_clock 等）的行当成上一段的名单。
            cur = m.group(1)
            if m.group(1) in ("no_input_delay", "no_output_delay"):
                mm = re.search(r"checking (no_input_delay|no_output_delay) \((\d+)\)", line)
                e = out.setdefault(mm.group(1), {"total": int(mm.group(2)), "bare": [], "fp": [], "bucket": None})
                e["total"] = int(mm.group(2))
            continue
        if cur not in ("no_input_delay", "no_output_delay"):
            continue
        m = re.search(r"There are (\d+) (?:input )?ports with no (?:input|output) delay specified\. \(HIGH\)", line)
        if m:
            out[cur]["bucket"] = "bare"
            out[cur]["declared_bare"] = int(m.group(1))
            continue
        m = re.search(r"There are (\d+) (?:input )?ports with no (?:input|output) delay"
                      r" but user has a false path.*\(MEDIUM\)", line)
        if m:
            out[cur]["bucket"] = "fp"
            out[cur]["declared_fp"] = int(m.group(1))
            continue
        nm = line.strip()
        # 同一桶里还有第三种"0 ports … but with a timing clock defined on it"（本设计实测为 0），
        # 它既不归 HIGH 也不归 MEDIUM：认不出严重度标记就不许改动 bucket，否则那份"0 条"会把
        # 上一段的声明数覆盖成 0 —— 一条只看计数的判据就会红得莫名其妙。
        if nm and re.match(r"^[A-Za-z_][\w]*(\[\d+\])?$", nm):
            b = out[cur].get("bucket")
            if b:
                out[cur][b].append(nm)
    return out

def match_any(nm, pats):
    for p in pats:
        if p.endswith("*") and nm.startswith(p[:-1]):
            return True
        if p == nm:
            return True
    return False

def methodology_names(path):
    """TIMING-18 明细里点名的引脚 -> (输入列表, 输出列表)。文件不在就返回空（由判据负责红）。"""
    ins, outs = [], []
    if not os.path.exists(path):
        return ins, outs
    for kind, pin in re.findall(r"An (input|output) delay is missing on (\S+) relative", read(path)):
        (ins if kind == "input" else outs).append(pin)
    return ins, outs

def pin_names(nm, bits):
    return [nm] if bits == 1 else ["%s[%d]" % (nm, i) for i in range(bits)]


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

def run(sumf, xdc_list=None, exempt_extra=None, baseline=None, methf=None, verbose=None):
    baseline = baseline or BASELINE
    methf = methf or METH
    rows, c, exempts = classify(xdc_list, exempt_extra)
    rep = report_counts(sumf) if os.path.exists(sumf) else {k: None for k in BASELINE}
    judged = []
    def j(tag, got, want, ok):
        judged.append((tag, got, want, "GREEN" if ok else "RED"))
    # 三态判据：单位/出处没定的那条**不许用 bool 表达**（j 的第四参数是 bool，
    # 传字符串 "GREEN" 会被当真值 ⇒ 假绿）。需要 NOT_MEASURED 的走 j3。
    def j3(tag, got, want, state):
        judged.append((tag, got, want, state))
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
    # I7：`check_timing -verbose` 那份件**自己内部**必须对得上账（这是收 #259 的那一刀）。
    #   三段都要相等：① 每一段"There are N …"的 N == 它下面点名的行数；② 小标题总数 == HIGH 点名数 + MEDIUM 点名数。
    #   对不上就只有两种可能：工具的口径和我读出来的不一样（那就是尺子错），或者名单被改过（那就是件不可信）。
    #   两种都不许静默通过。件读不到 = REFUSE（不是红也不是绿）。
    vl = verbose_lists(verbose or VERBOSE)
    if vl is None:
        j3("I7_verbose_selfreconcile", "verbose=%s not readable" % (verbose or VERBOSE),
           "each bucket count == named lines", "REFUSE")
    else:
        bad7, seg7 = [], []
        for chk in ("no_input_delay", "no_output_delay"):
            e = vl.get(chk)
            if not e:
                bad7.append("%s:section missing" % chk); continue
            nb, nf = len(e.get("bare", [])), len(e.get("fp", []))
            db, df = e.get("declared_bare"), e.get("declared_fp")
            if db != nb:
                bad7.append("%s:HIGH declared %s != named %d" % (chk, db, nb))
            if df != nf:
                bad7.append("%s:MEDIUM declared %s != named %d" % (chk, df, nf))
            if e["total"] != nb + nf:
                bad7.append("%s:header %s != HIGH%d+MEDIUM%d" % (chk, e["total"], nb, nf))
            seg7.append("%s=%s/%d+%d" % (chk, e["total"], nb, nf))
        j3("I7_verbose_selfreconcile", " ".join(seg7) + ("" if not bad7 else " MISMATCH: " + "; ".join(bad7)),
           "header=HIGH+MEDIUM and each bucket count == named lines", "GREEN" if not bad7 else "RED")
    # I10：**名字级**两向对账（工具那份 HIGH 名单 vs 我从 RTL+XDC 推出来的那份）。
    #   输入侧走严格相等；输出侧走"工具点名的每一个都必须在我这边有归属"+
    #   "我判 BARE 的每一个都必须被工具点名，除非落进上面 ① 那条差分对口径"。
    #   这一条是把 I6 的豁免表钉回现实的：豁免表要是漂了（多一条、少一条、名字写错），这里就红。
    if vl is None:
        j3("I10_names_vs_source", "verbose not readable", "name sets agree", "REFUSE")
    else:
        mine_in = sorted(p for nm, d, b, st in rows if st == "BARE" and d == "input" for p in pin_names(nm, b))
        tool_in = sorted(vl.get("no_input_delay", {}).get("bare", []))
        tool_out = sorted(vl.get("no_output_delay", {}).get("bare", []))
        mine_out_bare = set(p for nm, d, b, st in rows if st == "BARE" and d != "input" for p in pin_names(nm, b))
        mine_out_exempt = set(p for nm, d, b, st in rows if st == "EXEMPT" and d != "input" for p in pin_names(nm, b))
        mine_out_all = sorted(mine_out_bare | mine_out_exempt)
        # 差分负端（`_n` 且把 `_n` 换成 `_p` 后同一份名单里有对应名字）不被工具点名，是本设计实测到的口径 ①。
        neg = sorted(p for p in mine_out_bare
                     if p not in tool_out and
                     re.sub(r"_n(\[\d+\])?$", r"_p\1", p) in set(tool_out))
        ghosts10 = [x for x in tool_out if x not in mine_out_all]
        unexplained = [x for x in mine_out_bare if x not in tool_out and x not in neg]
        ok10 = (tool_in == mine_in) and not ghosts10 and not unexplained
        j3("I10_names_vs_source",
           "in src=[%s] tool=[%s] out_ghost=[%s] out_unexplained=[%s] diff_neg_excluded=[%s]" %
           (" ".join(mine_in), " ".join(tool_in), ",".join(ghosts10) or "none",
            ",".join(unexplained) or "none", " ".join(neg)),
           "input sets identical; no ghost out names; every out BARE named by tool (diff pair neg half excluded)",
           "GREEN" if ok10 else "RED")

    mi, mo = methodology_names(methf)
    src_in_pins = sorted(p for nm, d, b, st in rows if st == "BARE" and d == "input" for p in pin_names(nm, b))
    src_out_pins = sorted(p for nm, d, b, st in rows if st == "BARE" and d != "input" for p in pin_names(nm, b))
    # I8：输入侧**名字级**三源对账（源码位展开 == methodology 点名的引脚），少一个名字就红，不许靠计数蒙对
    j("I8_methodology_inputs", "src=[%s] meth=[%s]" % (" ".join(src_in_pins), " ".join(sorted(mi))),
      "identical-name-sets and meth>=1", sorted(mi) == src_in_pins and len(mi) >= 1)
    # I9：输出侧只做子集判（methodology 点名的每个引脚都必须落在我判 BARE 的输出里）；
    #   没被它点名的那几个（TMDS/MDIO 那 10 个引脚）是**留给 -verbose 的开放项**，念出来不判绿也不假判红
    # 2026-10-05（D2）：工具点名的输出引脚允许落进两个集合之一 —— 我判 BARE 的，或**带理由被豁免**的。
    # 这不是把豁免变成万能免死：豁免本身由 I6 管（理由 >=30 字、端口必须真存在），
    # 而 `--self` 的 control_ghost_meth_name 注入的 `not_a_pin[9]` 两个集合都不在 ⇒ 仍然必须红。
    exempt_out_pins = sorted(p for nm, d, b, st in rows if st == "EXEMPT" and d != "input" for p in pin_names(nm, b))
    allowed_out = set(src_out_pins) | set(exempt_out_pins)
    ghosts = [x for x in mo if x not in allowed_out]
    covered = [x for x in mo if x in exempt_out_pins]
    resid = [x for x in src_out_pins if x not in mo]
    j("I9_methodology_outputs", "named=%d ghost=%s unnamed_residual=%d named_but_exempted_with_reason=%s" %
      (len(mo), ",".join(ghosts) or "none", len(resid), ",".join(covered) or "none"),
      "no ghost names", not ghosts)
    states = set(x[3] for x in judged)
    if "RED" in states or "REFUSE" in states:
        verdict = "RED"
    elif "NOT_MEASURED" in states:
        verdict = "NOT_MEASURED"
    else:
        verdict = "GREEN"
    summary = ("IODEBT-SUMMARY report=%s src_in_bare=%d src_in_fp=%d src_out_bare=%d src_out_fp=%d "
               "rep_in_bare=%s rep_in_fp=%s rep_out_bare=%s rep_out_fp=%s "
               "user_bits=%d judged=%d meth_in=%d meth_out=%d resid_out=[%s] bare_in=[%s] bare_out=[%s] result=%s"
               % (sumf, c["in_bare"], c["in_fp"], c["out_bare"], c["out_fp"],
                  rep["in_bare"], rep["in_fp"], rep["out_bare"], rep["out_fp"],
                  c["user_bits"], len(judged), len(mi), len(mo), " ".join(resid),
                  " ".join(nm for nm, d, b, st in rows if st == "BARE" and d == "input"),
                  " ".join(nm for nm, d, b, st in rows if st == "BARE" and d != "input"),
                  verdict))
    return {"rows": rows, "judged": judged, "summary": summary, "verdict": verdict, "counts": c, "rep": rep}

def jt(res, tag):
    """按标签取那条判定行。`--self` 一律用它，不再写 judged[7] 这种硬编号：
    判据插在中间就会让对照打到别的判据上（这条尺子自己就差点被这样废掉）。"""
    for row in res["judged"]:
        if row[0] == tag:
            return row
    raise KeyError(tag)

def patch_verbose(src, drop=None, ghost_after=None, header=None):
    """把归档的 -verbose 件改成某种**坏法**，用来验对照真的能红。按行做，不做整串替换：
    那些名字行没有缩进，用 ' 名字' 去 replace 会静默失配（我第一版就是这样，三条对照全绿了个假）。"""
    lines = src.splitlines(True)
    if header:
        pat = "checking %s (" % header[0]
        lines = [re.sub(r"checking " + re.escape(header[0]) + r" \(\d+\)",
                        "checking " + header[0] + " (%d)" % header[1], ln) if pat in ln else ln
                 for ln in lines]
    if drop:
        for i, ln in enumerate(lines):
            if ln.strip() == drop:
                del lines[i]; break
        else:
            raise KeyError("drop 目标不在件里：%s" % drop)
    if ghost_after:
        for i, ln in enumerate(lines):
            if ln.strip() == ghost_after[0]:
                lines.insert(i + 1, ghost_after[1] + chr(10)); break
        else:
            raise KeyError("ghost_after 目标不在件里：%s" % ghost_after[0])
    return "".join(lines)

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
        # 默认读**盘上现行**那份实现报告，不是某一颗归档位流的副本：
        #   尺子的默认件必须是"当前这一版"，否则它读的是历史（规矩：报告默认路径是每轮变量）。
        sumf = rest[0] if rest else os.environ.get("IODEBT_SUM", DEFAULT_SUM)
        r = 0
        base = run(sumf)
        print("SELF baseline_verdict=%s counts_in_bare=%d in_fp=%d out_bare=%d out_fp=%d user_bits=%d"
              % (base["verdict"], base["counts"]["in_bare"], base["counts"]["in_fp"],
                 base["counts"]["out_bare"], base["counts"]["out_fp"], base["counts"]["user_bits"]))
        # 对照 1：输入侧对账这条必须**能绿**（源码数出来 5 位、报告也是 5 ⇒ 不是把把红的那种尺子）
        ok = jt(base, "I1_in_reconcile")[3] == "GREEN"
        print("SELF control_input_reconcile %s result=%s" % (jt(base, "I1_in_reconcile"), "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 2：删掉 key1_n 的 false path ⇒ in_fp 少一位、in_bare 多一位 ⇒ I1/I2 必须撞
        v2 = run(sumf, xdc_list=[make_variant([r"^\s*set_false_path\s+-from\s+\[get_ports\s+key1_n\]"], [])])
        a, b = jt(v2, "I1_in_reconcile"), jt(v2, "I2_falsepath_in")
        ok = a[3] == "RED" and b[3] == "RED"
        print("SELF mutation_drop_false_path %s %s result=%s" % (a, b, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 3：给 eth_rx_ctl 补一条 set_input_delay ⇒ 源码端 in_bare 变 4、报告仍是 5 ⇒ I1 必须红
        v3 = run(sumf, xdc_list=[make_variant([], ["set_input_delay -clock eth_rxc 2.000 [get_ports eth_rx_ctl]"])])
        row = jt(v3, "I1_in_reconcile")
        ok = row[3] == "RED"
        print("SELF mutation_add_input_delay %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 4：现场加一条没理由的豁免 ⇒ I6 必须红（反买通）
        v4 = run(sumf, exempt_extra="tmds_data_p|")
        row = jt(v4, "I6_exempt_integrity")
        ok = row[3] == "RED"
        print("SELF mutation_reasonless_exempt %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 5：豁免一个 RTL 里根本不存在的名字 ⇒ I6 也必须红（豁免不许空挂）
        v5 = run(sumf, exempt_extra="not_a_port_xyz|这条是编的名字，用来验尺子会不会让幽灵豁免蒙过去")
        row = jt(v5, "I6_exempt_integrity")
        ok = row[3] == "RED"
        print("SELF mutation_ghost_exempt %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 6（真实件，正对照）：D3 拿到 `-verbose` 的名字级清单以后，I7 与 I10 在真实归档件上
        #   必须**判得出绿**——一条只会红或只会 NOT_MEASURED 的判据等于没有（规矩：能判红的也要能判绿）。
        base = run(sumf)
        a, b = jt(base, "I7_verbose_selfreconcile"), jt(base, "I10_names_vs_source")
        ok = a[3] == "GREEN" and b[3] == "GREEN"
        print("SELF control_verbose_real_green %s | %s result=%s" % (a, b, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        real_v = read(VERBOSE)
        # 对照 7：把输出段的小标题 12 改成 11 ⇒ I7 必须红（目录行与正文行一起改：只改一处会被另一处盖回去）
        p7 = "/tmp/kx/iodebt_v_header.rpt"
        io.open(p7, "w", encoding="utf-8", newline="").write(
            patch_verbose(real_v, header=("no_output_delay", 11)))
        v7 = run(sumf, verbose=p7)
        row = jt(v7, "I7_verbose_selfreconcile")
        ok = row[3] == "RED"
        print("SELF control_header_mismatch %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 8：从 HIGH 名单里删掉一个名字 ⇒ 声明数与点名行数不再相等（I7 红），
        #   而我这边它仍是 BARE ⇒ 没被工具点名（I10 红）。一刀同时红两条，因为它们守的是同一个事实。
        p8 = "/tmp/kx/iodebt_v_dropped.rpt"
        io.open(p8, "w", encoding="utf-8", newline="").write(patch_verbose(real_v, drop="tmds_data_p[2]"))
        v8 = run(sumf, verbose=p8)
        r7, r10 = jt(v8, "I7_verbose_selfreconcile"), jt(v8, "I10_names_vs_source")
        ok = r7[3] == "RED" and r10[3] == "RED"
        print("SELF control_dropped_name %s | %s result=%s" % (r7, r10, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 9：往 HIGH 名单里塞一个本设计没有的引脚 ⇒ I10 必须红（幽灵点名，豁免表漂了也走这条）
        p9 = "/tmp/kx/iodebt_v_ghost.rpt"
        io.open(p9, "w", encoding="utf-8", newline="").write(
            patch_verbose(real_v, ghost_after=("tmds_clk_p", "not_a_pin[9]")))
        v9 = run(sumf, verbose=p9)
        row = jt(v9, "I10_names_vs_source")
        ok = row[3] == "RED"
        print("SELF control_ghost_verbose_name %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 10：verbose 件不在 ⇒ I7/I10 都 REFUSE（判据不许因为读不到输入而静默变绿）
        v10 = run(sumf, verbose="/tmp/kx/definitely_not_here.rpt")
        r7, r10 = jt(v10, "I7_verbose_selfreconcile"), jt(v10, "I10_names_vs_source")
        ok = r7[3] == "REFUSE" and r10[3] == "REFUSE"
        print("SELF control_verbose_missing_refuse %s | %s result=%s" % (r7, r10, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 11：把 methodology 的一条输入点名删掉 ⇒ I8 必须红（名字级对账不许靠计数蒙对）
        mt = read(METH).replace("An input delay is missing on eth_rxd[2] relative", "An input delay is missing on eth_rxd[2]", 1)
        f11 = "/tmp/kx/iodebt_meth_noinput.rpt"
        io.open(f11, "w", encoding="utf-8", newline="\n").write(mt)
        v11 = run(sumf, methf=f11)
        row = jt(v11, "I8_methodology_inputs")
        ok = row[3] == "RED"
        print("SELF control_missing_meth_name %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        # 对照 12：给 methodology 塞一个本设计里不存在的引脚名 ⇒ I9 必须红（幽灵点名）
        f12 = "/tmp/kx/iodebt_meth_ghost.rpt"
        io.open(f12, "w", encoding="utf-8", newline="\n").write(
            read(METH).replace("An output delay is missing on led[0] relative",
                               "An output delay is missing on not_a_pin[9] relative", 1))
        v12 = run(sumf, methf=f12)
        row = jt(v12, "I9_methodology_outputs")
        ok = row[3] == "RED"
        print("SELF control_ghost_meth_name %s result=%s" % (row, "PASS" if ok else "FAIL"))
        r |= 0 if ok else 1
        print("SELF check_io_timing_coverage judged=%d controls=12 result=%s"
              % (len(base["judged"]), "PASS" if r == 0 else "FAIL"))
        return r

    sumf = argv[0] if argv else os.environ.get("IODEBT_SUM", DEFAULT_SUM)
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

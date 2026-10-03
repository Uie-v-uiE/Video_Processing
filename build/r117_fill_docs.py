#!/usr/bin/env python3
# build/r117_fill_docs.py -- push r117's official-build readings into the delivery docs.
# Default is --check (print only); --apply writes. All CJK prose lives in
# build/r117_doc_templates.txt so this file stays ASCII-only (the GBK console / mixed-quote
# family of traps: ISSUES #321 #324 -- a straight quote inside a double-quoted Python string
# silently ends the literal and the next CJK token becomes "invalid character").
#
# Every number is read from a named artifact (prompt rule 44: a "now/current" claim's baseline
# must be an artifact, never my memory):
#   WNS/WHS/failing endpoints/total/WPWS : build/timing_summary.rpt (Design Timing Summary row)
#   per-clock setup/hold + rel margin    : build/evidence/r117_after_roster_probefmt.txt
#   worst hold cell shape                : build/hold_paths.rpt (first path block)
#   LUT/FF/BRAM/DSP                      : build/utilization.rpt
#   bit identity                         : build/evidence/r117_bit_md5.txt
#   gate counts / flash time / board     : --set key=value (must be read off that run's artifact)
import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
SUM = "build/timing_summary.rpt"
ROSTER = os.environ.get("VP_FILL_ROSTER", "build/evidence/r117_after_roster_probefmt.txt")
UTIL = "build/utilization.rpt"
BITMD5 = os.environ.get("VP_FILL_BIT", "build/evidence/r118_bit_md5.txt")
HOLD = "build/hold_paths.rpt"
TPL = "build/r117_doc_templates.txt"
MINUS = u"\u2212"
APPLY = "--apply" in sys.argv


def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read().splitlines()


def num(tok):
    if tok is None:
        return None
    m = re.search(r"-?\d+(?:\.\d+)?", tok.replace(MINUS, "-"))
    return float(m.group(0)) if m else None


def sgn(v):
    if v is None:
        return "NA"
    return (MINUS if v < 0 else "") + ("%g" % abs(v))


def die(msg):
    raise SystemExit("FILL-REFUSE " + msg)


def summary():
    ls = read(SUM)
    for i, l in enumerate(ls):
        if l.strip().startswith("WNS(ns)"):
            for j in range(i + 1, min(i + 6, len(ls))):
                t = ls[j].split()
                if len(t) >= 9 and re.match(r"^-?[\d.]+$", t[0]):
                    return dict(wns=float(t[0]), tns=float(t[1]), sfail=int(t[2]), stot=int(t[3]),
                                whs=float(t[4]), ths=float(t[5]), hfail=int(t[6]),
                                htot=int(t[7]), wpws=float(t[8]))
            die("no numeric row under Design Timing Summary in " + SUM)
    die("no 'WNS(ns)' header row in " + SUM)


def util():
    d = {}
    key = {"Slice LUTs": "lut", "Slice Registers": "ff", "Block RAM Tile": "bram", "DSPs": "dsp"}
    for l in read(UTIL):
        m = re.match(r"\|\s*(Slice LUTs|Slice Registers|Block RAM Tile|DSP48|DSPs)\s*\|\s*([\d.]+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*[\d,]+\s*\|\s*([\d.]+)\s*\|", l)
        if m and m.group(1) in key and key[m.group(1)] not in d:
            d[key[m.group(1)]] = (float(m.group(2)), float(m.group(3)))
    for k in ("lut", "ff", "bram", "dsp"):
        if k not in d:
            die("utilization row missing " + k + " in " + UTIL)
    return dict(lut=int(d["lut"][0]), lutp=d["lut"][1], ff=int(d["ff"][0]), ffp=d["ff"][1],
                bram=d["bram"][0], bramp=d["bram"][1], dsp=int(d["dsp"][0]), dspp=d["dsp"][1])


def roster():
    d = {}
    for l in read(ROSTER):
        if not l.startswith("ROSTER|"):
            continue
        parts = l.split("|")
        kind = parts[1]
        f = dict(x.split("=", 1) for x in parts[2:] if "=" in x)
        clk = f.get("clk", "?")
        v = num(f.get("slack"))
        if v is None:
            continue
        d[clk + "_setup" if kind == "setup" else clk + "_hold"] = v
        k2 = "setup_pct" if kind == "setup" else "hold_pct"
        d[clk + "_" + k2] = num(f.get("margin_pct"))
    for need in ("clk_fpga_0_setup", "eth_rxc_setup", "clkout0_1_setup", "sys_clk_setup",
                 "eth_rxc_hold", "clk_fpga_0_hold"):
        if need not in d:
            die("roster missing " + need + " in " + ROSTER)
    return d


def worst_hold():
    if not os.path.exists(HOLD):
        return {}
    t = "\n".join(read(HOLD))
    blk = t.split("---------------------------------------------")
    for b in blk:
        s = re.search(r"Slack \(.*?\):\s*(-?[\d.]+)ns", b)
        lv = re.search(r"Logic Levels:\s+(\d+)", b)
        rt = re.search(r"route ([\d.]+)ns \(([\d.]+)%\)", b)
        if s and lv:
            return dict(worst_hold_slack=float(s.group(1)), worst_hold_levels=int(lv.group(1)),
                        worst_hold_route=float(rt.group(2)) if rt else 0.0)
    return {}


def templates():
    specs, cur_path, cur_pref, body = [], None, None, []
    for l in read(TPL):
        if l.startswith("@@ "):
            if cur_path:
                specs.append((cur_path, cur_pref, "\n".join(body).strip()))
            head = l[3:].split(" ", 1)
            if len(head) != 2:
                die("template header must be '@@ <path> <prefix>': " + l)
            cur_path = head[0].strip()
            cur_pref = head[1].strip()
            # paths contain no spaces, so one split is enough; csv rows have no leading pipe
            if cur_path.endswith(".csv") and cur_pref.startswith("| "):
                cur_pref = cur_pref[2:]
            body = []
        elif cur_path:
            body.append(l)
    if cur_path:
        specs.append((cur_path, cur_pref, "\n".join(body).strip()))
    if len(specs) < 3:
        die("template file gave only %d specs" % len(specs))
    return specs


V = {}
V.update(summary())
V.update(util())
V.update(roster())
V.update(worst_hold())
V["bit"] = read(BITMD5)[0].strip() if os.path.exists(BITMD5) else "NA"
V.setdefault("worst_hold_levels", "NA")
V.setdefault("worst_hold_route", 0.0)
for a in sys.argv[1:]:
    if a.startswith("--set="):
        for kv in a[6:].split(";"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                V[k] = v
for need in ("g_judged", "g_green", "g_red", "flash_time", "bv_time", "bv_verdict",
             "r114_clk_fpga_0_pct", "ff_base"):
    if need not in V:
        die("missing --set key " + need + " (these must be read off that run's artifact)")

V["whs_owner"] = min((k for k in V if k.endswith("_hold")), key=lambda k: V[k]).rsplit("_hold", 1)[0]
V["wns_owner"] = min((k for k in V if k.endswith("_setup")), key=lambda k: V[k]).rsplit("_setup", 1)[0]
V["rel_owner"] = min((k for k in V if k.endswith("_setup_pct")), key=lambda k: V[k]).rsplit("_setup_pct", 1)[0]
V["wns_s"] = sgn(V["wns"])
V["whs_s"] = sgn(V["whs"])
for k in list(V):
    if k.endswith("_setup") or k.endswith("_hold"):
        V[k + "_s"] = sgn(V[k])
V["g_judged_i"] = str(int(V["g_judged"]))
V["g_green_i"] = str(int(V["g_green"]))
V["g_red_i"] = str(int(V["g_red"]))
V["sfail_i"] = str(V["sfail"])
V["hfail_i"] = str(V["hfail"])
V["stot_i"] = str(V["stot"])
V["lut_i"] = str(V["lut"])
V["ff_i"] = str(V["ff"])
V["dsp_i"] = str(V["dsp"])
V["bram_s"] = "%g" % V["bram"]
V["ffd_i"] = str(V["ff"] - int(V["ff_base"]))
for extra in ("bramp", "lutp", "ffp", "dspp", "wpws", "worst_hold_route",
              "eth_rxc_setup_pct", "clk_fpga_0_setup_pct", "clkout0_1_setup_pct",
              "sys_clk_setup_pct", "r114_clk_fpga_0_pct"):
    _v = V.get(extra)
    V[extra + "_g"] = "NA" if _v is None else ("%g" % float(_v))
V["worst_hold_levels_i"] = str(V["worst_hold_levels"])

specs = templates()
missing = set()
plan = []
for path, prefix, tpl in specs:
    for k in re.findall(r"\{([a-zA-Z0-9_]+)\}", tpl):
        if k not in V:
            missing.add(k)
    if not os.path.exists(path):
        die("target doc missing: " + path)
    ls = read(path)
    hits = [i for i, l in enumerate(ls) if l.startswith(prefix)]
    if len(hits) != 1:
        die("prefix %r matched %d rows in %s (want exactly 1)" % (prefix, len(hits), path))
    if path.endswith(".csv") and tpl.count(",") != 6:
        die("csv template for %r has %d commas, want 6 (7 fields)" % (prefix, tpl.count(",")))
    plan.append((path, hits[0] + 1, tpl))
if missing:
    die("unfilled placeholders: " + ", ".join(sorted(missing)))

def subst(tpl):
    out = tpl
    for k, v in sorted(V.items(), key=lambda x: -len(x[0])):
        out = out.replace("{" + k + "}", str(v))
    return out

checked = 0
byfile = {}
for path, ln, tpl in plan:
    new = subst(tpl)
    old = (byfile[path][0] if path in byfile else read(path))
    snap = list(old)
    checked += 1
    print("ROW %s:%d OLD=%s" % (path, ln, snap[ln - 1][:60].encode("ascii", "replace").decode()))
    print("ROW %s:%d NEW=%s" % (path, ln, new[:60].encode("ascii", "replace").decode()))
    snap[ln - 1] = new
    byfile[path] = (snap, [])
if not APPLY:
    print("FILL-CHECK rows=%d placeholders_filled=%d (no write)" % (checked, len(V)))
    raise SystemExit(0)
for path, ls in byfile.items():
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(ls) + "\n")
bad = 0
for path, ln, tpl in plan:
    new = subst(tpl)
    if read(path)[ln - 1] != new:
        bad += 1
        print("FILL-VERIFY-MISMATCH %s:%d" % (path, ln))
print("FILL-APPLY wrote=%d mismatch=%d" % (len(plan), bad))
raise SystemExit(1 if bad else 0)

#!/usr/bin/env python
# 用途："""build/p15b_parse_reports.py —— P15b：把 r118 原件报告抽成结构化数据 + 按时钟域展开的名册
# 输入：命令行参数
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# -*- coding: utf-8 -*-
"""build/p15b_parse_reports.py —— P15b：把 r118 原件报告抽成结构化数据 + 按时钟域展开的名册。

这是一件**只读**尺子：不跑构建、不改 src/、不碰 P15a 的 `build/provenance.md`。
它做四件事：
  1. `--emit`  解析 `build/*.rpt` 与 `build/*.txt`（r118 那一轮，指纹由 provenance.md 提供）
               → `build/parsed/<name>.json`（字段名沿用原件表头，每个值带 `file/line/col`）
               → `build/roster/roster_r118.tsv`（口径 = 既有尺子 `build/r115_roster_build.py` 的 13+1 列）
               → `build/roster/roster_r118_probe.tsv`（口径 = 既有探针名册的 ROSTER| 字段）
  2. `--check` 跑 6 条质量判据，一条一行，判定放**最后一个字段**，并打印分母
  3. `--self`  给每条判据注入一个反例，验证「只染红被注入的那一条」，连带红逐条列出
  4. `--fieldmap` 打印字段位置表（原件 + 行 + 列 + 取到的值），供 report/build-notes.md 引用

三态：`PASS` / `FAIL` / `NOT_MEASURED`。解析不到的值一律写 `NOT_MEASURED`，
**绝不写 0、绝不写空串**——`0` 在这个仓库里是「量到过 0 个违例」，`NOT_MEASURED` 才是「没读到」。
确定性：输出里不写墙钟时间，JSON 键排序，换行固定 LF ⇒ 同一输入两次跑逐字节一致（判据 6）。
"""
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time

try:                                       # Windows 控制台默认 GBK，中文行会抛 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

NM = "NOT_MEASURED"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUND = "r118"

# parsed/ 的 1:1 清单：一个原件 → 一个解析件。全部必须是 build/provenance.md 第 5 节里带指纹的行。
REPORTS = [
    "build/reports/build_timing_summary.rpt",
    "build/reports/build_utilization.rpt",
    "build/reports/methodology.rpt",
    "build/reports/cdc.rpt",
    "build/reports/power.rpt",
    "build/reports/build_route_status.rpt",
    "build/reports/clock_util.rpt",
    "build/reports/width_warnings.txt",
    "build/reports/multi_driven.txt",
]
PROVENANCE_MD = "build/provenance.md"
R118_PROBE_ROSTER = "board/output/r118_after_roster_probefmt.txt"
R118_PERCLK_GLOB = "build/roster_r118_after_%s_%s.rpt"
CLOCK_NAMES = ["clk_fpga_0", "clkfbout", "clkfbout_1", "clkout0_1", "clkout1_1",
               "clkout2", "eth_rxc", "sys_clk"]


# --------------------------------------------------------------------------
# 读原件的小工具：所有取值都带 (line, col)，位置是**当场找出来的**，不是手抄的行号
# --------------------------------------------------------------------------
def read_lines(rel):
    """返回 (行列表, None) 或 (None, 失败原因)。文件不存在/读不到 = NOT_MEASURED 的唯一合法入口。"""
    p = rel if os.path.isabs(rel) else os.path.join(REPO, rel)
    if not os.path.isfile(p):
        return None, "missing"
    try:
        txt = io.open(p, encoding="utf-8", errors="replace").read()
    except Exception as e:                                    # noqa: BLE001
        return None, "unreadable:%s" % e.__class__.__name__
    return txt.replace("\r\n", "\n").replace("\r", "\n").split("\n"), None


def tokens(lines, lineno):
    """1-based 行号 → 按空白切出的列（col 从 1 开始，与 awk 的 $n 同义）。"""
    if lineno is None or lineno < 1 or lineno > len(lines):
        return []
    return lines[lineno - 1].split()


def pipe_cells(lines, lineno):
    """1-based 行号 → 按 '|' 切的单元格（col 从 1 开始，跳过首尾空段）。"""
    if lineno is None or lineno < 1 or lineno > len(lines):
        return []
    raw = lines[lineno - 1].split("|")[1:-1]
    return [c.strip() for c in raw]


def cell(lines, lineno, col):
    """取一个空白列的值；取不到就 NM（不返回 ""、不返回 0）。"""
    t = tokens(lines, lineno)
    if col < 1 or col > len(t):
        return NM
    return t[col - 1]


def pcell(lines, lineno, col):
    """取一个 '|' 单元格；越界或原件该格本来就是空的 ⇒ NOT_MEASURED（空串不当读数）。"""
    t = pipe_cells(lines, lineno)
    if col is None or t is None or col < 1 or col > len(t) or t[col - 1] == "":
        return NM
    return t[col - 1]


def find(lines, pred, start=0):
    """返回 1-based 行号，找不到 = None。"""
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i + 1
    return None


def find_re(lines, pattern, start=0):
    """原件这些句子**行首有一个空格**（` There are 0 pins …`），所以按 strip 后的行匹配。"""
    rx = re.compile(pattern)
    for i in range(start, len(lines)):
        if rx.search(lines[i].strip()):
            return i + 1
    return None


def rec(fp, name, rel, lineno, col, value, how):
    """登记一个字段：值 + 位置 + 定位方式。取不到也登记（这样 NOT_MEASURED 可数）。"""
    fp.append({"field": name, "file": rel, "line": lineno if lineno else NM,
               "col": col if col else NM, "value": value, "locator": how})
    return value


# --------------------------------------------------------------------------
# 各报告形状的**现场量取**（铁律 1）：先找锚点行，再按锚点取列
# --------------------------------------------------------------------------
def parse_timing_summary(rel):
    lines, err = read_lines(rel)
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    if err:
        out["parse_status"] = NM
        out["reason"] = err
        return out
    fp = out["field_positions"]
    out["parse_status"] = "OK"
    out["sections"]["banner"] = parse_banner(rel, lines, fp)

    # Design Timing Summary：标题行 → 表头行 → 虚线行 → 数据行
    t = find(lines, lambda l: l.strip().startswith("| Design Timing Summary"))
    h = find(lines, lambda l: l.strip().startswith("WNS(ns)"), t or 0)
    hdr = tokens(lines, h) if h else []
    d = find(lines, lambda l: l.strip() != "" and not set(l.strip()) <= set("-"), (h or 0) + 1)
    names = ["WNS(ns)", "TNS(ns)", "TNS Failing Endpoints", "TNS Total Endpoints",
             "WHS(ns)", "THS(ns)", "THS Failing Endpoints", "THS Total Endpoints",
             "WPWS(ns)", "TPWS(ns)", "TPWS Failing Endpoints", "TPWS Total Endpoints"]
    row = {}
    for i, nm in enumerate(names):
        v = cell(lines, d, i + 1)
        row[nm] = v
        rec(fp, "design_timing_summary." + nm, rel, d, i + 1, v, locator_for(rel, d, i + 1))
    out["sections"]["design_timing_summary"] = {"title_line": t or NM, "header_line": h or NM,
                                                "header_cells": hdr, "data_line": d or NM, "row": row}

    # Clock Summary / Intra / Inter / Other Path Groups
    for title, hpat, key, ncols in (
            ("| Clock Summary", r"^Clock\s+Waveform\(ns\)", "clock_summary", 5),
            ("| Intra Clock Table", r"^Clock\s+WNS\(ns\)", "intra_clock_table", 13),
            ("| Inter Clock Table", r"^From Clock\s+To Clock", "inter_clock_table", 10),
            ("| Other Path Groups Table", r"^Path Group\s+From Clock", "other_path_groups_table", 10)):
        tt = find(lines, lambda l, x=title: l.strip().startswith(x))
        hh = find(lines, lambda l, p=hpat: re.match(p, l), tt or 0)
        rows = []
        if hh:
            i = hh + 1                                     # 索引 = 行号-1：表头(hh) 的下一行是虚线，再下一行才是数据
            while i < len(lines):
                ln = lines[i]
                if ln.strip() == "":
                    break
                tk = ln.split()
                r = {"line": i + 1, "cells": {}}
                for j, tok in enumerate(tk[:ncols]):
                    r["cells"]["col%d" % (j + 1)] = tok
                rows.append(r)
                i += 1
        out["sections"][key] = {"title_line": tt or NM, "header_line": hh or NM,
                                "header_cells": tokens(lines, hh) if hh else [],
                                "rows": rows, "row_count": len(rows)}
        if key == "intra_clock_table":
            for r in rows:
                c = r["cells"]
                nm = c.get("col1", NM)
                ntok = len(tokens(lines, r["line"]))
                full = ntok >= 9
                for lbl, col in (("WNS(ns)", 2), ("TNS Failing Endpoints", 4),
                                 ("THS Failing Endpoints", 8)):
                    v = c.get("col%d" % col, NM) if full else NM
                    rec(fp, "intra_clock[%s].%s" % (nm, lbl), rel, r["line"] if full else None,
                        col if full else None, v, locator_for(rel, r["line"] if full else None, col))
                vtp = c.get("col13", NM) if full else c.get("col5", NM)
                rec(fp, "intra_clock[%s].TPWS Total Endpoints" % nm, rel, r["line"],
                    13 if full else 5, vtp, locator_for(rel, r["line"], 13 if full else 5))
        if key == "clock_summary":
            for r in rows:
                c = r["cells"]
                rec(fp, "clock_summary[%s].Period(ns)" % c.get("col1", NM), rel, r["line"], 4,
                    c.get("col4", NM), locator_for(rel, r["line"], 4))
                rec(fp, "clock_summary[%s].Frequency(MHz)" % c.get("col1", NM), rel, r["line"], 5,
                    c.get("col5", NM), locator_for(rel, r["line"], 5))

    # 内嵌的 Report Methodology 表（原件自己就带了 report_methodology 的快照）
    rm = find(lines, lambda l: l.strip().startswith("| Report Methodology"))
    rh = find(lines, lambda l: l.strip().startswith("Rule       Severity") or
                              re.match(r"^Rule\s+Severity", l), rm or 0)
    mrows = []
    if rh:
        i = rh + 1
        while i < len(lines) and lines[i].strip():
            tk = lines[i].split()
            if len(tk) >= 4:
                mrows.append({"line": i + 1, "Rule": tk[0], "Severity": tk[1],
                              "Violations": tk[-1], "Description": " ".join(tk[2:-1])})
            i += 1
    out["sections"]["embedded_report_methodology"] = {"header_line": rh or NM, "rows": mrows}

    # check_timing report（report_timing_summary 自己内嵌的那段；行首有一个空格 ⇒ 不用 ^ 锚点）
    ck = {}
    for pat, key in ((r"There are (\d+) pins that are not constrained for maximum delay\.",
                      "pins_not_constrained_for_max_delay"),
                     (r"There are (\d+) pins that are not constrained for maximum delay due to constant clock",
                      "pins_not_constrained_due_to_constant_clock"),
                     (r"There are (\d+) register/latch pins with no clock", "pins_with_no_clock"),
                     (r"There are (\d+) input ports with no input delay specified\. \(HIGH\)",
                      "input_ports_no_input_delay_HIGH"),
                     (r"There are (\d+) input ports with no input delay but user has a false path constraint",
                      "input_ports_no_input_delay_MEDIUM_false_path"),
                     (r"There are (\d+) ports with no output delay specified\. \(HIGH\)",
                      "ports_no_output_delay_HIGH"),
                     (r"There are (\d+) ports with no output delay but user has a false path constraint",
                      "ports_no_output_delay_MEDIUM_false_path"),
                     (r"There are (\d+) register/latch pins with multiple clocks", "pins_with_multiple_clocks"),
                     (r"There are (\d+) generated clocks that are not connected to a clock source",
                      "generated_clocks_not_connected"),
                     (r"There are (\d+) combinational loops in the design", "combinational_loops")):
        ln = None
        m = None
        for i, l in enumerate(lines):
            mm = re.search(pat, l)
            if mm:
                ln, m = i + 1, mm
                break
        v = m.group(1) if m else NM
        ck[key] = {"value": v, "line": ln or NM,
                   "locator": "grep -n '%s' %s" % (pat, rel),
                   "text": lines[ln - 1].strip() if ln else NM}
        rec(fp, "check_timing." + key, rel, ln, None, v, locator_for(rel, ln, None))
    # 目录那 12 行的计数（`5. checking no_input_delay (7)`）：与上面的明细分开存，不当同一个数
    toc = []
    for i, l in enumerate(lines):
        mm = re.match(r"^(\d+)\. checking (\w+) \((\d+)\)\s*$", l)
        if mm:
            toc.append({"line": i + 1, "index": mm.group(1), "check": mm.group(2), "count": mm.group(3)})
    ck["toc"] = toc
    out["sections"]["check_timing"] = ck
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def locator_for(rel, ln, col, pipe=False):
    """把「怎么量到的」写成可复制的命令（列号 1-based；pipe=True 时是 '|' 单元格号）。"""
    if ln is None:
        return "grep -n '<锚点文本>' %s（本轮没定位到 ⇒ NOT_MEASURED）" % rel
    if col is None:
        return "sed -n '%dp' %s" % (ln, rel)
    if pipe:
        return "sed -n '%dp' %s | awk -F('|') '{print $%d}'" % (ln, rel, col + 1)
    return "sed -n '%dp' %s | awk '{print $%d}'" % (ln, rel, col)


def parse_banner(rel, lines, fp):
    """`| Tool Version : ...` 那一段。没有 banner 的原件（route_status.rpt）逐项落 NOT_MEASURED。"""
    keys = ["Tool Version", "Date", "Host", "Command", "Design", "Device",
            "Speed File", "Design State", "Grade", "Process", "Characterization"]
    b = {}
    for k in keys:
        ln = find(lines, lambda l, k=k: l.strip().lstrip("|").strip().startswith(k + " "))
        v = NM
        if ln:
            m = re.match(r"^\|?\s*%s\s*:\s*(.*)$" % re.escape(k), lines[ln - 1])
            if m and m.group(1).strip():
                v = m.group(1).strip()
        b[k] = v
        rec(fp, "banner." + k, rel, ln, None, v, locator_for(rel, ln, None))
    return b


def iter_pipe_tables(rel, lines, only_sections=None):
    """通用 `+---+ / | a | b |` 表格提取：返回 {section: [{header, rows:[{line, cells}]}]}。"""
    secs = []
    for i, l in enumerate(lines):
        m = re.match(r"^(\d+(?:\.\d+)*)[. ]+(\S.*)$", l)
        if m and i + 1 < len(lines) and set(lines[i + 1].strip()) <= set("-") and len(lines[i + 1].strip()) >= 3:
            secs.append((m.group(1), m.group(2).strip(), i + 1))
    res = []
    for si, (num, title, ln) in enumerate(secs):
        if only_sections and title not in only_sections and num not in only_sections:
            continue
        end = secs[si + 1][2] - 1 if si + 1 < len(secs) else len(lines)
        i = ln
        while i < end:
            if lines[i].startswith("+--") or lines[i].startswith("+--"):
                j = i + 1
                maybe_hdr = lines[j].strip() if j < end else ""
                has_hdr = maybe_hdr.startswith("|") and j + 1 < end and lines[j + 1].startswith("+--")
                hdr = pipe_cells(lines, j + 1) if has_hdr else []
                start = j + 2 if has_hdr else i + 1
                rows = []
                k = start
                while k < end and lines[k].startswith("|"):
                    cells = pipe_cells(lines, k + 1)
                    if any(c != "" for c in cells):
                        rows.append({"line": k + 1, "cells": cells})
                    k += 1
                if rows or hdr:
                    res.append({"section": "%s %s" % (num, title), "section_line": ln,
                                "table_border_line": i + 1, "header": hdr,
                                "header_line": (j + 1) if has_hdr else NM, "rows": rows})
                i = k
            else:
                i += 1
    return res


def parse_utilization(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    out["parse_status"] = "OK"
    fp = out["field_positions"]
    out["sections"]["banner"] = parse_banner(rel, lines, fp)
    tables = iter_pipe_tables(rel, lines)
    out["sections"]["tables"] = tables
    # 铁律 6：资源按模块归属。原件里有没有 by-hierarchy 的表，直接决定这一格能不能填数。
    hier = [t for t in tables if "Hierarchy" in t["section"]]
    rec(fp, "utilization_by_hierarchy_present", rel, hier[0]["section_line"] if hier else None,
        None, "Utilization by Hierarchy" if hier else NM,
        "grep -n 'Utilization by Hierarchy' %s" % rel)
    first = None
    for t in tables:
        if t["header"] and t["header"][0] in ("Site Type", "Type") and t["rows"]:
            first = t
            break
    if first:
        for r in first["rows"][:3]:
            nm = r["cells"][0] if r["cells"] else NM
            rec(fp, "table[%s].%s.Used" % (first["section"], nm), rel, r["line"], 2,
                pcell(lines, r["line"], 2), locator_for(rel, r["line"], 2, pipe=True))
            rec(fp, "table[%s].%s.Util%%" % (first["section"], nm), rel, r["line"],
                len(first["header"]), pcell(lines, r["line"], len(first["header"])),
                locator_for(rel, r["line"], len(first["header"]), pipe=True))
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_methodology(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    out["parse_status"] = "OK"
    fp = out["field_positions"]
    out["sections"]["banner"] = parse_banner(rel, lines, fp)
    cf = find_re(lines, r"^\s*Checks found:\s*\d+")
    v = NM
    if cf:
        m = re.search(r"Checks found:\s*(\d+)", lines[cf - 1])
        v = m.group(1) if m else NM
    rec(fp, "checks_found", rel, cf, None, v, "grep -n 'Checks found:' %s" % rel)
    out["sections"]["checks_found"] = {"value": v, "line": cf or NM}
    tables = iter_pipe_tables(rel, lines, only_sections=["REPORT SUMMARY"])
    out["sections"]["summary_table"] = tables[0] if tables else {"header": [], "rows": [], "section": NM}
    t = tables[0] if tables else None
    if t:
        for r in t["rows"]:
            rec(fp, "rule[%s].Checks" % (r["cells"][0] if r["cells"] else NM), rel, r["line"],
                len(t["header"]), pcell(lines, r["line"], len(t["header"])),
                locator_for(rel, r["line"], len(t["header"]), pipe=True))
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_space_table(rel, header_pred, ncols):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    out["parse_status"] = "OK"
    fp = out["field_positions"]
    out["sections"]["banner"] = parse_banner(rel, lines, fp)
    h = find(lines, header_pred)
    hdr = tokens(lines, h) if h else []
    rows = []
    if h:
        i = h + 1
        while i < len(lines):
            ln = lines[i]
            if ln.strip() == "":
                break
            tk = ln.split()
            rows.append({"line": i + 1, "cells": {("col%d" % (j + 1)): t for j, t in enumerate(tk)}})
            i += 1
    out["sections"]["table"] = {"header_line": h or NM, "header_cells": hdr, "rows": rows,
                               "row_count": len(rows)}
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_cdc(rel):
    o = parse_space_table(rel, lambda l: l.startswith("Severity  Source Clock"), 11)
    fp = o["field_positions"]
    for r in o["sections"]["table"]["rows"]:
        c = r["cells"]
        key = "%s>%s" % (c.get("col2", NM), c.get("col3", NM))
        rec(fp, "cdc[%s].Endpoints" % key, rel, r["line"], 6, c.get("col6", NM),
            "awk 'NR==%d{print $6}' %s" % (r["line"], rel))
        rec(fp, "cdc[%s].Unsafe" % key, rel, r["line"], 8, c.get("col8", NM),
            "awk 'NR==%d{print $8}' %s" % (r["line"], rel))
    o["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return o


def parse_power(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    out["parse_status"] = "OK"
    fp = out["field_positions"]
    out["sections"]["banner"] = parse_banner(rel, lines, fp)
    tables = iter_pipe_tables(rel, lines,
                              only_sections=["Summary", "On-Chip Components", "Power Supply Summary",
                                             "Confidence Level", "Clock Constraints"])
    out["sections"]["tables"] = tables
    for t in tables:
        if t["header"]:
            for r in t["rows"][:3]:
                if len(r["cells"]) < 2:
                    continue
                rec(fp, "table[%s].%s.%s" % (t["section"], r["cells"][0], t["header"][1]),
                    rel, r["line"], 2, pcell(lines, r["line"], 2),
                    locator_for(rel, r["line"], 2, pipe=True))
        else:                                    # 1. Summary 那张表原件里**没有表头行**
            for r in t["rows"]:
                if len(r["cells"]) >= 2:
                    rec(fp, "summary[%s]" % r["cells"][0], rel, r["line"], 2,
                        pcell(lines, r["line"], 2), locator_for(rel, r["line"], 2, pipe=True))
        # 2.2 Clock Constraints：`| Clock | Domain | Constraint (ns) |` —— Domain 就是这条钟的**源网络**，
        # 是「改名/重新源化」最直接的证据，逐时钟取下来（coverage.md 用它对名字）。
        if "Clock" in t["header"] and "Domain" in t["header"]:
            cidx = t["header"].index("Clock") + 1
            didx = t["header"].index("Domain") + 1
            kidx = t["header"].index("Constraint (ns)") + 1 if "Constraint (ns)" in t["header"] else None
            for r in t["rows"]:
                if len(r["cells"]) < max(cidx, didx):
                    continue
                clk = r["cells"][cidx - 1]
                rec(fp, "power_clock_constraints[%s].Domain" % clk, rel, r["line"], didx,
                    pcell(lines, r["line"], didx), locator_for(rel, r["line"], didx, pipe=True))
                if kidx:
                    rec(fp, "power_clock_constraints[%s].Constraint (ns)" % clk, rel, r["line"], kidx,
                        pcell(lines, r["line"], kidx), locator_for(rel, r["line"], kidx, pipe=True))
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_route_status(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    fp = out["field_positions"]
    out["parse_status"] = "OK"
    out["sections"]["banner"] = parse_banner(rel, lines, fp)   # 这份原件**没有** banner ⇒ 整段 NM
    rows = []
    for i, l in enumerate(lines):
        m = re.match(r"^\s*(# of [^.]+?)\.*\s*:\s*(\S+)\s*:?\s*$", l)
        if m:
            rows.append({"line": i + 1, "item": m.group(1).strip(), "value": m.group(2)})
            rec(fp, "route_status[%s]" % m.group(1).strip(), rel, i + 1, None, m.group(2),
                "sed -n '%dp' %s" % (i + 1, rel))
    out["sections"]["items"] = rows
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_clock_util(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        return out
    out["parse_status"] = "OK"
    fp = out["field_positions"]
    out["sections"]["banner"] = parse_banner(rel, lines, fp)
    tables = iter_pipe_tables(rel, lines, only_sections=["Clock Primitive Utilization",
                                                         "Global Clock Resources",
                                                         "Global Clock Source Details"])
    out["sections"]["tables"] = tables
    for t in tables:
        if "Global Clock Resources" not in t["section"]:
            continue
        hdr = t["header"]
        if "Clock" not in hdr:
            continue
        cidx = hdr.index("Clock") + 1
        pidx = hdr.index("Clock Period") + 1 if "Clock Period" in hdr else None
        sidx = hdr.index("Driver Pin") + 1 if "Driver Pin" in hdr else None
        nidx = hdr.index("Net") + 1 if "Net" in hdr else None
        hidx = hdr.index("Clock Loads") + 1 if "Clock Loads" in hdr else None
        for r in t["rows"]:
            if len(r["cells"]) < cidx:
                continue
            clk = r["cells"][cidx - 1]
            for lbl, idx in (("Clock Period", pidx), ("Net", nidx), ("Driver Pin", sidx),
                             ("Global Id", 1), ("Clock Loads", hidx)):
                if idx is None:
                    continue
                rec(fp, "clock_resources[%s].%s" % (clk, lbl), rel, r["line"], idx,
                    pcell(lines, r["line"], idx), locator_for(rel, r["line"], idx, pipe=True))
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


def parse_counter_txt(rel):
    out = {"sections": {}, "field_positions": [], "not_measured": []}
    lines, err = read_lines(rel)
    if err:
        out["parse_status"], out["reason"] = NM, err
        out["field_positions"] = [{"field": "counter_value", "file": rel, "line": NM, "col": NM,
                                   "value": NM, "locator": "cat %s" % rel}]
        return out
    fp = out["field_positions"]
    out["parse_status"] = "OK"
    body = [l for l in lines if l.strip() != ""]
    v = body[0].strip() if body else NM
    rec(fp, "counter_value", rel, 1 if body else None, 1, v, "sed -n '1p' %s" % rel)
    p = rel if os.path.isabs(rel) else os.path.join(REPO, rel)
    out["sections"]["value"] = {"value": v, "line": 1 if body else NM}
    out["sections"]["bytes"] = os.path.getsize(p)
    out["sections"]["non_empty_lines"] = len(body)
    out["sections"]["note"] = ("计数件：只有一个数字，不是报告。数字 0 = 「该检查真的数到 0 条」，"
                              "与读不到（NOT_MEASURED）是两回事。")
    out["not_measured"] = [f["field"] for f in fp if f["value"] == NM]
    return out


PARSERS = {
    "build/reports/build_timing_summary.rpt": parse_timing_summary,
    "build/reports/build_utilization.rpt": parse_utilization,
    "build/reports/methodology.rpt": parse_methodology,
    "build/reports/cdc.rpt": parse_cdc,
    "build/reports/power.rpt": parse_power,
    "build/reports/build_route_status.rpt": parse_route_status,
    "build/reports/clock_util.rpt": parse_clock_util,
}


def parse_one(rel):
    """按 **basename** 派发，这样临时副本/绝对路径也能走同一个解析器（判据 3 的反例要走这条路）。"""
    fn = os.path.basename(rel)
    key = rel if rel in PARSERS else next((k for k in PARSERS if os.path.basename(k) == fn), None)
    if key:
        res = PARSERS[key](rel)
    elif fn.endswith(".txt"):
        res = parse_counter_txt(rel)
    else:
        res = {"parse_status": NM, "reason": "no parser registered", "sections": {},
               "field_positions": [], "not_measured": ["*"]}
    if res.get("parse_status") == NM and not res.get("field_positions"):
        # 原件读不到时**也要留一行**，否则读者看见空表会以为「这张表本来就没数」
        res["field_positions"] = [{"field": "file_present", "file": rel, "line": NM, "col": NM,
                                   "value": NM, "locator": "test -f %s && echo present" % rel}]
        res["not_measured"] = ["file_present"]
    return res


# --------------------------------------------------------------------------
# provenance 配对（铁律 5 / 判据 5）：md5 必须当场重算并等于卡上的值
# --------------------------------------------------------------------------
def provenance_rows(md_rel):
    """从 build/provenance.md 第 5 节的产物表里抓 `| 路径 | md5(12) | sha256(16) | ...`。"""
    lines, err = read_lines(md_rel)
    rows = {}
    if err:
        return rows, err
    for i, l in enumerate(lines):
        if not l.strip().startswith("| `build/") and "| `build/" not in l:
            continue
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        path = cells[0].strip("`")
        rows[path] = {"md5_12": cells[1].strip("`"), "sha256_16": cells[2].strip("`"),
                      "line": i + 1, "identity": cells[-1]}
    return rows, None


def digest_pair(rel):
    p = rel if os.path.isabs(rel) else os.path.join(REPO, rel)
    if not os.path.isfile(p):
        return NM, NM
    b = open(p, "rb").read()
    return hashlib.md5(b).hexdigest()[:12], hashlib.sha256(b).hexdigest()[:16]


# --------------------------------------------------------------------------
# 名册：两把既有尺子的口径，不另起一套
#   A) build/r115_roster_build.py 的 13+1 列（docs/timing/roster_*.tsv 用的就是它）
#   B) 探针名册 ROSTER| 字段（board/output/r118_after_roster_probefmt.txt 用的就是它）
# --------------------------------------------------------------------------
def build_intra_roster(ts_rel, ck_rel, tmp_out, label):
    """直接 subprocess 调既有尺子；失败就返回 (None, 原因)，绝不自己编一张表。"""
    cmd = [sys.executable or "python", os.path.join("build", "r115_roster_build.py"),
           ts_rel, ck_rel, tmp_out, label]
    try:
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=180)
    except Exception as e:                                        # noqa: BLE001
        return None, "subprocess_error:%s" % e.__class__.__name__
    if r.returncode != 0:
        return None, "generator rc=%s %s" % (r.returncode, (r.stdout + r.stderr).strip()[:200])
    body, err = read_lines(tmp_out if os.path.isabs(tmp_out) else tmp_out)
    if err:
        return None, "generator wrote no file"
    return body, None


PROBE_COLS = ["clk", "type", "period", "slack", "margin_pct", "levels", "route_pct", "dest"]


def parse_probe_roster(rel):
    lines, err = read_lines(rel)
    if err:
        return None, err
    rows = []
    for i, l in enumerate(lines):
        if not l.startswith("ROSTER|"):
            continue
        parts = l.split("|")
        rec = {"line": i + 1, "type": parts[1], "fields": {}}
        for kv in parts[2:]:
            if "=" in kv:
                k, v = kv.split("=", 1)
                rec["fields"][k] = v.strip()
        m = re.match(r"^\s*(-?[0-9][0-9.]*)", rec["fields"].get("slack", ""))
        rec["fields"]["slack_ns"] = m.group(1) if m else NM      # 取前导数，同 timing_roster_diff.sh
        rows.append(rec)
    fano = [i + 1 for i, l in enumerate(lines) if l.startswith("FANOUT|")]
    return {"rows": rows, "fanout_lines": fano}, None


def emit(parsed_dir, roster_dir, prov_rel=PROVENANCE_MD, reports=None, probe_rel=R118_PROBE_ROSTER):
    reports = reports or REPORTS
    os.makedirs(parsed_dir, exist_ok=True)
    os.makedirs(roster_dir, exist_ok=True)
    prov, perr = provenance_rows(prov_rel)
    written = []
    for rel in reports:
        res = parse_one(rel)
        base = os.path.basename(rel)
        name = "parsed_%s.json" % re.sub(r"[^A-Za-z0-9_.-]", "_", base)
        md5, sha = digest_pair(rel)
        prow = prov.get(rel, {})
        res["pairing"] = {
            "provenance_file": prov_rel,
            "provenance_line": prow.get("line", NM),
            "provenance_md5_12": prow.get("md5_12", NM),
            "provenance_sha256_16": prow.get("sha256_16", NM),
            "recomputed_md5_12": md5,
            "recomputed_sha256_16": sha,
            "identity_from_provenance": prow.get("identity", NM),
            "pairing_result": "PASS" if prow.get("md5_12") == md5 and md5 != NM else
                              ("NOT_MEASURED" if md5 == NM else "FAIL"),
        }
        res["original"] = rel
        res["round"] = ROUND if prow.get("md5_12") == md5 else NM
        res["provenance_present"] = perr is None
        s = json.dumps(res, sort_keys=True, ensure_ascii=False, indent=1)
        outp = os.path.join(parsed_dir, name)
        with io.open(outp, "w", encoding="utf-8", newline="\n") as f:
            f.write(s + "\n")
        written.append(outp)

    # ---- 名册 A：既有 13+1 列口径 ------------------------------------------------
    ts_rel = "build/reports/build_timing_summary.rpt" if ts_in(reports) else NM
    ck_rel = ts_rel                       # r118 的 check_timing 段就在同一份原件里（第 58-140 行）
    roster_a_lines, a_err = (None, None)
    tmp = os.path.join(tempfile.gettempdir(), "p15b_roster_a.tsv")
    if os.path.isfile(os.path.join(REPO, ts_rel)) if ts_rel != NM else False:
        roster_a_lines, a_err = build_intra_roster(ts_rel, ck_rel, tmp, ROUND)
    out_a = os.path.join(roster_dir, "roster_%s.tsv" % ROUND)
    hdr_notes = []
    if roster_a_lines:
        keep = []
        for l in roster_a_lines:
            if l.startswith("# label="):
                # 既有尺子写的是墙钟时间；换成**原件自己的 Date:** ⇒ 判据 6 才谈得上逐字节一致。
                # 列名/列序/单位一字未动。
                keep.append("# label=%s built_from_original_Date=%s src_reports=%s,%s "
                            "generator=build/r115_roster_build.py" % (ROUND, report_date(ts_rel), ts_rel, ck_rel))
            elif l.startswith("#"):
                keep.append(l)
            else:
                keep.append(l)
        body = keep
        nclock = len([l for l in body if not l.startswith("#") and l.strip()]) - 1
        # 先落一次盘再算缺口：缺口那条注释本身要写进这份 TSV，不先写就只能拿上一轮的数（那是假数）
        with io.open(out_a, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(body) + "\n")
        gaps = clock_gap_count(roster_dir, parsed_dir)
        hdr_notes = [
            "# 覆盖域数=%d（roster 的行数 = 原件 Clock Summary 的时钟行数）；判据分母：wns_setup 的分母 = "
            "TNS Total Endpoints（=intra_endpoint_total 列），wns_hold 的分母 = THS Total Endpoints（同列同值），"
            "失败端点数 = nfp_setup / nfp_hold；setup 与 hold 各占同行两列，不合并、不只报全局 WNS" % nclock,
            "# NA = 该域在 Intra Clock Table 里只有名字没有 intra 路径（原件那几行的形状见 "
            "parsed/parsed_timing_summary.rpt.json 的 intra_clock_table.rows[].line），**不是**解析失败；"
            "解析失败在本口径里写 NOT_MEASURED",
            "# 口径冲突（两把尺子并存，见 report/build-notes.md）：本表 rel_margin_* 是**比值**（0.185000 = wns/period），"
            "探针名册 margin_pct 是**百分数**（18.50）；判据 G1/G2 用本表 ⇒ 裁决以本表为准",
            "# 名册缺口 gaps=%s（约束里声明的时钟名 vs 进表域数；算法见 build/p15b_parse_reports.py::clock_gap_count）" % gaps,
        ]
        if a_err:
            hdr_notes.append("# 生成器返回：%s ⇒ 本表 NOT_MEASURED" % a_err)
        with io.open(out_a, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(hdr_notes + body) + "\n")
        written.append(out_a)
    else:
        with io.open(out_a, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(
                ["# label=%s result=NOT_MEASURED reason=%s" % (ROUND, a_err or "no input"),
                 "\t".join(["clock", "period_ns", "src", "wns_setup", "tns_setup", "nfp_setup",
                            "wns_hold", "tns_hold", "nfp_hold", "rel_margin_setup",
                            "rel_margin_hold", "unconstrained_endpoints",
                            "io_unconstrained_ports", "intra_endpoint_total"]),
                 "\t".join([NM] * 14)]) + "\n")
        written.append(out_a)

    # ---- 名册 B：探针口径 -------------------------------------------------------
    out_b = os.path.join(roster_dir, "roster_%s_probe.tsv" % ROUND)
    pr, perr2 = parse_probe_roster(probe_rel) if probe_rel else (None, "no probe file")
    if pr:
        cols = ["clock", "type", "period_ns", "slack_ns", "slack_raw", "margin_pct",
                "levels", "route_pct", "dest", "source_line"]
        lines = ["# 口径 = build/evidence/*_after_roster_probefmt.txt 的 ROSTER| 字段（探针那把尺子，"
                 "差分由 build/timing_roster_diff.sh 判 D1..D6）",
                 "# 原件=%s ；FANOUT| 行数=%d（该节存在与否是差分闸门的口径检查之一）"
                 % (probe_rel, len(pr["fanout_lines"])),
                 "# margin_pct 是**百分数**，与 roster_%s.tsv 的 rel_margin_*（比值）同量不同单位；"
                 "本表不用于 G1/G2 裁决" % ROUND,
                 "# slack_raw 保留原件的散文尾巴（`0.739ns  (required time - arrival time)`），"
                 "slack_ns 取前导数（与 timing_roster_diff.sh::field 同法）；NOWRITE = 该域没有可读路径，不是 0",
                 "\t".join(cols)]
        for r in pr["rows"]:
            f = r["fields"]
            lines.append("\t".join([f.get("clk", NM), r["type"], f.get("period", NM),
                                    f.get("slack_ns", NM), f.get("slack", NM),
                                    f.get("margin_pct", NM), f.get("levels", NM),
                                    f.get("route_pct", NM), f.get("dest", NM), str(r["line"])]))
        with io.open(out_b, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        written.append(out_b)
    else:
        with io.open(out_b, "w", encoding="utf-8", newline="\n") as f:
            f.write("# result=NOT_MEASURED reason=%s\n%s\n%s\n"
                    % (perr2, "\t".join(PROBE_COLS), "\t".join([NM] * len(PROBE_COLS))))
        written.append(out_b)
    return written


def ts_in(reports):
    return "build/reports/build_timing_summary.rpt" in reports


NONDET = False          # --self 的 J6 反例开关：True = 把名册表头换回**墙钟**（既有尺子的原始行为）


def report_date(rel):
    lines, err = read_lines(rel)
    if err:
        return NM
    if NONDET:
        # 反例用：既有尺子往表头写的是**墙钟**（`built=time.strftime("%Y-%m-%d %H:%M:%S")`），
        # 同一秒内两次跑还会骗过判据 6 ⇒ 这里加 ns 级时间，模拟“表头掺进任何逐次变化的东西”
        return "%s.%d" % (time.strftime("%Y-%m-%d %H:%M:%S"), time.time_ns())
    ln = find(lines, lambda l: l.strip().lstrip("|").strip().startswith("Date "))
    if not ln:
        return NM
    m = re.search(r"Date\s*:\s*(.*)$", lines[ln - 1])
    return m.group(1).strip() if m else NM


def clock_gap_count(roster_dir, parsed_dir=None):
    """三个集合对账：本轮**加载的**约束里声明的时钟名 / 报告里出现的时钟名 / 进名册的域。
    缺口 = 前两者里有、名册里没有的。候选件（本轮没加载）单独数，不混进缺口。"""
    g = constraint_inventory(parsed_dir or os.path.join(REPO, "build", "parsed"))
    rostered = set(roster_clock_names(roster_dir))
    reported = set(g["reported"])
    loaded = set(g["loaded_declared"])
    miss = sorted((loaded | reported) - rostered)
    cand_only = sorted(set(g["candidate_declared"]) - (loaded | reported))
    return ("loaded_xdc=%d loaded_declared_clocks=%d reported_clocks=%d rostered=%d "
            "gap=%d [%s] | 候选件独占名=%d [%s] | 报告里有这个名字但**本轮加载的约束**没提过=%d [%s]" % (
                len(g["loaded_files"]), len(loaded), len(reported), len(rostered), len(miss),
                ",".join(miss) if miss else "none",
                len(cand_only), ",".join(cand_only) if cand_only else "none",
                len(g["reported_unnamed"]), ",".join(g["reported_unnamed"]) if g["reported_unnamed"] else "none"))


XDC_CLOCK_RX = re.compile(r"^\s*(create_clock|create_generated_clock)\b")
BUILD_TCL = "build/tcl/build_system_axigpio.tcl"


def loaded_xdc():
    """从**构建入口脚本**里读本轮到底挂了哪几份 XDC（不看目录列表猜），并记录是否被 env 开关包住。"""
    lines, err = read_lines(BUILD_TCL)
    out = []
    if err:
        return out
    for i, l in enumerate(lines):
        m = re.search(r"add_files -fileset constrs_1 -norecurse \[file join \$root src constraints (\S+\.xdc)\]", l)
        if not m:
            continue
        gate = None
        for j in range(i - 1, max(0, i - 14), -1):
            gm = re.search(r"info exists ::env\((VP_\w+)\)", lines[j])
            if gm:
                gate = gm.group(1)
                break
            if re.match(r"^\s*(create_project|set_property target_language)", lines[j]):
                break
        out.append({"xdc": "src/constraints/" + m.group(1), "tcl_line": i + 1, "env_gate": gate or "none"})
    return out


def xdc_clock_names(rels):
    """逐条 grep 指定 XDC，取约束里**写出来的**时钟名，并区分「创建」与「只是被引用」：
    `create_clock -name X` = 创建；`get_clocks X` / `-clock X` = 引用（引用不创造时钟，
    名字对不上就整条命令空转 —— 这就是覆盖面静默丢失的形状，见 coverage.md）。"""
    hits = []
    for rel in rels:
        lines, err = read_lines(rel)
        if err:
            continue
        for i, l in enumerate(lines):
            s = l.strip()
            if not s or s.startswith("#"):
                continue
            if XDC_CLOCK_RX.match(s):
                for m in re.finditer(r"-name\s+(\S+)", s):
                    hits.append({"clock": m.group(1), "kind": "created", "file": rel,
                                 "line": i + 1, "text": s, "cmd": s.split()[0]})
                continue
            for pat, kind, cmdname in ((r"get_clocks\s+(?:-\S+\s+)*(\w+)", "referenced", "get_clocks"),
                                       (r"-clock\s+(\S+)", "referenced", "-clock")):
                for m in re.finditer(pat, s):
                    hits.append({"clock": m.group(1), "kind": kind, "file": rel,
                                 "line": i + 1, "text": s, "cmd": cmdname})
    seen, uniq = set(), []
    for h in hits:
        k = (h["clock"], h["kind"], h["file"], h["line"], h["cmd"])
        if k in seen:
            continue
        seen.add(k)
        uniq.append(h)
    return uniq


def all_xdc_files():
    d = os.path.join(REPO, "src", "constraints")
    return ["src/constraints/" + fn for fn in sorted(os.listdir(d)) if fn.endswith(".xdc")] \
        if os.path.isdir(d) else []


def constraint_inventory(parsed_dir=None):
    """coverage.md 的数：加载件 vs 候选件 vs 报告里的时钟名。"""
    ld = loaded_xdc()
    loaded_files = [x["xdc"] for x in ld if x["env_gate"] == "none"]
    gated_files = [x["xdc"] for x in ld if x["env_gate"] != "none"]
    cand_files = [f for f in all_xdc_files() if f not in [x["xdc"] for x in ld]]
    lh = xdc_clock_names(loaded_files)
    ch = xdc_clock_names(gated_files + cand_files)
    reported = report_clock_names_from_parsed(parsed_dir or os.path.join(REPO, "build", "parsed"))
    created = sorted(set(h["clock"] for h in lh if h["kind"] == "created"))
    return {"loaded_files": loaded_files, "gated_files": gated_files, "candidate_files": cand_files,
            "loaded_created": created,
            "loaded_declared": sorted(set(h["clock"] for h in lh)),
            "candidate_declared": sorted(set(h["clock"] for h in ch)),
            "loaded_hits": lh, "candidate_hits": ch,
            "reported": reported,
            "reported_unnamed": sorted(set(reported) - set(h["clock"] for h in lh))}


def report_clock_names_from_parsed(parsed_dir=None):
    """报告里出现的时钟名 = timing_summary 原件 Clock Summary 那些行（从已生成的 parsed JSON 取）。"""
    p = os.path.join(parsed_dir or os.path.join(REPO, "build", "parsed"), "parsed_timing_summary.rpt.json")
    if not os.path.isfile(p):
        return []
    d = json.loads(io.open(p, encoding="utf-8").read())
    rows = d.get("sections", {}).get("clock_summary", {}).get("rows", [])
    return [r["cells"].get("col1") for r in rows if r["cells"].get("col1")]


def report_clock_names(roster_dir=None):
    """名册 A 的域 = roster_<round>.tsv 的行（第一列 clock）。"""
    p = os.path.join(roster_dir or os.path.join(REPO, "build", "roster"), "roster_%s.tsv" % ROUND)
    return [l.split("\t")[0] for l in _roster_body(p)]


def roster_clock_names(roster_dir=None):
    return report_clock_names(roster_dir)


def _roster_body(p):
    if not os.path.isfile(p):
        return []
    out = []
    lines = io.open(p, encoding="utf-8", errors="replace").read().replace("\r\n", "\n").split("\n")
    body = [l for l in lines if l and not l.startswith("#")]
    for l in body[1:]:
        out.append(l)
    return out


# --------------------------------------------------------------------------
# 判据 1..6：一条一行，判定放最后一个字段，打印分母
# --------------------------------------------------------------------------
def check(parsed_dir, roster_dir, prov_rel=PROVENANCE_MD, reports=None):
    reports = reports or REPORTS
    res = []
    denom = {}

    def say(j, name, detail, verdict, d):
        denom[j] = d
        res.append((j, name, detail, verdict))

    # J1 抽查 parsed/ 的数字能否在原件定位（逐字段回原件重取，不是只看行号存不存在）
    n_ok = n_bad = n_nm = 0
    samples = []
    total_fields = 0
    for rel in reports:
        p = os.path.join(parsed_dir, "parsed_%s.json" % re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(rel)))
        if not os.path.isfile(p):
            continue
        d = json.loads(io.open(p, encoding="utf-8").read())
        for f in d.get("field_positions", []):
            total_fields += 1
            if f["value"] == NM:
                n_nm += 1
                continue
            lines, err = read_lines(f["file"])
            if err or not f["line"] or f["line"] == NM or f["line"] > len(lines):
                n_bad += 1
                continue
            loc = f.get("locator", "")
            mode = "pipe" if "-F('|')" in loc or '-F"|"' in loc else ("col" if "NR==" in loc else "line")
            ln = lines[f["line"] - 1]
            if mode == "col":
                t = ln.split()
                c = int(f["col"]) if f["col"] != NM else 0
                hit = t[c - 1] if 0 < c <= len(t) else NM
                ok = (hit == f["value"])
            elif mode == "pipe":
                t = pipe_cells(lines, f["line"])
                c = int(f["col"]) if f["col"] != NM else 0
                hit = t[c - 1] if 0 < c <= len(t) else NM
                ok = (hit == f["value"])
            else:
                hit = ln.strip()
                ok = f["value"] in hit
            if ok:
                n_ok += 1
                if len(samples) < 12:
                    samples.append("%s=%s@%s:%s:%s" % (f["field"], f["value"], f["file"], f["line"], f["col"]))
            else:
                n_bad += 1
    v1 = "FAIL" if n_bad else ("NOT_MEASURED" if n_ok == 0 else "PASS")
    say("J1", "parsed 数字逐字段回原件定位(>=10)",
        "verified=%d mismatch=%d not_measured=%d total_fields=%d 抽样:%s" % (n_ok, n_bad, n_nm, total_fields,
                                                                             " | ".join(samples[:3]) or NM),
        v1, "分母=登记了位置的字段数 %d（NOT_MEASURED %d 个不参与命中）" % (total_fields, n_nm))
    if samples:
        print("J1-SAMPLE %s" % " ;; ".join(samples))

    # J2 名册覆盖全部时钟：域数 == 报告里的时钟数，缺口 = 0（全局 WNS 单独念，不当结论）
    gtxt = clock_gap_count(roster_dir, parsed_dir)
    inv = constraint_inventory(parsed_dir)
    rostered = set(roster_clock_names(roster_dir))
    reported = set(inv["reported"])
    loaded = set(inv["loaded_declared"])
    gap = sorted((loaded | reported) - rostered)
    v2 = "PASS" if (rostered and not gap) else ("NOT_MEASURED" if not rostered else "FAIL")
    say("J2", "名册逐域覆盖（不只全局 WNS）",
        "%s gap=%d" % (gtxt, len(gap)), v2,
        "分母=报告 Clock Summary 的时钟数 %d（名册行数 %d）" % (len(reported), len(rostered)))

    # J3 三态可触发：读不到位置的字段必须写 NOT_MEASURED（不是 0、不是空串、不是 PASS）。
    #     本轮的**真实**触发点：route_status.rpt 整份没有 banner、utilization.rpt 没有 by-hierarchy
    #     表、Intra Clock Table 里 4 个域只有名字没有 intra 路径。把原件真的移走那一条见 --self。
    bad3 = []
    nm_fields = 0
    nm_files = 0
    scan = []
    for rel in reports:
        p = os.path.join(parsed_dir, "parsed_%s.json" % re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(rel)))
        if not os.path.isfile(p):
            bad3.append("no_parsed_file:%s" % rel)
        else:
            scan.append(p)
    for f in sorted(os.listdir(parsed_dir)) if os.path.isdir(parsed_dir) else []:
        if f.endswith(".json") and os.path.join(parsed_dir, f) not in scan:
            scan.append(os.path.join(parsed_dir, f))
    for f in scan:
        d = json.loads(io.open(f, encoding="utf-8").read())
        for ff in d.get("field_positions", []):
            if ff["value"] == NM:
                nm_fields += 1
                # NOT_MEASURED 必须是**真的取不到**：按记录的位置回原件再取一次，取到值就不许写 NOT_MEASURED
                if ff["line"] != NM and ff["col"] != NM and ff["line"]:
                    lines, err = read_lines(ff["file"])
                    again = NM
                    if not err and ff["line"] <= len(lines):
                        if "-F('|')" in ff.get("locator", ""):
                            again = pcell(lines, ff["line"], int(ff["col"]))
                        else:
                            again = cell(lines, ff["line"], int(ff["col"]))
                    if again != NM and again != "":
                        bad3.append("%s 写成 NOT_MEASURED，但 %s:%s 列 %s 实际有值 %r"
                                    % (ff["field"], ff["file"], ff["line"], ff["col"], again))
            elif ff["value"] == "" or (ff["line"] == NM and ff["value"] == "0"):
                bad3.append("%s 没定位到却填了 %r" % (ff["field"], ff["value"]))
        if d.get("parse_status") == NM:
            nm_files += 1
            for ff in d.get("field_positions", []):
                if ff["value"] in ("0", ""):
                    bad3.append("%s 原件缺失却填了 %r" % (d.get("original"), ff["value"]))
        pr = d.get("pairing", {})
        if pr.get("recomputed_md5_12") == NM and pr.get("pairing_result") not in (NM, "NOT_MEASURED"):
            bad3.append("%s 原件缺失却判 %s" % (d.get("original"), pr.get("pairing_result")))
    v3 = "FAIL" if bad3 else ("PASS" if nm_fields else NM)
    say("J3", "读不到→NOT_MEASURED（不是 0/空串/PASS）",
        "本轮真实触发 %d 个字段（route_status 无 banner、utilization 无 by-hierarchy、"
        "intra 表 4 个域只有名字）；反向核对也做了：每个 NOT_MEASURED 都按记录的位置回原件重取一次，"
        "取到值就算违规；违规 %d 条；原件整体缺失那一支由 --self 移走副本演示"
        % (nm_fields, len(bad3)), v3,
        "分母=NOT_MEASURED 字段 %d + 缺件原件 %d，违规 %d" % (nm_fields, nm_files, len(bad3)))

    # J4 每条判据有反例且只染红该条：只能由 --self 实跑给出
    say("J4", "每条判据自带反例且只染红该条", "本模式不跑反例；跑 `--self` 看 6 段 SELF 行", NM,
        "分母=判据数 6")

    # J5 parsed ↔ provenance 一一对应（指纹当场重算）
    prov, perr = provenance_rows(prov_rel)
    orphan = []
    unmatched = []
    matched = 0
    for fn in sorted(os.listdir(parsed_dir)) if os.path.isdir(parsed_dir) else []:
        if not fn.endswith(".json"):
            continue
        d = json.loads(io.open(os.path.join(parsed_dir, fn), encoding="utf-8").read())
        rel = d.get("original", "")
        pr = d.get("pairing", {})
        if rel not in prov:
            orphan.append("%s→%s" % (fn, rel))
        elif pr.get("provenance_md5_12") != NM and pr.get("provenance_md5_12") == pr.get("recomputed_md5_12"):
            matched += 1
        else:
            unmatched.append("%s(prov %s vs 实算 %s)" % (fn, pr.get("provenance_md5_12"),
                                                          pr.get("recomputed_md5_12")))
    missing_parsed = [rel for rel in reports
                      if not os.path.isfile(os.path.join(parsed_dir, "parsed_%s.json" %
                                                          re.sub(r"[^A-Za-z0-9_.-]", "_", os.path.basename(rel))))]
    v5 = "FAIL" if (orphan or unmatched or missing_parsed) else ("NOT_MEASURED" if perr else "PASS")
    say("J5", "parsed/ 与 provenance.md 一一对应",
        "指纹相符=%d 找不到对应原件的解析件=%d 指纹不符=%d 缺解析件的原件=%d；provenance=%s" %
        (matched, len(orphan), len(unmatched), len(missing_parsed), "可读" if not perr else perr),
        v5, "分母=provenance 第 5 节点名的报告数 %d" % len(reports))

    # J6 确定性：同样的输入**再跑两遍**到临时目录，两份输出逐字节比
    t1 = tempfile.mkdtemp(prefix="p15b_det1_")
    t2 = tempfile.mkdtemp(prefix="p15b_det2_")
    emit(t1, t1)
    emit(t2, t2)
    diffs = []
    compared = 0
    names = [f for f in sorted(os.listdir(t1)) if os.path.isfile(os.path.join(t1, f))]
    for fn in names:
        a1 = io.open(os.path.join(t1, fn), "rb").read()
        p2 = os.path.join(t2, fn)
        compared += 1
        if not os.path.isfile(p2):
            diffs.append(fn + ":missing_in_run2")
        elif a1 != io.open(p2, "rb").read():
            diffs.append(fn)
    v6 = "PASS" if (compared and not diffs) else ("NOT_MEASURED" if not compared else "FAIL")
    say("J6", "同一输入跑两次逐字节一致",
        "比对文件=%d 两次不一致=%d %s" % (compared, len(diffs), diffs[:4] or "[]"),
        v6, "分母=两次运行都产出的文件数 %d" % compared)

    # 附加不变式（**不是**六条判据之一，红不算连带红）：盘上那份 = 当前输入跑出来的那份（防手改）
    disk_bad = []
    disk_ok = 0
    for fn in names:
        a1 = io.open(os.path.join(t1, fn), "rb").read()
        for dd in (parsed_dir, roster_dir):
            p = os.path.join(dd, fn)
            if os.path.isfile(p):
                if io.open(p, "rb").read() == a1:
                    disk_ok += 1
                else:
                    disk_bad.append(fn)
                break
    print("NOTE-DISKPAIR 盘上件与重跑逐字节一致=%d 不一致=%d %s（这条是“没被手改过”的证据，不计入六条判据）"
          % (disk_ok, len(disk_bad), disk_bad or "[]"))
    return res, denom


def print_checks(res, denom, header):
    print(header)
    for j, name, detail, verdict in res:
        print("GATE %s %-46s %-86s %s %s" % (j, name, detail, "判定", verdict))
    print("GATE-SUMMARY judged=%d PASS=%d FAIL=%d NOT_MEASURED=%d 分母:%s" % (
        len(res), sum(1 for r in res if r[3] == "PASS"), sum(1 for r in res if r[3] == "FAIL"),
        sum(1 for r in res if r[3] == NM), "; ".join("%s=%s" % (k, v) for k, v in sorted(denom.items()))))


def read_tsv_rows(path):
    """读名册 TSV（跳过 `#` 口径行），返回 (表头, [dict])。"""
    lines, err = read_lines(path)
    if err:
        return None, []
    hdr, rows = None, []
    for l in lines:
        if not l.strip() or l.startswith("#"):
            continue
        c = l.split("\t")
        if c[0] == "clock":
            hdr = c
            continue
        if hdr:
            rows.append(dict(zip(hdr, c)))
    return hdr, rows


def classify_clock_source(domain, driver, net, created_in_xdc):
    """**从报告自己**判这一路钟的来历（不用 r115_roster_build.py 里那张写死的名字表）。
    created_in_xdc = 本轮加载的约束里 `create_clock -name` 真正创建过的名字集合。"""
    s = " ".join([x for x in (domain, driver, net) if x])
    if domain and domain in created_in_xdc:
        return "create_clock(XDC)"
    if "processing_system7" in s:
        return "PS7_FCLKCLK0(BD)"
    if re.search(r"clkout\d|clkfbout|MMCM|u_clk/|u_idelay_clkgen/", s):
        return "MMCM_generated"
    return NM


def ruler_crosscheck(parsed_dir, roster_dir):
    """与既有两把尺子对表：单位口径 + `src` 列的名字表。冲突只打印，不自作主张改任何一把。"""
    hdr, A = read_tsv_rows(os.path.join(roster_dir, "roster_%s.tsv" % ROUND))
    _, B = read_tsv_rows(os.path.join(roster_dir, "roster_%s_probe.tsv" % ROUND))
    if not A or not B:
        print("RULER-UNIT result=%s（名册文件读不到：A=%d 行 B=%d 行）" % (NM, len(A), len(B)))
        return
    pj = {}
    for fn in ("parsed_timing_summary.rpt.json", "parsed_power.rpt.json", "parsed_clock_util.rpt.json"):
        p = os.path.join(parsed_dir, fn)
        if os.path.isfile(p):
            d = json.loads(io.open(p, encoding="utf-8").read())
            for f in d.get("field_positions", []):
                pj[f["field"]] = f["value"]
    a_by_clk = dict((r.get("clock"), r) for r in A)

    # RULER-UNIT：rel_margin_*（比值） vs margin_pct（百分数）——同一个量的两种单位
    agree = conflict = skipped = wrong = 0
    for r in B:
        clk, typ = r.get("clock"), r.get("type")
        col = "rel_margin_setup" if typ == "setup" else "rel_margin_hold"
        a = a_by_clk.get(clk, {}).get(col, NM)
        mp, sl = r.get("margin_pct", NM), r.get("slack_ns", NM)
        if a in (NM, "NA") or mp in (NM, "NA") or sl == NM:
            skipped += 1
            continue
        try:
            if abs(float(mp) - float(a) * 100.0) <= 0.02:
                agree += 1
            else:
                wrong += 1
        except Exception:
            wrong += 1
    if wrong:
        conflict = wrong
    print("RULER-UNIT 同一量的两种单位：roster_%s.tsv 的 rel_margin_*=wns/period（比值，如 0.092375）"
          " vs %s_probe.tsv 的 margin_pct=100*slack/period（百分数，如 9.24）；"
          "换算相符=%d 不符=%d 该域无 intra 路径而跳过=%d；裁决：G1/G2 与差分以**比值那张**为准，"
          "百分数只用于探针名册自己的 D 组判据 分母=%d 判定=%s"
          % (ROUND, ROUND, agree, conflict, skipped, agree + conflict + skipped,
             "FAIL" if conflict else ("PASS" if agree else NM)))

    # RULER-SRC：既有尺子的 src 列是**写死的名字表**，这里用报告自己的钟源网络逐时钟对回去
    okc = mism = unk = 0
    bad = []
    pairs = []
    created = set(constraint_inventory(parsed_dir)["loaded_created"])
    for r in A:
        clk = r.get("clock")
        dom = pj.get("power_clock_constraints[%s].Domain" % clk, NM)
        drv = pj.get("clock_resources[%s].Driver Pin" % clk, NM)
        net = pj.get("clock_resources[%s].Net" % clk, NM)
        derived = classify_clock_source(dom if dom != NM else None,
                                        drv if drv != NM else None,
                                        net if net != NM else None, created)
        pairs.append("%s:表=%s/报告=%s" % (clk, r.get("src"), derived))
        if derived == NM:
            unk += 1
            bad.append("%s:报告里没有源网络" % clk)
        elif derived == r.get("src"):
            okc += 1
        else:
            mism += 1
            bad.append("%s:表=%s 报告=%s" % (clk, r.get("src"), derived))
    print("RULER-SRC build/r115_roster_build.py::src_of() 是**按时钟名字**写死的表；"
          "本轮用 power.rpt 的 Domain 与 clock_util.rpt 的 Driver Pin/Net 逐路反查：%s；"
          "相符=%d 不符=%d 报告里没给源网络=%d 分母=%d 判定=%s"
          % ("；".join(bad) if bad else "八路全相符", okc, mism, unk, len(A),
             "FAIL" if (mism or unk) else ("PASS" if okc else NM)))


# --------------------------------------------------------------------------
# --self：每条判据一个反例，验证「只染红被注入的那一条」
# --------------------------------------------------------------------------
def selftest():
    global NONDET
    root = tempfile.mkdtemp(prefix="p15b_self_")
    a = os.path.join(root, "a")
    emit(a, a)
    base_res, _ = check(a, a)
    base = {r[0]: r[3] for r in base_res}
    print("SELF baseline 判定 %s 分母=判据数 %d" % (json.dumps(base, sort_keys=True), len(base)))

    def one(tag, j, mutate):
        d = os.path.join(root, "m_" + tag)
        os.makedirs(d, exist_ok=True)
        for fn in os.listdir(a):
            srcp = os.path.join(a, fn)
            if os.path.isdir(srcp):
                continue
            io.open(os.path.join(d, fn), "w", encoding="utf-8", newline="\n").write(
                io.open(srcp, encoding="utf-8", errors="replace").read())
        mutate(d)
        res, _ = check(d, d)
        got = {r[0]: r[3] for r in res}
        reds = sorted([k for k, v in got.items() if v != base.get(k)])
        ok = got.get(j) in ("FAIL", NM) and reds == [j]
        print("SELF %-26s 反例目标=%s 目标判定=%s 连带红=%s %s"
              % (tag, j, got.get(j), (reds if reds != [j] else "无"), "PASS" if ok else "FAIL"))
        return 0 if ok else 1

    r = 0

    def m_j1(d):
        # 把一条记录的行号改成 1（值还在、位置错）⇒ J1 必须咬住
        p = os.path.join(d, "parsed_timing_summary.rpt.json")
        t = json.loads(io.open(p, encoding="utf-8").read())
        for f in t["field_positions"]:
            if f["field"] == "intra_clock[eth_rxc].WNS(ns)":
                f["line"] = 1
                break
        io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(t, sort_keys=True, ensure_ascii=False))

    def m_j2(d):
        # 整域少一行（把 eth_rxc 那行删掉）⇒ 域数 != 报告的时钟数 ⇒ J2 必须红
        p = os.path.join(d, "roster_%s.tsv" % ROUND)
        lines = io.open(p, encoding="utf-8").read().split("\n")
        out = [l for l in lines if not l.split("\t")[0].startswith("eth_rxc")]
        io.open(p, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")

    def m_j5(d):
        # 多一个找不到对应原件的解析件（original 不在 provenance 第 5 节里）⇒ J5 的 orphan=1
        p = os.path.join(d, "parsed_orphan_ghost.rpt.json")
        io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(
            {"original": "build/__p15b_not_in_provenance__.rpt", "parse_status": "OK",
             "field_positions": [], "pairing": {"provenance_md5_12": NM, "recomputed_md5_12": NM,
                                                "pairing_result": NM}}, sort_keys=True))

    def m_j3b(d):
        # 把一条**位置有效**的读数改成 NOT_MEASURED（明明取到了却说没取到）⇒ J3 的反向核对要咬住
        p = os.path.join(d, "parsed_timing_summary.rpt.json")
        t = json.loads(io.open(p, encoding="utf-8").read())
        for f in t["field_positions"]:
            if f["field"] == "intra_clock[eth_rxc].WNS(ns)":
                f["value"] = NM
                break
        io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(t, sort_keys=True, ensure_ascii=False))

    r |= one("J1_位置与值不符", "J1", m_j1)
    r |= one("J2_名册少一个域", "J2", m_j2)
    r |= one("J3_取到却写成NOT_MEASURED", "J3", m_j3b)
    r |= one("J5_解析件无对应原件", "J5", m_j5)

    # J3 的反例 = 铁律要求的正路：**真的把一份原件从输入清单里移走**（这里用不存在的路径代替它，
    # 不动 build/ 里的任何真件），要求它写出 NOT_MEASURED，而不是 0、不是 PASS。
    g = os.path.join(root, "g")
    moved_away = [x for x in REPORTS]
    idx = moved_away.index("build/reports/power.rpt")
    moved_away[idx] = "build/reports/power.rpt.__moved_away_for_selftest__"
    emit(g, os.path.join(root, "g_roster"), reports=moved_away)
    gname = [fn for fn in os.listdir(g) if fn.startswith("parsed_power.rpt")][0]
    d = json.loads(io.open(os.path.join(g, gname), encoding="utf-8").read())
    vals = set(f["value"] for f in d.get("field_positions", []))
    ok3 = (d.get("parse_status") == NM and "0" not in vals and "" not in vals
           and d.get("pairing", {}).get("pairing_result") == NM)
    print("SELF J3_原件移走            parse_status=%s 值集合=%s pairing=%s 连带红=不适用(不经六条门) %s"
          % (d.get("parse_status"), sorted(vals) or "[]", d.get("pairing", {}).get("pairing_result"),
             "PASS" if ok3 else "FAIL"))
    r |= 0 if ok3 else 1

    # J3 的第二支：**真的**把一份原件改名移走 —— 但移的是我自己复制到临时目录的那份，
    # 仓库里 build/reports/power.rpt 一个字节都没动（先证明副本能读出数，再改名，看它变成 NOT_MEASURED）
    orig = os.path.join(REPO, "build", "power.rpt")
    odir = os.path.join(root, "orig")
    os.makedirs(odir, exist_ok=True)
    cp = os.path.join(odir, "power.rpt")
    with io.open(cp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(io.open(orig, encoding="utf-8", errors="replace").read())
    e1 = os.path.join(root, "j3_ok")
    emit(e1, e1, reports=[cp])
    d1 = json.loads(io.open(os.path.join(e1, "parsed_power.rpt.json"), encoding="utf-8").read())
    os.rename(cp, cp + ".renamed_away")
    e2 = os.path.join(root, "j3_gone")
    emit(e2, e2, reports=[cp])
    d2 = json.loads(io.open(os.path.join(e2, "parsed_power.rpt.json"), encoding="utf-8").read())
    v1s = set(f["value"] for f in d1.get("field_positions", [])) - {NM}
    v2s = set(f["value"] for f in d2.get("field_positions", []))
    ok3b = (d1.get("parse_status") == "OK" and len(v1s) >= 3 and d2.get("parse_status") == NM
            and v2s == {NM})
    print("SELF J3_副本改名移走(不动仓内原件) 改名前读到 %d 个值(例 %s) / 改名后 parse_status=%s 值集合=%s %s"
          % (len(v1s), sorted(v1s)[:2], d2.get("parse_status"), sorted(v2s),
             "PASS" if ok3b else "FAIL"))
    r |= 0 if ok3b else 1
    # J6 的反例 = 把名册表头换回既有尺子的**墙钟**行为 ⇒ 两次运行必然逐字节不一致 ⇒ J6 必须红
    NONDET = True
    res, _ = check(a, a)
    got = {x[0]: x[3] for x in res}
    NONDET = False
    reds = sorted([k for k, v in got.items() if v != base.get(k)])
    ok6 = got.get("J6") == "FAIL" and reds == ["J6"]
    print("SELF J6_表头回到墙钟         J6=%s 连带红=%s %s" % (got.get("J6"), reds if reds != ["J6"] else "无",
                                                             "PASS" if ok6 else "FAIL"))
    r |= 0 if ok6 else 1

    # J4 = 上面 7 支反例（J1 / J2 / J3×3 / J5 / J6）每条都有反例且各自只染红自己
    ok4 = r == 0
    print("SELF J4_反例只染红本条       反例数=7 各自独占红=%s 判定=%s"
          % ("是" if ok4 else "否", "PASS" if ok4 else "FAIL"))
    print("GATE-SELF judged=6 分母=反例 7 条（J1/J2/J3 三支/J5/J6，J4 由它们汇总） 判定=%s"
          % ("PASS" if ok4 else "FAIL"))
    print("SELFRESULT %s" % ("GREEN" if r == 0 else "RED"))
    return r


def fieldmap():
    d = os.path.join(REPO, "build", "parsed")
    rows = []
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".json"):
            continue
        j = json.loads(io.open(os.path.join(d, fn), encoding="utf-8").read())
        for f in j.get("field_positions", []):
            rows.append((f["field"], f["file"], f["line"], f["col"], f["value"], f["locator"]))
    print("FIELDMAP %d 行（字段 | 原件 | 行 | 列 | 值 | 定位方式）" % len(rows))
    for r in rows:
        print("FIELDMAP\t%s\t%s\t%s\t%s\t%s\t%s" % r)
    return 0


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--emit"
    pd = os.path.join(REPO, "build", "parsed")
    rd = os.path.join(REPO, "build", "roster")
    if mode == "--emit":
        w = emit(pd, rd)
        print("EMIT files=%d parsed=%s roster=%s" % (len(w), pd, rd))
        res, den = check(pd, rd)
        print_checks(res, den, "CHECK（emit 之后立刻跑同一份判据）")
        ruler_crosscheck(pd, rd)
        return 0
    if mode == "--check":
        res, den = check(pd, rd)
        print_checks(res, den, "CHECK")
        ruler_crosscheck(pd, rd)
        return 0 if all(r[3] != "FAIL" for r in res) else 1
    if mode == "--self":
        return selftest()
    if mode == "--fieldmap":
        return fieldmap()
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

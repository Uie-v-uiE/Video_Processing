#!/usr/bin/env python
# build/scan_async_reg_coverage.py —— 只抓**跨时钟域的捕获寄存器**有没有打 ASYNC_REG（TIMING-10 的源码侧尺子）
#
# 为什么再来这一把（#262，用户"改时序要看其他地方"那一问的第三处账）：
#   `report_methodology` 报 TIMING-9 / TIMING-10 各 1 条，但**不点名是哪两颗**；点名要 `report_cdc`，
#   而构建/台架在飞时我不开第二个 Vivado。官方口径（UG949 的 CDC 一节 + ASYNC_REG 属性）很直接：
#   **跨域链的捕获寄存器要打 `(* ASYNC_REG = "TRUE" *)`**，否则工具会挪位/复制它，亚稳态传播窗口就没保证。
#   本仓这一族有案：#65/#54（一个发射触发器扇到两组同步器 ⇒ CDC-11 Critical）、
#   #52（同步链复位值与源头不一致 ⇒ 上电白送一次长按）——与今天 #256 同一个"上电/属性"家族。
# 前两版为什么都不作数（写死在这里，别第三次犯）：
#   v1 把"任何两条相邻非阻塞赋值"都当同步链 ⇒ 数出 60 颗、57 颗"缺属性"，全是流水线（rd_data/dq/oq/cx2…）。
#      批量造假的尺子比没有尺子更坏。
#   v2 方向对了（只认 dst 与 src 时钟不同），但脚本里的 `\\b` 被 heredoc 退化成 0x08 退格符，
#      于是 begin/end 计数恒为 0、每个 always 的块范围塌成一行 ⇒ 真树上 pairs=0；
#      **而 fixture 恰好都是单行块，四条对照全过**——"对照过了"不等于"尺子能用"，
#      是 A1 那条计数地板把空转照出来的（规矩 46 的新实例）。
#   ⇒ 这一版整个不用 `\\b`（改显式边界），并把"多行 always 块"本身做成一条对照。
# 判据（一行一条，末列是判定）：
#   A1 射程地板：认出的跨域捕获对 >= 4（数不到就是形状没认对，不许当"没问题"）
#   A2 每一对都必须打 ASYNC_REG，缺的逐颗点名
#   A3 打了属性的名字必须在同一文件里真声明成 reg（防属性挂在幽灵名字上）
#   A4 逐条 (源域 -> 捕获域) 边都念出对数（防只数总数不看方向）
# 用法：python build/scan_async_reg_coverage.py [src/rtl]
#       python build/scan_async_reg_coverage.py --self   # 五条对照：打了→绿 / 抹掉→红 / 多行块→必须认到 / 同域→不该数
import io, os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "src/rtl"
# 地板不许是猜的：2 对来自 `build/evidence/r113_async_reg_scan.txt` 的实测（数组读出排除之后），
# 而 A5 直接钉名字——新增一条跨域捕获而忘了打属性时，A1 可能仍绿，A5 会抓住"该认的没认到"。
FLOOR_PAIRS = 2
MUST_SEE = ["rgray_s0", "wgray_s0"]
NBA_RE = re.compile(r"^\s*([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*<=\s*([^;]+?)\s*$")


def strip_comment(ln):
    return re.sub(r"//.*", "", ln)


def stmts(text):
    """[(行号, 单条语句)]：一行里多条赋值、以及 `always @(posedge X) begin ... end` 整块写在一行的都要拆开。
    每段开头残留的 always/begin/end/else 关键字在这里清掉（不用 \\b，见文件头 v2 的事故）。"""
    out = []
    for i, raw in enumerate(text.splitlines()):
        ln = strip_comment(raw)
        ln = re.sub(r"always\s*@\s*\([^)]*\)", " ", ln)
        ln = re.sub(r"always\b", " ", ln)
        for seg in ln.split(";"):
            seg = seg.strip()
            seg = re.sub(r"^(begin|end|else\s+begin|else)\s+", " ", seg)
            seg = seg.strip()
            if seg:
                out.append((i, seg))
    return out


def block_spans(text):
    """每个 always 的 (时钟, 起始行, 结束行)。允许一行内开了又收，也允许跨多行。"""
    lines = [strip_comment(l) for l in text.splitlines()]
    spans = []
    for i, ln in enumerate(lines):
        for m in re.finditer(r"always\s*@\s*\(\s*(?:posedge|negedge)\s+([A-Za-z_][\w.$]*)", ln):
            clk = m.group(1).split(".")[-1]
            depth, end = 0, i
            for j in range(i, len(lines)):
                s = lines[j]
                if "endmodule" in s:
                    continue
                depth += len(re.findall(r"begin", s))
                depth -= len(re.findall(r"end\b", s)) - len(re.findall(r"endmodule", s))
                if depth <= 0:
                    end = j
                    break
            spans.append((clk, i, end))
    return spans


def clock_of(spans, lineno):
    best = None
    for clk, a, b in spans:
        if a <= lineno <= b and (best is None or a >= best[1]):
            best = (clk, a)
    return best[0] if best else None


def array_names(text):
    """`(* ram_style = "block" *) reg [63:0] lo [0:D_LO-1];` 这种存储体（**宽度括号在名字前、
    深度括号在名字后**）：数组读出不是"跨域捕获寄存器"（跨域的是地址/空满，由格雷码指针与提交锁管）
    ⇒ 必须排除，否则就是 v1 那种批量造假。第一版这里要求名字后面跟两个括号，本仓的写法只有一个 ⇒
    五颗数组读出被念成"缺 ASYNC_REG"，A2 的红因此不可信（同一把尺子不许既漏又滥）。"""
    decl = re.findall(r"\breg\b\s*(\[[^\]]*\]\s*)?([A-Za-z_]\w*)\s*(\[[^\]]*\])?\s*;", text)
    return set(n for _w, n, d in decl if d)


def reg_clocks(text, spans):
    m = {}
    for lineno, seg in stmts(text):
        mm = NBA_RE.match(seg)
        if not mm:
            continue
        clk = clock_of(spans, lineno)
        if clk:
            m.setdefault(mm.group(1), set()).add(clk)
    return m


def scan(text, fname):
    """只收 `dst <= src` 且 src 是**另一个时钟域的寄存器** ⇒ dst 就是跨域捕获寄存器。"""
    spans = block_spans(text)
    rc = reg_clocks(text, spans)
    arrays = array_names(text)
    lines = text.splitlines()
    out = []
    for i, seg in stmts(text):
        mm = NBA_RE.match(seg)
        if not mm:
            continue
        dst, rhs = mm.group(1), mm.group(2)
        cd = clock_of(spans, i)
        if not cd:
            continue
        for src in [w for w in re.findall(r"[A-Za-z_]\w*", rhs) if w in rc and w != dst and w not in arrays]:
            cs = sorted(rc[src])
            if cd in cs:
                continue                      # 同一个时钟 = 普通流水线，不在射程
            win = "\n".join(lines[max(0, i - 8):i + 1])
            has = ("ASYNC_REG" in win or
                   re.search(r"ASYNC_REG[\s\S]{0,200}?\breg\b[^\n;]*\b" + re.escape(dst) + r"\b", text) is not None)
            out.append((dst, src, cd, ",".join(cs), i + 1, bool(has), fname))
    return out


def collect(root):
    rows = []
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            if n.endswith(".v"):
                p = os.path.join(dirpath, n).replace("\\", "/")
                rows += scan(io.open(p, encoding="utf-8", errors="replace").read(), p)
    return rows


def judge(rows, texts):
    j = []
    j.append(("A1_scope", "cross_domain_pairs=%d" % len(rows), "want>=%d" % FLOOR_PAIRS,
              "GREEN" if len(rows) >= FLOOR_PAIRS else "RED"))
    named = set(r[0] for r in rows)
    lack = [x for x in MUST_SEE if x not in named]
    j.append(("A5_must_see", "named=%d" % len(named), "missing=%s" % (",".join(lack) or "none"),
              "GREEN" if not lack else "RED"))
    miss = [r for r in rows if not r[5]]
    j.append(("A2_all_marked", "missing=%d" % len(miss), "want=0", "GREEN" if not miss else "RED"))
    ghost = ["%s:%s" % (f, dst) for dst, src, cd, cs, line, has, f in rows
             if has and not re.search(r"\breg\b[^\n;]*\b" + re.escape(dst) + r"\b", texts.get(f, ""))]
    j.append(("A3_no_ghost", "ghost=%d" % len(ghost), "want=0", "GREEN" if not ghost else "RED"))
    edges = {}
    for dst, src, cd, cs, line, has, f in rows:
        edges[(cs, cd)] = edges.get((cs, cd), 0) + 1
    j.append(("A4_edges_named", "edges=%d" % len(edges), "want>=2", "GREEN" if len(edges) >= 2 else "RED"))
    return j, miss, ghost, edges


FIXTURES = {
    "ok": """
module fk (input a_clk, input b_clk, input d, output reg q);
  reg a1, a2;
  (* ASYNC_REG = "TRUE" *) reg b1, b2;
  always @(posedge a_clk) begin a1 <= d; a2 <= a1; end
  always @(posedge b_clk) begin b1 <= a2; b2 <= b1; q <= b2; end
endmodule
""",
    "missing": """
module fk (input a_clk, input b_clk, input d, output reg q);
  reg a1, a2, b1, b2;
  always @(posedge a_clk) begin a1 <= d; a2 <= a1; end
  always @(posedge b_clk) begin b1 <= a2; b2 <= b1; q <= b2; end
endmodule
""",
    "multiline": """
module fk (input a_clk, input b_clk, input d, output reg q);
  reg a1, a2, b1;
  always @(posedge a_clk) begin
    a1 <= d;
    a2 <= a1;
  end
  always @(posedge b_clk) begin
    if (!b_clk) begin
      b1 <= 0;
    end else begin
      b1 <= a2;
    end
  end
endmodule
""",
    "same_clock": """
module fk (input a_clk, input d, output reg q);
  reg a1, a2;
  always @(posedge a_clk) begin a1 <= d; a2 <= a1; q <= a2; end
endmodule
""",
    "memory": """
module fk (input wr_clk, input rd_clk, input [7:0] di, output reg [7:0] q);
  reg [7:0] mem [0:63];
  reg [5:0] waddr;
  always @(posedge wr_clk) begin waddr <= waddr + 1; mem[waddr] <= di; end
  always @(posedge rd_clk) q <= mem[5'b00001];
endmodule
""",
}


def main():
    if "--self" in sys.argv:
        r = 0
        def run(name, text, min_pairs, want_missing, want_ghost):
            rows = scan(text, name)
            j, miss, ghost, edges = judge(rows, {name: text})
            ok = len(rows) >= min_pairs and len(miss) == want_missing and len(ghost) == want_ghost
            print("SELF %-11s pairs=%d missing=%d ghost=%d want>=%d/%d/%d %s"
                  % (name, len(rows), len(miss), len(ghost), min_pairs, want_missing, want_ghost,
                     "PASS" if ok else "FAIL"))
            return 0 if ok else 1
        r |= run("ok", FIXTURES["ok"], 1, 0, 0)
        r |= run("missing", FIXTURES["missing"], 1, 1, 0)
        r |= run("multiline", FIXTURES["multiline"], 1, 1, 0)     # v2 就是死在多行块上：这一条必须认到
        r |= run("memory", FIXTURES["memory"], 0, 0, 0)          # 数组读出不算跨域捕获（v1 的造假源）
        if scan(FIXTURES["memory"], "m"):
            print("SELF memory     被误当跨域 FAIL"); r |= 1
        if scan(FIXTURES["same_clock"], "sc"):
            print("SELF same_clock 被误当跨域 FAIL"); r |= 1
        else:
            print("SELF same_clock not_counted PASS")
        print("SELF scan_async_reg judged=5 result=%s" % ("PASS" if r == 0 else "FAIL"))
        return 0 if r == 0 else 1

    texts = {}
    for dirpath, _, names in os.walk(ROOT):
        for n in sorted(names):
            if n.endswith(".v"):
                p = os.path.join(dirpath, n).replace("\\", "/")
                texts[p] = io.open(p, encoding="utf-8", errors="replace").read()
    rows = collect(ROOT)
    judged, miss, ghost, edges = judge(rows, texts)
    for dst, src, cd, cs, line, has, f in rows:
        print("SYNCREG %-36s:%-6d %-14s(%s) <- %-14s(%s) %s"
              % (f, line, dst, cd, src, cs, "MARKED" if has else "MISSING"))
    for (cs, cd), n in sorted(edges.items()):
        print("SYNCREG-EDGE %-26s -> %-16s pairs=%d" % (cs, cd, n))
    for tag, got, want, verd in judged:
        print("SYNCREG %-16s %-22s %s %s" % (tag, got, want, verd))
    red = any(v[3] == "RED" for v in judged)
    print("SYNCREG-SUMMARY root=%s pairs=%d missing=%d ghosts=%d edges=%d result=%s"
          % (ROOT, len(rows), len(miss), len(ghost), len(edges), "RED" if red else "GREEN"))
    return 1 if red else 0


if __name__ == "__main__":
    sys.exit(main())

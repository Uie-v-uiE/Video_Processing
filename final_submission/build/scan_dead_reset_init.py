#!/usr/bin/env python
# 用途：全局扫："这颗寄存器的复位在层次里根本不通电 ⇒ 代码写的复位值不生效"
# 输入：命令行参数
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/scan_dead_reset_init.py —— 全局扫："这颗寄存器的复位在层次里根本不通电 ⇒ 代码写的复位值不生效"
#
# 为什么要有这一把（#256 的结构性余账）：r112/r113 修的是被眼睛看见的那一颗（key_debounce 的 key_stable），
#   病根却在 `system_top.v:250`——`sys_rst_n` 恒接 1'b1 ⇒ **这一域里每一条 `if (!rst_n)` 都是死支**，
#   综合把复位摘掉之后，上电值只剩位流 INIT（0），与代码想要的复位值无关。
#   只追最疼的那一颗就是"一根筋"。这一把从真顶层沿实例化树往下传死复位，逐颗念出没没写声明初值。
# 口径（两条都别越界）：
#   1) 这是**按名字的源码近似**，不是网表事实。网表那一侧由 build/tcl/probe_ff_init.tcl +
#      build/check_powup_init.sh 问 `get_property INIT`。两把尺子不许互相替。
#   2) 死复位**按顶层分别算**：system_top（AXI 流，在板上的那一版）与 pl_demo_top（纯 PL 演示流）
#      是两棵树，同一颗寄存器在一棵树里死、另一棵树里活完全可能。
#      前一版把两棵树混成一锅（按模块名全局合并 dead 集），pl_demo_top 的 `.axi_rst_n(1'b1)`
#      就把 system_top 那一侧也染成"死"——假案，这就是按根分开的动因。
# 判什么：
#   DEAD_RST   这一棵树里 (module, 复位网) 这对被恒值接死（沿实例化边界传播，只传复位口）
#   WANT1      某个 always 的复位分支把寄存器写成 1'b1（这颗上电就想要 1）
#   INIT_OK    同一模块里这颗 reg 有声明初值 `reg x = 1'b1`（综合把它带进 FF INIT ⇒ 安全）
#   INIT_MISS  没有声明初值 ⇒ 位流上电值 = 0 = 想要的反面（这就是债，逐颗列出来）
import os, re, sys, io

ROOT_DIR = sys.argv[1] if len(sys.argv) > 1 else "src/rtl"
ROOTS = (sys.argv[2] if len(sys.argv) > 2 else "system_top,pl_demo_top").split(",")

files = []
for dirpath, _, names in os.walk(ROOT_DIR):
    for n in sorted(names):
        if n.endswith(".v"):
            files.append(os.path.join(dirpath, n))
files.sort()
def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", " ", t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)
def read(f): return strip_comments(io.open(f, encoding="utf-8", errors="replace").read())

mod_re = re.compile(r"\bmodule\s+([A-Za-z_]\w*)\b", re.M)
mods = {}
for f in files:
    src = read(f)
    for m in mod_re.finditer(src):
        name = m.group(1)
        if name in mods:
            continue
        st = m.start()
        em = re.search(r"\bendmodule\b", src[st:])
        body = src[st: st + em.end()] if em else src[st:]
        pm = re.search(r"\bmodule\s+[A-Za-z_]\w*\s*(?:#\s*\([\s\S]*?\)\s*)?\(([\s\S]*?)\)\s*;", src[st:])
        mods[name] = dict(file=f, body=body,
                          ports=re.findall(r"[A-Za-z_]\w*", pm.group(1)) if pm else [])

KW = set("module endmodule begin end if else always assign wire reg input output inout posedge negedge "
         "parameter localparam initial case endcase for generate endfunction function task signed "
         "and or not xor nand nor buf de celse".split())
inst_re = re.compile(r"\b([A-Za-z_]\w*)\s*(?:#\s*\([\s\S]*?\)\s*)?([A-Za-z_]\w*)\s*\(", re.M)
const_re = re.compile(r"(?:\bwire\s+(?:\[[^\]]*\]\s*)?|^\s*assign\s+)([A-Za-z_]\w*)\s*=\s*1'b([01])", re.M)
portconn_re = re.compile(r"\.\s*([A-Za-z_]\w*)\s*\(\s*([^()]*?)\s*\)")
always_re = re.compile(r"always\s*@\s*\(\s*(?:posedge|negedge)\s+[\w.]+(?:\s+or\s+(?:posedge|negedge)\s+([\w.]+))?", re.M)
reset_if_re = re.compile(r"if\s*\(\s*(?:!\s*([\w.]+)|([\w.]+)\s*==\s*1'b0)\s*\)")
nba_re = re.compile(r"([A-Za-z_][\w]*)\s*(?:\[[^\]]*\])?\s*<=\s*1'b([01])\s*;")
decl_stmt_re = re.compile(r"\breg\b([^;]*?);", re.M)

def inits_of(body):
    """声明初值：`reg a = 1'b1, b = 1'b1;` 一条语句里多个声明子要逐个认
    （前一版只认最后一个，于是 key_sync1 被念成"没初值"——本尺子自己的假案，见 --self）。"""
    out = {}
    for grp in decl_stmt_re.findall(body):
        for piece in grp.split(","):
            m = re.search(r"([A-Za-z_]\w*)\s*=\s*1'b([01])", piece)
            if m:
                out[m.group(1)] = m.group(2)
    return out

def matching_paren(s, i):
    d = 0
    while i < len(s):
        if s[i] == "(":
            d += 1
        elif s[i] == ")":
            d -= 1
            if d == 0:
                return i
        i += 1
    return len(s) - 1

tok_re = re.compile(r"([A-Za-z_]\w*)\s*")
def instances(name):
    """手工扫描：标识符 -> 可选 #(参数表) -> 实例名 -> (端口表)。
    带参数的例化必须靠平衡括号走，正则会在参数表里第一个右括号截断（u_k2 就是这么漏掉的）。"""
    body = mods[name]["body"]
    res, i = [], 0
    while i < len(body):
        m = tok_re.match(body, i)
        if not m:
            i += 1
            continue
        child = m.group(1)
        j = m.end()
        if body.startswith("#", j):
            k = body.find("(", j)
            if k < 0:
                i += 1; continue
            j = matching_paren(body, k) + 1
        m2 = re.match(r"\s*([A-Za-z_]\w*)\s*\(", body[j:])
        if not m2:
            i += 1; continue
        inst = m2.group(1)
        oi = j + m2.end() - 1
        if child in KW or child not in mods or child == name or inst == child:
            i = oi + 1; continue
        args = body[oi: matching_paren(body, oi) + 1]
        res.append((child, inst, portconn_re.findall(args[1:-1])))
        i = oi + 1
    return res

_rst_cache = {}
def reset_nets(name):
    """该模块里真被当复位用的口名：always 的第二边沿，且紧跟的 `if (!同名的)` 用的就是它。"""
    if name in _rst_cache:
        return _rst_cache[name]
    body = mods[name]["body"]
    out = set()
    for am in always_re.finditer(body):
        r = am.group(1)
        if not r:
            continue
        base = r.split(".")[-1]
        rm = reset_if_re.search(body[am.end(): am.end() + 1500])
        if rm and (rm.group(1) or rm.group(2) or "").split(".")[-1] == base:
            out.add(base)
    _rst_cache[name] = out
    return out

def walk(root):
    dead = {}
    seen_inst = [0]
    def rec(mod, path, deadnets, depth):
        if depth > 24:
            return
        for n in reset_nets(mod):
            if n in deadnets:
                dead.setdefault((mod, n), []).append(path)
        local = set(deadnets) | set(net for net, _ in const_re.findall(mods[mod]["body"]))
        for child, inst, conns in instances(mod):
            seen_inst[0] += 1
            crn = reset_nets(child)
            cdead = set()
            for port, expr in conns:
                e = expr.strip()
                if port not in crn:
                    continue
                if re.fullmatch(r"1'b[01]", e) or e.split(".")[-1] in local:
                    cdead.add(port)
            rec(child, path + "/" + inst, cdead, depth + 1)
    rec(root, root, set(), 0)
    return dead, seen_inst[0]

def want1(mod, n):
    """(module, 死复位网) 之下：复位分支里被写成 1'b1 的寄存器，以及它有没有声明初值"""
    body = mods[mod]["body"]
    ini = inits_of(body)
    rows = []
    for am in always_re.finditer(body):
        r = am.group(1)
        if not r or r.split(".")[-1] != n:
            continue
        seg = body[am.end(): am.end() + 1500]
        rm = reset_if_re.search(seg)
        if not rm:
            continue
        k = seg.index(rm.group(0)) + len(rm.group(0))
        i, guard = k, 0
        while i < len(seg) and guard < 3000:
            if re.match(r"\s*else\b", seg[i:]):
                break
            i += 1
            guard += 1
        for lhs, val in nba_re.findall(seg[k:i]):
            if val == "1":
                rows.append((lhs, ini.get(lhs) == "1"))
    return rows

FAKE = """
module fake_a (input clk, input rst_n);
  reg  x = 1'b1, y = 1'b1, z;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin x <= 1'b1; y <= 1'b1; z <= 1'b0; end
    else begin x <= ~x; end
  end
endmodule
"""

if "--self" in sys.argv:
    r = 0
    ini = inits_of(FAKE)
    ok = (ini.get("x") == "1" and ini.get("y") == "1" and "z" not in ini)
    print("SELF multi_declarator x=%s y=%s z=%s %s"
          % (ini.get("x"), ini.get("y"), ini.get("z"), "PASS" if ok else "FAIL"))
    r |= 0 if ok else 1
    mods["fake_a"] = dict(file="fixture", body=FAKE, ports=["clk", "rst_n"])
    _rst_cache["fake_a"] = {"rst_n"}
    w = want1("fake_a", "rst_n")
    got = sorted(set((reg, ok2) for reg, ok2 in w))
    exp = [("x", True), ("y", True)]
    ok2 = got == exp
    print("SELF want1_rows %s expected=%s %s" % (got, exp, "PASS" if ok2 else "FAIL"))
    r |= 0 if ok2 else 1
    # 变异对照：把 x 的声明初值抹掉 ⇒ 必须正好漏出 x 一颗（尺子不能只会念 CLEAN）
    fake_bad = FAKE.replace("reg  x = 1'b1, y = 1'b1, z;", "reg  y = 1'b1, z;")
    mods["fake_b"] = dict(file="fixture", body=fake_bad, ports=["clk", "rst_n"])
    _rst_cache["fake_b"] = {"rst_n"}
    got3 = sorted(set((reg, v) for reg, v in want1("fake_b", "rst_n")))
    exp3 = [("x", False), ("y", True)]
    ok3 = got3 == exp3
    print("SELF mutation_x_no_init %s expected=%s %s" % (got3, exp3, "PASS" if ok3 else "FAIL"))
    r |= 0 if ok3 else 1
    # 第四条对照：整条"顶层把复位口接成 1'b1 ⇒ 子模块那颗想要 1 的寄存器没初值"必须被端到端抓到。
    # 没有这一条，真扫念出 dead_pairs=0 / CLEAN 就可能是扫描器根本没往下走（空转的绿，见规矩 46）。
    FAKE_TOP = """
module fake_top (input clk);
  wire rst_live = 1'b1;
  fake_child u_c (.clk(clk), .rst_n(rst_live));
endmodule
"""
    FAKE_CHILD = """
module fake_child (input clk, input rst_n);
  reg flag;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) flag <= 1'b1;
    else flag <= ~flag;
  end
endmodule
"""
    mods["fake_top"] = dict(file="fixture", body=FAKE_TOP, ports=["clk"])
    mods["fake_child"] = dict(file="fixture", body=FAKE_CHILD, ports=["clk", "rst_n"])
    _rst_cache.pop("fake_child", None)
    d4, n4 = walk("fake_top")
    hit = ("fake_child", "rst_n") in d4
    ok4 = hit and n4 >= 1
    print("SELF end_to_end_dead_found pairs=%s instances=%d %s"
          % (sorted(d4.keys()), n4, "PASS" if ok4 else "FAIL"))
    r |= 0 if ok4 else 1
    print("SELF scan_dead_reset judged=4 result=%s" % ("PASS" if r == 0 else "FAIL"))
    sys.exit(r)

print("# dead-reset scan (ruler: build/scan_dead_reset_init.py; netlist truth = probe_ff_init.tcl)")
grand_miss = 0
grand_want = 0
FLOOR_INST = 10          # 空转保护：一棵真树里数不到 10 个实例，就是扫描器自己没走下去
for root in ROOTS:
    root = root.strip()
    if root not in mods:
        print("ROOT %s NOT_FOUND" % root)
        grand_miss += 1
        continue
    dead, ninst = walk(root)
    scope = "PASS" if ninst >= FLOOR_INST else "RED"
    if scope == "RED":
        grand_miss += 1
    print("ROOT %s walk_instances=%d floor=%d dead_reset_pairs=%d scope=%s"
          % (root, ninst, FLOOR_INST, len(dead), scope))
    for (mod, n), paths in sorted(dead.items()):
        print("  DEAD %s.%s instances=%d e.g.=%s" % (mod, n, len(paths), paths[0]))
    seen, miss_rows = set(), []
    for (mod, n) in dead:
        for reg, ok in want1(mod, n):
            key = (mod, reg)
            if key in seen:
                continue
            seen.add(key)
            if not ok:
                miss_rows.append((mod, reg, n))
    for mod, reg, n in sorted(miss_rows):
        print("  INIT_MISS module=%-20s reg=%-20s rst=%s file=%s"
              % (mod, reg, n, mods[mod]["file"].replace("\\", "/")))
    print("  WANT1 root=%s want1=%d init_ok=%d init_miss=%d"
          % (root, len(seen), len(seen) - len(miss_rows), len(miss_rows)))
    grand_miss += len(miss_rows)
    grand_want += len(seen)
print("SCAN_SUMMARY roots=%d want1_total=%d init_miss_total=%d result=%s"
      % (len(ROOTS), grand_want, grand_miss, "NEEDS_REVIEW" if grand_miss else "CLEAN"))

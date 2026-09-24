#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build/check_ports.py —— 顶层接线的机器判据（门禁第 14 项）

为什么要有它（2026-09-25 凌晨，V8-5 做完才写）：
  这个仓库里 **pl_video_top / system_top 没有任何台架例化**（grep 得到，例化拿不到），
  所以"改了一个模块的端口、顶层忘了连/连错名"这类错，L1 全量 57 条一条都不会红，
  只能等 25 分钟的构建 —— 今晚 osd_overlay 换端口时就踩在这个空档上。

它判三条**会真出错**的事：
  ① 连了目标模块**没有**的端口名 ⇒ 综合报错；而 xsim 允许把拼错的名字当隐式 net，仿真不报。
  ② 目标模块的**输入端口没连** ⇒ 输入悬空 = Z/X，屏上表现为"设了没反应"，
     这正是本项目反复登记的那一类（#47 的红色占位、#55 的没人例化、#61 的多驱动）。
  ③ 端口的**位宽与接上去的东西不一致**（2026-09-25 加，r52 改 dbg_lat 从 5 口到 6 口时想的）。
     Verilog 在这里既不报错也不警告：输出接窄线 = 高位静默丢掉，输入接窄常数 = 静默补零。
     #57 就是这一类（lane30 的模式高位被一根 [7:0] 吞掉），代价是一次 25 分钟构建 + 一次上板。
     只判"两头都数得清"的连接：位宽是**纯数字或四则运算**（`[6*32-1:0]` 算得出 192），
     或 Verilog 字面量（`19'd0`）；`[W-1:0]` 这种含参数的、拼接、部分选择、表达式一律**跳过不猜**。
输出端口允许悬空（本仓有意识地留了几个观测口），不判红。

判据自己的反例（改了判据必须重跑，凭据 `build/ports_check_width_ce.txt`）：
  A. `system_top.v` 把 `wire [6*32-1:0] dbg_lat` 改成 `[5*32-1:0]` ⇒ ③ 必须报 192 vs 160；
  B. `pl_demo_top.v` 把 `.eth_wr_addr(19'd0)` 改成 `18'd0` ⇒ ③ 必须报 19 vs 18；
  C. 未改动的整棵树 ⇒ violations=0（当前 526 条宽度可比）。
  前两条各覆盖一种形状（① 声明位宽 vs 端口位宽、② 字面量位宽 vs 端口位宽），
  少任何一条都可能只测到自己写对的那一半。

保守优先：端口表看不懂（非 ANSI、`.*`、宏包着）就**整个跳过**，不猜。
判据自己不确定的时候必须闭嘴，否则第一次假红之后就会有人来把它关掉（#57/#60 的教训）。

用法（仓库根目录）：
    python build/check_ports.py             # 逐条打印
    python build/check_ports.py --quiet     # 只要汇总行（gates.sh 用）
退出码：0 干净 / 1 有违规 / 2 脚本自己出错
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RTL = os.path.join(ROOT, "src", "rtl")

KEYWORDS = {"module", "endmodule", "input", "output", "inout", "wire", "reg", "parameter",
            "localparam", "signed", "genvar", "integer", "logic", "and", "or", "not", "buf",
            "assign", "always", "initial", "begin", "end", "if", "else", "case", "endcase",
            "for", "while", "function", "endfunction", "task", "endtask"}
SKIP = {"BUFG", "BUFGCE", "MMCME2_BASE", "PLLE2_BASE", "OBUFDS", "IBUFDS", "OBUF", "IBUF",
        "OSERDESE2", "ISERDESE2", "FDRE", "SRL16E", "OBUFT", "MUX", "PLL"}


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
    t = re.sub(r"//[^\n]*", "", t)
    return t


def split_top(s):
    """按逗号切，但括号/方括号里面的逗号不算。"""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def match_paren(s, i):
    """s[i] 必须是 '('，返回匹配 ')' 的位置；不匹配返回 -1。"""
    depth = 0
    for k in range(i, len(s)):
        if s[k] == "(":
            depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                return k
    return -1


def lit_width(rng):
    """`[191:0]` / `[6*32-1:0]` 这种**只含数字与四则运算**的位宽 → 返回位数；
    含参数名（`[W-1:0]`）或非 `[hi:lo]` 形状 → 返回 None（不猜，交给调用方跳过）。"""
    if not rng:
        return 1
    m = re.match(r"^\s*\[\s*([0-9+\-*/()\s]+?)\s*:\s*([0-9+\-*/()\s]+?)\s*\]\s*$", rng)
    if not m:
        return None
    try:
        hi, lo = eval("(" + m.group(1) + ")"), eval("(" + m.group(2) + ")")   # noqa: S307
    except Exception:
        return None
    if not (isinstance(hi, int) and isinstance(lo, int)) or hi < 0 or lo < 0:
        return None
    return (hi - lo + 1) if hi >= lo else (lo - hi + 1)


def actual_width(expr, decls):
    """连接表达式能确定的位宽：Verilog 字面量 `64'd0`、`1'b0`，或**在本文件里声明过**的裸标识。
    拼接、部分选择、运算式一律 None —— 这三类正是第一版报假红的地方。"""
    e = expr.strip()
    m = re.match(r"^\d+\s*'[sS]?[bodhBODH]\s*[0-9a-fA-FxXzZ_]+$", e)
    if m:
        return int(re.match(r"^(\d+)", e).group(1))
    if re.match(r"^[A-Za-z_]\w*$", e):
        return decls.get(e)
    return None


def decl_widths(src):
    """本文件里 `wire [..] a` / `reg [..] b` 的**单名**声明 → {名字: 位数}。
    一行声明多个名字、或位宽含参数 ⇒ 跳过（宁可漏判，不可假红）。"""
    out = {}
    for m in re.finditer(r"\b(wire|reg)\s+(\[[^\]]*\])?\s+([A-Za-z_]\w*)\s*(=|;)", src):
        w = lit_width(m.group(2))
        if w is not None:
            out.setdefault(m.group(3), w)
    return out


def ports_of(src, mstart):
    """从 module 头部取 (inputs, all, widths)。看不懂就返回 None => 调用方跳过这个模块。"""
    j = src.index("(", mstart)
    # `module foo #(...)` 的头一个括号是**参数表**，先整段跳过去再读端口表
    pre = src[mstart:j]
    while "#" in pre:
        h = match_paren(src, j)
        if h < 0:
            return None
        j = src.find("(", h)
        if j < 0:
            return None
        pre = src[h:j]
    k = match_paren(src, j)
    if k < 0:
        return None
    body = src[j + 1:k]
    if ".*" in body or "`" in body:
        return None
    ins, allp, wids = set(), set(), {}
    for chunk in split_top(body):
        chunk = chunk.strip()
        if not chunk:
            continue
        d = re.match(r"^(input|output|inout)\b(.*)$", chunk, re.S)
        if not d:
            return None                       # 非 ANSI（裸名字表）：不猜
        is_in = d.group(1) in ("input", "inout")
        # 位宽**先取出来**再去掉：`[W-1:0]` 这种含参数的取不到 ⇒ None ⇒ 这一条不判宽度。
        rng = re.search(r"\[[^\]]*\]", d.group(2))
        w = lit_width(rng.group(0) if rng else None)
        rest = re.sub(r"\b(input|output|inout|reg|wire|signed)\b", " ", d.group(2))
        # **先去掉 [ ... ] 位宽**：`input wire [W-1:0] bus` 里的 W 是参数，不是端口。
        # 第一版没去 ⇒ 每个"带参数位宽"的端口都报成"输入 W 没连"，13 条假红。
        rest = re.sub(r"\[[^\]]*\]", " ", rest)
        names = [n for n in re.findall(r"[A-Za-z_]\w*", rest) if n not in KEYWORDS]
        if not names:
            return None
        for n in names:
            allp.add(n)
            if is_in:
                ins.add(n)
            if w is not None and len(names) == 1:   # 一行多名（`input [7:0] a, b`）不猜谁是谁
                wids[n] = w
    return ins, allp, wids


def collect():
    mods = {}
    for base, _d, names in os.walk(RTL):
        for n in sorted(names):
            if not n.endswith(".v"):
                continue
            path = os.path.join(base, n)
            src = strip_comments(io.open(path, encoding="utf-8", errors="replace").read())
            for mm in re.finditer(r"\bmodule\s+([A-Za-z_]\w*)", src):
                name = mm.group(1)
                lp = src.find("(", mm.end())
                if lp < 0 or src[lp - 1:lp].isspace() is False and src[lp - 1] == ";":
                    continue
                try:
                    got = ports_of(src, mm.start())
                except Exception:
                    got = None
                if got is None:
                    SKIP_LIST.append(name)
                    continue
                if name not in mods:                          # 同名模块取第一份
                    mods[name] = (path, got[0], got[1], got[2])
    return mods


SKIP_LIST = []


def instances(src):
    """产出 (mod, inst, 端口连接文本, 行号)。只认 `mod [ #(..) ] inst ( ... );` 这个形状。"""
    out = []
    for mm in re.finditer(r"\b([A-Za-z_]\w*)\s+(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?"
                          r"([A-Za-z_]\w*)\s*\(", src):
        mod, inst = mm.group(1), mm.group(2)
        if mod in KEYWORDS or inst in KEYWORDS:
            continue
        open_at = src.rindex("(", mm.start(), mm.end() + 1)
        close_at = match_paren(src, open_at)
        if close_at < 0:
            continue
        after = src[close_at + 1:close_at + 40].lstrip()
        if not after.startswith(";"):
            continue                          # 不是例化（函数调用、表达式等）
        line = src[:mm.start()].count("\n") + 1
        out.append((mod, inst, src[open_at + 1:close_at], line))
    return out


def main():
    quiet = "--quiet" in sys.argv
    mods = collect()
    problems, checked, wchecked = [], 0, 0
    for base, _d, names in os.walk(RTL):
        for n in sorted(names):
            if not n.endswith(".v"):
                continue
            path = os.path.join(base, n)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            src = strip_comments(io.open(path, encoding="utf-8", errors="replace").read())
            # 本文件的"标识符 → 位宽"表：内部 wire/reg 声明 + 本文件模块自己的端口。
            decls = decl_widths(src)
            for mname, (mpath, _mi, _ma, mw) in mods.items():
                if mpath == path:
                    for k, v in mw.items():
                        decls.setdefault(k, v)
            for mod, inst, arg, line in instances(src):
                if mod not in mods or mod in SKIP or mod == inst:
                    continue
                if mod == n[:-2]:                # 自己例化自己（不该发生，但别当违规报）
                    continue
                _p, ins, allp, wids = mods[mod]
                if ".*" in arg:
                    continue
                checked += 1
                conns = set(re.findall(r"\.\s*([A-Za-z_]\w*)\s*\(", arg))
                for bad in sorted(conns - allp):
                    problems.append("%s:%d  %s %s 连了不存在的端口 .%s()" % (rel, line, mod, inst, bad))
                for miss in sorted(ins - conns):
                    problems.append("%s:%d  %s %s 的输入 %s 没连（悬空=Z/X）" % (rel, line, mod, inst, miss))
                # ③ 位宽：Verilog 在这里**静默补零/静默截断**，仿真与综合都不报（#57 就是这么把
                #    lane30 的模式高位吞掉的）。只判"两头都数得清"的那一类，其余跳过。
                for chunk in split_top(arg):
                    m = re.match(r"^\.\s*([A-Za-z_]\w*)\s*\((.*)\)$", chunk.strip(), re.S)
                    if not m or m.group(1) not in allp:
                        continue
                    fw = wids.get(m.group(1))
                    aw = actual_width(m.group(2), decls)
                    if not fw or not aw:
                        continue
                    wchecked += 1
                    if fw != aw:
                        problems.append("%s:%d  %s %s .%s(…) 位宽不符：端口 %d 位，接的是 %d 位"
                                        "（Verilog 静默补零/截断 ⇒ 高位会被吃掉，见 #57）"
                                        % (rel, line, mod, inst, m.group(1), fw, aw))
    for p in problems:
        print(p)
    # 跳过的模块要**先**打出来：一个"跳了一半"的检查器报 PASS 是没有意义的（#60 那一课）。
    # 汇总行故意放在最后一行 —— gates.sh 用 tail -1 取它，别让别的行插到后面。
    if not quiet and SKIP_LIST:
        print("  skipped(端口表看不懂/非 ANSI): " + " ".join(sorted(set(SKIP_LIST))))
    print("CHECK PORTS: instances=%d modules=%d skipped=%d width_compared=%d violations=%d %s"
          % (checked, len(mods), len(set(SKIP_LIST)), wchecked, len(problems),
             "PASS" if not problems else "FAIL"))
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Comment-only surgery on Verilog files, with a proof that no code moved.

  python build/trim_comments.py --check            # 工作树 vs HEAD：只允许注释不同
  python build/trim_comments.py --strip [paths]    # 删装饰性注释行（纯标点/空注释）
  python build/trim_comments.py --stat [paths]     # 每个文件最长的注释块 / 注释行占比

`--strip` 只删整行注释且该行除标点外没有别的字符，因此不可能碰到代码；
但它仍然在写完之前用 `code_of()` 比一遍，不满足就回滚。
"""
import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATHS = ("src/rtl", "sim")

LINE_COMMENT = re.compile(r"^\s*//")
DECOR = re.compile(r"^\s*//\s*[-=~*_#.\s\u00b7\u2014\u2500]*\s*$")


def code_of(text: str) -> str:
    """Text with comments removed and trailing space stripped. String literals kept."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                if text[j] == "\n":
                    break
                j += 1
            out.append(text[i:j])
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j < 0:
                break
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            i = j
            out.append(" ")
            continue
        out.append(c)
        i += 1
    return "\n".join("".join(out).splitlines()).strip()


def norm(text: str) -> str:
    """Normalised code: comments gone, whitespace-insensitive."""
    return " ".join(code_of(text).split())


def tracked(paths):
    files = []
    for p in paths:
        root = ROOT / p
        if root.is_file():
            files.append(root)
        elif root.is_dir():
            files += sorted(root.rglob("*.v")) + sorted(root.rglob("*.sv"))
    return files


def head_version(path: Path) -> str:
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:{path.relative_to(ROOT).as_posix()}"],
                       capture_output=True, text=True, encoding="utf-8")
    return r.stdout if r.returncode == 0 else None


def do_check(paths):
    bad = []
    for f in tracked(paths):
        new = f.read_text(encoding="utf-8", errors="replace")
        old = head_version(f)
        if old is None:
            continue  # 新文件，HEAD 里没有
        a, b = norm(old), norm(new)
        if a != b:
            bad.append(f.relative_to(ROOT).as_posix())
    if bad:
        print(f"FAIL  {len(bad)} 个文件的**代码**与 HEAD 不一致（注释手术不许动代码）：")
        for b in bad:
            print("   ", b)
        return 1
    print("OK    注释之外的内容与 HEAD 完全一致")
    return 0


def do_strip(paths, apply):
    total = 0
    for f in tracked(paths):
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
        keep, dropped = [], 0
        for idx, ln in enumerate(lines):
            if DECOR.match(ln.rstrip("\n")):
                # 只有当它上下也是注释时才当装饰删，别把 `/*` 块中间的分割线删出空洞
                prev_is_cmt = idx > 0 and LINE_COMMENT.match(lines[idx - 1])
                next_is_cmt = idx + 1 < len(lines) and LINE_COMMENT.match(lines[idx + 1])
                if prev_is_cmt or next_is_cmt:
                    dropped += 1
                    continue
            keep.append(ln)
        if not dropped:
            continue
        total += dropped
        print(f"{'strip' if apply else 'dry  '} {f.relative_to(ROOT).as_posix():48s} -{dropped}")
        if apply:
            f.write_text("".join(keep), encoding="utf-8", newline="")
    print(f"total decorative comment lines: {total}  ({'applied' if apply else 'no write'})")
    return 0


def do_stat(paths):
    rows = []
    for f in tracked(paths):
        s = f.read_text(encoding="utf-8", errors="replace").splitlines()
        i = best = 0
        while i < len(s):
            if LINE_COMMENT.match(s[i]):
                j = i
                while j < len(s) and LINE_COMMENT.match(s[j]):
                    j += 1
                best = max(best, j - i)
                i = j
            else:
                i += 1
        cmt = sum(1 for l in s if LINE_COMMENT.match(l))
        rows.append((best, cmt, len(s), f.relative_to(ROOT).as_posix()))
    rows.sort(reverse=True)
    for b, c, n, p in rows:
        if b >= 8:
            print(f"blk={b:3d} cmt={c:4d}/{n:5d} {p}")
    print(f"files={len(rows)} comment_lines={sum(r[1] for r in rows)} "
          f"code_lines={sum(r[2] - r[1] for r in rows)}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="工作树的代码是否与 HEAD 一致")
    ap.add_argument("--strip", action="store_true", help="删装饰性注释行")
    ap.add_argument("--apply", action="store_true", help="配合 --strip 真正写盘")
    ap.add_argument("--stat", action="store_true", help="注释块体量分布")
    ap.add_argument("paths", nargs="*", default=None)
    a = ap.parse_args()
    paths = a.paths or list(DEFAULT_PATHS)
    if a.check:
        return do_check(paths)
    if a.strip:
        return do_strip(paths, a.apply)
    if a.stat:
        return do_stat(paths)
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())

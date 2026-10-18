#!/usr/bin/env python3
# 用途："""check_skill_cards.py —— 技能包自身的自检（选题指南 §3.3.5.2 的可复用性口径）
# 输入：命令行参数
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
"""check_skill_cards.py —— 技能包自身的自检（选题指南 §3.3.5.2 的可复用性口径）。

判据三条，任一不满足就退非 0：
  1) 每张卡片（标题形如 `# S12 …`）必须有完整的六节：触发 / 不适用 / 动作 / 完成判据 / 失效边界 / 出处。
     前五节回答"下次遇到这个症状该怎么办"，第六节指回一次真实失败 —— 缺任何一节，这张卡就不可复用。
  2) `skill/README.md` 里"目录里现在有 N 项编号条目"那一句的 N，必须等于盘上实际数出来的条数。
     全仓库只有那一行允许写这个数，所以它必须被机器核着，否则就是"文档说的与跑的不一样"。
  3) 每张卡片正文不超过 120 行（超长的卡通常是在复述过程而不是在沉淀方法）。

用法：python3 build/check_skill_cards.py [--self]
  --self  自带反例自检：临时造一张缺节的卡与一个错的计数，确认这个检查器**真的会红**
          （本项目每条判据都要配一个"改前必须红"的对照，检查器也不例外）
"""
import io
import os
import re
import sys

REQUIRED = [
    ("触发", "适用场景", "适用范围"),
    ("不适用",),
    ("动作", "使用方法"),
    ("完成判据", "已验证效果"),
    ("失效边界", "失效条件"),
    ("出处", "凭据", "来源"),
]
MAX_LINES = 120
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COUNT_RE = re.compile(r"目录里现在有 (\d+) 项编号条目")


def cards(root):
    out = []
    for dirpath, _dirs, files in os.walk(os.path.join(root, "skill")):
        for fn in sorted(files):
            if not fn.endswith(".md"):
                continue
            p = os.path.join(dirpath, fn)
            text = io.open(p, encoding="utf-8").read()
            m = re.search(r"^# (S\d+)\b", text, re.M)
            if m:
                out.append((os.path.relpath(p, root).replace("\\", "/"), m.group(1), text))
    return out


def check(root):
    errs = []
    found = cards(root)
    ids = {sid for _p, sid, _t in found}
    for path, sid, text in found:
        missing = ["/".join(role) for role in REQUIRED if not any(s in text for s in role)]
        if missing:
            errs.append("%s (%s) 缺节：%s" % (path, sid, "、".join(missing)))
        n = len(text.rstrip("\n").split("\n"))
        if n > MAX_LINES:
            errs.append("%s 正文 %d 行 > %d" % (path, n, MAX_LINES))
    idx = os.path.join(root, "skill", "README.md")
    if os.path.isfile(idx):
        m = COUNT_RE.search(io.open(idx, encoding="utf-8").read())
        if not m:
            errs.append("skill/README.md 找不到「目录里现在有 N 项编号条目」这一行")
        elif int(m.group(1)) != len(ids):
            errs.append("skill/README.md 写 %s 项，盘上是 %d 项" % (m.group(1), len(ids)))
    return found, errs


def selftest():
    """反例必须让检查器红，否则这个检查器没有牙。"""
    import shutil
    import tempfile

    tmp = tempfile.mkdtemp(prefix="skillself_")
    try:
        shutil.copytree(os.path.join(ROOT, "skill"), os.path.join(tmp, "skill"))
        _found, base_errs = check(tmp)
        if base_errs:
            print("SELF 前置不满足：真目录本身就有 %d 条问题，先修它再谈反例" % len(base_errs))
            return 1
        with io.open(os.path.join(tmp, "skill", "zz_selftest_bad.md"), "w", encoding="utf-8") as f:
            f.write("# S99 反例卡\n\n触发：随便\n动作：随便\n")
        _f2, e2 = check(tmp)
        ok_missing = any("缺节" in x for x in e2)
        text = io.open(os.path.join(tmp, "skill", "README.md"), encoding="utf-8").read()
        io.open(os.path.join(tmp, "skill", "README.md"), "w", encoding="utf-8").write(
            COUNT_RE.sub("目录里现在有 999 项编号条目", text))
        _f3, e3 = check(tmp)
        ok_count = any("项，盘上是" in x for x in e3)
        print("反例 1（缺节的卡）被红：", "是" if ok_missing else "否 —— 检查器没有牙")
        print("反例 2（写错的条目数）被红：", "是" if ok_count else "否 —— 检查器没有牙")
        return 0 if (ok_missing and ok_count) else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    if "--self" in sys.argv:
        return selftest()
    found, errs = check(ROOT)
    ids = sorted({sid for _p, sid, _t in found}, key=lambda s: int(s[1:]))
    print("扫了 %d 张卡片（%s … %s），六节与长度检查：%s"
          % (len(found), ids[0], ids[-1], "全部通过" if not errs else "%d 条问题" % len(errs)))
    for e in errs:
        print("  -", e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())

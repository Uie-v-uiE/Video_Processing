#!/usr/bin/env python3
# 用途：修我自己刚写进去的两处不合适的东西
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r92_doc_fixup.py —— 修我自己刚写进去的两处不合适的东西。
# (1) 新加的"念 WHS 要带口径"那条插在了编号项 1 与它的续行之间，会把列表打断；挪到 1 的末尾之后。
# (2) board/README 与 report/BUILD 里我举例子写了 `build/isolated_xxx/system.bit` 这种**不存在的路径**，
#     文档时效检查器（D4b/D4c）就点它——举例不能造假路径，改成"隔离滚一轮的产物"这种说法。
# 跑法：python build/r92_doc_fixup.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p): return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read()
def wr(p, s): io.open(os.path.join(ROOT, p), 'w', encoding='utf-8', newline='').write(s)

K = 'report/known_issues.md'
t = rd(K)
i = t.find('- **念 WHS 必须带口径**')
endmark = '见 `src/constraints/rk_zynq7020.xdc`）'
j = t.find(endmark, i)
bullet = t[i:j + len(endmark) + 1] if i >= 0 and j >= 0 else ''
if not bullet:
    print("SKIP 找不到那条 WHS 口径（可能已经挪过）")
    t2 = t.replace(bullet, '', 1)
    # 挪到编号项 2 之前（也就是 1 的全部续行之后）
    n = re.search(r'^2\. \*\*', t2, re.M)
    if n:
        pos = n.start()
        t2 = t2[:pos] + bullet + t2[pos:]
        wr(K, t2)
        print("OK   KNOWN_ISSUES：口径那条已挪到编号项 2 之前")
    else:
        wr(K, t)   # 把删掉的还回去，别留半成品
        print("SKIP 没找到编号项 2，原文已复原")

B = 'board/README.md'
t = rd(B)
old = '   # 想烧隔离滚出来的件：VP_BIT=build/isolated_xxx/system.bit（默认仍是 build/system.bit）'
new = '   # program_pl 认 VP_BIT=<路径>，用来烧"隔离滚一轮"的产物做对照；不设就是 build/system.bit'
c = t.count(old)
if c == 1:
    wr(B, t.replace(old, new)); print("OK   board/README：去掉举例用的假路径")
else:
    print(f"SKIP board/README（匹配 {c} 次）")

D = 'report/build.md'
t = rd(D)
old2 = '拿隔离滚的产物做板上对照时可以 `VP_BIT=<那个目录>/system.bit`'
new2 = '拿隔离滚的产物做板上对照时可以 `VP_BIT` 指过去'
c = t.count(old2)
if c == 1:
    wr(D, t.replace(old2, new2)); print("OK   report/BUILD：同上")
else:
    print(f"SKIP report/BUILD（匹配 {c} 次）")

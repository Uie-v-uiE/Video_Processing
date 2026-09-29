#!/usr/bin/env python3
# build/r92_add_clocktree_row.py —— 给验收表补一条**能机判**的行：收口只剩一棵时钟树。
# 为什么这条值得单列：#57 改的是时钟拓扑，而拓扑在 `clock_util.rpt` 里是一个可以直接数的数
# （`BUFIO` 用量 1 → 0），比"读 slack 看运气"硬。成对给数（改前/改后）是仓库规矩。
# 跑法：python build/r92_add_clocktree_row.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p): return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read()

def bufio_used(p):
    m = re.search(r'^\| BUFIO\s+\|\s*(\d+)\s+\|\s*(\d+)', rd(p), re.M)
    return m.group(1) if m else None

now = bufio_used('build/clock_util.rpt')
before = bufio_used('build/r88_clock_util.rpt')
print(f"BUFIO 用量：改前 {before} -> 改后 {now}")
if not (now and before):
    raise SystemExit("取不到数，不写行")

row = (f'| 10 | 收口只有一棵时钟树（#57 的结构判据，不靠 slack 碰运气） | '
       f'`build/clock_util.rpt`：**`BUFIO` 用量 {now}**（改前那一份是 {before}），'
       f'`eth_rxc` 只经一只 `BUFG/O`（`g2`←`src2`=`IBUF/O @IOB_X1Y28`，fabric 负载 2478）；'
       f'最差 20 条 hold 的时钟偏斜由 `build/hold_paths.rpt` 逐条读，实测 0.013~0.349 ns（改前那一条是 1.616 ns） | '
       f'`build/clock_util.rpt`、`build/hold_paths.rpt`；改前对照是仓库里的 `build/r88_clock_util.rpt`（rNN 命名的对照件，不随包） |')

p = 'board/ACCEPTANCE.md'
t = rd(p)
if '收口只有一棵时钟树' in t:
    print("SKIP 第 10 行已存在")
else:
    # 插在"机器判据"表最后一行之后（第 9 行以 `|` 开头且含"时序/资源读数与报告一致"）
    m = re.search(r'^\| 9 \|.*时序/资源读数与报告一致.*$\n', t, re.M)
    if not m:
        raise SystemExit("找不到第 9 行，不冒险插")
    t = t[:m.end()] + row + '\n' + t[m.end():]   # 尾巴必须接回来：漏了 `+ t[m.end():]` 就会把第 9 行之后整段删掉
    if len(t) <= len(rd(p)):                    # 这个脚本真栽过一次，所以"写完变短"直接停手
        raise SystemExit('REFUSE: 写回去比原文短，这是删除不是插入')
    io.open(os.path.join(ROOT, p), 'w', encoding='utf-8', newline='').write(t)
    print("OK   ACCEPTANCE 第 10 行已插入机器判据表")

# 顺手在 r92 那一节的表里补同一把尺子（只补一行，不重排）
p2 = 'docs/OPTIMIZATION_LOG.md'
t2 = rd(p2)
anchor = '| BRAM / LUT / FF / DSP | 95 / 14358 / 8075 / 19 | 95 / 14351 / 8075 / 19 |'
add = (f'| `BUFIO` 用量（`clock_util.rpt` 第一张表） | 1 | **{now}** | 结构判据：拓扑上真的少了一棵树，'
       f'与 slack 摆幅无关 |')
if 'BUFIO` 用量（`clock_util.rpt`' in t2:
    print("SKIP OPTIMIZATION_LOG 已有这行")
elif t2.count(anchor) == 1:
    i = t2.index(anchor)
    end = t2.index('\n', i) + 1
    io.open(os.path.join(ROOT, p2), 'w', encoding='utf-8', newline='').write(t2[:end] + add + '\n' + t2[end:])
    print("OK   OPTIMIZATION_LOG r92 表补了 BUFIO 用量一行")
else:
    print("SKIP OPTIMIZATION_LOG 找不到那行锚点（不改）")

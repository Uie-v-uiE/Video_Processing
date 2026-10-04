#!/usr/bin/env python3
"""build/evidence/r119_merge_sources.py — 把各目录的 `_proposed-sources.md` 合并进 `skill/_meta/sources.md`

为什么要脚本而不是手抄：手抄一次就会漂（这条规矩本身在 `skill/README.md` 的索引一致性声明里）。
幂等：只在 `BEGIN/END MERGED PROPOSED SOURCES` 标记之间重写，标记之外的正文一个字都不动。
三态：一个 `_proposed-sources.md` 都没有 ⇒ 打印 NOT_MEASURED 并以 2 退出（不许"没有东西可合并"被念成通过）。

跑法（仓库根）：python build/evidence/r119_merge_sources.py [--check]
退出码：0=写入且行数>0 1=有异常 2=NOT_MEASURED（找不到任何台账）3=前置不满足（sources.md 不在）
"""
import glob
import io
import os
import re
import sys

BEG = '<!-- BEGIN MERGED PROPOSED SOURCES -->'
END = '<!-- END MERGED PROPOSED SOURCES -->'
TARGET = 'skill/_meta/sources.md'
check = '--check' in sys.argv

if not glob.glob(TARGET):
    print('merge_sources 前置不满足：找不到 %s NOT_MEASURED' % TARGET)
    sys.exit(3)


def is_row(line):
    s = line.strip()
    if not s.startswith('|'):
        return False
    cells = [c.strip() for c in s.strip('|').split('|')]
    if len(cells) < 4:
        return False
    if all(re.fullmatch(r'[-: ]*', c) for c in cells):   # 表头分隔行
        return False
    if '结论一句话' in cells[0] or '来源' in cells[1]:   # 表头
        return False
    return all(cells[:4])                                # 四个字段都不能空


rows, per = [], {}
for path in sorted(glob.glob('skill/*/_proposed-sources.md')):
    txt = io.open(path, encoding='utf-8').read().split('\n')
    keep = [l.strip() for l in txt if is_row(l)]
    per[path] = len(keep)
    rows.extend(keep)

if not rows:
    print('merge_sources 判 0 项 一条可合并的台账都没有 NOT_MEASURED')
    sys.exit(2)

block = '\n'.join([
    BEG, '',
    '下面这张表由 `build/evidence/r119_merge_sources.py` 从各目录的 `_proposed-sources.md` 合并（条数=%d）。' % len(rows),
    '各目录那份原件保留不删——它是撰写者的原始台账；本表只是让 G8 的"外链必须有行"能在一处核对。',
    '',
    '| 结论一句话 | 来源 | 核对日期 | 用在哪个条目 |',
    '| --- | --- | --- | --- |',
    *rows,
    END,
])

t = io.open(TARGET, encoding='utf-8', newline='').read()
i, j = t.find(BEG), t.find(END)
new = (t[:i] + block + t[j + len(END):]) if (i >= 0 and j > i) else (t.rstrip('\n') + '\n\n' + block + '\n')

if check:
    print('merge_sources --check 条数=%d 一致=%s %s' % (len(rows), 'yes' if new == t else 'no',
                                                        'PASS' if new == t else 'FAIL'))
    sys.exit(0 if new == t else 1)

io.open(TARGET, 'w', encoding='utf-8', newline='').write(new)
after = io.open(TARGET, encoding='utf-8').read()
ok = END in after and after.count(BEG) == 1 and len(rows) > 0
print('merge_sources 写入 条数=%d 分布=%s 判 %d 项 %s' % (
    len(rows), {os.path.basename(os.path.dirname(k)): v for k, v in per.items()}, len(rows), 'PASS' if ok else 'FAIL'))
sys.exit(0 if ok else 1)

#!/usr/bin/env python3
# build/r92_rename_evidence.py —— 把 `r92f_*` 这五个证据文件改成会念出用途的名字。
# 为什么要改：导出器把包内名字里的轮次号去掉，`r92f_tx.txt` 就变成 `1_psboot.txt`/`tx.txt`
# 这种以数字开头、看不出是什么的名字——交付包不该长这样。改完 `r92_flash_1_psboot.txt`
# 在包里是 `flash_1_psboot.txt`，与 r90 那一批的形状一致（`flash_…`、`tx.txt`、`health.txt`）。
import io, os, re, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = {
    'r92f_1_psboot.txt': 'r92_flash_1_psboot.txt',
    'r92f_2_program_log.txt': 'r92_flash_program_log.txt',
    'r92f_3_app.txt': 'r92_flash_app.txt',
    'r92f_tx.txt': 'r92_tx.txt',
    'r92f_health.txt': 'r92_health.txt',
}
for old, new in MAP.items():
    a, b = os.path.join(ROOT, 'build', 'evidence', old), os.path.join(ROOT, 'build', 'evidence', new)
    if os.path.exists(a):
        subprocess.run(['git', '-C', ROOT, 'mv', 'build/evidence/' + old, 'build/evidence/' + new], check=False)
        print(f"改名 {old} -> {new}")
    elif os.path.exists(b):
        print(f"已是新名 {new}")
    else:
        print(f"SKIP 两个都不存在：{old}")

DOCS = ['board/ACCEPTANCE.md', 'docs/OPTIMIZATION_LOG.md', 'docs/PERF_REPORT.md', 'docs/log/ISSUES.md',
        'data/metrics.csv', 'build/r92_close_docs.py', 'build/r92_doc_refresh.py', 'build/r92_add_clocktree_row.py']
for p in DOCS:
    fp = os.path.join(ROOT, p)
    if not os.path.exists(fp):
        continue
    t = io.open(fp, encoding='utf-8', newline='').read()
    before = t
    for old, new in MAP.items():
        t = t.replace(old, new)
    if t != before:
        io.open(fp, 'w', encoding='utf-8', newline='').write(t)
        n = sum(before.count(o) for o in MAP)
        print(f"OK   {p}：换了 {n} 处引用")
    else:
        print(f"—    {p}：没有 r92f_ 引用")

left = subprocess.run(['grep', '-rn', 'r92f_', '--include=*.md', '--include=*.csv', '--include=*.py',
                       '.'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
print("树里还剩的 r92f_ 引用：\n" + (left if left else "（无）"))

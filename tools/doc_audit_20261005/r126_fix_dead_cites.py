#!/usr/bin/env python3
# r126 交付树死链收口：把"指到从来没有过的路径"和"指到被剪掉的原件"逐条改成能兑现的说法。
# 规矩与 r124/r125 那几支改口脚本一致：old 串按字面匹配，每条必须命中 1 次；
# 一次改一个文件、写完断言行数只减掉"整行删除"那几条；任何一条不匹配就整批不写。
# 用法：python r126_fix_dead_cites.py check|apply
import io
import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else 'check'
EDITS = [
    ('board/raw-vs-golden.md', [
        ('`board/compare/ddr-stale-15fps-dump.txt`（源自 `data/measured/ddr_dump_20260921_15fps.out.gz`）',
         '`board/compare/ddr-stale-15fps-dump.txt`（原件是那次 15 fps 停流后从板上读回的 DDR 转储，不随包）'),
        ('（仓库里没有示相机/采集卡导出，见 `board/captures/index.md` 第 4 节）',
         '（仓库里没有示相机/采集卡导出；当年放抓图与条件卡的那两层索引从未入库，也不随包）'),
        ('`build/frozen_r23_srcseen/cdc.rpt`（kv 抽取 `endpoints=@5`、`unsafe=@3`）',
         '`build/frozen_r23_srcseen/cdc.rpt`（那一组成套冻结件不随包；kv 抽取 `endpoints=@5`、`unsafe=@3`）'),
    ], [], []),
    ('build/provenance.md', [
        ('见 `build/artifacts/README.md` 对照表 A2/A3',
         '对照表里 A2/A3 那两行，再加上本行下一列那句 `file copy -force`'),
    ], [], []),
    ('report/technical-document.md', [
        ('# FSBL + bit + app → board/flash/BOOT.bin',
         '# FSBL + bit + app → board/flash/BOOT.bin（生成件，不随包）'),
    ], [], []),
    ('report/collaboration/README.md', [], [
        'report/collaboration/metrics.md           # 成本统计：全部现算，附命令与分母',
        'report/collaboration/redaction.md         # 脱敏台账（9 行处置 + 仓库既有命中的移交）',
    ], []),
    ('skills/templates/project-skeleton/templates/skeleton.md', [], [], [
        '`sim/run.sh`',
        '`docs/open-issues.md`',
    ]),
    ('src/host/README.md', [
        ('| `--clip data/inputs/rand64_512x300.rgb565` |',
         '| `--clip data/inputs/rand64_512x300.rgb565`（这两份是生成件，不随包：`node data/generated/gen_inputs.mjs` 现出） |'),
    ], [], []),
]

# 那支 grep 命令的样例里点着两层不存在的目录：命令照抄会报"No such file"，把不存在的那两项去掉。
RAW_OLD = ('A=$(grep -rhoE "data/golden/[A-Za-z0-9_.-]+\\.(png|mem|md)" \\\n'
           '      board/raw-vs-golden.md board/captures/index.md board/compare/index.md \\')
RAW_NEW = ('A=$(grep -rhoE "data/golden/[A-Za-z0-9_.-]+\\.(png|mem|md)" \\\n'
           '      board/raw-vs-golden.md \\')
EDITS[0] = (EDITS[0][0], EDITS[0][1] + [(RAW_OLD, RAW_NEW)], EDITS[0][2], EDITS[0][3])

bad = 0
staged = {}
for f, pairs, drops, wraps in EDITS:
    try:
        t = io.open(f, encoding='utf-8').read()
    except OSError:
        print('MISS 文件不在：%s' % f)
        bad += 1
        continue
    n0 = len(t.split('\n'))
    for old, new in pairs:
        c = t.count(old)
        if c != 1:
            print('BAD  %s 命中 %d 次（期望 1）：%s' % (f, c, old[:56]))
            bad += 1
        else:
            t = t.replace(old, new)
    for d in drops:
        c = t.count('\n' + d) + t.count(d + '\n')
        if t.count(d) != 1:
            print('BAD  %s 待删行命中 %d 次：%s' % (f, t.count(d), d[:56]))
            bad += 1
        else:
            t = t.replace(d + '\n', '')
    for w in wraps:
        if t.count(w) != 1:
            print('BAD  %s 槽位化命中 %d 次：%s' % (f, t.count(w), w[:56]))
            bad += 1
        else:
            t = t.replace(w, '【填入：' + w + '】')
    if len(t.split('\n')) != n0 - len(drops):
        print('BAD  %s 行数变化不符（%d → %d，只许减 %d）' % (f, n0, len(t.split('\n')), len(drops)))
        bad += 1
    staged[f] = t
    print('%-52s 替换=%d 删行=%d 槽位=%d' % (f, len(pairs), len(drops), len(wraps)))

if MODE == 'apply' and bad == 0:
    for f, t in staged.items():
        io.open(f, 'w', encoding='utf-8', newline='').write(t)
print('%s 文件=%d 不命中=%d' % ('APPLY' if MODE == 'apply' else 'CHECK-ONLY', len(EDITS), bad))
sys.exit(1 if bad else 0)

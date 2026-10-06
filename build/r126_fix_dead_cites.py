#!/usr/bin/env python3
# 作用：把交付文档里"指到从来没有过的路径""指到被剪掉的原件"那类死链，逐条改成能兑现的说法。
# 依赖：仓库根目录的本机 python3；只读文件、只改文本，不碰构建产物与硬件。
# 输入：工作树里 EDITS 点名的六份文档（board/raw-vs-golden.md、build/provenance.md、
#       report/technical-document.md、report/collaboration/README.md、
#       skills/templates/project-skeleton/templates/skeleton.md、src/host/README.md）。
# 输出：stdout 每条规则一行 HIT/OKAY/BAD，最后一行 APPLY/CHECK-ONLY 的总账；--apply 时把改后文本写回原文件。
# 关键参数：第一个参数 check（默认，只判不写）或 apply；其余值按 check 处理（不会写盘）。
# 退出码：0 全部命中；1 有不命中或行数不符 ⇒ 整批不落盘。
# 规矩与 r124/r125 那几支改口脚本一致：old 串按字面匹配，每条必须命中 1 次；
# 一次改一个文件、写完断言行数只减掉"整行删除"那几条；任何一条不匹配就整批不写。
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
fired = already = 0
rules = sum(len(p) + len(d) + len(w) for _, p, d, w in EDITS)
for f, pairs, drops, wraps in EDITS:
    try:
        t = io.open(f, encoding='utf-8').read()
    except OSError:
        print('MISS 文件不在：%s' % f)
        bad += 1
        continue
    n0 = len(t.split('\n'))
    # 三种落点都要有：命中→改；已改口→认（否则这支脚本在 apply 之后重跑会满屏 BAD，
    # 看着像"规则丢了"，实际是它自己判不了"改过没有"）；其余→BAD 且整批不写。
    for old, new in pairs:
        # 旧文只数"落在新文之外"的那些：改口常把原句整段包进新句（`X` → `X（生成件，不随包）`），
        # 直接 t.count(old) 在改完之后仍然是 1 —— 那样 re-apply 会把同一个尾巴再叠一遍。
        cn = t.count(new)
        c = t.replace(new, '').count(old)
        if c == 1 and cn == 0:
            t = t.replace(old, new)
            fired += 1
        elif c == 0 and cn == 1:
            already += 1
            print('OKAY %s 这条已改口（新文恰在位 1 次，新文之外读不到旧文）' % f)
        else:
            print('BAD  %s 新文外的旧文 %d 次／新文 %d 次（只准 1/0 或 0/1）：%s' % (f, c, cn, old[:56]))
            bad += 1
    dropped = 0
    for d in drops:
        if t.count(d) == 1:
            t = t.replace(d + '\n', '')
            dropped += 1
            fired += 1
        elif t.count(d) == 0:
            already += 1
            print('OKAY %s 那一行早已删掉' % f)
        else:
            print('BAD  %s 待删行命中 %d 次：%s' % (f, t.count(d), d[:56]))
            bad += 1
    for w in wraps:
        if t.count('【填入：' + w) >= 1:
            already += 1
            print('OKAY %s 那个名字早已包成槽位' % f)
        elif t.count(w) == 1:
            t = t.replace(w, '【填入：' + w + '】')
            fired += 1
        else:
            print('BAD  %s 槽位化命中 %d 次：%s' % (f, t.count(w), w[:56]))
            bad += 1
    if len(t.split('\n')) != n0 - dropped:
        print('BAD  %s 行数变化不符（%d → %d，只准减掉真删的那 %d 行）' % (f, n0, len(t.split('\n')), dropped))
        bad += 1
    staged[f] = t
    print('%-52s 规则：替换 %d／删行 %d／槽位 %d' % (f, len(pairs), len(drops), len(wraps)))

if MODE == 'apply' and bad == 0:
    for f, t in staged.items():
        io.open(f, 'w', encoding='utf-8', newline='').write(t)
print('%s 文件=%d 命中=%d 已改口=%d 不命中=%d 规则=%d' % (
    'APPLY' if MODE == 'apply' else 'CHECK-ONLY', len(EDITS), fired, already, bad, rules))
# 空转地板：每条规则必须落在"命中/已改口/不命中"三格之一；落不满就是这支脚本没在判东西。
if fired + already + bad != rules:
    print('REFUSE 规则 %d 条只判到 %d 条 ⇒ 这条改口波没在判东西' % (rules, fired + already + bad))
    sys.exit(1)
sys.exit(1 if bad else 0)

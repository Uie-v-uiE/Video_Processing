#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
build/r94_d4c_classify.py —— 一次性只读工具（任务 #121 / 账本 #122 那一族欠的分类活）

它做一件事：把 `src/host/doc_currency_check.mjs` 的 D4c「只报数」那一档（脚本里的 `adv` 桶）
逐条取出来，按"为什么不判红"归类。

规矩：
  * **只读**。本文件不写任何盘上文件，只 print；输出重定向由调用者决定。
  * **不改 mjs**。判据条件与 src/host/doc_currency_check.mjs 逐条对齐
    （CITE_ART / CITE_MD / DELIVERY / HAND_EXT / HAND_SKIP_DIRS / HAND_SKIP_PREFIX / SELF / MAPPER）。
  * `re.A`（ASCII）用来让 `\w` 与 JS 一样只认 ASCII —— 否则中文会被 Python 当成 `\w`，
    指路前缀的判定就与 JS 不同源了。
  * 读文件用 `newline=''` + `split('\n')`：JS 的 split('\n') 会把 CRLF 的 `\r` 留在行尾，本脚本照做。
  * 自检行（m / nd / rows / adv）必须与 `node src/host/doc_currency_check.mjs` 同一时刻的打印对上，
    对不上就是本脚本没复现口径，而不是盘上内容"差不多"。
    ⚠ 本脚本自身是 build/ 下的 .py，也在被扫描的那棵树里 ⇒ 它自己让 m 多 1 份。

分类（优先级自上而下，命中即停）：
  ①  来源在追加式日记 `report/log/*.md`：「当时存在、随后删掉」是日记常态，规则上就不许判红。
  ⑤  写方而非引用方：该行是命令/默认值，路径是**工具或脚本自己创建的输出目标**
     （`vivado -log <路径>`、`> <路径>`、`param([string]$Out = '<路径>')`）。#172 已经裁定过这一类
     "属于工具自己创建的文件，不是凭据"。
  ⑥  判据/对照的自测夹具：路径是**故意不存在**的假名（`no_such_*` / `*_nope*`），出现在阴性对照里。
  ②  目标当前在盘上（安全，红不了）。注意 D4c 的实现里 exists() 为真时**直接 continue**，
     连报数桶都不进 ⇒ ② 在「只报数」那 N 条里恒为 0；本脚本另外单独统计"非交付文件里点名且盘上存在"
     的凭据，用来回答"那些指当轮凭据的引用到底安不安全"。
  ③  目标不存在，但按章程**不随提交包**（导出器会剪）：`build/{evidence,frozen,failed}_*`、
     `build/evidence/`、`build/reports/`、`build/isolated_*`、`build/exp_*`、`build/<形状>_probe`、
     `build/rNN_*`、`HARD_DROP_RE` 里的 `sim/{probes,v98run,...}`、带轮次号的 board 记录、
     `.bit/.elf/.xsa/.dcp` 构建产物、`submission/` 复制品 —— 这一类是"要把理由说清"的。
  ④  目标不存在、又不属于以上任何一类 ⇒ **真漏网**，必须单列，一条不许藏。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- 以下常量逐条抄自 src/host/doc_currency_check.mjs ----
HAND_EXT = {'.md', '.mjs', '.sh', '.tcl', '.v', '.c', '.h', '.bat', '.ps1', '.xdc', '.py', '.csv'}
HAND_SKIP_DIRS = {'.git', 'vivado_system', 'vitis', 'xsim.dir', 'sim_work',
                  'node_modules', '.Xil', 'study', 'learn', 'golden', 'build'}
HAND_SKIP_PREFIX = ['build/frozen_', 'build/evidence_', 'build/failed_', 'report/study/']
HOME = ['README.md', 'README.en.md']
SELF = 'src/host/doc_currency_check.mjs'
MAPPER = 'build/make_submission.sh'

ART_EXT = 'txt|rpt|csv|bit|elf|md5|xdc|py|mjs|sh|tcl|v|bat|log|wdb'
CITE_ART = re.compile(r'(?:^|(?<=[^/\w.:-]))(?:build|data|sim|board|skill|docs)/[\w./-]*?[\w-]+\.(?:'
                      + ART_EXT + r')\b', re.A)
CITE_MD = re.compile(r'(?:^|(?<=[^/\w.:-]))(?:report/log|docs|build|src|sim|board|skill)/[\w./-]*?[\w-]+\.md\b', re.A)

# 写方上下文（机械可核）：路径是命令的输出目标，不是"去那儿查"的指路。
RE_LOG_TGT = re.compile(r'(?:^|[^/\w-])-log\s+"?\'?(' + r'(?:build|data|sim|board|skill|docs)/[\w./-]*?[\w-]+\.(?:' + ART_EXT + r'))', re.A)
# `>` 前不能是 `-`（`A -> B` 是叙述里的箭头，不是重定向），也不能是 `<`。
RE_REDIR = re.compile(r'(?<![-\w<>])(?:>>|>)\s*"?\'?(' + r'(?:build|data|sim|board|skill|docs)/[\w./-]*?[\w-]+\.(?:' + ART_EXT + r'))', re.A)
RE_DEFAULT = re.compile(r'=\s*"?\'?' + r'((?:build|data|sim|board|skill|docs)/[\w./-]*?[\w-]+\.(?:' + ART_EXT + r'))"?\'?\s*[\),]', re.A)
# 整行就是一个变量赋值（形如 `TMP=<某临时 tcl>`）：脚本随后 `> "$TMP"` 生成、用完 `rm -f`。
# ⚠ 这里不要把那个路径写成字面量 —— 本文件在被扫描的树里，写了就多一条假条目（已踩过两次）。
RE_ASSIGN = re.compile(r'^\s*[A-Za-z_]\w*=\s*["\']?'
                       r'((?:build|data|sim|board|skill|docs)/[\w./-]*?[\w-]+\.(?:' + ART_EXT + r'))["\']?\s*$', re.A)
RE_FIXTURE = re.compile(r'(^|/)(no_such|nosuch|_?nope)', re.A)
RE_FIXTURE_NAME = re.compile(r'/((?:no_such|nosuch)[\w.-]*|[\w.-]*_nope[\w.]*)', re.A)
# 日记的草稿件：build/rNN_issueNNN_entry.md —— 正文随后逐字并入 report/log/ISSUES.md（已核对 169/172 两份），
# 所以它属"追加式日记"那一族，不属"脚本注释"那一族。
DIARY_DRAFT = re.compile(r'build/r\d+_issue\d+_entry\.md', re.A)

# 章程不随包（导出器逐条剪，见 build/make_submission.sh §2/§3.9b 与 HARD_DROP_RE）
CLASS3 = [
    (re.compile(r'^build/(evidence|frozen|failed)_', re.A),
     '逐轮留档目录 build/{evidence,frozen,failed}_rNN/：导出器 §2 整类剪，不随提交包'),
    (re.compile(r'^build/evidence/', re.A),
     'build/evidence/ 归档目录：导出器 §2 剪（板级件另搬进 board/output/）'),
    (re.compile(r'^build/reports/', re.A),
     'build/reports/：导出器展平生成的目录，且已在 .gitignore ⇒ 仓库里没有是常态'),
    (re.compile(r'^build/(isolated_|exp_|.*_probe)', re.A),
     '探索/隔离/探针目录：导出器 HARD_DROP_RE 按形状剪（过程输出不随包）'),
    (re.compile(r'^build/r\d+_', re.A),
     '带轮次号的逐轮件：导出器剪「build 逐轮过程留档（不随包）」'),
    (re.compile(r'^board/.*r\d+', re.A),
     'board 里带轮次号的记录：导出器剪「board 里带轮次号的记录（不随包）」'),
    (re.compile(r'^sim/(probes|msim|v98run|xtest|tagchk|syntaxchk|v100run2)/', re.A),
     'sim 下的探针/临时运行目录：导出器 HARD_DROP_RE 整类剪'),
    (re.compile(r'.*\.(bit|elf|xsa|dcp)$', re.A),
     '构建产物：导出器一律剪，由板上那一版补回'),
    (re.compile(r'submission/', re.A),
     '复制品目录：不拿工作区的盘判它存在与否（脚本头部写死的那条边界）'),
]


def hand_written(dir_path, out, rel_base=''):
    for name in sorted(os.listdir(dir_path)):
        rel = f'{rel_base}/{name}' if rel_base else name
        if name in HAND_SKIP_DIRS and rel != 'build':
            continue
        if name == 'build':
            hand_written(os.path.join(dir_path, name), out, rel)
            continue
        if any((rel + '/').startswith(p) for p in HAND_SKIP_PREFIX):
            continue
        p = os.path.join(dir_path, name)
        if os.path.isdir(p):
            hand_written(p, out, rel)
        elif os.path.splitext(name)[1].lower() in HAND_EXT:
            out.append(rel)
    return out


def delivery(rel):
    return rel in HOME or rel == 'board/README.md' or bool(re.match(r'report/(?!log/)[\w.-]+\.md$', rel))


def exists(tok):
    return os.path.isfile(os.path.join(ROOT, tok.replace('/', os.sep)))


def write_side(line, tok):
    """该行里这个路径是不是**输出目标**（写方），而不是"去查"的引用。"""
    for rx, why in ((RE_LOG_TGT, '命令行的 `-log <路径>`：Vivado 自己创建的运行日志，不是凭据引用'),
                    (RE_REDIR, 'shell 重定向 `> <路径>`：这一行就是它的生成方'),
                    (RE_DEFAULT, '脚本的参数默认值（`= "<路径>"`）：写方，跑起来才有'),
                    (RE_ASSIGN, '整行是变量赋值：脚本随后 `> "$TMP"` 生成、用完 `rm -f` 删掉'
                                '（roll_isolated.sh:20/28/35 就是这么写的）⇒ 写方，且**设计上就是留不住**')):
        for m in rx.finditer(line):
            if m.group(1) == tok:
                return why
    return None


# 人工复核改判表（**全部打印出来**，不藏在代码里）：机械规则给错了类，逐条读原文之后改判。
# key = (来源文件, 行号, 点名路径)
# ⚠ 那个路径写成两截拼接：本文件也在被扫描的树里，连着的字面量会被 CITE_ART 当成一条指路，
#    于是"只报数"的总数被本工具自己 +1（2026-09-30 复核时adv 127 就是这么来的）。
OVERRIDE = {
    ('src/host/doc_enc_check.mjs', 32, 'build/frozen_r57_remap/MANIFEST.' + 'md5'): (
        4, '人工复核改判 ⇒ ④：目录 build/frozen_r57_remap/ **就在盘上**，只是里面那份叫 MANIFEST.'
           'txt 不叫 MANIFEST.md5 —— 所以"不随提交包"不是它取不到理由，理由是**文件名写错**'),
}


def classify(src, ln, line, tok, on_disk):
    """返回 (类号, 主理由, 备注)。优先级：人工改判表 > ① > ⑤ > ⑥ > ② > ③ > ④。"""
    ov = OVERRIDE.get((src, ln, tok))
    if ov:
        return ov[0], ov[1], ''
    note = ''
    if 'xxx' in tok or 'YYY' in tok:
        note = '〔点名带**占位名** xxx：判据的占位白名单只认 NN / $ / * ⇒ 这是尺子的口径缺口，不是真指路〕'
    p3 = None
    for rx, why in CLASS3:
        if rx.search(tok):
            p3 = why
            break
    if src.startswith('report/log/'):
        return 1, '来源是追加式日记 docs/log/ —— 拿今天的盘判昨天的日记，红的是历史记录本身，规矩不许', note
    if DIARY_DRAFT.match(src):
        return 1, ('来源是日记的**草稿件**（build/rNN_issueNNN_entry.md）：正文已逐字并入 report/log/ISSUES.md'
                   ' —— 同族规矩：日记里"当时存在、随后删掉"不判红'), note
    w = write_side(line, tok)
    if w:
        return 5, w + ('（同时也属 ③：' + p3 + '）' if p3 else ''), note
    if RE_FIXTURE_NAME.search('/' + tok):
        return 6, '路径是**故意不存在**的假名（no_such_/_nope）：阴性对照/自测夹具，不是指路', note
    if on_disk:
        return 2, '目标当前在盘上 ⇒ exists() 为真，脚本连报数都不进（红不了）', note
    if p3:
        return 3, p3, note
    return 4, '目标不存在，且不属于日记 / 写方 / 自测夹具 / 章程不随包任何一类 ⇒ 真漏网', note


def main():
    args = sys.argv[1:]
    show_all = '--all' in args
    only = None
    for a in args:
        if a.startswith('--only'):
            only = a[6:]

    all_files, lines_cache = {}, {}
    for rel in hand_written(ROOT, []):
        try:
            with open(os.path.join(ROOT, rel.replace('/', os.sep)), 'r', encoding='utf-8',
                      errors='replace', newline='') as f:
                all_files[rel] = f.read().split('\n')
        except OSError:
            continue

    rows, adv, art_all = [], [], []
    for rel, lines in all_files.items():
        if rel in (SELF, MAPPER):
            continue
        hard = delivery(rel)
        for i, line in enumerate(lines):
            for m in CITE_MD.finditer(line):
                tok = m.group(0)
                if 'NN' in tok or '$' in tok:
                    continue
                if exists(tok):
                    continue
                (rows if hard else adv).append((rel, i + 1, tok, line, 'D4a'))
            for m in CITE_ART.finditer(line):
                tok = m.group(0)
                if 'NN' in tok or '$' in tok or '*' in tok:
                    continue
                on = exists(tok)
                art_all.append((rel, i + 1, tok, on, hard, line))
                if on:
                    continue
                (rows if hard else adv).append((rel, i + 1, tok, line, 'D4c'))

    nd = sum(1 for r in all_files if delivery(r))
    n4a = sum(1 for r in adv if r[4] == 'D4a')
    n4c = sum(1 for r in adv if r[4] == 'D4c')
    on_disk_soft = [a for a in art_all if a[3] and not a[4]]

    print('# 复现口径自检（要和 node src/host/doc_currency_check.mjs 同一时刻的打印对上）')
    print(f'  手写文件 m = {len(all_files)}   交付文档 nd = {nd}   其余（只报数那一档的来源）= {len(all_files) - nd}')
    print(f'  判红 rows = {len(rows)}   只报数 adv = {len(adv)}   （adv 里 D4c {n4c} 条 + D4a {n4a} 条 —— '
          f'mjs 那句"点名凭据 {len(adv)} 条"把两者混在一个数里念）')
    print(f'  CITE_ART 总命中 {len(art_all)}；其中 exists 为真 {sum(1 for a in art_all if a[3])} 条（不进任何桶）')
    print(f'  ② 单独统计：非交付文件里点名且**盘上存在**的凭据 = {len(on_disk_soft)} 条')
    print()

    buckets = {1: [], 2: [], 3: [], 4: [], 5: [], 6: []}
    for rel, ln, tok, line, kind in adv:
        c, why, note = classify(rel, ln, line, tok, False)
        buckets[c].append((rel, ln, tok, kind, (why + ' ' + note).strip(), line))
    # ② 也落进桶里（它不在 adv 里，是单独统计的那批）
    for rel, ln, tok, on, hard, line in on_disk_soft:
        if rel.startswith('report/log/'):
            note = '（来源是日记，目标也在盘上 ⇒ 双保险）'
        elif write_side(line, tok):
            note = '（写方，且当轮已经把它生成出来了）'
        else:
            note = ''
        buckets[2].append((rel, ln, tok, 'D4c',
                           '目标当前在盘上 ⇒ exists() 为真，连报数桶都不进，红不了' + note, line))

    if rows:
        print('## 判红那一档（rows）：交付文档点名的凭据盘上没有 —— 逐条')
        for rel, ln, tok, line, kind in rows:
            print(f'  {rel}:{ln} {kind} → {tok}')
        print()

    titles = {4: '④ 真漏网（必须单列，一条不许藏）',
              5: '⑤ 写方而非引用方（#172 已裁这一类"是工具自己创建的文件，不是凭据"）',
              6: '⑥ 自测夹具/阴性对照里的假路径',
              1: '① 日记里的中间件（规则上不许判红）',
              3: '③ 目标不存在但按章程不随提交包（要说清理由）',
              2: '② 目标当前盘上存在（安全；这批不在"只报数"的 N 条里，单独统计）'}
    print(f'## 「只报数」那一档 adv = {len(adv)} 条的分类计数')
    for c in (1, 2, 3, 4, 5, 6):
        print(f'  类{c} = {len(buckets[c])} 条')
    print(f'  （①+③+④+⑤+⑥ = {len(adv)} 条；② 是另算的那批，不在 adv 里）')
    print()

    for c in (4, 5, 6, 3, 1, 2):
        items = buckets[c]
        print(f'### 类{c} —— {titles[c]}：{len(items)} 条')
        cap = 12 if c == 2 else len(items)
        if not items:
            print('  （0 条）')
        elif show_all or only == str(c):
            for rel, ln, tok, kind, why, line in items[:cap]:
                print(f'  {rel}:{ln}  [{kind}]  → {tok}  → 归类{c}  → {why}')
                print(f'      原文: {line.strip()[:170]}')
            if len(items) > cap:
                print(f'  …另外 {len(items) - cap} 条同型（② 全量按形状统计，见下面的交叉表）')
        else:
            print(f'  （未逐条打印；要全表跑 `--all`。抽样前 3 条：）')
            for rel, ln, tok, kind, why, line in items[:3]:
                print(f'  {rel}:{ln}  [{kind}]  → {tok}  → 归类{c}  → {why}')
        print()

    print('### 类② 的形状统计（盘上存在的那些点名，指到哪一类目录）')
    shape = {}
    for rel, ln, tok, kind, why, line in buckets[2]:
        head = '/'.join(tok.split('/')[:2]) if tok.startswith('build/evidence') or tok.startswith('build/frozen') else tok.split('/')[0] + '/'
        shape[head] = shape.get(head, 0) + 1
    for k in sorted(shape, key=lambda x: -shape[x]):
        print(f'  {k}: {shape[k]} 条')
    print()

    print('### 交叉表：来源顶层目录 × （点名凭据）存在与否')
    tab = {}
    for rel, ln, tok, on, hard, line in art_all:
        key = 'report/log' if rel.startswith('report/log') else rel.split('/')[0]
        tab.setdefault(key, [0, 0, 0])
        tab[key][0 if on else 1] += 1
        tab[key][2] += 1 if delivery(rel) else 0
    for k in sorted(tab):
        print(f'  {k}: 盘上存在 {tab[k][0]} / 盘上没有 {tab[k][1]} / 其中交付文档 {tab[k][2]}')


if __name__ == '__main__':
    main()

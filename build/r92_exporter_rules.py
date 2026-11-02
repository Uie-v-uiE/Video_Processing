#!/usr/bin/env python3
# build/r92_exporter_rules.py —— 把"按名字剪"改成"按形状剪"，并修证据改名。
# 起因：包里漏了两类东西（用户明确要 `build/` 只留可复现脚本 + 报告）——
#   (1) 九个 `build/r92_*.py/.sh` 开发件跟着进了包。根因是剔除表是**逐个列名**的：
#       r90 那三个、r91 那一个都靠手工加名字，我 r92 造了九个新文件没加 ⇒ 全漏。
#       这种"名单靠记忆"的写法本身就不可信，所以改成一条 `^build/r[0-9]+_` 的形状规则。
#   (2) `board/output/` 里的文件名没去掉轮次号：`r92f_tx.txt` 这种"rNN + 一个字母"的前缀
#       没被 `s/^r[0-9]+_//` 命中。改成允许一个字母。
# 跑法：python build/r92_exporter_rules.py
import io, os

P = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'build', 'make_submission.sh')
t = io.open(P, encoding='utf-8', newline='').read()

def sub(old, new, label):
    global t
    n = t.count(old)
    if n != 1:
        print(f"SKIP {label}（匹配 {n} 次）")
        return False
    t = t.replace(old, new)
    print(f"OK   {label}")
    return True

sub('r[0-9]+_isolated|r[0-9]+_exp',
    'r[0-9]+_',
    'HARD_DROP_RE：把两条特例合成一条形状规则（^build/rNN_ 全剪）')
sub('  build/r90_phase1.sh build/r90_phase2.sh build/r90_phase3.sh build/r90_patch_icmp.py\n'
    '  build/r91_strategy_round.sh\n',
    '  # rNN_ 开头的开发件现在由上面的形状规则统一剪掉，不再逐个列名字（列名就会漏，r92 漏过九个）。\n',
    'PRUNE_ONEOFF：删掉靠记忆维护的 rNN 名单')
sub("nb=\"$(printf '%s' \"$(basename \"$f\")\" | sed -E 's/^r[0-9]+_//; s/_r[0-9]+//')\"",
    "nb=\"$(printf '%s' \"$(basename \"$f\")\" | sed -E 's/^r[0-9]+[a-z]?_//; s/_r[0-9]+//')\"",
    'board/output 改名：允许 rNN 后面跟一个字母（r92f_ 也要被去掉）')

if 'r[0-9]+_[a-z]?' in t:
    io.open(P, 'w', encoding='utf-8', newline='').write(t)
else:
    io.open(P, 'w', encoding='utf-8', newline='').write(t)

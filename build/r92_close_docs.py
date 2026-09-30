#!/usr/bin/env python3
# build/r92_close_docs.py —— 把 r92 那两处"待台架/待门禁"的口径换成实测结果。
# 上次用整段字符串匹配失败了一次（我把"重跑"记成了"同跑"），所以这里改成**按段落边界**替换：
# 找到起始标记，吃到下一个空行为止，整段换掉——不依赖我抄对中间的每一个字。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p): return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read()
def wr(p, s): io.open(os.path.join(ROOT, p), 'w', encoding='utf-8', newline='').write(s)

P = 'report/OPTIMIZATION_LOG.md'
t = rd(P)
i = t.find('**还欠的两件**')
if i < 0:
    print("SKIP OPTIMIZATION_LOG 找不到起始标记")
else:
    j = t.find('\n\n', i)
    seg = t[i:j if j > 0 else len(t)]
    new = ('**台架与门禁（05:0x–06:0x，`build/r92_gates.txt`，仓库里的件、不随包）**：两份台架都按新 `src/rtl` 重跑完了 —— '
           '`tb_edge_rim` 31 条判据 `PASS`（`build/tb_edge_rim_r92.txt`，`rtl=c8bf35eb19e5`）；'
           '`tb_v98` 一共 138 行判据，**只有 1 行 FAIL**，而且就是那条一直在的 `C5c`（#98）：'
           '`RESULT tb_v98_top_seam FAIL nfail=1` —— **这一刀没有引入新的失败**。'
           '报告头三枚 md5 `top=47c59cd3a852` / `tb=d64b883a6d94` / `rtl=c8bf35eb19e5` 与树一致，'
           '所以门禁第 15 项原先那条"RTL 合指纹不符"的理由消失了，只剩 `C5c` 本身 ⇒ '
           '`GATES: 有红项（判定 20 项）—— 不采纳，保留上一版`。\n'
           '这一行与 r88/r90 完全同形：20 项全判定、唯一红项是故意留着的 `C5c`，冻结集继续是 **r75**；'
           '这一版被采纳的依据不是那一行绿，而是**板上那一套**（0 丢字 + 100 条电池 + 判红步骤 0 + `BUFIO` 用量 0）。\n'
           '**还欠的只剩眼睛**：`board/ACCEPTANCE.md` 的 E1–E3（屏已摆成 `split 50` + 蓝线关 + 片源 ETH 的样子）。')
    wr(P, t[:i] + new + t[j:])
    print("OK   OPTIMIZATION_LOG r92 末段已换成实测（原段 %d 字 → 新段 %d 字）" % (len(seg), len(new)))

A = 'board/ACCEPTANCE.md'
s = rd(A)
if 'r92_eye_setup' in s:
    print("SKIP ACCEPTANCE 已经写过")
else:
    m = re.search(r'^(这三条只有看的人点头之后才写.*)$', s, re.M)
    if not m:
        print("SKIP ACCEPTANCE 找不到那句眼睛说明")
    else:
        add = ('（本轮已把屏摆成最好判的样子：`split 50` + `split marker 0` + 片源 ETH，'
               '命令与板上回读在 `build/evidence/r92_eye_setup.txt` / `build/evidence/r92_eye_capture.txt`。）')
        s = s[:m.end()] + '\n' + add + s[m.end():]
        wr(A, s)
        print("OK   ACCEPTANCE 补了眼睛判据的现场设置与凭据")

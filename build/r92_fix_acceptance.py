#!/usr/bin/env python3
# 用途：修我自己截断 board/acceptance.md 的那个错
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
# build/r92_fix_acceptance.py —— 修我自己截断 board/acceptance.md 的那个错。
# 根因（写在这里免得下次再犯）：`r92_add_clocktree_row.py` 里插行时写成
#     t = t[:m.end()] + row + '\n'
# 少了 `+ t[m.end():]`，于是**第 9 行之后的整段（肉眼判据表 + 结论）被丢掉**，
# 而且脚本还打印了 OK —— 因为 `re.subn` 那种"改了就是改了"的回报根本不检查长度。
# 所以这个修复版做三件事：从 git 取回完整正文、正确插入、**写完立刻量行数并把尾部打印出来**。
import io, os, subprocess, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'board', 'acceptance.md')

full = subprocess.run(['git', '-C', ROOT, 'show', 'HEAD~2:board/acceptance.md'],
                      capture_output=True, text=True, encoding='utf-8').stdout
if full.count('\n') < 30:
    raise SystemExit("取回的版本也太短，停手别写")
print("从 HEAD~2 取回 %d 行" % (full.count('\n')))

row10 = ('| 10 | 收口只有一棵时钟树（#57 的结构判据，不靠 slack 碰运气） | '
         '`build/clock_util.rpt`：**`BUFIO` 用量 0**（改前那一份是 1），`eth_rxc` 只经一只 `BUFG/O`'
         '（`g2`←`src2`=`IBUF/O @IOB_X1Y28`，fabric 负载 2478）；最差 20 条 hold 的时钟偏斜由 '
         '`build/hold_paths.rpt` 逐条读，实测 0.013~0.349 ns（改前那一条是 1.616 ns） | '
         '`build/clock_util.rpt`、`build/hold_paths.rpt`；改前对照是仓库里的 `build/r88_clock_util.rpt`（rNN 命名的对照件，不随包） |')
m = re.search(r'^\| 9 \|.*$\n', full, re.M)
if not m:
    raise SystemExit("找不到第 9 行")
t = full[:m.end()] + row10 + '\n' + full[m.end():]

# 结论那一行的"9 条"要跟着改；脚注里的"缺行峰值=300"是上一版读数，本轮读到 299
t = t.replace('- 机器判据 9 条全部通过，凭据都在表里点名；', '- 机器判据 10 条全部通过（第 10 条是 #57 的结构判据），凭据都在表里点名；')
t = t.replace('`作废过帧=1`、`缺行峰值=300`', '`作废过帧=1`、`缺行峰值=299`')
eyes = re.search(r'^这三条只有看的人点头之后才写.*$', t, re.M)
if eyes and 'r92_eye_setup' not in t:
    add = ('\n（本轮已把屏摆成最好判的样子：`split 50` + `split marker 0` + 片源 ETH，'
           '命令与板上回读在 `build/evidence/r92_eye_setup.txt` / `build/evidence/r92_eye_capture.txt`。）')
    t = t[:eyes.end()] + add + t[eyes.end():]

io.open(P, 'w', encoding='utf-8', newline='').write(t)
back = io.open(P, encoding='utf-8', newline='').read()
print("写回之后 %d 行（应 ≥ 取回的 37 行）" % back.count('\n'))
print("尾部三行：")
for line in back.rstrip('\n').split('\n')[-3:]:
    print('   ' + line[:88])
print("肉眼节在否：%s / 结论节在否：%s / 第 10 行在否：%s"
      % ('要肉眼确认的' in back, '## 结论' in back, '收口只有一棵时钟树' in back))

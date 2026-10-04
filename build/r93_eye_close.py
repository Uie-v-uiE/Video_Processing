#!/usr/bin/env python3
# build/r93_eye_close.py —— 把 E2 按人说的话记进表，并补一句"两次 A/B 的结论"。
# 为什么这条 A/B 值得留在表里：人先报过"隔一段距离的两条白线"，我用**只改推流节奏**做了对照
# （29.76 → 一条；再复推 25 → 仍一条），**没有复现** ⇒ 那次是切换瞬间的暂态，不记缺陷；
# 但"下一次再看到就说清屏幕高度与是否随缩放档变化"这条排查路径留在表里，省得下次从头猜。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'board', 'acceptance.md')
raw = io.open(P, encoding='utf-8', newline='').read()

m = re.search(r'^\| E2 \|[^\n]*$', raw, re.M)
assert m, "找不到 E2 行"
e2 = ('| E2 | 缩放/旋转时不出现整行错位、画面不出屏 | `zoom 0.5` → `rot auto 1`（`split 50` + 关标记线最好判）'
      '| **过（2026-09-30 06:5x–07:0x，在场的人原话"现在画面正常只有一条"）**：0.50× + 自动旋转下无整行错位、'
      '无左右错开的水平界线；此前他报过一次"隔一段距离的两条白线"，我用**只改推流节奏**做了对照'
      '（29.76 fps 一条、复推 25 fps 仍一条）⇒ **未复现**，判为切换瞬间的暂态，不记缺陷；'
      '下次再看到要说清屏幕高度、以及是否随缩放档变化 | 状态回读 `build/evidence/r93_e2b_capture.txt`、'
      '`build/evidence/r93_ab_state_capture.txt`；台架对应 `C2/C3/C9` 三段 |')
t = raw[:m.start()] + e2 + raw[m.end():]

t = t.replace('**r92 这一轮：E1、E3 由在场的人口头确认（原话"现在都很正常"，2026-09-30 06:2x）；E2 当场切成 0.50× + 旋转，待同一个人看**。',
              '**r92/r93：E1、E3 由在场的人口头确认（原话"现在都很正常"，06:2x）；E2 确认（原话"现在画面正常只有一条"，06:5x–07:0x，'
              '含 0.50× + 自动旋转与 25 / 29.76 两档推流的对照）⇒ 三条眼睛判据这一轮全部由人点头。**')
assert len(t) > len(raw) - 500, ("写短了就是删了", len(raw), len(t))
io.open(P, 'w', encoding='utf-8', newline='').write(t)
back = io.open(P, encoding='utf-8', newline='').read()
print("E2 结果在=%s；三条齐=%s；行数 %d -> %d"
      % ('现在画面正常只有一条' in back, '三条眼睛判据这一轮全部由人点头' in back, raw.count('\n'), back.count('\n')))

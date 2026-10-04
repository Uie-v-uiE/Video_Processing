#!/usr/bin/env python3
# build/r92_eye_record.py —— 把"眼睛判据"的结果按**人说的话**记进验收表。
# 规矩：E1–E3 只有看的人点头之后才写"过"；记他的原话、时间，以及**当时屏上是什么状态**
# （状态用串口回读钉住，不靠记忆）。顺便把这张表加一栏"结果"——原来的四栏里根本没有地方写结论。
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'board', 'acceptance.md')
raw = io.open(P, encoding='utf-8', newline='').read()

head = re.search(r'^\| # \| 看什么 \| 怎么起 \| 看不到时先看哪一格 \|\n\|---\|---\|---\|---\|\n', raw, re.M)
assert head, "找不到眼睛表的表头，停手"
e1 = raw.index('| E1 |')
e3_end = raw.index('\n', raw.index('| E3 |')) + 1
old_block = raw[e1:e3_end]
assert old_block.count('\n') == 3, ("E1~E3 应该是三行", old_block.count('\n'))

S1 = ('当时屏上：`--demo --fps 25` 推流中、`src=1`（PL 拥有 UDP 通路）、`split 50` ⇒ `pos=512/1024 manual`、'
      '`marker=off`、`zsel=4`（1.00×）、`bilin=1`。回读 `build/evidence/r92_eye_capture2.txt`')
new_block = (
 '| E1 | 分割线以左是原画面、以右是处理后的同一帧，两侧几何一致 | 双击 `send_demo.bat`，串口 `split 50`'
 + ' | **过（2026-09-30 06:2x，在场的人原话"现在都很正常"）**：右半的白线与红块和左半对得上 | ' + S1 + ' |\n'
 '| E2 | 缩放/旋转时不出现整行错位、画面不出屏 | `zoom 0.5` → `rot auto 1`（`split 50` + 关标记线最好判）'
 + ' | **待看**：06:3x 已把屏切成 `zsel=2`（0.50×）+ `rot auto 1`（speed 2）、`geom=C0400A00` | 回读 `build/evidence/r92_eye_e2_capture.txt`；台架数到的列/行是 `C2/C3/C9` 三段 |\n'
 '| E3 | 移动白线与红块连续、无撕裂 | `send_demo.bat`（内置测试图每帧都动）'
 + ' | **过（同上，原话"现在都很正常"）** | ' + S1 + ' |\n')

t = raw[:e1] + new_block + raw[e3_end:]
t = t.replace(head.group(0), '| # | 看什么 | 怎么起 | 结果（谁点的头、什么时候） | 看不到时先看哪一格 |\n|---|---|---|---|---|\n')
t = t.replace('这三条只有看的人点头之后才写"过"。本轮结束时 E1–E3 由在场的人口头确认了吗 —— 见下面"结论"。',
              '这三条只有看的人点头之后才写"过"。**r92 这一轮：E1、E3 由在场的人口头确认（原话"现在都很正常"，2026-09-30 06:2x）；E2 当场切成 0.50× + 旋转，待同一个人看**。'
              '同一时间他还提了一句与判据无关的观感意见（测试图动画"太丑"）——记进任务，不当成红项，也不改动已经验完的那一块位流。')

assert len(t) > len(raw) - 400, ("写回去短得不对劲", len(raw), len(t))
io.open(P, 'w', encoding='utf-8', newline='').write(t)
back = io.open(P, encoding='utf-8', newline='').read()
print("OK 行数 %d -> %d；E1/E2/E3 栏位齐=%s；结论句在=%s"
      % (raw.count('\n'), back.count('\n'), back.count('| 过（2026-09-30') + back.count('| **过（'),
         'E1、E3 由在场的人口头确认' in back))
print("每行列数（应都是 5）：", [len(l.split(' | ')) for l in back.split('\n') if l.startswith('| E')])

#!/usr/bin/env python3
# build/r93_fps_caliber.py —— 把 OSD `FPS:` 这一格的**口径**在所有对外文档里改对。
# 事实（本轮实测 + RTL）：`pl_video_top.v:893-910` 的 `fps_acc` 累加的是 `vs_tick`（显示时序的场同步），
# 面板 1024×600 @ 50 MHz / 1344×625 ⇒ 59.52 场/秒，所以那一格**永远念 59/60**，与推流帧率无关。
# 文档里两处写着 `FPS:30`（`report/demo_script.md:24`、`board/verify_r87.md:30`）是过期口径 ——
# 数没错、名字错了（ISSUES #157）。改文档这一半现在就做；改 RTL 那一半（B 方案）另起任务，**本轮不动位流**。
import io, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def sub(p, old, new, label):
    fp = os.path.join(ROOT, p)
    t = io.open(fp, encoding='utf-8', newline='').read()
    n = t.count(old)
    if n != 1:
        print(f"SKIP {p:26s} {label}（匹配 {n} 次）")
        return
    assert len(t.replace(old, new)) >= len(t) - 300, ("写短了", p)
    io.open(fp, 'w', encoding='utf-8', newline='').write(t.replace(old, new))
    print(f"OK   {p:26s} {label}")

CAL = ('**这一格数的是显示场同步**（`pl_video_top.v:893-910` 累加 `vs_tick`，面板 1344×625 @ 50 MHz ⇒ 59.5 场/秒），'
       '**不是片源帧率**；源帧率的可信出处是 `data/metrics.csv` 那两行（板上 100 帧滑窗，SD 那一路 29.8–30.0 fps）。'
       '把它改成"写进屏的新帧"是已选定但暂缓动工的 B 方案，见 `report/log/issues.md` #157')

sub('report/demo_script.md',
    'L0 `1024X600 FPS:30 SRC:ETH`',
    f'L0 `1024X600 FPS:59 SRC:ETH`（{CAL}）',
    'DEMO 的 L0 期望值')
sub('board/verify_r87.md',
    '`1024X600 FPS:30 SRC:SD`',
    f'`1024X600 FPS:59 SRC:SD`（`FPS:` 是**显示刷新**计数，59–60 才对，不是片源帧率 —— 见 `report/log/issues.md` #157）',
    'VERIFY 第 2 步期望值')
sub('board/verify_r87.md',
    'FPS 与 `Latency:` 格给的是**可信测量**；不可信时是 `--` 而不是 0 或旧值',
    '`Latency:` 格给的是**可信测量**（不可信时是 `--` 而不是 0 或旧值）；`FPS:` 那格也可信，但它可信的是**显示刷新率**这一件事（≈59.5），别念成片源帧率（#157）',
    'VERIFY 第 31 步口径')
sub('board/HANDS_ON.md',
    '`SRC:` / `FPS:` / `Pipe:` / `Th:` / `Gamma:` / `Rot:` / `Zoom:` / `Split:` / `Latency:` / `Temp:` 各格',
    f'`SRC:` / `FPS:` / `Pipe:` / `Th:` / `Gamma:` / `Rot:` / `Zoom:` / `Split:` / `Latency:` / `Temp:` 各格（`FPS:` 念的是**屏幕每秒扫几遍** ≈59，不是片源帧率，#157）',
    'HANDS_ON 的 OSD 清单')
sub('report/modules.md',
    '| `osd_overlay` | 5 行状态叠加（面板/FPS/Src、',
    '| `osd_overlay` | 5 行状态叠加（面板/FPS/Src——`FPS` 来自显示场同步计数 `pl_video_top.v:893-910`，不是片源帧率，#157；',
    'MODULES 的 osd 行')
sub('report/architecture.md',
    '| MMCM 输入、按键、FPS 计数 |',
    '| MMCM 输入、按键、**显示场**计数（OSD 的 `FPS:` 那一格，#157） |',
    'ARCHITECTURE 的时钟表行')
sub('report/optimization_log.md',
    '（当前 14358 的 ~10 %',
    '（当前 14351 的 ~10 %',
    '顺手清一处"当前 14358"')

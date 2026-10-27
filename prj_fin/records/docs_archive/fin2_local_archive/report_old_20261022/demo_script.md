# 现场演示目录

这页只回答三件事：按顺序敲什么、每一步看到什么算通过、没看到时先查哪一格。根因和历史不在这里，过程记录在 `report/log/`。命令以 `src/ps/main.c` 的解析器为准，没实现过的写法一个都不出现。

## 0. 开机到能演

| 步 | 做什么 | 看见什么算通过 |
|---|---|---|
| 1 | 起 `hw_server`，按顺序走 JTAG：`xsdb.bat board/tcl/ps_jtag_boot.tcl` → `vivado -mode batch -source board/tcl/program_pl.tcl` → `xsdb.bat board/tcl/ps_app_reload.tcl` | 第一条打 `PS BOOT STEP DONE`，第二条打 `PROGRAMMED xc7z020_1`，第三条打 `CON: ok` |
| 2 | 串口 COM6，115200 8N1 | 敲 `stat` 回一行 `[STAT] …`；没有回显先查 COM6 是不是被另一个终端占着 |
| 3 | HDMI 接 1024×600 屏 | 屏上五行 OSD，第一行是 `512X300 FPS:30 SRC:ETH`（片源是 512×300；FPS 是进入屏幕的新帧率，ETH 推流时约 30） |
| 4 | PC 网卡静态 `192.168.1.100/24`，`ping 192.168.1.10` | 0% 丢包；不通就不要开始 |
| 5 | 先敲一次 `stat`，把这一行抄下来 | 最后复位对账要用 |

屏上到底跑的是哪一版，只认 md5：`md5sum board/project/system.bit board/project/ps_app.elf`，与 `board/README.md` 身份表逐个字符对上。

## 1. 三路片源仲裁（约 50 秒）

**前置**：卡上已经有裸帧序列（`node src/host/make_sd_video.mjs --in <mp4> --out E:`），PC 正在推流（`node src/host/video_sender.mjs --test bars --fps 15`），`src auto`。

```text
src auto
play
```

**看见什么算通过**：推流一开始，屏上换成 ETH 那一路，`SRC:` 写 `ETH` 且不带 `*`；拔网线，半秒内回到 `SD` 并继续播；插回，又回到 `ETH`。`*` 表示手动锁住，自适应让位时不该有。

**没看到时**：`play` 回 `play refused` 说明卡没挂载或上不是裸帧序列，先敲 `sd` 看摘要。拔线后画面冻住，说明心跳或看门狗没成立；当场说“这一项今天不演”，不要蒙。

## 2. 缩放与旋转（约 80 秒）

**前置**：`src 0` 切到测试图卡（格子肉眼可数），`split 50`，`split marker 0`。

```text
zoom 1.0
zoom 1.5
zoom 2
rot speed 1
rot auto 1
zoom auto
```

**看见什么算通过**：`zoom 1.0` 到 `zoom 2` 画面连续变大，边缘不糊；八档取最近档，回显把“你写的”和“我用的”并列出来。`rot auto 1` 之后画面开始转，屏上 `Zoom:` 跟着变并带 `(Fit)`；`zoom auto` 交还呼吸，后缀变回 `(Auto)`。

**注意**：旋转打开时倍率会被收进“当前角度刚好装得下”的那一档，所以 1.33、1.50、2.00 三档在旋转态会被拉回拟合档，档号不丢，关掉旋转立刻恢复。这是有意的，不是缩放坏了。要回到 1.00 倍必须写 `zoom 1.0`；`zoom 1` 是开关。

## 3. 六级效果链（约 60 秒）

**前置**：`src 2` 回到 SD 画面，`split 50`，`split marker 0`。

`pipe` 的九个字符里，最左边是 bit0。

```text
pipe 000000000
pipe 000010000
pipe 000001000
th 60
pipe 000001010
pipe show
```

**看见什么算通过**：处理侧从原图变 Sobel 边缘（bit4），再变二值（bit5）；`th 60` 一改，黑白面积立刻变；bit5 加 bit7 是二值加腐蚀，白笔画变细。`pipe show` 按名字念当前生效的算法。

**没看到时**：屏上的 `Pipe:` 不是这串 0/1，而是每级选了第几个算法的显示值；有人问就敲 `pipe show`。bit7 和 bit8 同时为 1 时两个形态学都不做，因为一遍 3×3 窗口做不了开运算和闭运算。

## 4. 同帧 A/B 分割线（约 40 秒）

**前置**：先让处理侧有活干，`pipe 000010000`。

```text
split 50
split marker 0
split show
split 20
split video
split screen
```

**看见什么算通过**：左原图、右处理图，同一帧；`split marker 0` 关掉两像素标记线；`split show` 回 `marker=off`；`split 20` 平移时两侧严格同帧；`split video` 之后旋转，缝跟着画面一起转。

**没看到时**：屏上 `Split:` 与 `show` 不同，说明缝位只有 10 位，`split 100` 会被夹到 1023 并在回显里说出来。越界的 `split px` 必须被拒且不改状态。

## 5. 双线性开/关（约 25 秒）

**前置**：`rot auto 0`，`zoom fit 0`，`zoom 1.5`（非整数倍率才看得出差别）。

```text
bilin off
bilin on
bilin show
```

**看见什么算通过**：1.5 倍下斜边从硬台阶变成软过渡，再切回去。`bilin show` 回显当前状态。

**注意**：用 2.00 倍或 1.00 倍做对照看不出差别是正确行为。整数倍率下每个源像素占整数个显示像素，小数权重为 0，插值按构造退化成最近邻。旋转态下现在也能切出差别。

## 6. Gamma 表（约 30 秒）

**前置**：`split 50`，左边是原图，明暗对比当场成立。

```text
gamma 1.8
gamma auto 100 300 20 2000
gamma manual
gamma show
```

**看见什么算通过**：`gamma 1.8` 立刻压暗中间调；`gamma auto` 在 1.00 到 3.00 之间来回扫，屏上 `Gamma:` 跟着走；`gamma manual` 停在当前值。

**注意**：参数单位认 `1.20` 也认 `120`，但 step 和 ms 必须是整数；`gamma auto 1.0 3.0 0.2 2000` 会被拒绝，拒绝就是没改任何状态。

## 7. 遥测、时延与温度（约 40 秒）

```text
stat
temp
temp th 60
temp
```

**看见什么算通过**：`temp` 回一行驱动读数、屏上三个字符、写进 PL 的值三方一致；`temp th 60` 之后再敲一次 `temp` 才有 `over=1`，因为阈值是比出来的。屏上 `Latency:` 在有可信测量时是毫秒数。

**注意**：屏上那一格是 `--` 时表示“没有可信测量”，不是 0。温度告警只在串口的 `over=` 里，屏上那一格不会变色。

主机侧另开终端：

```bash
python src/host/telemetry_listen.py 12
python src/host/link_selftest.py 192.168.1.10 6
```

遥测每秒一包，打印帧数、包数、坏包、作废、缺行、时延和处理窗完整性。自检会跑干净流、1% 丢包、恢复流三段；故障段作废计数上升、帧率下降，恢复段回到干净流水平。

## 8. 复位对账

任何一幕演砸，或不确定板子被谁动过，先敲 `stat` 看现在在哪，再敲下面这一串，然后回到第 0 步重新开始。

```text
pipe 000000000
th 80
zoom 1.0
zoom auto
zoom fit 0
rot auto 0
rot speed 0
bilin on
split screen
split 50
split marker 1
gamma off
temp th 85
src auto
stat
```

最后一行 `stat` 应与第 0 步抄下来的那行逐字段相等，只允许 `pub=` 不同，因为发布位每 100 ms 翻一次。

## 9. 拔 SD 卡（可选，约 20 秒）

**前置**：卡正在播，`stat` 里 `playing=1`。

拔掉卡，屏上应在半秒内落到 `SRC:TEST`，图卡自己在动；串口出一行说明“片源不可信，画面交回仲裁”。插回后主循环每 2 秒试一次重挂，成功会打印自动重挂；只有连续多次失败才需要手工 `sd remount`。

这一幕只有手上动作，没有串口命令，也不参与首尾 `stat` 对账。

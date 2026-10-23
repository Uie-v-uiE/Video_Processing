# 串口命令手册

这份手册对应板内当前 PS 固件，入口是 `src/ps/main.c` 的 `dispatch()` 和 `help`。命令的最终解释权在固件；如果手册和板上回显不一致，以板上 `help` 和实际回显为准。

串口参数：`115200 8N1`，端口按机器识别（本项目用 `COM6`）。一行一条命令，回车结束；CR、LF、CRLF 都认。动词与参数不区分大小写。一行最多 128 字节、最多切 8 个 token；超长行会被拒绝，不会静默截断后执行。

## 1 命令的三种结局

1. **执行**：写控制位或读计数，回一行带结果的消息。
2. **拒绝**：参数不合法，回一行说明该敲什么，并且一个寄存器都不写。
3. **不认**：动词不在表里，回 `[CMD] 不认: <整行>` 并打印帮助。

没有“收了但什么都不做”的第四种。串口电池 `board/scripts/cmd_battery_v81.txt` 和判据器 `src/host/uart_cmd_check.mjs` 就是按这三条钉的。

## 2 状态、链路与帮助

| 命令 | 作用 | 成功回显 | 说明 |
|---|---|---|---|
| `help` 或 `?` | 打印全部语法 | 多行帮助 | 最可靠的命令表；改固件后先看这里 |
| `stat` 或 `status` | 回读控制字、片源、帧数、效果、几何和 OSD | `[STAT] ctrl thr=... src=... zoom=... bilin=... zsel=... zman=... pub=... sd=... frames=... playing=... sel=... gm=... mode=... geom=... osd=...` | 字段顺序不许改；`pub=` 是每帧翻转的活位，前后对比时排除 |
| `temp` | 读 PS-XADC 温度、VCCINT、阈值和 OSD 编码 | `[TEMP] degC=... raw=... vccint=... th=... over=... sane=... osd=... gpio=...` | `sane=1` 表示读数像真实转换；`osd=--` 表示屏上不可信 |
| `temp th 60` | 改温度告警阈值 | `[TEMP] th=60C` | 0..200 °C；越界退回 85 |
| `link` | 读 PL 链路计数 | `[LINK] drop=... badpkt=... aborts=... rows_max=... stall=...ms gap_last=... gap_min=... gap_max=... gap_sum=... gap_valid=... live=...` | 只读，不改变片源 |
| `link clr` | 清零帧间隔统计 | `[LINK] gap statistics cleared` | 清完再推流，`gap_valid` 要等至少两帧才为 1 |
| `echo 0` / `echo 1` | 关/开板子对输入字符的回显 | `[ECHO] ...` | Vitis 串口终端自带本地回显，保持 `echo 0`；PuTTY 没本地回显，先 `echo 1`。只开一处，否则一个字符显示两遍 |

`link` 的字段含义：

- `drop`：丢弃的字节/包计数；
- `badpkt`：坏包计数；
- `aborts`：未收满/缺行/坏包导致的作废帧数；
- `rows_max`：一次作废里最多缺了多少行；
- `stall`：距最近一次有效帧的停流时间（ms）；
- `gap_last` / `gap_min` / `gap_max` / `gap_sum`：最近、最小、最大、累计帧间隔；
- `gap_valid`：间隔统计是否已由至少两帧校准；
- `live`：链路是否活着。

## 3 片源

| 命令 | 作用 | 成功回显 | 非法/备注 |
|---|---|---|---|
| `src auto` | 交还按键环，自动选源 | `[SRC] 已钉住 自动...` | 长按 KEY1 也可交还 |
| `src 0` | 钉住片内测试图卡（TEST） | `[SRC] 已钉住 TEST ...` | 图卡由 PL 自绘，不占 DDR |
| `src 1` | 钉住网络推流（ETH） | `[SRC] 已钉住 ETH ...` | 画面来自 DDR 乒乓 |
| `src 2` | 钉住 SD 回放并开始播 | `[SRC] 已钉住 SD ...` | 卡不认时先回 `[SD] play refused: <原因>` |
| `src 3` / `src 9` | 不存在这一路 | — | `[SRC] 只认 auto / 0=TEST 图卡 / 1=ETH 网络 / 2=SD 卡回放`，不改状态 |

`src 0/1/2` 与屏上 `SRC:` 的 `TEST/ETH/SD` 同源；`SRC:` 画的是屏幕真的那一路，不是“我希望的那一路”。

## 4 效果链 `pipe`

`pipe <九个 0/1>` 的字符位置就是位号：最左边是 bit0。

| 位 | 算法 | 级 |
|---|---|---|
| 0 | 灰度 | 颜色 |
| 1 | 反色 | 颜色 |
| 2 | 3×3 模糊 | 滤波 |
| 3 | 3×3 锐化 | 滤波 |
| 4 | Sobel 边缘 | 边缘 |
| 5 | 二值化（亮于阈值=白） | 阈值 |
| 6 | 二值化判决反相（仅 bit5=1 有意义） | 阈值 |
| 7 | 腐蚀 | 形态学 |
| 8 | 膨胀 | 形态学 |

- 9 位：执行，回 `[PIPE] sel=... 生效: ...`；
- 5 位：**只翻译、不执行**，回一句“等价的九位是 pipe XXXXXXXXX”；
- 其他长度：拒绝，一个寄存器都不写；
- `pipe show`：打印当前九位对应的级名；
- bit7 与 bit8 同时为 1 时，腐蚀和膨胀都不做；
- 六级链的总延迟固定 15 个像素时钟，开哪些级都不变。

屏上 `Pipe:` 那一格不是这串九位 0/1，而是五位、每位的 0..3 表示“这一级选了第几个算法”。要解释屏上五位，发 `pipe show`。

## 5 缩放、双线性、OSD 与阈值

| 命令 | 作用 | 成功回显 | 非法/备注 |
|---|---|---|---|
| `zoom on` / `zoom off` | 开/关右窗缩放（老写法 `ZOOM1`/`ZOOM0`） | `[CTRL] ... zoom=1/0` | 它也是手动档与呼吸的闸门 |
| `zoom 1.5` | 手动定档，取最近一档 | `[ZOOM] 1.5 → 最近档 1.50x（八档：...）` | 八档：0.25/0.33/0.50/0.75/1.00/1.33/1.50/2.00 |
| `zoom auto` | 回到呼吸自动档 | `[CTRL] zoom_step=... (自动呼吸)` | — |
| `zoom fit [0/1]` | 倍率跟着旋转角度定 | `[ZOOM] fit=1...` | 不带参数等于 1；屏上 Zoom 标 `(Fit)` |
| `bilin on` / `bilin off` | 双线性 / 最近邻 | `[BILIN] bilin=on/off` | 1.00 倍和旋转态下可能看不出差别，这是几何决定的，不是开关坏了 |
| `bilin show` | 念开关状态和对照序列 | 多行 | — |
| `osd on` / `osd off` | 开/关五行叠字 | `[OSD] osd=on/off` | 关掉只影响叠字，画面和计数不变 |
| `osd show` | 念 OSD 状态 | 多行 | — |
| `th 120` | 二值化阈值 | `[CTRL] ... thr=120` | 0..255；越界夹住；老写法 `TH120` |
| `gamma 1.8` | 写 256 项 gamma 曲线 | `[GAMMA] g=1.80 ...` | 1.00..3.00，也收 180；只作用于处理侧 |
| `gamma off` / `gamma on` | 关/开 gamma | `[GAMMA] off/...` | 表保留，来回切很快 |
| `gamma auto 1.0 3.0 0.2 2000` | 自动扫 gamma | `[GAMMA] auto：...` | 100≤lo<hi≤300、0<step≤hi−lo、ms≥200 |
| `gamma manual` / `gamma show` | 停自动 / 念状态 | 多行 | — |

`zoom 1` 是 V7 的开关写法，不是 1.00 倍；要 1.00 倍必须写 `zoom 1.0`。这是最容易在演示里敲错的一条。

## 6 几何：旋转与分割线

| 命令 | 作用 | 成功回显 | 非法/备注 |
|---|---|---|---|
| `rot auto [0/1]` | 自动旋转开关 | `[ROT] auto=1...` / `[ROT] auto=0...` | 不带参数等于 1；开 auto 时若 speed=0 会自动设 2，若未开 fit 会顺带开 fit |
| `rot speed 0..7` | 每帧转几个度 | `[ROT] speed=<n> 度/帧` | 0 = auto 开着但不走；60 fps 下 1≈6 s 一圈，7≈0.9 s 一圈 |
| `rot show` | 念 auto、speed、fit | `[ROT] auto=... speed=... zoom=fit/now` | 不含角度；角度只有屏上 `Rot:` 和 KEY1/KEY2 |
| `rot 45` | 不存在 | — | 绝对角度没有串口入口，用按键 ±1° 带到目标角 |
| `split screen` | 缝在显示列里扫 | `[SPLIT] screen：...` | 屏幕左右 0..1024 |
| `split video` | 缝在画面列里扫，跟着旋转 | `[SPLIT] video：...` | 画面左右 0..512 |
| `split 50` | 缝位百分比 | `[SPLIT] 50% -> pos=.../1024...` | 0..100；不足一列会截断，例如 30% 回显 29% |
| `split px 200` | 缝位绝对列 | `[SPLIT] pos=200 px = ...%` | 上限取当前空间宽 |
| `split auto` / `split manual` | 自动扫 / 停在当前位 | `[SPLIT] auto/manual ...` | — |
| `split swap 0/1` | 左右内容互换 | `[SPLIT] swap=1（只换内容，不换缝位）` | 缝位不变 |
| `split follow 0/1` | 切屏幕列 / 画面列坐标 | `[SPLIT] follow=...` | 与 `screen/video` 同一位 |
| `split marker 0/1` | 显示/隐藏 2 px 蓝线 | `[SPLIT] marker=...` | 1 = 隐藏（这一位是反着写的） |
| `split show` | 念缝位、坐标空间和旗标 | `[SPLIT] pos=...` | — |

`split range` 和 `split speed` 还是构建参数，当前命令层会明确拒绝，不要写进演示脚本。

## 7 SD 卡与回放

| 命令 | 作用 | 成功回显 | 非法/备注 |
|---|---|---|---|
| `sd` | 重新挂载并打摘要 | `[SD] ... frames ... fps ... files ...` | 挂不上回 `[SD] mount failed: <原因>` |
| `sd files` | 列文件 | `[SD] N file(s), ... frame(s) total` + 每行文件 | 卡未挂载时先 `sd` |
| `sd file 1` | 选第 1 个文件 | `[SD] file #1 ... first=...` | 序号从 0 开始；越界拒绝 |
| `sd remount` | 强制重挂 | `[SD] remount ok` | 卡热插拔后用 |
| `play` / `play 1` | 开始播放 | `[SD] playing ...` | 不带参数=开播；`play 0/off/stop` 停止 |
| `stop` | 停止播放 | `[SD] stopped; next frame ...` | — |
| `frame 1200` | 只显示第 1200 帧 | 屏上换帧；状态看 `stat` | 非十进制/负数报错 |
| `autoplay 0/1` | 下一次上电是否自动播放 | `[SD] autoplay on/off (only affects the next boot)` | 只影响下一次上电 |
| `fill` | 写一张四色诊断帧 | `[CTRL]` 两行 + 屏上四色块 | 查通路用，不写 SD |

SD 卡要求 FAT32；插拔后如果 `sd files` 失败，先等 2–3 秒再 `sd remount`。`src 2` 会钉住 SD 并开始播；`src 1` 回网络源。

## 8 老写法

现有工具和旧脚本里还会出现：

| 老写法 | 等价新写法 | 说明 |
|---|---|---|
| `SRC0` / `SRC1` / `SRC2` | `src 0/1/2` | 片源 |
| `ZOOM0` / `ZOOM1` | `zoom off/on` | 开关，不是倍率 |
| `TH80` | `th 80` | 阈值 |
| `BILIN0` / `BILIN1` | `bilin off/on` | 双线性 |
| `OSD0` / `OSD1` | `osd off/on` | 叠字 |
| `FRAME12` | `frame 12` | SD 帧号 |
| `AUTOPLAY0/1` | `autoplay 0/1` | 上电自动播放 |
| `pipe 11000` / `01010` / `pipe 00000` | 无 | 五位老写法只翻译成九位，不写寄存器 |

## 9 OSD 五行

| 行 | 内容 | 读法 |
|---|---|---|
| L0 | `512X300  FPS:30  SRC:ETH` | 片源尺寸、帧率、当前真正显示的源 |
| L1 | `Pipe:11000  Th:80  Gamma:1.8` | 屏上五位效果投影、阈值、gamma |
| L2 | `Rot:45°  Zoom:0.75X(AUTO)` | 角度、缩放档；`(Fit)` 表示倍率跟角度 |
| L3 | `Split:50%  Latency:16MS` | 缝位、PL 内部帧时延 |
| L4 | `Temp:62C` | XADC 温度；`--` 表示还没有可信读数 |

OSD 第一行是片源 512×300，不是面板 1024×600；`Latency` 只覆盖 PL 内部，不是玻璃到玻璃。

## 10 恢复默认与自检

演示或验收前恢复默认：

```text
src 1
zoom 1.0
rot auto 0
rot speed 0
split screen
split 50
split swap 0
split marker 0
osd on
pipe 000010000
stat
```

自动检查：

```bash
node src/host/uart_cmd_check.mjs --port COM6
node src/host/uart_cmd_check.mjs --replay board/uart_script_capture.txt
```

前者按 `board/scripts/cmd_battery_v81.txt` 逐条发并核对回显，最后一条 `STAT` 必须等于第一条（`pub=` 除外）；后者离线判一份已有捕获。没有判定行的“有回显”不算通过。

## 11 常见坑

1. `zoom 1` 是开关，`zoom 1.0` 才是 1.00 倍。
2. `pipe` 的 9 位和屏上 `Pipe:` 五位不是同一种写法；解释屏上内容用 `pipe show`。
3. `split swap` 只换内容，不换缝位；`split marker 1` 是隐藏蓝线。
4. `rot auto 1` 可能顺带把 speed 设为 2、把 zoom 切到 fit；不想要就先 `rot speed 2`/`zoom fit 0`，再开 auto。
5. `link clr` 后 `gap_valid` 需要至少两帧才变 1；停流后 `stall` 会增长，这是正常读数。
6. `temp` 的 `osd=` 和 `gpio=` 应与 `degC=` 对得上；对不上先查 PS→PL 的同步链，不要先改温度阈值。
7. 串口本地回显和板子 `echo` 只能开一处，否则一个字符显示两遍。
8. 一行最多 128 字节、8 个 token；长参数命令一次发一条。

# 04 · PS 侧裸机固件、命令面与上电自启

本卷只谈 PS（两颗 `ps7_cortexa9` 上跑的裸机 app）、它对外提供的两套接口（串口命令面、AXI GPIO 读写面），
以及"断电重上自己就有画面"这条链路。全部结论来自读代码与读留档，本卷没有一次上板动作。
先记一条口径：这份仓库里的数字只有"读到出处"和"不写"两种状态，所以下面每句带数字的话都在括号里点名到行。

## 4.1 一句话定位：视频通路全在 PL，PS 只做四件事

PS 干的是"收文件、送帧、下命令、读回"，一个像素都不加工。数据面的字节没有一处经过 PS：
ETH 那一路由 PL 自己收包、自己当 AXI 主设备写进 DDR；SD 回放那一路才由 PS 的 SD 控制器 DMA 写进另一块
bank，写完只翻一次发布位（来源：`report/ps_vs_pl.md` §2 的职责划分表与紧随其后那句
"数据面的字节没有一处经过 PS"）。固件自己也在开机横幅里说了一遍：
`[BOOT] UDP RX is in PL (RGMII PHY2). PS is control + SD playback.`（来源：`src/ps/main.c:1571`）。

与第 02 卷 ETH 通路的分工落到地址上更清楚：

| 通路 | 谁写 DDR | 写到哪 | 谁搬进显示帧缓存 | 证据 |
|---|---|---|---|---|
| ETH 推流 | **PL** 自己（收包链当 AXI 主设备） | `0x1000_0000` 与 `0x1008_0000` 乒乓两 bank | PL 内部（frame_reasm → BRAM → 显示） | `DDR_BASE = 32'h1000_0000`（`src/rtl/top/system_top.v:139`）；两 bank 见 `src/ps/main.c:19` 文件头注释 |
| SD 回放 | **PS** 的 SD 控制器 DMA（走 PS 自己的 HP0，不经过 PL） | 第三个 bank `0x1010_0000` | PL 在 `frame_start` 拉一次 HP0 复制 | `PS_DDR_BASE = 32'h1010_0000`（`src/rtl/top/system_top.v:144`）；`src/ps/sd_play.c:35` 与 `src/ps/main.c:46` 各有一份同值 `FRAME_ADDR` |

第三个 bank 为什么要分开，`system_top.v:140-143` 那段注释比任何转述都直白：以前 SD 也写 `0x1000_0000`，
于是"SD/FILL 一边写、ETH 一边读写同一块内存，屏幕上就是两个片源打架、闪"；并且它点明
"这个数**必须与固件里的 FRAME_ADDR 一致**：`src/ps/sd_play.c` 与 `src/ps/main.c` 各有一处，改这里不改那边
⇒ 现象是'PS 片源在屏上不动'"。

## 4.2 固件结构

### 4.2.1 文件职责

`src/ps/` 只有四份代码文件加一份说明：

| 文件 | 职责 | 关键锚点 |
|---|---|---|
| `main.c`（1596 行） | 控制面全部：三个 AXI GPIO 基址与位域合成、串口命令解析与派发、gamma 曲线生成、片上温度、PS 心跳 | `main.c:890` 的 `dispatch()`、`:208` 的 `ctrl_write()`、`:1519` 的 `main()` |
| `sd_play.c`（881 行） | 裸机 FAT32 只读 + `XSdPs` 读盘、簇链游标、逐帧 DMA 进 DDR、段表 | `sd_play.c:668` 的 `frame_map()`、`:742` 的 `feed_cur()`、`:846` 的 `sd_tick()` |
| `sd_play.h` | 回放模块对外的入口，含两个"反向通知" | `sd_play.h:58` 的 `ps_publish()`、`:65` 的 `ps_source_lost()` |
| `lscript_ocm.ld` | 链接脚本（名字是历史名，见 4.7.4） | `lscript_ocm.ld:29-33` 的 `MEMORY`、`:49` 的 `ENTRY(_boot)` |
| `README.md` | 重编 ELF 的步骤与 EMIO GPIO 位表 | `src/ps/README.md:16` 起的位表 |

两条边界规矩值得学：回放模块**不许**碰控制字——`sd_play.h:55-58` 写着 `ps_publish()` 的实现在 `main.c`，
理由是"只有它拥有那根 AXI GPIO 控制字，回放模块不该去改别人的位"；反过来 `main.c` 也不直接读卡。

### 4.2.2 启动顺序

`main()` 的次序是固定的（`main.c:1519-1595`）：

1. `Xil_ExceptionInit` → `Xil_DCacheEnable` → `Xil_ICacheEnable` → `Xil_ExceptionEnable`（`:1523-1526`）。
2. 打 `[BOOT] video_pipeline PL-UDP control plane`（`:1528`）。
3. `Xil_Out32(GPIO_TRI, 0x00000000u)` 把 `0x41200000` 那只 GPIO 设成全输出，随后 `ctrl_apply()` 下发第一份控制字（`:1529-1530`）。
4. **elf/bit 配套自检**：往 `0x41220000` 写 `0x1FF`、再写 `0x00780000`，读回来比对；图案故意只放保留段，
   "自检不许顺手把硬件切一下"（`:1532-1550`）。再单独验 gamma 窗口（通道 2，`+0x08`），
   理由是"ch1 活着不代表 ch2 在"（`:1552-1565`）。
5. `xadc_init()`（`:1569`），然后两条 BOOT 横幅，其中一条就是波特率与命令表入口（`:1571-1572`）。
6. `autoplay` 为真则 `sd_mount()` → `sd_status()` → `ctrl_set_src(1)` → `sd_play(1)`（`:1577-1585`），该变量默认值 `1`（`:638`）。
7. 主循环每圈六个调用：`uart_poll(); sd_tick(); sd_recover_tick(); ps_keepalive(); gamma_tick(); temp_poll();`（`:1587-1594`）。

### 4.2.3 内存布局要点

- **代码与数据现在在 DDR**：`lscript_ocm.ld:31` 第一段 `ORIGIN = 0x00200000, LENGTH = 0x00C00000`，
  即 2 MB 起留 12 MB；`:19-20` 的注释明写"第一段的名字还叫 `ps7_ram_0_S_AXI_BASEADDR`（Vitis 生成的段名），
  但 **ORIGIN 已经从 OCM 的 0x0 挪到 DDR 的 0x00200000**"。为什么要挪，见 4.7.4。
- **各模式栈仍在 OCM 顶**：`:32` 的第二段 `ORIGIN = 0xFFFF0000, LENGTH = 0x0000FE00`。
  它与"重编出来的 ELF 入口 `_boot@0x002000cc`、`_vector_table@0x00200000`"那两格读数是一对
  （来源：`report/log/issues.md` 第 409 条"重编产物"那一行）。
- **帧缓冲不进 linker script**，是硬编码地址 `FRAME_ADDR 0x10100000u`（`main.c:46`）。
  一帧的几何是算式不是数组：`FRAME_W 512`、`FRAME_H 300`、`FRAME_BYTES (FRAME_W * FRAME_H * 2)`
  （`main.c:38-40`）。
- PS 侧那份 DMA 目标缓冲也落在 app 镜像附近：冷启动留档的 `[SDRD!]` 三行打的是
  `dst=0x0021EA80` / `dst=0x0021E880`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt`）。

## 4.3 SD 播放通路

### 4.3.1 卡上的形状：预转换的裸帧序列

`src/ps/sd_play.c:9-10` 的文件头把约定写死：

```
VIDEO000.BIN .. VIDEO008.BIN   每个 512 帧 × 307200 B = 153.6 MiB
META.TXT   WIDTH/HEIGHT/FRAME_BYTES/FRAMES/FPS/CHUNK_FRAMES/FILES/SOURCE + FILEi=名字 FRAMES=n BYTES=b
```

一帧多少字节，代码里是算式：`#define FRAME_BYTES (512u * 300u * 2u)`，行尾注释补了等价写法
`/* RGB565 = 307200 B = 600 扇区 */`（`sd_play.c:34`）。挂载时固件会拿 `META.TXT` 的 `FRAME_BYTES`
与自己编译进去的那颗对一次，不等就拒挂，错误串直接告诉你该怎么办：
`"META FRAME_BYTES != compiled FRAME_BYTES (rebuild to match the card)"`（`sd_play.c:333-335`）；
`WIDTH` 不是 512 也拒（`:339`）。

冷启动实测那一份摘要可以当形状对照：

```
[SD] frames=4398 fps=30.000 measured=0.000 files=9 frame=307200B
```

来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt`，这一行由 `sd_play.c:654` 的 `sd_status()` 打出。
`4398 = 512*8 + 302`，与同一份留档接下来列的 9 个文件（8 个 `frames=512` 加 `VIDEO008.BIN frames=302`）逐个对得上。

### 4.3.2 全局帧号 → 文件 / 段内偏移

`frame_map()`（`sd_play.c:668`）把"第几帧"翻成"第几个文件、文件内第几帧"；`open_at()`（`:712`）先
`dir_lookup()` 拿首簇，然后**整簇跳过**——只走 FAT 不读数据（`:723` 的
`skip = (off * FRAME_BYTES) / bpc;`），再用 `ff_blk` 记簇内已用扇区数；`feed_cur()`（`:742`）逐簇读进
`FRAME_ADDR`，因为"簇链可以不连续"。

两条设计理由值得单独记。第一条：PS 不做 `memcpy`——`sd_play.h:5-6` 写得干净，
"PS 全程不做 memcpy：SD 控制器的 DMA 直接落到 PL 要读的那块 DDR，所以只需要一次'发布'动作告诉 PL：
这块内容可以拷了"；而"复制一次"而不是"每帧都复制"是关键，后者会在 PS 写到一半时把半张新图 + 半张旧图
搬上屏（撕裂），原文在 `sd_play.c:15-19`。第二条：`feed_cur()`（调用点 `src/ps/sd_play.c:785`）每搬一段就调一次 `uart_keepalive()`（`:757`），
因为整帧读完才回主循环轮询的话，"autoplay 期间命令要发好几遍才中一次（实测就是这么来的）"——
理由原文在 `:738-740`。

### 4.3.3 `sd_frame_total()` 返回什么，以及那次"冻帧"误判

先看函数本体，它就一行（`sd_play.c:811`）：

```c
u32 sd_frame_total(void) { return mounted ? total_frames : 0u; }
```

`total_frames` 来自 `META.TXT` 的 `FRAMES` 行。所以它返回的是**这部片子一共有多少帧**，挂载成功后就是常量。
同处的 `sd_frame_now()`（`:810`）返回 `nxt`，那才是"演到第几帧"。

误判是这么发生的（来源：`report/log/issues.md` 第 119 条，标题
"`[STAT]` 里那个 `frames=` 是**片子总帧数**，不是'演到第几帧'"）：跑完串口电池要确认"板子确实在播"，
于是连发两次 `stat` 隔 3 秒 —— `frames=4398` 一模一样，而同一份捕获里 `[SD] frame 1863 → 1963` 在涨。
第一反应是"帧号冻住了"（拔卡冻帧的旧账就在脑子里）。量完的结论三条：播放没停；`stat` 那一格喂的正是上面
这个函数；真正会动的 `sd_frame_now()` 没进 `stat`。所以这不是缺陷，是**字段名 inviting misread**：
`sd=%d frames=%d playing=%d` 三连读起来像"有 SD / 演了 N 帧 / 在播"，而第二格其实是"这部片子多长"。

`board/README.md` 把这条钉成了使用口径：同一条 `[STAT]` 里的 `frames=4398` 两份读数也同值，但
"这个同值不说明冻帧"，因为它打的是 `src/ps/sd_play.c:811` 的 `sd_frame_total()`
（由 `src/ps/main.c:1386` 那一行送进格式），"按构造就是静态字段。要判断通路活不活，看能动的字段
（`pub=`、`pc`、`degC`）"。这一格为什么不顺手改掉也有理由：改名会动串口电池按前缀匹配的元组顺序，
往后追加 `sdf_now=` 要重编 ELF、重下应用、重跑电池才算数，而它没被任何判据当"演到第几帧"用
（`report/log/issues.md` 第 119 条末段）。
**结论：读固件输出之前先读打它的那一行，别按英文字面猜语义。**

## 4.4 串口命令面

### 4.4.1 一条命令在固件里走的路

`uart_poll()`（`main.c:1426`）→ `tokenize()`（`:677`）→ `dispatch()`（`:890`）。三个上限常量都是踩过坑之后定的：
`CMD_BUF 128`（`:311`，旧值 48 且**静默截断**）、`RX_IDLE_MS 3000u`（`:319`，半行搁置超 3 s 就丢掉并明说丢了，
因为"残包"会让下一条命令与那半行拼成一句谁都没敲过的东西）、`T_MAX 8`（`:626`，最长那条
`gamma auto 1.0 3.0 0.2 2000` 要 6 个 token，4 会静默吃掉尾部参数）。

收字节与切派发被刻意拆成两半：`rx_fill()` 只搬字节进 `cmd_buf`（`:1478`），长流程里调的是
`uart_keepalive()`（`:1514`），派发只在主循环的 `uart_poll()`。理由写在 `:303-310`：`gamma_set` 一次写
256 项、约 2.6 ms 不回主循环，而"115200 波特下 Zynq 的 RX FIFO 只有 16 字节（≈1.4 ms 的量）"。

语法口径：一行 = 动词 + 至多若干参数，**大小写不敏感**（`ci_eq()` `:640`、`ci_pre()` `:650`，后者是前缀匹配）；
`CR`、`LF`、`CRLF` 都认（`:1483` 把 `\r` 折成 `\n`）。

### 4.4.2 真实清单（从 `dispatch()` 的分支里读，共 20 条派发支）

下表逐条来自 `main.c:890-1394` 的每个 `if (ci_eq/ci_pre)` 分支；"落到哪"那一列指 `ctrl_write()`
（`:208-227`）合成式里的位。

| 命令 | 落到的寄存器/字段 | 合法参数与范围 | 非法参数怎么处理 | 锚点 |
|---|---|---|---|---|
| 裸位串 `01010` / `000000100` | 走 `pipe` 那条口 | 只收 **9 位**或 5 位 | 6/7/8 位一律拒，不补零 | `:896-897`、`parse_bits` `:576-590`（判在 `:587`） |
| `pipe <九位>` / `pipe show` | `gpio_cfg1[8:0]` = `cur_sel` | 9 个 0/1，一位一级 | 给五位时**一个位都不写**，只回等价的九位 | `:899-910`、`apply_pipe_bits` `:478-489` |
| `th <n>` / `TH80` | `gpio_o[15:8]` = `cur_thr` | 0..255，越界**夹住**不是拒 | 跟的不是十进制 ⇒ `[TH] 要跟十进制 0..255`，不改状态 | `:911-920`（夹在 `:916-917`） |
| `src auto/0/1/2` | `gpio_o[16]` + `[24:23]` 模式码 + `[22]` 翻转位 | 只 `auto` 或 0/1/2 | `src 3`/`src 9` ⇒ 念"只认 auto / 0=图卡 1=网络 2=SD"，**不改状态** | `:921-931`、`cmd_src` `:711-736` |
| `zoom on/off/auto` / `zoom <倍率>` / `zoom fit [0|1]` | `gpio_o[17]`；`gpio_cfg1[28:26]`=`cur_zsel`、`[29]`=`cur_zman`、`[31]`=`ZOOM_FIT_BIT` | 倍率 0.01x..4.00x，落进八档取**最近档** | 认不出的 token ⇒ 一条"不认的参数"并列全写法，不改状态 | `:932-982`、`zoom_parse_x100` `:525-539`（上界 `:538`） |
| `bilin on/off/show` | `gpio_o[19]` = `cur_bilin` | 0/1/on/off 或 show | `[BILIN] 只认 on/off（0/1）或 show` | `:983-1004` |
| `osd on/off/show` | `gpio_o[20]`（**反相**）= `cur_osd` | 同上 | 同上形状 | `:1005-1027`、宏 `:57` |
| `rot auto [0|1]` / `rot speed <0..7>` / `rot show` | `gpio_cfg1[9]`、`[12:10]` | speed 只认 0..7 | `rot 45` 这种"设成某个绝对角度"**有意不做**，落通用拒绝 | `:1029-1094`（判在 `:1046`；不做的理由 `:1034-1036`） |
| `split screen/video/<0..100>/px <n>/auto/manual/swap 0\|1/follow 0\|1/marker 0\|1/show` | `gpio_cfg1[22:13]` 缝位 + `[23]auto` `[24]follow` `[25]swap` `[30]marker_off` | `px` 上限随当前空间变：显示列 1024、画面列 512；写进寄存器前夹到 **1023** | `split range 20 80` 这类"语法已收/硬件待接"走同一条拒绝，不改状态 | `:1095-1203`、`split_pos_clamp` `:165-169`、`SPLIT_POS_MAX 1023u` `:125` |
| `gamma off/on/<1.00..3.00>/auto [lo hi [step [ms]]]/manual/show` | `gpio_cfg2`（`0x41220000+0x08`）的 gamma 窗口，经 `gm_w` 影子整字写回 | γ×100，100..300；auto 要求 `100<=lo<hi<=300`、`0<step<=hi-lo`、`ms>=200` | 四个数原样念回；手动指定一个数会**先停 Auto** | `:1204-1252`、auto 的门在 `:329` |
| `frame <n>` / `FRAME12` | 不改控制字（除 `ctrl_set_src(1)`），直接读第 n 帧上屏 | 十进制且 `0..total_frames-1` | 非十进制/负数 ⇒ `[SD] frame 要跟十进制帧号`；越界由 `sd_show()` 返回 -1 | `:1258-1264`、`sd_show` `sd_play.c:790-794` |
| `sd` / `sd files` / `sd file <n>` / `sd remount` | 不写 GPIO | `file n` 的 n 是 `0..段数-1` | 越界与不认的子命令"不改任何状态"，段号范围由回包自己念出来 | `:1265-1320`（范围判 `:1284-1288`） |
| `play` / `play 0/off/stop` | `gpio_o[16]` + 模式码钉 SD | 只认 0/off/stop 与 1/on，裸词=开播 | `[SD] play 只认 0/off/stop 或 1/on（不带参数=开播）` | `:1321-1343`（这条的由来 `:1322-1326`） |
| `stop` | 只停播，**不**改片源位 | — | — | `:1344-1348` |
| `fill` | 直写一张 512×300 诊断帧到 `FRAME_ADDR`，然后 `ctrl_set_src(1)` + `ps_publish()` | — | 这条没有专属回声，屏上四块颜色就是证据 | `cmd_fill` `:692-709` |
| `echo [0|1]` | 会话内开关 `cmd_echo`，不写 GPIO | 0/1；不带参数=念当前值 | `[ECHO] 只认 0 或 1` | `:1350-1362` |
| `autoplay 0|1` | 全局 `autoplay`，**只影响下一次上电** | 0/1 | `[SD] autoplay 要跟 0 或 1` | `:1363-1369`、变量 `:638` |
| `temp` / `temp th <°C>` | 读 PS 侧 XADC；阈值改 `temp_th_deg`；同时刷屏上那一格 | 阈值默认 85 | 读数不可信时另打 `[TEMP!]`，并明说"这一格的数不许写进报告" | `:1370`、`cmd_temp` `:834-888`、默认值 `:748` |
| `stat` / `status` | 纯读 | — | — | `:1371-1391` |
| `help` / `?` | 打印语法 | — | — | `:1392`、`cmd_help` `:1396-1420` |

**谁都不匹配时**：`dispatch()` 返回 -1，`uart_poll()` 打 `[CMD] 不认: <整行>` 然后调一次 `cmd_help()`（`:1466-1469`）。

字段顺序是一条合同，不是排版偏好：`[STAT]` 那行的注释写着"字段顺序不许动：串口电池与
`uart_cmd_check.mjs` 都按 `'[STAT] ctrl thr=…'` 的前缀解析，后加的 sel / mode / geom 只能往后放"（`:1372-1375`），
现在这一整行的形状在 `:1381-1389`。

### 4.4.3 "清零计数"那一条不在串口上

这条容易找错。位域表里确实有一根清零线：`gapclr_sel` 落在 `gpio_o[26]`（`system_top.v:203`，位域表在文件头 `main.c:10`；位为什么挑 26
见 `:61-62`），PL 侧进 125 MHz 域前做 3 级同步（`report/interface-table.md` §C-1 的 `[26]` 那一行）。
但把 `ctrl_write()` 的合成式整个读一遍（`:214-218`）就能确认：**固件从来不为这一位写 1**，串口也没有对应动词。
真正拉它的是 JTAG 侧工具的 `--gapclr`：`const CLR = get('gapclr', false) === true;` 与
`const CLR_BIT = 26;`（来源：`src/host/health_read.mjs:44-45`），做法是拉高 250 ms 再落回原值——
`mwr` 写 `(keepVal | (1<<26))`、`after 250`、再把原值写回去（`clrScript()` `:272-279`）。
为什么要它，`:42-43` 的注释给的是"gap_max 是终身保持的，而两件事会污染它 —— ① 上一次实验留下的长空闲"。

### 4.4.4 切片源那一条为什么要写两次寄存器

`src auto|0|1|2` 是唯一一次改两根线的命令。`ctrl_publish_mode()`（`:508-515`）的做法是**两笔 `Xil_Out32`**：
第一笔只更新模式码、翻转位不动；第二笔只翻 `gpio_o[22]`。注释把风险点得很具体：像素域在翻转沿走到
3 级链末尾那一刻才采码，一次写同时改码和翻位，对面读到的可能是"新码 + 还没认的沿"或"旧码 + 已认的沿"，
症状是"串口回显成功、屏上没变"（`:503-507`）。这与每帧一次的发布位 `ps_publish()`（`:242-251`）是同一课：
先摆数据，再翻选通。另有一条不对称要知道：`src 2` 既钉模式码也真的把回放踢起来（`:727-731`），而 `stop`
只停播不改片源（`:1344-1348`）；`play` 那一支的注释说开播时钉源这一步是"故意保留"的，动它要连电池判据一起改
（`:1325-1326`）。

### 4.4.5 波特率与留档位置

- **115200** 在固件侧只有三处：注释里的刷屏账"`115200` 只有 11.5 KB/s"（`:206`）、RX FIFO 账（`:305`）、
  开机横幅 `uart115200`（`:1572`）。全文没有一行写波特率寄存器——`main.c` 只用
  `XUartPs_IsReceiveData` / `RecvByte` / `SendByte` 配 `STDIN_BASEADDRESS`（`:1480-1500`），
  初始化的事在 BSP 的 stdin 里。
- **控制台规格**：UART0 115200 8N1（`src/ps/README.md:12`；上位机文档第 2 节末句同一说法在 `report/host_guide.md:41`："串口是 COM6 / 115200 / 8N1"）。
- **板上读回不走串口，走 JTAG**（`src/ps/README.md:12` 后半句）。注意这句后半段的指针已经过期：它写的是
  `micro_rd.tcl`，而 `build/tcl/micro_rd.tcl:1` 自己是"只 place+route 帧缓存读口这一条路"的 Vivado 探针，
  不是板级读回工具；真正在用的是 `src/host/health_read.mjs` 与 `board/rdbck.tcl`（见 4.5）。
- **留档位置**：原始串口捕获 `build/evidence/r126_serial_raw.txt`；带判据的验收汇总
  `build/evidence/verify_1006_1944.txt`，其 `:63` 行是
  `RESULT PASS uart_cmd_check  (105 条命令, 98.2 s, 捕获 board/uart_script_capture.txt)`；
  命令清单本体 `board/cmd_battery_v81.txt`（139 行文件，去掉 `#` 注释与空行是 **105** 条，
  用 `grep -c "^[^#]"` 现数）。默认落盘的 `board/uart_script_capture.txt` 被 `.gitignore` 挡着、不入库，
  所以随包复核只认 `build/evidence/` 那一份（来源：`board/README.md` 第 3 节末段）。

## 4.5 AXI GPIO 读回机制

### 4.5.1 两步读法

PL → PS 的状态只有一只 32 位只读 GPIO（`axi_gpio_1`，`0x41210000`，`GPIO_1_tri_i` → `gpio1_i`）。
要看的量远不止 32 位，所以做成"选格 + 取值"两步：先把 lane 号写进**已经在用的** `axi_gpio_0` 的高 5 位
`gpio_o[31:27]`，再从 `0x41210000` 读回那一条 32 位。PL 侧就是两行组合逻辑：
`wire [4:0] lm_lane = gpio_o[31:27];`（`system_top.v:219`）与 `assign gpio1_i = lm_rd;`（`:247`）。
三个基址是钉死并回读校验过的：`build/tcl/build_system_axigpio.tcl:244-246` 的
`axi_gpio_0/S_AXI/Reg 0x41200000` / `axi_gpio_1/… 0x41210000` / `axi_gpio_2/… 0x41220000`，
`:241-242` 给了理由："BSP 不会重新生成 xparameters.h，固件里基址是硬编码的；地址一挪，
现象不是编译失败而是'写了没反应'——最难查的那一类"。

工具脚本的走形（`health_read.mjs` 的 `passScript()`，`:281-292`）：

```
mwr -force 0x41200000 0x<(keep | (n << 27))> 32
after 20
mrd -force 0x41210000 1
... 全部 lane 读完 ...
mwr -force 0x41200000 0x<原值> 32   ← 还原
catch {con}                          ← 只有最后一步才把 A9 放回去
```

三个不许省的细节，理由都在脚本注释里：**先读回 GPIO_0 的原值、只改这 5 位**，最后写回去，
否则 `threshold`/`src_sel` 那些位跟着遭殃（`:10-12`）；读 PL 外设用 `stop` / 末尾 `con`，
而不是 `rst -processor`——后者会停掉正在跑的 ELF（`:257-261`）；**不要在 Tcl 里对 `mrd` 的返回串做
`lindex`/`split`**，实测拿不到第二段、会把整条链读成 0，所以 Tcl 只 `puts "VAL [mrd …]"`，由 Node 侧按
`地址: 数据` 解析（`:265-269`）。

### 4.5.2 为什么是两步而不是一组宽寄存器

`health_read.mjs:9` 的括号里就是答案：**"不加 AXI 从设备，只用两个 GPIO"**。把 32 条计数摊成 32 个 32 位
寄存器要新开地址空间、重排 BD、重写 xparameters 口径；而这只 GPIO 本来就在，只借了当时没人用的 `[31:27]`。
代价也说清了（`:10-12`）：lane 号与效果控制字住在**同一只 32 位寄存器**里，所以读写两侧都必须"读-改-写 + 还原"。

读序本身也是判据的一部分：lane25→26→27→28→29 必须按这个顺序，因为 25 既是"轮次/钳位位"也是**武装位**
（来源：`report/interface-table.md` §D 末段"读序硬要求"，锚点给到 `system_top.v:232-234`）。
**能读回的计数**（§D 那张表）：lane 0-9 是 `link_monitor` 快照（`drop_words`、`bad|err`、`stall|rows`、
`gap_last`、`gap_min|max`、`gap_sum`、`cdc_episodes`、`flags`、`in_pkts`、`in_bytes`）；
lane 10–22 返回哨兵 `32'hDEAD_BEEF`，作用是"让脚本一眼看出自己写错了号"（`system_top.v:244`）；
lane 23 是缩放状态；lane 24-29 是时延那一组；lane 30 是片源仲裁；lane 31 是
`{lm_clk_slow, lm_clk_gone}` 两个心跳位（来源：`report/interface-table.md` §D 的 lane 表）。

### 4.5.3 一份真实读数（照抄）

`build/evidence/r92_health.txt`，头一行与几条 lane：

```
GPIO_0=0x41200000 读回 0xb5000（已还原），GPIO_1=0x41210000
lane  value       含义
   0  0x00000000  drop_words
   1  0x00000001  bad|err
   3  0x00000030  gap_last
   8  0x0002cffb  pkts
   9  0x0f4563c0  bytes
  30  0x00000007  片源仲裁：屏幕归 ETH，eth_live=1 时基可信=1 模式=AUTO 搬运中: PS=0 ETH=0 原因(判决拍)=0b000：无（ETH 想要总线）
  31  0x00000000  eth_rxc 心跳：正常
```

同一支 `mrd` 最原始的形态在 `board/measured/flash_20261006_1936.txt` 末尾，由 `board/rdbck.tcl` 打：

```
GPIO@0x41200000 = 41200000:   000B5000
```

`board/rdbck.tcl` 全文只有四句有效语句（`connect` / `targets -set -filter {name =~ "*APU*"}` / 那一句 `mrd` /
`exit`），把它和上面那行摆在一起，"两步读法"第一步的读数就落地了。`0x000B5000` 还能拿 `ctrl_write()` 的
合成式反推上去：`thr=80` ⇒ `0x50<<8`（`:214`），`src=1` ⇒ `1<<16`，`bilin=1` ⇒ `1<<19`，与冷启动那份回显
`[CTRL] AXI_GPIO=0x000B5000 … src=1 … bilin=1` 是同一个字
（`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt` 的 `[CTRL]` 行）。

## 4.6 上位机工具面

`src/host/` 只放 PC 侧工具，固件在 `src/ps/`，两边由扩展名与目录分家（来源：`src/host/README.md` 开头那节，
含 `build/deliver_spec_check.mjs` 的 C1-2 判法）。

| 类别 | 入口 | 一行用途 | 可复制调用 |
|---|---|---|---|
| 发流 | `src/host/video_sender.mjs` | UDP 推流，只用 Node 内置 `dgram`，自带 8 种对照图案 | `node src/host/video_sender.mjs --ip 192.168.1.10 --port 5001 --fps 15 --pace-mbps 15 --test bars` |
| 发流 | `src/host/udp_push.py` | 零第三方包的 Python 端口，`--pattern edge` 是"换帧原子性"的现场对照 | `python src/host/udp_push.py --pattern edge` |
| 串口 | `board/uart_cmd_script.ps1` | 按清单逐行发，每行前面 echo `>> <行>`，所以捕获能按命令切片 | `powershell board/uart_cmd_script.ps1 -Port COM6 -File board/cmd_battery_v81.txt` |
| 串口 | `board/uart_cap_once.ps1` | 只收不发，抓一段自发输出 | `powershell board/uart_cap_once.ps1 -Port COM6 -Seconds 14 -Out board/uart_capture.txt` |
| 命令校验 | `src/host/uart_cmd_check.mjs` | 逐条对回声 + 该拒的必须拒 + 跑完 `STAT` 必须回到初态 | `node src/host/uart_cmd_check.mjs --file board/cmd_battery_v81.txt --port COM6` |
| 命令校验 | `src/host/demo_cmds.mjs` | 演示脚本里的命令块逐条对固件解析器（**不碰板子**） | `node src/host/demo_cmds.mjs` |
| 读回 | `src/host/health_read.mjs` | JTAG 读健康快照 lane；`--gapclr` 先归零帧间隔统计 | `node src/host/health_read.mjs --gpio0 41200000 --gpio1 41210000 --gapclr` |
| 读回 | `src/host/geom_check.mjs` | 缩放/旋转的几何读数与预期公式对账 | 由 `build/board_verify.sh` 起（`node src/host/geom_check.mjs`） |
| 指标 | `src/host/metrics.mjs` | 两次 `health_read --json` 的差值算成抖动/丢包指标 | `node src/host/metrics.mjs --out board/evidence_r41 --tag r41_clean30` |
| 制片源 | `src/host/make_sd_video.mjs` | 把任意视频转成 SD 播放要的 512×300 RGB565 帧库 | `node src/host/make_sd_video.mjs --in D:/path/a.mp4 --out E: --chunks 512` |
| 编固件 | `build/ps_app.mjs` / `build/build_ps_app.py` | 不用 IDE 把 `src/ps` 编成 ELF 并做成品自检 | `node build/ps_app.mjs` |

出处：三条串口调用行抄自 `report/host_guide.md:110-112`（同行给了 `--dry` 只打印期望不碰串口、`--self`
给期望配反例）；`video_sender.mjs` 的用法头在 `:10-15`，载荷那条约束（`<= 1392 B`、必须 8 的倍数）在 `:9`
与 `:27-29`，默认值 `--ip 192.168.1.10`、`--port 5001`、`--src 192.168.1.100`、`--fps 15`、`--pace-mbps 15`、
`--count 0`、`--test bars` 都在 `:38-45` 的 `get()` 里；`health_read.mjs` 的用法抄自其 `:17-18`；
`metrics.mjs` 那条抄自 `board/README.md` 第 3 节 `evidence_r41` 那一行；`make_sd_video.mjs` 抄自其 `:8`；
`build_ps_app.py` 的五条自检（入口 = `_boot`、`_vector_table` = 第一个 LOAD 的 `VirtAddr`、基址落在
`[0x00100000, 0x3FEF0000]` 且不为 0、`.text` 体积下界、七个符号必须在）抄自 `report/host_guide.md:197`
（这一句原先指 `:152`，2026-10-07 上位机文档重排后那张工具表整体下移，行号跟着换成现量）。
一条本机事实：`python3` 这个别名不存在，`python` 才是 3.12（来源：`src/ps/README.md:44`）。

## 4.7 上电自启（本卷重点）

这一节整条链路都有留档，因此也整条可以证伪。三段失败各有一个独立根因，别把它们混成一件事。

### 4.7.1 `BOOT.bin` 里装了什么

`board/scripts/make_boot_image.sh` 用 `bootgen -arch zynq` 把**三份输入**打进一个镜像（`:5` 依赖、
`:30-32` 默认路径、`:53` 命令）：

```
the_design:
{
   [bootloader] <win>/vitis/platform/zynq_fsbl/build/fsbl.elf
   <win>/build/system.bit
   <win>/build/ps_app.elf
}
```

花括号里逐行一个文件、**不写逗号**——这一段是实测出来的：三种带逗号、带 `[boot]`、带 `configuration` 的写法
都被 bootgen 判语法错（`:14-16`；同一条也记在 `board/measured/flash_qspi_2026-10-05.txt` 的"踩到的三个障碍"第 1 条）。
脚本末尾打印 `BOOT_BYTES` / `BOOT_MD5` / `BIT_MD5` / `APP_MD5` / `FSBL_MD5` 五个数（`:57-63`），
这就是身份四元组的现场来源。

### 4.7.2 三档拨码，ON=0 的约定

实测的拨码表与采样时机：**`JTAG 00 / QSPI 10 / SD 11`，ON=0，只在上电采样**
（来源：`report/log/issues.md` 第 406 条里那句结论，它是"板子无罪"那串证据之一）。
"只在上电采样"的后果有两条：拨完码必须断电重上，热插不生效；也正因如此，**改了拨码这件事没法用软件读回来**
——见 4.9 第 3 条。

### 4.7.3 FSBL 那一行必须带 `[bootloader]`

缺了会怎样：**bootgen 照样报 `Bootimage generated successfully`，但打出来的镜像头 IHT+0x10 / +0x14 / +0x20
（分区表偏移那一组）全是 0**，启动 ROM 找不到分区，什么都不干。现场症状是"冷上电 + QSPI 档 ⇒ 串口零字节、
`DONE` 不亮"（来源：`report/log/issues.md` 第 406 条；`make_boot_image.sh:16-18` 与 `:41-45` 把它写进了脚本注释）。

为什么 bootgen 仍报成功，留档没有解释工具内部，只给了三条并列依据（第 406 条）：① 厂商那份镜像同三个位置是
`0x00001700 / 0x00018008 / 0x00018008`；② `bootgen -bif_help bootloader` 明写该属性
`SUPPORTED zynq, zynqmp, versal`，样例就是 `[bootloader] fsbl.elf`；③ 补上属性后我们这份变成
`0x00001700 / 0x0001f6f4 / 0x0001f6f4`（形状与厂商一致，数值差来自 FSBL 大小），体积 2 416 156 → **2 436 124**
（多的就是头）。**教训不是"bootgen 会说谎"，而是"工具的 exit code 与那句 `generated successfully`
都不是可启动性的证据"**——这与 `build/tcl/README.md:23` 那句"**不要相信退出码**"（`report/06-validation.md:91`
引的就是它，理由是两支历史脚本报错之后仍然 exit 0）是同一族。

### 4.7.4 app 从 OCM 重链到 DDR：原因与做法

`[bootloader]` 修好之后冷上电的**前一半**成立了（`Boot mode is QSPI` → `DMA Done !` → `FPGA Done !`），
但 app 没跑。那一跑的读数（`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt`）：

```
:67  Load Addr: 0x00000000
:68  Exec Addr: 0x000000CC
:75  Handoff Address: 0x00000000
:77  No Execution Address JTAG handoff
```

机制读到了源码那一行：`vitis/platform/zynq_fsbl/image_mover.c` 的 `LoadBootImage()` 里，
"PS 分区 && Load Address < DDR_START && Load Address==0 && 未签名未加密" 直接 `break`，
`ExecAddress` 因此从没被赋值；`main.c` 见 `FsblStartAddr==0` 就转 JTAG handoff 等待。那段注释自己写着
"Loop will break when PS load address zero"（来源：`report/log/issues.md` 第 407 条）。
**为什么这不是"换个写法"能绕的**：同一处记的 `readelf -l` 实测显示 `fsbl.elf` 与 `ps_app.elf` 的第一个 LOAD
都是 `VirtAddr 0x00000000`（OCM 低 192 KB 别名窗），FSBL 若真把 app 装到 0，就是一边执行一边覆盖自己。
⇒ 要"断电自启并且跑 app"，app 必须链进 DDR。

做法只有两处（第 409 条"改的三处"，逐条对到文件）：

1. `lscript_ocm.ld:31` 的第一段 `ORIGIN` 从 `0x00000000` 改成 **`0x00200000`**、`LENGTH = 0x00C00000`；
   `:32` 的 `0xFFFF0000`（各模式栈）不动。基址为什么挑 2 MB：PL 那三个 bank 是 `0x10000000` /
   `0x10080000` / `0x10100000`（第三个跨度 0x4B000），中间这一大片全仓零引用；上界受 `translation_table.S`
   的映射窗限制（只把 `[0x00100000, 0x3FFFFFFF]` 当 cacheable）。
2. 两支 PS 构建脚本 `build/ps_app.mjs` 与 `build/build_ps_app.py` 里那条**旧判据本身就是坑**：它写死
   "`_vector_table` 必须在 0x0，否则 FATAL"，而 FSBL 恰恰对"加载地址为 0"不交接。换成三条等值判据
   （入口 = `_boot`、`_vector_table` = 第一个 LOAD 的 `VirtAddr`、基址落在 `[0x00100000, 0x3FEF0000]`
   且不为 0），并且"取不到 LOAD 行时判'这条没跑，不算通过'"。现在的成品自检就在这两份脚本里，摘要见
   `report/host_guide.md:152`；`ENTRY(_boot)` 这一句本身在 `lscript_ocm.ld:49`，`:38-40` 记着为什么不是
   `ENTRY(_vector_table)`。

留档同时记了文件名债务：`lscript_ocm.ld` 现在链的是 DDR，名字仍是历史名，改名会牵动
`deliver_spec_check.mjs` 的 C12 名单与 `report/notice.md`（第 409 条末段）。

### 4.7.5 冷启动实测结论

判定那一份留档是 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt`（动作：拨到 `1 0` + 断电重上，
窗口 900 s，冷跑第 2 次）。串口从头到尾的关键几行，照抄：

```
:14   Boot mode is QSPI
:17   WINBOND 256M Bits
:19   QSPI is in 4-bit mode
:64   DMA Done !
:66   FPGA Done !
:107  Handoff Address: 0x002000CC
:109  SUCCESSFUL_HANDOFF
:112  [BOOT] video_pipeline PL-UDP control plane
:115  [CFG] axi_gpio_2 @41220000 ok
:117  [TEMP] PS-XADC @F8007100 ok
:120  [SD] dir map ok: 9 files, first clusters within 1946818
:134  [SD] autoplay: playing
```

`Boot mode is QSPI` → `FPGA Done !` → `SUCCESSFUL_HANDOFF` → SD 播放自己起来，四段连成一串，这是本卷里唯一
一条"断电自启成立"的直接证据（来源：`report/log/issues.md` 第 409 条，它给这条判据配的正是上面这份文件）。
交接地址 `0x002000CC` 与重编 ELF 的 `_boot@0x002000cc` 是同一个数（第 409 条"重编产物"那一行），
两边一对就把"链到哪"与"跳到哪"钉死了。自启状态下的机器验收比 JTAG 加载更有说服力，因为测的就是演示时那块板：
`VP_XSDB=… bash build/board_verify.sh --battery --geom --round=r126` ⇒
`RESULT board_verify PASS（判红的步骤：0）`，串口电池 105 条命令 98.2 s 全过（凭据：
`build/evidence/r126_serial_raw.txt`、`build/evidence/verify_1006_1944.txt`）。

同一条留档里还挂着一处**别念成已修好**的尾巴：这一跑播到 frame 2324 报 `frame file not found on card`，
随后自动重挂载打回 `dir map ok: 9 files` 并继续；"是一个文件放完/切下一个"还是"簇映射在第 2324 帧处断"，
那一轮没有判（来源：第 409 条"两条别念成已修好的尾巴"第 ① 条；现象原文在同份留档 `:141-144`）。

## 4.8 身份四元组与它带来的因果

留档里"现在板上这一版"是三枚 md5 定义的。`board/README.md` 第 0 节那张表注明"2026-10-06 19:36 用
`md5sum build/system.bit build/system.xsa build/ps_app.elf` 现量的，同一组数也印在
`board/measured/flash_20261006_1936.txt` 的 IDENTITY 段"：

| 件 | md5 前 12 位 | 出处 |
|---|---|---|
| `build/system.bit` | `cd04907e1369` | 上面那份 IDENTITY 段；同一句也写在 `report/06-validation.md:15` |
| `build/system.xsa` | `934ebdbaa13b` | 同一份 IDENTITY 段 |
| `build/ps_app.elf` | `57fa442a7eaf` | 同一份 IDENTITY 段 |
| `board/flash/BOOT.bin` | `f62b1b8cc3bdc3ca45631c50a0205346`（`BOOT_BYTES 2435868`） | `report/log/issues.md` 第 409 条"重编产物"那一行；`BOOT.bin` 本身不入库，所以这个数只能从留档读 |

历史引文与现役值不同，在这份仓库里是一件要主动交代的事，不是笔误：`report/06-validation.md:89` 抄的是某一次
门禁自己打印的三枚 md5，里面 ELF 是 `d0b07f84a068`（重链之前那一颗）。第 409 条的尾巴 ② 就是这条账——
"ELF 换了，凡是把 `d0b07f84a068` 当**现役** ELF 写的活句子都要改口（`board/README.md` 的身份表、
`report/70-reproduce.md` 的复现期望行），而引用某次门禁身份行/验收行的**历史引文**不动"。
`report/70-reproduce.md:207` 现在那一行给的是 `57fa442a7eaf`，并附了一句为什么换。

**改 `src/ps` 之后的强制因果链**（不是流程偏好，是地址与判据逼出来的）：

```
改 src/ps/*.c → 重编 ELF（node build/ps_app.mjs）
              → ELF 的 md5 变 ⇒ 重打 BOOT.bin（bash board/scripts/make_boot_image.sh）
              → 重新烧写（先在 JTAG 档，见 4.9 第 2 条）
              → 重跑板级校验（VP_XSDB=… bash build/board_verify.sh --battery --geom --round=<这一版>）
```

`src/ps/README.md:41-43` 给这条写了硬话：重编出来那颗与随包那颗不同（两颗的 md5 与 section 大小记在
`build/evidence/1005_ps_app_rebuild.txt`），**没有**替换随包这颗；"板上复验过的行为只绑这一颗；换 ELF 之后
必须再跑一次 `bash build/board_verify.sh` 才谈得上等价"。`board/README.md` 第 0 节末段同样：要用自己重编的件，
"就得重刷 + 跑一次第 2 节末尾那条 `board_verify`"。串口侧还有一条同族：`[STAT]` 的字段顺序是
`uart_cmd_check.mjs` 前缀匹配的合同（`main.c:1372-1375`），所以固件输出**只能往后加字段**，改了顺序即使行为
没错也会判红。

elf 与 bit 的配套另有一条独立证据路：`main.c:1532-1550` 的上电自检往 `0x41220000` 写图案读回来，读不回就大声
报"位流里没有新的 `axi_gpio_2`……elf/bit 不配套"；注释解释了为什么值得开机做——地址是硬编码的，位流里没有这个
从设备时**不会有编译错误**，现象只是"效果命令全都没反应"（`:1533-1535`；`:75-76` 是这条位域表上并列的那句
"这一条把 elf 与 bit 绑死了：旧位流上没有这个从设备"）。

## 4.9 坑清单（每一条都在这份仓库里核到过）

| 坑 | 现场证据（照抄关键半句） | 本卷给的处置 |
|---|---|---|
| 应用 ELF 不能直接进 `PROGRAM.FILES` | `board/tcl/flash_qspi.tcl:84-85`："`PROGRAM.FILES` 只收 `.bit`/`.bin`/`.mcs`（实测 44-518 'Valid file type extension .mcs or .bin'），应用 ELF 不能直接进这一层——它已经在 bootgen 打好的 `BOOT.bin` 里了" | 只喂 `BOOT.bin`；同文件 `:33-40` 记了另一头：cfgmem 与 `program_flash -fsbl` 是"给原料、工具自己打镜像"的接口，拿已打好的镜像再喂一次 = 镜像套镜像、分区表成垃圾 |
| 擦写 QSPI 必须先在 JTAG 档 | `report/log/issues.md` 第 406 条末段：`[Xicom 50-100]` 明说当前档不支持，硬写会"成功"但结果不可信；17:00 那次 x1 写在 QSPI 档做，报的 Erase/Program/Verify 全部作废 | 同处还记了 `program_flash -erase_all` 在这颗片上失败、扇区擦可以 |
| `MODE_PIN_M[2:0]` 不能当拨码证据 | 同一支只读探针 `build/tcl/probe_pl_done_state.tcl` 两档各读一次（`board/measured/pl_config_state_qspimode_2026-10-06.txt`、`..._jtagmode_2026-10-06.txt`）；结论原句"`MODE_PIN_M[2:0]` 两档都读 111，分辨不了拨码"（第 407 条末段） | 能判别的只有 DONE(内部/引脚)、EOS、GWE/GHIGH/GTS_CFG_B、CPU0_STATUS_VALID；QSPI 那份读数是 `BIT08/09/10 = 1 1 1` |
| `FPGA Done !` 不等于 app 在跑；`Verify successful` 不等于能自启 | 前半是第 407 条的形状（`FPGA Done !` 已打出而 `Handoff Address: 0x00000000`）；后半见 `board/measured/flash_qspi_2026-10-05.txt`"硬件回读校验的口径"："至于'断电后能自己起来'，还要把启动模式拨到 QSPI 再上电一次才算量过" | `PROGRAM.VERIFY=1` 只是从 flash 读回逐字节比对 |
| COM6 一次只能被一个程序占着 | `report/host_guide.md:141`："`COM6` 不能同时被别的终端占着，否则 PowerShell 报 `UnauthorizedAccessException`"；`board/README.md` 第 2.3 节补"不是板子坏了"，同处并列"要看寄存器就先停止推流" | 脚本拒绝打开 ≠ 板子故障 |
| 两块板的调试桥被写成同一个 USB 序列号 ⇒ `hw_server` 只出一个 target，表现是"两块板抢端口" | `board/hardware_setup.md:147` 同一条明确"写板载 FT2232 EEPROM（改 USB 序列号）——**不做**"，办法是**一次只插一块板的 USB-C** | 命名对不上，本卷按文件各自念不合并成一句"事实"：`src/ps/README.md:12` 写"FT2232 的第二通道"，`board/hardware_setup.md:47`/`:93` 记的是板载桥 **FTDI FT4232**（通道 A=JTAG、通道 B=UART ⇒ COM6） |
| 写整字探针必须自带还原 + 还原回读 | `build/runs/ledger.md` 第 395 行那条"两处读数错"：写 lane 号用整字 `mwr`，把 bit19（双线性）/bit20（OSD 反相）一起改了；第二份 tcl 才把 `0x000B5000` 写回去并读回确认 | 先读原值、只改 `[31:27]`、读完还原（见 4.5.1） |
| 读一个口之前先证明那个口真的由名义上那个信号驱动 | 同一行 ledger 前半：`0x41210000 = 0x00000000` 被写成"角度=0"，实际 lane0 是健康快照第 0 条，而 `angle` 只声明、只连接、没有读者，综合按 unused 删掉 ⇒ 板上没有机读的角度 | 这条后来进了 `report/commands.md` 的 `rot show` 行："**不含角度**：角度只有屏上 `Rot:` 那一格，固件没有角度读口" |
| `zoom 1` 不是 1.00 倍 | `src/ps/main.c:933-936`："r53 第一次跑电池就是拿 `zoom 1` 当'回到 1.0x'用，结果把呼吸又打开了"；拒绝消息自己印出同一条（`:979-980`） | `zoom 0/1` 沿用 V7 的 `ZOOM0/ZOOM1`，是**开关**；要 1.00 倍写 `zoom 1.0` |
| `pipe` 只收九位，五位不生效 | `apply_pipe_bits` `main.c:478-489`：给五位时"一个位都不写"，只回等价九位；`parse_bits:587` 拒 6/7/8 位 | 屏上 `Pipe:` 那一格是"每一级选了第几个算法"，与那 9 个 0/1 不同源（`print_sel_names:608-609`）；要现状就敲 `pipe show` |
| 不要把 `grep -E` 的词表挂到 `sed` 的 BRE 地址上 | `report/log/issues.md` 第 408 条的最小对照：同一行含"不随包"，`sed -e "/不随包\|本地留档/d"` 剩 1 行（没删）、`sed -E` 剩 0 行 ⇒ BRE 里 `\|` 是字面竖线，那层"同行声明豁免"一直空转 | 不是固件的坑，但是本卷引用的那些"文件在盘上却没被算进检查"的成因，属同一族纪律 |

## 4.10 本卷刻意没写的东西

任务里点名的坑，有两条我只读到历史账、没有改完之后的第一手留档，因此不进 4.9：

- **"现在上电默认是呼吸还是手动 1.00×"**。读到的是决定本身——`main.c:178-186` 那段把上电默认改成"手动 1.00×"
  并给了三条理由（`:186` 是 `static u8  cur_zman = 1;` 的声明行）；但没读到改完之后重跑冷启动、`[STAT] … zman=1`
  落在新 ELF 上的留档，所以不写现行症状。
- **"拔卡 ⇒ 永久冻帧"作为现行行为**。`sd_play.c:773` 起那段注释显示 PL 侧判据已换成活判据（"500 ms 收到过发布
  没有"），且 `ps_source_lost()` 只在读失败那一拍调用（`main.c:273-278`），这条已经改形；我只有代码没有对应的
  新一轮留档，故不作坑。
- **FSBL 那套横幅与 `fsbl.elf` 构建开关的关系**：留档里它是一条待办（"要么在构建前显式加 `-DFSBL_DEBUG_INFO`
  并校验产物里有横幅字符串，要么在文档里写清要改哪一行"，`report/log/issues.md` 第 405 条），不是已验事实。

## 4.11 本卷索引

| 想查 | 直接去 |
|---|---|
| 某个位落在哪只 GPIO | `main.c:1-20`（文件头位表）与 `report/interface-table.md` §C-1/§C-2 |
| 某条命令的拒绝消息原文 | `main.c:890-1394` 的 `dispatch()`，按动词找 `xil_printf` |
| lane 号对应什么量 / 一份读数长什么样 | `report/interface-table.md` §D 与 `build/evidence/r92_health.txt` |
| 三件套现在的 md5、一次完整刷板 | `board/measured/flash_20261006_1936.txt` 的 IDENTITY 段 |
| 断电自启的完整一次上电 | `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt` |
| 自启以前为什么不成立 | `report/log/issues.md` 第 405 / 406 / 407 / 409 四条，按时间顺序读 |
| 打镜像与烧 flash 的命令、前置 | `board/scripts/make_boot_image.sh`（`:39-53`）与 `board/tcl/flash_qspi.tcl`（`:6-14`） |

下一卷（05）谈 PL 侧的效果链与 OSD。本卷提到的 `gpio_cfg1` 位序在那一侧重复了一遍，唯一出处是
`src/rtl/process/proc_pipeline.v` 的文件头（`main.c:17` 与 `:109` 都指回它；这条"唯一出处"的规矩本身也是本卷内容之一）。

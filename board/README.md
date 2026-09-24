# Board bring-up（第四版 V6.x）

相关文档：`report/V6_BOARD_MEASUREMENT.md`（复测数据）、`report/V6_ROOT_CAUSE.md`（根因与判据方法）、
`report/ETH_BRINGUP.md`、`report/BOARD_PINS.md`、`report/AI_COLLABORATION.md`。

## Hardware

- RK-ZYNQ7020-F（`xc7z020clg484-2`），12 V 供电，HDMI **1024×600**，USB-C（JTAG + UART COM6）
- 网线接 **板卡 PL 网口**（PHY2），不是 PS 网口
- PC 有线网卡：静态 `192.168.1.100/24`（板卡 `192.168.1.10:5001`）
- 工具：Vivado / Vitis **2025.2.1**；上位机脚本为 Node.js（无需 python）

## 顺序

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat

%VIVADO% -mode batch -nojournal -log build\build_v6.log -source build\tcl\build_v6.tcl   :: bit + XSA + 报告
%XSDBAT% build\tcl\ps_jtag_boot.tcl  <path\to\ps7_init.tcl>                              :: 起 PS（DDR + FCLK0=100MHz）
%VIVADO% -mode batch -source build\tcl\program_pl.tcl                                     :: 配 PL
%XSDBAT% build\tcl\set_src.tcl                                                            :: GPIO=0x00010000（SRC1、特效关）
ping -n 2 192.168.1.10                                                                    :: 0% 丢包 = PL 网络栈活着
node src\host\video_sender.mjs --fps 15 --test move                                       :: 推流
```

> 交付态可以用 Vitis 里 Run ELF（FSBL）启动 PS；`ps_jtag_boot.tcl` 只是没有 Vitis 工程时的兜底，
> 它不会写 SLCR 里 `FPGA_FCM*` 一类寄存器。两者对本文的判定结论没有影响（判据只依赖 PL 通路），
> 但**性能类结论应以 FSBL 启动为准**。
>
> **2026-09-23 更新（R29）**：跑 PS 应用**不再需要 Vitis/FSBL** —— `build/ps_app.elf` 现在链上了
> 标准启动（`boot.S` 开 CPACR/FPEXC、设 VBAR 与各模式栈、按 BSP 恒等映射打开 MMU），
> 所以纯 JTAG 就能跑：`xsdb build/tcl/ps_app_reload.tcl`（只复位 A9、不动位流），
> 串口应出 `[BOOT]`，实测 `SD` 挂载 + 回放 30.0 fps（判据与坑见 `report/OVERNIGHT_LOG.md` §19、
> ISSUES #42/#44）。上面那条 `set_src.tcl` 在 PS 应用跑起来之后是多余的：应用开机自己写控制字，
> 串口里 `SRC1` / `SRC0` 就是同一件事。`FPGA_FCM*` 那句提醒仍然有效（它只影响性能口径，不影响能不能跑）。

## 不看屏幕的复验（本项目的主要验收手段）

`src/host/measure_v63.mjs` = 推 `frameid` 图案（像素值 = 字号 + 帧号）→ **发完再回读** →
逐 16bit 反解「这个字来自第几帧」→ 打印包内相位丢字率签名。

```bat
node src\host\measure_v63.mjs --fps 15 --count 200
```

判据（V6.3 实测，`data/measured/board_measure_15fps.txt`）：

| 指标 | 修复前 | V6.3 实测 |
|------|--------|-----------|
| 最新帧在自己 bank 的 16bit 命中率 | 42~52% | **100.0%**（15 / 30 / 60 fps 三档） |
| 包内字节偏移 0–48 B / 48 B 之后的丢字率 | 6.7% / 54~64% | **0.0% / 0.0%** |
| u32 内两个 16bit 属于不同帧 | 18.6% | **0 / 76800** |
| 帧号跨度 | 混十几帧 | 相邻两帧（每 bank 恰好一帧） |

已知残留：偶发地，bank 最后一个 64bit 字的高半个 u32（帧的最后 4 字节 = 2 像素）读到 0，
下一帧同地址即被覆盖 ⇒ 肉眼不可见；`sim/tb_v6_ingress_integrity.v +FULL` 不复现，
分析与复现思路见 `report/V6_BOARD_MEASUREMENT.md` §4.1。

## 无人值守的交接判据（#24 的机器那一半，2026-09-24 起）

`src/host/arb_handover_test.mjs` 自己开关推流、同时按 100 ms 采健康 GPIO 的 **lane30**
（`{仲裁看到的模式, row_busy, fill_busy, owner_eth, eth_live, eth_tb_ok}`，八位全在 axi 域），
于是"停流之后多久把屏幕交回 PS"变成一个**毫秒数**，而不是一个人的眼睛。

```bat
%XSDBAT% build	cl\ps_jtag_boot.tcl                                  :: 先起 PS
%VIVADO% -mode batch -source build	cl\program_pl.tcl                :: 再配 PL（顺序不能反，见上面 §顺序）
%XSDBAT% build	cl\ps_app_reload.tcl                                 :: 只复位 A9、跑固件（SD 会自动开播）
node src\hostrb_handover_test.mjs --selftest                       :: 先验判据本身（10 条，不打板子）
node src\hostrb_handover_test.mjs                                  :: 完整一轮：静默→推流→停→再推
```

七条判据与它们各自挡住的失败模式：

| 号 | 判据 | 红了意味着 |
|---|---|---|
| V1 | 静默基线归 PS | 上一轮就没交回（或模式被钉住） |
| V2 | 接管时限（默认 ≤2000 ms） | 链路活了但仲裁不抢总线 |
| V3 | 推流期不抖（稳占段 0 次翻转） | 滞回太短 / 判据在阈值上抖 |
| V4 | **停流后交回，报出实测毫秒** | 就是 #24 那两条眼睛判据的机器版本 |
| V5 | 交回之后不回跳 | 两路抢画面 |
| V6 | 再推流又能接管（可逆） | 必须重配 FPGA / 拔线才能恢复 |
| V0 | 采样密度 | JTAG 会话或板子没在跑（**空样本不许判绿**） |

红了之后脚本会**自己摆证据**（不判红，只定位）：停流段的模式读数、`eth_live` 为 1 的点数、
`eth_tb_ok` 为 0 的点数、两个 busy 的占空比 —— #28 那次就是靠这一步看到
"模式=锁 ETH、判据两位都正常"，从而定位到 ISSUES #52（同步链复位值与源头不一致，上电白送一次长按）。
原始样本与判据一起落 `data/measured/arb_handover_last.json`。

**它证明的是 owner 位的时序，不证明屏幕上有没有画面** —— 下面那几条眼睛判据仍然欠着。

**一条用坏过一整张卡换来的规矩（ISSUES #50/#45）**：*回放跑着的时候，别让调试器按住 A9。*
内核停在一次 SD 传输中间，恢复之后控制器仍留在那次未完成的传输里；连着几次之后
`XSdPs_CfgInitialize` 就再也不能成功（它每个上电周期只成功一次），表现是
`PLAY` 报 `SD read failed`、`STAT` 报 `sd=0`，**要重跑一遍完整 bring-up 才救得回来**
（`ps_jtag_boot → program_pl → ps_app_reload`；**不需要断电** —— 这一句在 09-24 之前写的是"只能断电重插"，
那是我在 #50 里判错的话，已改）。今晚就是这么把卡弄僵的。
所以：
- `arb_handover_test.mjs` 现在测前问一次 `STAT`，在放就先 `STOP`、测完再 `PLAY` 回去
  （串口被别的程序占着就跳过这层保护，并打印为什么跳过）；
- `health_read.mjs` / `metrics.mjs` 也会按住 A9（`stop`…`con`）——**回放期间用它们之前先手敲 `STOP`**，
  读完再 `PLAY`；
- 反过来，`rst -processor`（`ps_app_reload.tcl` 的第一步）打在传输中间，会让**这一次启动**的挂载失败：
  看到"救不回来"先怀疑是自己救的方式不对，别急着怪卡（我在 #50 里就写错过一次这条）。

## SD 回放在串口上该看到什么（#50 结案后的口径，elf `c00b6553` 起）

| 串口行 | 含义 | 不该看到什么 |
|---|---|---|
| `[SD] dir map ok: 9 files, first clusters within 1946818` | 挂载时把**每个**片源文件的首簇都与分区上界核对过一遍（#50 的判据） | `WARN n/9 file(s) have cluster >= ...` ⇒ 目录项/簇号不对，别再往下播 |
| `[SD] autoplay: playing` + 每 100 帧一条 `[SD] frame N: ... 29.x fps` | 自动开播，速率自报（不用任何人敲命令） | 停在 `frame 3584` ⇒ 用的是 #31 或更早的 elf（那条 elf 已标注作废） |
| 播到 4398 后出现 `frame 6 / 106 / 206 …` | **整卡播完并自动回绕**（这是 #50 修复的端到端凭据） | — |
| `[SD] autoplay: mount failed: cluster decode SELF-TEST failed (firmware bug, not the card)` | 固件的 FAT 解码自检没过 ⇒ **拒绝挂载**，与卡无关 | 看到这句不要怀疑卡，怀疑 elf |
| `[SDRD!] lba=… clus=… part_end=… OUT-OF-RANGE` | 读失败时自己报出"想去哪儿、这地址怎么来的、边界在哪" —— 就是它把 #50 从"并发挤的"翻案成"字节序拼错" | 正常回放里不该出现；出现就把这一行整行贴进 issue |

判据的完整推法（三个数字怎么锁死因果链）在 `report/ISSUES.md` #50 结案段，
凭据在 `build/frozen_r32_sdfix/`（`sd_hotspot_diag.txt` 是修复前、`sd_hotspot_fixed.txt` 是修复后、
`sd_selftest_red.txt` 是把字节序改回去后判据确实翻红的反例）。

## 需要肉眼确认的项

| # | 检查 | 期望 |
|---|------|------|
| 1 | SRC0 图卡（`set_src.tcl` 里改 `0x00000000`） | 干净、无横纹，而且**画面自己在动**（这一格原来是静止彩条，R32 起换成 `test_card.v`：移动块 + 帧号二值格；不动就等于通路没在刷新） |
| 2 | `--test move` 动图 | 红块移动处**无拖影**、无固定黑缝 |
| 3 | `--test blocks` + 右屏缩放 | 网格线不再被逐字空洞打断（细线闪烁属缩放算法，非数据问题） |
| 4 | OSD `eth=` / `net_bad=` | 帧计数随推流递增；限速下 `net_bad` 接近 0 |
| 5 | 停流后冻结帧 | 干净（覆盖门限：有空洞就不 commit） |
| 6 | 拔网线 30 s 再插 | 自动恢复推流，不需重下 bit |
| 7 | **（#31/#32 待确认）** 插着线推流 → 停流 | 画面在**零点几秒内**自动交回 SD 播放（不必重配、不必拔线）；#24 在这一条上是红的（判据被退化时钟骗住，见 ISSUES #49） |
| 8 | **（#31/#32 待确认）** 推流过程中 SD 同时在放 | 不出现两路抢画面 / 闪屏；ETH 优先，SD 的发布被挂住等轮次 |
| 9 | **（#31/#32 待确认）** `KEY1` 长按 1.2 s（**r46 起阈值改 0.6 s，且短按改松手才发** —— 见第 13–15 行） | 每按一次四态轮转一格：自动 → 锁 ETH → 锁 PS → 锁图卡 → 回自动；停在**锁图卡**时那张卡必须在动。已知代价：长按会顺带 +1° 旋转（同一根键的短按语义），这条不算 FAIL。机器侧已证 lane30 能读回模式与两位归属（`node src/host/health_read.mjs`），缺的只是"屏上真的换了来源" |
| 10 | **（r45 起）锐化**：串口 `pipe 000100000` | 右窗边缘比旁边一窗**更脆**（同一帧对比，左窗是原图）。开关切换瞬间画面**不许跳行**——跳了就是 ISSUES #54 那半没修好 |
| 11 | **（r45 起）形态学**：`pipe 000001000`（二值化）→ `pipe 000001010`（+腐蚀）→ `pipe 000001001`（+膨胀） | 腐蚀：白色笔画**变细**、孤立白点消失；膨胀：笔画**变粗**、孤立黑点消失。两者都只该改粗细，不该改形状位置（错位=第 10 条同一条判据） |
| 12 | **（r45 提出，r51 才修完）缝对齐 + 缝边不冒条**：SRC0 图卡（自带 32 像素网格）+ 右窗开任意一级，看左右两半**交界处** ①网格横线跨缝是否同一行、②缝两侧有没有一条竖的错色带、③右窗**顶部**有没有一条横的错色带。<br>**r51 之后的期望**：①对齐（顶层把右窗读坐标提前了链子的滞后 4 行）、②③都没有（`tb_v92` 的 C2/C3 从红翻绿：blur/sobel/morph 以前会把上一行末尾漏进本行第 0 列、sobel 连首行也漏）。<br>**为什么还要你眼睛看**：这台架量的是**模块级**，`cy_r` 那条接线在顶层，而**没有任何台架例化 `pl_video_top`** ⇒ 顶层这一段只有读代码 + 看屏幕两道保护。看到任何一条不对，请说是①/②/③哪一种 —— 它们是不同的修法。<br>先说明一处**不是缺陷**的现象，免得白报：右窗**最上面 4 行**每帧会短暂显示上一帧末尾的内容 ——
效果链是行缓存式的，前 4 行本来就没有"上一行"可算（`proc_pipeline` 的 `OFF_LINES=4` 就是这个数），
补偿之后这个带子还在，位置也从帧首挪不走。要看的是**中间**的横线跨缝断不断，不是这 4 行。
另外：中线本身仍有一根**故意画的 2 像素蓝线**（`split_display.v:32,42-43`），那是标记不是缺陷，参数化关它在 V8-4 |
| 13 | **（r46 起，r48 改标签语义）长按一次就要看见结果**：推流中长按 KEY1 一次 | OSD **第一行**的 `Src:` 那一格画的是屏幕上真的那一路（`Src:CARD/PS/ETH`，V8-5 四行格式），末尾一个 `*` = "这是手动锁住的"。所以推流中按一次：`SRC=ETH` → `SRC=PS*`，画面同时从网络切到 SD。**旧版把"意愿"（AUTO/锁ETH/锁PS/锁图卡）当事实画，才会出现"显示 ETH 时写着 AUTO""CARD/PS 看着反了"** —— 歧义已从结构上去掉：机器判据故意造了"仲裁以为占着屏、mux 却选了图卡"这个状态，标签必须跟着屏幕走（`tb_osd_lines`）|
| 14 | **（r46 起）按住过程中的反馈** | 按住约 0.2 s 后 LED1 亮、到 0.6 s 生效时 LED1 翻转并保持；松手后 LED1 不再随短按动。这一条是给"有时长按没反应"的判据：有反馈时用户不需要重按。**2026-09-24 用户已验：按键切换 OK** |
| 15 | **（r46 起，r48 改动过内容）字模完整性** | `Src:CARD`/`Src:PS`/`Src:ETH` 与第二~四行的小写（i p e r c a m n o s t u x y）里不能有字是空白或缺一笔：这次真正用到的新字模是 **U、H 与 `*`**（`*` = 手动锁住标记；`U` 因为不再显示 `AUTO` 而退出这一行，但字模留着给 V8-5 的四行格式）。`tb_osd_lines` 逐像素对位图、`tb_v794_osd_glyph` 另有一份独立的码点→字形金表 |
| 16 | **（r47 起）Gamma**：串口 `gamma 1.8`，再 `gamma off` | 右窗**整幅变亮/变暗**（暗部抬起来最明显），左窗原图不动 ⇒ 左右明暗不一致就是生效了。`gamma off` 之后左右必须**重新完全一致**（这是"关着必须一动不动"的板级对照，机器侧由 `tb_v88_gamma` T1 钉住）。串口同时要能看到 `[GAMMA] g=1.80 mono_bad=0 first=0 last=255` 与 `[CFG] gamma window @41220008 ok` |
| 17 | **（r52 起）四行 OSD 逐格读屏**：推流 + SD + 图卡三种片源下各看一眼 | 期望就是用户给的那四行（机器侧凭据 `tb_osd_lines`）：<br>`FPS:30  Src:ETH  512x300` / `Pipe:11000  Th:80  Gamma:1.8` / `Rot:45°  Zoom:0.75x(Auto)` / `Split:50%  Latency:16ms`。<br>三条要点：① **`Latency:` 必须有数**（不是 `--`）且与 `node src/host/health_read.mjs` 打印的"屏上 Latency=NNms  回读 tot/100000=NN ⇒ 同源一致 ok"是同一个数（r52 起这一条由 lane24 机器核对，`--json` 的 `osd_ms_matches_tot` 必须是 `true`，不是 `null`）—— 眼睛只需要确认屏上不是 `--`、并且屏幕上写的位数与那一行一致；② `Split:` 这一格现在写的是**几何参数**决定的 50 %，缝本身还不可动（V8-4b，ISSUES #62），所以改 `split` 命令不会有任何视觉变化 —— 命令本身会明说"硬件待接"，不会静默收下；③ 老六行的 DROP/STALL **撤下屏了**，这两个数仍然要看得见的请用 `health_read.mjs`（lane0/lane2）。看到任何一格是空白、少一笔、或数字明显不对（比如 FPS=0 而画面在动），请指出是第几行第几格 |

| 18 | **（r53 起）手动缩放档**：串口依次 `zoom 0.75` → 看几秒 → `zoom 2` → `zoom 0.25` → 最后 `zoom auto` | 四件事都要看见：① 下一帧起画面**钉在那一档不再呼吸**（自动呼吸一趟约 4 秒，钉住之后几秒内就该看出它不动）；② 屏上第三行 `Zoom:` 那一格的 **`(Auto)` 后缀消失**（这是本版唯一会消失的后缀，`Split:` 那格本来就没有）；③ `zoom 2` 是**放大** —— 采样窗收进画面内部，四周**不该**有黑边；只有 `zoom 0.25` 才该在四周看到黑边（那是缩小后的空边，不是坏点）；④ `zoom auto` 之后呼吸**从当前倍数继续走**，不该"弹"回 1.0x。②③④ 任何一条不对都算 bug：RTL 侧台架 `tb_v94_zoom_sel` 已经钉过（八档往返 + 交接不瞬移），板上看的是**同一套位真的走到了屏上** —— 这一跳今天**只有眼睛**能验（`status` 那根打包了 `inv_scale` 的观测线没人读；把它变成机器判据排在任务 #45 的 lane23） |

## JTAG 回读的三条硬规则

1. 回读前 `rst -processor`（否则 `mrd` 读到 A9 的 D-Cache），且**不要 `con`**
   （A9 重跑 boot ROM 会把 SD/QSPI 里的旧 bitstream 刷回 PL）；
2. **发完再读**：回读要几秒，边推边读会让每个地址段读到不同时刻的帧；
3. 每次回读都会停住 A9 ⇒ 下一轮复测前重跑 `ps_jtag_boot → program_pl → set_src`。

# design-choices.md · 为什么这么搭：选了什么、放弃了什么、代价记在哪

读完这篇能回答哪三个问题：

1. 眼前这条通路为什么是这样分工的（谁收包、谁写 DDR、谁读 DDR、谁决定屏幕归谁）？换一种分工要付什么？
2. 每个选择能拿出的**数字**在哪个文件里，哪些数字只是注释里的记载、当前报告没有复核过？
3. 哪些"当初想做成的样子"**没有**被实现证明，因而不能当事实念？

## 目录

- 第 1 节 这一篇的口径：三类来源标签与设计意图的处理
- 第 2 节 数据面分工：UDP 收包整个在 PL，PS 只做控制与 SD 回放
- 第 3 节 帧落地路径：DMA 直写 PL 要读的那块 DDR + 每帧一次发布
- 第 4 节 三路片源与仲裁：判据是"活着 + 能不能安全换手"，不是"哪边有数据"
- 第 5 节 输入 512×300、输出 1024×600：×2 展开与"整屏一个视口"
- 第 6 节 行缓存/帧缓存落在 BRAM 还是 LUTRAM（含 2 的幂拆块与"只开一个读口"）
- 第 7 节 异步 FIFO 的格雷码指针与两刀满判据（含一次已回滚的尝试）
- 第 8 节 原图/处理图同屏：分割线逐像素二选一
- 第 9 节 九级效果链可逐像素开关，代价是固定 15 拍与提前 4 行
- 第 10 节 双线性读口：每源像素用满 4 拍、单读口 + 乒乓结果缓冲
- 第 11 节 两条回读路：串口打印与 JTAG lane 读回
- 第 12 节 不做 MIPI、不做第二平台（KU5P）
- 第 13 节 实现策略与 phys_opt 旋钮为什么保持默认
- 第 14 节 "当初想做成的样子"（未被实现证明的条目）
- 第 15 节 小结与下一步
- 第 16 节 自测题

## 第 1 节 这一篇的口径：三类来源标签与设计意图的处理

每条都写成五段：**面对什么问题 → 可选做法（至少两个）→ 本项目选了什么、放弃什么 → 代价 → 证据来源**。
代价一栏里的每个数字都带一个标签，标签决定它能不能被念成事实：

| 标签 | 含义 | 例 |
|---|---|---|
| 【实测】 | 本次真的打开过的工具报告或 `data/metrics.csv` 里的读数 | `build/report/utilization.rpt:106` 的 `95.5 / 140（68.21 %）` |
| 【注释记载】 | RTL / 主机脚本注释里写的数字或事件，本次**没有**在同一轮报告里复核 | `src/rtl/eth/dc_fifo.v:37-39` 的 WNS −0.062 → −0.192 |
| 【报告记录】 | `report/` 下已有文档里的记录（含决策记录与逐轮对照表） | `report/40-optimization.md:69` 的策略两滚读数 |

三条硬规矩（与 `README.md` 第 1 节那套口径纪律同源，这里只补设计取舍特有的两条）：

1. 设计意图**不写成实现事实**。凡是"作者为什么想这么做"而代码与报告都证明不了的，
   集中放在第 14 节，并明写它未被实现证明。
2. 一个机制只有现象、没有原理时，按三段写（表现 / 两种解释 / 怎么区分），不许挑一个说法往下推。
   本篇有 3 处按这个形式写，分别是第 3、6、10 节里标注"未区分"的地方，外加第 13 节那一处。
3. 本篇不复述 `report/ps_vs_pl.md`、`report/04-resources.md`、`report/40-optimization.md` 的表格内容，
   只引它们的具体行 —— 引是为了给"选了哪个"找到当时的记录，不是把表搬过来。

小结 1：读这一篇的正确方式是"先看代价那一栏有没有标签"，没标签的数字就是漏了出处，按红项处理。
小结 2：三类标签里最弱的是【注释记载】—— 它是作者留下的话，不是工具的量。第 6 节会演示怎么发现它与报告不一致。
下一步：第 2 节，数据面分工。

## 第 2 节 数据面分工：UDP 收包整个在 PL，PS 只做控制与 SD 回放

**面对什么问题**：512×300 RGB565、30 fps 的入流要变成屏幕上能扫描的一帧。
中间有三件事：把乱序到达的 UDP 包重组成帧、把它放进 DDR、再让显示侧按随机地址读它。
谁做哪一件，决定 CPU 负载、决定延迟抖动、决定 PL 里要不要一整套协议栈。

**可选做法**（这一节的"可选"不是设想，`report/ps_vs_pl.md` 第 5-14 行的三代表把它们逐条列成了史实）：

| 做法 | 收包/重组在哪 | 显示侧读哪 | PS 角色 |
|---|---|---|---|
| A：PS 收包写 DDR，PL 读 DDR | PS GEM0 + lwIP，中断 + memcpy | PL 读 DDR（HP0） | 收包 + 控制 |
| B：PL 收包写 BRAM，PL 读 BRAM | PL 硬件解析 | PL 读自己那片 BRAM | 仅控制 |
| C：PL 收包经 CDC FIFO 写 DDR，PL 再从 DDR 搬进显示帧缓存 | PL 硬件解析 | 两台 AXI 读回机 | 仅控制 + SD 回放 |

**本项目选了什么、放弃什么**：现役树是 C。代码事实：

- PL 侧收包链 14 只实例（`subsystem-map.md` 第 4 节的表，例化处
  `src/rtl/eth/eth_udp_video_top.v:73`、`:186`、`:197`、`:235`、`:298`、`:354`）；
  写 DDR 的是 `u_saver`（`src/rtl/eth/axi_frame_saver64.v`，例化在 `src/rtl/eth/eth_udp_video_top.v:354`）。
- PS 不碰 UDP 数据面：`src/ps/main.c:2` 的文件头写的是"UDP 视频数据通路仍然整个在 PL"，
  PS 应用做的那两件事在 `src/ps/main.c:1` 与 `src/ps/sd_play.c:12-18`。
- A 那一条（PS 收包写 DDR + PL 读）在当前树里只留下**接口痕迹**，不是现役通路：
  `report/ps_vs_pl.md:6-14` 把它记为 v1 分支。所以严格说法是：本工程选的分工是
  "PL 收包 → DDR → PL 显示"，而"PS 写 DDR + PL 读"这一形状在 v3 里活下来的是**PS 的 SD/FILL 那一路**
  （见第 3 节），不是网口那一路。这一句必须这样写，否则就是把 v1 的方案念成现役方案。
- 放弃 A 的记录理由（`report/ps_vs_pl.md:32-41` 那张对比表）：延迟"中断 + 协议栈，毫秒级抖动"
  对"流水线，确定"；CPU"约 220 包/帧 × 30 fps"。220 这个包数与代码能对上：
  `src/host/one_click_test.py:25` 算的是 `PKTS_PER_FRAME = 221`（307200 B ÷ 1392 B 向上取整）。
- 放弃 B 的记录理由（`report/ps_vs_pl.md:10-12` 与 `report/04-resources.md:34-35`）：
  显示帧缓存要能被两台搬运机按整帧写、又被像素链随机读，容量与端口数都不合身。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 入流负载口径 | 9.2 MB/s（≈74 Mbps） | 【实测-计算】 | `data/metrics.csv:13`（该行自己写明"这是负载口径不是实测带宽"） |
| 板侧自己数的入流结果 | 600 帧一轮 0 丢帧 / 坏帧，实测 30.007 fps | 【实测】 | `data/metrics.csv:22` |
| 收侧缓冲 | 36 bit × 8192 条 = 16 KB，占 BRAM 一部分 | 【实测】 | `src/rtl/eth/eth_udp_video_top.v:295-298`；BRAM 总量见 `build/report/utilization.rpt:106` |
| PL 里要写 ARP/ICMP/CRC | 6 只控制面实例 | 【实测】 | `src/rtl/eth/eth_udp_video_top.v:119`、`:126`、`:140`、`:163`、`:180`、`:206` |
| 调试从"软件日志"换成"计数 + 快照" | 320 bit 健康总线、10 条 lane | 【实测】 | `src/rtl/eth/link_monitor.v:187-196`、`src/host/health_read.mjs:53-64` |
| 端到端时延 | min/avg/max = 20 / 33.34 / 51 ms（一轮 600 帧） | 【实测】 | `data/metrics.csv:25` |

**证据来源**：`report/ps_vs_pl.md:5-14`、`:32-41`；`src/ps/main.c:1-2`；
`src/rtl/eth/eth_udp_video_top.v`（14 只实例的例化行）；`src/host/one_click_test.py:23-25`；
`data/metrics.csv:13`、`:22`、`:25`；`build/report/utilization.rpt:106`。

小结 1："PS 收包写 DDR、PL 读"这一句在本工程里要分两半念：网口那半在 PL（v1 才在 PS），
SD 那半确实是 PS 写 DDR、PL 读（第 3 节）。
小结 2：这条分工换来的可核对好处是"入流有没有掉东西"变成 PL 自己数的数（lane0/lane8/lane9），
不是上位机推的数；代价是 PL 里多了整套协议逻辑。下一步：第 3 节，帧到底怎么落进 DDR。

## 第 3 节 帧落地路径：DMA 直写 PL 要读的那块 DDR + 每帧一次发布

**面对什么问题**：PS 从 SD 卡读到的一帧（307200 B）要交给 PL 显示。
如果先在 PS 里过一遍再交给 PL，就是要 300 KB 级的搬运 + 一块中转缓冲；
如果不告诉 PL"这张写完了"，PL 会在 PS 写到一半时把半新半旧的帧搬上屏。

**可选做法**：

1. PS 读进自己的缓冲、再 memcpy 进共享 DDR，然后发布。
2. SD 控制器的 DMA 直接把帧写进 PL 要读的那块 DDR，PS 只发一次发布脉冲。
3. 双缓冲：PS 与 PL 各用一块 DDR 页，换页即完成（不需要"发布"这件事）。

**本项目选了什么、放弃什么**：选 2 + 每帧一次发布。代码事实：

- `src/ps/sd_play.c:12-13`："帧的落地路径刻意做成'零拷贝'：SD 控制器的 DMA 直接写 PL 要读的那块 DDR，
  写完只发一次发布脉冲 ⇒ PS 不需要 300 KB 的 memcpy，也不需要第二块 DDR 做双缓冲" ——
  这一句同时把 1 和 3 放弃了。
- 协议的两端：PS 端翻转位在 `src/ps/main.c:242-251`（`ps_publish()`：`pub_lvl ^= 1u` 后整字写回），
  PL 端同步在 `src/rtl/util/ps_publish.v:18-25`、消费条件在 `src/rtl/top/pl_video_top.v:559`（`pub_consume`），
  搬运机 `u_aw` 的触发是同步后的沿（`src/rtl/top/pl_video_top.v:697`）。
- 为什么"复制一次"而不是"每帧都复制"：`src/ps/sd_play.c:16-18` 写的是这件事的反面 ——
  每帧复制会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（撕裂）。
- 地址分开：PS 专用第三个 bank `0x1010_0000`（`src/ps/main.c:41-46`、`src/ps/sd_play.c:35`），
  与 ETH 的乒乓两块 `0x1000_0000`/`0x1008_0000`（`src/rtl/eth/ddr_bank_commit.v:9-10`）错开。
  为什么只能靠地址分开：`src/rtl/top/pl_video_top.v:14-15` 明写"仲裁只管谁用 DDR→帧缓存这台搬运机，
  管不到谁写 DDR"（SD 的 DMA 走 PS 自己的 HP0，不经过 PL）。
- 缓存维护只做一件事：flush。`src/ps/main.c:714`（FILL 诊断帧）与 `src/ps/sd_play.c:95`
  （每块 64 扇区读之前）。为什么 DMA 目标区在**读进去之前**还要 flush：
  `src/ps/sd_play.c:86-88` 给的理由是"若那里有脏行，invalidate 之后脏行仍会被写回，
  把刚 DMA 进来的数据盖掉"。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| SD 回放的墙钟帧率 | 29.8 – 30.0 fps（100 帧滑窗） | 【实测】 | `data/metrics.csv:12` |
| 每帧的发布开销 | 一次整字 GPIO 写、无串口打印 | 【实测】 | `src/ps/main.c:204-207`（30 fps 回放每秒约 2 KB 文本，而 115200 只有 11.5 KB/s） |
| DDR 地址预算 | 3 块 307200 B 的 bank | 【实测】 | `src/rtl/eth/ddr_bank_commit.v:9-10`、`src/ps/main.c:46` |
| 发布协议的心跳 | PS 每 100 ms 一次、PL 侧 500 ms 判超时 | 【实测】 | `src/ps/main.c:260`、`src/rtl/top/pl_video_top.v:586` |
| 撕裂的窗口 | 一个帧周期（PL 只在 `frame_start` 搬一次） | 【注释记载】 | `src/ps/sd_play.c:16-18` |

**两种解释、本次未区分**的一处：`Xil_DCacheFlushRange` 之外**没有**再做 invalidate
（`src/ps/sd_play.c:95` 只在读之前 flush，`src/ps/main.c:714` 只在写完 flush）。
代码里能看到的表现是"屏上没有旧数据残留"（`data/metrics.csv:12` 的 29.8-30.0 fps 是间接旁证）。
机制上两种解释都说得通：① DMA 写完直接落到 DDR，PL 从 DDR 读，CPU 侧不再读这块缓冲，所以没必要 invalidate；
② flush 本身已经把 L1/L2 的那几行清出（BSP 实现是 clean+invalidate，见
`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:453-467`），
所以"不需要再 invalidate"是前者的结果而不是额外保证。
区分方法：在 `src/ps/sd_play.c:95` 之后、DMA 之前插一次对目标区首字节的读（制造 L1 命中），
再比较屏上帧与卡上帧 —— 本次没做，故写成未区分。
缓存一致性的通用口径与它在本仓库的另一处落点（DMA 驱动内部的"源刷 / 目的无效化"）
归 `mechanics.md` 第 7 节讲，本篇不重复；"下一层去哪儿补"归 `next-layer.md` 第 5 节。

**证据来源**：`src/ps/sd_play.c:12-18`、`:86-95`；`src/ps/main.c:41-46`、`:204-207`、`:242-251`、`:260`、`:714`；
`src/rtl/top/pl_video_top.v:559`、`:586`、`:697`；`src/rtl/util/ps_publish.v`；`data/metrics.csv:12`；
BSP 的 `xil_cache.c`（路径见上，本次打开的是该文件 `:265-310` 与 `:453-513`）。

小结 1："零拷贝"在这一篇里的意思是**PS 不做 memcpy**，不是"没有拷贝"——
PL 那侧仍要跑一次 DDR→帧缓存的整帧搬运（第 9 节提到的 `u_aw`/`u_row`）。
小结 2：这一节是本目录唯一用到 BSP 源文件当出处的地方；缓存维护 API 的完整语义与
"一致性端口 vs 非一致性端口"那条分界在 `next-layer.md` 第 4 节。下一步：第 4 节，谁拥有屏幕。

## 第 4 节 三路片源与仲裁：判据是"活着 + 能不能安全换手"，不是"哪边有数据"

**面对什么问题**：ETH 帧、SD 帧、片内图卡三路都想上屏，而它们共用**一台** AXI 读口和**一个**帧缓存写口。
选择位如果在一次拷贝中途翻转，就会留下半开的读突发；
而"哪边该拿到"这件事若用"自配置以来收过包没有"来判，拔网线也不会回 0。

**可选做法**：

1. 老写法：`eth_mode = 3FF(|s_pkts)` —— 收过任何一个包就归 ETH（含 ARP 触发的包）。
2. 只看"最近有包"：`stall_ms < 阈值` 就归 ETH（量它的那个时基可信与否不管）。
3. 三件分开：ETH 活着（`eth_live`）+ 量它的时基可信（`eth_tb_ok`）+ 换手只在两个引擎都空闲时，
   往 PS 方向再多等一段静默（滞回）。

**本项目选了什么、放弃什么**：选 3。代码事实：

- 1 被明确废弃并写出病史：`src/rtl/util/src_arb.v:4-8`（两条病：ARP 就触发、拔线不回 0 ⇒ PS 片源被永久锁死）。
- 2 被补了一刀：`src/rtl/util/src_arb.v:11-14` —— 板级实测断链时 RTL8211 不停供 RXC 而是把它拉到 ≈2.5 MHz，
  `stall_ms` 以约 1/48 的速度爬，"活着"这一位会连着十几秒说谎；
  同一条现象的第二处记录在 `src/rtl/eth/snap_cross.v:6-7` 与 `src/rtl/eth/link_monitor.v:6-7`。
- 判决式：`src/rtl/util/src_arb.v:51`（`eth_wanted = force_eth ? 1 : force_ps ? 0 : (eth_live & eth_tb_ok)`）
  与 `:67-76`（只有 `both_idle` 才换主人，往 PS 方向要 `quiet >= T_OFF_CYC`）；
  滞回常数 2_000_000 拍 = 20 ms @100 MHz 接在 `src/rtl/top/pl_video_top.v:421`。
- 手动锁只改"想要"、不改"什么时候换手"：`src/rtl/util/src_arb.v:41-43`，
  那里明写了"直接在输出上加一个 mux 是最容易想到的写法，也是错的"。
- 模式环（按键四态 + 串口覆盖）是另一件事：`src/rtl/util/src_mode.v`，
  它在 `src/rtl/top/pl_video_top.v:171` 被一行适配器翻译成仲裁看得懂的 2 位码 ——
  两份编码不同这件事在 `src/rtl/util/src_arb.v:27-28` 有警告。
- 图卡不参与仲裁：`src/rtl/top/pl_video_top.v:170` 的注释"它只是显示什么，不是谁在搬"；
  图卡本体 `src/rtl/video/test_card.v:2-5`（四样判读点：游动亮球 + 拖影、细网格、横扫亮带、帧号二值格）。
- 结果可观测：`src/rtl/top/pl_video_top.v:603` 的 `dbg_src`（lane30），
  位序解释在 `src/host/health_read.mjs:71-85`。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 仲裁本体 | 一只 79 行模块 + 16 位观测口 | 【实测】 | `src/rtl/util/src_arb.v` 全文；lane30 组装在 `src/rtl/top/pl_video_top.v:603` |
| "活着"这条判据的成本 | 不新增 GPIO 位、不新增异步配对 | 【实测-结构】 | `src/rtl/top/pl_video_top.v:112-115`（两个输入都是 `system_top` 在 fclk0 域取好的）；`:600-601` 记了"新加一对同步器白交税"的历史读数（cdc.rpt 3 端点/0 unsafe → 8/4，【注释记载】） |
| 换手要等两边都空 | 最长一帧的拷贝窗口 | 【实测】 | `src/rtl/video/frame_commit_lock.v:117-122`（起拷条件）、`src/rtl/axi/axi_frame_writer_gated.v:182-186`（完成条件） |
| 板级复验 | 3 路 + AUTO，拔线与拔卡都已在板上复验 | 【报告记录】 | `data/metrics.csv:19` |
| 判决原因位 | `why_ps` 三位 = 判决那一拍的输入快照 | 【实测】 | `src/rtl/util/src_arb.v:35-39`、`:73` |

**证据来源**：`src/rtl/util/src_arb.v:4-14`、`:41-51`、`:67-76`；
`src/rtl/top/pl_video_top.v:112-115`、`:170-171`、`:421`、`:600-603`；
`src/rtl/util/src_mode.v`；`src/rtl/video/test_card.v:2-5`；`src/host/health_read.mjs:71-85`；`data/metrics.csv:19`。

小结 1：这一节的取舍可以压成一句：**判据与换手时机分家**。
"谁该拿屏幕"可以错（时基说谎），但"什么时候能换"永远不能切断一次拷贝。
小结 2：仲裁与片源模式是两套编码，改任何一套要看那一行适配器（`src/rtl/top/pl_video_top.v:171`）。
下一步：第 5 节，画幅与 ×2。

## 第 5 节 输入 512×300、输出 1024×600：×2 展开与"整屏一个视口"

**面对什么问题**：面板是 1024×600，片源是 512×300。
要么把片源放大到面板分辨率再处理，要么保持 512×300 处理、上屏时做 ×2 展开；
而屏幕还要同时显示"原图"和"处理图"两半，并且两半要能任意比例切开、还要能一起旋转缩放。

**可选做法**：

1. 两半各画一整幅（左窗 512 列画原图、右窗 512 列画处理图）：缝只能钉死在 512。
2. 保持 512×300，整屏一份源坐标 + ×2 展开，缝改成逐像素二选一（一条地址流覆盖全屏）。
3. 把处理画幅直接提到 1024×600（帧缓存与入流都翻倍）。

**本项目选了什么、放弃什么**：选 2。代码事实：

- ×2 的两行本体：`src/rtl/top/pl_video_top.v:242-243`（`cx = x >> 1`、
  `cy = (y>>1) < IMG_H ? (y>>1) : IMG_H-1`），面板栅格本身是 1024×600
  （`src/rtl/video/video_timing_1024x600.v`，实例 `u_t` 在 `src/rtl/top/pl_video_top.v:226`）。
- 链子的一行变成 1024 个有效拍：`src/rtl/top/pl_video_top.v:800` 的 `#(.H_ACTIVE(2*IMG_W))`，
  代价与后果写在 `src/rtl/process/proc_pipeline.v:9-15`（"3×3 窗口的空间尺度现在就是按 1024 列算的 …
  横向模糊/锐化/Sobel 的半径因此是半个源像素"，并注明"这是既成事实、不是待评估的新风险"）。
- 原图抽头跟同一份坐标：`src/rtl/top/pl_video_top.v:775-781`，那里同时放弃"再开一个读口"。
- 1 被记录成历史形态：`src/rtl/top/pl_video_top.v:239-240`
  （"旧几何两屏各画一整幅，缝只能钉死在 512"）与 `src/rtl/video/split_display.v:9-18`
  （那条 `x < PANE_W` 把缝写死在 512，现在缝位是输入）。
- 3 被主机侧脚本否掉：`src/host/video_sender.py:12-13`（"把画幅提到 1026×600 需要四倍 BRAM"这一句
  原文写的是 1024×600，此处按原文引；结论是"这颗器件放不下"）。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 行缓存宽度翻倍 | 注释记"约 +8 块 BRAM" | 【注释记载】 | `src/rtl/top/pl_video_top.v:796-799`（同一处还写了"要回到源域等距就得给整条链加时钟使能"这条支路） |
| BRAM 总占用 | 95.5 / 140 tile（68.21 %） | 【实测】 | `build/report/utilization.rpt:106`；`data/metrics.csv:10` 同一读数 |
| 上述翻倍在报告里的形态 | 分布式 RAM 4044 LUT；窗口级行缓 SYNTH-5 336 件 | 【实测】 | `build/report/utilization.rpt:38`、`build/report/methodology.rpt:32`（明细样例 `:65`） |
| 效果链延迟 | 固定 15 拍、内容滞后 4 行 | 【实测】 | `src/rtl/process/proc_pipeline.v:2-4`、`:22` |
| 坐标抽头线的寄存器账 | 2×12×12 = 288 个触发器，注释按"Slice 寄存器 7936 的 3.6 %"计 | 【注释记载】 | `src/rtl/process/proc_pipeline.v:82`。注意：分母 7936 与当前报告的 8188（`build/report/utilization.rpt:40`）不是同一轮 ⇒ 这个百分比按旧轮口径念，不许当本轮数 |
| 场频 | 50 MHz ÷ 1344 ÷ 625 = 59.5 Hz | 【实测】 | `data/metrics.csv:3`（像素钟那一行）与 `:4`（1024×600 @59.5 那一行） |

**一处冲突要如实报**：`src/host/video_sender.py:12` 写的是"BRAM 里那一帧就是 512×300
（`build/utilization.rpt` 的 67.86 % 基本是它）"，而当前 `build/report/utilization.rpt:106` 是 68.21 %。
两种解释：① 那句引的是更早一轮的报告件；② 该轮之后确实多用了 BRAM。
区分方法：`report/04-resources.md:11-15` 的逐轮表与 `data/metrics.csv:10` 相减，或重跑一轮 `report_utilization`。
本次未做逐轮相减 ⇒ 只报冲突，不下结论。

**证据来源**：`src/rtl/top/pl_video_top.v:226`、`:239-243`、`:775-800`；
`src/rtl/process/proc_pipeline.v:2-4`、`:9-15`、`:22`、`:82`；`src/rtl/video/split_display.v:9-18`；
`src/host/video_sender.py:8-13`；`build/report/utilization.rpt:38`、`:40`、`:106`；
`build/report/methodology.rpt:32`；`data/metrics.csv:3`、`:4`、`:10`；`report/04-resources.md:11-15`。

小结 1：×2 展开换到的东西是"缝可以停在任意一列、左右两半从此同一份源坐标"，
付的是链子按显示列算尺度（滤波半径变相缩小一半）与一串行缓存宽度。
小结 2：这一节里两处百分比数字（3.6 % 与 67.86 %）都是旧轮口径，已经标出来了；
念的时候把标签一起念，不然就是把别人某一轮的账念成本轮。下一步：第 6 节，存储到底放哪儿。

## 第 6 节 行缓存/帧缓存落在 BRAM 还是 LUTRAM（含 2 的幂拆块与"只开一个读口"）

**面对什么问题**：像素链要 4 处行缓存（模糊、锐化、Sobel、形态学各一对）、
一条 4 行的原图延迟环、一块 512×300×16 bit 的帧缓存、一块 36 bit×8192 的跨域 FIFO、
一块 64×83 bit 的 skid 缓冲。器件只有 140 个 BRAM tile。全放 BRAM 会不够，
全放 LUTRAM 会吃掉大量 LUT 且深度上不去。

**可选做法**：

1. 全部交给综合器按约束挑（不写 `ram_style`）。
2. 逐块点名：大的强制 BRAM（`ram_style="block"`），小的强制分布式（`"distributed"`）。
3. 全部强制 BRAM。

**本项目选了什么、放弃什么**：选 2，并留一处给工具。写法逐处点名：

- 强制 BRAM：`src/rtl/eth/dc_fifo.v:20`、`src/rtl/video/frame_buffer_w64.v:37-38`（帧缓存两块）、
  `src/rtl/process/bilin/fb_bilin.v:142`（抽头暂存 512×32）、`src/rtl/process/bilin/fb_bilin.v:184`（结果缓冲 1024×17 乒乓）。
- 强制分布式：`src/rtl/axi/axi_frame_writer_gated.v:53-54`（skid 的 `sk_addr`/`sk_data`），
  理由在 `:50-52`：带异步复位的写法综合报 `Synth 8-4767`，64×83 bit 全掉进触发器，
  "约占整机剩余寄存器的一半"，于是换成"已验证的分布式 RAM 写法"。
- 不点名、让工具按约束挑：`src/rtl/video/raw_line_delay.v:51`（行环 `mem` 没有属性）。
- 深度必须是 2 的幂：`src/rtl/video/frame_buffer_w64.v:4-7` 记了一次对照 ——
  一个 38400 深的数组会被推断**向上填充到 2^16**，实测吃掉 128 个 RAMB36（全片 140，98.93 %），
  拆成 32768 + 8192 两块后实测 80 个；对照件名 `tmp_ramtest/fbtest.v`（v0 = 128、v5 = 80；该件与那个目录本次 `ls` 确认**不在盘上**，所以这两个数只能按【注释记载】念）。
  同一条规矩的第二处：`src/rtl/process/bilin/fb_bilin.v:181`。
- 一个逻辑读口的硬约束：`src/rtl/process/bilin/fb_bilin.v:180` 写"这里不许再开第二个逻辑读口：
  实测 BRAM 从 80 块顶到 160 块 RAMB36，全片才 140"；顶层同一件事在
  `src/rtl/top/pl_video_top.v:777-779`（"补偿不是再开一个读口"）。

**实测到的映射结果**（本次打开 `build/report/methodology.rpt` 数的）：

| 对象 | 工具把它放在哪 | 出处 |
|---|---|---|
| 窗口级行缓 `u_blur`/`u_sharp`/`u_sobel`/`u_morph` | 分布式 LUT RAM，理由是"时序约束提示这样映射更好"；SYNTH-5 共 336 件（blur 128 + sharp 128 + sobel 64 + morph 16） | `build/report/methodology.rpt:32`（计数）、`:63-66`（明细样例）；分组计数来自本目录本次执行的 `grep … uniq -c`（2026-10-05） |
| 原图行环 `u_raw/g_ring` | **RAM block**（原文 `implemented as a RAM block`），SYNTH-6 列 5 件 mem_reg_0..4 | `build/report/methodology.rpt:2210-2230` |
| 帧缓存 `u_bilin/u_fb` | RAM block，80 件 | 同上（SYNTH-6 段本次计数） |
| 跨域 FIFO `u_cdc` | RAM block，9 件 mem_reg_0..8 | 同上 |
| 合计 | Block RAM Tile 95.5/140、LUT as Distributed RAM 4044 | `build/report/utilization.rpt:106`、`:38` |

**一处必须报出来的不一致**：`report/04-resources.md:58-59` 把 336 条 SYNTH-5 解释成
"把窗口级行缓与 `raw_line_delay` 走 LUT-RAM 这一选择的直接代价"，
而同一套件里的 `build/report/methodology.rpt:2210` 把 `u_pl/u_raw/g_ring.mem_reg_*` 写成 RAM block。
两种解释：① 那一行写的是更早一轮（当时行环确实落 LUTRAM）；② 那一行把两处并列时误并了。
区分方法：把 `report/04-resources.md` 引用的那件 `build/utilization.rpt` 与当前件逐轮相减，
或复跑 `report_methodology` 看 `u_raw` 出现在 SYNTH-5 还是 SYNTH-6 —— 本次未做。
本篇按"当前 methodology 件"念（行环 = RAM block），并把这条冲突登记为红项，
不改那篇文档（不在这一批的权限内）。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| BRAM 是全设计最紧的一项 | 68.21 %（对比：LUT 26.61 %、寄存器 7.70 %、DSP 8.64 %） | 【实测】 | `build/report/utilization.rpt:35`、`:40`、`:106`、`:121` |
| 时序约束把 336 件行缓推成分布式 RAM | SYNTH-5 = 336 条 Warning（总检查 446 条） | 【实测】 | `build/report/methodology.rpt:26`、`:32` |
| 帧缓存拆块 | 128 → 80 个 RAMB36 | 【注释记载】 | `src/rtl/video/frame_buffer_w64.v:4-7`；旁证：SYNTH-6 里 `u_pl/u_bilin/u_fb` 本次数到 80 件 |
| 单读口约束换来的第二块 | 结果缓冲 1024×17 = 一块 RAMB36（36 bit 宽模式） | 【注释记载】 | `src/rtl/process/bilin/fb_bilin.v:178-184` |

**证据来源**：`build/report/methodology.rpt:26`、`:32-36`、`:63-66`、`:2210-2230`；
`build/report/utilization.rpt:10`、`:35`、`:38`、`:40`、`:106`、`:121`；
`src/rtl/video/frame_buffer_w64.v:4-7`、`:37-38`；`src/rtl/video/raw_line_delay.v:41-51`；
`src/rtl/process/bilin/fb_bilin.v:142`、`:178-184`；`src/rtl/axi/axi_frame_writer_gated.v:50-54`；
`src/rtl/eth/dc_fifo.v:20`；`report/04-resources.md:11-15`、`:58-59`。

小结 1：这一节的选择是"大的钉 BRAM、小的钉 LUTRAM、其余交给工具按约束判"，
而工具判的结果现在能在报告里逐件点名 —— 这就是为什么这一节的每个数都有出处。
小结 2：非 2 幂的深度会让 BRAM 用量翻倍，这是本工程里最贵的算术陷阱之一（两处注释 + 一件对照实验）。
下一步：第 7 节，跨域那条 FIFO 的指针为什么是格雷码。

## 第 7 节 异步 FIFO 的格雷码指针与两刀满判据（含一次已回滚的尝试）

**面对什么问题**：入流在 125 MHz、写 DDR 的 AXI 在 100 MHz，且 HP0 会被整帧拷贝独占一整个 V-blank。
中间必须有一块能同时被两个时钟访问的缓冲，而它的"满"与"空"两个判据要跨域。
指针若用二进制，相邻两格可能有多位同时变，对面打两拍后会读出一个**值域里没出现过**的数。

**可选做法**：

1. 二进制指针 + 打两拍（快、省，但会读到不存在的指针值）。
2. 格雷码指针 + 打两拍（相邻只有一位变）。
3. 握手式跨域（请求/应答一来一回），或厂商 FIFO IP。

**本项目选了什么、放弃什么**：选 2，并自己写（放弃 3 的 IP 与握手）。代码事实：

- 转换与跨域：`src/rtl/eth/dc_fifo.v:29-32`（`bin2gray = b ^ (b>>1)`）、`:45-47`、`:82-95`
  （两条方向相反的两级链）。二进制指针只在本地用（`:54`、`:62`、`:76`）。
- 指针为什么比地址宽一位：`:45` 的 `[ADDR_W:0]` 与 `:35-36` 注释的
  "满 = 对端格雷码最高两位取反、其余相等"是同一件事。
- 放弃 IP 的记录：`report/ps_vs_pl.md:67-75` 那张"自写 FIFO vs IP"表把取舍写成
  集成/BRAM 推断/可控性/跨钟四行，结论是"纯 RTL，可移植；指针/同步策略完全可见"。
  这条是【报告记录】，不是本目录的推断。
- 满判据的第一刀**被回滚**：`src/rtl/eth/dc_fifo.v:37-39` 记录给 `wr_full` 加 `max_fanout=12`
  想让综合复制本地缓冲，结果"实测无效"，并给出两个数（WNS 从 −0.062 掉到 −0.192、失败端点 28 → 34，
  凭据名 `build/r83_gates.txt` 与 `build/timing_summary.rpt`；前者本次 `ls` 确认不在盘上，后者在 `build/timing_summary.rpt` 与 `build/report/timing_summary.rpt` 各有一份）⇒ 结论写在同一行"扇出不是瓶颈"。
  这两件本次没有打开核对 ⇒ 那两个 WNS 数只按【注释记载】念。
- 满判据的第二刀**留下**：`:40-44` 把满判据从"下一个写指针 `wgray_n`"改成"当前 `wgray`"，
  理由是把 14 位加法 + 二进制转格雷 + 比较整条锥体从 `wr_en → ENARDEN` 上赶出去
  （注释记 r87 最差路径为 8 级逻辑、0.152 ns，件名 `build/r87_timing_summary.rpt`），
  副作用是"少一格"的病一起没了（记可用深度 DEPTH−1 → DEPTH，尺子 `sim/tb_cdc_capacity` 的 C1）。
  现在那一行是 `src/rtl/eth/dc_fifo.v:47`。
- 读侧必须每拍取一条：`src/rtl/eth/eth_udp_video_top.v:258-262` 记的是反例账 ——
  限成"每 3 个 axi 周期取 1 条"= 66 MB/s < 125 MB/s ⇒ 单包就能灌满 CDC、稳定丢约 46 % 的字，
  表现为"每隔一个 16 bit 空洞的黑纹"，且与上位机速率无关。现役写法 `:312`。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 缓冲容量 | 36 bit × 8192 条 = 16 KB | 【实测】 | `src/rtl/eth/eth_udp_video_top.v:295-298` |
| 容量够不够的账 | "15 MBps × 672 µs ≈ 1260 字"（独占窗口期间到达的入流） | 【注释记载】 | `src/rtl/eth/eth_udp_video_top.v:296-297`；V-blank 拍数账另见 `src/rtl/top/pl_video_top.v:392-399` 与 `:446`（`VBLANK_AXI_CYC = 67200`，实测口径由 `src/rtl/top/pl_video_top.v:448-452` 用来判 overrun） |
| 满判据那两刀的收益 | 注释记：锥体只剩比较；可用深度 +1 格 | 【注释记载】 | `src/rtl/eth/dc_fifo.v:40-44`、`:47` |
| 被挡掉的那一拍必须有计数出口 | `cdc_wr_req` → `drop_words` → lane0 | 【实测】 | `src/rtl/eth/eth_udp_video_top.v:283`、`src/rtl/eth/link_monitor.v:105`、`:122`、`:187` |
| 板侧零丢字 | `drop_words = 0`（演示工况，600 帧一轮） | 【报告记录】 | `data/metrics.csv:22` |

**证据来源**：`src/rtl/eth/dc_fifo.v:20-95`；`src/rtl/eth/eth_udp_video_top.v:258-262`、`:283`、`:295-305`、`:312`；
`src/rtl/eth/link_monitor.v:105-123`、`:187`；`src/rtl/top/pl_video_top.v:392-399`、`:446-452`；
`report/ps_vs_pl.md:67-75`；`build/report/utilization.rpt:106`；`data/metrics.csv:22`。

小结 1：这一节的取舍不是"格雷码 vs 二进制"一句，而是三句：指针只跨格雷码、
判据不许挂加法器锥、被挡掉的那一拍必须有计数出口。三句分别落回 `src/rtl/eth/dc_fifo.v:82-95`、`src/rtl/eth/dc_fifo.v:47`、`src/rtl/eth/link_monitor.v:105`。
小结 2：这里有一处**回滚**（`max_fanout=12`），它留下的两个数是这段设计最有价值的部分 ——
"扇出不是瓶颈"是被量过的，不是感觉出来的。下一步：第 8 节，同屏对比怎么做。

## 第 8 节 原图/处理图同屏：分割线逐像素二选一

**面对什么问题**：要在一块 1024×600 的屏上同时看到同一帧的原图与处理图，
还要能停在任意位置、能自动来回扫、能在旋转时跟着画面转。

**可选做法**：

1. 左右两个视口各画一整幅，缝钉死在两半的交界（与第 5 节的做法 1 是同一条）。
2. 一条地址流覆盖全屏 + 逐像素二选一，缝位是一个可运动的列号。
3. 先把处理结果与原图并排拼成一张 1024×600 的图，再送显示（屏幕上没有第二条几何）。

**本项目选了什么、放弃什么**：选 2。代码事实：

- 逐像素那一行：`src/rtl/video/split_display.v:43`（`left = seam_in_src ? ~src_orig : (x_sel < seam)`）
  与 `:47-48`（`take_orig` → `sel`，越界给黑）。缝只是**比较结果**，不是两个视口的边界。
- 那条标记线也是逐像素：`src/rtl/video/split_display.v:52-53`（缝两侧各 1 列，画蓝线），
  开关位是反相的 `gp[13]`（`src/rtl/top/pl_video_top.v:892-894`："复位/PS 没写过时屏上仍有那条 2 px 蓝线"）。
- 换边不换缝位：`src/rtl/video/split_ctrl.v:105`（`raw_on_left = ~swap`）。
- "跟画面一起转"：把缝量在**源列**里并在源头那一拍算好标签，由 `src/rtl/video/seam_src.v`
  （实例 `u_seam_src`，`src/rtl/top/pl_video_top.v:904-909`）搬过去；
  `follow` 同时管扫描坐标系与判据空间（`src/rtl/top/pl_video_top.v:896-898`、
  `src/rtl/video/split_ctrl.v:33`）。
- 1 被写在两处当历史：`src/rtl/video/split_ctrl.v:6-7`（单独成模块的理由是
  "`split_display` 那根 `x < PANE_W` 把缝写死在 512"）与 `src/rtl/top/pl_video_top.v:239-240`。
- 3 没有对应代码，本篇不把它当"被否掉的方案"写，只登记为"未实现"（见第 14 节第 5 条）。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 标签必须与内容同级 | 混色级坐标取 `x_d[MIX_D]`，`MIX_D = 3+1+1+LATENCY` = 20 | 【实测】 | `src/rtl/top/pl_video_top.v:354`、`:919-921`；不同级的历史后果写在 `src/rtl/video/split_display.v:9-14` |
| 缝在源列里要跟随 | 抽头数由流水线深度推出 `SEAM_TAPS = MIX_D + 1 - 3`，不抄字面量 | 【实测】 | `src/rtl/top/pl_video_top.v:902` |
| 扫描值 → 百分比那一级要额外寄存 | 注释指一次 −0.482 ns 的最差路径（28 级、含一个 DSP48） | 【注释记载】 | `src/rtl/video/split_ctrl.v:118-128`；当前名册 WNS +0.739 ns / 0 失败端点（【实测】`build/report/timing_summary.rpt:151`） |
| 百分比不许用除法 | `PCT` 是 elaboration 常数（1024→1600、512→3200），一次乘法 + 固定移位 | 【实测】 | `src/rtl/video/split_ctrl.v:107-117`；反例代价见 `src/rtl/top/pl_video_top.v:621-623`（组合除法器把 100 MHz 域打到 WNS −5.014 / 96 个失败端点，【注释记载】） |
| 越界标签 | 缝两侧共用同一位越界标签（同一份源坐标） | 【实测】 | `src/rtl/top/pl_video_top.v:924`、`src/rtl/video/split_display.v:44-46` |

**证据来源**：`src/rtl/video/split_display.v:9-18`、`:43-53`；`src/rtl/video/split_ctrl.v:6-7`、`:33`、`:94-105`、`:107-128`；
`src/rtl/top/pl_video_top.v:239-243`、`:354`、`:885-909`、:919-924`、`:621-623`；`src/rtl/video/seam_src.v`；
`build/report/timing_summary.rpt:151`。

小结 1：这一节真正的取舍是"缝是**数据**还是**几何**"。当几何（做法 1）时它跟旋转/缩放不相容；
当数据（做法 2）时每一级标签都得跟着内容走，代价全在花名册式的级数上（`MIX_D`、`SEAM_TAPS`）。
小结 2：`split` 那一路的开关位（`gp[10]`/`gp[11]`/`gp[12]`/`gp[13]`）与 `pos_px` 属于 19 位几何控制字，
位表正本在 `interface-contract.md` 第 5 节，本篇不复制。下一步：第 9 节，效果链。

## 第 9 节 九级效果链可逐像素开关，代价是固定 15 拍与提前 4 行

**面对什么问题**：九种算法要能任意组合、任一时刻改，还要在屏上看到"改了立刻生效"。
同时链子输出的像素必须与显示栅格、与另一路原图抽头逐格对齐。

**可选做法**：

1. 每级一个使能位，链子按"开了几级"改变延迟（数据到哪算哪）。
2. 每级一个使能位，但**每级都占自己的拍**（旁路时数据照走、只是不动它），整链延迟固定。
3. 一次只选一种算法（一个多路选择器，不做组合）。

**本项目选了什么、放弃什么**：选 2。代码事实：

- 位定义：`src/rtl/process/proc_pipeline.v:5-6`（`[0]灰度 [1]反色 [2]模糊 [3]锐化 [4]Sobel [5]二值化
  [6]判决反相 [7]腐蚀 [8]膨胀`），链序在 `:51`（gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学）。
- 固定 15 拍：`src/rtl/process/proc_pipeline.v:17-22`（逐拍账：灰度 1 + 反色 1 + 模糊 3 + 锐化 3 + Sobel 3 +
  阈值 1 + 形态学 3 = 15；参数 `LATENCY` 的注释明写"不许由外部覆盖"）；
  同级两个算法是**串联**的（`:118-129`，模糊与锐化各占 3 拍）。
- 1 被否掉的写法留下证据：`src/rtl/process/proc_pipeline.v:19-21` 要求顶层"不许另写一个数、
  只取 `u_pipe.LATENCY`"，顶层照做（`src/rtl/top/pl_video_top.v:816-817`），
  原图那一路的长度也由它推出（`:818` 的 `LEFT_TAIL = PROC_LAT`）；
  `:813-815` 记录了以前写字面量 7 的后果："不是编译错，而是左窗与右窗错开 N 个像素"。
- 3 的形态只剩一处：`src/rtl/process/proc_pipeline.v:59-61`（腐蚀与膨胀互斥，
  两位同时为 1 时两个都不做，注释给的理由是"开/闭要两遍 3×3 窗口，这里只有一遍"），其余八位自由组合。
- 控制字只有一套口径：`src/rtl/process/effect_ctrl.v:5-7` 与 `src/rtl/top/pl_video_top.v:28-29`
  （V7 那五位 `effect_en` 的兜底合流已删）；PS 侧抄同一张表在 `src/ps/main.c:109-118`。
- 同步链只开一条：`src/rtl/process/effect_ctrl.v:34-39`（13 位 `sel` 链把九位效果 + 缩放档 + 手动旗标
  一起带过去；gamma 那 32 位同一条链），理由在 `:30-33` 与 `:62`：
  新开一组就多一对跨域配对、`cdc.rpt` 基线要重画。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 整链延迟 | 15 拍固定，与开关组合无关 | 【实测】 | `src/rtl/process/proc_pipeline.v:17-22`；顶层由此推 `MIX_D`（`src/rtl/top/pl_video_top.v:354`） |
| 内容滞后 | −4 行、0 列，四个窗口级各贡献 −1 行 | 【实测】 | `src/rtl/process/proc_pipeline.v:23-27`、`:44`（`off_rows` 输出口） |
| 补偿滞后的做法 | 右窗读坐标**提前** 4 个显示行（数据不能提前） | 【实测】 | `src/rtl/top/pl_video_top.v:244-250`、`:284`；原图抽头靠行环延后同一行数（`:781`、`:788`） |
| 坐标要跟级走 | 12 级独立延迟线，288 个触发器 | 【实测-结构】+【注释记载】 | `src/rtl/process/proc_pipeline.v:71-98`；触发器账与百分比写在 `:82`（分母是旧轮数，见第 5 节那条"注意"） |
| 级数口径写错时的板相 | 每行往 319 号槽写进消隐期的 0x0000 ⇒ 板上一根钉死在显示列 320 的 1 像素黑竖线 | 【注释记载】 | `src/rtl/process/proc_pipeline.v:75-81`（并点名尺子 `sim/tb_v103_pipe_bypass.v` 的 C10d/C10f） |
| 控制位预算 | 九位效果 + 8 位阈值 + 3 位缩放档 + 1 位手动，全走一条链 | 【实测】 | `src/rtl/process/effect_ctrl.v:11-15`、`:50-56` |

**证据来源**：`src/rtl/process/proc_pipeline.v:2-6`、`:9-27`、`:44`、`:51-61`、`:71-98`、`:100-150`；
`src/rtl/process/effect_ctrl.v:2-7`、`:30-39`、`:50-56`、`:62`；
`src/rtl/top/pl_video_top.v:28-29`、`:244-250`、`:284`、`:354`、`:781-818`；`src/ps/main.c:109-118`。

小结 1：这条链用"延迟恒定"换"随便怎么开关都不会错位"，代价是**必须**在源头把地址提前/把原图延后，
于是一致性问题从"链子内部"转移成了"级数账对不对"。
小结 2：15 与 4 这两个数不许在顶层重写，只许从 `u_pipe.LATENCY`/`u_pipe.OFF_LINES` 取 ——
这一条本身就是设计取舍（宁可多开两个输出口，也不留两处字面量）。下一步：第 10 节。

## 第 10 节 双线性读口：每源像素用满 4 拍、单读口 + 乒乓

**面对什么问题**：缩放倍率是连续的（0.25–2.00），要平滑就不能用最近邻；
但帧缓存只有一个可用读口（第 6 节那条实测：开第二个读口要 160 块 BRAM，全片 140），
而一个源像素在屏上天然占 4 个 50 MHz 拍（2 显示列 × 2 显示行）。

**可选做法**（这一组三个候选在 `report/ps_vs_pl.md:57-64` 那张缩放表里）：

1. 流式 bicubic（推流行缓存）。
2. 逆映射 + 连续 `inv_scale` + 最近邻。
3. 逆映射 + 双线性，抽头在**同一个读口**上分四拍取完。

**本项目选了什么、放弃什么**：现役是 3，且 2 作为运行时开关保留。代码事实：

- 选择线：`bilin_en` 从 PS 的 `gpio_o[19]` 进来（`src/ps/main.c:52`）→
  三级同步 `src/rtl/top/pl_video_top.v:254-262` → `src/rtl/process/bilin/fb_bilin.v:51-54`
  把小数钉 0 并把抽头折回图内 ⇒ 注释 `:48` 写的是"板上 on/off 来回切不需要重新构建"。
  这一条同时否掉了"做成构建参数"的选项（对照 `ZOOM_DEFAULT_ON` 那种参数化写法在
  `src/rtl/top/pl_video_top.v:17`、`:215-217`）。
- 四拍调度：`src/rtl/process/bilin/fb_bilin.v:37-40`（四个相位各发一次读）与 `:56`
  （先选行再选列：两个 17 位加器串成一级 mux 之后，而不是四个候选字）。
- 单读口：`:65-68` 只例化一块 `frame_buffer_w64`；地址先寄存一拍 ⇒ 请求到数据 2 拍（`:39-40`）。
- 抽头暂存与结果缓冲各自一块 BRAM：`:142`（512×32）与 `:184`（1024×17 乒乓）。
- 索引为什么必须是显示列号而不是源列：`:136-138`（旋转时 `sx` 沿一行会停滞/倒退，
  用 `sx` 当地址会让同一个格子被别的源行重写 ⇒ 注释记的现象是"满屏噪点"，标注 2026-09-26 用户报）。
- 放弃 1 的记录理由：`report/ps_vs_pl.md:61`（"divider/行推流，与 FB 随机读不合"）。
- 算术核的三个精度决定：`src/rtl/process/bilin_lerp.v:4-7`（位复制展开、Q8 权重和恒 256 ⇒ 不需要饱和、
  纵向一次 +2^15 再 >>16）与 `:37`（只复位 valid，数据寄存器带异步复位会挡住它们被打进 DSP48 流水级）。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 结果整体晚 1 对显示行 | 顶层要再补 2 行（`BILIN_ROWS = 2`） | 【实测】 | `src/rtl/process/bilin/fb_bilin.v:182-183`、`src/rtl/top/pl_video_top.v:250`、`:276` |
| 两块额外 BRAM | `u_pl/u_bilin/tap_hold_reg`、`u_pl/u_bilin/res_reg` 各 1 件，都在 SYNTH-6 里点名 | 【实测】 | `build/report/methodology.rpt` 的 SYNTH-6 段（本次计数） |
| 乘加用量 | DSP48E1 19 / 220（8.64 %） | 【实测】 | `build/report/utilization.rpt:121-122`；用途口径见 `data/metrics.csv:11` |
| 最近邻仍占同一套级 | `bilin_en=0` 时逐位等于最近邻，级数不改 | 【实测-结构】 | `src/rtl/process/bilin/fb_bilin.v:48-54` |
| 末行/末列越界 | 抽头折回图内，对填充区零依赖 | 【实测】 | `src/rtl/process/bilin/fb_bilin.v:49-54`、`:144`、`:161-162` |

**只看到现象、原理未区分**的一处：`:150-153` 那对读写（写 `tap_hold[j_d2]`、读 `tap_hold[j_d1]`）
被注释写成"写只发生在 y0 行、读只用在 y0+1 行 ⇒ 同一拍同地址不会读写相撞"。
代码里能验证的是相位定义（`:120-123`）与两个地址的级差；机制上有两种说法：
① 两者的地址集合按行相位不相交；② 即使相交，同拍读到的是写之前的值（块 RAM 的读发出早于写生效）。
区分方法：在台架里逐拍列出 `ph_a1` 那一拍的 `j_d2` 与 `ph_b*` 那一拍的 `j_d1`，看有没有重合 ——
本次没做，故只记现象。

**证据来源**：`src/rtl/process/bilin/fb_bilin.v:24-56`、`:65-68`、`:120-154`、`:157-192`；
`src/rtl/process/bilin_lerp.v:4-7`、`:20-71`；`src/rtl/top/pl_video_top.v:250`、`:254-262`、`:276`、`:726-750`；
`src/ps/main.c:52`、`:190`；`report/ps_vs_pl.md:57-64`；`build/report/utilization.rpt:121`。

小结 1：这一节的核心取舍是"不加读口，改为把时间摊开"：一个源像素的四个抽头在四拍里取完，
用两块小 BRAM 换那"第二个口"，代价是内容整体晚一对显示行。
小结 2：双线性/最近邻做成运行时位而不是构建参数，是为了让对照在板上现场切
（`src/ps/main.c:190` 那句"演示时现场切换用"就是它的用途）。下一步：第 11 节，两条回读路。

## 第 11 节 两条回读路：串口打印与 JTAG lane 读回

**面对什么问题**：判红的时候要知道"此刻板上到底怎么了"。
一条路是人趴在串口上看打印，另一条是脚本从 JTAG 读寄存器。两条都给，就必须回答
"两边说的数是不是同一轮、同一个源"。

**可选做法**：

1. 只做串口（实现快，脚本要么去 grep 文本、要么没有判据）。
2. 只做 JTAG 读寄存器（机器判据干净，但现场没有可读的人话）。
3. 两条都做，并把"屏上/回读同源"当判据来设计（同一轮快照、同一份位序、同一套译码）。

**本项目选了什么、放弃什么**：选 3。代码事实：

- JTAG 那条不加从设备：`src/host/health_read.mjs:9-15` —— lane 号写在已有 GPIO_0 的 `bit[31:27]`，
  数据从只读的 GPIO_1 取；lane 0..9 是 `src/rtl/eth/link_monitor.v:187-196` 那十条，
  lane23/24..29/30 见 `src/rtl/top/pl_video_top.v:636-642`、`:688`、`:603`。
- 读两遍并**按 lane 是否单调**分别判：`src/host/health_read.mjs:23-25`、`:47-52`
  （单调集合 `{0,1,5,6,8,9}`、活集合 `{2,3,4,7}`）—— 这一条决定"两遍不等"算不算红。
- 五个时延字必须同一轮：`src/rtl/top/pl_video_top.v:79-82` 写了为什么需要 `lat_arm`
  （恒等式 `tot ≥ c1+c2` 会被"逐 lane 各读各的"破坏），快照出口在 `:636-642`；
  一次板级实测写在 `:81`（"11 组读数里 4 组破坏恒等式"，【注释记载】）。
- 屏上那一格与回读同源：`src/rtl/top/pl_video_top.v:963-987`（ms 跨回像素域给 OSD）；
  片上温度反向 —— 十进制在 PS 侧算完再跨（`src/ps/main.c:83-93`、
  `src/rtl/process/effect_ctrl.v:63-67`），理由是 OSD 那条 27 级链。
- 串口那条**默认不回显**：`src/ps/main.c:194-197`；
  以及 `:204-207`（每帧一次的发布只写寄存器不打字：30 fps 下每秒约 2 KB 文本，115200 只有 11.5 KB/s，
  且 `xil_printf` 是轮询等 TX 的阻塞实现）。
- 两条路的分工写在工具里：`src/host/one_click_test.py:4-11` 的四步
  （ping → JTAG 取基线 → UDP 发 → 再读 lane8/lane9 对账），串口只在人工核对 `[STAT]`/`[TEMP]` 时读
  （`data/metrics.csv:29` 那行的凭据就是串口回显件）。

**代价**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 位序表有多处读者，改一处要同批改 | RTL 组装 + 台架 + JS 译码 + C 宏 | 【实测】 | `src/rtl/top/pl_video_top.v:602`（"新位只往上加，老读者按位 0..6 解析"）、`src/host/health_read.mjs:66-70`、`src/ps/main.c:153-154` |
| 为回读新增的跨域 | lane23 那 20 位**必须真跨一次**（另两条口零新增跨域） | 【实测】 | `src/rtl/top/pl_video_top.v:76-78`、`:674-678` |
| 译码要自带判据 | JS 侧有 `--selfcheck`；否则"读回 0x310 被译成没有流而其实位挪了一格" | 【实测】 | `src/host/health_read.mjs:66-70` |
| 工具前置 | xsdb 路径只认环境变量 `VP_XSDB`，缺了就 REFUSE | 【实测】 | `src/host/health_read.mjs:36`；口径另见 `README.md` 第 2 节 |

**证据来源**：`src/host/health_read.mjs:9-25`、`:36`、`:47-52`、`:66-85`；`src/host/one_click_test.py:4-11`；
`src/ps/main.c:83-93`、`:153-154`、`:194-197`、`:204-207`、`:714`；
`src/rtl/top/pl_video_top.v:76-82`、`:602-603`、`:636-642`、`:674-678`、`:963-987`；
`src/rtl/eth/link_monitor.v:187-196`；`data/metrics.csv:29`。

小结 1：两条路的真正代价不在实现，而在**同源纪律**：位序不许重排、多字必须同轮快照、
译码自己要有判据 —— 这三条都被板级红项逼出来，不是设计洁癖。
小结 2："为什么不用中断"与这一节直接相关，正本在 `interface-contract.md` 第 7 节，本篇不重复。
下一步：第 12 节，两条明确不做的路。

## 第 12 节 不做 MIPI、不做第二平台（KU5P）

**面对什么问题**：范围。接一颗 MIPI 摄像头要不要写？同一套链再跑一块 Ku5P 板要不要留？
两条都会挤掉主线的收口时间。

**可选做法**：

1. 都做（MIPI 作为第四路片源，Ku5P 作为第二平台，仓库里长期并存两棵树）。
2. 都不做，只做 Z7 主线。
3. 保留为"未来工作"条目（不写实现、只写文档）。

**本项目选了什么、放弃什么**：选 2。这一节的"选了什么"只能引记录，不能引代码 ——
代码里没有 MIPI 与 Ku5P 的痕迹（本次实测：`src/rtl/` 下无 mipi/dsi/csi 模块；
`build/`、`src/`、`board/` 里 `grep -riln "multiboot|multi-boot|partial_reconfig|probe_region"` 输出为空，2026-10-05）。
可引的记录五条：

- `report/log/plan_v8_spec.md:49`（条目 D7，2026-09-24 晚定）：问题写"MIPI 与 KU5P 还留不留"，
  选项写"① 保留为未来工作；② 全部抛弃，只做 Z7 主线"，结论"**选 ②：抛弃**"，
  并写明影响（KU5P 的台架/文档/上板窗口退出 V8 工作清单；MIPI 连"未来工作"也不写）。
- `report/background_and_novelty.md:95` 给的是**技术前提**：这颗 Zynq-7020 没有 D-PHY 硬核，
  板上那个 FPC 只引出 CSI-2 差分对 ⇒ 接 MIPI 需要外加解串与 lanes 时序，不是"少写一个模块"。
- `report/architecture.md:6`：第二块板（RK-XCKU5P-F）的工程已于 2026-09-28 从仓库撤出（`ku5p/` 整棵树删除）。
- `report/log/contest_checklist.md:12`：把它写成"一块，且只宣称这一块"。
- `report/modules.md:123`：撤出的连带后果 —— `eth_ctrl` **没有台架例化本层**
  （原来那支单测随 Ku5P 那棵树一并撤出），该行的"验证"栏因此是空的。

**代价**（能给的都给了出处）：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 放弃的能力 | 第四路片源（相机）与第二平台的交付面 | 【报告记录】 | `report/log/plan_v8_spec.md:49` |
| 撤出的连带欠账 | `eth_ctrl` 无本层台架，只由顶层台架端到端覆盖 | 【报告记录】 | `report/modules.md:123` |
| 曾做过又被撤的部分 | `report/background_and_novelty.md:76` 记 `xcku5p`（纯 PL 无 PS）用同一套链跑通过，移植暴露两处原设计问题 | 【报告记录】 | `report/background_and_novelty.md:76` |
| 换来的东西 | 全部凭据集中在一棵树、一块板 | 【报告记录】 | `report/log/contest_checklist.md:12` |

**证据来源**：`report/log/plan_v8_spec.md:49`；`report/background_and_novelty.md:76`、`:95`；
`report/architecture.md:6`；`report/log/contest_checklist.md:12`；`report/modules.md:123`；
本目录本次 grep（2026-10-05）。

小结 1：这一节给读者的不是"这两件事不重要"，而是"这是一个有记录、有连带欠账的范围决定"。
小结 2：撤出 Ku5P 留下的那格空（`eth_ctrl` 无本层台架）是下一篇该收的坑，本篇不代它下结论。
下一步：第 13 节，构建侧的旋钮。

## 第 13 节 实现策略与 phys_opt 旋钮为什么保持默认

**面对什么问题**：时序差最后零点几 ns 的时候，工具给了三类免费旋钮：
换实现策略（`Performance_*` 一族，内部含 performance extent 档位）、开布线前/布线后
`phys_opt_design`（各带 directive）、给高扇出网强制复制。要不要在构建脚本里把它们钉死？

**可选做法**：

1. 在构建脚本里写死一个"最好的"策略与 directive 组合。
2. 全部保持工具默认，需要时由环境变量临时指定，并把名字打进构建日志。
3. 每次构建都扫一遍策略、取当轮最优。

**本项目选了什么、放弃什么**：选 2。代码事实：

- 默认那一档没被动过：`build/tcl/build_system_axigpio.tcl:291-297` 把 build#16 试过的旋钮**撤掉**了，
  注释留着当时的读数（`Performance_ExtraTimingOpt` 把 `clk_pix→clk_pix5x` 从 −0.485 抬到 +0.788、
  intra-5x 收到 −0.327，但整轮仍红），并留一条历史结论
  "`Performance_Explore` 与默认策略产出逐位相同的 bit ⇒ 那不是个可选项"。
- 旋钮走环境变量并打印出身：`:312-323`（`IMPL_STRATEGY` + `BUILD_STRATEGY <名字>`）、
  `:337-352`（`IMPL_PRPO=1` 才开 `STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED` +
  `ARGS.DIRECTIVE AggressiveExplore`，默认关）。注释给的理由是"产物自己带着出身"。
- 扫描工具有，但只用于比较不用于采纳：`build/tcl/sweep_impl_strategy.tcl:5`、`:99-101`
  （收尾把 `impl_1` 的 strategy 恢复成扫描前的值）。
- 强制复制那一刀留在候选件里：`build/tcl/r117_post_place_hook.tcl:45-55`
  （`phys_opt_design -force_replication_on_nets`，并记了一条工具用法教训：
  `catch` 成功时返回 `"0"`，判错法会把一次成功的 phys_opt 打死整条 impl run）；
  默认不挂，要 `IMPL_POST_PLACE_HOOK`（`build/tcl/build_system_axigpio.tcl:324-336`）。
  对照滚动的写法在 `build/tcl/mf114_roll.tcl:21-30`、`:135-154`。

**代价与读数**：

| 项 | 数 | 标签 | 出处 |
|---|---|---|---|
| 只换策略的两滚 | hold 三档 0.046/0.051/0.051（一位没买到）；setup 第二档从 +0.516 花到 +0.157 | 【报告记录】 | `report/40-optimization.md:69`、`:109`；逐轮件名 `report/optimization_log.md:689-690` |
| 布线后 phys_opt（`AggressiveExplore`） | 读数与基线逐位相同（WNS 0.553 / WHS 0.049 / 0 / 50883 / BRAM 95）⇒ 结构性空转 | 【报告记录】 | `report/40-optimization.md:72`；`report/optimization_log.md:808-818` |
| 一个不存在的策略名 | `Performance_ExploreWithHierarchy` 在 `set_property` 那步就被拒 ⇒ 记 NOT_MEASURED，不写成否决 | 【报告记录】 | `report/40-optimization.md:73`、`:111`；`report/perf_report.md:426` |
| 当前名册（默认流程的产物） | WNS +0.739 / WHS +0.052 / WPWS 0.264 / 0 失败端点 / 总端点 51135 | 【实测】 | `build/report/timing_summary.rpt:151`；`data/metrics.csv:5`、`:7` |
| 唯一被采纳过的一档 | `Performance_ExploreWithRemap` 把 WHS 从 0.019 抬到 0.028，r57 采纳并在两份构建日志里留下策略名 | 【报告记录】 | `build/tcl/build_system_axigpio.tcl:313-316`；`report/log/overnight_log.md:3589-3597`、`:3664-3677` |

**两种解释、本次未区分**：`build/tcl/build_system_axigpio.tcl:291-297` 撤掉旋钮的理由写的是
"留这个旋钮在这里没有意义（默认结构不需要它）"，而同一段给的读数是**改善过但仍红**。
机制上有两种说法：① 默认结构本身没有那条被改善的路，旋钮改善的是别处；
② 那一轮的红点根本不在 setup 侧。区分方法：把 `build/failed_r24/` 那件的失败端点名册
与当前 `build/report/timing_summary.rpt` 的逐时钟表（`:179-188`）对一次 ——
本次未做（该件属历史轮）。

**证据来源**：`build/tcl/build_system_axigpio.tcl:291-297`、`:312-336`、`:337-352`；
`build/tcl/sweep_impl_strategy.tcl:5`、`:99-101`；`build/tcl/r117_post_place_hook.tcl:45-55`；
`build/tcl/mf114_roll.tcl:21-30`、`:135-154`；`report/40-optimization.md:69`、`:72-73`、`:109-111`；
`report/optimization_log.md:257`、`:313-314`、`:689-690`、`:802-819`；`report/perf_report.md:426`；
`build/report/timing_summary.rpt:151`、`:179-188`；`data/metrics.csv:5`、`:7`。

小结 1：这一节的选择是"旋钮不进脚本"，因为它买到的东西在记录里两次都是零或负；
而代价是**每次都要能说出这颗 bit 是哪一档跑出来的** —— 于是有了 `BUILD_STRATEGY`/`BUILD_PRPO` 两行打印。
小结 2：通用侧（performance extent 与 directive 到底改了搜索的哪些步）在 `next-layer.md` 第 5 节。

## 第 14 节 "当初想做成的样子"（未被实现证明的条目）

本节单列，因为设计意图类内容只允许写在这里：**以下几条没有实现或报告能证明，不许当事实念**。

1. "左右两半各画一整幅对照"曾经是演示口径。当前实现已经不是（第 8 节），
   但 `src/rtl/video/split_display.v:2-3` 的文件头仍写 `Dual-pane: left original / right processed+zoomed`，
   `src/rtl/top/pl_video_top.v:241` 也留着 `left_pane` 这个只喂调试位的量。
   这一条只能写成"名义还在、行为已换"。
2. `src/rtl/video/split_ctrl.v:3` 的文件头写"本模块目前没有被任何顶层例化"，
   而它现在被例化在 `src/rtl/top/pl_video_top.v:885-891`。
   本篇不推测这句话是哪一轮留下的，只报"注释与接线不一致"这一件事。
3. "拔线立刻把屏幕交回 PS"是演示期望；实现里往 PS 方向要等 20 ms 静默 + 两边都空闲
   （`src/rtl/util/src_arb.v:18-20`、`:67-76`）。这个延迟被注释写成有意的滞回，
   但"演示时看不出来"这一句没有板级计时凭据 ⇒ 本篇不给。
4. "PS 侧那条 `split 100` 会推到整屏"的期望：`src/ps/main.c:125-141` 记的是相反的事实 ——
   字段只有 10 位（最大 1023）而屏宽 1024，于是"要整屏处理图"会得到"整屏原图"，
   并留下两份探针件名（`build/probe_split100_old.txt`、`build/probe_split100b_old.txt`，本次未打开）。
   修法是在 PS 侧夹住并**明说夹了**（`:162-169`）。
5. 第 8 节做法 3（先并排拼成一张图再显示）从未实现，也没有任何记录说它被否过 ⇒ 登记为"未实现、动机不明"。
6. "第二块板证明链子可移植"这个愿望：`report/background_and_novelty.md:76` 记的是一次做通过的移植，
   随后整棵树于 2026-09-28 撤出（`report/architecture.md:6`）。撤出的动机只引
   `report/log/plan_v8_spec.md:49` 那条 D7 原文，本篇不替作者补理由。

小结 1：本节 6 条里，第 1、2 条是"注释与代码冲突"，第 3、4 条是"只有注释支撑的期望"，
第 5、6 条是"没有实现/没有动机的记录"。四类要区别对待，不能合并成一句"设计意图"。
小结 2：要把本节任一条升级为事实，需要的动作分别是：改注释或加门禁（1、2）、板级计时（3）、
打开那两份探针件（4）、由队伍确认（5、6）。下一步：第 15 节。

## 第 15 节 小结与下一步

十三个取舍合起来是一条主线：**能把判断搬到别处就搬**（搬到 PL 判、搬到报告里数、搬到运行时位、
搬到主机换算、搬到源头寄存一拍），凡搬不动的地方就写死成一条不许外部覆盖的参数
（`src/rtl/process/proc_pipeline.v:22`、`src/rtl/video/raw_line_delay.v:39-41`）。
本篇给的数字里【实测】类可以现在复核；【注释记载】类要等下一次构建或台架才能验；
两处冲突（第 5 节的 3.6 %、第 6 节的行环归属）已如实登记，没有替任何一方圆场。

下一篇读 `next-layer.md`：本篇里被划给"通用原理"的部分（AXI 协议条款、CDC 约束语义、
缓存一致性 API 的确切含义、实现策略内部到底改了什么、HDMI 源端窗的规范条文）都在那里，
每条给"下一层读哪一节"与"学会的标志"。要动手复核本篇任何一条，
`hands-on.md` 实验 1/3/5 是给得起来的。

## 第 16 节 自测题

题目 1：**第 6 节那句"结果缓冲 `1024×17` 是一块 RAMB36"到底成不成立？**
本篇不回答。去查两处：`src/rtl/process/bilin/fb_bilin.v:178-184`（声明与那句注释）与
`build/report/methodology.rpt` 里 SYNTH-6 段中 `u_pl/u_bilin/res_reg` 那一行 ——
答出来的判据必须包含"报告里那件的个数"，不能只有注释。

题目 2：**第 13 节"`Performance_Explore` 与默认策略产出逐位相同的 bit"这条结论的适用范围是什么？**
去查：`build/tcl/build_system_axigpio.tcl:291-297`，再打开 `report/40-optimization.md:69` 与
`report/perf_report.md:426`，说出为什么"逐位相同"这一条**不能**推广到
`Performance_ExploreWithRemap`。

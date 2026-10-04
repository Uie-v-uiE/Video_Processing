# 资源占用与它的代价

这一章只念我在 `build/utilization.rpt`、`build/methodology.rpt`、`data/metrics.csv` 三件里
实际读到的数字，每个数旁边给文件名 + 那一行的原文片段。三件报告头一致：Design `system_top`、
Device `xc7z020clg484-2`、`utilization.rpt` 的 `Design State : Routed`（`build/utilization.rpt` 报告头）、
`methodology.rpt` 的 `Design State : Fully Routed`。

## 占用读数（`build/utilization.rpt`）
| 资源 | 读数 | 原文片段（该行） |
|---|---|---|
| Slice LUT | 14154 / 53200（26.61 %） | `\| Slice LUTs \| 14154 \| 0 \| 0 \| 53200 \| 26.61 \|` |
| Slice 寄存器 | 8188 / 106400（7.70 %） | `\| Slice Registers \| 8188 \| 0 \| 0 \| 106400 \| 7.70 \|` |
| Block RAM Tile | 95.5 / 140（68.21 %） | `\| Block RAM Tile \| 95.5 \| 0 \| 0 \| 140 \| 68.21 \|` |
| — RAMB36/FIFO | 93（66.43 %） | `\| RAMB36/FIFO* \| 93 \| 0 \| 0 \| 140 \| 66.43 \|` |
| — RAMB18 | 5 / 280（1.79 %） | `\| RAMB18 \| 5 \| 0 \| 0 \| 280 \| 1.79 \|` |
| DSP | 19 / 220（8.64 %） | `\| DSPs \| 19 \| 0 \| 0 \| 220 \| 8.64 \|` |
| LUT as Distributed RAM | 4044 | `\| LUT as Distributed RAM \| 4044 \| 0 \|` |
| BUFGCTRL | 8 / 32（25.00 %） | `\| BUFGCTRL \| 8 \| 0 \| 0 \| 32 \| 25.00 \|` |
| MMCME2_ADV | 2 / 4（50.00 %） | `\| MMCME2_ADV \| 2 \| 0 \| 0 \| 4 \| 50.00 \|` |
| Bonded IOB | 27 / 200（13.50 %） | `\| Bonded IOB \| 27 \| 27 \| 0 \| 200 \| 13.50 \|` |
| IDELAYE2 | 5（2.50 %） | `\| IDELAYE2/IDELAYE2_FINEDELAY \| 5 \| 5 \| 0 \| 200 \| 2.50 \|` |
| Unique Control Sets | 335（2.52 %） | `\| Unique Control Sets \| 335 \| \| 0 \| 13300 \| 2.52 \|` |

`data/metrics.csv` 对同样四项各有一行、与上表一致：第 8 行「Slice LUT 占用,资源,14154（26.61 %）」、
第 9 行「Slice 寄存器占用,资源,8188（7.70 %）」、第 10 行「Block RAM Tile 占用,资源,95.5 / 140（68.21 %）」、
第 11 行「DSP48 占用,资源,19 / 220（8.64 %）,个,…用在缩放/旋转的坐标乘法与 gamma 计算」。

## BRAM 的口径（要说清才不误导）
- 95.5 是 **tile** 数不是 RAM 块数：`utilization.rpt` 第 3 表把每片 RAMB36 计 1、每片 RAMB18 计 0.5，
  所以是上表 `93 + 5×0.5 = 95.5`；分母 140 是器件的 tile 总数（同一行 `Available` 列）。
- 口径是"实现后 Routed"（报告头 `Design State : Routed`），不是综合估算。
- 主要去向：帧缓存 + ETH↔AXI 的 `dc_fifo` + 窗口级行缓。定性依据 `data/metrics.csv` 第 10 行
  「帧缓存由 64-bit 宽 + 乒乓两块拼出，是 BRAM 的主要去向」。
- 68.21 % 是全设计里最紧的一项：LUT（26.61 %）与寄存器（7.70 %）都留有余量，压缩点在 BRAM 与
  快域读口。这一点 `report/perf_report.md` §4b 也这么讲（那节里的具体百分比是旧轮数字，本章不引）。

【未实测】：当前版本**逐实例**的 BRAM/DSP 归属（帧缓存到底吃几片、DSP 落在哪几级）。查过
`build/utilization.rpt`——它只给合计 95.5 tile / 19 DSP，不带实例层次；分层件 `build/util_hier.rpt`
是更旧一轮的产物，未与本报告同一轮重生成，故不当当前值念。

## 时序余量的口径（`data/metrics.csv`，其证据文件列为 `build/timing_summary.rpt`）
- setup WNS = **0.739 ns**：第 5 行「全局 setup WNS,核心,0.739,ns,失败 setup 端点 0 / 总端点 51135；
  板上 r118 bit cd04907e1369」。WNS 是全设计最负的 setup slack（单位 ns）。
- hold WHS = **0.052 ns**、WPWS = 0.264：第 7 行「全局 hold WHS,核心,0.052,ns,失败 hold 端点 0 /
  总端点 51135；WPWS 0.264；这一格是片内族（本版无输入窗）」。
- 口径必须一起念：这版**不带 RGMII 输入窗**。第 6 行「收口 I/O 的 5 个端点当前无输入窗 = 未检查
  （H5：未检查不等于满足）」。所以"失败端点 0 / 总 51135"讲的是**片内路径**，不等于收口 I/O 已过。

## 这些占用换来的代价（`build/methodology.rpt`，报告头 `Checks found: 446`）
| 规则 | 计数 | 原文片段 |
|---|---|---|
| SYNTH-5（因时序约束映射为分布式 RAM） | 336 | `\| SYNTH-5 \| Warning \| Mapped onto distributed RAM because of timing constraints \| 336 \|` |
| SYNTH-6（RAM block 时序可能非最优） | 98 | `\| SYNTH-6 \| Warning \| Timing of a RAM block might be sub-optimal \| 98 \|` |
| TIMING-18（缺 input/output delay） | 7 | `\| TIMING-18 \| Warning \| Missing input or output delay \| 7 \|` |
| DPIR-1（异步驱动检查） | 2 | `\| DPIR-1 \| Warning \| Asynchronous driver check \| 2 \|` |
| LUTAR-1 / TIMING-9 / TIMING-10 | 1 / 1 / 1 | `\| LUTAR-1 \| … 1 \|`、`\| TIMING-9 \| … 1 \|`、`\| TIMING-10 \| … 1 \|` |

读法：336 条 SYNTH-5 是"把窗口级行缓与 `raw_line_delay` 走 LUT-RAM"这一选择的直接代价——它换来
BRAM 余量，代价是工具按约束把 4044 项映射成分布式 RAM（`utilization.rpt` 的 LUT as Distributed RAM），
`proc_morph.v` 文件头第 7 行也自述掩码只存 1 bit/像素、配两条行缓存。DPIR-1 那 2 条点名
`u_pl/u_split_ctrl/prod` 的 B 输入挂的是异步复位寄存器、挡住 DSP 内部寄存器合并
（`build/methodology.rpt` 细节段）。TIMING-18 有 7 条"缺 I/O 延时"，方向与本版退回输入窗一致；但
7 与 metrics 说的"5 个收口端点"数目不等，我没有把这 7 条逐个对到引脚，故只并列、不合并成一个结论。

## 功耗（`data/metrics.csv` 第 27–29 行；证据文件列为 `build/power.rpt`）
- 动态功耗 **2.213 W**：第 27 行「实现后动态功耗,资源,2.213,W,本轮（r109）的实现后报告里
  `Dynamic (W)` 那一行（片上合计 2.391 W…）；工具置信度 Low」。⚠ 该表自己标注这一格是 **r109 轮**的
  报告，未随当前位流重取。
- 结温 **52.6 ℃**：第 28 行「结温估算,资源,52.6,℃,…这是工具估算，不是板上 XADC 读数」——是估算。
- 板上 XADC 实测 **61.2 – 61.7 ℃**：第 29 行「片上结温（板读 XADC）,资源,61.2 – 61.7,℃」，
  同表注明这是六次读数的极值、不是精度声明。

## 与资源配套的功能性读数（`data/metrics.csv`）
- SD 本地播放帧率 **29.8 – 30.0 fps**：第 12 行「SD 本地播放帧率,实测,29.8 – 30.0,fps,…100 帧滑窗读数；
  串口 115200-8N1」。
- UDP 入口负载 **9.2 MB/s**：第 13 行「UDP 入口负载,口径,9.2,MB/s,512×300×2 B × 30 fps 的计算值…
  **这是负载口径不是实测带宽**」。
- 越界机会计数 **190464 拍**：第 17 行「越界读写的机会计数,功能正确性,190464,拍,…」。

【未实测】：当前版**实测入口吞吐（MB/s）**。查 `data/metrics.csv`——第 22、23 行给的是 30.007 fps
的板读数与 300 s 长跑 0 丢帧，第 13 行给 9.2 MB/s 的计算负载口径，没有哪一行直接写"实测 MB/s"。

## 本章依据的产物
- `build/utilization.rpt`
- `build/methodology.rpt`
- `data/metrics.csv`
- `src/rtl/process/proc_morph.v`
- `report/perf_report.md`（仅引其资源口径的定性说法，未引其数字）

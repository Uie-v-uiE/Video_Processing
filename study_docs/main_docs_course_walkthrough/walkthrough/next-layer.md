# next-layer.md · 相邻知识地图：本项目没深挖的六件事，下一层读哪里

读完这篇能回答哪三个问题：

1. 这套文档在我没深挖的地方，边界画在哪一句、依据是哪个文件？
2. 要把那一层补上，该读哪份文档的哪一节（带文档号/URL 与核对日期），以及那份口径的原话是什么？
3. 我怎么知道自己学会了？——每条都有一个不需要板子、不需要问别人就能做完的小验证。

## 目录

- 第 1 节 这一篇的读法：四件一组的格式 + 外部出处的本次取得状态
- 第 2 节 AXI4 / AXI4-Lite / AXI-Stream 的语义差别与 burst 类型
- 第 3 节 CDC 形式核查：`set_clock_groups` 与 `set_max_delay -datapath_only` 各表达什么
- 第 4 节 部分重配置（PR）与 Multi-Boot
- 第 5 节 PS 侧缓存一致性与 DMA：本工程实际做到哪一步（核实结果）
- 第 6 节 时序收敛的实现策略选项：旋钮内部改了什么
- 第 7 节 HDMI 源端 TMDS 时序：规范口径 vs 本工程实测口径
- 第 8 节 与别的篇目的接缝（哪些已经讲透，这里只指路）
- 第 9 节 本篇的未确认清单与去处
- 第 10 节 小结与下一步
- 第 11 节 自测题

## 第 1 节 这一篇的读法：四件一组的格式 + 外部出处的本次取得状态

每条六件，顺序固定：

| 件 | 内容 | 硬性形式 |
|---|---|---|
| ① 零术语版 | 不用行话说一遍 | 紧跟一句「这样说会在 X 情形下误导你」，没有这句就不许写简化版 |
| ② 这里为什么没做 | 本工程的边界画在哪一行、不做的代价是什么现象 | 必须给 `文件:行` 或报告字段 |
| ③ 精确定义 + 出处 | 规范/官方文档的口径 | 带文档号或 URL + 核对日期；取不到正文就降级为现象描述并写明降级 |
| ④ 它不是什么 | 与最容易混的那一个的差别 + 本工程观察点 | 观察点必须落在 `文件:行` 或报告的某一列 |
| ⑤ 学会的标志 | 一个能独立做完的小验证 | 写成"打开 X，看 Y，出现 Z 才算过" |
| ⑥ 两个题外应用场景 | 这个机制在别的系统里以什么面目出现 | 两个，各自一句"在哪儿 + 会以什么症状出现"，不许写"很常见""很重要" |

### 1.1 外部出处本次（2026-10-05）的取得状态

| 想引的东西 | 通道 | 状态 | 正文怎么处理 |
|---|---|---|---|
| AXI 协议条文 | `https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf`（Arm `IHI 0022H`，封面标题 *AMBA AXI and ACE Protocol Specification*，页脚 `ID040120`，500 页） | **本次下载到并逐页抽取文本** | 引章节号与印刷页码（A3-41 / A3-44 / A3-49 / B1-120），可复核 |
| UG949 的时钟组 / CDC 约束 / 实现策略条文 | `https://www.mouser.com/pdfDocs/ug949-vivado-design-methodology.pdf`（第三方镜像；`UG949 (v2019.1) June 26, 2019`，封面标题 *UltraFast Design Methodology Guide*，302 页） | **本次下载到并逐页抽取文本** | 引第 3/4 章与印刷页码 138、171-172、175-176、197 |
| 同一份文档的官方正文页 | `https://docs.amd.com/r/en-US/ug949-vivado-design-methodology` | 打开后**取不到正文**（返回的是无正文的容器页） | 引用时说明"官方站需渲染，本次以 PDF 文本为据" |
| UG904 / UG906 / UG892 / UG835 的**文档号↔标题**对应 | UG949 正文自己的引用清单（本次抽取到） | 标题对应**有据**；这些文档的**正文本次未取得** | 只作"下一层去哪读"的指针，不引它们的内容 |
| HDMI 1.4 §4.2.4 Table 4-24 等规范条文 | 仓库取证件 `report/io/hdmi_cts_source_window.md:20-24`（内含 HDMI 1.4/1.3/1.1 镜像 PDF、Keysight 与 Tektronix 公开文档的 URL 与页码，核对日期 2026-10-04） | 本次**没有重新抓取原文** | 引用时说"仓库已登记的取证记录"，并标 `【本次未复核外部原文】` |
| UG909（Partial Reconfiguration） | 镜像 `http://ivpcl.unm.edu/ivpclpages/Research/drastic/PRWebPage/ug909-vivado-partial-reconfiguration.pdf` | 本次下载到 643 KB 但**解析失败**（`pypdf` 报 `Invalid object in /Pages`）⇒ 未取得正文 | 第 4 节整节的"规范口径"降级为现象描述，只给指针 |
| UG470（7 系列配置 / MultiBoot） | 三个通道都试过：`www.xilinx.com/support/documents/...` 返回 404、`eng.auburn.edu` 镜像取到 1.7 MB 但同样解析失败、`mouser` 返回 403 | **未取得正文** | 同上：只给指针 + 状态，不写条文内容 |

一句判据：**上面任何一行状态不是"本次抽取到"的，正文里就不许出现"规范说……"这种句式**；
只许出现"本工程的读数/写法是……，规范口径要去 X 的哪一节核对"。

### 1.2 与 `mechanics.md` 的关系

交付物清单里还有一篇 `mechanics.md`（"本项目用到但未解释的机制，逐条配出处"），它现在**未开始**，
阻塞原因登记在 `_progress.md` 第 1 节与 `_sources.md` 第 3 节（当时两次外部抓取失败）。
本次把两份外部文本真的取到了（见 1.1 前两行），因此那批机制里至少有两条已经够格写进 `mechanics.md`：
AXI 的 VALID/READY 独立性（第 2 节 ③）与异步 CDC 不该按时序判（第 3 节 ③）。
这一篇不替 `mechanics.md` 写完它们，只把"读哪一节 + 学到什么算够"放在这里。

小结 1：这一篇的可信度全在 1.1 那张表上——每一条外部口径后面都必须挂着"本次真打开过"或"降级"。
小结 2：想看本工程已经用到的那两层（结构与时序），先读 `clocking-and-reset.md` 与
`design-choices.md`；这一篇只管它们外面那一层。下一步：第 2 节。

## 第 2 节 AXI4 / AXI4-Lite / AXI-Stream 的语义差别与 burst 类型

**① 零术语版**：三种"问硬件要数据"的规矩。一种只能一次问一个字（写寄存器用）；
一种可以一次报一个地址、然后成串地收一串数据（搬画面用）；还有一种根本不问地址，
数据像水管一样流过去、只带"这是第一拍""这是最后一拍"两种标记
（比喻，不是实现；本工程没有 AXI-Stream 接口，最接近"这拍有效"的线是
`src/rtl/video/video_timing.v:68` 的 `de`/`frame_start`，见下面第 ② 层那一行）。
**这样说的误导处**：把"一次问一个字"听成"更慢"——它慢不在字节数，而在**不能成串、
也不能同时在路上放好几笔**；把"像水管"听成"没有握手"——它照样有"我这拍有效 / 你收不收"两根线。

**② 这里为什么没做**

本工程的 AXI 用量很小，两条路各用一种，第三条完全没用：

| 本工程用的 | 落在哪 | 用到的那一小块语义 |
|---|---|---|
| PS → PL 的寄存器写（GP0） | `build/tcl/build_system_axigpio.tcl:99`（`PCW_USE_M_AXI_GP0 {1}`）、`:190-197`（GP0 接三只 `axi_gpio` 的 `S_AXI`）、`:244-246`（地址钉 `0x41200000/0x41210000/0x41220000`） | 整字写、读回；没有突发概念 |
| PL → PS 的 64 位数据（HP0） | 同文件 `:100`（`PCW_USE_S_AXI_HP0 {1}` + `DATA_WIDTH {64}`）、搬运机 `src/rtl/axi/axi_frame_writer_gated.v:25-35` | 突发读：`arsize=3'b011`（8 字节）、`arburst=2'b01`（INCR）、`arlen=15`（16 拍），最多 4 笔在途（`:37-38`、`:41-47`） |
| AXI-Stream | **没有**：本工程没有 AXI-Stream 接口，像素流在 PL 内部用 `de`（数据有效）+ 栅格计数走（`src/rtl/video/video_timing.v:68`） | — |

所以"三者的语义差别"在本工程里没有对照面，写进正文就成了没有落点的空话 ⇒ 挪到这里。
代价是**看得见的两处**：

1. `arsize/arburst/arlen` 这三个信号在本工程是硬编码的常量
   （`src/rtl/axi/axi_frame_writer_gated.v:37-38`、`:132`、`:150`），
   换 burst 类型要动的不只是这里，还有 `:149` 的地址算式 `base_r + burst_idx * (BEATS * 8)`
   ——那一行本身就是 INCR 假设。
2. 写侧还有一台 `axi_frame_saver64`（`src/rtl/eth/eth_udp_video_top.v:354-367`），
   它的 `awlen/awburst` 与读侧是两套参数；两边各自成立不等于合起来成立。

**③ 精确定义 + 出处**（Arm `IHI 0022H`，PDF 本次抽取文本，核对日期 2026-10-05）

| 口径 | 原文要点（抽取到的表述） | 位置 |
|---|---|---|
| 握手独立性 | *The VALID signal of the AXI interface sending information must not be dependent on the READY signal of the AXI interface receiving that information.*；接收方**可以**等 VALID 再抬 READY，也可以先抬 READY | A3.3.1 *Dependencies between channel handshake signals*（印刷页 A3-44 起）；基础握手在 A3.2.1 *Handshake process*（A3-41） |
| burst 三型 | *The AXI protocol defines three burst types*：`FIXED`（每拍同一地址，用于反复访问同一位置，例如灌/倒 FIFO）、`INCR`（每拍按传输大小递增，用于普通顺序内存）、`WRAP`（类似 INCR，到界回绕；起始地址必须按每拍大小对齐、长度只能是 2/4/8/16 拍） | A3.4 *Transaction structure* → *Burst type*（印刷页 A3-49～A3-50） |
| size 编码 | `AxSIZE=0b011` ⇒ 每拍 8 字节（Table A3-2 *Burst size encoding*） | A3-49 |
| AXI3 vs AXI4 | *AXI3 supports burst lengths of 1-16 transfers, for all burst types*；AXI4 把 `INCR` 扩到 1-256 拍，其它型不变；长 INCR 可被拆成多个小突发 | A3.4 *Burst length*（A3-48～A3-49） |
| AXI4-Lite | Part B 专章：B1.1 *Definition of AXI4-Lite*（B1-120）、B1.2 *Interoperability*（B1-122） | Part B |
| AXI-Stream | **本次未取到该文档**（AXI-Stream 的规范是另一份 `IHI 0051`，本轮没有打开） | ⇒ 本条只写"本工程没用"，不写它的条文 |

本工程的对应取值：`arlen = 15`（16 拍）落在 AXI3/AXI4 都允许的范围内；`arsize = 8 字节`
正好是 HP0 的 64 位数据宽；`arburst = INCR` 与 `:149` 的地址算式一致。

**④ 它不是什么 + 本工程观察点**

- AXI4-Lite **不是**"不能并发的 AXI4"，而是**没有 burst、没有响应/数据的 ID 那套**的独立接口。
  观察点：三只 GPIO 全挂在 GP0 上、每个只有一张 8 字节内的寄存器窗
  （`build/tcl/build_system_axigpio.tcl:244-246` 的 `S_AXI/Reg` 三条），
  而视频帧 307200 B 走的是另一条 64 位通路（`src/rtl/eth/ddr_bank_commit.v:9-10` 的两个 bank 地址）。
  把这两条并成"同一种 AXI"，就会以为写寄存器也能"发一串"。
- "突发长度"不是"缓冲区大小"。本工程能同时在路上的量是 `MAX_OUT = 4` 笔 × 16 拍 = 64 拍
  （`src/rtl/axi/axi_frame_writer_gated.v:45-47`，注释给的理由是"够盖住 HP0/DDR 的读延迟，
  并在这个窗口里维持约 1 拍/周期"）。
- 与 `glossary.md` 词条 22（AXI 突发与通道独立性）的分工：词条讲定义，这里讲
  "三型/三接口的对照表 + 本工程只碰了一小块"。

**⑤ 学会的标志（可独立做完）**

不碰板子、不碰构建就能做的一条：

1. 打开 `src/rtl/axi/axi_frame_writer_gated.v:37-38` 与 `:149`，再打开抽取到的
   *Burst type* 一节（IHI0022H A3-49～A3-50）。
2. 回答并写下判据："把 `arburst` 改成 `2'b00`（FIXED）之后，除了 `araddr` 之外还要改哪一行，
   数据才会仍然写进 512 个不同的格子？" —— 过关的形式是**指出 `:149` 与 `:170`
   （`fb_wr_addr <= r_pix[18:2]`）这两处里哪一处承担地址推进**，而不是只说"要改地址算法"。
3. 再加一条对照：把 `arlen` 从 15 改成 31（`:132`、`:150` 两处 `m_axi_arlen`），
   问"这在本工程会不会撞到 `TOTAL_BURSTS`（`:44`）与 `sk_level` 上界（`:84`）哪一条"。
   能指出其中一条为约束者，说明突发长度与缓冲深度已经被分开持有。

**⑥ 两个题外应用场景**

1. **外设寄存器堆**：任何 SoC 里给自己写的模块挂一组 32 位寄存器（SPI 控制器、GPIO 扩展），
   用的就是 AXI4-Lite 那一档语义；它的典型症状是"寄存器写了但下一次读回是旧值"，
   根因往往在写通路被 pipelined 而读通路没有——与本工程刻意让 `health_read.mjs` 读两遍再判
   （`src/host/health_read.mjs:22-25`）是同一类问题的另一种解法。
2. **流式加速器前端**：把摄像头/ADC 的数据连续喂给一个核（编码器、NN 加速器），
   用的是 AXI-Stream 那套"没有地址、有 TLAST 表示一包结束"的语义；
   它的典型症状是"帧尾几拍丢在上一帧里"——本工程在**另一条路**上撞过同一形状的错，
   并把修法写进了 `src/rtl/eth/ddr_bank_commit.v:6-7`（`TAIL_GUARD`：旧判据吃帧尾 4 字节）。

小结 1：本工程只用了"一次一笔寄存器写"和"16 拍 INCR 突发"这一小块，
所以三接口/三 burst 型的对照表必须放在这一篇，而不是塞进正文当既成事实。
小结 2：AXI-Stream 的条文本次没取到 ⇒ 想学它，先把 `IHI 0051` 打开再说（本仓库里没有任何
可引用的 AXI-Stream 件）。下一步：第 3 节。

## 第 3 节 CDC 形式核查：`set_clock_groups` 与 `set_max_delay -datapath_only` 各表达什么

**① 零术语版**：跨时钟域有两种"跟工具打招呼"的方式。一种说"这两组钟没关系，别去算它们之间的账"；
另一种说"它们没关系没关系，但数据走的这段路**不许太长**，给个上限"。前一种会让报告里那一格消失，
后一种会让报告里那一格换成一个上限数字。
**这样说的误导处**：会让人以为两条可以同时生效、要求可以叠加——本次抽取到的原文写的是相反的：
**已经有了前一种，后一种会被忽略**。

**② 这里为什么没做**

本工程的跨域安全**全部交给结构**，时序分析那边只做了"排除"：

| 本工程做了的 | 位置 |
|---|---|
| 三组异步声明（`eth_rxc` / `clk_fpga_0` / `sys_clk` 及其生成钟） | `src/constraints/clock_groups_impl.xdc:28-31`；为什么单独成文件、只在实现阶段绑：`:3-8` |
| 四条结构保证（格雷码 FIFO / 翻转+3 拍 / 3 级像素+3 拍 / 3 拍控制字） | 同文件 `:19-23` |
| 结构核查读数（配对集合、Safe/Unsafe/Unknown 计数） | `build/report/cdc.rpt:15-18`；门禁按配对集合判：`build/gates.sh`（口径登记在 `_sources.md` 第 1 节） |
| **没有做的**：给任何一对异步钟加 `set_max_delay -datapath_only` | 记账在 `report/timing/debt_ledger.md:94-101`——原文："这两对被整体排除，没有任何 `set_max_delay -datapath_only` 给出界……界叠不到被排除的时钟对上" |
| **没有做的**：MTBF 类工具读数（`report_synchronizer_mtbf`） | 本次在 UG949 p.138 抽取到这条命令名；仓库内 `grep -rn "report_synchronizer_mtbf" build report src` 本次实测 0 命中 ⇒ 没跑过 |

不做的代价（可观察的现象）：**跨域那批路径不产生任何时序读数**，于是"时序名册全绿"这件事
对它们既不证明也不否证。这条在 `myths.md` 第 12 节已经落成辨认法，此处不重复。

**③ 精确定义 + 出处**（UG949 v2019.1，PDF 本次抽取文本，核对日期 2026-10-05）

| 口径 | 抽取到的原文要点 | 位置 |
|---|---|---|
| `set_clock_groups` | *Disables timing analysis between groups of clocks that you identify but not between the clocks within a same group.* | 第 3 章 *Defining Clock Groups and CDC Constraints*，印刷页 171 |
| `set_max_delay -datapath_only` | *Sets the maximum delay constraints on asynchronous CDC paths to limit the latency.* | 同页 171 |
| 两者的冲突（关键那一句） | *If clock groups or false path constraints already exist between the clocks or on the same CDC paths, the maximum delay constraints will be ignored. Therefore, it is important to thoroughly review every path between all clock pairs before choosing one CDC timing constraint over another to avoid constraints collision.* | 同页 171-172 |
| 推荐动作 | *RECOMMENDED: Xilinx also recommends running `report_methodology` to identify when a `set_max_delay -datapath_only` constraint is overridden by a `set_clock_groups` or `set_false_path` constraint.* | 同页 172 |
| 另一条同类约束 | `set_bus_skew` *Constrains a set of signals between asynchronous CDC paths by bus skew instead of latency.* | 同页 172 |
| 异步 CDC 不该按时序判 | *Asynchronous CDC paths usually have high skew and/or unrealistic path requirements. They should not be timed with the default timing analysis, which cannot prove they will be functional in hardware.* | 第 3 章 *Reviewing Clock Interactions*，印刷页 175-176 |
| `report_cdc` 是什么 | *performs a structural analysis of the clock domain crossings … does not provide timing information because timing slack does not make sense on paths that cross asynchronous clock domains*；它识别的拓扑含单比特同步器、多位总线同步器、异步复位同步器、MUX/CE 控制电路、**同步器之前的组合逻辑**、**同步器的多钟扇入** | 印刷页 176 |
| 为什么要打 `ASYNC_REG` | *You can design your own circuits, but the Vivado Design Suite must recognize the circuit and you must apply the `ASYNC_REG` attributes correctly*（并说这决定能否被 `report_synchronizer_mtbf` 识别、能否避开 `report_cdc` 报错） | 印刷页 138 |
| 文档号纠正 | UG949 正文把"Design Analysis and Closure Techniques"引作 **UG906**、"Implementation"引作 **UG904**、"Tcl Command Reference"引作 **UG835** | UG949 p.138 TIP 与 p.172 的引用行（本次抽取） |

纠正一条本仓库既有的说法：`src/rtl/eth/dc_fifo.v:23` 写"UG949 的 CDC 一节"，
而 `report/timing/a1_sources.md:10-15` 那张表把 UG949 记作 *Design Analysis*。
本次抽取到的 PDF 封面标题是 *UltraFast Design Methodology Guide*（UG949，v2019.1），
"CDC/时钟组"内容确实在它的第 3 章（p.138、171-176）；*Design Analysis and Closure Techniques* 是 **UG906**。
⇒ 念那两条出处时，"节名 + 页码"以本篇 ③ 表为准，`文件:行` 以仓库为准。

**④ 它不是什么 + 本工程观察点**

- `set_clock_groups` **不是**"证明跨域安全"，而是"我不检查这条路"。观察点：
  `build/report/timing_summary.rpt:192-199` 的 *Inter Clock Table* 只有两行
  （`sys_clk ↔ clkout0_1`），另三组之间**一行都没有**；`build/report/cdc.rpt:17-18`
  的 `Exceptions` 列写 `Asynch Clock Groups`——同一个事实的两种打印。
- `set_max_delay -datapath_only` **不是**"给跨域加保险"，而是"给数据段一个延迟上限"，
  且它与 clock groups **互斥生效**。本工程若真想加，必须先收窄排除（那会改变 WNS 的计算对象），
  这句话的凭据是 `report/timing/debt_ledger.md:100`（"那条债不能靠加约束消"）。
- `report_cdc` 的 `Unsafe/Unknown` 计数**不是**裕量：那份表里没有任何 ns 列
  （`build/report/cdc.rpt:15-18` 的表头：`Severity / Source Clock / Destination Clock / CDC Type /
  Exceptions / Endpoints / Safe / Unsafe / Unknown / No ASYNC_REG`）。

**⑤ 学会的标志（可独立做完）**

零成本的一条（只读，不需要板子、不需要构建）：

1. 打开 `build/report/cdc.rpt`，把两条 `Critical` 行的 `Unsafe` 列加起来（本次实测 `1 + 2 = 3`）。
2. 跑一次 `report_cdc -details`（需要 Vivado，读已布线的 `build/report` 那轮的 dcp），
   要求：**这 3 个 unsafe 端点每一个都能说出是哪对触发器**（`u_cdc/…` 或 `u_lat_x/…` 一类层次名）。
   说不出具体那一对 ⇒ 还没学会，只是看到了计数。
3. 再做一条纸面推演：按 UG949 p.171 那句"已有的 clock groups 会让 max_delay 被忽略"，
   判断"在当前约束集下新增 `set_max_delay -datapath_only 8.000 [get_clocks …]` 会不会出现在
   `report_exceptions` 里"。过关形式：说出**预期是 0 条例外**，并指出验证手段是
   `report_exceptions`（本工具没有 `get_timing_exceptions` 这类命令，见
   `report/timing/a1_sources.md:28`）。

**⑥ 两个题外应用场景**

1. **异步 FIFO / 串口 FIFO**：任何 MCU↔FPGA 或 FPGA↔FPGA 的跨时钟缓冲都会遇到同一组选择——
   "排除分析 + 结构保证"还是"保留分析 + 给 datapath 上限"；
   症状是"报告忽然变干净，但板上偶发读到半个字"，那正是排除范围盖住了没有同步器的多位总线。
2. **复位释放跨域**：UG949 p.138 的拓扑清单里专门有一类"异步复位同步器"（`XPM_CDC_ASYNC_RST`）。
   它的症状与本工程的 `key_debounce.v` 那一族同源：**复位支路其实走不到，
   上电值只由声明初值承载**（`src/rtl/util/key_debounce.v:1-31`、`clocking-and-reset.md` 第 2 节），
   在别的系统里表现为"上电第一帧偶尔全 0/全 F，重新上电又好了"。

小结 1：这两条约束表达的是**两种不同的承诺**——"我不算"与"我算但只算上限"，
本仓库当前选的是前者，并把后者的缺席记成了债。
小结 2：`set_bus_skew` 与 MTBF 类读数（`report_synchronizer_mtbf`）是同一层的下一格，
本工程一次都没跑过；要动它们，先按本篇第 9 节 N-2 那条问一句值不值得为读数多跑一轮。
下一步：第 4 节。

## 第 4 节 部分重配置（PR）与 Multi-Boot

**① 零术语版**：一块 FPGA 里面，可以只换一小块电路而让其余部分继续跑（部分重配置）；
也可以让芯片在启动时按顺序试好几个"开机方案"，第一个坏了用第二个（Multi-Boot）。
两者都动的是**配置这件事**，跟运行时改一个寄存器不是一回事。
**这样说的误导处**："只换一小块、其余继续跑"听起来像免费的，但前提是那一小块对外没有
三态总线、没有正在被别处采样的输出，并且它的引脚约束区域提前划好；条件不满足时它退化成
"换整片、期间画面黑掉"。

**② 这里为什么没做**

范围决定，不是技术遗漏，且**代码里连痕迹都没有**（本次实测）：

| 证据 | 结果 |
|---|---|
| `grep -rilnE "multiboot\|multi-boot\|partial_reconfig\|probe_region" src build board` | 本次执行，**输出为空**（2026-10-05） |
| 交付范围 | `report/log/contest_checklist.md:12`："一块，且只宣称这一块" |
| 决定记录 | `report/log/plan_v8_spec.md:49`（条目 D7：第二平台与 MIPI 一起抛弃）；连带后果 `report/modules.md:123`（`eth_ctrl` 没有本层台架） |
| 现役"换手"机制 | 不是 PR，是仲裁：`src/rtl/util/src_arb.v:67-76`（只在两个引擎都空闲时换主人）；两者常被混，判据见 `myths.md` 第 6 节 ⑤ |
| 位流侧现在受管的只有 | `BITSTREAM.GENERAL.COMPRESS TRUE`（`src/constraints/rk_zynq7020.xdc:77`）与 md5 身份（`_sources.md` 第 1 节"门禁 22 项"那一行的口径） |

不做的代价（现象）：想在演示中途换一套算法链，当前只能靠运行时开关
（`src/rtl/process/proc_pipeline.v:5-6` 的九位 `sel`、`src/rtl/process/bilin/fb_bilin.v:48-54` 的
`bilin_en` 运行时位），**换不了硬件本体**；代价被 `design-choices.md` 第 9、10 节的级数账接住了。

**③ 精确定义 + 出处**：**本次未取得规范正文**（1.1 表最后两行）⇒ 这一层降级为"指针 + 状态"。

- 要读的两个入口（文档号来自仓库内既有的引用与本次搜索结果，**标题↔文档号对应本次未核**）：
  部分重配置：`UG909`（仓库 `grep -rn "UG909" report skills` 本次 0 命中 ⇒ 本仓库此前没引过它）；
  Multi-Boot / 配置与启动顺序：`UG470`（同次 grep 0 命中）。
- 本次实际打开过、可以当作"边界在哪"的本地件：`report/timing/a1_sources.md:40`
  记录了本机 Vivado 安装里没有随附文档目录（`data/docs`、`help` 都不存在，`find -iname "UG*.pdf"` 为空）
  ⇒ 想走本地 PDF 这条路要先补下载通道。
- 一句不许写的：由于没有正文，本篇**不写**"PR 要求区域必须不含三态总线"这类条文体；
  只写"这一条必须去 PR 指南里核对之后才能进正文"。

**④ 它不是什么 + 本工程观察点**

- PR **不是**"运行时切换"。本工程的运行时切换全部是**同一片硬件内的多路选择**：
  效果链九位（`src/rtl/process/proc_pipeline.v:100-150` 的各级旁路）、
  双线性/最近邻一位（`src/rtl/process/bilin/fb_bilin.v:51-54`）、
  片源四态环（`src/rtl/util/src_mode.v`）。它们都在同一个已布线的网表里，不需要重新配置。
- Multi-Boot **不是**"重新下载 bit"。本工程现在换 bit 走的是 JTAG 三步链
  （`build/evidence/r90_flash_1_psboot.txt`、`r90_flash_2_program_pl.txt`、`r90_flash_3_app.txt`），
  以及 QSPI 刷写件（`build/evidence/r113_flash_console.txt`）——这些是"全片重来"，不是多镜像引导。
- 观察点（如果要评估一颗板子能不能做 PR）：先看那个区域对外有几条线。
  在本工程里这件事可以**静态**做完：`src/rtl/top/pl_video_top.v:800` 那处例化的端口清单
  就是候选区域的跨界线集合，而 `build/ports_check.txt:1` 给了全树实例分母。

**⑤ 学会的标志（可独立做完）**

不需要 PR 工具、也不需要板子的一条静态验证：

1. 选一个候选区域（建议 `u_pipe`，即效果链，例化在 `src/rtl/top/pl_video_top.v:800`）。
2. 把它对外的线全部列出来（方法：读那只例化的端口连接表，逐条标出"信号来自哪个域、
   去往哪个域"），并与 `clocking-and-reset.md` 第 3 节的跨域点全表对一次。
3. 过关形式：说出**这个区域里有几条线跨了时钟域、跨在哪一行**，
   并指出其中任意一条如果被划进可重配区域，运行时另一半还在采它会发生什么
   （答案要能落回 `myths.md` 第 3 节的翻转位/电平判据或 `src_arb` 的互锁判据）。
   说不出跨界线数量，就还不该谈 PR。

**⑥ 两个题外应用场景**

1. **软件无线电的前端可换**：同一块板上要切换两种调制/解调结构，
   用区域重配置换前端而保持链路其余部分不断流；症状是"换完前端之后旧数据被当成新帧"——
   与本工程在 `src/rtl/axi/axi_frame_writer_gated.v:75-79` 处理过的"在途数据必须排空"同一形状。
2. **工业相机的算法包升级**：现场不停机更新一个检测核，其余（采集、触发、通信）继续跑。
   这里的第一道坎不是重配置本身，而是**电源与配置存储的多镜像回滚**（Multi-Boot 那一族问题）：
   症状是"升级断电变砖"，判据要落在配置存储的启动顺序与回滚标记上。

小结 1：这一节的"没做"有记录、有连带欠账，但**规范口径这次没取到正文**，
所以整节只到"边界 + 指针"，没有条文。
小结 2：想把这一节升级成 `mechanics.md` 的一条，先解决 N-1（下载通道），
再回来补 ③ 与 ④。下一步：第 5 节。

## 第 5 节 PS 侧缓存一致性与 DMA：本工程实际做到哪一步（核实结果）

**① 零术语版**：CPU 自己有一份很快的草稿本（缓存），外面那块大内存才是真的。
如果另一个机器（DMA）直接往大内存里写数据，CPU 可能还在读自己草稿本里的旧内容；
反过来，CPU 写在草稿本里还没交出去的内容，会被 DMA 刚写进来的数据"盖掉"之后又被草稿本盖回去。
所以要"先把草稿本上的改动交出去"（clean/flush）、或"把草稿本里那份旧的扔掉"（invalidate）。
**这样说的误导处**："草稿本"会让人以为只要扔掉旧的就行——**扔掉**会把还没交出去的改动一起丢掉，
所以边界不对齐时不能直接扔。
（比喻，不是实现；实现见 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-467`（`Xil_DCacheFlushRange`）与 `:319`（`Xil_DCacheInvalidateRange`）。）

**② 这里为什么没做 / 实际做到哪一步**（本次逐行打开 `src/ps/` 与 BSP 源码核过，2026-10-05）

| 问题 | 本工程的事实 | 出处 |
|---|---|---|
| 开不开缓存 | 开：`Xil_DCacheEnable()`、`Xil_ICacheEnable()` | `src/ps/main.c:1546-1547` |
| 有没有把共享区改成不缓存（uncached 映射） | **没有**：`grep -rn "Xil_SetTlbAttributes" src/ps` 本次实测 0 命中 | 同上（否定结论，取证方式已写明） |
| 有没有用一致性端口（ACP） | **没有**：BD 里只开 `M_AXI_GP0` 与 `S_AXI_HP0`（64 位），没有任何 ACP 相关端口连线 | `build/tcl/build_system_axigpio.tcl:99-100`、`:174-175`、`:190-199` |
| PS 写帧（FILL）怎么保证 PL 读到新值 | 先用**带缓存的指针**写整帧，再对整段做一次 flush，然后才发布 | `src/ps/main.c:702`（`volatile u16 *p = (volatile u16 *)FRAME_ADDR`）、`:714`（`Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)`）、`:716`（`ps_publish()`） |
| SD 读进共享帧区之前做什么 | 每块 64 扇区读之前 flush 目标区间；给出的理由是"驱动读完会 invalidate 目标区间，但**进去**之前若有脏行，invalidate 之后脏行仍会被写回，把刚进来的数据盖掉" | `src/ps/sd_play.c:86-90`、`:95` |
| 应用自己有没有显式 invalidate | **没有**（两处 flush 之外没有第二处调用） | `grep -n "Xil_DCache" src/ps/main.c src/ps/sd_play.c` 本次实测只命中 `main.c:714`、`sd_play.c:95`、`main.c:1546` |
| 驱动在读取之后做什么 | 做：`Xil_DCacheInvalidateRange(Buff, BlkCnt*BlkSize)` | `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:351-358`（`EL1_NONSECURE` 两个分支各一条，命中的是那两处 `Xil_DCacheInvalidateRange`） |
| `flush` 到底是什么语义 | *If the cachelines are modified (dirty), they are written to the system memory before the lines are invalidated.* ⇒ clean **再** invalidate | `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-467`（`Xil_DCacheFlushRange` 的 @brief 注释与函数入口） |
| `invalidate` 的边界陷阱 | 地址未按缓存行（32 字节）对齐时，边界那一行**先 flush 再 invalidate**；注释明写这是与 Linux 一致的取舍，并警告"典型 ISR 里做 invalidate 会丢掉刚收到的数据" | 同文件 `:255-286`（说明块，其中 `:286` 是 "the second option is implemented" 那一行）、`:319`（`Xil_DCacheInvalidateRange` 入口）、`:321`（`const u32 cacheline = 32U;`） |
| SD 到底是 DMA 还是轮询 | **未区分**：调用名与注释写 "polled mode"（`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:300`（注释 "Performs SD read in polled mode."）、`:314`（函数入口）），同一份驱动的版本说明里写 "32 bit ADMA2 is selected. Default Block size is 512 bytes."（`:141`）。机制上有两种说法：① "polled" 只指命令/状态轮询，数据由控制器内部 ADMA2 搬到 `dst`；② 数据也经数据口逐拍搬。区分方法见本节 ⑤ 第 3 步 | 三行都在 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c`（本次打开） |

`design-choices.md` 第 3 节把"要不要再 invalidate"登记为"两种解释、本次未区分"。
本次打开 BSP 源码之后，其中一条**已经由原文落定**：flush 本身就是 clean+invalidate
（`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:455-467`），而 SD 读之后驱动又做一次 invalidate（`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:351-358`）。
剩下的未区分项是"SD 这条路的数据是不是 ADMA2 搬的"，那一条仍然没证据 ⇒ 写在这里，不写进正文。

**③ 精确定义 + 出处**

| 口径 | 出处 | 状态 |
|---|---|---|
| `Xil_DCacheFlushRange` / `Xil_DCacheInvalidateRange` 的行为、非对齐处理 | 本地 BSP 源码 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c`，本次打开的段落：`:255-286`（非对齐处理）、`:319`（`Xil_DCacheInvalidateRange`）、`:429-467`（`Xil_DCacheFlushLine`/`Xil_DCacheFlushRange`）（本次打开，2026-10-05） | 有据（本地件） |
| 驱动读后的 invalidate | 本地 BSP 源码 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:351-358` | 有据（本地件） |
| 一致性端口（ACE-lite/ACP）与非一致性 HP 口的差别 | **本次未取得正文**（Zynq TRM / 软件开发指南都不在可取通道内，`report/timing/a1_sources.md:40` 记了同类失败） | ⇒ 只写"本工程只用非一致性 HP0"这一事实，不写它为什么一致/不一致 |
| 缓存行大小 32 字节 | 本地件 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c`:469（`const u32 cacheline = 32U;`，在 `Xil_DCacheFlushRange` 体内） | 有据（本地件） |

**④ 它不是什么 + 本工程观察点**

- "零拷贝"在本工程指的是 **PS 不做 memcpy**，不是"没有搬运"：
  PL 侧仍要跑一次 DDR→帧缓存（`src/ps/sd_play.c:12-13` 的原话 +
  `src/rtl/top/pl_video_top.v:697` 的 `u_aw` 触发）。别把它读成"PS 写完 PL 直接就能看见"。
- flush ≠ invalidate：一个是"交出去（并且扔掉）"，一个是"扔掉（可能丢改动）"。
  本工程**只在交出去的方向上调用**，扔掉那一侧交给驱动（观察点见 ② 表最后两行）。
- 地址分开 ≠ 一致性：三条 DDR bank（`src/rtl/eth/ddr_bank_commit.v:9-10` 与
  `src/ps/main.c:41-46` 的第三块）解决的是"谁在写同一块内存"，
  不解决"写的人的缓存什么时候落地"。`pl_video_top.v:14-15` 明写仲裁管不到谁写 DDR。

**⑤ 学会的标志**

前两步零成本、第三步要板子：

1. 打开 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c:255-286`，说出"未对齐的 invalidate 会发生什么、为什么"。
   过关形式：能引用那句 "immediately after buffer allocation and before starting the DMA,
   do the invalidation" 并解释它为什么与本工程"读之前先 flush"（`sd_play.c:95`）不矛盾。
2. 打开 `main.c:702` 与 `:714`，说出"如果去掉 `:714` 那一行，最先坏的是哪个命令"
   （答案要指向 FILL 画出来的四色块会不会半新半旧，以及为什么 FILL 之后紧接
   `ctrl_set_src(1)` + `ps_publish()`（`:715-716`）会让这件事更容易看见）。
3. 板上验证 ADMA2 那条未区分项：在 `sd_play.c:95` 之后、`XSdPs_ReadPolled` 之前，
   对目标区首字节做一次读（制造缓存命中），比较屏上帧与卡上帧；
   这一步同时给出 ② 表最后一行的判决。⇒ `【需板上验证】`

**⑥ 两个题外应用场景**

1. **网口/ADC 的 DMA 收包**：任何"外设直接往内存写、CPU 随后读"的驱动都要面对同一对操作，
   症状是"包内容对但头 12 字节是旧的"——这类现象的检查点是缓存行未对齐时边界行的处理方向
   （本工程核到的规则写在 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c`:255-286`：边界那一行先 flush 再 invalidate）。
2. **GPU/显示核与 CPU 共享一张帧缓冲**：非一致性端口 + 手动 clean/invalidate 成对使用，
   症状是"画面出现上一帧的残影或半新半旧"，与本工程用"每帧一次发布 + 只在消隐窗搬"
   （`src/rtl/video/frame_commit_lock.v:117-122`）解决的是同一类时序问题，只是分层不同。

小结 1：本工程的实际做法是"开缓存 + 只在写出方向 flush + 靠驱动在读完后 invalidate +
不碰 uncached 映射 + 不用一致性端口"，这一句里每一段都有 ② 表的行号。
小结 2：没做的（TLB 属性改不缓存、ACP 一致性端口）也写清了取证方式与结果 0 命中——
**不许把它念成"做过但没必要"**。下一步：第 6 节。

## 第 6 节 时序收敛的实现策略选项：旋钮内部改了什么

**① 零术语版**：布局布线工具自己有一套"先怎么试、再怎么试"的日程表。
换"策略"是换整张日程表；换"directive"是给其中某一步换一个花样的做法。
两者都不改电路，只改工具怎么摆线。
**这样说的误导处**："不改电路"听起来"改了没风险"——它改的是**被分析对象的物理实现**，
所以每一次换档都要重新出一份名册；只念一格的改善就是拿别人的骰子当自己的收益。

**② 这里为什么没做**

`design-choices.md` 第 13 节已经把取舍与代价写完（选 2：默认档 + 环境变量临时指定 + 打印出身），
本节只补"通用口径"那一层。工程侧的边界（本次打开核对）：

| 事实 | 位置 |
|---|---|
| 策略走环境变量、不设就是工程默认 | `build/tcl/build_system_axigpio.tcl:312`、`:317-319`（被拒时打 `BUILD_STRATEGY_REJECTED`）、`:323`（打 `BUILD_STRATEGY <实际档名>`） |
| 布线后 `phys_opt` 默认关，`IMPL_PRPO=1` 才开，且写死一档 directive | `:341`、`:343-344`（`STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED` + `ARGS.DIRECTIVE AggressiveExplore`）、`:349`（打 `BUILD_PRPO on AggressiveExplore`） |
| 布线后钩子（强制复制）默认不挂 | `:324`（`IMPL_POST_PLACE_HOOK` 的说明块）、`build/tcl/r117_post_place_hook.tcl:45-55` |
| 扫策略的工具有，但收尾把档名恢复 | `build/tcl/sweep_impl_strategy.tcl:5`（参数 `SWEEP_STRATS`）、`:99-101`（恢复原 strategy，注释写"数字变了但没人改代码是最难查的那一类"） |
| 两滚读数与一次空转 | `report/40-optimization.md:69`（只换策略两滚：hold 三档 0.046/0.051/0.051）、`:72`（布线后 `AggressiveExplore` 读数与基线逐位相同）、`:73`（一个不存在的档名 ⇒ `NOT_MEASURED`） |

**③ 精确定义 + 出处**（UG949 v2019.1，第 4 章 *Implementation*，本次抽取文本，核对日期 2026-10-05）

| 口径 | 抽取到的原文要点 | 位置 |
|---|---|---|
| Strategy 是什么 | *Strategies are used by the Vivado Design Suite to control both the tool options and the reports that are generated by synthesis and implementation runs in Project Mode. You can use the strategies to adjust the implementation goals…* | 印刷页 197，*Strategies* |
| 官方推荐的起手式 | *RECOMMENDED: Try the default strategy Vivado Design Suite implementation defaults first. It provides a good trade-off between runtime and design performance.* | 印刷页 197 |
| 版本相关警告 | *Note: Strategies are tool and version specific. In some cases, strategies might require a longer runtime.* | 印刷页 197 |
| Directive 挂在哪四步上 | *Directives provide different modes of behavior for the following implementation commands: `opt_design` / `place_design` / `phys_opt_design` / `route_design`* | 印刷页 197（*Directives*） |
| 更细的读处 | 同一页把细节引向 UG904（*Vivado Design Suite User Guide: Implementation*，Ref 22）；Project/Non-Project 两种流程引向 UG892 | 印刷页 196-197 |

本工程的对应：四步里只碰了 `phys_opt_design` 的**布线后那一档**
（`:343-344`），而且默认关；`opt/place/route` 的 directive 一个字没设
（本次在 `build/tcl/build_system_axigpio.tcl` 内 grep `DIRECTIVE` 只命中那一条）。

**④ 它不是什么 + 本工程观察点**

- 换策略**不是**"改设计"。观察点：`report/40-optimization.md:73` 那一格——
  一个不存在的档名在 `set_property` 那一步就被拒（打印 `BUILD_STRATEGY_REJECTED`），
  于是那轮记 `NOT_MEASURED` 而不是"否决"。这与"跑了但没改善"是两种不同的行。
- 换 directive **不是**"一定有收益"。观察点：`:72` 那一滚读数与基线**逐位相同**
  （WNS 0.553 / WHS 0.049 / 0 / 50883 / BRAM 95），这份报告自己称"结构性空转"。
- 与 `myths.md` 第 12 节的分工：那边管"名册数字能说明什么"，
  这边管"改档为什么会动名册"。两篇不许互相代答。

**⑤ 学会的标志**

一条只读 + 一条要跑（都不需要板子）：

1. 只读：打开 `build_system_axigpio.tcl:341-349`，说出"这一档改的是 UG949 p.197 四条命令里的
   哪一条、以及为什么它不需要重跑 RTL 台架"（脚本自己在 `:340` 给了理由，念的时候要能对上
   "实现步骤不进 RTL 语义"这个口径）。
2. 要跑：用 `build/tcl/sweep_impl_strategy.tcl` 扫两档，并把**逐时钟名册**（
   `build/report/timing_summary.rpt:181-188` 那种表）逐行差分，
   过关形式是同时说出 WNS、WHS 与**总端点数**三个数（只报 WNS 一个数不算学会，
   端点数会变，理由见 `report/timing/debt_ledger.md:105-107` 的量纲红线）。

**⑥ 两个题外应用场景**

1. **发布前的 QOR 扫描**：产品封版前跑一遍策略扫描、按功耗/时序/资源三项挑一档，
   并把"这颗 bit 是哪一档跑出来的"随产物归档——本工程用两行打印做这件事
   （`BUILD_STRATEGY` / `BUILD_PRPO`，`:323`、`:349`）。症状：CI 里换了工具版本，
   默认档的内部行为跟着变，于是"没人改代码但数字变了"。
2. **器件降级/降成本**：想用同一套 RTL 塞进更小或更慢一档的器件，
   第一件试的事常常是策略而不是改设计。症状：`place` 拥塞或 `route` 失败被误读成
   "逻辑太深"，于是去改本不必改的 RTL（对照 `skills/pitfalls/tcl-and-probe-traps/SKILL.md:51-58`
   那条"报告字段/形状靠猜"的同族处理）。

小结 1：这一节的通用层只有一句是本次抽到原文的：**默认档是官方推荐的起手式，且策略是版本相关的**。
小结 2：要不要在本工程里真正启用一档，判据在 `design-choices.md` 第 13 节的两滚记录里，
本篇不重开这个决定。下一步：第 7 节。

## 第 7 节 HDMI 源端 TMDS 时序：规范口径 vs 本工程实测口径

**① 零术语版**：屏线上传的是三束数据加一束时钟。规范管的是"时钟那束和数据那束到达的时间差
不能太大、一对线内部的正负两根也不能差太多"。本工程能测到的是**芯片内部**这两段差；
芯片外面还有走线、连接器、接收端，那些没测。
**这样说的误导处**："能测到"听起来等于"合规"——本次抽取到的规范口径与工程实测之间差的正是
外面那一段与眼图那几条；所以这一节把**两个口径分开写**，不许并排念成一个。

**② 这里为什么没做**

| 没做的部分 | 为什么 | 出处 |
|---|---|---|
| 眼图掩模 / 抖动 / 占空比 / 上升下降时间 | 这几条不在 SDC 的语义里；`set_output_delay` 只约束沿的到达时刻 | `src/constraints/r119_hdmi_source_window.xdc:41-43`（"本文件不代表过 CTS"） |
| CTS 表本体 | 属 HDMI Adopter 的 NDA 材料 ⇒ 0.20 `Tcharacter` 之外的分档值只能用第三方代理 | 同文件 `:44`；取证件 `report/io/hdmi_cts_source_window.md:20-24` |
| 把窗口收进默认构建 | 新增约束会改变实现看出去的边界，必须先用一轮构建量它对逐时钟名册的影响 | `src/constraints/r119_hdmi_source_window.xdc:36-38`；开关 `build/tcl/build_system_axigpio.tcl:75-81`（当前打印 `off`） |
| 钟道自身的输出窗 | 源端的钟就是参考，对它要求的是占空比/抖动/沿/对内偏斜，都不是 SDC 量 | `src/constraints/r119_hdmi_source_window.xdc:48-49` |

**③ 两个口径，分开放**

**A. 规范口径（本次未复核外部原文，转引仓库取证件，核对日期 2026-10-04）**
`report/io/hdmi_cts_source_window.md:20-21`：

| 量 | 限值 | 登记的出处 |
|---|---|---|
| 互对偏斜（Source，TP1，max） | **0.20 `Tcharacter`**（`Tcharacter` = 像素周期；50 MHz ⇒ 4.000 ns） | 《HDMI Specification 1.4》§4.2.4 Table 4-24 行 `Inter-Pair Skew at Source Connector, max`；1.3 Table 4-16、1.1 Table 4-13 同值（1.1 写作 `0.20 T pixel`）；Keysight/Tektronix 公开文档逐句复述 |
| 对内偏斜（P 与 N 之间，max） | **0.15 `Tbit`**（`Tbit` = `Tcharacter/10`；50 MHz ⇒ 0.300 ns） | 同上表行 `Intra-Pair Skew at Source Connector, max`；CTS 侧标注频率 >165 MHz 时按此行判 |

⇒ 这两行在正文里念的时候，必须带"仓库取证件已登记、本次未重抓"这半句。`【本次未复核外部原文】`

**B. 本工程写进约束的口径**：`src/constraints/r119_hdmi_source_window.xdc:51-52`
（`set_output_delay -clock clkout1_1 -max 4.000` / `-min -4.000`，只挂 `tmds_data_p[*]/tmds_data_n[*]`），
数字来源与推导写在 `:19-26`。为什么参考钟是 `clkout1_1`（250 MHz）而不是别的：
`:29-34` + 探针件 `build/evidence/r119_ser_clock_probe.txt`；
对照 `build/evidence/r119_clock_networks.rpt` 只列 3 条主钟 ⇒ 必须从管脚反查。
中途还换过一次问法：`report/io/hdmi_tp1_sdc_measurement.md:29`、`:44-49`
记录了"直接问成品拿到 `Slack: inf` / `Path Group: (none)`"的形态，以及第二次用
`create_clock` 在钟脚上补一个 20.000 ns 的参考钟后，工具把要求时间展开成
`20.000 − 16.000 = 4.000 ns`（`:44`、`:49`）——那是"量纲错"被发现的过程。

**C. 本工程实测口径（本次打开件 `build/evidence/r119_window_check.txt`，11 行全读）**

| 判据 | 限值 | 实测 | 结论行 |
|---|---|---|---|
| W1 半窗可推导 | 期望 `0.20 × 20.000 ns = 4 ns` | 实读 `[4]` | `:1` PASS |
| W7 互对离散 max 角 | 上限 4 ns | 逐道 `[-0.041, -0.065, -0.049] ns`，最差 **0.065 ns** | `:8` PASS |
| W8 互对离散 min 角 | 上限 4 ns | 逐道 `[-0.04, -0.064, -0.048] ns`，最差 **0.064 ns** | `:9` PASS |
| W9 对内离散 | 上限 0.3 ns（`0.15 × Tbit = 2.000 ns`） | 四对 `[-0.001 ×4] ns`，最差 **0.001 ns** | `:10` PASS |
| W10 计数地板 | 数据道 3/3、P-N 对 4/4、钟道两角齐、全零读数 0 | 全齐 | `:7` PASS |
| W5 射程只含数据道 | 不许误挂 led/钟道 | 命中道只含 `tmds_data_p/n` | `:5` PASS |
| W6 默认不加载 | 引用行全在开关块内 | 引用行 = 2 | `:6` PASS |
| 总判 | — | 判定 10 项 红 0 未测 0 | `:11` |

**这两个口径的关系必须这样念**：实测的 0.065 / 0.001 ns 是 **FPGA 内部
（串行器的时钟脚 → 封装管脚）** 的 clock-to-pin 离散，
判据原文与范围限定写在 `report/io/hdmi_tp1_sdc_measurement.md:64-65`、`:88-89`
（"都在规范上限的 1/60 与 1/300 以内"是那份文档自己的结论，念的时候要带上"内部"这半句）。
**不含**：连接器之后、线缆、接收端，以及规范里那几条不能用 SDC 表达的量（眼图/抖动/占空比/沿）。
把 0.065 对 4.000 念成"过 HDMI 源端合规"就是这一条要防的错。

**④ 它不是什么 + 本工程观察点**

- "有窗约束" ≠ "测过板外"。观察点：当前构建打印的是 `VP_R119_TMDS_WINDOW off`
  （`build/tcl/build_system_axigpio.tcl:81`），也就是说这颗交付 bit 里**根本没有这条输出窗**，
  那 10 项判的是**已布线成品**上的离散量。
- "报告里没有 FAIL" ≠ "这一族检查过"。同一形状的红利/陷阱在 RGMII 输入侧记过账：
  `report/timing/debt_ledger.md:120-127`（加窗之后"缺口从 11 变 6，同时多出 5 个有限违例端点"）。
- 与 `myths.md` 第 15 节的分工：那边管 `5x`/`10x` 的命名混淆，这边管"两个口径不许并念"。

**⑤ 学会的标志（本次真跑过的那把尺子）**

1. 跑 `node build/r119_window_check.mjs --self`（2026-10-05 实测输出末行
   `对照总结：造 11 条畸形动红 11 条；缺输入 2 条报 NOT_MEASURED 2 条 PASS`）。
   过关形式：能指出**W7 的畸形同时染红了 W9**（这件事登记在
   `report/io/hdmi_tp1_sdc_measurement.md:97`），并说出为什么"一项红带动另一项红"
   说明这两项共用同一个被测量。
   ⚠ 一处文档与件的不同步要如实报：那份文档 `:95` 写"造 10 条畸形输入，10 条各自动红"，
   而本次实跑打印的是 **11 条**（另加 2 条缺输入分支）⇒ 数字以件为准，文档那一格待改。
2. 纸面一条：打开 `build/evidence/r119_window_check.txt` 第 1、9、10 行，
   说出 `4.000` 与 `0.300` 各自是**哪个乘式**的结果、两个乘式里的 `20.000` 与 `2.000`
   分别是什么周期（答案要能落回 `myths.md` 第 15 节的 `Tcharacter/Tbit` 定义）。

**⑥ 两个题外应用场景**

1. **长线缆/长走线的显示输出**：源端内部离散达标之后，连接器之后的部分要靠板级仿真与示波器；
   症状是"短线上正常、换长线偶发雪花"，处理顺序是先量化互对偏斜（同一套 UI 百分比口径），
   再动均衡/预加重。
2. **任何源同步串行链路**（LVDS 屏、SDI、相机 SerDes）：都用"字符率 = 位率 ÷ N，
   偏斜按 UI 百分比给限值"这一套量纲；症状是把"时钟频率"当"字符率"时，
   算出来的窗宽正好差 N 倍——与 `myths.md` 第 15 节那条 `5x/10x` 混淆同形。

小结 1：这一节只有一条可以念成"本工程量过"：**芯片内部 clock-to-pin 离散 ≤ 0.065 ns、
P/N 对内 ≤ 0.001 ns**（件 `build/evidence/r119_window_check.txt:8`、`:10`）；
规范那两条限值是转引仓库取证件，本次未重抓。
小结 2：眼图/抖动/占空比这三条要仪器，不在 SDC 语义里 ⇒ 想补这一层，先解决"谁提供示波器"。
下一步：第 8 节。

## 第 8 节 与别的篇目的接缝（哪些已经讲透，这里只指路）

| 概念 | 已经讲透的地方 | 本篇只留 |
|---|---|---|
| 翻转位 / 电平同步 / 准静态总线 | `glossary.md` 词条 4、6、8；`clocking-and-reset.md` 第 3 节跨域点全表；`myths.md` 第 3 节 | 不再讲；第 3 节只讲约束语义那一层 |
| 异步时钟组为什么必要、历史假违例 | `src/constraints/clock_groups_impl.xdc:10-23` + `clocking-and-reset.md` 第 5 节 | 第 3 节补"它与 max_delay 互斥生效"的原文口径 |
| 仲裁 vs 优先级、互锁 | `src/rtl/util/src_arb.v:1-16` + `myths.md` 第 6 节 | 第 4 节用它当"这不是 PR"的对照 |
| 饱和 / 回卷 / 粘滞 | `glossary.md` 词条 19；`myths.md` 第 5 节 | 不涉及 |
| BRAM vs 片外 DDR、存储推断 | `design-choices.md` 第 6 节；`myths.md` 第 7 节 | 不涉及 |
| 实现策略与旋钮的取舍、代价 | `design-choices.md` 第 13 节 | 第 6 节只补 UG949 的通用口径与"四步 directive"清单 |
| 缓存一致性的**决定**（选零拷贝 + 每帧一次发布） | `design-choices.md` 第 3 节 | 第 5 节只补"实际做到哪一步"的核实表与 BSP 原文语义 |
| TMDS 的 `5x/10x` 命名混淆 | `myths.md` 第 15 节 | 第 7 节只管两个口径不许并念 |
| 未约束 I/O = 未检查 | `report/timing/debt_ledger.md` §2；`myths.md` 第 12、13 节 | 第 7 节引它做"有窗≠测过板外"的对照 |

一处**必须报出来的过时**：自用件 `_sources.md` 第 1 节里"仓库路径"两行仍是 `src/ps/main.c`（`:30`、`:31`），而现役路径是 `src/ps/main.c`（本次打开的件）；
`report/timing/debt_ledger.md:10-12` 引的 `build_system_axigpio.tcl:19 / :24-26` 也与当前行号
（`:31` / `:36-38`）不同。这两条属于"行号漂移"，改它们不在本批权限内，
读那两篇时按**行内容**而不是按行号定位。

小结 1：这一篇存在的理由就是"最后一列"——所有已经讲透的都不再讲第二遍。
小结 2：如果读者从 `one-pass-walk.md` 跳到这里再跳回去，接缝是每节末尾那两行小结与上表。
下一步：第 9 节。

## 第 9 节 本篇的未确认清单与去处

计数口径同 `README.md` 第 1 节与 `_progress.md` 第 4 节（命令 `grep -o "<标记>" next-layer.md | wc -l`，
2026-10-05 实测）：`未确认` 这一种本篇正文为 0 次；
`本次未复核外部原文` 3 次（第 1 节 1.1 表"正文怎么处理"那一列 1 次、
第 7 节 ③ A 表末 1 次、本节 N-5 一行 1 次）；`需板上验证` 2 次（第 5 节 ⑤ 第 3 步 1 次、
本节 N-3 一行 1 次）。本段刻意把标记名写成不带方括号的样子，
免得计数句自己进计数。每个都对应一条能问用户或能实测的问题：

| 编号 | 位置 | 缺什么 | 怎么消掉（要谁） |
|---|---|---|---|
| N-1 | 第 4 节 ③（PR / MultiBoot 整节） | 本次三条下载通道都没拿到可解析的正文（UG909 镜像件解析失败、UG470 镜像件同样失败、mouser 403） | 需要一条能取 `docs.amd.com` PDF 的通道，或由用户批准"用某第三方抄件当正式出处"；在那之前第 4 节 ③ 保持"指针 + 状态"，不写条文 |
| N-2 | 第 3 节 ②/小结 2 | `report_synchronizer_mtbf` 没跑过；要不要为它多跑一次报告，取决于是否愿意把它进门禁 | 要问用户：值得为 MTBF 读数多跑一次实现阶段报告吗（值不值得由队伍定，不由文档定） |
| N-3 | 第 5 节 ② 表最后一行 | SD 这条路的数据是 ADMA2 搬的、还是逐拍经数据口搬的 | 实测方法已写在第 5 节 ⑤ 第 3 步（`【需板上验证】`）；也可读一次驱动 `XSdPs_Read` 的寄存器配置来定，但那要再开一轮 BSP 源码核对 |
| N-4 | 第 5 节 ③ 表第三行（ACP / 一致性端口） | 未取得 Zynq 侧的官方正文 ⇒ 只写了"本工程没用" | 与 N-1 同一个通道问题；也可以由用户口述"当年为什么不开 ACP"，那属于设计意图，只能进 `design-choices.md` |
| N-5 | 第 7 节 ③ A（HDMI 规范两条限值） | 本次未重抓原文，转引仓库取证件 `【本次未复核外部原文】` | 需要一次能访问镜像 PDF 的网络核对；核对之前不许在正文写"规范说" |
| N-6 | 第 7 节 ⑤ 第 1 步末段 | 文档 `report/io/hdmi_tp1_sdc_measurement.md:95` 写"10 条畸形"，实跑打印 11 条 | 要改的是那篇交付文档（不在本批权限内）⇒ 登记给队伍，两处一起改才不会又出现"改一处漏一处" |
| N-7 | 第 7 节 眼图/抖动/占空比 | 没有示波器，也没有 HDMI 接收端窗口数 | 需要用户给仪器与判据来源；在此之前不许把 0.065/0.001 外推为板外结论 |

小结 1：7 格里只有 N-1/N-4/N-5 是"外部资料通道"问题，N-2 是决定问题（要人拍板），
N-3/N-7 是实测问题，N-6 是文档不一致——四类不许合并成一句"待核实"。
小结 2：这一篇里所有降级都发生在 ③ 层（精确定义 + 出处），落点层（②④⑤）全部有据。下一步：第 10 节。

## 第 10 节 小结与下一步

六条的"为什么没做"归纳成三种，各配一个可核对的落点：

| 类型 | 六条里的哪几条 | 落点 |
|---|---|---|
| 范围决定（有记录） | 第 4 节（PR/MultiBoot）、第 7 节里的 CTS 本体（NDA） | `report/log/plan_v8_spec.md:49`、`src/constraints/r119_hdmi_source_window.xdc:44` |
| 工具语义边界（改它会改变被分析对象） | 第 3 节的 `set_max_delay -datapath_only`、第 6 节的策略/档位 | `report/timing/debt_ledger.md:94-101`、`build/tcl/build_system_axigpio.tcl:312-323` |
| 已经做到"够用"而没再深一层 | 第 2 节（只用两条 AXI）、第 5 节（只 flush）、第 7 节（只到内部离散） | `build/tcl/build_system_axigpio.tcl:99-100`、`src/ps/main.c:714`、`build/evidence/r119_window_check.txt:8-10` |

下一步去哪：
想动手复核本篇任一条 → `hands-on.md` 实验 1/3/4/5；
想知道"本工程实际用到哪些机制、配出处" → 那一篇 `mechanics.md` 还没开始，
本次取到的两份外部文本足够把它的前两条（AXI 握手独立性、异步 CDC 不按时序判）落地，
登记在 `_progress.md` 第 1 节那条阻塞已经解开了一半（状态更新归 `_progress.md` 的作者，本篇不改）。

## 第 11 节 自测题

题目 1：**"加了 `set_clock_groups` 之后跨域路径就安全了"这句话对不对？**
本篇不回答。要得出答案，打开两处：① 本次抽取到的 UG949 p.171 与 p.175-176 那两段
（`set_clock_groups` 的语义 + "异步 CDC 不该用默认时序分析证明功能"）；
② 本工程的 `report/timing/debt_ledger.md:94-101` 与 `src/constraints/clock_groups_impl.xdc:19-23`。
答出来的判据必须同时说出"这条约束取消什么"和"那件事改由谁保证"，两边都缺一半就是没读通。

题目 2：**本工程在 PS 侧到底有没有做缓存 invalidate？**
去查三处并说出各属哪一层：`src/ps/main.c:714`、`src/ps/sd_play.c:86-95`、
`vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/sdps/src/xsdps.c:350-357`。
过关形式：答案里必须出现"应用一处都没有、驱动读完之后有一处"这种**分层归属**，
并且能引用 `vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp/libsrc/standalone/src/arm/ARMv8/32bit/xil_cache.c`:455-467 里 `Xil_DCacheFlushRange` 的注释说明 flush 之后缓存行处于什么状态。

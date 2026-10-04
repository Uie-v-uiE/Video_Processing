# A1/A2 — 先读资料，再量自己的设计（本轮实际做到哪一步，逐条写清）

提示词 §2 要求"先建立官方判据，再拿它量自己的 xdc"。**这份文件的存在意义就是说清哪些判据我真拿到了、哪些没拿到。**
没拿到的部分，本轮所有结论一律只写"实测读数 + 出处"，不写"官方推荐这样做"。

## A1 外部文档：状态 = 未读，且不是因为"页面打不开"

| 提示词点名的文档 | 本轮状态 | 说明 |
| --- | --- | --- |
| UG903 Using Constraints | **未读** | 本机安装里没有随附 PDF（22:54 实测：`D:/Software/Vivado/2025.2.1/Vivado/data/docs` 不存在、`Vivado/help` 不存在、`find -maxdepth 4 -iname "UG*.pdf"` 返回空）。docs.amd.com 的正文是 JS 单页，需要按提示词给的三条路径之一去取；本轮没有把任何一条走通。 |
| UG906 Design Methodology | **未读** | 同上。本轮对 `report_methodology` 各检查项的理解**只来自工具自己打印的 Description 列**（件 `build/evidence/r115_base/methodology.txt` 的 SUMMARY 表），不来自文档。 |
| UG949 Design Analysis | **未读** | 同上。`report_design_analysis` 的可用模式是用 A2 探针量出来的，不是查文档得来的。 |
| UG904 Implementation | **未读** | 同上。`phys_opt_design` 的旗标语义只引用 `help phys_opt_design` 的原文（A2）。 |
| UG901（提示词写作"Static Timing Analysis User Guide"） | **未读，且文档号需要核对** | 不照抄提示词给的标题——文档号与标题的对应关系我这一轮无法验证，写错标题比不写更糟。需要 UG901 那条结论时，先核对再引用。 |
| UG382 SelectIO / UG482 Clocking | **未读** | §7 L1 的"器件能力边界"因此**不能**引用手册页码；本轮的 L1 论证只用工具实测（级数分布、route 占比）+ 已归档的真窗扫描。 |
| Zynq 侧：`FCLK_CLK*` 由 PS 配置推导 | **适用，且有本地凭据** | 名册里 `clk_fpga_0` 的来源写的是 `PS7_FCLKCLK0(BD)`、周期 10.000 ns，不是我手写的：`rk_zynq7020.xdc` 里 `create_clock` 只有两行（:6 sys_clk、:36 eth_rxc），grep 全仓 xdc 也没有 clk_fpga_0。MMCM 输出钟用 `-include_generated_clocks` 取名，见 `clock_groups_impl.xdc:28-31`。 |

**因此本轮的限制**：任何"官方建议"字样都不出现在判定与文档里；能用的是（a）工具自己打印的 help/报告原文，（b）本机已归档的实测扫描，（c）板上眼睛的签收记录。
下一轮做 A1 的正确入口已记下：`docs.amd.com/api/khub/documents/<id>/content` 直接给 PDF；浏览器工具能渲染；本机没有随附文档目录。

## A2 命令选项集探针（40 秒那笔投资，本轮真花了）

探针脚本 `build/tcl/r115_help_shapes.tcl`；凭据 `build/evidence/r115_help_shapes_console.txt`（本轮 22:2x 跑的）、
`build/evidence/r114_help2_console.txt`、`build/evidence/r114_help_probe_console.txt`（今天早些时候的同族探针）。量到并**改变了做法**的几条：

- `report_timing_summary` **没有** `-extended / -numeric_summary / -to` ⇒ 逐域数字只能从它的 Intra Clock Table 解析，不能靠额外旗标。
- `report_design_analysis` 实测可用：`-complexity -congestion -timing -routes -logic_level_distribution -routed_vs_estimated -qor_summary`；**是 `-routes` 不是 `-routing`，也没有 `-fanout`**。
- 本机**没有** `set_max_fanout`、没有 `report_methodology -rules`（只有 `-checks`）、没有 `get_false_paths/get_clock_groups/get_timing_exceptions`（只有 `report_exceptions`）、没有 `get_input_delays/get_output_delays` 命令。
- `get_ports` **没有** `-direction` ⇒ 端口清单要从 RTL 端口表或 `report_exceptions` 反推，不能一条命令问出来。
- 时钟对象上**没有** `*UNCERT*` 属性（时钟只有 CLASS/FILE_NAME/INPUT_JITTER/…/WAVEFORM/WEIGHT 那一串），
  `set_clock_uncertainty` 也不返回对象列表 ⇒ "**四个域各自有没有 hold 不确定度**"这件事问不出来（ISSUES #295），
  只能用"两滚差分"间接量（本轮 C2 那一刀，`build/uncertainty_uniform_ab.sh`）。
- 网对象只认**裸分层路径**（`get_nets -quiet a/b/c`）；`-filter "NAME == {…}"` / `FULL_NAME` / `-hier`+短名三种形式实测恒空。
  ⇒ `build/tcl/mf114_roll.tcl` 的取网逻辑按这条重写，并在取回后再做一次 `NAME` 字面相等核对。

## A1 的取文档通道：23:44 打通了**一半**，而且这一半就把候选约束的数改了

| 想拿的东西 | 状态 | 实际做法与结果 |
| --- | --- | --- |
| Xilinx UG903/906/949/904/382/482 | **仍未取到** | 本机 Vivado 安装里 `data/docs`、`help` 目录都不存在、`find -maxdepth 4 -iname "UG*.pdf"` 为空（22:56 实测）；`Read` 工具读 PDF 要 `pdftoppm`（poppler），本机没装 ⇒ 官方 UG 这一路今晚没走通。所以本轮**没有任何一句"官方建议"**。 |
| PHY 侧的 RGMII 窗口数（这是 H5 那笔债真正缺的东西） | **取到了**，而且来源是本机文件 | 本机 `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书….PDF`（69 页，Track ID JATR-8275-15 Rev 1.4）。通道：`pip install pypdf` + 按页文本抽取（`Read` 的渲染路线不可用，不等于"读不到 PDF"）。读数落在 **Table 60，手册页 60 = PDF 第 67 页**：`TsetupR`/`TholdR` min 1.0 / typ 2 ns，`TskewR` 1.0/1.8/2.6 ns（并要求 PCB 把时钟走线比数据多 1.5–2.0 ns），`Tcyc@1000M` 7.2/8/8.8 ns，`tR/tF` max 0.75 ns。 |
| 板子站在哪种模式（内部延迟 vs PCB 延迟） | **没读到，不许猜** | 原理图 `ZYNQ7020-F+V1.1原理图.pdf` 第 8 页的引脚表显示 `23 TXDLY/RXD1`、`24 RXDLY/RXD0`（ strap 与数据线复用）；寄存器 0x11 的当前值本机读不到（无 MDIO 读命令 + 无 `arm-none-eabi-gcc` ⇒ #131/#170）。⇒ 新候选约束取**两种模式的并集** min 1.000 / max 2.600，见 `src/constraints/r115_io_window_candidate.xdc`。 |
| DVI/HDMI 侧 TMDS 输出窗口数 | **未取到** | 输出侧 6 个端口继续挂账，**没有来源就不写数**（这一条不许用"看起来宽松"的数字凑）。 |

**这一节存在的意义**：A1 不是形式——正是这次取数把 `r114_io_async.xdc:39-43` 的 ±0.500 判成**用错了行**
（±0.5 是同一张表里 `TskewT`：发射端**没有**内部延迟时的输出偏差），并直接改掉了下一轮候选约束的数。
"空壳页面不等于文档不存在"这句在本机成立的方向是：**渲染路线打不开，就换文本抽取路线**，别把工具缺失当资料缺失。

## A3 产出物的支撑

`report/timing/debt_ledger.md` 的每一项都带 `文件:行`，行号是 22:54 用上面第二条那样的一次 grep 复核过的，不是记忆。

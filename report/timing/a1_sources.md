# A1/A2 — 先建立官方判据，再拿它量自己的设计（逐条：拿到了什么、凭什么）

提示词 §2 要求"先建立官方判据，再拿它量自己的 xdc"。**这份文件说清哪些判据真拿到了、哪些没拿到。**
没拿到的部分，结论一律只写"实测读数 + 出处"，不写"官方推荐这样做"。

## A1 外部文档：状态 = 未读，且不是因为"页面打不开"

| 提示词点名的文档 | 状态 | 依据 |
| --- | --- | --- |
| UG903 Using Constraints | **未读** | 本机安装里没有随附 PDF（实测：`D:/Software/Vivado/2025.2.1/Vivado/data/docs` 不存在、`Vivado/help` 不存在、`find -maxdepth 4 -iname "UG*.pdf"` 返回空）。docs.amd.com 的正文是 JS 单页，要按提示词给的三条路径之一去取；三条都没有走通。 |
| UG906 Design Methodology | **未读** | 同上。`report_methodology` 各检查项的理解**只来自工具自己打印的 Description 列**（件 `build/evidence/r115_base/methodology.txt` 的 SUMMARY 表），不来自文档。 |
| UG949 Design Analysis | **未读** | 同上。`report_design_analysis` 的可用模式是用 A2 探针量出来的，不是查文档得来的。 |
| UG904 Implementation | **未读** | 同上。`phys_opt_design` 的旗标语义只引用 `help phys_opt_design` 的原文（A2）。 |
| UG901（提示词写作"Static Timing Analysis User Guide"） | **未读，且文档号需要核对** | 不照抄提示词给的标题——文档号与标题的对应关系没有可核的凭据，写错标题比不写更糟。需要 UG901 那条结论时，先核对再引用。 |
| UG382 SelectIO / UG482 Clocking | **未读** | §7 L1 的"器件能力边界"因此**不能**引用手册页码；L1 的论证只用工具实测（级数分布、route 占比）+ 已归档的真窗扫描。 |
| Zynq 侧：`FCLK_CLK*` 由 PS 配置推导 | **适用，且有本地凭据** | 名册里 `clk_fpga_0` 的来源写的是 `PS7_FCLKCLK0(BD)`、周期 10.000 ns，不是我手写的：`rk_zynq7020.xdc` 里 `create_clock` 只有两行（:6 sys_clk、:36 eth_rxc），grep 全仓 xdc 也没有 clk_fpga_0。MMCM 输出钟用 `-include_generated_clocks` 取名，见 `clock_groups_impl.xdc:28-31`。 |

**因此这份文档的口径是**：任何"官方建议"字样都不出现在判定与文档里；能用的是（a）工具自己打印的 help/报告原文，（b）本机已归档的实测扫描，（c）板上眼睛的签收记录。
取 UG 正文的可行入口记在这儿：`docs.amd.com/api/khub/documents/<id>/content` 直接给 PDF；浏览器工具能渲染；本机 Vivado 安装没有随附文档目录。

## A2 命令选项集探针（40 秒一次，量的是本机工具到底有什么）

探针脚本 `build/tcl/r115_help_shapes.tcl` 与它的 console（`build/evidence/r115_help_shapes_console.txt`、
`build/evidence/r114_help2_console.txt`、`build/evidence/r114_help_probe_console.txt`）都是过程件、已随轮次清理 ⇒ 复算 = 在没有 design 的 Vivado Tcl 里跑一遍 `help <cmd>` 批（实测 40 秒一支）。量到并**改变了做法**的几条：

- `report_timing_summary` **没有** `-extended / -numeric_summary / -to` ⇒ 逐域数字只能从它的 Intra Clock Table 解析，不能靠额外旗标。
- `report_design_analysis` 实测可用：`-complexity -congestion -timing -routes -logic_level_distribution -routed_vs_estimated -qor_summary`；**是 `-routes` 不是 `-routing`，也没有 `-fanout`**。
- 本机**没有** `set_max_fanout`、没有 `report_methodology -rules`（只有 `-checks`）、没有 `get_false_paths/get_clock_groups/get_timing_exceptions`（只有 `report_exceptions`）、没有 `get_input_delays/get_output_delays` 命令。
- `get_ports` **没有** `-direction` ⇒ 端口清单要从 RTL 端口表或 `report_exceptions` 反推，不能一条命令问出来。
- 时钟对象上**没有** `*UNCERT*` 属性（时钟只有 CLASS/FILE_NAME/INPUT_JITTER/…/WAVEFORM/WEIGHT 那一串），
  `set_clock_uncertainty` 也不返回对象列表 ⇒ "**四个域各自有没有 hold 不确定度**"这件事问不出来（ISSUES #295），
  只能用"两滚差分"间接量（C2 那一刀，`build/uncertainty_uniform_ab.sh`）。
- 网对象只认**裸分层路径**（`get_nets -quiet a/b/c`）；`-filter "NAME == {…}"` / `FULL_NAME` / `-hier`+短名三种形式实测恒空。
  ⇒ `build/tcl/mf114_roll.tcl` 的取网逻辑按这条重写，并在取回后再做一次 `NAME` 字面相等核对。

## A1 的取文档通道：打通了**一半**，而这一半改掉了候选约束的数

| 想拿的东西 | 状态 | 实际做法与结果 |
| --- | --- | --- |
| Xilinx UG903/906/949/904/382/482 | **仍未取到** | 本机 Vivado 安装里 `data/docs`、`help` 目录都不存在、`find -maxdepth 4 -iname "UG*.pdf"` 为空；`Read` 工具渲染 PDF 要 `pdftoppm`，本机没有（`pdftotext` 在 `/mingw64/bin`，所以走文本抽取）⇒ 官方 UG 这一路不通，文档里**没有任何一句"官方建议"**。 |
| PHY 侧的 RGMII 窗口数（这是 H5 那笔债真正缺的东西） | **取到了**，而且来源是本机文件 | 本机 `（本机厂商资料目录）/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书….PDF`（69 页，Track ID JATR-8275-15 Rev 1.4）。通道：`pip install pypdf` + 按页文本抽取（`Read` 的渲染路线不可用，不等于"读不到 PDF"）。读数落在 **Table 60，手册页 60 = PDF 第 67 页**：`TsetupR`/`TholdR` min 1.0 / typ 2 ns，`TskewR` 1.0/1.8/2.6 ns（并要求 PCB 把时钟走线比数据多 1.5–2.0 ns），`Tcyc@1000M` 7.2/8/8.8 ns，`tR/tF` max 0.75 ns。 |
| 板子站在哪种模式（内部延迟 vs PCB 延迟） | **读到了：发射端内部延时是开的** | 原理图 `ZYNQ7020-F+V1.1原理图.pdf` 第 8 页那两只脚（`23 TXDLY/RXD1`、`24 RXDLY/RXD0`，strap 与数据线复用）都是 4.7 kΩ 上拉 IODVDD；规格书 Table 10/11 的对照与推导写在 `report/timing/rgmii_window_model.md` §7.5(1)。⇒ 窗取**发射端**两行 `TsetupT/TholdT` = min 1.200 / max 2.800，件 `src/constraints/r116_rgmii_input_window.xdc`；早先按并集 min 1.000 / max 2.600 写的那份候选（`src/constraints/r115_io_window_candidate.xdc`，用的其实是 `TskewR` 那一行）不作数。寄存器 0x11 的**现值**仍读不到：app 里没有 MDIO 读命令（#131/#170），编译器在位、重建的 app 未上板复验。 |
| DVI/HDMI 侧 TMDS 输出窗口数 | **已取到，走的是另一条通道** | 源端 TP1 的这些量不只印在不公开的 CTS 里，HDMI 规范本体 §4.2.4（Table 4-24 / Fig 4-30）就有；取数过程与逐条出处在 `report/io/hdmi_cts_source_window.md`，写成的约束是候选件 `src/constraints/r119_hdmi_source_window.xdc`（默认不加载，`VP_R119_TMDS_WINDOW=1` 才带）。`led[0..1]` 两个端口仍没有来源 ⇒ 继续挂账，**没有来源就不写数**（这一条不许用"看起来宽松"的数字凑）。 |

**这一节存在的意义**：A1 不是形式——Table 60 的读数把 `r114_io_async.xdc:39-43` 的 ±0.500 判成**用错了行**
（±0.5 是同一张表里 `TskewT`：发射端**没有**内部延迟时的输出偏差），候选约束的数因此改掉（现行数 min 1.200 / max 2.800，就在上面那一行）。
"空壳页面不等于文档不存在"在这台机器上成立的方向是：**渲染路线打不开，就换文本抽取路线**，别把工具缺失当资料缺失。

## A3 产出物的支撑

`report/timing/debt_ledger.md` 的每一项都带 `文件:行`，行号是按上面那条 grep 复核过的，不是记忆。

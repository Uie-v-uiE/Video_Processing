## r115_io_window_candidate.xdc —— RGMII 收口的**输入窗候选**（本轮不加载、不采纳，等 C2 落地后再走正式一轮）
##
## 状态：候选件。`build/tcl/build_system_axigpio.tcl:19/:24-26` 只加载 `rk_zynq7020.xdc` 与
##   `clock_groups_impl.xdc` 两份（2026-10-03 22:59 grep 实测），所以这个文件现在**不参与任何构建**。
##   它存在的意义：把"补 I/O 约束"这笔债的**数字**第一次落到有出处的地方，
##   下一轮（任务 #195 / ISSUES #259）不用再从头问"该写多少"。
##
## 出处（本机就有的两件事，不是记忆、不是二手博客）：
##   * 文件 `D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书_REALTEK(瑞昱)以太网芯片规格书.PDF`
##     （69 页，Track ID JATR-8275-15 Rev. 1.4）
##   * **Table 60 "RGMII Timing Parameters"，手册页 60 = PDF 第 67 页**（文本抽取读数，2026-10-03 23:44）：
##       TsetupR  Data→Clock Input Setup at receiver（发射端内部延迟已集成）  min 1.0  typ 2  –   ns
##       TholdR   Clock→Data  Input Hold  at receiver（同上）                 min 1.0  typ 2  –   ns
##       TskewR   Data→Clock  Input Skew  （PCB 走线延迟模式，并要求时钟比数据多走 >1.5、<2.0 ns）
##                                                                            min 1.0  typ 1.8  max 2.6 ns
##       Tcyc @1000 Mbps                                                      7.2 / 8 / 8.8 ns
##     ⇒ 这一族数**取代**了 `r114_io_async.xdc:39-43` 里那个 ±0.500：±0.5 是同一张表里 **TskewT**
##       （发射端**没有**内部延迟时的输出偏差）的数，用错了行；那条已经写进
##       `docs/timing/rgmii_window_model.md` §6。
##
## 为什么取 min 1.000 / max 2.600（而不是"猜 PHY 的延迟开着/没开"）：
##   RTL8211F 的 TXDLY/RXDLY 与 RXD1/RXD0 复用（原理图 `ZYNQ7020-F+V1.1原理图.pdf` 第 8 页引脚表：
##   `23 TXDLY/RXD1`、`24 RXDLY/RXD0`），复位时怎么被拉、寄存器 0x11 现在是什么值，本机都读不到
##   （app 侧没有 MDIO 读命令，且没有 `arm-none-eabi-gcc` ⇒ ELF 不能重建，ISSUES #131/#170）。
##   ⇒ 取**两种模式都更严**的并集：下界 1.0（TholdR/TsetupR 的 min），上界 2.6（TskewR 的 max）。
##   绿了就说明两种模式都绿；不猜是哪一种。**不许反过来写**：不许先假定延迟开着再挑好看的数。
##
## 为什么现在还不加载（H1/G3 与顺序）：
##   绑上任何窗之后，现行 `eth_rxc` 的 hold 会报负（±0.5 窗实测 −2.885，件
##   `build/evidence/r114_io_roll_console5.txt`；换成这里这组数预测 ≈ −3.02，推导见
##   `docs/timing/rgmii_window_model.md` §6）。负读数本身不是坏事，它是债显形；
##   但**采纳顺序必须是先 C2（把捕获沿提前 5.000 ns）再绑窗**，否则这一轮的"没有任何域变差"这一条
##   会被两笔债同时压着，分不清是哪笔。C2 的证伪在 `c2_scratch_1003` 丢弃副本树里跑，判据 S1–S5 已预登记。
##
## DDR 的第二沿必须一起声明（附录 1：本机 `set_input_delay` 没有 -setup/-hold，也没有 -clock_edges，
##   第二沿只能再写一条 -clock_fall；实测 rise-only 与 both-edge 变体给完全相同的数字，
##   所以这两条不是为了"补覆盖"好看，是为了口径完整、不让人下次再问）。
set_input_delay -clock eth_rxc -max  2.600 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -min  1.000 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -max  2.600 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock eth_rxc -clock_fall -min  1.000 [get_ports {eth_rxd[*] eth_rx_ctl}]

## 输出侧那 6 个端口（`tmds_clk_p`、`tmds_data_p[0..2]`、`led[0]`、`led[1]`）**这里故意不写**：
## 需要 DVI/HDMI 接收端或面板的窗口数，本机板级资料（用户手册 + 原理图 + 芯片手册目录）里没有这一项，
## 2026-10-03 试过在线取 DVI 规范原文也没取到可引用的一页。
## ⇒ **没有来源就不写数**，继续挂在 `docs/timing/debt_ledger.md` §2 当债，不许用"看起来宽松"的数凑绿灯。

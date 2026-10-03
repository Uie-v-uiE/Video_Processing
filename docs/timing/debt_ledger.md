# A3 债务清单 — 现有约束集的账（2026-10-03 夜，r114 树 = 板上那一版）

这一份只用**已读过的行**说话。每个数后面紧跟它的工件；工件路径 + md5 在 `docs/timing/baseline_INDEX.md`。
按 H1，本清单**不为任何一条债补约束**（补约束=改变被分析的对象，必须走候选→测量→采纳，见 `docs/timing/cut_ledger.tsv` 的 C4）。

## 0. 当前工程真正加载的约束文件（顺序即加载顺序）

| 顺序 | 文件 | 绑定时机 | 出处 |
| --- | --- | --- | --- |
| 1 | `src/constraints/rk_zynq7020.xdc` | 综合 + 实现 | `build/tcl/build_system_axigpio.tcl:19` |
| 2 | `src/constraints/clock_groups_impl.xdc` | **只在实现**（`used_in_synthesis false`） | 同文件 `:24-26` |

盘上还有三个 **没有被任何脚本 add_files** 的候选约束件：`r114_io_async.xdc`、`r114_io_variantA_rise_only.xdc`、
`r114_io_variantB_phy_delay.xdc`（22:59 `grep -n xdc build/tcl/build_system_axigpio.tcl` 只命中上面两行）。
⇒ 它们是 C4 那把刀的**实验材料**，不是现行约束集的一部分；本轮名册的口径按"现行两文件"算。
另有 `build/micro_rd/gen/*.xdc` 三个属于迷你探针工程，与本设计无关。

## 1. 每个时钟：周期来源 / 被约束端点数

| 时钟 | 周期 ns | 来源（**谁 create 的**） | Intra Clock 端点数 | 出处 |
| --- | --- | --- | --- | --- |
| `sys_clk` | 20.000 | 我在 xdc 手写：`rk_zynq7020.xdc:6` | 323 | 名册 `docs/timing/roster_baseline.tsv` |
| `eth_rxc` | 8.000 | 我在 xdc 手写：`rk_zynq7020.xdc:36` | 4,835 | 同上 |
| `clk_fpga_0` | 10.000 | **PS7 IP 自己** create（FCLKCLK[0]），不在我的 xdc 里（grep 全仓 xdc 无此行） | 15,721 | 同上 |
| `clkout0_1` | 20.000 | MMCM 输出（CLKOUT0） | 30,179 | 同上 |
| `clkout1_1` | 4.000 | MMCM 输出（CLKOUT1，TMDS 250 MHz） | 无 intra 路径行 | 同上（NA 是"这一族没有同沿路径"，不是"我读不到"） |
| `clkout2` | 5.000 | MMCM 输出（CLKOUT2，IDELAY 参考 200 MHz） | 无 intra 路径行 | 同上 |
| `clkfbout` / `clkfbout_1` | 20.000 | MMCM 反馈 | 无 intra 路径行 | 同上 |

`unconstrained_endpoints` = **0**（`check_timing -verbose` 自己那行 "pins that are not constrained for maximum delay."）⇒ H5 的端点那一半是干净的。
`io_unconstrained_ports` = **11**（端口对象单位：输入 5 + 输出 6）⇒ **H5 的另一半不为 0，本轮判红**，见 §2。

## 2. 每个外部端口的 I/O 时序覆盖（债务主体）

`check_timing -verbose`（件 md5 550b45d95449）点名：

- **没有 input delay 的 5 个输入**：`eth_rx_ctl`、`eth_rxd[0]`…`eth_rxd[3]`
  ⇒ 这正是 RGMII 的 4 位数据 + 控制。它们由 `eth_rxc`（8 ns，DDR）源同步驱动，
  但 `set_input_delay` 在整棵 `src/constraints/` 里 **0 次**（22:56 实测 grep：只命中 `create_clock`/`set_clock_uncertainty`/`set_false_path`/`set_property` 四类）。
  ⇒ **债务的真实含义**：现行名册里 eth_rxc 的 WHS 0.052 是"假设数据恰好在时钟沿到达"量出来的片内数，
  它**不包含** PHY→FPGA 走线与 PHY 内部延迟的那一段。
- **没有 output delay 的 6 个输出**：`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0]`…`tmds_data_p[2]`
  ⇒ TMDS 的负极性腿（`tmds_*_n`）不在名单里：差分对的 N 腿由同一对约束覆盖是工具的默认行为，
  但**这一条我没有官方出处**（A1 未读），所以只报"check_timing 没点它们的名"这个事实，不写"所以无需约束"的结论。
  LED 是两个静态指示脚；TMDS 那 4 个（时钟 + 3 数据）是真的对外接口，需要面板/接收端的手册窗口数。
- **已有 false path 的（MEDIUM）**：输入 `key1_n`、`key2_n`；输出 `eth_rst_n`、`eth_tx_clk`、`eth_tx_ctl`、`eth_txd[0..3]`。

**这笔债的量级已经测过，不是猜的**：把 ±0.500 ns 的 RGMII 输入窗（候选件 `r114_io_async.xdc:39-43`，四条 `set_input_delay`）
绑到同一份 `system_top_opt.dcp` 重跑 place+route ⇒ 终态 **WNS = 0.437 / WHS = −2.885 ns / THS = −14.344 ns**
（件 `build/evidence/r114_io_roll_console5.txt` 的 `[Route 35-57]` 行；变体 A 只声明上升沿 `r114_io_variantA_rise_only.xdc`，
读数逐位相同 ⇒ 印证附录 1 那条"rise-only 与 both-edge 给完全相同的数字"）。
也就是说：**加上真实窗口，收口现在就是红的**（对照名册里 eth_rxc 的 WHS 0.052 是"没有这条约束"时的数）；
差异被"缺约束"藏住了。

**23:44 更新：输入侧的窗数字第一次有了出处，而且旧候选件用错了行。**
本机就有 PHY 手册（`D:/Xilinx/Resource/ZYNQ7020/Board_Resource/芯片手册/C187932_以太网芯片_RTL8211F-CG_规格书….PDF`，
69 页，Track ID JATR-8275-15 Rev 1.4），`Table 60 RGMII Timing Parameters`（手册页 60 = PDF 第 67 页）给的是：
`TsetupR`/`TholdR` min **1.0** typ 2（发射端内部延迟集成时）、`TskewR` **1.0–1.8–2.6**（PCB 延迟模式，并要求时钟比数据多走 >1.5/<2.0 ns）、
`Tcyc@1000M` 7.2/8/8.8。**±0.500 那张表里对应的是 `TskewT`（发射端*没有*内部延迟时的输出偏差），不是收口该用的窗**——
所以 `r114_io_async.xdc:39-43` 的数错了行，新候选件 `src/constraints/r115_io_window_candidate.xdc` 改取
**min 1.000 / max 2.600（两种模式的并集）**，推导与重算见 `docs/timing/rgmii_window_model.md` §6（**该窗下现行结构预测 WHS ≈ −1.38**：把 §1 那条 −2.522 的 tap0 分量按实测斜率
63 ps/tap 补回 tap 26 的 IDELAYE2 ≈2.293，再把 min 换成 1.000 得 4.614 − 5.998 = −1.384；
同一套分量拿 ±0.5 那档回去算得 −2.884，与 r114 实测 −2.885 逐位对上，所以这套算法可信）。
PHY 到底站在哪一边**仍然没读出来**（TXDLY/RXDLY 与 RXD1/RXD0 复用，原理图第 8 页；本机读不到寄存器 ⇒ #131/#170），
所以取并集而不是宣称某一种模式；输出侧那 6 个端口仍然**没有来源数**，继续挂账。

**00:12 追补（同一把尺子量两块 DCP，纯只读，件 `build/evidence/r115_c2_scratch/option_a_main_console.txt`）**：
真窗（min 1.000 / max 2.600）下**主树**（没有 MMCM 的原版）实测 `hold −1.385 / setup −0.186`，
与 §6 用分量算出的 −1.38 对上（分量模型自校验）。00:16 更正一处（这一段我写错过一次算术，趁现在改掉）：沿动的时候 hold 与 setup 的 required **同向**移动（到达时刻由外部 PHY 决定），所以不存在“守恒、找不到点”那回事；真正互相交换的是**数据延迟**（IDELAY）——这也正是 F3 那条 tap 扫描走进死胡同的原因。报告自己的 skew 才是事实：**主树 5.008 vs 副本树 5.919**（件 `option_a_main_console.txt` / `option_a_console.txt` 的 `Clock Path Skew` 行） ⇒ MMCM 那一刀把捕获沿**推迟了 0.911 ns**，`-225°` 的相位提前被 MMCM+BUFG 自己的网络延迟吃掉还有余，所以它连主树都没追上（hold -1.426 vs -1.385、setup -0.972 vs -0.186）。⇒ 靶子改写成“**把到 IDDIR 的 ~5-6 ns 时钟网络延迟降下来**”，降下来 hold 与 setup 一起变好；下一轮唯一值得试的结构刀是 BUFIO/同区那一族。窗模型的残余风险不变：`TskewR` 那行讲的是 PCB **时钟走线**（要多走 1.5-2.0 ns），我却当数据散布用了，可能是第二次混行（第一次是 `TskewT` 的 ±0.5，见 ISSUES #304），所以 -1.385 / -0.186 只代表“该窗模型下的读数”，不代表板上真实差额；定模型要有人读那两行与 strap/寄存器现值（本机读不到，#131/#170）。输出侧那 6 个端口仍然**没有来源数**，继续挂账。

## 3. 每条既有例外的"当初理由"

| 约束 | 位置 | 当初理由 | 理由是否可查 |
| --- | --- | --- | --- |
| `set_false_path -to eth_rst_n` | `rk_zynq7020.xdc:55` | `eth_rst_n` 是**输出**（上电复位计数器驱动），只能是终点；原 `-from` 版本每次综合报 [Constraints 18-513] 空约束，已删 | ✅ 同文件 `:51-54` 注释 |
| `set_false_path -to eth_tx_clk/-to eth_tx_ctl/-to eth_txd[*]` | `:56-58` | 文件里**没有**写当初理由（只有 RGMII 发送侧由 IDELAY/OSERDES 对齐这一句在别处） | ⚠ **待复核债务**（不补约束、不删，见 H1） |
| `set_false_path -from key1_n/-from key2_n` | `:59-60` | 按键是异步输入，去抖链自己做跨域；上电那一拍的初值问题在 r113 修（声明初值），尺子是 `sim/tb_v113_key_powup.v` + `build/check_powup_init.sh` | ✅ 尺子在仓里；眼睛那一格 `board/ACCEPTANCE.md` E6 在 r114 上标的是**待重判**，不算已验 |
| `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` | `:50` | 给 hold **加**要求（方向与放松相反）：#46 量到 BUFIO/BUFG 两棵树差 1.616 ns，工具每次垫的量随机 ⇒ 垫成设计值 | ✅ 同文件 `:37-49` 注释（0.5→0.8 的加码过程也写着） |
| `set_clock_groups -asynchronous` 三组 | `clock_groups_impl.xdc:28-31` | 三组互异步的理由 + 四条跨域路径各自的结构保证（dc_fifo 格雷码 / 翻转+3FF / 3 级像素+3FF / 3FF 控制字）都写在该文件 `:19-23`，历史假违例（缺 `-include_generated_clocks` ⇒ WNS≈−6.7）写在 `:16-17` | ✅ 逐条写了 |
| `BITSTREAM.GENERAL.COMPRESS TRUE` | `:77` | 交付体积，与时序无关 | ✅（不是时序债务，列在这里只为闭合） |

## 4. `ASYNC_REG` 覆盖（#262 落地后的实测状态）

`build/tcl/probe_r114_async_netlist.tcl` 在**布线后网表**上量的（件 `build/evidence/r114_async_netlist_pre_console.txt` = 落地前，
`build/evidence/r114_async_reg_post.txt` = 落地后）：

- 名字含 gray 的单元 116 颗，其中触发器型（`FD*`）84 颗；
- 落地前 `marked_true=0` → 落地后 **`marked_true=56`**；
- **`report_methodology` 的 TIMING-10（Missing property on synchronizer）仍然是 1**（件 `build/evidence/r115_base/methodology.txt` SUMMARY 行）。
  ⇒ 剩下的那一处**没有被识别**：格雷码链不是它。这是本轮的一条"未知对象"债务（G12 要求它被列进下一轮候选，不许"未知原因但绿了"）。
  ⇒ 教训已记（#290）：**属性有没有落地**不能拿 methodology 的计数当凭据，它数的是"检查项"，不是"我的属性"。
   durable 的尺子是 `report_cdc -details` 点名到具体那对触发器（注意：仓库里 9 月那份 `build/cdc_details.rpt` 是**过期件**，不许引用）。

## 5. 异步组外跨域路径没有界（#266）

`report_exceptions`（件 `build/evidence/r115_base/exceptions.txt`）的表体只有一类跨钟行：
`{clkfbout clkfbout_1 clkout0_1 clkout1_1 clkout2 sys_clk} → {clk_fpga_0}` 与 `{eth_rxc} → {clk_fpga_0}`，
Setup/Hold 两列都写 `clock_group` ⇒ 这两对**被整体排除**，没有任何 `set_max_delay -datapath_only` 给出界。
按附录 1：界**叠不到**被排除的时钟对上（写在 `set_clock_groups` 之上会得到 0 条例外）。
⇒ 这条债**不能靠加约束消**；能做的只有收窄排除策略，而那会改变 WNS 的计算对象 = H1 的松动。
结论按提示词原样写：这是**工具语义边界**，不是我的疏漏，但也不能说它无害——跨域数据完全靠结构（§3 那四条）保证，STA 不参与。

## 6. `check_timing` 与 `report_methodology` 的类别计数（G4 的基线侧）

- `report_methodology`：**Checks found: 446 = DPIR-1 2 + LUTAR-1 1 + SYNTH-5 336 + SYNTH-6 98 + TIMING-9 1 + TIMING-10 1 + TIMING-18 7**
  （七项相加 446，闭合；只从 SUMMARY 表取数，整份文件 `grep -o` 会把每类多算一次）。
  TIMING-18（Missing input or output delay）7 条 = §2 那 11 个端口的**另一种量纲**（checks/pins，不是端口数）⇒ 两个数永不相减（附录 1 的量纲红线）。
- 工具侧的一条新账：`build/evidence/r115_base/check_timing.txt` **文件名与内容不符**——
  它里面的 `| Command :` 是 `report_timing`，不是 `check_timing`（22:59 实测）。
  本轮所有 I/O 债务的读数一律取自 `check_timing_verbose.txt`（它的 Command 行是 `check_timing -verbose`）。
  改名/重出这件事归到探针脚本 `build/tcl/r115_baseline_probe.tcl`，不在文档里含糊过去。

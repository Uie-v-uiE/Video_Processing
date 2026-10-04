# r118 结果页（最后一轮：只带收口眼心 τ=31；C9 已量过并否决）

写于 2026-10-04 04:22（链子 `build/r118_chain.sh` 04:18:25 起飞，件 `build/r118_console.txt`）。
本页只放**有件的数**；依赖官方构建的格子标 `【链子落地后填】`，不提前涂绿。

## 一、这一轮带什么、不带什么

**带**：`src/rtl/top/system_top.v` 的 `IDELAY_VALUE = 31`（r116 在同一份已布线 DCP 上把 0…31 扫满
量出来的收口眼心；两条实测直线 `HOLD(τ) = −2.822 + 0.0630τ`、`SETUP(τ) = +2.005 − 0.0920τ`，
`min(hold,setup)` 的最大点在 τ=31，比出货值 τ=26 抬 +0.315 ns。件 `build/evidence/r115_window/probe3_console.txt`）。

**不带**（两件都是量过之后的决定，不是"没做"）：

1. **RGMII 输入窗**（`src/constraints/r116_rgmii_input_window.xdc`）——r116 绑上它之后，那 5 个第一次被
   检查的端点把发布门的 4 条硬项判红（WNS/WHS/两个失败端点数）。仓库自己的门禁结论是
   "有红项 ⇒ 不采纳，保留上一版"。约束**不删**、证明**不删**，构建默认**不加载**，
   `VP_R116_IO_WINDOW=1` 一条命令复现带窗那一版（`build/tcl/build_system_axigpio.tcl` 里写着为什么）。
2. **C9 强制复制那根 239 引脚广播网**——见第三节。

⇒ 这一版的定位要说准：**它是一版"把收口到达窗推到实测眼心、且名册对 r114 逐格不劣化"的构建**，
它的收益不体现在片内 slack 上（τ 只动 I/O 单元的抽头），所以判据是 **B1 不劣化 + B4 发布门 + 板级复验**，
不是"WNS 变好"。把 τ=31 写成"WNS 收益"就是规矩 35 禁的那种读法。

## 二、判据（04:18 起飞前登记在 `build/r118_chain.sh` 头部，不接受事后改口径）

| 编号 | 判据 | 尺子（件） |
| --- | --- | --- |
| **B1** | 严格名册：4 域 × setup/hold 共 8 对里，**任何一格相对 r114 不许变小** | `build/evidence/r118_strict_b1.txt`（逐格 `GAIN/SAME/LOSS` + 末行 `losses= verdict=`） |
| **B2** | 机构中性：构建日志里**没有** `R117HOOK`（这版故意不挂复制钩子）；`unconstrained_internal_endpoints` 仍 0 | `build/r118_build_console.txt`、`build/tcl/r117_io_probe.tcl` 那一支的复检 |
| **B3** | 资源中性：Slice 寄存器与 r114 同值（8188）、LUT/BRAM/DSP 不变，无 `Place 30-439`、`route_status` successful | `build/utilization.rpt`、`build/evidence/r118_after.txt` |
| **B4** | 发布门：判定 24 项里红数 **== 1**（只有声明过的 `C5c`），且门禁两跑逐字节一致 | `build/r118_gates.txt` |
| 采纳 | 四条全过 ⇒ 刷 r118 + `board_verify --geom --battery --round=r118`；任一不过 ⇒ **板子回刷 r114**，r118 记"量过并否决" | `build/evidence/r118_board/BOARD_NOW.txt` |

⚠ B1 用的是**严格那把**尺子，不是 `build/timing_roster_diff.sh` 的 D3（D3 的门槛是"掉 25 % 以上的域数"）。
同一份数据两把尺子可以给不同判语，这件事记在 `report/log/ISSUES.md` **#328**；我没有改宽任何一方，
而是把严格判据独立成件，交付承诺按它判。

## 三、C9 为什么被否决（r117 官方构建的实测，全部有件）

| 域 / 类型 | r114 | r117 | 读法 |
| --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.850 ns（18.50 %） | **2.104 ns（21.04 %）** | 赢 +0.254 ns |
| `clkout0_1` setup | 3.630 ns（18.15 %） | **3.353 ns（16.77 %）** | 跌 −0.277 ns |
| `eth_rxc` setup | 0.739 ns（9.24 %） | **0.615 ns（7.69 %）** | 跌 −0.124 ns（全设计最紧那格） |
| `eth_rxc` hold | 0.052 ns | **0.044 ns** | 跌 −0.008 ns（全设计最薄那格） |
| `sys_clk` setup | 14.876 ns | **14.815 ns** | 跌 −0.061 ns |

机制本身**无可疑**：`impl_1/runme.log` 与 `build/r117_a1_read.sh` 两处出水口都记到
`u_pl/u_row/hi_reg_0[0]` 从 239 引脚折到 1、长出 10 颗 replica，位流 `beda9298331d`。
⇒ 结论不是"这刀没生效"，而是**"生效了，但代价落在最紧的两个域上"**——这正是 r115 那一夜
C1 复制刀被判负的同一个形状（`report/log/ISSUES.md` #288）。按 H7 回滚，原件与数都留着。

## 四、这一轮结束时"全局到极限"这句话的完整形状

**B1 已经判完（04:38:55，件 `build/evidence/r118_strict_b1.txt`）：8 对逐格与 r114 逐位相同**
——`clk_fpga_0` 1.850 / 0.053、`clkout0_1` 3.630 / 0.059、`sys_clk` 14.876 / 0.222、
`eth_rxc` 0.739 / 0.052，一格不差。这条读法要说准：它**不是**"τ 改了但时序没变"的巧合，而是
`IDELAY_VALUE` 只动 I/O 单元抽头、不动片内任何一条锥，所以片内名册本就该逐位复现；
它顺带给的那件是**放置与布线在这套工具上可复现**（与 r110/r113 的空白滚、r115 的
`noise_ns=0.000` 同一条事实）。τ=31 的收益在片外：眼心余量 +0.315 ns（件
`build/evidence/r115_window/probe3_console.txt`）。

门禁绿/红计数、板上 bit 身份与 `board_verify --geom --battery` 的读数**以件为准**：
`build/r118_gates.txt`（本轮那两次）、`build/r118_gates_final.txt`（改口之后重跑的那对）、
`build/evidence/r118_board/BOARD_NOW.txt`；本页不复述这几个数，就是为了不让"早上看到的句子"
跑在"件"前面（规则 44）。

⇒ 采纳后允许的写法只到这一句：**四个域逐格要么为正、要么被证明了关不掉；非放宽的物理杠杆
（策略扫描、同 DCP 重滚、Pblock、BRAM 换 setup、复制广播网 C9、灰码 ASYNC_REG、τ 扫档）已全部量过并给出赢或判负；
唯一还能改变结论的是架构那一刀（IDDR 吃短捕获钟 + 一级同步 FIFO 再进 BUFG 流水线），
门槛与代价面在 `report/TIMING_GLOBAL.md` 第 7 节，动手前还欠一个 40 秒只读实测（BUFIO 快/慢角 DCD，#323）。**
仍然**不许**写的两句：① "板上真实 hold 差额就是 −0.870"（窗模型自身有 `TskewR` 混行的残余风险，
`rgmii_window_model.md` §6/§7.5）；② "换短钟也关不掉"（那个角间差没实测）。
以及第三句新的不许写：**"收口 I/O 已通过时序检查"**——本版没有窗，那 5 个端点是未检查状态
（H5：未检查 ≠ 满足），这句已经写在首页那一行里。


## 五、08:1x 之后补的两件事（眼睛那一读 + 位流身份）

1. **E6 在 r118 上判过了**：冷上电（≥10 s）+ 只跑三步链 + 不碰 KEY1/KEY2，`ROT:` 读 **0**（队员 07:5x 原话「0度」）。
   这一版的预期本来就是 0（`ASYNC_REG` 只是放置指令，不碰上电值那条逻辑），所以这一读把 r118 的"片内中性"从名册那一侧补到了板的一侧。件 `build/evidence/r118_eyes/`。
2. **B1 名册逐位相同不等于"提交物身份相同"**：`git show HEAD:build/system.bit | md5sum` 量到 HEAD 里还是 r116 那块 ⇒ r118 的采纳笔漏了位流与报告（ISSUES #332）。
   补完之后 HEAD 与工作区对同一块 `cd04907e1369…` 逐位相同，读回件 `build/evidence/r118_eyes/head_bit_md5.txt`。
3. 门禁的最终形状没有因为这两件事改变：**23 绿 / 1 红**（唯一红 = 声明过的 `C5c`），两跑逐字节一致（`build/evidence/r118_board/g2c.txt`、`g3c.txt`、`gatesc_summary.txt`）。

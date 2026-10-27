# 00 · 从零开始：钟沿、setup/hold、slack，以及本工程的五张量纲表

> "时序优化"三篇的第一篇。读者假定：会写 `always @(posedge clk)`，从没做过静态时序分析（STA）。
> 这一篇只做一件事——**把 STA 的名词换成能点开的文件和能复算的除法**。
>
> 三条全文通行的规矩：
> 1. **每个数字都点名出处**。写 `(实测)` 的是本仓库盘上那份文件的第几行；
>    写 `(数据包 §X)` 的是本次写作依据的那份时序数据包（`report/study/timing/90-numbers-index.md`）第 X 节。
> 2. **报告形状必须实测，不许猜行号、不许猜列名**（§3.5 给能自己复跑的命令）。
> 3. **"没检查"不等于"满足"**。这不是修辞，是账本口径——`data/metrics.csv:6`
>    就写着"收口 I/O 的 5 个端点当前无输入窗 = 未检查"。
>
> 器件 `xc7z020clg484-2`（Zynq-7020，CLG484，速度等级 2），工具 Vivado / Vitis 2025.2.1（数据包 §1）。
> 这四点印在每份时序报告头上：`build/timing_summary.rpt` 第 3 行工具版本、第 8 行
> `Device : 7z020-clg484`、第 9 行 `Speed File : -2 PRODUCTION 1.12 2019-11-22`、
> 第 10 行 `Design State : Routed`。**读任何时序报告第一件事是看这四行**：没布线的报告里
> route 延时是估的，和板上那颗位流不是一回事。

---

## 1. 一个触发器怎么在钟沿取数

### 1.1 launch edge、capture edge、端点

```verilog
always @(posedge clk) din  <= a;        // 第一个触发器
always @(posedge clk) dout <= din + b;  // 第二个触发器
```

STA 不看"程序怎么执行"，它看**两个钟沿之间发生了什么**：第一个触发器在它的 `posedge clk` 收下 `a`、
从 `Q` 放出——放人的那个沿叫 **launch edge（发射沿）**；数据在片子里往外走（出 `Q` → 走线 → 组合逻辑
→ 再走线 → 到第二个触发器的 `D` 脚）；第二个触发器在**下一个**（有时是同一个，见 §1.5）`posedge clk`
采样 `D`——那个沿叫 **capture edge（捕获沿）**。一条"路径" = 一个发射沿 + 一段数据到达 + 一个捕获沿。

报告里每条路径都有名字（实测 `build/timing_summary.rpt:230-233`）：

```
Source:      u_pl/u_arb/owner_eth_reg/C
             (rising edge-triggered cell FDCE clocked by clk_fpga_0 {rise@0.000ns fall@5.000ns period=10.000ns})
Destination: u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]
             (rising edge-triggered cell RAMB36E1 clocked by clk_fpga_0 ...)
```

`Source` 是发射触发器的 `C` 脚，`Destination` 是捕获单元的采样脚。注意终点：`RAMB36E1`（一块 BRAM）
的 `WEA[0]`（写使能位），不是触发器的 `D`。**STA 检查的对象是任何"被钟沿采样"的引脚**：`D`、`CE`、
`S/R`、BRAM 的 `ADDRARDADDR`/`WEA`/`ENARDEN`、DSP 的输入寄存器脚……统称**端点（endpoint）**。
本设计共 **51,135 个端点**（实测 `:151`）。"端点"的数量级不是"几十个模块"，是**五万个要逐个回答的
采样脚**——这句话决定了 §1.8 为什么要用"失败端点数"而不是只看一个 slack。

### 1.2 数据路径由哪几段延时组成

报告把发射沿到捕获沿之间收到的总时间写成一行（实测 `:237`）：
`Data Path Delay: 7.544ns (logic 0.484ns (6.416%) route 7.060ns (93.584%))`

| 组成 | 报告里叫什么 | 由谁决定 |
| --- | --- | --- |
| **cell delay（单元延时）** | 逐行足迹里的 `(Prop_fdce_C_Q)`、`(Prop_lut6_I3_O)` | 器件手册 + 工艺角 + 这个单元在算什么 |
| **net delay（网络延时）** | 逐行足迹里的 `net (fo=N, routed)`，`N` 是扇出 | 布线器选了哪条金属、跨了几行几列 |
| **routing（互连）** | 上面 net 的合计；报告把 `logic` 与 `route` 两项相加 | 布局（谁挨着谁）+ 布线 |

同一条路径的逐拍足迹（实测 `:259-263`，原文照抄）：

```
SLICE_X43Y79   FDCE (Prop_fdce_C_Q)   0.379  2.835 r  u_pl/u_arb/owner_eth_reg/Q
               net (fo=269, routed)   6.576  9.411    u_pl/u_row/hi_reg_0[0]
SLICE_X96Y12   LUT6 (Prop_lut6_I3_O)  0.105  9.516 r  u_pl/u_row/lo_reg_0_16_i_2/O
               net (fo=1, routed)     0.484 10.000    u_pl/u_bilin/u_fb/lo_reg_0_16_1[0]
RAMB36_X5Y2    RAMB36E1                          r    u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]
```

读法（全篇最要紧的一个动作）：第一列是**物理坐标**，`SLICE_X43Y79 → SLICE_X96Y12` 横向差 53 个 SLICE、跨了时钟
区域；`Incr` 是这一步花多少，`Path(ns)` 是累计时刻；**最贵的两项都是 `net`**（6.576 + 0.484），两个单元脚合计只花
0.379 + 0.105 = 0.484 ns——括号里 `route 93.584 %` 就是这么来的；`fo=269` 是这根线带 269 个负载（本工程另有一根
239 引脚的广播网被针对做过强制复制，量过并否决，数据包 §3.1、见 §6.2）。

**这条路径只有 1 级逻辑**（实测 `:238`：`Logic Levels: 1 (LUT6=1)`），却吃掉 10 ns 周期里的 7.544 ns。
它是"改逻辑没用"的教科书例子：1 级的路没有算术可拆，能动的只有**布局**（把发射触发器搬到 BRAM 旁边）。

### 1.3 setup 检查比的是什么

setup 问一句话：**数据赶得上捕获沿吗？** 报告用两个数回答（实测 `:229`）：
`Slack (MET) : 1.850ns (required time - arrival time)`。

- **arrival time（到达时刻）**：§1.2 足迹的累计终点，这里 10.000 ns（实测 `:279`）。
- **required time（要求时刻）**：捕获沿在哪，再扣三笔（实测 `:266-278`）——捕获沿 `10.000 ns`
  （`:236` 的 `Requirement`）、`clock pessimism +0.097` 与 `clock uncertainty -0.154`、
  端点自己的建立时间 `Setup_ramb36e1_CLKARDCLK_WEA[0] = -0.476`；合起来 `required 11.850`（`:278`）。
- **slack = 11.850 − 10.000 = 1.850 ns**（实测 `:281`）。

`Requirement` 那行把"捕获沿减发射沿"写得很直白（实测 `:236`）：`10.000ns (clk_fpga_0 rise@10.000ns - clk_fpga_0
rise@0.000ns)`——**setup 的检查窗口 = 两沿之间的距离**，同域就是整整一个周期。这条公式解释后面所有事的量纲：
**周期越短、窗口越小**（100 MHz 给 10 ns，125 MHz 只给 8 ns）。

### 1.4 hold 检查比的是什么

hold 问另一句：**数据会不会太早，把上一个沿刚收的值冲掉？** 本设计真的一条 hold（实测 `:289-298`）：

```
Slack (MET) :  0.053ns  (arrival time - required time)
  Source:      u_bd/.../reg_slice_r/m_payload_i_reg[12]/C
  Destination: u_bd/.../memory_reg[31][9]_srl32/D
  Path Group:  clk_fpga_0
  Path Type:   Hold (Min at Fast Process Corner)
  Requirement: 0.000ns  (clk_fpga_0 rise@0.000ns - clk_fpga_0 rise@0.000ns)
  Data Path Delay: 0.249ns  (logic 0.141ns (56.528%)  route 0.108ns (43.472%))
  Logic Levels:    0
```

三处与 setup 正好相反：① **减法调头**，`slack = arrival − required`（正 = 到达得够晚）；
② **Requirement 是 0.000 ns**，发射沿与捕获沿是**同一个沿**；③ **角换了**——setup 查慢角
（`:235` `Setup (Max at Slow Process Corner)`），hold 查快角（`:295`，让最快的情形显形）。

### 1.5 为什么 hold 与频率无关

四个域的 hold `Requirement` 全是 0.000 ns，逐条实测：

| 域 | 原文 | 实测行 |
| --- | --- | --- |
| `clk_fpga_0` | `0.000ns (clk_fpga_0 rise@0.000ns - clk_fpga_0 rise@0.000ns)` | `:296` |
| `eth_rxc` | `0.000ns (eth_rxc rise@0.000ns - eth_rxc rise@0.000ns)` | `:459` |
| `sys_clk` | `0.000ns (sys_clk rise@0.000ns - sys_clk rise@0.000ns)` | `:620` |
| `clkout0_1` | `0.000ns (clkout0_1 rise@0.000ns - clkout0_1 rise@0.000ns)` | `:870` |

20 ns 的域、10 ns 的域、8 ns 的域，hold 窗口**都是 0**——hold 不看周期，只看"同一个沿放出的数据
有没有晚于这个沿的 hold 要求 + 时钟偏斜"。两条实用结论：

1. **降频救不了 hold。** setup 窗口随周期线性变宽，hold 窗口恒为 0。本工程 hold 余量最小的
   `clkout0_1` 是 0.059 ns（数据包 §1），而它的周期 20.000 ns 是全场最宽的一档。
2. **hold 的主战场是"最小延时 vs 时钟偏斜"**，不是算术深度。上面 0.053 那条 `Logic Levels: 0`
   （实测 `:298`），中间没有一级组合逻辑；`clkout0_1` 最差 hold 也是 `Logic Levels: 0`（实测 `:872`），
   起止还是"一组寄存器传到隔壁那一位"——逻辑上没东西可优化。

顺带给一把本工程量过的最小尺子：IDELAY 抽头**每档 63 ps**（数据包 §3.3）。`clkout0_1` 的 WHS
0.059 ns 比一档 IDELAY 还细 ⇒ 这条只能靠结构或靠放置改，"调一档看看"在它面前没有分辨率。

### 1.6 slack 的正负怎么读

- **正 slack（`MET`）不等于"这条好"**，它等于"在工具假设的边界条件下这一条不违规"。边界条件写在同一份报告里：
  慢角与快角都参与分析（实测 `:32-36`）、`Enable Pessimism Removal : Yes`（实测 `:21`）。**负 slack
  （`VIOLATED`）也不等于"板子一定错"**，它等于"至少有一组边界条件下这个采样不可靠"；反向也不成立——报告全绿
  不能证明板子对：`src/rtl/eth/rgmii_rx.v:10-11` 就是这个口径，报告只能证明内部路径，采样点落没落在眼里
  要由实流量判据（`bad`/`drop_words`）说。
- **符号位要留给所有列**。本项目栽过一次：违例时 `TNS` 是负数，门禁脚本只给 WNS/WHS 留了符号位、没给 TNS
  两列留 ⇒ 匹配不到 ⇒ 打印"读不到"再 `exit 2`，把最该看见的数字（WNS −0.482 / 19 个失败端点）换成了
  "读不到"这句话（`build/gates.sh:74-79` 记录，`:80-82` 是改后的写法）。
  **教训：尺子读不懂被测对象时，必须把它读的那一行原样打出来。**

### 1.7 WNS / TNS / WPWS / TPWS

汇总表表头 16 个字段与数据行照抄（实测 `:149` 与 `:151`）：

```
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
      0.739        0.000                      0                51135        0.052        0.000                      0                51135        0.264        0.000                       0                 12634
```

| 缩写 | 全称 | 含义 | 本设计读数 |
| --- | --- | --- | --- |
| WNS | Worst Negative Slack | 全场最负（这里是最小正值）的 setup slack | 0.739 ns |
| TNS | Total Negative Slack | 所有违规 setup 路径的 slack 求和 | 0.000（无违规，和就是 0） |
| WHS / THS | 同上，hold 版 | 最差 hold / hold 违例总和 | 0.052 ns / 0.000 |
| WPWS / TPWS | 同上，**最小脉冲宽度**版 | 时钟的高/低电平够不够长 | 0.264 ns / 0.000，作用在 12,634 个端点上 |

`:154` 那句 `All user specified timing constraints are met.` 是同一结论的另一种写法——它只说
"已纳检的都过了"，§4 会反复回到这句话的射程。WPWS 是最容易跳过的一列：**它与周期无关，与"这一拍钟沿
自己站不站得住"有关**。`clkout1_1`（250 MHz，周期 4.000 ns）在 Intra Clock Table 里 WNS/WHS 两格是空的，
只有脉宽那栏有数 `2.408 / 0.000 / 0 / 10`（实测 `:187`）；技术文档把这一行写成"不纳检（见 §6.4）"
（`report/technical-document.md:55`，数据包 §1 同）。**读法：某个域的 WNS 格是空的 = 这个域里没有 setup
端点被检查**，既不是"余量为 0"也不是"这个域过了"——250 MHz 那域只有串化原语（OSERDESE2）的时钟脚要站住，
算术在 50 MHz 像素域做完再送过来；同样的空格在 `clkfbout`、`clkfbout_1`、`clkout2` 三行
（实测 `:184-185, 188`）：反馈钟与 IDELAY 参考钟，只有脉宽检查。

### 1.8 "失败端点数"为什么比 WNS 更能说明问题的形状

只看 WNS 会把两种病读成同一个数。**形状 A：一两条特别差**——WNS −6 ns、TNS −6 ns、失败端点 1 个 ⇒ "某个锥太深"，
拆拍或搬模块能救。**形状 B：一大片都差一点**——WNS −0.2 ns、TNS −200 ns、失败端点 3,000 个 ⇒ **系统性**问题：
钟树偏斜、约束口径、congestion 或整体放置不合理，拆那一条锥只会让下一条浮上来。这就是本工程把"失败端点数"与
WNS 并列进门禁的原因（`build/gates.sh:197` 之后紧跟失败 setup / 失败 hold 两条），也是为什么当前读数要念成整套：
**WNS 0.739 ns + 0 个失败 setup 端点 + 0 个失败 hold 端点 + 分母 51,135**（实测 `:151`）——违规面为零，
但最紧的一条只剩周期的 9.2 % 可用（怎么算见 §2.2）。分母还回答"这一格是谁家的"（实测 Intra Clock Table `:181-186`）：

| 域 | WNS | 端点 | WHS | 端点 |
| --- | --- | --- | --- | --- |
| `clk_fpga_0` | 1.850 | 15,721 | 0.053 | 15,721 |
| `eth_rxc` | 0.739 | 4,835 | 0.052 | 4,835 |
| `sys_clk` | 14.876 | 323 | 0.222 | 323 |
| `clkout0_1` | 3.630 | 30,179 | 0.059 | 30,179 |

`sys_clk` 只有 323 个端点、WNS 14.876 ns——**它的"松"有一半是因为它几乎不干活**（按键、慢速控制，
数据包 §1）；`clkout0_1` 扛 30,179 个端点（帧缓存写侧 + AXI 全互连）。比较两个域之前先看端点数再看 slack。

---

## 2. 本工程的量纲：五个时钟域与各自余量

### 2.1 那张五域表

出处 `report/technical-document.md:49-55`（数据包 §1 是同一份）；端点列从 `build/timing_summary.rpt:181-187` 实测补上。

| 域 | 频率 | 周期 | 用途 | setup WNS (ns) | hold WHS (ns) | 端点 |
| --- | --- | --- | --- | --- | --- | --- |
| `sys_clk` | 50 MHz | 20.000 | 板载晶振输入、按键、慢速控制 | 14.876 | 0.222 | 323 |
| `clk_fpga_0` | 100 MHz | 10.000 | AXI 全互连与帧缓存写侧（PS FCLK0） | 1.850 | 0.053 | 15,721 |
| `clkout0_1` | 50 MHz | 20.000 | 显示读出、几何、效果链、OSD（`clk_pix`） | 3.630 | 0.059 | 30,179 |
| `eth_rxc` | 125 MHz | 8.000 | RGMII 收发、协议栈、仲裁 | 0.739 | 0.052 | 4,835 |
| `clkout1_1` | 250 MHz | 4.000 | TMDS 串行化（OSERDESE2） | 不纳检 | — | 10（仅脉宽） |

**这张表是后面所有讨论的量纲基准。** 五域里三只是同源不同频（`clk_fpga_0` 从 PS 出来，`clkout0_1`/
`clkout1_1`/`clkout2` 由 PL 侧 MMCM 分出），它们的树各有多重在 `build/clock_util.rpt:59-66` 的 BUFG 表里：
`clk_fpga_0` 走 `BUFGCTRL_X0Y16` 带 3,597 个负载、`clkout0_1` 走 `BUFGCTRL_X0Y0` 带 3,276 个、`eth_rxc` 走
`BUFGCTRL_X0Y1` 带 2,544 个（源 `u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O`）、`sys_clk` 走 `BUFGCTRL_X0Y4` 带
186 个；BUFG 用量 8/32（`:43`）、MMCM 用量 2（`:48`，与 `build/utilization.rpt:163` 的
`MMCME2_ADV | 2 | ... | 4` 是同一件事）。**读时钟问题第一眼就该看 BUFG 表**，它直接说哪只钟的树最重。

### 2.2 把 ns 换算成"这一周期里逻辑可用时间占百分之几"

`WNS / 周期` 是**余量占比**，`1 − WNS / 周期` 是**这一周期里被数据路径吃掉的比例**（严格说还要扣钟偏斜、不确定度
与端点自己的 setup 要求，见 §1.3 那三笔扣项，所以它是"可用时间的上限"）。每行都是 §2.1 里两个数的除法，可自算：

| 域 | 周期 | WNS | 余量占周期 | **逻辑可用时间占周期** | 一句话读法 |
| --- | --- | --- | --- | --- | --- |
| `sys_clk` | 20.000 | 14.876 | 74.4 % | **25.6 %** | 四分之三的时间是空的；这域不参与时序竞争 |
| `clk_fpga_0` | 10.000 | 1.850 | 18.5 % | **81.5 %** | 十个纳秒里 8.15 已走完，还剩 1.85 可分 |
| `clkout0_1` | 20.000 | 3.630 | 18.2 % | **81.8 %** | 和上一行几乎同宽，却扛 30,179 个端点 |
| `eth_rxc` | 8.000 | 0.739 | 9.2 % | **90.8 %** | 最紧：十个周期里只能留下不到一个周期 |

`clkout1_1` 不做这个除法——它的 WNS 格是空的（实测 `:187`），没有分子。

### 2.3 怎么用相对余量读"松还是紧"

1. **同周期档内比大小才有意义。** `clkout0_1`（3.630）绝对值是 `eth_rxc`（0.739）的 4.9 倍，按占比看是
   18.2 % 对 9.2 %，差 9 个百分点而不是"5 倍宽"。只看绝对 ns 会把 50 MHz 域读成"很松"、125 MHz 域读成"要死了"。
2. **占比低不一定坏；占比低 + route 占比高才难改。** `eth_rxc` 最差 setup 是 `logic 41.553 % /
   route 58.447 %`、`Logic Levels: 11 (CARRY4=6 LUT3=2 LUT4=2 LUT5=1)`（实测 `:373-374`）——11 级、
   6 条进位链，**有算术可拆**；`clk_fpga_0` 那条 1.850 是 `Logic Levels: 1` + `route 93.584 %`
   （实测 `:237-238`）——**没算术可拆**。两条"都很紧"的路径能下的刀完全不同
   （`CARRY4` 这个单元名一出现就该想到进位链/加法器）。
3. **hold 用绝对时间比，不用占比比**（§1.5：窗口恒为 0，没有分母）。

### 2.4 为什么 WNS 的绝对差不算收益也不算损失

本项目的纪律（数据包 §3.5；仓库里同一句话在 `report/technical-document.md:270-271`）。三条实测出来的理由：

1. **跨构建摆幅就有 0.4 ns。** 同一棵树重跑曾**逐位复现**正式构建的 WNS 读数 ⇒ 放置是确定性的，所以"两次构建
   差 0.4 ns"这类跨构建差值不能当收益（数据包 §2）。工具策略扫描就撞上这条：换一档量到 WNS +0.013，比基线低
   0.54 ns，超出实测 0.4 ns 摆幅 ⇒ 判它不是噪声里挑好看的；另一档与基线**一格不差**；两档都不采纳
   （数据包 §3.4；读数留在 `build/r95b_timing_summary.txt`，`:7` 基线、`:8-9` 两档）。
2. **WNS 会换族。** `dc_fifo` 格雷码链补 `ASYNC_REG` 那次，同一次构建 WNS 0.445→0.739，最差路径换成 `icmp_tx`
   的校验和锥（数据包 §3.1，§5.3 展开）——分子换了，差值不是同一件事的差值。
3. **别的域不许变差。** 采纳条件要求逐域念"变好 / 变差 / 没量"（数据包 §3.5）。

所以余量要念**相对值**。数据包 §3.5 给了一条完整样本，值得照抄它的记法：

> `clkout0_1` 那条：1.130 ns / 23 级 / route 77.5 % → 4.094 ns / 21 级 / 62.8 %，
> 相对余量 5.65 % → 20.5 %，代价 +2 LUT / −6 FF。

四个动作：分子分母都写（分母是周期 20.000 ns：1.130/20 = 5.65 %，4.094/20 = 20.5 %）；**级数与 route
占比同写**（23→21 级、77.5 %→62.8 %：两格同向才是结构改动的签名，单看 slack 看不出来）；**代价写**
（+2 LUT / −6 FF，资源与时序必须在同一次构建里一起结）；**不写"优化了 X ns"**。资源侧同期账（实测
`build/utilization.rpt`）：Slice LUT 14,154（26.61 %，`:35`）、Slice 寄存器 8,188（7.70 %，`:40`）、
Block RAM Tile 95.5/140（68.21 %，`:106`）、DSP48E1 19（`:212`）——只念 slack 变化、不念 LUT/FF 变化，
是这个领域最常见的漏账。

### 2.5 两把尺子并存：那条 0.800 ns 的 hold 带

同一份报告里，四个域的 WHS **不是同一把尺子量出来的**（数据包 §3.3）：

- `eth_rxc` 最差 hold 印着 `Clock Uncertainty: 0.800ns ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE + UU`
  （实测 `:466`）。末尾那个 **`+ UU`** 是 user uncertainty，即 `set_clock_uncertainty` 显式加的带；
  这一行的 TSJ/TIJ/DJ/PE 全是 0.000（实测 `:467-470`）⇒ 0.800 全部来自人为这条带。
- 另外三个域的最差 hold 段**根本没有 `Clock Uncertainty` 这一行**（`clk_fpga_0` 段实测 `:289-302`、
  `sys_clk` 段 `:613-625`、`clkout0_1` 段 `:863-875`）⇒ 它们的 hold 只扣钟偏斜，不扣人为带宽。

后果：**0.053 / 0.059 / 0.052 三个数不能直接比大小**，减掉的东西不一样多。统一加 0.800 ns 带的实测结果：
WHS 变 **−0.747**、失败 hold 端点 **25,742 个**（数据包 §3.3）——现在那四格 0.05x 是"没减带宽"的读数，
减了带宽，全场 hold 一起塌成形状 B（§1.8）。汇报时的口径纪律：**"两把尺子并存"必须念出来**（数据包 §3.3）。

---

## 3. 时序报告怎么读（teaching 一份真的）

本节全部围绕盘上那一份 `build/timing_summary.rpt`（`Date : Sun Oct 4 04:37:30 2026`、`Design State : Routed`，
实测 `:4`、`:10`）。重跑构建会原地重写它，**引用行号前先确认还是同一版**。

### 3.1 骨架与两张账本

| 段 | 行 | 该看什么 |
| --- | --- | --- |
| banner | `:3-10` | 工具版本、日期、**产生这份件的命令原文**（`:6`）、设计名、器件、速度档、Design State |
| Timer Settings | `:16-36` | `Enable Pessimism Removal`（`:21`）、哪些角参与分析（`:32-36`） |
| Report Methodology | `:39-52` | 方法学违规计数（`:46-52`，只取 SUMMARY 表） |
| check_timing | `:58-140` | 12 项覆盖检查——"没检查"的账本（目录 `:62-73`，展开 `:99-110`） |
| Design Timing Summary | `:144-154` | WNS/TNS/失败端点/总数 × setup/hold/脉宽（`:149` 列头、`:151` 数据） |
| Clock Summary / Intra / Inter | `:157-171` / `:174-188` / `:191-199` | 每只钟的波形周期频率；域内与跨域的 slack 与端点 |
| Other Path Groups / Timing Details | `:202-209` / `:211-` | 不属于任何钟组的例外路径（这份是空的）；每个 From/To 段一段，段内逐条列最差路径 |

**Methodology 的计数只取它的 SUMMARY 表**（数据包 §3.5）。实测 `:46-52` 那 7 行是 `DPIR-1 2`、`LUTAR-1 1`、
`SYNTH-5 336`、`SYNTH-6 98`、`TIMING-9 1`、`TIMING-10 1`、`TIMING-18 7`；整文件 `grep -o` 会把每类多数一遍，
所以计数要与它自己的 `Checks found:` 加总一致。`SYNTH-5` 那 336 条不是错误是选择：窗口级行缓存走 LUTRAM、
按约束映射成分布式 RAM 就会报它；`TIMING-9 / TIMING-10`（实测 `:50-51`）与 §5 的 CDC 直接有关。
`check_timing` 是覆盖率账本（实测目录 `:62-73`：`no_input_delay (7)`、`no_output_delay (12)`，其余 10 项为 0），
展开（实测 `:99-110`）：

```
There are 5 input ports with no input delay specified.                      (HIGH)
There are 2 input ports with no input delay but user has a false path ...   (MEDIUM)
There are 6 ports with no output delay specified.                           (HIGH)
There are 6 ports with no output delay but user has a false path constraint (MEDIUM)
```

**这 5 格与这 12 格就是"本报告不检查哪些 I/O"的清单**；§4.3 会说为什么"5"这个数比它的计数本身重要。

### 3.2 一条 setup 路径逐字段拆（1.850 ns 那条）

`build/timing_summary.rpt:229-281` 整段 53 行，字段顺序照抄（实测 `:229-245`，长行有省略）：

```
Slack (MET) :  1.850ns  (required time - arrival time)
Source / Destination: 见 §1.1（终点是 RAMB36E1 的 WEA[0]）
Path Group:    clk_fpga_0                    Path Type:  Setup (Max at Slow Process Corner)
Requirement:   10.000ns  (clk_fpga_0 rise@10.000ns - clk_fpga_0 rise@0.000ns)
Data Path Delay: 7.544ns  (logic 0.484ns (6.416%)  route 7.060ns (93.584%))
Logic Levels:  1  (LUT6=1)
Clock Path Skew: 0.024ns (DCD - SCD + CPR)   DCD 2.384 / SCD 2.456 / CPR 0.097
Clock Uncertainty: 0.154ns ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE   TSJ 0.071 / TIJ 0.300 / DJ 0 / PE 0
```

按顺序问五个问题：① **终点是什么脚？** `WEA[0]` = BRAM 写使能位——终点是 `D`/`CE` ⇒ 在改逻辑，终点是
`WEA`/`ENARDEN`/`ADDRARDADDR` ⇒ 在改"存储器的控制"，而存储器摆哪儿由布局器决定。② **logic 还是 route
主导？** `route 93.584 %` ⇒ 绕线主导；把 `LUT6` 拆成两级 `LUT3` 只会让 logic 从 0.484 涨上去，而这条路
只有 6.4 % 是逻辑。③ **扇出与坐标跨度？** `net (fo=269, routed) 6.576 ns`（实测 `:260`）一根线 269 个负载
花 6.576 ns，坐标从 `SLICE_X43Y79` 跳到 `SLICE_X96Y12`——这两行合起来就把"该动哪一手"指出来了。
④ **偏斜多大？** `Clock Path Skew: 0.024ns`（实测 `:239`）：同域同树只有 24 ps，而这个数正是 §6.2 第一刀
要消掉的东西（那条路当年是 1.616 ns）。⑤ **不确定度里哪一项在动？** `TIJ = 0.300 ns`（实测 `:245`）挂在
时钟源上；`set_clock_uncertainty` 是往同一格里再加一条带（§4.1）。

同一份报告里 `eth_rxc` 那条 0.739 形状完全不同：`logic 41.553 % / route 58.447 %`、`Logic Levels: 11`、
`Clock Path Skew: -0.123ns`（实测 `:373-375`）。本设计对这一族的归因结论是**域划分**而不是"某个加法器"：
摊拍后本族 0.739→0.691，最差换成 `rows_hit` 的 CE 广播（route 87.3 %）（数据包 §4）。`rows_hit` 那几条
能直接看到形状——`build/crit_paths.txt:6-10` 五行是 `u_eth/u_rx_par/p_eof_reg/C → u_eth/u_reasm/rows_hit_reg[*]/CE`，
1.017 ns、4 级逻辑。

### 3.3 三条 hold 路径（各有用途）

| 域 | 起止 | 级数 | 括号里 | 实测行 |
| --- | --- | --- | --- | --- |
| `clk_fpga_0` | AXI 交叉开关一位 → 一根 SRL32 移位单元的 `D` | 0 | `logic 56.528 % / route 43.472 %` | `:290-298` |
| `clkout0_1` | `u_pl/u_pipe/u_sobel/no_right_r_reg[0]/C` → 同组 `[1]/D` | 0 | `logic 37.317 % / route 62.683 %` | `:864-871` |
| `eth_rxc` | `u_eth/u_cdc/rgray_s1_reg[10]/C` → `u_eth/u_lm/full_d_reg/D` | 3 | `logic 43.520 % / route 56.480 %`，`CARRY4=2 LUT6=1` | `:453-461` |

三条的 `Requirement` 全是 `0.000ns`（§1.5）。它们分别教：前两条 `Logic Levels: 0`——中间没有一级组合逻辑，"少几级"
救 hold 是没有靶子，能动的只有让两端挨着（布局）、降时钟偏斜、或插缓冲加大最小延时；第三条的起点是格雷码同步链——
`rgray_s1` 就是 `src/rtl/eth/dc_fifo.v:27` 那四颗带 `ASYNC_REG` 的寄存器之一（`dc_fifo` 在
`src/rtl/eth/eth_udp_video_top.v:298` 以 `u_cdc` 例化），它的 `+ UU` 就是 §2.5 那条 0.800 带。另外：**CPR 的符号在
两处相反**——setup 是 `DCD - SCD + CPR`（实测 `:239`），hold 是 `DCD - SCD - CPR`（实测 `:462`）；不用背公式，但要知道
符号会不一样，否则会以为报告写错了。

### 3.4 path group 与 from/to

- **Path Group 默认是捕获侧那个时钟对象的名字。** 所以 `sys_clk → clkout0_1` 那条写着
  `Path Group: clkout0_1`（实测 `:1251`），却出现在 `From Clock: sys_clk` / `To Clock: clkout0_1` 段里
  （实测 `:1144-1145`）。**分组看 From/To 段头，看归属看 Path Group**；不一致时以段头为准。那条的
  `Requirement: 0.000ns (clkout0_1 rise@0.000ns - sys_clk rise@0.000ns)`（实测 `:1253`）是两个不同名字的钟、
  同一个 0 ns 的沿——这就是**同源时钟**（同一只 MMCM 分出来的）在 STA 眼里仍然可算的原因：沿关系确定；
  同段 `Clock Uncertainty: 0.259ns` 里有 `DJ = 0.175 ns`（实测 `:1260-1262`），离散抖动只在两钟有确定关系时
  才算得出来。
- **Inter Clock Table 只有两行**（实测 `:198-199`：`clkout0_1→sys_clk` 19 端点、`sys_clk→clkout0_1` 231 端点），
  **Other Path Groups Table 是空的**（实测 `:207-209` 只有表头）。也就是说 `eth_rxc` 与其余四域之间的路径
  **不在这份报告的跨域账上**——不是"检查过且过了"，是没检查（原因见 §4.2，后果见 §5）。
- **`-nworst 1 -max_paths N` 这条参数纪律**：按域出"最差路径阶梯"的件，参数印在文件头命令行里，例如
  `build/roster_r118_after_eth_rxc_setup.rpt:6`：`report_timing -delay_type max -nworst 1 -max_paths 4
  -from eth_rxc -to eth_rxc -file ...`。钉 `-nworst 1` 的理由：`-nworst 12` 会把同一对 launch/capture 的多个
  边沿组合重复报满 12 行 ⇒ 12 行可能只算 1 档；名册要**从写出的文件里反读 distinct 计数并打印**（数据包 §3.5）。
  文件名里那个编号是当时留下的记号，读文档不需要解释它。

### 3.5 报告形状必须实测：怎么复跑

**"WNS 在第 7 行"这种位置断言（数据包 §3.5 的原话）落到哪份文件上都要复认**：

- `build/timing_summary.rpt` 里 WNS 的**列头在 149 行、数据行在 151 行**（实测；`report/technical-document.md:58`
  也写着 151 是汇总行、154 是那句 "All user specified timing constraints are met"）。
- 同一套检查用门禁脚本打出来时，WNS 落在**第 7 行**（`build/r84_gates.txt:7`），另一份门禁件里落在**第 10 行**
  （`build/r118_gates_final.txt:10`）——中间多了三行 `md5` 身份行，内容都是 `WNS (ns) ... >= 0` 那一格。

⇒ **认形状不认行号。** 仓库里的门禁脚本就是这么写的：按"这一行前六个字段依次是带符号小数、带符号小数、整数、
整数、带符号小数、带符号小数"的形状匹配第一行数据，匹配不到时**把报告里最像的三行原样打出来再 `exit 2`**，
不静默跳过（实测 `build/gates.sh:80-87`）。能自己复跑的三条（都在仓库里、都是只读）：

```bash
awk 'NR==149 || NR==151' build/timing_summary.rpt   # 1) 取列头 + 数据行（16 个字段）
bash build/gates.sh                                 # 2) 不重跑构建，读盘上报告打一遍门禁
# 3) 想重新出这份件：文件头 :6 那行就是产生它的命令原文
#    report_timing_summary -file D:/Xilinx/Prj/pro/Video_Processing/build/timing_summary.rpt
```

成本账（数据包 §2）决定"先量什么再动什么"：一次全流程构建（建工程→综合→实现→出位流）约 20 分钟
（综合 10 分 09 秒、实现含 `write_bitstream` 7 分 22 秒）；整屏顶层台架一轮约两小时；**快车道**（不综合、
不改 RTL，只从已实现的 `impl_1/*_opt.dcp` 重跑 place+route）约 7–9 分钟，仓库里那份车道脚本是
`build/timing_lane.sh`（`:9-15` 写明分工：车道只跑分钟级判据与只读探针，车道的绿**不代替**门禁）。
另一条最省时间的实测：一次不带 design 的 `help <cmd>` 批探测要 40 秒 ⇒ **判据形状要先实测再解析**，
不许靠猜写解析器（数据包 §2、§3.5）。

---

## 4. 约束面：每一条 XDC 在动哪一格

总纲一句话：**约束不改变电路，约束改变"工具检查什么、用什么窗口检查"。** 所以"改约束得到的变好"只有两种：
真的没有违规了，或者**不检查了**。分辨办法是问"检查的面变没变"——看 §1.8 的失败端点数、§3.1 的
`check_timing` 12 项、§3.4 的 Inter Clock Table 有没有行。

### 4.1 `set_clock_uncertainty`：往窗口两边各推一点

它加的是一条**时间带**，不是延时：setup 侧相当于把捕获沿提前（更悲观），hold 侧相当于推后（也更悲观），
落点就是报告里 `Clock Uncertainty` 那行末尾的 `+ UU`（实测 `:466`）。本项目两条实测：只有 `eth_rxc` 挂着
hold 的 0.800 ns 带 ⇒ 四域 WHS 互相不可比（数据包 §3.3，§2.5）；四域统一挂 0.800 ns 带 ⇒ WHS 从正 0.05x
变 **−0.747**、失败 hold 端点 **25,742 个**（数据包 §3.3）——不是某条路坏，是**这条带要求的量比全设计的
hold 余量都粗**。

**它会不会把"本来没检查的"变成"检查的"？不会**——单挂不确定度只让已纳检的路更悲观，真正改变检查面的是
§4.2/§4.3/§4.4；但有一个反向的坑：**去掉**一条带会让 slack 集体变好，看上去像"优化了时序"，实际只是把尺子磨短了。

### 4.2 时钟组（`set_clock_groups`）：把跨域路从账上划走

划进不同异步组的两个钟之间，工具**不做 setup/hold 检查**。证据是本报告 Inter Clock Table 只有 `clkout0_1 ↔ sys_clk`
两行（实测 `:198-199`），`eth_rxc` 与其余四域的组合一行都没有——那些路在 RTL 里确实跨过去了，但不在 STA 的账上。
"异步"的技术含义就是这个：**承认两个钟的相位关系未知，因此不按固定周期算**；代价是这些路的正确性从此由结构保证
（§5），不由工具保证。**读法：报告里"没有那一行"永远是坏消息，不是好消息。** 本工程的欠账里就有一条：异步组外
四条跨域路没有 `set_max_delay -datapath_only`（数据包 §4，见 §4.5）。

### 4.3 `set_input_delay` / `set_output_delay`：给片外世界建一个窗

这两个是**真正把"没检查"变成"检查"的约束**：它们声明"外部器件送来的数据相对这只钟的沿落在哪个区间"，
于是 I/O 那个寄存器脚从此有了 setup/hold 要求。本项目的事故（数据包 §3.3）完整念一遍：

- 挂上 **±0.500 ns** 输入窗之后：WHS 从 **0.050** 掉到 **−2.885**、THS **−14.344**、**5 个失败 hold 端点
  全部落在 `u_iddr_rx_ctl/D`**，那 5 个端点的路径是 **2 级逻辑、route 0.000 %**。
- 读数解释：route 0.000 % 意味着这根线上**没有绕线可优化**——数据本来就贴着钟沿。`u_iddr_rx_ctl` 是 RGMII
  `RX_CTL` 的双沿采样触发器（`IDDR`，`SAME_EDGE_PIPELINED`），例化在 `src/rtl/eth/rgmii_rx.v:87-97`，
  它的 `D` 接 `rgmii_rx_ctl_delay`，也就是 `IDELAYE2` 的输出（同文件 `:67-80`）。
- 加窗必然先打开账本——窗本来就是"本来该有但没有"的那块检查。本项目没把 −2.885 念成"设计坏了"，而是继续量：
  **能不能靠调 τ 关掉？** 答案是量出来的（数据包 §3.3）：在已布线的 DCP 上扫 `IDELAY_VALUE` 0…31
  （`set_property IDELAY_VALUE` 在 DCP 上有效 ⇒ 整条扫描不花构建），量出 hold 每档 **+63 ps**、setup 每档
  **−92 ps** 两条实测直线，交点 τ = 31.1 ⇒ 取整数 31；同一次扫描给出**无解证明**：带发布窗后 hold 要求
  τ ≥ 44.8、setup 要求 τ ≤ 21.8，而器件合法 τ 只有 0…31 ⇒ 两个集合**不相交**；去掉与窗双重计的那 0.800 ns
  不确定度带也只是把下界挪到 32.1，仍不相交。根因读数：两只钟的角间差 **3.411 ns**（hold 慢角 DCD 5.008 /
  setup 快角 1.597），而数据窗口只有 **0.467 ns**；同一套算式在顶层注释里也写着（`src/rtl/top/system_top.v:162-171`，
  `:172` 就是出货值 `.IDELAY_VALUE(31)`）。**结论范围要守**：这只支持"当前结构下无解"，不支持"换短钟也关不掉"
  （BUFIO 快角的 DCD 未实测，数据包 §3.3、§4）。
- 于是那把窗退回候选件，今天的报告上就没有输入窗 ⇒ 收口 I/O 的 5 个端点回到"没检查"（数据包 §4；
  `data/metrics.csv:6` 与 `build/timing_summary.rpt:99` 那个"5 input ports with no input delay"是同一件事的
  两种写法）。**这就是"改约束"的完整代价曲线：加窗 ⇒ 打开账本 ⇒ 看见 5 个负数 ⇒ 要么真改结构，要么把窗摘掉。**

输出侧同构：TMDS 四组输出量过并判 BARE、被拒绝（数据包 §4）；源端窗口只能按 HDMI 规范的 TP1 口径引，不能拿
UG471 的接收窗数——那颗片子的 TMDS 引脚是**输出**（数据包 §4；`report/technical-document.md:215` 也写着
"那是展宽不是捕获窗"）。**"口径借错地方"的代价是把一个好设计判成负裕量。**

### 4.4 `set_false_path` / `set_multicycle_path`

- **`set_false_path`：告诉工具"这条关系不存在，别查。"** 它是**摘检查**，不是加余量；合法用法是准静态配置
  寄存器、确定不会被采样的路径。报告里能看到它的痕迹：`check_timing` 那两条 MEDIUM 就是"没有 input delay
  但有 false path"2 个端口、"没有 output delay 但有 false path"6 个端口（实测 `:101`、`:108`）。这 8 个端口
  在报告里**不会违例**，因为根本没查 ⇒ "这些 I/O 的时序是绿的"这句话在这份报告里是空的。
- **`set_multicycle_path`：告诉工具"这条路窗口不是 1 拍是 N 拍。"** 它改写 `Requirement` 那行的两沿距离
  （对比 §1.3）。合法前提是真的不会每拍变：本设计 `zoom_fit` 那条链的注释给的就是这个前提——"这条链的输入
  一帧才变一次（自动旋转的步进钉在帧首），多一拍对屏上什么都看不见"（`src/rtl/process/zoom/zoom_fit.v:35-38`）。
  但本项目实际选的是**在 RTL 里真拆成两拍**（`:40-43` 那一级寄存器），而不是写一条 multicycle 把它"声明"成
  两拍。差别：拆拍之后工具真的按两拍布线；multicycle 只放宽检查、逻辑还挤在一格里。
  **这就是 §6 那句"改结构优于改约束"的最小心法。**

### 4.5 `set_max_delay -datapath_only`：跨域路唯一的软尺子

它给一条路径只规定"数据最多走 N ns"、**不带时钟偏移**（`-datapath_only` 就是这个意思），适合"两个钟没有确定关系，
但要求数据别走太久、久到超过一两个周期"的跨域路，它是**加检查**。这条本项目还欠着：异步组外四条跨域路没有它
（数据包 §4）。欠着不等于已解决，报告里也不会有它的读数——这是"要按名字复查约束"（§6.3）的另一种形态。

### 4.6 一张"谁把检查加上、谁把检查摘掉"的表

| 约束 | 动的是哪一格 | 对检查面 | 本项目的凭据读数 |
| --- | --- | --- | --- |
| `set_clock_uncertainty` | 窗口两边（公式那一行） | 不变，数字更悲观 | 挂 0.800 带 ⇒ WHS −0.747 / 25,742 端点（数据包 §3.3） |
| `set_clock_groups` | 整段跨域路 | **摘掉** | Inter Clock 表只剩两行（实测 `:198-199`） |
| `set_input_delay` / `set_output_delay` | I/O 端点的要求时刻 | **加上** | 挂 ±0.500 窗 ⇒ WHS −2.885 / THS −14.344 / 5 端点（数据包 §3.3） |
| `set_false_path` | 整条路 | **摘掉** | `check_timing` 那 2 + 6 个端口（实测 `:101,108`） |
| `set_multicycle_path` | 两沿距离 | 检查面不变、窗口变宽 | 本项目用"真拆两拍"替代（`zoom_fit.v:40-43`） |
| `set_max_delay -datapath_only` | 数据段上限 | **加上**（跨域） | 未做，欠账（数据包 §4） |

**读任何时序数字之前先问这张表：这个数是几把尺子量出来的、检查面有没有变过。**

---

## 5. CDC：为什么 STA 管不了，`ASYNC_REG` 到底管什么

### 5.1 STA 的三个前提在跨域路上都不成立

STA 依赖：① 发射沿与捕获沿的距离是常数；② 数据只走一条已知的路；③ 采样的语义是"这一拍的值就是这一拍的
稳定值"。两只异步钟之间：①不成立——相位关系随时间漂移，工具只能挑最坏组合或干脆不查（§4.2）；③也不成立——
捕获沿可能正好撞上数据变化，触发器进入**亚稳态**：输出既不是 0 也不是 1，需要若干周期才塌回一边。这**不是
"延时不够"**：再宽的周期也买不到稳定，因为不稳定来自采样时刻与数据变化时刻重合，而重合概率由频率比决定、
与周期长短无关。于是 STA 只能管"同步器之后的路"，管不了"同步器本身的那一次采样"。本设计对此的处理是**结构**：
跨域只准过 `dc_fifo` 的格雷码指针和 `ddr_bank_commit` 的 3 级同步器，其余一律禁止组合跨域
（`src/rtl/eth/eth_udp_video_top.v:6` 的文件头规矩）。**格雷码的作用不是变快，是"一次最多变一位"**——即使
采到跳变沿，读回来的也只是相邻的旧值或新值，不会读出一个不存在的指针（`src/rtl/eth/dc_fifo.v:35-36`）。
`report_methodology` 里那两条 `TIMING-9 Unknown CDC Logic` / `TIMING-10 Missing property on synchronizer`
（实测 `:50-51`，各 1 条）就是这个话题的工单：前者说"工具看不懂这段跨域逻辑"，后者说"这段同步器**没打属性**"。

### 5.2 `ASYNC_REG` 是放置指令，不是让路径变快的指令

`(* ASYNC_REG = "TRUE" *)` 的作用：告诉实现器"这几颗寄存器要挨在一起放、不许复制、不许拆散"。
`src/rtl/eth/dc_fifo.v:23-26` 那段注释给了理由：不打属性工具可以挪位、复制，甚至把它们拆开，亚稳态传播窗口就没保证
——这正是 TIMING-10 冲着的。本工程写 `ASYNC_REG` 的位置（grep 实测）：`dc_fifo.v:27`（格雷码链 4 颗）、
`ddr_bank_commit.v:42`、`eth_udp_video_top.v:277`、`snap_cross.v:36-37`、`effect_ctrl.v:34-39`、
`rotate/angle_ctrl.v:24`、`pl_video_top.v:165, 212, 254, 267, 471`。**它不改变延时**：它改变的是"两级同步器之间的
物理距离"，那个距离决定亚稳态有多大概率来不及传播（MTBF），而 MTBF 不在 `report_timing` 的任何一列里。

### 5.3 那一次补 `ASYNC_REG`：为什么 WNS 变化不记成收益

数据包 §3.1 的事实：`dc_fifo` 格雷码同步链补 `ASYNC_REG` 后，网表里 `ASYNC_REG` 从 **0 颗变 56 颗**；
**同一次构建** WNS 从 **0.445 变 0.739**，且**最差路径换了族**（变成 `icmp_tx` 的校验和锥）。这笔 +0.294 ns
**不能记成收益**，三个理由：① 放置指令生效后**别的锥的布线全部重排**（同步器挨在一起 ⇒ 布线器重新分配绕线），
那 0.294 不是"格雷码链变快"，是"布局重排之后恰好轮到另一族最差"；② 分子换了族（§2.4 第 2 条），差值不是
同一件事的差值；③ 资源不是逐字中性时，"免费"这个词不该出现（数据包 §3.1：`ASYNC_REG` 是放置指令，所以这个
WNS 变化不记成收益，资源逐字中性时才算免费）。

**这是本篇最想教的一件事**：读 STA 的人最常见的错误，就是把"改完之后 WNS 变好了"当成因果。正确的记法是
四问：改了哪一类（结构 / 物理 / 约束 / 策略）、哪些格子跟着变了（级数、route 占比、族、端点数、资源）、
哪些**没量**。本仓库对"没有归属"的部分写法是"不念成收益"：行覆盖使能独热化那次 LUT −243，其中只有 −66 能归到
这一刀（按模块归属，OOC 单独综合给的就是 −66 那一小块），其余没有归属（数据包 §3.1）。至于 `ASYNC_REG` 该记成
什么：记成**正确性属性**——网表里 56 颗带属性的寄存器 ⇒ 同步链的物理约束成立；这条的验证手段不是
`report_timing`（slack 里读不出属性有没有生效），`dc_fifo.v:23-26` 那段注释自述了一把异步属性覆盖扫描的尺子，
本篇只按注释叙述，未把该件路径当作盘上凭据引用。

---

## 6. 为什么"改约束"经常不如"改结构"

### 6.1 症状 → 杠杆

| 报告里的症状 | 该动的杠杆 | 不该动的 |
| --- | --- | --- |
| `route` 占比高 + `Logic Levels` 低 | **结构**：把两端挨近 / 让端点落在同一块 BRAM | 拆算术（没算术可拆） |
| `Logic Levels` 高 + `logic` 占比高 | **结构**：插一级寄存器、拆锥、去除法器 | `set_multicycle_path`（只放宽检查） |
| `Clock Path Skew` 大 / DCD 与 SCD 差得多 | **结构**：把两只钟并进同一棵树 | 加不确定度带 |
| 检查面上有洞（`check_timing` 的 HIGH 项、空表） | **约束**：该补的窗要补 | 为数字好看补 `set_false_path` |
| 失败端点一大片 | **口径**：先确认尺子（带宽、组、窗）有没有变 | 逐条改最差那一路 |

### 6.2 本工程量过的几刀（全部有读数，含否决项）

1. **把 RGMII 采样钟并进同一棵 BUFG**（结构，采纳）。`rgmii_rx` 删掉 `BUFIO`、5 个 IDDR 改吃 BUFG、
   `IDELAY_VALUE` 15→26（数据包 §3.1；`src/rtl/eth/rgmii_rx.v:4-5` 给出原来两条树的 `SCD 3.171 / DCD 4.854`
   与偏斜 **+1.616 ns**，以及"WHS 每次重建在 ±1 ps 上掷硬币"这个机制）。读数：最差那族 hold 的偏斜
   **+1.616 ns → 同树内 0.013–0.349 ns**、`BUFIO` 用量 **1→0**（实测 `build/clock_util.rpt:45` 那行
   `| BUFIO | 0 | 16 |`），但 WHS 数字**没变好**（+0.051→+0.037，最差挪到 100 MHz 域）。**收益记的是结构性**：
   它消除的是"每次重建掷 ±1 ps 硬币"这个机制（数据包 §3.1）。连带账写在 `rgmii_rx.v:7-9`：改时钟源会把
   采样沿往后推 1.683 ns，数据侧必须补同样的量（15 + 11 = 26），后来的实测扫描把它再抬到 31（§4.3）。
2. **`zoom_fit` 的除法器与分两拍**（结构，采纳）。两条实测写在 `src/rtl/process/zoom/zoom_fit.v:26` 与
   `:34-38`：组合除法器在 100 MHz 域**把 WNS 打到 −5.014**；`angle → inv_fit` 一拍做完是 **15 级、含两个
   DSP48、slack 只剩 +1.843 ns**。修法是两处结构改动：把 `/W`、`/H` 折成"乘一个 elaboration 常数 + 定长移位"
   （`:29-30`，综合折成常量乘法、运行时没有除法器），再把分子与后段**分两拍**（`:39-43`）；代价写在注释里：
   拟合值晚两拍跟上新角度，而那两拍落在消隐里。拆拍之后工具真的按两拍布线，检查面没变、slack 是真的涨——
   这就是"改结构"与"改约束"的分别。
3. **OSD 读侧插一拍**（结构）：那条 23 级、+0.384 ns 的锥，修法是在读侧插一级寄存器，采纳条件要求别的域
   不许变差（数据包 §3.1）。
4. **强制复制驱动**（结构，量过并否决）：把一条 239 引脚的广播网强制复制（`phys_opt_design
   -force_replication_on_nets`），赢 1 格、跌 4 格含最紧两格，代价 +10 FF；机制确实动了（网表里出现
   `*_replica`），但名册差分判红 ⇒ 不采纳（数据包 §3.1）。两条配套工具事实：**这一版 Vivado 没有
   `set_max_fanout`，也没有 `report_design_analysis -fanout`** ⇒ 扇出只能用 `report_high_fanout_nets` 读；
   另一次针对 fo=316 广播使能的刀**没真降**（同一命令复读，数据包 §3.1）。仓库里还有一支更早、把结论写进
   RTL 注释的对照：给 `wr_full` 加 `max_fanout=12` 想让综合复制本地缓冲，WNS 从 −0.062 掉到 −0.192、失败端点
   28 → 34 ⇒ **已回滚**（`src/rtl/eth/dc_fifo.v:37-39`）——**"扇出主导"这个猜测被自己的数判掉的样本。**
5. **改约束那一刀**（约束，量过并退回候选件）：就是 §4.3 整条，最后靠两条实测直线证明"这本来就不是靠约束
   能关的"（数据包 §3.3）。
6. **换工具策略**（策略面，两档都不采纳）：`Performance_NetDelay_high` WNS +0.013（比基线低 0.54 ns，超出实测
   0.4 ns 摆幅）、`Performance_WLBlockPlacementFanoutOpt` 与基线**一格不差**；两份位流 md5 互不相同也不同正式件
   ⇒ "策略被应用了"有凭据；两档都不采纳 ⇒ **"靠工具再压时序"这一类问题到此关闭**（数据包 §3.4；件在
   `build/r95b_timing_summary.txt:7-9`）。BRAM 换 setup 那一刀同属此类：隔离构建里 +0.182 ns（期望 +0.516）、
   仍 4 级 ⇒ 判 **congestion 主导**，量过并否决，两刀回退（用 md5 等式证明回退干净，数据包 §3.4）。
7. **物理面也没做成一次对照**：`SLICE_X40Y20:SLICE_X66Y52` 那块 pblock 被工具拒绝（`Place 30-439`，进位链半内
   半外），落点下限实测 `PB_CONTAIN total=1716 inside=1461`；这条只能念"没做成一次对照"，不能当独立负结果
   （数据包 §3.2）。**每条否决都要写"量到什么、因此判它不行"——上面第 4/6/7 条就是这个格式。**

### 6.3 改名会静默缩小约束射程（本篇最要紧的一条习惯）

数据包 §3.3 最后一条：**加 MMCM / 重新源化时钟之后，`set_clock_uncertainty`、`clock_groups`、`input_delay`
可能不再命中任何时钟名而工具不报错 ⇒ 读任何 slack 之前先按名字复查约束还在不在。**

危险在于这三条约束都靠**名字**找对象。时钟被重新源化后，报告里出现的名字换了（例如从约束里写的名字变成
MMCM 输出自动生成的名字），于是三种失效都不报错，只有数字在动：`set_clock_uncertainty` 打空 ⇒ `Clock
Uncertainty` 行里的 `+ UU` 消失、全场 hold 数字集体变好，看起来像"时序被优化了"；`clock_groups` 打空 ⇒
跨域路从"摘掉检查"变回"按最坏周期检查"，反过来会凭空多出一堆违例；`input_delay` 打空 ⇒ 那批 I/O 端点从
"检查"退回"没检查"，`check_timing` 的 HIGH 计数变大（回到 §3.1 那 5 / 6 个端口那一格）。

**复查动作要按名字做**，本篇给出三个实测锚点：

1. **Clock Summary 那张表**（实测 `:162-171`）：约束里写的钟名必须原样出现在这里。当前这版列出 8 只
   `clk_fpga_0`、`eth_rxc`、`sys_clk`、`clkfbout`、`clkfbout_1`、`clkout0_1`、`clkout1_1`、`clkout2`，
   周期依次 10.000 / 8.000 / 20.000 / 20.000 / 20.000 / 20.000 / 4.000 / 5.000 ns。
2. **每个域最差 hold 段里那条 `Clock Uncertainty` 还在不在、值还是不是 0.800**（实测 `:466`）；消失 ⇒ 那条带打空了。
3. **`check_timing` 的 no_input_delay / no_output_delay 计数**（实测 `:66-67` 的 7 / 12）与 §4.3 那个
   "5 个收口端点"的账对不对得上；计数变大 ⇒ 有窗被摘掉了。

约束文件在 `src/constraints/` 下（本篇只核对文件名在盘上：`rk_zynq7020.xdc`、`clock_groups_impl.xdc`、
`r114_io_async.xdc`、`r114_io_varianta_rise_only.xdc`、`r114_io_variantb_phy_delay.xdc`、
`r115_io_window_candidate.xdc`、`r116_rgmii_input_window.xdc`、`r119_hdmi_source_window.xdc`、
`r119b_hdmi_tp1_pinclk.xdc`）。`rgmii_rx.v:10` 那句老注释"`src/constraints/` 里没有任何 `set_input_delay`"本身就是
这条纪律的活标本：同一件事在同一文件里被改过两次，文件头自己声明前提已变（`:12`）——**读到旧结论时先问"前提还在不在"。**

---

## 7. 自检问题（15 问）

每问都能在本篇前面找到答案，答不上就回读括号里的节号。

1. 报告头几行里，哪一行的值决定"route 延时是实测还是估计"？（§0，`:10` 的 `Design State`）
2. `Source` 与 `Destination` 各指路径的哪一端？端点必须是触发器的 `D` 脚吗？本设计有多少个端点？（§1.1）
3. `Data Path Delay` 括号里的 `logic` 与 `route` 分别由什么决定？1.850 ns 那条的 route 占几个百分点？（§1.2）
4. 为什么"1 级逻辑、93 % 走线"这条不该靠拆算术来救？该动哪一手？（§1.2、§6.1）
5. setup 与 hold 的 slack 哪个是 `required − arrival`、哪个反过来？各自在哪个工艺角查？（§1.3、§1.4）
6. 四个域的 hold `Requirement` 各是多少？由此推出"降频能不能救 hold"？（§1.5）
7. 本设计最小可控的时间颗粒是多少 ps？拿它读 `clkout0_1` 的 WHS 得出什么结论？（§1.5）
8. WPWS 检查的是什么？`clkout1_1` 的 WNS 格为什么空着——"空"能读成"余量为 0"或"这个域过了"吗？（§1.7）
9. WNS −0.2 ns/3,000 个失败端点，与 WNS −6 ns/1 个失败端点，改法有何不同？为什么端点数更能说明形状？（§1.8）
10. 把 `eth_rxc` 的 0.739 与 `clkout0_1` 的 3.630 换算成相对余量，各占周期百分之几？哪个更紧？（§2.2）
11. 为什么跨构建的"WNS 涨了 0.3 ns"不能记成收益？要满足哪些条件才算？（§2.4）
12. `:466` 那行末尾的 `+ UU` 是什么？为什么现在四个域的 WHS 不能直接比大小？（§2.5、§4.1）
13. 挂上 ±0.500 ns 输入窗后 WHS/THS 变成多少？5 个失败端点落在哪个引脚、`route 0.000 %` 说明什么？（§4.3）
14. `set_false_path`、`set_clock_groups`、`set_max_delay -datapath_only` 哪两条摘检查、哪一条加检查？报告里能看见
    "摘掉"证据的两个计数在哪一节？（§4.4、§4.6）
15. `ASYNC_REG` 改的是延时还是放置？那次网表 0→56 颗、WNS 0.445→0.739，为什么不记成收益？（§5.2、§5.3）

---

## 8. 本篇用过的凭据（每条都能点开）

| 凭据 | 用它证明什么 |
| --- | --- |
| `build/timing_summary.rpt`：`:3-10` banner、`:16-36` 设置与角、`:39-52` methodology 计数、`:58-140` check_timing（目录 `:62-73`、展开 `:99-110`）、`:144-154` 汇总、`:157-171` Clock Summary、`:174-188` Intra、`:191-199` Inter、`:202-209` Other Groups（空）、`:229-281` 一条 setup 全段、`:289-302 / :452-470 / :613-625 / :863-875` 四域 hold、`:365-382` `eth_rxc` setup、`:1144-1145` 与 `:1246-1262` 跨域段 | 本篇所有 slack、字段名、逐拍足迹、百分比、端点数、不确定度读数 |
| `build/utilization.rpt` `:35/:40/:106/:163/:212` | LUT 14,154（26.61 %）、寄存器 8,188（7.70 %）、BRAM 95.5/140（68.21 %）、MMCME2_ADV 2、DSP48E1 19 |
| `build/clock_util.rpt` `:43/:45/:48/:59-66` | BUFG 8/32、`BUFIO` 用量 0、MMCM 2、每只钟的树与负载数 |
| `build/gates.sh` `:34/:74-87/:197`；`build/r84_gates.txt:7` 与 `build/r118_gates_final.txt:10` | 门禁只读报告不重跑构建；WNS 那行按形状匹配；失败端点数进门禁；"WNS 在第几行"会随件漂 |
| `data/metrics.csv` `:5/:6/:7`；`report/technical-document.md` `:55/:58/:215/:270-271` | 全局 WNS 0.739、失败端点 0（分母 51,135）、WHS 0.052 与"5 个端点未检查"；五域表、汇总行行号、TMDS 窗口口径、WNS 绝对差不算收益 |
| `src/rtl/top/system_top.v:160-172`；`src/rtl/eth/rgmii_rx.v:4-11/:12-23/:67-80/:87-97` | 采样沿后移的量与 τ 扫描、"0~31 关不掉"、出货值 `.IDELAY_VALUE(31)`；两条钟树与 1.616 ns 偏斜、建窗后 −2.885 那笔账、IDELAYE2 与 `u_iddr_rx_ctl` 的连线 |
| `src/rtl/eth/dc_fifo.v:23-27/:35-36/:37-39` + `src/rtl/eth/eth_udp_video_top.v:6/:298`；`src/rtl/process/zoom/zoom_fit.v:26/:29-30/:34-43` | `ASYNC_REG` 四颗与理由、格雷码规矩、`max_fanout` 那一刀的负读数、跨域规矩与 `u_cdc` 例化；除法器 −5.014、常数乘、分两拍与"一帧才变一次"前提 |
| `build/r95b_timing_summary.txt:7-9`；`build/roster_r118_after_eth_rxc_setup.rpt:6`；`build/crit_paths.txt:6-10`；`build/timing_lane.sh:9-15` | 两档策略读数；`-nworst 1 -max_paths N` 参数原文；`rows_hit` 那一族的级数与 slack；快车道的分工 |
| `report/study/timing/90-numbers-index.md` §1/§2/§3.1/§3.2/§3.3/§3.4/§3.5/§4 | 五域表；构建与快车道成本；结构几刀；pblock；±0.500 窗、τ 扫描与 0.800 带；策略与 BRAM 两笔否决；相对余量纪律；仍欠的账 |

`src/rtl/process/zoom/` 里另三支（`zoom_ctrl.v`、`zoom_mapper.v`、`zoom_snap.v`）本篇未打开、不引其数。
**没写进本篇的数**（一律按"未实测/未读"处理）：`clkout1_1` 域内的任何 setup/hold 余量（报告里没有）、BUFIO 快角的
DCD、`eth_rxc` 前几档最差路径的逐档归因——读到别处出现这些数时，按 §6.3 的方式问它要凭据。
下一篇（本套三篇的第二篇）：[01-methods-and-priority.md](01-methods-and-priority.md)；第三篇实录：
`02-how-this-project-did-it.md`。

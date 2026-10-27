# 11 RGMII 收侧：从引脚到可提交的帧

这一章讲一条链：`eth_rxd[3:0]`/`eth_rx_ctl` 两个沿上的 4 位流，怎么变成 `frame_reasm` 的
`wr_en/wr_addr/wr_data` 与 `frame_done`。章里每个数都来自我打开过的文件，标 `文件:行`。
凡是我没量到、只能推断的，句子会写明"推断"或"未定"。

## 0 文件名对照（先钉死，免得照着找不到东西）

| 任务里点的名字 | 仓里真实的名字 | 头文件 |
| --- | --- | --- |
| `rgmii_to_gmii.v` | `rgmii_rx.v`（IDDR+IDelay 本体）与 `gmii_to_rgmii.v`（纯连线壳） | `src/rtl/eth/rgmii_rx.v:1`、`src/rtl/eth/gmii_to_rgmii.v:1` |
| `eth_mac_rx.v` | `gmii_rx_mac.v`（剥前导码、算 FCS、给 m_eof/m_good/m_bad） | `src/rtl/eth/gmii_rx_mac.v:2` |
| `crc32.v` | `crc32_d8.v`（一次一字节的反射 CRC32，收发共用） | `src/rtl/eth/crc32_d8.v:1` |

链路顺序写在顶层文件头：`gmii_to_rgmii → gmii_rx_mac(自算 FCS) → udp_rx_parser → frame_reasm →
dc_fifo(BRAM CDC) → axi_frame_saver64 → ddr_bank_commit`（`src/rtl/eth/eth_udp_video_top.v:3-4`）。
控制面（`arp`/`icmp`/`eth_ctrl`）在第 12 章，观测面（`link_monitor`）在本章末尾。

---

## 1 前置知识：读懂这一章需要哪些概念

### 1.1 源同步：`RXC` 不是"我们的时钟"，是 PHY 恢复出来的时钟

Gigabit 以太网的接收侧没有"发送方的字时钟"可用：PHY 从 Rx 差分对的比特流里用 CDR 恢复出时钟，
再把恢复出的 `RXC` 连同数据一起送给 FPGA。**因此这一族的所有时序关系只能以 `RXC` 为参考**，
FPGA 自己的任何时钟（`sys_clk`、MMCM 输出）都不能用来采这 5 根线。
本工程的 `create_clock` 就是打在引脚上的：`create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]`
（`src/constraints/rk_zynq7020.xdc:36`），引脚 `Y19`（`:20`），波形 `{0.000 4.000}`（周期 8 ns、占空比 50 %，
与 `build/timing_summary.rpt:165` 的 `eth_rxc {0.000 4.000} 8.000 125.000` 一致）。

"源同步"的实际含义：**时钟与数据同一条路径上的同一组不确定性**。片内的 `IDDR` 只关心
"`RXC` 到达 C 脚的时刻"与"数据到达 D 脚的时刻"之差；这两段各自要走多少，工具算得清清楚楚，
但也正是本工程所有麻烦的来源（§2）。

### 1.2 DDR 与位预算：每沿 4 bit、每字节 8 ns、每 4 ns 一个 UI

| 量 | 值 | 出处/算式 |
| --- | --- | --- |
| 时钟 | 125 MHz ⇒ 周期 8.000 ns | `rk_zynq7020.xdc:36` |
| 一个数据沿（UI） | 4.000 ns | 半周期；`build/evidence/r116/r116_io_setup.rpt:22` 的 `Requirement: 4.000ns` 就是它 |
| 每沿携带 | 4 bit | `input [3:0] rgmii_rxd`（`src/rtl/eth/rgmii_rx.v:30`） |
| 一个字节 | 2 沿 = 8.000 ns | `gmii_rxd[7:0]`（`:35`） |
| 线速 | 4 bit × 2 沿 × 125 MHz = 1 Gb/s | 上行三项相乘 |

位段规则（这是最容易搞反的一件事）：**`RXC` 上升沿那半字节是字节的低 4 位，下降沿是高 4 位**，
写在文件头第 2 行（`src/rtl/eth/rgmii_rx.v:2`）。硬件实现是纯位映射：`.Q1(gmii_rxd[i])` 与
`.Q2(gmii_rxd[4+i])`（`src/rtl/eth/rgmii_rx.v:133-134`）⇒ 等价于 `byte = {负沿nibble, 正沿nibble}`。
采错沿的失败形状不是"偶尔错一个 bit"，而是**整包字节错位**（`docs/walkthrough/glossary.md:530`
记的就是这条：错位 ⇒ 下游 FCS 全错、`bad` 计数上升）。

### 1.3 IDDR 的三种 `DDR_CLK_EDGE`，以及为什么本设计选 `SAME_EDGE_PIPELINED`

7 系列 ILOGIC 里的 DDR 输入寄存器有三种模式：`OPPOSITE_EDGE` / `SAME_EDGE` / `SAME_EDGE_PIPELINED`
（口径核对：`docs/walkthrough/glossary.md:533`，指 `ug471_7Series_SelectIO.pdf` 第 109 页）。
本工程 5 只 IDDR 全用 `SAME_EDGE_PIPELINED`（控制线那只 `src/rtl/eth/rgmii_rx.v:88`，
数据线那四只在 generate 循环里 `:128`）。

功能差别（这才是选它的理由）：
- `OPPOSITE_EDGE`：`Q1` 在上升沿出、`Q2` 在下降沿出。两个输出不同拍，**喂给一个上升沿驱动的
  fabric 触发器根本对不齐**——那需要 fabric 也能用双沿，或者再来一级跨沿对齐。
- `SAME_EDGE`：两个输出都在上升沿出，但同一拍的 `Q1`/`Q2` 来自**相邻的两个不同字节**（一个来自
  本沿、一个来自上一个下降沿），要拼成同一个字节得自己再排一次序。
- `SAME_EDGE_PIPELINED`：`Q1` 额外打一拍，使得同一拍的 `Q1`/`Q2` 正好是**同一个字节的低/高 nibble**。
  代价：整条收侧数据路径多 **1 个位时钟（8 ns）**的固定延迟。

固定延迟不参与时序判据（GMII 的 DV 走同一只 IDDR 的同一份流水，见 `:92-100` 与 `:48` 的 `gmii_rx_dv`），
所以下游看到的是一条干净的、字节对齐的 GMII 流——只是整体晚了一拍。

### 1.4 IDELAYE2 / IDELAYCTRL：抽头是"档"，不是纳秒

三段硬件（都在 `src/rtl/eth/rgmii_rx.v`）：
1. `IDELAYCTRL`：需要 200 MHz 参考钟才能工作，本设计 `.REFCLK(idelay_clk)`、`.RST(1'b0)`
   （`:59-63`）。参考钟来自 MMCM 的 CLKOUT2：`CLKOUT2_DIVIDE(5)` ⇒ VCO 1000 MHz / 5 = 200 MHz
   （`src/rtl/clocks/clk_gen.v:19` 与 `:27`），顶层把它接到 `idelay_clk`（`src/rtl/top/system_top.v:178`）。
2. `IDELAYE2`：`IDELAY_TYPE("FIXED")`、`.IDELAY_VALUE(IDELAY_VALUE)`、
   `.REFCLK_FREQUENCY(200.0)`（`src/rtl/eth/rgmii_rx.v:67-70`；数据线那份同样三条 `:108-111`）。
   **FIXED 意味着运行时改不了**——想量眼心只能重综合，或者按 `收口输入窗模型`
   那条候选换成 `VAR_LOAD`。
3. `(* IODELAY_GROUP = "rgmii_rx_delay" *)`：把这 5 只 IDELAY 与那只 IDELAYCTRL 钉成一组
   （`:58`、`:66`、`:105`、`:107`）。分组是工具要求（同一组的 IDELAY 必须由同一只 IDELAYCTRL 供参考），
   不是风格。

抽头的单位：手册口径 **`1 / (32 × f_REFCLK)`** ⇒ 200 MHz 下 `1/(32×200e6) = 156 ps/档`，
这条算术就写在文件头（`src/rtl/eth/rgmii_rx.v:8`）。
仓里还有另外两本账：`gmii_to_rgmii.v:23` 的参数注释写的是"n 表示延时 `n*78ps`"，
而实测斜率是 ≈63 ps/档（`:19`，`build/evidence/r115_window/probe3_console.txt` 的逐档读数）。
文件头自己承认三个数互不一致并把这条标成未定（`src/rtl/eth/rgmii_rx.v:21-22`）。
**结论只有一条：档数不能当纳秒换算用，要移动采样点就直接扫档看 slack。**

### 1.5 片外窗（`set_input_delay`）与片内钟树延迟（SCD/DCD）是两件事

- `set_input_delay` 描述的是**引脚上**数据相对参考钟沿的到达区间（片外那一段：走线 + PHY 内部延迟）。
- 报告的 `SCD`/`DCD` 描述的是**沿本身**从引脚走到源/目的触发器 C 脚要花多久。
- 判据是两者相加：`arrival = 发射沿 + 输入窗 + 数据路径(IBUF/IDELAY)`，
  `required = 捕获沿 + DCD − SCD + 不确定度 + 目的单元的建立/保持时间`。

一个反直觉但极重要的事实：**没有 `set_input_delay` 不等于"这一段被满足了"，而是"这一段根本没被检查"**。
这条债务的原话写在 `时序债务账` §2：未覆盖的 5 个输入是 `eth_rx_ctl`、`eth_rxd[0..3]`，
"现行名册里 eth_rxc 的 WHS 0.052 是**假设数据恰好在时钟沿到达**量出来的片内数"。

### 1.6 FCS-32 的数学，以及"残值"这个判据为什么成立

标准以太网 CRC-32：反射实现、生成多项式按反射写成 `0xEDB88320`、初值 `0xFFFFFFFF`、
末异或 `0xFFFFFFFF`、覆盖 `DA[0]` 到最后的载荷字节（不含前导码/SFD）。

关键性质：**把一段合法 CRC 串接在消息后面、再把"消息+FCS"整段重新过一遍同一个 CRC 机器，
得到的值与消息内容无关，是一个常数**（因为 FCS 的定义就是让最终 LFSR 状态为那个常数）。
标准实现下"消息 + FCS 再过一遍"的残值：**不末异或时是 `0xDEBB20E3`，末异或版与它互为取反 = `0x2144DF1C`**
（两个数都写在台架头注释里：`sim/tb_v795_rx_fcs.v:22`，另一次复述在 `:129`）。

本设计的收侧不做末异或，所以常数不同。RTL 里钉的是
`localparam [31:0] FCS_RESIDUE = 32'hC7_04_DD_7B;`（`src/rtl/eth/gmii_rx_mac.v:23`），
注释明说这是**实测值不是推算值**（`:21-22`）。我用一份独立实现（JS 的 `0xEDB88320` 表算法 +
逐位复抄 `src/rtl/eth/crc32_d8.v:23-81` 的 32 个异或式）复算过两帧：把
`DA..载荷` 与正确 FCS 一起喂进这个核，末态两帧都是 `c704dd7b` ⇒ 这个常数是可复现的，
不是自洽假设。

顺带钉一条关系（也是复算出来的）：`crc32_d8` 的寄存器值 = **标准反射 CRC 的 32 位逐位镜像**
（`rtl == rev32(std_raw)` 在两帧上成立）。这条决定了发送侧的字节顺序怎么拼（第 12 章 §2.6）。

### 1.7 GMII 的 DV/ER 与 RGMII 的 5 根线

GMII 给 `RX_DV`（有效）和 `RX_ER`（错误）两条边带；RGMII 只把 `RX_DV` 复用到 `RX_CTL` 上、
**没有错误通道**。这条缺失是本设计收侧一切判断的根因：
`rgmii_rx.v:6` 的原话是"RX_CTL 仅当 `gmii_rx_dv` 用：RGMII 没有 GMII 的 RX_ER 通道，
本模块交不出错误标志"。顶层因此把 ER 直接钉死：`.gmii_rx_er(1'b0)`（`eth_udp_video_top.v:189`）。

后果写在 `gmii_rx_mac.v:4-7`：原来的"没 ER 就算好"恒真 ⇒ 顶层 `p_good` 被硬接 1 ⇒
遥测里的"坏包"是构造性为 0 的死数字。**唯一的错误源必须自己造**，造法就是 §1.6 那个残值。

### 1.8 CDC 前置：格雷码与 `ASYNC_REG`

跨异步钟的 FIFO 只传**格雷码**指针，因为相邻计数值之间格雷码最多 1 位翻转，
"读到半个新值"的坏状态不可能存在（`src/rtl/eth/dc_fifo.v:35-36` 的注释是这么写的，实现见 `:82-95`）。
同步链那两级（外加本域的第一级）必须打 `(* ASYNC_REG = "TRUE" *)`，否则工具可以挪位、复制、
把它们拆得七零八落，亚稳态传播窗口就没有保证（`src/rtl/eth/dc_fifo.v:23-27`，
判据口径来自 UG949 的 CDC 一节与 `report_methodology` 的 TIMING-10）。

---

## 2 原理拆解：把这条链的时序算出来

### 2.1 当前出货的捕获结构

```
                       ┌─ IDELAYE2(FIXED, τ=31) ─┐
eth_rxd[i] ──IBUF──►───┤  IDATAIN ─► DATAOUT     ├──► IDDR(SAME_EDGE_PIPELINED).D ──► gmii_rxd[i]/[4+i]
eth_rx_ctl ──IBUF──►───┤  同一 IODELAY_GROUP      ├──► IDDR(那只) ──────────────────► gmii_rx_dv = Q1 & Q2
                       └──────────────────────────┘
eth_rxc ──IBUF──► BUFG（rgmii_rx.v:51）──┬──► 5 只 IDDR 的 C
                                         └──► 下游全部 fabric（gmii_rx_mac/parser/reasm/arp/icmp/...）
```

关键点：**IDDR 与 fabric 吃同一只 BUFG**（`src/rtl/eth/rgmii_rx.v:3`，实例见 `:51-54` 与 `:95`、`:135`）。
这条是 #57/#80 那一轮改出来的，代价写在 §4.1。

### 2.2 把那条 −0.870 ns 的 hold 拆到每一项

下面这组数全部抄自带窗实现后的 I/O 报告 `build/evidence/r116/r116_io_hold.rpt`
（`VP_R116_IO_WINDOW=1` 时才会加载窗，见 `build/tcl/build_system_axigpio.tcl:57-60`；默认构建**不加**，
`:62-63` 打的是 `VP_R116_IO_WINDOW off`）。

| 项 | 值 | 出处 |
| --- | --- | --- |
| Slack | **−0.870 ns**（VIOLATED） | `r116_io_hold.rpt:15` |
| 源/宿 | `eth_rx_ctl` → `u_eth/u_rgmii/u_rgmii_rx/u_iddr_rx_ctl/D` | `r116_io_hold.rpt:16-18` |
| Path Type | `Hold (Min at Slow Process Corner)` | `r116_io_hold.rpt:21` |
| Requirement | `0.000ns (eth_rxc rise@0.000ns - eth_rxc rise@0.000ns)` ⇒ **同沿检查** | `r116_io_hold.rpt:22` |
| Input Delay | 1.200 ns（窗下界，`r116_rgmii_input_window.xdc:32` 那条命令给的） | `r116_io_hold.rpt:25` |
| IBUF | 1.321 ns（累计到 2.521；引脚 `V19` = `eth_rx_ctl`，`rk_zynq7020.xdc:21`） | `r116_io_hold.rpt:43` |
| IDELAYE2 @τ=31 | 2.607 ns（累计到 5.128） | `r116_io_hold.rpt:45-46` |
| Data Path Delay | 3.928 ns，**route 0.000 ns（0 %）**，`Logic Levels: 2`（IBUF + IDELAYE2） | `r116_io_hold.rpt:23-24` |
| DCD | 5.008 ns；SCD 0.000 ns | `r116_io_hold.rpt:26-28` |
| Clock Uncertainty | 0.835 ns，其中 `User Uncertainty` = 0.800 ns | `r116_io_hold.rpt:30-35`，那 0.800 来自 `rk_zynq7020.xdc:50` |
| IDDR 自身 hold | 0.155 ns（那份 −2.522 的拆解里点名的就是它） | `收口输入窗模型` |

算式对得上（这是我自己按分量重算的，不是抄结论）：

```
arrival  = 1.200(窗) + 1.321(IBUF) + 2.607(IDELAY@31)          = 5.128 ns
required = 5.008(DCD，捕获沿走到 IDDR 的 C 脚) + 0.835(不确定度) + 0.155(IDDR hold) = 5.998 ns
slack    = 5.128 − 5.998                                        = −0.870 ns   ✓ 与报告逐位一致
```

把 0.870 的**构成**摊开看，结论和"设计错了"完全不同：`0.835 + 0.155 = 0.990` 是保护带，
数据真正"晚于沿"的只有 **5.128 − 5.008 = 0.120 ns**。

`DCD = 5.008` 也不是黑箱，同一族报告里它的构成是
`IBUF 1.430 + 走线 1.873 + BUFG 0.085 + 走线 1.620 = 5.008`（`收口输入窗模型`），
那只 BUFG 就是 `rgmii_rx.v:51` 的 `BUFG_inst`。

### 2.3 眼为什么还在：两套口径读同一个符号关系

数据在 IDDR 的 D 脚上什么时候是**稳定**的？τ=31 时它从 5.128 ns 开始有效，
下一个符号在 4 ns 之后才改变 ⇒ 稳定窗是 **[5.128, 9.128]**。捕获沿在 5.008 ns 到达。
把窗挪到 τ=0（数据只走 IBUF + 本底 0.655 ns）时，那份拆解给的是
**[3.476, 7.476]** 与"沿在 5.008 ⇒ 距前一次跳变 1.53 ns、距后一次跳变 2.47 ns，采样点在眼内"
（`收口输入窗模型`）。

⇒ **STA 报负 + 板上不丢包，这两件事同时是真的**：STA 的 hold 拿"同一个 pad 沿"当发射沿，
而这套结构是**故意把捕获沿推到数据眼中间**的（那段话的原文就是 `rgmii_window_model.md:43-44`）。
板侧证据是真实流量下的读数：推流 3001 帧 / 120.05 s = 25.00 fps、663221 包，推流之中
`drop_words=0`、`丢过字=0`、`stall_ms=0`、`CDC灌满过=0`（`board/acceptance.md:36`）。

### 2.4 窗的数从哪儿来，为什么是正的 1.200 / 2.800

窗不是拍的，是查来的（三条本地可核的出处，全部抄在 `src/constraints/r116_rgmii_input_window.xdc:8-20`）：

1. **原理图**：R57 4.7K 把 `PHY1_RXD0` 上拉到 `PHY1_IODVDD`、R59 同理 RXD1 ⇒ strap 决定
   `RXDLY` 被打开（`:9-10`）。
2. **规格书 Table 10/11 与 Table 6**：`RXD0=RXDLY`、`RXD1=TXDLY`；
   "1: Add 2ns delay to RXC for RXD latching" ⇒ **2 ns 加在 RXC 上，不是加在数据上**（`:11-13`）。
3. **Table 60 的发射端两行**（`TsetupT`/`TholdT`，min 1.2 typ 2）⇒ 两者相加 = 半周期 4 ns ⇒
   数据沿相对它自己的捕获沿落在 **[1.2, 2.8] ns 之前**（`:14-17`）。

写成正的 1.200/2.800 的理由在 `:22-27`：工具对 IDDR 的 D 脚做的是"相邻两沿、间隔 4.000 ns"的检查，
offset 要从**发射沿**量起。四条形同镜像的拼法被 `probe2_console.txt` 的 W1..W4 量出来过（该件不在盘上，
这条只作为文档留下的记录引用，不当我的实测）。
落地的 4 条命令是 `:32-35`，两两成对：不带 `-clock_fall` 的那对写上升沿发射，
带 `-clock_fall -add_delay` 的那对写下降沿发射——**DDR 的两沿必须都声明**，否则只有一半被检查（`:29`）。
两条本机限制也写在同一处：`set_input_delay` 在本机**没有** `-setup/-hold`、也没有 `-clock_edges`，
而且 `-min` 与 `-max` **必须各写一条命令**，合在一条会被解析成 positional 过多（`:30-31`，
那条坑记在 `开发台账` 的 #308）。

曾经用错过的两行也有账：±0.500 是同一张表里 `TskewT`（发射端**没有**内部延时的输出偏差）那一行，
不是收口该用的窗（错行那条写在 `src/constraints/r115_io_window_candidate.xdc:17-18`；
错行事件记 `开发台账` 的 #304 与 `:12671` 的 #309）。

### 2.5 τ 扫描：为什么是 31，不是"算出来的 26"

同一份已布线 DCP 上用 `set_property IDELAY_VALUE`（在 DCP 上有效）逐档扫 0…31，
两份读数都在 `build/evidence/r115_window/probe3_console.txt`：

| τ | HOLD slack | HOLD 数据路径 | SETUP slack | SETUP 数据路径 |
| --- | --- | --- | --- | --- |
| 0 | −2.822 ns（`:107`） | 1.976 ns | +2.005 ns（`:111`，MET） | 0.754 ns |
| 26 | −1.185 ns（`:170`） | 3.613 ns | −0.386 ns（`:174`） | 3.146 ns |
| 31 | **−0.870 ns**（`:188`） | 3.928 ns | **−0.846 ns**（`:192`） | 3.606 ns |

两条曲线的斜率：`(3.928−1.976)/31 = 63.0 ps/档`（hold 侧）、
`(3.606−0.754)/31 = 92.0 ps/档`（setup 侧）。交点由 `−2.822+0.063τ = 2.005−0.092τ` 解出
**τ = 31.1** ⇒ `min(hold, setup)` 的最大点在合法上限 τ=31，比 τ=26 抬
`−0.870 − (−1.185) = +0.315 ns`（`那一轮的逐轮页` 记的是同一条，读数一致）。
`src/rtl/top/system_top.v:160-172` 把这套理由原样写在传参处，并且明确说
"改成 31 的理由不是那段算术，而是工具在真窗下的实测曲线"。

⚠ 这一族**在 0…31 全档内都关不掉**：hold 查慢角（DCD 5.008）、setup 查快角（DCD 1.597），
钟网络的角间差 **3.411 ns** 远大于数据路径的 **0.467 ns** ⇒ 同时满足要
`D_slow/D_fast ≥ 1.45`（去带）或 `≥ 1.73`（保留 0.8 ns 带），而 IDELAY 主导的路径实测只有 1.15
（`收口输入窗模型`、`round_r116.md:36`）。
这是**极限判据**：不是"还没找到那个点"，是"该结构在那个点上不存在"。

### 2.6 FCS 判据的信息量在哪

收侧只做一件事：整帧过 CRC 核，末态等于常数就算好。相比"发送端算法 + 比较"的写法，
它省掉了"把收到的 FCS 与自算 CRC 拼起来比较"的那一整段对齐逻辑；代价是**判据的成立依赖核的约定**，
只用发送侧那同一个 `crc32_d8` 自证就是同义反复（**两边一起错也照样过**），
所以造帧必须用另一套实现（`sim/tb_v795_rx_fcs.v:20`）。

### 2.7 `gmii_rx_dv` 为什么是两只 IDDR 输出的"与"

RGMII 上 `RX_CTL` 在两个沿上都驱动（帧内两个沿都是 1、帧间两个沿都是 0）。
本设计把它两只 IDDR 输出相与：`assign gmii_rx_dv = gmii_rxdv_t[0] & gmii_rxdv_t[1];`
（`src/rtl/eth/rgmii_rx.v:48`，两只输出的定义在 `:93-94`）。
含义是"这个字节的**两个**半沿都说 DV=1 才算有效" ⇒ 单沿毛刺不会伪造出一个有效字节。
代价：DV 与数据同受 §1.3 那 1 拍流水延迟，二者仍然对齐，所以不引入新的时序关系。

---

## 3 代码逐段分析

### 3.1 `src/rtl/eth/rgmii_rx.v`

端口（`:24-36`）：`idelay_clk` 只给 IDELAYCTRL；RGMII 侧是 `rgmii_rxc`/`rgmii_rx_ctl`/`rgmii_rxd`
（`:28-30`）；GMII 侧输出 `gmii_rx_clk`/`gmii_rx_dv`/`gmii_rxd`（`:33-35`）。
参数只有一个：`parameter IDELAY_VALUE = 0`（`:39`）——注意**默认是 0**，真值由顶层传下来
（`:9` 那句"拍数只有一个出处"说的就是这个：唯一传参点在 `src/rtl/top/system_top.v:172` 的
`.IDELAY_VALUE(31)`；中间层 `gmii_to_rgmii.v:23` 与 `eth_udp_video_top.v:14` 都只做透传/默认）。

时钟与两条 assign（`:47-48`）：`gmii_rx_clk = rgmii_rxc_bufg` ⇒ **GMII 侧的 125 MHz 就是恢复钟本身**，
没有任何倍频/相移/缓冲复制。这一行决定了第 12 章的主线：发侧协议栈用的也是它。

`BUFG`（`:51-54`）：单只、输出直接给 IDDR 的 C（`:95`、`:135`）并给下游 fabric。
关于这只钟的负载，盘上有**两个读数、口径不同、不许混用**：`build/clock_util.rpt:174` 按负载类型
拆开写 `Slice Loads = 2544`、`IO Loads = 1`、`Clocking Loads = 0`（合计 2545，网名
`u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`）；而实现后时序报告里那条最差路的时钟网写的是
`net (fo=2546, routed) … u_eth/u_icmp/u_icmp_tx/gmii_rx_clk`（`build/timing_summary.rpt:393`，
上一行 `:392` 就是 `u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O`）⇒ **发侧协议栈确实挂在收侧这只 BUFG 上**。
**两处差 1 个负载，我没有把这 1 个对上去（未定）**；`域划分候选评估`
用的口径是 2544。

IDELAYCTRL（`:58-63`）：`RDY` 悬空、`RST` 绑 0。**没有用 RDY 做门控**，
所以上电早期（参考钟还没稳定）这几条延迟线的值不保证——本设计的兜底是 ETH 复位：
`eth_rst_n = phy_rst_cnt[23]`（`src/rtl/top/system_top.v:110-112`，50 MHz 下第 2^23 = 8.39 M 拍，
≈168 ms 才放开），再与 MMCM 的 `locked` 相与（`:175` `.rst_n(eth_rst_n & mmcm_locked)`）。

IDDELAY+IDDR（控制线）：`:66-84` 是那只 FIXED 延迟线（`.IDATAIN(rgmii_rx_ctl)` 在 `:79`），
`:86-100` 是 IDDR（`.D` 接 `rgmii_rx_ctl_delay`，`:97`；`SRTYPE("SYNC")`，`:91`；
`CE(1'b1)`、`R(1'b0)`、`S(1'b0)` 全绑死 ⇒ 不可屏蔽、不可同步复位，这是 ILOGIC 的标准用法）。

数据线：generate 循环 `for (i = 0; i < 4; i = i + 1)`（`:105`），每圈一只延迟线（`:108-125`）
+ 一只 IDDR（`:127-140`），位映射在 `:133-134`。整个文件除了 §2.1 那张图**没有任何组合逻辑**——
IDDR 之后到 `gmii_rxd` 是纯连线（`:3` 之后那句"IDDR 之后到 fabric 之间没有组合锥"说的就是这个形状）。

### 3.2 `gmii_to_rgmii.v`：壳，但有一行是全设计的枢纽

`:25` 的 `assign gmii_tx_clk = gmii_rx_clk;` 是"发侧协议栈在 RXC 域"这件事的**唯一物理来源**，
注释在 `:1-3`：RGMII 只有 RXC/TXC 两根钟，这里 TX 沿用收侧恢复出的那一路 ⇒
**整个 ETH 逻辑实际是单时钟域**。文件头还留了一处双句号的手误（`:3` 末），不影响任何东西，
写在这里是为了说明"这一行是刻意的设计决定，不是漏了实现"。

### 3.3 `gmii_rx_mac.v`：三态机 + 自算 FCS

状态：`S_WAIT`(0)/`S_PRE`(1)/`S_DATA`(2)（`:25-27`），寄存器只有 4 个：
`state`、`cnt`（16 位）、`saw_sfd`、`er_seen`（`:29-32`）。

逐态：
- `S_WAIT`（`:89-92`）：只等 `8'h55`，命中就进 `S_PRE` 并把 `cnt` 置 1。
  **注意它不要求前导码是 7 个**——任何 0x55 都能开局。
- `S_PRE`（`:94-105`）：等 SFD `8'hD5`；其间连续 0x55 只是把 `cnt` 往上加；
  出现别的字节就回 `S_WAIT` 并清 `cnt`。收到 D5 ⇒ 进 `S_DATA`、`cnt` 归 0、`saw_sfd` 置 1。
  这一拍同时是 CRC 核的清零拍（`:42`，见下）。
- `S_DATA`（`:106-112`）：逐字节把 `gmii_rxd` 打成 `m_data`+`m_valid`；`cnt==0` 那一拍发 `m_sof`；
  `gmii_rx_er` 若为 1 就锁 `er_seen`（本设计恒 0，见 §1.7）。

帧尾（`:69-85`）：`gmii_rx_dv` 掉下来且当前在 `S_DATA` ⇒ `m_eof <= 1'b1`，
并且**同拍**给 `m_good`/`m_bad` 之一。约定写在 `:71-74`："`m_eof` 与 `m_good`/`m_bad` 同拍，
表示'上一个 `m_valid` 的字节就是帧的最后一个字节'"。
这条约定不是装饰——V7.9.5 之前 `m_eof` 声明了、复位清了、却没有任何一处写 1
（`:73-74` 自陈），而 `sim/tb_v795_rx_chain.v` 的 C1 就是抓这一件事的（`:74` 明写）。

好帧的四条并列条件（`:76`）：`!er_seen && !gmii_rx_er && (cnt >= 16'd64) && fcs_ok`。
其中 `fcs_ok = (crc_q == FCS_RESIDUE)`（`:48`）。**长度 ≥64 与残值是两条独立的判据**：
短帧即使 CRC 恰好对（不可能）也不给 good；残值不对即使够长也是 bad。

CRC 例化（`:37-47`）两个时机值得逐字看：
```verilog
wire in_data = (state == S_DATA) && gmii_rx_dv;      // :35
.crc_en  (in_data),                                  // :41  含 FCS 那 4 个字节也累加
.crc_clr ((state == S_PRE) && gmii_rx_dv && (gmii_rxd == 8'hD5)),   // :42
```
清零发生在 **SFD 那一拍**、早于第一个数据字节。原因写在 `:43-44`：`crc32_d8` 里
`crc_clr` 的优先级高于 `crc_en`（`src/rtl/eth/crc32_d8.v:85-87`：
`if (crc_clr) ... else if (crc_en) ...`），若在第一个数据字节当拍清，
**第 0 字节会被吞掉**。这是一个"优先级顺序决定语义"的真实案例。

复位分支（`:51-61`）把 `m_*` 全部清 0，其中四个脉冲位与 `:63-67` 的每拍默认清零配对 ⇒
`m_valid`/`m_eof`/`m_good`/`m_bad` 都是**单拍脉冲**，下游必须用脉冲语义去数（不能当电平与）。

### 3.4 `crc32_d8.v`：这个核的约定必须逐条对齐

`:18` 先做**位反转**：`data_t = {data[0], ..., data[7]}`。这不是可选风格，
反射 CRC 的 LFSR 形式要求先送 LSB；`:20-21` 写的多项式
`x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x^1 + 1`
正是 `0x04C11DB7` 的正向表述，配合位反转等价于反射式 `0xEDB88320`。
`:23-81` 是 32 个两层异或式（综合成 LUT 树，深度约 2 级；收侧那条 8 ns 的预算里它不是瓶颈）。
`:83-89` 的优先顺序是 `复位 > crc_clr > crc_en > 保持`，`crc_clr` 与复位都给
`32'hff_ff_ff_ff`——**没有末异或**，这就是 §1.6 那个残值与标准值不同的原因。

文件头 `:1-4` 把两条使用口径写清了：`crc_next` 是"下一拍的值"（只有发送侧用它拼 FCS），
CRC 覆盖范围由例化者决定（收侧喂整帧，发侧喂"线上正在出的字节"）。

### 3.5 `udp_rx_parser.v`：按字节索引的过滤机

它不做流水线"字对齐"的字段抽取，而是维护一个帧内字节索引 `bcnt`（`:30`，
文件头 `:2` 的理由是 "Byte-index state machine (easier to verify)"）。
帧内偏移约定在 `:25-27`：0-13 是以太网头，14 起是 IPv4。

采样时刻表（`:117-125`）——这张表是全模块的语义核心：

| `bcnt` | 采到的字段 | 存到 |
| --- | --- | --- |
| 12 / 13 | EtherType 高/低 | `proto_chk[15:8]` / `[7:0]` |
| 14 | 版本 + IHL | `b14`、`ihl <= s_data[3:0]` |
| 20 / 21 | 标志 + 片偏移 | `b20`、`b21` |
| 23 | 协议号 | `b23` |

判决在 `bcnt == 14 + ihl*4` 那一拍（`:137-148`）：同时把 `udp_off <= bcnt`、
`pay_start <= bcnt + 16'd8` 一起寄存（`:138-139`；`:33` 的注释解释这是"把加器挪出 `p_good` 的锥"），
然后要求 `proto_chk == 16'h0800` 且 `b14[7:4] == 4'h4` 且 `b23 == 8'd17` 且
`{b20, b21} == 16'h0000`（不分片）才 `accept <= 1'b1`，否则 `stat_drop_filt` 脉冲。

`:133-136` 记录的是一个真实修过的坑：`ihl` 在 `bcnt==14` 这一拍才**写进**寄存器，
同拍读到的还是旧值 0 ⇒ 条件在 `bcnt==14` 也成立过，于是**每帧提前判一次**、
而那时 `b23` 还没采到 ⇒ 每帧误发一次 `stat_drop_filt`。修法是把 `ihl != 4'd0` 加进条件
（`:137` 的第一个合取项）。载荷随后在真正的 `bcnt==34` 仍被正确接受 ⇒ 只污染统计、不影响画面——
这类"统计计数器说谎"的缺陷，判据是 `tb_v795_rx_chain` 的 C1"不误报丢弃"。

端口过滤在 `bcnt == udp_off+3`：把 `{dport[15:8], s_data}` 与参数 `UDP_PORT` 比
（`:151-157`，高字节在 `+2` 存 `:158`）。长度字段在 `+4/+5`（`:159-160`），
尾界 `pay_end <= udp_off + {udp_len[15:8], s_data} - 16'd1` 在 `+5` 当拍算完（`:162`）。

载荷窗口 `:172-186`：`accept && bcnt >= pay_start && bcnt <= pay_end` 才吐字节。
`:169-171` 的注释钉的是厂商风格的一个致命点：**原来 `bcnt >= udp_off+8` 一路发到帧尾，
会把 4 个 FCS 字节也当载荷吐出去**（32 字节载荷吐出 36），接上 `frame_reasm` 就是每包确定性错位 4 字节。

包尾不发 `p_eof`，只记账：`eof_pend <= 1'b1`、`pay_len_q <= pay_cnt + 16'd1`（`:182-185`）。
理由写在 `:179-181`：FCS 的判定要等帧结束那一拍（`m_good`/`m_bad` 与 `m_eof` 同拍）才知道，
**早发就得猜，猜错就是"把坏包当好包提交"**。

收尾 `:196-213` 认两种 `s_eof` 时序（`:192-195` 的注释是必要的，否则换个例化方式就少一个字节）：
① 厂商风格 eof 与最后一个字节同拍（`tb_udp_parser` 就这么驱）；② 本仓 `gmii_rx_mac` 的
eof 与 good/bad 同拍、那一拍 `m_valid=0`。于是判定式是 `if (eof_pend || last_pay_now)`（`:197`），
`last_pay_now` 定义在 `:50`。还有一条兜底：帧到尾但 `udp_len` 声明的字节没发完 ⇒
畸形包，**闭合但判坏**（`:202-207`：`p_good <= 1'b0`）。

坏帧路径 `:92-106` 值得单独读：`s_bad` 来的时候也要把包**闭合**（`p_eof`、`p_good=0`），
条件是 `eof_pend || in_pay`（`:98`）。`:94-97` 说得很直白：下游的 `pkt_active` 一直挂着的话，
**下一包的字节会接到这一包后面——那比丢一帧更坏**。

两处死码顺手记下：`localparam integer ETH_HDR = 14`（`:28`）与
`wire [3:0] ihl_nib = s_data`（`:41`）在文件里没有第二次出现（全文件 grep 只命中声明行）。
不影响行为，综合会掉，但别照着它们推理布局。

### 3.6 `frame_reasm.v`：什么叫"这一帧可以提交"

状态只有 5 个：`S_OFF0..S_OFF3` 与 `S_DATA`（`:37`）。
上游接口是 `p_data/p_valid/p_sof/p_eof/p_good`（`:15-19`），输出是 16 位写口 + 一堆统计（`:20-35`）。

**包格式**：每个 UDP 包的前 4 个字节是**小端**的帧内字节偏移，之后才是像素。
装配手法在 `:105`：`wire [31:0] hdr = {p_data, off[23:0]};`——第 4 字节到时，
`off[23:0]` 已经装着低 3 字节，拼起来正好是 `{b3,b2,b1,b0}`。
写入路径逐拍：`:123` 装 `off[7:0]`、`:127` 装 `off[15:8]`、`:128` 装 `off[23:16]`、
`:130` 装 `off[31:24]` 并同拍把 `hdr` 记成 `pkt_start`、把 `pend` 预置成
`(hdr >= FRAME_BYTES) ? SAT : hdr[CW-1:0]`（`:131-132`）。

**帧边界是怎么知道的**：`if (hdr < 32'd4)`（`:133`）⇒ 偏移落在前 4 字节的包被当成"新帧的开头包"，
于是清 `cov`、清 5 个行覆盖 bank、清 `rows_hit`、清 `bad_frame`（`:134-138`）。
这不是协议层的信息，是**发包方的约定**：发送脚本按 `off = 0; off += MTU` 逐包写小端偏移
（`src/host/video_sender.mjs:195` 与 `:198` 的 `writeUInt32LE(off, 0)`），`MTU` 缺省 1392（`:29`），
`FRAME_BYTES = 512*300*2 = 307200`（`:26`）⇒ **每帧只有第一包的偏移是 0**，其余包的都是 1392 的整数倍，
所以 `hdr < 32'd4` 恰好只在帧头成立。按同一组数算一帧 `ceil(307200/1392) = 221` 包，
与板侧记的 663221 包 / 3001 帧 = 221.0 包每帧（`board/acceptance.md:36`）对上。

**像素成对**：`:141-143` 收低半、`:144-164` 收高半并写 `wr_data <= {p_data, pix_lo}`、
`wr_addr <= off[18:1]`、`off <= off + 2` ⇒ 一帧 512×300×2 = 307200 字节 = 153600 个 16 位字。
`FRAME_BYTES` 现在由顶层按 `IMG_W*IMG_H*2` 传（`eth_udp_video_top.v:235`）；
`:231-234` 记的是修前的状态：以前这里**没传**、用的是默认 307200，只在"512 且 300"时偶然相等。

**越界门**（`:150-152`）：`wr_en <= (off < FRAME_BYTES)`，且行覆盖统计用同一个边界（`:153`），
否则越界（`:161` `stat_oob_off <= stat_oob_off + 1`）。`:144-149` 的注释解释这是 #201：
原来这三行是无条件的，发包方选的偏移能把字写到帧缓存**之外**，而下游 `axi_frame_saver64`
自己没有上界检查。尺子是 `sim/tb_reasm_bounds.v` 的 R1，改前红凭据是 `build/r98_201_before.txt`
（这一件**在盘上**，我只确认了它的存在，没有重跑台架去复现里面的读数）。
顺带一条读数警告：那段注释里的 `131071 / 153600 字节 / 76800 字`是**那组测试参数**的量，
别拿它当现值：现值 307200 字节 = 153600 字，而 `off[18:1]` 是 18 位、位宽上限 262143。

**行覆盖为什么是 5×64 的 bank**（`:74-96`）：`row = off / (IMG_W*2)`（`:87`，
注释 `:84-85` 特别警告"不许用 `off[16:1]`"——像素序号截断会让 ~172/300 行的覆盖记丢、
`frame_done` 永不成立、画面出现黑纹）。位图拆成 `rok0..rok4` 五只 64 位寄存器（`:81`），
读侧是一个 5 选 1 的 `row_covered` mux（`:91-96`），写侧把"这一拍新起一行"独热化成
`bank_one = new_row_w ? (5'b00001 << rbank) : 5'b00000`（`:102`），
于是每只 bank 的 CE 只吃 ≤64 个负载、行计数器只吃 16 个（`:76-80` 给出修前的形状：
`fo=316`，最后一跳单独花掉 1.980 ns / 6.879 ns 的数据路径，布线占 81.2 %）。
`:97-99` 还留了一条编译顺序的坑：`bank_one` 必须定义在 `row_covered` **之后**，
否则 xvlog 报 `VRFC 10-3380` identifier used before its declaration。
边界守卫在文件末尾的 `initial`：`if (IMG_H > 5 * 64) $error(...)`（`:217-220`），
台架里当场喊、综合忽略。

**字节账（v5.1 的重写）**：`cov`（本帧累计，含在途包）与 `pend`（在途包自己的偏移）都是
`CW = $clog2(FRAME_BYTES+1)` 位的饱和计数（`:56-66`，FRAME_BYTES=307200 ⇒ CW=19）。
两个"最后一字节"的修正项：
```verilog
wire bytes_ok = cov_sat  | (cov_end  & p_valid);   // :70
wire last_pkt = pend_sat | (pend_end & p_valid);   // :72
```
`:68-69` 解释为什么要 `& p_valid`：帧最后一个字节与 `p_eof` 同拍，而计数器还没看见它，
"只在这一处补"，1 个 LUT 深。`:5-7` 给出这次重写的动机：原来
`cover + pkt_pay + 1 >= FRAME_BYTES` 这个**三操作数 32 位加法**占了该 125 MHz 组全部十条最差路径
（当时 WNS +0.499），换成"两条饱和累加 + 与常数比较"。`:55` 还留了命名理由：`cov` 不叫 `cover`，
因为 `cover` 在 `-sv` 下是关键字。

**验收门**（`:178-189`）：三条合取——`rows_hit >= IMG_H`、`bytes_ok`、`!bad_frame`。
`:179-182` 的注释说明为什么三条都要：只有行位图会让"丢一包但行被别的包填满"当成完整，
而那个洞（从没被写过的 BRAM 字 = 0）在流停下来之后就是黑条。

**失败分支**（`:190-203`）：短帧保留上一帧在屏上、只数一次；`last_pkt` 才脉冲
`frame_abort` 并记 `rows_missed = (rows_hit >= IMG_H) ? 0 : (IMG_H - rows_hit)`。
`:199-202` 明确写了"行数够但字节不够的作废，`rows_missed` 会是 0 —— 这不是 bug，
是在说缺的不是行、是最后一包的字节"。`:26-28` 补了另一半：连 `FRAME_BYTES` 都没凑够的短帧
**不**脉冲 `frame_abort`（它没有"结束"可报），那种情况由 `link_monitor` 的 `stall_ms` 抓。

**坏包分支**（`:206-210`）：`p_good==0` 时 `stat_bad+1`、`frame_err` 脉冲、`bad_frame <= 1`
——后者会一直挂到下一次帧头才清（`:137`），一帧内任何一个坏包都让整帧不可能提交。
`:46-48` 说这是**故意**相对 v5.0 的行为改变：字节总数没法"退掉"一个坏包，所以改成 1 bit 记账。

### 3.7 收侧用到的异步件（逐个点名）

1. `dc_fifo`（BRAM 双口，格雷码）：`u_cdc` 36 位宽 × 8192 深，写域 `gmii_rx_clk`、
   读域 `axi_clk`（`eth_udp_video_top.v:298-305`；`(* ram_style = "block" *)` 在 `dc_fifo.v:20`）。
   满判据用的是**当前**写指针而不是下一个（`dc_fifo.v:47`，`wr_full = (wgray == {~rgray_s1[高2位], ...})`），
   空判据 `(rgray == wgray_s1)`（`:68`）。`:40-44` 记下这一改的两笔收益：锥体只剩比较、
   可用深度从 `DEPTH-1` 变成 `DEPTH`（由 `sim/tb_cdc_capacity.v` 的 C1 钉住，改前 8191 / 改后 8192）。
   36 位的打包：`{1'b0, fb_wr_addr, fb_wr_data}` 或 flush 标记 `{1'b1, 19'd0, 16'd0}`
   （`eth_udp_video_top.v:264-265`），写请求 `cdc_wr` 还要防满（`:263`）。
   读侧带宽：`:258-262` 记下 v6.1 那次实测——一个 1392 B 的包在 125 MHz 下是**连续线速**进来的
   （每包 698 个 16 位写），原来限成"每 3 个 AXI 周期取 1 条"= 66 MB/s < 125 MB/s，
   单包就能灌满 512 深的 CDC ⇒ 稳定丢 ~46 % 的字，表现为"每隔一个 16bit 空洞"的黑纹。
2. `gapclr_sel` 三级同步（`eth_udp_video_top.v:277-281`）：fclk0 域的**电平**，先 3FF 再当电平用；
   `gapclr_sel` 来自 `gpio_o[26]`（`src/rtl/top/system_top.v:203`）。
3. `frame_done` 跨域 = 翻转 + 3FF + 边沿检测（`ddr_bank_commit.v:37-47`），
   换页条件在 `:50-51`：`TAIL_GUARD` 把判据从"只看 `saver_idle`"扩成
   "`cdc_empty` 且三级读流水都空"，修的是 v6.4 的"帧尾 4 字节偶发丢失"（`:6-8`）。
4. `link_active` 寄存一拍（`eth_udp_video_top.v:381-386`）：#209 说得很清楚——它原来是 16 位包计数
   的**组合或**却被像素域三级同步器的第一拍直接采走，计数器进位那几拍或树会出毛刺 ⇒
   一次假的"链路掉"。⚠ 同一处还写着这条判据是**结构**判据、台架判不了（RTL 仿真没有门延迟，
   `|s_pkts` 在仿真里永不出毛刺，`:378-380`）。
5. `lm_bus` 跨域 = 准静态总线 + 跳变沿捕获（`snap_cross.v:2-7` 与 `:36-46`）：
   边沿要 3 级同步才到目的域，而源总线至少保持到下一次写入（本项目 ≥1 ms），
   所以采到的一定是完整值。心跳那条有个反直觉点（`:6-7`）：**断链时 RTL8211 不停供 RXC，
   而是把它拉到约 1/48 ⇒ 心跳一直在、`hb_gone` 永不触发；要看的是间隔变长**（`hb_slow`）。

`sync_fifo`（`u_icmp_fifo`，`eth_udp_video_top.v:119-124`）**不是** CDC：它的写使能来自收侧
`icmp_rec_en`、读使能来自发侧 `icmp_tx_req`，而两侧同一根钟（§3.2）⇒ 它是同时钟 FIFO。
文件头 `sync_fifo.v:2` 就是这么定位的。`:3-4` 记的历史坑：存储阵列原先带异步复位时推不出 BRAM，
落到寄存器堆，导致 `eth_rxc@125MHz` 域内路径 WNS 为负。

### 3.8 观测面：收侧的数在哪读

`link_monitor` 的 10 条 lane 定义在 `link_monitor.v:187-196`（lane0 丢字、lane1 `{err16,bad16}`、
lane2 `{rows_miss_max, stall_ms}`、lane3..5 帧间隔、lane6 CDC 灌满次数、lane7 标志位、
lane8/9 包数与字节数）。三条纪律写在文件头 `:2-7`：输入必须是源模块**已打过一拍**的寄存器输出
（所以本模块里不许再插组合逻辑进关键路径）、`lm_bus` 是快照、所有"ms"其实是周期数。

`:82-84` 有一条容易被忽略的实现纪律：两个计数的使能**延迟事件谓词本身**一拍，
不能延迟两个操作数——`(req_d && full_d)` 与 `(req && full)` 延一拍不等价，
两信号在不同拍各自变化时前者会漏记那一拍（台架 E1 实测 DUT 31 / 参考 32）。
`:38-41` 又一条：分频器宽度必须由 `TC` 算出来，原来写死 `[15:0]` 装不下 125000 ⇒
`ms_div == TC-1` 恒假 ⇒ ms_tick 永远不来，而仿真把 `CLK_HZ` 改成 1000 完全看不出，
取证是 `WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed`。

---

## 4 为什么这样选（与另一种写法的对比）

### 4.1 IDDR 吃共享 BUFG，而不是 BUFIO

**当初为什么搬**（`src/rtl/eth/rgmii_rx.v:4-5`、`rk_zynq7020.xdc:37-42`、`开发台账` 的 #80）：
起点 IDDR 走 BUFIO（SCD 3.171 ns）、终点 fabric 走 BUFG（DCD 4.854 ns），同频同相却分走两条树，
偏斜 +1.616 ns 由综合器插 hold buffer 硬补 ⇒ 每次重建在 ±1 ps 上掷硬币：
同一份 RTL 的两次数是 `r62 的 WHS +0.001` 与 `r63b 的 +0.052`。
这一刀确实把域内余量做实了：现在 `eth_rxc` 的 WNS 0.739 / WHS 0.052、失败端点 0
（`build/timing_summary.rpt:182`）。

**代价是什么**：搬进 BUFG 之后，捕获沿到 D 脚附近要 5.008 ns，而**当时没有人给片外数据写到达窗**
（`开发台账`、`开发台账`：
"搬完之后没有人再给片外数据写到达窗，于是这条 4.8~5.0 ns 的捕获钟延迟只体现在'数据与钟同树'的错觉里"）。
窗一建起来，同一只 BUFG 就变成"捕获沿比数据晚到 ~5 ns"的净损失
（`src/rtl/eth/rgmii_rx.v:16-18`）。

**另一种写法**：IDDR 回 BUFIO、fabric 用同区 BUFR（7 系列 BUFIO/BUFR 是成对要求，这正是当初放弃它的
原因），或者给喂 RXC 的 MMCM 输出加负相移把捕获沿提前 ≈5.0 ns。后者已经试过并判负：
`−225° @ 125 MHz` 被归一化成 `rise@3.000`，终态 WHS −2.126，只买到 +0.759 ns
（`收口输入窗模型` 的 B 行）。
⇒ 现在的立场是"BUFG 保留、窗作为候选件留在仓里、下一刀是短钟网络"，
而 `#194` 的问题被改写成"**提前之后眼心还在不在 τ=31**"（`域划分候选评估`）。

**这一处最该记住的一句话**：`IDDELAY_VALUE` 换 31 买到的是**报告数字好看 0.315 ns**，
代价是真实角上的鲁棒性下降（`收口输入窗模型` 就写着这句）。
两种口径都要报，不能只报好看的那个。

### 4.2 FIXED 而不是 VAR_LOAD

FIXED 的代价：眼心只能靠**重综合 + 在已布线 DCP 上 set_property 扫**来量（`:68`），
运行时改不了 ⇒ 想在线调只能换 `VAR_LOAD` 或加 ICAP/AXI 写通路，而那条候选还需要先有板级判据
（`收口输入窗模型`）。
换到 VAR_LOAD 的收益是"能拿串口逐档加载 + 1000M 实流量看 `bad`"，也就是真正量一次片内眼心；
风险是要新增一条运行时写路径。这一笔**没有做**，登记为候选。

### 4.3 自算 FCS，而不是"长度 ≥64 且没有 ER"

后者的问题不是判据弱，而是**恒真**：RGMII 上没有 ER 这根线（§1.7），
所以 `p_good` 只能是常数 1，`stat_bad` 是死数字（`eth_udp_video_top.v:154-157` 把这段历史写全了）。
自算 FCS 的代价：一条 32 位 XOR 锥（`crc32_d8.v:23-81`）+ 一个 32 位比较 + 一个必须钉死的常数，
以及"必须有一支用另一套实现造帧的台架"（`sim/tb_v795_rx_fcs.v`）。
收益：收侧第一次有了真错误源，`frame_reasm` 的 `bad_frame`（`:48`）与 `frame_err`（`:208`）
从此是活的路径。

### 4.4 残值判据 vs 逐帧重算再比较

残值口径把"提取 FCS 4 字节 + 位反转 + 比较"整段省掉，比较退化成
`crc_q == FCS_RESIDUE`（`gmii_rx_mac.v:48`）。代价是判据正确性与核的约定**强耦合**，
常数只能实测钉（`:21-22` 的原话："凭印象写的那个数被 T5 判据当场拦下"）。

### 4.5 行覆盖位图 vs 只数字节数

只数字节：字节够就提交 ⇒ 缺行的洞在静止画上是黑条，缩放时"会动"（`frame_reasm.v:2-3`）。
代价是 300 个覆盖 FF + 除法 `off / ROW_STRIDE`（`:87`）。这一族后来被两把刀削过：
bank 化降扇出（§3.6）与 v5.1 的算术重写。

### 4.6 字节索引机 vs 字段级流水

`:2` 那句 "easier to verify" 是有代价的：`bcnt == 16'dN` 的比较一串并到一个 `accept` 锥上，
而且边界时刻全靠人记（`:133-136` 那个 bug 就是这类记账错）。
收益是每条判据都能写成一行的真值表，台架可以按字节喂——`sim/tb_udp_parser.v` 与
`sim/tb_v795_rx_chain.v` 都是这么打的。

### 4.7 为什么现在不做"MAC 之上插异步 FIFO"

`verilog-ethernet` 的形状是 MAC 之上一层都不在 RXC 域（三个时钟口 + 两只 async_fifo_adapter），
本工程的 `gmii_tx_clk` 与 `gmii_rx_clk` 同一根 ⇒ 收侧链、发侧协议栈、`link_monitor` 全压在同一颗
8 ns 时钟上：**2544 只寄存器**（`build/clock_util.rpt:174`）、4835 个 setup 端点
（`build/timing_summary.rpt:182`）。解耦（候选 B）的代价写在
`域划分候选评估`：每一处"发侧由收侧事件触发"都要缓冲、
新增跨域要重新过 CDC 判据、台架与上板复验全跑 ⇒ 是一整轮的活。

⚠ 一条必须带着走的更正：**`axi_frame_saver64` 那 512×64 的 LUTRAM 打包器不在 `eth_rxc` 域**。
`src/rtl/eth/eth_udp_video_top.v:355` 写的是 `.clk(axi_clk)`，而 `axi_clk` 是 HP0 的 100 MHz
（`clk_fpga_0`，挂 3338 只寄存器，`build/clock_util.rpt:128`）。
这条以前写错过（把打包器算进这一族），现在的归属以
`域划分候选评估` 为准；同一文档 §1 已把"把打包器移出域"这条候选**作废**。
⇒ `eth_rxc` 的"装得多"要按"收侧链 + 发侧协议栈"来还，不能按打包器来还。

---

## 5 怎么验：点名工件与每条判据在测什么

**先说工件可见性**：本章的 `src/`、`sim/`、`build/`、`report/` 引用都以工作树
`D:/Xilinx/Prj/pro/Video_Processing`（分支 `main`）为准；这份交付副本是分支 `review/20261005`，
`docs/course/` 那一族在它里面放在 `local_docs/course_and_walkthrough/`，所以我引
`docs/course/04-…` 的那几处在包内要按这个映射去找。`build/evidence/` 有两件被注释点名但盘上确实没有
（`r115_window/probe2_console.txt`、`r114_sweep*`），正文里都写明了"不在盘上"。

先说跑法。单支台架：

```bash
VP_VIVADO_BIN=<Vivado>/bin bash build/sim/run_one.sh tb_v795_rx_chain
```

`build/sim/run_one.sh` 是仓里唯一存在的入口——**`sim/run_one.sh` 不存在**，但
`sim/tb_icmp_rx_len.v:38`、`sim/tb_v795_rx_fcs.v:19` 等台架的头注释里点的是 `sim/run_one.sh`——
照抄之前先 `ls`；判定行的读法是 `RESULT <tb> PASS` 顶格或 `PASS <tb> ALL`。
退出码约定只有一个出处：`build/sim/run_one.sh:117` 那行写的 `0 绿 / 1 编译或例化失败 / 2 REFUSE /
3 **判红** / 4 认不出判定行`（`docs/course/04-rgmii-rx-frame-reassembly.md:212-213` 是同一口径的复述）。

| 台架 / 命令 | 测的是本章的哪件事 | 关键判据（写的是**表达式语义**，不是"跑过"） |
| --- | --- | --- |
| `sim/tb_v795_rx_fcs.v` | §1.6 残值数学 + §3.3 的帧尾约定 | T0 量具自校（TB 造的帧真是标准以太网帧，校验值必须 `debb20e3`）；T1/T2 两种内容各一次 good 且 `dut.crc_q` 两次**相同**（残值与内容无关）；T3 翻 1 bit ⇒ bad；T4 截短 ⇒ bad；T5 `dut.FCS_RESIDUE === res1`（把 RTL 常数钉回实测值） |
| `sim/tb_v795_rx_chain.v` | §3.3+§3.5 的整条转发 | C1 好帧：`pl_cnt=32`、`pl_sof=1`、`pl_eof=1`、`pl_good=1`、`stat_udp_ok=1`、`sb+sf=0` 且逐字节 `got[k] === 8'hA0+k`；C2 载荷翻 1 bit ⇒ `m_bad=1`、`pl_good=0`、`sb=1`；C3 目的端口 5002 ⇒ `pl_cnt=0`、`sf=1`；C4 **截断帧**（只发 60 字节）⇒ `pl_cnt=10`、`pl_eof=1`、`pl_good=0`；C5 两帧连发 ⇒ 计数互不串（`pl_cnt=64`、`pl_eof=2`） |
| `sim/tb_udp_parser.v` | §3.5 的窗口/过滤（厂商风格 eof） | 判据 1 `pay_bytes == 10`；判据 2 把 `frame[37]` 改成 `8'h8A`（dport 5002）⇒ `pay_bytes == 0` |
| `sim/tb_icmp_rx_len.v` | 收侧 ICMP 载荷长度边界（第 12 章的输入侧） | A..G 十四轮 `N=1,2,3,...,63,64`（奇偶都有）逐一钉 `rec_byte_num===N`、`en_cnt===N`、第 k 个 `rec_en` 上 `rec_data===pay[k]`、`reply_checksum===exp_sum(N)`（**成对累加、奇数尾字节放低半、32 位不折叠**）、`done_cnt===1`、`cur_state===S_IDLE`；K/L 族钉"声明 0 而线上流 4 字节"和"只到 2 字节而声明 10"两个畸形包之后，**紧跟的正常包仍被完整应答** |
| `sim/tb_icmp_len_wrap.v` | IP 总长 <28 的回绕 | R3 合法包先自证激励为真；R1 畸形包过完帧间隙后 `(dut.cur_state == S_RX_DATA)` 必须为假；R1b 跨两帧数 `rec_en` ⇒ `en_bytes==8`（>8 说明畸形帧把下一整帧当自己的载荷吐了）；R2 紧跟的合法 ping 仍被应答（`icmp_id`/`icmp_seq` 对得上） |
| `sim/tb_reasm_bounds.v` | §3.6 的越界门 | R1 越界包（`off=288`）`w_total==0 && w_oob==0`（**改前必红**）；R2 同一个包 `stat_oob_off` 至少 +1；R3 末字包 `w_total==2 && w_max==127`；R4 整帧 64 包 ⇒ `done_pulse==1`、`stat_frames==1`、`w_total==128`；R4a `stat_pkts==64 && stat_bad==0` |
| `sim/tb_eth_video.v` | GMII 直环：`udp_tx` 发的字节流直接喂回收侧，再进 `frame_reasm` | 判据 1 `n_rec == 68`（一发一收的字节数不被截断）；判据 2 两包（偏移 0 与偏移 64）之后 `stat_frames >= 1`；每包等 `tx_done`，超 5000 拍判 `FAIL timeout tx`（反空转）。⚠ 这一支的收侧用的是厂商 `udp_rx.v` 那一路，**不是**顶层现在例化的 `udp_rx_parser` ⇒ 它证明的是"环得通"，不是"现行过滤对" |
| `sim/tb_udp_reasm.v` | §3.6 的正序/乱序/坏包/重复 | 乱序段先 `send_pkt(8,...)` 再 `send_pkt(0,...)` ⇒ `capture[4]==16'hBEEF` 且 `capture[0]==16'h1111`；坏包段 `good=0` ⇒ `s_bad≠0`；重复段同偏移发两遍 ⇒ 后写覆盖前写 |
| `sim/tb_cdc_capacity.v` | §3.7 的 `dc_fifo` 满边界 | C1 首次报满发生在**收下第 8192 个字之后**（不是 8191）；C2 报满之后一个都不再收；C3/C4 排空字数==深度且逐字对得上写入序号；C5 三轮灌满-排空跨过指针回绕点不丢字不乱序 |
| `sim/tb_crc32.v` | §3.4 的核 | 复位释放后 `crc_data==32'hFFFF_FFFF`；喂 `8'h00` 与 `8'hFF` 后两次值不等；`crc_clr` 拉一拍后回到全 F；序列 `{55,AA,01}` 中途清零跑两遍逐位相同 |
| `sim/tb_link_monitor.v` | §3.8 的仪表本身 | E1/E2 `P_DROP === 参考计数`（台架用同两个式子独立数一遍）、`P_CDC_EP===ref_ep`；B2 统计寄存器自洽 + `force u_lm.gap_sum` 后判据必须转红（**反空转**）；D 段心跳 1.5 µs ⇒ `d_slow===0`、8 ms ⇒ `d_slow===1` 且 `d_gone===0`、停钟 ⇒ `d_gone===1`；xdomain 换 100 个总线图案 ⇒ `tears==0` |
| `bash build/tb98_report.sh` | 顶层（唯一例化顶层的台架 `sim/tb_v98_top_seam.v`） | 一次 40+ 帧约 75 分钟；报告头部钉 `pl_video_top.v` 与本台架的 md5，对不上就判"这份不算数"（`build/tb98_report.sh:10-16` 的理由是 #88：gates 14/14 与顶层台架同红可以同时成立） |
| `node src/host/health_read.mjs` | 板侧读回 | lane0..9 + 23..31 的读数与两遍比对（单调 lane 只允许第二次 ≥ 第一次，变小就是采到快照刷新那一拍）；`drop_words` 的语义写在 `src/host/health_read.mjs:54`："被 `fifo_full` 挡住而永久消失的 16bit 字数（板上唯一真实丢数据通道）" |
| `bash build/board_verify.sh` | 板上收侧链路健康 | 第 2)步直接跑 `health_read.mjs --json` 并对 `drop_words` 做判定（`build/board_verify.sh:204-216`）；C9 那一格是 `ping 192.168.1.10`（`board/hardware_setup.md:53`，它同时验位流，因为应答由 PL 里的 ICMP 决定） |

窗这一侧的复现只有一条路，而且它**不要求你重新综合**：

```bash
VP_R116_IO_WINDOW=1 bash build/tcl/build_system_axigpio.tcl   # 把 r116 那 4 条 set_input_delay 带进实现
```

预期读数（不是"过"，是"红得有限"）：5 个 I/O 端点、hold −0.870 / setup −0.846 在 τ=31
（`build/tcl/build_system_axigpio.tcl:40-56` 的注释把"4 项发布门禁机械判红"的原因写全了；
`那一轮的逐轮页` 记的采纳结局是窗退回候选件、默认不加载）。
逐档复量靠的是 `set_property IDELAY_VALUE` 在已布线 DCP 上有效这一条（件
`build/evidence/r115_window/probe3_console.txt`，我上面 §2.5 那张表就是它的 `:107/:111/:170/:174/:188/:192` 六行）。

### 5.1 本章判据的三个盲区（写下来，别让"全绿"骗人）

1. **窗默认不在构建里** ⇒ 名册上 `eth_rxc` 的 WHS 0.052 不包含片外那一段
   （`时序债务账` §2 的原文口径："未覆盖 = 不是满足，是没检查"）。
   任何"收侧时序有余量"的说法都必须带上这句前提。
2. **台架不看物理采样点**。所有 RX 台架都从 GMII 字节流这一级注入（`tb_v795_rx_chain` 驱的是
   `rxd/dv`），引脚级的双沿/IDELAY/BUFG 偏斜**根本不在它们的观察范围内**。
   采样点落没落在眼里，只能由 1000M 实流量的 `drop_words`/`bad` 判
   （`src/rtl/eth/rgmii_rx.v:10-11` 写的就是这条，虽然它当时的那句"没有 set_input_delay"已在
   `:12` 被自己更正）。
3. **`p_good` 之外的错误通道今天只有 CDC 那一条是真的**。断流/短帧靠 `stall_ms`
   （`frame_reasm.v:26-28` 明确说了连 `FRAME_BYTES` 都没凑够的帧不报 abort），
   丢字靠 `link_monitor` 的 lane0；这两条都要与"源时钟健康"相与才可信
   （`link_monitor.v:6-7`：断链时 RXC 被拉到 ≈1/48，所有 ms 字段其实是周期数）。

小结一句：这一段的难度不在"能不能收到数据"，而在四件事同时成立——
双沿拼字不错位（§1.2/§1.3）、捕获点真的在眼内（§2.2/§2.3，且要用实测斜率而不是名义 ps/档）、
错误源是自己造的且有独立实现钉住（§1.6/§4.3）、跨域只走那几条被允许且有结构保证的路（§3.7）。
下一章讲发侧：`arp_tx`/`icmp_tx`/`udp_tx`/`eth_ctrl` 怎么把一帧拼出来，以及为什么它们也在这颗 8 ns 的钟上。

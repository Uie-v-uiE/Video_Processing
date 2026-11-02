# 00 · 前置知识：读这套代码之前必须握在手里的那张地图

> 这一章不讲 Verilog，也不讲"什么是触发器"。它只做一件事：**把读这套代码要用到的那些概念，
> 全部换成这个仓库自己的数字和文件位置**。每一条都指到我实际打开过的那一行。
>
> 三条全文通行的规矩：
> 1. **每个数都点名它的出处**。没有出处的数写"未量"，不靠"看起来应该是"补全。
> 2. **量纲先问，再动手**。本项目已经有一次把外部规范的散布量当捕获窗绑进 SDC 的事故，
>    代价是把一个好设计判成负裕量（本文件第 2 节）。
> 3. **"没检查"不等于"满足"**。这句话在仓库里出现了很多次，它不是修辞，是账本口径
>    （`src/constraints/r116_rgmii_input_window.xdc:5`）。
>
> 实现报告的读数按收稿时盘上那一份：`build/timing_summary.rpt` 文件头打的是
> `Date : Sun Oct 4 04:37:30 2026`、`Design State : Routed`，对应板上那颗 r118 位流。
> 重跑构建会原地重写 `build/` 那一份，所以**引用这些行号前先确认还是同一版**
> （怎么确认见第 8 节）。

---

## 1. 视频时序：像素钟、消隐、有效区，以及"为什么不能随机访问整帧"

### 1.1 这套设计的节拍是从哪来的

外面只进来两只钟：板子上的 50 MHz 晶振（`sys_clk`，约束在 `src/constraints/rk_zynq7020.xdc:6`
用 `create_clock -period 20.000` 声明）和 PS 的 `FCLK_CLK0`（100 MHz，`clk_fpga_0`，
**不是我在 XDC 里写周期**，它是 PS7 IP 自己的 XDC 从 BD 配置 `PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`
（`build/tcl/build_system_axigpio.tcl:97`）推出来的）。PL 侧其余所有节拍都由一只 MMCM 合成：

```
CLKIN1_PERIOD 20.000  →  CLKFBOUT_MULT_F 20.000  ⇒  VCO = 1000 MHz
CLKOUT0_DIVIDE_F 20.000 ⇒ 50 MHz  像素钟 clk_pix
CLKOUT1_DIVIDE      4   ⇒ 250 MHz 5 倍串行钟 clk_pix5x
CLKOUT2_DIVIDE      5   ⇒ 200 MHz IDELAY 参考钟
```

出处是 `src/rtl/clocks/clk_gen.v:17-27`（文件头 `src/rtl/clocks/clk_gen.v:2` 那句注释就是这本账的摘要）。
这只模块被例化了**两次**：`src/rtl/top/pl_video_top.v:128` 的 `u_clk` 出像素/5 倍/参考三只，
`src/rtl/top/system_top.v:121` 的 `u_idelay_clkgen` 只为了拿一路 200 MHz 给 IDELAYCTRL
（同文件 `src/rtl/top/system_top.v:123-124` 把它的像素输出显式接到 `_unused` 上）。这就是
`build/utilization.rpt:163` 那行 `MMCME2_ADV | 2 | ... | 4 | 50.00` 的来源——
**资源报告里那个"2"不是冗余，是这颗器件上唯一的"用 MMCM 换一只 200 MHz"的写法**。

八只时钟对象、四只有内部路径，实测名册在 `build/timing_summary.rpt:162-171`
（Clock Summary 表）与 `build/timing_summary.rpt:181-187`（Intra Clock Table）。
把它们连到具体的树上，最省事的是 `build/clock_util.rpt:59-66` 那张 BUFG 表：
`clk_fpga_0` 走 `BUFGCTRL_X0Y16` 吃 3597 个负载、`clkout0_1` 走 `BUFGCTRL_X0Y0` 吃 3276 个、
`eth_rxc` 走 `BUFGCTRL_X0Y1` 吃 2544 个。**读时钟问题第一眼就该看这张表**，
因为它直接告你哪只钟的树最重、跨时钟区域的负载挂在哪。

### 1.2 一帧的完整账（这是全设计唯一的时间预算）

面板是 1024×600，参数写在 `src/rtl/video/video_timing_1024x600.v:18-21`：

```
H: 1024 有效 + 44 前肩 + 88 同步 + 188 后肩 = 1344 拍
V:  600 有效 +  3 前肩 +  6 同步 +  16 后肩 =  625 行
```

乘上 20 ns 的像素周期，得到后面所有判断都要用的四个数（我按上面的参数算的，
场频那一格与 `data/metrics.csv` 第 3 行"1024×600 @59.5"以及 `#153` 的口径一致）：

| 量 | 值 | 算法 |
|---|---|---|
| 一行 | 26.88 µs | 1344 × 20 ns |
| 一帧 | 16.80 ms | 625 × 26.88 µs |
| 场频 | 59.52 Hz | 50 MHz ÷ 1344 ÷ 625（**不是 50 Hz**，这条曾经被念错过） |
| 垂直消隐 | 672 µs = 33 600 像素拍 = 67 200 个 100 MHz 拍 | 25 行 |

最后一行是全设计最要紧的一个数，因为**显示帧缓存的整幅搬运只能塞在垂直消隐里**，
仓库自己的算式在 `src/rtl/top/pl_video_top.v:393-394`：
"25 blank lines = 33.5k pix cycles = 67k axi(100M) cycles, and one frame is 38.4k 64-bit words"。
把这两个数并排看就知道余量在哪：**38 400 个字 vs 67 200 拍 ≈ 1.75 拍/字**，
而读口是 64 bit + 突发（`src/rtl/axi/axi_frame_writer_gated.v:37-38` 钉
`arsize=3'b011`／`arburst=2'b01`），所以搬运能在第一行有效像素被画出来之前收工。
这条"整帧只在消隐里换页"的策略被叫做 ATOMIC SWAP（`src/rtl/top/pl_video_top.v:392`），
它的存在理由不是漂亮，是**避免拷贝追上扫描束**——上一版固定位置的那条黑线就是这么来的。

消隐窗的边界本身还有一次修正：`src/rtl/top/pl_video_top.v:399` 的
`VB_X_GUARD = 12'd1279`（= H_TOTAL 1344 − 65），早关 64 个消隐像点，
理由是 `allow_copy_axi` 过 `frame_commit_lock` 的 CDC 要晚这个窗口约 5 个像素拍。
**这是一个"CDC 延迟反过来定义了几何时序边界"的例子**，第 5 节会再回到它。

### 1.3 de / x / y 三件套的因果，和它为什么不是"随便三个信号"

`src/rtl/video/video_timing.v` 是唯一的时序发生器，全部三行组合判断在
`src/rtl/video/video_timing.v:49-51`：

```
hs_act = (h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC)
vs_act = (v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC)
de_act = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE)
```

关键在于 `:63-67`：`x <= h_cnt; y <= v_cnt; de <= de_act;` —— **输出的 x/y/de 比计数器晚一拍**。
所以任何拿 `de` 当"这一拍有效"、又拿同一拍的 `x/y` 去索引存储的设计，
它的地址实际比像素晚一格。这一族错位在本仓库有过专门的账（`src/rtl/process/proc_pipeline.v:14-15`
那段"坐标抽头与 de 同拍、行缓存写地址越界"的 #103）。
`frame_start` 与 `frame_done` 也是边沿标志而不是电平（`src/rtl/video/video_timing.v:68-69`），
`frame_done` 落在最后一行的最后一个像素拍——**这就是第 5 节那条跨域脉冲的源头**。

### 1.4 为什么流式管线不能随机访问整帧（本项目的三条硬约束）

不是风格问题，是三条可以逐条指到代码的机制：

**(a) 窗口滤波天然滞后一行。** 行缓存式 3×3 滤波在收到第 y 行时才**才刚能**算第 y−1 行的窗口，
因果性决定了这个 −1 行；本项目五个可选级里四个是窗口级，于是整链的内容偏移固定
**−4 行、0 列**，这个数写在参数上：`src/rtl/process/proc_pipeline.v:27` 的
`parameter integer OFF_LINES = 4`，注释 `:24-26` 就是这句话的原文。
它同时说明了解药的形状："顶层能补：帧缓存是随机地址的，把右窗读坐标对应的显示行提前
OFF_LINES 行，链子自己的滞后正好把它抵消"（`src/rtl/process/proc_pipeline.v:25-26`）。

**(b) 流水线延迟必须是常数。** `src/rtl/process/proc_pipeline.v:22` 写死
`parameter integer LATENCY = 15`，并且注释 `:21` 明说"不许由外部覆盖"。
逐拍账在 `:3` 与 `:19-21`：灰度1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3 = 15。
为什么必须是常数：**输出端的 `de`/`x`/`y` 与像素数据必须在同一拍对齐**，
延迟跟"开了哪一级"挂钩的话混色和 OSD 叠加就会逐档错位。
而"级 0 的 gamma 是分布式 RAM 组合读出 ⇒ 不占拍"这句（`:21`）意味着
**存储的读口类型是流水线拍数的一部分**——这是第 6 节的核心。

**(c) 只有帧缓存给随机读。** 一旦要做缩放/旋转这类"目标像素 → 源坐标"的映射，
就不再是"流过就行"，而是要**按算出来的地址回头取任意像素**。
本项目的做法是：DDR 里整帧 → 消隐窗内搬进片内显示帧缓存 → 读口按随机坐标出像素
（`src/rtl/process/bilin/fb_bilin.v:2-6`：输入每拍的 `sx/sy` + Q8 小数请求流，
"每个源像素用满它天然的 4 个 50 MHz 拍（2 显示列 × 2 显示行），一个读口每拍一次读，全程不进快域"）。

于是"流式 vs 随机访问"这条线在本项目里画得很具体：
**几何变换是破坏流式的那件事，代价是必须存在一整块可随机读的帧缓存**，
而那块帧缓存就是 BRAM 的主要去向（`build/utilization.rpt:106` 的
`Block RAM Tile | 95.5 | ... | 140 | 68.21`，`data/metrics.csv` 的 BRAM 那一行写的
"帧缓存由 64-bit 宽 + 乒乓两块拼出"）。`src/rtl/video/frame_buffer.v:1-3` 顺手记下另一件事：
那份"整帧双端口 BRAM"文件**本树无人例化**（现役是 64 bit 写口的 `frame_buffer_w64`），
所以找结构别按它找——遗留件与在用的件混在一个目录里，这是读任何老仓库都要有的警觉。

---

## 2. TMDS 10:1 串行与字符间 skew：它是**散布**，不是**捕获窗**

### 2.1 10:1 是怎么拼出来的

一个字符 10 bit，像素钟 50 MHz ⇒ 字符周期 `Tcharacter` = 20 ns；
线上一 bit = `Tcharacter/10` = **2 ns**，所以串行钟是 250 MHz 且必须**DDR**：
`src/rtl/hdmi/tmds_serializer.v:2` 那句 "`DATA_WIDTH=10` requires `DATA_RATE_OQ=DDR`" 就是这个除法。
10 bit 一只 OSERDESE2 装不下（一台最多 8 位），于是主从级联：
master 吃 D1–D8（`src/rtl/hdmi/tmds_serializer.v:33-40`）、slave 只吃 D3/D4 = `din[8]/din[9]`
（`:71-74`），中间靠 `SHIFTOUT→SHIFTIN` 串起来（`:43-44` 与 `:65-66`），
最后 `OBUFDS` 出差分对（`:91`）。两台共用 `CLK=clk_pix5x`／`CLKDIV=clk_pix`
（`:31-32` 与 `:69-70`）——**CLKDIV 这一根就是"并串两边共享同一只慢域"的接线证据**。

时序含义（第 7 节会用到）：`clk_pix` 与 `clk_pix5x` 同 MMCM、5:1、0° 相位，
本设计**有意把它们留在同一个时钟组里**，让这条并串转换按同步路径做 setup 分析；
`src/constraints/clock_groups_impl.xdc:25-26` 明写"声明成异步反而会漏检"。

### 2.2 三个量纲，别再混

| 名字 | 定义 | 50 MHz 档的值 |
|---|---|---|
| `Tcharacter` | 一个 10-bit 字符 = 一个像素周期 | 20.000 ns |
| `Tbit` | 串行一位 | 2.000 ns |
| 互对偏斜上限 | **两脚到达时刻之差**的单边上限 | 0.20 × `Tcharacter` = **4.000 ns** |
| 对内偏斜上限 | P/N 两脚之差的上限 | 0.15 × `Tbit` = **0.300 ns** |

出处是 HDMI 1.4 §4.2.4 Table 4-24（1.3/1.1 同值），逐条取证与镜像 PDF 的页码在
`屏侧窗口取证`；那份文件还明确划出哪些量只能作"第三方代理"引用。

### 2.3 本项目吃过的那次量纲错（这是本文件最想让你记住的一段）

把 0.20 `Tcharacter` 当成 ±窗，用 `set_output_delay` 绑上去，做了两次 load 实验：

- 参考钟用片内串行钟 `clkout1_1`：三条数据道立刻判
  **−3.482 / −3.458 / −3.474 ns**（`src/constraints/r119_hdmi_source_window.xdc:51-52`
  就是那两个 `set_output_delay -clock clkout1_1 -max 4.000` / `-min -4.000`；
  读数件 `build/evidence/r119_xdc_loads_probe3.txt`）。
- 参考钟换成脚上钟（`create_clock -period 20.000 [get_ports {tmds_clk_p}]`）：
  **−4.897 / −4.873 / −4.890 ns**（件 `build/evidence/r119_xdc_loads_probe4_pinclk.txt`）。

第二次实验里工具自己把要求时间展开成
`Requirement: 4.000ns (r119b_tmclk rise@20.000ns - clkout1_1 rise@16.000ns)`——
**这一行就是证据**：`set_output_delay` 的语义是"外部接收器在参考沿附近采样"，
于是它把一个 20 ns 字符周期里的 4 ns 要求，算成了"数据必须落在采样沿附近"。

判别链条的完整版（含"为什么这不是设计不合格"）在
`屏侧实测记录` 与
`report/collaboration/corrections.md:229-233`。两条结论要分开记：

1. **量纲错记在约束侧，不许靠放宽窗把它变绿。** 原话："这是记在约束侧的量纲错，
   不是设计时序债，也不许靠放宽窗把它变成通过"（`report/60-failure-analysis.md:172`）。
2. **`.xdc` 里写 Tcl 控制流会被解析器整块跳过而且 rc=0。** 第一版候选件里写了
   "读不到参考钟就 REFUSE"的守卫，Vivado 逐行报 `CRITICAL WARNING [Designutils 20-1307]`
   然后**继续加载成功**——防呆变成"防呆失效且不报错"，比没有守卫更危险。
   这件事在 `build/tcl/build_system_axigpio.tcl:72-74` 又写了一遍，因为它是构建脚本
   为什么把守卫留在 Tcl 侧的原因。

### 2.4 同一件事的正确问法（同量纲、工具能直接答）

不问"窗"，问"离散"：在**已布线**成品上逐脚量 clock-to-pin 的 `Data Path Delay`，
再取脚间差。探针 `build/tcl/probe_tmds_pin_skew.tcl:1` 干的正是这件事（10 个输出脚各取
max/min 一条路径），读数：

| 判据 | 规范上限 | 实测（r118 已布线） |
|---|---|---|
| 互对离散（数据道 vs 钟道） | 0.20 `Tcharacter` = 4.000 ns | 最差 **0.065 ns** ⇒ 余量约 61× |
| 对内离散（每对 P/N） | 0.15 `Tbit` = 0.300 ns | 最差 **0.001 ns** |

表在 `屏侧实测记录`，判定件
`build/evidence/r119_window_check.txt:11`（`判定 10 项 红=0 未测=0 PASS`）。
**这三行能说什么、不能说什么，那段写得比读数更值得读**
（`屏侧实测记录`）：它只覆盖 FPGA 内部到封装脚，
规范的对象是 Source Connector，板级走线/连接器的离散**未量**；
而眼图、抖动、占空比、上升下降这几条**在 SDC 里没有容器**，只能仿真 + 示波器，状态是未实测。

### 2.5 可推广的那一条规矩

搬外部规范的数之前先问它是哪一类：

- **窗**（setup/hold 双边）→ 能用 `set_input_delay`/`set_output_delay` 表达；
- **散布 / 离散上限**（单边差值）→ 不能表达成窗，只能换成"量的问法"；
- **波形质量**（眼/抖动/占空比/沿）→ SDC 根本没有容器，只能仿真与仪器。

这条判据的原文在 `开发台账` 第 335 条，`限制清单`
是它被压缩成两句的版本。

---

## 3. RGMII 源同步：RXC 由 PHY 恢复、4 bit DDR、抽头与它的非线性

### 3.1 结构与"谁提供节拍"

RGMII 用 4 位数据线双沿搬运字节，125 MHz ⇒ 500 Mbps。
本项目收口是 `src/rtl/eth/rgmii_rx.v`，一句话概括它的功能：
**RGMII(4bit DDR) → GMII(8bit SDR)**（`src/rtl/eth/rgmii_rx.v:1`）。
位段定义在同一个文件的头两行：RXC 上升沿那半字节是**低位**、下降沿是**高位**，
实现靠 `IDDR` 的 `SAME_EDGE_PIPELINED` 模式，`Q1`=正沿、`Q2`=负沿
（`src/rtl/eth/rgmii_rx.v:88` 与 `:133-134`，四根数据位由 generate 循环各配一对
`IDELAYE2`+`IDDR`）。`RX_CTL` 只当 GMII 的 `rx_dv` 用，
且判"两沿都为 1"才算有效（`src/rtl/eth/rgmii_rx.v:48`，注释 `:6` 说明了为什么交不出错误标志）。

**关键概念：`eth_rxc` 不是本板产生的钟，是 PHY 从数据流里恢复出来再送出来的**，
所以它的相位不由我们控制。这只钟在 FPGA 内部的走法被改过一次，而那次改动是整个第 3 节的因：

> 原来 IDDR 吃 `BUFIO`（SCD 3.171 ns）、fabric 吃 `BUFG`（DCD 4.854 ns），
> 同频同相却分走两条树，偏斜 +1.616 ns 由综合器插 hold buffer 硬补
> ⇒ WHS 每次重建在 ±1 ps 上掷硬币（r62 量到 +0.001）。
> —— `src/rtl/eth/rgmii_rx.v:4-5`

现在 5 只 IDDR 与下游 fabric **吃同一只 BUFG**（`src/rtl/eth/rgmii_rx.v:51-54`），
`build/utilization.rpt:162` 那行 `BUFIO | 0 | ... | 16 | 0.00` 就是这件事在资源报告里的影子。

**改时钟树本身就是一次时序动作**：`BUFIO→BUFG` 把采样沿往后推了 **1.683 ns**，
于是数据侧必须补同样的量（`src/rtl/eth/rgmii_rx.v:7-9`）——这就是抽头参数存在的物理原因。

### 3.2 窗的数字从哪来（以及"用错行"用了三次）

RTL8211F-CG 的 strap 决定内部延时加在谁身上。原理图第 8 页读到 R57/R59 4.7K 把
`PHY1_RXD0/RXD1` 上拉到 `IODVDD` ⇒ **RXDLY 与 TXDLY 都是开的**，
而规格书 Table 11 原文是 "1: Add 2ns delay to **RXC** for RXD latching"
（`src/constraints/r116_rgmii_input_window.xdc:11-13`，抄件
`build/evidence/r115_rtl8211f_delay_source.txt`）。
**延时加在钟上，不是加在数据上**——方向反了整笔账就反了。

于是这一路的窗要看规格书 Table 60 的**发射端**两行（"transmitter" = PHY 输出 = 我们的收口）：

```
TsetupT  Data→Clock Output Setup at transmitter (delay integrated)  min 1.2  typ 2  –
TholdT   Clock→Data  Output Hold  at transmitter (delay integrated)  min 1.2  typ 2  –
两者相加 = 半周期 4 ns ⇒ 数据沿相对它自己的捕获沿落在 [1.2, 2.8] ns 之前
```

同一张表里还有 `TskewR 1/1.8/2.6` 与 `TsetupR/TholdR`，那是 **PHY 的接收端**，
也就是本板 TXD/TXC 那一侧——**不能拿来当收口的窗**。
仓库把这一族"用错行"记了三次（±0.500 用的是 `TskewT` 那一行；并集 1.000–2.600 用的是
`TskewR`；ISSUES #304 与 #309），全都在
`src/constraints/r116_rgmii_input_window.xdc:18-20` 与
`收口输入窗模型`。
**教训的形状**：芯片手册里同一个"skew"字出现在发射端和接收端两行，量纲和方向都不同；
拿错行不是笔误，是把另一个器件的接口当自己的接口。

### 3.3 工具的边配对决定 offset 从哪个沿量起

窗建起来之后，第一件意外是"正确的拼法只有一种，其余是镜像"。同一只已布线 DCP、
同一把窗，四种拼法（`Requirement` 那一列是工具自己打的）：

| 拼法 | min/max | HOLD | SETUP |
|---|---|---|---|
| W1 同沿（负） | −2.800/−1.200 | **−5.185** | +3.614 |
| W2 移一个整周期 | 5.200/6.800 | +2.815 | **−4.386** |
| W3 = W2 + `-clock_fall` | 5.200/6.800 | +2.815 | −4.386 |
| W4 = W1 + `-clock_fall` | −2.800/−1.200 | −5.185 | +3.614 |

⇒ 工具对 IDDR 的 D 脚做的是"**上升沿发射 → 下一个下降沿捕获**"的 setup（
`Requirement: 4.000ns (eth_rxc fall@4.000ns - eth_rxc rise@0.000ns)`）
和"同一个沿"的 hold（`Requirement: 0.000`），所以 offset 必须从**发射沿**量起，
正确的拼法是 W5 = `min 1.200 / max 2.800`。表在
`收口输入窗模型`，
落到文件里是四条命令（`src/constraints/r116_rgmii_input_window.xdc:32-35`）。
顺带一条工具口径：本机 `set_input_delay` 没有 `-setup/-hold`、也没有 `-clock_edges`，
而 `-min` 与 `-max` **必须各写一条**，合在一条会被解析成"太多 positional"（同文件 `:30-31`，ISSUES #308）。

### 3.4 抽头与那个"约 78 ps"的非线性

IDELAYE2 是一根**模拟可编程延迟线**，`IDELAY_VALUE` 合法范围 0…31，
参考钟 `REFCLK_FREQUENCY(200.0)`（`src/rtl/eth/rgmii_rx.v:70`）。
"一拍等于多少 ps"这件事，仓库里同时存在**四个互不一致的数**，全部有件：

| 数 | 来源 | 性质 |
|---|---|---|
| 78 ps | `src/rtl/eth/gmii_to_rgmii.v:23` 的参数注释"如果为 n, 表示延时 n*78ps" | 继承来的注释，无件 |
| 156 ps | 1/(32×200 MHz)，`src/rtl/eth/rgmii_rx.v:8` 用它推 +11 拍 | 纸面算术 |
| 88 ps | 报告里 IDELAYE2 的 2.292 ns / 26 档 | 工具分量 |
| **63 ps** | 真窗下把 τ 从 0 扫到 31 得到的实测斜率 | 实测 |

`src/rtl/eth/rgmii_rx.v:21-23` 明确把这件事登记为**未定**，并写了一句很硬的话：
"谁要再按『拍数 = 1.683 ns / 156 ps』推采样点，先把这条量清楚（未定，不当结论用）"。
**这就是"抽头与 ~78 ps 的非线性"的全部含义**：拍→时间不是常数，
所以任何用单一 ps/tap 反推采样点位置的推理都不能当作结论。
顺带一条与延迟线类型相关的物理事实：**IDELAY 是模拟延迟线，几乎不随工艺角缩放**，
只有 IBUF 那一段缩放 ⇒ 加更多抽头反而把慢/快角的比值压得更低
（`收口输入窗模型`）。

### 3.5 为什么这一族在 0…31 全档内关不掉（极限判据的样子）

在 W5 窗下把 `IDELAY_VALUE` 从 0 扫到 31（只读，`set_property IDELAY_VALUE` 在已布线 DCP 上有效，
readback 逐档对上 ⇒ 这一趟不花构建），两条曲线是实测直线
（`收口输入窗模型`）：

```
HOLD(带 0.800) = −2.822 + 0.0630·τ   ⇒ 要 ≥ 0 需要 τ ≥ 44.8
SETUP          = +2.005 − 0.0920·τ   ⇒ 要 ≥ 0 需要 τ ≤ 21.8
τ 的合法区间只有 0…31
```

**两个区间不相交**。带子去掉也一样（32.1 与 21.8 仍不相交）。
根因不在"点没找好"，而是**两条检查用的不是同一只钟的同一个数**：
hold 查慢角钟网络（DCD 5.008 ns）、setup 查快角（1.597 ns），
**钟网络的角间差 3.411 ns 远大于数据路径的角间差 0.467 ns**
（`收口输入窗模型`）。
写成联合门槛就是：带子保留要 `D_slow/D_fast ≥ 1.73`，去掉要 ≥ 1.45，
而实测 3.613/3.146 = **1.15**，两个门槛都够不着（同页 `:336-338`）。

这里要分清两件事：**"我没找到好点"与"可行区间为空"是两种完全不同的结论。**
前者下轮还要花钱试，后者可以停止花钱。这份不等式就是提示词 §7 那条"极限判据"第一次被真正满足的地方
（`收口输入窗模型`）。

还有一层，很多讲法会漏：**报告最优点不等于硅片眼心**。真实硅片只活在一个角上，
把物理条件单独写一遍（`C` = 钟网络到 IDDR C 脚的延迟，`D = 1.976 + 0.0630τ`，
`Ts ∈ [1.2, 2.8]` = PHY 提前量），采对沿的充要条件是 `|C − D| ≤ 1.2 ns`；
而工具的角包络 `C ∈ [1.597, 5.008]` 宽 **3.41 ns > 2.4 ns** ⇒ 任何 τ 都盖不全
（`收口输入窗模型` 与 `:414-422` 那张覆盖表）。
按这个度量 τ=21 与 26 覆盖 70 %，**τ=31 只有 67 %**。
所以本项目的现行出货值（`src/rtl/top/system_top.v:172` 的 `.IDELAY_VALUE(31)`）
是**"报告最好"而不是"硅片最好"**，这一点写在
`收口输入窗模型`，采纳条件与回退条件写在 `:428-432`，
而那条 `bad=0` **至今没有闭合**（同一件里 `pkt_err=?`/`frames_bad=?`）。
最后一刀必须落在板上：`IDELAY_TYPE="FIXED"`（`src/rtl/eth/rgmii_rx.v:68`）⇒
运行时改不了抽头，一次位流只有一个 τ；想真量眼心得先把它换成 `VAR_LOAD` 或加一条写通路。
**这类"结构上没有出口"的判断，比任何 slack 数字都值钱。**

---

## 4. AXI4-Lite vs AXI4-Full、HP0、以及 PS/PL 之间的两条内存通路

### 4.1 这个设计里有两条完全不同的 AXI 路

| 通路 | 方向 | 协议形态 | 用途 | 在 BD 里的位置 |
|---|---|---|---|---|
| `M_AXI_GP0` | PS → PL | **AXI4-Lite**（无 ID、无突发、一次一个 transfer） | 控制/状态寄存器 | 经 `axi_gp0_ic` 扇出 3 个 `axi_gpio` |
| `S_AXI_HP0` | PL → PS(→DDR) | **AXI4-Full，但在 PS 侧降级为 AXI3** | 帧数据搬运 | `axi_mem_intercon` 唯一一条 M00 |

BD 里两者的声明分别是 `CONFIG.PCW_USE_M_AXI_GP0 {1}` 与
`CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64}`
（`build/tcl/build_system_axigpio.tcl:99` 与 `:100`），
互连规模是 `NUM_MI {3}` 与 `NUM_MI {1}/NUM_SI {1}`（`:157-160`），
连接在 `:190-199`，`make_bd_intf_pins_external` + 改名把 PL 侧那个主口叫成 `M_AXI_HP0`
（`:201-204`）。

**Lite 与 Full 的差别在本项目里不是教材条目，是两条不同的失效模式。**
GP0 挂的是寄存器：写错没反应、位序错读回来是另一个数；
HP0 挂的是数据流：握手协议细节直接决定吞吐（下面 §4.3）。

### 4.2 HP0 在这颗器件上是 **AXI3**：一次截位差就要在顶层显式写出来

AXI4 的 `AxLEN` 是 8 位（最长 256 拍），AXI3 是 4 位（最长 16 拍）。
PS 的 HP 口是 AXI3，所以顶层必须**自己把宽度砍下来**：

```
wire [7:0]  m_awlen;                 // 内部 8 位（AXI4 形状）
wire [3:0]  m_awlen_axi3 = m_awlen[3:0];   // 送进 HP0 之前截成 4 位   —— src/rtl/top/system_top.v:73
wire [5:0]  m_arid;  wire [3:0] m_arlen_axi3;  ...                  // 读侧同理
assign m_arlen_axi3 = m_arlen8[3:0];                               // —— src/rtl/top/system_top.v:106
```

`src/rtl/top/system_top.v:73` 与 `:106` 那两行截位就是"跨协议版本适配"的落点。
配套的边界条件在读口：`m_axi_arlen` 声明为 8 位，但实际最大只发到
`8'd15`（`src/rtl/axi/axi_frame_writer_gated.v:105`、`:132`、`:150` 三处 `BEATS[7:0]-8'd1`）
⇒ **设计者自己知道只有 4 位能用**。读这一族文件时，"端口宽度"和"实际取值范围"要分开看：
前者是形状，后者才是协议约束。
`src/rtl/eth/axi_frame_saver64.v:40-42` 把写侧的 `AWLEN` 钉成 `8'd0`（单拍写）、`AWSIZE=3'b011`（8 字节）、
`AWBURST=2'b01`（INCR），这是另一条设计选择：**入包链不做突发，做流水**（见下节）。

还有一条只存在于 Zynq-7000 的细节：HP 口的 `ARCACHE/AWCACHE` 被硬编成 `4'b0011`
（`src/rtl/top/system_top.v:89-94`），`ARLOCK/AWLOCK` 钉 `2'b00`，
`BID/BRESP` 直接悬空不接（`:99`）。**悬空不是遗漏，是"我不处理异常响应"这个决定的物证**，
它和 §4.5 的缓存问题合起来构成"PS 与 PL 共享同一块 DDR"的全部风险面。

### 4.3 吞吐由**在途事务数**决定，不由缓冲深度决定

这是本项目最大的一次性能根因，值得把它的算术记住。
早期版本每字走完 `S_AW→S_W→S_B`，**在途深度恒 1** ⇒ HP0 的写延迟（约 40 拍，
被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈20 MB/s ⇒ 板上现象是
"每包固定从第 48 字节起丢字"（`src/rtl/eth/axi_frame_saver64.v:5-6`，ISSUES #31）。

反直觉的第二半：**加深缓冲治不了它**（`src/rtl/eth/axi_frame_saver64.v:7`，ISSUES #32）——
"瓶颈是平均排空速率不是深度，v6.2 把 CDC 做到 8192 时上板毫无改善"。
真正的解法是**写通道流水化**：AW/W 并行挂出、各自握手，发完立刻取下一个字
（`src/rtl/eth/axi_frame_saver64.v:2-3`），在途上限 `localparam [3:0] OST = 4'd8`
（`:66`，注释就写着"够盖住 HP0 写延迟"），而 **B 通道永不反压**：
`m_axi_bready <= 1'b1` 只回收计数（`:156`）。

这里的 Little 定律形状是通用的：吞吐 ≈ 在途字节数 ÷ 往返延迟。
深度只吸收突发，**不改变平均速率**；改速率只有两条路——加大在途、或缩短单拍周期。

一条工程细节值得抄进自己的清单：`outst` 计数器**只减不回绕**
（`src/rtl/eth/axi_frame_saver64.v:158-160`）。
理由写在注释里——上游偶尔多回一个 B，回绕成 15 会让 `have` 永远不成立，
整条入包链就此卡死 = 板上"冻结"类症状。**宁可少计，不可锁死。**

### 4.4 写选通：分包长度不敏感是靠 `wstrb` 换来的

`m_axi_wstrb` 不是恒 `8'hFF`，而是按 16 bit lane 从 `keep_r` 展开（
`src/rtl/eth/axi_frame_saver64.v:83-84`）。原因是一段很具体的坏味道：
旧实现恒全 1，于是"同一个 64 bit 字被相邻两包分两次写"时后一次会把前一次的半字**覆盖成 0**；
分包长度不是 8 的倍数（例如 1396）时每帧 111 处 = **222 个 16 bit 黑洞**，
屏上表现为均匀散布的黑点（`src/rtl/eth/axi_frame_saver64.v:80-82`）。
**症状（屏上黑点）与原因（wstrb 语义）隔了整整三层抽象**，
这一条是"读寄存器/总线语义要读到位"的证据。

### 4.5 通路之外的第三件事：缓存一致性

PL 走 HP0 直接落 DDR，**不经过 APU 的 cache**；PS 写帧数据时写的是自己的 cache。
所以 PS 侧写完必须显式刷，否则 PL 读到的是旧内容：
`Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)`
（`src/ps/main.c:706`，同一个函数 `src/ps/main.c:691-708` 里先逐像素写再刷再发布）。

`FRAME_ADDR = 0x10100000u`（`src/ps/main.c:46`）与 RTL 侧的
`localparam [31:0] PS_DDR_BASE = 32'h1010_0000`（`src/rtl/top/system_top.v:144`）
是**同一个地址写在两个语言里**，两处必须一致。

### 4.6 地址是这套代码的"第二套类型系统"

三个 GPIO 的基址在构建脚本里钉死并**回读校验**：
`0x41200000 / 0x41210000 / 0x41220000`（`build/tcl/build_system_axigpio.tcl:243-251`），
固件里也是硬编码（`src/ps/main.c:48` 的 `AXI_GPIO_BASE`、`:77` 的 `AXI_GPIO_CFG_BASE`）。
为什么必须钉：BSP 不会重新生成 `xparameters.h`，**地址一挪，现象不是编译失败而是"写了没反应"**
（`build/tcl/build_system_axigpio.tcl:240-242` 原话）。
这是最难查的一类 bug，而它没有任何编译器或工具会替你挡——只能靠构建脚本里的回读。

DDR 侧同理：ETH 用 `0x1000_0000` 与 `0x1008_0000` 乒乓两 bank（每帧 300 KB），
PS 专用第三个 bank 从 `0x1010_0000` 起（`src/rtl/top/system_top.v:140-144`）。
仲裁只管"谁用搬运机"，**管不到谁写 DDR**（SD 的 DMA 走 PS 的 HP0、不经过 PL）
⇒ 两路同时跑时重叠只能靠地址分开（同文件 `:141-143`，也写在
`src/rtl/top/pl_video_top.v` 的 `PS_BASE_ADDR` 注释里）。

---

## 5. CDC 的三种合法形态，以及 Vivado 怎么查它们

`src/constraints/clock_groups_impl.xdc:19-23` 那段是全仓对 CDC 最凝练的一句话：
**"跨域数据由结构保证，不靠时序分析"**，然后把四个跨域方向各自的形态列出来。
下面把三种合法形态讲清楚，每种都指到本项目的实例。

先说**为什么异步组不能替代结构**：`set_clock_groups -asynchronous` 只是告诉工具
"别分析这两个域之间的路径"（`src/constraints/clock_groups_impl.xdc:28-31`）。
它让时序报告变绿，**不让亚稳态消失**。所以真正要审的是结构，报告只是辅助。

### 5.1 形态一：翻转位 + N 级同步（单事件/握手家族）

用于"发生了一件事"这种单 bit 事件。做法：源域把事件转成**电平的翻转**（不是脉冲），
目的域同步两到三级再取边沿。本项目的实例：
`src/rtl/eth/ddr_bank_commit.v:37-41` 的 `frame_done_tog`（gmii 域）+
`:42-47` 的 `(* ASYNC_REG = "TRUE" *) reg fd0, fd1, fd2` 与 `fd_axi = fd1 ^ fd2`。

为什么必须是翻转而不是脉冲：**脉冲宽度可能小于目的域一个周期**，
同步链会整个吞掉它；翻转位是电平，永远不会丢，只需要付"晚几拍到"的代价。

握手形态在 PS 发布路径上：`src/rtl/util/ps_publish.v:3` 写得很直白——
"这段逻辑本身是一个异步握手（翻转位来自 `axi_clk` 域，消费在 `clk_pix` 域）"，
同步链就是 `:18` 那三颗 `ASYNC_REG`。
本项目的规矩（`架构章` 与 `pl_video_top.v` 的文件内注释）是：
**新增一个跨域信号，优先并进已有的链**，不新开一组同步器。
理由不是省 FF，是 `cdc.rpt` 的"源→目的配对集合"会按配对增长（见 §5.5）。

### 5.2 形态二：格雷码指针（双口 FIFO）

多 bit 计数值**永远不跨域**，跨出去的只有格雷码版本——相邻计数值只有一位变化，
所以"部分更新"这个状态在物理上不存在。实例：`src/rtl/eth/dc_fifo.v`
（`(* ASYNC_REG = "TRUE" *) reg wgray_s0, wgray_s1, rgray_s0, rgray_s1` 在 `:27`，
两条同步链在 `:82-95`，二进制指针 `:50-57`/`:70-79` 绝不跨域）。
满/空判据用的是"对端格雷码的最高两位取反、其余相等"这一式
（`:47` 的 `wr_full`、`:68` 的 `rd_empty`），省掉一次二进制比较。

这里还藏着一个**性能与结构耦合**的实例，值得记：
`src/rtl/eth/dc_fifo.v:40-44` 记的是 #105 那一刀——满判据原本用"**下一个**写指针 `wgray_n`"，
把 14 位加法 + 二进制转格雷 + 比较整条锥体挂在了 `wr_en → ENARDEN` 上（8 级逻辑），
改成用"**当前** `wgray`" 之后锥体只剩比较，副作用是可用深度从 `DEPTH−1` 变成 `DEPTH`。
**改的是判据里的一拍提前量，收益是逻辑级数**——这类"看起来等价"的微调
必须配一台能量深度的台架（它由 `sim/tb_cdc_capacity` 的 C1 钉住）。

同一段还留了一条负结果：给 `wr_full` 加 `max_fanout=12` 想复制高扇出缓冲，
结果 WNS 从 −0.062 掉到 −0.192、失败端点 28→34 ⇒ **扇出不是瓶颈**
（`src/rtl/eth/dc_fifo.v:37-39`）。**负结果要留在代码旁边，否则下一个人还会再花一次构建。**

本项目最深的一只 CDC FIFO 是 `dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc`
（`src/rtl/eth/eth_udp_video_top.v:298`）= 8192 项 × 36 bit，存储声明成
`(* ram_style = "block" *)`（`src/rtl/eth/dc_fifo.v:20`）⇒ 它是 BRAM 的主要去向之一。

### 5.3 形态三：准静态总线 + 跳变沿（"影子值"）

宽总线不能一次安全跨域（**19 位各自打两拍 ⇒ 读到半新一半旧**，
`src/rtl/top/pl_video_top.v:649` 就是这么写对照的）。合法做法只有一种形状：
**总线在源域整拍写好、保持足够长时间不变（准静态），另发一个翻转位当"值有效"的沿，
目的域在同步过的沿上再采一次。**

本项目的实现是 `src/rtl/eth/snap_cross.v`：`(* ASYNC_REG *) reg [2:0] ts/hs` 在 `:36-37`，
`bus_edge = ts[2] ^ ts[1]` 在 `:45`，采样动作在 `:69-72`。
它为什么安全的论证就写在文件头（`src/rtl/eth/snap_cross.v:3-5`）：
**边沿要 3 级同步才到目的域，而源总线至少保持到下一次写入（本项目 ≥1 ms），
所以采到的一定是完整值。** "准静态"不是形容词，是一个可核对的时间不等式。

那条 19 位的几何控制字走的就是这一条链：`split_ctl[18:0]` 声明在
`src/rtl/top/pl_video_top.v:52` 附近，注释 `:52-53` 同时给出两条禁令——
**不并进 `effect_ctrl` 那条现成的链**（加宽会让 `cdc.rpt` 的 unsafe 端点按位长涨），
**也不开第二条 `snap_cross`**（多一对 bus/toggle 同步器 = CDC-11 的签名）。

另一族更简单的形态是"单 bit 准静态电平 ⇒ 同步后直接当电平用，不需要握手"，
这句话的原文在 `src/rtl/eth/eth_udp_video_top.v:276-277`（`copy_hold`，
"它是准静态控制位、不是脉冲"）。**分清"电平"与"事件"是选形态的第一步**：
电平可以慢一拍到，事件不能丢。

### 5.4 三种形态的**共同前提**（违反它就有名字）

- 前提一：**目的域第一、第二级 FF 不能被工具搬走**。这就是 `ASYNC_REG` 的用途。
  `src/rtl/eth/dc_fifo.v:23-26` 把理由写全了：不打属性工具可以挪位、复制、
  甚至把它们拆到不同区域，亚稳态传播窗口就没保证（`report_methodology` 的 TIMING-10
  就是冲这个来的）。当前 `report_methodology` 里确实还剩
  `TIMING-10 Warning Missing property on synchronizer | 1`
  （`build/methodology.rpt:35`），1 条不是"没有"，是要认的那一格。
- 前提二：**同步器之前不许有组合逻辑**。违反了就是 **CDC-10**
  ("Combinational logic detected before a synchronizer")，
  当前件里这一类还有 3 条（`build/cdc_details.rpt:23`）。
  本项目的真实标本：`link_active = |s_pkts[15:0]` 这根**组合或缩**被像素域三级链采样，
  从建仓起就在，只是报告一直不说（`问题清单` 与 `:683`）。
  修法是**在源头各寄存一拍**，代价 1 个 FF 与晚一拍（`开发台账` 附近）。
- 前提三：**一个发射 FF 不许扇出到两组目的域同步器**。这一族的签名仓库里叫 **CDC-11**
  ("Fan-out from launch flop to destination clock")。
  如实说明：**当前盘上的 `build/cdc_details.rpt` 规则表里没有 CDC-11 这一行**
  （`build/cdc_details.rpt:17-25` 只列 CDC-1/2/3/5/6/7/10/13/15，`grep -c "CDC-11"` = 0）；
  它的两次红是在 **r54 构建 #34** 那次，记在 `开发台账` 与
  `:2980`。所以这一条的正确读法是"**曾经出现过、因此被立成规矩**"，
  不是"当前报告里有"。规矩落成：`z_hb_tog` 这类心跳位要单独建一级，
  不许共用别人的发射 FF（`开发台账`、`:5062`）。
- 前提四（最容易忘）：**声明了初值不等于复位有效**。`src/rtl/eth/snap_cross.v:20-28` 记的是
  一整颗"死复位下的上电值"问题：`pl_demo_top` 那棵树把 `sys_rst_n` 绑成常量 `1'b1`
  ⇒ `if (!dst_rst_n)` 分支永远走不到 ⇒ 上电值**只由位流里的 INIT 承载**。
  这一处对现役位流是无感的（`pl_demo_top` 不在当前位流里），
  文件里也因此明写"不能拿来当收益讲"。**"件存在"与"件在生效的路径上"是两件事。**

### 5.5 `report_cdc` 的口径怎么念

当前 `build/cdc.rpt` 的表格（`:15-25`）九行，两行 Critical：

```
Critical  clk_fpga_0 → clkout0_1  Endpoints 103   Safe 102  Unsafe 1  Unknown 0  No ASYNC_REG 2
Critical  sys_clk    → eth_rxc    Endpoints 1968  Safe 1436 Unsafe 2 Unknown 530 No ASYNC_REG 0
```

四个计数列的含义要分清，否则会把报告念成结论：

- **Endpoints** 是**端点数**，不是"信号数"，也不是"错误数"。1968 个端点里 1436 个被判 Safe 是正常形状。
- **Unsafe** 才是"结构可疑"的那一格（本项目剩 1 + 2）。
- **Unknown** 是"工具认不出这是哪种 CDC 结构"——**它既不是好也不是坏**，
  sys_clk→eth_rxc 那 530 个 Unknown 就是本项目最大的未解释格，念的时候不许省。
- **No ASYNC_REG** 是"跨域但没打属性"，2 那一格正是 TIMING-10 的同族。

门禁这一项的判据不是"数字变小"，而是"**与基线的行集合比，配对不新增、unsafe 不增长**"
（`build/gates.sh:101`）。为什么要这么写，代码注释里给了实录：
原来那版写死"4 行以内算过"，我加了一对同步器使 Critical 从 3 行变 4 行，
**脚本照样打印 PASS** ⇒ 门禁把自己要挡的东西漏掉了（`build/gates.sh:102-106`）。
还有一条同样重要的自律：**条数变少也不算改进**——少了的原因没查清之前只报出来不记账。
（另外注意 `cdc_details.rpt` 与 `cdc.rpt` 是两次不同时间的运行：前者头部
`Date : Fri Sep 25 23:00:12 2026`，`build/cdc_details.rpt:4`。
**两份不同版本同名报告并存在仓里，引用时必须点文件名。**）

### 5.6 CDC-10/CDC-11 之外，"查 CDC"的射程边界

三条边界，都得记住：

1. 异步时钟组一旦被声明，这些路径**根本不做时序分析**（Exceptions 列写着 `Asynch Clock Groups`）。
   工具不再替你判跨域对不对 ⇒ 结构错了报告也不响。
2. `report_cdc` 只看**结构形状**，不看功能语义。格雷码总线写成二进制但恰好同步了，
   它也可能报 Safe；反过来，一套完全正确的准静态快照可能被报 Unknown。
3. 真正能判"数据到底有没有撕"的只有台架与板级读数：`eth_rxc → clk_fpga_0` 那条链的裁判是
   1000M 实流量的 `bad`/`drop_words`（`src/constraints/r116_rgmii_input_window.xdc` 与
   `极限核对` 两侧都写这句话）。

---

## 6. LUTRAM vs BRAM：512×100 位打包器为什么必须落在 LUTRAM 上

### 6.1 一个数组只有三种物理落点，代价完全不同

| 落点 | 来源 | 典型代价 |
|---|---|---|
| 触发器（FDRE） | 综合器拒绝/无法推断成 RAM | 每 bit 一只 FF，**位宽×深度**直接进 Slice Registers |
| 分布式 RAM（LUTRAM） | 需要**异步读口**（组合读出） | 吃 LUT；深度越大越贵；读口无寄存 ⇒ 影响时序预算 |
| BRAM | 需要同步读口 + `ram_style="block"` | 吃整块 tile，粒度粗；读口固定 1 拍延迟 |

这三行不是并列选项：**读口是异步还是同步，决定了你能不能选 LUTRAM**，
而选了 LUTRAM 就顺手决定了流水线的拍数（见 §6.3）。

### 6.2 本项目的打包器：512 × 100 bit 的 LUTRAM

`src/rtl/eth/axi_frame_saver64.v` 里那三个数组就是它：

```
parameter FW = 9                                   // 512 项
(* ram_style = "distributed" *) reg [31:0] q_addr [0:(1<<FW)-1];
(* ram_style = "distributed" *) reg [63:0] q_data [0:(1<<FW)-1];
(* ram_style = "distributed" *) reg [3:0]  q_keep [0:(1<<FW)-1];
```

32 + 64 + 4 = **100 bit/项 × 512 项 = 51 200 bit**
（`src/rtl/eth/axi_frame_saver64.v:10` 是 `FW=9`，`:48-50` 是三个数组）。
异步读口是明写的：`:55-58` 用 `ridx = rptr[FW-1:0]` 直接组合读出三路。

为什么不用 BRAM、也不用触发器，注释里是一条**实测过的对照表**：
早先版本让它被综合成触发器，512×100 bit ≈ 5.1 万 FDRE，
**占整机 Slice Register 的 94 %**，`FW=11` 直接 DRC UTLZ-1
（`src/rtl/eth/axi_frame_saver64.v:10-13`）。
改成显式 `distributed` 之后，`:46-47` 记的是"512×100bit 只要 ~800 个 LUT-RAM"。

**还有一条只有 Vivado 用户会踩的坑，值得单独抄走**：存储写的 always 块
**必须独占、且不带异步复位**。写成 task + 和指针同在异步复位块里时，
Vivado 报 `Synth 8-7186` 拒绝把数组推断成 RAM，512×64 bit 退化成 **3.29 万个 FDRE**；
对照实测：task 写法 FF=32904 / LUTRAM=0，现写法 FF=85 / LUTRAM=864
（`src/rtl/eth/axi_frame_saver64.v:104-107`，落点在 `:108-114` 那个 `always @(posedge clk)`）。
"这不是风格问题"是原话——**同一份功能语义，写法不同就差三万多个触发器**。

### 6.3 这条选择怎么一路影响到显示链

`src/rtl/process/proc_pipeline.v:21`：级 0 的 gamma 是**分布式 RAM 组合读出 ⇒ 不占拍**，
所以 `LATENCY = 15`；同一行后面跟着警告——
"谁改成寄存读出（BRAM 风格）LATENCY 必须同时改成 16"。
这条链一直传到混色级的延迟账：`src/rtl/top/pl_video_top.v:354` 的
`localparam MIX_D = 3 + 1 + 1 + u_pipe.LATENCY;`（**直接取模块参数，不在顶层重写数字**，
理由与对账台架写在 `:812-815`）。

于是：**"gamma 表用 LUTRAM 还是 BRAM"这个选择，改变的是流水线拍数、
显示与处理链的对齐，以及一个 localparam 的表达式。** 资源与正确性不是两件事。

### 6.4 全局账：怎么读资源报告里的存储行

当前件（`build/utilization.rpt`）：

```
:35  Slice LUTs                 14154 / 53200   26.61 %
:37  LUT as Memory               4185 / 17400   24.05 %
:38    LUT as Distributed RAM    4044
:39    LUT as Shift Register      141
:40  Slice Registers             8188 / 106400   7.70 %
:106 Block RAM Tile              95.5 / 140     68.21 %
:107   RAMB36/FIFO*                93 / 140     66.43 %
:109   RAMB18                       5 / 280      1.79 %
```

**两条口径红线**（`build/README.md` 第三节末尾写得很硬）：
`RAMB36/FIFO*` 的**单元数**与 `Block RAM Tile` 的**瓦片数**不是同一个数，引用要分清
（一个 36 K tile 可以装两只 18 K，所以 95.5 与 93 都对，但含义不同）；
`Slice LUTs` 这一行**已经是 Logic + Memory 之和**（`build/gates.sh:88` 的注释）。

再补一条：报告里那行 `Warning! LUT value is adjusted to account for LUT combining`
（`build/utilization.rpt:47`）意思是**LUT 数被综合器的合并调整过**，
拿它去和 RTL 里的"应有 LUT 数"逐项相减会得到不闭合的账——
本项目做资源归因时用的是逐层件相减，不是这一行
（`data/metrics.csv` 的 "Slice LUT 占用" 那一行就写着这套归因）。

还有一条工具口径值得单独记：`report_methodology` 里有
`SYNTH-5 Mapped onto distributed RAM because of timing constraints | 336` 与
`SYNTH-6 Timing of a RAM block might be sub-optimal | 98`
（`build/methodology.rpt:32-33`）。
前者的意思是"**工具为了时序主动把 RAM 放到分布式**"——
这既可能是我们要求它这么放（`ram_style` 显式声明），也可能不是。
**分不清这两类的情况下，不要把 336 念成"336 个问题"。**

（另注：7 系列**没有 URAM**，这条在本仓库是量过的结论而不是常识，
探针 `build/tcl/uram_presence.tcl` 与 `build/tcl/uram_sites.tcl`，
结论写在 `build/tcl/README.md:53-55`。）

---

## 7. 时序收敛的词汇表：每个词都配一条本项目里的读数

### 7.1 两把尺子：setup 与 hold，同一个数在两个角上

| 检查 | 问的问题 | 数据路径取哪个角 | 时钟路径取哪个角 |
|---|---|---|---|
| Setup (Max) | 最慢的硅片上，数据来得及吗 | **慢** | 对 setup 不利的角 |
| Hold (Min) | 最快的硅片上，数据别被下一个沿冲掉 | **快** | 对 hold 不利的角 |

报告里那两行标题就是答案：`Setup (Max at Slow Process Corner)`、
`Hold (Min at Fast Process Corner)`（`build/timing_summary.rpt:235` 与 `:295`）。
本项目内部路径是**教科书方向**；但 **I/O 那 5 格的角分配是相反的**（hold 用慢钟、setup 用快钟），
表与解读在 `收口输入窗模型`：
"源同步收口该有的保守方向"，把钟放在对该检查最不利的角，数据那一侧用同角的值。
把"真正最坏"自己算一遍的结论是：**工具读数已经比真实最坏宽松 ~0.4–0.5 ns，仍然是负的**
（`收口输入窗模型`）。
**这句话是"报告不会替你想"的最好例子。**

### 7.2 WNS / WHS / TNS / 失败端点

| 词 | 含义 | 当前全局读数（`build/timing_summary.rpt:151`） |
|---|---|---|
| WNS | Worst Negative Slack，最差那条的裕量 | **0.739 ns** |
| TNS | Total Negative Slack，所有违例之和 | 0.000 ns |
| TNS Failing Endpoints | 违例端点数 | 0（总端点 **51135**） |
| WHS | Worst Hold Slack | **0.052 ns** |
| THS / THS Failing Endpoints | hold 违例和 / 端点数 | 0.000 / 0 |
| WPWS | Worst Pulse Width Slack（脉宽够不够） | 0.264 ns，失败 0 / 12634 |

**WNS 与 TNS 要一起看**：WNS 告诉你最坏一条离零多远，TNS 告诉你一共欠了多少。
本项目历史上有一次 WNS 只差 0.06 ns 而失败端点 34 个，
那种形状靠砍一条逻辑是修不掉的（`src/rtl/eth/dc_fifo.v:37-39` 记的正是这一类）。
端点数才是"这是一条孤例还是一族问题"的分界。

逐域读才有意义（`开发流水账:5-13`，A 列 = 冻结基线）：

| 域 | 周期 ns | setup WNS | hold WHS | 相对余量 | 端点 |
|---|---|---|---|---|---|
| `sys_clk` | 20 | 14.876 | 0.222 | 74.4 % | 323 |
| `clk_fpga_0` | 10 | 1.850 | 0.053 | 18.5 % | 15721 |
| `clkout0_1` | 20 | 3.630 | 0.059 | 18.2 % | 30179 |
| `eth_rxc` | 8 | **0.739** | **0.052** | **9.2 %** | 4835 |

相对余量的定义写死在名册头部：`rel_margin_* = wns_* / period_ns`
（`开发流水账:3`）。
**为什么必须除以周期**：0.739 ns 在 8 ns 域上是 9.2 %（真紧），
在 20 ns 域上是 3.7 %（其实很松）。绝对 ns 会骗人，相对余量不会。
同一把 B 列（绑上 RGMII 输入窗那一版）在 `eth_rxc` 上给
`b_wns_setup=-0.846 / b_wns_hold=-0.870 / 失败端点各 5`，判定 `RED`
（`开发流水账:12`）——这就是第 3 节那次窗实验的读数落点。

### 7.3 逻辑级数与布线占比：本项目的两条真实路径

**路径 A（`clk_fpga_0` 最差 setup，`build/timing_summary.rpt:227-243`）：**

```
u_pl/u_arb/owner_eth_reg/C → u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]
Requirement 10.000ns;  Data Path Delay 7.544ns (logic 0.484 (6.4 %)  route 7.060 (93.6 %))
Logic Levels: 1 (LUT6=1)
中间那一根：net (fo=269, routed) 6.576ns   u_pl/u_row/hi_reg_0[0]
终点是 RAMB36E1
```

**一级逻辑、93.6 % 全是布线、其中 6.576 ns 落在一根高扇出广播网上**
（`build/timing_summary.rpt:260` 那行 `net (fo=269, routed) 6.576`）。
这一行的意思：这不是"器件慢"，也不是"逻辑深"，是**扇出 + 跨片布线**。
根因标签在本仓库被明确写成 `FANOUT` 而不是 `PLACE`
（`极限核对`、`:34`）。
**同一根网上有一个未对账的口径差，这里如实登记**：`极限核对` 的散文写"239 引脚"，
而它引用的报告行与钩子文件抄的都写 `fo=269`（`build/tcl/r117_post_place_hook.tcl:15` 引的是
`net (fo=269, routed) 5.690`），当前件里那一行是 `fo=269 … 6.576`
（`build/timing_summary.rpt:260`）。⇒ **引脚数 269 有两件相撑，"239" 只有一处散文；
线上延迟 5.690 与 6.576 分属两次构建，本来就不该相等。**
念这一族数的时候：先分"报告行"与"散文复述"，再分版本。

**路径 B（`eth_rxc` 最差 setup，`build/timing_summary.rpt:365-377`）：**

```
u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C → .../check_buffer_reg[19]/D
Requirement 8.000ns;  Data Path Delay 7.066ns (logic 2.936 (41.6 %)  route 4.130 (58.4 %))
Logic Levels: 11 (CARRY4=6 LUT3=2 LUT4=2 LUT5=1)
```

**11 级里有 6 级是 CARRY4（进位链）** ⇒ 这是 IP 校验和的算术锥，
逻辑与布线五五开。同一族 10 条路径的 route 占比全在 57–60 %
（`极限核对`）⇒ **是"一族"而不是"一条"**，
这个区别决定修它是改结构还是改约束。

**为什么"级数"和"route 占比"必须成对讲**：
只有级数 → 会得出"再插一拍"的错药（插一拍要付 BRAM 读口或流水线寄存器）；
只有 route 占比 → 会得出"复制驱动"的错药（本项目 #288 量过：
机制生效了 0→296/310 颗 `_replica`、目标族 +0.456 ns，
但 `eth_rxc` hold 从 0.050 掉到 0.035 ⇒ **代价落在最紧的域上**，名册差分判负）。
"两把尺子读同一条路径"在这里变成了一句有代价的话。

### 7.4 时钟不确定度：第二把加在预算上的尺子

报告里的公式：`Clock Uncertainty: ((TSJ^2 + TIJ^2)^1/2 + DJ)/2 + PE (+ UU)`。
本项目现读的三个值：

| 域 | Uncertainty | 组成 | 位置 |
|---|---|---|---|
| `clk_fpga_0` | 0.154 ns | **TIJ = 0.300 ns**（外部输入抖动声明） | `build/timing_summary.rpt:243-247` |
| `eth_rxc` 内部 setup | 0.035 ns | TSJ 0.071，TIJ/DJ/PE 全 0 | `build/timing_summary.rpt:379-383` |
| `eth_rxc` hold | **0.800 ns** | 全是 UU（User Uncertainty） | `build/timing_summary.rpt:466-471` |

那 0.800 不是工具算出来的，是**人加上去的要求**：
`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`
（`src/constraints/rk_zynq7020.xdc:50`）。
它的来历值得看：同一族的 `eth_rxc` hold 在两个版本之间只差 1 ps（+0.001 vs +0.052）
⇒ 余量是**掷硬币掷出来的**，于是**给 hold 加 0.5 ns 要求，逼工具把余量做成设计值**，
0.5 那一档只做到 +0.051 ⇒ 再加严到 0.8（`src/constraints/rk_zynq7020.xdc:41-49`）。
**方向与"放松判据"完全相反：用约束把运气变成要求。**

三件必须知道的射程：

1. `-hold` 的那一支**不参与 setup 检查**（同文件 `:41-42` 明写），
   所以加它不会伤 WNS，只会逼布线器插缓冲。
2. **只有 `eth_rxc` 带这一行**：其余三域的报告里根本没有
   `Clock Uncertainty` 那一格（实测在 `不确定度对照`，
   统一加严后 WHS 会变成 −0.747 / 25 742 个失败端点 ⇒ **未采纳**，
   因为它会让名册的 hold 列变成两把尺子）。
3. 约束文件里 `get_clocks` 取不到的名字**会连带整条命令空转**：
   `src/constraints/rk_zynq7020.xdc:43-45` 写的是这条实测——
   把 `clk_fpga_0` 并进 `eth_rxc`/`sys_clk` 那一条命令里，
   `-quiet` 只能压住报错、压不住命令失效，**连别的组一起废掉，现场只留一句 warning**。
   这一条直接引出第 01 章要讲的"约束按生效时机拆文件"。

### 7.5 时钟路径 skew：DCD / SCD / CPR

`build/timing_summary.rpt:239-242`（路径 A）：

```
Clock Path Skew: 0.024ns (DCD - SCD + CPR)
  Destination Clock Delay (DCD): 2.384ns = (12.384 - 10.000)
  Source Clock Delay      (SCD): 2.456ns
  Clock Pessimism Removal (CPR): 0.097ns
```

四个必须内化的点：**skew 不是"两条线的差"，它已经被做过一次悲观化修正**；
公式符号（`+CPR` 与 `-CPR`）在 setup/hold 两类检查里不同；
DCD 那一行的括号是工具自己写的"到达时刻 − 周期"；
**CPR 存在的意义是去掉共享段的重复计入**（工具设定 `Pessimism Removal Resolution: Nearest Common Node`，
`build/timing_summary.rpt:22`）。
本项目 RGMII 那一族关不掉，根因就是 DCD 的两个角（5.008 / 1.597）而**不是**数据路径——
这一句在 §3.5 已经给了算式，这里只强调：**DCD/SCD 是理解"为什么两把尺子用的不是同一只钟"的钥匙。**

### 7.6 噪声底、布线占比、以及"同口径复跑"

- **噪声底是量出来的，不是假设的。** 本项目跑两次空白构建得到的
  `noise_ns = 0.000`（两空白滚的头条四数与最差路径身份逐位相同才算 0），
  出处 `时序专章` 的 §3 B4 那一格。同一天不同版之间 slack 绝对值会摆零点几 ns
  （放置运气）——`build/README.md` 第三节末尾那条"判断有没有变好要同口径复跑，不看单个 WNS"
  就是这条的操作化说法。
- **同口径 = 同一把生成器。** 名册差分要求两侧同一把尺，混口径直接 `REFUSE`
  （`时序专章` 末节的 `build/timing_roster_diff.sh` 与 `r115_roster_build.py` 分工，
  ISSUES #291/#293）。同一份数据两把尺子给不同判语是真实发生过的（#328），
  处理方式不是改宽任何一方，而是把严格判据独立成件。
- **"未测"与"通过"是两句话。** 读数的三态在仓库里是硬约定
  （`report/collaboration/corrections.md:182-183` 把它写成：退出 = 后面几层一个都没测
  = `NOT_MEASURED`，而 `NOT_MEASURED` 与"没有"是两句完全不同的话）。

---

## 8. 为什么每个数字都要点名它的报告

这一节不是流程说明，是**这套代码的推理能被反驳的前提**。理由有三起真实事故。

### 8.1 三起事故，同一类根因

`src/host/metric_recheck.mjs:5-13` 记的就是这三笔：

| 事故 | 症状 | 根因 |
|---|---|---|
| #145 | 表里写"128 条逐像素判定"，留档报告数出来是 138 | 抄完，报告又变了 |
| #138/#145 | 凭据换了一轮，表里的数还是上一轮的 | 同上 |
| 当天 | "50 MHz 显示域 +1.177 ns（12 %）" | **1.177 是对的，12 % 是拿 10 ns 去除的**；报告里 `clkout0_1` 的 `Requirement` 明写 20.000 ns ⇒ 真正是 5.9 % |

第三起的结论最值钱："**人去复核一个百分数不会发现除错周期，脚本会 ——
因为它把分母也一起从同一份报告读**"（`src/host/metric_recheck.mjs:12-13`）。

### 8.2 这把尺子的射程，故意收得很窄

`metric_recheck` **只判点名了这三份报告的行**：`timing_summary` / `utilization` / `power`
（`src/host/metric_recheck.mjs:14`）。认不出的行**算作未判并打印条数**，
不静默放过、也不冒充判据——一句原话值得背下来：
"**一条判据不许靠『没人反对』变绿**"（`src/host/metric_recheck.mjs:15`）。
判据的输入是一张表：`data/metrics.csv`（列头 `指标名称,类别,数值,单位,测量条件,测试次数或时长,证据文件`），
**"证据文件"那一列就是这个体系的落款位**。

还有一条同族的符号射程：`src/host/metric_recheck.mjs:40-45` 记的是 r116 起
slack 可能是**负**的（第一次给 RGMII 输入绑窗），而旧写法只认
`[0-9]+\.[0-9]+` ⇒ 负数读成 null，null 在这把尺子里是"判红"，
于是**文档写对了也红**。中文文档用 U+2212（−）、英文用 ASCII hyphen，两者都得吃进去，
否则 `Number('−0.846')` 是 NaN，**比读不到更难查**。
⇒ 读任何正则式判据时，第一问永远是"**它的射程覆盖几种输入**"。

### 8.3 尺子最容易没牙的三种形状（本仓库都付过学费）

1. **空结果被当成合法的 0。** `build/gates.sh` 里两处 `naa` 分支
   （`:206`、`:209`）专门为此而写：报告文件不在这套目录里 ⇒ 这一项**没门禁**，
   而不是判红也不是判绿（#164：过去空结果被当合法的 0 念成 PASS）。
2. **符号位没留，导致读不到。** `build/gates.sh:74-78`：TNS 违例时是**负数**（−6.457），
   而原式只给 WNS/WHS 留了符号位 ⇒ awk 不匹配 ⇒ 脚本打印 `FATAL 读不到` 然后 exit 2。
   停下来是对的，但它把最该看见的数字（WNS −0.482 / 19 个失败端点）
   换成了"读不到"这句话。现在的规矩是**读不到时把候选行原样打出来**。
3. **写死条数。** `build/gates.sh:13`：门禁条数**不写死**，以本文件里 `say` 的调用次数为准
   （历史上从"七项"长到 15 → 18 → 20+ 项，每长一项都对应一次踩坑）。
   第 6 项 CDC 从"4 行以内"改成"与基线行集合比"是同一个病
   （`build/gates.sh:101-106`）。

### 8.4 行号引用为什么是硬错误

`src/host/line_cite_check.mjs:25` 定义了判红的三类：
**引的文件不在树里、行号越过文件末尾、例化者列指错、逐字抄的固件回声对不上**。
容忍度是判据的**力度**而不是风格：区间引用（`:16-18`）0 行容忍，单点 ±2 行
（`src/host/line_cite_check.mjs:94-98`）。为什么这么定，注释里给了真实事故：
#122 那次错位恰好只有 3 行（16-18 ↔ 19-21），"给 ±3 就等于判不住它要判的那件事"。

而"锚点取不出来"这一类**不判红，单独列成需人看清单**（`src/host/line_cite_check.mjs:72`，判据本体在同文件 `--list-soft` / `--list-need` 那两条跑法里），
理由是"宁可少判，也不要误判成文档错了"。**这是判据设计上的克制**，
读这套工具时值得学：硬错误只留给机器能单独判定的那一类。

注意射程：它只管**代码/脚本**行号（`.v .c .h .mjs .sh .tcl .ps1`，
`src/host/line_cite_check.mjs:40`、`:48`），`.md` 之间的行号引用**故意不收**——
追加式档案（ISSUES / OVERNIGHT_LOG）里的行号是历史现场，
"把过去的记录改成迎合检查器等于销毁证据"（`src/host/line_cite_check.mjs:28-29`）。
⇒ **本文件里所有指向 `.md` 的引用都只点文件名与段落，不给行号**，
除非那行号是给人去 grep 用的锚。

路径与时效另有两把尺子：`src/host/doc_currency_check.mjs` 的三条判据
（D1 当前/默认句不许点名带编号的构建、D2 文档点名的冻结目录必须在盘上、
D3 首页那句"门禁全绿 = rNN"必须等于盘上最新且 ALL PASS 的那一套，
`:17-23`），以及 `build/checks/check_repo_consistency.mjs` 的 C1–C12。
**这三把合起来才凑成"数字—文件—时间"的闭环。**

### 8.5 一个数字的完整生命周期（把前面几节串起来）

```
RTL / 约束   ──构建──►  实现报告（build/ 那一份，会被下一次构建原地重写）
                          │
                          ├──► data/metrics.csv 的一行（必须填"证据文件"列）
                          │       └──► metric_recheck.mjs 对回 timing_summary/utilization/power
                          ├──► gates.sh 的某一项（say 调用，阈值在下一列）
                          └──► 交付文档里那句话（必须点名是哪一版构建）
```

任何一环少了"哪一版"，这句话就**不可反驳**，因此也无价值。
本项目对这件事的表述：产物要"自己带着出身"——
构建策略名、挂没挂钩子、开没开 PRPO 全部打进日志（`build/tcl/build_system_axigpio.tcl:323`、
`:333`、`:349`），这正好是第 01 章要逐段拆的内容。

---

## 9. 收工自检（能一口答上来再进第 01 章）

1. 一帧 1024×600 的垂直消隐是多少个 100 MHz 拍？显示帧缓存为什么要在这段里搬完，
   它的字数和拍数分别是什么？（`src/rtl/top/pl_video_top.v:393-394`）
2. `Tcharacter` 与 `Tbit` 在 50 MHz 档各是多少？
   0.20 `Tcharacter` 这个数是窗还是散布？
   用 `set_output_delay` 绑它会得到什么读数，那读数说明什么、不说明什么？
   （`屏侧实测记录`）
3. RGMII 的 2 ns 内部延时加在钟上还是数据上？
   为什么窗要写成 `min 1.200 / max 2.800` 而不是 ±0.500 也不是 1.000–2.600？
   （`src/constraints/r116_rgmii_input_window.xdc:11-20`、`:22-27`）
4. 为什么 `eth_rxc` 那一族在 τ=0…31 全档内关不掉？
   把两条直线和"区间不相交"那一步自己写一遍。
   τ=31 是"报告最好"还是"硅片最好"，为什么？（`收口输入窗模型`、`:414-422`）
5. HP0 在这颗器件上是 AXI3 还是 AXI4？证据是哪两行截位？
   为什么加深 CDC 缓冲到 8192 仍然没治好 20 MB/s？
   （`src/rtl/top/system_top.v:73`、`:106`，`src/rtl/eth/axi_frame_saver64.v:5-7`、`:66`）
6. CDC 的三种合法形态各自的前提是什么？
   CDC-10 和 CDC-11 分别是什么形状的结构错误？
   当前 `build/cdc_details.rpt` 的规则表里有 CDC-11 吗？（§5.4）
7. 512×100 bit 的打包器为什么必须是 LUTRAM？
   把它写成 `task` + 异步复位块会得到什么综合结果，工具报什么？
   （`src/rtl/eth/axi_frame_saver64.v:104-107`）
   gamma 表如果改成 BRAM 风格寄存读出，要同时改哪几个数？（`src/rtl/process/proc_pipeline.v:21`、`src/rtl/top/pl_video_top.v:354`）
8. `clk_fpga_0` 最差路径的逻辑级数、route 占比、以及那根高扇出网的延迟分别是多少？
   这个形状说明该动逻辑还是该动物理？动它的杠杆是什么、代价是什么？
   （`build/timing_summary.rpt:236-243`，`极限核对`）
9. `eth_rxc` 的 0.800 ns hold uncertainty 是工具算的还是人写的？
   它参与不参与 setup 检查？只有哪一域带这一格？（`src/constraints/rk_zynq7020.xdc:41-50`）
10. 你手上这个百分数的分母，是从哪份报告读的？那份报告是哪一版构建的？
    （`src/host/metric_recheck.mjs:5-15`）

答不上第 4、第 7、第 10 题的话，这套代码里最贵的三刀你会看不懂。

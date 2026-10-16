# 多源视频流多效果变换处理系统

> 器件 `xc7z020clg484-2`，工具链 Vivado / Vitis 2025.2.1，板卡 RK-ZYNQ7020-F，
> 在板位流 `system.bit`（md5 前 12 位 `cd04907e1369`）。

## 摘要

本系统以一块 Zynq-7020 SoC 为核心，把千兆网口推进来的视频流在可编程逻辑里完成协议解析、几何变换、
算法处理与同帧对照显示，直接驱动 1024×600 的 HDMI 屏，链路上没有任何逐像素的软件参与。

上位机把 512×300 的 RGB565 帧切成每包不超过 1392 字节的 UDP 报文发往 5001 端口；以太网协议栈整体做在
PL 里，PS 不承担转发。载荷由 PL 作 AXI 主设备写入 PS 侧 DDR3 的乒乓帧缓存，显示侧读回后经坐标映射
（0.25–2.00 倍八档缩放与任意角度旋转的逆映射加双线性插值）、六级效果链（九位控制字，任意组合下整链
延迟恒为 15 拍），再按一条可编程竖缝把同一帧的原图与处理图逐列混合，叠加五行 OSD 后经 TMDS 出屏。
另有 SD 卡裸帧与 PL 自绘图卡两路备源，链路静默或拔卡时自动回落，不需要复位。

实现规模：RTL 80 个文件 11,768 行，PS 裸机 2,544 行，上位机工具 29 支，模块级台架 82 支。主要结果：
51,135 个端点 setup/hold 零违例；512×300@30 fps 跑 9000 帧 / 300 s 丢帧、坏帧、重复帧均为 0，实测
29.99 fps，入流能力下界 116.7 fps；LUT 26.61 %、寄存器 7.70 %、BRAM 68.21 %、DSP48 8.64 %；整屏逐像素
判据 141 条通过 140 条，一键门禁 24 项绿 23 项，板级 105 条串口命令回归 98.2 s 全过；固化进板载 32 MB
QSPI NOR 后断电自启成立。

**关键词**：Zynq-7020；千兆以太网；RGMII；UDP 视频流；乒乓帧缓存；双线性插值；同帧对照显示；TMDS

---

## 第一部分 作品概述

### 1.1 功能与特性

系统接收上位机经千兆网口推来的 512×300 RGB565 视频流，在 PL 内完成入包、组帧与 DDR 缓存，经缩放、
旋转、效果链与同帧左右对照后驱动 1024×600 HDMI 屏。片源三路可选且能自动回落：网口 UDP 流、SD 卡预转换
帧序列、PL 自绘动态图卡。运行时特性：缩放八档加呼吸与 Fit，旋转 ±1° 步进，九位控制字逐位开关六级算法，
分割线 0–100 % 可调，OSD 五行实时显示帧率、丢帧计数、结温与当前几何参数。同一组状态可由屏、串口
（115200-8N1）与 JTAG/xsdb 三条路读回，链路上的丢帧、坏帧与帧间隔由 PL 自己数出。

### 1.2 应用领域

一类是机器人、无人机与云台载荷的图传落地显示：链路带宽与丢包随时变化，屏上计数与串口读数给出"卡住是
链路问题还是处理问题"的现场判据，不需要外接采集卡。一类是工业检测、内窥与显微的即时回看：核心需求是
同一帧里改动前后的对照，本系统的左右分屏把算法效果变成现场可调、当场可判的功能。一类是多路视频墙与
显示控制节点：乒乓缓存、单 owner 仲裁与纯逻辑协议栈是这类设备的公共底座，片源数与分辨率按同一套接口
扩展。一类是教学与实验平台：82 支可复跑台架与 24 项一键门禁使整套设计成为能动手验证的样本。

### 1.3 主要技术特点

1. **纯可编程逻辑的千兆以太网栈**：RGMII 收发、MAC、IPv4/UDP、ARP 与 ICMP 应答全在 PL 内，推流占满
   通道时板子仍可 ping 通。
2. **收口采样窗可算可扫**：`IDELAYE2` 全档扫描下 hold 每档约 +63 ps、setup 约 −92 ps，交点 31.1 取 31。
3. **DDR 乒乓缓存与单 owner 仲裁**：三路源共用 bank0，owner 变化经三级同步送写侧，拔线拔卡自动换源可插回。
4. **几何共用一套坐标算子**：适配系数 3 颗 DSP、逐像素映射 8 颗、双线性 6 颗；倍率与来源可机读回读。
5. **固定延迟效果链**：六级算法任意组合下延迟恒 15 拍、内容偏移恒 −4 行，对外只有一个 `LATENCY`。
6. **跨时钟域按器件钉住**：5 个时钟域、4 处跨域点，一律三级同步加 `ASYNC_REG`，格雷码指针单独约束。
7. **零违例与可复现**：51,135 端点零违例，一键门禁 24 项，整屏台架约 108 分钟，QSPI 固化断电自启。

### 1.4 主要性能指标

下表只列已量到的项，读数取自同一次构建的报告与实测留档。

| 指标 | 数值 | 条件 |
| --- | --- | --- |
| 器件 / 工具链 | `xc7z020clg484-2` / Vivado·Vitis 2025.2.1 | 速度等级 2 |
| 显示输出 | 1024×600 @ 59.5 Hz | 像素钟 50 MHz，H_TOTAL 1344，V_TOTAL 625 |
| 入流格式 | 512×300 RGB565，UDP 端口 5001 | 每包 ≤1392 字节，307,200 字节/帧 |
| 入流零丢包 | 0 丢帧 / 0 坏帧 / 0 重复帧 | 限速 15 MB/s，600 帧一轮；300 s / 9000 帧长跑 |
| 入流帧率与间隔 | 29.99 fps，平均 33.34 ms（min 20 / max 51） | PL 收包链相邻两帧之间隔 |
| 入流能力下界 | ≥116.7 fps 不丢字 | 不限速，目标 120 fps，960 帧 |
| SD 播放 | 29.8–30.0 fps | 预转换 RGB565，板上不解码 |
| 缩放 / 旋转 | 0.25–2.00 倍八档 + 呼吸 + Fit / ±1° 步进 | 双线性可关，回读可机读 |
| 效果链延迟 | 15 拍，内容偏移 −4 行 | 九位控制字任意组合 |
| 时序裕量 | `eth_rxc` 0.739 ns / `clk_pix` 3.630 / `clk_fpga_0` 1.850 / `sys_clk` 14.876 ns | 失败端点 0 / 51,135 |
| 资源占用 | LUT 14,154（26.61 %）、FF 8,188（7.70 %）、BRAM 95.5/140（68.21 %）、DSP48 19/220（8.64 %） | 实现后报告 |
| 功耗与结温 | 动态 2.213 W（工具估算，置信度 Low）；结温 61.2–61.7 ℃（板读 XADC 六次极值） | 满载演示态 |
| 构建时间 | 全流程 19 分 30 秒（综合 10 分 09 秒 + 实现含出位流 7 分 22 秒） | Vivado 批模式 |

### 1.5 主要创新点

1. **同一帧内的左右对照显示**：按列号逐像素在"原图"与"处理图"之间实时切换，缝位置是运行时参数，算法效果当场对照得出来，不接采集卡、不录屏。
2. **几何与效果链共用一套坐标与延迟契约**：缩放、旋转、双线性共用同一组 DSP 坐标算子；效果链在任意算法组合下延迟恒为 15 拍，叠加算法时读口调度不必重算。
3. **让硬件自己数自己的账**：丢帧、坏帧、帧间隔、结温与几何参数由 PL 计数并叠在屏上，串口与 JTAG 同源可读，链路判断不依赖肉眼。

### 1.6 设计流程

先按"每像素 20 ns 预算"做软硬件划分——50 MHz 像素率下任何逐像素操作进软件都掉帧，于是协议、几何、
算法、混合全落 PL，事务性的文件系统、命令与采样落 PS。再自底向上写模块并配一支台架（共 82 支），集成后
按域逐个量关键路径、把被实测否掉的优化回退。之后上板做 36 行人眼验收与 105 条串口命令回归，固化进 QSPI
验证断电自启，最后用 24 项一键门禁与整屏逐像素台架锁定结论。

![图1 系统整体框图](figures/contest/fig1-system.png)

---

## 第二部分 系统组成及功能说明

### 2.1 整体介绍

系统由片外四部分（上位机、板载 PHY、DDR3 颗粒、HDMI 屏）、芯片内五只主要实例和一份 PS 裸机固件组成。

| 实例 | 模块 | 时钟域 | 职责 |
| --- | --- | --- | --- |
| `u_bd` | `design_1_wrapper`（PS7 + AXI 互连 + 三路 AXI GPIO） | `clk_fpga_0` 100 MHz / PS | DDR 控制器、AXI 从口、PS↔PL 控制与状态通道 |
| `u_idelay_clkgen` | `clk_gen`（`MMCME2_BASE`） | `sys_clk`→200 MHz | 只给收口 `IDELAYCTRL` 提供参考钟 |
| `u_eth` | `eth_udp_video_top` | `eth_rxc` 125 MHz + `axi_clk` | RGMII 收发、协议解析、帧重组、AXI 写 DDR、链路计数 |
| `u_lm_axi` | `snap_cross` | `eth_rxc`→`clk_fpga_0` | 320 位健康快照跨域后送到 PS 可读的 GPIO 窗口 |
| `u_pl` | `pl_video_top` | `clk_pix` 50 MHz + `axi_clk` + `sys_clk` | 显示通路：读回、几何、效果链、混合、OSD、TMDS 编码 |

主干数据流是 E1 推流 → E2 RGMII 入 `u_eth` → E9 作 AXI 主设备写 `u_bd` 的 `M_AXI_HP0` → E11 落片外
DDR3；显示侧 E10 读回同一块 DDR，经 E22 的三对数据一对时钟驱动屏。控制面走 E14：`main.c` 一次整字写
三个 AXI GPIO 从设备，PL 侧收 E15/E16/E17 三束线；状态经 E8 的 32 位 lane 回读，上位机用 JTAG/xsdb
读写同一组寄存器（E20），不开第四个通道。时钟与复位见 E12/E13/E19/E23/E24，按键走 E21。
全设计 4 处跨时钟域点都有器件承担：`dc_fifo` 格雷码指针、`snap_cross` 快照加翻转位、GPIO 准静态电平走
三条独立同步链、lane 读回口在 `clk_fpga_0` 域组合选择不新增跨域。

![图2 时钟域与跨时钟域点](figures/contest/fig2-clocks.png)

### 2.2 硬件系统介绍

#### 2.2.1 硬件整体介绍

整机由四件现成硬件组成：RK-ZYNQ7020-F 开发板（`xc7z020clg484-2`，CLG484，速度等级 2）、1024×600 HDMI
显示器、一根千兆网线、一台带有线网卡的 PC。板卡由 DC 座 12 V 供电，调试经 USB 的 FT4232 桥（A=JTAG、
B=UART）。与本设计相关的板级资源：

| 资源 | 器件 / 规格 | 与本设计的关系 |
| --- | --- | --- |
| 主芯片 | Zynq-7020，PS 双核 Cortex-A9，PL 为 7 系列 85K 逻辑单元 | 视频通路全在 PL，控制面在 PS |
| 板载晶振 | 50 MHz，引脚 `W17`，`create_clock -period 20.000` | `sys_clk`，像素钟与串行钟由它派生 |
| 主存 | 32 位 DDR3 `MT41K256M16`，`DDR_FREQ_MHZ 533.333`，DDR3-1066F，4096 MBit | PS7 预设控制器，作乒乓帧缓存 |
| 配置闪存 | 32 MB QSPI NOR，丝印 `W25Q256FV`，3.3 V，接 PS 的 MIO1/2/3/4/5/6 | 固化位流 + FSBL + 应用，断电自启 |
| 以太网 PHY | Realtek RTL8211F-CG（JATR-8275-15 Rev 1.4），RGMII，用 **PL 侧 RJ45 的 PHY2** | 收发延迟特性由 PL 侧约束按该手册给 |
| HDMI 输出 | HDMI OUT 座，TMDS 三对数据一对时钟，8 脚 `IOSTANDARD TMDS_33`，**无缓冲芯片，由 PL 直接串化** | 10:1 串行由 `OSERDESE2` 完成 |
| 按键 / 指示灯 | `key1_n`（`W18`）`key2_n`（`V14`）低有效，RC 4.7 kΩ + 100 nF；`led[0]` 心跳 `led[1]` 异常 | 长按换源、短按 ±1°；正常 1.5 Hz、异常 6 Hz |
| 调试口 / 启动 | FT4232（串口 115200-8N1），`hw_server` 链上 `arm_dap_0` + `xc7z020_1`；拨码 JTAG=00 / QSPI=10 / SD=11 | 命令回显与 xsdb 读寄存器；固化演示拨到 QSPI |

PHY 的两个硬件细节决定约束写法：`RXDLY`/`TXDLY` 与 `RXD1`/`RXD0` 复用（原理图第 8 页），板上两颗 4.7 kΩ
把这两个脚上拉到 IODVDD，即 **PHY 把约 2 ns 延时加在 RXC 上**；实测断链时 RTL8211 不停供 `RXC` 而是拉到
约 2.5 MHz（约 1/48），所以判断"链路活着"必须同时判断量它的那个时基准不准。

#### 2.2.2 机械设计介绍

本作品没有自主机械结构：开发板与显示器均为成品，用 HDMI 线与网线连接，没有需要设计的支架、外壳或光路。
结构上唯一的约束是启动拨码与散热——演示时板卡平放、四周不留遮挡，满载结温 61.2–61.7 ℃ 即在此状态下量得。

#### 2.2.3 电路各模块介绍

按信号流从入口到屏逐级给出各模块的输入、输出与关键电路，标号（E*）与图1 一致。

**（1）时钟与复位 `clk_gen`（`u_idelay_clkgen`、`u_pl` 内 `u_clk`）**：输入 `sys_clk` 与 `sys_rst_n`，
一只 `MMCME2_BASE` 出 `clk_200m` 专供 `IDELAYCTRL`，第二只 MMCM 出 `clk_pix` 与 `clk_pix5x`，`locked`
作复位释放条件。倍相关系：

| 输出钟 | 频率 | 周期 | 用途 |
| --- | --- | --- | --- |
| `clk_200m` | 200 MHz | 5.000 ns | `IDELAYCTRL` 参考 |
| `clk_pix` | 50 MHz | 20.000 ns | 显示扫描、几何、效果链、OSD |
| `clk_pix5x` | 250 MHz | 4.000 ns | `OSERDESE2` 10:1 串化 |
| `clk_fpga_0` | 100 MHz | 10.000 ns | AXI 互连与帧缓存写侧（FCLK_CLK0） |
| `eth_rxc` | 125 MHz | 8.000 ns | RGMII 收发与协议栈（`Y19`） |

**（2）RGMII 收口 `rgmii_rx` + `gmii_to_rgmii`（`u_rgmii`）**：输入 `eth_rxc`（`Y19`）、`eth_rx_ctl`
（`V19`）、`eth_rxd[3:0]`（`W20/W21/U20/V20`），用 `IDDR` 把 125 MHz 双沿 4 位还原成 GMII 单沿字节流，
采样沿由 `IDELAYE2` 抽头决定（全档扫描下 hold 每档 +63 ps、setup −92 ps，交点 31.1 取 31）；发侧
`eth_txd[3:0]`（`T21/U21/AA22/AA21`）等由 `ODDR` 合成，`mdc`/`mdio`/`rst_n` 完成 PHY 复位与管理接口。

**（3）入包与协议链**：`gmii_rx_mac` 去前导码并自算 FCS-32；`udp_rx_parser` 解析 IPv4/UDP 只放行 5001
端口；`frame_reasm` 按载荷偏移拼帧、`rows_hit` 满足后提交；`arp` 与 `icmp` 与推流并行应答；发侧由
`eth_ctrl` 仲裁、`udp_tx` 拼头、`crc32_d8` 补 FCS。这一层的 `arp*`/`icmp*`/`udp*`/`eth_ctrl` 与 RGMII
三件初版来自板卡厂商例程 `eth_udp`，本工程改造了组帧判据、端口过滤、PL 作 AXI 主设备直写 DDR、健康计数
与采样窗。

**（4）DDR 写入与乒乓提交**：16 位字节流先过 `dc_fifo`（格雷码指针跨域）作速率与域解耦，再由
`axi_frame_saver64` 拼成 64 位 AXI3 突发写入 ETH 那一路的乒乓对（`BANK0=0x1000_0000`、
`BANK1=0x1008_0000`；PS 那一路另用第三个基址 `0x1010_0000`），
`ddr_bank_commit` 在整帧写完后给换页脉冲；读侧 `frame_buffer_w64` 64 位读 16 位出，PS 那一路由
`axi_frame_writer64` 与按行搬运的 `axi_frame_writer_gated` 承担，owner 由 `src_arb` 判定。

**（5）链路健康与仲裁**：`link_monitor` 用 `eth_rxc` 域毫秒计数（`TC = CLK_HZ/1000`）判静默并出 10 组
计数；针对断链时 RXC 慢到 2.5 MHz 的实测事实，心跳位与独立的 `hb_slow` 合成 `eth_tb_ok` 作仲裁输入，
避免"没帧"与"时基不准"分不清。`frame_commit_lock` 管消隐窗口与看门狗，`src_life` 出 500 ms 心跳。

**（6）几何：缩放、旋转与双线性**：`video_timing_1024x600` 出显示坐标；`zoom_fit`（3 颗 DSP48）算适配
系数，`zoom_mapper`（8 颗）做含旋转的逆映射，出 `sx[11:0]/sy[11:0]/oob/zfrac`；`angle_ctrl` 按 ±1° 步进，
`sin_rom`/`cos_rom` 供系数；`fb_bilin` 内 `bilin_lerp` 做两次线性插值（6 颗 DSP48），`BILIN_ROWS = 2`。
倍率为八档定点数（25/33/50/75/100/133/150/200）加呼吸与 Fit 档。DSP 合计 19 颗 = `u_lerp` 6 + `u_blur` 1
+ `u_split_ctrl` 1 + `u_zfit` 3 + `u_zmap` 8；gamma 用 LUTRAM 查表不占 DSP。

**（7）效果链 `proc_pipeline`**：六级顺序 gamma、颜色、滤波、边缘、阈值、形态学，控制字 `gpio_cfg[8:0]`
一位一算法，级 5 的腐蚀与膨胀互斥（同置 1 两个都不做）。四个窗口级各自维护列标签、抽头号按该级之前累积
拍数取（blur 2、sharp 5、sobel 8、morph 12），故任意组合下延迟恒 15 拍、偏移恒 −4 行；顶层只取参数
`u_pipe.LATENCY`，台架实测 `de_in`→`de_out` 与之比对。

**（8）同帧混合、OSD 与 TMDS**：`split_display` 按 `split_eff[11:0]` 逐列取原图（`raw_line_delay` 的
4 行环加 15 拍滑移）或处理图，两半来自同一帧同一时刻；`osd_overlay` 叠五行（面板/帧率/片源、效果位/阈值
/gamma、角度/缩放档、缝位置/时延打点、结温与异常句）；`rgb2dvi` 内三只 `tmds_encoder` 与四只
`tmds_serializer`（`OSERDESE2` 10:1，`clk_pix5x`），输出 `tmds_clk_p/n`（`W16/Y16`）与三对数据
（`AA17/AB17`、`U17/V17`、`U15/U16`），全部 `TMDS_33` 直连 HDMI OUT 座。

![图3 u_eth 入包链（RGMII → 解析 → 组帧 → 写 DDR）](figures/contest/fig3-eth-chain.png)

![图4 u_pl 显示通路（读回 → 几何 → 效果链 → 混合 → OSD → TMDS）](figures/contest/fig4-pl-display.png)

### 2.3 软件系统介绍

#### 2.3.1 软件整体介绍

软件分三层：PC 上位机（推流、取数、判定）、PS 裸机应用（命令、寄存器、SD、温度）、PL 逻辑（只写它接受
的寄存器接口）。三层之间只有两条通道——UDP 5001 的视频流，和三个 AXI GPIO 从设备的寄存器读写；上位机经
JTAG/xsdb 读的是同一组寄存器，因此"串口看到的"与"xsdb 看到的"必然同源。

上位机共 29 支工具（26 支 `.mjs` + 3 支 `.py`），零第三方依赖：`video_sender` 推任意片源，
`one_click_test.mjs`（入口 `run_test.sh`）串起 ping → 经 JTAG 写读 lane → 发内置片源 → 计数对账四步且
任一步 FAIL 退出码非 0，`health_read` / `uart_cmd_check` 分别批量读 lane 与驱动 105 条命令回归，
`geom_check`、`ddr_verify`、`pipe_len_check`、`metrics` 是量问题的尺子，`doc_currency_check` 对齐文档
与指标表。PS 裸机 2,544 行 C 跑在 `ps7_cortexa9_0`，BSP 由随工程导出的 Vitis 平台提供；需要的只是
UART、SD、GPIO 与一段主循环，带操作系统的栈在这里是成本不是收益。

![图5 PS 裸机主循环与命令分发流程](figures/contest/fig5-ps-flow.png)

#### 2.3.2 软件各模块介绍

主循环每轮依次做四件事：`uart_poll()` 收命令（`rx_fill()` 补缓冲 → `tokenize()` 切词 → `dispatch()`
分发）、`temp_poll()` 采 XADC、`sd_recover_tick()` 处理拔卡与重挂载、`ps_keepalive()` 与 `ps_publish()`
发布"活着"位。关键输入是串口行与寄存器现值，关键输出是 `gpio_o` / `gpio_cfg1_o` / `gpio_cfg2_o` 三个
整字与串口回显。各模块的函数、输入输出与职责：

| 模块 | 关键函数 | 输入 → 输出 | 要点 |
| --- | --- | --- | --- |
| 控制字合成 | `ctrl_write` `ctrl_apply` `apply_pipe_bits` `legacy_to_sel` | `sel`(9 位) `thr` `zoom` `angle` `split` 两个开关 → 32 位整字 | 只允许一次整字写，PL 侧统一打三级同步；`gpio_o[19]` 双线性、`[20]` OSD（反相，复位值=有 OSD） |
| 命令分发 | `dispatch` `cmd_src` `cmd_fill` `cmd_temp` `cmd_help` | 首词 + 参数 → 落地并回显 | `src/fill/split/zoom/rot/bilin/osd/gamma/thr/temp/lane/help`，`ci_eq`/`ci_pre` 大小写不敏感，`strict_int` 非数字即判参数错 |
| 缩放档 | `zoom_parse_x100` `zoom_step_near` | 百分数字符串 → 八档之一 | 命令可给任意倍率，落到最接近的定点档 |
| gamma | `gamma_curve` `gamma_put` `gamma_set` `gamma_auto_start` `gamma_tick` `gamma_off` | `g100`（145 即 1.45）+ 索引 → 256 项窗口写进 `gpio_cfg2_o` | 软件只写窗口，逐像素查表由 PL 做 |
| SD 与 FAT32 | `sd_mount` `parse_bpb` `dir_lookup` `fat_next` `clus_lba` `open_at` `feed_cur` `show_frame` | 8.3 文件名 → 簇号 → LBA → 帧 → DMA 进 DDR | `meta_try`/`parse_meta` 校验同名 `.txt` 的 `frames=`/`width=`/`fps=`；`card_gone`/`sd_recover_tick` 处理重插；不解码，只搬预转换的 RGB565 裸帧 |
| 温度与状态 | `xadc_init` `temp_poll` `temp_code_of` `temp_disp_write` `ps_publish` | XADC（`0xF8007100`）的 `mc`/`mv` → OSD 三字符码 + GPIO 值 | 温度对账三路：驱动读数、屏上三字符、写进 PL 的 GPIO |
| 回读 | `lane23` 组 | `GPIO_1_tri_i[31:0]` → 倍率 / 来源 / 手自动 / 双线性 | 屏、串口、JTAG 读的是同一组寄存器 |

PL 侧接受软件配置的寄存器契约：

| 通道 | 地址 | 位段与含义 |
| --- | --- | --- |
| `gpio_o[31:0]` | `0x41200000` | `[15:8]` 阈值、`[16]` 片源、`[17]` 呼吸开关、`[18]` 发布翻转位、`[19]` 双线性、`[20]` OSD 关（反相）、`[22]` 模式翻转位 + `[24:23]` 模式码、`[26]` 帧间隔清零、`[31:27]` lane 号 |
| `gpio_cfg1_o[31:0]` | `0x41220000` | `[8:0]` 九位 `stage_sel`、`[9]` 自动旋转、`[12:10]` 旋转速度、`[22:13]` 缝列、`[23]` 缝自动、`[24]` follow、`[25]` swap、`[28:26]` 缩放档、`[29]` 手动旗标、`[30]` marker 关、`[31]` 缩放拟合 |
| `gpio_cfg2_o[31:0]` | `0x41220008` | `[31]` gamma 使能、`[30]` 写表翻转位、`[29:22]` 表项、`[21:14]` 表索引、`[13:8]` 屏上 gamma 格、`[7:0]` 屏上温度码（`0xFF` = 画 `--`） |
| lane 读回口 | `0x41210000` | `GPIO_1_tri_i[31:0]`：按 `gpio_o[31:27]` 选一条 32 位状态（丢帧、坏帧、包数、帧间隔、缩放状态、时延分段、时基可信位） |
| `gpio_o[19] / [20] / [26]` | — | 双线性开关 / OSD 总开关（反相）/ 帧间隔统计清零 |

![图6 上位机、PS 与 PL 之间的控制与观测通道](figures/contest/fig6-sw-stack.png)

---

## 第三部分 完成情况及性能参数

### 3.1 整体介绍

整机已完成并可独立运行：PC 推流、板卡处理、屏上显示、串口与 JTAG 读回四条通路同时成立；位流与固件已
写进板载 QSPI NOR，拨码打到 QSPI 档后断电重上电即自起，不需要 PC 参与。

【照片 1｜整机正面全景】要拍到：RK-ZYNQ7020-F 板卡 + HDMI 屏上正在显示的画面（OSD 五行要能读清）
+ 网线与 12 V 电源。横向构图，屏面占画面 2/3 以上，关灯或避开反光，别只拍板子。

【照片 2｜斜 45° 全景】要拍到：板卡右侧的 HDMI OUT 座、PL 侧 RJ45（插着网线）、屏上同一帧画面。
这张的作用是让人看出"网口进、HDMI 出"的接法。

### 3.2 工程成果

#### 3.2.1 机械成果

无自主机械结构，因此没有机械成果件；板卡与显示器用现成支架与桌面摆放。

#### 3.2.2 电路成果

| 成果件 | 内容 |
| --- | --- |
| 位流 | `system.bit`，2.20 MB，md5 前 12 位 `cd04907e1369` |
| 硬件描述 | `system.xsa`，865 KB，Vitis 平台由它导出 |
| 固件 | `ps_app.elf`，343 KB，链接基址 `0x00200000`（OCM 高段，避开 FSBL 自己） |
| 启动镜像 | `BOOT.bin` = FSBL + 位流 + 应用，2,435,868 字节 |
| 烧写 | QSPI 32 MB NOR，擦写 + 回读校验通过，耗时 137 s |
| 断电自启 | 串口出现 FSBL 横幅、`Boot mode is QSPI`、`QSPI is in 4-bit mode`、`DMA Done !`、`FPGA Done !`，随后 `SUCCESSFUL_HANDOFF`、`[CFG] axi_gpio_2 @41220000 ok`、`[CFG] gamma window @41220008 ok`、`[TEMP] PS-XADC @F8007100 ok`，SD 自动播片且网口那一路也出画面 |

【照片 3｜板卡顶面特写】要拍到并在图上标出四个位置：PL 侧 RJ45（PHY2，Realtek RTL8211F-CG）、
HDMI OUT 座、启动模式拨码（拨到 QSPI 档）、板载 32 MB QSPI NOR 丝印 `W25Q256FV`。
建议俯拍 + 后期箭头标注，这是电路成果最直接的一张。

【照片 4｜断电自启瞬间】要拍到：拨码在 QSPI 档、上电后屏自己出画面（无 PC 参与）、串口窗口里
有 `Boot mode is QSPI` 与 `FPGA Done !` 那两行。这张证明"固化"这一格是真的。

#### 3.2.3 软件成果

上位机一条命令推流（`video_sender.py --input <帧目录>`）、一条命令自检（`bash run_test.sh`）；PS 侧
串口控制台 115200-8N1，一次 105 条命令回归耗时 98.2 秒且跑完回到初态。下面三张是上位机按同一套算法
重算出的参考结果图，用作与屏上画面对照的同源基准。

![图7 同帧左右对照参考图：左窗原图 / 右窗处理图](../data/golden/dual_preview.png)

*图7 说明：1280×360 并排预览，左半为原始画面、右半为经过效果链与几何变换后的画面，对应屏上那条可由
控制字定位的竖缝两侧所看到的内容。*

![图8 效果链六级全开的参考图](../data/golden/proc_all.png)
![图9 旋转 45° 加双线性插值的参考图](../data/golden/rot_045.png)

【照片 5｜上位机截图】要拍到：推流窗口正在发包的那一行（含帧率与包数）+ 紧随其后的一键自检
判定输出（四步各自的 PASS）。终端字体调大，别缩成一片。

【照片 6｜串口控制台截图】要拍到：`[STAT]`（收包/坏帧/重复帧/帧间隔）、`[TEMP]`（XADC 读数）、
`lane23` 回读（当前倍率与来源）三行，以及它们对应的屏上 OSD 同一组数——最好屏和终端同框，
用来证明"三路同源"。

真实串口回显片段（105 条命令回归的留档形态）：

```text
[CFG] axi_gpio_2 @41220000 ok
[CFG] gamma window @41220008 ok
[TEMP] PS-XADC @F8007100 ok
[CTRL] mode=0 src=1 bilin=1 zoom=100 angle=000 split=50
[STAT] rx=  9000  bad=0 dup=0 lost=0 gap_min=20 gap_max=51 avg=33.34 fps=29.99
RESULT board_verify PASS（判红的步骤：0）
```

#### 3.3 特性成果

| 功能 | 量化结果 | 判据来源 |
| --- | --- | --- |
| RGMII 收包与零丢包 | 512×300@30 fps，600 帧一轮与 9000 帧 / 300 s 长跑，丢帧 0、坏帧 0、重复帧 0 | 整屏台架 + `link_monitor` 自数计数 |
| 入流能力 | ≥116.7 fps 不丢字（目标 120 fps、960 帧，过载点未顶到） | 不限速长跑 |
| 并行应答 | 推流期间 `ping` 仍有回包，ARP 与 ICMP 在 PL 内应答 | 主机侧 `ping` + 四条回归 |
| 缩放 | 0.25 / 0.33 / 0.50 / 0.75 / 1.00 / 1.33 / 1.50 / 2.00 八档 + 呼吸 + Fit，倍率与来源可机读 | `lane23` 回读 + 屏上量格 |
| 旋转 | ±1° 步进，逆映射加双线性，四角是否出屏由台架判 | 台架映射判据 M1/M2/M4/M6 |
| 效果链 | 六级 9 位控制字，任意组合延迟恒 15 拍、偏移恒 −4 行 | 每级一条旁路判据 + 实测 `de_in`→`de_out` |
| 同帧对照 | 缝位置 0–100 % 运行时可调，改参数后 marker 位不变 | 串口 `split <n>` 判据 |
| OSD | 五行齐全，字模索引在有效区整屏走一遍越出上界 190,464 拍（划出可用样本下限） | 36 行人眼验收逐条 |
| 自动回落 | 拔网线、拔卡能切走，插回能切回，不需要复位 | 板级现场复验 |
| 固化 | 断电自启整条成立（位流与固件两格都量过） | 冷上电回显 |
| 时序收敛 | 4 个受检域全满足（setup/hold）：`sys_clk` 14.876/0.222、`clk_fpga_0` 1.850/0.053、`clk_pix` 3.630/0.059、`eth_rxc` 0.739/0.052 ns，51,135 端点失败 0 | 实现后时序汇总 |
| 最紧路径 | `eth_rxc` 0.739 ns 落在 `u_icmp_tx/ip_head_reg[4][16] → check_buffer_reg[19]/D`，11 级含 6 个 CARRY4、布线 58.4 %；4–12 档是 `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[*]/CE`，4 级、布线 85 % | 逐域前 12 档取端点 |
| 资源与取舍 | LUT 14,154（26.61 %）、FF 8,188（7.70 %）、BRAM 95.5/140（68.21 %）、DSP48 19/220（8.64 %）；打包 FIFO 改 LUTRAM 释放约 5 万 FF，BRAM 曾顶到 98.93 % 后回落 | 实现后报告 |
| 功耗与温升 | 工具估算动态 2.213 W（置信度 Low）；板读 XADC 结温六次极值 61.2–61.7 ℃ | 满载演示态 |
| 验证覆盖 | 模块级台架 82 支 + 5 支变异对照；整屏逐像素判据 141 条通过 140 条；一键门禁 24 项绿 23 项；板级 36 行人眼验收与 105 条串口命令 | 门禁与留档 |

---

## 第四部分 总结

### 4.1 可扩展之处

一是屏那一路的对外时序结论还没有：六个 TMDS 输出口只量到离散量（互对最差 0.065 ns、对内最差 0.001 ns，
HDMI 1.4 源端 0.20 `Tcharacter` 在 50 MHz 档约合 ±4.000 ns），要做的是把源端窗落到约束、减掉走线失配并
补眼图量测；同时给三个域补同一测量条件下的 hold 不确定度，为异步组屏蔽的 4 条跨域路补
`set_max_delay -datapath_only`。二是端到端时延的出入口目前不同次测量，需一次测完给出整值。三是收口余量：
拆开 `gmii_rx_clk` 的 2546 扇出、加一级短捕获钟，判据是慢捕与快捕偏差从 3.411 ns 收到约 1.2 ns 以内。
四是片源与画幅：当前帧率与画幅同时被消隐窗口卡住，上更高分辨率或更多片源改的是这个窗口与 bank 分配。
五是能力边界：H.264 解码、重传与多屏同步不在本版内，入流上界也需把过载顶到才能报确切值。

### 4.2 心得体会

这个项目最大的改变，是把判断"做完了"的标准从"看起来对"移到"有一条能红的判据"。

最疼的一课是全绿并不代表对。有一次五支台架、56 条检查项全部 PASS，我把这一轮记成了通过；后来发现综合
报告里那条逻辑根本不存在——边界守卫的一侧接了常数，被综合直接删掉。从此我要求每条判据必须能红：靠空集
通过的判据本身就算失败，为此写了 `mut_control.sh`，把修复前的写法复原一次，判据仍不红就判 MUTATION
FAILED。类似的一次是 `for (stage = 2'd0; stage < 2'd4;)` 这种两位计数器，循环里永远够不到 4，一屏满
PASS 而那一整轮从未执行。这两件事之后，我在读任何"通过"之前先看它覆盖到的样本数。

第二课是被实测推翻的假设最值钱。设计假设"拔线后 PHY 会停供 RXC"，于是链路静默只看计数不涨；真拔一次线，
计数确实不涨但画面也不交回 SD，`STALL` 钉死在上限值。查下去得到的物理事实是 RTL8211 断链时不停 RXC 而是
拉到约 2.5 MHz，慢约 48 倍，所以"毫秒计数小于 200"能连着十几秒为真——错的不是仲裁的换手规则，是喂给它
的那位在说谎。修法是承认测量结果，把"量它的时基可不可信"做成仲裁输入再加一个独立心跳位。同样被实测否掉
的还有校验和摊到每拍一项、强制复制 239 引脚广播网、把 RGMII 输入窗直接挂上（一挂就 −2.885 ns 整批红）
这几刀。我把它们连同数据一起留下，因为删掉过程，结论就没有可核对的链条了。

第三课是时序要靠算和扫，不靠猜。RGMII 采样沿位置先建模型再取整；同一套办法用在时钟不确定度上，给四个域
统一加 0.800 ns 的带量出来 WHS −0.747、25,742 个失败端点，数据不支持就不采纳。最紧路径也不只看全局最差
那条：每个域取前 12 档，`eth_rxc` 那 0.739 ns 是校验和锥、布线只占 58.4 %，而 4–12 档全是使能广播、布线
占 85 %，瓶颈不同能做的事就不同。算清这类账，才知道"再动它换到的是余量，换不到正确性"什么时候成立。

第四课是关于工具与协作的。以把关为目的的检查必须用 `&&` 串在被它守护的动作之前——"看见它判不通过"和
"它挡住了这次提交"是两件事；跑任何一支脚本前先读它自己的头部注释。至于和大模型协作：没逐条核实过的
采纳率不可用，没验过的话不能当结论，"这条判据真的能红吗"只能由机器跑一遍回答。

最后的收获是关于边界的：把每像素 20 ns 的预算作为划分依据，链路上就没有一处逐像素的软件参与；把"硬件
自己数自己的账"作为观测面，屏、串口与 JTAG 三路同源，现场判断就不再依赖肉眼。这两条不是一开始就想清楚
的，是被一次次判红逼出来的。

---

## 第五部分 参考文献

[1] HDMI Forum. High Definition Multimedia Interface Specification Version 1.4, Section 4.2.4, Table 4-24 (Source Timing Requirements). HDMI.org, 2013.
[2] Arm Ltd. AMBA AXI and ACE Protocol Specification, AXI3, Issue J (IHI 0022J). Arm, 2023-03, 273 p.
[3] Arm Ltd. AMBA AXI and ACE Protocol Specification, Issue H (IHI 0022H). Arm, 2020-04, 500 p.
[4] Realtek Semiconductor Corp. RTL8211F-CG 10/100/1000M Ethernet Transceiver Datasheet, Track ID JATR-8275-15, Rev 1.4, Table 10 & Table 60. Realtek, 2018.
[5] Xilinx Inc. Zynq-7000 SoC Technical Reference Manual (UG585), v1.13. AMD/Xilinx, 2021-04-02.
[6] Xilinx Inc. XC7Z010/XC7Z020 Data Sheet: DC and AC Switching Characteristics (DS187), v1.21. AMD/Xilinx, 2020-12-01.
[7] Xilinx Inc. Vivado Design Suite User Guide: Using Constraints (UG906), v2025.2. AMD/Xilinx, 2025-12-10.
[8] Xilinx Inc. Vivado Design Suite User Guide: Implementation (UG949), 中文版 v2024.2. AMD/Xilinx, 2024-12-18.
[9] Xilinx Inc. 7 Series FPGAs Memory Architecture User Guide (UG473). AMD/Xilinx.
[10] Xilinx Inc. 7 Series FPGAs Clocking Resources User Guide (UG479). AMD/Xilinx.
[11] Xilinx Inc. 7 Series FPGAs SelectIO Resources User Guide (UG471). AMD/Xilinx.
[12] Xilinx Inc. Zynq-7000 SoC XADC (UG835). AMD/Xilinx.
[13] Xilinx Inc. AXI GPIO v3.3 Product Guide (PG054). AMD/Xilinx, 2017-10-04.
[14] Xilinx Inc. Interfacing DDR SDRAM with the Memory Interface Generator (XAPP793), v1.0. Xilinx, 2012-09-20.
[15] Micron Technology. MT41K256M16 4Gb DDR3 SDRAM Mobile DRAM datasheet, Rev. Q. Micron, 2017-12.
[16] AMD/Xilinx. Vivado Design Suite & Vitis Unified Software Platform 2025.2.1 (build 6403652) Release Notes and Installation Guides. 2025.
[17] RK-ZYNQ7020-F 开发板用户手册 V1.0（第 7、36 页）与 ZYNQ7020-F+V1.1 原理图（第 8 页 PHY 引脚复用表）. 板卡资料.
[18] Keysight Technologies. D9021HDMC HDMI Source Compliance Test Application Programmed Reference Guide, 9924-01437, 74 p.; Tektronix Inc. TDS/HT3 HDMI Source Test Application Reference Guide; Diodes Inc. PI3HDX1204B1 HDMI 2.0 CTS 2.0 Compliance Report. （仪器厂商与应用笔记的转述资料）
[19] DVI Test & Measurement Guide, Rev. 1, 26 p.（DVI/HDMI 源端信号量测方法参考）
[20] RK-ZYNQ7020-F 开发板厂商例程 RTL：`eth_udp` 以太网协议栈（`arp`／`icmp`／`udp`／`eth_ctrl`／RGMII 三件的初版来源）. 板卡资料配套例程.

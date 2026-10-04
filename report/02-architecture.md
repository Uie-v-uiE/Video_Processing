# 架构

本章的数字口径以 `../data/metrics.csv` 与 `build/report/*.rpt` 为准；重复写出是为了让这一章能单独读懂。

## 软硬件划分：哪些在 PL、哪些在 PS、为什么

数据面整条在 PL：收包、拼帧、写 DDR、读回、帧缓存、几何（缩放与旋转）、效果链、逐像素混合、OSD、
TMDS 编码（`report/architecture.md` §3）。PS 只做三件事：发命令、读计数、把 SD 卡上的帧 DMA 进它自己
那块 DDR；SD 控制器把帧直接落进那块内存，CPU 不逐帧搬第二遍，写完只翻一次发布位，也不中转 ETH 视频字节
（`src/host/ps/main.c` 文件头、`report/architecture.md` §3）。

这样切的结果是可核对的：实时数据面放 PL，显示链上每一级的延迟由流水线级数决定，与软件运行状态无关，
CPU 占用接近 0；控制面留 PS，命令与状态各走一条独立的 GPIO 通道。两条路的取舍与对照实验记在
`report/ps_vs_pl.md` §3。

## 顶层与连线点名

| 文件 | 在这一版里的角色 | 出处 |
|---|---|---|
| `src/rtl/top/system_top.v` | 板上顶层，把 `design_1_wrapper`（PS7 加 AXI GPIO）、`clk_gen`（IDELAY 参考）、`eth_udp_video_top`（自研收包，占 HP0 写 DDR）、`pl_video_top`（显示通路）、`snap_cross`（观测 lane 复用回 AXI）连起来 | 该文件文件头第 2–3 行；对外端口 `sys_clk / key1_n / key2_n / led / tmds_clk_p / tmds_data_p / eth_rxc / eth_rxd / eth_txd` 见同文件端口段 |
| `src/rtl/top/pl_video_top.v` | 显示主通路：栅格、几何、帧缓存读写、两条抽头、混合、OSD、TMDS | `report/modules.md` 记它例化在 `system_top.v:258` |
| `src/rtl/eth/eth_udp_video_top.v` | RGMII→协议栈→拼帧→跨时钟域→打包写 DDR 的容器 | `report/modules.md` 的 eth/ 表 |
| `src/rtl/axi/axi_frame_writer64.v`、`axi_frame_writer_gated.v`、`src/rtl/eth/axi_frame_saver64.v` | 整帧搬运的两头：两支 writer 把帧从 DDR 读回显示帧缓存（PS 路与 ETH 路各一支，复用同一个读口），saver 那一支把收好的包写进 DDR | `report/modules.md` 的 axi/ 与 eth/ 表 |
| `src/rtl/video/frame_buffer_w64.v` | 显示帧缓存 | 同上 |
| `src/rtl/clocks/clk_gen.v` | MMCM：像素钟、串化钟与 IDELAY 参考钟都由它出 | 同上 |

## 数据通路与缓冲

通路按 `report/architecture.md` §1 的流程图，原样抄在那里：
```
PC ─UDP:5001─► RGMII ─► gmii_rx_mac ─► udp_rx_parser ─► frame_reasm   (eth_rxc 125 MHz)
        └─► dc_fifo（格雷码指针，eth_rxc → axi_clk 的跨域缓冲）
        └─► axi_frame_saver64（16b→64b 打包 + AXI3 写 DDR HP0）
SD 卡 ─► PS sd_play.c DMA ─► 写进 PS 专用 bank，翻发布位 gpio_o[18]
        └─► axi_frame_writer64 / _gated 按 owner 复用读口，整帧搬进 frame_buffer_w64
读出后立刻分两条抽头：原图抽头过 raw_line_delay（4 显示行的行延迟环），
处理抽头过 proc_pipeline（15 拍）；两条同拍并排，由 split_display 逐像素二选一，
再叠 osd_overlay、编 rgb2dvi 出 TMDS。
```
两处说法需要先立住，否则上面的图读不下去。"乒乓"指同一份数据用两块缓冲交替：一块在被写、另一块在被读，
写完读、读完写。"抽头"指同一条读流上并行取出的两路值：原图一路、处理图一路，两者来自同一拍。

缓冲与地址的分配：ETH 那两路乒乓占 `0x1000_0000` 与 `+0x0008_0000`，SD 与图卡填充走第三个 bank
`0x1010_0000`（`src/host/ps/main.c` 文件头第 19 行、第 41–46 行注释；`report/architecture.md` §4）。
三个 bank 的地址必须分开，这条结论来自板级实测：早期 SD 那路用的正是乒乓第 0 块的地址，两路同时写同
一块内存，屏幕表现为两个片源互相覆盖（`src/host/ps/main.c` 第 41–45 行注释把现象与原因写在一起）。
帧的拷贝只在消隐窗口内做，赶不上窗口就整笔作废、屏上保留上一帧；把关的是 `frame_commit_lock`，
它的职责记于 `report/modules.md`，通路记于 `report/architecture.md` §1。

## 时钟域与跨域做法

名字与频率的口径在 `report/architecture.md` §2 的表里，这里列每个名字由谁产生：

| 时钟 | 来源文件 |
|---|---|
| `sys_clk`（板载振荡器输入） | `src/constraints/rk_zynq7020.xdc` |
| `clk_pix`（= MMCM `clkout0`） | `src/rtl/clocks/clk_gen.v` |
| `clk_pix5x`（= MMCM `clkout1`） | `src/rtl/clocks/clk_gen.v` |
| `clk_200m`（= MMCM `clkout2`，IDELAYCTRL 参考） | `src/rtl/clocks/clk_gen.v` |
| `axi_clk`（= `clk_fpga_0`，PS 的 FCLK0） | `src/rtl/top/system_top.v` |
| `eth_rxc` → `gmii_rx_clk`（PHY 侧 RGMII） | `src/constraints/rk_zynq7020.xdc` 与 `src/rtl/top/system_top.v` |

跨域的做法按被搬运的对象分四类，仓库里没有一支共用的通用跨时钟域 IP：单 bit 的准静态电平用 2~3 级
`ASYNC_REG` 同步器；脉冲先转成翻转位、在目的域用 3 级同步加异拍出沿；宽总线走 `snap_cross`，即"源域整拍
写总线并翻一个标志位、目的域等到沿再采样"；16 bit 的视频流从 eth_rxc 进 axi_clk 用 `dc_fifo` 的格雷码指针
配双级同步。这四类的分工记于 `report/architecture.md` §2。

异步时钟组的关系不写在功能约束里，单独放 `src/constraints/clock_groups_impl.xdc`，并且带
`used_in_synthesis false`。原因是 `clk_fpga_0` 由 PS7 IP 自己的约束文件创建，综合阶段还不存在这个时钟，
提前声明会在综合里落空；这条记于 `report/architecture.md` §2。

## 这一章管到哪里

- 只覆盖仓库里这一版工程。第二块板卡的那份工程目录已移出仓库，所以本章不写跨板卡的通路
  （范围声明在 `report/architecture.md` 文件头）。
- 本章只写结构与地址，不写实测读数。读数与出处集中在 `data/metrics.csv` 与 `build/` 下的报告原件，
  逐时钟的余量读法在 `report/timing_global.md`，那里每个数旁边有它自己的产物文件。
- 端口与地址的机器可读表在 `report/interface-table.md`，模块级的端口与时序假设在 `report/modules.md`；
  本章与那两份说法不一致时，以那两份为准。

## 本章依据的产物
- `report/architecture.md`
- `report/ps_vs_pl.md`
- `report/modules.md`
- `src/rtl/top/system_top.v`
- `src/host/ps/main.c`

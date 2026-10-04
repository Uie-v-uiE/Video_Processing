# 架构

## 软硬件划分：哪些在 PL、哪些在 PS、为什么
数据面整条在 PL：收包、拼帧、写 DDR、读回、帧缓存、几何（缩放/旋转）、效果链、逐像素混合、
OSD、TMDS 编码（`report/architecture.md` §3）。PS 只做三件事：发命令、读计数、把 SD 卡上的帧
DMA 进它自己那块 DDR——写完只翻一次发布位，零拷贝，不中转 ETH 视频字节
（`src/ps/main.c` 文件头、`report/architecture.md` §3）。

为什么这样切：把实时数据面放 PL 换来的是流水线确定的延迟与接近 0 的 CPU 占用；
控制面留 PS 才体现软硬件协同（对比与结论记于 `report/ps_vs_pl.md` §3）。

顶层与连线点名：
- `src/rtl/top/system_top.v`——板上顶层，把 `design_1_wrapper`（PS7 + AXI GPIO）、`clk_gen`
  （IDELAY 参考）、`eth_udp_video_top`（自研收包，占 HP0 写 DDR）、`pl_video_top`（显示通路）、
  `snap_cross`（观测 lane 复用回 AXI）连起来（该文件文件头第 2–3 行）。对外端口如
  `sys_clk / key1_n / key2_n / led / tmds_clk_p / tmds_data_p / eth_rxc / eth_rxd / eth_txd`
  见同文件端口段。
- `src/rtl/top/pl_video_top.v`——显示主通路（`report/modules.md` 记它例化在 `system_top.v:258`）。
- `src/rtl/eth/eth_udp_video_top.v`——RGMII→协议栈→拼帧→CDC→打包写 DDR 的容器。
- `src/rtl/axi/axi_frame_writer64.v` / `axi_frame_writer_gated.v` / `src/rtl/eth/axi_frame_saver64.v`
  ——PS 路 / ETH 路的整帧读写搬运引擎。
- `src/rtl/video/frame_buffer_w64.v`——显示帧缓存；`src/rtl/clocks/clk_gen.v`——MMCM。

## 数据通路与缓冲
按 `report/architecture.md` §1 的流程图：
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
缓冲/地址的口径：ETH 走 DDR 乒乓两块 `0x1000_0000` / `+0x0008_0000`，SD/FILL 走第三个 bank
`0x1010_0000`（`src/ps/main.c` 文件头第 19 行、第 41–46 行注释；`report/architecture.md` §4）。
三个 bank 地址分开是因为早期 SD 与乒乓第 0 块重叠导致"两个片源打架"，是板级实测结论
（`src/ps/main.c` 第 41–45 行注释）。拷贝只在消隐窗口内做、赶不上就整笔作废保留上一帧，
由 `frame_commit_lock` 把关（职责记于 `report/modules.md`，通路记于 `report/architecture.md` §1）。

## 时钟域清单（只列名字与来源文件）
名字与频率口径取自 `report/architecture.md` §2 的表；来源文件如下：
- `sys_clk`（板载振荡器输入）——`src/constraints/rk_zynq7020.xdc`
- `clk_pix`（= MMCM `clkout0`）——`src/rtl/clocks/clk_gen.v`
- `clk_pix5x`（= MMCM `clkout1`）——`src/rtl/clocks/clk_gen.v`
- `clk_200m`（= MMCM `clkout2`，IDELAYCTRL 参考）——`src/rtl/clocks/clk_gen.v`
- `axi_clk`（= `clk_fpga_0`，PS FCLK0）——`src/rtl/top/system_top.v`
- `eth_rxc` → `gmii_rx_clk`（PHY 侧 RGMII）——`src/constraints/rk_zynq7020.xdc` + `src/rtl/top/system_top.v`

跨域做法按对象分（不搞通用 IP）：单 bit 准静态电平用 2~3 级 `ASYNC_REG`；脉冲先转翻转位、目的域
3 级 + 异拍出沿；宽总线用 `snap_cross`「准静态总线 + 跳变沿」；16 bit 视频流 eth_rxc→axi_clk 走
`dc_fifo` 格雷码 + 双级同步。分类记于 `report/architecture.md` §2。异步时钟组的声明单独放
`src/constraints/clock_groups_impl.xdc`，且 `used_in_synthesis false`——原因（`clk_fpga_0` 由 PS7 IP
的 XDC 创建、综合阶段还不存在）记于 `report/architecture.md` §2。

## 本章依据的产物
- `report/architecture.md`
- `report/ps_vs_pl.md`
- `report/modules.md`
- `src/rtl/top/system_top.v`
- `src/ps/main.c`

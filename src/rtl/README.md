# PL 源码

顶层是 `top/system_top.v`，显示主通路在 `top/pl_video_top.v`。

## 模块分工

| 路径 | 职责 | 关键约束 |
|---|---|---|
| `top/system_top.v` | PS7、时钟、ETH、显示三条边界的连接 | PS FCLK0 100 MHz；PHY 恢复时钟只进 IDDR/FIFO 写侧 |
| `top/pl_video_top.v` | 帧缓存、几何、效果、竖缝、OSD、TMDS | 像素域 50 MHz；效果链恒 15 拍 |
| `eth/eth_udp_video_top.v` | RGMII → MAC → UDP → 重组 → AXI 写 DDR | 收包与协议逻辑在 125 MHz |
| `eth/frame_reasm.v` | 按帧内偏移拼帧、行覆盖、字节门、A9 idle timer | 三个条件同时满足才提交 |
| `eth/dc_fifo.v` | 收包域到 AXI 域的异步 FIFO | 格雷码指针，不能当同步 FIFO |
| `eth/axi_frame_saver64.v` | 16→64 位打包、AXI 突发写 DDR | 满 FIFO + flush 的尾字要保留 |
| `video/frame_buffer_w64.v` | 64 位宽整帧缓存、乒乓 | BRAM 的主要去向 |
| `process/zoom/zoom_mapper.v` | 显示坐标 → 源坐标的定点逆映射 | 八个缩放档 + 任意角度 |
| `process/bilin/fb_bilin.v` | 双线性读口 | 四个邻点、2 行结果缓冲 |
| `process/proc_pipeline.v` | 六级效果链 | 总延迟 15 个像素时钟 |
| `video/split_display.v` | 原图/处理图逐像素二选一 | 缝只是选择位变化的地方 |
| `video/osd_overlay.v` | 五行 OSD | 不改变竖缝几何 |
| `eth/link_monitor.v` | 帧间隔、作废、坏包、flags | `stall`、`gap_last/min/max/sum` |
| `eth/snap_cross.v` | 准静态总线跨域快照 | 翻转沿 + 整拍保持 |
| `clocks/clk_gen.v` | 像素/串化时钟 | 像素与串化保持 5:1 |
| `hdmi/` | TMDS 编码与串化 | 50 MHz 像素、250 MHz 串化 |

## 读代码时先看“行李”

一个像素信号要和它的坐标标签、越界位、`de`、帧/片源标识同一条流水线走。很多一行串色、缝上错位、边缘填黑，都是“像素到了，行李没跟上”。C22 修的是行标签滞后一行，C31 修的是 `sx` 比原图抽头晚两行；两条都在 `docs/verification.md` 里有判据。

## 时钟与复位

- 恢复时钟 `eth_rxc` 只用于 IDDR 采样和异步 FIFO 写侧；
- 协议逻辑在 `clkout3` 125 MHz，显示在 `clkout0_1` 50 MHz，控制面 `clk_fpga_0` 100 MHz；
- 跨域三类：异步 FIFO、准静态快照、三级同步器；
- 复位异步断言、本域同步释放；最差 setup 是复位恢复路径，边界在 `docs/optimization.md`。

## 验证

改 RTL 前先在 `sim/` 找对应台架；完整视频台架 `tb_video_pipeline_top.v` 覆盖几何、效果、竖缝、OSD 和边界。最终判定在 `sim/results/`。

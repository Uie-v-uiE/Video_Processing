# 源码地图（`src/` 逐文件的四列现算表）

这张表由 `node 仓库留档 r120_src_map.mjs（剪枝件，不随包）` 生成，输出重定向进 `report/src-map.md`，覆盖 **83 个源文件**。
表里的文件数与 git 跟踪的 `src/` 下 *.v/*.c/*.h 数量由脚本现算并比对，两个数不一致时脚本拒绝出图。

## 这四列的用途与边界

- **能**：某个模块在哪个文件、文件多大、那个文件头注的第一句是什么（逐字搬运，不改写）。
- **不能**：数据流顺序、时钟域归属、寄存器位序。这些数据由各自的文档单点维护，这张表只提供
  四列，免得同一份数据出现两个口径。指路：数据通路看 `report/02-architecture.md`，时钟域看 `report/board_pins.md` 与
  `report/build.md`，寄存器看 `skill/runtime/register-map-and-readback/SKILL.md`，
  台架（`sim/` 下的仿真测试例）与模块的对应关系看 `sim/README.md`。
- 头注列为空的文件有 0 个；这一列由脚本原样抄头注，不代写内容。

| 路径 | 声明的 module | 行数 | 文件头注第一行（逐字） |
| --- | --- | --- | --- |
| `src/ps/main.c` | `（无 module：C/H 或纯 include）` | 1643 | PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL（rtl/eth 目录）。 |
| `src/ps/sd_play.c` | `（无 module：C/H 或纯 include）` | 882 | SD 卡本地视频回放：裸机 FAT32 只读 + XSdPs，不依赖 FatFs / 任何文件系统库。 |
| `src/ps/sd_play.h` | `（无 module：C/H 或纯 include）` | 68 | SD 卡本地回放的 PS 侧接口（见 sd_play.c 与 report/log/overnight_log.md §P1）。 |
| `仓库留档 axi_frame_writer.v（剪枝件，不随包）` | axi_frame_writer | 169 | AXI3 HP0 整帧取数（64bit、最多 16 拍/突发）。警告 **本树无人例化**：现役两代是 |
| `src/rtl/axi/axi_frame_writer64.v` | axi_frame_writer64 | 116 | AXI3 HP read: DDR frame -> 64-bit BRAM writes, with overlapped bursts |
| `src/rtl/axi/axi_frame_writer_gated.v` | axi_frame_writer_gated | 191 | axi_frame_writer_gated：pl_video_top 里的 u_row —— 显示帧缓存的逐行搬运机：从 HP0 把 DDR 里刚提交 |
| `src/rtl/clocks/clk_gen.v` | clk_gen | 58 | MMCM: 50 MHz -> 50 MHz pixel + 250 MHz 5x + 200 MHz IDELAY ref |
| `src/rtl/eth/arp.v` | arp | 96 | arp — arp_rx + arp_tx + 一份 crc32_d8。 |
| `src/rtl/eth/arp_rx.v` | arp_rx | 182 | arp_rx — 从 GMII 收流里认 ARP 帧，取出对端的 MAC/IP。 |
| `src/rtl/eth/arp_tx.v` | arp_tx | 309 | arp_tx — 拼一帧 ARP 请求/应答并吐给 GMII 发送口。 |
| `仓库留档 axi_frame_saver.v（剪枝件，不随包）` | axi_frame_saver | 99 | AXI3 write master: one RGB565 pixel per beat (2-byte strobe) into DDR. |
| `src/rtl/eth/axi_frame_saver64.v` | axi_frame_saver64 | 185 | axi_frame_saver64 — AXI3 DDR 写入器（64bit 字）：AWLEN=0 + **写通道流水化**，AW/W 并行挂出、各自握手， |
| `src/rtl/eth/axi_frame_saver_burst.v` | axi_frame_saver_burst | 206 | AXI3 DDR writer v5: deep FIFO + consecutive-address bursts. |
| `src/rtl/eth/crc32_d8.v` | crc32_d8 | 92 | crc32_d8 — 一次一字节（8 bit）的以太网 CRC32 核，收/发两侧共用同一份、同一套约定。 |
| `src/rtl/eth/dc_fifo.v` | dc_fifo | 97 | Dual-clock FIFO (gray code). Width = DATA_W, depth = 2**ADDR_W. |
| `src/rtl/eth/ddr_bank_commit.v` | ddr_bank_commit | 82 | DDR 乒乓 bank 的「提交 / 换页」glue：frame_done（gmii 域）→ 3 级同步 + 边沿检测（axi 域）→ |
| `src/rtl/eth/eth_ctrl.v` | eth_ctrl | 168 | eth_ctrl — 发送仲裁：ARP/UDP/ICMP 三路共用一根 GMII 发送口， |
| `src/rtl/eth/eth_udp_video_top.v` | eth_udp_video_top | 389 | ETH UDP video top — ghosting-fix v5：DDR ping-pong + burst saver，提交脉冲带 completed base。 |
| `src/rtl/eth/frame_reasm.v` | frame_reasm | 223 | frame_reasm — commits a frame only if EVERY source row was written this frame; missing rows |
| `src/rtl/eth/gmii_rx_mac.v` | gmii_rx_mac | 119 | Minimal GMII RX MAC: strip preamble/SFD, output frame payload+FCS bytes; m_eof/m_good pulse |
| `src/rtl/eth/gmii_to_rgmii.v` | gmii_to_rgmii | 53 | gmii_to_rgmii — 纯连线壳：把厂商的 rgmii_rx / rgmii_tx 拼在一起，并让 gmii_tx_clk = gmii_rx_clk |
| `src/rtl/eth/icmp.v` | icmp | 116 | icmp — icmp_rx + icmp_tx + 一份 crc32_d8，做 ping 的应答通路。 |
| `src/rtl/eth/icmp_rx.v` | icmp_rx | 321 | icmp_rx — 从 GMII 收流里认 IPv4+ICMP，收 echo request 并备应答。 |
| `src/rtl/eth/icmp_tx.v` | icmp_tx | 456 | icmp_tx — 拼一帧 ICMP 回显应答（ping reply）发给对端。 |
| `src/rtl/eth/link_monitor.v` | link_monitor | 208 | link_monitor — ETH 入包链路的硬件在线健康统计：丢字数 / 作废帧 / 帧间隔 / 断流 ms。 |
| `src/rtl/eth/rgmii_rx.v` | rgmii_rx | 145 | rgmii_rx — RGMII(4bit DDR) → GMII(8bit SDR)。**采样沿这一处被改过**（#57/#80）。 |
| `src/rtl/eth/rgmii_tx.v` | rgmii_tx | 54 | rgmii_tx — GMII(8bit SDR) → RGMII(4bit DDR)。 |
| `src/rtl/eth/snap_cross.v` | snap_cross | 74 | snap_cross — 「准静态总线 + 跳变沿捕获」跨域器（ddr_bank_commit 用同一套路子）。 |
| `src/rtl/eth/sync_fifo.v` | sync_fifo | 51 | 同时钟 FIFO。定位：eth_udp_video_top 的 u_icmp_fifo（ICMP 请求字节，收/发两侧同一根 gmii 时钟）。 |
| `src/rtl/eth/udp_rx.v` | udp_rx | 216 | udp_rx — 从 GMII 收流里剥头，逐字节给 rec_en/rec_data/rec_byte_num。 |
| `src/rtl/eth/udp_rx_parser.v` | udp_rx_parser | 218 | Ethernet/IPv4/UDP filter. Byte-index state machine (easier to verify). |
| `src/rtl/eth/udp_tx.v` | udp_tx | 379 | udp_tx — 逐字节拼一帧 Ethernet + IPv4 + UDP 再吐给 GMII 发送口。 |
| `src/rtl/hdmi/rgb2dvi.v` | rgb2dvi | 54 | RGB888 + 同步 → HDMI TMDS 差分。定位：pl_video_top 的 u_dvi，吃的就是 osd_overlay 之后那一路 |
| `src/rtl/hdmi/tmds_encoder.v` | tmds_encoder | 77 | DVI/HDMI TMDS 8b/10b encoder (channel) |
| `src/rtl/hdmi/tmds_serializer.v` | tmds_serializer | 93 | 10:1 OSERDESE2 cascade (UG471): DATA_WIDTH=10 requires DATA_RATE_OQ=DDR |
| `src/rtl/process/bilin/fb_bilin.v` | fb_bilin | 200 | fb_bilin：显示侧唯一的帧缓存读口，做双线性插值。 |
| `src/rtl/process/bilin/fb_rd5x.v` | fb_rd5x | 159 | fb_rd5x —— 显示侧帧缓存读口"每像素 5 次读"那一版：50 MHz 像素时钟 + 同源 250 MHz 5 倍时钟，每个像素周期发 |
| `src/rtl/process/bilin/tap_sched.v` | tap_sched | 154 | tap_sched —— 帧缓存读口的"每像素周期 5 槽"调度器：右窗 1 个请求 → 4 个 RGB565 抽头 p00/p10/p01/p11 + |
| `src/rtl/process/bilin_lerp.v` | bilin_lerp | 72 | bilin_lerp —— 双线性插值的**算术核**：4 个 RGB565 抽头 + Q8 小数位 → 1 个 RGB565。与"抽头怎么取来"完全解耦 |
| `src/rtl/process/effect_ctrl.v` | effect_ctrl | 81 | 效果选择解码 + 跨域同步：AXI GPIO(GP0, 100 MHz) → 像素域(50 MHz)。两件活： |
| `src/rtl/process/proc_binary.v` | proc_binary | 37 | 级 4 阈值：亮度 >= threshold 出全白、否则全黑（pol 位反相）。放在滤波之后、形态学之前——形态学的定义 |
| `src/rtl/process/proc_box_blur.v` | proc_box_blur | 154 | 级 2 滤波的第一路：3×3 均值模糊（逐光栅，bypass 时出中心像素）。proc_pipeline 里占 **3 拍**、 |
| `src/rtl/process/proc_gray.v` | proc_gray | 36 | 级 1 颜色的第一路：RGB565 → 亮度 → 写回三个分量（去色）。proc_pipeline 里占 1 拍，~w_gray 时纯旁路。 |
| `src/rtl/process/proc_invert.v` | proc_invert | 29 | 级 1 颜色的第二路：RGB565 逐位取反。与 proc_gray **串接**（所以两个各占自己的 1 拍），~w_inv 时纯旁路。 |
| `src/rtl/process/proc_morph.v` | proc_morph | 146 | 级 5：形态学 —— 3×3 腐蚀 / 膨胀。放在阈值之后是因为它的定义就是"邻域内全 1 才 1 / 有 1 就 1"，本来就是 |
| `src/rtl/process/proc_pipeline.v` | proc_pipeline | 152 | proc_pipeline：显示通路的效果链，级 0 gamma + 级 1..5 五个可选级（八个算法位 + 一个判决反相位）， |
| `src/rtl/process/proc_sharpen.v` | proc_sharpen | 132 | 级 2 的第二个算法：3×3 锐化，卷积核 [0,-1,0 ; -1,5,-1 ; 0,-1,0]（四邻是上/下/左/右）。与 proc_box_blur |
| `src/rtl/process/proc_sobel.v` | proc_sobel | 156 | Sobel edge magnitude (Gx,Gy) on 3x3 window, output white edge on black |
| `src/rtl/process/rotate/angle_ctrl.v` | angle_ctrl | 47 | Angle control: KEY1 +1°, KEY2 -1°, wrap 0..359。V9-3 加三个口：`frame_tgl`（每个显示帧翻一次，像素域 |
| `src/rtl/process/rotate/cos_rom.v` | cos_rom | 373 | Auto-generated cos_rom: round(fn(angle_deg)*256), signed 10-bit |
| `src/rtl/process/rotate/rotate_mapper.v` | rotate_mapper | 67 | Inverse map display/canvas (x,y) -> source (sx,sy) for angle 0..359. |
| `src/rtl/process/rotate/sin_rom.v` | sin_rom | 373 | Auto-generated sin_rom: round(fn(angle_deg)*256), signed 10-bit |
| `src/rtl/process/zoom/zoom_ctrl.v` | zoom_ctrl | 145 | 无极缩放控制：原本尺寸(1.0x)为最大，向缩小方向循环再回到 1.0x。 |
| `src/rtl/process/zoom/zoom_fit.v` | zoom_fit | 62 | V9-2：按角度自动定缩放 —— "旋到哪个角度，就缩到刚好整个画面还在屏幕里"（用户 2026-09-25 提的那条）。 |
| `src/rtl/process/zoom/zoom_mapper.v` | zoom_mapper | 118 | 右屏无极缩放逆映射：屏幕 (x,y) → 源图 (sx,sy)。 |
| `src/rtl/process/zoom/zoom_snap.v` | zoom_snap | 48 | zoom_snap —— 把"像素域这一帧真正在用的缩放状态"打包成一条**准静态总线**并配上合法的跨域沿（V8-8 lane23）。 |
| `src/rtl/top/pl_demo_top.v` | pl_demo_top | 89 | Pure-PL demo top: colorbar + full 0-359 rotate + effects + HDMI dual pane. |
| `src/rtl/top/pl_video_top.v` | pl_video_top | 1051 | pl_video_top：显示通路顶层（system_top 里那份 PL 逻辑）。链路 = video_timing_1024x600 出时序 → |
| `src/rtl/top/system_top.v` | system_top | 323 | system_top：FPGA 顶层（构建脚本的 top）。design_1_wrapper(PS7+AXI) + clk_gen(IDELAY 参考) + |
| `src/rtl/util/key_debounce.v` | key_debounce | 72 | Active-low 按键消抖 + 单拍按下脉冲。定位：pl_video_top 的 u_k1/u_k2（板键 KEY1/KEY2，sys_clk 域）， |
| `src/rtl/util/key_long.v` | key_long | 48 | key_long —— "按住不放"检测器（与 `key_debounce` 配套，把同一个按键用出两种语义）。跑在 sys_clk 域。 |
| `src/rtl/util/ps_publish.v` | ps_publish | 34 | PS→PL "这一帧 DDR 写完了"的发布脉冲跨域 + 挂起。 |
| `src/rtl/util/shown_rate.v` | shown_rate | 65 | shown_rate —— OSD 的 `FPS:` 格：数**写进屏的新帧**，不是数扫过屏的显示场（ISSUES #128）。 |
| `src/rtl/util/src_arb.v` | src_arb | 80 | 片源仲裁：DDR→帧缓存 这一台搬运机，到底归 ETH 引擎还是归 PS(SD/FILL) 引擎。 |
| `src/rtl/util/src_life.v` | src_life | 59 | src_life —— "此刻到底还有没有片源"这件事的**活判据**（ISSUES #94）。时钟域：clk_pix，单域，零新增异步配对。 |
| `src/rtl/util/src_mode.v` | src_mode | 104 | src_mode：长按事件（sys_clk 域的翻转位）+ 串口覆盖命令 → 片源模式，输出本域的四态格雷码寄存器 mode。 |
| `src/rtl/video/color_bar.v` | color_bar | 71 | Built-in color bar + diagonal stripe (RGB565). Synthesis-friendly (no div). |
| `src/rtl/video/frame_buffer.v` | frame_buffer | 34 | 整帧双端口 BRAM（顺序写、随机读）。警告 **本树无人例化**：现役显示帧缓存是 frame_buffer_w64 |
| `仓库留档 frame_buffer_db.v（剪枝件，不随包）` | frame_buffer_db | 68 | 乒乓帧缓存。警告 **本树无人例化**：乒乓改在 DDR bank 层做（ddr_bank_commit + frame_reasm）， |
| `src/rtl/video/frame_buffer_w64.v` | frame_buffer_w64, integer | 83 | Display frame buffer: 64-bit write port (4 RGB565), 16-bit random read. 写 wr_clk / 读 rd_clk 两个域。 |
| `src/rtl/video/frame_commit_lock.v` | frame_commit_lock | 147 | frame_commit_lock —— 把"提交一帧"锁到显示消隐窗口里再搬（两个时钟域：axi_clk 搬、pix_clk 判窗口）。 |
| `src/rtl/video/frame_latency.v` | frame_latency | 198 | frame_latency：把"一帧提交 → 这一帧开始被扫描"分成三段量（c1 commit→copy_start、c2 copy_start→copy_done、 |
| `src/rtl/video/gamma_lut.v` | gamma_lut | 54 | 级 0：Gamma 查找表 —— 256 项 8-bit 表，PS 通过第二个控制字的通道 2 逐项写入。时钟域：像素域，读写都在 |
| `src/rtl/video/line_cache.v` | line_cache | 29 | 简单双端口行缓存（一 clk 写、另一 clk 读）。警告 **本树无人例化**：效果链里三行窗口用的是 |
| `src/rtl/video/osd_overlay.v` | osd_overlay | 526 | osd_overlay：像素通路的最后一级，把 5 行状态文字叠在画面上（尺寸/FPS/片源、Pipe/Th/Gamma、 |
| `src/rtl/video/raw_line_delay.v` | raw_line_delay, integer | 100 | raw_line_delay —— 把一路像素流整体延后 N 个显示行的行环形缓存（V8-4b，ISSUES #62 / #68）。单像素时钟，读写同拍。 |
| `src/rtl/video/seam_src.v` | seam_src | 51 | V9-1：把"缝"从**显示列**搬到**图像列** —— 分割线长在画面上，跟着旋转一起转（用户要的是"蓝线放在视频 |
| `src/rtl/video/split_ctrl.v` | split_ctrl | 131 | V8-4 分割线发生器：手工位置 + 自动三角扫描 + 端点(range)/速度(speed)/交换(swap)/跟随(follow)。 |
| `src/rtl/video/split_display.v` | split_display | 73 | Dual-pane: left original / right processed+zoomed. 单个像素时钟域，输出打一拍。 |
| `src/rtl/video/test_card.v` | test_card, disc | 201 | test_card —— 第三源（TEST）的"会动的画面"。时钟域：像素时钟。四样判读点：① 游动亮球 + 三段拖影 |
| `src/rtl/video/video_timing.v` | video_timing | 73 | 320x180 or 640x360 video timing generator |
| `src/rtl/video/video_timing_1024x600.v` | video_timing_1024x600 | 28 | 1024x600 @ ~60Hz, pixel clock 50 MHz (spec 50.25MHz, 0.5% ok) |
| `仓库留档 video_timing_720p.v（剪枝件，不随包）` | video_timing_720p | 27 | 720p 时序发生器。警告 **本树无人例化**：现役面板是 1024x600@50 MHz（video_timing_1024x600）。 |

MAP 生成 文件=83 头注缺=0 判 83 项 PASS

## 模块清单（`src/rtl/` 逐目录，照旧 `src-map.md` 原表搬）

上面那张表按文件给四列，这几张按 `src/rtl/` 的目录给「职责 / 例化者 / 台架」三列。
旧 `src-map.md` 要删掉，所以它的表头以下的每一格照原样抄在下面，行号、读数、`⇒`、被引的脚本锚点一个都没动。

这份表按 `src/rtl/` 的目录列出每个 RTL 文件是什么、被谁例化、有没有对应的仿真台架。
"台架"在下文一律指 `sim/` 下的 Verilog 测试例（testbench），它不跑在板上。读这张表之前先对齐三件事：

1. **例化者**一栏只写当前代码里真实存在的例化位置（`文件:行`）。写"未例化"就是从综合顶层不可达；
   写"仅台架"是只有 `sim/` 下的测试例例化它。这个判断另用综合日志复核了一遍：综合日志里的
   `Synth 8-6157`（`synthesizing module 'X'`）只对从顶层可达的模块出现，下面 13 个文件不在那些行里，
   复核脚本与它的通过条件写在 `仓库里的 orphan_rtl.sh（工具，不随包）:2-13`（它报的是"这一版构建里没有"，不是"永远没用"）——
   `axi_frame_saver`、`axi_frame_saver_burst`、`axi_frame_writer`、`color_bar`、`fb_rd5x`、
   `frame_buffer`、`frame_buffer_db`、`line_cache`、`pl_demo_top`、`rotate_mapper`、
   `tap_sched`、`udp_rx`、`video_timing_720p`（13 个）。
2. 综合收录的文件清单来自 `build/tcl/build_system_axigpio.tcl:24-30`（各目录整体 + 两个顶层），
   综合顶层是 `system_top`（同文件 `:288`）；不在这份清单里的文件谈不上可达性。
3. 原理、常数、时钟域、"改动某处要先看哪个台架"都在 `report/02-architecture.md`。

## top/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `system_top` | 板上顶层：PS Block Design + PL ETH + PL 视频三者的连线，lane 读回口在这一层 | 综合顶层 | 无（发布前检查第 14 项用 `build/check_ports.py` 检查接线） |
| `pl_video_top` | 显示主通路：栅格、几何、帧缓存读写、两条抽头、混合、OSD、TMDS、仲裁与观测 | `system_top.v:282`、`pl_demo_top.v:20` | `tb_video_pipeline_top`（唯一例化它的台架；发布前检查第 15 项读它的报告） |
| `pl_demo_top` | 无 PS 的纯 PL 演示顶层（GPIO 全钉常量） | 未例化，且不在构建清单里 | — |

## clocks/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `clk_gen` | `MMCME2_BASE`：50 → 50 / 250 / 200 MHz，VCO 1000 MHz | `pl_video_top.v:134`、`system_top.v:129` | — |

## axi/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `axi_frame_writer_gated` | ETH 路：DDR→显示帧缓存的整帧读回，只在 `allow_wr` 窗口内发 AR | `pl_video_top.v:460` | `tb_gated`、`tb_copy`、`tb_vblast`、`tb_first_ar`、`tb_full_done`、`tb_fb_vblank_copy` |
| `axi_frame_writer64` | PS 路：同一件事，由 `ps_frame_start` 触发起一次整帧搬运 | `pl_video_top.v:740` | 无独立台架 |
| `axi_frame_writer` | 16bit 宽度的早期版本 | 未例化 | 无 |

## video/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `video_timing` | 参数化栅格发生器（消隐/极性都可配），产出 `x,y,hs,vs,de,frame_start` | `video_timing_1024x600.v:17`、`video_timing_720p.v` | `tb_timing` |
| `video_timing_1024x600` | 本项目的显示时序：1024×600，H_TOTAL 1344 / V_TOTAL 625 | `pl_video_top.v:232` | `tb_fb_vblank_copy` 用（顶层由 `tb_video_pipeline_top` 覆盖） |
| `video_timing_720p` | 720p 时序 | 未例化 | — |
| `frame_buffer_w64` | 显示帧缓存：64bit 写口（4×RGB565）+ 16bit 随机读，读延迟 1 拍 | `fb_bilin.v:65`、`fb_rd5x.v:103` | `tb_fb_roundtrip` |
| `frame_buffer` / `frame_buffer_db` | 16bit 时代的整帧 RAM / 双缓冲 | 未例化 | 无（`tb_fb_roundtrip` 测的是 `frame_buffer_w64`） |
| `fb_bilin` | 显示侧唯一读口：双线性，每个源像素用满它天然的 4 个 50 MHz 拍；`bilin_en=0` 逐位等于最近邻 | `pl_video_top.v:780` | `tb_fb_bilinear` |
| `fb_rd5x` | 另一条读口方案（借 250 MHz 每像素发 5 次读），已被 `fb_bilin` 取代 | 未例化 | `tb_fb_rd5x` |
| `tap_sched` | `fb_rd5x` 的 5 槽调度器 | 仅被未例化的 `fb_rd5x` 例化 | `tb_tap_sched` |
| `bilin_lerp` | 双线性算术核（文件在 `process/` 下） | 见 process/ 表 | `tb_bilinear_core` |
| `raw_line_delay` | 原图抽头的行环形延迟：延迟恰 = LINES 行 + 1 拍且列不偏，消隐期钳读地址 | `pl_video_top.v:847（u_raw）、1015（u_seam_ring）` | `tb_raw_delay` |
| `frame_commit_lock` | 提交锁：`allow_copy` 只给消隐窗口、窗口开启才 `start_copy`、带看门狗 `copy_abort` + 翻转位 | `pl_video_top.v:436` | `tb_lock`、`tb_fb_vblank_copy`、`tb_abort_toggle` |
| `split_ctrl` | 分割线的**位置**发生器：手动百分比 / 自动扫描 / 跟随画面端点 / 交换两侧 | `pl_video_top.v:967` | `tb_split_ctrl` |
| `seam_src` | 把缝从显示列搬到图像列：在源坐标那一拍判定这一格属原图还是处理图，线跟着画面转 | `pl_video_top.v:1008` | 无独立台架（经 `tb_video_pipeline_top` 的 C1~C3 覆盖） |
| `split_display` | 逐像素二选一 + 2 图像列宽的标记线 + OOB 涂黑，输出一拍后的 RGB/de | `pl_video_top.v:1062` | `tb_seam_scan`（四份配置对照） |
| `osd_overlay` | 5 行状态叠加（面板/FPS/Src；Pipe/Th/Gamma、Rot/Zoom、Split/Latency、Temp/无信号），5×7 字模 ×3。`FPS:` 这一格数的是**写进屏的新帧**，计数器是 `src/rtl/util/shown_rate.v`，顶层例化在 `src/rtl/top/pl_video_top.v:1006`。这一格的计数写法换过一次：在换成数新帧之前，这一格数的是扫过屏的显示场 ⇒ 屏上恒读 59 或 60，那是面板场频不是片源帧率；两段的推导与验证记录在 `report/log/issues.md` #128、#157。端口 `osd_en`（0 = 输出逐位等于背景，由 `gpio_o[20]` 反相驱动） | `pl_video_top.v:1160` | `tb_osd_overlay`（T13 成对）、`tb_osd_glyph_rom`、`tb_video_pipeline_top` 的 C12 |
| `test_card` | 图卡片源：移动块 + 帧号二值格 + 八色彩条，自带"通路在不在刷新"的判读点 | `pl_video_top.v:807` | `tb_test_card`、`tb_card_render` |
| `color_bar` | 静止彩条（图卡的上一版） | 未例化 | `tb_test_card` 里作对照例化 |
| `gamma_lut` | 效果链级 0：256 项 8bit 表，PS 逐项目写入；组合读出、不加拍 | `proc_pipeline.v:144` | `tb_gamma` |
| `frame_latency` | 链路内时延：commit→起拷→拷完→该帧开始扫描，分三段量并在 axi 域除成 ms | `pl_video_top.v:623` | `tb_latency` |
| `line_cache` | 早期"左扫效果→右读行缓"的行列缓存 | 未例化 | 无 |

## hdmi/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `rgb2dvi` | RGB + de/hs/vs → 三路 TMDS：三套编码器 + 三套 5× 串化（channel0 走蓝，消隐期把 hs/vs 当控制符送进去） | `pl_video_top.v:1186` | — |
| `tmds_encoder` | 单通道 8b/10b：比较查表翻转 + 运行不一致度 + 特例码 | `rgb2dvi.v:22,26,30,25,29` | 无独立台架 |
| `tmds_serializer` | 10bit 并→串（跑在 `clk_pix5x` 上） | `rgb2dvi.v:35,39,43,49` 起 | 无独立台架 |

## process/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `proc_pipeline` | 级 0 gamma + 五级效果的装配：链延迟 `LATENCY`=15、内容滞后 `OFF_LINES`=4 都由它声明 | `pl_video_top.v:878` | `tb_pipe_sel`、`tb_align`、`tb_rotate_window`、`tb_osd_overlay` |
| `effect_ctrl` | AXI→像素域的准静态控制字同步（三对 `ASYNC_REG`）+ 九位 `stage_sel` 解码，只此一套口径 | `pl_video_top.v:204` | `tb_pipe_sel` |
| `proc_gray` | 级 1：RGB565 → 亮度 → RGB565 | `proc_pipeline.v:151` | `tb_proc_gray` |
| `proc_invert` | 级 1 的第二选项：反色 | `proc_pipeline.v:155` | 无独立台架（`tb_v86`/`tb_v89` 覆盖） |
| `proc_box_blur` | 级 2：3×3 均值模糊，两条行缓存、三拍 de 链 | `proc_pipeline.v:161` | `tb_morph`、`tb_sharpen`、`tb_align`、`tb_seam_bleed`、`tb_display_edge_rim` |
| `proc_sharpen` | 级 2 的第二选项：3×3 锐化（与模糊同级、非串联） | `proc_pipeline.v:167` | `tb_sharpen`、`tb_align`、`tb_display_edge_rim` |
| `proc_sobel` | 级 3：Sobel 梯度幅值，白边黑底 | `proc_pipeline.v:174` | `tb_align`、`tb_seam_bleed`、`tb_display_edge_rim` |
| `proc_binary` | 级 4：阈值二值化，`pol` 选判决方向（亮于/暗于阈值算白） | `proc_pipeline.v:182` | 无独立台架（`tb_v86` 逐档、`tb_v89` 整链） |
| `proc_morph` | 级 5：3×3 腐蚀 / 膨胀；两位同时为 1 时明确旁路 | `proc_pipeline.v:188` | `tb_morph`、`tb_align`、`tb_display_edge_rim` |
| `bilin_lerp` | 双线性算术核，两级流水（先横后纵），与抽头怎么来完全解耦 | `fb_bilin.v:172` | `tb_bilinear_core` |

## process/rotate/ 与 process/zoom/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `angle_ctrl` | 角度寄存器：短按 ±1°、自动旋转按帧走 `speed[2:0]` 度、0..359 环回 | `pl_video_top.v:189` | `tb_fit_rot`（T3） |
| `sin_rom` / `cos_rom` | 360 项 Q8 三角表（角度 0..359，值是 10 位有符号：`cos(0)=10'sd256`，不是 255） | `zoom_mapper.v:22`、`zoom_fit.v:20` | — |
| `rotate_mapper` | 独立的旋转逆映射器 | 未例化（旋转已并进 `zoom_mapper`） | `tb_rotate_mapper` |
| `zoom_mapper` | 唯一的视口逆映射：缩放 ⊕ 旋转同级，3 级流水，出 `sx,sy,oob,frac_x,frac_y` | `pl_video_top.v:349` | `tb_zoom_mapper`、`tb_zoom_scan` |
| `zoom_ctrl` | 缩放来源选择与自动呼吸：八档表 + 手动档 + 拟合档，外加旋转态那一钳：旋转生效时倍率不许超出 fit 档，整幅画面因此在屏内，代价是旋转时不给放大，手动档号不丢；`inv_used` 是唯一读数、`rot_forced` 只喂 OSD 的 `(Fit)` | `pl_video_top.v:331` | `tb_zoom_sel`（T8a~T8f）、`tb_fit_rot`、`tb_zoom_mapper` |
| `zoom_fit` | 按角度算出"刚好装得下"的 `inv_fit` | `pl_video_top.v:328` | `tb_fit_rot` |
| `zoom_snap` | 把像素域真在用的缩放状态打成准静态总线 + 合法跨域沿，供 lane23 回读 | `pl_video_top.v:651` | `tb_zoom_snap` |

## util/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `key_debounce` | 低有效按键消抖 + 单拍脉冲（`CNT_MAX` 由调用处给） | `pl_video_top.v:142,145` | 无独立台架 |
| `key_long` | 同一按键的长按语义：短按松手才发、长按发**翻转位** | `pl_video_top.v:154` | `tb_key_long` |
| `src_mode` | 长按翻转位 → 四态片源模式（自动/锁 ETH/锁 SD/锁图卡），命令覆盖优先于按键 | `pl_video_top.v:163` | `tb_src_mode` |
| `src_arb` | DDR→帧缓存这台搬运机归谁：交换条件 + "两个引擎都空闲"才换手 + 让位延时 | `pl_video_top.v:427` | `tb_src_arb` |
| `src_life` | "此刻还有没有片源"的在线条件：PS 发布心跳 500 ms 看门狗，没有就落图卡 | `pl_video_top.v:587` | `tb_src_life` |
| `ps_publish` | PS 发布翻转位的跨域 + 挂起：一次发布恰好一次消费 | `pl_video_top.v:563` | `tb_ps_publish` |

## eth/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `eth_udp_video_top` | RGMII→协议栈→拼帧→CDC→打包写 DDR 的容器，含乒乓基址与提交脉冲 | `system_top.v:174` | `tb_fb_pingpong`、`tb_eth_ingress_integrity`、`tb_bank`、`tb_link_monitor` |
| `gmii_to_rgmii` | RGMII ↔ GMII 的壳：BUFG 收钟 + IDELAYCTRL + 收/发两侧 | `eth_udp_video_top.v:125` | — |
| `rgmii_rx` | IDDR(`SAME_EDGE_PIPELINED`) **吃 BUFG**（IO 与 fabric 现在共用同一棵钟树）+ IDELAYE2(FIXED, 参考 200 MHz, `IDELAY_VALUE=31`) | `gmii_to_rgmii.v:48` | — |
| `rgmii_tx` | ODDR 双沿拼 4bit + TX_CTL | `gmii_to_rgmii.v:82` | — |
| `gmii_rx_mac` | 去前导/SFD、按字节数与自己算的 FCS-32 判包好坏，出 `m_good/m_bad` | `eth_udp_video_top.v:271` | `tb_rx_fcs` |
| `udp_rx_parser` | 按下标解 IPv4/UDP + 目的端口过滤，出 `p_sof/p_eof/p_good` | `eth_udp_video_top.v:282` | `tb_udp_parser`、`tb_rx_chain` |
| `frame_reasm` | `[u32 LE offset][RGB565]` 拼帧：凑满 307200 B 才算一帧，坏帧计数、缺行上报 | `eth_udp_video_top.v:326` | `tb_udp_reasm`、`tb_rows`、`tb_rows_prod`、`tb_cover_gate`、`tb_link_monitor` |
| `dc_fifo` | eth_rxc→axi_clk 的 36bit 数据 FIFO（格雷码 + 双级同步，BRAM 推断） | `eth_udp_video_top.v:446` | `tb_fb_pingpong`、`tb_eth_ingress_integrity`、`tb_tail_bank` |
| `axi_frame_saver64` | 16bit→64bit 打包 + AXI3 写 DDR：`AWLEN=0` 的单拍写、AW/W 并行挂出、在途 OST=8（B 只回收计数） | `eth_udp_video_top.v:502` | `tb_bank`、`tb_fb_pingpong`、`tb_tail_bank`、`tb_eth_ingress_integrity` |
| `ddr_bank_commit` | 换 bank 必须等本帧数据全部穿过 CDC，之后发 `commit_pulse` + 完成基址 | `eth_udp_video_top.v:478` | `tb_fb_pingpong`、`tb_tail_bank` |
| `link_monitor` | 链路健康计数：丢字、坏包、缺行、断流 ms、帧间隔 min/last/max/Σ，打包 10 条 lane + 心跳 | `eth_udp_video_top.v:432` | `tb_link_monitor` |
| `eth_ctrl` | 发送侧仲裁与 GMII 出口复用（ARP/ICMP/UDP 三路） | `eth_udp_video_top.v:291` | 没有仿真台架直接例化这一层：原先那支单测随第二块板（RK-XCKU5P-F）的工程目录一并移出仓库，因此这一层只被顶层台架的端到端路径覆盖，这一列没有独立条目。另有一处缺口要写明：它的通用用户 FIFO 口在本层没有对端——`fifo_tx_data`/`fifo_tx_req`/`fifo_rec_en`/`fifo_rec_data` 只在 `eth_udp_video_top.v:114-116` 声明、`:219-220` 连进来，本层再没有别的驱动或读者 |
| `snap_cross` | 「准静态总线 + 跳变沿」跨域器，带心跳丢失/变慢两种上报 | `system_top.v:238`、`pl_video_top.v:673,895,1036` | `tb_link_monitor`、`tb_zoom_snap` |
| `sync_fifo` | 同钟 FIFO（读出寄存一拍、空满比指针最高位；存储无异步复位 + `ram_style=block`） | `eth_udp_video_top.v:196`（ICMP 载荷） | `tb_sync_fifo` |
| `crc32_d8` | 反射 CRC-32 逐字节核 | `udp_tx.v`、`gmii_rx_mac.v`、`arp.v`、`icmp.v` | `tb_crc32` |
| `udp_tx` | 以太/IP/UDP 头的组装与发送（`udp_tx.v:44-47` 那批常数：`ETH_TYPE`、`MIN_DATA_NUM`）；FCS 由外挂的 `crc32_d8` 算、它填进帧尾。Z7 上 `tx_start_en` 恒 0：接着但从不启动 | `eth_udp_video_top.v:248` | `tb_eth_video` |
| `arp` → `arp_rx` / `arp_tx` | who-has 请求与应答，MAC/IP 由参数给（外部样例那一批，文件头 `arp.v:3,7`） | `eth_udp_video_top.v:203` → `arp.v:46,62` | — |
| `icmp` → `icmp_rx` / `icmp_tx` | echo reply，载荷走下面的 `sync_fifo`（同一批外部样例） | `eth_udp_video_top.v:217` → `icmp.v:56,76` | — |
| `udp_rx` | 外部样例的收侧包装层 | 未例化（收侧换成了上面的自研那一对） | `tb_eth_video` 仍直接测它 |
| `axi_frame_saver` / `axi_frame_saver_burst` | 16bit 与早期 burst 两版打包器 | 未例化 | `tb_saver`（测 `_burst`） |

### 并表留下的几处，需发起者判定

1. 那张四列表的来路写在 `report/src-map.md:3`：「这张表由 `node 仓库留档 r120_src_map.mjs（剪枝件，不随包）` 生成，
   输出重定向进 `report/src-map.md`」。生成器的 stdout（`仓库留档 r120_src_map.mjs（剪枝件，不随包）:51-70`）只出四列表那一张，
   102 行往后的按目录的表与口径说明都不在它的产出里 —— 重定向是整份覆盖，谁再跑一次，
   这几张表和那段口径说明就一起没了。
2. 同一页 `:9-12` 划的边界是「这些数据由各自的文档单点维护，这张表只提供四列，免得同一份数据出现两个口径」，
   并且把台架指给 `sim/README.md`（「台架（`sim/` 下的仿真测试例）与模块的对应关系看 `sim/README.md`」）。
   按目录那几张表带的正是「职责／例化者／台架」三列，现在同一份数据在这页有两处、
   台架那一列还和 `sim/README.md` 重叠。要不要留、以哪份为准，需发起者判定。
3. 旧 `modules.md` 删掉后，指着它做行号锚点的引文要改：`report/timing/eth_tx_decoupling_inventory.md:183`、
   `:350`、`:387` 引的是旧 `modules.md` §eth/ 那一行（`eth_ctrl` 那一行的台架格），这一格现在在
   `report/src-map.md:230`，按号引用得重指。
4. `report/figures/legend.md:29` 与 `report/figures/fig-01-system-level.txt:104` 说的是「旧 `modules.md` §口径说明 第 1 条」，
   指的是那段口径说明的第 1 条（13 个未进本版构建的 RTL 点名那一处）；那一条的原文照抄在四列表之后，没动。
5. 目录归属与盘上路径不一致的（原表照抄，一格没改）：`## video/` 那张里的 `fb_bilin`、`fb_rd5x`、`tap_sched`
   盘上在 `src/rtl/process/bilin/`；`bilin_lerp` 在 `## video/` 与 `## process/` 各占一行，
   前者的例化者格写的是「见 process/ 表」。
6. 覆盖对账（`git ls-files 'src/rtl/*.v' | wc -l` = 80）：四列表 80 个 .v 每个都有一行；
   按目录那几张表 73 行，点到 79 个文件 —— `arp`/`icmp` 两行各写三个名字，
   `frame_buffer` / `frame_buffer_db`、`sin_rom` / `cos_rom`、`axi_frame_saver` / `axi_frame_saver_burst`
   三行各两个文件。剩下一个 `src/rtl/util/shown_rate.v` 在按目录的表里没有自己的行，只在 `osd_overlay`
   那一格正文里被点名（它的 `src/rtl/top/pl_video_top.v:1006` 例化行也在那一格）。
   两份清单都没列到的 .v 文件：0 个。

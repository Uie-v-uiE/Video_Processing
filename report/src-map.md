# 源码地图（`src/` 逐文件的四列现算表）

这张表由 `node build/r120_src_map.mjs` 生成，输出重定向进 `report/src-map.md`，覆盖 83 个源文件。
表里的文件数与 git 跟踪的 `src/` 下 *.v/*.c/*.h 数量由脚本现算并比对，两个数不一致时脚本拒绝出图。

## 这四列的用途与边界

- 四列是：文件路径、头注里声明的 module 名、行数、头注第一行原文。头注那一列逐字搬运，不改写。
- 数据流顺序、时钟域归属、寄存器位序都不在这张表里，那些数由各自的文档单点维护，免得同一份数据出现两个口径。
  数据通路看 架构章，时钟域看 `report/board_pins.md` 与 `report/build.md`，寄存器看
  `skills/runtime/register-map-and-readback/SKILL.md`，仿真测试例（`sim/` 下那批）与模块的对应关系看 `sim/README.md`。
- 头注列为空的文件有 0 个；这一列由脚本原样抄头注，不代写内容。

| 路径 | 声明的 module | 行数 | 文件头注第一行（逐字） |
| --- | --- | --- | --- |
| `src/ps/main.c` | `（无 module：C/H 或纯 include）` | 1619 | PS control plane + SD 卡本地回放。UDP 视频数据通路仍然整个在 PL（rtl/eth 目录）。 |
| `src/ps/sd_play.c` | `（无 module：C/H 或纯 include）` | 882 | SD 卡本地视频回放：裸机 FAT32 只读 + XSdPs，不依赖 FatFs / 任何文件系统库。 |
| `src/ps/sd_play.h` | `（无 module：C/H 或纯 include）` | 68 | SD 卡本地回放的 PS 侧接口（见 sd_play.c 与 夜轮记录 §P1）。 |
| `src/rtl/axi/axi_frame_writer.v` | axi_frame_writer | 169 | AXI3 HP0 整帧取数（64bit、最多 16 拍/突发）。警告 **本树无人例化**：现役两代是 |
| `src/rtl/axi/axi_frame_writer64.v` | axi_frame_writer64 | 116 | AXI3 HP read: DDR frame -> 64-bit BRAM writes, with overlapped bursts |
| `src/rtl/axi/axi_frame_writer_gated.v` | axi_frame_writer_gated | 191 | axi_frame_writer_gated：pl_video_top 里的 u_row —— 显示帧缓存的逐行搬运机：从 HP0 把 DDR 里刚提交 |
| `src/rtl/clocks/clk_gen.v` | clk_gen | 58 | MMCM: 50 MHz -> 50 MHz pixel + 250 MHz 5x + 200 MHz IDELAY ref |
| `src/rtl/eth/arp.v` | arp | 96 | arp — arp_rx + arp_tx + 一份 crc32_d8。 |
| `src/rtl/eth/arp_rx.v` | arp_rx | 182 | arp_rx — 从 GMII 收流里认 ARP 帧，取出对端的 MAC/IP。 |
| `src/rtl/eth/arp_tx.v` | arp_tx | 309 | arp_tx — 拼一帧 ARP 请求/应答并吐给 GMII 发送口。 |
| `src/rtl/eth/axi_frame_saver.v` | axi_frame_saver | 99 | AXI3 write master: one RGB565 pixel per beat (2-byte strobe) into DDR. |
| `src/rtl/eth/axi_frame_saver64.v` | axi_frame_saver64 | 177 | axi_frame_saver64 — AXI3 DDR 写入器（64bit 字）：AWLEN=0 + **写通道流水化**，AW/W 并行挂出、各自握手， |
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
| `src/rtl/video/frame_buffer_db.v` | frame_buffer_db | 68 | 乒乓帧缓存。警告 **本树无人例化**：乒乓改在 DDR bank 层做（ddr_bank_commit + frame_reasm）， |
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
| `src/rtl/video/video_timing_720p.v` | video_timing_720p | 27 | 720p 时序发生器。警告 **本树无人例化**：现役面板是 1024x600@50 MHz（video_timing_1024x600）。 |

MAP 生成 文件=83 头注缺=0 判 83 项 PASS

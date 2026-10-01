# 模块清单（`src/rtl/` 逐目录）

读这份表的三条口径：

1. **例化者**一栏只写当前代码里真实存在的例化位置（`文件:行`）。写"未例化"就是从这个顶层不可达；
   写"仅台架"是只有 `sim/` 下的测试例化它。这个集合用综合日志复核过：下面 13 个文件不出现在
   `Synth 8-6157` 行里（口径与判据见 `build/orphan_rtl.sh:2-13`）——
   `axi_frame_saver`、`axi_frame_saver_burst`、`axi_frame_writer`、`color_bar`、`fb_rd5x`、
   `frame_buffer`、`frame_buffer_db`、`line_cache`、`pl_demo_top`、`rotate_mapper`、
   `tap_sched`、`udp_rx`、`video_timing_720p`（13 个）。
2. 综合收的文件清单 = `build/tcl/build_system_axigpio.tcl:12-17`（各目录整体 + 两个顶层），
   顶层 = `system_top`（同文件 `:232`）；不在清单里的可达性无从谈起。
3. 原理、常数、时钟域、门禁对应关系都在 `report/ARCHITECTURE.md`，这里不重复。

## top/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `system_top` | 板上顶层：PS Block Design + PL ETH + PL 视频三者的连线，lane 读回口在这一层 | 综合顶层 | 无（第 14 项 `check_ports.py` 判接线） |
| `pl_video_top` | 显示主通路：栅格、几何、帧缓存读写、两条抽头、混合、OSD、TMDS、仲裁与观测 | `system_top.v:248`、`pl_demo_top.v:20` | `tb_v98_top_seam`（唯一例化它的台架，门禁第 15 项认其报告） |
| `pl_demo_top` | 无 PS 的纯 PL 演示顶层（GPIO 全钉常量） | 未例化，且不在构建清单里 | — |

## clocks/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `clk_gen` | `MMCME2_BASE`：50 → 50 / 250 / 200 MHz，VCO 1000 MHz | `pl_video_top.v:128`、`system_top.v:121` | — |

## axi/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `axi_frame_writer_gated` | ETH 路：DDR→显示帧缓存的整帧读回，只在 `allow_wr` 窗口内发 AR | `pl_video_top.v:428` | `tb_v5_gated`、`tb_v5_copy`、`tb_v5_vblast`、`tb_v57_first_ar`、`tb_v58_full_done`、`tb_v6_vblank_copy` |
| `axi_frame_writer64` | PS 路：同一件事，由 `ps_frame_start` 触发起一次整帧搬运 | `pl_video_top.v:666` | 无独立台架 |
| `axi_frame_writer` | 16bit 宽度的早期版本 | 未例化 | 无 |

## video/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `video_timing` | 参数化栅格发生器（消隐/极性都可配），产出 `x,y,hs,vs,de,frame_start` | `video_timing_1024x600.v:17`、`video_timing_720p.v` | `tb_timing` |
| `video_timing_1024x600` | 本项目的显示时序：1024×600，H_TOTAL 1344 / V_TOTAL 625 | `pl_video_top.v:226` | `tb_v6_vblank_copy` 用（顶层由 `tb_v98` 覆盖） |
| `video_timing_720p` | 720p 时序 | 未例化 | — |
| `frame_buffer_w64` | 显示帧缓存：64bit 写口（4×RGB565）+ 16bit 随机读，读延迟 1 拍 | `fb_bilin.v:65`、`fb_rd5x.v:103` | `tb_fb_roundtrip` |
| `frame_buffer` / `frame_buffer_db` | 16bit 时代的整帧 RAM / 双缓冲 | 未例化 | 无（`tb_fb_roundtrip` 测的是 `frame_buffer_w64`） |
| `fb_bilin` | 显示侧唯一读口：双线性，每个源像素用满它天然的 4 个 50 MHz 拍；`bilin_en=0` 逐位等于最近邻 | `pl_video_top.v:706` | `tb_v101_fb_bilin` |
| `fb_rd5x` | 另一条读口方案（借 250 MHz 每像素发 5 次读），已被 `fb_bilin` 取代 | 未例化 | `tb_fb_rd5x` |
| `tap_sched` | `fb_rd5x` 的 5 槽调度器 | 仅被未例化的 `fb_rd5x` 例化 | `tb_tap_sched` |
| `bilin_lerp` | 双线性算术核（文件在 `process/` 下） | 见 process/ 表 | `tb_bilin_lerp` |
| `raw_line_delay` | 原图抽头的行环形延迟：延迟恰 = LINES 行 + 1 拍且列不偏，消隐期钳读地址 | `pl_video_top.v:762` | `tb_v100_raw_delay` |
| `frame_commit_lock` | 提交锁：`allow_copy` 只给消隐窗口、窗口开启才 `start_copy`、带看门狗 `copy_abort` + 翻转位 | `pl_video_top.v:404` | `tb_v5_lock`、`tb_v6_vblank_copy`、`tb_v79_abort_toggle` |
| `split_ctrl` | 分割线的**位置**发生器：手动百分比 / 自动扫描 / 跟随画面端点 / 交换两侧 | `pl_video_top.v:859` | `tb_v93_split_ctrl` |
| `seam_src` | 把缝从显示列搬到图像列：在源坐标那一拍判定这一格属原图还是处理图，线跟着画面转 | `pl_video_top.v:878` | 无独立台架（经 `tb_v98` 的 C1~C3 覆盖） |
| `split_display` | 逐像素二选一 + 2 图像列宽的标记线 + OOB 涂黑，输出一拍后的 RGB/de | `pl_video_top.v:885` | `tb_v97_seam_scan`（四份配置对照） |
| `osd_overlay` | 5 行状态叠加（面板/FPS/Src——`FPS` 数的是**写进屏的新帧**（`src/rtl/util/shown_rate.v`，顶层例化在 `src/rtl/top/pl_video_top.v:915`；#128 改的口径。⚠ 板上那一版 r97 仍是显示场计数 ⇒ 读数还是 59/60，改完要等 r99 上板才算数（r98 被门禁拒了、没上板））；Pipe/Th/Gamma、Rot/Zoom、Split/Latency、Temp/无信号），5×7 字模 ×3；端口 `osd_en`（0 = 输出逐位等于背景，由 `gpio_o[20]` 反相驱动） | `pl_video_top.v:973` | `tb_osd_lines`（T13 成对）、`tb_v794_osd_glyph`、`tb_v98` 的 C12 |
| `test_card` | 图卡片源：移动块 + 帧号二值格 + 八色彩条，自带"通路在不在刷新"的判读点 | `pl_video_top.v:733` | `tb_v81_test_card`、`tb_v83_card_render` |
| `color_bar` | 静止彩条（图卡的上一版） | 未例化 | `tb_v81_test_card` 里作对照例化 |
| `gamma_lut` | 效果链级 0：256 项 8bit 表，PS 逐项目写入；组合读出、不加拍 | `proc_pipeline.v:102` | `tb_v88_gamma` |
| `frame_latency` | 链路内时延：commit→起拷→拷完→该帧开始扫描，分三段量并在 axi 域除成 ms | `pl_video_top.v:598` | `tb_v90_latency` |
| `line_cache` | 早期"左扫效果→右读行缓"的行列缓存 | 未例化 | 无 |

## hdmi/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `rgb2dvi` | RGB + de/hs/vs → 三路 TMDS：三套编码器 + 三套 5× 串化（channel0 走蓝，消隐期把 hs/vs 当控制符送进去） | `pl_video_top.v:1000` | — |
| `tmds_encoder` | 单通道 8b/10b：比较查表翻转 + 运行不一致度 + 特例码 | `rgb2dvi.v:22,26,30,25,29` | 无独立台架 |
| `tmds_serializer` | 10bit 并→串（跑在 `clk_pix5x` 上） | `rgb2dvi.v:35,39,43,49` 起 | 无独立台架 |

## process/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `proc_pipeline` | 级 0 gamma + 五级效果的装配：链延迟 `LATENCY`=15、内容滞后 `OFF_LINES`=4 都由它声明 | `pl_video_top.v:774` | `tb_v86_pipe_sel`、`tb_v89_align`、`tb_rotate_window`、`tb_osd_lines` |
| `effect_ctrl` | AXI→像素域的准静态控制字同步（三对 `ASYNC_REG`）+ 九位 `stage_sel` 解码，只此一套口径 | `pl_video_top.v:198` | `tb_v86_pipe_sel` |
| `proc_gray` | 级 1：RGB565 → 亮度 → RGB565 | `proc_pipeline.v:109` | `tb_proc_gray` |
| `proc_invert` | 级 1 的第二选项：反色 | `proc_pipeline.v:113` | 无独立台架（`tb_v86`/`tb_v89` 覆盖） |
| `proc_box_blur` | 级 2：3×3 均值模糊，两条行缓存、三拍 de 链 | `proc_pipeline.v:119` | `tb_v84_morph`、`tb_v85_sharpen`、`tb_v89_align`、`tb_v92_seam_bleed`、`tb_edge_rim` |
| `proc_sharpen` | 级 2 的第二选项：3×3 锐化（与模糊同级、非串联） | `proc_pipeline.v:125` | `tb_v85_sharpen`、`tb_v89_align`、`tb_edge_rim` |
| `proc_sobel` | 级 3：Sobel 梯度幅值，白边黑底 | `proc_pipeline.v:132` | `tb_v89_align`、`tb_v92_seam_bleed`、`tb_edge_rim` |
| `proc_binary` | 级 4：阈值二值化，`pol` 选判决方向（亮于/暗于阈值算白） | `proc_pipeline.v:140` | 无独立台架（`tb_v86` 逐档、`tb_v89` 整链） |
| `proc_morph` | 级 5：3×3 腐蚀 / 膨胀；两位同时为 1 时明确旁路 | `proc_pipeline.v:146` | `tb_v84_morph`、`tb_v89_align`、`tb_edge_rim` |
| `bilin_lerp` | 双线性算术核，两级流水（先横后纵），与抽头怎么来完全解耦 | `fb_bilin.v:172` | `tb_bilin_lerp` |

## process/rotate/ 与 process/zoom/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `angle_ctrl` | 角度寄存器：短按 ±1°、自动旋转按帧走 `speed[2:0]` 度、0..359 环回 | `pl_video_top.v:183` | `tb_v100_fit_rot`（T3） |
| `sin_rom` / `cos_rom` | 360 项 Q8 三角表（角度 0..359，值是 10 位有符号：`cos(0)=10'sd256`，不是 255） | `zoom_mapper.v:22`、`zoom_fit.v:20` | — |
| `rotate_mapper` | 独立的旋转逆映射器 | 未例化（旋转已并进 `zoom_mapper`） | `tb_rotate_mapper` |
| `zoom_mapper` | 唯一的视口逆映射：缩放 ⊕ 旋转同级，3 级流水，出 `sx,sy,oob,frac_x,frac_y` | `pl_video_top.v:317` | `tb_zoom_mapper`、`tb_v96_zoom_scan` |
| `zoom_ctrl` | 缩放来源选择与自动呼吸：八档表 + 手动档 + 拟合档，外加旋转态那一钳（#93：生效倍率不许超出 fit ⇒ 整幅在屏内，代价是旋转时不给放大，档号不丢），`inv_used` 是唯一读数、`rot_forced` 只喂 OSD 的 `(Fit)` | `pl_video_top.v:299` | `tb_v94_zoom_sel`（T8a~T8f）、`tb_v100_fit_rot`、`tb_zoom_mapper` |
| `zoom_fit` | 按角度算出"刚好装得下"的 `inv_fit` | `pl_video_top.v:296` | `tb_v100_fit_rot` |
| `zoom_snap` | 把像素域真在用的缩放状态打成准静态总线 + 合法跨域沿，供 lane23 回读 | `pl_video_top.v:626` | `tb_v95_zoom_snap` |

## util/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `key_debounce` | 低有效按键消抖 + 单拍脉冲（`CNT_MAX` 由调用处给） | `pl_video_top.v:136,139,139` | 无独立台架 |
| `key_long` | 同一按键的长按语义：短按松手才发、长按发**翻转位** | `pl_video_top.v:148` | `tb_v87_key_long` |
| `src_mode` | 长按翻转位 → 四态片源模式（自动/锁 ETH/锁 SD/锁图卡），命令覆盖优先于按键 | `pl_video_top.v:157` | `tb_v82_src_mode` |
| `src_arb` | DDR→帧缓存这台搬运机归谁：判据 + "两个引擎都空闲"才换手 + 让位延时 | `pl_video_top.v:395` | `tb_v796_src_arb` |
| `src_life` | 活判据"此刻还有没有片源"：PS 发布心跳 500 ms 看门狗，没有就落图卡 | `pl_video_top.v:562` | `tb_v102_src_life` |
| `ps_publish` | PS 发布翻转位的跨域 + 挂起：一次发布恰好一次消费 | `pl_video_top.v:538` | `tb_ps_publish` |

## eth/

| 模块 | 职责 | 例化者 | 台架 |
|------|------|--------|------|
| `eth_udp_video_top` | RGMII→协议栈→拼帧→CDC→打包写 DDR 的容器，含乒乓基址与提交脉冲 | `system_top.v:154` | `tb_v6_pingpong`、`tb_v6_ingress_integrity`、`tb_v5_bank`、`tb_link_monitor` |
| `gmii_to_rgmii` | RGMII ↔ GMII 的壳：BUFG 收钟 + IDELAYCTRL + 收/发两侧 | `eth_udp_video_top.v:73` | — |
| `rgmii_rx` | IDDR(`SAME_EDGE_PIPELINED`) **吃 BUFG**（#57 之后 IO 与 fabric 同一棵树）+ IDELAYE2(FIXED, 参考 200 MHz, `IDELAY_VALUE=26`) | `gmii_to_rgmii.v:28` | — |
| `rgmii_tx` | ODDR 双沿拼 4bit + TX_CTL | `gmii_to_rgmii.v:42` | — |
| `gmii_rx_mac` | 去前导/SFD、按字节数与自己算的 FCS-32 判包好坏，出 `m_good/m_bad` | `eth_udp_video_top.v:186` | `tb_v795_rx_fcs` |
| `udp_rx_parser` | 按下标解 IPv4/UDP + 目的端口过滤，出 `p_sof/p_eof/p_good` | `eth_udp_video_top.v:197` | `tb_udp_parser`、`tb_v795_rx_chain` |
| `frame_reasm` | `[u32 LE offset][RGB565]` 拼帧：凑满 307200 B 才算一帧，坏帧计数、缺行上报 | `eth_udp_video_top.v:235` | `tb_udp_reasm`、`tb_v50_rows`、`tb_v50_rows_prod`、`tb_v6_cover_gate`、`tb_link_monitor` |
| `dc_fifo` | eth_rxc→axi_clk 的 36bit 数据 FIFO（格雷码 + 双级同步，BRAM 推断） | `eth_udp_video_top.v:298` | `tb_v6_pingpong`、`tb_v6_ingress_integrity`、`tb_v6_tail_bank` |
| `axi_frame_saver64` | 16bit→64bit 打包 + AXI3 写 DDR：`AWLEN=0` 的单拍写、AW/W 并行挂出、在途 OST=8（B 只回收计数） | `eth_udp_video_top.v:354` | `tb_v5_bank`、`tb_v6_pingpong`、`tb_v6_tail_bank`、`tb_v6_ingress_integrity` |
| `ddr_bank_commit` | 换 bank 必须等本帧数据全部穿过 CDC，之后发 `commit_pulse` + 完成基址 | `eth_udp_video_top.v:330` | `tb_v6_pingpong`、`tb_v6_tail_bank` |
| `link_monitor` | 链路健康计数：丢字、坏包、缺行、断流 ms、帧间隔 min/last/max/Σ，打包 10 条 lane + 心跳 | `eth_udp_video_top.v:284` | `tb_link_monitor` |
| `eth_ctrl` | 发送侧仲裁与 GMII 出口复用（ARP/ICMP/UDP 三路） | `eth_udp_video_top.v:206` | **没有台架例化本层**（原来那支单测随 KU5P 那棵树一并撤出，2026-09-28）⇒ 它的行为只由顶层台架端到端覆盖，本行的"验证"栏因此是空的。它的用户收发口在本层无下游：`fifo_tx_*`/`fifo_rec_*` 只在 `:111-113` 声明、`:218-219` 连线 |
| `snap_cross` | 「准静态总线 + 跳变沿」跨域器，带心跳丢失/变慢两种上报 | `system_top.v:204`、`pl_video_top.v:648,850,954,850,954` | `tb_link_monitor`、`tb_v95_zoom_snap` |
| `sync_fifo` | 同钟 FIFO（读出寄存一拍、空满比指针最高位；存储无异步复位 + `ram_style=block`） | `eth_udp_video_top.v:119`（ICMP 载荷） | `tb_sync_fifo` |
| `crc32_d8` | 反射 CRC-32 逐字节核 | `udp_tx.v`、`gmii_rx_mac.v`、`arp.v`、`icmp.v` | `tb_crc32` |
| `udp_tx` | 以太/IP/UDP 头的组装与发送（`udp_tx.v:52` 那批常数）；FCS 由外挂的 `crc32_d8` 算、它填进帧尾。Z7 上 `tx_start_en` 恒 0：接着但从不启动 | `eth_udp_video_top.v:163` | `tb_eth_video` |
| `arp` → `arp_rx` / `arp_tx` | who-has 请求与应答，MAC/IP 由参数给（外部样例那一批，文件头 `arp.v:3,7`） | `eth_udp_video_top.v:126` → `arp.v:46,62` | — |
| `icmp` → `icmp_rx` / `icmp_tx` | echo reply，载荷走下面的 `sync_fifo`（同一批外部样例） | `eth_udp_video_top.v:140` → `icmp.v:56,76` | — |
| `udp_rx` | 外部样例的收侧包装层 | 未例化（收侧换成了上面的自研那一对） | `tb_eth_video` 仍直接测它 |
| `axi_frame_saver` / `axi_frame_saver_burst` | 16bit 与早期 burst 两版打包器 | 未例化 | `tb_v5_saver`（测 `_burst`） |

# 系统架构（Zynq-7020 主线）

器件 `xc7z020clg484-2`、综合顶层 `system_top`（`build/tcl/build_system_axigpio.tcl:16,288`）、
Vivado / Vitis 2025.2.1。架构描述以当前源码为准，每条断言给 `文件:行号`；逐轮改动的过程记录在
`report/log/issues.md`、`report/log/overnight_log.md`（追加式记录文件）。
第二块板（RK-XCKU5P-F）的工程目录 `ku5p/` 已在 2026-09-28 移出仓库，所以架构描述的范围只有 Zynq7020
这一块板。

## 1. 数据从哪里来、到哪里去

三路片源里只有前两路过 DDR。ETH 那路由 PL 自己收包、自己当 AXI 主设备写进 DDR 的乒乓
bank，PS 全程不碰这些字节；SD 回放那路由 PS 的 SD 控制器 DMA 写进**第三个** bank，PL 只在
收到发布翻转位之后把它搬上屏；图卡那路根本不进内存，由 PL 按同一份源坐标现场画。
三路在"进帧缓存"这一层由仲裁器选一路（决定搬运引擎归谁），在"像素从哪来"这一层再由 `fb_vis`
选一次（帧缓存还是图卡，`src/rtl/top/pl_video_top.v:595`）。读出之后立刻分叉成两条抽头：原图抽头
过一条 4 显示行的行延迟环，处理抽头过 15 拍的特效链；两条在同一拍上并排站着，由分割线逐像素
二选一，再叠 OSD、编 TMDS 出屏。

```
片源（三路）                      写侧（进 DDR）                    读侧与显示（clk_pix = 50 MHz）
─────────────                    ────────────                      ────────────────────────────
 PC ─UDP:5001─► RGMII ─► gmii_rx_mac ─► udp_rx_parser ─► frame_reasm
                      (eth_rxc 125 MHz：自算 FCS-32、按目的端口过滤)
                                                                    │ {flush,addr[18:0],data[15:0]}
                                                                    ▼
                                              dc_fifo（格雷码指针，eth_rxc → axi_clk）
                                                                    ▼
                                              axi_frame_saver64（16b→64b 打包 + AXI3 写 HP0）
                                                                    │
 SD 卡 ─► PS 固件 sd_play.c ─► SD 控制器 DMA ─┐   DDR：PS bank 0x1010_0000 ｜ ETH 乒乓 0x1000_0000、0x1008_0000
                                             │                     ▼
                       发布位 gpio_o[18] 翻转 ─┤      frame_commit_lock（提交锁到消隐窗口 + 看门狗）
                                             │                     │ allow_copy / start_copy / copy_abort
                                             ▼                     ▼
                     axi_frame_writer64(PS) 或 axi_frame_writer_gated(ETH)，按 owner_eth 复用读口
                                             └────────┬───────────┘  64bit 整帧
                                                      ▼
                       frame_buffer_w64（实例在 fb_bilin 里）← 一条地址流、一份坐标
                                                      │  cx = x>>1 ，cy_r = (y + OFF + BILIN)>>1
                                                      ▼
                                zoom_mapper 逆映射（缩放 ⊕ 旋转，Q8 sin/cos）→ sx,sy,frac,oob
                                                      │
                                          fb_bilin（bilin_en 选双线性 / 最近邻）→ fb_rd
                                                      │
   图卡 test_card（PL 现场画，吃同一份 sx,sy）───────► pix_raw = oob ? 黑 : (fb_vis ? fb_rd : 图卡)
                                                      │
                    ┌─────────────────────────────────┴──────────────────────────────┐
                    ▼ 原图抽头                                                        ▼ 处理抽头
        raw_line_delay（4 行环，17 位含 oob 标签）                    proc_pipeline（stage_sel[8:0]，15 拍）
                    │ 再串 PROC_LAT 拍 skid                              │ 再打一拍
                    └────────────────────────┬───────────────────────────┘
                                             ▼
                    split_display 逐像素二选一（缝位来自 split_ctrl，图像域时由 seam_src 判定）
                                             ▼
                                osd_overlay（5 行）──► rgb2dvi ──► TMDS 1024×600
```

`src/rtl/top/pl_video_top.v:241-247` 是"整屏一个视口"那段：1024 个显示列对应 512 个源列、
600 个显示行对应 300 个源行，左右两半从此共用同一份源坐标，`left_pane` 只剩调试用途。

## 2. 时钟与复位

| 时钟 | 频率 | 来源 | 谁用 |
|------|------|------|------|
| `sys_clk` | 50 MHz（周期 20 ns，引脚 W17） | 板载振荡器，`src/constraints/rk_zynq7020.xdc:5-6` | MMCM 输入、按键、心跳/LED；OSD 的 `FPS:` 那一格的计数口径在这个域与 `clk_pix` 之间改过一次，见下一行 |
| `clk_pix` = `clkout0` | 50 MHz | MMCM CLKOUT0 ÷20，`src/rtl/clocks/clk_gen.v:21` | 栅格、映射、特效链、混合、OSD、`shown_rate`（OSD `FPS:` 那一格现在数"写进屏的新帧"，`src/rtl/util/shown_rate.v`，顶层例化 `src/rtl/top/pl_video_top.v:941`；在这一格改成数新帧之前，它数的是扫过屏的显示场，也就是约 60 Hz 的面板场频 ⇒ 屏上恒读 59 或 60。两种计数口径的推导与验证记录在 `report/log/issues.md` #128、#157 两节） |
| `clk_pix5x` = `clkout1` | 250 MHz | MMCM CLKOUT1 ÷4，`clk_gen.v:24` | TMDS 串化（`rgb2dvi`） |
| `clk_200m` = `clkout2` | 200 MHz | MMCM CLKOUT2 ÷5，`clk_gen.v:27` | IDELAYCTRL 参考 |
| `axi_clk` = `clk_fpga_0` | 100 MHz | PS FCLK0，`system_top.v:83` | AXI 读写、GPIO、两个搬运引擎 |
| `eth_rxc` → `gmii_rx_clk` | 125 MHz（引脚 Y19，`rk_zynq7020.xdc:20,36`） | PHY2 RGMII，经 BUFG | 整个收包协议栈 + frame_reasm |

MMCM 是 `MMCME2_BASE`，VCO = 50 × 20 = 1000 MHz（`clk_gen.v:15-31`）。`pl_video_top` 与
`system_top` 各例化一只 `clk_gen`（`pl_video_top.v:128`、`system_top.v:121`），后者只取 200 MHz 那一路。

复位：`rst_pix_n = sys_rst_n & locked`（`pl_video_top.v:132`），MMCM 失锁即整条像素链一起停；
`axi_rst_n` 用 PS 的 `FCLK_RESET0_N`（`system_top.v:250-251`，该处 `sys_rst_n` 恒接 1'b1）；
ETH 侧 `rst_n = eth_rst_n & mmcm_locked`（`system_top.v:163`），`eth_rst_n` 由 24 位计数器
的 bit23 给出，即 2^23 / 50 MHz ≈ 168 ms（`system_top.v:108-112`）。

跨域做法按被搬运的对象分四类，没有共用的通用 CDC IP：

- 单 bit 准静态电平 → 2~3 级 `ASYNC_REG`（`pl_video_top.v:212-222` 缩放使能、`effect_ctrl.v:38-43` 三对同步器）
- 脉冲 → 先转翻转位、目的域 3 级 + 异拍出沿（`key_long`→`src_mode`、`ps_publish`、`frame_commit_lock.v:106-108` 的 `abort_tgl`）
- 宽总线 → `snap_cross`「准静态总线 + 跳变沿」：源域整拍写总线并翻 toggle，目的域等同步沿再采
  （`system_top.v:202`、`pl_video_top.v:648,850,954`，接口约定写在 `src/rtl/eth/snap_cross.v:2-8`）；
  像素域→axi 域的缩放快照先由 `zoom_snap` 打包并配独立心跳触发器（`pl_video_top.v:624-643`）
- 16 bit 视频流 eth_rxc → axi_clk → `dc_fifo` 格雷码指针 + 双级同步（BRAM 推断，`eth_udp_video_top.v:298`）

异步时钟组的声明**不在**功能约束里，单独放 `src/constraints/clock_groups_impl.xdc`，且
`used_in_synthesis false`（`build/tcl/build_system_axigpio.tcl:36-37`）—— `clk_fpga_0` 由 PS7 IP 自己的 XDC
创建，综合阶段还不存在。`sys_clk` 那一组必须带 `-include_generated_clocks`，否则 `clk_pix` 会被当成
独立钟去和 `eth_rxc` 做 setup 分析；该文件 13-17 行的注释记着这条历史：漏掉后缀时读到过一条几 ns 量级的
假违例（`report/log/issues.md` #18）。

## 3. 软硬件划分

数据面全在 PL：收包、拼帧、写 DDR、读回、帧缓存、几何、特效、混合、OSD、TMDS。
PS 做三件事：发命令、读计数、把 SD 卡上的帧 DMA 进自己那块 DDR（零拷贝，写完只翻一次发布位，
`src/host/ps/sd_play.c:13-20`）。PS 不中转任何 ETH 视频字节。

| 通道 | 地址 | 方向 | 内容 |
|------|------|------|------|
| `axi_gpio_0`（`gpio_o`） | `0x41200000` | PS→PL | 阈值 `[15:8]`、`src_sel[16]`、`zoom_en[17]`、发布位 `[18]`、双线性 `[19]`、OSD 关 `[20]`（**反相**，1 = 关掉叠层，`pl_video_top.v:267-279` 那一条独立 3 级链）、片源模式码 `[24:23]`+翻转 `[22]`、lane 选择 `[31:27]`（`src/host/ps/main.c:47`、`system_top.v:261-289`） |
| `axi_gpio_2` 通道 1 | `0x41220000` | PS→PL | 九位 `stage_sel[8:0]`、几何控制字 `[22:13]`/`[25:23]`/`[9]`/`[12:10]`/`[30]`/`[31]`、缩放档 `[28:26]`、手动旗标 `[29]`（`main.c:71-72`、`system_top.v:265-272`） |
| `axi_gpio_2` 通道 2 | `0x41220000 + 0x08` | PS→PL | gamma 表窗口 `{en,wr,data[29:22],idx[21:14]}` + 只给 OSD 的 `gamma_disp`/温度（`main.c:79-96`、`pl_video_top.v:32-34`） |
| `axi_gpio_1`（`GPIO_1_tri_i`） | `0x41210000` | PL→PS | 32 位状态窗口，**命令写 gpio_o、状态读这一只**（`build/tcl/build_system_axigpio.tcl:223-226,245-246`） |

状态通道是"先写 lane 号再读一个字"的窗口：lane 号取 `gpio_o[31:27]`，读回 `gpio1_i`。
lane0~9 是链路健康计数（`src/rtl/eth/link_monitor.v:187-196`），lane23 是像素域真正在用的缩放
状态，lane24~29 是时延快照，lane30 是仲裁输入，lane31 是 ETH 时基健康（`system_top.v:227-236`）。
`lat_arm` 就是"lane 指到 25"这一拍，用来把五个时延字同时抄进一份自洽快照（`system_top.v:226`）。

## 4. 关键常数

| 常数 | 值 | 出处 |
|------|----|------|
| 源（帧缓存）尺寸 | 512 × 300，RGB565，一帧 307200 B | `pl_video_top.v:9-10`、`src/rtl/eth/frame_reasm.v:9-11` |
| 显示尺寸 / 时序 | 1024 × 600，H_TOTAL 1344、V_TOTAL 625，像素钟 50 MHz 代 50.25 MHz | `src/rtl/video/video_timing_1024x600.v:2-4,17-20` |
| 视口映射 | 1 源列 = 2 显示列（`cx = x>>1`）、1 源行 = 2 显示行 | `pl_video_top.v:245-247` |
| 效果链延迟 `LATENCY` | 15 拍（1+1+3+3+3+1+3），与旁路组合无关 | `src/rtl/process/proc_pipeline.v:22` |
| 效果链内容滞后 `OFF_LINES` | 4 行（四个窗口级各 −1） | `proc_pipeline.v:27` |
| 混合域 `MIX_D` | 3 + 1 + 1 + LATENCY = 20（顶层只从 `u_pipe.LATENCY` 取） | `pl_video_top.v:354` |
| 原图行延迟环 | 深 = `u_pipe.OFF_LINES` = 4 行、宽 `W = 2*IMG_W` = 1024、位宽 17（像素+oob 同环） | `pl_video_top.v:781,788` |
| 双线性额外行 `BILIN_ROWS` | 2 显示行（乒乓读口一对结果下一对才读得到），必须为偶数 | `pl_video_top.v:253-254` |
| 缝判定抽头 `SEAM_TAPS` | `MIX_D + 1 - 3` = 18 | `pl_video_top.v:902` |
| 缩放范围 | `INV_LO`=256（1.0×）↔ `INV_HI`=512（0.5×），`STEP`=2，三角波按帧走 | `pl_video_top.v:325`、`zoom_ctrl.v:3-8` |
| 手动档 / 拟合档 | 八档表按 `inv_used` 分界（900/644/427/299/224/182/150）；`fit_en` 时 inv 由角度定。旋转生效时 inv 还要被钳进 fit 那一档：`angle_ctrl.v` 明写 `rotate_active = (angle != 0)`，只要角度非 0（自动旋转逐 1° 也算）钳制就在，整幅画面因此永远在屏内；代价是旋转态不提供放大，手动 1.33x/1.5x/2.0x 会被拉回 fit 档，但档号不丢；**0° 不钳** —— 角度为 0 时这条钳制整个解除 | `src/rtl/process/zoom/zoom_ctrl.v`（分界与旋转钳制都在本文件）、`zoom_fit.v:2-7` |
| 端口 / 地址 | UDP 5001、板 MAC `00-11-22-33-44-55`、IP 192.168.1.10 | `system_top.v:145,158-159` |
| DDR bank | ETH 乒乓 `0x1000_0000` / `+0x0008_0000`；PS 专用 `0x1010_0000` | `src/rtl/eth/eth_udp_video_top.v:67-68`、`pl_video_top.v:12-16` |
| 消隐拷贝窗口 | `disp_quiet` 从第 600 行起、末行只到 `x ≤ 1279`；判超用的门限 67200 个 axi 拍 | `pl_video_top.v:400,446` |
| 片源看门狗 | PS 心跳超时 500 ms；ETH 让位静默 2×10^6 个 axi 拍 = 20 ms | `pl_video_top.v:586,421` |
| 链路存活判定 | `LIVE_MS` = 200 ms @125 MHz（`stall_ms < 200` 即 lane7.bit3） | `eth_udp_video_top.v:284-286`、`system_top.v:241-246` |
| 按键 | 消抖计数 10^6（20 ms）；长按 3×10^7 = 0.6 s，松开臂 10^7 = 0.2 s | `pl_video_top.v:136-148` |
| RGMII 输入延迟 | `IDELAY_VALUE` = **31**（FIXED 抽头，参考 200 MHz ⇒ 每拍 156 ps）。这一档原本是 26：IDDR 与 fabric 合到同一棵钟树之后，按 `4.854−3.171=1.683 ns` 补了 +11 拍；后来在同一份已布线设计上把 FIXED 抽头的可用档位逐档扫了一遍，取收口窗最宽的那一档，于是 26 抬到 31。扫描的读数、它买到多少、两端仍是违例读数，全部在 `report/05-timing.md` 的"片外到达窗"一节 | `src/rtl/top/system_top.v:172`、`src/rtl/eth/rgmii_rx.v:68-71`、`report/timing/round_r118.md` §一 |
| OSD 版式 | 5 行（`N_LINES`）、5×7 字模 ×3 放大（18×21）、每行 32 格、起点 (16,12) | `src/rtl/video/osd_overlay.v:9-19` |

## 5. 改哪里要看什么

发布前检查脚本 `build/gates.sh` 逐项打印结果，"第 N 项"就是它按打印顺序编号的那一项。其中被 md5
绑定的仿真台架（`sim/` 下的 Verilog 测试例，不跑在板上）只有两个：第 15 项（打印名"顶层台架 tb_v98"）认 `build/tb_v98_report.txt` 头部的
`top_md5`（`src/rtl/top/pl_video_top.v`）、`rtl_md5`（整棵 `src/rtl` 的合指纹）与 `tb_md5`
（`sim/tb_v98_top_seam.v`）三枚，缺一即判未通过（`build/gates.sh:293-357`）；紧随其后的第 15b 项
（打印名"边缘条带 tb_edge_rim"）同样认 `sim/tb_edge_rim.v` 与同一枚 RTL 合指纹
（`gates.sh:367-401`）。改过 `src/rtl` 里任何一个文件，这两份报告在复跑之前都会被判未通过。

| 改动位置 | 先看哪个台架 | 对应的发布前检查项 |
|----------|--------------|----------|
| `top/pl_video_top.v`、`top/system_top.v` | `tb_v98_top_seam`（唯一例化顶层的台架，一趟 40+ 帧） | 第 15 项读它的报告；第 14 项 `build/check_ports.py` 检查端口名/悬空输入/位宽 |
| 四个窗口级（`proc_box_blur`/`sharpen`/`sobel`/`morph`） | `tb_v89_align`（位置）、`tb_edge_rim`（边缘内容）、`tb_v92_seam_bleed` | 15b 读 `tb_edge_rim` 的报告，并要求四条边缘带的覆盖率不低于既定下限 |
| `proc_pipeline` 的级数 / `LATENCY` | `tb_v86_pipe_sel`（实测 de_in→de_out 与声明值对账） | 顶层 `MIX_D`、`PROC_LAT` 都从它推，改一次三处跟着动 |
| `fb_bilin` / `bilin_lerp` / `frame_buffer_w64` | `tb_v101_fb_bilin`、`tb_bilin_lerp`、`tb_fb_roundtrip` | 经 15 项的 `rtl_md5` 生效 |
| `raw_line_delay` | `tb_v100_raw_delay` | 同上 |
| `split_ctrl` / `split_display` / `seam_src` | `tb_v93_split_ctrl`、`tb_v97_seam_scan` | 分割线的最终凭据是 15 项报告里的 `tb_v98` C1~C3 三行 |
| `zoom_ctrl` / `zoom_fit` / `zoom_mapper` / `zoom_snap` | `tb_v94_zoom_sel`、`tb_v100_fit_rot`、`tb_v96_zoom_scan`、`tb_v95_zoom_snap` | — |
| ETH 收包链（`gmii_rx_mac`/`udp_rx_parser`/`frame_reasm`） | `tb_v795_rx_fcs`、`tb_v795_rx_chain`、`tb_udp_reasm`、`tb_v50_rows*` | — |
| DDR 写/读与提交（`axi_frame_saver64`/`ddr_bank_commit`/`frame_commit_lock`/两个 writer） | `tb_v6_pingpong`、`tb_v6_tail_bank`、`tb_v6_vblank_copy`、`tb_v5_lock`、`tb_v79_abort_toggle` | — |
| 片源仲裁与心跳（`src_arb`/`src_mode`/`src_life`/`ps_publish`） | `tb_v796_src_arb`、`tb_v82_src_mode`、`tb_v102_src_life`、`tb_ps_publish` | 第 16 项 `src/host/ps_hb_check.mjs --self` 检查固件那一侧的约定 |
| `osd_overlay` | `tb_osd_lines`、`tb_v794_osd_glyph` | — |
| `link_monitor` / `snap_cross` | `tb_link_monitor` | — |
| 手写文档的编码、文档里的数字是否还指向当前构建 | 无需台架 | 第 17 项 `src/host/doc_enc_check.mjs`、第 18 项 `src/host/doc_currency_check.mjs`、第 19 项把排练脚本与讲稿抽取结果逐行比对 |
| 约束、CDC 结构 | 无需台架 | 第 1~11 项读 Vivado 报告；第 6 项拿 `build/cdc_baseline.txt` 的**配对集合**做比较，新增配对或 unsafe 数增长即判未通过 |

## 6. 未覆盖的范围与数字出处

- 板上实测数字与逐时钟时序读数的落点：时序口径与逐域余量在 `report/05-timing.md`，
  资源、功耗、帧率等数字在 `data/metrics.csv`。
- 已知未覆盖项：RGMII 收口的 `eth_rx_ctl` 与四根 `eth_rxd` 数据线这 5 个输入端点当前没有输入延迟约束，
  片外那一段的余量因此不在任何一张检查表里，详见 `report/05-timing.md` 第 6 节。

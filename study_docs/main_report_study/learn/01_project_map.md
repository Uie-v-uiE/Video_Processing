# 01 · 项目地图：信号从哪进、经过谁、从哪出

这一章回答三个问题：**数据走哪条路**、**PS 与 PL 各管什么、接口在哪**、
**改一处东西会牵到哪些地方、有什么会立刻变红**。读完应该能在别人问"这个功能在哪实现"时
说出文件名，并且知道改它之前先跑哪条命令。

写作基线：这一版是**照着当前这棵树重画的**，与工程一起改过；文中每一条 `文件:行`
都是这一轮在盘上 grep 或 Read 确认过的。行号会随提交漂移，对不上时以信号名重新 grep
（每条引用旁边我都同时给了信号名）。凡与旧稿不一致的地方，集中记在 §12。

---

## 1. 一句话与一张数据流

一颗 Zynq-7020（`xc7z020clg484-2`，Vivado / Vitis 2025.2.1）。三路片源里两路过 DDR、
一路不进内存：网口收到的是 UDP 视频包（PL 自己收、自己拼帧、自己当 AXI 主设备写 DDR，
PS 全程不碰这些字节），SD 卡那路由 PS 的 SD 控制器 DMA 写进第三个 bank，片内图卡那路由 PL
现场按同一份源坐标画出来。三路在"进帧缓存"这一层由仲裁器选一路，在"像素从哪来"这一层再选一次
（帧缓存还是图卡）。读出之后立刻分叉成两条抽头：原图抽头过一条 4 显示行的行环形缓存，
处理抽头过 15 拍的效果链；两条在同一拍并排站着，由分割线**逐像素**二选一，再叠 OSD、
编 TMDS 出屏到 1024×600。PS 做三件事：发命令、读计数、把 SD 上的帧 DMA 进自己那块 DDR。

```
片源（三路）                    写侧（进 DDR，axi_clk 100 MHz）        读侧与显示（clk_pix 50 MHz）
─────────────                  ─────────────────────────────         ──────────────────────────────
 PC ─UDP:5001─► RGMII
   └► gmii_rx_mac(自算 FCS-32) ─► udp_rx_parser(端口过滤) ─► frame_reasm(逐行验收)
                                              │ 36bit{flush,addr,data}
                                              ▼
                                    dc_fifo（格雷码，eth_rxc → axi_clk）
                                              ▼
                              axi_frame_saver64（16→64bit 打包 + AXI3 写 HP0）
                                              │  乒乓 bank 0x1000_0000 / +0x0008_0000
 SD 卡 ─► PS 固件 sd_play.c ─► SD DMA ────────┐│  PS 专用 bank 0x1010_0000
                发布位 gpio_o[18] 翻转 ───────┤│
                                              ▼▼
                        frame_commit_lock（提交锁进消隐窗口 + 看门狗）
                                              │ allow_copy / start_copy / copy_abort
                                              ▼
             axi_frame_writer_gated(ETH 路) 或 axi_frame_writer64(PS 路)，按 owner 复用同一个 AXI 读口
                                              │ 64bit 整帧
                                              ▼
        frame_buffer_w64（实例在 fb_bilin 里）← 一条地址流、一份源坐标
                                              │  cx = x>>1 ，cy_r = ((y+OFF+BILIN)>>1) mod IMG_H
                                              ▼
                     zoom_mapper 逆映射（缩放 ⊕ 旋转，Q8 三角表）→ sx,sy,frac,oob
                                              │
                        fb_bilin（bilin_en 选双线性 / 最近邻，单读口每源像素 4 拍）
                                              │
  test_card（PL 现场画，吃同一份 sx,sy）─────► pix_raw = oob ? 黑 : (fb_vis ? 帧缓存 : 图卡)
                                              │
              ┌───────────────────────────────┴────────────────────────────┐
              ▼ 原图抽头                                                   ▼ 处理抽头
   raw_line_delay（4 显示行环，17bit 含 oob 标签）        proc_pipeline（gamma + 五级可选，15 拍）
              │ 再串 PROC_LAT 拍 skid                                  │ 再打一拍
              └───────────────────────────┬───────────────────────────┘
                                          ▼
              split_display 逐像素二选一（缝在显示列 or 图像列，由 seam_src/split_ctrl 供）
                                          ▼
              osd_overlay（5 行状态）──► rgb2dvi ──► TMDS 4 对差分 ──► HDMI 1024×600

   PS(Arm)：UART 命令 → axi_gpio_0/2（控制）；lane 窗口 ← axi_gpio_1（状态）；SD DMA（数据）
```

"同一份源坐标同时喂两条抽头"是本项目的立足点：缝左边是原图、右边是同一坐标系下处理后的图，
逐像素对齐，所以任何一条边缘、一次错位都能在同一帧里被看见。它既是演示手段，也是调试仪器 ——
后面第 20、60 章反复用这一点。

## 2. 目录地图：哪些目录真的有东西

```
Video_Processing/
├── src/rtl/{top,video,process,eth,hdmi,clocks,axi,util}   79 个 .v，设计源码
│                         └ process/{zoom,rotate,bilin}    几何与双线性单独成目录
├── src/ps/          Arm 裸机固件：main.c(1525) + sd_play.c(878) + sd_play.h + lscript_ocm.ld
├── src/constraints/ rk_zynq7020.xdc（功能约束）+ clock_groups_impl.xdc（只在实现阶段生效）
├── src/host/        23 个 .mjs：推流、回读、比对、文档自检；没有 Python
├── sim/             63 个 tb_*.v + prim/（MMCM 等原语的仿真占位件）+ run_sim.tcl / run_one.sh
├── build/           门禁 gates.sh、冻结 freeze_evidence.sh、板级验收 board_verify.sh、tcl/、
│                    报告 *.rpt、rNN_gates.txt、evidence_rNN/ 与 frozen_rNN/（凭据，别清）
├── board/           上板操作卡 README.md / HANDS_ON.md、串口脚本 *.ps1、回读 tcl、evidence_rNN/
├── data/            golden/ 参考图与实测数据 measured/
├── report/            **交付文档**（ARCHITECTURE / MODULES / COMMANDS / PERF_REPORT / …）
│   ├── log/         **工作记录**：ISSUES.md、OVERNIGHT_LOG.md、版本谱系（追加式，会过期）
│   └── study/       **本地学习文档**（不进 git）：00_前置知识…06_自测 中文那一套 + 本目录 learn/
└── skill/           与大模型协作沉淀的方法包（每项四段，换题目也能用的那一层）
```

三条容易被旧文档误导的话，先说在前面：

- **没有 `report/` 这个目录。** 交付文档在 `report/`，工作记录在 `report/log/`
  （`report/README.md:5-9` 就是这张分派表）。凡是 `report/xxx.md` 的写法都是搬家之前的路径。
- **仓库里不再有第二块板。** KU5P（`xcku5p`）那棵独立工程树连同它的构建脚本、台架
  （`tb_ku5p_*`）与上位机（`src/host/ku5p_*.mjs`）在 2026-09-28 整体删除了，本套文档之后
  不再提"跨器件移植"这条线。想复核：`ls` 里应当没有 `ku5p/`，`ls src/host` 与 `ls sim` 里
  应当没有任何 ku5p 字样。
- **上位机只剩 Node.js 与 PowerShell。** `video_sender.py`、`serial_ctrl.py`、
  `make_test_mjpeg.py`、`requirements.txt` 和三个 `run_*.bat` 都删了
  （`build/` 下那两份 `.py` 是静态判据，不是上位机）。今天只有：
  推流 `node src/host/video_sender.mjs`，真实视频用根目录的 `stream_video.bat`
  （ffmpeg 解成 512×300 RGB565 裸流，管道喂 `--file -`），串口
  `board/uart_cmd_script.ps1`（从文件按行读命令）与 `board/uart_cap_once.ps1`
  （`-Cmds "A,B"` 那种一次性的）。口径见 `report/HOST_GUIDE.md:3-10`。

## 3. 三个顶层，只有一个会进板子

| 文件 | 角色 | 谁例化它 |
|---|---|---|
| `src/rtl/top/system_top.v`（305 行） | 板上真正的顶层。端口就是 PS 固定外设（`DDR_*`、`FIXED_IO_*`）、`sys_clk`、两个按键、两个 LED、`tmds_*` 四对差分、RGMII（`eth_rxc/rx_ctl/rxd/tx_clk/tx_ctl/txd/mdc/mdio`）与 `eth_rst_n` | 综合顶层（`build/tcl/build_system_axigpio.tcl` 里 `set top`） |
| `src/rtl/top/pl_video_top.v`（994 行） | 显示主通路的全部逻辑：栅格、几何、帧缓存读写、两条抽头、混合、OSD、TMDS、仲裁与观测 | `system_top.v:242-243`（`u_pl`）；台架侧唯一例化它的是 `sim/tb_v98_top_seam.v` |
| `src/rtl/top/pl_demo_top.v`（86 行） | 无 PS 的纯 PL 演示顶层，GPIO 全钉常量。**不在构建清单里、没进位流**，改视频通路时不要误当入口 | 无人例化 |

`system_top` 内部三块：Block Design 的封装 `design_1_wrapper u_bd`（`system_top.v:74`）、
PL 侧以太网视频 sink `eth_udp_video_top u_eth`（`:150`）、显示主通路 `u_pl`（`:242`）。
BD 里是 PS7 + AXI 互联 + 三只 AXI GPIO，`FCLK_CLK0` 就是 100 MHz 的 `axi_clk`
（`:82`），GPIO 三只分别是 `GPIO_0_tri_o`（`:83`，PS→PL 控制字）、
`GPIO_1_tri_i`（`:84`，PL→PS 状态窗口的 32 bit）、`GPIO_2/GPIO_3_tri_o`（`:85-86`，
第二个控制字的两个通道）。PHY 复位不靠 PS：`:107-111` 那一段用一个 24 位计数器
在 `sys_clk` 上数到 bit23，即约 2^23 / 50 MHz ≈ 168 ms 后释放 `eth_rst_n`；
以太网侧真正用的复位是 `eth_rst_n & mmcm_locked`（`:159`）。

还有一件容易看漏的事：`system_top` 自己又例化了一只 `clk_gen`
（`system_top.v:117`，`u_idelay_clkgen`），**只取 200 MHz 那一路**给 IDELAYCTRL 当参考，
另外两路输出接了不用的线（`:115`）。也就是说全设计里有两只 MMCM：一只在
`pl_video_top.v:124` 的 `u_clk`（产生 50 MHz 像素钟与 250 MHz 串行钟），一只在这里。

## 4. `pl_video_top` 的实例清单（按行号读，别按名字猜顺序）

这一张表是本工程最重要的一张。用 `u_` 前缀命名是有意的：`grep -n "^\\s*u_[a-z0-9_]*\\s*(" src/rtl/top/pl_video_top.v`
一次就能列全，改完顶层第一件事就是拿它对照本表。

| 实例 | 行 | 模块 | 一句话 | 时钟域 |
|---|---|---|---|---|
| `u_clk` | 124 | `clk_gen` | MMCM：50 进 → 50 像素 / 250 五倍串行 / 200 IDELAY 参考 | sys_clk |
| `u_k1` / `u_k2` | 132 / 135 | `key_debounce` | 两个板上按键消抖，`CNT_MAX=1_000_000`（20 ms @50 MHz） | sys_clk |
| `u_k1l` | 144 | `key_long` | 同一个按键的两种语义：松手短按 = 旋转 ±1°，长按 0.6 s = 换片源模式；出**翻转位** | sys_clk |
| `u_mode` | 153 | `src_mode` | 长按事件 + 串口覆盖命令 → 四态片源模式 `mode` | clk_pix |
| `u_ang` | 179 | `angle_ctrl` | 角度累加（0..359 十进制度），自动旋转的节拍由帧首翻转位给 | sys_clk |
| `u_eff` | 194 | `effect_ctrl` | 九位 `stage_sel` + 阈值 + 缩放两位 + gamma 通道的跨域同步（三对 `ASYNC_REG`） | clk_pix |
| `u_t` | 222 | `video_timing_1024x600` | 显示栅格：`x/y/hs/vs/de/frame_start/frame_done` | clk_pix |
| `u_zfit` | 278 | `zoom_fit` | "旋到哪个角度就缩到刚好装得下"，与 `zoom_mapper` 用同一张 Q8 三角表 | clk_pix |
| `u_zctrl` | 281 | `zoom_ctrl` | 缩放倍率的来源：呼吸三角波 / 手动八档 / 拟合，三种来源在这里选一个 | clk_pix |
| `u_zmap` | 298 | `zoom_mapper` | 逆映射：显示 (x,y) → 源 (sx,sy) + Q8 小数 + `oob`，缩放与旋转叠在一起 | clk_pix |
| `u_arb` | 376 | `src_arb` | DDR→帧缓存这台搬运机归 ETH 还是归 PS，带 20 ms 让位静默 | axi_clk |
| `u_cmt` | 385 | `frame_commit_lock` | 把"提交一帧"锁到消隐窗口里，带看门狗与中止翻转位 | 两域 |
| `u_row` | 409 | `axi_frame_writer_gated` | ETH 路：DDR→显示帧缓存整帧读回，只在 `allow_wr` 窗口内发 AR | axi_clk |
| `u_pub` | 514 | `ps_publish` | PS 的"这帧写完了"翻转位跨到像素域 + 挂起/消费握手 | clk_pix |
| `u_life` | 538 | `src_life` | "此刻还有没有片源"的活判据（心跳超时 500 ms，不再用粘滞位） | clk_pix |
| `u_lat` | 574 | `frame_latency` | 一帧提交→开始扫描分三段量，输出 axi 拍数 | axi_clk |
| `u_zsnap` | 602 | `zoom_snap` | 把像素域真在用的缩放状态打包成准静态总线，晚 8 拍发沿 | clk_pix → axi |
| `u_aw` | 637 | `axi_frame_writer64` | PS 路：同一个搬运动作，由 `ps_frame_start` 触发 | axi_clk |
| `u_bilin` | 677 | `fb_bilin` | 显示侧**唯一**读口：双线性/最近邻可运行时切换，每源像素用满 4 拍 | clk_pix |
| `u_bar` | 704 | `test_card` | 会动的图卡（游动亮球 + 拖影 + 网格 + 帧号二值格） | clk_pix |
| `u_raw` | 733 | `raw_line_delay` | 原图抽头的 4 行环形缓存，17 bit 把 `oob` 标签打包一起走 | clk_pix |
| `u_pipe` | 745 | `proc_pipeline` | 效果链：级 0 gamma + 五级可选算法，固定 15 拍 | clk_pix |
| `u_split_x` | 821 | `snap_cross` | 19 位几何控制字 axi → 像素域（准静态总线 + 跳变沿） | clk_pix |
| `u_split_ctrl` | 830 | `split_ctrl` | 分割线的**位置**发生器：手动百分比 / 自动扫描 / 跟随画面端点 / 交换 | clk_pix |
| `u_seam_src` | 849 | `seam_src` | 把缝从显示列搬到图像列，于是那条线跟着画面一起转 | clk_pix |
| `u_split` | 856 | `split_display` | 逐像素二选一 + 2 列宽标记线 + 越界涂黑，输出打一拍 | clk_pix |
| `u_lat_x` | 925 | `snap_cross` | axi 域算好的时延 ms + 两位状态跨到像素域给 OSD | clk_pix |
| `u_osd` | 944 | `osd_overlay` | 5 行状态叠加（递进去的是**面板**尺寸 `2*IMG_W/2*IMG_H`） | clk_pix |
| `u_dvi` | 970 | `rgb2dvi` | RGB888 + 同步 → TMDS 三对数据 + 一对时钟，250 MHz 串行化 | clk_pix / clk_pix5x |

以太网那一路的实例都在 `system_top.v:150` 那个 `u_eth` 里面，链路顺序写在
`src/rtl/eth/eth_udp_video_top.v:3-4`：`gmii_to_rgmii → gmii_rx_mac（自算 FCS）→
udp_rx_parser → frame_reasm → dc_fifo(BRAM CDC) → axi_frame_saver64 → ddr_bank_commit`，
控制面 `arp / icmp / eth_ctrl`，观测面 `link_monitor`（`:280-281`）。

## 5. 控制字：九位 `stage_sel`、19 位几何字、以及屏上那五位

**九位效果控制字**（唯一的一套效果口径，V7 那五位 `effect_en` 的兜底合流已删）：

| 位 | 含义 | 位 | 含义 |
|---|---|---|---|
| `[0]` | 灰度 | `[5]` | 二值化 |
| `[1]` | 反色 | `[6]` | 判决反相（仅 `[5]=1` 有意义） |
| `[2]` | 3×3 均值模糊 | `[7]` | 腐蚀 |
| `[3]` | 3×3 锐化 | `[8]` | 膨胀 |
| `[4]` | Sobel 边缘 | | |

位表正本在 `src/rtl/process/proc_pipeline.v:5-6`，解码在 `:49-58`。固件侧那一份只是抄
（`src/ps/main.c:104-112`），注释明确写了"位定义的唯一出处是 `proc_pipeline.v` 文件头"。
**级 5 那两位互斥**：腐蚀与膨胀同时置 1 时两个都不做（`proc_pipeline.v:56-57`），
因为开/闭运算要两遍 3×3 窗口而链子上只有一遍。

**屏上 OSD 的 `Pipe:` 只有五位**，因为九位是**成对**打包的：每一级两个算法位合成一个 0..3
的数字，含义是"这一级实际生效的是哪个"。合成式在 `src/rtl/video/osd_overlay.v:127-138`，
其中 `lvl(a,b)` 函数在 `:115-123`。于是：

- 第 1 格 = 灰度 + 反色，第 2 格 = 模糊 + 锐化，第 3 格 = 只有 Sobel（第二个恒 0，`:131`）；
- 第 4 格特殊：极性是二值化的**修饰**而不是并列选项，所以只可能是 0/1/2（`:132-134`）；
- 第 5 格用 `lvl(腐蚀 & ~膨胀, 膨胀 & ~腐蚀)`（`:138`）—— 两位同时为 1 时那一格显示 0 而不是 3，
  因为链子上那两位是明确旁路。写 3 就成了"屏上写着两个都开、画面上什么都没发生"。

拿 `pipe 111111111` 算一遍：`3 3 1 2 0`。等价效果 = 灰度取反 +（模糊≈抵消锐化）+ Sobel +
反相二值化 + 形态学旁路。这不是 bug，是编码方式；想知道开着什么就敲 `pipe show`
（帮助文本 `main.c:1355-1357` 说的就是这件事）。

**19 位几何控制字** `split_ctl`：`[9:0]=pos_px`、`[10]=auto_en`、`[11]=follow`、`[12]=swap`、
`[13]=marker_off`、`[14]=rot_auto`、`[17:15]=rot_speed`（度/帧）、`[18]=zoom_fit`
（端口注释 `pl_video_top.v:44-50`，像素域的切片在 `:172-174`）。物理位是
`CFG_DATA0[22:13]`、`[25:23]`、`[30]`、`[9]`、`[12:10]`、`[31]`，由 `system_top` 拼成一束，
**19 位一起过同一条 `snap_cross`**。为什么不并进 `effect_ctrl` 那条现成的同步链、
也不开第二条 `snap_cross`：`pl_video_top.v:48-49` 写着两处理由（前者会让 CDC unsafe 端点按位长涨，
后者就是 `CDC-11 Critical` 的签名（`:48-49`）。

**GPIO 地址表**（区分控制面与 DDR 地址，见 `00_prerequisites.md` §8）：
`0x4120_0000` 控制字 0、`0x4121_0000` 状态窗口（读）、`0x4122_0000` / `+0x08` 控制字 1/2。
DDR 的三个 bank 是 `0x1000_0000`、`0x1008_0000`（ETH 乒乓，`eth_udp_video_top.v:67-68`）
与 `0x1010_0000`（PS 专用，`pl_video_top.v:13`、`main.c:45`）。为什么 PS 那路要单独开一个地址：
仲裁只管"谁用 DDR→帧缓存这台搬运机"，**管不到谁写 DDR**（SD 的 DMA 走 PS 自己的 HP0，
不经过 PL），两路同时跑时只能靠地址分开（`pl_video_top.v:10-12`）。

## 6. 关键常数：改任何一条之前先看谁在依赖它

| 量 | 值 | 出处 | 谁依赖它 |
|---|---|---|---|
| 源（帧缓存）尺寸 | 512×300，RGB565，一帧 307200 B | `pl_video_top.v:6-7` | 帧缓存容量、几何、图卡、`frame_reasm` 验收门 |
| 半窗宽 `PANE_W` | 512（今天只剩调试位与 `DISP_W=2*PANE_W` 用） | `pl_video_top.v:8`、`:241`、`:830` | `left_pane`、`split_ctrl` 的显示域宽 |
| 显示 | 1024×600 有效 | `video_timing_1024x600.v:17-18` | 时序、×2 展开、OSD 第一行 |
| `H_TOTAL` / `V_TOTAL` | 1344 / 625 | `video_timing.v:26-27`（由 porch 相加） | 消隐期长度、行环槽位相位、拷贝预算 |
| `DISP_V_LINES` / `DISP_V_LAST` | 600 / 624 | `pl_video_top.v:352-353` | 消隐拷贝窗口 |
| `VB_X_GUARD` | 1279 = `H_TOTAL-65` | `pl_video_top.v:354` | 末行早关 64 个消隐像点：`allow_copy` 过 CDC 要晚这个窗口约 5 个像素拍 |
| `VBLANK_AXI_CYC` | 67200 axi 拍 | `pl_video_top.v:401` | 拷贝超窗判据（`copy_overrun`，`:402-406`） |
| 效果链延迟 `LATENCY` | 15 拍（1+1+3+3+3+1+3） | `proc_pipeline.v:19`（逐拍账 `:14-15`） | `MIX_D`、`PROC_LAT`、`SEAM_TAPS`、相位对齐 |
| 内容滞后 `OFF_LINES` | 4 行（四个窗口级各 −1） | `proc_pipeline.v:24`（理由 `:20-23`） | 行环深度、读侧 `cy_r` |
| 混合总延迟 `MIX_D` | 3+1+1+15 = 20 | `pl_video_top.v:309` | 混色级与 OSD 的整束标签 `:864`、`:950` |
| 缝判定抽头 `SEAM_TAPS` | `MIX_D+1-3` = 18 | `pl_video_top.v:847`、默认值 `seam_src.v:9` | 图像域分割线 |
| 双线性额外行 `BILIN_ROWS` | 2 显示行，**必须偶数** | `pl_video_top.v:250`（理由 `:244-249`） | 读侧行号 `y_right_adv`（`:263`） |
| 行环深度 | `2^clog2(OFF_LINES+1)` = 8 行、宽 `2*IMG_W`、17 bit | `raw_line_delay.v:41`、`pl_video_top.v:726,733` | 帧头槽位相位（§7 硬条件） |
| 缩放区间 | `INV_LO=256`(1.0×) ↔ `INV_HI=512`(0.5×)，`STEP=2` | `pl_video_top.v:281`、`zoom_ctrl.v:6-8` | 八档表 `zoom_ctrl.v:60-67`、OSD 档位号 |
| 片源看门狗 | PS 心跳 500 ms；ETH 让位静默 2×10^6 axi 拍 = 20 ms | `pl_video_top.v:536`、`:376` | `src_life`、`src_arb` |
| 链路存活判据 | `LIVE_MS=200` @125 MHz | `eth_udp_video_top.v:280-281` | lane7.bit3 → `eth_live` → `no_sig`、`src_arb` |
| 端口 / 地址 | UDP 5001、MAC `00:11:22:33:44:55`、IP 192.168.1.10 | `system_top.v:141,154-155` | 上位机、`ping`、ARP |
| 按键 | 消抖 `CNT_MAX=1_000_000`（20 ms）；长按 3×10^7 = 0.6 s，松开臂 10^7 = 0.2 s | `pl_video_top.v:132-135`、`:144` | `key_debounce`、`key_long`、`src_mode` |
| RGMII 输入延迟 | `IDELAY_VALUE=26`（FIXED 抽头，200 MHz 参考 ⇒ 156 ps/拍；#57 换树时按 1.683 ns 补 +11 拍） | `src/rtl/top/system_top.v:162` | `rgmii_rx.v` |
| OSD 版式 | `N_LINES=5`、5×7 字模 ×3 放大（18×21）、每行 32 格、起点 (16,12) | `osd_overlay.v:8-19` | 屏上排版与 `tb_osd_lines` 整串比对 |

两处"看着巧合、其实是硬条件"的数值要记住。第一，行环深 8 行、一帧 600 有效行，
`600 mod 8 = 0` 才让每一行的槽位对得上；第二，`V_TOTAL=625` **不是** 8 的整数倍，
竖直消隐那 25 行会把槽位相位挪走，所以"消隐期读地址一律钳到 0"这种更简单的修法不行
—— 推演写在 `src/rtl/video/raw_line_delay.v:77-79`，同一段还写了另一种错法
（把读出再打一拍 ⇒ 每列都推后一格）。

## 7. 两条抽头与它们的相位（本项目最容易踩的一节）

约定：**内容**与**关于内容的标签**必须同一拍。这里给一份完整记账。

- 原图抽头：`pix_raw`（`:717`）→ `u_raw` 行环（`:733`，4 显示行 + 1 拍）→ 15 拍 skid
  （`:776-792`）→ `orig_disp`（`:793`）。
- 处理抽头：同一个 `pix_raw` → `u_pipe` 15 拍（`:745`）→ 再打一拍 `pipe_dout_q`（`:770-774`）。
- 两者到混色级 `u_split`（`:856`）同一拍；标签整束 `x/y/de/hs/vs/x_sel` 取自 `*_d[MIX_D]`
  （`:864-866`），OSD 用的 `x/y` 也取自同一级（`:950`）。

三次真实缺陷都在这条线上，值得逐个记：

1. **标签比内容旧 9 列。** 历史上 `u_split` 拿的是第 11 级标签，内容是第 20 级，
   于是缝左边约 9 列里标签说"左窗"、内容其实走的是被清 0 的那一路，屏上是一条近黑竖带。
   正本注释：`src/rtl/video/split_display.v:10-15`；记账推导：`pl_video_top.v:306-310`。
2. **两条抽头差一整拍。** 环之后是 15+1 拍，链子只有 15 拍 ⇒ 处理抽头早一整列。
   1.00× 铺满看不出，一缩小就把画面自己最左那一列甩进背景带 —— 用户念的"贴在屏幕边缘的一条线"
   这一笔占一列。注释与凭据：`pl_video_top.v:764-769`。
3. **越界标签绕过行环。** 像素过环、`oob` 走等长 skid ⇒ 到混色级差 (4 行, 1 列)，
   表现为"上边缘有东西闪"。修法是打包成 17 bit 一起过环，代价是 RAM 宽度 +1 位
   而**一块 BRAM 不多要**（17 bit 仍在 RAMB36 的 18 位宽度模式里），
   注释在 `raw_line_delay.v:11-16` 与 `pl_video_top.v:727-731`。

还有一处必须理解的补偿：读地址提前。效果链内容天生滞后 4 行（因果性：行缓存式 3×3 滤波
在收到第 y 行时才算得出第 y−1 行），"把数据提前"不可能，只能"把地址提前"，
而且提前量要加在 **mapper 的显示行输入**上而不是输出的源行上
（`proc_pipeline.v:20-23` 与 `pl_video_top.v:244-248`）。双线性读口又额外晚一整对显示行
（乒乓缓冲：一对的结果在那对的第二行才算得出），于是 `BILIN_ROWS=2` 叠在同一处
（`pl_video_top.v:249`）。这一串算下来就是 `:263` 的 `y_right_adv`，
再对 `IMG_H` 取一次模（`:271`，最大 302 所以一次减法就够，不留除法器）。

**你可以自己验证。** 三件事都能不碰板子做完：

```bash
bash sim/run_one.sh tb_v86_pipe_sel      # 实测 de_in→de_out 与 LATENCY 对账
bash sim/run_one.sh tb_v100_raw_delay    # 行环：延迟恰 = LINES 行 + 1 拍、列不偏、行首那一格
bash sim/run_one.sh tb_v89_align         # 四个窗口级的内容滞后与 off_rows
```

## 8. 时钟域与复位（一张表，六股钟）

| 时钟 | 频率 | 来源 | 谁用它 |
|---|---|---|---|
| `sys_clk` | 50 MHz（周期 20 ns，引脚 W17） | 板载振荡器，`src/constraints/rk_zynq7020.xdc:5-6` | MMCM 基准、按键、FPS 计数 |
| `clk_pix` = CLKOUT0 | 50 MHz | `clk_gen.v:21`（÷20） | 栅格、映射、帧缓存读、效果链、混合、OSD |
| `clk_pix5x` = CLKOUT1 | 250 MHz | `clk_gen.v:24`（÷4） | TMDS 串行化（`rgb2dvi`/`tmds_serializer`） |
| `clk_200m` = CLKOUT2 | 200 MHz | `clk_gen.v:27`（÷5） | IDELAYCTRL 参考 |
| `axi_clk` = `clk_fpga_0` | **100 MHz** | PS FCLK0，`system_top.v:82`，配置项 `PCW_FPGA0_PERIPHERAL_FREQMHZ` | AXI 读写、三只 GPIO、两个搬运引擎、`link_monitor` 的 lane 读回 |
| `eth_rxc` → `gmii_rx_clk` | 125 MHz（引脚 Y19） | PHY 恢复时钟，经 BUFG | 整个自研收包协议栈与 `frame_reasm`、`link_monitor` |

MMCM 是 `MMCME2_BASE`，VCO = 50 × 20 = 1000 MHz（`clk_gen.v:16-31`）。
注意 `tap_sched` 的"每像素周期 5 个快槽"方案跑在 250 MHz 上，但**它没进位流**（§11）。

复位有三条，全部异步释放、同步使用：

- `rst_pix_n = sys_rst_n & locked`（`pl_video_top.v:128`）：MMCM 一失锁，整条像素链一起停；
- `axi_rst_n` 用 PS 的 `FCLK_RESET0_N`；
- 以太网侧 `rst_n = eth_rst_n & mmcm_locked`（`system_top.v:159`），
  `eth_rst_n` 由 24 位计数器的 bit23 给出（`:107-111`，约 168 ms）。

RAM 与它的读出通常不复位（省复位布线），所以"未初始化就判"的台架会看到 X ——
这条与它的对策写在 `00_prerequisites.md` §2.2。

## 9. 三路片源、仲裁与"屏上这一路到底是谁"

判据分三层，别混：

1. **谁活着**：`link_monitor` 在 125 MHz 域里用 `stall_ms < 200` 判"最近真的见过完整帧"
   （`link_monitor.v:13-14` 的 `LIVE_MS`，输出 lane7.bit3）；PS 那一路由 `src_life`
   用心跳超时 500 ms 判（`pl_video_top.v:536-541`）。这里有一处历史根因：
   最早的判据是 `eth_link = |s_pkts`——"自配置以来收过任何一个包"，ARP 就触发、拔线不回 0，
   于是 PS 片源被永久锁死（`src_arb.v:4-9` 讲的是这件事，编号 #47）。
2. **谁在搬**：`src_arb`（`pl_video_top.v:376`）在 axi 域决定搬运机归 ETH 还是 PS，
   换手只发生在安全点，且 ETH 让位要有 20 ms 静默（`T_OFF_CYC(2_000_000)`）。
   模式寄存器 `mode`（`u_mode`，`:153`）是"意愿"，编码 `00 自动 / 01 ETH / 11 SD / 10 TEST`
   （`pl_video_top.v:148`，与固件 `main.c:59-62` 同一张表）。
3. **屏上画的是谁**：`fb_vis`（`:545`）—— 图卡模式恒 0，钉住 ETH/SD 恒 1，AUTO 时看仲裁结果，
   并且还要 `have_src`。OSD 的 `SRC:` 那一格画的是 `{fb_vis, owner_eth_pix}`
   （`:959`），也就是**屏幕上真的这一路**，不是意愿；意愿只用尾部一个 `*` 表示
   （`osd_overlay.v:234-249`）。

无信号那句话的判据在 `pl_video_top.v:465`：`no_sig = (mode_eth | owner_eth_pix) & ~eth_live_pix`。
为什么必须有这一句：ETH 停流时画面会冻在最后一帧，屏上没有任何说法就被当成"板子卡死"
（`:462-464`）。AUTO 模式不判，因为那时仲裁已经把屏交回 PS/图卡，屏上画的不是冻结帧。

## 10. 观测面：先写 lane 号、再读一个字

PL→PS 的状态通道是"窗口"式的，不是一堆寄存器：先用控制字 0 的 `[31:27]` 写一个 lane 号，
再从 `0x4121_0000` 读回那一条 32 bit。多路信号复用同一个口的代价是"读法要有节拍"，
好处是**零新增跨域**。实现：`system_top.v:203-229`，健康快照 320 bit 从 125 MHz 域经
`snap_cross` 跨进 axi 域（`:198`）。

| lane | 内容 | 出处 |
|---|---|---|
| 0..9 | 链路健康：丢字 / 坏包与作废帧 / 最大缺行与断流 ms / 最近帧间隔 / 间隔 max·min / Σ间隔 / CDC 灌满次数 / 标志位 / 包数 / 字节数 | `link_monitor.v:178-187` |
| 23 | 像素域**真的在用**的缩放状态（19 位：`inv_used`、`zoom_dir`、`zoom_active`、`bit19=zoom_fit`…） | `pl_video_top.v:628-633`、打包 `u_zsnap`（`:602`） |
| 24..29 | 时延快照：`q_ms` 与五段拍数 | `system_top.v:213-227` |
| 30 | 仲裁输入与判决：`owner_eth`、两个 busy、`why_ps` 等 16 位 | `pl_video_top.v:61-64` |
| 31 | ETH 时基健康：`{hb_slow, hb_gone}` | `system_top.v:193,222` |
| 10..22 | 越界读 → `32'hDEAD_BEEF`，好让脚本一眼看出自己写错了号 | `system_top.v:195,228` |

`lat_arm` 是一个巧妙的小机制：把 lane 指到 25 那一拍，就是"把五个时延字同时抄进一份自洽快照"
的触发（`system_top.v:216-220`）。否则逐 lane 各读各的会读到不同轮，板级对账就成了
"11 组读数来自 3 个时刻"（编号 #59）。

读回脚本：`node src/host/health_read.mjs`（打包读 lane0~9）、`src/host/metrics.mjs`
（推流 N 秒 → 读回 → 算成指标）、`src/host/lane30_watch.mjs`（连采仲裁那一口）、
`src/host/geom_check.mjs`（证明"像素域真的用了这个值"，而不只是固件回显了它）。

## 11. 哪些文件在位流里、哪些只有台架

本工程有 79 个 `.v`，其中有一批**不在综合顶层的可达集里**但仍留在树里，原因是它们各自
还有台架在钉着形状。搞混这一层就会误以为"改了它屏上会变"。已确认的三个典型：

| 文件 | 状态 | 怎么确认 |
|---|---|---|
| `src/rtl/process/bilin/fb_bilin.v` | **在位流里**：顶层唯一读口 `u_bilin`（`pl_video_top.v:677`） | grep 例化名 |
| `src/rtl/process/bilin/fb_rd5x.v` | **不在**：被 `fb_bilin` 取代（r63/#52），只剩 `sim/tb_fb_rd5x.v` 驱动 | `fb_rd5x.v:4-6` 的文件头就写着这件事 |
| `src/rtl/process/bilin/tap_sched.v` | 不在：它只被 `fb_rd5x` 例化（`fb_rd5x.v:91`），因而随上一行退出位流 | `tap_sched.v:5` |
| `src/rtl/process/rotate/rotate_mapper.v` | 不在：几何今天的旋转在 `zoom_mapper` 里（`pl_video_top.v:298`），`rotate_mapper` 只有 `sim/tb_rotate_mapper.v:13` 例化 | `grep -rn rotate_mapper src/rtl sim` |

**所以关于双线性插值，正确的一句话是**：读口调度在 `fb_bilin` 里，它是"一个读口、每拍一次读、
每个源像素用满它天然的 4 个 50 MHz 拍"（`fb_bilin.v:4`），
`(row0,col0)` 的四种组合分别发 A / A+1 / B / B+1 四个字号（`fb_bilin.v:36-56`），
地址先打一拍 + BRAM 一拍 ⇒ 请求到数据 2 拍，所以顶层 `MIX_D` 那两个 `1` 一个字没改
（`fb_bilin.v:39-40`）。算术核单独成模块 `bilin_lerp`（`fb_bilin.v:172` 例化），
与"抽头怎么取来"完全解耦，所以能单独对着行为黄金模型逐位验（`bilin_lerp.v:2`）。
而"借 250 MHz 每像素发 5 次读 + 5 槽调度器"是**另一条被换掉的方案**，
它的价值留在 `tap_sched.v:43-47` 那笔"快域不做算术"的时序账里。

另一处值得单独点名的旧话：`src/rtl/video/split_ctrl.v:3-7` 的文件头写着
"本模块目前没有被任何顶层例化"。这句在 #73 之前是真的，**今天已经不成立** ——
它就在 `pl_video_top.v:830`（`u_split_ctrl`），缝位从那里送进 `split_display` 与 `seam_src`。
这类"源码注释比代码旧"的地方本仓库还有几处，读代码时以例化关系为准：

```bash
grep -n "split_ctrl #(" src/rtl/top/pl_video_top.v          # 它被例化
sed -n '1,8p' src/rtl/video/split_ctrl.v                    # 文件头还写着"没有被例化"
bash build/orphan_rtl.sh                                    # 一次算出"没进这一版位流"的清单（按去向分类）
```

`build/orphan_rtl.sh` 值得记一笔，因为它解释了"为什么用综合日志当 oracle 而不是 grep 例化名"
（`build/orphan_rtl.sh:3-12`）：grep 会漏掉行首直接例化、又会把注释里的名字假命中，
而 `INFO: [Synth 8-6157] synthesizing module 'X'` 只对从顶层可达的模块出现。

## 12. 与旧稿、与其它文档不一致的地方（核对记录）

这一节是这一轮重画地图时逐条比对的结果。写在这里而不是偷偷改掉，是因为"文档说 A、
代码是 B"本身就是这个项目的一类缺陷。

| 旧说法（本目录上一版或 `report/` 某处） | 现在的实情 | 凭据 |
|---|---|---|
| `report/ISSUES.md`、`report/OVERNIGHT_LOG.md` | `report/` 目录已不存在；交付文档在 `report/`、工作记录在 `report/log/` | `ls docs`、`ls report/log`、`report/README.md:5-9` |
| "旧的中文目录版在 `Video_Processing/study/`，已被本套取代" | 中文那一套在 `report/study/00_前置知识 … 06_自测`，是**本套的写作范本**，两者并存且都在 `report/study/` 下（整个 `report/study/` 被 `.gitignore:105` 挡住，不进 git） | `ls report/study` |
| 第二块板 KU5P 的移植段（`ku5p/`、`tb_ku5p_*`、`ku5p_*.mjs`） | 本仓库不再包含：整棵树 2026-09-28 删除 | `ls`（无 `ku5p/`）与 `ls src/host`（无 `ku5p_*.mjs`） |
| Python 上位机 + `run_sender.bat` / `run_video.bat` / `run_serial.bat` + `requirements.txt` | 只剩 Node 与 PowerShell；根目录一个 `stream_video.bat` 用 ffmpeg 管道喂 `video_sender.mjs --file -` | `ls *.bat`、`report/HOST_GUIDE.md:3-10` |
| "AXI-Lite 基址 `0x1000_0000` / `0x1010_0000`" | 这两个数是 **DDR 帧 bank 地址**，不是 AXI-Lite；GPIO 是 `0x4120_0000` / `0x4121_0000` / `0x4122_0000(+0x08)` | `pl_video_top.v:9,13`、`main.c:47,71,90` |
| "七级图像处理链" | 九位 `stage_sel`（八个算法位 + 一个判决反相位），级序 gamma → 颜色 → 滤波 → 边缘 → 阈值 → 形态学，固定 15 拍 | `proc_pipeline.v:5-6,49-58` |
| `LATENCY` 在 `proc_pipeline.v:44`、`OFF_LINES` 在 `:52` | 现在分别在 `:19` 与 `:24`（顶层 `MIX_D` 从 `:368` 漂到 `:309`、`SEAM_TAPS` 从 `:968` 漂到 `:847`）—— 整棵顶层的行号都因删除旧的两屏几何而上移 | 本轮 grep |
| "OSD 是四行格式" | 代码里 `N_LINES = 5`（`osd_overlay.v:19`）：**前四行**（面板尺寸/FPS/片源、Pipe/Th/Gamma、Rot/Zoom、Split/Latency）字段与顺序是定好的格式，第 5 行是后加的常驻温度 + 无信号提示。所以"四行"指格式受约束的那四行，屏上实际是 5 行 | `osd_overlay.v:16-18,256-320` |
| 双线性"有独立读口调度器 `tap_sched`" | 顶层用的是 `fb_bilin`（单读口、慢域、每源像素 4 拍）；`fb_rd5x`/`tap_sched` 只剩台架 | §11 |
| 几何"`rotate_mapper` 参与旋转" | 旋转与缩放叠在同一个 `zoom_mapper` 里（三级流水，`:17` 出 `oob`）；`rotate_mapper` 只有台架例化 | §11 |
| `report/ARCHITECTURE.md` / `report/MODULES.md` 里的若干 `文件:行` | 那些行号本身也有漂移（例如把 `u_bilin` 指到 `:787`、`u_osd` 指到 `:1081`，实际是 `:677` 与 `:944`）。**架构结论是对的，行号要重新 grep** | 本轮 grep |
| 门禁"20 项" | 今天跑出来确实 20 项，但 `build/gates.sh:2-9` 明确"不再写死条数，以本文件 `say` 调用为准"；念数要念同一套产物 | `bash build/gates.sh` 输出 |

## 13. 验证地图：改哪里会立刻红

先记住两条总规矩：**红灯 = 没做完**；改 RTL 之前先想清楚哪条判据能证明它坏了
（方法论见 `00_prerequisites.md` §12）。

| 改了什么 | 谁盯它 | 门禁关系 |
|---|---|---|
| 顶层 `pl_video_top` / `system_top` | `sim/tb_v98_top_seam.v`（唯一例化整顶层的台架） | 第 15 项认它的报告头三枚 md5；第 14 项 `build/check_ports.py` 当场判接线 |
| 四个窗口级（blur / sharpen / sobel / morph） | `tb_v89_align`（位置）、`tb_edge_rim`（边缘内容）、`tb_v92_seam_bleed` | 第 15b 项认 `tb_edge_rim` 的报告与四条圈的覆盖地板 |
| `proc_pipeline` 级数 / `LATENCY` | `tb_v86_pipe_sel`（实测拍数与声明值对账） | 顶层 `MIX_D`、`PROC_LAT` 都从它推，改一次三处跟着动 |
| `fb_bilin` / `bilin_lerp` / `frame_buffer_w64` | `tb_v101_fb_bilin`、`tb_bilin_lerp`、`tb_fb_roundtrip` | 经第 15 项的 `rtl_md5` 生效 |
| `raw_line_delay` | `tb_v100_raw_delay`（T7 一族，靠变异检验） | 同上 |
| `split_ctrl` / `split_display` / `seam_src` | `tb_v93_split_ctrl`、`tb_v97_seam_scan` | 缝的最终凭据是第 15 项里 `tb_v98` 的 C1~C3 |
| `zoom_ctrl` / `zoom_fit` / `zoom_mapper` / `zoom_snap` | `tb_v94_zoom_sel`、`tb_v100_fit_rot`、`tb_v96_zoom_scan`、`tb_v95_zoom_snap` | — |
| 收包链（`gmii_rx_mac` / `udp_rx_parser` / `frame_reasm`） | `tb_v795_rx_fcs`、`tb_v795_rx_chain`、`tb_udp_reasm`、`tb_v50_rows*` | — |
| DDR 写读与提交（`axi_frame_saver64` / `ddr_bank_commit` / `frame_commit_lock` / 两个 writer） | `tb_v6_pingpong`、`tb_v6_tail_bank`、`tb_v6_vblank_copy`、`tb_v5_lock`、`tb_v79_abort_toggle` | — |
| 片源仲裁与心跳（`src_arb` / `src_mode` / `src_life` / `ps_publish`） | `tb_v796_src_arb`、`tb_v82_src_mode`、`tb_v102_src_life`、`tb_ps_publish` | 第 16 项 `ps_hb_check.mjs --self` 管固件那半边 |
| `osd_overlay` | `tb_osd_lines`（整串比对）、`tb_v794_osd_glyph`（字模金表） | — |
| `link_monitor` / `snap_cross` | `tb_link_monitor` | 第 6 项按 `build/CDC_BASELINE.txt` 的**配对集合**判 |
| 串口命令表、文档口径、编码 | `uart_cmd_check.mjs`、`demo_cmds.mjs --emit/--check`、`pipe_len_check.mjs` | 第 17/18/19 项（`doc_enc_check`、`doc_currency_check`、排练脚本比对） |
| 广播口、端口过滤、注释体积 | `build/check_ports.py`、`build/trim_comments.py --check` | 第 14 项 |

台架怎么跑：单个用 `bash sim/run_one.sh <tb名>`（编译前盖 `top_md5` / `tb_md5` / `rtl_md5`
三枚出处，`sim/run_one.sh:34-45`），全量用
`vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`（63 个台架，几十分钟）。
`run_one.sh:16-25` 有一条硬规矩值得先知道：**同一时刻只许一个 xsim 在写运行目录**，
第二个不会让第一个停下，两跑的行会混进同一份 `run.log`，于是报告可能"md5 全对、正文来自两个进程"。
所以它先 `tasklist` 探活，有活的就 `REFUSE` 并说清该杀谁（不自动杀）。

## 14. 构建、门禁、冻结：四个入口

| 目的 | 命令 | 说明 |
|---|---|---|
| 建工程 + 综合 + 实现 + 出位流/xsa | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` | **唯一**构建入口；收文件清单见 `build/tcl/build_system_axigpio.tcl:12-17`，顶层 `set top system_top` 在同文件 `:232`，`launch_runs` 在 `:243` 与 `:277` |
| 读回门禁 | `bash build/gates.sh`（或 `bash build/gates.sh build/evidence_rNN`） | 只读已有 Vivado 报告并与阈值比，不重跑构建；退出码全绿 0 |
| 冻结一套凭据 | `bash build/freeze_evidence.sh <NN>` | 两道门：`rNN_gates.txt` 必须 `ALL PASS`，`tb_v98` 报告的两枚指纹必须还等于当前树 |
| 板级机器验收 | `bash build/board_verify.sh --battery --geom` | 串口命令电池 + 几何自动化；人判的三行在 `board/README.md` 的表里 |

关于"入口只有一个"，有两条操作层面的坑要提前知道：

1. 构建脚本靠 `file dirname [info script]` 往上跳两级定位仓库根
   （`build/tcl/build_system_axigpio.tcl:2`），所以**必须从 `build/tcl` 里以 `-source` 跑**；
   `build/tcl/` 下另有两个兄弟脚本把根算短了一级，它们在 `add_files` 处失败**却仍以 0 退出码结束**。
2. 门禁输出**不许直接重定向成它自己要读的那份 `rNN_gates.txt`**：
   `>` 会在第一项判据跑之前就把它截断，而第 18 项恰恰拿"盘上最新且 `ALL PASS` 的那一份"当基准
   （`build/gates.sh:12-18` 把这一课写全了，包括正确姿势：先跑到临时文件，全绿之后再 `cp`）。

上板三件套（JTAG，不写 QSPI）：

```bat
xsdb build\tcl\ps_jtag_boot.tcl
vivado -mode batch -source build\tcl\program_pl.tcl
xsdb build\tcl\ps_app_reload.tcl
```

顺序有理由：`ps_jtag_boot.tcl` 含 `rst -system`，跑过它位流就掉了，必须重下；
`ps_app_reload.tcl` 只 `rst -processor`，可以在不重下位流的前提下换固件
（`report/HOST_GUIDE.md:21-23`、`report/BUILD.md` §3 第 4 步）。

## 15. 从这里出发

| 我想做的事 | 看哪一章 | 顺手跑 |
|---|---|---|
| 改某一级效果的算术 | 10 章 + 60 章 | `bash sim/run_one.sh tb_v86_pipe_sel` |
| 改缩放/旋转/插值 | 11 章 | `node src/host/interp_study.mjs` |
| 屏幕上多了一条线 / 一块带 | 20 章的"相位"一节 + 11 章 | `bash sim/run_one.sh tb_v98_top_seam` |
| 加一个显示字段 | 20 章 OSD 一节 + 40 章 | `bash sim/run_one.sh tb_osd_lines` |
| 时钟、约束、TMDS、PS↔PL 边界 | 30 章 | `bash build/gates.sh`（看第 1/2/6/11 项） |
| 加一条串口命令 | 40 章 | `node src/host/uart_cmd_check.mjs`（要板子）、`node src/host/pipe_len_check.mjs`（离线） |
| 从零把工程跑起来 | 50 章 + 40 章 | 本文 §14 的三条命令 |
| "这个结论凭什么算数" | 60 章 | `node src/host/doc_enc_check.mjs --self` |

最后一条口径要记住：本工程所有"文档 → 代码"的引用都只给 `文件:行 + 信号名`，
**版本号、门禁项数、板上是哪一版这类会过期的数**只写在 `report/PERF_REPORT.md` 与仓库根首页，
本套学习文档一律指路、不抄数（这条规矩本身由第 18 项 `doc_currency_check.mjs` 把关，
它的三条判据 D1/D2/D3 写在 `src/host/doc_currency_check.mjs:13-19`）。

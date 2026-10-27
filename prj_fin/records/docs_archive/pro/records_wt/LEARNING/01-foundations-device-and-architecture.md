# 01 · 地基：器件、工具链、目录、通路与那批必须记住的数

> 面向"会 Verilog、没碰过这套系统"的读者。这一卷不讲算法细节，只把五件事钉死：这颗片子是什么、
> 代码住在哪、一个字节怎么走、几个时钟各管什么、面板和帧的数学关系。每句话后面的括号就是它的出处，
> 括号里没有出处的句子都是在陈述本卷自己的推导，推导式会写出来。
>
> 读法上有两条约定。第一，凡是"报告里这么写"与"代码里这么写"对不上的地方，本卷会明说哪里对不上，
> 不替任何一方圆场。第二，`build/report/` 下那七份 `.rpt` 是某一次具体构建的产物（文件头有 `Date` 与
> `Design State : Routed`），重跑构建会原地改掉它们；引行号之前先确认自己手里的是同一版。

---

## 1 器件与工具链

### 1.1 板上那颗片子

结论：整个工程绑死在 `xc7z020clg484-2` 这一颗器件上，速度等级 2，板卡是 `RK-ZYNQ7020-F`。
这三个值在仓库里只有一个权威源，就是 `report/declarations.md` 的 `BEGIN-AUTHORITATIVE` 块
（`report/declarations.md:9` `part: xc7z020clg484-2`、`:10` `vivado: 2025.2.1`、
`:11` `vivado_build: 6403652`、`:13` `node: v24.21.0`、`:14` `board: RK-ZYNQ7020-F`）。
该文件自己声明这是"器件型号与工具版本的唯一权威源"，其余文档抄到这些值时必须与它对上，
取值不同才算红（`report/declarations.md` 第 5–6 行的原话）。

型号串怎么读，因为这决定了后面所有资源百分比的分母：

| 段 | 含义 | 这一版里的实际值与它的后果 |
|---|---|---|
| `xc7z` | 7 系列、Zynq-7000 SoC（PS + PL 同一颗 die） | PL 侧能用 7 系列的全部原语：`MMCME2_BASE`（`src/rtl/clocks/clk_gen.v:15`）、`IDDR`（`src/rtl/eth/rgmii_rx.v:3`）、`OSERDESE2`（`src/rtl/hdmi/tmds_serializer.v:15`）；PS 侧才有 `FCLK_CLK0` 和 `S_AXI_HP0` |
| `020` | 7020 这一档的 PL 容量 | 决定可用数：Slice LUT 53 200、Slice Register 106 400、Block RAM Tile 140、DSP48E1 220、BUFG 32、MMCM 4（以上逐条取自 `build/report/utilization.rpt:35`、`:40`、`:106`、`:121`、`:161`、`:163`） |
| `clg484` | 封装：484 脚 CLG | 引脚表按这个封装给，例如 `sys_clk` 在 W17（`src/constraints/rk_zynq7020.xdc:5`）、`eth_rxc` 在 Y19（同文件 `:20`） |
| `-2` | 速度等级 2 | 报告头直接写着 `Speed File : -2  PRODUCTION 1.12 2019-11-22`（`build/report/clock_util.rpt:9`）；换等级所有时序数作废 |

工具链：Vivado / Vitis 2025.2.1，Node 24，Python 3.12 且**不装第三方包**，串口用 PowerShell 而不是
pyserial（以上四项同见 `README.md` 第 29–30 行；PowerShell 那条在 `board/uart_cap_once.ps1:3` 写着
`No pyserial needed`）。`2025.2.1` 不是大版本线里的装饰性后缀——同一份 RTL 换工具版本可能给出不同的
布线结果，所以 `report/declarations.md` 的"已知边界"一节明写"所有时序/资源数字都是在上面这一版工具上、
对这一颗器件测出来的；换版本或换器件必须重跑，不能沿用数字"。

### 1.2 PS 与 PL 各自负责什么

结论：**凡是逐像素的、凡是必须与扫描同步的，全在 PL；凡是事务性的、低频的、需要文件系统的，全在 PS。**
判据不是"哪边写起来方便"，而是每像素预算——像素钟 50 MHz 时一像素只有 20 ns，任何逐像素操作进了
软件就一定掉帧（这条判据的原文在 `report/technical-document.md` §5 末尾）。

| 职责 | 在哪一侧 | 代码里的证据 |
|---|---|---|
| RGMII 收发、GMII 域还原、以太网帧头解析、ARP/ICMP 应答、UDP 端口过滤 | PL | `src/rtl/eth/` 25 个 `.v`；文件头链路一句话：`gmii_to_rgmii → gmii_rx_mac(自算 FCS) → udp_rx_parser → frame_reasm → dc_fifo → axi_frame_saver64 → ddr_bank_commit`（`src/rtl/eth/eth_udp_video_top.v:3`） |
| DDR 读写、帧缓存、缩放/旋转/双线性、效果链、逐像素混合、OSD、TMDS 编码 | PL | 显示通路顶层是 `src/rtl/top/pl_video_top.v`，单文件 1 050 行（本次 `wc -l`）；整设计的口径是 80 个 module / 223 个实例（`build/ports_check.txt` 第 1 行 `CHECK PORTS: instances=223 modules=80 skipped=0 width_compared=562 violations=0 PASS`）；`src/rtl` 整树 11 768 行，与 `report/technical-document.md` §2.3 的"80 个 / 11,768 行"同数 |
| 串口命令解析（115200-8N1）、寄存器整字写、SD 卡 FAT32 目录读取、XADC 片上温度、状态回显 | PS | `src/ps/main.c` + `src/ps/sd_play.c` + `sd_play.h` 共 2 544 行（`wc -l src/ps/*.c src/ps/*.h`，与 `report/technical-document.md` §2.3 的"2,544 行"一致）；波特率那句在 `src/ps/main.c:1572` 的开机横幅 `uart115200` |
| 把 SD 卡上的一帧放进 DDR | PS 的 SD 控制器 DMA，**CPU 不逐帧搬** | `src/ps/sd_play.c:12-13`："SD 控制器的 DMA 直接写 PL 要读的那块 DDR，写完只发一次发布脉冲 ⇒ PS 不需要 300 KB 的 memcpy" |
| 推流、发包、量测、判据脚本 | 上位机（Node / Python） | `src/host/` 26 支 `.mjs` + 3 支 `.py`（本次 `ls` 清点，与 `README.md` 第 17 行的"26 支 .mjs 与 3 支 .py"相同） |

为什么"ping 应答"要放在 PL 而不是让 Linux/裸机协议栈干：推流跑满时 PS 的收包通道被视频字节占着，
而演示现场需要"板子还能 ping 通"这件事与推流互不干扰。这条理由写在
`report/technical-document.md` §5 的分工表里（"ARP/ICMP 应答 | PL | 推流占满 CPU 通道时仍要能 ping 通"），
实现位置是 `src/rtl/eth/arp_rx.v`、`arp_tx.v`、`icmp_rx.v`、`icmp_tx.v` 四支。

---

## 2 工程目录：八个顶层目录与各自的入口

结论：顶层八个目录按"写的东西 / 验的东西 / 跑出来的东西"分三层——`src/` 与 `board/` 是源，
`sim/`、`build/`、`data/` 是过程与产物，`report/`、`skills/`、`study_docs/` 是说法。

| 目录 | 放什么 | 想办事时先打开哪个文件 |
|---|---|---|
| `src/rtl/` | 80 个 `.v`，分 8 个子目录：`axi`(3) `clocks`(1) `eth`(25) `hdmi`(3) `process`(21) `top`(3) `util`(7) `video`(17)，括号里是本次 `find` 清点的文件数 | 顶层只有三个文件，按顺序读：`src/rtl/top/system_top.v`（板上顶层，把 PS 的 BD、收包、显示通路接起来）→ `src/rtl/top/pl_video_top.v`（显示通路）→ `src/rtl/eth/eth_udp_video_top.v`（收包通路）。`src/rtl/top/pl_demo_top.v` 是台架用的裁剪顶层，不是板上那颗 |
| `src/ps/` | 裸机 C：`main.c`（命令层 + 寄存器）、`sd_play.c`/`.h`（FAT32 只读 + XSdPs）、`lscript_ocm.ld` | `src/ps/main.c` 的文件头注释就是控制字位表，逐位写着 `[18] ps_publish`、`[19] bilin_en`、`[31:27] 健康 lane 号`（`src/ps/main.c` 文件头第 8–15 行） |
| `src/host/` | 上位机工具：推流、发命令、读 lane、量测、检查器 | 推流 `src/host/video_sender.mjs` 或 `video_sender.py`；一键对账 `src/host/one_click_test.py`；工具清单与用法在 `src/host/README.md` |
| `src/constraints/` | 9 份 `.xdc`，**在用的只有 2 份**，其余 7 份是候选/实验件（`README.md` 第 17 行）。在用那两份由构建脚本点名：`rk_zynq7020.xdc`（`build/tcl/build_system_axigpio.tcl:31`）与 `clock_groups_impl.xdc`（同文件 `:36-38`，并且 `used_in_synthesis false`） | 改时钟周期 / 加引脚 → `src/constraints/rk_zynq7020.xdc`；改异步时钟组 → `src/constraints/clock_groups_impl.xdc` |
| `sim/` | 82 支 `tb_*.v`（本次 `find sim -name tb_*.v` 数得 82，与 `README.md` 第 18 行、`report/technical-document.md` §2.3 同数）+ 运行脚本 | 怎么跑看 `sim/README.md`；唯一例化整屏顶层的那支是 `sim/tb_v98_top_seam.v` |
| `build/` | 7 份流程入口 `.tcl`（本次 `ls build/*.tcl` 清点）、检查器 `.py`/`.sh`/`.mjs`、门禁 `gates.sh`、`build/report/` 下 7 份工具原始报告、历轮证据 `build/evidence/` | 一键建工程到出位流：`build/build.tcl`；重出报告：`build/report.tcl`；发布前检查：`build/gates.sh` |
| `board/` | 上板工程（`zynq_video_sys.xpr` + `.srcs/`）、Vitis 平台、烧写脚本、实测留档 | 先读 `board/README.md`：第 0 节给板上那颗位流的 md5 身份，第 1 节给工程形状，第 2 节给脚本，第 3 节给 `board/measured/` 的实跑读数 |
| `data/` | `inputs/` 8 份输入序列、`golden/` 参考图、`measured/` 板级量测、`metrics.csv` 指标表（第 1 行表头、往下 28 行，本次 `wc -l` = 29 行；口径同 `README.md` 第 21 行） | **`data/metrics.csv` 是全部数字的唯一出口**，每行最后一列点名它的证据文件（该表第 1 行的表头就是 `指标名称,类别,数值,单位,测量条件,测试次数或时长,证据文件`） |
| `report/` / `skills/` / `study_docs/` | 设计文档与失败分析 / 49 条做法条目（本次把 `skills/` 下的 `SKILL.md` 逐个列出来数得 49，同 `README.md` 第 22 行）/ 既有学习文档 | 中性入口：`report/technical-document.md`（概览）、`report/02-architecture.md` + `report/architecture.md`（结构）、`report/05-timing.md`（时序）、`report/08-limits.md`（限制与欠账） |

三条"改 X 先看 Y"的硬指向，抄自 `report/architecture.md` §5 的表：

- 改 `src/rtl/top/pl_video_top.v` 或 `system_top.v` → 台架看 `tb_v98_top_seam`，门禁第 15 项读它的报告，
  第 14 项 `build/check_ports.py` 查端口名 / 悬空输入 / 位宽。
- 改 `proc_pipeline` 的级数或 `LATENCY` → 台架看 `tb_v86_pipe_sel`；顶层的 `MIX_D`、`PROC_LAT` 都从
  `u_pipe.LATENCY` 推，动一次三处跟着变。
- 改约束或 CDC 结构 → 不需要台架，但门禁第 1~11 项会读 Vivado 报告，第 6 项拿
  `build/cdc_baseline.txt` 的**配对集合**做比较：新增配对或 unsafe 数增长即判未通过。

---

## 3 顶层数据流：一个字节从网线到屏上那一格

### 3.1 通路图

```
 上位机                 PL 收包侧 eth_rxc 125 MHz              axi_clk 100 MHz
 UDP:5001 ──网口──► rgmii_rx → gmii_rx_mac → udp_rx_parser → frame_reasm
 (512×300 RGB565,                            (自算 FCS-32、按目的端口过滤)
  ≤1392 B 一包)                                      │ {flush,addr[18:0],data[15:0]}
                                                     ▼
                                          dc_fifo (格雷码指针跨域)
                                                     ▼
 SD 卡 ─► PS 的 SD 控制器 DMA ─┐       axi_frame_saver64 (16b→64b + AXI3 写 HP0)
 （PS 侧，不经过 PL）           │                │
 TEST 图卡 ─►（不进 DDR）       │                ▼
                              │   DDR3：0x1000_0000 / 0x1008_0000 乒乓(ETH)
                              │          0x1010_0000 (PS 专用第三 bank)
                              │                │
        src_arb 选 owner ─────┴────────────────▼
                              frame_commit_lock → axi_frame_writer_gated / writer64
        clk_pix 50 MHz（5.1 那只 MMCM 的 CLKOUT0）      │ 64bit 整帧，只在消隐窗内搬
                              ┌─────────────────────────▼
                              │ frame_buffer_w64（显示帧缓存）
                              │ 读坐标 cx = x>>1、cy = y>>1（就是这次 >>1 完成 ×2 展开）
                              ▼
              zoom_mapper（缩放 ⊕ 旋转逆映射）→ fb_bilin（双线性 / 最近邻）
                              ▼
   两条抽头同拍并排：raw_line_delay（4 显示行环）│ proc_pipeline（15 拍、9 位控制字）
                              ▼
        split_display 逐像素二选一（缝 0–100 %）→ osd_overlay（5 行）
                              ▼
       rgb2dvi → tmds_serializer（OSERDESE2，clk_pix5x = 250 MHz）→ HDMI 1024×600 @ 59.5 Hz
```

图的骨架与 `report/02-architecture.md` §"数据通路与缓冲"、`report/architecture.md` §1 一致，模块名换成了仓库里真实存在的文件名，逐段见 3.2。

### 3.2 分段账：每段在哪个文件、什么域、多宽

| 段 | 文件 | 时钟域 | 数据位宽 | 关键事实 |
|---|---|---|---|---|
| 引脚到 GMII | `src/rtl/eth/rgmii_rx.v` | `eth_rxc` 125 MHz | 4 → 8 | 5 个 IDDR 与下游 fabric **吃同一只 BUFG**（文件头 `:3`）；IDELAY 抽头取 31（`src/rtl/top/system_top.v:172`） |
| MAC 收 + 自算 FCS | `src/rtl/eth/gmii_rx_mac.v`、`crc32_d8.v` | 125 MHz | 8 | 链路注释 `src/rtl/eth/eth_udp_video_top.v:3` |
| 端口过滤 + ARP/ICMP | `udp_rx_parser.v`、`arp_rx.v`/`arp_tx.v`、`icmp_rx.v`/`icmp_tx.v`、`arp.v`、`icmp.v`、`eth_ctrl.v` | 125 MHz | 8 | 目的端口常量 `UDP_VIDEO_PORT = 16'd5001`（`src/rtl/top/system_top.v:145`），MAC `00-11-22-33-44-55`、IP `192.168.1.10`（同文件 `:158-159`） |
| 包→帧重组与验收 | `src/rtl/eth/frame_reasm.v` | 125 MHz | 每字节一拍 | `parameter FRAME_BYTES = 307200`（`src/rtl/eth/frame_reasm.v:11`）；验收门是"每个源行都被写过才提交"（文件头 `:2-3`） |
| 跨域缓冲 | `src/rtl/eth/dc_fifo.v` | 125 → 100 MHz | 16 | 格雷码指针 + 双级同步，BRAM 实现（`report/architecture.md` §2 末段） |
| 打包并写 DDR | `src/rtl/eth/axi_frame_saver64.v` | `axi_clk` 100 MHz | 16 → 64 | `AWLEN=0` + 写通道流水化，"发完立刻取下一个字（≤2 拍/字 = 400 MB/s）"，B 响应永不阻塞数据通路（`src/rtl/eth/axi_frame_saver64.v:2-3`） |
| 乒乓 bank 提交 | `src/rtl/eth/ddr_bank_commit.v` | 100 MHz | — | `BANK0 = BASE_ADDR`、`BANK1 = BASE_ADDR + 32'h0008_0000`（`src/rtl/eth/eth_udp_video_top.v:67-68`） |
| 链路健康计数 | `src/rtl/eth/link_monitor.v` | 125 MHz | 320 bit 快照 | 每毫秒周期数 `TC = CLK_HZ / 1000`，`CLK_HZ = 125_000_000` ⇒ 125 000（`src/rtl/eth/link_monitor.v:9`、`:36`）；断流判据 `LIVE_MS = 200`（`:13`） |
| 整帧搬进显示缓存 | `src/rtl/axi/axi_frame_writer_gated.v`（ETH 路）、`axi_frame_writer64.v`（PS 路） | 100 MHz | 64 | 两支复用同一个读口，按 `owner_eth` 选（`report/02-architecture.md` 通路图） |
| 显示帧缓存 | `src/rtl/video/frame_buffer_w64.v`（实例在 `fb_bilin` 里） | 写 100 MHz / 读 50 MHz | 64 | 双口：写侧搬运机、读侧扫描 |
| 提交锁与消隐窗 | `src/rtl/video/frame_commit_lock.v` | — | — | `VBLANK_AXI_CYC = 32'd67200` 是判超时的门限（`src/rtl/top/pl_video_top.v:446`） |
| 坐标生成 | `video_timing_1024x600.v` → `video_timing.v` | 50 MHz | x/y 12 bit | 参数见 6.1 |
| 缩放 | `src/rtl/process/zoom/zoom_mapper.v`、`zoom_fit.v`、`zoom_ctrl.v`、`zoom_snap.v` | 50 MHz | — | `u_zmap` 8 个 DSP48、`u_zfit` 3 个（`report/technical-document.md` §3.3） |
| 旋转 | `src/rtl/process/rotate/rotate_mapper.v`、`angle_ctrl.v`、`sin_rom.v`、`cos_rom.v` | 50 MHz | 角度 9 bit | 逆映射 + 双线性（`report/technical-document.md` §1.3 第 3 条） |
| 双线性 | `src/rtl/process/bilin/fb_bilin.v`、`fb_rd5x.v`、`tap_sched.v`、`bilin_lerp.v` | 50 MHz | — | `u_lerp` 6 个 DSP48；读口按 `BILIN_ROWS = 2` 供数（`src/rtl/top/pl_video_top.v:250`） |
| 效果链 | `src/rtl/process/proc_pipeline.v` 及 6 个 `proc_*.v` + `gamma_lut.v`、`effect_ctrl.v` | 50 MHz | RGB565→17 bit | `parameter integer LATENCY = 15`、`OFF_LINES = 4`（`src/rtl/process/proc_pipeline.v:22`、`:27`）；控制字 9 位定义在同一文件头 `:5-6` |
| 原图抽头延迟环 | `src/rtl/video/raw_line_delay.v` | 50 MHz | 17（像素 + oob 标签） | 深 4 显示行、宽 `2*IMG_W` = 1024（`src/rtl/top/pl_video_top.v:788` 的例化 `#(.LINES(RAW_LINES), .W(2*IMG_W), .DW(17))`） |
| 缝与混合 | `src/rtl/video/split_ctrl.v`、`split_display.v`、`seam_src.v` | 50 MHz | — | 逐像素二选一，左右两半是同一帧同一时刻（`report/technical-document.md` §1.3 第 1 条） |
| OSD | `src/rtl/video/osd_overlay.v` | 50 MHz | — | 5 行、5×7 字模 ×3 放大、每行 32 格（`report/architecture.md` §4"OSD 版式"行，指 `osd_overlay.v:9-19`） |
| TMDS | `src/rtl/hdmi/rgb2dvi.v`、`tmds_encoder.v`、`tmds_serializer.v` | 并行 50 MHz / 串行 250 MHz | 8 → 1 | 10:1 OSERDESE2 级联，`DATA_WIDTH=10` 要求 `DATA_RATE_OQ=DDR`（`src/rtl/hdmi/tmds_serializer.v:2`、`:15`） |
| 第三源图卡 | `src/rtl/video/test_card.v`（顶层实例 `u_bar`） | 50 MHz | — | 不占 DDR，与帧缓存共用同一份 `sx,sy`（`src/rtl/top/pl_video_top.v:759`） |

### 3.3 顶层的四个大例化

`system_top` 内部只有四个大例化加一小块观测面复用，这是读整套代码最先要建立的形状（行号取自 `src/rtl/top/system_top.v` 本体）：

| 实例 | 模块 | 端口段 | 职责 |
|---|---|---|---|
| `u_bd` | `design_1_wrapper` | `:75-104` | PS7（双 Cortex-A9 + DDR 控制器 + `S_AXI_HP0` + 三只 AXI GPIO + FCLK/RESET） |
| `u_idelay_clkgen` | `clk_gen` | `:121-125` | 只为 IDELAYCTRL 拿一路 200 MHz；它的像素输出被显式接到 `_unused`（`:123`） |
| `u_eth` | `eth_udp_video_top` | `:154-204` | 自研收包 + AXI 写 DDR |
| `u_pl` | `pl_video_top` | `:258-321` | 显示通路 |
| `u_lm_axi` + 组合选择器 | `snap_cross` | `:212-247` | 把 320 bit 健康快照按 lane 送到 PS 能读的 GPIO_1 |

---

## 4 三路片源与 `src_arb` 的仲裁

### 4.1 三个来源

| 片源 | 数据从哪来 | 进不进 DDR | 落哪块地址 |
|---|---|---|---|
| ETH | 上位机 UDP 推流，PL 硬件收包链 | 进 | `0x1000_0000` / `0x1008_0000` 乒乓（`src/rtl/eth/eth_udp_video_top.v:67-68`） |
| SD | 板上 SD 卡预转换的裸帧序列，PS 读 | 进 | `0x1010_0000`，PS 专用第三 bank（`src/ps/main.c:46`） |
| TEST | PL 现场画的动态图卡（渐变底 + 移动块 + 帧号） | **不进** | 无 |

三路共用 DDR→帧缓存这一台搬运机，所以同一时刻只能有一个 owner。地址必须分开这条结论来自板级实测：早期
SD 那一路用的正是乒乓第 0 块的地址，两路同时写同一块内存，屏幕表现为两个片源互相覆盖（`src/ps/main.c:41-45`）。

### 4.2 `src_arb` 管的不是"哪边有数据"

结论：**它管的是"哪边活着 + 现在能不能安全换手"，两个问题分开判。**
`src/rtl/util/src_arb.v` 的文件头（第 2–16 行）把这条写成了模块存在的全部理由。三个要点：

1. **老写法 `eth_mode = 3FF(|s_pkts)` 是错的，而且错两处**：`|s_pkts` 表示"自配置以来收到过任何一个包"，
   PC 发一次 ARP 就够触发，并且拔网线它也不回 0；就算换成"最近有包"，两个引擎共用同一个 AXI 读口和
   同一个 BRAM 写口，选择位在一次拷贝中途翻转会留下半开的读突发（`src_arb.v:5-8`）。
2. **"活着"必须过两级**：第一级是 `link_monitor` 的 `stall_ms > LIVE_MS`（默认 200 ms，
   `src/rtl/eth/link_monitor.v:13`）；第二级是**先确认量它的时钟还算准**。板级实测断链时 RTL8211
   不停 RXC，而是把它拉到约 2.5 MHz，于是 `stall_ms` 以约 1/48 的速度爬，`stall_ms < 200` 会连着骗人
   十几秒（`src_arb.v:11-13`）。这就是 `eth_live` 与 `eth_tb_ok` 两个输入口的来历
   （`src_arb.v:24-25`；顶层的取处在 `src/rtl/top/system_top.v:255-256`）。
3. **换手只在两个引擎都空闲时发生**：`both_idle = ~row_busy & ~fill_busy`（`src_arb.v:48`），
   唯一的 `owner_eth` 赋值点被这个条件包着（`src_arb.v:67-75`）。往 PS 方向让位还带一段静默滞回
   `T_OFF_CYC = 2_000_000` 个 AXI 拍，100 MHz 下等于 20 ms（`src_arb.v:20`；顶层例化
   `src/rtl/top/pl_video_top.v:421` 的行尾注释同样写着"AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS"）。

模块还额外输出一只 3 bit 的 `why_ps`（`src_arb.v:39`），位序固定为 `{force_ps, ~eth_live, ~eth_tb_ok}`，
与 `owner_eth` 在**同一个决定点**写（`:73`）。这条"同拍快照"的规矩有过一次教训：挂在无条件那一支时，
拷贝期间翻 `eth_live` 会让屏上读到的"为什么 PS 拿着"跟着变，而主人一次都没换（`:68-72`）。

### 4.3 长按切源与串口钉模式

板上只有两个按键，且已被"旋转 ±1°"占用，所以第三个语义只能从同一个键上挤：**短按改角度，长按 0.6 s
切片源模式**（`src/rtl/util/key_long.v:3` 说明了这个前提；阈值 `HOLD_CYC = 30_000_000`，50 MHz 下
= 0.6 s，见该文件 `:9`）。三处细节值得先记住，因为它们是这个系统跨域做法的缩影：

- `key_long` 跑在 `sys_clk`，输出是**翻转位 `tog` 而不是脉冲**——脉冲跨域会被吃掉（`key_long.v:4-5`）。
  消费端 `src_mode` 在目的域用 3 级 `ASYNC_REG` 同步再异拍出沿（`src/rtl/util/src_mode.v:26-27`、`:59`）。
- 长按环按**格雷码**排：`M_AUTO=00 / M_ETH=01 / M_SD=11 / M_TEST=10`（`src_mode.v:24`），
  下一状态按位写成 `{ring[0], ~ring[1]}`（`:89`）。写成 `if (mode==…)` 的比较式会被综合重编成
  one-hot，格雷码的意义就在实现层被抹掉（`:20-21`）。
- 串口命令也能定住片源：`gpio_o[24:23]` 是模式码、`[22]` 是翻转位（`src/rtl/top/system_top.v:293`）。
  ⚠ 这份编码与 `src_arb` 自己的 `sel` **不是一套**：`src_arb` 那边 SD=2、TEST 走 AUTO
  （`src_arb.v:26-28` 的注释明说这不是 `src_mode` 的四态码），适配器是
  `src/rtl/top/pl_video_top.v:171` 那一行 `arb_sel`。图卡模式不参与仲裁，因为它只决定"显示什么"、
  不决定"谁在搬"（同一行的上一句注释）。

### 4.4 关键分工：ETH 那一路 PL 自己当 AXI master，SD 那一路 PS 的 DMA 写 DDR

这是本项目最容易被读错的一条分工。**证据是端口名和它们的方向。**

ETH 路——PL 是主设备，写进 PS 的 HP0 从端口：

- `eth_udp_video_top` 的端口声明里，`m_axi_awaddr`、`m_axi_awlen`、`m_axi_wdata`、`m_axi_wstrb`、
  `m_axi_wlast`、`m_axi_bready` 全是 **`output`**（`src/rtl/eth/eth_udp_video_top.v:39` 起这一段方向声明），
  对应的 `*ready` 是 `input`——这是一只 AXI master 的标准形状。
- `system_top` 把这些线连到 BD 的 `M_AXI_HP0_awaddr / awlen / awsize / awburst / awvalid / awready /
  wdata / wstrb / wlast / wvalid / wready / bvalid / bready`（`src/rtl/top/system_top.v:193-199` 是
  `u_eth` 一侧的连接，`:88-103` 是 `u_bd` 一侧对应脚位）。
- BD 那边 `S_AXI_HP0_DATA_WIDTH {64}`、`PCW_USE_S_AXI_HP0 {1}`（`build/tcl/build_system_axigpio.tcl:100`），
  并且 `processing_system7_0/S_AXI_HP0` 与 `axi_mem_intercon/M00_AXI` 接成一条 net（同文件 `:198-199`）。
- 打包器把 16 bit 的字攒成 64 bit 再发，理由写在文件头：`AXI3 DDR 写入器（64bit 字）`
  （`src/rtl/eth/axi_frame_saver64.v:2`）。

SD 路——PS 是主设备，PL 只读：

- `src/ps/main.c:44`：「仲裁只管谁用 DDR→帧缓存那台搬运机，**管不到谁写 DDR（SD 的 DMA 走 PS 自己的
  HP0，不经过 PL）**，所以只能靠地址分开。」
- `src/ps/sd_play.h:4-5`：数据流 `SD(DMA) → DDR@BASE_ADDR →（PL 在 frame_start 拉一次 HP0 复制）→ 显示帧缓存`，
  并且"PS 全程不做 memcpy"。
- 两侧的握手只有一个 bit：PS 写完一帧翻一次 `gpio_o[18]`（`src/rtl/top/system_top.v:288`
  的 `.ps_publish(gpio_o[18])`）。"复制一次"而不是"每帧都复制"是关键——前者让 PS 有整个帧周期可以
  安全覆写 DDR，后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（`src/ps/sd_play.c:16-18`）。

控制面走的是另一条 AXI 通道，别与 HP0 混：PS 的 `M_AXI_GP0` → `axi_gp0_ic` → 三只 `axi_gpio_*`
（`build/tcl/build_system_axigpio.tcl:99` `PCW_USE_M_AXI_GP0 {1}`、`:190-195` 三条 connect），
GPIO_0 基址 `0x41200000`（`src/ps/main.c:48` 的 `AXI_GPIO_BASE`），GPIO_2 钉在 `0x41220000`
（`build/tcl/build_system_axigpio.tcl:145` 的注释与 `:150-151` 的双通道配置）。

---

## 5 时钟与域

### 5.1 `clk_gen.v` 的 MMCM：把配置逐行抄下来

这只模块是全设计节拍的唯一合成点，参数一共就几行，逐条列在这里（全部来自
`src/rtl/clocks/clk_gen.v`，行号是该文件本体）：

| 参数 | 值 | 行号 | 算出来的频率 |
|---|---|---|---|
| `BANDWIDTH` | `"OPTIMIZED"` | `:16` | — |
| `CLKIN1_PERIOD` | `20.000` | `:17` | 输入 50 MHz |
| `DIVCLK_DIVIDE` | `1` | `:18` | 分频后鉴相 50 MHz |
| `CLKFBOUT_MULT_F` | `20.000` | `:19` | VCO = 50 × 20 = **1 000 MHz**（同文件 `:3` 的注释就是这本账） |
| `CLKOUT0_DIVIDE_F` | `20.000` | `:21` | 1 000 ÷ 20 = **50 MHz** 像素钟 |
| `CLKOUT1_DIVIDE` | `4` | `:24` | 1 000 ÷ 4 = **250 MHz** 串化钟 |
| `CLKOUT2_DIVIDE` | `5` | `:27` | 1 000 ÷ 5 = **200 MHz** IDELAY 参考 |
| `REF_JITTER1` | `0.010` | `:30` | 10 ps |
| `STARTUP_WAIT` | `"FALSE"` | `:31` | 不等启动 |

三路输出各过一只 `BUFG`（`:53-56`，反馈走 `:53` 的 `u_bufg_fb`）。**这只模块被例化了两次**，
这是第一次读代码最容易漏的一件事：`src/rtl/top/pl_video_top.v:128` 的 `u_clk` 拿 `clk_pix`（50 MHz）
与 `clk_pix5x`（250 MHz），`clk_200m` 那路接在 `clk_200m_unused` 上（同一例化的 `:130`）；
`src/rtl/top/system_top.v:121` 的 `u_idelay_clkgen` 只为 IDELAYCTRL 拿 200 MHz，像素/5 倍两路显式接
`_unused`（`:123-124`）。所以 `build/report/clock_util.rpt:48` 的 `MMCM | 2 | 4` 与
`build/report/utilization.rpt:163` 的 `MMCME2_ADV | 2 | 0 | 0 | 4 | 50.00`（这一张表的列序是 Used / Fixed /
Prohibited / Available / Util%）——那个"2"不是冗余；同表 `:161` 的 `BUFGCTRL | 8 | 0 | 0 | 32 | 25.00` 是那八只 BUFG 的出处。

复位与锁定的耦合也在这里：像素链的复位是 `rst_pix_n = sys_rst_n & locked`
（`src/rtl/top/pl_video_top.v:132`），MMCM 一失锁整条像素链一起停；ETH 侧是
`.rst_n(eth_rst_n & mmcm_locked)`（`src/rtl/top/system_top.v:175`），而 `eth_rst_n` 由一只 24 位
上电计数器的 bit23 给出（`:108-112`），2^23 / 50 MHz = 8 388 608 × 20 ns ≈ **168 ms**（本卷算的：
操作数 2^23 是 `phy_rst_cnt[23]`（`src/rtl/top/system_top.v:112`）、50 MHz 来自 `rk_zynq7020.xdc:6`）。

### 5.2 五个域各自驱动什么

| 域 | 频率 / 周期 | 谁产生 | 驱动什么 | 周期这个数从哪份文件读来 |
|---|---|---|---|---|
| `sys_clk` | 50 MHz / 20.000 ns | 板载振荡器，引脚 W17 | MMCM 输入、两只按键的去抖与长按、上电复位计数器、`angle_ctrl` | `src/constraints/rk_zynq7020.xdc:5`（引脚）与 `:6`（`create_clock -period 20.000`） |
| `clk_fpga_0`（代码里叫 `axi_clk` / `fclk0`） | 100 MHz / 10.000 ns | PS7 的 `FCLK_CLK0` | AXI 读写、GPIO、两支搬运引擎、`snap_cross` 的目的域 | **不在 XDC 里**——它是 PS7 IP 自己的 XDC 从 BD 配置 `PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`（`build/tcl/build_system_axigpio.tcl:97`）推出来的；网名与驱动树在 `build/report/clock_util.rpt:59`（`g0 … clk_fpga_0 … FCLK_CLK_0_BUFG/O`），周期 10.000 在 `build/report/timing_summary.rpt:164` |
| `clkout0_1`（= `clk_pix`） | 50 MHz / 20.000 ns | `u_pl/u_clk` 的 MMCM `CLKOUT0` | 栅格、坐标映射、效果链、混合、OSD、`shown_rate` | `clkout0_1 {0.000 10.000} 20.000 50.000`（周期这行出自 `build/report/timing_summary.rpt:169`）；网名↔实例名对应见 `build/report/clock_util.rpt:60` |
| `eth_rxc`（收侧记作 `gmii_rx_clk`） | 125 MHz / 8.000 ns | PHY 的 RGMII 接收时钟，引脚 Y19，经 BUFG | 整个收包协议栈 + `frame_reasm` + `link_monitor` | `src/constraints/rk_zynq7020.xdc:20`（引脚）与 `:36`（`create_clock -period 8.000`）；BUFG 树 `build/report/clock_util.rpt:61` |
| `clkout1_1`（= `clk_pix5x`） | 250 MHz / 4.000 ns | 同一只 MMCM 的 `CLKOUT1` | TMDS 串化（OSERDESE2） | `build/report/timing_summary.rpt:170`；负载只有 8 个时钟脚，`build/report/clock_util.rpt:63` |

还有一只 200 MHz 的 `clkout2`（`CLKOUT1` 那一档 `DIVIDE 5` 之外的一路，`clk_gen.v:27`）专供
IDELAYCTRL 参考，周期 5.000 ns，`build/report/timing_summary.rpt:171`；它的负载只有 1 个脚
（`build/report/clock_util.rpt:65`）。加上 `clkfbout` 与 `clkfbout_1` 两只反馈钟，报告里一共
**八个时钟对象**，其中四只带 fabric 路径的 setup/hold 行（`build/report/timing_summary.rpt:164-171`
的 Clock Summary 全表）。

### 5.3 网名和代码名对不上时怎么读

实现后的报告用的是**综合后的网名**，与源码里的端口名不同名。唯一的对应表是
`build/report/clock_util.rpt:59-66` 那张 Global Clock Resources：

```
g0 clk_fpga_0  10.000 ns  3597 loads  ← u_bd/…/FCLK_CLK_0_BUFG/O
g1 clkout0_1   20.000 ns  3276 loads  ← u_pl/u_clk/u_bufg_pix/O   net = u_pl/u_clk/clk_pix
g2 eth_rxc      8.000 ns  2544 loads  ← u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O
g3 sys_clk     20.000 ns   186 loads  ← sys_clk_IBUF_BUFG_inst/O
g4 clkout1_1    4.000 ns     8 loads  ← u_pl/u_clk/u_bufg_5x/O    net = u_pl/u_clk/clk_pix5x
g5 clkfbout    20.000 ns     1 load   ← u_idelay_clkgen/u_bufg_fb/O
g6 clkout2      5.000 ns     1 load   ← u_idelay_clkgen/u_bufg_200/O
g7 clkfbout_1  20.000 ns     1 load   ← u_pl/u_clk/u_bufg_fb/O
```

`_1` 后缀是"同名 prim 的第二个实例"给的：`clkout0` 与 `clkout0_1`、`clkfbout` 与 `clkfbout_1`
分别来自那两只 `clk_gen`（对照 5.1 的两处例化）。看负载数就能判断哪只钟的树最重：
`clk_fpga_0` 3 597、`clkout0_1` 3 276、`eth_rxc` 2 544，其余都在 200 以下。

这一段最初是本卷写作者报出来的"文档与实现对不上"，现已按实现改口（台账 `report/log/issues.md:14276`）：
`report/technical-document.md` §2.1 一度把 `clkout0_1` 的用途写成"帧缓存写侧与 AXI 全互连"、
把 `clk_fpga_0` 写成"显示读出、几何、效果链、OSD"——两列正好贴反。按代码与上面这张 BUFG 表，
`clkout0_1` 就是 `u_pl/u_clk/clk_pix`，它驱动的是栅格 / 映射 / 效果链 / OSD
（`report/architecture.md` §2 的表也是这么列的，`clk_pix = clkout0`），而 AXI 与两支搬运引擎在
`clk_fpga_0`。判据以 `build/report/clock_util.rpt:60` 那一行与两处顶层端口连接为准。
留这段是为了记一条读表纪律：**表里"某列描述某一行"的对应关系，和列里的数字一样需要回核**——
每个数都对得上，行仍可能贴错；这类表要成对判，先判数、再判列与行的配对。

### 5.4 为什么 250 MHz 那条不纳检

结论：**因为那条域里没有任何被约束的端点，报告对它只出脉冲宽度一行。**

`build/report/timing_summary.rpt:187` 的 Intra Clock Table 里，`clkout1_1` 那一行
WNS / TNS / 失败端点 / 总端点四列**全空**，只有 `WPWS 2.408`、`TPWS Failing Endpoints 0`、
`TPWS Total Endpoints 10`。`report/05-timing.md:35` 把这一行抄成 `NOWRITE / NA`，并在
§7 第 1 条给了正确读法："这四行（`clkfbout`、`clkfbout_1`、`clkout1_1`、`clkout2`）在清单里是
`NOWRITE`/`NA`，它们的状态是**没有同沿路径行**，而不是已被证明关不掉。"

机制在代码里：这只 250 MHz 只有 8 个时钟负载（`build/report/clock_util.rpt:63`），全部是 OSERDESE2
的串行时钟脚（`src/rtl/hdmi/tmds_serializer.v:15`），即"并行 50 MHz 寄存器 → OSERDESE2 → 引脚"这一条路；
fabric 里没有 250 MHz 到 250 MHz 的组合路径，所以没有 setup/hold 可算。真正会把它纳检的是屏那一路的
对外时序，而它至今没有结论：`set_output_delay` 一条都没进默认约束（窗留在候选件
`src/constraints/r119_hdmi_source_window.xdc`，开关 `VP_R119_TMDS_WINDOW`）。量过的那一轮读数是——挂上窗
之后新纳检的 `clkout1_1` 那 6 个输出口端点整批红，setup −5.408 / hold −1.923 ns，同一轮四个老域的八个
读数里七个变差，于是判 DECLINE（`report/08-limits.md` §"现在的处置"一段）。这条欠账不会因为停手而消失。

---

## 6 面板与帧的数学

### 6.1 50 MHz 像素钟 → 1024×600 @ 59.5 Hz

结论：**59.5 是除出来的，不是配出来的。** 面板时序参数只有六个数，全部写在一个例化里
（`src/rtl/video/video_timing_1024x600.v:18-21`）：

```
H_ACTIVE 1024   H_FP 44   H_SYNC 88   H_BP 188   ⇒ H_TOTAL = 1024 + 44 + 88 + 188 = 1344
V_ACTIVE  600   V_FP  3   V_SYNC  6   V_BP  16   ⇒ V_TOTAL  =  600 + 3 + 6 + 16    =  625
```

两行合计也直接抄在同一文件的 `:3` 与 `:4` 的注释里。像素周期取 `clk_pix` 的 20.000 ns
（`build/report/timing_summary.rpt:169`），于是（下面每一格都是本卷按这两个操作数算的）：

| 量 | 算式 | 结果 |
|---|---|---|
| 一行 | 1344 × 20 ns | 26.88 µs |
| 一帧 | 625 × 26.88 µs | 16.80 ms |
| 场频 | 50 000 000 ÷ 1344 ÷ 625 | **59.52 Hz** ⇒ 文档一律写 59.5（`data/metrics.csv` 第 3 行"1024×600；H_TOTAL 1344、V_TOTAL 625 ⇒ 场频 59.5 Hz"，第 4 行"1024×600 @59.5"） |
| 垂直消隐 | (625 − 600) × 1344 × 20 ns | 25 行 = 33 600 像素拍 = 672 µs |

为什么是 59.5 而不是 60：面板 spec 的目标是 50.25 MHz 像素钟，本工程用 50 MHz 代它，误差 0.5 %
以内（`src/rtl/video/video_timing_1024x600.v:2` 的注释原文 `pixel clock 50 MHz (spec 50.25MHz, 0.5% ok)`）。
50.25 MHz 才会给出约 60 Hz，50 MHz 就落在 59.52。这条换算曾经被念错成"50 Hz"，
`data/metrics.csv` 第 3 行的括号里专门钉了一句"#153：不是 50 Hz"。

### 6.2 512×300 与 1024×600 的 ×2 关系

结论：**处理画幅 512×300，屏 1024×600，输出侧做整数倍 ×2 展开，所以"一源像素 = 2×2 显示像素"。**
代码里这条展开就一行：`wire [11:0] cx = x >> 1;`（`src/rtl/top/pl_video_top.v:242`，同一行的行尾注释
"视口内的源列（0..511），左右两半同一个数"），行方向是紧接下一行的 `cy = (y >> 1) < IMG_H ? … : IMG_H-1`
（`src/rtl/top/pl_video_top.v:243`，含越界钳位）。

为什么要 ×2 而不是直接把画幅提到 1024×600：一帧 RGB565 在 512×300 是 307 200 B，提到 1024×600
是它的 **4 倍**（(1024×600) ÷ (512×300) = 2 × 2 = 4，两个操作数分别来自
`video_timing_1024x600.v:18` 与 `system_top.v:136-137`），而这颗器件一共只有 140 个 BRAM tile、
本版已经用掉 95.5 个（`build/report/utilization.rpt:106`）。`src/host/video_sender.py` 的文件头把这条
写成了使用约束："把画幅提到 1024×600 需要四倍 BRAM，这颗器件放不下——不是软件开关的问题"（该文件 `:12-13`）。

副作用要一并记住：因为整屏只有**一份**源坐标，左右两窗在同一列上取的是同一个 `cx`，
"原图 / 处理图"的差别只在后面那一段链子上（`src/rtl/top/pl_video_top.v:239-240` 的注释把这条叫
"缝 0~100 % 可调与整体旋转缩放在数学上第一次相容"）。另一个副作用是效果链的空间尺度按 1024 列算：
`proc_pipeline` 收到的 `H_ACTIVE` 由顶层传 `#(.H_ACTIVE(2*IMG_W))` = 1024 个有效拍（`src/rtl/process/proc_pipeline.v:9-10`），
同级相邻两列在源上只差半格，所以横向模糊/锐化/Sobel 的半径实际是半个源像素——这是既成事实，
该文件 `:11-15` 特意把它写成一段警告。

### 6.3 一帧多少字节，一帧多少包

```
一帧 = 512 × 300 × 2 B  = 307 200 B        （宽高来自 system_top.v:136-137；×2 来自 RGB565 = 2 B/像素，见 frame_reasm.v:11 的 FRAME_BYTES = 307200）
     = 300 × 512 × 2 / 8 = 38 400 个 64 bit 字   （64 bit 打包器见 axi_frame_saver64.v:2；顶层注释也直接给了这个数：pl_video_top.v:394 "frame is 38.4k 64-bit words"）
     = 600 个 512 B 扇区                        （sd_play.c:34 的行尾注释 `RGB565 = 307200 B = 600 扇区`）
一帧包数 = ceil(307 200 / 1392) = 221            （分子同上一行，分母来自 video_sender.py:35；结果 221 直接钉在 src/host/one_click_test.py:25 `PKTS_PER_FRAME = -(-FRAME_BYTES // MTU)  # 221 包/帧`）
```

按 30 fps 推流的话，入口负载 = 307 200 B × 30 = 9 216 000 B/s ≈ 9.2 MB/s
（分子 `FRAME_BYTES` 见 `src/rtl/eth/frame_reasm.v:11`，30 fps 见 `src/host/video_sender.py:44`
的 `--fps` 默认值 30.0；这一格 `data/metrics.csv` 第 13 行也是 9.2 MB/s，并说明"这是负载口径不是实测带宽"）。

### 6.4 1392 这个上限是怎么来的

结论：**它是"两条硬约束 + 一条工程账"的交点，不是什么标准 MTU 值。**

| 约束 | 内容 | 出处 |
|---|---|---|
| 必须是 8 的倍数 | 包边界若落在 64 bit DDR 字中间，打包器对同一个字分两次推送会互相覆盖 ⇒ 屏上出现规律黑点 | `src/host/udp_push.py:5-7`；`src/host/video_sender.mjs:21-22` 同一句话，并说明 `--mtu-payload 1396` 是**复现**这个错误用的对照，不是日常用法 |
| 加上 4 字节的头之后不能触发 IP 分片，因为收包链不分片 | 载荷上限 1392 B | `src/host/video_sender.py:35` 的行尾注释；分片后果见 `study_docs/main_docs_course_walkthrough/walkthrough/interface-contract.md:174`"超过 1392 B 会触发 IP 分片，而收包链不分片" |
| 整包长度必须小于 1500 | 本卷按仓库里的两个操作数自己算：载荷 1392（`video_sender.py:35`）+ 帧内偏移头 4（`video_sender.py:34` `HDR = 4`）= 1396 B 的 UDP 载荷；再加 UDP 头 8 B = 1404；再加 IP 头 20 B = 1424；再加以太网头 14 B = **1438 < 1500**。（UDP/IP/以太网的头长在收侧解析器里对应 `src/rtl/eth/udp_rx_parser.v` 与 `src/rtl/eth/gmii_rx_mac.v` 的字段偏移，本卷只借用这两个常数做加法。） | 计算式与两个操作数如上；`1392 % 8 == 0`、`1396 % 8 == 4`（后者就是那条"规律黑点"的形状） |
| 今天仍然选 1392 而不是 1456 | v6.4 起写选通按 16 bit lane 生成，1396 那一行复测已经变干净，硬件对这个坑免疫；仍留 1392 是"少发重复 beat、便于用包内相位定位"两条工程账，不是物理约束 | `study_docs/main_report_study/learn/20_capture_and_display_path.md:156-159`，其转引的原始凭据是 `report/host_guide.md` 的 1392/1396 对照行 |

包内偏移用 4 字节小端整数表示（`[u32 LE byte_offset][RGB565 载荷]`，`src/host/video_sender.mjs:9`、
`src/host/video_sender.py:4-5`），所以"一个随机 UDP 包"对下游而言就是一次地址随机的 ≤1392 B 写。

### 6.5 真正的时间预算是垂直消隐

这条数学是全设计最要紧的一格，值得单独列出来：**显示帧缓存的整幅搬运只能塞在垂直消隐里**。

```
消隐预算 = 25 显示行 × 1344 拍/行 = 33 600 个像素拍 × 20 ns = 672 µs     （1344/625 见 video_timing_1024x600.v:3-4；20 ns 见 timing_summary.rpt:169）
换到 100 MHz 的 AXI 域 = 672 µs ÷ 10 ns = 67 200 拍                      （10 ns 见 timing_summary.rpt:164）
搬运需求 = 38 400 个 64 bit 字 ÷ ≤2 拍/字 ⇒ 最多 76 800 拍，实际取决于在途深度
                                                      （分子见 pl_video_top.v:394 注释；分母上限见 axi_frame_saver64.v:3）
```

代码里把这条账钉成了一个门限常数：`localparam [31:0] VBLANK_AXI_CYC = 32'd67200;`
（`src/rtl/top/pl_video_top.v:446`），窗口判据是 `disp_quiet = (y >= DISP_V_LINES) && ((y < DISP_V_LAST) || (x <= VB_X_GUARD))`
（`src/rtl/top/pl_video_top.v:400-401`），其中 `DISP_V_LINES = 600`、`DISP_V_LAST = 624`、
`VB_X_GUARD = 1279`（`:397-399`）。`VB_X_GUARD` 取 1279 = 1344 − 65，注释给的原因是"早关 64 个消隐
像点——`allow_copy_axi` 过 `frame_commit_lock` 的 CDC 要晚这个窗口约 5 个像素拍"（`:399`）。

后果值得记一句：赶不上窗口就整笔作废、屏上保留上一帧，把关的是 `frame_commit_lock`
（`report/02-architecture.md` §"数据通路与缓冲"末段）。这条设计换来的性质是"显示 BRAM 在每一行有效
像素期间持有的是一整帧"，于是既没有新旧接缝，也没有读写冲突——这段因果是
`src/rtl/top/pl_video_top.v:392-396` 的注释自己写出来的（英文原文，v5 那条固定位置的黑线就是
copier 中途追上电子束造成的）。

---

## 7 资源占用与它说明什么

### 7.1 读数

实现后的绝对数，逐格取自 `build/report/utilization.rpt`（同一份数在 `data/metrics.csv` 第 8~11 行，
README 表格也念它）：

| 资源 | 已用 | 可用 | 占比 | 出处（`build/report/utilization.rpt` 的行号） |
|---|---|---|---|---|
| Slice LUTs | 14 154 | 53 200 | **26.61 %** | `:35` |
| ├ LUT as Logic | 9 969 | 53 200 | 18.74 % | `:36` |
| ├ LUT as Memory | 4 185 | 17 400 | 24.05 % | `:37` |
| │ └ LUT as Distributed RAM | 4 044 | — | — | `:38` |
| │ └ LUT as Shift Register | 141 | — | — | `:39` |
| Slice Registers | 8 188 | 106 400 | **7.70 %** | `:40` |
| F7 Muxes | 1 164 | 26 600 | 4.38 % | `:43` |
| Block RAM Tile | 95.5 | 140 | **68.21 %** | `:106` |
| ├ RAMB36/FIFO | 93 | 140 | 66.43 % | `:107` |
| └ RAMB18 | 5 | 280 | 1.79 % | `:109` |
| DSP48E1 | 19 | 220 | **8.64 %** | `:121` |
| BUFGCTRL | 8 | 32 | 25.00 % | `:161` |
| MMCM (`MMCME2_ADV`) | 2 | 4 | 50.00 % | `:163` |

时序与功耗一并列在这里，因为它们同样是"还能不能改"的约束：全设计 setup WNS **0.739 ns**、
hold WHS **0.052 ns**、失败 setup/hold 端点 **0 / 51 135**、脉冲 WPWS 0.264（这一整行的原始形状是
`build/report/timing_summary.rpt:151` 那一行连续数字；`data/metrics.csv` 第 5~7 行分三行抄它，
`build/r126_gates.txt` 第 11–14 行是门禁对这四项的判据）。逐时钟：`clk_fpga_0` 1.850 / 0.053、
`eth_rxc` 0.739 / 0.052、`clkout0_1` 3.630 / 0.059、`sys_clk` 14.876 / 0.222，端点数分别是
15 721 / 4 835 / 30 179 / 323（`build/report/timing_summary.rpt:181-187` 的 Intra Clock Table）。
动态功耗 2.213 W、片上合计 2.391 W、工具置信度 **Low**（`build/report/power.rpt:36`、`:33`、`:41`）
⇒ 这是估算，不是实测。

### 7.2 这两格余量各说明什么

**BRAM 68.21 %：能加的"缓存类"改动很有限，能加的"算术类"改动完全不受它限制。**
剩下的余量本卷算得出来：140 − 95.5 = **44.5 个 tile**（两列都取自 `utilization.rpt:106`）。
按本版一帧 307 200 B ÷ 95.5 tile ≈ 3 217 B/tile 摊，44.5 tile 只能再多放约 143 KB（分子
`FRAME_BYTES = 307200` 见 `src/rtl/eth/frame_reasm.v:11`，分母同上），而 1024×600 的一帧要
1 228 800 B（(1024×600) × 2，因子来自 `video_timing_1024x600.v:18` 与 `src/ps/main.c:40` 的
`FRAME_BYTES (FRAME_W * FRAME_H * 2)` 的算法）⇒ **画幅提到面板分辨率在 BRAM 这层就过不了**，与 6.2 一致。

这 95.5 tile 的主要去向恰好就是"缓存"：`data/metrics.csv` 第 10 行的条件列写着"帧缓存由 64-bit 宽 +
乒乓两块拼出，是 BRAM 的主要去向"。所以任何新增行缓存、新增 FIFO、把组合逻辑改成表查询的改动，都要
先对着 44.5 tile 算一遍。历史上这里翻过一次车：把打包 FIFO 从触发器改成 LUTRAM 释放了约 5 万个 FF，
代价是 **BRAM 一度顶到 98.93 %**，随后才回落到本版 68.21 %（`report/technical-document.md` §7.3 末段）
⇒ 这一格余量不是天生这么大的。还有一条容易踩：BRAM 与 LUT 在抢同一种资源——`utilization.rpt:37` 的
LUT as Memory 4 185 里 4 044 是分布式 RAM（`:38`），而 `src/rtl/eth/axi_frame_saver64.v:10-12` 明写
打包 FIFO 的存储"必须是**分布式 RAM**"，因为早先让它综合成触发器时 512×100 bit ≈ 5.1 万 FDRE 直接吃掉
整机 Slice Register 的 94 %。动这一层要同时看 BRAM%、LUT-as-Memory%、FF% 三格，只看一边会被自己骗到。

**DSP 8.64 %：算术类改动还有一大截余量，但要先知道 19 个都花在哪。**
可用 220 个（`utilization.rpt:121` 的 Available 列），已用 19，余 201 个（同一行两列相减）。
逐实例的账是 `u_lerp` 6 + `u_blur` 1 + `u_split_ctrl` 1 + `u_zfit` 3 + `u_zmap` 8 = 19
（`report/technical-document.md` §3.3；`data/metrics.csv` 第 11 行同样给出这一串，并点名逐实例那份
报告是 `build/util_hier_probe.rpt`）。同一行还特别标注 **gamma 那一级 DSP = 0**，因为它是 LUTRAM
查表、不做乘法。

这条余量的实际含义是：再加一档需要乘法的算法（更高斯、更多抽头的滤波、色域矩阵 3×3 就是 9 个乘）
在 DSP 这一层不会成为瓶颈；瓶颈会在 BRAM（行缓存）和那个最紧的 100 MHz / 50 MHz 域。
而反过来，"把画幅提到面板分辨率"这类改动，DSP 有 201 个空位也没用，因为挡住它的是 7.2 前半段
那 44.5 tile。两格余量指的是两类完全不同的改动，混着念会得出错误结论。

最后一句必须一起念：**这些百分数是"这一版工具、这一颗器件、这一次布局"的读数。**
`build/r126_gates.txt` 第 2 行的新鲜度是 `system.bit 2026-10-04 04:36:56 / timing 2026-10-04 04:37:30`，
第 3 行的身份是 `system.bit md5=cd04907e1369`。同一份门禁文件第 6 行还有一条 WARN：有 RTL 源比
`system.bit` 新（列出 `src/rtl/eth/icmp_tx.v`、`src/rtl/top/pl_video_top.v`、`src/rtl/top/system_top.v`），
意思是这份产物不含这些改动。所以引用这一节任何一个数之前，先确认自己手里的是同一版报告。

---

## 8 术语最小表

只收这套系统里真的会用到的词，每条按"是什么 / 在这套代码的哪一处"来写，不抄教科书定义。

| 术语 | 说人话 | 在本工程里的位置 |
|---|---|---|
| setup | "数据要赶得上采样沿"。时钟周期扣掉路径延迟后还剩多少，叫 setup slack | `build/report/timing_summary.rpt:181-187` 的 WNS 列；本设计最差 0.739 ns |
| hold | "数据不许跑得比采样沿还早到"。检查的是最短路径，与周期无关，所以只有布线延迟能修它 | 同一张表的 WHS 列，最差 0.052 ns 在 `eth_rxc` |
| WNS / WHS / TNS / WPWS | Worst Negative Setup / Hold：全设计或某一时钟域最差的那一格 slack；TNS 是所有违例的总和；WPWS 是最短脉冲宽度余量 | 报告表头就在 `build/report/timing_summary.rpt:149`；`build/r126_gates.txt` 的判据行直接拿 WNS/WHS 两个数 |
| CDC | Clock Domain Crossing，跨时钟域。规矩是"电平用 3 级同步、脉冲先转翻转位、宽总线走快照、连续流走格雷码 FIFO" | 四类做法的分工表在 `report/architecture.md` §2 末段；对应实现 `effect_ctrl.v`、`key_long`→`src_mode`、`snap_cross.v`、`dc_fifo.v` |
| ping-pong（乒乓） | 同一份数据用两块缓冲交替：一块在被写、另一块在被读，写完读、读完写 | DDR 上的两块是 `BANK0/BANK1`，`src/rtl/eth/eth_udp_video_top.v:67-68`（差 `0x0008_0000`）；持有这个关系的是 `ddr_bank_commit` |
| bilinear（双线性插值） | 目标像素落在四个源像素中间时，按两个方向的线性加权求值。两级：先横向、再纵向 | `src/rtl/process/bilin_lerp.v`（实例 `u_lerp`，6 个 DSP48）；运行时开关 `gpio_o[19]`（`src/rtl/top/system_top.v:286`）；读口行缓存 `BILIN_ROWS = 2`（`pl_video_top.v:250`） |
| inverse mapping（逆映射） | 不去算"源像素映到屏上哪儿"（那样目标像素会漏），而是遍历每个目标像素、反算它的源坐标 | 缩放 `src/rtl/process/zoom/zoom_mapper.v`、旋转 `src/rtl/process/rotate/rotate_mapper.v`（Q8 的 sin/cos 表在 `sin_rom.v`/`cos_rom.v`） |
| OSD | On-Screen Display：把状态字直接叠在视频上面输出 | `src/rtl/video/osd_overlay.v`，顶层实例 `u_osd`（`src/rtl/top/pl_video_top.v:999`）；5 行版式见 `report/architecture.md` §4 |
| TMDS | Transition-Minimized Differential Signaling：HDMI 的三线对 + 一线对时钟的编码，8 bit 经 10:1 串化 | 编码器 `src/rtl/hdmi/tmds_encoder.v`，串化 `tmds_serializer.v:15` 的 OSERDESE2；并行 50 MHz、串行 250 MHz，正好 1:5，8b/10b 与 5 倍频相乘给出 4:1 的名义像素率比 |
| RGMII / GMII | GMII 是 8 bit 并行 @125 MHz 的 MAC↔PHY 接口；RGMII 把它压成 4 bit、双边沿 @125 MHz，引脚少一半 | `src/rtl/eth/rgmii_rx.v` 用 5 只 IDDR 还原（文件头 `:2` 讲清"正沿是低半字节、负沿是高半字节"）；发侧 `gmii_to_rgmii.v`、`rgmii_tx.v` |
| AXI GP / HP | Zynq 的 PS↔PL 两类 AXI 端口：GP 是通用目的、窄、走地址映射；HP 是高带宽、直接进 DDR 控制器 | 本工程的分工正是这个：GP 走 GPIO（`build/tcl/build_system_axigpio.tcl:99` `PCW_USE_M_AXI_GP0 {1}`、`:190` 起连到三只 `axi_gpio_*`），HP 走数据面（`:100` `S_AXI_HP0_DATA_WIDTH {64}`、`:199` 与 `axi_mem_intercon/M00_AXI` 成 net） |
| owner / `src_arb` | "此刻谁拥有 DDR→帧缓存这台搬运机"。owner 变化只在两个引擎都空闲时发生 | `src/rtl/util/src_arb.v:31`（`owner_eth`）、`:48`（`both_idle`）、`:67-75`（唯一赋值点） |
| lane | PS 侧不新加通路，而是"先写 lane 号、再读一个 32 bit 字"的观测窗口 | 号在 `gpio_o[31:27]`（`src/rtl/top/system_top.v:219`），读回 `gpio1_i`（`:247`）；lane 定义在 `link_monitor.v` 尾部的 `lm_bus` |
| WSTRB | AXI 写选通：一个字节一条，允许部分写 | 打包器按 16 bit lane 生成 `m_axi_wstrb`（`src/rtl/eth/axi_frame_saver64.v:2` 的形状 + `src/rtl/top/system_top.v:196` 的连接），这正是"非 8 倍数载荷不再产生黑点"的原因 |

---

## 9 本卷的数字速查（每条带一个能打开的位置）

| 数字 | 含义 | 位置 |
|---|---|---|
| `xc7z020clg484-2` / 2025.2.1 / 6403652 / v24.21.0 | 器件；Vivado 版本与构建号；Node | `report/declarations.md:9,10,11,13` |
| 50 / 100 / 125 / 250 MHz | `sys_clk` / `clk_fpga_0` / `eth_rxc` / `clk_pix5x` | `rk_zynq7020.xdc:6,36`；`build_system_axigpio.tcl:97`；`build/report/timing_summary.rpt:164-170` |
| 1000 / 50 / 250 / 200 MHz | VCO 与三路 CLKOUT | `src/rtl/clocks/clk_gen.v:19,21,24,27` |
| 1344 × 625 / 59.5 Hz | H_TOTAL × V_TOTAL 与场频（50e6 ÷ 1344 ÷ 625） | `src/rtl/video/video_timing_1024x600.v:3-4`；`data/metrics.csv` 第 3 行 |
| 512 × 300 / 1024 × 600 / 307 200 B | 处理画幅 / 面板 / 一帧字节 | `system_top.v:136-137` / `video_timing_1024x600.v:18` / `frame_reasm.v:11` |
| 1392 B / 221 包 | 载荷上限 / 一帧包数 | `src/host/video_sender.py:35` / `src/host/one_click_test.py:25` |
| 0x1000_0000 / 0x1008_0000 / 0x1010_0000 / 5001 | ETH 乒乓 / PS 专用 / UDP 端口 | `eth_udp_video_top.v:67-68` / `src/ps/main.c:46` / `system_top.v:145` |
| 31 / 67 200 | RGMII IDELAY 抽头 / 消隐窗预算（100 MHz 拍） | `src/rtl/top/system_top.v:172` / `src/rtl/top/pl_video_top.v:446` |
| 15 拍 / −4 行 | 效果链固定延迟 / 内容偏移 | `src/rtl/process/proc_pipeline.v:22,27` |
| 0.6 s / 0.2 s / 200 ms / 20 ms | 长按阈值 / 计时反馈 / 链路存活 / 让位滞回 | `key_long.v:9-10` / `link_monitor.v:13` / `src_arb.v:20` |
| 0.739 / 0.052 ns，0 / 51 135 | WNS / WHS，失败端点 / 总端点 | `build/report/timing_summary.rpt:151` |
| 14154 / 8188 / 95.5 / 19 → 53200 / 106400 / 140 / 220 | LUT / FF / BRAM tile / DSP 的已用 → 可用 | `build/report/utilization.rpt:35,40,106,121` 的 Used 与 Available 两列 |
| 2.213 W / Low | 动态功耗与工具置信度 | `build/report/power.rpt:36,41` |
| 80 / 11768 / 82 / 49 / 2544 | RTL 文件数 / RTL 行数 / 台架数 / 条目数 / PS 代码行数 | `report/technical-document.md` §2.3；本卷复点过，两处一致 |

没找到来源、因此本卷没写的数字：HDMI 屏的厂牌与物理尺寸（仓库只有分辨率与时序，`report/board_pins.md`
没有面板型号那一格）；端到端时延的任何毫秒值（`data/metrics.csv` 第 20 行明确写"本表不填没有复核过的
数"，而第 25 行那个 33.34 ms 已于 2026-10-07 按凭据改名为"入流帧间隔（PL 内）"，不再被当端到端引用）；PS 的 CPU 占用百分比
（`report/02-architecture.md` 只写"CPU 占用接近 0"这类定性说法，没有读数）。

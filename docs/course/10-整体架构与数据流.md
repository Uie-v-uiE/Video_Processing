# 10 整体架构与数据流：原理 → 实现 → 取舍

前面九篇是一级一级看的。这一篇把它们接成一台机器，并回答两个问题：
**为什么边界切在这里**，以及**一份画面从网络到屏幕要经过哪几双手**。

## 1. 顶层只有五个部分

`src/rtl/top/system_top.v:2-3` 逐字写着：

```
system_top：FPGA 顶层（构建脚本的 top）。
design_1_wrapper(PS7+AXI) + clk_gen(IDELAY 参考) + eth_udp_video_top(自研收包，占 HP0 写 DDR)
+ pl_video_top(显示通路) + snap_cross(观测 lane 复用回 AXI)
```

| 块 | 干什么 | 时钟域 | 细读 |
|---|---|---|---|
| `design_1_wrapper` | PS7 硬核 + AXI 互连 + AXI GPIO（BD 生成） | PS 侧 | `01` 第 3.3 节 |
| `clk_gen` | MMCM：50 MHz 进 ⇒ 50 MHz 像素 + 250 MHz 五倍 + 200 MHz IDELAY 参考（VCO=1000 MHz） | `clk_in`→三路 | `src/rtl/clocks/clk_gen.v:2` |
| `eth_udp_video_top` | 收包、帧重组、写 DDR、控制面（arp/icmp/eth_ctrl）、链路健康 | `eth_rxc` 125 MHz + `axi_clk` 100 MHz | `04`、`05` |
| `pl_video_top` | 显示通路：搬帧 → 读口 → 效果链 → 混合 → 叠字 → 出屏 | `clk_pix` **单域** | `06`、`07` |
| `snap_cross` | 把各域的观测 lane 复用回 AXI 可读写口 | 跨域快照 | `src/rtl/eth/snap_cross.v` |

**架构上的第一个取舍**：显示通路坚持单域（`src/rtl/top/pl_video_top.v:5`："时钟域：clk_pix 单域；
PS 侧命令经 `effect_ctrl`/`src_*` 的同步器进来"）。所有会"动画面"的逻辑都在一朵钟里，
跨域只发生在**命令进来**与**观测出去**两处。这样屏上看到的与坐标相关的东西不会有相位歧义
（`07` 第 2.1 节那条 `#68` 就是单域换来的可判性）。

## 2. 一份画面的路径（数据流）

```
PC 推流(UDP 512×300 RGB565)
  → rgmii_rx 双沿拼字节                125 MHz
  → gmii_rx_mac 自算 FCS → udp_rx_parser
  → frame_reasm「每个源行都被写过才提交」
  → dc_fifo（BRAM 双时钟 FIFO，格雷码）→ 100 MHz
  → axi_frame_saver64 写 DDR 乒乓 bank
  → ddr_bank_commit：等真实交付，提交 base + 翻转 bank
  ──────────────── 上面是"收"，下面是"放" ────────────────
  → axi_frame_writer_gated/64 在消隐期把新帧搬进显示帧缓存（BRAM）
  → fb_bilin 读口（每源像素用满 4 拍，可出双线性抽头）
  → proc_pipeline 九级（级 0 gamma + 五个可选级，固定 15 拍、−4 行）
  → split_display 逐像素选原图/处理图（同帧 A/B）
  → osd_overlay 叠 5 行状态字
  → 同一份 RGB888+同步：一路走面板，一路走 u_dvi(rgb2dvi → 3× tmds_serializer)
```

写显示 BRAM 的时机被硬约束：**只在消隐期写**（`src/rtl/top/pl_video_top.v:6-7``：
"Display BRAM written ONLY by `axi_frame_writer_gated` during blanking (~de)；
commit base locked until copy completes"）。这是"永撕裂"的实现前提——
拷贝中途不会把正在扫描的那一半换掉。

HDMI 那一路的形状（`src/rtl/hdmi/rgb2dvi.v:2-3`、`src/rtl/hdmi/tmds_serializer.v:2-4`）：
10:1 串化用 **OSERDESE2 主从级联**，`DATA_WIDTH=10` 要求 `DATA_RATE_OQ=DDR`，
Master 出 D1–D8、Slave 出 D3/D4，Slave `SHIFTOUT` → Master `SHIFTIN`（UG471 的接法）。
`u_dvi` 吃的就是 `osd_overlay` 之后那一路，**与面板同一份内容**——
所以屏上看到的与 HDMI 抓到的必然一致，这一点在取证时很重要。

## 3. 三路片源与"谁搬帧"的仲裁

片源有三个：ETH（网络）、SD（PS 播 FAT32 文件）、TEST（PL 自绘测试图卡）。
它们不是"三选一的开关"，而是**两台引擎抢一台搬运机**：

`src/rtl/util/src_arb.v:2-8` 把为什么要单独成模块写得最清楚：

> 这件事的正确答案**不是**"哪边有数据"，而是"哪边活着 + 现在能不能安全换手"。
> 老写法是 `eth_mode = 3FF(|s_pkts)`，两个问题叠在一起：
> ① `|s_pkts` 是"自配置以来收到过任何一个包"——PC 的 ARP 就够触发，且**拔网线也不会回 0**，
>    于是 PS 片源被永久锁死；② 就算换成"最近有包"，两个引擎共用同一个 AXI 读口 +
>    同一个 BRAM 写口，选择位在**一次拷贝中途**翻转会留下半开的读突发。

⇒ 架构上把"活着"（`src_life`）、"模式/意愿"（`src_mode`、`ps_publish`）、
"换手时机"（`src_arb`）**分成三个模块**，而不是揉成一个 `if`。
`05` 第 4 节那条"仲裁只管搬运机、管不到谁写 DDR（SD 的 DMA 走 PS 的 HP0，不经过 PL）"
就是这套划分的另一半。

## 4. 观测：一帧的"活着"要有三样证据

| 观测量 | 产生地 | 怎么跨到 AXI 可读 |
|---|---|---|
| 丢字数 / 作废帧 / 帧间隔 / 断流周期 | `link_monitor`（125 MHz 域） | `lm_bus` 快照 + `lm_bus_tog` 边沿 → `snap_cross` |
| FPS（数**写进屏的新帧**） | `shown_rate`（`src/rtl/util/shown_rate.v:2-6`） | 同一 lane 复用 |
| 端到端时延 `lat_ms` | AXI 域打点 | 翻转位跨到像素域给 OSD，同时进 lane |

`shown_rate` 的来历是**一个口径错误被量出来**：原来数的是显示场的 `vs` 沿、窗口是 `sys_clk` 的
1.000 s，而面板实际是 1344×625@50 MHz ⇒ 59.52 Hz ⇒ 屏上那一格**恒在 59/60 附近**，
片源是 30 fps、15 fps 还是没有片源都看不出来（`:4-6`）。
修完之后那一格才等于"真的有新帧进屏"。**教训**：一个计数器的名字不构成它的定义，
定义由"它在哪个域的哪个事件上加一"决定。

## 5. 四朵钟与它们的物理来源（把 `08` 的表放到架构上看）

| 钟 | 来源 | 覆盖 |
|---|---|---|
| `sys_clk`（20 ns） | 板载晶振 | 复位/按键/部分观测窗口 |
| `clk_fpga_0`（10 ns） | PS7（BD 里的 FCLK0） | AXI、HP0 拷贝、`shown_rate` 窗口等 |
| `clk_pix`（20 ns，50 MHz） | `clk_gen` 的 MMCM | 整条显示通路（单域） |
| `eth_rxc`（8 ns） | PHY 恢复的源同步时钟 | 收包族 **+ 发侧协议栈（arp/icmp/udp）+ 512×100 位打包 FIFO**：`gmii_tx_clk` 与 `gmii_rx_clk` 是同一根（`src/rtl/eth/eth_udp_video_top.v:5`），所以它是全设计端点最密、setup 余量最薄的一族（4835 端点、相对余量 9.24 %，账在 `04` 第 7 节） |
| （派生）`clk_pix5x` 250 MHz、`clk_200m` | 同一 MMCM | TMDS 10:1 串化、IDELAY 参考 |

**为什么 MMCM 输出的名字带 `_1`**（`clkout0_1`）：那是 BD/MMCM 生成时钟的命名，
不是"第二版"；引用它的时候按工具给的名字引，不要自己造（`08` 第 1 节 `clk_fpga_0` 那条同一课）。

## 6. 资源与形状的账（为什么长成这样，不是想当然）

- 帧缓存用 **80 块 RAMB36**；再加一个逻辑读口会顶到 160 块而全片只有 140 块
  （`src/rtl/process/bilin/tap_sched.v:10-12`）⇒ 所以读口是"每源像素用满 4 拍"而不是"多开一个口"。
- 打包器 FIFO 是**承重**的：512/512 满，深度不许降（过程台账 `#140` 的资源量账）；
  存储必须是 LUTRAM（`src/rtl/eth/axi_frame_saver64.v:9-10`）。
- gamma 表与坐标映射都用 LUTRAM：异步读不占流水级（`02` 第 5 节、`05` 第 3 节）。
- 效果链的固定 15 拍与 −4 行是把窗口级的结构性代价**算进预算**后定的（`06` 第 4 节）。

## 7. 从这里读代码的建议顺序

1. `system_top` 的端口与五个实例（半小时能读完连线）；
2. `eth_udp_video_top`（收侧链路顺序 + 跨域纪律）；
3. `pl_video_top` 的 `u_pipe`/`split_display`/`osd_overlay`/`u_dvi` 四段；
4. 挑一级深挖：`02`/`03`/`06` 任一篇对应一个模块；
5. 最后读 `08`/`09`——**约束与验证是这台机器的一部分**，不是附件。

小结：这台机器的架构选择可以压缩成四句话——
**显示单域、跨域只走被允许的几条路、搬运机换手要有"活着 + 安全时机"两个条件、
所有观测量都要能被三处独立读到（屏、串口、JTAG）。**

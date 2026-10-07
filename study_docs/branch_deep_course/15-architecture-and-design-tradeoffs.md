# 15 整体架构与取舍账：数据怎么走、时钟怎么分、以及每一步为什么值那些资源

读完这一章要能回答四件事：一个字节从网线到屏上那一格到底经过哪几个例化名；这棵树里有几个时钟域、
跨域的**合法路**是哪几条、为什么只有这几条；PS 写的那三个寄存器窗口里每一位对应硬件上的哪件事；
以及最重要的一件——哪些改法是**量过之后采纳**的、哪些是**量过之后否决**的、哪些仍然欠着。

本章的每一条断言都指向打开过的文件行；资源与时序数字全部抄自 `build/` 里那一套 r118 产物
（`build/r118_gates_final.txt`），不是记忆。

---

## 1 顶层四块，职责按"谁碰 DDR"划分

`system_top` 是构建的顶层（`src/rtl/top/system_top.v:4`），它的端口就是板上那组真实引脚
（DDR/FIXED_IO/sys_clk/key1_n/key2_n/led/tmds_*/eth_*，`:5-42`）。内部只有四个大例化：

| 例化名 | 模块 | 职责 | 引用 |
|---|---|---|---|
| `u_bd` | `design_1_wrapper` | PS7（ARM + DDR 控制器 + HP0 互联 + 三个 AXI GPIO + FCLK/RESET） | `src/rtl/top/system_top.v:75-104` |
| `u_idelay_clkgen` | `clk_gen` | 只为 IDELAY 生 200 MHz 参考钟（其余三路输出处悬空） | `:121-125` |
| `u_eth` | `eth_udp_video_top` | 自研收包：RGMII→GMII→MAC→解析→重组→CDC→AXI 写 DDR | `:154-204` |
| `u_pl` | `pl_video_top` | 显示通路：读 DDR→帧缓存→效果链→几何→混合→OSD→TMDS | `:258-321` |

外加一小块**观测面复用回 AXI**的读数口：`u_lm_axi`（一台 `snap_cross`）加一个 5 路组合选择器，
把 `eth` 侧的健康快照送到 PS 能读的 GPIO_1（`:212-247`）。
这个"数据面自己走、观测面借用现成 AXI GPIO"的形状是刻意的：整个仓库没有给观测另开一条 AXI 主路。

文件头那句概括值得原文照抄（`src/rtl/top/system_top.v:2-3`）：
`design_1_wrapper(PS7+AXI) + clk_gen(IDELAY 参考) + eth_udp_video_top(自研收包，占 HP0 写 DDR) +
pl_video_top(显示通路) + snap_cross(观测 lane 复用回 AXI)`。

### 1.1 几何与地址只在顶层出现一次

`src/rtl/top/system_top.v:134-145` 定义了四个 localparam：`VIDEO_W=512`、`VIDEO_H=300`、
`PANE_W=512`、`DDR_BASE=32'h1000_0000`，再加 `PS_DDR_BASE=32'h1010_0000` 与 `UDP_VIDEO_PORT=5001`。
注释把为什么要收在一处写清了（`:135`）：原来 512/300/0x1000_0000 在下面两个例化上**各写一遍字面量**，
两个模块自己都有 parameter，但**没有任何东西阻止两边不一致** ⇒ 现象是"写进去的帧几何与读出来的
显示几何对不上"（整幅错位/撕裂），既不是综合错误也不是仿真必红。换分辨率因此从"全文搜字面量"
变成"改这四行"。

`PS_DDR_BASE` 这条是**跨语言的一致性**，比顶层内部的一致性更脆：`:140-144` 明写
"这个数必须与固件里的 `FRAME_ADDR` 一致：`src/ps/sd_play.c` 与 `src/ps/main.c` 各有一处，
改这里不改那边 ⇒ 现象是 PS 片源在屏上不动（搬运机读的是另一块内存）"。
固件侧同一件事写在 `src/ps/main.c:38-43`，那里还补了**为什么只能靠地址分开**：
"仲裁只管谁用 DDR→帧缓存那台搬运机，管不到谁写 DDR（SD 的 DMA 走 PS 自己的 HP0、不经过 PL）"。

### 1.2 DDR 的三个 bank

| bank | 地址 | 谁写 | 谁读 |
|---|---|---|---|
| BANK0 | `0x1000_0000` | `u_eth/u_saver`（PL 的 AXI master，AWLEN=0 流水化） | `u_pl/u_row` |
| BANK1 | `0x1008_0000` | 同上（乒乓） | 同上 |
| PS bank | `0x1010_0000` | PS 的 SD DMA / FILL | `u_pl/u_aw` |

`BANK0/BANK1` 的定义在 `src/rtl/eth/eth_udp_video_top.v:67-68`（`BASE_ADDR + 32'h0008_0000`），
乒乓关系由 `ddr_bank_commit` 的 `#(.BANK0(BANK0), .BANK1(BANK1), .TAIL_GUARD(1'b1)) u_commit`
（`:330-332`）持有；`src/rtl/top/system_top.v:140-141` 给的理由是"每帧 300 KB，间隔 512 KB 够用，
所以第三个 bank 从 +1 MB 起"。

---

## 2 端到端数据流：一路字节的完整旅程

### 2.1 收侧（`eth_rxc` / `gmii_rx_clk` 125 MHz）

```
eth_rxc/eth_rx_ctl/eth_rxd[3:0]
  → u_eth/u_rgmii            gmii_to_rgmii，内部 IDDR + IDELAY(#57 之后与 fabric 同吃一只 BUFG)
  → u_eth/u_rx_mac           gmii_rx_mac（自算 FCS）
  → u_eth/u_rx_par           udp_rx_parser（目的端口过滤，UDP_PORT=5001）
  → u_eth/u_reasm            frame_reasm（FRAME_BYTES 显式传入，#158）
  → u_eth/u_cdc              dc_fifo  BRAM CDC，36 bit × 8192
  ───────────────── 跨域边界（格雷码指针）─────────────────
  → u_eth/u_saver            axi_frame_saver64  axi_clk 100 MHz，AW/W 并行、B 不阻塞
  → u_eth/u_commit           ddr_bank_commit    提交脉冲带上 completed_base
```

例化名逐条来自 `src/rtl/eth/eth_udp_video_top.v`：`u_rgmii:73`、`u_icmp_fifo:119`、`u_arp:129`、
`u_icmp:142`、`u_udp_tx:163`、`u_rx_par:197`、`u_reasm:235`、`u_lm:286`、`u_cdc:298`、`u_commit:332`、
`u_saver:354`。文件头 `:2-6` 就是这条链的官方说法。

两处设计约束写在这个文件的头部注释里（`src/rtl/eth/eth_udp_video_top.v:5-6`）：
`gmii_rx_clk` 与 `gmii_tx_clk` 是**同一根**（收侧恢复出来的 125 MHz）；与 `axi_clk`（HP0 100 MHz）
之间**只准过 `dc_fifo` 的格雷码指针与 `ddr_bank_commit` 的 3 级同步器，其余一律禁止组合跨域**。

CDC 那一层的深度是量出来的，不是拍的：`:295-298` 写"8192 条 = 4096 个 64bit 字 = 16 KB，
足以吸收显示拷贝独占 HP0 一整个 V-blank 期间到达的入包数据（15 MBps × 672 µs ≈ 1260 字）"。
存储风格被钉成 BRAM（`src/rtl/eth/dc_fifo.v:20` 的 `(* ram_style = "block" *)`），
指针跨域只传格雷码（`:22`、`:35`），四颗格雷码寄存器带 `ASYNC_REG`（`:27`，r114 那一刀的成果）。

读侧的限速也在同一层（`src/rtl/eth/eth_udp_video_top.v:258-263`）：
一个 1392 B 的包在 125 MHz 下是**连续线速**进来的（上位机限速只能拉开包间隔），每包 698 个 16bit 写。
原来读侧限成"每 3 个 axi 周期取 1 条"= 66 MB/s < 125 MB/s，单包就能把 512 深的 CDC 灌满 →
稳定丢约 46 % 的字，表现为板上"每隔一个 16bit 空洞"的黑纹，且**与上位机速率无关**。
现在 1 条/周期（200 MB/s），并且 flush 标记永远让路给真实数据写。

### 2.2 写进 DDR 的那台机器为什么必须流水化

`src/rtl/eth/axi_frame_saver64.v:2-7` 给了完整的因果：AWLEN=0 + 写通道流水化，AW/W 并行挂出、
各自握手，发完立刻取下一个字（≤2 拍/字 = 400 MB/s），B 响应只在 outst 计数里回收、**永不阻塞数据通路**。
不流水化时的老形状（ISSUES #31）：每字走完 `S_AW→S_W→S_B`，在途深度恒 1 ⇒ HP0 写延迟（约 40 拍，
被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈ 20 MB/s ⇒ 板上"每包固定从第 48 字节起丢字"。
紧接着 `:7` 是这一整套架构里最值钱的一条经验：**"加深缓冲治不了它（ISSUES #32）：
瓶颈是平均排空速率不是深度，v6.2 把 CDC 做到 8192 时上板毫无改善。"**

同一文件 `:9-12` 还钉了打包器自己的存储类型：512 项打包 FIFO 的 `q_addr/q_data/q_keep`
必须是 `(* ram_style = "distributed" *)`（`:48-50`）——早先版本让它被综合成触发器
（512×100 bit ≈ 5.1 万 FDRE），占整机 Slice Register 的 94 %，FW=11 直接 DRC UTLZ-1。

### 2.3 读侧与显示（`clk_pix` 50 MHz）

```
frame_start / commit
  → u_pl/u_cmt   frame_commit_lock   把 eth_commit 与"能不能拷"合成 start_copy + copy_base
  → u_pl/u_row   axi_frame_writer_gated  axi_clk：逐行把 DDR 那一帧搬进显示帧缓存
  → u_pl/u_bilin fb_bilin             唯一的显示侧读口（内含帧缓存 + 双线性）
  → u_pl/u_raw   raw_line_delay       原图那一路，4 显示行 + 1 拍的行环（17 bit 打包过环）
  → u_pl/u_pipe  proc_pipeline        处理那一路，固定 15 拍、内容滞后 4 行
  → u_pl/u_split split_display        缝那一列逐像素二选一
  → u_pl/u_osd   osd_overlay          五行状态字叠上去
  → u_pl/u_dvi   rgb2dvi → tmds_serializer → OSERDE2 + BUFT
```

例化行号：`u_cmt:430`、`u_row:454`、`u_aw:694`、`u_bilin:734`、`u_bar:759`、`u_raw:788`、`u_pipe:800`、
`u_split:911`、`u_osd:999`、`u_dvi:1026`（均在 `src/rtl/top/pl_video_top.v`）。

搬运机是**一台、两归属**：`u_row`（ETH 那一路，`src/rtl/top/pl_video_top.v:454-470`）与
`u_aw`（PS 那一路，`:692-705`）共用同一组 AXI R 通道，切换靠
`assign m_axi_araddr = eth_mode ? row_araddr : fill_araddr;` 那六行（`:709-714`）。
`eth_mode` 就是仲裁结果 `owner_eth`（`:429`）。

**为什么读侧只有一个 `u_bilin`、没有"左用哪套源坐标/右用哪套"的 mux**：
`src/rtl/top/pl_video_top.v:720` 那句话是整个 r59b 几何改造的落点——
"一个读口、一条地址流、一份坐标（#73）：这里从此没有左用哪套源坐标、右用哪套的 mux"。
1024 个显示列对应 512 个源列 ⇒ 每个源列在屏上占两列；行方向 600 对 300，还是那一次 `>>1`
（`:238-240`）。代价写在 `:796-800`：行缓存宽度翻倍（约 +8 块 BRAM），而且 3×3 滤波的空间尺度
从"源像素"变成"显示像素"（横向覆盖 1.5 个源列）⇒ 横方向的模糊/边缘比旧版略宽。
这不是免费的，而且是**已知并被接受**的不免费。

读口为什么能挂在 50 MHz：`src/rtl/process/bilin/fb_bilin.v:4` 说"每个源像素用满它天然的 4 个
50 MHz 拍（2 显示列 × 2 显示行），一个读口每拍一次读，全程不进快域"。
这是这一整套里最漂亮的一笔——不为了插值去开一条 100 MHz 的快域，
而是利用"屏上每源像素本来就要占 4 拍"这个既成事实。

### 2.4 缝（seam）与两路抽头的同深度要求

`split_display` 的端口注释（`src/rtl/video/split_display.v:6-13`）记了这条为什么必须钉住：
以前那里直接用 `x` 判左/右窗，而顶层的 `x` 是第 11 级标签、`orig_pix/proc_pix` 却是第 20 级的内容
（3 拍打地址 + 1 拍读地址寄存 + 1 拍 BRAM + `u_pipe.LATENCY`=15）⇒ 判定比内容旧 9 列 ⇒
缝左边约 9 列里"标签说左窗、内容其实是右窗那一路（被强制清 0）"⇒ 选中的是 0 ⇒ 一条近黑的竖带：
这就是用户念的"缩放碰到分割线时周围出现颜色条"的第二个成分（第一个是故意画的蓝线）。

`src/rtl/top/pl_video_top.v:819-826` 记了另一半：原图那一路 = `raw_line_delay`(1 拍 RAM 读出) +
`orig_skid`(PROC_LAT 拍) = **PROC_LAT+1 拍**，而链子自己只有 PROC_LAT 拍 ⇒ 处理抽头比原图抽头
早一整拍 = 混色级早一整列。1.00x 时画面铺满整屏看不出来；一缩小，左边界就把"画面自己最左那一列"
甩进背景带、右边界少一列。**"贴在边上的一条线"这一笔占一列。**
所以 `PROC_LAT` 只从 `u_pipe.LATENCY` 取（`:813-816`，注释："以前这里是字面量 7，于是链上加一级
必须同时记得改这里——忘了不是编译错，而是左窗与右窗错开 N 个像素"）。

行方向的提前量在 `src/rtl/top/pl_video_top.v:276-284`：
`y_right_adv = y + pipe_off_rows + BILIN_ROWS`、`y_req_row = y_right_adv >> 1`、
`cy_r = (y_req_row >= IMG_H) ? (y_req_row - IMG_H) : y_req_row`。
`:278-283` 解释这是"资源换正确"的一刀：帧缓存是随机地址的，把右窗读坐标对应的显示行提前
`OFF_LINES` 行，链子自己的滞后正好把它抵消（零 BRAM）。`:280-283` 又钉了两条纪律：
取模的对象是**请求行**，窗必须按"写进环的那一拍"来开；`y_req_row` 最大 302 ⇒ 减一次就够，
**不需要除法器/取模**。

---

## 3 时钟与复位拓扑

### 3.1 六个时钟对象，四个真正被使用

| 时钟 | 周期 | 谁产生 | 挂在哪 |
|---|---|---|---|
| `sys_clk` | 20.000 ns / 50 MHz | 板晶振（`create_clock` 在 `src/constraints/rk_zynq7020.xdc:6`） | 顶层按键/时序发生器/`angle_ctrl` |
| `eth_rxc` | 8.000 ns / 125 MHz | PHY 恢复出来的 RXC（`rk_zynq7020.xdc:36`） | 整条收包链 + 整套发侧协议栈 |
| `clk_fpga_0` (`fclk0`) | 10.000 ns / 100 MHz | **PS7 IP 自己 create**（FCLKCLK[0]），不在手写 xdc 里 | AXI 两侧（`u_saver`/`u_row`/`u_aw`/`u_arb`/`u_cmt`）+ 观测跨域 |
| `clkout0_1` (`clk_pix`) | 20.000 ns / 50 MHz | `u_clk` 的 MMCM CLKOUT0 | 整条显示通路 |
| `clkout1_1` (`clk_pix5x`) | 4.000 ns / 250 MHz | CLKOUT1 | 只喂 `u_dvi` 里的 TMDS 串行化 |
| `clkout2` | 5.000 ns / 200 MHz | CLKOUT2 | IDELAY 参考（`u_idelay_clk`、`u_eth` 的 `idelay_clk`） |

MMCM 的参数在 `src/rtl/clocks/clk_gen.v:15-30`：`CLKIN1_PERIOD=20.000`、`CLKFBOUT_MULT_F=20.000`
⇒ **VCO = 1000 MHz**，`CLKOUT0_DIVIDE_F=20.000`（50 MHz）、`CLKOUT1_DIVIDE=4`（250 MHz）、
`CLKOUT2_DIVIDE=5`（200 MHz）。四路输出各挂一只 `BUFG`（`:50-53`）。

同一份 `clk_gen` 被例化**两次**：`u_idelay_clkgen`（顶层，只取 `clk_200m`，
`:121-125`）与 `u_pl` 内部的 `u_clk`（`src/rtl/top/pl_video_top.v:128-132`，取 `clk_pix`/`clk_pix5x`，
`clk_200m` 悬空）。所以 `mmcm_locked` 有两个来源，顶层把 `u_idelay_clkgen` 的那一枚喂给了
`u_eth` 的复位合流（`src/rtl/top/system_top.v:175`：`.rst_n(eth_rst_n & mmcm_locked)`）。

时钟清单与端点数是从名册读的（`时序债务账` §1 那张表，`:18-27`）：
`sys_clk` 323 端点、`eth_rxc` 4835、`clk_fpga_0` 15721、`clkout0_1` 30179；
`clkout1_1`/`clkout2`/`clkfbout`/`clkfbout_1` **无 intra 路径行**——
同表 `:26` 特意注明"NA 是这一族没有同沿路径，而不是读不到"。

### 3.2 `eth_rxc` 到底是什么域，以及 LUTRAM 打包器不在里面

这是最容易被写错的一句归属话，所以把它说plainly：

**`axi_frame_saver64`（那个 512×100 bit 分布式 RAM/LUTRAM 打包器）在 `axi_clk`（即 `clk_fpga_0`，
100 MHz）那一侧，不在 `eth_rxc`。** 连线证据是 `src/rtl/eth/eth_udp_video_top.v:355` 那一行写的
`.clk(axi_clk), .rst_n(axi_rst_n)`（例化行 `:354`）；同文件 `:4` 的时钟域注释也是同一句话
（"时钟域：全程 `axi_clk`（HP0 100 MHz）；入包侧的字由 `eth_udp_video_top` 里的 BRAM CDC 打过来"
写在 `src/rtl/eth/axi_frame_saver64.v:4`）。`eth_rxc` 那一侧真正挂着的是收包链本身
（`u_rgmii`/`u_rx_mac`/`u_rx_par`/`u_reasm`）与发侧协议栈（`u_arp`/`u_icmp`/`u_udp_tx`），
以及 `link_monitor`（`:286-293`，`.clk(gmii_rx_clk)`）。

这件事在 `域划分候选评估` §1 被正式纠正过一次，值得完整读一遍它的口径：
"先前写下的那条前提：打包器 `axi_frame_saver64` 和收包链挤在同一颗 8 ns 时钟上，所以它是这个域过载
的主要构成"——"实测的连线：`src/rtl/eth/eth_udp_video_top.v:355` 写的是 `.clk(axi_clk)`……
**打包器本来就在 `clk_fpga_0`（100 MHz）那一侧，不在 `eth_rxc`**"——"所以这条候选作废。
它不是更便宜的版本，它是把域归属写错了"（`域划分候选评估`）。

`eth_rxc` 上真正挂了多少寄存器是有件的数：**2544**（`域划分候选评估`，
出处 `build/clock_util.rpt:174`），对比 `clk_fpga_0` 的 3338（同页 `:15`）。
同域最差那条的起止也点名了：`u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C →
…/check_buffer_reg[19]/D`，逻辑约 41.6 %、布线约 58.4 %（`:16-17`）。
**所以 `eth_rxc` 的瓶颈不是收口 RTL、也不是那条 LUTRAM，是发侧的 ICMP 校验和加法树**——
这一条在 `开发台账` 的 #378 段里被归因结案（"最差那条不是 RGMII 收口 RTL，
是 `src/rtl/eth/icmp_tx.v` 里一拍加 5~6 项的校验和加法树，11 级逻辑含 6 个 CARRY4、route 58 %"）。

### 3.3 复位拓扑：没有一根全局复位树

复位是**分域各来一份**的，这决定了后面所有同步器的写法：

- `sys_rst_n = 1'b1` 直接接（`src/rtl/top/system_top.v:260`）——顶层没有外部复位引脚。
  上电语义被写进**声明初值**（r113 那一刀，`build/runs/decisions.md` 的 r113 行：
  "带 `rst_n=1'b1` 再综合的那个 1 确实进位流：`probe_init_tied_rst.tcl` 量到 FDRE INIT=1'b1 ×4"）。
- `eth_rst_n` 是一根 24 bit 计数器的最高位（`src/rtl/top/system_top.v:108-112`），
  即上电后自动放开，且与 `mmcm_locked` 相与后才给 `u_eth`（`:175`）。
- `fclk0_rst_n = FCLK_RESET0_N`，由 PS7 出（`:83`）。
- 像素域复位是**本地合成**的：`wire rst_pix_n = sys_rst_n & locked;`
  （`src/rtl/top/pl_video_top.v:132`）——MMCM 没 lock 之前像素域不得运行。

`PHY 的复位`（`eth_rst_n`）是片内计数器产生的，而 MDIO 那一路今天**根本不碰**：
`src/rtl/top/system_top.v:113-117` 说"本工程的数据面不碰 MDIO（RGMII 走 16-27，MDIO 52-53 不用），
PHY 的工作模式由板上 strap 定 ⇒ MDIO 高阻、MDC 钉 0。综合报 `Synth 8-3917 port eth_mdc driven by
constant 0` 是**陈述而不是缺陷**；要真做 PHY 寄存器读写得另起一个位时序机，那一版再来消它"。
这句话同时也解释了 `时序债务账` §2 里为什么 `eth_mdio`/`eth_mdc`
能被列为"无理由不成立但也没有寄存器到管脚路径"的豁免（`build/runs/decisions.md` 的 D2 段，
#385：`I3 7→4`，剩下四组正是 TMDS）。

### 3.4 跨域只准走三种形状

| 形状 | 用在哪 | 代码位置 |
|---|---|---|
| 准静态电平：3 级 `ASYNC_REG` | `src_sel`、`zoom_en`、`bilin_en_axi`、`osd_off_axi`、`gapclr_sel` | `src/rtl/top/pl_video_top.v:471-474`（`ss*`）、`:491-496`（`el*`）、`:267-275`（`oo*`）；`src/rtl/eth/eth_udp_video_top.v:277-281`（`gc*`） |
| 翻转位 + 3 级同步 + 整拍锁存（`snap_cross`） | 几何控制字 19 位、缩放状态 20 位、latency 18 位、健康快照 320 位 | `src/rtl/top/pl_video_top.v:876`、`:674`、`:980`；`src/rtl/top/system_top.v:214` |
| BRAM/分布式 RAM 双口 FIFO（格雷码指针） | `dc_fifo`（CDC）、`sync_fifo`（发侧） | `src/rtl/eth/dc_fifo.v:22`、`:27`；`src/rtl/eth/eth_udp_video_top.v:298`、`:119` |

三条纪律各有事故编号，而且**都是被 CDC 报告反过来教的**：

1. **脉冲不许直接跨域**。`src/rtl/top/pl_video_top.v:144-147`：长按事件用**翻转位**跨域
   （"脉冲跨域会被吃掉，与 `ps_publish` / ISSUES #36 是同一课"）。
2. **同一个翻转位不许扇出到两组目的域同步器**。这条被违反了两次、红过两次：
   `src/rtl/top/pl_video_top.v:231-235`（"自动旋转的节拍⚠ **单独一个发射触发器**，不共用现成的
   `sof_tgl`/`z_hb_tog`：同一个翻转位扇出到两组目的域同步器 = CDC-11 Critical 的签名，
   本文件里已为这件事红过两次（#65、r54 构建 #34）"）、`:971-978`（latency 那一票同样另起一只 FF）。
   `src/rtl/top/system_top.v:281-286` 补了第三条同族的"不要复用"：`bilin_en_axi`
   **不并进 `effect_ctrl` 那条已批准的链**（#71 的红线），也不与任何现成发射 FF 共用。
3. **组合或缩出来的电平不能直接被另一个域的触发器采走**。`src/rtl/eth/eth_udp_video_top.v:374-386`：
   `link_active` 原来是 16 位收包计数的组合或缩（`|s_pkts`），却被像素域那三级链的第一拍直接采走。
   计数器进位的那几拍或树会出毛刺，采进去就是一次假的"链路掉"；寄存一拍 ⇒ 跨域变回触发器→触发器。
   这一条同时给出**判据类型**的老实话："判据是**结构**判据，台架判不了这一条：RTL 仿真没有门延迟"，
   凭据是 `build/r98_cdc_details.txt` 里那条 CDC-10 行，改后必须看不见 `eth_rxc>clkout0_1`。

还有一条控制位的分配纪律值得单独学：`src/rtl/top/system_top.v:249-250` 说仲裁的两个输入
"都取自已经 `u_lm_axi` 同步进 fclk0 的现成信号 ⇒ 顶层不新增跨域，也**不在这里做相与**：
判据的组合归 `src_arb` 管（那里才台架验得到，见 `tb_v796_src_arb` 的 E 段）"。
**能在顶层写的只有接线；能被证明的必须活在一个有台架的模块里。**

---

## 4 控制面：PS 写三个窗口，PL 读出九位 + 19 位 + 心跳

### 4.1 三个窗口的地址与为什么地址是硬编码的

| 窗口 | 地址 | BD 里的设备 | RTL 里的名字 |
|---|---|---|---|
| GPIO_0 | `0x41200000` | `axi_gpio`（V7 那条） | `gpio_o` |
| GPIO_2 ch1 (`CFG_DATA0`) | `0x41220000` | `axi_gpio_2` 通道 1 | `gpio_cfg1_o` |
| GPIO_2 ch2 (`CFG_DATA1`) | `0x41220000 + 0x08` | `axi_gpio_2` 通道 2 | `gpio_cfg2_o` |

定义在 `src/ps/main.c:48-50`、`:77-78`、`:96`。`:85-89` 解释了为什么地址是硬编码：
"基址 `0x41220000` 是 `build/tcl/build_system_axigpio.tcl` 里**钉死并回读校验过**的。
为什么硬编码：手工链接的 BSP 不会重新生成 `xparameters.h`，地址变了不会编译失败，
只会写了没反应"。同一段还钉了配套关系："这一条把 elf 与 bit 绑死了：**旧位流上没有这个从设备**。
开机自检会写 0 再读回来，读不回 0 就大声报位流/elf 不配套"
（自检实现在 `src/ps/main.c:1529-1564`，`Xil_Out32` 之后 `Xil_In32` 回读比对）。

### 4.2 `gpio_o`（0x41200000）逐位

位表在 `src/ps/main.c:4-19`，PL 侧的接线在 `src/rtl/top/system_top.v:264-293`。逐位与它**实际做的事**：

| 位 | 名字 | 硬件上发生什么 |
|---|---|---|
| `[4:0]` | 退役的 V7 五位 effect_en | **保留但不接**，PS 一律写 0（`system_top.v:262-264`；`main.c:5-8` 给的理由是"位还占着只因为整字是 32 位、重排位序会把按位写的工具全打乱"） |
| `[15:8]` | `threshold` | 二值化阈值，进 `u_eff` 同步链（`pl_video_top.v:207`） |
| `[16]` | `src_sel` | PS 侧片源请求，3 级同步成 `ss2`（`pl_video_top.v:471-475`） |
| `[17]` | `zoom_en` | 呼吸缩放开关，3 级同步，复位值取参数 `ZOOM_DEFAULT_ON`（`:212-224`） |
| `[18]` | `ps_publish` | **翻转一次** = 请求 PL 在下一个 `frame_start` 把 DDR 那一帧搬上屏（`pl_video_top.v:57`；`u_pub:564`） |
| `[19]` | `bilin_en` | 双线性/最近邻 A-B 对照开关（`system_top.v:281-286`，#83 才真正接上：PS 从 V6 起就在写，PL 从来没读） |
| `[20]` | `osd_off`（**反相**） | 1 = 关掉叠层；复位 = 0 ⇒ 有 OSD（`system_top.v:287`；`main.c:53-57` 解释极性："默认观感与 r82 之前逐位相同，不会因为忘了初始化变成干净画面"） |
| `[21]`、`[25]` | 保留 | 定表时留给以后（`main.c:12`） |
| `[22]` | `mode_tog` | 翻转一拍 = 下面那两位码是新写的（`system_top.v:293`） |
| `[24:23]` | `mode_ovr` | 00 自动 / 01 锁 ETH / 11 锁 SD / 10 锁 TEST；屏上那三个词就是这张表（`main.c:14-16`） |
| `[26]` | `gapclr_sel` | 测量前把帧间隔统计归零，进 `u_eth` 的 `gc*` 三级链（`system_top.v:203`；`eth_udp_video_top.v:275-281`） |
| `[31:27]` | lane 号 | 健康快照的选择器（`system_top.v:219`） |

`[22]` 与 `[24:23]` 的**先后关系**由软件保证而不由硬件保证，这件事被写进注释：
`src/ps/main.c:505` "那一刻才采码 ⇒ 码必须在沿之前就已经稳定。一次 `Xil_Out32` 同时改码和翻位，
对面读到的……"——同一段（`:497-510`）是 `mode` 命令的实现，`src/rtl/top/pl_video_top.v:290-293`
则从 PL 侧说同一件事："码与翻转的先后由 `main.c` 保证（先写码再翻位），跨域在 `src_mode` 里做"。
这是一个典型的"约定写在两侧注释里、没有机器判据"的形状——它正是
`src/host/ps_hb_check.mjs` 这类"源码之间的约定"尺子存在的理由（见第 14 章 §10）。

为什么占 22~24 而不是别的位，`src/rtl/top/system_top.v:291-292` 给了完整的分配账：
"gpio_o 的 `[4:0]`/`[15:8]`/16/17/18/19 都各有主人，`[26]` 是 gapclr，`[31:27]` 是 lane 号 ⇒
20~25 是当时唯一成片的空位（取中段三个，留 20/21/25 给以后）"。**位图是被剩下的空间决定的，
不是被语义设计的**——这一点要如实说。

### 4.3 `CFG_DATA0`（0x41220000）：九位效果字 + 19 位几何字

`src/ps/main.c:16-19` 定义了这个字，PL 侧在 `src/rtl/top/system_top.v:264-275` 拆回去：

| 位段 | 内容 | 到哪儿 |
|---|---|---|
| `[8:0]` | `stage_sel` 九位算法选择 | `u_pl.stage_sel` → `u_eff` 同步链 → `u_pipe.stage_sel` |
| `[9]`, `[12:10]` | `rot_auto`、`rot_speed[2:0]` | 拼进 `split_ctl[17:14]` |
| `[22:13]` | 缝的 10 位位置 + `auto_en`/`follow`/`swap` | 拼进 `split_ctl[12:0]` |
| `[25:23]` | 三个旗标 | 拼进 `split_ctl[15:13]` |
| `[28:26]`, `[29]` | 手动缩放档号 + 手动旗标 | `zoom_sel_async`/`zoom_manual_async` |
| `[30]` | `marker_off`（蓝线关） | 拼进 `split_ctl[16]` |
| `[31]` | `zoom_fit` | 拼进 `split_ctl[18]` |

九位算法的定义唯一出处是 `src/rtl/process/proc_pipeline.v:5-6`：
`[0]`灰度 `[1]`反色 `[2]`3×3 模糊 `[3]`3×3 锐化 `[4]`Sobel `[5]`二值化
`[6]`判决反相（仅 `[5]=1` 有意义）`[7]`腐蚀 `[8]`膨胀。
`src/ps/main.c:112-113` 明说"这里只是抄一份"——**但抄了就是两份**，这是本项目反复登记的一类债
（"两处各说一遍"，见 `src/rtl/top/pl_video_top.v:990-992` 关于 `SPLIT_PCT_FIX` 那笔的清理）。

19 位几何字的**跨域方式**是这一节的设计要点：`src/rtl/top/pl_video_top.v:51-53` 写
"19 位**一起过同一条 `snap_cross`**。位图唯一出处 = ISSUES #70 追加 与 `pl_video_top` 的端口注释"，
紧接两条 ⚠："不并进 `effect_ctrl` 那条现成的 `ASYNC_REG` 链（#71：加宽会让 `cdc.rpt` 的 unsafe
端点按位长涨），也不再开第二条 `snap_cross`（多一对 bus/toggle 同步器 = CDC-11 Critical 的签名，
#65、r54 构建 #34 各红过一次）"。

顶层的拼接写法（`src/rtl/top/system_top.v:274-275`）值得逐字看：
```
.split_ctl({gpio_cfg1_o[31], gpio_cfg1_o[12:10], gpio_cfg1_o[9],
            gpio_cfg1_o[30], gpio_cfg1_o[25:23], gpio_cfg1_o[22:13]})
```
——这不是一次切片，是**六段重排**。`[9]`/`[12:10]` 被搬到 `[17:14]`、`[30]` 搬到 `[16]`、
`[31]` 搬到 `[18]`。为什么要重排而不是让 PL 直接按物理位读：`split_ctl` 的语义索引
（`gp[14]=rot_auto`、`gp[17:15]=rot_speed`、`gp[18]=zoom_fit`，`pl_video_top.v:176-178`）
必须稳定，而物理位是**被剩下的空位决定的**（4.2 末尾那条账）。这一层重排把两件事解耦了。

`#51` 那三个参数（`SPLIT_SPEED`/`SPLIT_LO16`/`SPLIT_HI16`，`pl_video_top.v:18-20`）的注释
是"取舍"的一个小样：扫描速度与端点是"设一次就忘"的量 ⇒ **做成构建参数，不占控制位**（#70 的预算账）。
控制位是稀缺资源，因为每一位都要过同一把跨域与同一份 CDC 账。

### 4.4 `CFG_DATA1`（+0x08）：gamma 窗口，以及"为什么换算在 PS 做"

位序在 `src/ps/main.c:79-95`：`[31]` en、`[30]` **wr 是翻转位不是电平**、`[29:22]` data、
`[21:14]` idx、`[13:8]` `gamma_disp = γ×10`、`[7:0]` `temp_disp` 两位十进制 BCD。

`[7:0]` 那一段是全章最能说明"为什么一个看起来无关紧要的显示换算会影响时序"的注释
（`src/ps/main.c:85-91`，逐字要点）：

> 十进制换算是**这里**做的、不是 OSD 里：OSD 那五行字符是一整块组合逻辑，而
> `u_pipe/xd_reg → u_osd/g_reg`（27 级）正是 `clkout0_1` 那一组的 WNS 路径——
> 在屏上再加一次 `/100` 与 `/10` 就是往全设计最差的链上加深度。同一件事的先例：
> Latency 那一格从 #59 起就是"换算在 axi 域做完再跨域"。

于是这条规矩变成了架构性的：**凡是除法、BCD、查表插值这类"只为显示"的算术，
一律不做在像素域**——PS 侧算完再写进 GPIO，或 axi 域算完再过 `snap_cross`
（`src/rtl/top/pl_video_top.v:965-987` 是 latency 那一格的实现：`u_lat_x` 把 18 位
`{lat_ok, ~lat_sticky, lat_ms}` 跨过来，像素域只做 `lat_ok_pix = lat_bus_q[17] & lat_bus_q[16] & ~lat_gone`）。
`[13:8]` 与 `[7:0]` 那两位 `*_disp` 的注释都写着同一句"只给 OSD 那一格用，**PL 不参与运算**"。

同一窗口还埋了一条正确性规矩（`src/ps/main.c:93-95`）："这一组位与 gamma 协议在**同一个寄存器**里 ⇒
所有写通道 2 的地方都必须从 `gm_w` 这个影子出发**整字写回**（读-改-写会踩 #55 那个
'PS 每帧重写把别的位抹掉'的同一个坑）"。`src/ps/main.c:1558` 也照着这条做：自检收尾
"回影子值而不是回 0"。

### 4.5 观测面：lane 号写进 GPIO_0，读回走 GPIO_1

`src/rtl/top/system_top.v:206-211` 讲的是复用手法："读法：先用**已经存在**的 GPIO_0（输出）
把 lane 号写到 `gpio_o[31:27]`，再从新加的 GPIO_1（输入）读那一条 32 bit。"
选择器是一个 7 路组合 always（`:237-246`）：

| lane | 内容 |
|---|---|
| 31 | `{30'd0, hb_slow, hb_gone}`——bit0 源时钟没有，bit1 源时钟被拉慢 |
| 30 | `{16'd0, dbg_src}`，`[10:8] = why_ps` |
| 29..25 | `dbg_lat[(N-25)*32 +: 32]`（指到 25 时五个字**同时**抄进快照） |
| 24 | `dbg_lat[5*32 +: 32]` = `q_ms`，与 `q_tot` 同一轮 |
| 23 | `dbg_zoom`（像素域在用的缩放状态，20 位打包） |
| 10..9 | `32'hDEAD_BEEF` |
| 0..9 | `lm_axi[lane*32 +: 32]`（健康快照） |

两处细节是判据，不是排版：
（a）越界给 `DEAD_BEEF` 的理由写在 `:211`——"好让脚本一眼看出自己写错了号"，
而不是给 0（0 会读成"这个计数器是 0"）；
（b）`lane25..29` 必须**一次性**抄（`:232-234`）："#59：逐 lane 各读各的会读到不同轮，
于是板级 11 组读数里 4 组破坏了恒等式 `tot ≥ c1 + c2`。读的顺序必须是 25→26→27→28→29，
因为 25 既是'轮次/钳位位'也是武装位（`health_read.mjs` 的 want 列表就是这个顺序）。"
`lat_arm = (lm_lane == 5'd25)`（`:236`）就是那个武装位，一直传到 `u_pl` 的端口。

位宽曾经吞掉过高位，而且综合只给一条警告：`:224-227` 记的是 r54 起 `dbg_src` 是 16 bit，
而这里曾写过 `[5:0]` ⇒ `Synth 8-689` 把模式高位**静默丢掉**：TEST(10) 读起来像自动(00)、
SD(11) 像 ETH(01)（ISSUES #57）。这条现在由门禁第 14 项的位宽判据当场拦。
`台架变异对照` 也记了同族一次：`dbg_src` 接错宽度时"七项门禁当时全绿"。

lane30 的**动机**是这一整套观测面的设计原则，值得原文抄（`src/rtl/top/system_top.v:221-223`）：
"有了 lane30，'停流后 `owner_eth` 是否在几十毫秒内从 1 变 0'就是**可机器判定**的，不必等任何人看屏幕"。
反过来也成立：读不到的那一位就只能等人看——这正是第 14 章 §10 里那条"只能由人眼判的"清单的来源。

---

## 5 为什么是这个形状：五条组织原则

把上面散落的注释归拢，这棵树的组织方式可以归纳成五条，每条都有反例支持。

**原则 1：数据面整个在 PL，控制面整个在 PS，中间只过 GPIO 电平。**
`src/ps/main.c:3` 是这句话的官方版本："PS control plane + SD 卡本地回放。
UDP 视频数据通路仍然整个在 PL（`rtl/eth` 目录）"。
PS 不参与逐像素、不参与帧同步、不参与任何 8 ns 域的事；它只做三件事：写控制字、
读回状态、把 SD 上的帧 DMA 进第三个 bank。这条划分让 PS 侧的任何软件改动都不需要重跑 FPGA 构建，
也让 PL 侧的时序收敛不被 ARM 侧的时钟干扰。

**原则 2：仲裁只管"谁用搬运机"，不管"谁写 DDR"。**
`src/rtl/top/pl_video_top.v:14-15` 与 `src/ps/main.c:38-43` 各写了一遍同一句话。
因为 SD 的 DMA 走 PS 自己的 HP0、不经过 PL，硬件上没有任何东西可以让仲裁拦住它 ⇒
两路同时跑时**只能靠地址分开**。这条原则的诚实之处是它承认了一个管不到的边界，
而不是在 RTL 里假造一个全局所有权。

**原则 3：能被证明的逻辑必须住在一个有台架的模块里。**
最清楚的例子是 `src_mode` 的搬出（`src/rtl/top/pl_video_top.v:153-156`）：
"模式寄存器搬到了 `src/rtl/util/src_mode.v`，理由是这段逻辑有没有台架：写在这里时顶层没有
台架碰得到它，于是同步链的复位值与源头不一致（`tog` 复位 0、链复位 3'b111）一直没人查 ⇒
上电白送一次长按、模式自走到锁 ETH、`force_eth` 长占 ⇒ #28 板级交接判据红的根（见 ISSUES #49）"。
同一条原则的否定形式在 `src/rtl/top/system_top.v:249-250`（顶层不许自己做相与）
与 `src/rtl/top/pl_video_top.v:990-992`（OSD 里那个死数 `SPLIT_PCT_FIX` 连同推导注释一起删掉，
"留着就是两处各说一遍"）。

**原则 4：延迟/级数只有一个出处，而且由模块自己声明。**
`src/rtl/top/pl_video_top.v:816`：`localparam PROC_LAT = u_pipe.LATENCY;`——
"处理链的延迟只有一处定义：`proc_pipeline` 自己的 `LATENCY`"。
`src/rtl/process/proc_pipeline.v:22-27` 把这条参数钉成**不许外部覆盖**，并给出逐拍账
（灰度1+反色1+模糊3+锐化3+Sobel3+阈值1+形态学3=15），
还警告"窗口级是**三拍**不是两拍"与"gamma 是分布式 RAM 组合读出 ⇒ **不占拍**；
谁改成寄存读出（BRAM 风格）LATENCY 必须同时改成 16"。
行环的 `LINES` 同样只从链子取（`src/rtl/top/pl_video_top.v:781`：
"`LINES` 的唯一合法出处是 `u_pipe.OFF_LINES`（链子改了这条跟着改）"）。
顶层与台架各写一遍字面量是这个项目最常见的一类根因，这四行参数化就是它的解药。

**原则 5：快域只在不得不用它的地方存在。**
显示通路整体跑在 50 MHz（`clk_pix`），TMDS 的 5 倍频只在 `u_dvi` 里用于串行化
（`src/rtl/top/pl_video_top.v:1026-1031`），DDR 读侧靠"每源像素天然 4 拍"而不是提频
（`src/rtl/process/bilin/fb_bilin.v:4`），写侧靠**流水化**而不是加深缓冲
（`src/rtl/eth/axi_frame_saver64.v:5-7`）。唯一被迫跑在 8 ns 的是网线那一侧，
而它正是当前余量最薄的一族（`build/r118_gates_final.txt:19-26`：
`eth_rxc` setup 0.739 ns 是全设计 WNS，而 `sys_clk` 有 14.876 ns、`clkout0_1` 有 3.630 ns）。

### 5.1 一路片源的仲裁与"三个片源在两层各选一次"

三路片源（ETH / SD-PS / 图卡）不是在一个 mux 上合并的，而是**两层**：
`src/rtl/top/pl_video_top.v:595` 那一行 `wire fb_vis = (mode_card ? 1'b0 : (mode_eth | mode_ps) ? 1'b1 : src_use) && have_src;`
是第二层（帧缓存 vs 图卡）；第一层（谁用搬运机）在 `u_arb`（`:421-427`，`src_arb`，
`T_OFF_CYC(2_000_000)` = AXI 域 100 MHz ⇒ 20 ms 静默才让给 PS）。
`架构章` 也把这条写成官方口径，并且指出图卡那路**根本不进内存**。

`u_arb` 的两个输入是第 3.4 节那两位现成同步值（`src/rtl/top/system_top.v:255-256`）。
为什么要 `eth_tb_ok` 这一位，`system_top.v:252-254` 给了板级实测的理由：
"板级实测：断链时 RTL8211 不停 RXC 而是拉到 ~2.5 MHz ⇒ `stall_ms` 慢约 48 倍地爬，
单看那一位会永远判活着 ⇒ 仲裁死死占住 ETH、SD 再也接不回画面（屏上 `STALL=9999` 是
OSD 钉住的显示值，不是 9999 ms）。`hb_slow` 专门看这种心跳还在但变慢。"
这条硬件事实（拔线时 PHY 不停钟而是把钟拉慢）是整个跨域设计里最反直觉的一条，
`sim/tb_link_monitor.v` 的 `snap_cross` 心跳段（1.5 µs / 8 ms / 停钟 62.5 ms 三种间隔，
`:15` 与 `:26`）就是为了把它做成可判红的数。

---

## 6 取舍账（上）：量过并采纳的

来源是 `build/runs/decisions.md` §1.1 那张"采用"表（`:23-45`），这里只挑能说明架构选择的几笔。
所有数字都抄自那张表点名的件。

| 采纳什么 | 判它的尺子 | 代价（量到的） |
|---|---|---|
| **r92**：`rgmii_rx.v` 删 BUFIO、5 个 IDDR 改吃 BUFG；`IDELAY_VALUE` 15→26 | 结构判据 `BUFIO` 用量 1→0 + `build/hold_paths.rpt` 偏斜 **1.616→0.013~0.349 ns** | 采样沿往后推 1.683 ns ⇒ 数据侧补 +11 拍（`system_top.v:160-162`）；板侧 `drop_words=0`、100 条电池全过 |
| **r107**：`frame_reasm.v` 行覆盖位图拆 5 个 64 bit bank（砍 `fo=316` 的使能广播） | 同端点对夹逼 **0.723 → 2.006 ns**、级数 5→4 | 逐拍等价 + 错组变异（`build/evidence/r107_rowok_bank_equiv.txt`，**动手之前**量的） |
| **r109**：`osd_overlay.v` 选中格提前一拍寄存 | `clkout0_1` 同族 **1.130/23 级 → 4.094/21 级**（相对余量 5.65 % → 20.5 %） | C12a/b/c 三条，其中 **C12c 是阳性对照**（旧拍点必须不相等）⇒ 不用额外构建就拿到"改前红" |
| **r112**：`key_debounce.v` 上电武装门 + `icmp_tx.v` 校验和累加器 32→20 位 | 两刀各自凭据；发出字节流 `cmp` 全等（台账点名的件名 `build/evidence/r112_tx_bytes_{base,cut}.txt`，**现盘上无此件**） | 资源账**闭合到个位**：`+66−31=+35`、`+46−12=+34`（`build/evidence/r112_util_attrib.txt`） |
| **r114**：`dc_fifo.v` 四颗格雷码寄存器 `ASYNC_REG="TRUE"` | **网表侧**凭据：`marked_true` 0→**56 颗** | 名册 16 对六条全绿；**不拿 methodology 计数当凭据**（#290 已证明那是错的读法） |
| **r116→r118**：`IDELAY_VALUE` 26→**31**（实测眼心） | **预测逐格命中**：DCP 上扫出的 `HOLD(τ)=−2.822+0.0630τ` 在真构建里对到小数第三位（预测 −0.870 / 实测 −0.870） | V5 资源逐格中性 + 告警按类不增；片内 slack 一条没变好（τ 只动 I/O 单元抽头），所以判据是"不劣化"而不是"WNS 变好" |

r116 那一笔的定位说明值得单独读（`那一轮的逐轮页`）：
"这一版的定位要说准：它是一版把收口到达窗推到实测眼心、且名册对 r114 逐格不劣化的构建，
它的收益不体现在片内 slack 上……**把 τ=31 写成 WNS 收益就是规矩 35 禁的那种读法**"。
这是这套账里"采纳一个改动但拒绝把它记成收益"的范例。

采纳的**批准口径**也在这本账里，而且它承认自己的限制：`build/runs/decisions.md:7-19` 定义了三种取值
（`队伍在场批准` / `规则预登记 + agent 执行` / `【队伍未确认】`），
并明写第二种"**不是人的批准**：判据在起飞之前写死在链脚本/台账头部，agent 只按判据执行；
凡采用都还要过 `build/gates.sh` 的发布门"。同一段第 19-20 行给了一条全局事实：
`loosen_ledger.tsv`（放宽台账）**全程 0 条**（四处独立复核），
含义是"没有任何一次改小约束换绿灯发生过；r116 那次想过'去掉与窗双重计的 0.800 hold 带'，
量过之后**没做**（既然换不来绿，就不去碰 H1）"。

---

## 7 取舍账（中）：量过并否决的

这本账的价值不在于"试过了没成"，而在于**每一条都留下了可指路的件，而且没有被重新记成收益**。
编号沿用 `build/runs/decisions.md` §1.2（`:46-71`）。

### 7.1 复制驱动（V9 / V12 / V19，三把刀同一个形状）

同一个候选被量了**三次**，三次都是机制成立、代价落在最紧的域：

| 轮次 | 目标 | 机制 | 收益 | 代价 | 判定 |
|---|---|---|---|---|---|
| r114 (#288) | 39 根高扇出网（`eth_rxc` 侧） | `REPLICA_CELLS` 0→296、`u_pl/u_clk/u_mmcm_0` 扇出降 58 | 目标族 0.445→**0.901** | `eth_rxc` hold **0.050→0.035**（相对余量 −29.0 %） | `verdict=DECLINE`（`build/evidence/r114_mf/verdict.txt`） |
| r115 (C1) | 39 根 >200 扇出的网 | `REPLICA_CELLS` 0→**310**（不是 `MECHANISM_INERT`） | — | 32 次比较里 **4 格红**且变差的正好是最紧的 `eth_rxc`；FF `8188→8463`（+275） | C1 拒绝，不进任何正式构建 |
| r117 (C9) | 单根 `u_pl/u_row/hi_reg_0[0]`（239 引脚） | `pins_before=239 → pins_after=1`、`replica_cells=10`，**两处独立出水口都读到** | `clk_fpga_0` 1.850→**2.104** | `clkout0_1` 3.630→3.353、`eth_rxc` 0.739→0.615、`eth_rxc` hold 0.052→0.044、`sys_clk` 14.876→14.815 **四格一起跌** | 按 H7 回滚（`build/r117_verdict_declined.txt`，位流 `beda9298331d`） |

三次的**结论口径**被分别写下来，这是这本账最该学的地方：
r114 那条写"降扇出那根网正是'驱动类型是 LUT 但名字像钟'的三根之一 ⇒ 若重开这一刀，
**得先把这三根从目标名单里剔出去再量一次**，否则连收益来自哪里都说不清"；
r115 那条写"**不是'复制没用'，而是在 `eth_rxc` 没有可信 hold 余量之前，复制的代价由它付** ⇒
顺序换成 C3 在前"；r117 那条写"**结论不是这刀没生效**：生效了，代价落在最紧的两个域上"。

`门禁逐条页` 有对应的记账规矩（G11）："不把已判负的刀再记一次收益"——
复制驱动 #288、MMCM 相移（r115 §7.3）、Pblock（r113 + r116 的 `PB_EXISTING_BOX=` 空自拒）
"都没有被重新记成收益"。

### 7.2 Pblock（V0、V10、以及一次方向被推翻）

两次尝试，两种失败：

- **r89（V0）**：圈 `u_cdc` 回它自己那 9 块 BRAM 旁边。三条否：
  ① 它瞄准的那一族本来就不在最差名单里 ⇒ **没有可归属的收益对象**；
  ② 唯一可见的变化 `eth_rxc` +0.516→+0.363 落在实测摆幅内 ⇒ "没有任何可主张的改变"；
  ③ 代价真实存在：把芯片一角写死，而新的最差路径贴着被圈的区 ⇒
  **"买了风险，没买到东西"**。XDC 与构建脚本挂载全部回退，
  台账写"两份报告留在盘上作反例凭据"（件名 `build/r89_exp/`），本次核对**该目录已不在盘上**（第 7.7 节统一登记）。
- **r113（V10）**：圈 `u_rx_par`+`u_reasm`。`REFUSE`：`Place 30-439` 说**进位链半内半外**，
  落点地板实测 `PB_CONTAIN total=1716 inside=1461`；矩形 v1 写法（`CLBLM_*`）还被工具直接拒
  （`[Vivado 12-28489] pblock resize has invalid range`，7 系要 `SLICE_*`）。
  这条特意写清"**这不等于物理这条路判死**：要修得把共享 carry chain 的 `u_eth/u_rx_mac`
  一起收进去再滚一次"。
- **还有一次是方向被推翻而不是失败**：`极限核对` 记
  同一页早先版本把"只圈 `u_fb` 的 pblock"排进了日程，之后 D0 那一次**只读量**
  （`build/evidence/r117_d0/`）把根因从"离得远"改正成 `FANOUT`（一根 239 引脚网吃 5.690 ns），
  于是台账里那一支 pblock 快车道脚本**自拒**（`PB_EXISTING_BOX=` 空）且方向已被推翻（脚本名 `build/r117_fb_pblock_fastlane.sh` 现盘上无）。

同一段还留了一条硬账（`极限核对`）：r113 那次"不是单变量"，
所以在"G11 声称到极限"那一栏里它只能算"一条没做成"，不能与复制驱动并列成独立负结果
（`门禁逐条页`）。

### 7.3 BRAM 换 setup（V1）：一笔被算反的账

`build/runs/decisions.md:52` 那行是整本账里最简洁的一条判断：

> **BRAM 换 setup**：`frame_buffer_w64.v` 拆三块（省 5 片 RAMB36）。
> 省的是 140 片里 5 片、BRAM 哪版都没饱和（67.86 %/64.64 %）；
> 付的是**最快那个域** setup 余量 6.5 %→2.3 %，而它同时是全设计 hold 最薄所在 ⇒
> **"在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的"**

台账记"三滚产物全在盘"（件名 `build/isolated_0929_2036/`、`_2105/`、`build/isolated_lenm1/`）；**这三处目录现均不在盘上**（第 7.7 节）；
副产物是两条可复用的结论：**拿 FF 买级数划算、拿 BRAM 削 setup 不划算**，
回退用 md5 等式钉住（三处同为 `41384499f3a9`）。
这条结论后来变成了 `极限核对` 那条"不许再来一次"的依据：
结构侧（`u_fb` 是不是该从 LUTRAM 换成 BRAM）"已被 #140 挡过一次（打包 FIFO 512/512 满、BRAM 承重），
且 r90 量过 BRAM 换 setup 收益不成立 ⇒ **不许再来一次**"。

对照 7.1 的"拿复制买扇出"与第 6 节 r109/r112 的"拿 FF 买级数"——三种货币，两种划算、一种不划算，
而判断依据始终是**同一把尺子**：逐时钟名册差分，别域不许变差。

### 7.4 校验和的三条算术改法：全部实测关闭

这条线索在 `eth_rxc` 族上追了三刀，前两刀判负、第三刀等价过了台架但名册判负。

| 刀 | 做法 | 等价凭据 | 时序判定 |
|---|---|---|---|
| r108 | 一拍 10 项 → 两拍各 5 项 | 差分台架三场景逐字节全同 + 少加一项的变异**只红在校验和两格**（台账点名的件名 `build/evidence/r108_csum_diff.txt`，现盘上无此件） | 同端点对 0.725→**1.081 ns** ⇒ **采纳**（`build/runs/decisions.md` r108 行） |
| #380 | 摊到每拍一项 | `tb_icmp_tx_cksum` 四场景整帧字节流逐字节 diff=0 | 把那族 11 级 / 6 个 CARRY4 的锥**从最差名里拿掉了**，但名册没变好 ⇒ 判负、已回退 |
| #382/#383 | 6 个编译期常量抽成 `localparam IP_CSUM_K`（变量项 10→4） | 改前/改后各跑一次 `tb_icmp_tx_cksum`，72/110/72/72 字节与四枚 `SUM32` **diff=0** | 三条**收益行**（`clkout0_1` 3.630→3.723、`sys_clk` 14.876→15.175、`eth_rxc` hold 0.052→0.053）都有，但 `D3_margin_cost` `big_loss=1` ⇒ `result=RED` ⇒ 回退 |

第三刀的机制解释是这本账里质量最高的一段
（`开发台账` #383 段）：**"为什么少了 6 个变量项反而更差"**——
`IP_CSUM_K` 把 6 个常数并进同一拍，第一拍的加法树**变深**（常量并入 = 更深的一层门）而不是变浅；
端点数只 4835→4819（−16），网表规模几乎没瘦，放置/布线却换到另一副分布上。
"这与 §7.3 那次'摊拍之后本族反而更差'同向，两条合起来把结论钉死：**`eth_rxc` 这一族的路径长度
不是由加法树的项数决定的**，项数方向的三条算术改法（摊两拍各 5 项、摊到每拍一项、常量折叠）
全部实测关闭。"

三条纪律同时体现在这里：回退用 `git checkout -- src/rtl/eth/icmp_tx.v`，
还原后 md5 `ef463e6a2e1aec57e6cc6372a719c572` 与 `git show HEAD:...` 同一枚；
**台架留着**（它是校验和与整帧内容的回归闸，与被否掉的刀无关）；
文档里的 WNS 数字一字不改（`时序章`、`data/metrics.csv`、首页三处仍是 r118 读数）。

### 7.5 r116 的 RGMII 输入窗：约束是对的，但不进发布物

这一笔最容易被念错，所以把三件事分开说：

1. **约束本身是对的，而且有出处。** `src/constraints/r116_rgmii_input_window.xdc` 的
   min 1.200 / max 2.800 取自 RTL8211F-CG 规格书 `Table 60` 的**发射端**两行 + 原理图 R57/R59 上拉
   ⇒ RXDLY 开着、2 ns 加在 RXC 上（`时序债务账` §2 追加表 `r116 的变化`，`:120`，
   抄件在台账里点名 `build/evidence/r115_rtl8211f_delay_source.txt`，**现盘上无此件**）。
   在此之前还有一个更基本的更正：旧候选件 `r114_io_async.xdc:39-43` 的 ±0.500 **取错了行**
   ——那对应的是 `TskewT`（发射端*没有*内部延迟时的输出偏差），不是收口该用的窗
   （`时序债务账`）。
2. **绑上它之后，仓库自己的发布门禁有 4 项机械判红。**
   `build/tcl/build_system_axigpio.tcl:44-48`：WNS ≥ 0、失败 setup 端点 == 0、WHS ≥ 0、
   失败 hold 端点 == 0 全被那 5 个**第一次被检查的端点**打红（实测
   WNS −0.846 / 失败 setup 5 / WHS −0.870 / 失败 hold 5，`build/r116_gates.txt`）；
   而门禁末尾那句写死的是"有红项 ⇒ 不采纳，保留上一版"。
   同一段的话要说全：**"这个设计只有在'RGMII 输入不被检查'的前提下才过发布门禁。这不是话术，是两件事实。"**
3. **这一族在合法 0…31 全档内关不掉。** 不等式来自 `收口输入窗模型` §7.5(4)：
   hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，而合法档位只有 0…31；
   根因是两只钟的角间差 3.411 ns 对数据 0.467 ns
   （`build/tcl/build_system_axigpio.tcl:49-52`、`极限核对`）。

于是处置是 `build/tcl/build_system_axigpio.tcl:53-55` 那三行：默认**不加载**（回到 r114 的约束集），
把它留在仓里当**候选件 + 全份证明**；复现只要 `VP_R116_IO_WINDOW=1` 再构建一次；
"撤销的不是约束的正确性，是把它带进发布物这个动作；下一刀（把 IDDR 捕获钟换成短钟）落地之后，
这个窗应当重新加载"。

**代价一起念**（`build/runs/decisions.md:67` 的 V18 那格）：撤窗之后那 5 个端点回到"没检查"状态——
`check_timing` 的 `no_input_delay` 从 0 **回到 5**，这是撤窗的诚实读数，不藏；
同时"相对 r114 这不是放宽"（r114 从来没有这条约束，松动台账仍 0 条）。

还有一笔未闭合的诚实：窗模型自己还有残余风险。`时序债务账` 承认
`TskewR` 那行讲的是 PCB **时钟走线**（要多走 1.5-2.0 ns），却被当数据散布用了，
"可能是第二次混行（第一次是 `TskewT` 的 ±0.5，见 ISSUES #304），所以 −1.385 / −0.186
只代表该窗模型下的读数，**不代表板上真实差额**"。这一条至今没关。

### 7.6 其余四把被量过并否决的刀

| 编号 | 被否的东西 | 依据（能指到件的那一句） |
|---|---|---|
| V2 | 实现策略 `Performance_Explore` / `Performance_ExtraTimingOpt` | hold 三档 0.046/0.051/0.051 **一位没买到**；setup 第二档从 +0.516 花到 +0.157 ⇒ "换策略对 `+0.05x` 的 hold 必然无效，**placer 无权改布线树拓扑**"（这一轮的负结果把 r92 的方向定死了） |
| V3 | 布线后 `phys_opt_design -directive AggressiveExplore` | **工具自己那三行**就是结论：`WNS ≥ 0 ⇒ All physical synthesis setup optimizations will be skipped`、`Hold fix optimization will be skipped`、`No setup violation found. The netlist was not modified` ⇒ 这一档永远不会给已过时的本版带来收益 |
| V4 | 策略 `Performance_ExploreWithHierarchy` | 这一档不在这颗器件的流里（`list_property_value strategy` 没有它）⇒ 判 **`NOT_MEASURED`，不写成"否决"**（把"读不到报告"写成 DECLINE 就是让"没数"长得像"结论"） |
| V14 | MMCM 负相移提前捕获沿（`CLKOUT0_PHASE = −225°`） | 终态 `WNS 0.954 / WHS −2.126` ⇒ **窗没关住，只买到 +0.759 ns**；更要紧的半条：那 0.759 里约 **0.67 ns 是"约束作用范围被削弱"换来的**（终点已是派生钟，那条路的 `Clock Uncertainty` 从 0.835 变成 0.166，UU 项消失了）——**没写任何放松约束的命令，它自己发生了** |
| V16 | tap 扫描想"少给几拍延迟" | 0/13/26/31 四档 WHS = −4.522/−3.703/−2.885/−2.570（斜率 ≈ 63 ps/tap）⇒ 到最大档仍差 −2.57 ⇒ **超量程** |
| V7 | `set_max_delay -datapath_only` 四条跨域界 | `report_exceptions` 表体 A 滚 13 行 / B 滚 13 行，`-datapath_only` 这个词出现 **0 次** ⇒ 写在 `set_clock_groups -asynchronous` 之上**不落表**，四条界一条都没生效。**不是"已补上界"**：正解是口径决策，会动 WNS 的算法范围 ⇒ 必须单独一轮带尺子做（**到 r119 仍未决**） |
| V21 | HDMI 源端 `set_output_delay` 互对窗（±0.20 Tcharacter = 4.000 ns） | 给出 −3.482/−3.458/−3.474 ns（与 −4.897/−4.873/−4.890），因为**规范那一行是 skew（两脚到达时刻之差的上限，单边离散量），`set_output_delay` 是采样窗 ⇒ 两者不同量纲** ⇒ 这条是"量纲用错"，不是"设计不合格"；**不许靠放宽窗把它变绿** |
| V22 | 拿 `report_methodology` 的 TIMING-10 计数当 `ASYNC_REG` 落地凭据 | 属性上了网表（0→56 颗）**但 TIMING-10 计数一点没动**（仍 = 1）⇒ 预先登记的这条判据**被数据判错**；durable 的尺子换成 `report_cdc -details` 点名到具体那对触发器 |
| V23 | "同一条路在两次构建之间摆 0.4 ns"当同树噪声底用 | 那句把**跨变体**的散布当成**同树重复滚**的噪声底用了；同树重复滚的底今天量到是 **0.000** ⇒ 数不动、**用法错** |

V3 那一格是这套账里最省钱的一条：**先用工具自己打出的三行话判定一个候选结构性空转，
再决定要不要花一整轮构建**。V4 与 V22、V23 三条则是同一类元规则：
"没读到数"、"用错尺子"、"用错噪声底"都必须被登记成**独立形状**，
不许混进"设计结论"里，也不许被顺手改成绿。

---

### 7.7 一件必须如实说的事：台账点名的部分件已不在盘上

上面这几节的**判定与读数**都抄自 `build/runs/decisions.md`、`开发流水账` 与 `开发台账`，
但本套在写这些行之前把它们点名的件路径逐个 `-e` 测过一遍，结果是：**有六处件名在当前工作树里已经不存在**——
`build/r89_exp/`、`build/isolated_0929_2036/`、`build/isolated_0929_2105/`、`build/isolated_lenm1/`、
`build/evidence/r112_tx_bytes_{base,cut}.txt`、`build/evidence/r108_csum_diff.txt`、
`build/evidence/r115_rtl8211f_delay_source.txt`，
外加两支脚本 `build/r117_fb_pblock_fastlane.sh` 与 `build/tcl/repl117_roll3.tcl`。
它们仍在台账正文里被当作"当时留下的凭据"点名。

这与仓库自己已知的一个洞是同一形状：`域划分候选评估` 写
"那份名册现在不在盘上（它当年没入库，属长期已知的那个洞），所以这个数字**当前无法复量、只能算待核，
不许当依据**"。本章按同一条口径处理：**判定可以引用（它是一次真测量的记录），件路径不可以引用**——
所以在上面每一处都写明了"现盘上无此件"，而不是删掉点名（删掉就把"当初确实量过"这条也一起删了）。

仍然在盘上、可以直接复核的：`build/evidence/r114_mf/verdict.txt`、`build/evidence/r117_d0/`、
`build/evidence/r115_c2_scratch/option_a_main_console.txt`、`build/evidence/r115_window/probe3_console.txt`、
`build/evidence/r107_rowok_bank_equiv.txt`、`build/evidence/r112_util_attrib.txt`、
`build/r117_verdict_declined.txt`、`build/r116_gates.txt`、`build/r98_cdc_details.txt`、
`build/hold_paths.rpt`、`build/clock_util.rpt`、`build/tcl/r117_post_place_hook.tcl`。

---

## 8 取舍账（下）：仍然欠着的三件

### 8.1 角度机读口（ISSUES #185，观测性账）

欠的不是功能而是**证据**：`board/README.md` 的 `[STAT]` 回读里没有角度字段
（`未决项集中表`），`src/ps/main.c:1032` 现在写着"角度本身仍然只活在 PL 的
`angle_ctrl` 里（按键 ±1° 那条路一个字没动），这里发出去的是要不要自动转 / 每帧几个度两个控制位"。
于是验收表 E6 那一格**只能人眼签收**——r118 那一格确实就是这么签的
（`build/runs/decisions.md:44`：E6 由队员眼睛签，原话「0度」）。

方案已经写好并且在盘上：`build/r113_angle_lane_plan.md`——走 lane23 的保留位 `[28:20]`、
不新增跨域，代价约"一处 RTL + 一轮构建 + lane 表同步"。
在落之前，`未决项集中表` 那句约束成立：**"这类判据不许由机器代做。"**

`src/ps/main.c:1035-1036` 还记了与之相关的一笔设计取舍：**有意没有** `rot 37` 这种
"设成某个绝对角度"的语法——"那需要一个 9 位写窗口 + 一次跨域同步（新硬件、新时序账），
而 ±1° 的按键已经能把角度带到 0..359 的任何一格"。所以"读不到角度"和"设不了角度"
是同一笔账的两面：那 9 位窗口一旦开出来，第 8.1 节这条观测性债就顺手还掉了。

### 8.2 I/O 约束债：11 个未声明端口里，输入侧还了一半，输出侧没有来源

`时序债务账` §2 的原始清单：没有 input delay 的 5 个输入
（`eth_rx_ctl`、`eth_rxd[0..3]`）+ 没有 output delay 的 6 个输出
（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）= 11 个。

- 输入那 5 个在 r116 进过一次构建、又按 7.5 退出来了；今天它们回到"没检查"状态。
- 输出那 6 个**仍然零声明**，而且理由不是懒：
  "要接收端（面板/HDMI 接收器）或 DVI/HDMI 规范的窗口数；本机板级资料没有，
  两次在线取原文没拿到可引用的一页 ⇒ **没有来源就不写数**"
  （`时序债务账` §2 追加表 `:121`）。
  这句"本机没有"后来被**升级成查过的否定**：把 7-series SelectIO 官方手册（`ug471`，188 页）
  整本按页抽文本扫过，TMDS 那一节只给 **I/O 标准与属性**（`Table 1-52`、50 Ω 上拉到 3.3 V、
  `TMDS_33` 只在 HR bank、VCCO 3.3 V），**没有任何接收端 setup/hold 窗口或 UI 数**；
  DVI Test & Measurement Guide 那 26 页讲的是**怎么测**（第 5 页 "the eye pattern masks of the
  DVI specification are essential"），也没有印出接收端的那串 UI 数
  （`时序债务账`）。

同一段还留了一条没资格下结论的诚实：差分对的 N 腿（`tmds_*_n`）不在 `check_timing` 名单里，
"但"这一条没有官方出处"（A1 未读），所以只报'check_timing 没点它们的名'这个事实，
不写'所以无需约束'的结论"。

`时序债务账` 给了这笔债的**量级**（不是猜的）：同一份
`system_top_opt.dcp` 上绑 ±0.500 窗重跑 place+route ⇒ 终态 WNS 0.437 / WHS −2.885 /
THS −14.344；变体 A（只声明上升沿）读数**逐位相同** ⇒ 沿的条数不是原因。
结论那句是全仓最该被复述的一次自检："现行名册里 `eth_rxc` 的 WHS 0.052 是
'假设数据恰好在时钟沿到达'量出来的**片内**数，它**不包含** PHY→FPGA 走线与 PHY 内部延迟那一段"。

`build/check_io_timing_coverage.py` 现在判 **10** 条、**9 绿 1 红**（读数件 `build/evidence/1006_d3/`）：
唯一红是 `I3_output_covered bare_out_ports=4`（就是屏那一路的四个输出端口名），
它由"TMDS 窗量过并判 DECLINE"这条决定（见 7.5 与第 13 章 5.6），不是没做。
`led`/`eth_mdc`/`eth_mdio` 三组走带出处的豁免（`rk_zynq7020.xdc:10-11`、`system_top.v:117`、`system_top.v:116`），
`I3` 因此从 7 降到 4。
名字级两条 `I7_verbose_selfreconcile` 与 `I10_names_vs_source` 实测**绿**：
把归档的 `-verbose` 件逐行数过之后，`checking no_input_delay (7)` = HIGH 5 行 + MEDIUM 2 行、
`checking no_output_delay (12)` = HIGH 6 行 + MEDIUM 6 行 ⇒ 小标题与明细是**同一个单位、不同射程**。
**先前那一版这一处写的是"报告自己两个单位不同"，那是读错了**（也连带解释了为什么曾经把 `12−6=6`
当成量纲差——真把差值钉成常量才是错，见第 13 章 7.3）。

### 8.3 `eth_rxc` 域划分那四候选的判定

`域划分候选评估` 回答的问题很窄："要让 `eth_rxc` 的余量变宽，值得动哪里"。
四条候选逐条给"前提 → 证据 → 判断 → 代价"，而且这份文档自己声明
"**不改 RTL、不跑构建，所以每一条的收益都只写成待量的数，不写成结论**"（`:5-7`）。

| 候选 | 判断 | 关键依据 |
|---|---|---|
| **A**：把 512×100 bit LUTRAM 打包器移出 `eth_rxc` | **前提为假，这条作废** | `eth_udp_video_top.v:355` 写的是 `.clk(axi_clk)`——打包器本来就在 `clk_fpga_0` 那一侧（`:24-30`）。同一位置剩下的真候选是打包器**写指针扇出**，但当年记的 `wptr_reg[5]` 吃 1165 个负载那份名册**现在不在盘上**（当年没入库）⇒ 那个数字**当前无法复量、只能算待核，不许当依据**（`:31-35`） |
| **B**：发侧协议栈从 RXC 域解耦（`verilog-ethernet` 那条的廉价版） | **值得做，但要一整轮** | 他工程里 MAC 之上没有任何逻辑去吃 RXC 的预算（`eth_mac_1g_rgmii_fifo.v` 三个时钟口，包流在 `logic_clk` 消费，中间两只 `axis_async_fifo_adapter`）；本工程 `gmii_tx_clk` 与 `gmii_rx_clk` 是同一根 ⇒ 发侧 arp/icmp/udp 全压在收侧恢复钟上，**最差那条恰好就是发侧校验和**（`:38-42`）。廉价版不动协议、只动时钟归属（`rgmii_tx_clk` 本来就是 PL 输出端口，可以由 MMCM 另生一颗 125 MHz）。预期收益：**未量** |
| **C**：#194 把 RGMII 收侧的捕获钟提前（BUFIO 或 MMCM 相移） | **先量才能判** | #57 那一轮已经把 IDDR 的捕获钟从 BUFIO 改成共享 BUFG（`BUFIO` 1→0，skew 1.616→0.013–0.349 ns）；所以问题不是"要不要提前"，而是"**提前之后眼心还在不在 τ=31**"。这条要求一次真构建 + 真输入窗扫描，且 BUFIO 的快角 DCD 本机还没实测（#323 欠着）。**判据要连着 hold 与输入窗一起看，单独看 WNS 会误判** |
| **D**：#259 补对外 I/O 约束 | **它不买余量，但不补就是失实**；四子里唯一一条**该尽早做**的 | TMDS/LED/MDIO 今天没有任何输入/输出窗声明，而唯一红着的门禁项就来自这里。源端窗口已经按 HDMI 规范 §4.2.4（TP1）取证过：管脚间实测 0.065/0.001 ns 对 4.000/0.300 ns 的界（`build/r119_window_check.mjs`）；而把 `skew ≤ 0.20 Tcharacter` 当成捕获窗去绑，实测会把设计判成 −3.48/−4.90 ns ⇒ **那是量纲错，不是 DUT 差**（`:71-78`） |

建议顺序（`:81-84`）：**D → B → C**，A 作废。理由不是收益大小而是
"D 把一条长期未声明变成有界"、"B 真正打域过载这一条"、"C 与 B 抢同一批资源与预算，放 B 之后再单变量量"。

四条共同遵守的纪律写在最后一段（`:86-87`）：
"每一条例子都遵守同一条纪律：**逐时钟名册差分**（`build/timing_roster_diff.sh`，
八对 (时钟,类型) 要全配上），本族没变好而别域变差就是**代价**，不是'没找到收益'。"

### 8.4 域归属这条账，本仓错过两次

`域划分候选评估` 记的不是候选 A 作废就完了，而是它连带改了两处文档：
"本文件第 2 节连带把 `docs/course/04` §7.4 与 `docs/course/10` 的 `eth_rxc` 行改正
（**那两处原先把打包器算进这个域**）"。这就是第 14 章 §9.2 那条 D1/D2 判据在架构层面的实际效果：
把域归属写错不会让位流编不出来，只会让下一轮的人沿着错的地图找资源。

同一条"错地图"的更坏版本记在候选 A 那段（`:31-35`）：一个**再也没法复量**的数字
（1165 个负载）曾经被当作决策依据写进文档，因为那份名册"当年没入库，属长期已知的那个洞"。
文档给的处置是"不许当依据；复现它的办法是把同一支只读探针重跑一遍
（`build/tcl/probe_timing_roster.tcl` 那一族）"，而且即便复量成立，接下来那把刀
（配复制驱动）**已经在别的广播上被量过并否决过一次（#117：`eth_rxc` hold 0.050→0.035 被判红 ⇒ DECLINE），
所以它属于要单独一轮、带名册差分的活，不是顺手改**。

---

## 9 资源与频率账：这一版落在哪儿

全部来自 `build/r118_gates_final.txt`（同一套产物，`system.bit` md5 `cd04907e1369`）：

| 项 | 读数 | 门禁阈值 | 余量 |
|---|---|---|---|
| BRAM | 95.5 tile / **68.21 %** | ≤ 97 % | 还有 44.5 tile；但 7.3 那条已判"不缺资源" |
| Slice LUT | 14154 / **26.61 %** | ≤ 98 % | 极松；逻辑侧的债不在数量 |
| Slice 寄存器 | 8188 | 记录用 | r115 那把复制刀的代价就是 +275 颗（`8188→8463`） |
| WNS | 0.739 ns（= `eth_rxc` 组） | ≥ 0 | 相对余量 9.24 %（`域划分候选评估`），四域最紧 |
| WHS | 0.052 ns（= `eth_rxc` 组） | ≥ 0 | 同上，且它是唯一被绑过输入窗就会翻负的一族 |
| Dynamic | 2.213 W | 与前次同量级 | 无阈值（第 14 章 §11 第 3 条） |
| 端点总数 | 51135 | — | `build/r118_gates_final.txt:38` |

**四个域互相不能替换读数**（`时序债务账` 的名册 +
`build/r118_gates_final.txt:22-26` 的分组最差）：
`sys_clk` 14.876 ns（74 % 相对余量，本轮没有欠刀）、`clkout0_1` 3.630 ns
（主导项是 22 级逻辑含 9 级 CARRY4，即 OSD 的地址/字符算术锥——**功能面授权之外**）、
`clk_fpga_0` 1.850 ns（根因被 D0 那次只读量改成 `FANOUT`，明知未到极限但没预算动）、
`eth_rxc` 0.739 ns（I/O 那 5 格已被证成结构极限）。

`极限核对` 的那句全局总结是把这四域放在同一张账上的最好示范：
"**四个域里：两个本轮没有欠刀；`eth_rxc` 的 I/O 那 5 格被证明是结构极限；
`clk_fpga_0` 是唯一一个明知未到极限、但今晚没有预算动的域**……
这一条不是遗漏，是排期"。

时序余量换资源、资源换时序，在这本账里是**双向都做过的交易**，
而且两次都要求"别域一格都不许变差"：r109 用 27 级 → 21 级买回 5.65 %→20.5 % 相对余量（买级数 = 花 FF），
r104 那笔 `#141` 提前寄存买回锥深但代价是 **FF +48 两次独立构建可复现**（采纳），
而 r115 那把复制驱动买回目标族 +0.456 却付掉 `eth_rxc` hold 的 29 %（拒绝）。
同一件事的否定形式在 `极限核对`：**拿 BRAM 削 setup 不划算**。

---

## 10 已量 / 未量

**已量（本章引用的、来自本章打开过的件）**：
四个顶层例化与 11 个 eth 侧例化名、32 个 `pl_video_top` 侧例化名及其行号；
MMCM 的 VCO 与各路分频（`src/rtl/clocks/clk_gen.v:17-29`）、六个时钟对象的周期与端点数
（`时序债务账` §1）；`eth_rxc` 挂 2544 只寄存器 / `clk_fpga_0` 3338
（`域划分候选评估`）；
三个 GPIO 窗口的地址与位图（`src/ps/main.c:4-19`、`:48-96`、`src/rtl/top/system_top.v:264-293`）；
效果链固定 15 拍与 −4 行偏移（`src/rtl/process/proc_pipeline.v:3`、`:24-30`）；
CDC 深度 8192×36 与 `ram_style`（`src/rtl/eth/eth_udp_video_top.v:295-298`、`src/rtl/eth/dc_fifo.v:20`）；
打包器 LUTRAM 与域归属（`src/rtl/eth/axi_frame_saver64.v:9-12`、`:48-50`、
`src/rtl/eth/eth_udp_video_top.v:354-355`）；
采纳 / 否决 / 未决三本账的逐条依据与读数（第 6、7、8 节，全部指回 `build/runs/decisions.md`、
`开发流水账`、`开发台账`）；r118 的资源与时序总账
（`build/r118_gates_final.txt`）。

**未量 / 本章不能替它下结论的**：
**台账点名的凭据件有六处目录/文件与两支脚本已不在盘上**（逐条清单见 §7.7）——
判定可以引用，件路径不可以；本章因此在每一处都改写成"台账点名的件名，现盘上无此件"，
而没有删掉点名。要把这些负结果重新变成可复核的，需要重跑那两支只读探针
（`build/tcl/probe_timing_roster.tcl` 那一族），本章没跑。
`eth_rxc` 域四条候选里 **B 与 C 的预期收益都是"未量"**（`域划分候选评估`
明写"这里不给数字，只登记代价与判据"），所以本章不写它们能买到几纳秒。
候选 A 剩下的那条写指针扇出读数（1165）**当前无法复量**（`:31-35`）。
`未决项集中表` 那条角度机读口是**未落地**，不是"落地了但没测"。
`build/r113_angle_lane_plan.md` 里那个保留位 `[28:20]` 的实际占用本章没打开核过；
`dbg_zoom` 的位序只核了 `src/rtl/top/pl_video_top.v:680-688` 那一段（bit31 活着旗、bit19 拟合、
bit[18]=zman、[17:15]=zsel、[14:12]=zoom_code、[11]=zoom_active、[10]=zoom_dir、[9:0]=inv_used）。
三路片源同时跑的仲裁观感没有量化凭据（`架构章` 那张图给的是结构不是数）；
`build/r118_gates_final.txt:41-44` 那一路 `cdc.rpt` 提示
"基线里有而本版没有：`eth_rxc>clkout0_1`、`eth_rxc>clkout0_1`（原因未查证，不算改进）"与
"同配对端点数增长：`clk_fpga_0>clkout0_1`(17→103)、`sys_clk>eth_rxc`(1909→1968)（记录用，不判红）"——
这两笔本章只登记，不解释；解释它们需要一次 CDC 明细的逐对读，本章未做。

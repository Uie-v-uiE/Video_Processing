# A1 · 整体架构、分层与时钟/复位/地址平面

> 卷 A1 / 共 A 系列。对象：`D:\Xilinx\Prj\Video_Processing` 下的 Zynq-7020 视频工程（`src/rtl` + `build/report`）。
> 本文所有数字均在后文点名来源 `（文件:行号）`；未能从文件/报告中确认的条目一律标注 `未证`。

## 目录

1. [三棵顶层的包含关系与跨层端口](#1-三棵顶层的包含关系与跨层端口)

### 1.1 包含关系（自顶向下）

```
system_top                      src/rtl/top/system_top.v:4
├─ design_1_wrapper u_bd        同文件:75      (PS7 + DDR 控制器 + HP0/GPIO 互联)
├─ clk_gen u_idelay_clkgen      同文件:121     (只取 clk_200m 与 locked；clk_pix/clk_pix5x 声明为
│                                               *_unused，同文件:119 与 :123)
├─ eth_udp_video_top u_eth      同文件:154     (入流侧：RGMII→GMII→UDP→行环→DDR 写)
├─ snap_cross u_lm_axi          同文件:214     (eth_rxc → fclk0 的 320bit 健康快照)
└─ pl_video_top u_pl            同文件:258     (显示侧：DDR 读→效果链→OSD→TMDS)
   └─ clk_gen u_clk             pl_video_top.v:128  (clk_pix / clk_pix5x 的真正消费者)
```

三棵树之间**没有层次包含**：`eth_udp_video_top` 与 `pl_video_top` 都是 `system_top` 的平级兄弟，
它们之间的所有连线都要经过 `system_top` 的线网（入流侧的 5 个 `eth_wr_*` / `eth_commit` 就是这样，
见 `system_top.v:185-192` 出、`:303-312` 进）。`pl_demo_top.v` 不在这棵树里，判据见 §1.4。

### 1.2 跨层端口表（名字 / 位宽 / 方向 / 所在时钟域）

| # | 端口（system_top 侧写法） | 位宽 | 方向 | 时钟域 | 引用 |
|---|---|---|---|---|---|
| 1 | `fclk0` = `FCLK_CLK0` | 1 | BD → PL | `clk_fpga_0` 100 MHz | `system_top.v:83` |
| 2 | `fclk0_rst_n` = `FCLK_RESET0_N` | 1 | BD → PL | 同上（异步复位脚） | `system_top.v:83` |
| 3 | `gpio_o` = `GPIO_0_tri_o` | 32 | BD → PL | `clk_fpga_0`（PS 写更新） | `system_top.v:84`、域说明 `:235` |
| 4 | `gpio1_i` = `GPIO_1_tri_i` | 32 | PL → BD | `clk_fpga_0` | `system_top.v:85`、驱动 `:247` |
| 5 | `gpio_cfg1_o` / `gpio_cfg2_o` = `GPIO_2/3_tri_o` | 32+32 | BD → PL | `clk_fpga_0` | `system_top.v:86-87` |
| 6 | `M_AXI_HP0_aw/w/b` | 64 bit 数据 | PL → BD | `clk_fpga_0` | `system_top.v:94-103` |
| 7 | `M_AXI_HP0_ar/r` | 64 bit 数据 | PL → BD | `clk_fpga_0` | `system_top.v:88-101` |
| 8 | `rgmii_rxc` ← `eth_rxc` | 1 | 板 → u_eth | `eth_rxc` 125 MHz | `system_top.v:174` |
| 9 | `rst_n` = `eth_rst_n & mmcm_locked` | 1 | 组合 → u_eth | 两个域的产生值相与 | `system_top.v:175` |
| 10 | `idelay_clk` = `clk_200m` | 1 | clk_gen → u_eth | 200 MHz IDELAY 参考 | `system_top.v:124`、`:178` |
| 11 | `fb_wr_en/addr/data` | 1/19/16 | u_eth → u_pl | `eth_gmii_clk`（= `gmii_rx_clk`） | `system_top.v:185-187`、`:303-306` |
| 12 | `eth_gmii_clk` → `eth_wr_clk` | 1 | u_eth → u_pl | 同上 | `system_top.v:190`、`:303`、`eth_udp_video_top.v:387` |
| 13 | `ddr_commit_base/pulse` → `eth_ddr_base/eth_commit` | 32/1 | u_eth → u_pl | `clk_fpga_0` | `system_top.v:191-192`、`:311-312` |
| 14 | `lm_bus` / `lm_bus_tog` / `lm_hb` | 320/1/1 | u_eth → snap_cross | `eth_rxc` | `system_top.v:202`、域声明 `eth_udp_video_top.v:58-62` |
| 15 | `eth_live` = `lm_axi[7*32+3]`、`eth_tb_ok` | 1+1 | snap_cross → u_pl | `clk_fpga_0`（已同步） | `system_top.v:255-256`、`:308-309` |
| 16 | `stage_sel` = `gpio_cfg1_o[8:0]` | 9 | BD → u_pl | `clk_fpga_0` 异步 | `system_top.v:264` |
| 17 | `split_ctl`（19 bit 拼装） | 19 | BD → u_pl | `clk_fpga_0` 异步 | `system_top.v:274-275`、端口注释 `pl_video_top.v:48-54` |
| 18 | `gamma_ctl` = `gpio_cfg2_o` | 32 | BD → u_pl | `clk_fpga_0` | `system_top.v:276` |
| 19 | `bilin_en_axi` / `osd_off_axi` / `ps_publish` | 1×3 | BD → u_pl | `clk_fpga_0` 准静态 | `system_top.v:286-288` |
| 20 | `dbg_src` | 16 | u_pl → lane30 mux | `clk_fpga_0` | `system_top.v:227`、`:295`、`pl_video_top.v:603` |
| 21 | `dbg_lat` | 6×32 | u_pl → lane24..29 | `clk_fpga_0` | `system_top.v:229`、`pl_video_top.v:642` |
| 22 | `dbg_zoom` | 32 | u_pl → lane23 | `clk_fpga_0`（源在像素域，经 snap_cross） | `system_top.v:228`、`pl_video_top.v:674-688` |
| 23 | `tmds_clk_p/n`、`tmds_data_p/n` | 1×2 + 3×2 | u_pl → 板 | `clk_pix` + `clk_pix5x` | `system_top.v:296-297`、`pl_video_top.v:1026-1032` |
| 24 | `copy_hold` | 1 | u_pl → u_eth | 当前恒 0（`pl_video_top.v:538`） | `system_top.v:179`、`:320` |

`pl_video_top` 内部的两条搬运机（`u_row` / `u_aw`）在 `axi_clk` 域共享同一个 AXI 读通道，mux 只有一处：
`assign m_axi_araddr = eth_mode ? row_araddr : fill_araddr;`（`pl_video_top.v:709`）。

### 1.3 参数一次定型（跨层唯一出处）

`system_top.v:136-145` 是本工程"几何 + 地址"的唯一字面量出处：`VIDEO_W = 16'd512`、`VIDEO_H = 16'd300`、
`PANE_W = 16'd512`、`DDR_BASE = 32'h1000_0000`、`PS_DDR_BASE = 32'h1010_0000`、
`UDP_VIDEO_PORT = 16'd5001`，然后分别下发给 `u_eth`（`:154-157`）与 `u_pl`（`:258-259`）。
文件里把为什么要集中写清楚了：「原来 512/300/0x1000_0000 在下面两个例化上各写一遍字面量……
现象是"写进去的帧几何与读出来的显示几何对不上"」（`system_top.v:135`）。
注意片源是 512×300、面板是 1024×600，两侧靠 `cx = x >> 1` / `y >> 1` 对齐（`pl_video_top.v:242-243`），
入流侧的整帧字节门同步放大：`frame_reasm #(.FRAME_BYTES(IMG_W*IMG_H*2))` = 307200
（`eth_udp_video_top.v:235`，为什么以前漏传见 `:231-234`）。

判据按强弱排开，每一条都点名文件与行号：

| # | 判据 | 证据 |
|---|---|---|
| 1 | 工具侧的 `Design` 行就是位流顶层 | `build/report/utilization.rpt:7` 与 `build/report/timing_summary.rpt:7` 都写 `\| Design       : system_top`；`utilization.rpt:10` 进一步写 `\| Design State : Routed` |
| 2 | 报告里的实例前缀只有 `u_bd / u_eth / u_pl` | `timing_summary.rpt:347` 的 `u_eth/u_cdc/mem_reg_0/CLKBWRCLK`、`:731` 的 `u_pl/u_clk/u_mmcm/CLKOUT0`（Sources 行）。全篇没有 `pl_demo_top` 前缀的路径 |
| 3 | 端口面：`pl_demo_top` 根本没有网口与 DDR | `pl_demo_top.v:4-13` 只有 `sys_clk / key1_n / key2_n / led[1:0] / tmds_*`；`system_top.v:5-42` 有 DDR 全套 + `FIXED_IO_*` + `eth_rxc/txc/mdio` |
| 4 | 演示顶层把 AXI/PS 侧全部钉成常量 | `pl_demo_top.v:24-26`：`.sys_rst_n(1'b1)`、`.axi_clk(sys_clk)`（演示树里"axi 时钟"= 50 MHz 晶振，不是 PS 的 100 MHz FCLK）、`.axi_rst_n(1'b1)`；`:41` `.split_ctl(19'd0)`；`:42` `.ps_publish(1'b0)`；`:43` `.mode_ovr(2'b00)`。文件头自述 `pl_demo_top.v:2-3`「Pure-PL demo top … No PS required.」 |
| 5 | 例化参数缺 `PS_BASE_ADDR` ⇒ 走默认 | `pl_demo_top.v:20-21` 只传 4 个参数，`PS_BASE_ADDR` 落到 `pl_video_top.v:16` 的默认 `32'h1010_0000` |
| 6 | 仓库自己的口径一致 | `src/rtl/eth/snap_cross.v:27` 明写「`pl_demo_top` **不在当前位流里**（正式构建的是…」；门禁把它归入"台架也扫"那一格（`build/check_ports.py:325`），反例文件里也拿它当靶子（`build/ports_check_width_ce.txt:8`） |

⚠ 一条"行号会过期"的实证：`build/ports_check_width_ce.txt:9` 把反例点名为 `pl_demo_top.v` 的第 19 行
的 `.eth_wr_addr(…)`，而现版 `pl_demo_top.v:19` 是 `wire       src_sel   = 1'b0;`。机制仍成立（顶层接线检查
扫这棵树），行号已漂 ⇒ 本卷一律按名字复核之后再引行号。

**结论**：真上板的是 `system_top` 这一棵；`pl_video_top` 是它的显示子树（`system_top.v:258`）；
`eth_udp_video_top` 是入流子树（`system_top.v:154`）；`pl_demo_top` 只是无 PS 的纯 PL 演示顶层，
它与板上树**共享** `pl_video_top`，所以改显示通路时必须两棵树一起接线（`pl_demo_top.v:31-33` 那句
"新加一口必须两棵树一起接"就是这条纪律的出处，也是 ISSUES #83 那次悬空成 `Z` 的根因）。

2. [五个时钟域逐个拆解](#2-五个时钟域逐个拆解)

两颗 MMCM、八个 BUFG（`build/report/utilization.rpt:161` `| BUFGCTRL | 8 |`、`:163`
`| MMCME2_ADV | 2 |`）。工具给出的全部时钟及周期见 `timing_summary.rpt:162-171` 的 Clock Summary 表。

### 2.0 MMCM 参数（两颗实例同一份 RTL）

`src/rtl/clocks/clk_gen.v:15-31` 只有一个 `MMCME2_BASE`，两颗实例（`system_top.v:121` 的
`u_idelay_clkgen`、`pl_video_top.v:128` 的 `u_clk`）参数完全相同：

| 参数 | 值 | 出处 | 算式 |
|---|---|---|---|
| `CLKIN1_PERIOD` | `20.000` | `clk_gen.v:17` | 50 MHz 晶振（`sys_clk`） |
| `DIVCLK_DIVIDE` | `1` | `clk_gen.v:18` | 分频器不降频 ⇒ 参考 50 MHz |
| `CLKFBOUT_MULT_F` | `20.000` | `clk_gen.v:19` | **VCO = 50 × 20 = 1000 MHz**（文件头 `clk_gen.v:3` 同句） |
| `CLKOUT0_DIVIDE_F` | `20.000` | `clk_gen.v:21` | 1000 / 20 = **50 MHz** ⇒ `clk_pix` |
| `CLKOUT1_DIVIDE` | `4` | `clk_gen.v:24` | 1000 / 4 = **250 MHz** ⇒ `clk_pix5x` |
| `CLKOUT2_DIVIDE` | `5` | `clk_gen.v:27` | 1000 / 5 = **200 MHz** ⇒ `clk_200m` |
| `REF_JITTER1` | `0.010` | `clk_gen.v:30` | — |

四个输出各过一只 `BUFG`（`clk_gen.v:53-56`：`u_bufg_fb / u_bufg_pix / u_bufg_5x / u_bufg_200`）。
工具名与 RTL 名的对应关系（按报告的 `Sources:` 行反查）：
`clkout0_1 = u_pl/u_clk/u_mmcm/CLKOUT0`（`timing_summary.rpt:731` 段头的 Sources 行 `:931`）、
`clkout1_1 = u_pl/u_clk/u_mmcm/CLKOUT1`（`:956`）、`clkout2 = u_idelay_clkgen/u_mmcm/CLKOUT2`（`:979`）、
`clkfbout = u_idelay_clkgen/.../CLKFBOUT`（`:696`）、`clkfbout_1 = u_pl/u_clk/.../CLKFBOUT`（`:719`）。
⇒ `u_idelay_clkgen` 的 CLKOUT0/CLKOUT1 在位流里没有名字，因为它们的输出管脚在顶层就没接
（`system_top.v:119` `wire clk_pix_unused, clk_pix5x_unused, mmcm_locked;`、`:123`）。

### 2.1 `sys_clk`（50 MHz 板晶振）

- 产生：板上晶振，引脚 `W17`（`timing_summary.rpt:567` `W17 ... sys_clk (IN)`），周期 20.000
  （`:166` `sys_clk {0.000 10.000} 20.000 50.000`），经 `sys_clk_IBUF_BUFG_inst`（`:571`）。
- 消费：按键去抖 `key_debounce`（`pl_video_top.v:136-141`，`CNT_MAX(1_000_000)`）、长按
  `key_long`（`:148`，`HOLD_CYC(30_000_000)` 注释即"50 MHz ⇒ 0.6 s"）、旋转计数 `angle_ctrl`
  （`:183-188`）、LED 心跳 25 bit 计数器 `hb`（`:1034-1039`）、PHY 上电计数器
  `phy_rst_cnt`（`system_top.v:108-112`）。
- 余量：Intra Clock 表 `timing_summary.rpt:183` —— `sys_clk WNS 14.876 / WHS 0.222 / WPWS 7.000`，
  端点 323 个。最差 setup 路径 `u_pl/u_ang/angle_reg[2]/C → angle_reg[3]/D`，5 级逻辑
  （`:545-553`）。pulse-width 余量由 `MMCME2_ADV/CLKIN1` 的 3.000 ns 门限给出（`:676-677`）。
- 跨域：`clkout0_1 ↔ sys_clk` 是报告里唯一成对出现的两个域间组，`sys_clk→clkout0_1` WNS 3.695 /
  WHS 0.200（`:199`），`clkout0_1→sys_clk` 14.757 / 0.165（`:198`）。

### 2.2 `clk_fpga_0` = `axi_clk`（PS FCLK0，100 MHz）

- 产生：PS7 的 `FCLKCLK[0]`，Pulse Width 段的 `Sources:` 行点名
  `{ u_bd/design_1_i/processing_system7_0/inst/PS7_i/FCLKCLK[0] }`（`timing_summary.rpt:344`），
  周期 10.000（`:164`），经 `FCLK_CLK_0_BUFG`（`:255`）。顶层网线叫 `fclk0`（`system_top.v:83`）。
- 消费：`u_eth` 的 CDC 读侧与打包器（`eth_udp_video_top.v:303`、`:307`、`:354-355`）、
  `pl_video_top` 的两条搬运机与仲裁（`pl_video_top.v:421-425` `src_arb`、`:454` `u_row`、
  `:692` `u_aw`、`:624` `frame_latency`）、`snap_cross u_lm_axi` 的目的域（`system_top.v:215`）。
- 余量：Intra 表 `timing_summary.rpt:181` —— `clk_fpga_0 WNS 1.850 / WHS 0.053 / WPWS 3.870`，
  端点 15721。最慢 setup 路径点名在 `:230-233`：
  `u_pl/u_arb/owner_eth_reg/C → u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]`，`Data Path Delay 7.544ns`
  其中 **route 7.060 ns（93.584%）**（`:237`），只有 1 级 LUT6（`:238`）⇒ 这一档是布线瓶颈不是逻辑瓶颈。
  `u_pl/u_arb/FCLK_CLK0` 那根网线扇出 4375（`:256`）。
- 注意：全设计最紧的**数字**不在这里，而在 `clkout2` 的 0.264 ns（见 §2.6 与 `:151`）。

### 2.3 `clk_pix` = `clkout0_1`（50 MHz 像素域）

- 产生：`u_pl/u_clk/u_mmcm/CLKOUT0`（`timing_summary.rpt:931` Sources 行），算式 1000/20（`clk_gen.v:19`+`:21`），
  经 `u_bufg_pix`（`clk_gen.v:54`）；`pl_video_top.v:126` 声明、`:128-131` 例化、`:226-230` 例化时序发生器。
- 消费：本卷最大的一片 —— 时序 `video_timing_1024x600`、缩放 `zoom_fit/zoom_ctrl/zoom_mapper`
  （`pl_video_top.v:322-349`）、打拍链 `de_d/x_d/...`（`:356-374`）、`fb_bilin` 读口（`:732-750`）、
  `raw_line_delay`（`:788`）、`proc_pipeline`（`:800`）、`split_display`（`:911`）、`osd_overlay`（`:999`）、
  `rgb2dvi` 的并行侧（`:1026-1027`）。
- 余量：Intra 表 `timing_summary.rpt:186` —— `clkout0_1 WNS 3.630 / WHS 0.059 / WPWS 8.870`，
  **端点 30179**（全设计 51135 的 59%）。最差 setup 点名 `:740-748`：
  `u_pl/x_d_reg[20][3]/C → u_pl/u_osd/ch_r_reg/ADDRARDADDR[6]`，`Data Path Delay 15.834ns`、
  **22 级逻辑**（`CARRY4=9 LUT2=1 LUT3=2 LUT4=5 LUT6=4 MUXF7=1`）——OSD 的字符取模那一段是像素域的真正深度。
  最差 hold 是 `u_pl/u_pipe/u_sobel/no_right_r_reg[0] → [1]`，0 级逻辑、靠 0.259 ns 时钟偏斜撑
  （`:864-873`）。
- 时钟扇出：`u_pl/clk_pix` 这条网线 fo=5515（`:772`、`:892`）。

### 2.4 `clk_pix5x` = `clkout1_1`（250 MHz，TMDS 串行化）

- 产生：`u_pl/u_clk/u_mmcm/CLKOUT1`（`timing_summary.rpt:956`），算式 1000/4 = 250 MHz
  （`clk_gen.v:19` + `:24`），周期 4.000 ns（`:170` `clkout1_1 {0.000 2.000} 4.000 250.000`），
  经 `u_bufg_5x`（`clk_gen.v:55`）。
- 消费：只给 `rgb2dvi` 的 OSERDES 串并转换（`pl_video_top.v:1026-1032` 的 `.clk_pix5x`）。
  板上占用与资源表吻合：`OSERDESE2 8`、`ODDR 5`、`OBUFDS 4`（`utilization.rpt:215`、`:218`、`:221`），
  6 条 TMDS 线 + 时钟对正好用 8 只 OSERDES。
- 余量：报告里这一栏 **Setup/Hold 都是 `NA`**（`timing_summary.rpt:945-946`），只有脉宽检查
  `WPWS 2.408`（`:187`、`:947`），因为它的 endpoint 全在 `BUFG/I` 的 Min Period 上
  （`:959` `Min Period n/a BUFG/I n/a 1.592 4.000 2.408 BUFGCTRL_X0Y2 u_pl/u_clk/u_bufg_5x/I`）。
  ⇒ 这一域没有常规同步路径可判，**不要把它当成"有正裕量"**（源同步串行器由 OSERDES 自己保证相位关系）。

### 2.5 `clk_200m` = `clkout2`（200 MHz，IDELAY 参考）

- 产生：`u_idelay_clkgen/u_mmcm/CLKOUT2`（`timing_summary.rpt:979`），1000/5（`clk_gen.v:27`），
  周期 5.000（`:171`）；顶层把它接到 `u_eth` 的 `idelay_clk`（`system_top.v:124`、`:178`），
  再进 `gmii_to_rgmii` 的 `IDELAYCTRL_inst/REFCLK`（`:982-983` 的路径名
  `u_eth/u_rgmii/u_rgmii_rx/IDELAYCTRL_inst/REFCLK`）。
- 余量：`WPWS 0.264`（`:188`），并且**这一位就是全设计的 WPWS 最小值**
  （`:151` 设计级汇总 `WPWS(ns) 0.264`）。展开在 `:983`：
  `Max Period n/a IDELAYCTRL/REFCLK n/a 5.264 5.000 0.264` ⇒ 门限是"周期必须 ≤ 5.264 ns"，
  实际 5.000 ns 只留 0.264 ns。**含义**：这颗参考钟不能再降频、MMCM 的 CLKOUT2_DIVIDE=5 是硬约束
  （改 6 就变 166.67 MHz = 6.000 ns，立刻越界）。资源侧对应 `IDELAYCTRL 1`（`utilization.rpt:141`）。

### 2.6 `eth_rxc` = `gmii_rx_clk`（125 MHz，PHY 恢复时钟）

- 产生：不在 RTL 里产生——PHY 出来的时钟引脚 `Y19`（`timing_summary.rpt:388` `Y19 ... eth_rxc (IN)`），
  过 `eth_rxc_IBUF_inst` → `u_eth/u_rgmii/u_rgmii_rx/BUFG_inst`（`:390-392`），周期 8.000（`:165`）。
  `Sources: { eth_rxc }`（`:523`）。这条钟同时是收发两侧：`eth_udp_video_top.v:5` 明写
  「gmii_rx_clk 与 gmii_tx_clk 是**同一根**」，`:387` `assign eth_gmii_clk = gmii_rx_clk;`。
- 消费：RGMII→GMII 解帧、`gmii_rx_mac` 的 FCS（`eth_udp_video_top.v:186-192`）、`udp_rx_parser`
  （`:197-204`）、`frame_reasm`（`:235`）、`link_monitor`（`:284-293`，`CLK_HZ(125_000_000)`）、
  CDC 写侧 `dc_fifo`（`:299`）、IDDR/IDELAY 的数据捕获。
- 余量：Intra 表 `timing_summary.rpt:182` —— `eth_rxc WNS 0.739 / WHS 0.052 / WPWS 3.500`，端点 4835。
  最差 setup 就是全设计的 WNS（`:149-151` 与 `:357` 同值 0.739），路径点名
  `:366-374`：`u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C → check_buffer_reg[19]/D`，11 级逻辑
  （`CARRY4=6 LUT3=2 LUT4=2 LUT5=1`）——是 ICMP 的校验和累加器，不是视频通路。
  最差 hold `:453-471`：`u_eth/u_cdc/rgray_s1_reg[10] → u_eth/u_lm/full_d_reg`，其中
  **`User Uncertainty (UU): 0.800ns`**（`:471`）——这 0.8 ns 是 XDC 里为 RGMII 加的额外不确定度，
  它一个人吃掉了 8 ns 周期的 10%，是该域 hold 只有 0.052 ns 的直接原因。
- 全设计汇总行（`:151`）：`WNS 0.739 / TNS 0.000 / 0 failing / 51135 endpoints`，
  `WHS 0.052 / 0 failing`，`WPWS 0.264 / 0 failing`，紧跟 `:154`「All user specified timing
  constraints are met.」

3. [面板与帧的数学（1024×600 档）](#3-面板与帧的数学1024x600-档)

### 3.1 各段数值（唯一出处 = 参数表）

`src/rtl/video/video_timing_1024x600.v:17-22` 只是 `video_timing` 的参数化封装，数值全在那一个例化里：

| 段 | 行（H）数值 | 出处 | 列（V）数值 | 出处 |
|---|---|---|---|---|
| 有效 | `H_ACTIVE 1024` | `video_timing_1024x600.v:18` | `V_ACTIVE 600` | 同行 `:18` |
| 前肩 FP | `H_FP 44` | `:19` | `V_FP 3` | `:20` |
| 同步脉宽 | `H_SYNC 88` | `:19` | `V_SYNC 6` | `:20` |
| 后肩 BP | `H_BP 188` | `:19` | `V_BP 16` | `:20` |
| 合计 | **1344** | 文件头 `:3`「H: 1024 + 44 + 88 + 188 = 1344」 | **625** | 文件头 `:4`「V: 600 + 3 + 6 + 16 = 625」 |
| 极性 | `H_POL 1'b1`（+） | `:21`、文件头 `:5` | `V_POL 1'b0`（−） | `:21`、`:5` |

显示侧把这两个合计数**再抄了一遍**成 localparam：`DISP_V_LINES = 12'd600`（`pl_video_top.v:397`）、
`DISP_V_LAST = 12'd624`（`:398`，注释 `V_TOTAL-1`）、`VB_X_GUARD = 12'd1279`（`:399`，注释
`H_TOTAL(1344)-65：早关 64 个消隐像点`）。⇒ 改面板必须同时改这两处，这是本卷找到的**唯一一处**
时序常数重复（`video_timing_1024x600.v` 与 `pl_video_top.v:397-399`）。

### 3.2 一行、一帧多少拍

操作数全部来自上表，单位是 `clk_pix`（50 MHz ⇒ 20 ns/拍，`timing_summary.rpt:169`）：

- 一个显示行 = `H_TOTAL` = **1344 拍** = 1344 × 20 ns = **26.880 µs**（`video_timing_1024x600.v:3`）。
- 一帧 = `H_TOTAL × V_TOTAL` = 1344 × 625 = **840 000 拍** = 16.800 ms
  （两个操作数分别来自 `video_timing_1024x600.v:3` 与 `:4`）。
- 有效像素 = 1024 × 600 = 614 400 拍，**消隐占比 (840000−614400)/840000 = 26.85%**。
- V 消隐窗口 = (625 − 600) × 1344 = 25 × 1344 = **33 600 个像素拍** = 672 µs。
  这一段 RTL 自己算过并写在注释里：「V_TOTAL 625 - active 600 = 25 blank lines = 33.5k pix cycles
  = 67k axi(100M) cycles」（`pl_video_top.v:393-394`），落成的判据常数是
  `VBLANK_AXI_CYC = 32'd67200`（`pl_video_top.v:446`）——33 600 拍 × 2（100 MHz 对 50 MHz）= 67 200，
  与注释的"33.5k / 67k"对得上（注释取了整）。超窗即粘滞：`copy_overrun`（`pl_video_top.v:447-452`）
  并由 `led[0]` 以 6 Hz 快闪报出（`pl_video_top.v:1039`）。

### 3.3 场频 / 帧周期

`f_field = 50 000 000 / (1344 × 625) = 50 000 000 / 840 000 = 59.523 8 Hz`，
`T_frame = 840 000 / 50 000 000 = 16.8 ms`。
三个操作数的来源：像素钟 50 MHz ← `clk_gen.v:21`（1000/20）与 `timing_summary.rpt:169`
（`clkout0_1 20.000 50.000`）；1344 ← `video_timing_1024x600.v:3`；625 ← 同文件 `:4`。
RTL 里对这件事的口径性描述：「面板是 1344×625@50 MHz ⇒ 读数恒在 59/60」（`pl_video_top.v:932-933`），
那句正是在解释为什么 OSD 的 `FPS:` 后来改成数"写进屏的新帧"而不是数显示场（`pl_video_top.v:940-950`）。

### 3.4 片源 512×300 与面板 1024×600 的对齐

- 列方向：`cx = x >> 1`（`pl_video_top.v:242`）⇒ 每个源列在屏上占两列，注释同页 `:239`
  「1024 个显示列对应 512 个源列」。
- 行方向：`cy = (y >> 1) < IMG_H ? (y >> 1) : (IMG_H - 1)`（`pl_video_top.v:243`）⇒ 600 显示行对 300 源行。
- 于是**每个源像素在屏上有 4 个 50 MHz 拍**，`fb_bilin` 就是按这句话设计的：
  「每源像素用满它天然的 4 个 50 MHz 拍」（`pl_video_top.v:721-722`）。
- 效果链的一行按显示列算：`proc_pipeline #(.H_ACTIVE(2*IMG_W))`（`pl_video_top.v:800`），
  OSD 同理 `osd_overlay #(.OUT_W(2*IMG_W), .OUT_H(2*IMG_H))`（`:999`），行环同理
  `raw_line_delay #(.W(2*IMG_W))`（`:788`）⇒ ×2 这个关系在显示侧只有一个写法（`:997-998` 明确认领了这一点）。
- 一帧的数据量与搬运字数：512 × 300 × 2 B = 307 200 B（字节门 `FRAME_BYTES(IMG_W*IMG_H*2)`，
  `eth_udp_video_top.v:235`）= 307200 / 8 = **38 400 个 64 bit 字**，RTL 写作"one frame is 38.4k 64-bit
  words"（`pl_video_top.v:395`）⇒ 搬运机必须在 67 200 个 axi 拍里发完 38 400 个字，
  即平均 **1.75 axi 拍/字**（38400/67200 由 `pl_video_top.v:446` 与 `:395` 两个数相除得）。
4. [复位树](#4-复位树)

### 4.1 四个复位发生器

| 网线 | 产生者 | 极性 | 出处 |
|---|---|---|---|
| `fclk0_rst_n` | PS7 的 `FCLK_RESET0_N`（BD 直出） | 低有效 | `system_top.v:83`（`.FCLK_CLK0(fclk0), .FCLK_RESET0_N(fclk0_rst_n)`） |
| `eth_rst_n` | `sys_clk` 域自由运行计数器 `phy_rst_cnt` | 高有效计数、末位即复位释放 | `system_top.v:108-112`：`if (!(&phy_rst_cnt)) phy_rst_cnt <= phy_rst_cnt + 1'b1;` / `assign eth_rst_n = phy_rst_cnt[23];` |
| `sys_rst_n` | **顶层绑常量** | — | `system_top.v:260` `.sys_clk(sys_clk), .sys_rst_n(1'b1)` ⇒ `pl_video_top` 的 `sys_rst_n` 与 `u_clk` 的 `rst_n` 都是 1（`pl_video_top.v:129`） |
| `clk_gen.RST` | MMCM 的高有效脚，由 `~rst_n` 驱动 | 反相一次 | `clk_gen.v:49` `.RST(~rst_n)` |

`phy_rst_cnt` 的宽度决定 PHY 上电保持时间：2^24 − 1 = 16 777 215 拍 × 20 ns = **≈335.5 ms**
（操作数：`system_top.v:108` 的 `24'd0`/`:112` 的 `[23]`、周期来自 §3.3 的 50 MHz）。

### 4.2 `mmcm_locked` 参与的地方（逐处点名）

1. `system_top.v:124` — `u_idelay_clkgen` 的 `.locked(mmcm_locked)`；这颗 MMCM 的 `rst_n` 接的是
   `1'b1`（`system_top.v:122`），所以它**从不复位**，`locked` 只当门控电平用。
2. `system_top.v:175` — `.rst_n(eth_rst_n & mmcm_locked)`：`u_eth` 里**所有** `or negedge rst_n`
   的时序（`eth_udp_video_top.v:96`、`:267`、`:278`、`:382`）以及 CDC 写侧复位 `wr_rst_n`（`:299`）
   都吃这一个组合值 ⇒ IDELAY 参考钟没锁上时，收包侧整片保持复位。
3. `pl_video_top.v:130-132` — `.locked(locked)` 之后 `wire rst_pix_n = sys_rst_n & locked;`。
   因为 `sys_rst_n` 恒 1（§4.1 第 3 行），**像素域的复位实际上就等于 `locked` 本身**。
4. `pl_video_top.v:1046` — `locked` 被塞进 `status[31:0]` 的打包里（`{zoom_dir, zoom_active, inv_used,
   eth_ready, locked, ...}`），JTAG 侧能直接读它，这是唯一的"复位树可观测"出口。
5. `src/rtl/eth/snap_cross.v:21` 记了一条后果：「这颗寄存器在 `pl_demo_top` 那棵树下，顶层把
   `sys_rst_n` 绑成常量 1'b1」——同一句在 `system_top.v:260` 也成立。⇒ 板上这些
   `if (!dst_rst_n)` 分支**永远不会执行**，上电值只由位流里的 FF 初值承载，所以"声明初值必须与复位
   分支想给的值一致"是硬纪律（本卷在 `pl_video_top.v:214-217` 的 `ze0/ze1/ze2` 复位取
   `ZOOM_DEFAULT_ON`、`:256-257` 的 `be0..be2` 取 `1'b1`、`:269-270` 的 `oo0..oo2` 取 `1'b0` 三处
   都能看到这条纪律被执行，且每处都写了理由）。

### 4.3 跨域复位（一份设计里并存两套异步复位）

| 结构 | A 侧复位 | B 侧复位 | 引用 |
|---|---|---|---|
| `dc_fifo`（BRAM CDC，36 bit × 8192） | `wr_rst_n(rst_n)`＝eth_rxc 域 | `rd_rst_n(axi_rst_n)`＝PS | `eth_udp_video_top.v:299`、`:303` |
| `ddr_bank_commit` | `rst_n` | `axi_rst_n` | `eth_udp_video_top.v:335-336` |
| `axi_frame_saver64` | 只在 axi 域：`clk(axi_clk), rst_n(axi_rst_n)` | — | `eth_udp_video_top.v:355` |
| `frame_commit_lock` | `axi_rst_n` | `pix_rst_n` | `pl_video_top.v:431-433` |
| `snap_cross`（4 处） | 目的域 `dst_rst_n` | 源域不复位，靠 toggle | `system_top.v:215`、`pl_video_top.v:877`、`:983`、`:675` |
| 显示帧缓存 `fb_bilin` | 读侧 `clk_pix/rst_pix_n` | 写侧 `wr_clk(axi_clk)` **无独立复位脚** | `pl_video_top.v:735-736` |

`u_bilin` 的写侧只有 `wr_en/wr_addr/wr_data` 三个口、不带 `wr_rst_n`（`pl_video_top.v:736`），
这与 §2.2 那条最慢路径的终点正是这块 BRAM（`timing_summary.rpt:232-233` 的
`u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]`）是同一件事的两面：写口是纯数据、不参与复位树。

### 4.4 复位极性的量化读数

`utilization.rpt:51-67` 的「1.1 Summary of Registers by Type」给出全设计的触发器按复位方式分布：
异步复位 5956（`:64` `| 5956 | Yes | - | Reset |`）、异步置位 392（`:63`）、同步复位 1779（`:66`）、
同步置位 61（`:65`），合计与 `:40` 的 `Slice Registers 8188` 一致。
⇒ **低有效异步复位是绝对主流**（5956/8188 = 72.7%），对应 primitive 表里的
`FDCE 5956`（`utilization.rpt:194`）；392 只 `FDPE`（`:204`）主要是各条 `ASYNC_REG` 链复位成 `1`
的那些位（如 `pl_video_top.v:215-217`）。Latch 为 0（`utilization.rpt:42`
`| Register as Latch | 0 |`）⇒ 与"禁止组合跨域"的策略自洽（`eth_udp_video_top.v:6`）。

5. [AXI 平面与地址映射](#5-axi-平面与地址映射)

### 5.1 两个平面

- **GP0（控制面，PS→PL 寄存器）**：位流里实例化的互联是
  `design_1_axi_gp0_ic_imp_xbar_0` 与 `design_1_axi_gp0_ic_imp_auto_pc_0`
  （`utilization.rpt:246-247`），挂 3 只 AXI GPIO（`design_1_axi_gpio_0_0/1_0/2_0`，
  `utilization.rpt:243-245`）——4 个 tri 口对应 3 只 IP，因为第二只是双通道：
  「BD 里第二个 AXI GPIO，2 通道 × 32 bit，纯输出」（`system_top.v:47`）。
  口的分工见 `system_top.v:84-87`：`GPIO_0` 输出（旧控制字 + lane 选择）、`GPIO_1` 输入
  （PL→PS 的健康 lane，唯一驱动是 `assign gpio1_i = lm_rd;` `system_top.v:247`）、
  `GPIO_2/GPIO_3` = cfg1/cfg2（效果九位 + gamma）。
  GP0 在时序报告里露面的方式：`:290-292` 的全名 `u_bd/design_1_i/axi_gp0_ic/xbar/...`。
- **HP0（数据面，PL→DDR，64 bit）**：顶层唯一出口在 `system_top.v:88-103`。
  写通道由 `u_eth` 驱动（`system_top.v:193-199`），读通道由 `u_pl` 驱动（`system_top.v:298-302`），
  两条流在 BD 内部并进同一个 HP0 slave。静态属性直接钉在顶层连线上：
  `arcache/awcache = 4'b0011`（`:89`、`:94`）、`arlock/awlock = 2'b00`（`:90`、`:95`）、
  `arprot/arqos = 0`（`:91`）、`awid/wid = 6'd0`（`:95`、`:102`）、ARID/RID 6 bit（`:53`、`:59`）。
  **AXI3 的 4 bit LEN**：PL 侧内部是 8 bit（`m_arlen8` `:62`、`m_awlen` `:65`），跨界前截成 4 bit——
  `wire [3:0] m_awlen_axi3 = m_awlen[3:0];`（`:73`）与 `assign m_arlen_axi3 = m_arlen8[3:0];`（`:106`）。

### 5.2 DDR 上的帧缓存地址

| bank | 地址 | 用途 | 出处 |
|---|---|---|---|
| BANK0 | `0x1000_0000` | ETH 乒乓 A | `system_top.v:139`、`eth_udp_video_top.v:67` `localparam [31:0] BANK0 = BASE_ADDR;` |
| BANK1 | `0x1008_0000` | ETH 乒乓 B | `eth_udp_video_top.v:68` `localparam [31:0] BANK1 = BASE_ADDR + 32'h0008_0000;` |
| PS bank | `0x1010_0000` | SD 回放 / FILL 诊断帧 | `system_top.v:144`、`pl_video_top.v:16`、例化 `:692-693` |

每帧 300 KB、两 bank 间隔 512 KB（原文「每帧 300 KB，间隔 512 KB 够用」`system_top.v:141`）；
第三个 bank 从 +1 MB 起（`:142-143`）。**跨向约束**：`:142-143` 明写「这个数必须与固件里的
FRAME_ADDR 一致：`src/ps/sd_play.c` 与 `src/ps/main.c` 各有一处，改这里不改那边 ⇒ 现象是"PS 片源在
屏上不动"」。提交脉冲把"哪一 bank 已完整"一起带出：`ddr_commit_base`/`ddr_commit_pulse`
（`eth_udp_video_top.v:36-37`、`:346-347`），显示侧在 `frame_commit_lock` 里把它锁到拷贝结束
（`pl_video_top.v:430-440`）。

### 5.3 Outstanding 与突发参数

写侧 `axi_frame_saver64`（`clk = axi_clk`，`eth_udp_video_top.v:354-355`）：

| 参数 | 值 | 出处 | 含义 |
|---|---|---|---|
| `AWLEN` | `8'd0` | `axi_frame_saver64.v:40` | 每笔突发 1 拍（单 beat INCR） |
| `AWSIZE` | `3'b011` | `:41` | 8 字节 = 64 bit 全宽 |
| `AWBURST` | `2'b01` | `:42` | INCR |
| `WLAST` | 恒 `1'b1` | `:44` | 单拍 ⇒ 每拍都是末拍 |
| `OST` | `4'd8` | `:66` | 在途 beat 上限 8，「够盖住 HP0 写延迟」 |
| 打包 FIFO | `FW = 9` ⇒ 512 项 | `:10`、`:48-50` | 显式 `ram_style = "distributed"`，理由见 `:11-13` |
| 吞吐上限 | ≤2 拍/字 = 400 MB/s | 文件头 `:2-3` | 流水化前后的差别写在 `:5-7`（旧版在途深度恒 1 ⇒ ≈20 MB/s） |
| 为什么加深缓冲没用 | 「瓶颈是**平均排空速率**不是深度」 | `:7` | v6.2 把 CDC 做到 8192 条时上板毫无改善 |

上游的 CDC 深度：`dc_fifo #(.DATA_W(36), .ADDR_W(13))` = 8192 条 36 bit = 4096 个 64 bit 字 = 16 KB
（`eth_udp_video_top.v:298`，容量算式与"够不够"的论证在 `:295-297`：15 MBps × 672 µs ≈ 1260 字），
读侧 `fifo_rd <= !fifo_empty && !sv_full;` ⇒ 满则反压、不取出来丢（`:312`、`:256`）。
入流限速的历史教训在 `:258-262`：原「每 3 个 axi 周期取 1 条 = 66 MB/s < 125 MB/s」造成稳定丢 46% 的字。

读侧 `axi_frame_writer_gated`（`pl_video_top.v:454-469` 的 `u_row`）：

| 参数 | 值 | 出处 |
|---|---|---|
| `ARSIZE` | `3'b011`（8 B） | `axi_frame_writer_gated.v:37` |
| `ARBURST` | `2'b01`（INCR） | `:38` |
| `BEATS` | 16 | `:41` |
| `PIX_PER_BEAT` | 4（64 bit = 4 个 RGB565 像素） | `:40` |
| `TOTAL_WORDS` | `(153600+3)/4` = 38 400 | `:42-43` |
| `TOTAL_BURSTS` | `38400/16` = 2 400 | `:44` |
| `MAX_OUT` | `3'd4` ⇒ 4 × 16 拍 = 64 个在途 beat | `:45-47` |
| skid | `SK = 6` ⇒ 64 项分布式 RAM，「64×83 bit」 | `:48`、`:50-54` |

`:45-46` 给的理由与 §3.2 的窗口数字是同一件事：「enough outstanding to cover HP0/DDR read latency and
hold ~1 beat/cycle through the 25-line window」——25 行窗口 = 33 600 像素拍 / 67 200 axi 拍（§3.2）。
另一路读口 `axi_frame_writer64`（`u_aw`，PS 片源）参数未见独立定义，它复用同名端口束
（`pl_video_top.v:692-707`），两路的 mux 见 `:709-714`；`axi_frame_writer64.v` 内部的
`ARLEN/MAX_OUT` 本卷**未证**（没有打开那份文件）。
总线抢占由 `src_arb` 仲裁，`T_OFF_CYC(2_000_000)` @100 MHz = 20 ms 静默才让给 PS
（`pl_video_top.v:421-425` 与 `:417` 的说明）。
6. [资源占用实测读数](#6-资源占用实测读数)

全部现读自 `build/report/utilization.rpt`（`Design: system_top`、`Device: xc7z020clg484-2`、
`Design State: Routed`，见 `:7-10`）。表名用报告自己的编号。

### 6.1「1. Slice Logic」（`:29`）

```
| Slice LUTs                 | 14154 |     0 |          0 |     53200 | 26.61 |   :35
|   LUT as Logic             |  9969 |     0 |          0 |     53200 | 18.74 |   :36
|   LUT as Memory            |  4185 |     0 |          0 |     17400 | 24.05 |   :37
|     LUT as Distributed RAM |  4044 |     0 |            |           |       |   :38
|     LUT as Shift Register  |   141 |     0 |            |           |       |   :39
| Slice Registers            |  8188 |     0 |          0 |    106400 |  7.70 |   :40
| F7 Muxes                   |  1164 |     0 |          0 |     26600 |  4.38 |   :43
| F8 Muxes                   |    85 |     0 |          0 |     13300 |  0.64 |   :44
| Unique Control Sets        |   335 |       |          0 |     13300 |  2.52 |   :45
```

读数要点：**LUT 的一半以上不是逻辑而是存储**——`LUT as Memory 4185` 里 `Distributed RAM 4044`（`:38`），
对应 primitive 表「8. Primitives」的 `| RAMD64E | 4044 |`（`:195`）。这不是意外，是两处刻意为之的
`ram_style = "distributed"`：`axi_frame_saver64.v:48-50`（否则 512×100 bit 变成 5.1 万个 FDRE，
`:11-12` 说它「占整机 Slice Register 的 94%」）与 `axi_frame_writer_gated.v:53-54`（`:50-52` 同样记了
Synth 8-4767 那笔账）。方法论报告把这一族数了出来：`SYNTH-5 Warning Mapped onto distributed RAM
because of timing constraints 336`（`timing_summary.rpt:48`）。

### 6.2「2. Slice Logic Distribution」（`:70`）/「3. Memory」（`:100`）/「4. DSP」（`:115`）

```
| Slice                                      | 5051 | ... | 13300 | 37.98 |   :76
|   SLICEM                                   | 1928 |     |       |       |   :78
| Block RAM Tile                             | 95.5 | ... |   140 | 68.21 |   :106
|   RAMB36/FIFO*                             |   93 | ... |   140 | 66.43 |   :107
|   RAMB18                                   |    5 | ... |   280 |  1.79 |   :109
| DSPs                                       |   19 | ... |   220 |  8.64 |   :121
```

BRAM 是全设计最紧的一格：**95.5 / 140 tile = 68.21%**（`:106`）。注意 `RAMB36/FIFO 93` 但
`Block RAM Tile 95.5` —— 那 2.5 的差来自 `RAMB18 5`（`:109`，5 × 18 bit 拼出 2.5 tile 的等价占用），
`primitives` 表里 `| RAMB18E1 | 5 |`（`:217`）对上。工程里对 BRAM 的唯一一次"预算式"论证是
`pl_video_top.v:779-780`：开第二个逻辑读口「实测把 80 块 BRAM 顶到 160 块，全片才 140」，
所以原图抽头改成走行环（`raw_line_delay`，`:788`）；`:785` 那句「17 位仍在 RAMB36 的 18 位宽度模式里
⇒ BRAM 一块不多要（这句要在 utilization.rpt 上核，不许停在注释）」就是留给本节的作业，
核对结果：环 + `osd_overlay` 的字库 + CDC + 帧缓存合计 95.5 tile，确实没顶到 140。
DSP 只有 19 只（`:121`），用途与 §2.1 的最慢路径一致——`zoom_mapper` 的旋转乘法
（`timing_summary.rpt:934` `DSP48E1/CLK ... u_pl/u_zmap/yr_m_reg/CLK`、`:1195` `u_pl/u_zmap/rot_ys/P[1]`）。

### 6.3「5. IO and GT Specific」（`:126`）与「6. Clocking」（`:155`）

```
| Bonded IOB                  |   27 |    27 |          0 |       200 |  13.50 |   :132
| Bonded IOPADs               |  130 |   130 |          0 |       130 | 100.00 |   :136
| IDELAYCTRL                  |    1 |     0 |          0 |         4 |  25.00 |   :141
| IDELAYE2/IDELAYE2_FINEDELAY |    5 |     5 |          0 |       200 |   2.50 |   :145
| ILOGIC                      |    5 |     5 |          0 |       200 |   2.50 |   :147
| OLOGIC                      |   13 |    13 |          0 |       200 |   6.50 |   :149
|   OSERDES                   |    8 |     8 |          0 |       200 |        |   :151
| BUFGCTRL                    |    8 |     0 |          0 |        32 |  25.00 |   :161
| BUFIO                       |    0 |     0 |          0 |        16 |   0.00 |   :162
| MMCME2_ADV                  |    2 |     0 |          0 |         4 |  50.00 |   :163
| BUFR                        |    0 |     0 |          0 |        16 |   0.00 |   :167
```

三句话读这张表：
1. `Bonded IOPADs 130/130 = 100.00%`（`:136`）——Zynq 的 MIO 环（`FIXED_IO_mio[53:0]`，
   `system_top.v:22`）把 130 个 IOPAD 全占满，这与 PL 侧只剩 27 只 IOB 是两件事，但意味着
   **再加板级信号只能动 DDR 侧或放弃**。
2. `BUFIO 0 / BUFR 0`（`:162`、`:167`）——RGMII 的 125 MHz 走的是 `BUFG`
   （`timing_summary.rpt:392` `BUFGCTRL_X0Y1 ... u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O`），
   这正是 `system_top.v:160-168` 那一大段 IDDELAY tap 算术的起因：「IDDR 与 fabric 同吃 BUFG 之后，
   采样沿往后推 1.683 ns（BUFIO→BUFG 之差）」（`:160-161`），最终 `IDELAY_VALUE(31)`（`:172`）。
3. `ILOGIC 5 / OLOGIC 13`（`:147`、`:149`）里 `IFF_IDDR_Register 5`（`:148`，RGMII 的 4 数据 + 1 控制）
   与 `OUTFF_ODDR_Register 5` + `OSERDES 8`（`:150-151`，TMDS 3 对 + 时钟对），
   `OBUFDS 4`（`:221`）正好是 4 对差分。

### 6.4 与"温度格"有关的一处未证

OSD 有一格片上温度（`pl_video_top.v:195` `wire [7:0] tmp_disp; // V9-6：只给 OSD 的片上温度 BCD`），
而「7. Specific Feature」表里 `| XADC | 0 | ... | 1 | 0.00 |`（`utilization.rpt:184`）——
硬 XADC 没有被例化。温度的真实来源本卷**未证**（需要读 `effect_ctrl.v` / `osd_overlay.v`，
不在本卷预算内）。

7. [ASCII 结构图（数据流 + 时钟域标注）](#7-ascii-结构图数据流--时钟域标注)

```
   时钟/域标注：〔E〕eth_rxc 125 MHz（PHY 恢复钟，Y19） 〔A〕clk_fpga_0 100 MHz（PS FCLK0）
                〔P〕clk_pix 50 MHz = clkout0_1        〔5〕clk_pix5x 250 MHz = clkout1_1
                〔S〕sys_clk 50 MHz（板晶振，W17）      〔2〕clk_200m 200 MHz = clkout2（IDELAY 参考）

 PC(上位机推流) ──UDP:5001──> PHY(RTL8211)
        │ RGMII: RXD[3:0] + RX_CTL @ RXC                     ┌────────────────────────────┐
        ▼                                                     │ PS7 (u_bd)               │
 ┌─────────────────────┐ 〔2〕IDELAYCTRL 参考                │  GP0 ── 3×axi_gpio       │
 │ eth_udp_video_top   │  〔E〕IDDR + BUFG 后的 tap=31       │  HP0 ◄── 64 bit PL 主    │
 │ u_rgmii  4bit nibble│                                     │  DDR 控制器 ──► DDR3     │
 │  → 8bit GMII 字节   │                                     └─────┬───────────▲────────┘
 │ u_rx_mac 自算 FCS   │  〔E〕                                    │ fclk0     │ HP0
 │ u_rx_par 端口过滤   │  〔E〕               system_top.v:83-103  │(100 MHz)  │(读写)
 │ frame_reasm 行环+偏移│──┐                                       ▼           │
 │ dc_fifo 36×8192 BRAM│  │ 〔E〕→〔A〕格雷码指针 CDC             ▼           │
 │ axi_frame_saver64   │  │ (:298-305)   OST=8, AWLEN=0  〔A〕 ┌──────────────┴─────────┐
 │ ddr_bank_commit     │  │  commit_base/pulse 〔A〕 ─────────►│ pl_video_top (u_pl)   │
 └─────────────────────┘  │                                   │                       │
        │ fb_wr_en/addr/data 〔E〕(:239, system_top.v:185-187) │  〔S〕按键/角度/LED    │
        │ eth_gmii_clk ─────────────────────────────────────► │  key_debounce(:136)    │
        ▼                                                     │  angle_ctrl(:183)      │
   DDR: 0x1000_0000 / 0x1008_0000 (ETH 乒乓)  0x1010_0000 (PS) │  clk_gen u_clk (:128) ─┼─► 〔P〕〔5〕〔2〕
        ▲ 写：HP0 从 PL 出     读：HP0 从 PL 出（AR/R）         │       locked → rst_pix_n│
        │                                                     │  〔A〕axi 侧：          │
   link_monitor(320bit 快照,〔E〕) ──snap_cross──> lane0..31    │   src_arb(:421) T_OFF   │
        （system_top.v:202 → :214 → :247 交给 GPIO_1 → PS/JTAG）│   u_row(:454) 16拍×4    │
                                                              │   u_aw (:692) PS 片源   │
  〔A〕owner_eth / row_* / fill_* ──frame_commit_lock(:430)──►  │   frame_latency(:624)   │
                                                              │  〔P〕像素流水线：       │
                                                              │   video_timing_1024x600  │
                                                              │    (:226) 1344×625      │
                                                              │   zoom_fit/ctrl/mapper   │
                                                              │    (:322/:325/:343)     │
                                                              │   fb_bilin 双线性读口    │
                                                              │    (:732) axi 写/P 读   │
                                                              │   raw_line_delay 行环    │
                                                              │    (:788) OFF_LINES 行   │
                                                              │   proc_pipeline 九级效果│
                                                              │    (:800) H_ACTIVE=1024 │
                                                              │   split_display 缝混合   │
                                                              │    (:911) x_d[MIX_D]    │
                                                              │   osd_overlay (:999)    │
                                                              └───────────┬────────────┘
                                                                         │ 〔P〕RGB888+hs/vs/de
                                                                         ▼
                                                              rgb2dvi u_dvi (:1026)
                                                              〔P〕并行 → 〔5〕OSERDES×8
                                                                         │
                                                    tmds_clk_p/n + tmds_data_p[2:0]/n ──► 1024×600 面板
```

数据流一句话总结：**字节进、位出**——`eth_rxc` 域的 4 bit nibble 经 6 级缓冲变成 DDR 里的 64 bit 字，
`clk_fpga_0` 域的搬运机在 V-blank 的 67 200 拍窗口里把 38 400 个字灌进显示帧缓存，
`clk_pix` 域把它读成 16 bit RGB565 像素、过九级效果和 OSD，最后 `clk_pix5x` 域用 8 只 OSERDES
串行成 3 对 TMDS。域之间**只有三处合法握手**：`dc_fifo` 的格雷码指针
（`eth_udp_video_top.v:3` 的链路声明 + `:298` 的实现）、`ddr_bank_commit` 的 3 级同步（`:4` 声明、`:330`）、
以及 `snap_cross` 的 toggle+总线快照（4 处：`system_top.v:214`、`pl_video_top.v:674`、`:876`、`:980`）。
`eth_udp_video_top.v:5-6` 那句「与 axi_clk(HP0 100 MHz) 之间只准过 dc_fifo 的格雷码指针与
ddr_bank_commit 的 3 级同步器，其余一律禁止组合跨域」是这一节的宪法。

8. [总表：每一站的输入格式 → 输出格式](#8-总表每一站的输入格式--输出格式)

沿 §7 那条"字节进、位出"的链，一站一格。域标记同 §7。位宽一律抄模块自己的端口声明。

| 站 | 输入格式 | 输出格式 | 域 | 负责文件 : 行 |
|---|---|---|---|---|
| 0 上位机 UDP 包 | 1 帧 = 307 200 B 的片源，切成 1392 B/包（「一个 1392B 的包在 125MHz 下是连续线速进来的，每包 698 个 16bit 写」） | 同左，落在线路上 | — | `eth_udp_video_top.v:258-260`；字节门 `:235` |
| 1 板级 RGMII | 4 bit 数据 nibble + 1 bit RX_CTL，DDR 时钟 125 MHz（**没有 RX_ER 这根线**） | 同上 | 〔E〕进 | `system_top.v:34-36`；无 RX_ER 的事实记在 `eth_udp_video_top.v:156-157`、`:189` |
| 2 nibble → GMII 字节 | `rgmii_rxd[3:0]`/`rgmii_rx_ctl` 双沿 | `gmii_rxd[7:0]` + `gmii_rx_dv`（DDR 展开成字节） | 〔E〕出，〔2〕做 IDELAY | `gmii_to_rgmii` 例化 `eth_udp_video_top.v:73-79`；tap=31 的定值过程 `system_top.v:160-172`；IDDR/IDELAY 计数 5+1（`utilization.rpt:145-148`） |
| 3 GMII 字节 → MAC 帧 + 边界 | 8 bit 字节流 + dv | `m_data[7:0]`, `m_valid`, `m_sof`, `m_eof`, `m_good`, `m_bad`（FCS-32 **自算**） | 〔E〕 | `gmii_rx_mac` 例化 `eth_udp_video_top.v:186-192`；为什么要自算 `:154-158` |
| 4 帧 → UDP 载荷（端口过滤） | 第 3 站的 6 根 | `p_data[7:0]`, `p_sof/p_eof/p_good`, `p_pay_len[15:0]` + 三个统计位 | 〔E〕 | `udp_rx_parser` 例化 `eth_udp_video_top.v:197-204`，过滤值 `UDP_PORT` 来自 `system_top.v:145` |
| 5 载荷 → **行环**（写口） | 第 4 站的字节对 | `wr_en` + `wr_addr[18:0]` + `wr_data[15:0]`（地址单位 = 一个 16 bit 像素，帧内 153 600 个 ⇒ 19 bit 够） | 〔E〕 | `frame_reasm` 例化 `eth_udp_video_top.v:235-245`；`fb_wr_*` 端口 `:29-31`；19 bit 的下游形状 `system_top.v:128` |
| 6 行环 → CDC FIFO | `{1'b0, addr[18:0], data[15:0]}` = 36 bit（flush 标记借同一槽位 `{1'b1,…}`） | 36 bit × 8192 条 BRAM，异步读写 | 〔E〕写 / 〔A〕读 | 打包式 `eth_udp_video_top.v:264-265`；`dc_fifo #(.DATA_W(36), .ADDR_W(13))` `:298-305`；容量论证 `:295-297` |
| 7 CDC → **DDR 字** | 每 axi 拍取 1 条 36 bit（`fifo_rd <= !fifo_empty && !sv_full;`） | `m_axi_awaddr[31:0]` + `m_axi_wdata[63:0]` + `m_axi_wstrb[7:0]`（按 16 bit lane 生成分段写选通），AWLEN=0/OST=8 | 〔A〕 | 反压读 `eth_udp_video_top.v:312`；`axi_frame_saver64` 例化 `:354-367`；wstrb 说明 `axi_frame_saver64.v:43`、参数 `:40-44`、`:66` |
| 8 提交（乒乓换页） | `frame_done`〔E〕 + `saver_idle`/`cdc_empty`〔A〕 | `ddr_commit_base[31:0]`(=BANK0/BANK1) + `ddr_commit_pulse` | 〔E〕→〔A〕 3 级同步 | `ddr_bank_commit` 例化 `eth_udp_video_top.v:330-350`；两个 bank 常量 `:67-68` |
| 9 DDR → 帧缓存搬运 | `m_axi_araddr[31:0]` + `arlen/arsize/arburst`，AR 在途 4×16 拍 | `fb_wr_en` + `fb_wr_addr[18:0]` + `fb_wr_data[63:0]`（**一拍 4 个像素**），只在消隐窗口落 BRAM | 〔A〕 | `axi_frame_writer_gated` 例化 `pl_video_top.v:454-469`；`PIX_PER_BEAT=4`/`MAX_OUT=4` `axi_frame_writer_gated.v:40-47`；窗口 `pl_video_top.v:397-401`、`:446` |
| 10 64 bit → **像素** | 写侧 64 bit（〔A〕），请求侧 `sx/sy[11:0]` + `fx/fy[7:0]` 小数 | `pix[15:0]` RGB565 + `oob_out`（双线性 4 抽头） | 〔A〕写 / 〔P〕读 | `fb_bilin` 例化 `pl_video_top.v:732-750`；「每源像素用满它天然的 4 个 50 MHz 拍」`:721-722`；地址提前量 `:276-284` |
| 11 原图抽头（行环延时线） | `{oob_raw, pix_raw}` = 17 bit，`de/x/y` 取第 5 级 | 17 bit × `OFF_LINES` 个显示行 | 〔P〕 | `raw_line_delay #(.LINES(u_pipe.OFF_LINES), .W(2*IMG_W), .DW(17))` `pl_video_top.v:781-792`；为什么不开第二个读口 `:779-780` |
| 12 **效果链** | 16 bit 像素 + `stage_sel[8:0]` + `threshold[7:0]` + gamma 4 根 + `hs/vs/de/x/y`（第 3 级抽头） | `pipe_dout[15:0]` + `pipe_de` + `off_rows[7:0]`；栅格是 1024 **显示列** | 〔P〕 | `proc_pipeline #(.H_ACTIVE(2*IMG_W))` `pl_video_top.v:800-810`；深度唯一出处 `u_pipe.LATENCY` `:816`、`MIX_D` `:354`；横向尺度代价自述 `:796-799` |
| 13 缝混合（原图/处理逐像素二选一） | `orig_disp[15:0]` + `proc_pix[15:0]` + `x/y/de/hs/vs`（第 `MIX_D` 级）+ `split_eff[11:0]` + 两个标签 | `r/g/b` 各 **8 bit** + `de_out/hs_out/vs_out` | 〔P〕 | `split_display` `pl_video_top.v:911-928`；执行者 `split_ctrl` `:885-891`；缝标签由流水线推 `SEAM_TAPS` `:902-909`；奇偶对齐凭据 `:819-824` |
| 14 **OSD** | 8 bit ×3 的 `r_in/g_in/b_in` + `hs_in/vs_in` + 17 个状态字（angle/fps/stage/gamma/zoom/split/lat/src/mode/temp）+ `osd_en` | 8 bit ×3 + `de_out/hs_out/vs_out`（`OUT_W=2*IMG_W`, `OUT_H=2*IMG_H`） | 〔P〕 | `osd_overlay` `pl_video_top.v:999-1024`；`fps_q` 来源 `shown_rate` `:941-950`；`lat_ms_pix` 跨域 `:980-987`；`tmp_disp` 来源见 §6.4（未证） |
| 15 **TMDS 串行位** | 8 bit ×3 并行 + 同步，〔P〕50 MHz | 3 对数据 + 1 对时钟的差分串行位，〔5〕250 MHz = 5× 像素钟 | 〔P〕+〔5〕 | `rgb2dvi` `pl_video_top.v:1026-1032`；引脚 `system_top.v:30-33`；5× 算式 `clk_gen.v:24`；硬件计数 `OSERDES 8`/`ODDR 5`/`OBUFDS 4`（`utilization.rpt:151`、`:218`、`:221`） |

三格特别值得停一下：

- 站 6 用 36 bit 里最高那 1 bit 当"这不是数据、是 flush"的标记（`{1'b1, 19'd0, 16'd0}`，
  `eth_udp_video_top.v:265`），下游在 `:315-316` 拆回 `sav_en`/`sav_flush`。整帧字节对齐的
  "最后一拍 4 字节"就是靠这一位穿过 CDC 的（`:328-329` 说明为什么这段 glue 单独成模块）。
- 站 7→9 之间**位宽没有变**（都是 64 bit），但语义变了：写侧一个字 = 4 个像素槽里的**两个**
  16 bit lane（wstrb 按 lane 生成，`axi_frame_saver64.v:43`），读侧一个字 = 4 个像素
  （`PIX_PER_BEAT = 4`，`axi_frame_writer_gated.v:40`）。⇒ 每帧 38 400 个字正好整除
  （`pl_video_top.v:395`、`axi_frame_writer_gated.v:43`），但尾字只填一半的场合由
  `TAIL_GUARD(1'b1)` 兜住（`eth_udp_video_top.v:331`）。
- 站 12 的"一行"是 1024 个**显示列**而不是 512 个源列，`:796-799` 把这笔账写在脸上：
  行缓存宽度翻倍（约 +8 块 BRAM）+ 3×3 滤波的空间尺度从源像素变成显示像素（横向覆盖 1.5 个源列）。
  与 §6.2 的 BRAM 68.21% 读数是同一件事的两端。

---

### 附：本卷引用到的文件（去重）

`src/rtl/top/system_top.v` · `src/rtl/top/pl_video_top.v` · `src/rtl/top/pl_demo_top.v` ·
`src/rtl/eth/eth_udp_video_top.v` · `src/rtl/eth/axi_frame_saver64.v` · `src/rtl/axi/axi_frame_writer_gated.v` ·
`src/rtl/clocks/clk_gen.v` · `src/rtl/video/video_timing_1024x600.v` · `src/rtl/eth/snap_cross.v` ·
`build/report/timing_summary.rpt` · `build/report/utilization.rpt` · `build/check_ports.py` ·
`build/ports_check_width_ce.txt`

**未证清单**（本卷没有打开的文件，因此不给行号）：`axi_frame_writer64.v` 的 `ARLEN/MAX_OUT`；
`rgmii_rx.v` / `gmii_rx_mac.v` / `frame_reasm.v` / `dc_fifo.v` / `ddr_bank_commit.v` 的端口内部实现；
`effect_ctrl.v` 里 `temp_disp` 的产生方式（§6.4）；`video_timing.v` 里 `frame_start` 的确切落拍。


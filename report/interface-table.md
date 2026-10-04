# `report/interface-table.md` —— 端口 / 寄存器 / 时序约定的机器可读表（P13）

生成轮：2026-10-04 无人值守批次（任务号 P13）。**本轮一个源文件都没改**（证据见 §H-4）。

## 0. 本表的口径（先读这一节，否则判据会被误用）

- **权威来源是代码本身**：`src/rtl/**.v`、`src/constraints/*.xdc`、`src/ps/*`、`src/host/*.mjs`。
  文档与本表冲突时**以 RTL 为准**（P13 交付物清单原文："与 RTL 一致，冲突以 RTL 为准"）。
- 每一行的最后一列是**锚点**：一个可以在源码里 `grep` 到的标识符或 `文件:行`。
  §H-2 给出逐行回 grep 的命令与命中率；锚点取不出来的行一律写 `【无锚点】`，不写"略"。
- 表格用竖线分隔（`|`），列顺序固定，便于脚本再解析；单元格里不写散文。
- `位宽` 列的写法照 RTL 原文（`(scalar)` = 1 bit），**不做换算**，避免"表格与代码两套口径"。
- 术语：`悬空` = 实例化时写成 `.name()`（空关联）；`钉值` = 实例化时接常量；
  `孤儿` = RTL 里存在但本表 A–E 的契约层没有语义说明的端口（只在 §F 索引里出现），逐条列在 §G。

---

## A. 顶层端口 ↔ 约束落点（`src/rtl/top/system_top.v`，构建顶层）

顶层身份：`build/tcl/build_system_axigpio.tcl:276` `set_property top system_top [current_fileset]`。
端口声明本体：`src/rtl/top/system_top.v:5-42`（38 个端口对象）。
约束文件（参与本次构建的）：`src/constraints/rk_zynq7020.xdc`（综合+实现）与
`src/constraints/clock_groups_impl.xdc`（仅实现，`build/tcl/build_system_axigpio.tcl:24-26`）。

| 端口 | 方向 | 位宽 | 含义 | 有效条件 / 时序要求 | 约束落点 | 锚点 |
| --- | --- | --- | --- | --- | --- | --- |
| `sys_clk` | input | (scalar) | 板载 50 MHz 有源钟，喂 MMCM 与上电计数器 | 上升沿有效；`create_clock -period 20.000` | `rk_zynq7020.xdc:5`(W17 LVCMOS33) `:6`(clock) | `system_top.v:26` |
| `key1_n` | input | (scalar) | 低有效按键 1（短按=旋转 ±1°，长按 0.6 s=切片源模式） | 异步输入，无建立要求：整脚被排除在时序分析外 | `rk_zynq7020.xdc:8`(W18) `:59`(false_path -from) | `system_top.v:27` |
| `key2_n` | input | (scalar) | 低有效按键 2 | 同上 | `rk_zynq7020.xdc:9`(V14) `:60`(false_path -from) | `system_top.v:28` |
| `led` | output | [1:0] | `led[0]`=心跳/拷贝超窗快闪；`led[1]`=长按计时与翻转态 | clk_pix 域寄存输出，无对外时序窗 | `rk_zynq7020.xdc:10`(V15) `:11`(V13) | `pl_video_top.v:1039` `:1042` |
| `tmds_clk_p` | output | (scalar) | HDMI 时钟对 P | TMDS_33；源端窗是**候选件未进发布约束集**（§G-6） | `rk_zynq7020.xdc:12`(W16 TMDS_33) | `system_top.v:30` |
| `tmds_clk_n` | output | (scalar) | HDMI 时钟对 N | 同上 | `rk_zynq7020.xdc:13`(Y16) | `system_top.v:31` |
| `tmds_data_p` | output | [2:0] | B/G/R 三对 TMDS 数据 P（位 0=B、1=G、2=R） | 250 MHz 并串（`clk_pix5x`），与钟的 skew 判据见候选件 | `rk_zynq7020.xdc:14,16,18` | `system_top.v:32` |
| `tmds_data_n` | output | [2:0] | 同上 N 侧 | 同上 | `rk_zynq7020.xdc:15,17,19` | `system_top.v:33` |
| `eth_rxc` | input | (scalar) | RGMII 收时钟 125 MHz（PHY 恢复出来的） | `create_clock -period 8.000` + `set_clock_uncertainty -hold 0.800` | `rk_zynq7020.xdc:20`(Y19) `:36` `:50` | `system_top.v:34` |
| `eth_rx_ctl` | input | (scalar) | RGMII DV（本设计当 `gmii_rx_dv` 用；板上没有 RX_ER 这根线） | 与 `eth_rxc` 同域；无 ER ⇒ 收侧错误源由 FCS 自算 | `rk_zynq7020.xdc:21`(V19) | `system_top.v:35` `gmii_rx_mac.v:5-7` |
| `eth_rxd` | input | [3:0] | RGMII 收数据 nibble | 125 MHz DDR 采样（IDDR + IDELAY，tap 取值见 §B-3） | `rk_zynq7020.xdc:22-25` | `system_top.v:36` |
| `eth_tx_clk` | output | (scalar) | RGMII 发时钟（与收侧同一根 125 MHz） | 输出，被排除在时序分析外 | `rk_zynq7020.xdc:26`(AB22) `:56` | `system_top.v:37` `eth_udp_video_top.v:5` |
| `eth_tx_ctl` | output | (scalar) | RGMII EN | 同上 | `rk_zynq7020.xdc:27`(AB21) `:57` | `system_top.v:38` |
| `eth_txd` | output | [3:0] | RGMII 发数据 nibble | 同上 | `rk_zynq7020.xdc:28-31` `:58`(通配) | `system_top.v:39` |
| `eth_mdc` | output | (scalar) | **钉 0**：数据面不碰 MDIO，PHY 模式由板 strap 定 | 常量驱动；综合报 `Synth 8-3917` 是陈述不是缺陷 | `rk_zynq7020.xdc:32`(AB20) | `system_top.v:117` |
| `eth_mdio` | inout | (scalar) | **高阻**，同上 | 无驱动无接收 | `rk_zynq7020.xdc:33`(AB19) | `system_top.v:116` |
| `eth_rst_n` | output | (scalar) | PHY 复位（低有效），由上电计数器给 | `phy_rst_cnt[23]` ⇒ 约 2^24 个 sys_clk 拍后释放 | `rk_zynq7020.xdc:34`(Y21) `:55`(false_path -to) | `system_top.v:108-112` |
| `DDR_*`（15 个端口对象） | inout | 见 `system_top.v:5-19` | PS7 的 DDR3 外部引脚，PL 逻辑不碰 | **不在任何 .xdc 里**（机械检查：`grep -rn 'DDR_\|FIXED_IO' src/constraints/` 命中 0 行）⇒ 由 PS7 IP 的 BD 约束与 `apply_board_preset "0"` 负责 | 无（互联自动分配） | `system_top.v:5-19` `build_system_axigpio.tcl:76` |
| `FIXED_IO_*`（6 个端口对象） | inout | 见 `system_top.v:20-25` | PS7 的 MIO/电源/POR/SRST 引脚 | 同上（0 条 .xdc 命中） | 无（互联自动分配） | `system_top.v:20-25` |

小结（数字由 `grep` 现算，见 §H-2）：38 个顶层端口对象里 **17 个落在 .xdc 上有引脚/时序**，
**21 个（DDR_* 与 FIXED_IO_*）在 .xdc 里完全没有落点**，走 PS7 IP 的约束路径。

---

## B. 一级实例接线（`system_top` 内部，5 个实例）

| 实例 | 模块 | 定义文件:行 | 例化文件:行 | 时钟/复位归属 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `u_bd` | `design_1_wrapper` | **工具产物**，不在 `src/`（`vivado_system/zynq_video_sys.gen/sources_1/bd/design_1/hdl/design_1_wrapper.v`） | `system_top.v:75-104` | 产生 `fclk0`=100 MHz、`fclk0_rst_n` | PS7 + AXI GPIO×3 + HP0；再生成方式见 `report/src-map.md` §3 |
| `u_idelay_clkgen` | `clk_gen` | `src/rtl/clocks/clk_gen.v:4` | `system_top.v:121-125` | `clk_in(sys_clk)`、`rst_n(1'b1)` | 顶层**只用 `clk_200m`**（IDELAY 参考钟）；两个 `clk_pix*` 输出接空线 |
| `u_eth` | `eth_udp_video_top` | `src/rtl/eth/eth_udp_video_top.v:7` | `system_top.v:154-204` | `rgmii_rxc`(125 MHz) / `axi_clk=fclk0` / `idelay_clk=clk_200m`；`rst_n = eth_rst_n & mmcm_locked` | UDP 视频接收面，写 DDR 走 HP0 |
| `u_lm_axi` | `snap_cross` | `src/rtl/eth/snap_cross.v:13` | `system_top.v:214-218` | 目的域 `fclk0` | 320 bit 健康快照 + 心跳跨到 PS 侧 |
| `u_pl` | `pl_video_top` | `src/rtl/top/pl_video_top.v:8` | `system_top.v:258-321` | `sys_clk` + `fclk0`，内部再派生 `clk_pix`/`clk_pix5x` | 显示通路全部 |

### B-1 顶层钉值与不接清单（`system_top` 这一层）

| 被接对象 | 怎么接的 | 文件:行 | 为什么这样接（读到的原文理由） |
| --- | --- | --- | --- |
| `u_bd.M_AXI_HP0_arcache/awcache` | 钉 `4'b0011` | `system_top.v:89,94` | HP0 端口属性常量 |
| `u_bd.M_AXI_HP0_arlock/awlock` | 钉 `2'b00` | `system_top.v:90,95` | 非独占 |
| `u_bd.M_AXI_HP0_arprot/awprot` | 钉 `3'b000` | `system_top.v:91,96` | 未用保护属性 |
| `u_bd.M_AXI_HP0_arqos/awqos` | 钉 `4'b0000` | `system_top.v:91,96` | 未用 QoS |
| `u_bd.M_AXI_HP0_awid/wid` | 钉 `6'd0` | `system_top.v:95,102` | 单一 ID |
| `u_bd.M_AXI_HP0_bid` / `M_AXI_HP0_bresp` | **悬空**（`.()`） | `system_top.v:99` | BRESP 未检查：见 §G-1 的 O1 |
| `u_pl.sys_rst_n` | 钉 `1'b1` | `system_top.v:260` | 上电复位交给 `locked`（`pl_video_top.v:132` `rst_pix_n = sys_rst_n & locked`）；`sim/tb_v113_key_powup.v:5,36` 把这条当"真接线"台架基准 |
| `u_eth.gapclr_sel` | `gpio_o[26]` | `system_top.v:203` | 准静态电平，帧间隔统计归零 |
| `u_pl.stat_*` 一组（`u_eth.stat_frames/pkts/bytes/bad`） | **悬空** ×4 | `system_top.v:200-201` | 原文理由：这四口原来送进 `pl_video_top` 用两级触发器跨 16 位总线，同步值没有读者；计数的正路是 `link_monitor → snap_cross` 的 lane1/8/9（注释点名 ISSUES #64）。端口本身保留是因为一批台架直接读它们（`system_top.v:130-133`） |
| `clk_gen.clk_pix/clk_pix5x` | 接到空线 `clk_pix_unused`/`clk_pix5x_unused` | `system_top.v:119-124` | 顶层这份 MMCM 只为 IDELAY 供 200 MHz；显示钟由 `u_pl` 内部第二份 `clk_gen` 产生（`pl_video_top.v:128`） |

### B-2 跨顶层共用的控制字（同一根线在两个顶层的接法必须一致）

| 端口（`pl_video_top`） | `system_top` 里的来源 | `pl_demo_top` 里的来源 | 锚点 |
| --- | --- | --- | --- |
| `stage_sel[8:0]` | `gpio_cfg1_o[8:0]` | 常量 `9'd1`（gray only） | `system_top.v:264` / `pl_demo_top.v:16,27` |
| `threshold[7:0]` | `gpio_o[15:8]` | 常量 `8'd80` | `system_top.v:264` / `pl_demo_top.v:17` |
| `bilin_en_axi` | `gpio_o[19]` | 钉 `1'b1`（无 PS ⇒ 与 localparam 默认同行为） | `system_top.v:286` / `pl_demo_top.v:34` |
| `osd_off_axi` | `gpio_o[20]`（**反相**） | 钉 `1'b0` = OSD 常显 | `system_top.v:287` / `pl_demo_top.v:35` |
| `split_ctl[18:0]` | 由 `gpio_cfg1_o` 的 [31]/[12:10]/[9]/[30]/[25:23]/[22:13] 拼成 | 常量 `19'd0`（位宽必须跟着端口走，原文警告见注释） | `system_top.v:274-275` / `pl_demo_top.v:38-41` |
| `gamma_ctl[31:0]` | `gpio_cfg2_o`（axi_gpio_2 通道 2，+0x08） | 常量 `32'd0` = 逐位旁路 | `system_top.v:276` / `pl_demo_top.v:79-84` |
| `m_axi_*`（读 DDR 那 12 口） | 接 `u_bd.M_AXI_HP0_*` | 输出全悬空、输入钉 0（纯 PL 演示没有 DDR 片源） | `system_top.v:298-302` / `pl_demo_top.v:51-63` |

### B-3 `u_eth` 的参数取值（唯一有实测曲线支撑的那个）

| 参数 | 顶层取值 | 定义处的默认 | 取值依据（读到的原文） | 锚点 |
| --- | --- | --- | --- | --- |
| `IMG_W` / `IMG_H` | `16'd512` / `16'd300` | `512` / `300` | localparam 单点定义，避免两棵例化各写一遍字面量 | `system_top.v:136-137,155` |
| `BASE_ADDR` | `32'h1000_0000` | `32'h1000_0000` | ETH 的乒乓两 bank 之第一块 | `system_top.v:139,156` `eth_udp_video_top.v:67-68` |
| `UDP_PORT` | `16'd5001` | `16'd5001` | PC 推流目的端口，收侧过滤用同一个常数 | `system_top.v:145` `eth_udp_video_top.v:11` |
| `BOARD_MAC` | `48'h00_11_22_33_44_55` | 同值 | —（旁边无出处文档，登记 `【取值依据待补】`，见 `docs/src-audit.md（未写）` A-7） | `system_top.v:158` `eth_udp_video_top.v:12` |
| `BOARD_IP` | `{8'd192,8'd168,8'd1,8'd10}` | 同值 | 上位机侧的 DES_IP 是 `.102`（`eth_udp_video_top.v:118`）⇒ 两条一起看 | `system_top.v:159` |
| `IDELAY_VALUE` | `31`（默认 15） | `15` | 原文给了实测扫描曲线与交点算法，并声明"这一族在 0~31 全范围内都关不掉" | `system_top.v:160-172` `eth_udp_video_top.v:14` |

---

## C. PS ↔ PL 寄存器表（AXI GPIO @ GP0 从端口）

三个基址由构建脚本钉死并回读校验（`build/tcl/build_system_axigpio.tcl:228-253`）；
固件里的宏必须等于它（`src/ps/main.c:48,77`）。JTAG 侧读法见 `src/host/health_read.mjs:34-35`（默认 `41200000`/`41210000`）。

| 基址 | BD 实例 | 引出的外部端口 | 位宽/方向 | RTL 侧消费者 | 锚点 |
| --- | --- | --- | --- | --- | --- |
| `0x41200000` | `axi_gpio_0` | `GPIO_0_tri_o` → `gpio_o` | 32 输出 | `system_top` 的 PS 控制字 | `build_system_axigpio.tcl:211,232` `system_top.v:84` |
| `0x41200000 + 0x00` | 同上（`GPIO_DATA`） | — | 32 写 | 同上 | `main.c:49` |
| `0x41200000 + 0x04` | 同上（`GPIO_TRI`） | — | 32 写 | 固件上电写 `0x00000000`（全输出） | `main.c:50` `main.c:1551` |
| `0x41210000` | `axi_gpio_1` | `GPIO_1_tri_i` → `gpio1_i` | 32 **只读** | PL 侧 `lm_rd` 多路选择 | `build_system_axigpio.tcl:212,233` `system_top.v:85,247` |
| `0x41220000` | `axi_gpio_2`（双通道） | `GPIO_2_tri_o`/`GPIO_3_tri_o` → `gpio_cfg1_o`/`gpio_cfg2_o` | 2×32 输出 | 几何/效果控制字 + gamma 窗口 | `build_system_axigpio.tcl:213-214,234` `system_top.v:86-87` |
| `0x41220000 + 0x00` | 通道 1 = `CFG_DATA0` | — | 32 写 | 同一个字里既有 `stage_sel` 又有缩放/几何位 | `main.c:77-78` `system_top.v:264-275` |
| `0x41220000 + 0x08` | 通道 2 = `CFG_DATA1` | — | 32 写 | gamma 表窗口 | `main.c:96` `system_top.v:276` |

### C-1 `0x41200000` 的位域（`gpio_o`）

| 位 | 名称 | RTL 落点 | PS 侧宏 | 时序性质 | 锚点 |
| --- | --- | --- | --- | --- | --- |
| `[4:0]` | **保留、不接**（V7 五位 effect_en 已随 #66 退役） | `pl_video_top` 无此入口 | 写 0 | 准静态 | `system_top.v:262-263` `main.c:5-7` |
| `[15:8]` | `threshold` | `.threshold(gpio_o[15:8])` | `cur_thr`（默认 80） | 经 `effect_ctrl` 同步链 | `system_top.v:264` `main.c:171` |
| `[16]` | `src_sel` | `.src_sel(gpio_o[16])` | `cur_src` | 同上 | `system_top.v:264` `main.c:170` |
| `[17]` | `zoom_en` | `.zoom_en(gpio_o[17])` | `cur_zoom` | 3 级 ASYNC_REG（`ze0..ze2`） | `system_top.v:280` `pl_video_top.v:212-219` |
| `[18]` | `ps_publish`（翻转一次 = 请求搬一帧） | `.ps_publish(gpio_o[18])` | `PUBLISH_BIT 18u` | 翻转位跨域（脉冲跨域会被吃掉） | `system_top.v:288` `main.c:51` `pl_video_top.v:55-57` |
| `[19]` | `bilin_en` | `.bilin_en_axi(gpio_o[19])` | `BILIN_BIT 19u` | 准静态电平，独立 3 级链 | `system_top.v:286` `main.c:52` |
| `[20]` | `osd_off`（**反相**：1 = 关叠层） | `.osd_off_axi(gpio_o[20])` | `OSD_OFF_BIT 20u` | 准静态 | `system_top.v:287` `main.c:57` |
| `[21]`、`[25]` | 保留 | 无 | 无 | — | `main.c:11` |
| `[22]` | `mode_ovr_tog` | `.mode_ovr_tog(gpio_o[22])` | `MODE_TOG_BIT 22u` | 翻转位 | `system_top.v:293` `main.c:63` |
| `[24:23]` | `mode_ovr`（00 自动/01 ETH/11 SD/10 TEST） | `.mode_ovr(gpio_o[24:23])` | `MODE_CODE_BIT 23u` + `MODE_*` | 码先稳定再翻位（先后由 `main.c` 保证） | `system_top.v:293` `main.c:64-68` |
| `[26]` | `gapclr_sel` | `.gapclr_sel(gpio_o[26])` | — | 进 125 MHz 域前 3FF | `system_top.v:203` `eth_udp_video_top.v:277` |
| `[31:27]` | 健康 lane 号 | `lm_lane = gpio_o[31:27]` | — | axi 域组合选择 | `system_top.v:219` |

### C-2 `0x41220000 + 0x00`（`CFG_DATA0` = `gpio_cfg1_o`）的位域

| 位 | 名称 | RTL 落点 | PS 侧宏 | 锚点 |
| --- | --- | --- | --- | --- |
| `[8:0]` | `stage_sel`（九级效果，一位一级） | `.stage_sel(gpio_cfg1_o[8:0])` | `SEL_GRAY`…`SEL_DILATE`（`1u<<0`…`1u<<8`） | `system_top.v:264` `main.c:110-118` |
| `[9]` | `rot_auto` | `split_ctl` 拼接的第 4 位 | `ROT_AUTO_BIT (1u<<9)` | `system_top.v:274-275` `main.c:155` |
| `[12:10]` | `rot_speed`（度/帧） | 同上 | `ROT_SPEED_SHIFT 10u` | `system_top.v:274` `main.c:156-157` |
| `[22:13]` | 缝位 `[9:0]`/`auto_en`/`follow`/`swap` | 同上 | `SPLIT_POS_SHIFT 13u`、`SPLIT_AUTO/FOLLOW/SWAP_BIT` | `system_top.v:275` `main.c:123-139` |
| `[25:23]` | 三个缝旗标 | 同上 | — | `system_top.v:275` |
| `[28:26]` | `zoom_sel_async`（八档） | `.zoom_sel_async(gpio_cfg1_o[28:26])` | `cur_zsel`（默认 4 = 1.00x） | `system_top.v:268` `main.c:183` |
| `[29]` | `zoom_manual_async` | `.zoom_manual_async(gpio_cfg1_o[29])` | `cur_zman`（默认 1） | `system_top.v:268` `main.c:189` |
| `[30]` | `marker_off` | `split_ctl` 拼接 | `SPLIT_MARKOFF_BIT (1u<<30)` | `system_top.v:275` `main.c:140` |
| `[31]` | `zoom_fit` | `split_ctl` 最高位 | `ZOOM_FIT_BIT (1u<<31)` | `system_top.v:274` `main.c:158` |

`split_ctl` 的位序（RTL 侧口径，19 位一起过同一条 `snap_cross`）：`[9:0]=pos_px、[10]=auto_en、
[11]=follow、[12]=swap、[13]=marker_off、[14]=rot_auto、[17:15]=rot_speed、[18]=zoom_fit`。
锚点：`pl_video_top.v:48-54`。

### C-3 `0x41220000 + 0x08`（`CFG_DATA1` = `gpio_cfg2_o` = `gamma_ctl`）的位域

| 位 | 名称 | 锚点 |
| --- | --- | --- |
| `[31]` | `GM_EN`（gamma 级使能） | `main.c:97` `pl_video_top.v:32-34` |
| `[30]` | `GM_WR`（写表脉冲） | `main.c:98` |
| `[29:22]` | `GM_DATA(v)`（表项数据） | `main.c:99` |
| `[21:14]` | `GM_IDX(i)`（表项下标） | `main.c:100` |
| `[13:8]` | `GM_DISP`（屏上 gamma 格，6 bit） | `main.c:101-102` |
| `[7:0]` | `GM_TEMP`（两位十进制 BCD；`0xFF` = 画 `--`） | `main.c:104-106` |

写序要求（原文）：先摆地址与数据、`wr` 不动，再同字置 `wr` 一拍 —— 见 `main.c:368,371`（两次 `Xil_Out32(CFG_DATA1, …)`）。

### C-4 DDR 地址约定（PL 与 PS 必须同数）

| 地址 | 用途 | RTL 出处 | PS 出处 | 锚点 |
| --- | --- | --- | --- | --- |
| `0x1000_0000` | ETH 乒乓 bank0 | `BANK0 = BASE_ADDR` | —（不写） | `eth_udp_video_top.v:67` `system_top.v:139` |
| `0x1008_0000` | ETH 乒乓 bank1（+512 KB） | `BANK1 = BASE_ADDR + 32'h0008_0000` | — | `eth_udp_video_top.v:68` |
| `0x1010_0000` | PS 片源专用第三 bank（SD 回放 / FILL） | `PS_DDR_BASE` / `PS_BASE_ADDR` | `FRAME_ADDR`（两处各一份） | `system_top.v:140-144` `pl_video_top.v:16` `main.c:46` `sd_play.c:35` |
| 一帧字节数 | 307200 = 512×300×2（RGB565） | `FRAME_BYTES` 参数（顶层传 `IMG_W*IMG_H*2`） | `FRAME_BYTES (512u*300u*2u)` | `frame_reasm.v:11` `eth_udp_video_top.v:235` `main.c:40` `sd_play.c:34` |

原文风险声明（照抄条件句，不改写）：**改这里不改那边 ⇒ 现象是"PS 片源在屏上不动"**（`system_top.v:142-143`）。

---

## D. 健康回读 lane 表（`0x41210000`，32 bit 只读）

写法（原文）：先用 `gpio_o[31:27]` 选 lane，再从 `GPIO_1` 读那一条 32 bit。锚点：`system_top.v:206-208,219,247`。

| lane | 内容 | 产生位置 | 锚点 |
| --- | --- | --- | --- |
| 0 | `drop_words` 丢字总数（自启动以来） | `link_monitor` | `link_monitor.v:187` |
| 1 | `{err16, bad16}` 高 16=坏包、低 16=作废帧 | 同上 | `link_monitor.v:188` |
| 2 | `{rows_miss_max, stall_ms}` 高 16=最大缺行、低 16=已断流 ms | 同上 | `link_monitor.v:189` |
| 3 | `{16'd0, gap_last}` 最近一帧间隔（ms） | 同上 | `link_monitor.v:190` |
| 4 | `{gap_max, gap_min}`（ms） | 同上 | `link_monitor.v:191` |
| 5 | `gap_sum`（Σ间隔，均值 = lane5/(frames_ok−1)） | 同上 | `link_monitor.v:192` |
| 6 | `{16'd0, ep16}` CDC 灌满次数 | 同上 | `link_monitor.v:193` |
| 7 | `{27'd0, flag5}` 标志位（**bit3 = eth_live**，判据 `stall_ms < 200`） | 同上 / `system_top.v:251,255` | `link_monitor.v:194` |
| 8 | `in_pkts` 收到的包数 | 同上 | `link_monitor.v:195` |
| 9 | `in_bytes` 收到的有效字节 | 同上 | `link_monitor.v:196` |
| 10–22 | `32'hDEAD_BEEF`（哨兵：让脚本一眼看出自己写错了号） | 顶层组合选择 | `system_top.v:244` |
| 23 | `dbg_zoom`：像素域在用的缩放状态（位序唯一出处 = `pl_video_top` 文件尾 `assign dbg_zoom` 上方注释） | `pl_video_top.v:78` `:674-686` | `system_top.v:241` |
| 24 | `dbg_lat[5*32 +: 32]` = `q_ms`（与 `q_tot` 同一轮） | `pl_video_top` | `system_top.v:230-231,240` |
| 25 | `dbg_lat[0*32 +: 32]` = `{n_meas, clamped}`，**同时是这一组五字的武装位** | 同上 | `system_top.v:232-236` |
| 26–29 | `dbg_lat[(N-25)*32 +: 32]` = max / tot / c2 / c1（等消隐、搬运、提交→上屏） | 同上 | `system_top.v:229-231,242-243` `pl_video_top.v:69-72` |
| 30 | `{16'd0, dbg_src}`：`bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy bit4=row_busy bit[6:5]=模式(格雷码) bit[10:8]=why_ps` | `pl_video_top.v:62-68` | `system_top.v:239` |
| 31 | `{30'd0, lm_clk_slow, lm_clk_gone}`：bit0=源时钟没有、bit1=源时钟被拉慢（拔线时 RXC≈2.5 MHz ⇒ 只有 bit1 会亮） | `snap_cross` 输出 | `system_top.v:209-211,238` |

读序硬要求（原文）：lane25→26→27→28→29 必须按这个顺序读，因为 25 既是"轮次/钳位位"也是武装位；
`src/host/health_read.mjs` 的 want 列表就是这个顺序（`system_top.v:232-234`）。
位宽硬要求：`dbg_src` 的线宽必须与端口一模一样（r54 起 16 bit）；曾写过 `[5:0]` ⇒ 综合只给一条
`Synth 8-689` 警告就静默丢掉模式高位（`system_top.v:224-226`，门禁第 14 项 `build/check_ports.py` 拦这一族）。

---

## E. 时钟 / 复位 / 跨域约定

### E-1 时钟名册

| 名字 | 频率/周期 | 来源 | 域内干什么 | 锚点 |
| --- | --- | --- | --- | --- |
| `sys_clk` | 20.000 ns（50 MHz） | 板载有源钟，`create_clock` | 顶层上电计数器、`clk_gen` 输入、按键消抖 | `rk_zynq7020.xdc:6` `system_top.v:26,109` |
| `clk_pix` | 50 MHz | MMCM `CLKOUT0_DIVIDE_F=20.000`（VCO 1000 MHz） | 显示通路单域（时序/效果/OSD/TMDS 并侧） | `clk_gen.v:19,21` `pl_video_top.v:126-132` |
| `clk_pix5x` | 250 MHz | `CLKOUT1_DIVIDE=4` | TMDS 并串（OSERDES） | `clk_gen.v:24` `pl_video_top.v:126` |
| `clk_200m` | 200 MHz | `CLKOUT2_DIVIDE=5` | IDELAY 参考钟（156.25 ps/拍） | `clk_gen.v:27` `system_top.v:120-124` `system_top.v:162`(156 ps/拍) |
| `eth_rxc` | 8.000 ns（125 MHz） | PHY 恢复时钟，`create_clock` | 整个 ETH 协议栈 + `frame_reasm` | `rk_zynq7020.xdc:36` `system_top.v:34` |
| `fclk0`(`clk_fpga_0`) | 100 MHz | PS7 FCLK0，BD 端口声明 `-freq_hz 100000000` | 全部 AXI 事务与 GPIO | `build_system_axigpio.tcl:194` `system_top.v:83` |
| 面板 | 1024×600 @ ≈59.5 Hz | `H: 1024+44+88+188=1344`、`V: 600+3+6+16=625` @ 50 MHz | 显示扫描 | `video_timing_1024x600.v:2-4` `pl_video_top.v:226-229` |

### E-2 复位归属

| 复位 | 极性 | 产生 | 消费者 | 锚点 |
| --- | --- | --- | --- | --- |
| `fclk0_rst_n` | 低有效 | BD 端口 `FCLK_RESET0_N`，`CONFIG.POLARITY ACTIVE_LOW` | AXI 侧全部（`axi_rst_n`） | `build_system_axigpio.tcl:196-197` `system_top.v:83` |
| `eth_rst_n` | 低有效 | `phy_rst_cnt[23]`（`sys_clk` 域计数器） | `u_eth.rst_n = eth_rst_n & mmcm_locked` | `system_top.v:108-112,175` |
| `rst_pix_n` | 低有效 | `sys_rst_n & locked`（顶层把 `sys_rst_n` 钉 `1'b1`） | 像素域全部 | `pl_video_top.v:132` `system_top.v:260` |
| 上电无 PS 复位 | — | `pl_demo_top` 两个 `rst_n` 都钉 `1'b1`（纯 PL 树没有 PS） | 演示顶层 | `pl_demo_top.v:24,26` |

### E-3 跨域机制（结构保证，不靠时序分析）

| 路径 | 机制 | 锚点 |
| --- | --- | --- |
| `eth_rxc → clk_fpga_0` 视频流 | `dc_fifo`：格雷码指针 + 2FF + BRAM | `clock_groups_impl.xdc:26` `dc_fifo.v:19-20` |
| `eth_rxc → clk_fpga_0` 帧事件 | 翻转 + 3 级同步边沿检测 | `clock_groups_impl.xdc:27` `ddr_bank_commit.v` |
| `clk_pix → clk_fpga_0` 消隐窗 | 3 级像素 + 3FF | `clock_groups_impl.xdc:28` `frame_commit_lock.v` |
| `clk_fpga_0 → clk_pix` 控制字 | 3FF（`effect_ctrl` / `src_*`） | `clock_groups_impl.xdc:29` `pl_video_top.v:212-219` |
| 准静态宽总线 + 心跳 | `snap_cross`（总线整拍写好 + 同拍翻 toggle，目的域 3 级后采样） | `snap_cross.v:2-8` `system_top.v:214-218` |
| 125 MHz 域内电平（`gapclr_sel`） | 3FF `(* ASYNC_REG = "TRUE" *)` 后当电平用，**不是脉冲** | `eth_udp_video_top.v:274-278` |

### E-4 时序约束条文（本表只登记"哪条约束管哪个对象"，不重述推导）

| 条文 | 对象 | 文件:行 | 备注（读到的原文要点） |
| --- | --- | --- | --- |
| `create_clock -period 20.000 sys_clk` | `sys_clk` | `rk_zynq7020.xdc:6` | — |
| `create_clock -period 8.000 eth_rxc` | `eth_rxc` | `rk_zynq7020.xdc:36` | — |
| `set_clock_uncertainty -hold 0.800` | 只取 `eth_rxc` 一个对象 | `rk_zynq7020.xdc:50` | 原文：这是**加**要求不是放松；把取不到的名字并进同一条命令会让整条空转（`:43-46`） |
| `set_false_path -to eth_rst_n` | 输出脚 | `rk_zynq7020.xdc:55` | 原先 `-from` 版本每次都报 `Constraints 18-513` 空约束，已删（`:51-54`） |
| `set_false_path -to eth_tx_clk / tx_ctl / txd[*]` | RGMII 输出侧 | `rk_zynq7020.xdc:56-58` | — |
| `set_false_path -from key1_n / key2_n` | 按键 | `rk_zynq7020.xdc:59-60` | — |
| `set_clock_groups -asynchronous`（三组） | `eth_rxc` / `clk_fpga_0` / `sys_clk` + 全部生成钟 | `clock_groups_impl.xdc:33-36` | 必须带 `-include_generated_clocks`，否则 `clk_pix` 被当独立钟与 `eth_rxc` 做 setup ⇒ 历史上 WNS≈−6.7 的假违例（`:16-20`） |
| `BITSTREAM.GENERAL.COMPRESS TRUE` | 设计属性 | `rk_zynq7020.xdc:77` | — |
| `CFGBVS / CONFIG_VOLTAGE` | `current_design` | `rk_zynq7020.xdc:2-3` | 3.3 V |

`clk_pix` 与 `clk_pix5x` **有意留在同一组内**（同 MMCM、5:1、0°），让 TMDS 并串按同步路径分析
（`clock_groups_impl.xdc:31-33`）。

### E-5 AXI 事务约定（PL 是主、HP0 是从）

| 约定 | 当前取值 | 风险（原文/机械检查所得） | 锚点 |
| --- | --- | --- | --- |
| HP0 是 **AXI3** 接口，`ARLEN`/`AWLEN` 在 BD 侧只有 4 bit | 顶层把 PL 的 8 bit 长度截成 4 bit：`m_awlen_axi3 = m_awlen[3:0]`、`assign m_arlen_axi3 = m_arlen8[3:0]` | 当前所有 burst 都是 `8'd15`（16 拍）或 `8'd0`（1 拍）⇒ 截断无损；**但没有任何守卫**：一旦哪个模块给出 >16 拍的 burst，4 bit 会静默回绕（§G-2 的 O-9） | `system_top.v:54,73,106` `axi_frame_writer64.v:50,72,101,107` `axi_frame_writer_gated.v:132,150` `axi_frame_saver64.v:40` |
| 写侧 `AWSIZE`/`BURST` | `saver64` 固定 `awlen=8'd0`（单拍）、`wstrb=8'h03`、`awburst=2'b01`(INCR) | — | `axi_frame_saver.v:29-32` |
| 读侧 `ARSIZE` | `writer64` 用 64 bit 拍，`PIX_PER_B = 4`（RGB565×4） | `PIX_PER_B`/`BEATS` 旁边无出处注释 ⇒ `【取值依据待补】` | `axi_frame_writer64.v:36-37` |
| `ARID`/`AWID`/`WID` | 钉 `6'd0` | 单一 ID 假设：`RID` 未检查（`bid` 悬空） | `system_top.v:95,102` |

---

## G. 孤儿 / 悬空清单（RTL 里有、契约层没有语义说明的）

口径：**悬空 = 实例化处写成空关联 `.name()`**；机械筛命令与命中数见 §H-3。
本仓库现有 51 行含空关联、共 57 处空关联。下面按"为什么悬空"分类，每一条都给 `文件:行`。

### G-1 顶层故意不接（有原文理由的）

| # | 端口（所属模块方向） | 悬空处 | 为什么悬空（读到的原文） | 是否算问题 |
| --- | --- | --- | --- | --- |
| O-1 | `design_1_wrapper` 的 `M_AXI_HP0_bid` / `M_AXI_HP0_bresp`（输出） | `system_top.v:99` | 只与本设计的读回包一起看：B 通道只取 `bvalid/bready`。**本表登记为风险**：响应码从未被检查 ⇒ 写失败在 PL 侧不可见 | 是（`docs/src-audit.md（未写）` A-9） |
| O-2 | `eth_udp_video_top` 的 `stat_frames/stat_pkts/stat_bytes/stat_bad`（输出） | `system_top.v:200-201` | 原文（`:130-133`）：这四个口原来在 `pl_video_top` 里用两级触发器跨 16 位总线，而同步值没有读者；数的正路是 `link_monitor → snap_cross` 的 lane1/8/9（ISSUES #64）。端口留着是因为 `tb_v50_rows / tb_v6_* / tb_udp_reasm / tb_link_monitor` 直接读它们 | 否（有据） |
| O-3 | `clk_gen` 的 `clk_pix` / `clk_pix5x`（输出，顶层那份实例） | `system_top.v:119-124` | 顶层这份 MMCM 只为了 IDELAY 的 200 MHz 参考；显示钟来自 `u_pl` 内部第二份 `clk_gen` | 否（有据）；但"两份 MMCM"这件事契约头里应写明 → A-6 |
| O-4 | `pl_demo_top` 的 `m_axi_araddr/arid/arlen/arsize/arburst/arvalid/rready/status`（输出） | `pl_demo_top.v:51-57,63,86` | 纯 PL 演示顶层没有 PS/DDR：读口整组留空，输入侧钉 0（`:57-73`） | 否（有据） |
| O-5 | `ddr_bank_commit` 的 `switch_req` / `force_flush`（输出） | `eth_udp_video_top.v:348-349` | 本文件与 commit 生产者同层，两个请求口在本设计里**没有执行者**（bank 切换由 commit 脉冲自己决定）。原文没有写"为什么不接"，因此登记为悬空无据 | 是（A-10） |
| O-6 | `axi_frame_saver64` 的 `busy`（输出） | `eth_udp_video_top.v:359` | 同一实例的 `idle` 已接出去并被 `ddr_bank_commit` 消费（`:340-345`），`busy` 无人读 | 是（低危，A-10） |
| O-7 | `eth_ctrl` 的 `arp_tx_type` / `icmp_tx_data` / `udp_tx_data`（输出） | `eth_udp_video_top.v:209,214,218` | 这三个是"控制面发送侧"的并行数据口；同一层的 `udp_rec_data/udp_rec_en` 注释原话："这条 rec 转发路径本设计无人消费；接真字节而不是硬 0"（`:219-220`）—— 三个 tx 口**没有**这样的说明 | 是（A-10） |
| O-8 | `sync_fifo`(u_icmp_fifo) 的 `full` / `empty` / `level`（输出） | `eth_udp_video_top.v:122` | 溢出与水位没有被任何判据消费 ⇒ 队列满时静默丢字节 | 是（A-11） |
| O-9 | `axi_frame_writer64`(u_aw) 的 `copy_cycles`（输出） | `pl_video_top.v:706` | 拷贝拍数已另有 lane24–29 的时延快照（`system_top.v:229-231`），这个逐实例计数无读者 | 否（有据） |
| O-10 | `snap_cross` 的 `hb_slow` / `hb_gone`（输出，PL 内三份实例） | `pl_video_top.v:677,879,984` | 原文（`:671-673`）：`SLOW_MS` 那一档不接出去，因为模块里 5 ms 门限是给 1 ms 心跳（eth_rxc）定的，帧心跳本来就是 16.7 ms，硬接只会常亮一位没意义的慢标志 | 否（有据） |
| O-11 | `key_debounce`(u_k2) 的 `key_stable`（输出） | `pl_video_top.v:140` | 第二路按键只要脉冲，不要电平 | 否 |

### G-2 器件原语（Vivado 实例模板）的未用输出

`clk_gen.v:36-47`（`MMCME2_BASE` 的 `CLKFBOUTB/CLKOUT0B/1B/2B/3/3B/4/5/6`，9 处）、
`rgmii_rx.v:60,72,113`（`RDY`/`CNTVALUEOUT`，3 处）、
`tmds_serializer.v:24-30,62-68`（`OFB/OQ/SHIFTOUT1/2/TBYTEOUT/TFB/TQ`，11 处）。
共 23 处空关联集中在原语实例上（机械核对：`grep -c` 见 §H-3）。
判定：**不算可读性问题**（这些是 Vivado 实例模板里必须写出的可选输出，接出来反而多出无读者的网络），
但 P13 铁律 2 的契约头里应写"未处理情形：原语未用输出留空"，本轮未加（B1 决定）。

### G-3 当前源码树里没有被例化的模块（`src/rtl/` 内）

机械口径：**模块名作为"行首例化名"在 `src/rtl/**/*.v` 里出现 0 次**（排除自身定义行与注释行）。
命令与输出在 §H-5。

| 模块 | 定义文件 | `sim/` 里有例化吗 | 去向判定 |
| --- | --- | --- | --- |
| `axi_frame_writer` | `src/rtl/axi/axi_frame_writer.v` | 否 | 64 bit 版（`axi_frame_writer64`）的 32 bit 前身；三处都没有引用 ⇒ 唯一"可考虑删"的一档，**本轮不删**（P13 铁律 1：不许顺手删） |
| `frame_buffer` | `src/rtl/video/frame_buffer.v` | 否 | 被 `frame_buffer_w64` 取代（`fb_bilin.v:65` 用 w64 版） |
| `frame_buffer_db` | `src/rtl/video/frame_buffer_db.v` | 否 | 同上 |
| `axi_frame_saver` | `src/rtl/eth/axi_frame_saver.v` | 否 | 被 `axi_frame_saver64` 取代（`eth_udp_video_top.v:354`，注释原话"v5.0: use saver64"） |
| `axi_frame_saver_burst` | `src/rtl/eth/axi_frame_saver_burst.v` | 是（`sim/tb_v5_saver.v:17`） | 只在台架里活着 |
| `udp_rx` | `src/rtl/eth/udp_rx.v` | 是（`sim/tb_eth_video.v:37`） | 被 `udp_rx_parser` 取代（在用的一版见 `eth_udp_video_top.v:200` 附近） |
| `fb_rd5x` | `src/rtl/process/bilin/fb_rd5x.v` | 是（`sim/tb_fb_rd5x.v:29`） | 5×5 抽头读口，台架在验、RTL 树里无人接 |
| `rotate_mapper` | `src/rtl/process/rotate/rotate_mapper.v` | 是 | 旋转映射的旧几何（默认 640×360，与当前 512×300 不符） |
| `color_bar` | `src/rtl/video/color_bar.v` | 是 | `pl_demo_top.v:2` 的注释说演示 = colorbar + 旋转，但当前 `pl_demo_top` 文件里**没有** `color_bar` 实例（`grep -rn 'color_bar' src/rtl` 只命中定义文件）⇒ 注释与接线不一致，登记 A-12 |
| `line_cache` | `src/rtl/video/line_cache.v` | 否 | 行缓存的旧实现 |
| `video_timing_720p` | `src/rtl/video/video_timing_720p.v` | 否 | 720p 分辨率备选 |
| `pl_demo_top` / `system_top` | 两个顶层 | 否（`sim/*.v` 里只在注释中提到） | 顶层由 Vivado 构建设置选：`build/tcl/build_system_axigpio.tcl:276` = `system_top`、`build/tcl/build_pl_full.tcl:19` = `pl_demo_top` ⇒ 两棵树并存是有意的 |

交叉核对：`bash build/orphan_rtl.sh build/evidence_r75/r75_build_console.txt` 用综合日志当 oracle，
报 14 个名字（其中 12 个与本表一致，`pl_demo_top`/`shown_rate`/`tap_sched`/`icmp_*` 的差集是因为
r75 那一版的源码与今天不同、且该脚本的"台架引用"列按 `grep -lw` 统计）。
**该日志是 2026-09-27 的 r75 构建，不是本轮实测** ⇒ 只当旁证，本轮不做可达性结论（`NOT_MEASURED`）。

### G-4 未被任何构建脚本引用的约束文件（`src/constraints/`）

机械口径：`grep -rl '<文件名>' build --include='*.tcl' --include='*.sh' --include='*.mjs' --include='*.py'` 命中 0。

| 文件 | 行数 | 状态 | 锚点 |
| --- | --- | --- | --- |
| `src/constraints/r114_io_varianta_rise_only.xdc` | 69 | 没有任何构建脚本引用 | §H-6 输出 |
| `src/constraints/r114_io_variantb_phy_delay.xdc` | 69 | 同上 | 同上 |
| `src/constraints/r115_io_window_candidate.xdc` | 46 | 同上 | 同上 |
| `src/constraints/r119b_hdmi_tp1_pinclk.xdc` | 26 | 同上，且**未入库**（`git status --porcelain` 里是 `??`） | 同上 |

在用的：`rk_zynq7020.xdc`（15 处引用）、`clock_groups_impl.xdc`、`r116_rgmii_input_window.xdc`
（受 `VP_R116_IO_WINDOW=1` 开关，默认不加载：`build_system_axigpio.tcl:44-52`）、
`r119_hdmi_source_window.xdc`（受 `VP_R119_TMDS_WINDOW=1`，默认不加载：`:63-70`，且**未入库**）、
`r114_io_async.xdc`（只被 `build/tcl/r114_io_roll*.tcl` / `r114_idelay_sweep.tcl` 这类实验脚本加载）。

---

## F. 全模块端口索引（机器生成，覆盖 `src/rtl` 的 80 个模块）

这一节不是手写的，是下面这条命令的输出（awk 程序正文存在 `report/src-map.md` §4，逐字照抄即可复跑）。
口径：只取 module 头里 `module` 行 → 端口表闭合的 `);` 之间的方向声明；模块体内的 `task` 形参不算。
列序 = `模块|定义文件|声明行|方向|端口名|位宽`。

```
$ awk -f pidx.awk $(find src/rtl -name '*.v' | sort)      # pidx.awk 正文见 report/src-map.md §4
```

```
#MOD axi_frame_writer src/rtl/axi/axi_frame_writer.v 5
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|10|input|clk|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|11|input|rst_n|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|12|input|enable|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|13|input|frame_start|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|14|output|frame_busy|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|15|output|frame_done|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|16|output|fb_wr_en|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|17|output|fb_wr_addr|[18:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|18|output|fb_wr_data|[15:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|19|output|m_axi_araddr|[31:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|20|output|m_axi_arlen|[7:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|21|output|m_axi_arsize|[2:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|22|output|m_axi_arburst|[1:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|23|output|m_axi_arvalid|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|24|input|m_axi_arready|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|25|input|m_axi_rdata|[63:0]
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|26|input|m_axi_rlast|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|27|input|m_axi_rvalid|(scalar)
axi_frame_writer|src/rtl/axi/axi_frame_writer.v|28|output|m_axi_rready|(scalar)
#MOD axi_frame_writer64 src/rtl/axi/axi_frame_writer64.v 4
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|9|input|clk|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|10|input|rst_n|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|11|input|enable|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|12|input|frame_start|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|13|input|base_addr|[31:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|14|output|frame_busy|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|15|output|frame_done|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|17|output|fb_wr_en|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|18|output|fb_wr_addr|[18:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|19|output|fb_wr_data|[63:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|21|output|m_axi_araddr|[31:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|22|output|m_axi_arlen|[7:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|23|output|m_axi_arsize|[2:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|24|output|m_axi_arburst|[1:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|25|output|m_axi_arvalid|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|26|input|m_axi_arready|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|27|input|m_axi_rdata|[63:0]
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|28|input|m_axi_rlast|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|29|input|m_axi_rvalid|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|30|output|m_axi_rready|(scalar)
axi_frame_writer64|src/rtl/axi/axi_frame_writer64.v|31|output|copy_cycles|[31:0]
#MOD axi_frame_writer_gated src/rtl/axi/axi_frame_writer_gated.v 8
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|13|input|clk|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|14|input|rst_n|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|15|input|enable|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|16|input|start|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|17|input|base_addr|[31:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|18|input|allow_wr|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|19|input|abort|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|20|output|busy|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|21|output|done|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|22|output|fb_wr_en|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|23|output|fb_wr_addr|[18:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|24|output|fb_wr_data|[63:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|25|output|m_axi_araddr|[31:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|26|output|m_axi_arlen|[7:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|27|output|m_axi_arsize|[2:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|28|output|m_axi_arburst|[1:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|29|output|m_axi_arvalid|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|30|input|m_axi_arready|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|31|input|m_axi_rdata|[63:0]
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|32|input|m_axi_rlast|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|33|input|m_axi_rvalid|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|34|output|m_axi_rready|(scalar)
axi_frame_writer_gated|src/rtl/axi/axi_frame_writer_gated.v|35|output|copy_cycles|[31:0]
#MOD clk_gen src/rtl/clocks/clk_gen.v 4
clk_gen|src/rtl/clocks/clk_gen.v|5|input|clk_in|(scalar)
clk_gen|src/rtl/clocks/clk_gen.v|6|input|rst_n|(scalar)
clk_gen|src/rtl/clocks/clk_gen.v|7|output|clk_pix|(scalar)
clk_gen|src/rtl/clocks/clk_gen.v|8|output|clk_pix5x|(scalar)
clk_gen|src/rtl/clocks/clk_gen.v|9|output|clk_200m|(scalar)
clk_gen|src/rtl/clocks/clk_gen.v|10|output|locked|(scalar)
#MOD arp src/rtl/eth/arp.v 4
arp|src/rtl/eth/arp.v|5|input|rst_n|(scalar)
arp|src/rtl/eth/arp.v|7|input|gmii_rx_clk|(scalar)
arp|src/rtl/eth/arp.v|8|input|gmii_rx_dv|(scalar)
arp|src/rtl/eth/arp.v|9|input|gmii_rxd|[7:0]
arp|src/rtl/eth/arp.v|10|input|gmii_tx_clk|(scalar)
arp|src/rtl/eth/arp.v|11|output|gmii_tx_en|(scalar)
arp|src/rtl/eth/arp.v|12|output|gmii_txd|[7:0]
arp|src/rtl/eth/arp.v|15|output|arp_rx_done|(scalar)
arp|src/rtl/eth/arp.v|16|output|arp_rx_type|(scalar)
arp|src/rtl/eth/arp.v|17|output|src_mac|[47:0]
arp|src/rtl/eth/arp.v|18|output|src_ip|[31:0]
arp|src/rtl/eth/arp.v|19|input|arp_tx_en|(scalar)
arp|src/rtl/eth/arp.v|20|input|arp_tx_type|(scalar)
arp|src/rtl/eth/arp.v|21|input|des_mac|[47:0]
arp|src/rtl/eth/arp.v|22|input|des_ip|[31:0]
arp|src/rtl/eth/arp.v|23|output|tx_done|(scalar)
#MOD arp_rx src/rtl/eth/arp_rx.v 6
arp_rx|src/rtl/eth/arp_rx.v|12|input|clk|(scalar)
arp_rx|src/rtl/eth/arp_rx.v|13|input|rst_n|(scalar)
arp_rx|src/rtl/eth/arp_rx.v|15|input|gmii_rx_dv|(scalar)
arp_rx|src/rtl/eth/arp_rx.v|16|input|gmii_rxd|[ 7:0]
arp_rx|src/rtl/eth/arp_rx.v|17|output|arp_rx_done|(scalar)
arp_rx|src/rtl/eth/arp_rx.v|18|output|arp_rx_type|(scalar)
arp_rx|src/rtl/eth/arp_rx.v|19|output|src_mac|[47:0]
arp_rx|src/rtl/eth/arp_rx.v|20|output|src_ip|[31:0]
#MOD arp_tx src/rtl/eth/arp_tx.v 6
arp_tx|src/rtl/eth/arp_tx.v|7|input|clk|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|8|input|rst_n|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|10|input|arp_tx_en|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|11|input|arp_tx_type|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|12|input|des_mac|[47:0]
arp_tx|src/rtl/eth/arp_tx.v|13|input|des_ip|[31:0]
arp_tx|src/rtl/eth/arp_tx.v|14|input|crc_data|[31:0]
arp_tx|src/rtl/eth/arp_tx.v|15|input|crc_next|[ 7:0]
arp_tx|src/rtl/eth/arp_tx.v|16|output|tx_done|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|17|output|gmii_tx_en|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|18|output|gmii_txd|[ 7:0]
arp_tx|src/rtl/eth/arp_tx.v|19|output|crc_en|(scalar)
arp_tx|src/rtl/eth/arp_tx.v|20|output|crc_clr|(scalar)
#MOD axi_frame_saver src/rtl/eth/axi_frame_saver.v 4
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|7|input|clk|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|8|input|rst_n|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|9|input|enable|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|10|input|wr_en|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|11|input|wr_addr|[18:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|12|input|wr_data|[15:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|13|output|busy|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|15|output|m_axi_awaddr|[31:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|16|output|m_axi_awlen|[7:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|17|output|m_axi_awsize|[2:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|18|output|m_axi_awburst|[1:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|19|output|m_axi_awvalid|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|20|input|m_axi_awready|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|21|output|m_axi_wdata|[63:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|22|output|m_axi_wstrb|[7:0]
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|23|output|m_axi_wlast|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|24|output|m_axi_wvalid|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|25|input|m_axi_wready|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|26|input|m_axi_bvalid|(scalar)
axi_frame_saver|src/rtl/eth/axi_frame_saver.v|27|output|m_axi_bready|(scalar)
#MOD axi_frame_saver64 src/rtl/eth/axi_frame_saver64.v 8
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|15|input|clk|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|16|input|rst_n|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|17|input|enable|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|18|input|base_addr|[31:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|19|input|wr_en|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|20|input|wr_addr|[18:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|21|input|wr_data|[15:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|22|input|flush|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|23|output|fifo_full|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|24|output|idle|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|25|output|busy|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|26|output|m_axi_awaddr|[31:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|27|output|m_axi_awlen|[7:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|28|output|m_axi_awsize|[2:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|29|output|m_axi_awburst|[1:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|30|output|m_axi_awvalid|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|31|input|m_axi_awready|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|32|output|m_axi_wdata|[63:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|33|output|m_axi_wstrb|[7:0]
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|34|output|m_axi_wlast|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|35|output|m_axi_wvalid|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|36|input|m_axi_wready|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|37|input|m_axi_bvalid|(scalar)
axi_frame_saver64|src/rtl/eth/axi_frame_saver64.v|38|output|m_axi_bready|(scalar)
#MOD axi_frame_saver_burst src/rtl/eth/axi_frame_saver_burst.v 4
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|7|input|clk|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|8|input|rst_n|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|9|input|enable|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|10|input|base_addr|[31:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|11|input|wr_en|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|12|input|wr_addr|[18:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|13|input|wr_data|[15:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|14|input|flush|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|15|output|fifo_full|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|16|output|idle|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|17|output|busy|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|18|output|m_axi_awaddr|[31:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|19|output|m_axi_awlen|[7:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|20|output|m_axi_awsize|[2:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|21|output|m_axi_awburst|[1:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|22|output|m_axi_awvalid|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|23|input|m_axi_awready|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|24|output|m_axi_wdata|[63:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|25|output|m_axi_wstrb|[7:0]
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|26|output|m_axi_wlast|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|27|output|m_axi_wvalid|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|28|input|m_axi_wready|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|29|input|m_axi_bvalid|(scalar)
axi_frame_saver_burst|src/rtl/eth/axi_frame_saver_burst.v|30|output|m_axi_bready|(scalar)
#MOD crc32_d8 src/rtl/eth/crc32_d8.v 5
crc32_d8|src/rtl/eth/crc32_d8.v|6|input|clk|(scalar)
crc32_d8|src/rtl/eth/crc32_d8.v|7|input|rst_n|(scalar)
crc32_d8|src/rtl/eth/crc32_d8.v|8|input|data|[ 7:0]
crc32_d8|src/rtl/eth/crc32_d8.v|9|input|crc_en|(scalar)
crc32_d8|src/rtl/eth/crc32_d8.v|10|input|crc_clr|(scalar)
crc32_d8|src/rtl/eth/crc32_d8.v|11|output|crc_data|[31:0]
crc32_d8|src/rtl/eth/crc32_d8.v|12|output|crc_next|[31:0]
#MOD dc_fifo src/rtl/eth/dc_fifo.v 3
dc_fifo|src/rtl/eth/dc_fifo.v|7|input|wr_clk|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|8|input|wr_rst_n|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|9|input|wr_en|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|10|input|wr_data|[DATA_W-1:0]
dc_fifo|src/rtl/eth/dc_fifo.v|11|output|wr_full|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|13|input|rd_clk|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|14|input|rd_rst_n|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|15|input|rd_en|(scalar)
dc_fifo|src/rtl/eth/dc_fifo.v|16|output|rd_data|[DATA_W-1:0]
dc_fifo|src/rtl/eth/dc_fifo.v|17|output|rd_empty|(scalar)
#MOD ddr_bank_commit src/rtl/eth/ddr_bank_commit.v 8
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|13|input|gmii_clk|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|14|input|axi_clk|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|15|input|rst_n|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|16|input|axi_rst_n|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|18|input|frame_done|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|20|input|saver_idle|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|21|output|sav_base|[31:0]
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|22|output|pack_flush|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|25|input|cdc_empty|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|26|input|cdc_rd|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|27|input|cdc_d1_v|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|28|input|sav_en|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|29|input|sav_flush|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|31|output|completed_base|[31:0]
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|32|output|commit_pulse|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|33|output|switch_req|(scalar)
ddr_bank_commit|src/rtl/eth/ddr_bank_commit.v|34|output|force_flush|(scalar)
#MOD eth_ctrl src/rtl/eth/eth_ctrl.v 6
eth_ctrl|src/rtl/eth/eth_ctrl.v|7|input|clk|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|8|input|rst_n|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|10|input|arp_rx_done|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|11|input|arp_rx_type|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|12|output|arp_tx_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|13|output|arp_tx_type|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|14|input|arp_tx_done|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|15|input|arp_gmii_tx_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|16|input|arp_gmii_txd|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|18|input|icmp_tx_start_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|19|input|icmp_tx_done|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|20|input|icmp_gmii_tx_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|21|input|icmp_gmii_txd|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|23|input|icmp_rec_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|24|input|icmp_rec_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|25|input|icmp_tx_req|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|26|output|icmp_tx_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|28|input|udp_tx_start_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|29|input|udp_tx_done|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|30|input|udp_gmii_tx_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|31|input|udp_gmii_txd|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|33|input|udp_rec_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|34|input|udp_rec_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|35|input|udp_tx_req|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|36|output|udp_tx_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|38|input|tx_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|39|output|tx_req|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|40|output|rec_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|41|output|rec_data|[7:0]
eth_ctrl|src/rtl/eth/eth_ctrl.v|43|output|gmii_tx_en|(scalar)
eth_ctrl|src/rtl/eth/eth_ctrl.v|44|output|gmii_txd|[7:0]
#MOD eth_udp_video_top src/rtl/eth/eth_udp_video_top.v 7
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|16|input|rgmii_rxc|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|17|input|rst_n|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|18|input|axi_clk|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|19|input|axi_rst_n|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|20|input|idelay_clk|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|21|input|copy_hold|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|23|input|rgmii_rx_ctl|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|24|input|rgmii_rxd|[3:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|25|output|rgmii_tx_clk|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|26|output|rgmii_tx_ctl|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|27|output|rgmii_txd|[3:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|29|output|fb_wr_en|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|30|output|fb_wr_addr|[18:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|31|output|fb_wr_data|[15:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|32|output|frame_done|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|33|output|link_active|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|34|output|eth_gmii_clk|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|36|output|ddr_commit_base|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|37|output|ddr_commit_pulse|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|39|output|m_axi_awaddr|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|40|output|m_axi_awlen|[7:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|41|output|m_axi_awsize|[2:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|42|output|m_axi_awburst|[1:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|43|output|m_axi_awvalid|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|44|input|m_axi_awready|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|45|output|m_axi_wdata|[63:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|46|output|m_axi_wstrb|[7:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|47|output|m_axi_wlast|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|48|output|m_axi_wvalid|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|49|input|m_axi_wready|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|50|input|m_axi_bvalid|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|51|output|m_axi_bready|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|53|output|stat_frames|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|54|output|stat_pkts|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|55|output|stat_bytes|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|56|output|stat_bad|[31:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|60|output|lm_bus|[319:0]
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|61|output|lm_bus_tog|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|62|output|lm_hb|(scalar)
eth_udp_video_top|src/rtl/eth/eth_udp_video_top.v|65|input|gapclr_sel|(scalar)
#MOD frame_reasm src/rtl/eth/frame_reasm.v 8
frame_reasm|src/rtl/eth/frame_reasm.v|13|input|clk|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|14|input|rst_n|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|15|input|p_data|[7:0]
frame_reasm|src/rtl/eth/frame_reasm.v|16|input|p_valid|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|17|input|p_sof|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|18|input|p_eof|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|19|input|p_good|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|20|output|wr_en|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|21|output|wr_addr|[18:0]
frame_reasm|src/rtl/eth/frame_reasm.v|22|output|wr_data|[15:0]
frame_reasm|src/rtl/eth/frame_reasm.v|23|output|flush|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|24|output|frame_done|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|25|output|frame_err|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|29|output|frame_abort|(scalar)
frame_reasm|src/rtl/eth/frame_reasm.v|30|output|rows_missed|[15:0]
frame_reasm|src/rtl/eth/frame_reasm.v|31|output|stat_frames|[31:0]
frame_reasm|src/rtl/eth/frame_reasm.v|32|output|stat_pkts|[31:0]
frame_reasm|src/rtl/eth/frame_reasm.v|33|output|stat_bytes|[31:0]
frame_reasm|src/rtl/eth/frame_reasm.v|34|output|stat_bad|[31:0]
frame_reasm|src/rtl/eth/frame_reasm.v|35|output|stat_oob_off|[31:0]
#MOD gmii_rx_mac src/rtl/eth/gmii_rx_mac.v 8
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|9|input|clk|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|10|input|rst_n|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|11|input|gmii_rxd|[7:0]
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|12|input|gmii_rx_dv|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|13|input|gmii_rx_er|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|14|output|m_data|[7:0]
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|15|output|m_valid|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|16|output|m_sof|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|17|output|m_eof|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|18|output|m_good|(scalar)
gmii_rx_mac|src/rtl/eth/gmii_rx_mac.v|19|output|m_bad|(scalar)
#MOD gmii_to_rgmii src/rtl/eth/gmii_to_rgmii.v 4
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|5|input|idelay_clk|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|7|output|gmii_rx_clk|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|8|output|gmii_rx_dv|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|9|output|gmii_rxd|[7:0]
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|10|output|gmii_tx_clk|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|11|input|gmii_tx_en|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|12|input|gmii_txd|[7:0]
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|14|input|rgmii_rxc|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|15|input|rgmii_rx_ctl|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|16|input|rgmii_rxd|[3:0]
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|17|output|rgmii_txc|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|18|output|rgmii_tx_ctl|(scalar)
gmii_to_rgmii|src/rtl/eth/gmii_to_rgmii.v|19|output|rgmii_txd|[3:0]
#MOD icmp src/rtl/eth/icmp.v 6
icmp|src/rtl/eth/icmp.v|8|input|rst_n|(scalar)
icmp|src/rtl/eth/icmp.v|10|input|gmii_rx_clk|(scalar)
icmp|src/rtl/eth/icmp.v|11|input|gmii_rx_dv|(scalar)
icmp|src/rtl/eth/icmp.v|12|input|gmii_rxd|[7:0]
icmp|src/rtl/eth/icmp.v|13|input|gmii_tx_clk|(scalar)
icmp|src/rtl/eth/icmp.v|14|output|gmii_tx_en|(scalar)
icmp|src/rtl/eth/icmp.v|15|output|gmii_txd|[7:0]
icmp|src/rtl/eth/icmp.v|17|output|rec_pkt_done|(scalar)
icmp|src/rtl/eth/icmp.v|18|output|rec_en|(scalar)
icmp|src/rtl/eth/icmp.v|19|output|rec_data|[ 7:0]
icmp|src/rtl/eth/icmp.v|20|output|rec_byte_num|[15:0]
icmp|src/rtl/eth/icmp.v|21|input|tx_start_en|(scalar)
icmp|src/rtl/eth/icmp.v|22|input|tx_data|[ 7:0]
icmp|src/rtl/eth/icmp.v|23|input|tx_byte_num|[15:0]
icmp|src/rtl/eth/icmp.v|24|input|des_mac|[47:0]
icmp|src/rtl/eth/icmp.v|25|input|des_ip|[31:0]
icmp|src/rtl/eth/icmp.v|26|output|tx_done|(scalar)
icmp|src/rtl/eth/icmp.v|27|output|tx_req|(scalar)
#MOD icmp_rx src/rtl/eth/icmp_rx.v 7
icmp_rx|src/rtl/eth/icmp_rx.v|8|input|clk|(scalar)
icmp_rx|src/rtl/eth/icmp_rx.v|9|input|rst_n|(scalar)
icmp_rx|src/rtl/eth/icmp_rx.v|11|input|gmii_rx_dv|(scalar)
icmp_rx|src/rtl/eth/icmp_rx.v|12|input|gmii_rxd|[ 7:0]
icmp_rx|src/rtl/eth/icmp_rx.v|13|output|rec_pkt_done|(scalar)
icmp_rx|src/rtl/eth/icmp_rx.v|14|output|rec_en|(scalar)
icmp_rx|src/rtl/eth/icmp_rx.v|15|output|rec_data|[ 7:0]
icmp_rx|src/rtl/eth/icmp_rx.v|16|output|rec_byte_num|[15:0]
icmp_rx|src/rtl/eth/icmp_rx.v|18|output|icmp_id|[15:0]
icmp_rx|src/rtl/eth/icmp_rx.v|19|output|icmp_seq|[15:0]
icmp_rx|src/rtl/eth/icmp_rx.v|20|output|reply_checksum|[31:0]
#MOD icmp_tx src/rtl/eth/icmp_tx.v 8
icmp_tx|src/rtl/eth/icmp_tx.v|9|input|clk|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|10|input|rst_n|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|12|input|reply_checksum|[31:0]
icmp_tx|src/rtl/eth/icmp_tx.v|13|input|icmp_id|[15:0]
icmp_tx|src/rtl/eth/icmp_tx.v|14|input|icmp_seq|[15:0]
icmp_tx|src/rtl/eth/icmp_tx.v|15|input|tx_start_en|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|16|input|tx_data|[ 7:0]
icmp_tx|src/rtl/eth/icmp_tx.v|17|input|tx_byte_num|[15:0]
icmp_tx|src/rtl/eth/icmp_tx.v|18|input|des_mac|[47:0]
icmp_tx|src/rtl/eth/icmp_tx.v|19|input|des_ip|[31:0]
icmp_tx|src/rtl/eth/icmp_tx.v|20|input|crc_data|[31:0]
icmp_tx|src/rtl/eth/icmp_tx.v|21|input|crc_next|[ 7:0]
icmp_tx|src/rtl/eth/icmp_tx.v|22|output|tx_done|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|23|output|tx_req|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|24|output|gmii_tx_en|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|25|output|gmii_txd|[ 7:0]
icmp_tx|src/rtl/eth/icmp_tx.v|26|output|crc_en|(scalar)
icmp_tx|src/rtl/eth/icmp_tx.v|27|output|crc_clr|(scalar)
#MOD link_monitor src/rtl/eth/link_monitor.v 8
link_monitor|src/rtl/eth/link_monitor.v|15|input|clk|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|16|input|rst_n|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|19|input|cdc_wr_req|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|20|input|cdc_full|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|21|input|frame_done|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|22|input|frame_abort|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|23|input|frame_err|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|26|input|gapclr|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|27|input|rows_missed|[15:0]
link_monitor|src/rtl/eth/link_monitor.v|28|input|in_pkts|[31:0]
link_monitor|src/rtl/eth/link_monitor.v|29|input|in_bytes|[31:0]
link_monitor|src/rtl/eth/link_monitor.v|32|output|lm_bus|[319:0]
link_monitor|src/rtl/eth/link_monitor.v|33|output|lm_bus_tog|(scalar)
link_monitor|src/rtl/eth/link_monitor.v|34|output|lm_hb|(scalar)
#MOD rgmii_rx src/rtl/eth/rgmii_rx.v 24
rgmii_rx|src/rtl/eth/rgmii_rx.v|25|input|idelay_clk|(scalar)
rgmii_rx|src/rtl/eth/rgmii_rx.v|28|input|rgmii_rxc|(scalar)
rgmii_rx|src/rtl/eth/rgmii_rx.v|29|input|rgmii_rx_ctl|(scalar)
rgmii_rx|src/rtl/eth/rgmii_rx.v|30|input|rgmii_rxd|[3:0]
rgmii_rx|src/rtl/eth/rgmii_rx.v|33|output|gmii_rx_clk|(scalar)
rgmii_rx|src/rtl/eth/rgmii_rx.v|34|output|gmii_rx_dv|(scalar)
rgmii_rx|src/rtl/eth/rgmii_rx.v|35|output|gmii_rxd|[7:0]
#MOD rgmii_tx src/rtl/eth/rgmii_tx.v 4
rgmii_tx|src/rtl/eth/rgmii_tx.v|6|input|gmii_tx_clk|(scalar)
rgmii_tx|src/rtl/eth/rgmii_tx.v|7|input|gmii_tx_en|(scalar)
rgmii_tx|src/rtl/eth/rgmii_tx.v|8|input|gmii_txd|[7:0]
rgmii_tx|src/rtl/eth/rgmii_tx.v|11|output|rgmii_txc|(scalar)
rgmii_tx|src/rtl/eth/rgmii_tx.v|12|output|rgmii_tx_ctl|(scalar)
rgmii_tx|src/rtl/eth/rgmii_tx.v|13|output|rgmii_txd|[3:0]
#MOD snap_cross src/rtl/eth/snap_cross.v 8
snap_cross|src/rtl/eth/snap_cross.v|14|input|dst_clk|(scalar)
snap_cross|src/rtl/eth/snap_cross.v|15|input|dst_rst_n|(scalar)
snap_cross|src/rtl/eth/snap_cross.v|16|input|bus|[W-1:0]
snap_cross|src/rtl/eth/snap_cross.v|17|input|bus_tog|(scalar)
snap_cross|src/rtl/eth/snap_cross.v|18|input|hb_tog|(scalar)
snap_cross|src/rtl/eth/snap_cross.v|19|output|bus_q|[W-1:0]
snap_cross|src/rtl/eth/snap_cross.v|29|output|hb_gone|(scalar)
snap_cross|src/rtl/eth/snap_cross.v|30|output|hb_slow|(scalar)
#MOD sync_fifo src/rtl/eth/sync_fifo.v 5
sync_fifo|src/rtl/eth/sync_fifo.v|9|input|clk|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|10|input|rst_n|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|11|input|wr_en|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|12|input|wr_data|[DATA_W-1:0]
sync_fifo|src/rtl/eth/sync_fifo.v|13|output|full|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|14|input|rd_en|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|15|output|rd_data|[DATA_W-1:0]
sync_fifo|src/rtl/eth/sync_fifo.v|16|output|empty|(scalar)
sync_fifo|src/rtl/eth/sync_fifo.v|17|output|level|[ADDR_W:0]
#MOD udp_rx src/rtl/eth/udp_rx.v 8
udp_rx|src/rtl/eth/udp_rx.v|9|input|clk|(scalar)
udp_rx|src/rtl/eth/udp_rx.v|10|input|rst_n|(scalar)
udp_rx|src/rtl/eth/udp_rx.v|12|input|gmii_rx_dv|(scalar)
udp_rx|src/rtl/eth/udp_rx.v|13|input|gmii_rxd|[  7:0]
udp_rx|src/rtl/eth/udp_rx.v|14|output|rec_pkt_done|(scalar)
udp_rx|src/rtl/eth/udp_rx.v|15|output|rec_en|(scalar)
udp_rx|src/rtl/eth/udp_rx.v|16|output|rec_data|[7 : 0]
udp_rx|src/rtl/eth/udp_rx.v|17|output|rec_byte_num|[ 15:0]
#MOD udp_rx_parser src/rtl/eth/udp_rx_parser.v 4
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|7|input|clk|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|8|input|rst_n|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|9|input|s_data|[7:0]
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|10|input|s_valid|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|11|input|s_sof|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|12|input|s_eof|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|13|input|s_good|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|14|input|s_bad|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|15|output|p_data|[7:0]
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|16|output|p_valid|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|17|output|p_sof|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|18|output|p_eof|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|19|output|p_good|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|20|output|pay_len|[15:0]
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|21|output|stat_drop_bad|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|22|output|stat_drop_filt|(scalar)
udp_rx_parser|src/rtl/eth/udp_rx_parser.v|23|output|stat_udp_ok|(scalar)
#MOD udp_tx src/rtl/eth/udp_tx.v 7
udp_tx|src/rtl/eth/udp_tx.v|8|input|clk|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|9|input|rst_n|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|11|input|tx_start_en|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|12|input|tx_data|[ 7:0]
udp_tx|src/rtl/eth/udp_tx.v|13|input|tx_byte_num|[15:0]
udp_tx|src/rtl/eth/udp_tx.v|14|input|des_mac|[47:0]
udp_tx|src/rtl/eth/udp_tx.v|15|input|des_ip|[31:0]
udp_tx|src/rtl/eth/udp_tx.v|16|input|crc_data|[31:0]
udp_tx|src/rtl/eth/udp_tx.v|17|input|crc_next|[ 7:0]
udp_tx|src/rtl/eth/udp_tx.v|18|output|tx_done|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|19|output|tx_req|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|20|output|gmii_tx_en|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|21|output|gmii_txd|[ 7:0]
udp_tx|src/rtl/eth/udp_tx.v|22|output|crc_en|(scalar)
udp_tx|src/rtl/eth/udp_tx.v|23|output|crc_clr|(scalar)
#MOD rgb2dvi src/rtl/hdmi/rgb2dvi.v 4
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|5|input|clk_pix|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|6|input|clk_pix5x|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|7|input|rst_n|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|8|input|r|[7:0]
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|9|input|g|[7:0]
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|10|input|b|[7:0]
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|11|input|hs|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|12|input|vs|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|13|input|de|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|14|output|tmds_clk_p|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|15|output|tmds_clk_n|(scalar)
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|16|output|tmds_data_p|[2:0]
rgb2dvi|src/rtl/hdmi/rgb2dvi.v|17|output|tmds_data_n|[2:0]
#MOD tmds_encoder src/rtl/hdmi/tmds_encoder.v 3
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|4|input|clk|(scalar)
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|5|input|rst_n|(scalar)
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|6|input|din|[7:0]
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|7|input|c0|(scalar)
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|8|input|c1|(scalar)
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|9|input|de|(scalar)
tmds_encoder|src/rtl/hdmi/tmds_encoder.v|10|output|dout|[9:0]
#MOD tmds_serializer src/rtl/hdmi/tmds_serializer.v 4
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|5|input|clk_pix|(scalar)
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|6|input|clk_pix5x|(scalar)
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|7|input|rst_n|(scalar)
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|8|input|din|[9:0]
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|9|output|data_p|(scalar)
tmds_serializer|src/rtl/hdmi/tmds_serializer.v|10|output|data_n|(scalar)
#MOD fb_bilin src/rtl/process/bilin/fb_bilin.v 7
fb_bilin|src/rtl/process/bilin/fb_bilin.v|11|input|clk|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|12|input|rst_n|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|15|input|wr_clk|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|16|input|wr_en|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|17|input|wr_addr|[18:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|18|input|wr_data|[63:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|21|input|sx|[11:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|21|input|sy|[11:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|22|input|jd|[8:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|23|input|fx|[7:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|23|input|fy|[7:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|24|input|bilin_en|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|25|input|col0|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|26|input|row0|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|27|input|pair_odd|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|28|input|req_vld|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|29|input|oob_in|(scalar)
fb_bilin|src/rtl/process/bilin/fb_bilin.v|31|output|pix|[15:0]
fb_bilin|src/rtl/process/bilin/fb_bilin.v|32|output|oob_out|(scalar)
#MOD fb_rd5x src/rtl/process/bilin/fb_rd5x.v 9
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|13|input|clk|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|14|input|clk5x|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|15|input|rst_n|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|18|input|wr_clk|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|19|input|wr_en|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|20|input|wr_addr|[18:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|21|input|wr_data|[63:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|24|input|sx_l|[11:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|24|input|sy_l|[11:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|25|input|sx_r|[11:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|25|input|sy_r|[11:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|26|input|fx_r|[7:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|26|input|fy_r|[7:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|27|input|bilin_en|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|28|input|sel_right|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|29|input|oob_l|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|29|input|oob_r|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|32|output|pix|[15:0]
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|33|output|oob_out|(scalar)
fb_rd5x|src/rtl/process/bilin/fb_rd5x.v|34|output|right_out|(scalar)
#MOD tap_sched src/rtl/process/bilin/tap_sched.v 7
tap_sched|src/rtl/process/bilin/tap_sched.v|13|input|clk|(scalar)
tap_sched|src/rtl/process/bilin/tap_sched.v|14|input|rst_n|(scalar)
tap_sched|src/rtl/process/bilin/tap_sched.v|16|input|req|(scalar)
tap_sched|src/rtl/process/bilin/tap_sched.v|17|input|word|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|18|input|word_p1|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|19|input|word_row|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|20|input|word_row_p1|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|21|input|lane|[1:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|22|input|fx|[7:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|23|input|fy|[7:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|25|input|aux_word|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|26|input|aux_lane|[1:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|27|output|aux_q|[63:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|28|output|aux_lane_q|[1:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|30|output|rd_word_addr|[16:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|31|input|rd_word|[63:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|33|output|p00|[15:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|34|output|p10|[15:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|35|output|p01|[15:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|36|output|p11|[15:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|37|output|ofx|[7:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|38|output|ofy|[7:0]
tap_sched|src/rtl/process/bilin/tap_sched.v|39|output|vld|(scalar)
#MOD bilin_lerp src/rtl/process/bilin_lerp.v 8
bilin_lerp|src/rtl/process/bilin_lerp.v|9|input|clk|(scalar)
bilin_lerp|src/rtl/process/bilin_lerp.v|10|input|rst_n|(scalar)
bilin_lerp|src/rtl/process/bilin_lerp.v|11|input|p00|[15:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|12|input|p10|[15:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|13|input|p01|[15:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|14|input|p11|[15:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|15|input|fx|[7:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|16|input|fy|[7:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|17|output|pix|[15:0]
bilin_lerp|src/rtl/process/bilin_lerp.v|18|output|vld|(scalar)
#MOD effect_ctrl src/rtl/process/effect_ctrl.v 8
effect_ctrl|src/rtl/process/effect_ctrl.v|9|input|clk|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|10|input|rst_n|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|11|input|stage_sel_async|[8:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|12|input|zoom_sel_async|[2:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|13|input|zoom_manual_async|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|14|input|threshold_async|[7:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|15|input|gamma_async|[31:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|16|output|stage_sel|[8:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|17|output|zoom_sel|[2:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|18|output|zoom_manual|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|19|output|threshold|[7:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|20|output|gamma_en|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|21|output|gamma_wr|(scalar)
effect_ctrl|src/rtl/process/effect_ctrl.v|22|output|gamma_idx|[7:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|23|output|gamma_data|[7:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|24|output|gamma_disp|[5:0]
effect_ctrl|src/rtl/process/effect_ctrl.v|25|output|temp_disp|[7:0]
#MOD proc_binary src/rtl/process/proc_binary.v 5
proc_binary|src/rtl/process/proc_binary.v|6|input|clk|(scalar)
proc_binary|src/rtl/process/proc_binary.v|7|input|rst_n|(scalar)
proc_binary|src/rtl/process/proc_binary.v|8|input|bypass|(scalar)
proc_binary|src/rtl/process/proc_binary.v|9|input|threshold|[7:0]
proc_binary|src/rtl/process/proc_binary.v|10|input|pol|(scalar)
proc_binary|src/rtl/process/proc_binary.v|11|input|de_in|(scalar)
proc_binary|src/rtl/process/proc_binary.v|12|input|din|[15:0]
proc_binary|src/rtl/process/proc_binary.v|13|output|de_out|(scalar)
proc_binary|src/rtl/process/proc_binary.v|14|output|dout|[15:0]
#MOD proc_box_blur src/rtl/process/proc_box_blur.v 4
proc_box_blur|src/rtl/process/proc_box_blur.v|7|input|clk|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|8|input|rst_n|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|9|input|bypass|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|10|input|hs_in|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|11|input|vs_in|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|12|input|de_in|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|13|input|x_in|[11:0]
proc_box_blur|src/rtl/process/proc_box_blur.v|14|input|y_in|[11:0]
proc_box_blur|src/rtl/process/proc_box_blur.v|15|input|din|[15:0]
proc_box_blur|src/rtl/process/proc_box_blur.v|16|output|de_out|(scalar)
proc_box_blur|src/rtl/process/proc_box_blur.v|17|output|dout|[15:0]
#MOD proc_gray src/rtl/process/proc_gray.v 5
proc_gray|src/rtl/process/proc_gray.v|6|input|clk|(scalar)
proc_gray|src/rtl/process/proc_gray.v|7|input|rst_n|(scalar)
proc_gray|src/rtl/process/proc_gray.v|8|input|bypass|(scalar)
proc_gray|src/rtl/process/proc_gray.v|9|input|de_in|(scalar)
proc_gray|src/rtl/process/proc_gray.v|10|input|din|[15:0]
proc_gray|src/rtl/process/proc_gray.v|11|output|de_out|(scalar)
proc_gray|src/rtl/process/proc_gray.v|12|output|dout|[15:0]
#MOD proc_invert src/rtl/process/proc_invert.v 5
proc_invert|src/rtl/process/proc_invert.v|6|input|clk|(scalar)
proc_invert|src/rtl/process/proc_invert.v|7|input|rst_n|(scalar)
proc_invert|src/rtl/process/proc_invert.v|8|input|bypass|(scalar)
proc_invert|src/rtl/process/proc_invert.v|9|input|de_in|(scalar)
proc_invert|src/rtl/process/proc_invert.v|10|input|din|[15:0]
proc_invert|src/rtl/process/proc_invert.v|11|output|de_out|(scalar)
proc_invert|src/rtl/process/proc_invert.v|12|output|dout|[15:0]
#MOD proc_morph src/rtl/process/proc_morph.v 8
proc_morph|src/rtl/process/proc_morph.v|11|input|clk|(scalar)
proc_morph|src/rtl/process/proc_morph.v|12|input|rst_n|(scalar)
proc_morph|src/rtl/process/proc_morph.v|13|input|mode|[1:0]
proc_morph|src/rtl/process/proc_morph.v|14|input|threshold|[7:0]
proc_morph|src/rtl/process/proc_morph.v|15|input|de_in|(scalar)
proc_morph|src/rtl/process/proc_morph.v|16|input|x_in|[11:0]
proc_morph|src/rtl/process/proc_morph.v|17|input|y_in|[11:0]
proc_morph|src/rtl/process/proc_morph.v|18|input|din|[15:0]
proc_morph|src/rtl/process/proc_morph.v|19|output|de_out|(scalar)
proc_morph|src/rtl/process/proc_morph.v|20|output|dout|[15:0]
#MOD proc_pipeline src/rtl/process/proc_pipeline.v 8
proc_pipeline|src/rtl/process/proc_pipeline.v|29|input|clk|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|30|input|rst_n|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|31|input|stage_sel|[8:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|32|input|threshold|[7:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|33|input|gamma_en|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|34|input|gamma_wr|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|35|input|gamma_idx|[7:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|36|input|gamma_data|[7:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|37|input|rotate_active|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|38|input|hs_in|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|39|input|vs_in|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|40|input|de_in|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|41|input|x_in|[11:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|42|input|y_in|[11:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|43|input|din|[15:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|44|output|off_rows|[7:0]
proc_pipeline|src/rtl/process/proc_pipeline.v|45|output|de_out|(scalar)
proc_pipeline|src/rtl/process/proc_pipeline.v|46|output|dout|[15:0]
#MOD proc_sharpen src/rtl/process/proc_sharpen.v 7
proc_sharpen|src/rtl/process/proc_sharpen.v|10|input|clk|(scalar)
proc_sharpen|src/rtl/process/proc_sharpen.v|11|input|rst_n|(scalar)
proc_sharpen|src/rtl/process/proc_sharpen.v|12|input|bypass|(scalar)
proc_sharpen|src/rtl/process/proc_sharpen.v|13|input|de_in|(scalar)
proc_sharpen|src/rtl/process/proc_sharpen.v|14|input|x_in|[11:0]
proc_sharpen|src/rtl/process/proc_sharpen.v|15|input|y_in|[11:0]
proc_sharpen|src/rtl/process/proc_sharpen.v|16|input|din|[15:0]
proc_sharpen|src/rtl/process/proc_sharpen.v|17|output|de_out|(scalar)
proc_sharpen|src/rtl/process/proc_sharpen.v|18|output|dout|[15:0]
#MOD proc_sobel src/rtl/process/proc_sobel.v 6
proc_sobel|src/rtl/process/proc_sobel.v|9|input|clk|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|10|input|rst_n|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|11|input|bypass|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|12|input|vs_in|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|13|input|de_in|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|14|input|x_in|[11:0]
proc_sobel|src/rtl/process/proc_sobel.v|15|input|y_in|[11:0]
proc_sobel|src/rtl/process/proc_sobel.v|16|input|din|[15:0]
proc_sobel|src/rtl/process/proc_sobel.v|17|output|de_out|(scalar)
proc_sobel|src/rtl/process/proc_sobel.v|18|output|dout|[15:0]
#MOD angle_ctrl src/rtl/process/rotate/angle_ctrl.v 7
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|8|input|clk|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|9|input|rst_n|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|10|input|key_inc|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|11|input|key_dec|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|12|input|frame_tgl|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|13|input|auto_en|(scalar)
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|14|input|speed|[2:0]
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|15|output|angle|[8:0]
angle_ctrl|src/rtl/process/rotate/angle_ctrl.v|16|output|rotate_active|(scalar)
#MOD cos_rom src/rtl/process/rotate/cos_rom.v 3
cos_rom|src/rtl/process/rotate/cos_rom.v|4|input|angle|[8:0]
cos_rom|src/rtl/process/rotate/cos_rom.v|5|output|value|[9:0]
#MOD rotate_mapper src/rtl/process/rotate/rotate_mapper.v 5
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|9|input|clk|(scalar)
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|10|input|rst_n|(scalar)
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|11|input|angle|[8:0]
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|12|input|enable|(scalar)
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|13|input|x_in|[11:0]
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|14|input|y_in|[11:0]
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|15|output|x_out|[11:0]
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|16|output|y_out|[11:0]
rotate_mapper|src/rtl/process/rotate/rotate_mapper.v|17|output|oob|(scalar)
#MOD sin_rom src/rtl/process/rotate/sin_rom.v 3
sin_rom|src/rtl/process/rotate/sin_rom.v|4|input|angle|[8:0]
sin_rom|src/rtl/process/rotate/sin_rom.v|5|output|value|[9:0]
#MOD zoom_ctrl src/rtl/process/zoom/zoom_ctrl.v 5
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|10|input|clk|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|11|input|rst_n|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|12|input|enable|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|13|input|zsel|[2:0]
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|14|input|manual|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|22|input|rotate_en|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|23|input|fit_en|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|24|input|inv_fit|[9:0]
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|25|input|frame_start|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|26|output|inv_scale|[9:0]
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|27|output|inv_used|[9:0]
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|28|output|zoom_active|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|29|output|zoom_code|[2:0]
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|30|output|dir|(scalar)
zoom_ctrl|src/rtl/process/zoom/zoom_ctrl.v|31|output|rot_forced|(scalar)
#MOD zoom_fit src/rtl/process/zoom/zoom_fit.v 8
zoom_fit|src/rtl/process/zoom/zoom_fit.v|13|input|clk|(scalar)
zoom_fit|src/rtl/process/zoom/zoom_fit.v|14|input|rst_n|(scalar)
zoom_fit|src/rtl/process/zoom/zoom_fit.v|15|input|angle|[8:0]
zoom_fit|src/rtl/process/zoom/zoom_fit.v|16|output|inv_fit|[9:0]
#MOD zoom_mapper src/rtl/process/zoom/zoom_mapper.v 4
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|8|input|clk|(scalar)
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|9|input|rst_n|(scalar)
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|10|input|inv_scale|[9:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|11|input|angle|[8:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|12|input|rotate_en|(scalar)
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|13|input|x_in|[11:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|14|input|y_in|[11:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|15|output|x_out|[11:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|16|output|y_out|[11:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|17|output|oob|(scalar)
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|18|output|frac_x|[7:0]
zoom_mapper|src/rtl/process/zoom/zoom_mapper.v|19|output|frac_y|[7:0]
#MOD zoom_snap src/rtl/process/zoom/zoom_snap.v 8
zoom_snap|src/rtl/process/zoom/zoom_snap.v|9|input|pix_clk|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|10|input|pix_rst_n|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|11|input|frame_start|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|12|input|zman|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|13|input|zsel|[2:0]
zoom_snap|src/rtl/process/zoom/zoom_snap.v|14|input|zoom_code|[2:0]
zoom_snap|src/rtl/process/zoom/zoom_snap.v|15|input|zoom_active|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|16|input|zoom_dir|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|17|input|inv_scale|[9:0]
zoom_snap|src/rtl/process/zoom/zoom_snap.v|21|input|rot_forced|(scalar)
zoom_snap|src/rtl/process/zoom/zoom_snap.v|22|output|bus|[19:0]
zoom_snap|src/rtl/process/zoom/zoom_snap.v|23|output|bus_tog|(scalar)
#MOD pl_demo_top src/rtl/top/pl_demo_top.v 4
pl_demo_top|src/rtl/top/pl_demo_top.v|5|input|sys_clk|(scalar)
pl_demo_top|src/rtl/top/pl_demo_top.v|6|input|key1_n|(scalar)
pl_demo_top|src/rtl/top/pl_demo_top.v|7|input|key2_n|(scalar)
pl_demo_top|src/rtl/top/pl_demo_top.v|8|output|led|[1:0]
pl_demo_top|src/rtl/top/pl_demo_top.v|9|output|tmds_clk_p|(scalar)
pl_demo_top|src/rtl/top/pl_demo_top.v|10|output|tmds_clk_n|(scalar)
pl_demo_top|src/rtl/top/pl_demo_top.v|11|output|tmds_data_p|[2:0]
pl_demo_top|src/rtl/top/pl_demo_top.v|12|output|tmds_data_n|[2:0]
#MOD pl_video_top src/rtl/top/pl_video_top.v 8
pl_video_top|src/rtl/top/pl_video_top.v|23|input|sys_clk|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|24|input|sys_rst_n|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|25|input|axi_clk|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|26|input|axi_rst_n|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|30|input|stage_sel|[8:0]
pl_video_top|src/rtl/top/pl_video_top.v|31|input|threshold|[7:0]
pl_video_top|src/rtl/top/pl_video_top.v|34|input|gamma_ctl|[31:0]
pl_video_top|src/rtl/top/pl_video_top.v|35|input|src_sel|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|36|input|zoom_en|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|37|input|bilin_en_axi|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|38|input|osd_off_axi|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|41|input|mode_ovr|[1:0]
pl_video_top|src/rtl/top/pl_video_top.v|42|input|mode_ovr_tog|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|46|input|zoom_sel_async|[2:0]
pl_video_top|src/rtl/top/pl_video_top.v|47|input|zoom_manual_async|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|54|input|split_ctl|[18:0]
pl_video_top|src/rtl/top/pl_video_top.v|57|input|ps_publish|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|59|input|key1_n|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|60|input|key2_n|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|61|output|led|[1:0]
pl_video_top|src/rtl/top/pl_video_top.v|68|output|dbg_src|[15:0]
pl_video_top|src/rtl/top/pl_video_top.v|72|output|dbg_lat|[6*32-1:0]
pl_video_top|src/rtl/top/pl_video_top.v|78|output|dbg_zoom|[31:0]
pl_video_top|src/rtl/top/pl_video_top.v|82|input|lat_arm|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|84|output|tmds_clk_p|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|85|output|tmds_clk_n|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|86|output|tmds_data_p|[2:0]
pl_video_top|src/rtl/top/pl_video_top.v|87|output|tmds_data_n|[2:0]
pl_video_top|src/rtl/top/pl_video_top.v|89|output|m_axi_araddr|[31:0]
pl_video_top|src/rtl/top/pl_video_top.v|90|output|m_axi_arid|[5:0]
pl_video_top|src/rtl/top/pl_video_top.v|91|output|m_axi_arlen|[7:0]
pl_video_top|src/rtl/top/pl_video_top.v|92|output|m_axi_arsize|[2:0]
pl_video_top|src/rtl/top/pl_video_top.v|93|output|m_axi_arburst|[1:0]
pl_video_top|src/rtl/top/pl_video_top.v|94|output|m_axi_arvalid|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|95|input|m_axi_arready|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|96|input|m_axi_rdata|[63:0]
pl_video_top|src/rtl/top/pl_video_top.v|97|input|m_axi_rid|[5:0]
pl_video_top|src/rtl/top/pl_video_top.v|98|input|m_axi_rresp|[1:0]
pl_video_top|src/rtl/top/pl_video_top.v|99|input|m_axi_rlast|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|100|input|m_axi_rvalid|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|101|output|m_axi_rready|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|103|input|eth_wr_clk|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|104|input|eth_wr_en|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|105|input|eth_wr_addr|[18:0]
pl_video_top|src/rtl/top/pl_video_top.v|106|input|eth_wr_data|[15:0]
pl_video_top|src/rtl/top/pl_video_top.v|107|input|eth_link|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|114|input|eth_live|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|115|input|eth_tb_ok|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|116|input|eth_frame|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|117|input|eth_ddr_base|[31:0]
pl_video_top|src/rtl/top/pl_video_top.v|118|input|eth_commit|(scalar)
pl_video_top|src/rtl/top/pl_video_top.v|123|output|status|[31:0]
pl_video_top|src/rtl/top/pl_video_top.v|124|output|copy_hold|(scalar)
#MOD system_top src/rtl/top/system_top.v 4
system_top|src/rtl/top/system_top.v|5|inout|DDR_cas_n|(scalar)
system_top|src/rtl/top/system_top.v|6|inout|DDR_cke|(scalar)
system_top|src/rtl/top/system_top.v|7|inout|DDR_ck_n|(scalar)
system_top|src/rtl/top/system_top.v|8|inout|DDR_ck_p|(scalar)
system_top|src/rtl/top/system_top.v|9|inout|DDR_cs_n|(scalar)
system_top|src/rtl/top/system_top.v|10|inout|DDR_odt|(scalar)
system_top|src/rtl/top/system_top.v|11|inout|DDR_ras_n|(scalar)
system_top|src/rtl/top/system_top.v|12|inout|DDR_reset_n|(scalar)
system_top|src/rtl/top/system_top.v|13|inout|DDR_we_n|(scalar)
system_top|src/rtl/top/system_top.v|14|inout|DDR_ba|[2:0]
system_top|src/rtl/top/system_top.v|15|inout|DDR_addr|[14:0]
system_top|src/rtl/top/system_top.v|16|inout|DDR_dq|[31:0]
system_top|src/rtl/top/system_top.v|17|inout|DDR_dm|[3:0]
system_top|src/rtl/top/system_top.v|18|inout|DDR_dqs_n|[3:0]
system_top|src/rtl/top/system_top.v|19|inout|DDR_dqs_p|[3:0]
system_top|src/rtl/top/system_top.v|20|inout|FIXED_IO_ddr_vrn|(scalar)
system_top|src/rtl/top/system_top.v|21|inout|FIXED_IO_ddr_vrp|(scalar)
system_top|src/rtl/top/system_top.v|22|inout|FIXED_IO_mio|[53:0]
system_top|src/rtl/top/system_top.v|23|inout|FIXED_IO_ps_clk|(scalar)
system_top|src/rtl/top/system_top.v|24|inout|FIXED_IO_ps_porb|(scalar)
system_top|src/rtl/top/system_top.v|25|inout|FIXED_IO_ps_srstb|(scalar)
system_top|src/rtl/top/system_top.v|26|input|sys_clk|(scalar)
system_top|src/rtl/top/system_top.v|27|input|key1_n|(scalar)
system_top|src/rtl/top/system_top.v|28|input|key2_n|(scalar)
system_top|src/rtl/top/system_top.v|29|output|led|[1:0]
system_top|src/rtl/top/system_top.v|30|output|tmds_clk_p|(scalar)
system_top|src/rtl/top/system_top.v|31|output|tmds_clk_n|(scalar)
system_top|src/rtl/top/system_top.v|32|output|tmds_data_p|[2:0]
system_top|src/rtl/top/system_top.v|33|output|tmds_data_n|[2:0]
system_top|src/rtl/top/system_top.v|34|input|eth_rxc|(scalar)
system_top|src/rtl/top/system_top.v|35|input|eth_rx_ctl|(scalar)
system_top|src/rtl/top/system_top.v|36|input|eth_rxd|[3:0]
system_top|src/rtl/top/system_top.v|37|output|eth_tx_clk|(scalar)
system_top|src/rtl/top/system_top.v|38|output|eth_tx_ctl|(scalar)
system_top|src/rtl/top/system_top.v|39|output|eth_txd|[3:0]
system_top|src/rtl/top/system_top.v|40|output|eth_mdc|(scalar)
system_top|src/rtl/top/system_top.v|41|inout|eth_mdio|(scalar)
system_top|src/rtl/top/system_top.v|42|output|eth_rst_n|(scalar)
#MOD key_debounce src/rtl/util/key_debounce.v 18
key_debounce|src/rtl/util/key_debounce.v|21|input|clk|(scalar)
key_debounce|src/rtl/util/key_debounce.v|22|input|rst_n|(scalar)
key_debounce|src/rtl/util/key_debounce.v|23|input|key_n|(scalar)
key_debounce|src/rtl/util/key_debounce.v|24|output|pulse|(scalar)
key_debounce|src/rtl/util/key_debounce.v|25|output|key_stable|(scalar)
#MOD key_long src/rtl/util/key_long.v 8
key_long|src/rtl/util/key_long.v|12|input|clk|(scalar)
key_long|src/rtl/util/key_long.v|13|input|rst_n|(scalar)
key_long|src/rtl/util/key_long.v|14|input|pressed|(scalar)
key_long|src/rtl/util/key_long.v|15|output|tog|(scalar)
key_long|src/rtl/util/key_long.v|16|output|short_pulse|(scalar)
key_long|src/rtl/util/key_long.v|17|output|holding|(scalar)
#MOD ps_publish src/rtl/util/ps_publish.v 9
ps_publish|src/rtl/util/ps_publish.v|10|input|clk|(scalar)
ps_publish|src/rtl/util/ps_publish.v|11|input|rst_n|(scalar)
ps_publish|src/rtl/util/ps_publish.v|12|input|tog|(scalar)
ps_publish|src/rtl/util/ps_publish.v|13|input|consume|(scalar)
ps_publish|src/rtl/util/ps_publish.v|14|output|pend|(scalar)
ps_publish|src/rtl/util/ps_publish.v|15|output|new_tog|(scalar)
#MOD shown_rate src/rtl/util/shown_rate.v 22
shown_rate|src/rtl/util/shown_rate.v|25|input|clk|(scalar)
shown_rate|src/rtl/util/shown_rate.v|26|input|rst_n|(scalar)
shown_rate|src/rtl/util/shown_rate.v|27|input|frame_start|(scalar)
shown_rate|src/rtl/util/shown_rate.v|28|input|owner_eth_pix|(scalar)
shown_rate|src/rtl/util/shown_rate.v|29|input|fb_vis|(scalar)
shown_rate|src/rtl/util/shown_rate.v|30|input|eth_new|(scalar)
shown_rate|src/rtl/util/shown_rate.v|31|input|pub_consume|(scalar)
shown_rate|src/rtl/util/shown_rate.v|32|input|pub_pend|(scalar)
shown_rate|src/rtl/util/shown_rate.v|33|output|fps_q|[7:0]
#MOD src_arb src/rtl/util/src_arb.v 17
src_arb|src/rtl/util/src_arb.v|22|input|clk|(scalar)
src_arb|src/rtl/util/src_arb.v|23|input|rst_n|(scalar)
src_arb|src/rtl/util/src_arb.v|24|input|eth_live|(scalar)
src_arb|src/rtl/util/src_arb.v|25|input|eth_tb_ok|(scalar)
src_arb|src/rtl/util/src_arb.v|26|input|sel|[1:0]
src_arb|src/rtl/util/src_arb.v|29|input|row_busy|(scalar)
src_arb|src/rtl/util/src_arb.v|30|input|fill_busy|(scalar)
src_arb|src/rtl/util/src_arb.v|31|output|owner_eth|(scalar)
src_arb|src/rtl/util/src_arb.v|39|output|why_ps|[2:0]
#MOD src_life src/rtl/util/src_life.v 8
src_life|src/rtl/util/src_life.v|17|input|clk|(scalar)
src_life|src/rtl/util/src_life.v|18|input|rst_n|(scalar)
src_life|src/rtl/util/src_life.v|19|input|frame_start|(scalar)
src_life|src/rtl/util/src_life.v|20|input|ps_pub|(scalar)
src_life|src/rtl/util/src_life.v|21|input|eth_owner|(scalar)
src_life|src/rtl/util/src_life.v|22|input|mode_eth|(scalar)
src_life|src/rtl/util/src_life.v|23|input|mode_ps|(scalar)
src_life|src/rtl/util/src_life.v|24|output|ps_src_now|(scalar)
src_life|src/rtl/util/src_life.v|25|output|have_src|(scalar)
src_life|src/rtl/util/src_life.v|26|output|ps_no_pub|(scalar)
#MOD src_mode src/rtl/util/src_mode.v 5
src_mode|src/rtl/util/src_mode.v|6|input|clk|(scalar)
src_mode|src/rtl/util/src_mode.v|7|input|rst_n|(scalar)
src_mode|src/rtl/util/src_mode.v|8|input|ltog|(scalar)
src_mode|src/rtl/util/src_mode.v|9|input|eth_now|(scalar)
src_mode|src/rtl/util/src_mode.v|15|input|ov_code|[1:0]
src_mode|src/rtl/util/src_mode.v|16|input|ov_tog|(scalar)
src_mode|src/rtl/util/src_mode.v|17|output|mode|[1:0]
#MOD color_bar src/rtl/video/color_bar.v 8
color_bar|src/rtl/video/color_bar.v|12|input|clk|(scalar)
color_bar|src/rtl/video/color_bar.v|13|input|rst_n|(scalar)
color_bar|src/rtl/video/color_bar.v|14|input|x|[11:0]
color_bar|src/rtl/video/color_bar.v|15|input|y|[11:0]
color_bar|src/rtl/video/color_bar.v|16|input|de|(scalar)
color_bar|src/rtl/video/color_bar.v|17|output|rgb565|[15:0]
#MOD frame_buffer src/rtl/video/frame_buffer.v 5
frame_buffer|src/rtl/video/frame_buffer.v|9|input|wr_clk|(scalar)
frame_buffer|src/rtl/video/frame_buffer.v|10|input|wr_en|(scalar)
frame_buffer|src/rtl/video/frame_buffer.v|11|input|wr_addr|[18:0]
frame_buffer|src/rtl/video/frame_buffer.v|12|input|wr_data|[15:0]
frame_buffer|src/rtl/video/frame_buffer.v|14|input|rd_clk|(scalar)
frame_buffer|src/rtl/video/frame_buffer.v|15|input|rd_addr|[18:0]
frame_buffer|src/rtl/video/frame_buffer.v|16|output|rd_data|[15:0]
#MOD frame_buffer_db src/rtl/video/frame_buffer_db.v 5
frame_buffer_db|src/rtl/video/frame_buffer_db.v|9|input|wr_clk|(scalar)
frame_buffer_db|src/rtl/video/frame_buffer_db.v|10|input|wr_en|(scalar)
frame_buffer_db|src/rtl/video/frame_buffer_db.v|11|input|wr_addr|[18:0]
frame_buffer_db|src/rtl/video/frame_buffer_db.v|12|input|wr_data|[15:0]
frame_buffer_db|src/rtl/video/frame_buffer_db.v|13|input|wr_frame_done|(scalar)
frame_buffer_db|src/rtl/video/frame_buffer_db.v|15|input|rd_clk|(scalar)
frame_buffer_db|src/rtl/video/frame_buffer_db.v|16|input|rd_vsync|(scalar)
frame_buffer_db|src/rtl/video/frame_buffer_db.v|17|input|rd_addr|[18:0]
frame_buffer_db|src/rtl/video/frame_buffer_db.v|18|output|rd_data|[15:0]
#MOD frame_buffer_w64 src/rtl/video/frame_buffer_w64.v 8
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|12|input|wr_clk|(scalar)
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|13|input|wr_en|(scalar)
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|14|input|wr_addr|[18:0]
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|15|input|wr_data|[63:0]
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|17|input|rd_clk|(scalar)
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|18|input|rd_addr|[18:0]
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|19|output|rd_data|[15:0]
frame_buffer_w64|src/rtl/video/frame_buffer_w64.v|20|output|rd_data64|[63:0]
#MOD frame_commit_lock src/rtl/video/frame_commit_lock.v 5
frame_commit_lock|src/rtl/video/frame_commit_lock.v|10|input|axi_clk|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|11|input|axi_rst_n|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|12|input|commit_req|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|13|input|commit_base|[31:0]
frame_commit_lock|src/rtl/video/frame_commit_lock.v|14|input|pix_clk|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|15|input|pix_rst_n|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|16|input|de|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|17|input|vsync|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|18|input|blank_safe|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|19|input|copy_busy|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|20|input|copy_done|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|21|output|start_copy|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|22|output|copy_base|[31:0]
frame_commit_lock|src/rtl/video/frame_commit_lock.v|23|output|frame_ready_pix|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|24|output|allow_copy_axi|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|25|output|copy_abort|(scalar)
frame_commit_lock|src/rtl/video/frame_commit_lock.v|26|output|abort_tgl|(scalar)
#MOD frame_latency src/rtl/video/frame_latency.v 6
frame_latency|src/rtl/video/frame_latency.v|7|input|axi_clk|(scalar)
frame_latency|src/rtl/video/frame_latency.v|8|input|axi_rst_n|(scalar)
frame_latency|src/rtl/video/frame_latency.v|9|input|commit|(scalar)
frame_latency|src/rtl/video/frame_latency.v|10|input|copy_start|(scalar)
frame_latency|src/rtl/video/frame_latency.v|11|input|copy_done|(scalar)
frame_latency|src/rtl/video/frame_latency.v|12|input|disp_sof_tgl|(scalar)
frame_latency|src/rtl/video/frame_latency.v|13|input|arm|(scalar)
frame_latency|src/rtl/video/frame_latency.v|14|output|c1_cyc|[31:0]
frame_latency|src/rtl/video/frame_latency.v|15|output|c2_cyc|[31:0]
frame_latency|src/rtl/video/frame_latency.v|16|output|tot_cyc|[31:0]
frame_latency|src/rtl/video/frame_latency.v|17|output|max_cyc|[31:0]
frame_latency|src/rtl/video/frame_latency.v|18|output|n_meas|[15:0]
frame_latency|src/rtl/video/frame_latency.v|19|output|clamped|(scalar)
frame_latency|src/rtl/video/frame_latency.v|26|output|q_c1|[31:0]
frame_latency|src/rtl/video/frame_latency.v|27|output|q_c2|[31:0]
frame_latency|src/rtl/video/frame_latency.v|28|output|q_tot|[31:0]
frame_latency|src/rtl/video/frame_latency.v|29|output|q_max|[31:0]
frame_latency|src/rtl/video/frame_latency.v|30|output|q_stat|[31:0]
frame_latency|src/rtl/video/frame_latency.v|31|output|q_ms|[31:0]
frame_latency|src/rtl/video/frame_latency.v|33|output|lat_ms|[15:0]
frame_latency|src/rtl/video/frame_latency.v|34|output|lat_valid|(scalar)
frame_latency|src/rtl/video/frame_latency.v|35|output|lat_sticky|(scalar)
frame_latency|src/rtl/video/frame_latency.v|36|output|lat_tog|(scalar)
#MOD gamma_lut src/rtl/video/gamma_lut.v 8
gamma_lut|src/rtl/video/gamma_lut.v|9|input|clk|(scalar)
gamma_lut|src/rtl/video/gamma_lut.v|10|input|rst_n|(scalar)
gamma_lut|src/rtl/video/gamma_lut.v|11|input|en|(scalar)
gamma_lut|src/rtl/video/gamma_lut.v|12|input|wr|(scalar)
gamma_lut|src/rtl/video/gamma_lut.v|13|input|idx|[7:0]
gamma_lut|src/rtl/video/gamma_lut.v|14|input|data|[7:0]
gamma_lut|src/rtl/video/gamma_lut.v|15|input|din|[15:0]
gamma_lut|src/rtl/video/gamma_lut.v|16|output|dout|[15:0]
#MOD line_cache src/rtl/video/line_cache.v 4
line_cache|src/rtl/video/line_cache.v|7|input|wr_clk|(scalar)
line_cache|src/rtl/video/line_cache.v|8|input|wr_en|(scalar)
line_cache|src/rtl/video/line_cache.v|9|input|wr_addr|[11:0]
line_cache|src/rtl/video/line_cache.v|10|input|wr_data|[15:0]
line_cache|src/rtl/video/line_cache.v|11|input|rd_clk|(scalar)
line_cache|src/rtl/video/line_cache.v|12|input|rd_addr|[11:0]
line_cache|src/rtl/video/line_cache.v|13|output|rd_data|[15:0]
#MOD osd_overlay src/rtl/video/osd_overlay.v 8
osd_overlay|src/rtl/video/osd_overlay.v|26|input|clk|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|27|input|rst_n|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|28|input|x|[11:0]
osd_overlay|src/rtl/video/osd_overlay.v|29|input|y|[11:0]
osd_overlay|src/rtl/video/osd_overlay.v|30|input|de|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|32|input|angle|[8:0]
osd_overlay|src/rtl/video/osd_overlay.v|33|input|fps|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|34|input|stage_sel|[8:0]
osd_overlay|src/rtl/video/osd_overlay.v|35|input|threshold|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|36|input|gamma_disp|[5:0]
osd_overlay|src/rtl/video/osd_overlay.v|37|input|zoom_code|[2:0]
osd_overlay|src/rtl/video/osd_overlay.v|38|input|zoom_auto|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|39|input|zoom_fit|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|40|input|split_pct|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|41|input|split_auto|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|42|input|lat_ms|[15:0]
osd_overlay|src/rtl/video/osd_overlay.v|43|input|lat_ok|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|44|input|src_eff|[1:0]
osd_overlay|src/rtl/video/osd_overlay.v|45|input|mode|[1:0]
osd_overlay|src/rtl/video/osd_overlay.v|48|input|no_sig|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|53|input|temp_disp|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|54|input|bg_pix|[15:0]
osd_overlay|src/rtl/video/osd_overlay.v|58|input|osd_en|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|59|output|r|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|60|output|g|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|61|output|b|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|62|output|de_out|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|63|input|hs_in|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|64|input|vs_in|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|65|output|hs_out|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|66|output|vs_out|(scalar)
osd_overlay|src/rtl/video/osd_overlay.v|67|input|r_in|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|68|input|g_in|[7:0]
osd_overlay|src/rtl/video/osd_overlay.v|69|input|b_in|[7:0]
#MOD raw_line_delay src/rtl/video/raw_line_delay.v 8
raw_line_delay|src/rtl/video/raw_line_delay.v|19|input|clk|(scalar)
raw_line_delay|src/rtl/video/raw_line_delay.v|20|input|rst_n|(scalar)
raw_line_delay|src/rtl/video/raw_line_delay.v|21|input|de|(scalar)
raw_line_delay|src/rtl/video/raw_line_delay.v|22|input|x|[11:0]
raw_line_delay|src/rtl/video/raw_line_delay.v|23|input|y|[11:0]
raw_line_delay|src/rtl/video/raw_line_delay.v|24|input|d_in|[DW-1:0]
raw_line_delay|src/rtl/video/raw_line_delay.v|25|output|d_out|[DW-1:0]
raw_line_delay|src/rtl/video/raw_line_delay.v|26|output|de_out|(scalar)
#MOD seam_src src/rtl/video/seam_src.v 8
seam_src|src/rtl/video/seam_src.v|11|input|clk|(scalar)
seam_src|src/rtl/video/seam_src.v|12|input|rst_n|(scalar)
seam_src|src/rtl/video/seam_src.v|13|input|sx|[11:0]
seam_src|src/rtl/video/seam_src.v|14|input|oob|(scalar)
seam_src|src/rtl/video/seam_src.v|15|input|seam|[11:0]
seam_src|src/rtl/video/seam_src.v|16|input|marker_on|(scalar)
seam_src|src/rtl/video/seam_src.v|17|input|raw_left|(scalar)
seam_src|src/rtl/video/seam_src.v|18|output|take_orig|(scalar)
seam_src|src/rtl/video/seam_src.v|19|output|mark|(scalar)
#MOD split_ctrl src/rtl/video/split_ctrl.v 8
split_ctrl|src/rtl/video/split_ctrl.v|13|input|clk|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|14|input|rst_n|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|15|input|de|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|16|input|pos_px|[11:0]
split_ctrl|src/rtl/video/split_ctrl.v|17|input|auto_en|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|18|input|follow|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|19|input|speed|[3:0]
split_ctrl|src/rtl/video/split_ctrl.v|20|input|lo16|[4:0]
split_ctrl|src/rtl/video/split_ctrl.v|21|input|hi16|[4:0]
split_ctrl|src/rtl/video/split_ctrl.v|22|input|swap|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|23|output|split_eff|[11:0]
split_ctrl|src/rtl/video/split_ctrl.v|24|output|raw_on_left|(scalar)
split_ctrl|src/rtl/video/split_ctrl.v|25|output|shown_pct|[11:0]
#MOD split_display src/rtl/video/split_display.v 4
split_display|src/rtl/video/split_display.v|5|input|clk|(scalar)
split_display|src/rtl/video/split_display.v|6|input|rst_n|(scalar)
split_display|src/rtl/video/split_display.v|7|input|x|[11:0]
split_display|src/rtl/video/split_display.v|8|input|y|[11:0]
split_display|src/rtl/video/split_display.v|15|input|x_sel|[11:0]
split_display|src/rtl/video/split_display.v|18|input|seam|[11:0]
split_display|src/rtl/video/split_display.v|19|input|raw_left|(scalar)
split_display|src/rtl/video/split_display.v|24|input|seam_in_src|(scalar)
split_display|src/rtl/video/split_display.v|25|input|src_orig|(scalar)
split_display|src/rtl/video/split_display.v|26|input|src_mark|(scalar)
split_display|src/rtl/video/split_display.v|27|input|marker|(scalar)
split_display|src/rtl/video/split_display.v|28|input|de|(scalar)
split_display|src/rtl/video/split_display.v|29|input|hs|(scalar)
split_display|src/rtl/video/split_display.v|30|input|vs|(scalar)
split_display|src/rtl/video/split_display.v|31|input|orig_pix|[15:0]
split_display|src/rtl/video/split_display.v|32|input|proc_pix|[15:0]
split_display|src/rtl/video/split_display.v|33|input|angle_idx|[1:0]
split_display|src/rtl/video/split_display.v|34|input|oob_l|(scalar)
split_display|src/rtl/video/split_display.v|35|input|oob_r|(scalar)
split_display|src/rtl/video/split_display.v|36|output|r|[7:0]
split_display|src/rtl/video/split_display.v|37|output|g|[7:0]
split_display|src/rtl/video/split_display.v|38|output|b|[7:0]
split_display|src/rtl/video/split_display.v|39|output|de_out|(scalar)
split_display|src/rtl/video/split_display.v|40|output|hs_out|(scalar)
split_display|src/rtl/video/split_display.v|41|output|vs_out|(scalar)
#MOD test_card src/rtl/video/test_card.v 8
test_card|src/rtl/video/test_card.v|12|input|clk|(scalar)
test_card|src/rtl/video/test_card.v|13|input|rst_n|(scalar)
test_card|src/rtl/video/test_card.v|14|input|vs|(scalar)
test_card|src/rtl/video/test_card.v|15|input|x|[11:0]
test_card|src/rtl/video/test_card.v|16|input|y|[11:0]
test_card|src/rtl/video/test_card.v|17|input|de|(scalar)
test_card|src/rtl/video/test_card.v|18|output|rgb565|[15:0]
#MOD video_timing src/rtl/video/video_timing.v 4
video_timing|src/rtl/video/video_timing.v|16|input|clk|(scalar)
video_timing|src/rtl/video/video_timing.v|17|input|rst_n|(scalar)
video_timing|src/rtl/video/video_timing.v|18|output|x|[11:0]
video_timing|src/rtl/video/video_timing.v|19|output|y|[11:0]
video_timing|src/rtl/video/video_timing.v|20|output|hs|(scalar)
video_timing|src/rtl/video/video_timing.v|21|output|vs|(scalar)
video_timing|src/rtl/video/video_timing.v|22|output|de|(scalar)
video_timing|src/rtl/video/video_timing.v|23|output|frame_start|(scalar)
video_timing|src/rtl/video/video_timing.v|24|output|frame_done|(scalar)
#MOD video_timing_1024x600 src/rtl/video/video_timing_1024x600.v 6
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|7|input|clk|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|8|input|rst_n|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|9|output|x|[11:0]
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|10|output|y|[11:0]
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|11|output|hs|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|12|output|vs|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|13|output|de|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|14|output|frame_start|(scalar)
video_timing_1024x600|src/rtl/video/video_timing_1024x600.v|15|output|frame_done|(scalar)
#MOD video_timing_720p src/rtl/video/video_timing_720p.v 4
video_timing_720p|src/rtl/video/video_timing_720p.v|5|input|clk|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|6|input|rst_n|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|7|output|x|[11:0]
video_timing_720p|src/rtl/video/video_timing_720p.v|8|output|y|[11:0]
video_timing_720p|src/rtl/video/video_timing_720p.v|9|output|hs|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|10|output|vs|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|11|output|de|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|12|output|frame_start|(scalar)
video_timing_720p|src/rtl/video/video_timing_720p.v|13|output|frame_done|(scalar)
```

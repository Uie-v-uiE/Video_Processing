# ETH 发侧解耦（候选 B）跨域清单 —— 只读盘点，未动 RTL

这份文档回答一个问题：**把 TX 协议栈（ARP 应答 / ICMP 应答 / UDP 视频 ack）从 `eth_rxc` 挪到一颗独立的
125 MHz，中间到底要跨多少条边**。它是 `report/timing/eth_rxc_partition_options.md` 第 2 节那条候选 B 的
动手前置件：那张表里"今天没有同步器、只因两端同钟才安全"的点必须逐条安排掉，才允许改 RTL。

口径：

- 本轮**只读**：没跑综合/实现/仿真，没碰板子、COM6、`hw_server`、`xsdb`。所有数字来自已在盘上的报告与
  本轮真的打开过的源码行；取不到的写 **未量**，不补数。
- "今天两端同钟"有三处独立证据：`src/rtl/eth/eth_udp_video_top.v:5`（域声明）、
  `src/rtl/eth/gmii_to_rgmii.v:25`（实现 `assign gmii_tx_clk = gmii_rx_clk;`）、
  `src/rtl/eth/eth_ctrl.v:3`（仲裁层同款声明）。所以 §2 表里凡是两端分属 RX 侧 / TX 侧的信号，
  今天的源域与目的域**都是 `eth_rxc`**，表里不再重复写一遍。
- 层次路径按工具打印的写法给（前缀 `u_eth/`、`u_pl/`），与 `build/cdc_details.rpt:435`、
  `build/cdc_details.rpt:1383` 那类名字同口径。

---

## 1. 今天的时钟归属

### 1.1 TX 时钟从哪来

`rgmii_tx_clk` 是 PL 输出端口（`src/rtl/eth/eth_udp_video_top.v:25`），顶层接到引脚 `eth_tx_clk`
（`src/rtl/top/system_top.v:37` 声明、`:182` 连接，引脚 `AB22` 见 `src/constraints/rk_zynq7020.xdc:26`）。
引脚之内没有第二颗钟：`src/rtl/eth/rgmii_tx.v:16` 写 `assign rgmii_txc = gmii_tx_clk;`，而
`gmii_tx_clk` 就是 `gmii_rx_clk`（`src/rtl/eth/gmii_to_rgmii.v:25`），后者是 `rgmii_rxc` 过一只 BUFG 的
恢复钟（`src/rtl/eth/rgmii_rx.v:47` + `:51`）。

`build/clock_util.rpt:61` 把这件事写得很直白：全局钟 `g2` 驱动
`u_eth/u_rgmii/u_rgmii_rx/BUFG_inst/O`、网络 `u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`、周期 8.000 ns、
时钟负载 2544、**非时钟负载 1**（那 1 个就是走时钟树出去打 `eth_tx_clk` 引脚的那只输出原件）。

### 1.2 `eth_rxc` 这一族今天有多重

| 量 | 读数 | 出处 |
|---|---|---|
| setup 最差 / hold 最差 | 0.739 ns / 0.052 ns，失败端点 0 | `build/timing_summary.rpt:182` |
| 检查的端点数 | 4835 | `build/timing_summary.rpt:182` |
| 挂在树上的寄存器 | 2544 时钟负载（网表）；名册另一列 2546 | `build/clock_util.rpt:61`、`build/timing_summary.rpt:182` |
| 这一族最差那条的归属 | `From Clock: eth_rxc / To Clock: eth_rxc`（同域内路径） | `build/evidence_r75/timing_summary.rpt:354-355` |

最后那两行是本清单的立论基础：**最差路径两端写同一个钟名**，说明发侧协议栈今天整个在这 8 ns 预算里被
检查。B 要买的就是把发侧那一半从这张表里搬走。

### 1.3 新 125 MHz 的来源（B 的钟从哪来）

- 资源余量：`build/clock_util.rpt:48` `MMCM 2/4`、`:43` `BUFGCTRL 8/32`、`:45` `BUFIO 0/16`
  （#57 那轮把 IDDR 从 BUFIO 搬进 BUFG 之后就是 0）。**再要一颗 125 MHz + 一只 BUFG，资源上是空的。**
- `u_idelay_clkgen`（`src/rtl/top/system_top.v:121-125`）是 `clk_gen` 的 MMCME2_BASE，VCO = 1000 MHz
  （`src/rtl/clocks/clk_gen.v:19`），CLKOUT0/1/2 已用（`:21`、`:24`、`:27`），
  **CLKOUT3…CLKOUT6 全空着没接**（`src/rtl/clocks/clk_gen.v:43-47`）。1000 / 8 = 125 MHz，
  即加一个 `.CLKOUT3_DIVIDE(8.000)` 就出得来；BUFG 照 `src/rtl/clocks/clk_gen.v:53-56` 再加一只。
- 性质：它的输入是 `sys_clk`（`src/rtl/top/system_top.v:122`），所以新钟是 **`sys_clk` 的生成钟**，
  不是 PHY 恢复钟的派生 —— 这正是"解耦"要的形状，但也决定了约束归属（§5.4）。
- 全仓 **0 条 `create_generated_clock`**；`create_clock` 只有 `rk_zynq7020.xdc:6` 与 `:36` 两条，
  MMCM 输出钟名由工具自动派生（`clkout0_1` / `clkout1_1` / `clkout2` 见
  `build/clock_util.rpt:60`、`:63`、`:65`）。
- 新钟到 `AB22` 那只 ODDR 的**时钟区域可达性：未量**（现有读数只给了 `g2` 跨 5 个 load clock region，
  `build/clock_util.rpt:61`；`u_idelay_clkgen` 的 MMCM 在 `MMCME2_ADV_X0Y0`，见 `:83-84`，
  而这一版从没布过新钟）。

---

## 2. 跨域清单

### 2.1 定义"会迁走的 TX 侧"

取的集合：`u_eth/u_arp/u_arp_tx`（`src/rtl/eth/arp.v:62-82`）、`u_eth/u_icmp/u_icmp_tx`
（`src/rtl/eth/icmp.v:76-102`）、`u_eth/u_udp_tx`（`src/rtl/eth/eth_udp_video_top.v:163-179`）、发侧三只
`crc32_d8`（`arp.v:85-93`、`icmp.v:105-113`、`eth_udp_video_top.v:180-182`）、
`u_eth/u_rgmii/u_rgmii_tx`（`gmii_to_rgmii.v:42-50`），以及**必须跟着走的两个锥**：
`u_eth/u_ctrl`（`eth_udp_video_top.v:206-222`，三选一仲裁 + GMII 出口复用）与顶层那段
`icmp_dly / icmp_tx_start_en / icmp_tx_byte_num` glue（`eth_udp_video_top.v:96-109`，
现在是 `always @(posedge gmii_rx_clk …)`）。
留在 `eth_rxc`：`u_rgmii_rx`、`u_rx_mac`、`u_rx_par`、`u_reasm`、`u_lm`、`u_arp_rx`、`u_icmp_rx`、
`u_cdc` 写侧。

**`gmii_tx_mac.v` 这个文件不存在**（`src/rtl/eth/` 里没有；发侧只有 `rgmii_tx.v` 与 `eth_ctrl.v` 里那段
复用）。任务书点了它的名，所以单独记一句。

「同步形式」列只取四种值：**无** ／ **3 位移位链**（目的件内部 `d0/d1/d2`，无 `ASYNC_REG`，见 §3.2）／
**单钟 FIFO**（`sync_fifo`，结构上不是跨域件）／ **休眠**（网表上是跨域，今天没有流量）。

### 2.2 RX 侧 → TX 侧（23 条）

| # | 信号（层次路径）→ 目的 | 位宽 | 同步形式 | 证据（源行） |
|---|---|---|---|---|
| X01 | `u_arp/u_arp_rx/src_mac` → `u_arp_tx/des_mac` | 48 | **无**，`st_idle` 那一拍整把采走 | 写 `arp_rx.v:157`；连 `arp.v:73`、`eth_udp_video_top.v:136`；采 `arp_tx.v:187-199` |
| X02 | `src_mac` → `u_icmp/u_icmp_tx/des_mac` | 48 | **无** | 连 `icmp.v:89`、`eth_udp_video_top.v:150`；采 `icmp_tx.v:261-269` |
| X03 | `src_mac` → `u_udp_tx/des_mac` | 48 | **休眠**（`tx_start_en` 恒 0） | 连 `eth_udp_video_top.v:166`（`1'b0`）、`:169`；采 `udp_tx.v:223-230` |
| X04 | `u_arp_rx/src_ip` → `u_arp_tx/des_ip` | 32 | **无** | `arp_rx.v:158`、`arp.v:74`、`arp_tx.v:187` |
| X05 | `src_ip` → `u_icmp_tx/des_ip` | 32 | **无** | `icmp.v:90`、`icmp_tx.v:253` |
| X06 | `src_ip` → `u_udp_tx/des_ip` | 32 | **休眠** | `eth_udp_video_top.v:170`、`udp_tx.v:216` |
| X07 | `arp_rx_done` → `u_ctrl/arp_rx_done` | 1（单拍脉冲） | **无**，直接当组合条件 | 出 `arp_rx.v:156`；连 `eth_udp_video_top.v:208`；用 `eth_ctrl.v:133` |
| X08 | `arp_rx_type` → `u_ctrl/arp_rx_type` | 1（随 X07 那一拍） | **无** | `arp_rx.v:163-164`、`eth_ctrl.v:133` |
| X09 | `icmp_rec_pkt_done` → glue 的 `icmp_dly` 装载 | 1（单拍脉冲） | **无** | 出 `icmp_rx.v:302`；连 `eth_udp_video_top.v:146`；用 `eth_udp_video_top.v:101-102` |
| X10 | `icmp_rec_byte_num` → glue 的 `icmp_tx_byte_num` | 16 | **无** | `icmp_rx.v:303`、`eth_udp_video_top.v:103` |
| X11 | `icmp_tx_start_en` → `u_icmp_tx/tx_start_en` | 1（单拍脉冲） | **3 位移位链** | 出 `eth_udp_video_top.v:106`；连 `icmp.v:86`；链 `icmp_tx.v:103-113`，沿检测 `:99` |
| X12 | `icmp_tx_byte_num` → `u_icmp_tx/tx_byte_num` | 16 | **无**（`pos_start_en && st_idle` 那拍采） | `eth_udp_video_top.v:93`、`:149`；采 `icmp_tx.v:125-129` |
| X13 | `u_icmp_rx/icmp_id` → `u_icmp_tx/icmp_id` | 16 | **无**，每包都换 | 写 `icmp_rx.v:242-243`；连 `icmp.v:99`；采 `icmp_tx.v:258` |
| X14 | `u_icmp_rx/icmp_seq` → `u_icmp_tx/icmp_seq` | 16 | **无** | `icmp_rx.v:244-246`、`icmp.v:100`、`icmp_tx.v:258` |
| X15 | `u_icmp_rx/reply_checksum` → `u_icmp_tx` | 32 | **无** | 写 `icmp_rx.v:310`；连 `icmp.v:101`；进校验和锥 `icmp_tx.v:296-297` |
| X16 | `icmp_rec_en` → `u_icmp_fifo/wr_en` | 1（逐字节） | **单钟 FIFO** | `eth_udp_video_top.v:121`、`sync_fifo.v:9` |
| X17 | `icmp_rec_data` → `u_icmp_fifo/wr_data` | 8 | **单钟 FIFO** | `eth_udp_video_top.v:121`、`sync_fifo.v:30-33` |
| X18 | `icmp_fifo_q` → `u_icmp_tx/tx_data` | 8（随 `tx_req` 逐字节） | **单钟 FIFO** 读侧，读使能来自对侧 | `eth_udp_video_top.v:123`、`:148`；用 `icmp_tx.v:349` |
| X19 | `p_data` → `u_ctrl/udp_rec_data` | 8 | **休眠**，且目的端出去接死网（§3.5） | `eth_udp_video_top.v:193`、`:217`；`eth_ctrl.v:79-81` |
| X20 | `p_valid` → `u_ctrl/udp_rec_en` | 1 | **休眠** | `eth_udp_video_top.v:217`、`eth_ctrl.v:79` |
| X21 | `arp_tx_en` → `u_arp_tx/arp_tx_en` | 1（恰好一拍） | **3 位移位链** | 出 `eth_ctrl.v:159`；连 `arp.v:71`；链 `arp_tx.v:66-76`，沿检测 `:63` |
| X22 | `u_ctrl/gmii_tx_en` → `u_rgmii_tx` | 1，**线速逐拍** | **无**，也不可能 2-FF | 出 `eth_ctrl.v:89-110`；连 `eth_udp_video_top.v:221`→`:76`；ODDR `rgmii_tx.v:27-28` |
| X23 | `u_ctrl/gmii_txd` → `u_rgmii_tx` | 8，**线速逐拍** | **无** | `eth_ctrl.v:92-108`、`rgmii_tx.v:45-46` |

### 2.3 TX 侧 → RX 侧（12 条）

| # | 信号 | 位宽 | 同步形式 | 证据 |
|---|---|---|---|---|
| X24 | `u_icmp_tx/tx_req`（`icmp_tx_req`）→ `u_icmp_fifo/rd_en` | 1，逐拍 | **单钟 FIFO** 对侧 | `icmp_tx.v:336`、`eth_udp_video_top.v:123`、`:151` |
| X25 | `icmp_tx_req` → `u_ctrl/icmp_tx_req` | 1 | **无** | `eth_udp_video_top.v:213`、`eth_ctrl.v:56` |
| X26 | `u_udp_tx/tx_req` → `u_ctrl/udp_tx_req` | 1 | **休眠** | `eth_udp_video_top.v:174`、`:218` |
| X27 | `u_arp_tx/tx_done` → `u_ctrl/arp_tx_done` | 1 | **无**（仲裁 busy/pend 判据） | `arp_tx.v:303`、`eth_udp_video_top.v:209` |
| X28 | `u_icmp_tx/tx_done` → `u_ctrl/icmp_tx_done` | 1 | **无**（清 `icmp_tx_busy`） | `icmp_tx.v:450`、`eth_udp_video_top.v:211`、`eth_ctrl.v:117` |
| X29 | `u_udp_tx/tx_done` → `u_ctrl/udp_tx_done` | 1 | **休眠**（清 `udp_tx_busy`） | `eth_udp_video_top.v:215`、`eth_ctrl.v:126` |
| X30 | `arp_gmii_tx_en` → `u_ctrl` 复用 | 1 | **无** | `eth_udp_video_top.v:210`、`eth_ctrl.v:96` |
| X31 | `arp_gmii_txd` → `u_ctrl` 复用 | 8 | **无** | `eth_udp_video_top.v:210`、`eth_ctrl.v:97` |
| X32 | `icmp_gmii_tx_en` → `u_ctrl` 复用 | 1 | **无** | `eth_udp_video_top.v:212`、`eth_ctrl.v:104` |
| X33 | `icmp_gmii_txd` → `u_ctrl` 复用 | 8 | **无** | `eth_udp_video_top.v:212`、`eth_ctrl.v:105` |
| X34 | `udp_gmii_tx_en` → `u_ctrl` 复用 | 1 | **休眠** | `eth_udp_video_top.v:216`、`eth_ctrl.v:100` |
| X35 | `udp_gmii_txd` → `u_ctrl` 复用 | 8 | **休眠** | `eth_udp_video_top.v:216`、`eth_ctrl.v:101` |

（表内路径省略前缀 `src/rtl/eth/`；顶层连接行全在 `src/rtl/eth/eth_udp_video_top.v`。）

### 2.4 不算信号跨域、但会被 B 改性质的一条

**异步复位锥**：`rst_n = eth_rst_n & mmcm_locked`（`src/rtl/top/system_top.v:175`），而 `eth_rst_n` 由
`phy_rst_cnt_reg[23]` 在 **`sys_clk`** 域产生（`src/rtl/top/system_top.v:109-112`）。今天它是全部
`eth_rxc` 触发器的 `negedge rst_n` 异步清，`report_cdc` 已把这一族点名为 CDC-7 / CDC-13 / CDC-15
（`build/cdc_details.rpt:1379-1394`；CDC-13 两行落在 `u_eth/u_icmp_fifo/mem_reg/ENBWREN`、`/RSTRAMB`，
见 `:1383-1384`）。B 之后同一根 `rst_n` 要异步清**第二个** 125 MHz 域，这一族按发侧寄存器数增长，
**增量未量**。

### 2.5 小账

**35 条** RX↔TX 信号级 crossing（23 RX→TX + 12 TX→RX）+ 1 条异步复位级。其中 8 条属"休眠"
（X03、X06、X19、X20、X26、X29、X34、X35；根由写在 `eth_udp_video_top.v:158` 的自述与 `:166`），
今天没流量但**网表上仍是跨域**。

若把 `eth_ctrl` + 出口复用 + `icmp_dly` glue 整体搬到 TX 侧（这是唯一让 X22/X23 不至于要求"给线速 9 位
总线配同步器"的做法），则 **X21、X22、X23、X25…X35 共 16 条就地变 TX 内部**，需要真缓冲的只剩 19 条，
而 19 条按语义可并成 **4 条通道**：

1. ARP 事件通道：X07 + X08。
2. 对端地址快照通道：X01…X06（准静态，`arp_rx.v:157-158` 只在命中那一拍写）。
3. ICMP 请求事件 + 参数快照通道：X09…X15。
4. ICMP 载荷字节流通道：X16、X17、X18、X24（今天那只 `sync_fifo`）。

**按通道算是 4 条、按信号算是 19 条（35 条全部要重新定性）** —— 这就是"一整轮而不是顺手改"的量化理由。

---

## 3. 今天没有同步器、只因同钟才安全的点（B 会直接打断的）

### 3.1 三条最危险

1. **线速 9 位出口 X22/X23**：`gmii_tx_en/gmii_txd` 是逐拍有效的发送流
   （`src/rtl/eth/eth_ctrl.v:89-110`），直接进 ODDR 的 D1/D2
   （`src/rtl/eth/rgmii_tx.v:27-28`、`:45-46`）。这种流不能 2-FF，只能让复用器与三路发送器**一起**待在
   TX 域。凡"只换时钟、不换归属"的方案都在这一条上失败。
2. **`u_icmp_fifo` 读侧 X18/X24**：`sync_fifo` 只有一个 `clk`（`src/rtl/eth/sync_fifo.v:9`），
   `empty/full` 是同钟 `wptr == rptr` 的组合比较（`:24-27`）。分域后这套判据不是"有亚稳态风险"，
   而是**逻辑上不再成立**。
3. **逐包刷新的多位总线 X12/X13/X14/X15**：`icmp_id`/`icmp_seq`/`reply_checksum`/`tx_byte_num` 每个
   echo request 都换（写点 `src/rtl/eth/icmp_rx.v:242-246`、`:303`、`:310`），而 `icmp_tx` 在
   `st_idle` + `trig_tx_en` 那一拍整把采走（`src/rtl/eth/icmp_tx.v:258`、`:125-129`）。
   ⇒ "写完翻 toggle、对端再采"的准静态套路**在这里不成立**，参数必须与事件本身一起过。

### 3.2 那三条"看着像同步器"的移位链不算

`arp_tx.v:66-76`、`icmp_tx.v:103-113`、`udp_tx.v:77-87` 各有 `d0/d1/d2` 三级，配
`pos_tx_en = (~tx_en_d2) & tx_en_d1`（`src/rtl/eth/arp_tx.v:63`、`icmp_tx.v:99`、`udp_tx.v:73`）。
它们是**在同钟里捕一个脉冲的上升沿**，不是为 CDC 设计的：三处都没有 `ASYNC_REG`
（`grep ASYNC_REG src/rtl/eth/` 只命中 4 族：`dc_fifo.v:27`、`ddr_bank_commit.v:42`、
`eth_udp_video_top.v:277`、`snap_cross.v:36-37`），而源脉冲是恰好一拍宽
（`src/rtl/eth/eth_ctrl.v:159-160` 的注释与实现、`eth_udp_video_top.v:106`）。时钟一不同，
能不能采到取决于频率比与相位。⇒ **X11、X21 不能靠现成移位链交差**，要另配脉冲跨域件。

### 3.3 六条地址线是最好办的一组

X01…X06（`src_mac` 48 位 + `src_ip` 32 位）只在 ARP 命中那一拍被写
（`src/rtl/eth/arp_rx.v:156-158`），之后长期不变，TX 侧每帧重采一次
（`arp_tx.v:187`、`icmp_tx.v:253`、`:261`、`udp_tx.v:216`）。这正是 `snap_cross` 那套路子的适用前提
（`src/rtl/eth/snap_cross.v:2-5`）。**但要补一样今天不存在的东西**：`snap_cross` 采的是总线本身，
分域后必须配"写入完成"的 toggle，否则 48 位里可能采到半新半旧。

### 3.4 事件那两条需要一个新的发射件

X07（`arp_rx_done`）与 X09（`icmp_rec_pkt_done`）是 RX 侧单拍脉冲。仓里已有的脉冲跨域形状只有两种：
`ddr_bank_commit` 的"翻转 + 3FF + 异或出边沿"（`src/rtl/eth/ddr_bank_commit.v:37-47`，
`ASYNC_REG` 在 `:42`）与 `snap_cross` 的"边沿 + 整幅采样"（`src/rtl/eth/snap_cross.v:36-46`、`:69-72`）。
两者都能照抄，**都不必新写一个 CDC 原件**，但都要在源模块加一级 toggle（`arp_rx.v:156`、`icmp_rx.v:302`
今天只出脉冲、不出 toggle）。

### 3.5 顺带查到的两处死口（B 期间要一起处理）

- `u_ctrl` 的通用用户 FIFO 口对端不存在：`fifo_tx_data` / `fifo_tx_req` / `fifo_rec_en` /
  `fifo_rec_data` 只在 `src/rtl/eth/eth_udp_video_top.v:114-116` 声明、`:219-220` 连进去，本层再无驱动
  或读者；综合确实报过 `[Synth 8-3848] Net fifo_tx_data … does not have driver`
  （`report/log/issues.md:10549-10551`），`report/modules.md:125` 已登记这个缺口。
- `src/rtl/top/pl_video_top.v:103-106` 那四个 `eth_wr_*` 口被
  `src/rtl/top/system_top.v:303-306` 驱动，但 `pl_video_top.v` 全文除端口声明外**没有任何使用点**
  （`grep eth_wr_` 只命中 103-106）。与 B 无因果，只是钉一条：`eth_gmii_clk`
  （`eth_udp_video_top.v:387`）这个名字在顶层还挂着，**B 之后它仍是收侧钟，不许改接成 TX 钟**。

---

## 4. 现成 CDC 件能不能复用

**`dc_fifo` —— 可以，而且只有它能吃字节流。** 真双钟（`src/rtl/eth/dc_fifo.v:8`、`:13`），跨域只传
格雷码指针，四颗捕获寄存器 `wgray_s0/wgray_s1/rgray_s0/rgray_s1` 打了 `ASYNC_REG`
（`:27`，理由在 `:23-26`），移位链 `:82-95`，二进制指针永不跨域（`:81`）；满/空是格雷码比较
（`:47`、`:68`）。今天的实例 `u_cdc`：`DATA_W=36`、`ADDR_W=13`（8192 条），写侧 `gmii_rx_clk`、
读侧 `axi_clk`（`src/rtl/eth/eth_udp_video_top.v:298-305`）—— 它跨的是 RX → `clk_fpga_0`，与 B 无关，
但它是仓里唯一被门禁承认的"流可以走 FIFO"的先例。给 B 复用：ICMP 字节流（X16–X18、X24，今天
8 位 × 2048，`eth_udp_video_top.v:119`）换成 `dc_fifo #(.DATA_W(8), .ADDR_W(11))` 参数上就够
（`:4-5`）。`dc_fifo` 没有 `level` 口（对比 `sync_fifo.v:17`），而 `u_icmp_fifo` 今天就没接
（`eth_udp_video_top.v:122` 三个口是空括号），所以不损失。**已知代价**：现有 `u_cdc` 已经吃一条
CDC-5 Warning，起点 `u_eth/u_cdc/rgray_reg[13:0]/C`、终点 `u_eth/u_cdc/rgray_s0_reg[13:0]/D`
（`build/cdc_details.rpt:444`）；**新加一只会把同形状的 Warning 复制一份**，不阻塞但要预先记账。

**`sync_fifo` —— 不能复用。** 单 `clk` 口（`src/rtl/eth/sync_fifo.v:9`），`full/empty/level` 同钟比较
（`:24-27`），文件头自我定位就是"同时钟 FIFO，定位 `u_icmp_fifo`（收/发两侧同一根 gmii 时钟）"
（`:2`）。B 之后这只件**必须被替换**，加属性救不回来。

**`snap_cross` —— 吃 X01…X06，但要先给源端加 toggle。** 两条 `ASYNC_REG` 链
（`src/rtl/eth/snap_cross.v:36-37`）、边沿检测 `:41-46`、边沿那一拍整幅采 `bus`（`:69-72`）；
端口 `bus/bus_tog/hb_tog/bus_q/hb_gone/hb_slow` 见 `:16-30`，今天的实例是观测 lane
（`src/rtl/top/system_top.v:214-218`，`W=320`、目的域 `fclk0`）。用于 X01…X06 时 `W=80`。
**`hb_tog/hb_gone/hb_slow` 这一族对 TX 侧没有物理含义**（TX 不存在"源时基退化"），
接常量还是新开一版，本轮没决定 ⇒ 记为待设计。另注意 `snap_cross.v:20-26` 那条规矩：
复位分支走不到的场合必须写声明初值，新增 toggle 源要一起过上电初值判据
（`build/check_powup_init.sh` 是否覆盖新增位 **未量**）。

**`ddr_bank_commit` 的翻转+3FF —— 吃 X07/X09 这类单脉冲**
（`src/rtl/eth/ddr_bank_commit.v:37-47`，`ASYNC_REG` 在 `:42`），可直接照抄成两条事件线。

---

## 5. 现有工具与约束会怎么判

### 5.1 门禁第 6 项会直接判红

`build/gates.sh:108` 取 `CDCBASE=build/cdc_baseline.txt`，`:112` 的 `rows()` 从 `report_cdc` 汇总表抽
Critical 行的"源钟>目的钟 / 端点数 / unsafe"，`:135` 算**新增配对**，`:145-146` 写明
"新增 Critical 配对 ⇒ 这一项判红"，`:158` 再加一把尺子与采纳版
`build/evidence_r75/cdc.rpt` 比差集。

基线现在是 4 行（`build/cdc_baseline.txt:20-23`）：`eth_rxc>clk_fpga_0 272 1`、
`clk_fpga_0>clkout0_1 17 1`、`eth_rxc>clkout0_1 51 1`、`sys_clk>eth_rxc 1909 2`。
当前报告对应 `build/cdc.rpt:15-23`（Critical 两行：`clk_fpga_0→clkout0_1` 103 端点 1 unsafe、
`sys_clk→eth_rxc` 1968 端点 2 unsafe / 530 Unknown，`:17-18`）。

**B 之后必然新增的配对**：`eth_rxc>新TX钟` 与反向（35 条里只要有一条没被 FIFO 吃掉就会落上去）。
若新钟按 §1.3 由 `sys_clk` 的 MMCM 生成，它会落进 `sys_clk` 那一组，`sys_clk>eth_rxc` 那行的端点数
还会继续长。**这两条判红是设计带来的、不是 bug**，所以采纳 B 必须同轮改写
`build/cdc_baseline.txt`（该文件 `:8` 自己规定"只有某一版被采纳为新的默认时才允许改"）。

### 5.2 `report_cdc` 规则号：B 会让哪几类长

下表计数取 `build/r99_cdc_details.txt:8-15`（这是最新的可用摘要）；`build/cdc_details.rpt:19-25`
那份分类表是 2026-09-25 跑的，**比两份汇总报告旧**，只用它取具体行位置。

| 规则 | 含义 | r99 计数 | B 之后 |
|---|---|---|---|
| CDC-1 | 1-bit unknown CDC circuitry | 113（`:8`） | 会长：未标 `ASYNC_REG` 的单 bit 都算 |
| CDC-5 | 多位同步但缺 `ASYNC_REG` | 2（`:10`） | 每加一只 `dc_fifo` 复制一份（`build/cdc_details.rpt:444`） |
| CDC-7 | 异步复位造成 unknown CDC | 415（`:12`） | 会长：发侧寄存器挂 `phy_rst_cnt` 那根 `rst_n`（`:1379-1382`） |
| CDC-10 | 同步器前有组合逻辑 | 1（`:13`），唯一一条 `u_pl/u_cmt/d1_reg/C → u_pl/ac0_reg/D`（`:17-20`） | 不该长；若长出新的，就是 §3.2 那三条移位链被判成同步器 |
| CDC-13 | 1-bit CDC 落在非 FD 原件 | 2（`:14`），两条都在 `u_eth/u_icmp_fifo/mem_reg/ENBWREN`、`/RSTRAMB`（`build/cdc_details.rpt:1383-1384`） | **换掉 `sync_fifo` 后这两条应消失或搬家** ⇒ 本轮唯一一条"B 顺手能修的账" |
| CDC-15 | clock-enable 控制的 CDC 结构 | 1656（`:15`） | 会长（CE 挂跨域 enable） |

### 5.3 `report_methodology`

`build/methodology.rpt:34-36` 现在只有：TIMING-9 Unknown CDC Logic **1**、
TIMING-10 Missing property on synchronizer **1**、TIMING-18 Missing input or output delay **7**。
TIMING-10 就是"同步器没打 `ASYNC_REG`"（`build/methodology.rpt:2238-2240`）—— 新同步器少打属性会直接
让它从 1 变多。TIMING-18 那 7 条里 5 条是 RGMII **收**口（`eth_rx_ctl`、`eth_rxd[0..3]`，
`:2243-2266`），**发口一条都没有**，因为被 false path 掉了。

### 5.4 现有约束把谁排除在外

- 异步组只有一条命令、三组钟：`src/constraints/clock_groups_impl.xdc:28-31`
  （`eth_rxc` / `-quiet clk_fpga_0` / `-include_generated_clocks sys_clk`）；成员解释在 `:10-17`，
  结构保证的跨域路清单在 `:19-23`。**今天与 ETH 有关的组合只有 `eth_rxc ↔ clk_fpga_0` 与
  `eth_rxc ↔ sys_clk 家族`；TX 侧根本不在表里，因为它和 RX 同钟。**
- 默认构建只加载两份 XDC：`build/tcl/build_system_axigpio.tcl:31`（`rk_zynq7020.xdc`）与 `:36-37`
  （`clock_groups_impl.xdc`，`used_in_synthesis false`）；`r116`/`r119` 要环境变量
  （`:57-64`、`:75-82`），三份 `r114_*` **不在构建里**。
- ⇒ 那四条 `set_max_delay -datapath_only`（`src/constraints/r114_io_async.xdc:57-63`）
  **对默认构建不生效**，`clock_groups_impl.xdc` 里一条 `set_max_delay` 都没有。今天跨域路是
  **被 `set_clock_groups` 完全排除、没有任何延迟尺子**的状态（该文件 `:48-53` 自己就这么承认）。
- 发口被 false path：`src/constraints/rk_zynq7020.xdc:56`（`eth_tx_clk`）、`:57`（`eth_tx_ctl`）、
  `:58`（`eth_txd[*]`）。这笔账已立案：`report/timing/debt_ledger.md:76`（"文件里没有写当初理由"）、
  `report/timing_global.md:113`（RGMII 发送是源同步，"假路"是在说芯片到 PHY 不检查）。
  `build/check_timing_verbose.rpt:83-87` 点名 `eth_tx_ctl`/`eth_txd[0..3]`，
  而 `eth_tx_clk` 不在名单里（口径见 `build/check_io_timing_coverage.py:128` 的第 ③ 条；
  同文件 `:129` 把它列为 `CLOCK_OUTPUTS`）。
- `set_clock_uncertainty -hold 0.800` 只打在 `eth_rxc`（`src/constraints/rk_zynq7020.xdc:50`），
  其余三域没有这一行。

**哪些新跨域落在现有钟组之外**：只有当新 TX 钟**不是** `sys_clk` 的 MMCM 派生时才会出现"三组之外"。
按 §1.3 走 CLKOUT3 时它会自动成为 `sys_clk` 的生成钟、被 `-include_generated_clocks sys_clk` 抓进第三组
（同样的机制被 `clock_groups_impl.xdc:14-17` 用来抓 `clkout0_1`/`clkout1_1`/`clkout2`）。
**这个"自动被抓到"的推断本轮没量到**：`u_idelay_clkgen` 的 CLKOUT2 确实是
`build/clock_util.rpt:65` 的 `g6/clkout2`，但它与 `sys_clk` 的组关系在 `build/cdc.rpt:15-23` 里没有
独立行 ⇒ 现有报告证明不了，必须一次真构建读 `report_cdc` 汇总表。

---

## 6. 需要新写的约束清单

按"没有它就等于放开一把尺子"排序。每条给：写什么 / 今天为什么没有 / 判据。

1. **新钟的时钟定义**：走 `clk_gen` CLKOUT3 时**不需要**新写 `create_clock`
   （先例：`build/clock_util.rpt:60`、`:65` 里的自动派生名）。
2. **把新钟显式点名进时钟组**：`clock_groups_impl.xdc:28-31` 目前用 `-quiet` 兜 `get_clocks`，
   名字取不到时**整条命令空转**、连带把 `eth_rxc`/`sys_clk` 两组一起废掉，而只留一句 warning ——
   这个坑在 `src/constraints/rk_zynq7020.xdc:43-45` 与 `:65-74` 记了两次
   （症状 `CRITICAL WARNING [Vivado 12-4739]`）。⇒ 判据：构建日志里不许出现 12-4739；
   `report_cdc` 里 `eth_rxc` 与新钟必须写成 `Asynch Clock Groups`，不许是 `Safely Timed`。
3. **每条新同步通道的 `set_max_delay -datapath_only`**：为 §2.5 的 4 条通道各写一对，式样照
   `src/constraints/r114_io_async.xdc:57-63`（那里 `eth_rxc→clk_fpga_0` 用 10.000、反向 8.000）。
   今天默认构建一条都没有（§5.4）⇒ 这是净新增尺子，不是搬运。判据：`check_timing` 的
   "没覆盖"两类缺口不许变多；新写的 `set_max_delay` 必须真的出现在 `report_timing` 的路径头上。
4. **新域的 `set_clock_uncertainty`**：镜像 `rk_zynq7020.xdc:50`。TX 侧没有片外输入窗要防，取值应比
   0.800 小 —— **具体多少未量**（本轮不跑构建，只立"必须显式写、不许吃默认 0"这条判据）。
5. **发口时序的重新论证**：`rk_zynq7020.xdc:56-58` 那三条在 B 之后技术上仍成立（新 TX 钟就是送到 PHY 的
   GTXCLK），但 `debt_ledger.md:76` 已记为待复核、`timing_global.md:113` 要求改成 `set_output_delay`。
   规格书侧：**`TskewR = 1 / 1.8 / 2.6 ns` 已经抄进
   `src/constraints/r116_rgmii_input_window.xdc:18`，并明确标注"是 PHY 的接收端 = 我们 TXD/TXC 那一侧"**；
   同一条注里提到的 `TsetupR`/`TholdR` **数值没有抄进仓**（该文件只给了收口的
   `TsetupT/TholdT = min 1.2 / typ 2 ns`，`:15-17`）⇒ 想这一轮就绑发窗，缺的是那两个数，**未量**，
   不要拿 ±0.500 猜（"用错行"的两次已经记在 ISSUES #304/#309，`:19-20`）。
6. **异步复位那一族的定性**：`rst_n` 从 `sys_clk` 域异步清 TX 域（§2.4）。要么在 XDC 注释里写清并
   接受 CDC-7/CDC-13 条数增长、把它记进逐时钟名册，要么换复位结构。**增量未量**。

---

## 7. 需要重跑的台架清单

### 7.1 直接覆盖 TX 协议栈

| 台架 | 被测件（例化行） | 为什么必须重跑 |
|---|---|---|
| `sim/tb_icmp_ping0.v` | `icmp_tx`（`:60`） | `ping -l 0` 那一支，钉 `#188`（`src/rtl/eth/icmp_tx.v:351-358`） |
| `sim/tb_icmp_tx_cksum.v` | `icmp_tx`（`:48`） | 整帧逐字节指纹 + 校验和自洽（A1..A4） |
| `sim/tb_v112_ip_csum.v` | `icmp_tx`（`:47`） | IP 首部校验和十项求和、两次折叠 |
| `sim/tb_v112_tx_bytes.v` | `icmp_tx`（`:40`） | 发出的 72 字节流逐字节相等（`src/rtl/eth/icmp_tx.v:78-79` 指定的等价凭据） |
| `sim/tb_eth_video.v` | `udp_tx`（`:31`）、`crc32_d8`（`:41`）、`udp_rx`（`:49`）、`frame_reasm`（`:69`） | GMII 直环，UDP 发送侧唯一端到端件 |
| `sim/tb_crc32.v` | `crc32_d8`（`:22`） | 发侧 FCS 的独立实现对照 |
| `sim/tb_sync_fifo.v` | `sync_fifo`（`:23`） | **B 会替换掉这个件**：这一支随之退役或改判成 `dc_fifo` |

结构事实（这条决定台架工作量）：这七支**全是单时钟台架**。`sim/tb_icmp_tx_cksum.v:31-32` 只有一个
`always #4 clk = ~clk`，`des_mac/des_ip/icmp_id/icmp_seq/reply_checksum` 全是 `reg` 直驱
（`:34-43`），没有第二个时钟域可激励 ⇒ **双钟版本要新写**，工作量本轮未量。

### 7.2 覆盖"RX 事件触发 TX"那半条链

`sim/tb_icmp_rx_len.v`（`icmp_rx`，`:63`）、`sim/tb_icmp_len_wrap.v`（`icmp_rx`，`:51`）、
`sim/tb_v795_rx_chain.v`（`gmii_rx_mac` `:34`、`udp_rx_parser` `:42`）、
`sim/tb_v795_rx_fcs.v`（`gmii_rx_mac` `:36`）、`sim/tb_udp_parser.v`（`udp_rx_parser` `:28`）。
这五支不改时钟也照跑，但事件那一路（X07…X15）一旦换成 toggle+3FF，**端到端延迟会变**，
判据要一起复看。

### 7.3 查不到的部分（"没有台架"这句话的证据）

用行首例化形式 `^<模块名> <实例名>` 在 `sim/*.v` 里搜（避开注释假命中 —— 这个教训写在
`build/orphan_rtl.sh:11-16`），结果全为**空**：

- `arp`、`arp_rx`、`arp_tx`：没有任何台架例化。
- `eth_ctrl`：没有任何台架例化；`sim/tb_icmp_tx_cksum.v:10` 那一处只是注释引用源码行。
  同一缺口已登记在 `report/modules.md:125`。
- `rgmii_tx`、`rgmii_rx`、`gmii_to_rgmii`：没有任何台架例化。
- `eth_udp_video_top`、`system_top`：没有任何台架例化。`grep -l` 命中的
  `sim/tb_link_monitor.v`、`sim/tb_v5_bank.v`、`sim/tb_v6_ingress_integrity.v`、
  `sim/tb_v6_pingpong.v`、`sim/tb_v796_src_arb.v`、`sim/tb_v113_key_powup.v` 全是注释或复刻，
  不是例化（`sim/tb_v5_bank.v:4` 自己写着"bank FSM 是台架按 eth_udp_video_top 的 glue 复刻的 reg，
  不是例化件"）。
- 顶层台架 `sim/tb_v98_top_seam.v`、`sim/tb_v98_c8_edge_column.v` 的被测件是 `pl_video_top`
  （两文件 `:2`）⇒ **拿它们当"B 之后复验过发侧"是错的**。

### 7.4 板侧（属于重跑清单，不属于仿真）

- `src/host/one_click_test.mjs` 步骤 ① PING（`:117`、`:125-134`）是**唯一一条机器判定的
  ARP 应答 + ICMP 应答端到端证据**。
- `build/board_verify.sh` 不测 ping（全文 `grep -i "ping\|arp"` 命中 0），它管读回口 + 开机自检 +
  `--stream`/`--battery`/`--geom` 三档（`build/board_verify.sh:8-16`）。
- `bash build/gates.sh` 第 6 项整条重来，且 `build/cdc_baseline.txt` 与采纳版对照件
  `build/evidence_r75/cdc.rpt` 要在同一轮里一起更新。

---

## 8. 这份清单对"一轮还是一处"的回答

- **只改 `eth_udp_video_top.v` 一行时钟不够**：X22/X23（线速 9 位出口）与 X18/X24（`sync_fifo` 对侧读）
  在结构上不允许"只换时钟、不换归属"。
- 最小闭环 = 把 `eth_ctrl` + `icmp_dly` glue 迁到 TX 域（消掉 16 条）+ 新写 4 条通道（§2.5）
  + 把 `u_icmp_fifo` 换成 `dc_fifo` + §6 的 6 组约束 + §7 的 12 支台架与 3 项门禁/板侧复验。
  这与 `report/timing/eth_rxc_partition_options.md` 第 2 节当时写的"一整轮"一致，现在有行号可查。
- **B 的预期收益仍未量**：发侧从 4835 个 `eth_rxc` 端点（`build/timing_summary.rpt:182`）里搬走多少，
  只能从一次真构建的逐时钟名册差分读；本轮一次构建都没跑。
- 一条顺带可能修掉的账：CDC-13 那两条就落在今天要被替换的 `u_eth/u_icmp_fifo` 上
  （`build/cdc_details.rpt:1383-1384`）。

---

## 9. 自审：读出来的 / 没量到的

| 条目 | 状态 | 凭据，或"为什么没量到" |
|---|---|---|
| `gmii_tx_clk == gmii_rx_clk` 的三处独立声明 | 读出来 | `gmii_to_rgmii.v:25`、`eth_udp_video_top.v:5`、`eth_ctrl.v:3` |
| 35 条 crossing 的位宽 / 驱动 / 接收 / 行号 | 读出来 | §2.2、§2.3 证据列；本轮打开 17 个 `.v` 文件 |
| 其中 33 条完全没有同步器 | 读出来 | §2 表"同步形式"列 + `grep ASYNC_REG src/rtl/eth/` 只命中 4 族，全不在 TX 协议栈内 |
| X11/X21 的三级链不算同步器 | 读出来 | `arp_tx.v:66-76`、`icmp_tx.v:103-113` 无 `ASYNC_REG`；脉冲宽度 `eth_ctrl.v:159-160` |
| `dc_fifo` 可复用、`sync_fifo` 不可 | 读出来 | `dc_fifo.v:8`、`:13`、`:27`；`sync_fifo.v:2`、`:9`、`:24-27` |
| BUFG 8/32、MMCM 2/4、BUFIO 0/16 | 读出来 | `build/clock_util.rpt:43`、`:48`、`:45`（2026-10-04 04:37 路由后报告） |
| CLKOUT3…6 空闲、VCO/8 = 125 MHz | 读出来 | `clk_gen.v:19`、`:43-47` |
| `eth_rxc` 名册行 0.739 / 0.052 / 4835 / 2546 | 读出来 | `build/timing_summary.rpt:182` |
| 最差路径两端同钟 | 读出来 | `build/evidence_r75/timing_summary.rpt:354-355` |
| 默认只加载 2 份 XDC；`set_max_delay` 一条都不生效 | 读出来 | `build_system_axigpio.tcl:31`、`:36-37`；`r114_io_async.xdc:57-63` 未加载 |
| CDC 基线 4 行与门禁判红机制 | 读出来 | `build/cdc_baseline.txt:20-23`、`build/gates.sh:108`、`:112`、`:135`、`:145-146`、`:158` |
| CDC-1/5/7/10/13/15 计数与唯一 CDC-10 归属 | 读出来 | `build/r99_cdc_details.txt:8-20` |
| CDC-13 两条落在 `u_icmp_fifo` | 读出来 | `build/cdc_details.rpt:1383-1384`（该文件是 2026-09-25 的，比 §5.1 两份旧） |
| 台架覆盖矩阵（谁有 bench、谁没有） | 读出来 | §7.1、§7.2 的例化行；§7.3 的空命中 |
| `fifo_tx_data` 无驱动；`eth_wr_*` 无使用 | 读出来 | `report/log/issues.md:10549-10551`、`report/modules.md:125`；`pl_video_top.v:103-106` |
| `eth_tx_clk` 在 `check_timing` 名单里缺席的口径 | 读出来 | `build/check_io_timing_coverage.py:128`（第 ③ 条）、`:129` |
| **新 TX 钟的实际钟名，以及它是否真被 `-include_generated_clocks` 抓进 `sys_clk` 组** | 未量 | 需要一次真构建后的 `report_cdc` / `report_clock_networks`；现有报告里没有这个钟 |
| **B 之后的 WNS / 端点数 / 资源增量（即收益）** | 未量 | 只能从真构建的逐时钟名册差分读 |
| **新增 CDC-1/5/7/15 各长多少条** | 未量 | 需 `report_cdc -details` |
| **新域 `set_clock_uncertainty` 的取值** | 未量 | 无窗可依据，见 §6 第 4 条 |
| **PHY 发侧 `TsetupR` / `TholdR` 的数值**（仓里只有 `TskewR 1/1.8/2.6`） | 未量 | `src/constraints/r116_rgmii_input_window.xdc:18`；规格书原文不在本仓 |
| **新钟到 `AB22` 那只 ODDR 的时钟区域可达性** | 未量 | 只有 `g2` 跨 5 区这一条读数（`build/clock_util.rpt:61`），新钟从未布过 |
| **双时钟版本 TX 台架的工作量** | 未量 | 现有 7 支全为单钟（`sim/tb_icmp_tx_cksum.v:31-32`） |
| **`snap_cross` 用在 TX 侧时 `hb_tog/hb_gone/hb_slow` 怎么接** | 未量（待设计） | `snap_cross.v:16-30` 这一族是为"源时基退化"设计的，TX 侧无对应物理量 |
| **上电初值判据是否覆盖新增 toggle 源** | 未量 | `build/check_powup_init.sh` 本轮没跑 |
| `gmii_tx_mac.v` | 查不到 | 该文件不存在：`src/rtl/eth/` 全清单里没有 |

# A2 · 入流数据链路逐拍（网口 → DDR）

> 卷 A2：以太网入口侧收包链路的实现级拆解。所有结论以 `（文件:行号）` 溯源；无法从代码或既有报告判明的条目一律标注 `未证`。

## 目录

1. [物理层：RGMII→GMII、`IDDR`、`IDELAYE2` 与 `IDELAYCTRL`](#1-物理层rgmiigmiiiddriddelaye2-与-iddelayctrl)
2. [协议栈模块逐个：`eth_ctrl` / `arp_*` / `icmp_*` / `udp_rx_parser` / CRC](#2-协议栈模块逐个eth_ctrl--arp_-icmp_-udp_rx_parser--crc)
3. [UDP 载荷 → 像素：字节序、`pay_start`/`pay_end` 与长度常数分布](#3-udp-载荷--像素字节序paystartpay_end-与长度常数分布)
4. [`frame_reasm.v`：行环组织、就绪标志与帧提交条件](#4-frame_reasmv行环组织就绪标志与帧提交条件)
5. [AXI 写侧：请求切分、`awlen/awsize/awburst/wlast` 与 `dc_fifo` 的 CDC](#5-axi-写侧请求切分awlenawsizeawburstwlast-与-dcfifo-的-cdc)
6. [仲裁与健康：`src_arb` / `link_monitor`](#6-仲裁与健康srcarblinkmonitor)
7. [逐拍延迟表：从第一个 RGMII nibble 到第一个 DDR 写](#7-逐拍延迟表从第一个-rgmii-nibble-到第一个-ddr-写)
8. [各站「数据长什么样」汇总](#8-各站数据长什么样汇总)

---

## 1. 物理层：RGMII→GMII、`IDDR`、`IDELAYE2` 与 `IDELAYCTRL`

本节覆盖 `rgmii_rx` 一只模块（`src/rtl/eth/rgmii_rx.v`，全文 144 行）与它的两颗时钟来源（`src/rtl/clocks/clk_gen.v`、顶层 `src/rtl/top/system_top.v` 的参数下传链）。

### 1.1 端口与位宽

| 方向 | 端口 | 位宽 | 出处 |
| --- | --- | --- | --- |
| in | `idelay_clk` | 1 | `rgmii_rx.v:25` |
| in | `rgmii_rxc` | 1 | `rgmii_rx.v:28` |
| in | `rgmii_rx_ctl` | 1 | `rgmii_rx.v:29` |
| in | `rgmii_rxd` | 4 | `rgmii_rx.v:30` |
| out | `gmii_rx_clk` | 1 | `rgmii_rx.v:33` |
| out | `gmii_rx_dv` | 1 | `rgmii_rx.v:34` |
| out | `gmii_rxd` | 8 | `rgmii_rx.v:35` |

组合逻辑只有两句：`gmii_rx_clk = rgmii_rxc_bufg`（`rgmii_rx.v:47`）和 `gmii_rx_dv = gmii_rxdv_t[0] & gmii_rxdv_t[1]`（`rgmii_rx.v:48`）——后者是"上升沿和下降沿那两位都拉高才算有效"，等价于 GMII 的一整个字节周期。

### 1.2 nibble→byte 的拼法

5 只 `IDDR`：1 只给 `rx_ctl`（`u_iddr_rx_ctl`，`rgmii_rx.v:92`）+ generate 循环里 4 只给数据（`u_iddr_rxd`，`rgmii_rx.v:127`，循环上界 `i < 4` 在 `rgmii_rx.v:105`）。全部使用 `.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")`（`rgmii_rx.v:88` 控制通道 / `rgmii_rx.v:128` 数据通道），`.INIT_Q1(1'b0)`、`.INIT_Q2(1'b0)`、`.SRTYPE("SYNC")`（`rgmii_rx.v:89`–`rgmii_rx.v:91`），且 `.CE(1'b1)`、`.R(1'b0)`、`.S(1'b0)` 常开不复位（`rgmii_rx.v:96`–`rgmii_rx.v:99`）。

`SAME_EDGE_PIPELINED` 的语义在本模块被固定读成：`Q1` = 正沿采到的位、`Q2` = 负沿采到的位（`rgmii_rx.v:2` 的文件头与 `rgmii_rx.v:93`–`rgmii_rx.v:94` 的端口注释一致）。数据通道的位分配是

* `Q1(gmii_rxd[i])` —— 上升沿 → 字节**低**半段（`rgmii_rx.v:133`）
* `Q2(gmii_rxd[4+i])` —— 下降沿 → 字节**高**半段（`rgmii_rx.v:134`）

于是"RXC 上升沿那半字节是字节低位"这条约定不是靠约束保证的，是靠位索引硬接的（`rgmii_rx.v:2`）。

RGMII 没有 GMII 的 `RX_ER` 通道，本模块交不出错误标志（`rgmii_rx.v:6`），下游只能把 `gmii_rx_dv` 当唯一的有效性输入 —— 这一点决定了第 2 节里 `eth_ctrl` 无法从物理层拿到 CRC 失败提示。

### 1.3 时钟树：IDDR 与 fabric 同吃一只 BUFG

`BUFG BUFG_inst`（`rgmii_rx.v:51`–`rgmii_rx.v:54`）直接把 `rgmii_rxc` 送进全局树，输出 `rgmii_rxc_bufg`，同时是 `gmii_rx_clk`（`rgmii_rx.v:47`）和全部 5 只 IDDR 的 `.C`（`rgmii_rx.v:95`、`rgmii_rx.v:135`）。

改这一处的动机写在文件头：原先 IDDR 吃 `BUFIO`（SCD 3.171 ns）、fabric 吃 `BUFG`（DCD 4.854 ns），同频同相分走两条树，偏斜 +1.616 ns 由综合器插 hold buffer 硬补，导致 WHS 每次重建在 ±1 ps 抖动（`rgmii_rx.v:4`–`rgmii_rx.v:5`，并记为"r62 量到 +0.001"）。搬进同一棵树之后，报告里的 DCD 变成 5.008 ns、SCD = 0（`rgmii_rx.v:17`–`rgmii_rx.v:18`）。

125 MHz 这个数不由本工程产生 —— `gmii_rx_clk` 就是 PHY 出来的 `rgmii_rxc` 本身（`rgmii_rx.v:47`），顶层把它命名为 `eth_rxc` 输入（`system_top.v:174`）。

### 1.4 `IDELAYE2`：类型、现值、下传链

每只 IDELAYE2 的参数只有三项被覆盖，且 ctl 通道与数据通道逐字相同：

* `.IDELAY_TYPE("FIXED")` —— `rgmii_rx.v:68`（`u_delay_rx_ctrl`）与 `rgmii_rx.v:109`（`u_delay_rxd`）；可选值注释列为 FIXED / VARIABLE / VAR_LOAD / VAR_LOAD_PIPE
* `.IDELAY_VALUE(IDELAY_VALUE)` —— `rgmii_rx.v:69`、`rgmii_rx.v:110`，注释标 0–31
* `.REFCLK_FREQUENCY(200.0)` —— `rgmii_rx.v:70`、`rgmii_rx.v:111`

除 `IDELAY_VALUE` 之外的所有控制脚都被接地/接常量：`.C(1'b0)`、`.CE(1'b0)`、`.CINVCTRL(1'b0)`、`.CNTVALUEIN(5'b0)`、`.DATAIN(1'b0)`、`.INC(1'b0)`、`.LD(1'b0)`、`.LDPIPEEN(1'b0)`、`.REGRST(1'b0)`，`.CNTVALUEOUT()` 悬空（`rgmii_rx.v:72`–`rgmii_rx.v:83`，数据侧同构 `rgmii_rx.v:113`–`rgmii_rx.v:124`）。也就是说运行时不可调档、不可回读档位，档位是综合期常量，`FIXED` + 全 tie-off 是刻意的。

`IDELAY_VALUE` 现值 = **31**，唯一驱动点是 `system_top.v:172` 的 `.IDELAY_VALUE(31)`。下传链三级：`system_top.v:172` → `eth_udp_video_top.v:73`（`gmii_to_rgmii #(.IDELAY_VALUE(IDELAY_VALUE)) u_rgmii`，模块自身默认值 `eth_udp_video_top.v:14` 是 15）→ `gmii_to_rgmii.v:29` → `rgmii_rx.v:29`（`rgmii_rx` 自己的默认 `IDELAY_VALUE = 0` 在 `rgmii_rx.v:39`，实际从不生效）。

值的三段历史都在注释里，需注意它们互相冲突：

1. 早期 15 档；#57 把时钟源搬进 BUFG 后采样沿后移 1.683 ns，按 200 MHz 参考算 `1/(32×200 MHz) = 156 ps`/拍，+10.8 拍取 +11，得 26（`rgmii_rx.v:7`–`rgmii_rx.v:9`、`system_top.v:160`–`system_top.v:161`）。
2. r116 改成 31，理由换成"工具在真窗下的实测曲线"：hold 从 −2.822 抬到 −0.870（+63 ps/拍）、setup 从 +2.005 降到 −0.846（−92 ps/拍），两线交点在 tap 31（`system_top.v:162`–`system_top.v:168`）。
3. `rgmii_rx.v:21`–`rgmii_rx.v:23` 明确登记了 156 / 63 / 88 ps 三种斜率互不自洽，并写下"不当结论用"。⇒ **拍数与 ns 的换算关系：未证**。

这一族在 0–31 全档都关不掉时序：hold 查慢角（钟网络 5.008 ns）、setup 查快角（1.597 ns），角间差 3.4 ns 远大于数据路径的 0.47 ns（`system_top.v:169`–`system_top.v:171`）。

### 1.5 `IDELAYCTRL` 校准

单只 `IDELAYCTRL`，`IODELAY_GROUP = "rgmii_rx_delay"` 的 attribute 打了三处：`rgmii_rx.v:58`（本尊）、`rgmii_rx.v:66`（ctl 的 IDELAY）、`rgmii_rx.v:107`（generate 块标签行，块内 4 只共享）。`.REFCLK(idelay_clk)`、`.RST(1'b0)`、`.RDY()` 悬空（`rgmii_rx.v:60`–`rgmii_rx.v:62`）。

结论：校准只做上电那一次，之后不复校（`RST` 恒 0），且没有任何逻辑消费 `RDY`（悬空）。复位域内也看不到对 IDELAYCTRL 的复位请求 —— 上层 `rst_n` 只接到 eth 模块的复位（`system_top.v:175`）。风险面：`RDY` 未接 ⇒ 无法判定校准完成前是否已放行采样，代码上没有任何保护节拍。

### 1.6 200 MHz 参考钟从哪来

`idelay_clk` = `clk_200m`，出自 `clk_gen` 的 MMCM 第三路输出：`MMCME2_BASE` 实例 `u_mmcm`（`clk_gen.v:15`、`clk_gen.v:32`），输入 `CLKIN1_PERIOD(20.000)` 即 50 MHz（`clk_gen.v:17`），`CLKFBOUT_MULT_F(20.000)` ⇒ VCO = 1000 MHz（`clk_gen.v:19`、注释见 `clk_gen.v:3`），`CLKOUT2_DIVIDE(5)` 注释直写"200 MHz IDELAY ref"（`clk_gen.v:27`），经 `BUFG u_bufg_200` 出 `clk_200m`（`clk_gen.v:56`）。同一只 MMCM 的另两路是 50 MHz 像素钟（`CLKOUT0_DIVIDE_F(20.000)`，`clk_gen.v:21`→`u_bufg_pix`，`clk_gen.v:54`）与 250 MHz 5x 钟（`CLKOUT1_DIVIDE(4)`，`clk_gen.v:24`→`u_bufg_5x`，`clk_gen.v:55`）。`LOCKED` 引出为 `locked`（`clk_gen.v:50`），顶层用它与 `eth_rst_n` 相与作为 eth 的复位（`system_top.v:175`）。

注意 `REFCLK_FREQUENCY(200.0)` 与实际 `CLKOUT2_DIVIDE(5)` 是两处独立声明，一致性靠人工维护；改分频而忘改这一项，IDELAY 的 ps/拍 会静默错标（这里只述机制，是否曾错过：未证）。

### 1.7 补记：TX 侧共钟与第四种 "ps/档" 说法

`gmii_to_rgmii.v:25` 的 `assign gmii_tx_clk = gmii_rx_clk;   // TX 侧不发自己的时钟，见文件头` 是第 2 节"全 ETH 单时钟域"结论的物理依据（`eth_ctrl.v:3`–`eth_ctrl.v:4` 正是引用这句）。同文件的 `u_rgmii_rx` 例化把参数原样下传（`gmii_to_rgmii.v:28`–`gmii_to_rgmii.v:30`，`idelay_clk` 同脚 `gmii_to_rgmii.v:31`）。

第四种每档延时的说法出现在 `gmii_to_rgmii.v:23` 的注释里：`parameter IDELAY_VALUE = 0;  //输入数据IO延时(如果为n,表示延时n*78ps)`。把四种口径并排列出，供后续修订时统一：

| 说法 | ps/档 | 出处 |
| --- | --- | --- |
| 200 MHz 参考推算 `1/(32×f)` | 156 | `rgmii_rx.v:8`、`system_top.v:161` |
| 真窗下 hold 实测斜率 | ≈63 | `rgmii_rx.v:19`、`system_top.v:166` |
| 报告里 IDELAYE2 的 2.292 ns / 26 档 | ≈88 | `rgmii_rx.v:22` |
| 本模块链上的老注释 | 78 | `gmii_to_rgmii.v:23` |
| setup 侧斜率（负向）与交点解 | −92 / 0.155 ns 差 | `system_top.v:166`–`system_top.v:167` |

`rgmii_rx.v:21`–`rgmii_rx.v:23` 只登记了前三种的互不一致并写明"不当结论用"；78 ps 这条比那份注释更早、且没有出现在冲突登记里。⇒ 本卷采信的结论只有一条：**采样点的绝对 ns 位置无法由代码确定**，能确定的只有档位（31）与参考钟频率声明（200.0，`rgmii_rx.v:70`）。

> **数据在这一站长什么样**：入口是 4 bit 并行 nibble + 1 bit `RXC` + 1 bit `RX_CTL`，DDR，理论线速 1 Gb/s ⇒ 每 8 ns 一个 nibble、每 16 ns 一个字节。出口是 `gmii_rxd[7:0]` 单字节 SDR，随 `gmii_rx_clk`（= 片外 RXC，125 MHz）每拍一个字节，`gmii_rx_dv` 高电平期间有效（`rgmii_rx.v:47`–`rgmii_rx.v:48`）。字节内位序由位索引定死：低半段来自上升沿、高半段来自下降沿（`rgmii_rx.v:133`–`rgmii_rx.v:134`），且 `SAME_EDGE_PIPELINED` 保证 Q1/Q2 同拍对齐（`rgmii_rx.v:88`）。这一层没有错误通道（`rgmii_rx.v:6`），所以"采样点偏离眼心"表现为**静默的位错**：字节值随机翻位，CRC 在第 2 节才被算出来。按现有实现，位错会让 `udp_rx_parser` 的 `udp_len`/端口字段读歪，进而包被丢弃；屏幕上应表现为丢帧或画面撕裂 —— 但工程里并未把 RGMII 位错单独计数（`bad`/`drop_words` 是下游计数，见 `rgmii_rx.v:11`），因此"某一位错具体对应屏幕上什么图案"：**未证**。

---

## 2. 协议栈模块逐个：`eth_ctrl` / `arp_*` / `icmp_*` / `udp_rx_parser` / CRC

收侧的模块顺序是：`gmii_rx_mac`（成帧 + FCS 判定）→ `udp_rx_parser`（过滤 + 剥头）→ `frame_reasm`（第 4 节）。`arp_rx` / `icmp_rx` 是**旁路**嗅探器，直接从 `gmii_rxd`/`gmii_rx_dv` 吃原始字节；`eth_ctrl` 管的是发送侧三路仲裁，收侧只做二选一转发。

### 2.1 `gmii_rx_mac.v` —— 成帧与唯一错误源

端口（`gmii_rx_mac.v:8`–`gmii_rx_mac.v:20`）：`clk` 1、`rst_n` 1、`gmii_rxd` 8、`gmii_rx_dv` 1、`gmii_rx_er` 1、`m_data` 8、`m_valid` 1、`m_sof` 1（"first payload byte (DA[0])"）、`m_eof` 1（"last byte (FCS[3])"）、`m_good` 1、`m_bad` 1。

状态机三态（`gmii_rx_mac.v:25`–`gmii_rx_mac.v:27`），实现在 `gmii_rx_mac.v:87`–`gmii_rx_mac.v:114` 的 `case (state)`：

| 现态 | 吃哪些字节 | 转移条件 | 去向 |
| --- | --- | --- | --- |
| `S_WAIT` | 前导码 `0x55` 之前的空闲 | `gmii_rxd == 8'h55`（`gmii_rx_mac.v:89`） | `S_PRE`，`cnt <= 16'd1`（`gmii_rx_mac.v:91`） |
| `S_PRE` | 前导码余下字节 | `gmii_rxd == 8'hD5` ⇒ SFD（`gmii_rx_mac.v:95`）；仍是 `8'h55` 则 `cnt+1` 留在本态（`gmii_rx_mac.v:99`–`gmii_rx_mac.v:100`）；其它值退回（`gmii_rx_mac.v:101`–`gmii_rx_mac.v:104`） | `S_DATA` + `saw_sfd <= 1'b1`（`gmii_rx_mac.v:96`–`gmii_rx_mac.v:98`） |
| `S_DATA` | DA 起的全部字节（含 4 字节 FCS） | 只要 `gmii_rx_dv` 继续为 1 就一直 `cnt+1`（`gmii_rx_mac.v:110`），首字节打 `m_sof`（`gmii_rx_mac.v:109`） | 见下 |

帧尾不在状态里判，而在 `gmii_rx_dv` 掉下来的那一拍判（`gmii_rx_mac.v:69`–`gmii_rx_mac.v:85`）：`state == S_DATA` 时打 `m_eof`，同拍按 `!er_seen && !gmii_rx_er && (cnt >= 16'd64) && fcs_ok` 决定 `m_good` 还是 `m_bad`（`gmii_rx_mac.v:76`–`gmii_rx_mac.v:80`）。这里的脉冲约定很关键：`m_eof` 与 `m_good/m_bad` 同拍、而那一拍 `m_valid` 已经为 0，即"最后一个字节在上一拍就出去了"（注释 `gmii_rx_mac.v:71`–`gmii_rx_mac.v:74`）。V7.9.5 之前 `m_eof` 声明了、复位清了，却没有任何一处写 1（`gmii_rx_mac.v:73`–`gmii_rx_mac.v:74`）。

FCS 判定用的是残值法：整帧（含 FCS 那 4 字节）过发送侧同一只 `crc32_d8`，一帧算完留下的常数 `FCS_RESIDUE = 32'hC7_04_DD_7B`（`gmii_rx_mac.v:23`，注释强调"实测值、不是推算值"，`gmii_rx_mac.v:21`–`gmii_rx_mac.v:22`），`fcs_ok = (crc_q == FCS_RESIDUE)`（`gmii_rx_mac.v:48`）。累加门控 `crc_en = in_data = (state == S_DATA) && gmii_rx_dv`（`gmii_rx_mac.v:35`）；清零只发生在 SFD 那一拍：`crc_clr ((state == S_PRE) && gmii_rx_dv && (gmii_rxd == 8'hD5))`（`gmii_rx_mac.v:42`），因为若在第一个数据字节当拍清，`crc_clr` 的优先级会吞掉第 0 字节（`gmii_rx_mac.v:43`–`gmii_rx_mac.v:44`）。`crc_next()` 在本例化悬空（`gmii_rx_mac.v:46`）。

`gmii_rx_er` 在 RGMII 板上恒为 0（`gmii_rx_mac.v:32`，且第 1 节已说明 RX_CTL 不当错误位用），所以"没有 ER"这条判据恒真（`gmii_rx_mac.v:4`–`gmii_rx_mac.v:6`）——FCS 残值是收侧唯一真实错误源。

`crc32_d8.v` 本体：`clk`/`rst_n`/`data[7:0]`/`crc_en`/`crc_clr` 入，`crc_data[31:0]` 寄存输出、`crc_next[31:0]` 组合输出（`crc32_d8.v:5`–`crc32_d8.v:12`），全文 91 行（`crc32_d8.v:91`），无状态机。

### 2.2 `udp_rx_parser.v` —— 字节索引状态机

参数 `UDP_PORT = 16'd5001`（`udp_rx_parser.v:5`）。端口（`udp_rx_parser.v:7`–`udp_rx_parser.v:23`）：入 `clk`、`rst_n`、`s_data[7:0]`、`s_valid`、`s_sof`、`s_eof`、`s_good`、`s_bad`；出 `p_data[7:0]`、`p_valid`、`p_sof`、`p_eof`、`p_good`、`pay_len[15:0]`、`stat_drop_bad`、`stat_drop_filt`、`stat_udp_ok`。

没有显式 `case`，状态是 `bcnt`（帧内字节索引，`udp_rx_parser.v:30`）+ `accept`/`in_pay`/`eof_pend`（`udp_rx_parser.v:36`–`udp_rx_parser.v:38`）三位的隐式阶段机。逐字节职责：

| `bcnt` | 吃的字节 | 动作 | 出处 |
| --- | --- | --- | --- |
| 12, 13 | IPv4 type 字段（帧内偏移 12–13，即 EtherType） | 存进 `proto_chk[15:8]` / `[7:0]` | `udp_rx_parser.v:117`–`udp_rx_parser.v:118` |
| 14 | IPv4 ver/ihl 首字节 | `b14 <= s_data`、`ihl <= s_data[3:0]` | `udp_rx_parser.v:119`–`udp_rx_parser.v:122` |
| 20, 21 | IPv4 flags 两字节 | `b20`、`b21` | `udp_rx_parser.v:123`–`udp_rx_parser.v:124` |
| 23 | IPv4 protocol | `b23` | `udp_rx_parser.v:125` |
| `14 + ihl*4` | UDP 首字节（源端口高） | 定 `udp_off`、`pay_start`，判过滤 | `udp_rx_parser.v:137`–`udp_rx_parser.v:148` |
| `udp_off+2/+3` | 目的端口高/低 | 与 `UDP_PORT` 比 | `udp_rx_parser.v:158`、`udp_rx_parser.v:151`–`udp_rx_parser.v:157` |
| `udp_off+4/+5` | UDP length 高/低 | 存 `udp_len`、算 `pay_end` | `udp_rx_parser.v:159`–`udp_rx_parser.v:162` |
| `[pay_start, pay_end]` | 载荷 | 逐字节发 `p_data`/`p_valid` | `udp_rx_parser.v:172`–`udp_rx_parser.v:186` |

接受条件（四合一，`udp_rx_parser.v:141`–`udp_rx_parser.v:143`）：`proto_chk == 16'h0800`、`b14[7:4] == 4'h4`、`b23 == 8'd17`、`{b20, b21} == 16'h0000`（不分片）。任一不满足 ⇒ `accept <= 1'b0; stat_drop_filt <= 1'b1`（`udp_rx_parser.v:145`–`udp_rx_parser.v:146`）；目的端口不匹配同样 `stat_drop_filt`（`udp_rx_parser.v:153`–`udp_rx_parser.v:155`）。

错误路径三条：

1. `s_bad` 同拍强制闭合：`stat_drop_bad <= 1'b1`，若 `eof_pend || in_pay` 则补一个 `p_eof` 且 `p_good <= 1'b0`，并清零 `bcnt/in_pay/accept`（`udp_rx_parser.v:92`–`udp_rx_parser.v:106`）。注释给出理由：坏帧不闭合的话，下一包的字节会接到这一包后面，"那比丢一帧更坏"（`udp_rx_parser.v:94`–`udp_rx_parser.v:95`）。
2. 帧到尾但 `udp_len` 声明的字节没发完 ⇒ 畸形包，`p_eof` + `p_good = 1'b0` + `pay_len <= pay_cnt`（`udp_rx_parser.v:202`–`udp_rx_parser.v:207`）。
3. 每拍默认清零三个统计位（脉冲化）——`stat_udp_ok`、`stat_drop_bad`、`stat_drop_filt`（`udp_rx_parser.v:85`、`udp_rx_parser.v:89`–`udp_rx_parser.v:90`），此前两位没有默认值，变成"见过一次坏帧就永远为 1"的粘连电平（`udp_rx_parser.v:86`–`udp_rx_parser.v:88`）。

一处曾经的坑值得记：`ihl` 在 `bcnt==14` 当拍才被存进去，同拍读到的还是旧值 0，于是 `bcnt == 14 + ihl*4` 在 `bcnt==14` 也成立，每帧提前判定一次 ⇒ 每帧误发一次 `stat_drop_filt`。修法是加 `(ihl != 4'd0)` 前置（`udp_rx_parser.v:133`–`udp_rx_parser.v:137`）。另外 `ETH_HDR = 14` 这个 localparam 声明在 `udp_rx_parser.v:28`，本文件的判定逻辑里全部用字面量 14，没引用它。

### 2.3 `arp_rx` / `arp_tx` / `icmp_rx` / `icmp_tx`

`arp_rx`（`#(...)` 带 `BOARD_MAC = 48'h00_11_22_33_44_55`、`BOARD_IP = {8'd192,8'd168,8'd1,8'd10}`，`arp_rx.v:8`、`arp_rx.v:10`）：入 `clk`/`rst_n`/`gmii_rx_dv`/`gmii_rxd[7:0]`（`arp_rx.v:12`–`arp_rx.v:16`），出 `arp_rx_done`、`arp_rx_type`（0 请求 / 1 应答）、`src_mac[47:0]`、`src_ip[31:0]`（`arp_rx.v:17`–`arp_rx.v:20`）。独热态 `st_idle`/`st_preamble`/`st_eth_head`/`st_arp_data`/`st_rx_end`（`arp_rx.v:24`–`arp_rx.v:28`，`reg [4:0] cur_state`/`next_state`，`arp_rx.v:32`–`arp_rx.v:33`），类型码 `ETH_TPYE = 16'h0806`（原文如此，拼写少了 T，`arp_rx.v:29`）。解析计数器 `cnt[4:0]`、暂存 `des_mac_t`/`des_ip_t`/`src_mac_t`/`src_ip_t`/`eth_type`/`op_data`（`arp_rx.v:36`–`arp_rx.v:42`）。错误路径是 `error_en`：默认每拍清 0（`arp_rx.v:86`、`arp_rx.v:100`），在 `st_eth_head`/`st_arp_data` 的字段比对失败处置 1（`arp_rx.v:111`、`arp_rx.v:127`），置 1 后本包不再报 `arp_rx_done`。全文 181 行（`arp_rx.v:181`）。

`arp_tx`：入 `arp_tx_en`、`arp_tx_type`、`des_mac[47:0]`、`des_ip[31:0]`、`crc_data[31:0]`、`crc_next[7:0]`（`arp_tx.v:10`–`arp_tx.v:15`），出 `tx_done`、`gmii_tx_en`、`gmii_txd[7:0]`、`crc_en`、`crc_clr`（`arp_tx.v:16`–`arp_tx.v:20`）。五态 `st_idle`/`st_preamble`/`st_eth_head`/`st_arp_data`/`st_crc`（`arp_tx.v:34`–`arp_tx.v:38`，`reg [4:0] cur_state` `arp_tx.v:46`），`ETH_TYPE = 16'h0806`、`HD_TYPE = 16'h0001`、`PROTOCOL_TYPE = 16'h0800`、`MIN_DATA_NUM = 16'd46`（`arp_tx.v:39`–`arp_tx.v:43`），前导码用数组常量 `preamble[7:0]`（`arp_tx.v:48`）。

`icmp_rx`：入 `gmii_rx_dv`、`gmii_rxd[7:0]`（`icmp_rx.v:11`–`icmp_rx.v:12`），出 `rec_pkt_done`、`rec_en`、`rec_data[7:0]`、`rec_byte_num[15:0]`、`icmp_id[15:0]`、`icmp_seq[15:0]`、`reply_checksum[31:0]`（`icmp_rx.v:13`–`icmp_rx.v:20`）。七态 `st_idle`/`st_preamble`/`st_eth_head`/`st_ip_head`/`st_icmp_head`/`st_rx_data`/`st_rx_end`（`icmp_rx.v:31`–`icmp_rx.v:37`，`reg [6:0] cur_state` `icmp_rx.v:47`）；`ICMP_TYPE = 8'd1`、`ECHO_REQUEST = 8'h08`（`icmp_rx.v:41`、`icmp_rx.v:44`）；字段寄存器含 `ip_head_byte_num[5:0]`、`total_length[15:0]`、`icmp_type`/`icmp_code`/`icmp_checksum`/`icmp_data_length`/`icmp_rx_cnt`（`icmp_rx.v:57`–`icmp_rx.v:65`）。`error_en`（`icmp_rx.v:50`）与 `data_len_zero`（`icmp_rx.v:51`–`icmp_rx.v:52`，处理 IP 总长正好 28 即 `ping -l 0` 的合法无数据包）是两条错误/特例路径。全文 320 行（`icmp_rx.v:320`）。

`icmp_tx`：入 `reply_checksum[31:0]`、`icmp_id[15:0]`、`icmp_seq[15:0]`、`tx_start_en`、`tx_data[7:0]`、`tx_byte_num[15:0]`、`des_mac[47:0]`、`des_ip[31:0]`、`crc_data[31:0]`、`crc_next[7:0]`（`icmp_tx.v:12`–`icmp_tx.v:21`），出 `tx_done`、`tx_req`、`gmii_tx_en`、`gmii_txd[7:0]`、`crc_en`、`crc_clr`（`icmp_tx.v:22`–`icmp_tx.v:27`）。八态含两次校验阶段 `st_check_sum`（IP 首部）与 `st_check_icmp`（ICMP 首部+数据）（`icmp_tx.v:41`–`icmp_tx.v:48`，`reg [7:0] cur_state` `icmp_tx.v:62`），`MIN_DATA_NUM = 16'd18`（`icmp_tx.v:55`），`check_buffer[19:0]` / `check_buffer_icmp[31:0]` 做和校验累加（`icmp_tx.v:80`–`icmp_tx.v:81`）。`tx_bit_sel[1:0]` + `data_cnt[15:0]` 负责把 32 bit 头数组 `ip_head[6:0]`（`icmp_tx.v:66`）拆成字节发（`icmp_tx.v:82`–`icmp_tx.v:83`）。全文 455 行（`icmp_tx.v:455`）。

### 2.4 `eth_ctrl.v` —— 发侧仲裁 + 收侧二选一转发

端口全表（方向按声明，位宽未写的即 1 bit）：

| 端口 | 方 | 位宽 | 行 | 端口 | 方 | 位宽 | 行 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `clk` | in | 1 | `eth_ctrl.v:7` | `icmp_tx_req` | in | 1 | `eth_ctrl.v:25` |
| `rst_n` | in | 1 | `eth_ctrl.v:8` | `icmp_tx_data` | out | 8 | `eth_ctrl.v:26` |
| `arp_rx_done` | in | 1 | `eth_ctrl.v:10` | `udp_tx_start_en` | in | 1 | `eth_ctrl.v:28` |
| `arp_rx_type` | in | 1 | `eth_ctrl.v:11` | `udp_tx_done` | in | 1 | `eth_ctrl.v:29` |
| `arp_tx_en` | out reg | 1 | `eth_ctrl.v:12` | `udp_gmii_tx_en` | in | 1 | `eth_ctrl.v:30` |
| `arp_tx_type` | out | 1 | `eth_ctrl.v:13` | `udp_gmii_txd` | in | 8 | `eth_ctrl.v:31` |
| `arp_tx_done` | in | 1 | `eth_ctrl.v:14` | `udp_rec_data` | in | 8 | `eth_ctrl.v:33` |
| `arp_gmii_tx_en` | in | 1 | `eth_ctrl.v:15` | `udp_rec_en` | in | 1 | `eth_ctrl.v:34` |
| `arp_gmii_txd` | in | 8 | `eth_ctrl.v:16` | `udp_tx_req` | in | 1 | `eth_ctrl.v:35` |
| `icmp_tx_start_en` | in | 1 | `eth_ctrl.v:18` | `udp_tx_data` | out | 8 | `eth_ctrl.v:36` |
| `icmp_tx_done` | in | 1 | `eth_ctrl.v:19` | `tx_data` | in | 8 | `eth_ctrl.v:38` |
| `icmp_gmii_tx_en` | in | 1 | `eth_ctrl.v:20` | `tx_req` | out | 1 | `eth_ctrl.v:39` |
| `icmp_gmii_txd` | in | 8 | `eth_ctrl.v:21` | `rec_en` | out reg | 1 | `eth_ctrl.v:40` |
| `icmp_rec_en` | in | 1 | `eth_ctrl.v:23` | `rec_data` | out reg | 8 | `eth_ctrl.v:41` |
| `icmp_rec_data` | in | 8 | `eth_ctrl.v:24` | `gmii_tx_en` | out reg | 1 | `eth_ctrl.v:43` |
| — | — | — | — | `gmii_txd` | out reg | 8 | `eth_ctrl.v:44` |

内部状态只有 6 项：`protocol_sw[1:0]`（`eth_ctrl.v:48`）、`icmp_tx_busy`（`eth_ctrl.v:49`）、`udp_tx_busy`（`eth_ctrl.v:50`）、`arp_rx_flag`（`eth_ctrl.v:51`）、`icmp_tx_req_d0`/`udp_tx_req_d0`（`eth_ctrl.v:52`–`eth_ctrl.v:53`）、`arp_pend`（`eth_ctrl.v:142`）。`icmp_tx_data`/`udp_tx_data` 在声明里就是 8 bit（`eth_ctrl.v:26`、`eth_ctrl.v:36`），由 `assign` 给出选择结果（`eth_ctrl.v:57`–`eth_ctrl.v:58`）：本路请求未拉起时该输出被赋常量 0。

整块跑 `clk = gmii_rx_clk`，因为 RGMII 下 `gmii_tx_clk` 就是 `gmii_rx_clk` 本身，所以全 ETH 逻辑实际单时钟域（`eth_ctrl.v:3`–`eth_ctrl.v:4`）——这是本卷"入流无 CDC"结论的第一个落点。

仲裁不是经典 FSM，而是 `protocol_sw[1:0]` 的三值 mux（`eth_ctrl.v:48`，`case` 在 `eth_ctrl.v:94`–`eth_ctrl.v:108`）：`2'b00`=ARP、`2'b01`=UDP、`2'b10`=ICMP（`eth_ctrl.v:2`）。转移由三条 start/done 线驱动：`udp_tx_start_en` ⇒ `2'b01`（`eth_ctrl.v:151`–`eth_ctrl.v:152`）、`icmp_tx_start_en` ⇒ `2'b10`（`eth_ctrl.v:153`–`eth_ctrl.v:154`）、ARP 授权 ⇒ `2'b0` 同时 `arp_tx_en <= 1'b1`（`eth_ctrl.v:155`–`eth_ctrl.v:161`）。忙标志 `icmp_tx_busy`/`udp_tx_busy` 在 start 置 1、done 清 0（`eth_ctrl.v:113`–`eth_ctrl.v:119`、`eth_ctrl.v:123`–`eth_ctrl.v:128`）。

V7.9 的 ARP 记账（`arp_pend`，`eth_ctrl.v:142`）三处细节都带原因：

* 原来只有一拍宽的 `arp_rx_flag`（`eth_ctrl.v:130`–`eth_ctrl.v:135`）若把授权条件从 `||` 改成 `&&`，请求会在"另一路正在发"的那一拍被丢掉，PC 要等 ARP 超时重发 ⇒ 改成记账（`eth_ctrl.v:137`–`eth_ctrl.v:139`）。
* 记账与兑现必须在同一个 `always` 里，否则 `arp_tx_en` 连高两拍、ARP 帧第 0 字节被重发（`eth_ctrl.v:140`–`eth_ctrl.v:141`）。
* 兑现条件要的是"全部空闲"`(udp_tx_busy == 1'b0) && (icmp_tx_busy == 1'b0)`，原文两个 busy 用 `||` 会在帧中间把 mux 切给 ARP（`eth_ctrl.v:155`–`eth_ctrl.v:157`）；清账与授权同拍，所以 `arp_tx_en` 恰好一拍宽（`eth_ctrl.v:160`）；记账语句放最后，避免同拍新请求被这次授权吃掉（`eth_ctrl.v:162`–`eth_ctrl.v:163`）。

收侧转发只有一句优先级：`icmp_rec_en` 优先于 `udp_rec_en`，`rec_en`/`rec_data` 各打一拍（`eth_ctrl.v:72`–`eth_ctrl.v:86`）——即收侧数据在本模块**引入 1 拍延迟**。发侧 FIFO 读请求 `tx_req = udp_tx_req ? 1'b1 : icmp_tx_req`（`eth_ctrl.v:56`），数据回送经各自寄存一拍 `*_tx_req_d0`（`eth_ctrl.v:52`–`eth_ctrl.v:53`、`eth_ctrl.v:61`–`eth_ctrl.v:69`），未选中的一路恒 `8'd0`（`eth_ctrl.v:57`–`eth_ctrl.v:58`）。ARP 应答类型硬编 `arp_tx_type = 1'b1`（`eth_ctrl.v:55`）。

> **数据在这一站长什么样**：进 `udp_rx_parser` 的是 `s_data[7:0]` 单字节、125 MHz 每拍最多一个、连续无泡（GMII 语义，`gmii_rx_mac.v:14`–`gmii_rx_mac.v:17`），首尾由 `m_sof`/`m_eof` 标注，好坏由 `m_good`/`m_bad` 同拍标注（`gmii_rx_mac.v:16`–`gmii_rx_mac.v:19`）。出的是 `p_data[7:0]` 载荷字节 + `p_sof`/`p_eof`/`p_good` + 一包总字节数 `pay_len`（`udp_rx_parser.v:15`–`udp_rx_parser.v:20`），字节序**原样透传**、不重排（`p_data <= s_data`，`udp_rx_parser.v:174`）。这一层出错的可观测后果：FCS 残值不符 ⇒ `m_bad` ⇒ 整包以 `p_good=0` 闭合（`udp_rx_parser.v:98`–`udp_rx_parser.v:100`），表现为整帧丢弃而非局部坏点；过滤判据错 ⇒ `stat_drop_filt`，画面表现为完全无更新；而 `p_eof` 漏发（历史上真发生过，见 `udp_rx_parser.v:169`–`udp_rx_parser.v:171` 的 FCS 4 字节混进载荷）在屏幕上就是**每包多 4 字节的确定性错位**，即整行右移 2 个像素的斜纹。"斜纹"这一具体图案为按错位量推导，板上实拍记录：**未证**。

---

## 3. UDP 载荷 → 像素：字节序、`pay_start`/`pay_end` 与长度常数分布

### 3.1 线格式：4 字节偏移前缀 + RGB565 载荷

三份发侧实现在协议上必须逐字一致：每包 = `[u32 LE byte_offset][RGB565 载荷]`。

* `src/host/video_sender.py:9` 的注释口径与 `src/host/video_sender.mjs:9` 的 "每包 [u32 LE byte_offset][RGB565 载荷], 载荷 <= 1392 B（8 的倍数）" 相同。
* 前缀的构造：`sock.sendto(struct.pack("<I", off) + chunk, addr)` —— `video_sender.py:161`、`udp_push.py:69`（JS 侧同构，见 `video_sender.mjs:193`–`video_sender.mjs:196` 的 `sendFrame` 切片循环）。`"<I"` 即小端无符号 32 位。
* 像素打包：`struct.pack("<H", px)` 重复 `W*H` 次（`udp_push.py:57`），测试图形同样用 `"<H"`（`video_sender.py:105`、`video_sender.py:116`、`video_sender.py:118`）⇒ **每个 RGB565 像素低字节在前**。

收侧的对应拆解：`off<={24'd0,p_data}`→`off[15:8]`→`off[23:16]`→`off[31:24]` 按 S_OFF0..S_OFF3 逐字节填（`frame_reasm.v:126`–`frame_reasm.v:130`），即第 1 个字节是偏移的最低位，与小端约定一致；四处 UDP 头字段则按"高字节先落"存：`udp_len[15:8] <= s_data` 在 `bcnt == udp_off+4`、`udp_len[7:0]` 在 `+5`（`udp_rx_parser.v:159`–`udp_rx_parser.v:160`），因为 UDP length 字段本身是网络序（大端）。⇒ **同一根线上两套字节序**：UDP/IP 头大端、应用偏移与像素小端，这正是 14/34 偏移处理必须分模块的原因。

像素拼接在 `frame_reasm.v:141`–`frame_reasm.v:151`：第一个载荷字节进 `pix_lo` 并置 `have_lo`（`frame_reasm.v:142`），第二拍 `wr_data<={p_data,pix_lo}`（`frame_reasm.v:150`）—— 后到的字节当高位、先到的当低位，把"低字节在前"翻译回 16 bit 数值。

### 3.2 `pay_start` / `pay_end` 的算法与"提前一拍寄存"

算法（`udp_rx_parser.v`）：

* `udp_off = 14 + ihl*4`，判定条件写成 `bcnt == (16'd14 + {10'd0, ihl, 2'b00})`（`udp_rx_parser.v:137`），`ihl` 已在前面的 `bcnt==14` 存好（`udp_rx_parser.v:121`）。
* `pay_start <= bcnt + 16'd8` —— 这一拍的 `bcnt` 就是 `udp_off`，所以 UDP 头固定 8 字节（`udp_rx_parser.v:139`）。
* `pay_end <= udp_off + {udp_len[15:8], s_data} - 16'd1` —— 在 `udp_len` 低字节到达的同一拍把尾界算完（`udp_rx_parser.v:161`–`udp_rx_parser.v:162`）。
* 发射门：`accept && (bcnt >= pay_start) && (bcnt <= pay_end)`（`udp_rx_parser.v:172`–`udp_rx_parser.v:173`）。

"提前一拍寄存"防的是什么：这两行的注释把动机写死了 —— `pay_start` 是"与 `udp_off` **同拍**寄存，把加器挪出 `p_good` 的锥"，`pay_end` 是"与 `udp_len` 低字节同拍寄存（同一手法）"（`udp_rx_parser.v:33`–`udp_rx_parser.v:34`）。也就是说：如果把 `udp_off + 8` / `udp_off + udp_len - 1` 留在发射那一现算，16 bit 加法器就串在 `p_good`/`p_eof` 的扇入路径上；预寄存后，发射门只剩比较器，加法在头解析阶段免费完成。这是时序收敛手法而不是协议要求。

`pay_end` 的必要性（反证也在注释里）：早期写法是 `bcnt >= udp_off+8` 一路发到帧尾，于是把帧尾 4 个 FCS 字节当载荷吐出去 —— 32 字节载荷吐出 36 个，接上 `frame_reasm` 就是每包多 4 字节的确定性错位（`udp_rx_parser.v:169`–`udp_rx_parser.v:171`）。

尾界到达时不当场发 `p_eof`，只记账 `eof_pend <= 1'b1`、`pay_len_q <= pay_cnt + 16'd1`（`udp_rx_parser.v:182`–`udp_rx_parser.v:185`），要等帧结束那拍才知道 FCS 好坏；注释给出的取舍是"早发就得猜，猜错就是把坏包当好包提交，那是最坏的一种错"（`udp_rx_parser.v:179`–`udp_rx_parser.v:181`）。为兼容两种 `s_eof` 时序（厂商式：`s_eof` 与最后字节同拍；本仓库 `gmii_rx_mac` 式：`m_eof` 与 `m_good/m_bad` 同拍而 `m_valid=0`），另设 `last_pay_now` 组合线（`udp_rx_parser.v:50`，声明必须在 reg 之后，`udp_rx_parser.v:49`；用法在 `udp_rx_parser.v:197`–`udp_rx_parser.v:200`；时序约定全文在 `udp_rx_parser.v:192`–`udp_rx_parser.v:195`）。

### 3.3 为什么载荷必须是 8 的倍数

发侧给出的理由（`udp_push.py:5`–`udp_push.py:6`）：包边界若落在 64 bit DDR 字中间，打包器对同一个字分两次推送会互相覆盖 ⇒ 屏上出现规律黑点。`video_sender.mjs:28` 同样把 `--mtu-payload 1396` 定位为"用来复现这个错误的（A/B 对照实验用）"。两份实现对非 8 倍数都只告警不拦：`udp_push.py:95`–`udp_push.py:97`、`video_sender.mjs:30`。

在 RTL 侧能看到的对应事实：`frame_reasm` 的写单位是 16 bit（`wr_addr<=off[18:1]`，`frame_reasm.v:151`），也就是 2 字节一字；`off` 每写一字 +2（`frame_reasm.v:163`）。8 字节对齐的要求发生在 64 bit 那一层（第 5 节的 `axi_frame_saver64`），本模块不做 8 的倍数的校验，也没有对奇数 `off` 的拒绝路径 —— 偏移只要 `< FRAME_BYTES` 就写（`frame_reasm.v:152`）。⇒ "非 8 倍数具体在 64 bit 打包器里是哪一拍互相覆盖"，本节不结论，留给第 5 节；若无对应代码行则记 **未证**。

### 3.4 常数分布表

| 常数 | 值 | 出现的文件:行 |
| --- | --- | --- |
| UDP 载荷上限 | 1392 | `video_sender.py:35`（`MAX_PAYLOAD = 1392`）、`udp_push.py:45`（`--mtu-payload` default）、`video_sender.mjs:29`（`const MTU = Number(get('mtu-payload', 1392))`）；另在注释里各出现一次：`video_sender.py:5`、`udp_push.py:5`、`video_sender.mjs:9` |
| 应用层头长 | 4 | `video_sender.py:34`（`HDR = 4`）、`udp_push.py:30`（`HDR = 4`）、`video_sender.mjs:26`（`HDR = 4` 与 `W/H/FRAME_BYTES` 同行） |
| 帧字节数 | 307200 | `frame_reasm.v:11`（`parameter FRAME_BYTES = 307200`）；发侧由 `OUT_W*OUT_H*2` 推得：`video_sender.py:32`–`video_sender.py:33`（`OUT_W, OUT_H = 512, 300`）、`video_sender.mjs:26`、`udp_push.py:29` |
| 以太头长 | 14 | `udp_rx_parser.v:28`（`ETH_HDR = 14`，声明后未被判定式引用）、字面量 14 见 `udp_rx_parser.v:137` |
| IP 头长 | `ihl*4`（本链路 20） | `udp_rx_parser.v:137` |
| UDP 头长 | 8 | `udp_rx_parser.v:139` |
| 以太网帧最小长 | 64 | `gmii_rx_mac.v:76`（`cnt >= 16'd64`） |
| ARP 最小数据 | 46 | `arp_tx.v:43` |
| ICMP 最小数据 | 18 | `icmp_tx.v:55` |
| IP 分片上限核对 | 1472 | `udp_push.py:98`（`if a.mtu_payload + HDR > 1472`）；`video_sender.py:35` 用另一句话表达同一约束（"再大就会 IP 分片，而收包链不分片"） |
| FCS 残值 | `32'hC7_04_DD_7B` | `gmii_rx_mac.v:23` |
| UDP 目的端口 | 5001 | `udp_rx_parser.v:5`；顶层同值默认见 `eth_udp_video_top.v:11` |

### 3.5 一帧的包数与字的算术（全部由上表常数推得）

```
帧 = 512 x 300 px x 2 B  = 307200 B           (frame_reasm.v:9-frame_reasm.v:11, video_sender.py:32-video_sender.py:33)
   / 1392 B 每包          = 220.69  -> 221 包  (ceil 式见 video_sender.py:233 的 (FRAME_BYTES + MAX_PAYLOAD - 1) // MAX_PAYLOAD)
   / 2 B (frame_reasm 写单位) = 153600 个 16bit 字  (wr_addr = off[18:1], frame_reasm.v:151)
   / 8 B (AXI beat 单位)      =  38400 个 64bit 字?  不 —— 见下面"两处口径不一致"
```

`cur_widx = wr_addr[18:2]`（`axi_frame_saver64.v:88`）把 16 bit 字索引再右移 2 ⇒ 64 bit 字索引，153600 / 4 = 38400 个 beat/帧；按 `axi_frame_saver64.v:3` 的 ≤2 拍/字（100 MHz）即 ≤76800 拍 = 0.768 ms/帧 ⇒ 理论上限 ≈1300 帧/s，与 400 MB/s 的声明自洽（307200 B / 0.768 ms ≈ 400 MB/s）。

**两处口径不一致，登记不圆场**：`frame_reasm.v:146`–`frame_reasm.v:147` 的注释写"帧只有 153600 字节 = 76800 个字"，而同一模块的 `FRAME_BYTES = 307200`（`frame_reasm.v:11`）与 `video_sender.py:33` 的 `FRAME_BYTES = OUT_W * OUT_H * 2` 都是 307200。153600 恰是像素数（`axi_frame_writer_gated.v:42` 的 `TOTAL_PIX = IMG_W * IMG_H`，`axi_frame_writer_gated.v:42`）。⇒ 那条注释把"像素数"当"字节数"写了，导致它推出的 76800 字（=16bit 字数的一半）与 `off[18:1]` 的实际上界 131071 之间的余量被夸大一倍。代码里的门限 `off < FRAME_BYTES`（`frame_reasm.v:152`）用的是正确的 307200，所以**只是注释错、不是逻辑错**；但任何人按 `frame_reasm.v:146` 推理越界后果会得到错的结论。该注释是否已提修订：未证。

另一条与"8 的倍数"直接相关的量化：`axi_frame_saver64.v:82` 给出非 8 倍数（举例 1396）时"每帧 111 处 = 222 个 16bit 黑洞"。按本卷常数核对：307200 / 1400（1396+4 前缀）≈ 219.4 包，包边界跨界次数与 111 同量级但不等 ⇒ 111 应来自 `sim`/实测而非这个近似式；该 111 的推导过程：**未证**（本卷只做量级核对，不把它当公式）。

> **数据在这一站长什么样**：入口 8 bit 字节流，125 MHz 每拍 1 字节，连续无泡；一包载荷最多 1392 字节 ⇒ 最多 1392 拍 = 11.136 µs。出口是 16 bit `wr_data` + 19 bit `wr_addr`（字索引）+ 单拍 `wr_en`（`frame_reasm.v:20`–`frame_reasm.v:22`），有效节拍变成"每 2 拍一次"（`have_lo` 分相，`frame_reasm.v:141`–`frame_reasm.v:164`）。字节序：偏移小端、像素小端、UDP 头大端。出错可见后果：`pay_end` 算错多吐 4 字节 ⇒ 整帧每包右移 2 像素的连续斜纹（`udp_rx_parser.v:170`–`udp_rx_parser.v:171` 直接称其为"确定性错位"）；偏移前缀被读歪 ⇒ `off` 落到别处，屏幕表现为"内容出现在错误行"，且越界那部分被 `frame_reasm.v:152` 拦下并计入 `stat_oob_off`（`frame_reasm.v:161`）。具体图案实拍证据：**未证**。

---

## 4. `frame_reasm.v`：行环组织、就绪标志与帧提交条件

模块头一句话把设计意图讲完了：只有本帧**每一行源像素都被写过**才提交；缺行会在 DDR 里留下旧/零像素 ⇒ 冻结的画面在缩放时黑纹会"动"（`frame_reasm.v:2`–`frame_reasm.v:3`）。时钟域 `gmii_rx_clk / eth_rxc` 125 MHz，所有输出都寄存（`frame_reasm.v:4`）。v5.1 只重写了字节计数算术、验收判定不动：三操作数 32 位加法器 `cover + pkt_pay + 1 >= FRAME_BYTES` 独占本 125 MHz 组十条最差路径（WNS +0.499），现改为两个饱和累加 + 常数比较（`frame_reasm.v:5`–`frame_reasm.v:7`）。

端口（`frame_reasm.v:13`–`frame_reasm.v:35`）：参数 `IMG_W = 512`、`IMG_H = 300`、`FRAME_BYTES = 307200`（`frame_reasm.v:9`–`frame_reasm.v:11`）。入 `clk`/`rst_n`/`p_data[7:0]`/`p_valid`/`p_sof`/`p_eof`/`p_good`。出 `wr_en` 1、`wr_addr` **19 bit**、`wr_data` 16 bit、`flush`、`frame_done`、`frame_err`、`frame_abort`、`rows_missed` 16、`stat_frames`/`stat_pkts`/`stat_bytes`/`stat_bad`/`stat_oob_off` 各 32。

### 4.1 行覆盖环：5 × 64 bit bank，不是 RAM

行覆盖不用 BRAM，用 5 只 64 bit 寄存器 `rok0..rok4` + 16 bit 计数器 `rows_hit`（`frame_reasm.v:81`–`frame_reasm.v:82`）。地址算法（`frame_reasm.v:86`–`frame_reasm.v:96`）：

* `ROW_STRIDE = IMG_W * 2`（`frame_reasm.v:86`）
* `row_idx = off / ROW_STRIDE`（`frame_reasm.v:87`）—— 除法，512 字节一行时综合成移位
* `ridx = row_idx[8:0]`、`rbank = ridx[8:6]`、`roff = ridx[5:0]`（`frame_reasm.v:88`–`frame_reasm.v:90`）
* 读回是 5 选 1 mux `row_covered = (rbank == 3'd0) ? rok0[roff] : ...`（`frame_reasm.v:91`–`frame_reasm.v:96`）

边界 5 × 64 = 320 行 ≥ `IMG_H=300`，写死在 5；`initial` 里 `if (IMG_H > 5 * 64) $error(...)`，台架当场喊、综合忽略（`frame_reasm.v:217`–`frame_reasm.v:220`，注释 `frame_reasm.v:215`–`frame_reasm.v:216`）。为什么分 bank：`new_row_w` 曾是全部 300 个覆盖 FF 加 16 个 `rows_hit` FF 的使能驱动（r106 布线后报告 fo=316，仅这最后一跳就吃掉 6.879 ns 数据路径里的 1.980 ns，布线占比 81.2 %），现在每 bank 只接 ≤64 个负载、行计数器使能只接 16 个（`frame_reasm.v:76`–`frame_reasm.v:80`）。独热化写法：`bank_one = new_row_w ? (5'b00001 << rbank) : 5'b00000`（`frame_reasm.v:102`），写侧变成 5 条 `if (bank_one[k]) rokk[roff] <= 1'b1`（`frame_reasm.v:154`–`frame_reasm.v:158`）+ `if (|bank_one) rows_hit <= rows_hit + 16'd1`（`frame_reasm.v:159`）。`bank_one` 必须声明在 `row_covered` 之后，否则 xvlog 报 `[VRFC 10-3380]`（`frame_reasm.v:97`–`frame_reasm.v:99`）；`rbank<=4` 由 `row_idx<IMG_H` 保证（`frame_reasm.v:101`）。

一条曾经算错的口径值得记住：`row_idx` 不能用 `off[16:1]` —— 16 bit 像素索引截断约 172/300 行 ⇒ `frame_done` 永不成立 ⇒ SRC1 全黑（`frame_reasm.v:84`–`frame_reasm.v:85`）。

### 4.2 字节计数与两个饱和累加

`CW = $clog2(FRAME_BYTES + 1)`、`SAT = FRAME_BYTES`、`SAT1 = FRAME_BYTES - 1`（`frame_reasm.v:56`–`frame_reasm.v:58`）。`cov` = 本帧已收载荷字节（含在途包），`pend` = 在途包自己的字节数、也就是它下一个载荷字节要落的偏移（`frame_reasm.v:50`–`frame_reasm.v:55`）。两者都在 `FRAME_BYTES` 饱和且无损失，因为旧代码只问"cov + 1 >= FRAME_BYTES"，对单调计数等价于"== FRAME_BYTES"（`frame_reasm.v:52`–`frame_reasm.v:54`）。命名 `cov` 而非 `cover`，因为 `cover` 在 `-sv` 下是 SystemVerilog 关键字（`frame_reasm.v:55`）。

判据（`frame_reasm.v:63`–`frame_reasm.v:72`）：`bytes_ok = cov_sat | (cov_end & p_valid)`、`last_pkt = pend_sat | (pend_end & p_valid)`。需要 `& p_valid` 是因为一包最后一字节与 `p_eof` 同拍、计数还没看见它，只在这里补记（`frame_reasm.v:68`–`frame_reasm.v:70`）。累加都带饱和门：`if (!cov_sat) cov <= cov + 1'b1`、`if (!pend_sat) pend <= pend + 1'b1`（`frame_reasm.v:166`–`frame_reasm.v:167`，EOF 分支里再各写一次 `frame_reasm.v:193`–`frame_reasm.v:194`）。

### 4.3 标志位的置位/清除时机

| 信号 | 置位时机 | 清除时机 | 出处 |
| --- | --- | --- | --- |
| `p_good`→本地 `bad_frame` | `p_eof && pkt_active`（`frame_reasm.v:174`）且 `!p_good` ⇒ `bad_frame <= 1`，同时 `stat_bad+1`、`frame_err <= 1` | 帧起点（`S_OFF3` 且 `hdr < 32'd4`）与提交成功那拍 | `frame_reasm.v:206`–`frame_reasm.v:209`、`frame_reasm.v:133`–`frame_reasm.v:138`、`frame_reasm.v:187` |
| `row_covered` 位（rok0..rok4） | 每写入一个字且该行首次被碰 ⇒ `bank_one` 独热位置 1（限 `off < FRAME_BYTES`） | 同两处：帧起点清零 5 只 bank（`frame_reasm.v:135`）、提交清零（`frame_reasm.v:185`） | `frame_reasm.v:153`–`frame_reasm.v:158` |
| `rows_hit` | 与 bank 位同拍 `+1` | 帧起点 / 提交，同清零 `rows_hit<=0` | `frame_reasm.v:159`、`frame_reasm.v:136`、`frame_reasm.v:186` |
| `frame_err` | `p_eof && pkt_active && !p_good`（这一包被判坏） | 默认每拍清 0（单拍脉冲），复位亦清 | `frame_reasm.v:208`、`frame_reasm.v:118`、`frame_reasm.v:112` |
| `frame_done` | `p_eof && pkt_active && p_good && rows_hit >= IMG_H && bytes_ok && !bad_frame` | 每拍默认清 0 ⇒ 脉冲 | `frame_reasm.v:182`–`frame_reasm.v:183`、`frame_reasm.v:118` |
| `frame_abort` + `rows_missed` | 字节预算用完（`last_pkt`）但验收门没过 ⇒ 脉冲一次，`rows_missed = IMG_H - rows_hit`（行数够而字节不够时为 0，注释明说这不是 bug） | 每拍默认清 0 | `frame_reasm.v:26`–`frame_reasm.v:28`、`frame_reasm.v:196`–`frame_reasm.v:203` |
| `flush` | 任何 `p_eof && pkt_active`（好坏都 flush） | 每拍默认清 0 | `frame_reasm.v:174`–`frame_reasm.v:175`、`frame_reasm.v:118` |
| `stat_oob_off` | `off >= FRAME_BYTES` 的二元组到达时 `+1` | 不清（累计） | `frame_reasm.v:160`–`frame_reasm.v:161` |

`bad_frame` 是 v5.1 有意相对 v5.0 的行为改变：运行中的字节总数无法撤销一个失败包的计数，所以坏包改成置 1 bit、由提交门去测（判定结果相同，代价 1 bit）（`frame_reasm.v:46`–`frame_reasm.v:48`）。

注意帧起点清零的条件是 `hdr < 32'd4`（`frame_reasm.v:133`–`frame_reasm.v:138`）—— 只有偏移 0..3 的那个包（即帧的第一个包）才重置 `cov`/bank/`rows_hit`/`bad_frame`。⇒ 若首包丢失，后面所有包的字节都累在上一帧的计数上；这条推论的代码依据是上面的行，是否有额外补救：未见。

### 4.4 `byte_off` 越界防护与帧提交条件

防护只有一处、但被写进两个地方：`wr_en <= (off < FRAME_BYTES)`（`frame_reasm.v:152`）与覆盖统计同一个 `if (off < FRAME_BYTES)`（`frame_reasm.v:153`）。#201 的记录说明这曾经是不一致的：`wr_en` 那三行是无条件的，而 `if (off < FRAME_BYTES)` 只管 `rok0..rok4/rows_hit` ⇒ 发包方选的偏移能把字写到帧缓存之外（`off[18:1]` 最大 131071，帧只有 153600 字节 = 76800 字，越界后落在谁身上由下游 `axi_frame_saver64` 的乘法决定，而它自己没有上界检查）；尺子是 `sim/tb_reasm_bounds.v` 的 R1，改前红凭据 `build/r98_201_before.txt`（越界包发了 2 次写、最大字索引 145 > 128）（`frame_reasm.v:144`–`frame_reasm.v:149`）。

提交门三条同时成立（`frame_reasm.v:178`–`frame_reasm.v:182`）：本帧无坏包（`!bad_frame`）、每一源行都被碰过（`rows_hit >= IMG_H[15:0]`）、全部 `FRAME_BYTES` 到齐（`bytes_ok`）。注释解释了为什么行位图不够：行位图会让丢包以"整行齐全"的身份过关，那个洞（从未写过的 BRAM 字 = 0）会在停流后作为黑纹留下来（`frame_reasm.v:178`–`frame_reasm.v:181`）。提交那拍清 `cov`/5 只 bank/`rows_hit`/`bad_frame` 并 `stat_frames+1`（`frame_reasm.v:183`–`frame_reasm.v:188`）。

短帧（没凑够 `FRAME_BYTES` 的帧）走 else 分支：不上报 `frame_abort`，只在内存里保留上一帧好画面并计一次数（`frame_reasm.v:190`–`frame_reasm.v:204`）；`frame_reasm.v:28` 明确说这类帧由 `stall_ms` 抓到 —— 与第 6 节接上。

> **数据在这一站长什么样**：进 8 bit/拍、连 1392 拍；出 16 bit + 19 bit 字地址 + 单拍 `wr_en`，占空比 50 %（每 2 拍 1 写）。`wr_addr = off[18:1]` 是**字索引**不是字节地址（`frame_reasm.v:151`），上界 2^19 = 524288 字远大于本帧的 153600 字节（=19200 个 64 bit 字，或 76800 个 16 bit 字），所以真正的护栏是 `off < FRAME_BYTES` 那句而不是位宽。观测面：`rows_missed` 直接就是"黑纹行数"（`frame_reasm.v:27`）。因此这一站出错在屏幕上有两种可分辨形态：提交门误判好帧 ⇒ 部分行是旧数据（画面卡顿/撕裂）；把坏帧误提交 ⇒ 依 `frame_reasm.v:2`–`frame_reasm.v:3`，冻结流上留下会随缩放移动的竖黑纹。`stat_bad`/`stat_oob_off` 的实测数值本卷不引用。

---

## 5. AXI 写侧：请求切分、`awlen/awsize/awburst/wlast` 与 `dc_fifo` 的 CDC

### 5.1 `axi_frame_saver64.v` —— 唯一真正的 AXI 写侧

全文跑 `axi_clk`（HP0 100 MHz）；入包侧的字由 `eth_udp_video_top` 里的 BRAM CDC 打过来（`axi_frame_saver64.v:4`）。参数 `BASE_ADDR = 32'h1000_0000`、`FW = 9` ⇒ 512 项打包 FIFO（`axi_frame_saver64.v:9`–`axi_frame_saver64.v:13`）。端口：入 `wr_en`/`wr_addr[18:0]`/`wr_data[15:0]`/`flush`/`enable`/`base_addr[31:0]`，出 `fifo_full`/`idle`/`busy` 与 AXI3 写通道（`axi_frame_saver64.v:15`–`axi_frame_saver64.v:38`），`m_axi_wdata` 64 bit、`m_axi_wstrb` 8 bit（`axi_frame_saver64.v:32`–`axi_frame_saver64.v:33`）。

四个写通道常量的真实写法（`axi_frame_saver64.v:40`–`axi_frame_saver64.v:44`）：

| 信号 | 现值 | 含义 |
| --- | --- | --- |
| `m_axi_awlen` | `8'd0` | 每笔传输 1 个 beat（不是 INCR 长度 8/16），突发被降到最小粒度 |
| `m_axi_awsize` | `3'b011` | 每 beat 8 字节 = 64 bit，与 `m_axi_wdata` 位宽一致 |
| `m_axi_awburst` | `2'b01` | INCR |
| `m_axi_wlast` | `1'b1` | 恒 1 —— 因为 `awlen=0`，每一拍都是最后一拍，`wlast` 不携带信息 |

请求切分的实际单位是"打包器推出的一个字"：`q_addr`/`q_data`/`q_keep` 三张分布式 RAM（`(* ram_style = "distributed" *)`，`axi_frame_saver64.v:48`–`axi_frame_saver64.v:50`），推入时机两条 —— ① 来了新的字索引先把正在拼的旧字推走、② `flush` 把半截字推走，两处内容相同所以合成一个写脉冲 `push_now = enable && ((wr_en && idx_chg) || (flush && cur_dirty && !wr_en))`（`axi_frame_saver64.v:97`–`axi_frame_saver64.v:101`），`pack_we = push_now && !fifo_full` ⇒ FIFO 满时该字被丢弃（第二处还会清 `cur_dirty`），这是 v6.4 原样保留的语义（`axi_frame_saver64.v:100`、`axi_frame_saver64.v:102`）。

16 bit lane → 64 bit 字的拼装由 `wr_addr[1:0]` 选位（`axi_frame_saver64.v:125`–`axi_frame_saver64.v:130` 首填、`axi_frame_saver64.v:133`–`axi_frame_saver64.v:137` 续填），每 lane 记一个 `cur_keep` 位。地址由 `pack_base + {10'd0, cur_widx, 3'b000}` 算（`axi_frame_saver64.v:110`）——`cur_widx = wr_addr[18:2]`（`axi_frame_saver64.v:88`），即"19 bit 字索引（8 字节单位）× 8"。`pack_base` 只在 `!cur_dirty` 时装载新 `base_addr`（`axi_frame_saver64.v:92`–`axi_frame_saver64.v:95`）。

**写选通是本卷找到的"8 的倍数"根因**：`m_axi_wstrb = {{2{keep_r[3]}}, {2{keep_r[2]}}, {2{keep_r[1]}}, {2{keep_r[0]}}}`（`axi_frame_saver64.v:83`–`axi_frame_saver64.v:84`，每个 16 bit lane 展成 2 个字节选通）。注释写明（`axi_frame_saver64.v:80`–`axi_frame_saver64.v:82`）：旧实现恒为 `8'hFF`，于是"同一个 64bit 字被相邻两包分两次写"时后一次会把前一次的半字覆盖成 0 —— 分包长度不是 8 的倍数（如 1396）时每帧 111 处 = 222 个 16bit 黑洞，屏上均匀散布的黑点。⇒ 第 3 节的"必须 8 的倍数"在 v6.4 之后由 `wstrb` 兜住，发侧的 1392 变成性能选择而非正确性要求；这条结论的证据是上述代码行，板上是否还复现黑点：未证。

在途深度：`localparam [3:0] OST = 4'd8`（`axi_frame_saver64.v:66`，注释"够盖住 HP0 写延迟"），`outst` 是已发出、B 未回的 beat 数（`axi_frame_saver64.v:68`），装载条件 `have = (rptr != wptr) && !beat && (outst < OST)`（`axi_frame_saver64.v:74`），`beat = aw_wait || w_wait`（`axi_frame_saver64.v:72`）。AW 与 W **并行挂出、各自握手**（`m_axi_awvalid = aw_wait`、`m_axi_wvalid = w_wait`，`axi_frame_saver64.v:76`–`axi_frame_saver64.v:77`；`if (aw_wait && m_axi_awready) aw_wait <= 1'b0` 等同构清位，`axi_frame_saver64.v:170`–`axi_frame_saver64.v:171`），握手成功后若对方拉低 ready，valid 保持不动（`axi_frame_saver64.v:149`）。`m_axi_bready <= 1'b1` 每拍置起 ⇒ B 通道永不反压，只回收计数（`axi_frame_saver64.v:156`）。`outst` 只减不回绕（`axi_frame_saver64.v:160`），理由是偶尔多回一个 B 会回绕成 15 使 `have` 永不成立 = 整条入包链卡死（`axi_frame_saver64.v:158`–`axi_frame_saver64.v:159`）。`idle = enable && !cur_dirty && fifo_empty && !beat && (outst == 4'd0)`（`axi_frame_saver64.v:86`）。

为什么必须流水化（`axi_frame_saver64.v:5`–`axi_frame_saver64.v:7`）：v6.2 之前每字走完 `S_AW→S_W→S_B`，在途深度恒 1 ⇒ HP0 写延迟（~40 拍，被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈20 MB/s ⇒ 板上"每包固定从第 48 字节起丢字"；且加深缓冲治不了它，瓶颈是平均排空速率不是深度（v6.2 把 CDC 做到 8192 时上板毫无改善）。现值上限：发完立刻取下一个字 ⇒ ≤2 拍/字 = 400 MB/s（`axi_frame_saver64.v:2`–`axi_frame_saver64.v:3`）。

打包 FIFO 的空满判据是二进制指针比较：`fifo_full = (wptr[FW] != rptr[FW]) && (wptr[FW-1:0] == rptr[FW-1:0])`、`fifo_empty = (wptr == rptr)`（`axi_frame_saver64.v:52`–`axi_frame_saver64.v:53`）——单时钟域内，不需要格雷码。存储写独占一个**不带异步复位**的 `always @(posedge clk)`（`axi_frame_saver64.v:108`），因为写成 task 且与指针同在异步复位块时 Vivado 报 `Synth 8-7186` 拒绝把数组推断成 RAM，512×64bit 退化成 3.29 万个 FDRE（实测 task 写法 FF=32904/LUTRAM=0 vs 本写法 FF=85/LUTRAM=864，`axi_frame_saver64.v:104`–`axi_frame_saver64.v:107`）。

### 5.2 `dc_fifo.v` 的 CDC

`module dc_fifo` 双时钟 FIFO（格雷码），宽 `DATA_W`、深 `2**ADDR_W`（`dc_fifo.v:2`–`dc_fifo.v:3`），默认 `DATA_W = 32`、`ADDR_W = 4`（`dc_fifo.v:4`–`dc_fifo.v:5`）；入流链上实际用 8192 条（`axi_frame_saver64.v:13` 的注释"深缓冲在 eth_udp_video_top 里 BRAM 实现的 CDC（8192 条）"，`dc_fifo.v:44` 自证"可用深度从 DEPTH−1 变成 DEPTH…改前 8191、改后 8192"）⇒ `ADDR_W` 被顶层覆盖为 13。**顶层实际参数值：未证**（本卷未打开 `eth_udp_video_top` 的例化段）。

* 存储 `(* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1]`（`dc_fifo.v:20`）。
* 格雷码：`bin2gray = b ^ (b >> 1)`（`dc_fifo.v:29`–`dc_fifo.v:32`），指针 `wbin, wgray, rbin, rgray` 全 `ADDR_W:0`（`dc_fifo.v:22`），二进制指针永不跨域（`dc_fifo.v:81`）。
* 跨域同步链 `(* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wgray_s0, wgray_s1, rgray_s0, rgray_s1`（`dc_fifo.v:27`），四颗一起标而非只标 s1（`dc_fifo.v:25`–`dc_fifo.v:26`）；不打属性工具可以挪位、复制、拆到不同 SLR 相邻区，亚稳态传播窗口就没保证（ISSUES #262 / UG949 的 CDC 一节，`dc_fifo.v:23`–`dc_fifo.v:24`）。尺子是 `build/gates.sh` 里 CDC 那一项：报告末五列永远是 Endpoints / Safe / Unsafe / Unknown / No-ASYNC_REG（`build/gates.sh:111`），"没被 ASYNC_REG/握手保护住的采样点"判红（`build/gates.sh:134`，台账 #65 那一族病就是这么躲过第 6 项的）。`rgray` 在写域打两拍（`dc_fifo.v:82`–`dc_fifo.v:87`），`wgray` 在读域打两拍（`dc_fifo.v:89`–`dc_fifo.v:93`）。
* 空/满：`rd_empty = (rgray == wgray_s1)`（`dc_fifo.v:68`）；`wr_full = (wgray == {~rgray_s1[ADDR_W:ADDR_W-1], rgray_s1[ADDR_W-2:0]})`（`dc_fifo.v:47`）—— 满判据从"下一个写指针 `wgray_n`"改成"**当前**写指针 `wgray`"，与读侧对称（`dc_fifo.v:40`–`dc_fifo.v:41`），因为原式把 14 位加法 + 二进制转格雷 + 比较整条锥体挂在 `wr_en → ENARDEN` 上（r87 最差路径 8 级逻辑、0.152 ns）（`dc_fifo.v:41`–`dc_fifo.v:42`）。`wbin_n`/`wgray_n` 仍留着给指针推进用（`dc_fifo.v:45`–`dc_fifo.v:46`、`dc_fifo.v:54`–`dc_fifo.v:55`）。
* 第一刀（给 `wr_full` 加 `max_fanout=12`）已回滚，实测 WNS 从 −0.062 掉到 −0.192、失败端点 28→34 ⇒ 扇出不是瓶颈（`dc_fifo.v:37`–`dc_fifo.v:39`）。
* 读口是同步 BRAM 读：`rd_data <= mem[rbin[ADDR_W-1:0]]`（`dc_fifo.v:75`），复位为异步低有效、两域各自 `wr_rst_n`/`rd_rst_n`（`dc_fifo.v:8`、`dc_fifo.v:14`）。

`axi_frame_writer_gated.v` 需要澄清定位：它是 **DDR→帧缓存的读侧拷贝引擎**，AXI 侧只有 AR/R 通道（`m_axi_araddr[31:0]`、`m_axi_arlen[7:0]`、`m_axi_arsize[2:0]`、`m_axi_arburst[1:0]`、`m_axi_rdata[63:0]`、`m_axi_rlast`，`axi_frame_writer_gated.v:25`–`axi_frame_writer_gated.v:34`），写帧缓存走本地口 `fb_wr_en`/`fb_wr_addr[18:0]`/`fb_wr_data[63:0]`（`axi_frame_writer_gated.v:22`–`axi_frame_writer_gated.v:24`），所以本模块不产生 `m_axi_awlen`/`wlast`。能对照的写法：`m_axi_arsize = 3'b011`、`m_axi_arburst = 2'b01`（`axi_frame_writer_gated.v:37`–`axi_frame_writer_gated.v:38`）、`m_axi_arlen<=8'd15`（复位值，`axi_frame_writer_gated.v:105`）⇒ 16 beat/突发；`MAX_OUT = 3'd4`，注释直说"4 x 16-beat bursts in flight ≈ 64 beats, enough outstanding to cover HP0/DDR read latency and hold ~1 beat/cycle through the 25-line window"（`axi_frame_writer_gated.v:45`–`axi_frame_writer_gated.v:47`）。切分算术 `TOTAL_PIX = IMG_W*IMG_H`、`TOTAL_WORDS = (TOTAL_PIX + PIX_PER_BEAT - 1)/PIX_PER_BEAT`、`TOTAL_BURSTS = (TOTAL_WORDS + BEATS - 1)/BEATS`（`axi_frame_writer_gated.v:42`–`axi_frame_writer_gated.v:44`）。发突发的门是六条件与：`can_issue = active && allow_wr && !m_axi_arvalid && !abort && !dropping && (outstanding < MAX_OUT) && (burst_idx < TOTAL_BURSTS) && (sk_level <= ((1<<SK)-1-BEATS))`（`axi_frame_writer_gated.v:81`–`axi_frame_writer_gated.v:84`）。`abort` 后按 `drain_left`（= abort 那一刻的 `outstanding`）排空尾巴、期间 `m_axi_rready = (active && !sk_full) || dropping`（`axi_frame_writer_gated.v:70`–`axi_frame_writer_gated.v:79`）。它在本卷的意义是"与入流抢同一根 HP0"，正是 `OST`/`MAX_OUT` 两处深度注释的假想敌。

### 5.3 一拍丢数据的确切位置

`link_monitor.v:4`–`link_monitor.v:5` 给出了口径：本模块输入全是源模块已打过一拍的寄存器输出，模块内不许再插组合逻辑进关键路径；板上唯一会吃掉数据的通道是 CDC 写口被 `fifo_full` 挡住那一拍。（同处注释写"p_good 在顶层硬接 1，见 ISSUES #38"，而第 2 节读到的 `gmii_rx_mac`/`udp_rx_parser` 已实现真 FCS 判定 —— 顶层现在到底连的是 `m_good` 还是常量 1：本卷未打开顶层例化段，**未证**，两处表述以代码为准、以本节标注为冲突登记。）

## 6. 仲裁与健康：`src_arb` / `link_monitor`

### 6.1 `link_monitor` 的三个读数

参数：`CLK_HZ = 125_000_000`、`SETTLE = 32`、`LIVE_MS = 16'd200`（`link_monitor.v:9`–`link_monitor.v:13`）。每毫秒周期数 `TC = CLK_HZ / 1000 = 125000`（`link_monitor.v:36`）。分频器宽度必须由 `TC` 算出来：`DW = $clog2(TC + 1)`（`link_monitor.v:41`）—— 原来写死 `[15:0]` 装不下 125000 ⇒ `ms_div == TC-1` 恒假 ⇒ `ms_tick` 永远不来 ⇒ `ms32/stall/gap/心跳` 在板上全死，而仿真把 `CLK_HZ` 改成 1000（`TC=1`）完全看不出；取证是 `WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed`（`link_monitor.v:38`–`link_monitor.v:40`）。

`ms_tick`/`lm_hb`：`ms_div` 数到 `TC-1` 归零并打一拍 `ms_tick`，同拍翻转 `lm_hb`（`link_monitor.v:58`–`link_monitor.v:61`）。

`stall_ms`（"距上一个 frame_done 过了多少 ms（活看门狗）"，`link_monitor.v:74`）：`frame_done` 那拍清 0（`link_monitor.v:136`），否则每个 `ms_tick` 加一、到 `16'hFFFF` 钉住不回绕（`link_monitor.v:151`–`link_monitor.v:152`）。阈值判据两处在别处使用：快照 `flag5` 的 bit3 = `(stall_ms < LIVE_MS)`（`link_monitor.v:159`）与发布触发 `(ms_tick & (stall_ms >= LIVE_MS))`（`link_monitor.v:164`）——"没有帧"本身也要能被下游持续看到（`link_monitor.v:12`–`link_monitor.v:13`）。16 bit 字段越过 65535 一律饱和而不回卷，因为健康数字回卷到 0 会被读成"没问题"，这是比少报更坏的错（`link_monitor.v:88`–`link_monitor.v:92`，同理由见 `link_monitor.v:50`–`link_monitor.v:51`）。

`drop_words`（`link_monitor.v:69`，注释"被 fifo_full 吃掉的字（= 板上唯一真实的丢数据通道）"）来自哪一拍：谓词 `cdc_wr_req && cdc_full`（`link_monitor.v:105`）先寄存成 `drop_ev_d`，下一拍才 `drop_words <= drop_words + 1'b1`（`link_monitor.v:122`）。延迟的是**事件谓词本身**而非两个操作数 —— `(req_d && full_d)` 与 `(req && full)` 延一拍不等价，两信号在不同拍上各自变化时前者会漏记那一拍（台架 E1 实测 DUT 31 / 参考 32）（`link_monitor.v:82`–`link_monitor.v:84`）。动机是全设计最差 setup 就在 `u_cdc/wbin_reg -> … -> CE`（ISSUES #121/#124）。同拍还记 `cdc_rise = cdc_full & ~full_d`（`link_monitor.v:81`）→ `cdc_ep`（进入"满"状态的**次数**不是拍数，`link_monitor.v:72`、`link_monitor.v:123`）。这两个事件寄存器也补进复位，否则综合各多插一级不复位推断、`Synth 8-7137` 从 19 涨到 21（r86 实测，`link_monitor.v:100`–`link_monitor.v:102`）。

`frame_err`/`pkt_err`：`link_monitor.v:23` 标注"上板时恒 0，见文件头"⇒ 与 5.3 的 `p_good` 冲突登记同源；`frames_bad` 由 `frame_abort` 递增并顺手取 `rows_missed` 最大值 `rows_miss_max`（`link_monitor.v:126`–`link_monitor.v:129`）。

### 6.2 断链时 2.5 MHz 对计数的污染

`link_monitor.v:6`–`link_monitor.v:7`：断链时 RTL8211 **不停供 RXC 而是拉到 ≈2.5 MHz（≈1/48）**，于是本模块所有"ms"其实是周期数、饱和在 `0xFFFF`；下游拿它做实时判断必须先与"源时钟健康"相与 —— 即 `system_top` 的 `eth_live` 与 `snap_cross` 的 `hb_slow`。

后果是可算的：`TC` 按 125 MHz 定标（`link_monitor.v:36`），2.5 MHz 下 `ms_div` 数满 125000 个周期需要 50 ms 而不是 1 ms ⇒ 一切"ms"读数被放大 48 倍（1/48 见 `link_monitor.v:6`）。`stall_ms` 因此**涨得慢 48 倍**，`LIVE_MS = 200` 这条线要真实 10 s 才越过（放大关系由 `link_monitor.v:6` 与 `link_monitor.v:36` 直接推得；板上实测读数：未证）。同理 `gap_*`、`lm_hb` 心跳、`SETTLE` 节流窗口（256 ns @125 MHz，`link_monitor.v:165`–`link_monitor.v:166`）全部按同一系数失真，`SETTLE=32` 只保证覆盖到 31 MHz 以下的目的时钟（`link_monitor.v:166`）—— 目的域侧的安全边界，不救源域。

`eth_tb_ok` 的定义在 `src_arb.v:25`：`量 eth_live 的那个源时基仍然准（0=被拉慢或停掉 ⇒ 不信 eth_live）`。`eth_live` 则是"已在本域同步好的电平（慢变量，ms 级）"（`src_arb.v:24`）。两者与 `why_ps[0]` 的语义闭环：断链时 RXC 被拉到 ≈2.5 MHz ⇒ `eth_live` 那个读数不能用（`src_arb.v:36`–`src_arb.v:37`）。`why_ps` 三个位的完整编码：`[2]=1` 被人用 `src 1` 钉住了（不是故障）、`[1]=1` 时基准但没有流（网线/上位机停了）、`[0]=1` 时基本身不可信（`src_arb.v:36`–`src_arb.v:37`），只在 `owner_eth=0` 时有意义（`src_arb.v:38`）。为什么只要寄存不许再算一遍：屏上/上位机看到的"原因"必须与主人是同一份输入产生的，否则就是 #55 那一类"两个地方各说一套"（`src_arb.v:32`–`src_arb.v:34`）。

### 6.3 `src_arb` 的滞回换手

跑 `axi_clk`（两个引擎都在这个域，`src_arb.v:22`）。输入 `sel[1:0]`：`00=AUTO 01=强制 ETH 10=强制看 fb（=SD 回放）11=按 AUTO 处理`（`src_arb.v:26`），并警告这份编码**不是** `src_mode` 的四态码（那边 SD=3、TEST=2），顶层 `pl_video_top` 有一行适配器翻译（`src_arb.v:27`–`src_arb.v:28`）。忙线：`row_busy` = ETH 引擎（`axi_frame_writer_gated`）正在拷贝（`src_arb.v:29`）、`fill_busy` = PS 引擎（`axi_frame_writer64`）正在拷贝（`src_arb.v:30`），输出 `owner_eth`（`src_arb.v:31`）。换手条件 `both_idle = ~row_busy & ~fill_busy`（`src_arb.v:48`），强制位只改"谁想要总线"不改"什么时候能换手"（`src_arb.v:41`），因为直接在输出加 mux 会在一次拷贝中途翻选择位、留下半开的 AXI 读突发（`src_arb.v:42`–`src_arb.v:43`）。`force_eth = (sel == 2'd01)`、`force_ps = (sel == 2'd10)`（`src_arb.v:44`–`src_arb.v:45`），静默计数 `quiet` 32 bit（`src_arb.v:47`）。

两级滞回：`T_OFF_CYC = 2_000_000`（AXI 域 100 MHz ⇒ 20 ms，`src_arb.v:18`–`src_arb.v:20`）是第二级；第一级是 `stall_ms > LIVE_MS`（默认 200 ms，`src_arb.v:19`）—— 即"断流 200 ms 才可能放手，放手前还要再静默 20 ms"。`sel`/`quiet` 的完整判决式与 `why_ps` 的三位分别在哪一拍寄存：本卷未逐行读完 `src_arb.v:48` 之后部分，**未证**。

> **数据在这一站长什么样**：`lm_bus` 是一条 **320 bit** 快照，10 个显式 `[31:0]` lane 拼成 `{lane9, lane8, lane7, lane6, lane5, lane4, lane3, lane2, lane1, lane0}`（`link_monitor.v:32`、`link_monitor.v:198`–`link_monitor.v:205`）：lane0 丢字总数、lane1 `{err16, bad16}`、lane2 `{rows_miss_max, stall_ms}`、lane3 最近帧间隔、lane4 `{gap_max, gap_min}`、lane5 Σ间隔、lane6 CDC 灌满次数、lane7 `{27'd0, flag5}`、lane8 包数、lane9 有效字节（`link_monitor.v:187`–`link_monitor.v:196`）。每 lane 显式声明成 `[31:0]` 再拼的原因是：一行里塞两个字段曾把 lane1 拼成 48 bit、整条总线错位（`link_monitor.v:186`）。跨域用 `lm_bus_tog` 边沿捕获（`link_monitor.v:5`、机制见 `snap_cross`）。发布受 `pub = (upd_w | pend_ev) && (settle == 8'd0)` 节流（`link_monitor.v:171`），节流期间到的事件由 `pend_ev` 记账补发，否则正好落在 settle 窗口里的 `frame_done` 会被整个丢掉、而 stall 要等 200 ms 才再刷（`link_monitor.v:168`–`link_monitor.v:169`、`link_monitor.v:180`）；节流只合并发布、不丢计数（`link_monitor.v:166`）。这一站自身出错在屏幕上看不见（它是仪表），但**读数说谎会误导判因**：`stall_ms` 在断链时被放大 48 倍，会让人把"网口已经掉速"读成"还在正常跑"（依 `link_monitor.v:6`–`link_monitor.v:7` 的机制推论；具体误判案例：未证）。

---

## 7. 逐拍延迟表：从第一个 RGMII nibble 到第一个 DDR 写

下表是**结构性拍数**，即每站寄存级的深度，不是端到端实测延迟（本卷不引用任何未做过的测量）。时钟列：E = `gmii_rx_clk`/`eth_rxc` 125 MHz（8 ns），A = `axi_clk`/HP0 100 MHz（10 ns）。

| # | 站 | 拍数 | 域 | 点名文件段落 |
| --- | --- | --- | --- | --- |
| 0 | `IDELAYE2` 31 档输入延时 | 0 拍（纯模拟延时，量级为 ns，且 ps/档 三值互斥） | — | `rgmii_rx.v:69`、`system_top.v:172`；换算冲突见 `rgmii_rx.v:21`–`rgmii_rx.v:23` |
| 1 | `IDDR` nibble→byte（`SAME_EDGE_PIPELINED`，Q1/Q2 同拍出字） | 1 E | E | `rgmii_rx.v:88`、位分配 `rgmii_rx.v:133`–`rgmii_rx.v:134`（器件语义本身未在本仓库文档取证：**未证**） |
| 2 | `gmii_rx_mac` 出字寄存 `m_data <= gmii_rxd`，首字节打 `m_sof` | 1 E | E | `gmii_rx_mac.v:107`–`gmii_rx_mac.v:109` |
| 3 | `udp_rx_parser` 出载荷 `p_data <= s_data` | 1 E | E | `udp_rx_parser.v:174`–`udp_rx_parser.v:175` |
| 4 | `frame_reasm` 剥 4 字节偏移头 `S_OFF0→S_OFF3` | 4 E | E | `frame_reasm.v:126`–`frame_reasm.v:130`，`hdr` 组合式 `frame_reasm.v:105` |
| 5 | `frame_reasm` 拼第一个 16 bit 字（`have_lo` 分相） | 2 E | E | `frame_reasm.v:141`–`frame_reasm.v:151` |
| 6 | `wr_en`/`wr_addr`/`wr_data` 已是寄存输出 | 0（含在 #5 那一拍里） | E | `frame_reasm.v:152`、`link_monitor.v:3`–`link_monitor.v:4` |
| 7 | `dc_fifo` 格雷码跨域：对方指针 2 拍同步 + 空判 | ≥2 A | E→A | `dc_fifo.v:89`–`dc_fifo.v:93`、`dc_fifo.v:68` |
| 8 | `dc_fifo` BRAM 同步读口 `rd_data <= mem[...]` | 1 A | A | `dc_fifo.v:75`、`dc_fifo.v:20` |
| 9 | 打包器凑满 64 bit 字后推 FIFO：要等 `idx_chg`（下一字首字节）或 `flush` | 2 A 起，末字要等 `flush` | E→A | `axi_frame_saver64.v:89`、`axi_frame_saver64.v:101`、`axi_frame_saver64.v:97`–`axi_frame_saver64.v:98` |
| 10 | 打包 FIFO（同域）读出 + 装载 beat（`have` → `a_r/d_r/keep_r`） | 1 A | A | `axi_frame_saver64.v:74`、`axi_frame_saver64.v:162`–`axi_frame_saver64.v:168` |
| 11 | AW/W 并行挂出到各自被 `awready`/`wready` 接收 | ≥1 A，握手由互联决定 | A | `axi_frame_saver64.v:76`–`axi_frame_saver64.v:77`、`axi_frame_saver64.v:170`–`axi_frame_saver64.v:171` |
| 12 | B 响应回收 | 不占数据通路（`m_axi_bready` 恒 1） | A | `axi_frame_saver64.v:156`、`axi_frame_saver64.v:5`–`axi_frame_saver64.v:3` |

首写的结构性下限 ≈ 1+1+1+4+2 (E) + 2+1 (A) + 推/装载 1–2 (A) + 握手 1 (A) ≈ **13 拍跨两域**，再加 HP0/DDR 写延迟；`axi_frame_saver64.v:6` 给的对照数是"v6.2 之前每字走完 `S_AW→S_W→S_B`、在途深度恒 1 ⇒ HP0 写延迟 ~40 拍、被显示拷贝抢端口时上百拍"。稳态上限由 `axi_frame_saver64.v:3` 声明："发完立刻取下一个字（≤2 拍/字 = 400 MB/s）"。三个域名的时钟列 E/A 与 `axi_frame_saver64.v:4`、`link_monitor.v:3` 的自述一致；`gmii_rx_clk` 与 `axi_clk` 之间只有 #7–#8 这一处 CDC，其余全链单域（`eth_ctrl.v:3`–`eth_ctrl.v:4`）。

一处容易读错的因果：#9 那一站意味着**入流方向上"一个字的写出"天然滞后一个字**，所以真正决定首字何时进 DDR 的是下一拍 `wr_en` 的索引变化，而不是本字写完；只有包尾那个半截字靠 `flush` 推走（`axi_frame_saver64.v:101`、`frame_reasm.v:174`–`frame_reasm.v:175` 的 `flush<=1` 在 `p_eof` 那拍）。这也是为什么 `frame_reasm.v:2`–`frame_reasm.v:3` 的验收门必须等字节凑齐才提交。

### 7.1 链路总览与域边界

```
 rgmii_rxc 125M(片外) --+-- BUFG (rgmii_rx.v:51) --+-----------------------------------------+
                       |                          |                                         |
 PHY nibble[3:0] -> IDELAYE2 x5 (rgmii_rx.v:67/108, 31 档 system_top.v:172)                 |
                       v                                                                    |
                   IDDR x5 SAME_EDGE_PIPELINED (rgmii_rx.v:87/127) --> gmii_rxd[7:0]+dv ----+  域 E
                       v                                                                    |
              gmii_rx_mac (成帧 55/D5, cnt>=64, FCS 残值)  [gmii_rx_mac.v:89/95/76/48]        |
                       v                                                                    |
              udp_rx_parser (bcnt 状态机, pay_start/pay_end) [udp_rx_parser.v:137/139/162]    |
                       v                                                                    |
              frame_reasm (S_OFF0..3 剥偏移头 + 拼 16bit 字 + 5x64 行覆盖环) [frame_reasm.v:126/151/81]
                       v                                                                    |
                   dc_fifo  ---- 唯一的 E -> A 边界（格雷码 + ASYNC_REG）[dc_fifo.v:27/47/68]--+
                       v
              axi_frame_saver64 打包器 (q_addr/q_data/q_keep, cur_keep)   [axi_frame_saver64.v:48-50/60-62]
                       v                                                          域 A = axi_clk 100M
                   AXI3 AW/W/B  m_axi_awlen=0 / awsize=011 / INCR / wlast=1  [axi_frame_saver64.v:40-44]
                       v
                   HP0 -> DDR (BASE_ADDR = 32'h1000_0000, axi_frame_saver64.v:9)

 旁路：arp_rx / icmp_rx 直接吃 gmii_rxd（arp_rx.v:15-16, icmp_rx.v:11-12）；
 发侧仲裁 eth_ctrl（eth_ctrl.v:94-108）与收侧共用同一 125 MHz 域（eth_ctrl.v:3-4）。
 仪表：link_monitor 全在域 E（link_monitor.v:3），快照经 snap_cross 过域（link_monitor.v:5）。
 主人：src_arb 在域 A（src_arb.v:22），决定 owner_eth（src_arb.v:31）。
```

### 7.2 全链"数据会被吃掉"的 5 个点（按发生顺序）

| 点 | 条件 | 后果 | 出处 |
| --- | --- | --- | --- |
| 1 帧被判坏 | `!fcs_ok` 或 `cnt < 64` ⇒ `m_bad` | 整包以 `p_good=0` 闭合，本帧作废（`bad_frame`） | `gmii_rx_mac.v:76`–`gmii_rx_mac.v:80`、`udp_rx_parser.v:98`–`udp_rx_parser.v:100`、`frame_reasm.v:206`–`frame_reasm.v:209` |
| 2 过滤不过 | 非 IPv4/UDP/有分片/端口不等于 5001 | 整包不进载荷，`stat_drop_filt` | `udp_rx_parser.v:141`–`udp_rx_parser.v:146`、`udp_rx_parser.v:153`–`udp_rx_parser.v:155` |
| 3 偏移越界 | `off >= FRAME_BYTES` | `wr_en <= 0`，该字不写；`stat_oob_off+1` | `frame_reasm.v:152`、`frame_reasm.v:160`–`frame_reasm.v:161` |
| 4 CDC 满 | `cdc_wr_req && cdc_full` | **板上唯一真实丢数据通道**，`drop_words+1` | `link_monitor.v:4`–`link_monitor.v:5`、`link_monitor.v:105`、`link_monitor.v:122`；满判据 `dc_fifo.v:47` |
| 5 打包 FIFO 满 | `push_now && fifo_full` | 该 64 bit 字被丢弃（`flush` 路径还清 `cur_dirty`），v6.4 原样保留 | `axi_frame_saver64.v:100`–`axi_frame_saver64.v:102`、`axi_frame_saver64.v:52` |

注意 #4/#5 两个"满"是**不同层次**的：#4 是跨域 BRAM CDC（`dc_fifo`，8192 条，`axi_frame_saver64.v:13`），#5 是 `axi_clk` 域内的分布式打包 FIFO（512 条，`axi_frame_saver64.v:10`）。两者都不反压上游 —— 上游 `frame_reasm` 没有 `rdy` 输入（端口表 `frame_reasm.v:13`–`frame_reasm.v:35` 只有 `p_*`），`gmii_rx_mac` 同样无处可反压（`gmii_rx_mac.v:8`–`gmii_rx_mac.v:20`）。⇒ 整条入流是**只丢不拦**的设计：靠 125 MHz→100 MHz 的净空（1 字节/8 ns 进、1 字/20 ns 出的打包率余量）和 `OST = 8` 的在途深度把平均排空速率撑住（`axi_frame_saver64.v:66`、`axi_frame_saver64.v:7`），而不是靠背压。加深缓冲无效的实测依据在 `axi_frame_saver64.v:7`。

### 7.3 与吞吐相关的三个已写死的数

* 进：1 字节/8 ns = 125 MB/s 有效载荷上限（GMII 语义，`rgmii_rx.v:47`–`rgmii_rx.v:48`；1 Gb/s 线速的 125 MB/s 里减掉 42 字节头/包 + 4 字节偏移前缀）。
* 拼：1 个 16 bit 字 / 2 E 拍 = 125 MB/s（`frame_reasm.v:141`–`frame_reasm.v:164`）—— 与进完全同速，无余量，靠下游缓冲吸收突发。
* 出：1 个 64 bit 字 / ≤2 A 拍 = 400 MB/s（`axi_frame_saver64.v:3`）—— 3.2 倍净空，且 `axi_frame_saver64.v:7` 记录 v6.2 之前的 20 MB/s 上限是流水化缺失而非带宽不足。

## 8. 各站「数据长什么样」汇总

第 1–6 节末尾各有一段现场描述，这里给跨站对照，便于定位"哪一站的哪种错会画出什么"。

| 站 | 位宽 | 字节/字序 | 有效节拍 | 出错时屏上（可判明的） |
| --- | --- | --- | --- | --- |
| RGMII 引脚 | 4 + 1 钟 + 1 控，DDR | nibble：升沿=低 4 位、降沿=高 4 位（`rgmii_rx.v:2`、`rgmii_rx.v:133`–`rgmii_rx.v:134`） | 8 ns/nibble | 无错误通道（`rgmii_rx.v:6`）⇒ 静默位错，具体图案 **未证** |
| GMII 抽象 | `gmii_rxd[7:0]` + `dv` | 一字节/拍 | 125 MHz，`dv` 高才有效（`rgmii_rx.v:48`） | 同上 |
| `gmii_rx_mac` | 8 bit + `m_sof`/`m_eof`/`m_good`/`m_bad` | 帧内自然序（DA 在前） | 连续；`m_eof` 与 `m_good/m_bad` 同拍、`m_valid` 已为 0（`gmii_rx_mac.v:71`–`gmii_rx_mac.v:74`） | FCS 残值不符 ⇒ 整帧丢（`gmii_rx_mac.v:23`、`gmii_rx_mac.v:76`） |
| `udp_rx_parser` | 8 bit + `p_sof`/`p_eof`/`p_good` + `pay_len[15:0]` | 头大端、载荷透传不重排（`udp_rx_parser.v:159`–`udp_rx_parser.v:160` vs `udp_rx_parser.v:174`） | 头之后每拍 1 字节，最长 1392 拍 | 尾界算错 ⇒ 每包多 4 字节的确定性错位（`udp_rx_parser.v:170`–`udp_rx_parser.v:171`） |
| `frame_reasm` | `wr_data[15:0]` + `wr_addr[18:0]`（字索引） | 像素小端：`{p_data, pix_lo}`（`frame_reasm.v:150`）；偏移小端（`frame_reasm.v:126`–`frame_reasm.v:130`） | 每 2 拍 1 写 | 提交门误判 ⇒ 旧行残留/撕裂；坏帧误提交 ⇒ 缩放时移动的竖黑纹（`frame_reasm.v:2`–`frame_reasm.v:3`）；`rows_missed` 即黑纹行数（`frame_reasm.v:27`） |
| `dc_fifo` | `DATA_W`（入流链 8192 深，`ADDR_W` 顶层覆盖值 **未证**） | 不解释内容，只搬字 | 跨域 ≥2 拍同步 + 1 拍 BRAM 读（`dc_fifo.v:91`–`dc_fifo.v:93`、`dc_fifo.v:75`） | 满 ⇒ 丢字（唯一真实丢数据通道，`link_monitor.v:4`–`link_monitor.v:5`），画面表现为随机缺字/冻结 |
| `axi_frame_saver64` | 64 bit beat + 8 bit `wstrb` + `awlen=0/awsize=3'b011/awburst=2'b01`（`axi_frame_saver64.v:40`–`axi_frame_saver64.v:44`） | 4 个 16 bit lane，`wr_addr[1:0]` 定位（`axi_frame_saver64.v:125`–`axi_frame_saver64.v:137`） | 稳态 ≤2 拍/字（`axi_frame_saver64.v:3`） | `wstrb` 退化为 `8'hFF` 时：分包非 8 倍数 ⇒ 每帧 111 处、222 个 16bit 黑洞 ⇒ 均匀散布黑点（`axi_frame_saver64.v:80`–`axi_frame_saver64.v:82`） |
| `link_monitor` | `lm_bus[319:0]`，10 × 32 bit lane | 数字，非字节流 | 事件驱动 + `SETTLE=32` 节流（`link_monitor.v:11`、`link_monitor.v:166`） | 不画像素；断链时 ms 读数放大 ≈48 倍（`link_monitor.v:6`–`link_monitor.v:7`） |
| `src_arb` | `owner_eth` 1 + `why_ps[2:0]` | — | 换手只在 `both_idle`（`src_arb.v:48`） | 误判主人 ⇒ 半开读突发（`src_arb.v:42`–`src_arb.v:43`），画面表现为拷贝中途撕裂 |

### 8.1 本卷取证边界（未打开因而标 `未证` 的项）

已逐行打开：`rgmii_rx.v`、`clk_gen.v`、`eth_ctrl.v`、`udp_rx_parser.v`、`gmii_rx_mac.v`、`frame_reasm.v`、`axi_frame_saver64.v`、`link_monitor.v`。仅按匹配行取证（端口/状态/常数的行号可靠，逐拍行为未展开）：`system_top.v`（IDELAY 段）、`eth_udp_video_top.v`、`gmii_to_rgmii.v`、`arp_rx.v`、`arp_tx.v`、`icmp_rx.v`、`icmp_tx.v`、`crc32_d8.v`、`dc_fifo.v`、`src_arb.v`、`axi_frame_writer_gated.v`、`r114_io_async.xdc` 与 `src/host/` 三份发侧脚本。

明确的 `未证` 清单：① IDELAY 每档的 ps 数（156/63/88 三值冲突，`rgmii_rx.v:21`–`rgmii_rx.v:23`）；② 顶层给 `dc_fifo` 的实际 `DATA_W/ADDR_W`；③ 顶层 `p_good` 是否仍硬接 1（`link_monitor.v:5` 与 `gmii_rx_mac.v:4`–`gmii_rx_mac.v:7` 的现状态互相冲突）；④ 1392 与 1472 之间 80 字节余量的设计意图；⑤ 各类误码在屏幕上的具体图案实拍（全部按代码机制推述）；⑥ `src_arb.v:48` 之后 `quiet`/`sel`/`why_ps` 的完整判决式；⑦ 所有未在台架或板上量过的时延数值。

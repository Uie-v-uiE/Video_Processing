# 第 02 卷 · 入口通路：网口收包到 DDR 帧缓存

读者画像：看过第 01 卷的架构分工，知道"数据面整个在 PL、PS 只发命令"。本卷不再讲为什么这么分，只逐段拆怎么实现，以及每一段被什么判据钉住。

## 0. 本卷的口径约定

三条规矩，后面每一节都照它走。

| 规矩 | 内容 |
|------|------|
| 数字 | 每个数都点名真实文件；自己算的写出算式和两个操作数的出处 |
| 行号 | 只写 `文件:行号` 之前真读到的那一行；不确定就只给文件名 |
| 时钟 | 三档名字固定：`eth_rxc` 125 MHz、`clk_fpga_0` 100 MHz、`clkout0_1` 50 MHz（来源：build/timing_summary.rpt 第 164–169 行） |

"三档"是名字，`eth_rxc` 是引脚上恢复出来的收时钟（来源：src/rtl/eth/rgmii_rx.v:47 `assign gmii_rx_clk = rgmii_rxc_bufg;`），`clk_fpga_0` 是 PS 给 PL 的 FCLK0，`clkout0_1` 是显示像素钟（来源：src/rtl/clocks/clk_gen.v:21 `CLKOUT0_DIVIDE_F (20.000), // 50 MHz pixel`）。

## 1. 骨架：一个以太网帧进来到落进 DDR 走哪几级

结论：从引脚到 DDR 是七级流水，全在 `eth_udp_video_top` 这一个壳里，其中六级挤在 125 MHz 单域。

| 级 | 模块 | 顶层例化名 | 时钟域 | 交接的东西 |
|----|------|-----------|--------|-----------|
| 1 | `gmii_to_rgmii`（内含 `rgmii_rx` / `rgmii_tx`） | `u_rgmii` | eth_rxc | 4bit DDR → 8bit GMII |
| 2 | `gmii_rx_mac` | `u_rx_mac` | eth_rxc | 字节流 + `m_sof/m_eof/m_good/m_bad` |
| 3 | `udp_rx_parser` | `u_rx_par` | eth_rxc | UDP 载荷 + `p_*` + `pay_len` |
| 4 | `frame_reasm` | `u_reasm` | eth_rxc | 16bit 像素写 + `frame_done` |
| 5 | `dc_fifo`（36bit × 8192） | `u_cdc` | 跨域 | 格雷码指针 |
| 6 | `axi_frame_saver64` | `u_saver` | clk_fpga_0 | AXI3 AW/W 写突发 |
| 7 | `ddr_bank_commit` | `u_commit` | 两域 | `completed_base` + `commit_pulse` |

出处：src/rtl/eth/eth_udp_video_top.v:73、:186、:197、:235、:298、:354、:330 各例化行。

一个容易读错的点：发送侧没有第二个时钟域。`gmii_to_rgmii.v:25` 原文 `assign gmii_tx_clk = gmii_rx_clk;   // TX 侧不发自己的时钟，见文件头`——所以 ARP/ICMP/CRC 那些注释里写的"tx 域"就是 rx 域，整个 ETH 逻辑实际是单时钟域（src/rtl/eth/eth_ctrl.v:4 同一口径）。复位也只有一路：`rst_n(eth_rst_n & mmcm_locked)`（src/rtl/top/system_top.v:175），`eth_rst_n` 由一个 24 位计数器最高位给出（同文件 :108–112）。

## 2. RGMII → GMII：引脚、IDDR、IDELAY 抽头

结论：这一段的本质是"用 5 个 IDDR 把 4bit 双沿拆成 8bit 单沿"，难点全在采样点落在眼图哪儿——它是全设计最紧的一档，也是最没有报告可依赖的一档。

### 2.1 引脚、模块名与端口

六个收侧端口，全 LVCMOS33（来源：src/constraints/rk_zynq7020.xdc 第 20–25 行）：

| 端口 | 引脚 | 端口 | 引脚 |
|------|------|------|------|
| `eth_rxc` | Y19 | `eth_rxd[2]` | U20 |
| `eth_rx_ctl` | V19 | `eth_rxd[3]` | V20 |
| `eth_rxd[0]` | W20 | `eth_rxd[1]` | W21 |

时钟上不做任何乘法：`create_clock -period 8.000 -name eth_rxc` 直接给引脚造钟（rk_zynq7020.xdc:36）。

壳模块叫 `gmii_to_rgmii`（src/rtl/eth/gmii_to_rgmii.v:4），它不含逻辑、只把 `rgmii_rx`（例化名 `u_rgmii_rx`，:28–30）与 `rgmii_tx`（`u_rgmii_tx`，:42）拼起来。两端口的对照就是这一层的唯一内容：

| `gmii_to_rgmii` 端口 | 方向 | 接到 | 备注 |
|---------------------|------|------|------|
| `idelay_clk` | in | 顶层 `clk_200m` | IDELAY 参考钟 |
| `rgmii_rxc` / `rgmii_rx_ctl` / `rgmii_rxd[3:0]` | in | 引脚 | 板上名字是 `eth_rxc/eth_rx_ctl/eth_rxd` |
| `gmii_rx_clk` / `gmii_rx_dv` / `gmii_rxd[7:0]` | out | `u_rx_mac` 等 | 4bit DDR 变 8bit SDR |
| `gmii_tx_clk` / `gmii_tx_en` / `gmii_txd[7:0]` | in | `eth_ctrl` 的发送口 | |
| `rgmii_txc` / `rgmii_tx_ctl` / `rgmii_txd[3:0]` | out | 引脚 | |

端口表出处 gmii_to_rgmii.v:5–19；参数只有一个 `IDELAY_VALUE`，默认 0（:23）。

位段规则：RXC 上升沿那半字节是字节低位、下降沿是高位（rgmii_rx.v:2 文件头）。落到代码上就是 `Q1(gmii_rxd[i])` 吃正沿、`Q2(gmii_rxd[4+i])` 吃负沿（src/rtl/eth/rgmii_rx.v:133–134）。所以 8bit 字节里 [3:0] 是正沿那半、[7:4] 是负沿那半。

`gmii_rx_dv` 不是直接接 `rx_ctl`，而是两沿都判：

```verilog
    assign gmii_rx_dv  = gmii_rxdv_t[0] & gmii_rxdv_t[1];
```
（src/rtl/eth/rgmii_rx.v:48，`gmii_rxdv_t` 由 `u_iddr_rx_ctl` 的两个 Q 拼成，:92–94）

RGMII 没有 GMII 的 `RX_ER` 通道，这个模块交不出错误标志（rgmii_rx.v:6 文件头）。这句话是本卷后面三条推论的根：`gmii_rx_er` 在顶层被硬接 `1'b0`（eth_udp_video_top.v:189）、第 3 节必须自己算 FCS、第 10 节的丢数计数只能数 CDC 满。

### 2.2 IDDR 与那只 BUFG

5 个 IDDR 都用 `SAME_EDGE_PIPELINED`（1 个 `u_iddr_rx_ctl` 在 rgmii_rx.v:87，4 个 `u_iddr_rxd` 在 generate 里的 :127；文件自述"现在 5 个 IDDR 与下游 fabric 吃同一只 BUFG"在 rgmii_rx.v:3）。时钟网络只有一个 `BUFG BUFG_inst`（rgmii_rx.v:51）。

这一步是改过的，改的理由写在同一个文件的文件头（rgmii_rx.v:4–5）：原来 IDDR 吃 BUFIO、fabric 吃 BUFG，同频同相却分走两条树，偏斜 +1.616 ns 由综合器插 hold buffer 硬补，"WHS 每次重建在 ±1 ps 上掷硬币"，r62 量到 +0.001 ns。

代价也写在同一处（rgmii_rx.v:7–8）：换钟源把采样沿往后推 1.683 ns，数据侧必须补同样的量。补法是加抽头，拍数只有一个出处——顶层传下来的 `IDELAY_VALUE`。

### 2.3 IDELAY 在做什么，抽头值是多少

`IDELAYE2` 是 IO 单元里的可编程输入延时，`IDELAY_TYPE("FIXED")`、`REFCLK_FREQUENCY(200.0)`（rgmii_rx.v:68–70 与 :109–111，即 rx_ctl 一份 + rxd 四份）。参考钟 `idelay_clk` 是 200 MHz（`CLKOUT2_DIVIDE (5), // 200 MHz IDELAY ref`，src/rtl/clocks/clk_gen.v:27；在顶层接到 `u_idelay_clkgen` 的 `.clk_200m`，src/rtl/top/system_top.v:121–124），由一只 `IDELAYCTRL` 校准（rgmii_rx.v:59）。

**当前生效值：`IDELAY_VALUE(31)`**（src/rtl/top/system_top.v:172，从 `eth_udp_video_top` 参数再透传给 `gmii_to_rgmii` 再传给 `rgmii_rx`，见 eth_udp_video_top.v:73）。默认值一路都被覆盖掉：`rgmii_rx` 默认 0（rgmii_rx.v:39），`eth_udp_video_top` 默认 15（eth_udp_video_top.v:14）。

为什么是 31 而不是算术推出来的 26，`system_top.v:160–171` 那段注释把账写全了，摘要如下（数字均出自该段）：

| 项 | 读数 |
|----|------|
| 补 BUFIO→BUFG 推后的算术值 | 26 = 15 + 11 |
| 带窗扫描 hold 曲线 | −2.822 → −0.870 ns（+63 ps/拍） |
| 带窗扫描 setup 曲线 | +2.005 → −0.846 ns（−92 ps/拍） |
| 两曲线交点 | tap 31（用 0.155 ns/拍 的斜率差解出 31.1） |
| tap 26 / tap 31 的 `min(hold, setup)` | −1.185 / −0.870 |

同一处的警告也要一起念：这一族在 0~31 全范围内都关不掉，因为 hold 查慢角（钟网络 5.008 ns）、setup 查快角（1.597 ns），钟网络的角间差 3.4 ns 远大于数据路径的 0.47 ns。

抽头的"每档多少 ps"在本仓库里有四个互不一致的数，别拿任意一个去推：`gmii_to_rgmii.v:23` 注释写 78 ps、`rgmii_rx.v:8` 按 200 MHz 参考算 156 ps、`rgmii_rx.v:19` 实测斜率约 63 ps/tap、同一行从报告反推 2.292 ns / 26 档约 88 ps/tap。这条不一致由 `rgmii_rx.v:21–23` 自己登记为"未定，不当结论用"。

输入窗是另一件事，也是这段最新的一笔账。候选窗给的是 `set_input_delay -clock eth_rxc -min 1.200` / `-max 2.800`，正负沿各一对（src/constraints/r116_rgmii_input_window.xdc:32–35），数从 RTL8211F 规格书的 `TsetupT/TholdT` 得来、同文件第 12–17 行给了推导。这份窗最终没进发布件：`data/metrics.csv` 第 5 行的测量条件明写"本版不带 RGMII 输入窗"。

### 2.4 为什么 125 MHz 是最紧的一档

逐时钟 intra-clock 的 setup WNS（来源：build/timing_summary.rpt 第 181–186 行）：

| 时钟 | 周期 | WNS | 端点数 |
|------|------|-----|--------|
| `clk_fpga_0` | 10.000 ns | 1.850 ns | 15721 |
| `eth_rxc` | 8.000 ns | **0.739 ns** | 4835 |
| `clkout0_1` | 20.000 ns | 3.630 ns | 30179 |
| `sys_clk` | 20.000 ns | 14.876 ns | 323 |

`eth_rxc` 那 0.739 ns 同时就是全设计 WNS（`data/metrics.csv` 第 5 行：全局 setup WNS 0.739 ns、失败 setup 端点 0、总端点 51135）。

原因不是"这条链逻辑深"，而是周期短、且这一族里最狠的锥属于控制面不属于数据面。全设计最差的那一条起点终点都在 ICMP 发送器里：

```
0.739ns | eth_rxc | 7.066ns | 11 | u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C -> u_eth/u_icmp/u_icmp_tx/check_buffer_reg[19]/D
```
（来源：build/crit_paths.txt 第 3 行；表头说明 slack | clock_group | data_path_delay | logic_levels | start -> end，同文件第 2 行）

数据路径 7.066 ns 吃掉了 8.000 ns 周期的 88 %，11 级逻辑。第二紧的一族是收包链自己的：`u_eth/u_rx_par/p_eof_reg/C -> u_eth/u_reasm/rows_hit_reg[*]/CE`，1.017 ns slack、4 级（build/crit_paths.txt 第 6–10 行）——那条是被"行覆盖位图的使能广播"拖累的，改法见第 5.3 节。

## 3. RX MAC：怎么在一串字节里认出一帧

结论：`gmii_rx_mac` 用三态机找边界，边界不靠任何带内定界符，靠"跑 0x55 然后见 0xD5"和"`rx_dv` 掉下去"；对错靠自算 FCS，不靠外部标志。

模块与例化：`src/rtl/eth/gmii_rx_mac.v`，顶层名 `gmii_rx_mac`，端口 `clk / rst_n / gmii_rxd[7:0] / gmii_rx_dv / gmii_rx_er / m_data / m_valid / m_sof / m_eof / m_good / m_bad`（gmii_rx_mac.v:8–19）。

状态机（gmii_rx_mac.v:25–27、:87–:114）：

| 状态 | 进入条件 | 做什么 |
|------|---------|--------|
| `S_WAIT` | 复位或 `dv=0` | 等 `gmii_rxd == 8'h55`（:89） |
| `S_PRE` | 见第一个 0x55 | 数连续的 0x55；见 `8'hD5` 进 `S_DATA`、`cnt` 归 0（:95–97） |
| `S_DATA` | SFD 之后 | 逐字节 `m_valid`；`cnt==0` 那一拍出 `m_sof`（:109） |

`m_sof` 落在 DA[0]，`m_eof` 落在 FCS 最后一个字节之后那一拍。约定写在 gmii_rx_mac.v:71–74：`m_eof` 与 `m_good/m_bad` 同拍，表示"上一个 `m_valid` 的字节就是帧的最后一个字节"。这条约定不是天生的——`m_eof` 曾声明了、复位清了、却没有任何一处写 1，例化它的下游永远等不到包边界，是 `sim/tb_v795_rx_chain.v` 的 C1 抓到的（gmii_rx_mac.v:72–74）。

错包判据四条并列（gmii_rx_mac.v:76）：

```verilog
                    if (!er_seen && !gmii_rx_er && (cnt >= 16'd64) && fcs_ok) begin
```

`er_seen` 在 RGMII 上恒 0（`gmii_rx_er` 顶层接 1'b0），`cnt >= 64` 是最小帧长门，真正的判定权在 `fcs_ok`。FCS 由本模块内一份 `crc32_d8` 逐字节累加整帧（含 FCS 那 4 字节），一帧算完留下的**残值**与载荷内容无关，拿残值当判据（gmii_rx_mac.v:34–48）：

```verilog
    localparam [31:0] FCS_RESIDUE = 32'hC7_04_DD_7B;
```
（gmii_rx_mac.v:23；文件自述这是"实测值、不是推算值"，由 `sim/tb_v795_rx_fcs.v` 量出并钉住）

一处细节值得抄进笔记：`crc_clr` 在 SFD 那一拍（`gmii_rxd == 8'hD5`）拉，不在第一个数据字节那拍拉——"若在第一个数据字节当拍清，`crc_clr` 优先级会吞掉第 0 字节"（gmii_rx_mac.v:42–44）。

坏帧在这一级不丢，只打标（`m_bad`），丢在第 4 节的过滤与第 5 节的验收门。这样分是对的：MAC 级不知道这帧跟本设计有没有关系，无权丢弃。

## 4. 过滤：`udp_rx_parser` 怎么选包、怎么闭合

结论：这是一台按字节编号走的匹配机，四条协议判据 + 一条端口判据，任何一条不过就 `stat_drop_filt`；但它对"进来的坏帧"仍要吐一个 `p_eof`——闭合比过滤更重要。

模块 `udp_rx_parser`，唯一参数 `UDP_PORT`（src/rtl/eth/udp_rx_parser.v:4–5），值 5001 的出处是 `localparam [15:0] UDP_VIDEO_PORT = 16'd5001;`（src/rtl/top/system_top.v:145）。

字节偏移按 MAC 之后计数：以太网头 14 字节（`localparam integer ETH_HDR = 14;`，udp_rx_parser.v:28），IPv4 头从 14 起、UDP 头从 `14 + IHL*4` 起。采样点（udp_rx_parser.v:117–125）：

| 字节号 | 采成 | 用途 |
|--------|------|------|
| 12、13 | `proto_chk` | 必须是 `16'h0800`（IPv4） |
| 14 | `b14`、`ihl` | `b14[7:4]` 必须是 `4'h4` |
| 20、21 | `b20`、`b21` | 必须全 0（不分片） |
| 23 | `b23` | 必须是 `8'd17`（UDP） |

判定发生在 `bcnt == 14 + ihl*4` 那一拍，且加了 `ihl != 4'd0` 的门（udp_rx_parser.v:137）。这个门是补的：`ihl` 在 `bcnt==14` 当拍才被存进去，同拍读到的是旧值 0，于是 `bcnt == 14 + ihl*4` 在 `bcnt==14` 也成立，每帧提前判一次、而那时 protocol 还没采到 ⇒ **每帧误发一次 `stat_drop_filt`**（udp_rx_parser.v:133–136 自述）。四条协议判据原文在 udp_rx_parser.v:141–142。

端口过滤读 UDP 头的 +2/+3 两字节（udp_rx_parser.v:151–158）：

```verilog
                    if ({dport[15:8], s_data} != UDP_PORT) begin
                        accept <= 1'b0;
                        stat_drop_filt <= 1'b1;
```

载荷的起止是 `pay_start = udp_off + 8`（udp_rx_parser.v:139）、`pay_end = udp_off + udp_len - 1`（`:162`，那一行的长度低字节是当拍拼进来的，所以源码写成拼接形式），两个界都提前一拍寄存，为的是把加法器挪出 `p_good` 的锥。这一刀的代价被指标表逐字记着："r106 比 r104 多 22 个触发器 = 收包链那一刀的代价：把 `pay_start`／`pay_end` 两个 16 位界提前一拍寄存"（`data/metrics.csv` 第 9 行的测量条件段）。

为什么要按 UDP 长度字段收尾而不是发到帧尾：`原来的写法 bcnt >= udp_off+8 会把帧尾那 4 个 FCS 字节也当载荷吐出去（32 字节的载荷吐出 36 个），接上 frame_reasm 就是每包多 4 字节的确定性错位`（udp_rx_parser.v:169–171）。

最后一个载荷字节不当场发 `p_eof`，而是记 `eof_pend`，等 MAC 那一级给真伪判定（udp_rx_parser.v:179–185）；"早发就得猜，猜错就是把坏包当好包提交"。坏帧路径同样闭合，条件里带 `in_pay`：只要往外吐过字节就必须给一个 `p_eof`（udp_rx_parser.v:94–103）。三个统计位 `stat_drop_bad / stat_drop_filt / stat_udp_ok` 全部逐拍脉冲化，此前两个没有默认值、变成"见过一次坏帧就永远为 1"的粘连电平（udp_rx_parser.v:86–90）。

## 5. UDP 载荷 → 像素：切包、拼帧、验收

### 5.1 一帧被切成多少包（算式）

协议：每包 `[u32 小端帧内偏移][RGB565 载荷]`（src/host/video_sender.py:4–5）。发侧三个常量：`OUT_W, OUT_H = 512, 300`、`FRAME_BYTES = OUT_W * OUT_H * 2`、`HDR = 4`、`MAX_PAYLOAD = 1392`（video_sender.py:32–35）。收侧对应：`IMG_W=512`、`IMG_H=300`、`FRAME_BYTES(IMG_W*IMG_H*2)`（system_top.v:136–137 与 eth_udp_video_top.v:235）。

| 量 | 算式 | 值 | 来源 |
|----|------|-----|------|
| 一帧字节 | 512 × 300 × 2 | 307200 B | frame_reasm.v:11 的默认值 `FRAME_BYTES = 307200` |
| 每包净荷上限 | — | 1392 B | video_sender.py:35（`MAX_PAYLOAD`，注为"8 的倍数；再大就会 IP 分片，而收包链不分片"） |
| 一帧包数 | ⌈307200 ÷ 1392⌉ | 221 | 上两行相除；`1392 × 220 = 306240`，尾包 `307200 − 306240 = 960` |
| 偏移开销 | 221 × 4 | 884 B/帧 | `HDR = 4`（video_sender.py:34）× 上一行的 221 |
| 线上 UDP 载荷 | 1392 + 4 | 1396 B | 上限须 ≤1472（= 1500 − 20 − 8，见 udp_push.py:98 那句 `if a.mtu_payload + HDR > 1472`） |
| 221 的独立硬证 | 663221 ÷ 3001 | 221 整除 | board/acceptance.md:36（表内第 5 行）："3001 帧 / 120.05 s = 25.00 fps、共发 663221 包" |

载荷必须是 8 的倍数的原因在写侧：包边界若落在 64bit DDR 字中间，打包器对同一个字分两次推送会互相覆盖 ⇒ 屏上出现规律黑点（src/host/udp_push.py:5–6）。1392 这个上限在三个发侧实现里各写了一遍、彼此一致：`MAX_PAYLOAD = 1392`（video_sender.py:35）、`const MTU = Number(get('mtu-payload', 1392))`（src/host/video_sender.mjs:29）、`--mtu-payload, type=int, default=1392`（udp_push.py:45）。第 7.3 节的 WSTRB 是那台打包器的解法，不是免罪符——`旧实现恒为 8'hFF，分包长度不是 8 的倍数（如 1396）时每帧 111 处 = 222 个 16bit 黑洞`（src/rtl/eth/axi_frame_saver64.v:80–82）。

### 5.2 偏移头与拼字

`frame_reasm` 的状态机五态：`S_OFF0/S_OFF1/S_OFF2/S_OFF3/S_DATA`（src/rtl/eth/frame_reasm.v:37）。四个偏移字节按小端逐字节拼，`wire [31:0] hdr = {p_data, off[23:0]};`（frame_reasm.v:105）在 `S_OFF3` 当拍成形，那里同时定下 `pkt_start` 与本包起点 `pend`（:131–132）。

载荷两字节拼一个 RGB565 字：

```verilog
                                wr_data<={p_data,pix_lo};
                                wr_addr<=off[18:1];
                                wr_en  <=(off < FRAME_BYTES);
```
（frame_reasm.v:150–152）

第三行是 #201 那一刀：原先这三行无条件写，而下面的行覆盖统计有界，于是发包方选的偏移能把字写到帧缓存之外。越界计数 `stat_oob_off`（frame_reasm.v:161），尺子是 `sim/tb_reasm_bounds.v` 的 R1/R2。

### 5.3 验收门：什么才叫"一帧收完"

`frame_done` 只在一个与门后头（frame_reasm.v:182）：

```verilog
                    if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame) begin
```

三条各挡一类事故。字节数挡不住"整行没来过"，所以有行位图；行位图会把"一个坏包填满一行"当好行，所以有 `bad_frame`；两者都过但最后一包短了，还有 `bytes_ok`。文件头把这条判据的现象写得很直白：缺行 ⇒ DDR 里留着旧/零像素 ⇒ 放大时黑纹会跟着动（frame_reasm.v:2–3）。

行覆盖存成 5 份 64bit 组（`rok0..rok4`，frame_reasm.v:81），因为 300 行 ≤ 320。行号由除法得到：`row_idx = off / ROW_STRIDE`，`ROW_STRIDE = IMG_W * 2`（frame_reasm.v:86–87），注释同时警告不许用 `off[16:1]` 截断——那会让约 172/300 行的判定错掉、`frame_done` 永不成立。

这个除法+位图在 125 MHz 上是有代价的：`这个"这一字节起一个新行"的项曾是全部 300 个覆盖触发器加 16 个 rows_hit 触发器的 CE 驱动，r106 布线后报告 fo=316，仅最后一跳就吃掉 6.879 ns 数据路径里的 1.980 ns，route 占 81.2 %`（frame_reasm.v:76–79 转述）。改法是每个 bank 单独一根使能网、公共项独热化成 `bank_one`（frame_reasm.v:97–102）。

`IMG_H` 越界由一条仿真期断言拦：`if (IMG_H > 5 * 64) $error(...)`（frame_reasm.v:217–220）。

### 5.4 乱序、丢包、重复各走哪条路，计数分别叫什么

结论：这个协议没有序号，所以"乱序"根本不是错误——每包自带绝对偏移，先到先写。真正的错误只有"缺"和"坏"。

| 情况 | 硬件行为 | 计数/输出 | 出处 |
|------|---------|----------|------|
| 乱序（先高偏移后低偏移） | 正常写入，行位图按到达记 | 无 | `sim/tb_udp_reasm.v` 覆盖点含"乱序（先高偏移后低偏移）" |
| 整帧字节凑够但缺行 | 不提交，保上一帧 | `frame_abort` 脉冲一次 + `rows_missed` | frame_reasm.v:196–203 |
| 缺行且没凑够 `FRAME_BYTES` | 不脉冲 `frame_abort`（没有"结束"可报） | 由 `stall_ms` 抓到 | frame_reasm.v:26–28 注释 |
| 坏包（`p_good` 不成立时） | `bad_frame<=1`，整帧作废 | `stat_bad++`、`frame_err` | frame_reasm.v:206–210（判据那个 if 在 :177） |
| 重复包（同偏移重发） | 覆盖同一批字，结果不变 | 计入 `stat_pkts` | 覆盖行为见 `sim/tb_udp_reasm.v` 覆盖点 |
| 偏移越界 | 不写、只数 | `stat_oob_off++` | frame_reasm.v:161 |
| 包计数 / 字节计数 / 成帧计数 | 每包/每帧累加 | `stat_pkts` / `stat_bytes` / `stat_frames` | frame_reasm.v:176、:188、:205 |

`bad_frame` 这一位是故意的行为改变：running byte total 没法把失败过的那一包扣回去，所以改成"坏包置一位、提交门测这一位"（frame_reasm.v:46–48 原文说明 verdict 不变、只多一位）。

`FRAME_BYTES` 曾在顶层没被传下去、用的是默认 307200，它只在 `IMG_W=512 且 IMG_H=300` 时与 `IMG_W*IMG_H*2` 偶然相等，改分辨率就会让它提前成立（提交半幅黑帧）或永不成立（不出 `frame_done`）。现在这一笔显式传参（eth_udp_video_top.v:231–235）。

## 6. ARP / ICMP / UDP 全在 PL：不等价的"等价最低实现"

结论：本设计能 `ping` 通，是因为把 ARP 和 ICMP 各自重做成了只干一件事的小状态机，省掉的不是代码量而是"一整套通用栈所必须维护的状态"。

### 6.1 每个模块负责什么

| 模块 | 职责 | 关键判据/字段 | 出处 |
|------|------|--------------|------|
| `arp_rx` | 从 GMII 流里认 ARP，取对端 MAC/IP | 以太网类型 `0x0806` 且目的 MAC 等于本机或广播；`src_mac/src_ip` 取的是**发送方** SHA/SPA | src/rtl/eth/arp_rx.v:1–4 |
| `arp_tx` | 拼一帧 ARP 请求/应答 | 前导码 8B + 以太头 14B（类型 0x0806）+ ARP 28B，补齐到 46B | src/rtl/eth/arp_tx.v:2–4 |
| `arp` | 上两者 + 一份 `crc32_d8` 的包装 | CRC 输入就是线上正在出的 `gmii_txd`，所以 FCS 只覆盖 ARP 帧（ARP 不经 IP，无伪头校验和） | src/rtl/eth/arp.v:1–4、:85 |
| `icmp_rx` | 认 IPv4 + ICMP，收 echo request | `0x0800` → 按 byte14 低 4 位 IHL 跳 IP 头 → 协议字段 1；载荷字节数 = IP 总长 − 20 − 8 | src/rtl/eth/icmp_rx.v:2–5 |
| `icmp_tx` | 拼 ICMP 回显应答 | 以太头 14B + IPv4 头 20B（版本/IHL `0x45`、TTL `0x80`）+ ICMP 8B + 数据，不足 46B 补齐 | src/rtl/eth/icmp_tx.v:2–6 |
| `icmp` | 上两者 + 一份 `crc32_d8` | `identifier/sequence` 原样回填 | src/rtl/eth/icmp.v:1–4、:105 |
| `eth_ctrl` | 三路共用一根 GMII 发送口的仲裁 | `protocol_sw`：`2'b00`=ARP、`2'b01`=UDP、`2'b10`=ICMP；ARP 应答从"抢一拍"改为"记账 + 全空闲才兑现" | src/rtl/eth/eth_ctrl.v:1–7 |
| `udp_tx` | UDP 发送器 | 顶层 `tx_start_en(1'b0)`，"与今天一致：Z7 不发 UDP" | eth_udp_video_top.v:166 |

`crc32_d8` 有 4 份实例：arp.v:85、icmp.v:105、eth_udp_video_top.v:180（发送侧）、gmii_rx_mac.v:37（接收侧）。

### 6.2 CRC 是硬件算的，不是查表

`crc32_d8` 通体是 32 条形如 `assign crc_next[0] = crc_data[24] ^ crc_data[30] ^ data_t[0] ^ data_t[6];` 的组合异或式（src/rtl/eth/crc32_d8.v:23–26），一次吞一字节，没有 ROM、没有查表、没有迭代。多项式在注释里给了完整展开（crc32_d8.v:20–21）。两个约定要记住：`crc_data` 复位为全 1、每字节异或前先做位反转 `data_t`（crc32_d8.v:2，`assign data_t = {...}` 在 :18）。

查表实现需要 8×32bit 的 ROM 加至少一次移位/异或的时序，在 125 MHz 上通常要拆两拍；组合 XOR 树一拍就走完，代价是 LUT。本工程选后者，因为收侧那份 CRC 长在 `gmii_rx_mac` 的帧尾判定锥上，第 2.4 节说的 8 ns 周期不给多一拍。

### 6.3 为什么没有 lwIP 也能 ping 通

ping 需要的完整链条其实只有五件事：有人应答 ARP、有人认得 ICMP echo request、有人把 identifier/sequence 抄回去、有人算两个校验和、有人发出去。逐条对上代码：

| 需要 | 本设计的做法 | 出处 |
|------|-------------|------|
| 一个 IP | 编译期常量 `{8'd192,8'd168,8'd1,8'd10}` | system_top.v:159 |
| 一个 MAC | 编译期常量 `48'h00_11_22_33_44_55` | system_top.v:158 |
| ARP 表 | 无表，只把来包源字段存进 `src_mac/src_ip` 并当唯一目的地址用 | eth_udp_video_top.v:134、:136–137 |
| 路由/分片 | 无；收包链不分片 | video_sender.py:35 的注释 |
| 应答时机 | `icmp_rec_pkt_done` 装 `icmp_dly = 6'd20`，倒数到 1 时打 `icmp_tx_start_en` | eth_udp_video_top.v:96–109 |
| 载荷暂存 | 一份 8bit × 2048 深同步 FIFO | eth_udp_video_top.v:119 |
| 两个校验和 | IP 首部与 ICMP 全在一拍数里算一补数、进位折叠两次再取反 | icmp_tx.v:5–7 |

`icmp_dly` 那 20 拍在 125 MHz 上是 160 ns，作用是给对端留出接收间隔，不是软件超时。

省下的是什么：PS 侧一个字节都不碰这条通路（`main.c:2` 的口径是"UDP 视频数据通路仍然整个在 PL"；`report/ps_vs_pl.md:40` 同一句）。于是省掉了每包一次中断加一次 memcpy——v1 那套 PS + lwIP 的成本在 `report/ps_vs_pl.md:23` 量化为"约 220 包/帧、30 fps"。省掉了片上协议栈的 RAM/ROM 与它的初始化，也省掉了"PL 收包 → 通知 PS → PS 拼帧 → PS 写 DDR"这三次交接。演示口径里 `ping 192.168.1.10` 通不通判的就是位流在不在跑（`report/host_guide.md:17`、`report/demo_script.md:28`）。

省不掉的两件事，本卷必须一起写：这套最低实现没有任何错误源（第 13 节），以及它的行为边界要靠台架自己钉住（第 12 节那几支 icmp 台架不是装饰，`ping -l 0` 那一档改前会让发侧数据态数到 65536 拍，见 `report/known_issues.md` 第 321–345 行的 `#188`）。

## 7. PL 当 AXI master 写 DDR

### 7.1 五份变体，哪一份在跑

| 文件 | 例化在 `src/rtl` 里？ | 谁在仿它 | 定位 |
|------|---------------------|---------|------|
| `eth/axi_frame_saver64.v` | 是（`u_saver`，eth_udp_video_top.v:354） | tb_v5_bank / tb_v6_ingress_integrity / tb_v6_pingpong / tb_v6_tail_bank | **现役入包写侧** |
| `eth/axi_frame_saver.v` | 否 | — | 每 beat 一个像素、2 字节 AWSIZE 的早期版（头注释 src/rtl/eth/axi_frame_saver.v:2，`m_axi_awlen = 8'd0` 在 :29） |
| `eth/axi_frame_saver_burst.v` | 否 | tb_v5_saver | 攒连续地址成 burst 的那一代 |
| `axi/axi_frame_writer_gated.v` | 是（`u_row`，pl_video_top.v:454） | tb_v5_copy/gated/vblast/v57/v58/v6_vblank_copy/tb_writer_abort | 现役 **ETH→显示帧缓存** 读侧搬运机 |
| `axi/axi_frame_writer64.v` | 是（`u_aw`，pl_video_top.v:692） | — | 现役 **PS(SD/FILL)→显示帧缓存** 读侧搬运机 |
| `axi/axi_frame_writer.v` | 否（文件头自述"本树无人例化"） | 只在 `build/sim/run_sim.tcl` 的文件清单挂名 | 遗留件 |

顶层端口连接给出的判据：`u_eth` 的 `m_axi_awaddr/wdata/wstrb/bvalid` 那一线接到 HP0（system_top.v:193–199），`u_pl` 的 `m_axi_ar*` 读口按 `eth_mode` 在两台搬运机之间二选一（pl_video_top.v:709–714）。

### 7.2 突发长度、outstanding、握手形状

结论：写侧**不做长突发**——`m_axi_awlen = 8'd0`、`m_axi_awsize = 3'b011`（8 字节）、`m_axi_awburst = 2'b01`（AXI 编码里的 INCR）、`m_axi_wlast` 恒 1（axi_frame_saver64.v:40–44）。吞吐完全靠并行挂出与在途深度。

```verilog
    localparam [3:0] OST = 4'd8;          // 在途 beat 上限（够盖住 HP0 写延迟）
    wire       have   = (rptr != wptr) && !beat && (outst < OST);
```
（axi_frame_saver64.v:66、:74）

AW/W 各自握手、各自等接收，`m_axi_bready` 恒 1，"B 通道永不反压，只回收计数"（axi_frame_saver64.v:156）；`outst` 只减不回绕，理由是"万一上游偶尔多回一个 B，回绕成 15 会让 `have` 永远不成立 ⇒ 整条入包链就此卡死"（:158–160）。

为什么必须流水化：`v6.2 之前每字走完 S_AW→S_W→S_B，在途深度恒 1 ⇒ HP0 写延迟（~40 拍，被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈20 MB/s ⇒ 板上"每包固定从第 48 字节起丢字"`（axi_frame_saver64.v:5–7）。改后 ≤2 拍/字 = 400 MB/s（:2–3 自述；100 MHz ÷ 2 × 8 B = 400 MB/s）。同文件 :7 补了一句重要的话：加深缓冲治不了这个瓶颈，v6.2 把 CDC 做到 8192 条时上板毫无改善——瓶颈是平均排空速率，不是深度。

### 7.3 16bit → 64bit 的打包器

`axi_frame_saver64` 内部一份 512 深（`FW = 9`）的打包 FIFO，必须显式要 `ram_style = "distributed"`：早先让它被综合成触发器时 512×100bit 约 5.1 万个 FDRE，占整机 Slice Register 的 94 %，`FW=11` 直接 DRC UTLZ-1（axi_frame_saver64.v:10–13、:46–50）。同一处还留了一条反直觉的实现纪律：存储写必须独占一个不带异步复位的 always 块，写成 task 并和指针同块时 Vivado 报 `Synth 8-7186` 拒绝推断成 RAM，实测 task 写法 FF=32904/LUTRAM=0，本写法 FF=85/LUTRAM=864（:104–107）。

`WSTRB` 按 16bit lane 展开：`{ {2{keep_r[3]}}, {2{keep_r[2]}}, {2{keep_r[1]}}, {2{keep_r[0]}} }`（axi_frame_saver64.v:83–84）。

### 7.4 跨域与提交时机

125 MHz → 100 MHz 只过一份 BRAM CDC：`dc_fifo #(.DATA_W(36), .ADDR_W(13))`（eth_udp_video_top.v:298），36bit = 1 位 flush 旗 + 19 位字地址 + 16 位数据（`:264–265`）。深度 8192 条 = 4096 个 64bit 字 = 16 KB，够吸收"显示拷贝独占 HP0 一整个 V-blank"期间到达的入包（:295–297 的估算写作 15 MBps × 672 µs ≈ 1260 字）。

读侧节拍从"每 3 个 axi 周期取 1 条"改成 1 条/周期：前者 66 MB/s 小于入流需要的 125 MB/s，单包就能把 CDC 灌满，稳定丢约 46 % 的字，表现为"每隔一个 16bit 空洞"的黑纹（eth_udp_video_top.v:258–262）。同一处规定 flush 标记永远让路给真实数据写。

那句"每包 698 个 16bit 写"（eth_udp_video_top.v:259）数的是整包 UDP 数据流的宽度：`(1392 + 4) ÷ 2 = 698`，两个操作数是第 5.1 节的净荷上限与偏移头长度。真正带像素的写只有 `1392 ÷ 2 = 696` 条——那 4 个偏移字节走的是 `frame_reasm` 的 `S_OFF0..S_OFF3` 四个状态、不产生 `wr_en`（frame_reasm.v:126–130）；每包末尾再补一条 flush 进同一条流（:174–175）。698 / 696 / 697 各有意义，念的时候要说明是哪一个。`report/perf_report.md:27` 那行写的 "payload≤1396" 用的是 UDP 数据段口径（1392 + 4），不是发侧那个 1392 的净荷上限，两处不矛盾但字面差 4。

`ddr_bank_commit` 干三件事（src/rtl/eth/ddr_bank_commit.v）：`frame_done` 先转成翻转位再过 3 级同步器（:37–47）；请求换页并等打包器排空；排空判据不只看 `saver_idle`：

```verilog
    wire tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
    wire commit_ok    = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle;
```
（ddr_bank_commit.v:50–51）

`TAIL_GUARD=1` 修的是 v6.4 的"帧尾 4 字节偶发丢失"——旧判据只看 `saver_idle`，它对 8192 深的 CDC 和后面的读流水完全不可见，结果帧尾几个 16bit 被写进下一帧的 bank，板上是 HDMI 右下角少 2 像素（:6–7）。顶层确实带 `TAIL_GUARD(1'b1)` 例化（eth_udp_video_top.v:330–331）。这段 glue 之所以是独立模块，理由写在 :4–5：以前写在顶层里、TB 只能手抄一份，而抄的那份永远不会因真代码改错而变红。

## 8. 帧缓存与乒乓 bank

结论：乒乓做在 **DDR bank 层**，不发生在 BRAM 层；显示侧只有一块帧缓存。

### 8.1 地址分配

| 用途 | 地址 | 大小 | 出处 |
|------|------|------|------|
| ETH bank0 | `32'h1000_0000` | 一帧 307200 B | system_top.v:139 `DDR_BASE`；eth_udp_video_top.v:67 |
| ETH bank1 | `BASE_ADDR + 32'h0008_0000` = `0x1008_0000` | 同上 | eth_udp_video_top.v:68 |
| PS 专用第三 bank | `32'h1010_0000` | 同上 | system_top.v:144 `PS_DDR_BASE`；sd_play.c:35 `FRAME_ADDR` |

间隔 512 KB（0x80000）而一帧只 300 KB，是刻意留裕量的：`ETH 占 0x1000_0000 与 0x1008_0000 乒乓两 bank（每帧 300 KB，间隔 512 KB 够用），所以第三个 bank 从 +1 MB 起`（system_top.v:140–141）。同一段还钉了一条跨语言契约：这个数必须与固件里的 `FRAME_ADDR` 一致，改一边不改另一边的现象是"PS 片源在屏上不动"。

### 8.2 读写同时命中同一 bank 会怎样

三种情形分别处理：

- **写 DDR、同时读 DDR 显示**：不撞。写的是 `bank` 选中的那块，读的是 `completed_base` 那块；换页只在提交那拍发生（ddr_bank_commit.v:67–72）。
- **两台搬运机同时抢同一条 HP0 读口**：不允许同时。`eth_mode ? row_arvalid : fill_arvalid` 一系 mux 加 `src_arb` 的 `both_idle` 互锁（pl_video_top.v:709–714、第 9 节）。
- **搬运与扫描同时在帧缓存 BRAM 上撞**：写侧被 `allow_wr` 钳在消隐期。预算写在 pl_video_top.v:392–396：`V_TOTAL 625 - active 600 = 25 blank lines = 33.5k pix cycles = 67k axi(100M) cycles, and one frame is 38.4k 64-bit words`——搬得完，所以显示 BRAM 在每一个有效行里都握着一整帧，没有新旧缝。超没超窗口是硬件自测的：`VBLANK_AXI_CYC = 32'd67200`，超过就把 `copy_overrun` 粘住并用 led[0] 看（pl_video_top.v:445–452）。

这里要纠正一个常被念反的口径：**帧缓存 BRAM 的写侧在 100 MHz、读侧在 50 MHz**，不是反过来。写口 `wr_clk(axi_clk)`（pl_video_top.v:736，一路透传进 `fb_bilin` 的 `frame_buffer_w64`，src/rtl/process/bilin/fb_bilin.v:66），读口 `.rd_clk(clk)` 而 `fb_bilin` 的 `clk` 是 `clk_pix`，文件头自己写着"时钟域：clk_pix 50 MHz 单域（wr_clk 只是帧缓存的写侧直通）"（fb_bilin.v:6）。分工的道理：搬运机必须跟 AXI 同域才能直连 HP0 的 R 通道；扫描必须跟像素钟同域才能一拍一像素出数。两侧不同频，所以 `frame_buffer_w64` 声明为"写 wr_clk / 读 rd_clk 两个域"、读延迟 1 拍（src/rtl/video/frame_buffer_w64.v:2–3）。

帧缓存本身有一条尺寸教训：不能直接声明一个 38400 深的阵列，BRAM 推断会把非 2 的幂的深度向上填到 2^16，512×300 实测吃掉 128 个 RAMB36（全片只有 140 个），拆成 32768 + 8192 两块后实测 80 个（frame_buffer_w64.v:4–8）。当前实现后总量是 95.5 / 140 tile、68.21 %，"帧缓存由 64-bit 宽 + 乒乓两块拼出，是 BRAM 的主要去向"（`data/metrics.csv` 第 10 行）。

### 8.3 `snap_cross` 的初值问题

找到了一条，写清楚。`snap_cross` 的 `hb_gone` 带声明初值：

```verilog
    output reg             hb_gone = 1'b1,
```
（src/rtl/eth/snap_cross.v:29）

原因是这颗寄存器在 `pl_demo_top` 那棵树下，而顶层把 `sys_rst_n` 绑成常量：snap_cross 的文件头点名"`system_top.v:250` 那条死复位，`snap_cross.dst_rst_n` 是它传下来的"（snap_cross.v:21–24 原文），现文件里那条死复位在 `system_top.v:260` 的 `.sys_clk(sys_clk), .sys_rst_n(1'b1),`。于是 `if (!dst_rst_n)` 分支永远走不到 ⇒ 上电值只由位流里的 INIT 承载；不写声明初值它就是 `1'b0`，而复位分支写的是 `1'b1` ⇒ "心跳没来过"这件事在配置完成后的一拍会被误报。尺子是 `build/scan_dead_reset_init.py`（随包在树里），snap_cross.v:25 记的改前读数是 `WANT1 root=pl_demo_top init_miss=1`、要求改后 `init_miss=0`；它点名的原始凭据件 当时那份死复位扫描输出没随包留下 不在这份拷贝里，所以那条读数只能引到注释、引不到原件。同一段还钉了一条不许顺嘴说的话：`pl_demo_top` 不在当前位流里（正式构建的是 `system_top`），所以这一处对时序名册与 WNS 是无感的，不能拿来当收益讲（snap_cross.v:27–28）。

`snap_cross` 的其余机制一句话能说完：源域整拍写好 320 位宽总线并同拍翻 `bus_tog`，目的域等同步过来的跳变沿再采（`bus_edge = ts[2] ^ ts[1]`）；心跳另判两件事——`hb_gone` 是钟停了，`hb_slow` 是钟被拉慢，两条分开是因为"时钟退化≠时钟停"（snap_cross.v:4–7、:58–65）。顶层参数：`W=320`、`DST_HZ=100_000_000`、`HB_TO_MS=200`（system_top.v:214）。

## 9. `src_arb`：三路网口之外的仲裁

结论：这台仲裁管的不是"屏幕显示哪一路"，而是"这一台 DDR→帧缓存搬运机归谁"，所以它只需要在两个引擎都空闲时换手，切换不需要复位任何东西。

被仲裁的两侧：`row_busy` 来自 ETH 引擎（`axi_frame_writer_gated`），`fill_busy` 来自 PS 引擎（`axi_frame_writer64`）（src/rtl/util/src_arb.v:29–30）。第三路图卡不参与仲裁——它只决定"显示什么"，不决定"谁在搬"（pl_video_top.v:170 注释）。

换手判据两行：

```verilog
            if (both_idle) begin
                why_ps <= {force_ps, ~eth_live, ~eth_tb_ok};
                if (eth_wanted)             owner_eth <= 1'b1;
                else if (quiet >= T_OFF_CYC) owner_eth <= 1'b0;
```
（src_arb.v:67、:73–75）

`both_idle = ~row_busy & ~fill_busy`（:48）是唯一赋值点 ⇒ 一次拷贝中途选择位绝不翻转。文件头把这条写成规矩：手动锁"只改谁想要总线，不改什么时候能换手"，直接在输出上加 mux 会留下半开的 AXI 读突发（:41–:44）。这就是"切换不需要复位"的原因：换手发生在两台都静止的那一拍，两侧的状态本来就是干净的。

两级判据与一级滞回：

| 层 | 内容 | 数值 | 出处 |
|----|------|------|------|
| 活着 | `eth_live` = 快照 lane7.bit3 = `stall_ms < 200` | 200 ms | system_top.v:251、eth_udp_video_top.v:285 `LIVE_MS(16'd200)` |
| 时基可信 | `eth_tb_ok = !(lm_clk_slow || lm_clk_gone)` | — | system_top.v:256 |
| 滞回 | `T_OFF_CYC = 2_000_000`，AXI 域 100 MHz ⇒ 20 ms | 20 ms | src_arb.v:20；pl_video_top.v:421 |

为什么要有第二级：`stall_ms` 这些"ms"其实是周期数，而断链时 RTL8211 不停供 RXC、把它拉到约 2.5 MHz（约 1/48），于是 `stall_ms` 以 1/48 的速度爬、`stall_ms < 200` 会连着骗人十几秒 ⇒ 仲裁死占 ETH、SD 接不回画面（link_monitor.v:6；src_arb.v:11–14）。`eth_wanted` 因此是 `eth_live & eth_tb_ok` 相与（src_arb.v:51），且这个相与放在仲裁模块里而不是外面那个裸与门上——只有放进去才台架验得到（src_arb.v:14）。

长按怎么切：板上只有两个键、已被"旋转 ±1°"占了，所以短按保持原意、长按多出一个事件。`key_long #(.HOLD_CYC(30_000_000), .ARM_CYC(10_000_000))` 在 50 MHz 上就是 0.6 s 触发、0.2 s 起 LED 提示（pl_video_top.v:148–150；语义与阈值变更见 src/rtl/util/key_long.v:1–10）。长按输出是**翻转位**而不是脉冲（脉冲跨域会被吃掉），进 `src_mode` 与串口覆盖命令合流成四态格雷码 `AUTO/ETH/SD/TEST`（src/rtl/util/src_mode.v:1–3、:19、:24），再由一行适配器翻译成 `src_arb` 的 `sel`（pl_video_top.v:171）。`src_arb` 的 `sel` 编码与 `src_mode` 的四态码不是同一份（那边 SD=3、TEST=2），中间那一行适配是唯一出处（src_arb.v:26–28）。

当前来源怎么读回：`dbg_src` 那 16 位（位序唯一出处在 pl_video_top 的端口注释与 `assign dbg_src`，pl_video_top.v:65–68、:603）经 lane30 出去：`lm_rd = {16'd0, dbg_src}`（system_top.v:239）。位展开：bit0 `eth_tb_ok`、bit1 `eth_live`、bit2 `owner_eth`、bit3 `fill_busy`、bit4 `row_busy`、bit[6:5] 仲裁看到的模式、bit[10:8] `why_ps`。宽度这条有历史教训：顶层曾写过 `[5:0]`，综合只给一条 `Synth 8-689` 警告就把模式高位静默丢掉，TEST(10) 读起来像自动(00)、SD(11) 像 ETH(01)（system_top.v:224–226）。

## 10. `link_monitor`：这台硬件数了什么、怎么读回来

### 10.1 计数清单（只列代码里真存在的寄存器）

`link_monitor` 全在 `eth_rxc` 域，输入都是源模块已打过一拍的寄存器输出，所以模块内不许再往关键路径插组合逻辑（src/rtl/eth/link_monitor.v:3–4）。参数在顶层钉：`CLK_HZ(125_000_000)`、`LIVE_MS(16'd200)`（eth_udp_video_top.v:284–285），`SETTLE` 默认 32（link_monitor.v:11）。

| 内部寄存器 | 含义 | 出处 |
|-----------|------|------|
| `drop_words` | 被 `fifo_full` 吃掉字数（板上唯一真实丢数据通道） | link_monitor.v:69 |
| `frames_bad` | 被作废的帧 | :70 |
| `pkt_err` | 坏包（上板恒 0，见 10.4） | :71 |
| `cdc_ep` | CDC 进入"满"状态的**次数**，不是拍数 | :72 |
| `rows_miss_max` | 历次作废帧里缺行最多的一次 | :73 |
| `stall_ms` | 距上一个 `frame_done` 过了多少 ms（活看门狗） | :74 |
| `gap_last/gap_min/gap_max/gap_sum` | 帧间隔的最近/最小/最大/累加，由 `gap_cnt` 直接数出来 | :75–76 |

`TC = CLK_HZ / 1000` 在 125 MHz 上是每毫秒 125000 拍（:36）。分频器位宽必须由 `TC` 算（`DW = $clog2(TC + 1)`，:41）：写死 `[15:0]` 时装不下 125000，`ms_div == TC-1` 恒假 ⇒ ms_tick 永远不来，ms32/stall/gap/心跳在板上全死，而仿真把 `CLK_HZ` 改成 1000 完全看不出（:38–40）。

16bit 字段一律饱和不回卷：`> 0xFFFF` 就钉在 `0xFFFF`（:90–92）。理由原文："健康数字回卷到 0 会被读成'没问题'，这是比少报更坏的错"（:88–89）。

发布节流：`SETTLE=32` ⇒ 两次写入之间留 256 ns，覆盖到 31 MHz 以下的目的时钟；节流期间到的事件记进 `pend_ev`、窗口一过补发，否则正好落在窗口里的 `frame_done` 会被整个丢掉而 stall 要等 200 ms 才再刷（:165–184）。

### 10.2 十条 lane 的打包

`lm_bus` 是 320 位 = 10 条 32 位 lane（link_monitor.v:187–196、:202–203）：

| lane | 内容 | lane | 内容 |
|------|------|------|------|
| 0 | `drop_words` | 5 | `gap_sum`（均值 = lane5/(frames_ok−1)） |
| 1 | 高 16 = `pkt_err`，低 16 = `frames_bad` | 6 | `cdc_ep` |
| 2 | 高 16 = `rows_miss_max`，低 16 = `stall_ms` | 7 | `flag5` 五位标志 |
| 3 | `gap_last` | 8 | `in_pkts`（= `frame_reasm.stat_pkts`） |
| 4 | 高 16 = `gap_max`，低 16 = `gap_min` | 9 | `in_bytes`（= `stat_bytes`） |

每条都显式声明成 `[31:0]` 再拼，因为"一行里塞两个字段曾把 lane1 拼成 48 bit、整条总线错位"（:186）。`flag5` 位序：bit4 帧间隔统计已可用、bit3 流还活着、bit2 CDC 曾灌满、bit1 作废过帧、bit0 丢过字（:158–162）。

### 10.3 怎么经 AXI GPIO 读回来

不需要新加 AXI 从设备，只用两只 GPIO：

| 角色 | 地址 | 用法 | 出处 |
|------|------|------|------|
| GPIO_0（输出） | `0x41200000` | bit[31:27] 写 lane 号 | build/tcl/build_system_axigpio.tcl:244；system_top.v:219 |
| GPIO_1（输入） | `0x41210000` | 读那一条 32bit | build_system_axigpio.tcl:245；system_top.v:247 `assign gpio1_i = lm_rd;` |

xsdb 侧的机械动作就两句：`mwr -force ${GPIO0} 0x${((keep | (n << 27)) >>> 0).toString(16)} 32` → `after 20` → `mrd -force 0x41210000`（src/host/health_read.mjs:283–286，脚本里的 GPIO0 默认拼成上表的 0x41200000，见 health_read.mjs:38）。选 lane 之前先把 GPIO_0 原值读回来、只改这 5 位、最后写回去，否则会踩掉 `src_sel/特效/阈值`（health_read.mjs:10–11、:314–321：读不到原值就直接退出，第一版失败后继续往下写就把控制字清零了）。越界的 lane 号返回 `0xDEAD_BEEF`，让脚本一眼看出自己写错了号（system_top.v:244）。

清零：`gapclr_sel = gpio_o[26]`（system_top.v:203），进 125 MHz 域前先过 3 级 `ASYNC_REG`（eth_udp_video_top.v:277–281），因为它是准静态电平不是脉冲，同步后直接当电平用。**没有串口命令做这件事**——本仓库的清零入口是上位机：`node src/host/health_read.mjs --gapclr` 把 bit26 拉高 250 ms 再落下（health_read.mjs:41–45 `CLR_BIT = 26`、:271–278）。清零只动 `gap_*` 与 `have_base/gap_valid`，lane0/1/2/6/8/9 保持"自启动以来"的语义（link_monitor.v:24–25、:116–119）。为什么非要有这个入口：`gap_max` 是终身保持的，一次长空闲就会污染它，而且回卷后会读起来反而更小（eth_udp_video_top.v:63–65）。

### 10.4 实测读数与各自的条件

留档件有两份，都不是"随便一读"：

**件 A**：`build/evidence/r92_health.txt`，同内容被导出器改名放进提交包的 `final_submission/board/output/health.txt`（改名记录见 `final_submission/_pruned.txt:301`）。条件是 r92 那轮推流中读的（`board/acceptance.md:20` 与 `:37` 点名这份件；`report/perf_report.md:413` 把它归到 r92 那一跑）。原文读数：

| lane | 十六进制 | 十进制解 |
|------|---------|---------|
| 0 `drop_words` | `0x00000000` | 0 |
| 1 `bad\|err` | `0x00000001` | 作废帧 1、坏包 0 |
| 2 `stall\|rows` | `0x012b0000` | stall_ms 0、缺行峰值 299（0x12B） |
| 3 `gap_last` | `0x00000030` | 48 ms |
| 4 `gap_min\|max` | `0x003e0013` | min 19、max 62 ms |
| 5 `gap_sum` | `0x000081bb` | 33211 ms |
| 7 `flags` | `0x0000001a` | 0b11010：作废过帧 / 流活着 / 间隔已校准 |
| 8 `pkts` | `0x0002cffb` | 184315 |
| 9 `bytes` | `0x0f4563c0` | 256205760 |

件 A 内部可以自证，两条恒等式都严格成立：`221 × 834 + 1 = 184315`（包数 = 834 整帧 × 221 包 + 1 包），`307200 × 834 + 960 = 256205760`（字节 = 834 整帧 + 一个 960 B 尾包）。两个乘数分别是第 5.1 节的 221 包/帧与 960 B 尾包，除数是 307200 B/帧。这等于用硬件计数复算了一遍切包算式。

不过同一轮的汇总行写的是 `bytes=390417344`（report/perf_report.md:413），换算 `0x17454bc0`，与留档件里的 `0x0f4563c0` 对不上；两份件引用时只能各念各的，不能互相背书。

**件 B**：`build/r94_health_rotclamp.txt`（第 4–22 行）。条件更硬：推流**之中**读的，同一行给了"3001 帧 / 120.05 s = 25.00 fps、共发 663221 包"（board/acceptance.md:36 第 5 行）。读数：lane0 = 0、lane1 = `0x00000001`、lane2 = `0x012c0000`（缺行峰值 300）、lane3 = `0x28`（40 ms）、lane4 = `0x005f0009`（min 9 / max 95 ms）、lane5 = `0xdd41`（56641 ms）、lane7 = `0x1a`、lane8 = `0x4c9dd`（313821）、lane9 = `0x1a09a002`（436838402）。同页末尾自带的判读行是："drop_words=0 stall_ms=0 缺行峰值=300 丢过字=0 作废过帧=1 CDC灌满过=0 流活着=1 间隔已校准=1"，结论那句写的是"入包链一个字都没丢——这正是屏幕上看不出来的那部分证据"（件 B 第 32–33 行）。

**读数的适用边界**，三条必须一起念：

1. 空闲态的 `drop_words=0` 是零样本。`board/signoff.md:88–93` 的 S8 就是把这条判成 NOT_MEASURED 的：`board_verify_console.txt:21` 的 `drop_words → 0` 与同一份读数 `:18` 的 `"eth_live":0` 摆在一起——没有流量时它不可能不丢。该判据只在带流那两次（S7）才算成立，处理方式写死为"S8 永远不升 PASS"（:290）。
2. `lane8/lane9` 是自启动以来的累计量，不是这一轮的量。件 B 的 313821 包明显小于该轮已发出的 663221 包，读的是中途值。
3. `stall_ms` 与所有"ms"在断链时不成立，必须与"源时基健康"相与再用（link_monitor.v:6–7）。

限速侧的丢包量化另有一份表：30 fps / 限速 15 MB/s 的演示工况 600 帧零作废、`drop_words=0`、平均帧间隔 33.33 ms、交付 30.007 fps；每 2000 包丢 1 时作废 66 帧、每 200 包丢 1 时 600 帧全部作废；300 秒长跑 9000 帧零丢帧/零坏帧/零重复帧；不限速到 116.7 fps 仍不丢字，因此不给"PL 能扛多少 fps"的数字（`report/perf_report.md` 第 173–178 行的那张表；`data/metrics.csv` 第 22、23、24 行是它的指标化版本）。

## 11. SD 通路：为什么这条路不需要 PL 的 AXI master

结论：SD 那一路写 DDR 的人是 PS 的 SD 控制器，PL 只做一次读，所以 PL 侧那台 `axi_frame_saver64` 在这条路上根本没有工作。

数据流原文："SD(DMA) → DDR@BASE_ADDR →（PL 在 frame_start 拉一次 HP0 复制）→ 显示帧缓存"（src/ps/sd_play.h:4）；同一件事在 sd_play.c 文件头写成"帧的落地路径刻意做成零拷贝：SD 控制器的 DMA 直接写 PL 要读的那块 DDR，写完只发一次发布脉冲 ⇒ PS 不需要 300 KB 的 memcpy，也不需要第二块 DDR 做双缓冲"（src/ps/sd_play.c:12–13）。

代码上看得见的三点：

1. 目标地址直接就是 DDR：`feed_cur()` 里 `left = FRAME_BYTES, dst = FRAME_ADDR`，逐簇推进 `dst     += bytes`（sd_play.c:744、:759），`FRAME_BYTES = 512×300×2 = 307200 B = 600 扇区`、`FRAME_ADDR = 0x10100000`（sd_play.c:34–35）。
2. 控制器调用一次到位：`XSdPs_ReadPolled(&Sd, lba, n, dst)`，`dst` 就是那块 DDR（sd_play.c:109）。搬运之前先 `Xil_DCacheFlushRange`，注释解释了为什么必须先 flush：驱动读完会 invalidate 目标区间，但若那里有脏行（例如刚跑过 FILL），invalidate 之后脏行仍会被写回，把刚进来的数据盖掉（sd_play.c:86–88、:95）。
3. 通知 PL 只有一拍：`ps_publish()` 翻一个电平位再写整字（src/ps/main.c:242–245），位是 `gpio_o[18]`（system_top.v:288 那根线；位表在 `main.c:9–10`），PL 侧 `pub_consume = frame_start && src_use && !owner_eth_pix`——"复制一次"而不是"每帧都复制"是关键，前者让 PS 有整个帧周期可以安全覆写 DDR，后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（sd_play.c:15–18；pl_video_top.v:559）。

于是两条通路的分工差异可以一表说清：

| | ETH 通路 | SD 通路 |
|--|---------|---------|
| 谁把帧放进 DDR | PL 当 AXI master 走 HP0 写口 | PS 侧 SD 控制器直接写 |
| PL 用的 AXI 通道 | AW/W/B（写） | 只用 AR/R（读） |
| 乒乓 | 有（bank0/bank1 换页） | 无（同一块 `0x1010_0000`，靠"一次只搬一帧"避开撕裂） |
| 通知方式 | `frame_done` 硬件自数验收门 | 软件翻 `gpio_o[18]` |
| 搬运机 | `u_row`（`axi_frame_writer_gated`） | `u_aw`（`axi_frame_writer64`，`enable(eth_mode ? 1'b0 : src_sel)`，pl_video_top.v:696） |

代价也写在文件里：SD 那一路没有 PL 的验收门，所以片源活着与否必须靠第二条心跳判据（"最近 500 ms 收到过发布没有，停心跳 = 把画面交回仲裁"，sd_play.c:772–773 的 `#94` 段；判据本体在 src/rtl/util/src_life.v）。

## 12. 本卷的台架清单

下面这些文件名在 `sim/` 里真实存在（`ls sim/` 数到 82 支 `tb_*.v`），只列覆盖本卷内容的。

| 台架 | 打什么判据 |
|------|-----------|
| `tb_v795_rx_fcs.v` | 量具自校（TB 造的帧真是标准以太网帧）、好帧判好、翻 1 bit 判坏、短帧判坏、残值与载荷无关，并把残值钉回 RTL 里的 `FCS_RESIDUE` |
| `tb_v795_rx_chain.v` | `gmii_rx_mac` + `udp_rx_parser` 串起来：好帧全收、翻 bit、端口不对被过滤、载荷中段被截断、两帧连发计数互不串；C1..C5 |
| `tb_udp_parser.v` | 一条 52 字节合法帧的 10 字节载荷逐拍吐出；dport 改 5002 后一字节都不许外发 |
| `tb_udp_reasm.v` | 正序成帧、乱序、坏包计数、重复包覆盖、第二次成帧，加 `wr_en/wr_addr/wr_data` 落点 |
| `tb_reasm_bounds.v` | #201：越界偏移不许发 `wr_en` 但必须被 `stat_oob_off` 数到，边界与正常路径不许被收紧（R1/R2/正常段三场景） |
| `tb_v6_cover_gate.v` | 覆盖率门控：丢过一包（留黑洞）的帧必须不提交且计入 `stat_bad`；完整帧与恢复帧各提交一次 |
| `tb_crc32.v` | 复位初值 `FFFF_FFFF`、单字节更新、`crc_clr`、同一序列跑两遍逐位相同 |
| `tb_icmp_ping0.v` | `tx_byte_num=0` 不再回绕成巨帧（数据态 18 拍而非 65536）；8/56 两档不被补位逻辑改动 |
| `tb_icmp_rx_len.v` | 14 轮载荷长度 1,2,…,64 逐字节收取：`rec_byte_num`、`rec_en` 次数、字节顺序、每包一次 `rec_pkt_done`，含"声明长度 0"与截断包不再楔死 |
| `tb_icmp_len_wrap.v` | #206：IP 总长 < 28 的畸形包之后解析器必须回 idle、紧跟的合法 ping 必须仍被应答（R1/R2/R3 三条配对） |
| `tb_icmp_tx_cksum.v` | 把整帧字节流钉死，作为"校验和拆拍"类改动的等价尺子 |
| `tb_v112_ip_csum.v` / `tb_v112_tx_bytes.v` | IP 首部十项求和 + 两次折叠 + `20 位累加器装得下` 这条界；以及 6 个矢量的发送字节流指纹 |
| `tb_sync_fifo.v` | 8bit × 16 深同步 FIFO 的 `level/empty` 与先连写后连读的数据对应 |
| `tb_cdc_capacity.v` | `dc_fifo` 36bit × 8192 的满边界落在第几格、报满后是否还收字、指针回绕 3 轮（C1..C5） |
| `tb_v6_ingress_integrity.v` | `frame_reasm → dc_fifo → axi_frame_saver64` 整条链，逐级计数把丢字定位到某一级，量 CDC 与打包 FIFO 峰值占用 |
| `tb_v5_saver.v` / `tb_v5_bank.v` | 64 个连续 16bit 攒成 64bit burst 并回 idle；`frame_done` 当拍 bank 翻到 BANK1、`completed_base` 锁住刚写完的 BANK0 |
| `tb_v6_pingpong.v` / `tb_v6_tail_bank.v` | 连续推帧时"提交→等 `saver_idle`→翻 bank"是否让每帧整帧落进自己那笔 commit 的 bank；帧尾最后 2 个 lane 在反压放开那拍会不会被提前翻页甩进下一帧（TAIL_GUARD 的 A/B 两条链） |
| `tb_writer_abort.v` | abort 那一拍之后仍在途的 R 读拍不许串进下一帧头几拍、outstanding 不许被旧拍的 `rlast` 打乱 |
| `tb_v5_copy.v` / `tb_v5_gated.v` / `tb_v5_vblast.v` / `tb_v5_lock.v` / `tb_v6_vblank_copy.v` / `tb_v57_first_ar.v` / `tb_v58_full_done.v` | `axi_frame_writer_gated` + `frame_commit_lock` 这一族：只在 `allow` 落 BRAM、`done` 要每个 64bit 字都写完、V-blank 内搬完、首次 AR、abort 翻转位一一对应 |
| `tb_commit_strobe.v` | `frame_ready_pix` 是"一个像素拍的脉冲"还是粘住的电平、第二次提交能否再出沿、watchdog abort 只来一次 |
| `tb_link_monitor.v` | 三份例化（测试时基 / 生产 `CLK_HZ` / 手摆打 `gapclr` 相撞）：丢字与参考计数逐字相等、断帧与坏包、断流后快照继续刷新、间隔 min/last/max/sum 与饱和与 gapclr、快照不撕裂与心跳退化 |
| `tb_v796_src_arb.v` | 互锁、往 PS 让位的静默滞回、`eth_live` 抖动下换手次数地板、时基不可信必须让位、默认参数 20 ms、`sel` 手动锁与保留值 11 按 AUTO 处理、`why_ps` 三位编码 |
| `tb_src_arb_why.v` | #174：`why_ps` 必须是换手判决那一拍的输入快照，互锁冻住主人期间不许被最新输入刷新（W5 钉这条、W7 是它的反配对） |
| `tb_timing.v` | 显示时序一侧的对照台架（被测是 `video_timing` 的小光栅，不是以太网时序）；放这里是为了说明"入包链的 125 MHz 与显示的 50 MHz 各有一把尺子" |

一条判据设计上的口径值得学：`tb_v6_tail_bank` 与 `tb_v6_pingpong` 例化的是 `ddr_bank_commit` 本身而不是 TB 里手抄的 glue（ddr_bank_commit.v:4–5 说明了为什么），"抄的那份永远不会因真代码改错而变红"。另一条是判据不能靠放松通过：`data/metrics.csv` 第 15 行写整屏台架 141 条判据时特意注明"一条判据都不许靠空集通过"。

## 13. 本卷没写进来源的东西（照规矩就不编）

| 项 | 状态 |
|----|------|
| 收侧 ARP/ICMP 的错误源 | **未修**。顶层 `eth_udp_video_top.v:131`/`:144` 把**原始** `gmii_rx_dv/gmii_rxd` 交给 `u_arp`/`u_icmp`，而同一份顶层 `:186–192` 已经产出算过 FCS-32、带 `m_good/m_bad` 的干净流给视频那条路；后果是 ICMP 校验和只采不验、ARP 学来的 `src_mac/src_ip` 无条件发布（出处：`report/known_issues.md` 第 596–602 行，`#205`）。本卷第 6 节讲"能 ping 通"时不掩盖这一条。 |
| `frame_reasm` 的 `PKT_MAX` 参数 | 代码里没有这个名字；实际参数是 `IMG_W / IMG_H / FRAME_BYTES`（frame_reasm.v:8–12）。所以"每包字节上限"取自发侧 `MAX_PAYLOAD`，不取自 RTL。 |
| 协议里的时间戳 / "一包进 PHY → 该帧 commit" 的时延 | 没有测，也不猜：`report/perf_report.md:191` 明写"本版本**仍然没有测**。协议里没有时间戳，PL 里也没有'帧首字节到达'这个打点"。本卷因此不写这一格。 |
| `src/rtl/eth/udp_rx.v` 与厂商 `udp` 包装 | 现在无人例化（`src/rtl` 内 0 处），只有 `tb_eth_video.v` 还在用它做 GMII 直环。收侧现役的是 `udp_rx_parser`。 |
| MDIO / PHY 寄存器读写 | 数据面不碰：`eth_mdio = 1'bz`、`eth_mdc = 1'b0`，PHY 工作模式由板上 strap 定（system_top.v:113–117）；`report/board_pins.md:62` 同一口径。要做寄存器读写得另起一个位时序机。 |
| 重复帧计数的硬件出口 | 指标行有"0 丢帧/坏帧/重复帧"这个说法（`data/metrics.csv` 第 23 行），但 `frame_reasm` 与 `link_monitor` 里没有叫这个名字的端口；`link_monitor` 里能对上的只有 `frames_bad / pkt_err / cdc_ep / drop_words / gap_* / stall_ms / rows_miss_max`。本卷只按代码里存在的端口念。 |

## 14. 自测四题

1. `gmii_rx_dv` 为什么是 `IDDR` 两个 Q 相与，而不是把 `rx_ctl` 直接接过来？答不出就回去读 rgmii_rx.v:48 与 :86–100，并说明 `INIT_Q1/INIT_Q2 = 0` 起什么作用。
2. 第 5.1 节的 221 与件 A 的 184315 是什么关系？把 `221 × 834 + 1` 与 `307200 × 834 + 960` 两式独立算一遍，再说明为什么件 B 的两个数不能套同一组式子。
3. 把 `TAIL_GUARD` 改成 0 会先看到什么现象、在哪个台架上先红、在屏上后红？依据是 ddr_bank_commit.v:6–7 与 tb_v6_tail_bank 的 A/B 结构。
4. 拔网线之后，为什么 `owner_eth` 不能只靠 `eth_live` 交出屏幕？说出 2.5 MHz、1/48、`hb_slow`、`T_OFF_CYC` 四个东西各自站在哪一级（link_monitor.v:6、snap_cross.v:58–65、src_arb.v:11–14、:20）。

---

上一卷：`01-foundations-device-and-architecture.md`（器件与架构分工）。下一卷：`03-geometry-effects-osd-and-hdmi.md`（几何、效果链、OSD 与 HDMI 输出）。本卷涉及的三份深读课在 `study_docs/branch_deep_course/` 的 10/11/12 三章，可作对照阅读，但本卷所有数字都是就地从 `src/`、`sim/`、`build/`、`board/`、`data/` 读来的。

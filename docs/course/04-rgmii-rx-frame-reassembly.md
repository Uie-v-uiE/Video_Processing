# 04 RGMII 收包与帧重组：原理 → 实现 → 取舍

网络片源是本工程的主片源，也是全设计时序最紧的一族。这一篇从协议要求讲到"哪些数不能当纳秒用"。

## 1. 原理：RGMII 只是 GMII 的"4 位双沿"版本，但多出三件事

| 事项 | GMII | RGMII | 对本工程的影响 |
|---|---|---|---|
| 数据宽度 | 8 位单沿 | 4 位双沿（`RXD[3:0]`） | 一个 125 MHz 时钟能带 1 Gb/s |
| 采样沿 | 上升沿 | **上升沿给字节低 4 位、下降沿给高 4 位** | 必须用双沿原语，不能只靠一个时钟沿 |
| 有效标志 | `RX_DV` + `RX_ER` | 只有 `RX_CTL`（双沿复用） | **RGMII 没有错误通道** ⇒ 本模块交不出 `RX_ER` 那种错误标志（`src/rtl/eth/rgmii_rx.v:6``） |
| 时钟关系 | 同源同相 | 规范要求 PHY 在 `RXC` 上**内建约 2 ns 偏移** | 接收侧要么把这 2 ns 补回数据上，要么给数据设窗（第 6 节） |

`RXC` 本身就是 125 MHz，也就是 GMII 侧的接收时钟 ⇒ 这一族的周期只有 8 ns，是全设计里
"算术底最薄"的一层（100 MHz 那层的相对余量是 18.15 %，这里是 9.24 %）。

## 2. 实现：五只 IDDR 与一只 BUFG

```verilog
IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .INIT_Q1(1'b0), .INIT_Q2(1'b0)) ...
     .Q1(gmii_rxdv_t[0]),   // 正沿那半
     .Q2(gmii_rxdv_t[1])    // 负沿那半   （src/rtl/eth/rgmii_rx.v:87-93）
assign gmii_rx_dv = gmii_rxdv_t[0] & gmii_rxdv_t[1];   // :48  两沿都为 1 才算有效
assign gmii_rx_clk = rgmii_rxc_bufg;                  // :47
```

4 位拼成 8 位是**纯位映射**（`Q1 → gmii_rxd[i]`、`Q2 → gmii_rxd[4+i]`，`:133-134`），
IDDR 之后到 fabric 之间没有组合锥。真正有讲究的是时钟树：

- **现在**：5 只 IDDR 与下游 fabric **吃同一只 BUFG**（`:3`、`:50-51`）。
- **以前**：IDDR 吃 BUFIO（SCD 3.171 ns）、fabric 吃 BUFG（DCD 4.854 ns），同频同相却走两条树，
  偏斜是"两棵树之间"的量，无法靠布局消掉。
- **代价被写在文件头**：改时钟源会把采样沿往后推 **1.683 ns**（BUFIO→BUFG 之差），
  所以数据侧必须补同样的量（`:7`；`src/rtl/top/system_top.v:160-172`` 里 `.IDELAY_VALUE(31)` 就是这笔补偿，
  文件头 `:17` 还留了报告读数：DCD = 5.008 ns、SCD = 0，证明"搬进 BUFG 消偏斜"这一步确实发生了）。

**tap 不是纳秒刻度**：同一个 IDELAY 的"每档多少 ps"有三本账互相不一致——
 datasheet 名义 78 ps/tap、实测斜率 ≈63 ps/tap、报告里 `IDELAYE2` 的 2.292 ns / 26 档 ≈ 88 ps/tap
（`:20-22`）。所以任何"把 `IDELAY_VALUE` 从 n 改到 m 就等于移动 x ns"的说法都不能裸用，
必须用实测斜率或直接把窗挂上看 slack。

## 3. 从比特流到一帧：链路顺序与跨域纪律

`src/rtl/eth/eth_udp_video_top.v:4-5` 把链路写死在文件头：

```
gmii_to_rgmii → gmii_rx_mac(自算 FCS) → udp_rx_parser → frame_reasm
             → dc_fifo(BRAM CDC) → axi_frame_saver64 → ddr_bank_commit
控制面：arp / icmp / eth_ctrl      观测面：link_monitor
```

跨域纪律（`:6-7`）：`gmii_rx_clk` 与 `gmii_tx_clk` 是**同一根**（收侧恢复出的 125 MHz），
它们与 `axi_clk`（HP0，100 MHz）之间**只准**过 `dc_fifo` 的格雷码指针与
`ddr_bank_commit` 的 3 级同步器，其余一律禁止组合跨域。
这不是风格问题：本工程有过一次"顺手加一级组合选择"把 CDC 报告多顶出一条 Critical 配对的真实记录。

## 4. 帧重组：什么叫"这一帧可以提交"

`src/rtl/eth/frame_reasm.v:2-3`（文件头原文）：

> commits a frame only if EVERY source row was written this frame; missing rows leave old/zero
> pixels in DDR ⇒ a frozen frame shows black stripes that "move" while zooming.

也就是说提交条件不是"字节数够了"，而是**每一个源行都被写过**。缺行的后果不是花屏而是"黑条"，
并且黑条会在缩放时"动"——这是用户肉眼发现、机器判据后来才补上的那类缺陷。

它的算术也做过一次与本次同样的刀（`:5-7`）：v5.1 只重写字节数算术（接受/拒绝判定不动），
因为 `cover + pkt_pay + 1 >= FRAME_BYTES` 这个**三操作数 32 位加法**曾经占掉该 125 MHz 组
**全部十条最差路径**（当时 WNS +0.499），改成"两条饱和累加 + 与常数比较"。
——这条先例是 `icmp_tx` 校验和那一刀的直接参考：同一族问题（一拍多操作数宽加法）在这一层已被
量过并确认方向。

## 5. 硬件在线健康统计：单位会被硬件偷偷换掉

`src/rtl/eth/link_monitor.v` 数的是丢字数 / 作废帧 / 帧间隔 / 断流 ms，全在 `eth_rxc` 域。
三条纪律写在文件头：

1. 输入都必须是**源模块已打过一拍的寄存器输出** ⇒ 本模块内不许再插组合逻辑进关键路径（`:3-4`）。
2. `lm_bus` 是**快照**，跨域方用 `lm_bus_tog` 的边沿去捕获（机制在 `snap_cross`），
   而不是直接拿总线跨域（`:4-5`）。
3. 注意： **断链时 RTL8211 不停供 RXC，而是把它拉到约 2.5 MHz（≈1/48）**（`:6-8`）。
   ⇒ 这里所有"ms"其实是**周期数**、并饱和在 0xFFFF；下游要做实时判断，必须先与"源时钟健康"相与
   （`system_top` 的 `eth_live`、`snap_cross` 的 `hb_slow`）。

第 3 条值得单独记：**一个计数器的单位并不由名字决定，而由那颗时钟决定**。
板上一断网，"断流毫秒"会以约 48 倍慢速增长——把它当毫秒用会得出完全错误的结论。

## 6. 这一族现在的时序账（读法）

| 事实 | 出处 |
|---|---|
| `eth_rxc` 组 setup 最差 0.739 ns、0 失败端点；两端都在 `icmp_tx` 的校验和累加，**不是 IDDR 之后** | `build/roster_r118_after_eth_rxc_setup.rpt:15-24`、`build/crit_paths.txt:3-10` |
| 该组次族是 `p_eof → rows_hit*/CE`，4 级逻辑但 **route 85.17 %**，中段节点扇出 304 | 同件 `:258-266` |
| 5 个收口引脚**没有任何 `set_input_delay`**（TIMING-18 × 5） | `build/report/methodology.rpt:2245`、`build/check_timing_verbose.rpt:52-61` |
| `eth_rxc` 只声明了 hold 不确定度（`set_clock_uncertainty -hold 0.800`），setup 侧无窗 | `src/constraints/rk_zynq7020.xdc:50` |
| 挂上按规范算出的输入窗，hold 立刻 `−2.885 ns`（2 级逻辑、route 0 %、终点是 `u_iddr_rx_ctl/D`） | `report/log/issues.md` 的 r116 那一节；候选件 `src/constraints/r116_rgmii_input_window.xdc` |

## 7. 这一族为什么只剩 9 % 余量：把"RTL 的锅"分清楚

### 7.1 先解剖最差那条路径

| 项 | 读数 |
|---|---|
| 起点 → 终点 | `u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C` → `…/check_buffer_reg[19]/D` |
| 要求 | 8.000 ns（`eth_rxc` 125 MHz） |
| 数据路径 | **7.066 ns ＝ 逻辑 2.936 ns（41.6 %）＋ 布线 4.130 ns（58.4 %）** |
| 逻辑级数 | 11（`CARRY4`×6、`LUT3`×2、`LUT4`×2、`LUT5`×1） |
| 时钟路径偏斜 / 不确定度 | −0.123 ns / 0.035 ns（setup 侧没有窗，见第 6 节） |
| 该域端点 | 4835 个，失败端点 0（约束全部满足） |

出处 `build/timing_summary.rpt:365-375`（路径）与 `:182`（该域 WNS/端点）。

### 7.2 算术侧写的是什么

`ip_head` 是一块 7×32 位的"存下来的首部"（`src/rtl/eth/icmp_tx.v:66`）。发送前在 `st_check_sum`
里把 IP 首部的 10 个 16 位字**重新加一遍**：两个状态各加 5 项（`:276-291`），目标寄存器只有 20 位
（`:80`）；`st_check_icmp` 再加 4 项（`:296-297`）。综合出来的形状是一条 20 位进位链（6 颗 `CARRY4`）
前面挂一小片 CSA 树 ⇒ 那 2.936 ns 逻辑基本就是这条链本身。

对照 `verilog-ethernet` 的做法（`rtl/udp_checksum_gen.v`）：**每拍最多三个操作数**
（`:469``:474``:479``:491`），跑动的累加器是 32 位（`:162`），折叠单独占一拍（`:509`），
而且每个首部的校验和是**写进一张按指针索引的小存储**（`:369``:375`），不是临发前把整份首部重加。
真正的差别不在"加法宽度"，而在"要不要在最后一拍去读一整排分散在各处的寄存器"——
那正是 58 % 布线占比的来源。

### 7.3 但算术已经不是绑定约束：一条实测反证

把 `st_check_sum` 的加法摊到每拍一项之后重跑一遍完整构建，名册是这样动的
（`build/isolated_1005_icmpck1/timing_summary.rpt` 对照 `build/timing_summary.rpt`）：

| | 现状 | 摊到每拍一项之后 |
|---|---|---|
| `eth_rxc` WNS | 0.739 | **0.691**（更差） |
| 该族最差路径 | `icmp_tx/check_buffer_reg[19]`，逻辑 41.6 % | `frame_reasm/rows_hit_reg[12]/CE`，5 级、**布线 87.3 %** |
| `clk_fpga_0` WNS | 1.850 | 1.727（更差） |
| `sys_clk` WNS | 14.876 | 14.068（更差） |
| `clkout0_1` WNS | 3.630 | 3.799（变好） |

校验和那条锥**确实消失了**，可本族的读数反而更低，另外两个域也丢。这条反证的用处是：
它把"削算术"这条路封死在证据上——瓶颈已经换成一根纯布线的广播（0.904 ns 逻辑 + 6.204 ns 布线），
再优化加法只会把名字换一换。所以这一族的债要按"这个域装得太多"来还。

### 7.4 结构性对照：他的 RXC 域里没有协议栈

`rtl/eth_mac_1g_rgmii_fifo.v` 有三个时钟口：`gtx_clk`（`:67`）、`logic_clk`（`:70`）、
`rgmii_rx_clk`（`:96`）。收侧数据寄存器在 `rx_clk` 域（`:182`），包流却在 `logic_clk` 域被消费
（`:190``:209`），中间隔两只 `axis_async_fifo_adapter`（`:254``:305`）。
⇒ **MAC 之上没有任何逻辑去吃 8 ns 的预算**，PHY 恢复出来的 RXC 域里只剩 PHY 接口本身。

本工程的 `gmii_tx_clk` 与 `gmii_rx_clk` 是同一根（`src/rtl/eth/eth_udp_video_top.v:5`），
于是收侧链路、发侧协议栈（arp / icmp / udp）、512×100 位的 LUTRAM 打包器
（`src/rtl/eth/axi_frame_saver64.v:48-51`，`FW=9`）和 `link_monitor` 全压在同一颗 8 ns 时钟上
⇒ 4835 端点、时钟网 2546 负载（`build/timing_summary.rpt:182`），
而 `u_saver/wptr_reg[5]` 这一根写指针位单独吃 1165 个负载
（`build/roster_r118_after_fanout.rpt` 汇总表第 5 行）。
一个域里塞这么多，代价就是这个域里**每一条**路径都要先付 4 ns 量级的布线。

### 7.5 两条可以从那个工程 import 的改法，按代价排序

1. **校验和"边装配边累加"**（改动只在 `icmp_tx`）：`st_idle` 写 `ip_head[k]` 的那一拍就把对应的
   16 位字并进一个 20 位累加器，`st_check_sum` 只剩折叠。逐位等价的理由要写清楚：10 个 16 位项之和
   ≤ 10×65535 = 655350 = `0x9FFF6`，装得进 20 位、不进位丢失，折叠次序一字不改，所以最终写进
   `ip_head[2][15:0]` 的那 16 位与现在完全相同。收益上限是拿掉 2.936 ns 里的逻辑那半，
   **4.130 ns 布线一分不动**；再叠加 §7.3 已经量到的"削算术会把瓶颈换成布线"，
   所以它必须先有逐字节钉住整帧输出流的台架（`sim/tb_icmp_tx_cksum.v` 就是为此而留的），
   然后走一整轮构建 + 逐时钟名册差分（别的域不许丢）才谈得上采纳。
2. **在 MAC 与协议栈之间插异步 FIFO**（`eth_mac_1g_rgmii_fifo` 的形状）：把
   arp / icmp / udp / frame_reasm / saver 移出 `eth_rxc`；或者只挪发侧——RGMII 的 `TXC` 本来
   就由 MAC 侧产生（本工程 `rgmii_tx_clk` 是输出端口），所以发侧可以用 PL 的 MMCM 生成一颗
   独立 125 MHz，与收侧恢复钟解耦。这才是让布线占比真正下降的杠杆。
   代价是整条收/发链的握手要重画、`dc_fifo` 与 `ddr_bank_commit` 之外会多出新跨域、
   这些跨域要重新过 CDC 判据，台架与上板复验全跑一遍。

顺序上为什么不做第 2 条再说：主片源就是网络，`ping` 应答在验收清单上。
在没有一整轮验证预算的时候做域划分，等于拿"已经满足的 0.739"去换"功能尚未证明"。
所以这一族的账现在这样记：**算术侧已被两次实测关闭（削它本族更差），剩下的债是域划分，
它是一整轮的活，判据和台架先备好。**

## 8. 怎么验

```bash
# 单元级
VP_VIVADO_BIN=<Vivado>/bin bash build/sim/run_one.sh tb_icmp_rx_len     # 长度/索引/reply_checksum
VP_VIVADO_BIN=<Vivado>/bin bash build/sim/run_one.sh tb_link_monitor    # 丢字/作废帧/帧间隔
VP_VIVADO_BIN=<Vivado>/bin bash build/sim/run_one.sh tb_writer_abort    # 提交脉冲与 abort 在途拍
# 顶层（整帧同帧 A/B、缝、C5c 帧头那一族都在这里）
bash build/tb98_report.sh
# 板上：读回口
#   [STAT] 行里的 drop_words / frames_bad / stall_ms；OSD 同格显示同一组计数
```

`build/sim/run_one.sh` 的约定要记住：**退出码 3 = 台架自己判红**（不是编译失败），
判定行按"最后一个非空字段"读；`RESULT … PASS` 顶格才算通过。

小结：RGMII 这一段的难度不在"能不能收到数据"，而在三件事同时成立：双沿拼字不错位、
2 ns 偏移的账要用实测斜率而不是名义值、跨域只走那两条被允许的路。
下一步：`05-framebuffer-and-axi.md`。

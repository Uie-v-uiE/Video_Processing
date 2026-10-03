# r115 计划：把 RGMII 捕获沿挪到该在的地方（#194 的设计、尺子与否决条件）

写这份文件的动机不是"再想一个招"，是今天一整天的测量把方向逼出来了。所有数字都有件，没件的都标 **未定**。

## 一、今天量到的事实（先只看这些）

| # | 事实 | 件 |
|---|---|---|
| F1 | 出货流程里 **没有任何** `set_input_delay`/`set_output_delay` 覆盖 RGMII 收口 5 个输入（`eth_rx_ctl`、`eth_rxd[3:0]`）；`check_timing` 把它们点名成 HIGH 缺口 | `build/check_timing_verbose.rpt`、`report/TIMING_GLOBAL.md` §4b |
| F2 | 一旦把窗建起来（模型 a：`-max 0.500 / -min -0.500`，配 `-clock_fall` 那一对），`eth_rxc` 的 **min 检查立刻违例 −2.885 ns**，5 个端点全在 `u_iddr_rx_ctl/D` | `build/evidence/r114_io_roll_console5.txt`、ISSUES #275 |
| F3 | 数据侧的路是**死的**：同一份窗下 IDELAY 从 0 扫到 31 档 = −4.522 / −3.703 / −2.570（斜率实测 ≈63 ps/tap，要补 2.7 ns 需要 43 档而最大只有 31） | `build/evidence/r114_sweep*`、ISSUES #280/#282 |
| F4 | 换窗模型（b：数据落在沿后 1.5–2.5 ns，等于"PHY RX 内部还有延迟"）整条曲线**平移了恰好 2.0 ns**（tap0：−4.522 → −2.522） | ISSUES #282 的两模型表 |
| F5 | 那份 hold 报告的算术把差额放在**捕获钟的网络延迟**上：`DCD = 5.008 ns`，arrival 7.113 / required ≈9.84 | ISSUES #285（原始报告 `build/evidence/r114_sweepB/rt_tap0_*`） |
| F6 | r92/#57 当年为了消掉 BUFIO(SCD 3.171) 与 BUFG(DCD 4.854) 之间 1.616 ns 的树偏斜，把 5 个 IDDR 搬进 BUFG，并把 `IDELAY_VALUE` 从 15 补到 26（+11 档 ≈ +1.683 ns） | `src/rtl/eth/rgmii_rx.v` 头注、r92 记录 |
| F7 | #288 刚量过：动物理侧（复制驱动）能把目标族 setup 抬 +0.456，但同域 hold 从 0.050 掉到 0.035 ⇒ 被名册差分否决。**这个域的 hold 余量不能再被动用** | `build/evidence/r114_mf/verdict.txt` |

**F4 是方向判据**：把外部数据整体推晚 2.0 ns，min 检查就恰好变好 2.0 ns ⇒ 这条违例读数是
"数据相对捕获沿太早"的形状，**要补的是把捕获沿挪早**（或者把数据挪晚——F3 说数据侧已经没钱了）。
所以 #194 的"把 IDDR 的捕获钟提前"方向成立，而且成立的方式与 F5 一致：DCD 越大，required 越晚，slack 越负。

**未定（写清楚，不许混进判据）**：#285 那份报告里 `Requirement: 0.000 (fall@4.000 − fall@4.000)` 与
rising-edge IDDR 的对应关系我没读实（arrival/required 还差 0.155 ns 没逐项拆开）。
这不影响方向（F4 是实验平移，不依赖这套解释），但影响**数值目标**，所以 r115 第一步要把这个拆开。

## 二、三个候选，按"预测能不能关住"排序（预测都标预测）

| 候选 | 动什么 | 预测效果（按 F5/F6 的量算，**不是实测**） | 代价面 | 前置债 |
|---|---|---|---|---|
| **C1** | IDDR 回 **BUFIO**（DCD 5.008 → ~3.17 量级），fabric 侧配同区 **BUFR** | 挪早 ≈1.8 ns ⇒ **预测仍差 ~0.9 ns**（F3 的 2.7 缺口买不满） | BUFR 只驱动本时钟区：GMII 下游逻辑今天跨区（这正是 r92 放弃它的原因）；`IDELAY_VALUE` 的 +11 补偿要退回去（F6） | 时钟区归属要先量（`report_clock_networks`/`report_utilization` 的 BUFR 行） |
| **C2** | `eth_rxc` 走 IBUF → **MMCM 负相移** → 同一只 BUFG 同时喂 IDDR 与 GMII fabric | 相移范围是整周期（125 MHz ⇒ 0–8 ns），**关得住 2.7 ns**；且保住 r92 的"IDDR 与 fabric 同树同相"这个既得成果 | 新增一只 MMCM 的资源与它的 DCD/jitter；fabric 侧 125 MHz 的**来源换了** ⇒ 与 `clk_fpga_0`/`clkout0_1` 的时钟组关系、`set_clock_uncertainty` 全部要重算 | 现网表里 `eth_rxc` 是 `create_clock` 直接钉在 IBUF 输出上的（要量出来再改，别凭记忆写） |
| **C3** | 什么都不动，把 F1 的窗**继续不建**（现状） | hold 报 0.050 这种"看着像设计值"的数（F2 之后知道它是没建模的产物） | 交付文档上这一路永远欠一条"为什么没有约束"的书面理由（UG949 的 I/O 规则要的就是这句） | 无 |

排法说明：**C1 的预测是负的**，所以它不该先做——先做那个能关住的（C2），除非 C2 的时钟组重算把别的域挤坏。
这条排序本身就是"别一根筋"：C2 的风险全在代价面（跨域关系），所以判据必须先有（下面第三节）。

## 三、这一刀的尺子（先配能红的，再落刀；红绿凭据都进 `build/evidence/`）

1. **改前必须红**（已有，不用再造）：同一份窗 XDC 下 `eth_rxc` min = −2.885 / tap31 仍 −2.570
   （F2/F3 的件）。判据 = `fail_hold(eth_rxc)=0` 且 `hold_worst ≥ 0`，**窗必须一起进构建**，
   否则这条判据是在判一个没约束的设计（#285 的教训）。
2. **名册八对逐格差分**（`build/roster_from_summary.sh` + `build/timing_roster_diff.sh --self` 6/6）：
   其余三域不许从 MET 掉进违例、相对余量掉过 25 % 判红。#288 就是被这条判死的，同一把尺子。
3. **机制侧读数**（不能只看 slack）：`report_clock_networks` / `report_clock_utilization` / `report_utilization`
   里 MMCM/BUFG/BUFIO/BUFR 的**计数**变化——C2 期望 MMCM 计数 +1、`eth_rxc` 的 DCD 读数变化要有出处。
   计数没动 ⇒ `MECHANISM_INERT`（"这一刀没打到东西"），不许写成"时序收益不成立"。
4. **板侧唯一真判据**：1000M 实流量的 `bad` / `drop_words` 必须仍为 0，且 `--geom --battery` 全过。
   报告只能证明内部路径变好；**采样点落没落在眼里只有实流量说了算**（r92/#57 当时就把这句话写进了注释，
   今天它仍然是这一类改动唯一的收口）。
5. **PHY 侧的口径**：RXDLY 寄存器今天读不到（`main.c` 没有 MDIO 读命令 + 本机无 arm-none-eabi ⇒ 不能重建 ELF，
   #131/#170）。所以 F4 的"模型 b"只是**可判的假设**，不许写成"PHY 延迟已确认开着"。
   这一条决定了窗的**数值**最终由谁签字：要么补上 MDIO 读口（单独一笔），要么由第 4 条的实流量代判。

## 四、还欠着的两笔（r115 之前或同轮带走）

* **`set_clock_uncertainty` 的 uniform 带**：今天只有 `eth_rxc` 带 `-hold 0.800`，其余三域裸数 ⇒ 四域 WHS 不可比（#265）。
  尺子 `build/uncertainty_uniform_ab.sh` 已落地（六条判据、`--self` 7/7），**真件还没跑**。
  C2 会改时钟来源 ⇒ 这笔必须在 C2 之前或同一轮收掉，否则名册差分的 hold 那一列是拿不同口径在比。
* **`set_bus_skew` / 异步组排除范围**（#191）：`set_max_delay -datapath_only` 叠在
  `set_clock_groups -asynchronous` 上不产生新异常行（#276 实测 13 行不变），所以它不是"补了更严"，
  而是"要不要把某些跨域路从排除里放出来"的范围决定 ⇒ 需要单独一轮，不与 C2 混。

## 五、纪律

* 一次构建带多刀，但每刀各自先红后绿；`src/rtl` 与 `src/constraints` 在构建/台架在飞时不动。
* C2 是**结构改动**（多一只 MMCM、改时钟归属）⇒ 必须先走正式一轮，不许拿快车道当结论
  （快车道从 `opt.dcp` 起跑，改不了综合出来的钟网）。
* 采纳笔含 bit/xsa；刷板后 `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --geom --battery --round=r115`，
  眼睛判据仍归用户。
* 判据不许反着写：不能因为 slack 变好就采纳（#288 正是"变好但被代价否决"），也不能因为 WNS 的绝对差就判收益或损失。

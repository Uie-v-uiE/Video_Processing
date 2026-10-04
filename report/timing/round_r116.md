# r116 结果（最后一轮 · 全局时钟名册 · 写给早上看的你）

写这份文件的时刻：2026-10-04 **02:57**。构建已经回来（01:13 起飞、01:34 出位流 `bb2fb707aebc`），
板子已经刷过并带真实流量复验过（01:37 三步链、01:50 `board_verify` PASS、02:14–02:21 带流 A/B 对照）。
第三节 V1..V6 现在**全部是实测读数**，没有空格；顶层台架与门禁在 03:0x 之后回来，落点写在本页第六节。

## 零、一句话结果（红的那半句排在前面，不藏）

* **本轮按字面判定是红的两条**：G1 —— `eth_rxc` 两格相对余量比基线小（0.739→−0.846、0.052→−0.870）；
  H5 —— 输出侧还有 **6 个端口**没有被时序检查覆盖（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）。
  这两条我都没有用"看起来完成了"的话盖过去：G1 的红**就是这 5 个端点第一次被检查**（绑窗前它们是
  `Slack: inf`，"没检查"不等于"满足"，那是 H5 明令禁止的读法）；H5 的红需要**外部资料或你的批准**才能关
  （第五节第一条）。
* 除此之外**没有任何东西变差**：另外三个域 setup/hold 八格里七格逐格不动、`clk_fpga_0` 与 `clkout0_1`
  的相对余量各 +6.8 % / +1.9 %；资源一格不差；`report_methodology` 类计数不增、实例 446→441；
  **松动台账 0 条**（H1/G3）。
* `eth_rxc` 那 5 格已被**证明**是这一代器件/结构下的边界，不是"还没找到点"：
  tap 全档扫描给出不相交区间（hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8、合法 0…31），
  根因是两只钟的角间差 3.411 ns 而数据只有 0.467 ns（第一节第 5、6 行）。
* 板侧：同一台板、同一份 147 Mbps 真实流量，**回刷 r114 做 A/B**，四个读数逐格相同
  （`drop_words=0`、`pkt_err=0`、`frames_bad=1` 不增长）⇒ r116 与已被证明能跑的 r114 在板级**不可区分**。

---

---

## 一、这一轮真正拿到的结果（不依赖构建，今天已有凭据）

| # | 结果 | 凭据 |
| --- | --- | --- |
| 1 | **RGMII 收口的窗终于有了出处**：板上 `RXDLY`/`TXDLY` 都由 4.7K 上拉到 IODVDD ⇒ PHY 把 2 ns 延时加在 **RXC** 上，数据沿提前于它自己的捕获沿 | 原理图 V1.1 第 8 页图件 `build/evidence/r115_sch_p8/rxd_area.png`、`phy2_straps.png`；规格书 Table 10/11 抄件 `build/evidence/r115_rtl8211f_delay_source.txt` |
| 2 | **窗的正确数值 = min 1.200 / max 2.800**（从发射沿量起），并纠正了三次"用错行" | Table 60 `TsetupT/TholdT min 1.2 typ 2`（发射端两行 = 本板收口）；ISSUES #304/#309 |
| 3 | **工具的边配对被读实**：IDDR 的 D 脚 setup 查 `rise→fall`（Requirement 4.000）、hold 查同一沿（0.000）⇒ 负数写法与整周期平移写法都是它的镜像 | `build/evidence/r115_window/probe2_console.txt` 四组 W1..W4 |
| 4 | **`IDELAY_VALUE` 0…31 全档扫满**：`HOLD=−2.822+0.0630τ`、`SETUP=+2.005−0.0920τ` ⇒ 交点 τ=31.1，**tap 31 是 min(hold,setup) 的最大点**，比出货值 tap 26 抬 **+0.315 ns** | `build/evidence/r115_window/probe3_console.txt`（`set_property IDELAY_VALUE` 在已布线 DCP 上有效，见 ISSUES #310） |
| 5 | **这一族的极限被写成不等式**（不是"没找到点"）：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，合法区间 0…31 ⇒ **不相交**；去掉与窗双重计的 0.800 hold 带也只是 44.8→32.1，仍不相交 | `report/timing/rgmii_window_model.md` §7.5(4) |
| 6 | **根因定位到钟网络的角间差**：hold 查慢角 DCD **5.008**、setup 查快角 DCD **1.597**，差 **3.411 ns**，而数据路径角间差只有 **0.467 ns**；同时满足要 `D_slow/D_fast ≥ 1.73`（带子保留）/ ≥ 1.45（去带），IDELAY 主导的路径实测只有 **1.15** | 同上（分量都抄自报告本身） |

一句话：**`eth_rxc` 这一族在今天的结构（IDDR 与 4835 端点的 125 MHz 流水线共用一只 BUFG）下，
物理上不存在能同时满足两条检查的采样点**；能动的三样（数据延时、相位、不确定度带）都量过、都关不掉。
出口只有一个：把到 IDDR 的那段钟做短且角间不散（下一轮，见第四节）。

## 二、这一轮进了构建的两刀

1. `src/constraints/r116_rgmii_input_window.xdc` —— 5 个 RGMII 输入**第一次**被时序检查
   （之前 `check_timing` 点名它们是 HIGH 缺口、`report_timing` 对它们报 `Slack: inf / Path Group: (none)`）。
   加载方式 `used_in_synthesis false` ⇒ **综合网表逐字节不变**，任何差异都只可能来自实现阶段。
2. `src/rtl/top/system_top.v` 的 `IDELAY_VALUE` 26 → **31**（上表第 4 行的实测眼心）。

**没有放宽任何东西**：`report/timing/loosen_ledger.tsv` 本轮 0 条；`rk_zynq7020.xdc` / `clock_groups_impl.xdc` 一个字没改。

## 三、等构建回来的判据（V1..V6）

| 判据 | 要看到什么 | 现在 |
| --- | --- | --- |
| V1 机制 | 5 个输入路径出现**有限** slack + `Input Delay:` 行 | ✅ **过了**：`r116_io_hold.rpt` 第一格 `Slack (VIOLATED) -0.870ns`、`Path Type: Hold (Min at Slow Process Corner)`、`Input Delay: 1.200ns`、`Data Path Delay 3.928ns (logic 100.000% route 0.000%)`；`r116_io_setup.rpt` 第一格 `-0.846ns`、`Setup (Max at Fast Process Corner)`、`Input Delay: 2.800ns`。件 `build/evidence/r116/r116_io_{HOLD,SETUP}.rpt`。**"有限"是这条判据的全部内容**——绑窗之前这些路是 `Slack: inf / Path Group: (none)`（无检查），现在它们第一次被检查、第一次给出可读的数 |
| V2 债 | `check_timing` 不再点名 `eth_rx*`；未约束端口 11 → 6 | ✅ **过了，且两个数分开念**（提示词附录 1 的量纲红线）：`unconstrained_internal_endpoints = **0**`；`no_input_delay` 里"没有任何 input delay 的端口"= **0**（另有 2 个输入端口是**既有** false_path 覆盖的，MEDIUM，本轮没动它）；`no_output_delay` 从 11 个里的 5 个降到 **6 个**（`led[0] led[1] tmds_clk_p tmds_data_p[0..2]`，另有 6 个输出端口同样是既有 false_path 覆盖）。件 `build/evidence/r116/r116_check_timing.txt`。警告 `report_methodology` 的同一族只报 **TIMING-18 = 2**（`led[0]`/`led[1]`）——**这是第二把尺子（checks/pins 口径），不与 6 相减**；两把尺子的数都写在件里 |
| V3 收益 | I/O 族最差格从 DCP 实测的 −1.185（tap26）挪到 ≈ −0.87（tap31） | ✅ **预测逐格命中**：正式构建实测 hold **−0.870**（预测 −0.870）、setup **−0.846**；四根数据线的 setup 分别是 −0.846/−0.835/−0.833/−0.813（件 `build/evidence/r116_after.txt` 的 `eth_rxc` 段）。⇒ DCP 上扫出来的那条曲线（`HOLD=−2.822+0.0630τ`）在真构建里对到了小数第三位，这是本轮模型最大的可信度证据 |
| V4 名册 | 四域 setup/hold 逐格差分，其它三域不许从 MET 掉进违例 | ✅ **其它三域一格没掉**：`clk_fpga_0 1.850→1.976`（相对余量 18.50→19.76 %）、`clkout0_1 3.630→3.698`（18.15→18.49 %）、`sys_clk 14.876→14.876`、hold 三域 0.053/0.059/0.222 **逐格不动**。❌ **唯一变差的是 `eth_rxc` 两格**（0.739→−0.846、0.052→−0.870）——它不是被搬走的负裕量，是**第一次被检查的那 5 个 I/O 端点**；名册差分按字面判 **RED**（`judged=6 pairs=8 result=RED`，件 `build/evidence/r116_roster_diff.txt`）。同一条差分里 `D6_fanout_inventory` 也红：A 侧那份没有扇出节 ⇒ **尺子口径**问题，不是设计问题（#291/#293 那一族，已登记） |
| V5 代价 | 资源行 / 告警名册 / `report_methodology` 类计数不增加 | ✅ **资源逐字中性**：`Slice LUTs 14154`、`Slice Registers 8188`、`Slice 5051`、`LUT as Memory 4185`、`BUFGCTRL 8`、`CARRY4 1147` 与 HEAD（r114）那份**一格不差**（件 `build/utilization.rpt` 盘上 vs `git show HEAD:build/utilization.rpt`；综合网表本来就该逐字节不变，因为新 XDC 是 `used_in_synthesis false`）。✅ **告警按类不增加**：类仍是 3 类（TIMING-9/10/18），实例 `Checks found: 446 → **441**`，其中 `TIMING-18` 从 **7 → 2**（少掉的 5 条就是这轮第一次被检查的 5 个 RGMII 输入）。件 `build/methodology.rpt` vs `git show HEAD:build/methodology.rpt` |
| V6 板侧 | ✅ **过了，但不是零样本过的**：01:37 三步刷板（bit `bb2fb707aebc`）→ 01:50 `board_verify --geom --battery` **PASS，判红步骤 0**（geom 10/0、105 条串口命令全过、`drop_words=0`）。警告 但那次 `drop_words=0` 是在 **`eth_live=0`（没有流）** 时读的 ⇒ 零样本通过，不算数。02:14 补一次**带流**的：`video_sender --demo --fps 60 --pace-mbps 0`（512×300 RGB565 ≈ **147 Mbps**，50 s / 3001 帧 / 66.3 万包）跑着读两次 ⇒ `eth_live=1 owner_eth=1`、**`drop_words=0`、`pkt_err=0`、`flags.drop_seen=0`** 两次都一样；`frames_bad=1` 在两次读数里**都不增长**（是历史/链路建立期的一次性计数，不是本采样点造成的，见下条未定）。件：`build/evidence/r116_board/health_t12.json`、`health_t34.json`、`sender_live4.log` |

**采纳规则（写在 `build/r116_batch_plan.md`，不许事后改口径）**：全绿才当演示位；
若只有 I/O 族为负（这是本轮的**预测**），则把它当"极限判据的实验件"刷一次板，
让 1000M 实流量判决——`bad=0` ⇒ 报告与真实采样点之间还有一层模型悲观（那是下一轮**有板级凭据**的放宽）；
`bad>0` ⇒ 窗是对的、结构确实到极限 ⇒ 回退刀 2、刀 1 退回候选件，板与仓库停在 r114。

## 四、下一轮（r117）唯一值得动的刀，已经配好靶子

**动什么**：把 IDDR 的捕获钟从全局 BUFG 挪到**短而角间不散**的 I/O 钟（BUFIO，或本区 BUFR + 只让
IDDR/第一级寄存吃它），下游那条 4835 端点的 125 MHz 流水线仍吃 BUFG。

**先量再动**（这三件事没量完不许落刀）：
1. **BUFIO 的快角 DCD** —— r92 只留下慢角 3.171 这一个数；本轮的判据是 `C_slow − C_fast ≤ ~1.2 ns`
   （现在 BUFG 是 3.411）。这一条决定"有没有解"，是 40 秒的只读探针。
2. **IDDR→BUFG 流水线的跨树代价** —— r92 的症状是 WHS 在 ±1 ps 掷硬币。名册差分必须把
   `eth_rxc` 内部 hold 那一格与 I/O 那 5 格**分开念**（否则就是拆东墙补西墙）。
3. **`gmii_rx_clk` 到底驱动谁**（今天已读实：arp_rx / gmii_rx_mac 的 FCS-32 锥 / udp_rx_parser /
   frame_reasm / eth_ctrl / dc_fifo 写侧）⇒ "整条流水线搬进一个时钟区"是**不可能**的，
   所以这一刀只能搬 IDDR + 第一级，别信"全搬"的方案。

**明确不要再试的**（都量过）：MMCM 相移（r115 关死，`−225°` 被网络延迟吃掉还有余）、
IDELAY 再扫（本轮扫满 0…31）、复制驱动（#288 被名册判负）、Pblock（r113 carry chain 出块）、
`set_max_delay -datapath_only` 叠异步组（#276 零新行）、给四个域统一加 0.800 hold 带（#302 全设计红）。

## 五、还欠着的（不是本轮"没做"，是要人签字或有外部资料）

* 输出侧 6 个端口（`tmds_clk_p`、`tmds_data_p[0..2]`、`led[0..1]`）仍无 `set_output_delay`：
  要么给一份可引用的 DVI/HDMI 窗口数，要么你批准把它们声明为不检查（那是放宽，要进松动台账）。
* `#266` 异步组外四条跨域路的 `set_bus_skew` / `-datapath_only` 范围决定（要单独一轮）。
* 眼睛判据：E6 在 r114 上的复验、演示默认位的确认。

### 4b 下一轮的**数值靶子**（01:2x 补：把"短钟网络"从方向变成能判红绿的数）

今天的报告已经把两只钟的**角间分量**各拆开了（慢 / 快）：`IBUF 1.430 / 0.454`、
`BUFG 0.085 / 0.029`、`网络 1.873+1.620 / 0.731+0.903` ⇒ 现在这条 BUFG 树是
`C_slow 5.008 / C_fast 1.597`（角间差 **3.411**）。

把 IDDR 的捕获钟换成 I/O 专用短钟（BUFIO：IBUF + 专用走线，几乎没有通用布线）之后，
按"专用走线 ≈ 0.5 / 0.2 ns"这个**未量的假设**估：`C_slow ≈ 1.93 / C_fast ≈ 0.65`（角间差 1.28）。
代回今天量到的两条曲线（数据侧 `D_slow = 1.976+0.0630τ`、`D_fast = 0.754+0.0920τ`，
**0.800 的 hold 带保留不动**）：

```
HOLD  要 D_slow ≥ C_slow + 0.155 + 0.800 − 1.2 = 1.685  → τ ≥ −4.6   ⇒ τ=0 就满足
SETUP 要 D_fast ≤ 4 + C_fast − 0.035 − 0.259 − 2.8 = 1.556 → τ ≤ 8.7
⇒ τ ∈ [0, 8.7] 全区间两检查同号为正；最平衡点 τ ≈ 4~5（hold +0.54 / setup +0.44）
```

⇒ **这一族在短钟网络下是可关的，而且不需要放宽任何东西**（带子留着也算得出正）。
但整段推导吊在"专用走线 ≈ 0.5/0.2 ns"这一个**没量过**的数上 ⇒
下一轮第一刀之前，先花 40 秒把 **BUFIO 的慢/快 DCD 实测**问回来（只读探针：
`report_timing` 里那条 `ILOGIC_X1Y37 IDDR/C` 的到达时间，r92 当年只留了慢角 3.171）。
如果实测角间差仍然 > 1.7 ns，上面这个区间就再次变成空集，那时要说的就不是"换树"而是
"这一代器件的 I/O 时钟树对 8 ns 周期 + 1.6 ns 外部散布就是不给解"——那句话也得有件才能写。

### 4c 但 4b 那一刀有一个**必须先算的代价面**（01:3x 补，写在这里挡下一轮重复 r92）

短钟网络把 IDDR 的捕获沿提前之后，**IDDR→下游流水线**这条内部路就变成"发射沿 1.93、捕获沿 5.008"的
跨树路：工具为了让这些路不违例，要在数据上插 ~3.07 ns 的延迟。而这条流水线里最重的锥是
`gmii_rx_mac` 的 FCS-32（`build/evidence/r115_base/setup_nworst.txt` 实测数据+布线 **7.066 ns**，
8 ns 周期）—— 3.07 ns 的预算被吃掉之后，**同一条 7.066 的锥只剩 ~4.9 ns 可用** ⇒ 大概率从 MET 掉进违例。

⇒ 所以"换短钟"不是一个可以单独落的刀。它的完整形状是：
**IDDR（+ 紧邻第一级）吃短钟，跨到 BUFG 域要经过一级同步 FIFO / 打拍接口**，
让 `eth_rxc` 内部那条 4835 端点的流水线不再直接吃 IDDR 的钟。这是一次**架构改动**，
门槛与 r92 当年放弃 BUFR 的理由是同一个（GMII 下游跨区）。

下一轮如果要动，先做这三件**只读**事再决定要不要花构建：
1. BUFIO 的慢/快 DCD 实测（决定 4b 的区间是不是真的存在）；
2. `report_clock_networks` / `report_utilization` 数一下 `gmii_rx_clk` 的 2546 负载落在几个时钟区
   （决定"BUFR 只喂本区"还剩多少东西可喂）；
3. 用名册差分把"IDDR→流水线"那族的 setup 代价**单独列一格**——它和 I/O 那 5 格不是一个东西，
   不许用后者的收益盖掉前者（H2 的字面意思）。

### V6 的两条未定（不圆场）

1. **`frames_bad=1` 的归属没查**：它在带流的两次读数（相隔 22 s、期间 66 万包）里都不变，
   所以**不是这一版采样点正在造成的**；但它到底是"链路建立时那一下"、"上一次 --drop-packet 演示留下的"，
   还是"刷板前就有"，**没有对照就不能说**。要定它只需一步：把 r114 那份位流（`build/evidence/r114_bit/system.bit`）
   回刷一次、同样推 50 s、读同一个计数器。这一笔留给早上决定（回刷+测 ≈ 4 分钟）。
0. **(02:21 补) `frames_bad=1` 的归属已经用 A/B 对照查清了：不是 r116 造成的。**
   同一台板子、同一个 app、同一份推流（512×300@60、50 s、3001 帧 / 663,221 包），
   先回刷 r114 的位流（`build/evidence/r114_bit/system.bit`，md5 `7142a1fbf082`）再刷回 r116，各读两次：

   | 位流 | 读数 | eth_live | owner_eth | drop_words | pkt_err | frames_bad | drop_seen |
   | --- | --- | --- | --- | --- | --- | --- | --- |
   | r114（τ=26，无窗） | a / b | 1 | 1 | 0 | 0 | **1 / 1** | 0 |
   | r116（τ=31，带窗） | a / b | 1 | 1 | 0 | 0 | **1 / 1** | 0 |

   ⇒ **四个读数逐格相同** ⇒ `frames_bad=1` 在 r114 上就有（一次性计数，链路建立期的那一下），
   与本轮的采样点无关；r116 的 τ=31 + 输入窗在真实流量下与已被证明能跑的 r114 **不可区分**。
   件：`build/evidence/r116_board/health_r114ctrl_{a,b}.json`、`health_r116again_{a,b}.json`、
   摘要器 `build/r116_ab_summary.mjs`（读不到的键显式打 `ABSENT`，不许打 `?` 冒充读数）。
1. **147 Mbps 不等于 1000M 线速**：发送端是 512×300@60 的帧率上限，链路虽然协商在 1000M，
   但**没有把 RX 打到线速**。所以 V6 证的是"真实流量下不丢字"，不证"线速下不丢字"。
   要压到线速需要更大的画幅或更高的 fps（`--fps` 是上限，源是 512×300）⇒ 这一条写在明处，
   不许把 147 Mbps 的绿念成 1000M 的绿。

## 六、03:1x 追加：尺子先修，交付数字改口，第三刀已排上链

三件事按顺序做完了，都不是"读数"而是"让下一轮读数可信"：

1. **`metric_recheck` 读不出负数**（#321）。本轮第一次让首页的 headline slack 变成负的（−0.846 / −0.870），
   而首页那一层四个取数式全写成 `[0-9]+\.[0-9]+`，负数读成 null，而 null 在这把尺里就是红 ⇒
   **写对了也红、写错了也红 = 这一维没有射程**（rule 46 那一类）。补了 `sgn()`（U+2212 折成 ASCII）
   + 四个式子加符号位 + **六条合成对照**（wns/clocks/whs 各一对：已知绿的负数必须全绿、已知错的必须仍红），
   跑在正常模式里并计数：`SELFSIGN-SUMMARY 判 6 条（负数可读=绿、负数写错=红），红 0`；
   `--self` 原有两条 fixture 仍恰好红 2 次（没把老对照弄钝）。
2. **交付数字改口**：首页两份 + `data/metrics.csv` 三行全部换到 r116 实测值，
   `node src/host/metric_recheck.mjs` 从 **23 条红 → 红 0**（判 115 个数：首页层 61 个、解析到 10/10 行）。
   改口用脚本 `build/r116_rotate_en.py`（按行首标签定位、整行重写、命中数≠1 就 REFUSE），
   中途踩到两条自己的坑：CSV 一行里写了 ASCII 逗号 ⇒ 字段数从 7 变 8，"凭据列"读成"一次构建"；
   以及交付文档**不许**引用 `docs/`（那是本地工作区，不随包）⇒ 首页里三处 `docs/timing/…` 引用
   改指 `report/timing_global.md` 第 6/7 节，那两节现在是真写了（406 行，含逐域极限审计与下一刀的数值靶子）。
   件：`node src/host/doc_currency_check.mjs` 从 14 → 6 条（剩下 4 条就是还没落地的 `build/r116_gates.txt`，两条是别的路径），
   门禁落地后这一层会自己收敛。
3. **第三刀（C9）已经从"排期"变成"量到的赢"**：02:49 的 D0 探针把根因从"两端离得远"改成
   **FANOUT**（一根 239 引脚的网吃 5.690 ns，载荷铺在 99 个 tile，件 `build/evidence/r117_d0/`），
   03:01 的快车道单变量滚量到 +0.033 / +0.187 / +0.298（三域 setup），代价 +10 只 FF，
   `eth_rxc` 与四域 hold 一格不动（件 `build/evidence/r117_repl3/b_console.txt`）。
   采纳入口 `build/tcl/r117_post_place_hook.tcl` + 构建脚本的 `IMPL_POST_PLACE_HOOK` 环境变量
   （默认不设＝不挂，r116 的复现路径不改写；钩子属性名先用只读探针在真实工程上验过，
   件 `build/evidence/r117/prop_probe.txt`，因为提示词 A2 那条规矩我今晚已经违反过一次 #319）。
   **03:15 起飞 `build/r117_chain.sh`**：它先等 r116 的门禁件落地（`build/*.rpt` 是同一批被跟踪产物，
   不能两版混着读），再打指纹 → 正式构建 → 名册/差分/快车道 → 判读 → 门禁两跑。
   预登记的判据四条（A1 机制 pins_after≪239 且 replica_cells≥1，否则 MECHANISM_INERT；
   A2 `clk_fpga_0` rel_margin ≥ 19.76 %；A3 其余三域不许变小；A4 FF 增量 ≤ 15 且无 `Place 30-439`）
   写在链脚本头部，不接受事后改口径。

**这一页早上看起来的样子**：如果 r117 的四条判据全过并已刷板复验，板上位流就是 r117 那一颗，
本页第一节到第五节讲的"极限判据"不变（那一族没被这一刀碰到，`eth_rxc` 两格在滚 B 里逐格相同）；
如果链子中断（构建/门禁/板级任一环节），板上仍是 r116 `bb2fb707aebc`，
而 C9 的赢面与落地入口都已在这一页和第 6.2 节留痕，早上只要决定要不要花那一轮。

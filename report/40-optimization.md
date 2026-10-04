# 优化过程：按轮次叙述（收益与代价同行，含被否决的刀）

对应赛题 3.3.5.3"优化过程，含优化前后的性能与资源对比表"与 3.3.4"取得可测量的性能表现，
并给出与基线的对比""合理使用片上资源，避免以显著的资源代价换取有限的性能收益"。

本章**只搬运与叙述**：每个数都指向盘上已有的工件文件与其中的字段，本章内不重算、
不四舍五入、不换算单位。派生量（比值、百分比）的公式与两个原始数在
[`comparison-notes.md`](comparison-notes.md)；结果与指标表在 [`50-results.md`](50-results.md)。

## 0. 单一事实源与台账未落地的说明

按 P18b 铁律 1，本节应当引用 `build/parsed/`、`build/roster/`、`build/runs/`、`report/measurements.md`。
**本节开工时（2026-10-04 上午）这四样都不存在**（实测 `ls build/roster build/parsed build/runs
report/measurements.md` 全部 `No such file or directory`），所以逐格取了名册与差分的**原件**；
写作期间并行 agent 把其中三样落地了（`build/roster/roster_r118.tsv`、`build/roster/roster_r118_probe.tsv`、
`build/parsed/*.json`、`report/measurements.md`），**`build/runs/`（P15c 逐轮台账）与
`report/build-notes.md`、`docs/optimization-rounds.md（未写）` 仍缺**。
本节与落地后的那三样做过交叉核对，结果与两条不同源登记在 `report/comparison-notes.md` §7。
**待 `build/runs/ledger.md` 落地后，本节改为引用台账**；在那之前，本节里凡是"某轮的名册"都指下表点名的原件。

| 类别 | 本节实际引用的原件 |
| --- | --- |
| 逐时钟名册 | `report/timing/roster_baseline.tsv`、`report/timing/roster_round115.tsv`、`report/timing/roster_round116.tsv`、`build/evidence/r114_after_roster_probefmt.txt`、`build/evidence/r116_after_roster.txt`、`build/evidence/r117_after_roster_probefmt.txt`、`build/evidence/r118_after_roster_probefmt.txt`（当前版另有 `build/roster/roster_r118.tsv`、`roster_r118_probe.tsv` 与之对照，见 `comparison-notes.md` §7） |
| 名册差分 | `build/timing_roster_diff.sh` 的产物：`build/evidence/r116_roster_diff.txt`、`build/evidence/r117_roster_diff_vs_r114.txt`、`build/evidence/r118_roster_diff_vs_r114.txt` |
| 严格判据件 | `build/evidence/r118_strict_b1.txt`、`build/r117_verdict_declined.txt`、`build/r118_verdict.txt` |
| 轮次台账 | `report/timing/debt_ledger.md` 的各轮追加节、`report/timing/round_r116.md`/`round_r117.md`/`round_r118.md`、`report/timing_global.md` §2/§4d/§4e/§6/§9、`report/optimization_log.md` 的 r62…r104 各节、`report/log/issues.md` #146/#230/#231/#234/#246/#250/#253–#255/#275–#335 |
| 每轮量 | `build/rNN_gates.txt`（r103…r118）、`build/evidence/rNN_before.txt` / `rNN_after.txt`、`build/*.rpt` |
| 指标表 | `data/metrics.csv` |

**台账由 P15c 落地后本节改为引用** `build/runs/ledger.md` 与 `build/roster/`；在此之前，本节里凡是
"某轮的名册"都指上表点名的原件，不指台账。

口径与已写好的三章一致：`report/04-resources.md`（资源与方法论告警）、`report/05-timing.md`（逐时钟名册）、
`report/06-validation.md`（四类判据射程）。第 8 节列出我发现的**两处不同值**，一律以证据文件为准，
不做取舍。

## 1. 基线定义（两把，可比性不同）

| 基线 | 是哪一轮 | 指纹 | 口径 | 可否与本轮相减 |
| --- | --- | --- | --- | --- |
| **B-early（优化前）** | 2026-09-18 那一版：`set_clock_groups` 未含 MMCM 生成钟、`sync_fifo` 带异步复位 | 无位流 md5 记录（件自述"产物：`build/system.bit`、`build/system.xsa`（21:40 前后）"，未钉 md5） | 无逐时钟名册、无门禁项数、约束集只有 `rk_zynq7020.xdc` 一份、RTL 规模与现在不同（LUT 10621） | **不可比，仅定性**（`comparison-notes.md` §3） |
| **B-main（可比主基线）** | **r114**，位流 md5 `7142a1fbf082`（`build/r114_gates.txt:3`） | 树指纹 `fpver=norm1 files=80 top=56c269602e18`（`build/evidence/r116_tree_fp.txt` 起各轮同一枚 `top`，`rtl=07570b1ac1b4`） | 约束集 = `src/constraints/rk_zynq7020.xdc` + `clock_groups_impl.xdc` 两份；名册由 `build/tcl/probe_timing_roster.tcl` 生成，对照侧必须同生成器（`report/log/issues.md` #326：混口径会被判 REFUSE） | **可比**：r117/r118 的差分件就是拿它当 A 侧（`build/evidence/r114_after_roster_probefmt.txt`） |

选 r114 而不是 r116 当主基线的理由写在 `report/timing/round_r117.md` §〇：r116 多带一份 RGMII 输入窗，
拿它当对照会把"撤掉一条约束"读成收益。

**贯穿全表的一条读法**（`build/evidence/r118_after.txt` 头部第 4 行原文）：
"判的是**同一个时钟 / 同一条锥**自己动没动；全局 WNS 的绝对差不算收益也不算损失（rule 35）"。
所以下表"各域 setup/hold"一栏从不与上一行相减当收益；只有**同域同锥**的两端夹逼读数才写进"关键性能"。

## 2. 按轮次对比表

列固定为 P18b 点名的八列。空格一律写 `NOT_MEASURED`（读不到输入 ≠ 通过 ≠ 失败）。
"结论"列的 `采纳`/`否决`/`测量不采纳`/`未进默认构建` 都指**是否进发布物**，不是指"做得对不对"。

| 轮次 | 改动一句话 | 关键性能（单位）| LUT/FF/BRAM/DSP | 各域 setup/hold（ns）| 告警按类 | 结论 | 证据路径 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-09-18 前 | 状态照录，无改动 | 跨域假违例 `eth_rxc→clkout0_1` **−6.748 ns** | NOT_MEASURED（该节未记 FF/DSP 分项，只记 LUT/FF 见下一行） | clk_fpga_0 +2.077 / eth_rxc +0.214 / sys_clk +14.897；hold 四域 NOT_MEASURED | NOT_MEASURED | 基线 B-early（不可比） | `report/optimization_log.md` 第 13–18 行 |
| 2026-09-18 首轮 | 异步组加 `-include_generated_clocks` + `sync_fifo` 去异步复位 + `ram_style=block` + rd_addr 打拍 | 全设计 `All user specified timing constraints are met`（跨域 −6.748 消失） | LUT 10621（19.96 %）/ FF 20253（19.03 %）/ BRAM 83 tile（59.29 %）/ DSP 13（5.91 %）/ 动态 2.240 W、结温 50.8 ℃ | clk_fpga_0 +0.865 / eth_rxc +0.111 / sys_clk +14.445 / clkout0_1 +1.882；hold NOT_MEASURED | NOT_MEASURED | 采纳（该轮记录自称已上板） | `report/optimization_log.md` 第 26–76 行 |
| r62 | V9 几何参数化上板 | WNS +0.792 / 失败 setup 端点 0 / WHS +0.001 | 12958（24.36 %）/ 9491 / 96（68.57 %）/ NOT_MEASURED；动态 2.201 W | 逐域 NOT_MEASURED（那一轮还没有名册） | 门禁 `build/gates_r62.txt`（项数与今日不同口径） | 采纳（历史行） | `report/optimization_log.md` 第 586 行；`build/gates_r62.txt` |
| r63b | **双线性读口接进来**（功能新增，非优化） | WNS +0.918 / WHS +0.052 | 14116（26.53 %）/ 9856 / 97（69.29 %）/ NOT_MEASURED；动态 2.204 W | 逐域 NOT_MEASURED | `build/r63b_gates.txt` | 采纳；**LUT/BRAM 的增量是功能代价，不写成优化收益**（§5 第 1 条） | `report/optimization_log.md` 第 587 行 |
| r75 | OSD 字格几何从最差锥挪走一拍（#96） | WNS +0.287 / WHS +0.041 | 14776（27.77 %）/ 10018 / 97.5（69.64 %）/ NOT_MEASURED；动态 2.209 W | 逐域 NOT_MEASURED | `build/r75_gates.txt` | 采纳，且是**最近一套全绿并被冻结**的版本 | `report/optimization_log.md` 第 588 行 |
| r84 | 回滚 `max_fanout` 之后把两刀贡献分开 | WNS **−0.094** / 失败 setup 端点 **16** / WHS +0.056 | 14360（26.99 %）/ 8073 / 95（67.86 %）/ NOT_MEASURED；动态 2.205 W | 逐域 NOT_MEASURED | `build/r84_gates.txt` | 采纳（负 WNS 的那一族在 r86/r87 被收掉） | `report/optimization_log.md` 第 589 行 |
| r86 | 诊断计数器使能改喂"寄存过的事件"（#124） | 目标族失败端点 **16 → 2**；WNS −0.135 / WHS +0.053 | 14358（26.99 %）/ 8075 / 95 / NOT_MEASURED；动态 2.205 W | 逐域 NOT_MEASURED | `build/r86_gates_final.txt` | 采纳；**判据是端点数不是 WNS 绝对值** | `report/optimization_log.md` 第 590 行 |
| r87 | 第二轮遍历代码 + `link_monitor` 两个事件位补进复位清单 + OSD 地址算法改乘加 | WNS +0.152 / WHS +0.051 | 14363（27.00 %）/ 8075 / 95 / NOT_MEASURED；动态未取 | 逐域 NOT_MEASURED | 门禁未跑完（该节自述"这一行只有报告数"） | 当时的板上版；门禁红 ⇒ 不作"过门禁的一版" | `report/optimization_log.md` 第 591 行、第 610–612 行 |
| r88 | `dc_fifo` 满判据改用当前写指针（#105 第二刀） | `u_cdc` 一族**整族从最差路径里消失**；WNS +0.516 / WHS +0.051 | 14358（26.99 %）/ 8075 / 95 / NOT_MEASURED；动态 2.205 W | clk_fpga_0 +1.643 / sys_clk +14.621（eth_rxc 即 +0.516）；其余 NOT_MEASURED | 门禁 18 项判定全过、**2 项因缺同跑台架凭据未判** ⇒ `PARTIAL`（#141） | 采纳上板，但**当轮不算"过门禁的一版"** | `report/optimization_log.md` 第 592 行；`build/r88_gates_partial.txt`；`report/log/issues.md` #141 |
| r89 | 给 `u_cdc` 的 9 块 BRAM 旁画 Pblock | 目标族本来就不在最差名单 ⇒ 无可归属收益；`eth_rxc` WNS +0.516→+0.363 | 14357（对照 r88 14358）/ NOT_MEASURED / 95 / NOT_MEASURED | 见左（`clk_fpga_0` +1.861、`sys_clk` +13.808）| NOT_MEASURED | **否决**：买风险没买到东西 | `report/log/issues.md` #146；`build/evidence/r89exp_timing_summary.rpt` |
| r90 | 帧缓存 `mem[0:38399]` 拆成三块 2 的幂深度 | BRAM 省 **5 片 RAMB36**；代价：`eth_rxc` WNS +0.516→+0.232（拆）→**+0.182**（拆+寄存）；最差级数 4→9→4 | NOT_MEASURED / NOT_MEASURED / **88**（64.64 %）/ NOT_MEASURED | 见左 | NOT_MEASURED | **否决**（§5 权衡判断的主体） | `report/optimization_log.md` 第 623–665 行 |
| r91 | 只换实现策略（RTL/XDC 一字不改）：`Performance_Explore`、`Performance_ExtraTimingOpt` 各一整滚 | hold 三档 0.046/0.051/0.051 ⇒ **一位没买到**；setup 第二档反而 0.516→**0.157** | NOT_MEASURED | 全设计 WNS/WHS 见左；逐域 NOT_MEASURED | NOT_MEASURED | **否决**；副产品：把"+0.05x 的 hold 是时钟树结构不是不够用力"钉硬 | `report/optimization_log.md` 第 686–698 行 |
| r92 | #57：`rgmii_rx` 删 `BUFIO`、5 个 IDDR 改吃 BUFG；`IDELAY_VALUE` 15→26 | **最差那族 hold 的时钟偏斜 +1.616 ns → 同树内 0.013–0.349 ns**；WHS 数字没变好（+0.051→+0.037） | 14351 / 8075 / 95 / 19 | eth_rxc +0.522/+0.049、clkout0_1 +0.885/+0.048、clk_fpga_0 +2.161/+0.037 | `build/r92_gates.txt` 20 项判定 / 1 红（`C5c`） | 采纳；**收益记结构性，不记数字** | `report/optimization_log.md` 第 709–746 行；`build/clock_uncertainty.rpt` |
| r94 | 几何两刀落地（#104 小数位、#93 旋转态钳进 fit） | WNS 0.553 / WHS 0.049 / 失败端点 0 / 50883 | NOT_MEASURED（该节未列，r95 引作基线） | 逐域 NOT_MEASURED | 20 项判定 / 1 红（`C5c`） | 采纳（板上版 `a1465f29c9e4`） | `report/optimization_log.md` 第 785–800 行；`report/log/issues.md` #179；r95 节把它写作基线戳 |
| r95 A | 布线后 `phys_opt_design -directive AggressiveExplore` | 读数与基线**逐位相同**：WNS 0.553 / WHS 0.049 / 0 / 50883 / BRAM 95 | 同基线（BRAM 95）| 逐域 NOT_MEASURED | NOT_MEASURED | **否决**（结构性空转，凭工具自己那三行：`All physical synthesis setup optimizations will be skipped` / `The netlist was not modified`） | `report/optimization_log.md` 第 802–818 行；`build/isolated_r95_postroute_physopt/build_console.txt:2568` 起 |
| r95 B | `Performance_ExploreWithHierarchy` | NOT_MEASURED（`list_property_value strategy` 里没有它，`set_property` 步就拒 ⇒ `BUILD_STRATEGY_REJECTED`，退出码 2） | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | **NOT_MEASURED，不写成否决** | `report/optimization_log.md` 第 819 行 |
| r95b | 另两档策略 `Performance_NetDelay_high` / `Performance_WLBlockPlacementFanoutOpt` | 前者 WNS **+0.013** / WHS +0.056；后者 WNS +0.553 / WHS +0.049（与基线一格不差，位流不同） | BRAM 均 95；余 NOT_MEASURED | 逐域 NOT_MEASURED | NOT_MEASURED | **两档都不采纳** ⇒ "靠工具再压时序"这一问题关闭 | `report/optimization_log.md` 第 836–844 行；`build/r95b_timing_summary.txt` |
| r99 | 五刀（#209/#128/#185/#186/#188/#201） | 全设计 WNS +0.284 / WHS +0.051 / 0 失败 / 50867 | 14330 / 8078 / 95 / 19 / 动态 2.213 W、估算结温 52.6 ℃ | 收包 0.284 / 100 MHz 1.117 / 显示 `clkout0_1` 1.317；`sys_clk` NOT_MEASURED | 19 绿 / 1 红（同一条 `C5c`），台架 140 PASS + 1 FAIL，指纹 fresh | 采纳（bit `b0f0914becc1`） | `report/optimization_log.md` 第 954–968 行 |
| r102 | `icmp_rx` 状态机出路 | WNS +0.384 / WHS +0.052 / WPWS +0.264 / 0 失败 / 50868 | NOT_MEASURED（该节逐条给的是路径表） | 逐域 NOT_MEASURED；六条最窄路径里 4 条是 0–1 级逻辑、route 65–94 % ⇒ 瓶颈是**布线/拥塞不是深度** | NOT_MEASURED | 采纳；本节的"到头"含义被写成"剩下的杠杆不在 RTL 逻辑层"。**代价同栏念**：该节记录 WNS 从 +0.506（r101）落到 +0.384、WHS 从 +0.028 到 +0.052 —— 按规矩 35 这一升一降**都不写成收益或损失**，能写的只有"两端都 met、0 失败端点、最差格归属换了"；真正付出的是排期（把"再砍 RTL"的收益上限量到趋近零） | `report/optimization_log.md` 第 970–1000 行 |
| r103 | 唯一 RTL 改动 = `zoom_mapper` #189（全在组合逻辑里） | WNS +0.608 / WHS +0.053 / WPWS +0.264 / 0 失败 / 50868 | 14333（26.94 %）/ **8079（与 r102 触发器一字未动那一版相同）** / 95 / 19；LUT as Memory 4186、Dist RAM 4044 | eth_rxc 0.608 / clk_fpga_0 1.035 / clkout0_1 1.061 / sys_clk 14.849；hold 最差 0.053 | 19 绿 / 1 红；综合告警名册 19 种码 | 采纳；**LUT −22 只是这一刀的资源代价，不构成时序收益宣称** | `report/optimization_log.md` 第 1002–1035 行；`build/r103_gates.txt:10,12,14,15,16` |
| r104 | **#141**：`icmp_tx` 三处 16 位减法提前一拍寄存 | 目标族从最差位消失；全设计 WNS 0.608→**0.812**（换族，不算收益）；WHS 0.053 不变 | 14334（+1）/ **8127（+48）** / 95 / NOT_MEASURED | 逐域见 r105 那把对照（同数）| 综合告警名册 **19 种码逐码计数与 8-7137 寄存器身份列表都相同**；门禁 22 项 / 1 红 | **采纳**（代价 +48 FF，两次独立构建给出同一代价） | `report/optimization_log.md` 第 1037–1059 行；`build/r104_gates.txt:10,12,15,16,17` |
| r105 | 不是构建轮：为 #141 做"同树重复滚"的 A/B（post ×3 独立调用、pre ×2） | post 三滚全 0.812 / pre 两滚全 0.608 ⇒ 该策略下**可复现的 +0.204 ns**，且四个域一起抬（eth_rxc +0.204 / clk_fpga_0 +0.323 / clkout0_1 +1.613 / sys_clk +0.187）；post 各滚位流 md5 互不相同 | NOT_MEASURED（隔离滚动产物，未取资源行） | 上列四域 setup；hold NOT_MEASURED | NOT_MEASURED | 采纳侧的证据；**同树重复滚噪声底实测 0.000**。**代价同栏念**：这一趟不产资源行（隔离滚，NOT_MEASURED），它付的是**口径收窄**——把台账里"0.4 ns 放置摆幅"从"可以用来否掉一个 +0.204"降级成"只适用于跨变体的两次构建之间"（件里第 36–40 行的改口），并明写"不宣称 #141 在所有策略下都涨" | `build/evidence/r105_ab_rolls.txt` 第 12–16 行（读数表）与第 27–40 行（三条读法，含"同树重复滚噪声底 0.000"在第 37 行） |
| r106 | 只落了收包链那一刀（`udp_off+8`／`+len-1` 提前一拍寄存） | WNS 0.723 / WHS 0.051 / 0 失败 | 14323（26.92 %）/ **8149（+22 相对 r104）** / 95（67.86 %）/ NOT_MEASURED；动态 2.214 W | clk_fpga_0 1.387/0.053、clkout0_1 1.264/0.052、eth_rxc 0.723/0.051、sys_clk 13.196/0.121 | 门禁 22 项 / 1 红；**`doc_currency` 第一次以自红形状被抓**（`r106_gates_firstselfred.txt`） | 采纳；D6 数字对账第一次接进门禁就抓到首页四格还是 r103 的数（#219） | `build/r106_gates.txt:10,12,14,15,16,17`；`build/evidence/r106_gates_firstselfred.txt`；`data/metrics.csv` 第 14 行 |
| r107 | 行覆盖位图分 5 组（`rok0..rok4`）降广播扇出 | 目标族两端夹逼 **0.723 → 2.006 ns**（同一起点/终点对），该族从最差 8 条里退出；WNS 0.725 是**换了主人**不是变好 | 14323（与 r106 逐字相同）/ 8156（+7）/ 95 / 19 | 逐域 NOT_MEASURED（该轮只给族级） | 门禁 22 项 / 1 红 | 采纳；等价性由逐拍台架 + 错组变异判红撑着（`r107_rowok_bank_equiv.txt`） | `report/log/issues.md` #230；`build/evidence/r107_rowok_bank_equiv.txt`；`build/r107_gates.txt` |
| r108 | IP 首部校验和由一拍 10 项摊成两拍各 5 项 | 同端点对夹逼 **0.725 → 1.081 ns**，级数 9→11（CARRY4 4→6）、route 60.9 %→56.2 %；**代价：全局 WHS 0.050→0.035** | 14360（26.99 %）/ 8168 / 95 / NOT_MEASURED；动态 2.212 W | 逐域 NOT_MEASURED；新最差 `u_iddr_rx_ctl→icmp_rx/des_mac` route 84.3 %，且钟网络 SCD 5.008 / DCD 4.493 ns | 门禁 22 项 / 1 红 | 采纳；"极致"位置由此量出：**收包域 setup 由钟插入延迟 + 自加不确定度定死** | `report/log/issues.md` #231；`build/r108_gates.txt:10,12,14,15,16,17` |
| r109 | **#105 尾账**：`osd_overlay.v` 选中格提前一拍寄存（`ch_r` 落分布式 RAM） | `clkout0_1` 最差 **1.130 / 23 级 → 4.094 / 21 级**；该域相对余量 5.65 %→20.5 %（同一条尺子、同一个域）；全局 WNS 0.721→0.605 是持有者换了 | 14362（27.00 %）/ **8162（−6）** / **95.5**（68.21 %）/ NOT_MEASURED；动态 2.214 W | eth_rxc 0.605、clk_fpga_0 1.238、clkout0_1 4.094、sys_clk 15.289；hold 0.049/0.052/0.053/0.121 | 门禁 24 项；台架阶段**被我自己并发的 xsim 挡死 ⇒ 该阶段无凭据** | **不采纳、不刷板、不改口**（构建与三份只读探针是真跑完的） | `report/log/issues.md` #234；`build/evidence/r109_clk01_before.txt`/`r109_clk01_after.txt`；`build/r109_gates.txt:10,12,14,15,16,17` |
| r110 | 刀 4①：`rows_hit` 写使能从三项式改独热两项式 | 抓手判据**达成**：`fo=316` 那根网本轮报告里不存在、`rows_hit*/CE` 作最差终点出现 0 次；WNS 0.713 / WHS 0.042 | **14119（−243）/ 8154（−8）** / 95.5 / NOT_MEASURED；端点 51029→51013 | 逐域 NOT_MEASURED | 门禁 24 项 = 21 绿 / 3 红（3 条红是"还没采纳"的正常形状） | **不采纳**：−243 LUT 无法从扁平汇总件归到模块 ⇒ 没归到具体模块的量不写进首页（规矩 46） | `report/log/issues.md` #246/#249/#250；`build/r110_gates.txt:10,12,14,15,16,17`；`build/evidence/r110_attrib.txt` |
| r112 | 两刀：`key_debounce` 武装门（#256 未打中那一半）+ `icmp_tx` 校验和累加器 32→20 位 | 刀 B 同族对照成立：`check_buffer` 一族改前 5 块 → 改后 **0 块**；全设计最差 0.713→0.445 **归属换族**，同一条 `rows_hit` 族 RTL 一字没动却从 >1.174 变 0.445 | **14154（+35）/ 8188（+34）** / 95.5 / NOT_MEASURED；端点 51135 | eth_rxc 0.445/0.050、clk_fpga_0 1.135/0.056、clkout0_1 4.467/0.059、sys_clk 14.463/0.133 | 综合告警名册 19 种码不变 | **带两刀采纳**；刀 B 记为"同族抓手成立、设计余量未抬"，代价与不兑现一起登记 | `report/log/issues.md` #250/#253/#254/#255；`build/evidence/r112_verdict.txt`、`r112_util_attrib.txt`；`build/r112_gates.txt:10,12,14,15,16,17` |
| r113 | `snap_cross.hb_gone` 声明上电初值（#256/#257 收尾） | **八个 (域,类型) 对逐位相同** ⇒ 功能修复、时序中性；位流 `897fa9d93956`→`b94f4da6cdff` | 14154 / 8188 / 95.5（与 r112 逐字相同） | 同 r112（0.445/1.135/4.467/14.463 与 0.050/0.056/0.059/0.133） | 名册差分 D1..D6 **唯一红是 `D6_fanout_inventory`（工具自己的账，不是设计的）** | 采纳；#254 那一夜同时证伪了"骰子"说法：同一 `opt.dcp` 重跑 place+route 逐位复现 | `report/timing_global.md` §2b；`report/log/issues.md` #261/#263；`build/evidence/r113_roster_diff.txt`；`build/r113_gates.txt:10,12,14,15,16,17` |
| r114 | 两刀：`dc_fifo` 四颗格雷码寄存器打 `ASYNC_REG`（#262）+ `hb_gone` 声明初值 | WNS 0.445→**0.739** / WHS 0.050→**0.052**；网表侧带属性 FF **0→56 颗**；**收益记给"结构账变干净"，不记给 slack**（`ASYNC_REG` 是放置指令） | 14154 / 8188 / **95.5** / 19（资源逐字中性） | eth_rxc 0.739/0.052、clk_fpga_0 1.850/0.053、clkout0_1 **3.630**/0.059、sys_clk 14.876/0.222 ⇒ 相对 r113：`clkout0_1` setup 掉 18.8 %、`clk_fpga_0` hold 掉 5.4 %，都在预登记 25 % 门槛内 | 资源中性；综合告警名册差分**是空**；`report_methodology` **446 / 7 类**（DPIR-1 2、LUTAR-1 1、SYNTH-5 336、SYNTH-6 98、TIMING-9 1、TIMING-10 1、TIMING-18 7） | **采纳**（bit `7142a1fbf082`，门禁 24 项 23 绿 / 1 红、两跑逐字节一致） | `report/log/issues.md` #290/#292/#293/#294；`report/timing/roster_baseline.tsv`；`build/evidence/r114_after.txt`；`build/r114_gates.txt`；`build/methodology.rpt:26,30-36` |
| r115 | 一整夜只做**测量**：名册尺子、噪声底、三把候选刀 | **收敛 0 ns**；`noise_ns = 0.000`（两次空白滚逐位相同）；C1 复制刀机制动了（`REPLICA_CELLS` 0→**310**）但 32 次比较里 **4 格红**；C2 统一 0.800 hold 带 ⇒ WHS **−0.747 / 25,742 失败端点**；C3 MMCM 副本树 ⇒ WHS **−2.126** 且 UU 脱离派生钟覆盖面 | NOT_MEASURED（本轮不采纳，未出正式资源行）| 名册 = `roster_baseline.tsv` 那八格；B 滚四域见 `roster_round115.tsv` 的 `b_*` 列 | 类不增（无正式构建可量）；`loosen_ledger.tsv` **0 条数据行** | **什么都不采纳**（G1 红四格 ⇒ C1 拒绝；夜里无批准人 ⇒ C2/C3 只做测量） | `report/timing/README.md` §时间线/结论；`report/timing/roster_round115.tsv`；`build/evidence/r115_fanout_ab/verdict_header.txt`；`report/log/issues.md` #297/#301/#302/#305/#306 |
| r116 | 两刀进构建：RGMII 输入窗第一次写上（min 1.200 / max 2.800）+ `IDELAY_VALUE` 26→**31** | I/O 那 5 格**第一次被检查**（此前 `Slack: inf / Path Group: (none)`）；`eth_rxc` setup **−0.846 / hold −0.870**；`clk_fpga_0` 1.850→1.976、`clkout0_1` 3.630→3.698、`sys_clk` 14.876→14.876；`check_timing` 未约束输入端口 5→**0**、`io_unconstrained_ports` 11→**6** | 资源**逐字中性**：14154 / 8188 / 95.5 / 19 | 见左；hold `clk_fpga_0` 0.053、`clkout0_1` 0.059、`sys_clk` 0.222 逐格不动 | `Checks found` 446→**441**、TIMING-18 **7→2**（少的 5 条就是这轮第一次被检查的 5 个输入）| 两刀**都被量到底**；窗被自家发布门 4 条硬项判红 ⇒ 退回候选件；τ=31 留在 r117/r118 | `report/timing/round_r116.md` §一/二/三 V1–V6；`report/timing/roster_round116.tsv`；`build/evidence/r116/r116_io_{HOLD,SETUP}.rpt`；`build/r116_gates.txt:10-13` |
| r117 | 一刀：`phys_opt_design -force_replication_on_nets {u_pl/u_row/hi_reg_0[0]}`（239 引脚广播网）挂 `PLACE_DESIGN.TCL.POST` | 机制成立：`pins_before=239 → pins_after=1`、`replica_cells=10`、端点 15,721→**15,731（+10）**；`clk_fpga_0` setup 1.850→**2.104**（赢的那一格正是靶子）| 快车道滚 B 的代价：Slice 寄存器 8,188→**8,198（+10）**、LUT/BRAM/DSP 不动（正式构建的资源行未进发布物 ⇒ NOT_MEASURED） | `clkout0_1` 3.630→**3.353**、`sys_clk` 14.876→**14.815**、`eth_rxc` 0.739→**0.615**、`eth_rxc` hold 0.052→**0.044** ⇒ **四格跌** | `report_methodology` 类计数不增（判据 A4） | **否决（DECLINED）**：预登记的严格口径不过 ⇒ 按 H7 回滚这一处切割；位流 `beda9298331d` 留档不删 | `report/timing/round_r117.md` §一/二/二之二/三；`build/r117_verdict_declined.txt`；`build/evidence/r117_after_roster_probefmt.txt`；`build/evidence/r117_roster_diff_vs_r114.txt`；`report/log/issues.md` #327/#328 |
| r118 | 只带 `IDELAY_VALUE = 31` 一刀（不挂复制钩子、不加载输入窗） | 片内名册**8 对逐位与 r114 相同**（`losses=0`）⇒ 这轮的收益**不体现在片内 slack**，判据是 B1 不劣化 + B4 发布门 + 板级复验；τ 那把刀的量在片外：−1.185→**−0.870**（+0.315 ns） | 14154 / 8188 / 95.5 / 19（B3 判资源中性） | eth_rxc 0.739/0.052、clk_fpga_0 1.850/0.053、clkout0_1 3.630/0.059、sys_clk 14.876/0.222 | 资源与告警回落到 r114 那一版：`Checks found: 446`、TIMING-18 7 条（撤窗的诚实读数） | **采纳并上板**（bit `cd04907e1369`，`board_verify --geom --battery` PASS 判红步骤 0，E6 眼睛判过读 0）。**代价同栏念**：这一版没有窗 ⇒ `eth_rx_ctl` 与 `eth_rxd[3:0]` 这 5 个收端点**没有被任何输入延迟约束覆盖**（未检查 ≠ 满足），且片内一格也没变好（B1 的"逐位相同"是中性不是收益） | `report/timing/round_r118.md` §一/二/三/四/五；`build/evidence/r118_strict_b1.txt`；`build/r118_verdict.txt`；`build/evidence/r118_after.txt`；`build/r118_gates.txt:10-13` |
| r119 | 只读探针 + 两份候选 XDC：把 HDMI 源端 TP1 的数写成 `set_output_delay` | 挂上后互对窗给 −3.482/−3.458/−3.474 ns，打在钟脚上的 20 ns 参考钟给 −4.897/−4.873/−4.890 ns ⇒ **是量纲错不是设计红**；换同量纲问法（已布线成品逐脚 clock-to-pin 离散）：互对最差 **0.065 ns**（上限 0.20 `Tcharacter` = 4.000 ns）、对内最差 **0.001 ns**（上限 0.15 `Tbit` = 0.300 ns），判 10 项红 0 | NOT_MEASURED（未进构建）| NOT_MEASURED（只读开 r118 成品 DCP，未重跑名册） | NOT_MEASURED | **未进默认构建**（`VP_R119_TMDS_WINDOW=1` 默认关）；债改成两笔：板级走线/连接器离散未量、眼图/抖动/占空比/沿未量 | `report/timing/debt_ledger.md` 2026-10-04 09:4x 追加节；`build/evidence/r119_window_check.txt`；`build/evidence/r119_xdc_loads_probe3.txt`、`_probe4_pinclk.txt`；`report/log/issues.md` #335 |

> **本表的计数与"收益/代价同栏"的兑现方式**：表共 **35 行轮次**（第一行 `2026-09-18 前` 是**基线行**，
> 它没有刀也没有收益，只记状态，所以不进"只有收益的轮次"那笔账）。其余 34 行里，
> 每一行的"关键性能"给收益、"LUT/FF/BRAM/DSP"+"告警按类"+"结论"三格中至少一格给代价；
> 读不到的代价一律写 `NOT_MEASURED` 并在下面第 6 节说明缺的是哪一份件，
> **不以"没写"冒充"没有代价"**。采纳刀的代价另在 §4 逐条集中念（8 条），否决刀的代价在 §3 逐条念（21 条）。

## 3. 被否决的刀（收益 + 代价 + 判据 + 为什么不进发布物）

> 只报收益的行等于未完成，所以这一节把每条**代价**与**判据**并列摆出。
> "为什么不进发布物"这一列说的是：在指名的那份判据下它过不了，或者它的收益对象根本不存在。

| # | 被否决的刀 | 量到的收益 | 量到的代价 | 判它的那把尺（预登记与否） | 为什么不进发布物 | 凭据 |
| --- | --- | --- | --- | --- | --- | --- |
| V1 | **Pblock 圈住 `u_cdc` 的 9 块 BRAM**（r89） | 无（目标族 r88 起已不在最差名单 ⇒ 没有可归属的收益对象） | `eth_rxc` WNS +0.516→+0.363（落在实测摆幅内，不称坏也不称好）；代价还有"以后每次改动都少一块可摆放的地"，新最差路径贴着被圈住的区域 | 规矩 35（绝对差不算收益/损失）+ 归属判据 | 买风险没买到东西；XDC 与挂载全部回退，实验目录留作反例凭据 | `report/log/issues.md` #146 |
| V2 | **BRAM 换 setup**：帧缓存拆三块省 RAMB36（r90） | RAMB36 93→**88**、tile 95→**90.5**（省 140 片里的 5 片） | `eth_rxc`（125 MHz，最快域）WNS +0.516→**+0.182**，即 8 ns 周期的 6.5 %→2.3 %；级数 4→9（结构性量，不能用摆幅解释掉）；补 FF 那一刀把级数修回 4，但 setup 没修回来 | 同一把尺子 `build/tcl/crit_path.tcl` + 两滚复现（件里原话："两份报告的 WNS 与级数**完全相同**"） | **在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的**（§5） | `report/optimization_log.md` 第 623–665 行 |
| V3 | **实现策略 `Performance_Explore` / `Performance_ExtraTimingOpt`**（r91） | 无：hold 三档 0.046/0.051/0.051 全在历史噪声带内 | 后者把 `eth_rxc` setup 从 +0.516 花到 **+0.157** | 跑之前写在 `build/r91_strategy_round.sh` 头部：WHS ≥ +0.15、WNS ≥ +0.40、失败端点 0 | 两滚无一同向好、门槛一条没过；副产品把"+0.05x hold 是时钟树结构"钉硬 | `report/optimization_log.md` 第 683–698 行 |
| V4 | **布线后 `phys_opt_design`**（r95 A） | 0（与基线逐位相同） | 0（网表未被修改） | 事前门槛 WNS ≥ +0.65 / WHS ≥ +0.15 / 端点 0 / BRAM ≤ 95 | 工具在一个无违例设计上**结构性跳过全部优化** ⇒ 这一档永远不会给已过时的本版带来收益；`DECLINED（结构性空转）`的凭据是工具自己那三行日志而不是我的推断 | `report/optimization_log.md` 第 805–818 行 |
| V5 | **策略 `Performance_ExploreWithHierarchy`**（r95 B） | NOT_MEASURED | NOT_MEASURED（工具在 `set_property` 步就拒 ⇒ `BUILD_STRATEGY_REJECTED`） | 退出码表（2 = REFUSE，3 = 判红，4 = 认不出判定）分开了"没数"和"红" | 读不到输入 = `NOT_MEASURED`，**不许写成否决**（把它写成 DECLINE 就是让"没数"长得像"结论"） | `report/optimization_log.md` 第 819 行 |
| V6 | **两档策略 `Performance_NetDelay_high` / `WLBlockPlacementFanoutOpt`**（r95b） | 前者 WNS +0.013（比基线低 0.54 ns，超出 0.4 ns 摆幅 ⇒ 不是噪声里挑好看的）；后者与基线一格不差 | 两份位流 md5 互不相同、也不同于正式件 ⇒ "策略被应用了"是有凭据的，不是拿默认流程冒充 | 事前门槛同 r95 | 一档方向不利、一档毫无作用 ⇒ "靠工具再压时序"这个问题到此关闭；按规矩 35 后者只念"没达门槛"不念"打平" | `report/optimization_log.md` 第 836–844 行 |
| V7 | **Pblock `SLICE_X40Y20:SLICE_X66Y52`（r113 roll B）** | 没量到（滚在两分钟内自拒） | 无资源代价（未产出对照）；代价是**这一刀没做成单变量实验** | `Place 30-439`：进位链半内半外；落点地板实测 `PB_CONTAIN total=1716 inside=1461`；`--self` 的 `PB-REFUSE` 地板让它死而不产伪造对照 | 不是"物理这条路判死"，是**那块表达式不成立**（要修得把共享 carry chain 的 `u_eth/u_rx_mac` 一起收进来再滚）；`report/timing/gates_g1_g12.md` G11 明写这一条在 L2 计数里只能算"没做成"，不能当一条独立负结果 | `report/log/issues.md` #254/#255；`build/evidence/r113_roll_abc_verdict.txt` |
| V8 | **`place_design -directive Explore`（r113 roll C）** | 0：与对照滚 A **一格不差**（0.445 / WNS 0.445 / 0 of 51135，落点也相同） | 无 | 三滚单变量 A/B（唯一变量写在脚本首行 `VARS`） | 负结果不进首页成绩；它的正面价值是排除法——把候选从"换策略"逼到"扇出复制"与"Pblock 修表达式"两类 | `report/timing_global.md` §3；`report/log/issues.md` #255 |
| V9 | **RGMII ±0.500 ns 输入窗**（r114 快车道 B 滚） | 输入侧欠账清了：`check_timing` 的 HIGH 无输入延迟端口 5→**0** | WHS 0.050→**−2.885**、THS **−14.344**、5 个失败 hold 端点全在 `u_iddr_rx_ctl/D`（2 级逻辑、**route 0.000 %**）；其余三域 setup 只是 ±0.26 ns 内的小动 | 同一份 `opt.dcp` 两滚、唯一变量是那份候选 XDC；A 滚逐位复现正式构建 ⇒ 差是约束造成的不是放置骰子 | **不是回归，是旧读数的口径本来就不成立**：那 0.050 是"数据恰好在钟沿到达"这个隐含假设换来的；变体 A（只声明上升沿）读数逐位相同 ⇒ 沿的条数不是原因（#278），`-clock_fall` 那条解释被数据否掉 | `report/timing_global.md` §4d；`report/log/issues.md` #275/#278；`build/evidence/r114_io_roll_console5.txt` |
| V10 | **`set_max_delay -datapath_only` 叠在异步组上**（#276） | 无：四条跨域界一条都没生效 | `report_exceptions` 表体 A 滚 13 行、B 滚 13 行，`-datapath_only` 出现 **0 次** | 只读 A/B 四份件（base/base_after/io_before/io_after） | 界**叠不到**被时钟组整体排除的钟对上；要真给界必须动"那一对钟要不要继续整组互斥"这个口径决策 ⇒ 会改 WNS 的算法范围，必须单独一轮带名册差分做，不许顺手做掉 | `report/log/issues.md` #276；`report/timing_global.md` §4d 末、§4c |
| V11 | **复制驱动（39 根 fo≥200 的广播网，r114 快车道）** | 目标族 `p_eof → rows_hit[*]` 0.445→**0.901（+0.456 ns）**；机制两路来源都对上（`REPLICA_CELLS` 0→**296**；`u_pl/u_clk/u_mmcm_0` 扇出降 58） | `eth_rxc` hold 0.050→**0.035**（相对余量 0.62 %→0.44 %，**−29.0 %**）；另有 `clkout0_1` setup −5.5 %、`sys_clk` setup −1.4 %；Slice LUTs 14154→14185（+31） | 名册差分 8 对（D1 新违例 0、**D3 `big_loss=1` ⇒ RED**）；头条 WNS 不参与裁决 | 买到的 +0.456 与被拿走的东西在**同一个域**，而那个域的 hold 已被 V9 证明根本没有可信余量 ⇒ 再削三成等于把"WHS 在 ±1 ps 上掷硬币"重新请回来。`MF-SUMMARY … verdict=DECLINE`。还留一条老实话：V2c 那根下降的网名字像钟（`u_pl/u_clk/u_mmcm_0`），重开这刀前要先把它剔出目标名单 | `report/log/issues.md` #288；`report/timing_global.md` §4e；`build/evidence/r114_mf/verdict.txt` |
| V12 | **复制驱动重开（r115 夜 C1，310 颗 replica）** | 确实抬高了 `clk_fpga_0` setup 相对余量（0.185→0.1959）与 `clkout0_1`（0.1815→0.195）；`u_pl/u_clk/u_mmcm_0` 扇出 2109→2062 | 32 次比较里 **4 格红**：`eth_rxc` setup 0.739→0.665、`eth_rxc` hold、`sys_clk` setup、`clk_fpga_0` hold；FF 8188→**8463（+275）**、LUT +35 | `build/r115_roster_build.py` 的 G1+G2 判定，判据原话是"在 `noise_ns=0.000` 之下非零差都算真的" ⇒ `F5_roster_diff … verdict=RED` | **结论不是"复制没用"，而是"在 `eth_rxc` 没有可信 hold 余量之前，复制的代价由它付"** ⇒ 顺序换成 C3 在前。副产品：A 滚名册与 `roster_baseline.tsv` 逐格相同 ⇒ 快车道在这棵树上能复现正式构建名册 | `report/log/issues.md` #301；`report/timing/roster_round115.tsv`；`build/evidence/r115_fanout_ab/verdict_header.txt` |
| V13 | **统一 0.800 ns hold 不确定度给四域（C2）** | 无收益（方向是**加严**，本来就不产收益）；它买到的是"债显形" | 设计级 WHS 0.053→**−0.747**、THS 失败端点 **25,742**（WPWS 0.264 不变）；`−0.747 = 0.053 − 0.800` 与 `clk_fpga_0` 现行报的数逐位对上 | 只读开正式 routed dcp，约束只活在会话里；尺子 `--self` 六条对照 | **这是测量不是采纳**：读数会变难看需要有人点头（G3），夜里无批准人 ⇒ 只测。它的真正产出是把交付文档那句"四域 hold 全为正"限定成"在现行约束集下为真"，且四个 WHS **不可跨域比大小**（只有 eth_rxc 带那条带） | `report/log/issues.md` #302；`report/timing/uncertainty_hold_ab.md`；`report/timing/cut_ledger.tsv` C2 行 `blocked(no approver for adoption)` |
| V14 | **MMCM 负相移把 IDDR 捕获钟提前（C3，副本树）** | S2 机制 GREEN（副本树 `mmcm=1/iddr=5/bufg=1`，主树 `mmcm=0` 且正对照当场红）；S4 `io_unconstrained_ports` 11→6；WNS 侧只买到 **+0.759 ns** | S1 RED：终态 WHS **−2.126**、THS −10.552、5 个 hold 失败端点 ⇒ **窗没关住**；更要紧的是那 +0.759 里约 **0.67 ns 是"约束作用范围被削弱"换来的**（`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` 不再覆盖派生钟 `mmcm_clk0`，UU 项从读数里消失）；S3 判不了（fabric 换到派生钟 ⇒ 名册按名字配对失效，脚本按约定没替它圆场） | 事前把判据写在 `report/timing/rgmii_window_model.md` §4；资源代价几乎为零（`MMCME2_ADV` 2/4→3/4、LUT +5、FF 不变），死因是**机制不是代价** | 不进主树、不采纳、不刷板；主树 `src/` 一字未动。它产出了本轮最值钱的一条清单（件里原话）：**新建或改名一只钟之后，点名旧钟的那几类约束要逐条重查覆盖面**（`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay -clock`、IDELAY/参考钟关系）。同一刀路在 00:12 又被算术关了一次：真窗下主树 hold −1.385 / setup −0.186 | `report/log/issues.md` #305/#306；`report/timing/cut_ledger.tsv` C3 行 `rejected-measured`；`build/evidence/r115_c2_scratch/option_a_console.txt`、`option_a_main_console.txt` |
| V15 | **`IDELAY_VALUE` 在 0…31 之外找点（tap 全档）** | 在带窗口径下扫满 0…31，量到两条实测直线与交点 τ=31.1 ⇒ 31 是 `min(hold,setup)` 的最大点（比出货值 26 抬 +0.315 ns，这一半被 r116/r118 采纳） | 关掉它的是**不等式**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，合法 τ 只有 0…31 ⇒ 两个集合**不相交**；去掉与窗双重计的那 0.800 带也只是把下界挪到 32.1，仍不相交 | `build/evidence/r115_window/probe3_console.txt`（`set_property IDELAY_VALUE` 在已布线 DCP 上有效 ⇒ 整条扫描不花构建） | 极限判据第一次真满足（L1+L2+L3 齐）：根因是两只钟的角间差 **3.411 ns**（hold 慢角 DCD 5.008 / setup 快角 1.597）而数据只有 **0.467 ns** ⇒ 在"`eth_rxc` 那 5 个端点 + 当前结构"这一条件下**不存在同时满足两条检查的采样点**。⚠ 这条**只支持**"当前结构下无解"，不支持"换短钟也关不掉"（BUFIO 快角 DCD 未实测，#323） | `report/log/issues.md` #310/#311/#323；`report/timing/round_r116.md` §一 第 5/6 行；`report/timing/rgmii_window_model.md` §7.5(4) |
| V16 | **`clock_groups_impl.xdc` 合回主文件（C6）** | 无（已被证伪） | 合回去会让整条 `set_clock_groups` 空转（`Vivado 12-4739`），连带废掉 `eth_rxc`/`sys_clk` 两组；现场只留一句 warning | `help` 形状探针 + 实测加载 | "不适用——已被证伪"，D0；它进台账的价值是让后来的人不再花一轮去试 | `report/timing/cut_ledger.tsv` C6 行 |
| V17 | **C9 强制复制那根 239 引脚广播网（r117 官方构建）** | 机制无可疑（两处出水口都记 `pins_before=239 → pins_after=1`、`replica_cells=10`）；`clk_fpga_0` setup 1.850→**2.104**，正是这一刀瞄准的那一格 | **四格跌**：`clkout0_1` 3.630→3.353、`sys_clk` 14.876→14.815、`eth_rxc` setup 0.739→**0.615**（全设计绝对最紧那一格）、`eth_rxc` hold 0.052→**0.044**（全设计最薄那一格）；代价 +10 只 FF（端点 +10 == replica 10 == 寄存器 +10 闭合） | 起飞前预登记在 `build/r117b_chain.sh` 头部的 A1..A5，其中 A2/A3 是严格口径"rel_margin 一格不许变小"；`noise_ns=0.000` | **生效了，但代价落在最紧的两个域上** —— 与 V11/V12 同一个形状。`build/timing_roster_diff.sh` 的 D3（25 % 门槛）对同一份数据给 `result=GREEN`：两把尺子判语相反**没有靠改宽任何一方来消除**，而是把严格那把独立成可指路的件（#328），交付承诺按它判。按 H7 回滚，钩子与数都留在树里、件不删 | `build/r117_verdict_declined.txt`；`report/timing/round_r117.md`；`build/evidence/r117_roster_diff_vs_r114.txt`；`report/log/issues.md` #319/#320/#327/#328 |
| V18 | **把 RGMII 窗绑进正式构建（r116 那一刀的另一半）** | 债真的清了半边：未约束输入端口 5→0、`io_unconstrained_ports` 11→6；`Checks found` 446→441、TIMING-18 7→2；其余三域 setup 变好或持平、四域 hold 一格不动、资源逐字中性、松台账 0 条 | 发布门四条硬项机械判红：WNS **−0.846**、失败 setup 端点 **5**、WHS **−0.870**、失败 hold 端点 **5**（`build/r116_gates.txt:10-13`）；`GATES: 有红项（判定 24 项）—— 不采纳，保留上一版` | 门禁 24 项（阈值一个字没动过）；采纳规则事前写在 `build/r116_batch_plan.md` | 处置**不是改门**、也不是删约束：默认不加载、原件与全部证明留在 `src/constraints/r116_rgmii_input_window.xdc`，`VP_R116_IO_WINDOW=1` 一条命令复现。相对 r114 这**不是放宽**（r114 本来也没有它，`loosen_ledger.tsv` 仍 0 条）。代价要一起念：那 5 个收端点回到"没检查"状态，而**没检查 ≠ 满足**（H5） | `report/timing/round_r117.md` §〇；`report/timing/round_r118.md` §一；`report/timing/debt_ledger.md` §2 追加节；`build/r116_gates.txt` |
| V19 | **把 HDMI 源端 TP1 的 skew 数写成 `set_output_delay` 窗（r119）** | 窗真的挂上了（`Path Group` 从 `(none)` 变成有钟） | 互对 −3.482/−3.458/−3.474 ns、参考钟版 −4.897/−4.873/−4.890 ns ⇒ 立刻造违例；另一件是 `.xdc` 里写 Tcl 守卫会被解析器整块跳过（`rc=0` 但守卫没执行） | `build/r119_window_check.mjs` 的 `--self` 六条能红的对照 + `report/log/issues.md` #335 的量纲判据 | 这是**记在约束侧的量纲错**，不是设计的时序债 ⇒ **不许**靠放宽窗把它变绿；换成同量纲的问法（pin-to-pin 到达离散）后成品判 10 项红 0，但那两笔新债（板级走线离散、眼图/抖动/占空比/沿）不能用"窗已过"来抵 | `report/timing/debt_ledger.md` 2026-10-04 09:4x 追加节；`build/evidence/r119_xdc_loads_probe3.txt`、`_probe4_pinclk.txt`、`r119_window_check.txt` |
| V20 | **`#179`：`icmp_rx` 校验和累加器那一族**（候选，未开刀） | 量过的上限是"收益上限低"：该路 route 占 **70.5 %** | 未付代价（判死在候选阶段） | §3 的候选筛选（route 主导 + 级数已经很低 ⇒ 拆逻辑救不了） | "明确不做"的一条，与 `#141`（当时指 BRAM 换 setup 那一笔）、`#105` 尾账并列写在同一行，防下一个人再花构建轮 | `report/timing_global.md` §3 末行；`report/log/issues.md` #249 尾、第 11273 行 |
| V21 | **r110 刀 4①（独热化降扇出）与 r112 刀 B（校验和累加器 32→20 位）** | r110：`fo=316` 那根网本轮不存在、`rows_hit*/CE` 作最差终点 0 次 ⇒ 抓手判据**达成**；r112 刀 B：`check_buffer` 一族改前 5 块 → 改后 0 块 | r110：出现一个 **−243 LUT / −8 FF** 的待解释量，而 `build/utilization.rpt` 是扁平汇总没有逐层实例行 ⇒ 归不到模块；r112 刀 B：同轮 `rows_hit` 族从 >1.174 掉到 0.445，净账 +26 LUT/+34 FF（OOC 两腿相减闭合） | 规矩 46"归属句要有凭据"（资源侧同样适用）+ 规矩 35 | r110：**不采纳、不刷板**，`git checkout --` 把首页 30 处改动复原（一提交 `metric` 就会在 HEAD 上判红）；r112：刀 B 记为"同族抓手成立、设计余量未抬"，退刀要再付一整轮换**另一条路**的旧数 ⇒ 带两刀采纳，但代价与不兑现一起登记 | `report/log/issues.md` #246/#250/#253/#254/#255；`build/evidence/r110_attrib.txt`、`r112_verdict.txt` |

## 4. 采纳的刀与它们的代价（每条同样是收益 + 代价）

| 刀 | 收益（有件的） | 代价（同件或另一份件的） | 为什么仍选择它 | 凭据 |
| --- | --- | --- | --- | --- |
| #141 三处 16 位减法提前一拍寄存（r104） | `icmp_tx` 那一族从全设计最差位上消失；次差那族余量为正（"没退回上一次的失败"，不是"改进"） | **Slice 寄存器 +48**（8079→8127），LUT 只 +1；隔离滚与正式滚给出的代价**一致** | 触发器不是本设计的压缩点（7.70 %），而 `eth_rxc` 是全设计最紧的域；两次独立构建同一代价 ⇒ 归因清楚 | `report/optimization_log.md` 第 1037–1059 行；`build/r104_gates.txt:16`；`build/evidence/r105_ab_rolls.txt` |
| r107 行覆盖位图分 5 组 | 目标族同端点对夹逼 0.723→**2.006 ns**，该族退出最差 8 条 | Slice 寄存器 **+7**；LUT 与 r106 逐字相同；BRAM/DSP 不动 | 这是"动的就是它瞄准的那一条"的第一次；等价性由逐拍台架 + 一条**错组变异判红**撑着 | `report/log/issues.md` #230；`build/evidence/r107_rowok_bank_equiv.txt` |
| r108 校验和摊成两拍各 5 项 | 同端点对 0.725→**1.081 ns** | **全局 WHS 0.050→0.035**（同一格目的地，源换成 `rgray_s1_reg[7]`，uncertainty 0.800 是自加严口径）；该状态多占一拍 | 换来的是"极致位置"被量出来：收包域 setup 由钟树插入延迟定死 ⇒ 后续不再在这类锥上花构建轮 | `report/log/issues.md` #231 |
| r112 两刀（武装门 + 累加器 32→20 位） | 目标 (b) 的修复在刀 A；刀 B 同族抓手成立 | **净 +26 LUT / +34 FF**（−40 换 +66，逐层相减闭合到个位）；同轮 `rows_hit` 族落到 0.445 | 0.445 ns 仍是 MET、失败端点 0；退刀 B 要再付一整轮换另一条路的旧数 | `report/log/issues.md` #250/#254/#255 |
| r113 `hb_gone` 声明上电初值 | 八个 (域,类型) 对逐位相同 ⇒ **功能修复、时序中性**；位流 `897fa9d93956`→`b94f4da6cdff` | 无资源与告警代价（综合告警名册差分为空） | 代价为零但修的是"上电那一度"这个真实缺陷；`ASYNC_REG` 与初值是两笔不同的账 | `report/timing_global.md` §2b；`report/log/issues.md` #261/#292 |
| r114 格雷码 `ASYNC_REG` + 初值 | `u_cdc` 下带属性 FF **0→56 颗**；名册 16 对六条全绿；资源逐字中性 | `clkout0_1` setup 相对余量掉 **18.8 %**、`clk_fpga_0` hold 掉 **5.4 %**（都在预登记 25 % 门槛内，但要念出来）；**TIMING-10 一条没少** ⇒ 那个计数不是属性落地与否的代理 | 结构账变干净（同步器对上了属性），头条那 +0.294 ns **不记在本刀名下** | `report/log/issues.md` #290/#293/#294 |
| r116/r118 `IDELAY_VALUE` 26→31 | 收口到达窗的最差档 −1.185→**−0.870**（+0.315 ns，同一份 DCP、同一把尺子）；片内名册 8 对逐位不劣化 | **片内名册这一侧没有 slack 收益**（8 对逐位与 r114 相同；τ 只动 I/O 单元抽头）；窗那半被退回 ⇒ 那 5 个端点回到未检查 | 这条的判据本来就不是 WNS（规矩 35）；r118 顺带交付的是**放置与布线可复现** | `report/timing/round_r118.md` §一/§四；`build/evidence/r118_strict_b1.txt`；`report/timing/cut_ledger.tsv` C8 行 |
| r92 #57 采样钟进 BUFG | 最差那族 hold 的偏斜 **+1.616 ns → 同树内 0.013–0.349 ns**（`BUFIO` 用量 1→**0**，结构判据） | WHS 数字没变好（+0.051→+0.037，最差挪到 100 MHz 域）；LUT −7、`IDELAY_VALUE` 15→26 | 把"每次重建掷 ±1 ps 硬币"这个机制**消除**了；把 +0.051→+0.037 念成退步和念成"改结构没用"都是错的 | `report/optimization_log.md` 第 709–746 行 |

## 5. 资源代价与性能收益的权衡判断（赛题 3.3.4 的考察点）

这一节是判断，不是数字罗列。三条判断都用上面表里已经摆出的数。

**判断 1（否决方向，r90）**：拆三块帧缓存省的是 140 片里的 **5 片 RAMB36**，
而 BRAM 在拆之前（67.86 %）和拆之后（64.64 %）**都不在压缩点上**；付出的是全设计最快那个域
（125 MHz）的 setup 余量 **6.5 % → 2.3 %**，而那个域同时也是保持时间最薄的一格。
⇒ **在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的**。同一轮里
"换 FF 买级数"（#150 那一刀）是划算的并已证明，"换 BRAM 削 setup" 量过就放下 ——
这两个方向出自**同一次测量**，所以差别不是偏好而是余量落在哪一列。

**判断 2（否决方向，r114 V11 / r117 V17）**：两把复制驱动的刀都**机制成立、目标格变好**
（+0.456 ns / +0.254 ns），资源代价分别只有 +31 LUT 与 +10 FF —— 光看这两项，两把都该收。
它们被否掉的唯一理由是**代价落在最紧的域上**：V11 削掉 `eth_rxc` hold 相对余量的 29 %，
V17 同时削掉 `eth_rxc` setup（全设计绝对最紧那一格）与 `eth_rxc` hold（全设计最薄那一格）。
⇒ 我的判断是：**在这颗器件这一版结构下，"资源便宜"不是采纳理由，"谁的余量被扣了"才是。**
尤其当那个域的外部窗口还没有被约束建全（V9 量到一挂真窗它就是 −2.885 ns），
在它身上再买三成相对余量等于把已经结掉的旧账重新请回来。

**判断 3（采纳方向，r104 / r107 / r113 / r114）**：这四把共同形状是
**在被扣的那一列本来就不紧张的地方付出代价**（触发器 7.70 %、LUT 26.61 %、BRAM/DSP 不动、
综合告警名册差分为空），换来的是**最差格的主人被换掉**或**结构账变干净**。
⇒ 在"资源有余量 + 代价可逐层归属 + 名册差分不过线"三个条件同时成立时，
即便头条 WNS 变好也不能写成本刀的收益（r114 明写"收益记给结构账，不记给 slack"），
但只要没有域被挤坏，就值得进发布物。

**判断 4（设计层面的长期取舍）**：`report_methodology` 的 **SYNTH-5 = 336 条**
（"因为时序约束才映射成分布式 RAM"）与 `build/utilization.rpt` 的 **LUT as Memory 4185**
是同一个选择的直接代价：窗口级行缓与 `raw_line_delay` 走 LUT-RAM，**换来 BRAM 余量**
（帧缓存 64-bit 宽 + 乒乓两块，是 BRAM 的主要去向），代价是 336 条约束驱动的分布式 RAM 推断。
这也是一笔"资源换性能"，只是它发生在架构选择上而不是某一轮切割上 ——
口径与数字见 `report/04-resources.md`。

## 6. 缺证据的轮次清单（不用相邻轮次的数字顶替）

| 项 | 状态 | 缺什么 |
| --- | --- | --- |
| r13…r58 的门禁项数与首页可对齐读数 | **不列**（不是没做，是跨口径） | `report/optimization_log.md` 第 607–609 行自己写明：早期轮次用另一套文件名（`build/gates_rNN.txt`）且**门禁项本身一路在长**，跨口径拼接会得到假趋势；要补得先写一张"哪些项在哪些轮存在"的映射表 |
| r87 的门禁 | NOT_MEASURED | 该节自述"这一行只有报告数"，`build/r87_timing_summary.rpt`/`r87_utilization.rpt` 有，门禁件没有 |
| r99 的 `sys_clk` 逐域 hold | NOT_MEASURED | 那一轮的表只给"收包 / 100 MHz / 显示"三个 setup 数与全设计 WHS，未逐域列 hold |
| r105、r111 的构建侧资源与告警 | NOT_MEASURED | 两轮都不是构建轮（r105 是隔离 A/B 滚、r111 是 JTAG 只读回读）；`build/` 里也没有 `r105_gates.txt`/`r111_gates.txt` |
| r115 的正式资源行 | NOT_MEASURED | 本轮 0 采纳，没有正式构建可量 |
| r117 正式构建的资源行 | NOT_MEASURED | 判负未采纳 ⇒ 只有快车道滚 B 的 +10 FF 有件；正式资源行未进发布物也不进本表 |
| r119 的名册与资源 | NOT_MEASURED | 只读探针 + 默认关的候选件，未做过一次"带窗量名册"的构建（`report/timing/debt_ledger.md` 09:1x 追加节明写还欠这一次） |
| 板级 `drop_words` 在 r118 的三个字段 | **NOT_MEASURED**（件里显式打 `?`） | `pkt_err=? frames_bad=? drop_seen=?`（`report/log/issues.md` #318 把读不出来的字段显式化），不许写成 0，也不许拿 r116 那两次带流读数替它答 |

## 7. 本节里"到极限"这句话允许的完整形状

只在指得出件的范围里说（`report/timing_global.md` §9 末与 `report/timing/round_r118.md` §四给的是同一段）：
在**不动架构（捕获钟拓扑）也不动功能（OSD 锥）**的前提下，r118 名册上的每一格要么已为正、
要么被证明了关不掉；非放宽的物理杠杆（策略扫描、同 DCP 重滚、Pblock、BRAM 换 setup、
复制广播网 C9、灰码 `ASYNC_REG`、τ 扫档）已逐把量过并给出赢或判负。
这句话里**没有**"每颗时钟都被证明已到物理极限"这一项：`clkfbout`/`clkfbout_1`/`clkout1_1`/`clkout2`
四行在名册里是 `NOWRITE`/`NA`，它们的状态是"没有同沿路径行"，不是"已被证明关不掉"
（`report/timing/debt_ledger.md` §1 钉死的读法）。

仍然**不许**写的三句（件已在 §2/§3 点名）：
① "板上真实 hold 差额就是 −0.870"（窗模型自身有 `TskewR` 混行的残余风险）；
② "换短钟也关不掉"（BUFIO 的快角 DCD 未实测，#323 只到"没筛出来"）；
③ "收口 I/O 已通过时序检查"（r118 没有窗，那 5 个端点是未检查状态，未检查 ≠ 满足）。

## 8. 与既有章节的差异清单（两处不同值，以证据文件为准，不自行取舍）

| # | 我的读数（来自证据文件） | 另一处的读数 | 处置 |
| --- | --- | --- | --- |
| D1 | `data/metrics.csv` 第 14 行「门禁自检项,自检,**22**,项」 | `build/r118_gates.txt:53` 与 `build/r116_gates.txt:53` 都打「判定 **24** 项、未判 0 项」；`report/06-validation.md` §3 亦写 24 | **以门禁件为准**（24）。metrics.csv 那 22 是 r106 时代的行没跟着改口（`report/log/issues.md` #229 记的就是这个"两个自洽解"陷阱）；metrics.csv 属禁改文件，本节不改它 |
| D2 | `data/metrics.csv` 第 15 行「整屏逐像素判据,核心,**141**,条」，其测量条件列自述钉的是 `top_md5=2bf2ceeede07` | `build/tb_v98_report.txt` 盘上那份：`^PASS` **161** 行、`^FAIL` **1** 行、头部 `top_md5=56c269602e18`（本次 `grep -c` 实数）；`report/06-validation.md` §2 已明写"计数跨轮不可比，以当前件为准" | **以当前件为准**（161/1，且两者都不同源 ⇒ 不可比）。本节不把它写成收益或退步 |
| D3 | `build/methodology.rpt:26,30-36`（r118 盘上那份）：`Checks found: 446`、**7 个规则类** | `report/timing/round_r116.md` V5 说 r116 那份是"类仍是 **3 类**（TIMING-9/10/18），实例 446→**441**" | 两句话不冲突但**口径不同**（"3 类"只数 TIMING-* 那一族）。本节按盘上件念 7 类/446，并保留 r116 的 441/2 属带窗那一版 |
| D4 | `report/timing/debt_ledger.md` 2026-10-04 08:5x 追加节：拿接收端窗口去约束发送脚"方向是错的" | `report/timing_global.md` §4 与 §6.4 那两处仍写"要外部 DVI/HDMI **窗口数**"、"要面板/接收端的手册窗口数" | **以更晚的追加节为准**（源端 TP1 / HDMI CTS，件 `report/io/hdmi_cts_source_window.md`）。本节只引路径不重述其数 |
| D5 | `build/evidence/r117_after.txt:3` 头部位流身份写 `bb2fb707aebc`（那是 r116 的位流） | `build/evidence/r117_bit_md5.txt` 与 `build/r117_verdict_declined.txt` 都给 r117 = `beda9298331d` | **以轮次专属件为准**（beda9298331d）。差因由 `report/log/issues.md` #332 记录："r118 那两支提交只带了文档，bit/xsa/`build/*.rpt` 全悬在工作区"，探针读的是当时的 `build/system.bit`。本节引用 r117 读数时不引用那份头部 |
| D6 | `build/power.rpt:39` 打 `Max Ambient (C) 57.4` | `data/metrics.csv` 第 28 行的测量条件列写 "Max Ambient **57.5** ℃" | **以 power.rpt 为准**（57.4）。metrics.csv 不改，列为差异 |
| D7 | `grep -n` 当前 `build/power.rpt` 给 `Effective TJA :38`、`Max Ambient :39`、`Junction :40`、`Confidence :41` | `report/measurements.md` §1 的同几格引作 `power.rpt:37-38` 与 `:40` | **数值两边相同**，只有行号漂移 1 行 ⇒ 不改数、不改判据，登记后由作者决定统一哪一侧的引用（与 `data/metrics.csv` 的 G3 是同一批，见 `report/measurements.md` §5） |

## 9. 本节依据的产物（一次找齐）

`report/timing/README.md`、`report/timing/roster_baseline.tsv`、`report/timing/roster_round115.tsv`、
`report/timing/roster_round116.tsv`、`report/timing/debt_ledger.md`、`report/timing/round_r116.md`、
`report/timing/round_r117.md`、`report/timing/round_r118.md`、`report/timing/cut_ledger.tsv`、
`report/timing/loosen_ledger.tsv`、`report/timing/gates_g1_g12.md`、`report/timing/uncertainty_hold_ab.md`、
`report/run-queue.md`；
`build/evidence/`（`r105_ab_rolls.txt`、`r107_rowok_bank_equiv.txt`、`r108_csum_diff.txt`、
`r109_clk01_{before,after}.txt`、`r110_attrib.txt`、`r112_verdict.txt`、`r112_util_attrib.txt`、
`r113_roll_abc_verdict.txt`、`r113_roster_diff.txt`、`r114_after.txt`、`r114_after_roster_probefmt.txt`、
`r114_mf/verdict.txt`、`r115_base/methodology.txt`、`r115_fanout_ab/verdict_header.txt`、
`r116_after.txt`、`r116_after_roster.txt`、`r116_roster_diff.txt`、`r117_d0/`、`r117_repl3/b_console.txt`、
`r117_after.txt`、`r117_after_roster_probefmt.txt`、`r117_bit_md5.txt`、`r118_after.txt`、
`r118_after_roster_probefmt.txt`、`r118_strict_b1.txt`、`r118_bit_md5.txt`、`r119_window_check.txt`、
`r119_xdc_loads_probe3.txt`、`r119_xdc_loads_probe4_pinclk.txt`、`r89exp_timing_summary.rpt`、
`r116_bit/`、`r114_bit/`）；
`build/{r103,r104,r106,r107,r108,r109,r110,r112,r113,r114,r116,r118}_gates.txt`、
`build/r117_verdict_declined.txt`、`build/r118_verdict.txt`、
`build/{utilization,timing_summary,methodology,power,clock_util,cdc,setup_paths,hold_paths}.rpt`；
`report/timing_global.md`、`report/optimization_log.md`、`report/log/issues.md`、
`report/log/overnight_log.md`、`data/metrics.csv`；
`report/04-resources.md`、`report/05-timing.md`、`report/06-validation.md`（口径对齐，只引不改）。

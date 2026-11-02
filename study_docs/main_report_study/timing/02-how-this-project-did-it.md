# 本项目时序优化实录：怎么开始、每一步看到什么数、哪些判负退回

> 这是"时序优化"三篇的第三篇。第 1 篇讲概念，第 2 篇讲优先级怎么判，这一篇只讲一件事：
> 这套 Zynq7020 视频系统的时序，一步一步是怎么量出来的、量到什么、据此判了什么。
> 全篇只搬运与叙述，不重算、不换算、不补数；每一个数字后面紧跟它的凭据文件。
> 读之前不需要任何时序背景，需要的是肯把每一件原始报告翻到那一行。

## 0. 这一篇的数字从哪儿来

点名这一篇真正打开读过、并且直接引用其读数的件。凡下面出现的数，都能在这些件里找到；找不到的一律写"没量过"，不写推测值。

| 件 | 它是什么 | 这一篇从它取什么 |
| --- | --- | --- |
| `build/timing_summary.rpt` | 布线后的时序汇总（工具自己落的那份） | 端点总数、失败端点数、WNS/WHS/WPWS、"约束全满足"那一行 |
| `build/evidence/r124_tiers_ladder.txt`、`report/timing/roster_baseline.tsv` | 只读探针出的**逐时钟前 12 档阶梯**与逐时钟**名册**的正式形状（13 列） | 档位数、每档 slack、起点/终点、级数、route 占比、hold 首末档、各域端点数与相对余量 |
| `build/tcl/r124_tiers_probe.tcl`、`build/tcl/probe_timing_roster.tcl`、`build/timing_roster_diff.sh` | 生成名册与差分的三支脚本 | `-nworst 1 -max_paths 12` 的写法、distinct 反读的实现、六条判据 D1..D6、口径不一致判 REFUSE |
| `build/r118_gates.txt`、`build/evidence/r118_board/gatesc_summary.txt`、`build/r118_verdict.txt`、`build/evidence/r118_strict_b1.txt` | 发布门输出、两跑对账、那一次采纳的判定件 | 判定项数、绿/红计数、逐字节一致、身份 md5、B1/B2/B3 的实测结论 |
| `report/timing/round_r118.md`、`round_r117.md`、`round_r116.md`、`gates_g1_g12.md` | 三页逐轮结果页与一张判定表 | 每轮"带什么/不带什么"、判据登记原文、否决理由、"红在哪、为什么红、哪些是债哪些是刀" |
| `report/timing/rgmii_window_model.md`、`eth_rxc_partition_options.md` | RGMII 收口到达窗的拆解（含 0…31 全档扫描）、一个域四种改法的逐条判断 | 两条实测直线、交点、不相交区间、角间差不等式、归因结论、收益上界、定型理由 |
| `report/timing/debt_ledger.md`、`cut_ledger.tsv`、`loosen_ledger.tsv` | 三份台账：欠什么、打算动什么、松过什么 | 属性落地计数、跨域界缺口、"这一刀没量过"的凭据 |
| `report/optimization_log.md`、`report/40-optimization.md`、`report/timing_global.md` | 逐批施工记录、逐批对照表、全局名册方法与工具账 | 每把刀的改前/改后读数与代价、结论、指路；报告形状实测、扇出读法、两次单变量对照 |
| `src/constraints/rk_zynq7020.xdc`、`clock_groups_impl.xdc`、`r116_rgmii_input_window.xdc` | 约束面（两文件现行 + 一份被退回的候选） | 不确定度带那一行、异步时钟组的分组、窗件的原文与被退回状态 |
| `build/clock_util.rpt`、`hold_paths.rpt`、`clock_uncertainty.rpt`、`route_status.rpt`、`utilization.rpt`、`methodology.rpt` | 构建顺带落下的报告 | `BUFIO` 用量、时钟偏斜逐项、告警计数、资源行 |
| `data/metrics.csv`、`report/technical-document.md` | 指标表与交付文档 | 共用条件、台架耗时、五域口径 |

三条贯穿全篇的读法，后面每一步都要用到：

1. **WNS 的绝对差既不算收益也不算损失。** 全局最差那一条换了主人（换了模块、甚至换了时钟域），相减得到的数就没有意义；能主张的只有"同一个域自己那条锥动没动"，而且别的域不许变差（`report/40-optimization.md` §1 把这条写成"贯穿全表的一条读法"，`build/timing_roster_diff.sh:9-13` 的头部注释是同一件事）。
2. **读不到输入写"没量过"，不写"通过"也不写"失败"。** 逐批表里这一格一律填 `NOT_MEASURED`（`report/40-optimization.md` §2 的列规则与 §6 的缺证据清单）。
3. **判负要写成判负。** 每一条否决都要写"量到什么、因此判它不行"，不许写成"做了但没测"，也不许写成成功（`report/timing/gates_g1_g12.md` 的 G11/G12 与 `report/40-optimization.md` §3 那 21 条）。

---

## 1. 起点：第一次做的事不是优化，是把读数口径立起来

拿到手的那一版是"跑得通但时序紧"：功能上板验过、屏上有画面、串口读得回来，
时序上四个域全部为零违例，但最紧的那个域余量只有 0.7 ns 量级。这种状态下最容易犯的错，
是顺手挑一条最差路径去削它——削完之后不知道自己是赚是赔，因为参照系还没立。

所以第一份产出的不是 RTL 改动，而是一张五域表和四条口径。

### 1.1 五域清单与那一版的读数

| 域 | 频率 | 周期 ns | 该域端点数 | setup WNS ns | hold WHS ns | 凭据 |
| --- | --- | --- | --- | --- | --- | --- |
| `sys_clk` | 50 MHz | 20.000 | 323 | 14.876 | 0.222 | `build/evidence/r124_tiers_ladder.txt` 第 68–80 行；端点数 `report/timing/roster_baseline.tsv` 末行 |
| `clk_fpga_0` | 100 MHz | 10.000 | 15,721 | 1.850 | 0.053 | 同上第 35–49 行；端点数 `roster_baseline.tsv` 第 6 行 |
| `clkout0_1` | 50 MHz | 20.000 | 30,179 | 3.630 | 0.059 | 同上第 52–66 行；端点数 `roster_baseline.tsv` 第 9 行 |
| `eth_rxc` | 125 MHz | 8.000 | 4,835 | 0.739 | 0.052 | 同上第 17–33 行；端点数 `roster_baseline.tsv` 第 12 行 |
| `clkout1_1` | 250 MHz | 4.000 | 无 intra 路径行 | 不纳检 | — | `report/timing/debt_ledger.md` §1 那一行；`build/r118_gates.txt:24-32` 该域打 `NAns` |

设计级那三行是这件事的锚点，全部出自同一份件的同一张表：

```
build/timing_summary.rpt:149   WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) ...
build/timing_summary.rpt:151     0.739   0.000                      0               51135   0.052  ...
build/timing_summary.rpt:154 All user specified timing constraints are met.
```

也就是：端点总数 **51,135**、失败 setup 端点 **0**、失败 hold 端点 **0**（同一行右半段）、
脉冲宽度检查的端点总数 12,634 与失败 0（同一行末段）。这四串数字后来被门禁原样引用
（`build/r118_gates.txt:10-13` 与 `:53` 那句"端点总数 51135"）。

把五域摊开而不是只念 WNS，理由很实在：`report/timing/eth_rxc_partition_options.md` §7 那句
"这份表不产生采纳结论：它只把'后面还有几档、每一档属于哪一族'从推断变成有件的事实"。

### 1.2 为什么要先说"四个域里只有一个域有 hold 不确定度带"

全仓现行约束里，`set_clock_uncertainty` 只有一条，而且只加在 hold 上、只加在一个对象上：

```
src/constraints/rk_zynq7020.xdc:50
set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]
```

后果是：`eth_rxc` 那一列 WHS 是**被扣掉 0.800 ns 之后**的数，另外三列 WHS 没有任何带子。
于是四个 WHS 数不是四把一样的尺子量出来的，**跨域比大小没有意义**。这件事必须在任何人
拿"0.052 比 0.222 薄"得出结论之前说清楚，因为它是那条结论的直接否定。

这不是理论担忧，它被量过一次：给另外三个域也统一挂上 0.800 ns 的 hold 带之后，设计级
WHS 从 **0.053 变成 −0.747**、失败 hold 端点 **25,742**，而 WPWS 0.264 不变
（`report/40-optimization.md` §3 的 V13 行与 `report/timing/cut_ledger.tsv` 的 C2 行；
等式 `−0.747 = 0.053 − 0.800` 与逐域读数的对照件是 `report/timing/uncertainty_hold_ab.md`）。
那次对照的定位被写成一句话：**这是测量，不是采纳**——方向是加严，本来就不产收益，
它买到的是"欠账显形"。同一件事还留下一条纪律：交付文档里"四域 hold 全为正"那句
必须限定成"在现行约束集下为真"。

顺带一条同源的方法教训，写在同一份约束文件的注释里（`src/constraints/rk_zynq7020.xdc:43-45`）：
把 `get_clocks` 取不到的名字并进同一条命令，会让**整条命令空转**、连带把能取到的那几组一起废掉，
而现场只留一句 warning。同名风险在加 MMCM 或重新源化时钟之后更常见——
`set_clock_uncertainty`、`clock_groups`、`input_delay` 都可能不再命中任何时钟名而工具不报错。
所以读任何 slack 之前，先按名字复查约束还在不在（那次副本树对照把它量成了硬读数：
+0.759 ns 里约 0.67 ns 是覆盖面丢失换来的，见 `report/timing/gates_g1_g12.md` 的 C3 行）。

### 1.3 成本表：先量什么，再动什么

四条实测成本决定了后面所有动作的排序，每一格都点名件：

| 动作 | 实测耗时 | 凭据 |
| --- | --- | --- |
| 一条链跑完：建工程→综合→实现→出位流→落报告→名册判完 | 起飞 04:18:25、B1 判完 04:38:55，同一份件里两个时刻；位流与报告时间戳 04:36:56 / 04:37:30 | `report/timing/round_r118.md` 首行与 §四首行；`build/r118_gates.txt:2` |
| **快车道**：不综合、不改 RTL，只从已实现的 `impl_1/*_opt.dcp` 重跑 place+route | 两次重跑合计约 13 分钟（place 每滚 1–2 分钟、route 每滚约 4 分钟）；单滚约 7–9 分钟 | 13 分钟那条出自 `report/timing_global.md` §4e 第三条"先在便宜的通道上量"；单滚区间出自 `report/study/timing/90-numbers-index.md` §2 |
| 整屏顶层台架一轮 | 约 108 分钟 | `data/metrics.csv` "整屏逐像素判据"那一行的测量条件列 |
| 一次**不开设计**的 `help <命令名>` 批探测（用来确认某条报告命令有哪些选项） | 约 40 秒 | `report/timing_global.md` §5："问出这件事只花 40 秒" |

快车道那一条还附赠一件更值钱的事实：**同一棵树上重跑能逐位复现正式构建的读数**
（`report/timing/round_r118.md` §四：`IDELAY_VALUE` 只动 I/O 单元抽头，片内名册 8 对逐位复现；
`report/timing/gates_g1_g12.md` 的反证段落：不带任何变量的空白滚，名册与基线逐格相同，
`noise_ns = 0.000`）。放置既然确定性，"**两次构建差了 0.4 ns**"这类跨构建差值就不能当收益——
这条纪律后来把好几把本来要开的刀挡在了立案阶段。

---

## 2. 逐时钟名册是怎么建的

### 2.1 要解决的问题：只看头条会一直看见同一张脸

`build/timing_roster_diff.sh:9-13` 的头部把动机写成两句：只把全设计最差的那条排第一，
每轮看到的都是同一个域，其它三个域是涨是跌没人念；"绝对差不算收益"那条规矩只挡住了"拿差值吹收益"，
没挡住"把一个域改坏了而头条没动"。于是名册判的不是 WNS，判的是**八个 (域,类型) 对各自的相对余量**。

### 2.2 每个域一条 12 档最差路径阶梯

出阶梯的脚本是 `build/tcl/r124_tiers_probe.tcl`（只读探针：`VP_TIERS_REPORT_ONLY=1`，
读已经 Complete 的 `impl_1`，不保存工程、不改任何 `.xdc` 内容）。它对四个域各跑两条命令：

```
build/tcl/r124_tiers_probe.tcl:110   report_timing -delay_type max -nworst 1 -max_paths 12 -from $cobj -to $cobj -file ...setup.rpt
build/tcl/r124_tiers_probe.tcl:112   report_timing -delay_type min -nworst 1 -max_paths 12 -from $cobj -to $cobj -file ...hold.rpt
```

`-from $c -to $c` 这个形状也不是随手写的：`build/tcl/probe_timing_roster.tcl:12-13` 记着
`-of_objects [get_clocks X]` 会**同时**拒绝 `-delay_type` 与 `-max_paths`（报 `[Vivado 12-1365]`），
能用的写法是 `-from`/`-to` 成对夹同一个时钟对象。

**参数坑在 `-nworst`。** 脚本自己把它写成注释：

```
build/tcl/r124_tiers_probe.tcl:108-109（逐字）
# -nworst 1 是这里的规矩（同 build/tcl/c2_scratch_probe.tcl:60）：nworst>1 会把同一个端点
# 的上升/下降沿组合念成好几条，看着像 12 档其实只有 1 档。
```

这个坑在现场是有实物的：同一支脚本第 83 行出汇总报告用的正是
`report_timing_summary -max_paths 12 -nworst 12`，而每域阶梯用的是 `-nworst 1 -max_paths 12`。
两份件的"12"不是同一个东西。`build/evidence/r124_tiers_ladder.txt:13-14` 把这条口径差异写死：

> `-nworst 1 -max_paths 12` ＝ 每个端点只取最差一条、共取 12 个端点 ⇒ 每行是一个**不同端点**；
> 另一次数的是端点重数（0.739×5 之类），两者不矛盾：同一档的多个位属于同一只锥。

端点重数那一组的实物在 `report/timing/cut_ledger.tsv` 的 C10 行：档位分布
0.739×5 / 0.873×5 / 0.961×5，全部出自同一只 `u_icmp_tx/ip_head_reg[4][16]`。
**12 行可能只算 1 档**，说的就是这件事。

### 2.3 distinct 计数要从写出的文件里反读

参数写完不等于档位到手，必须回到文件里数。`build/tcl/r124_tiers_probe.tcl:84-102` 那段
`tiers_digest` 干的就是这件事：把每个 `Slack (MET|VIOLATED) : N ns` 行计数，然后打印

```
TIERS $tag distinct=$n first=[lindex $sl 0] last=[lindex $sl end]
```

`$n == 0` 时打印 `distinct=0 (no path block parsed)`，即"这一路根本没解析到路径块"，
而不是把空集当成 0 档通过。**反读的价值在于它与请求参数无关**：如果 `-nworst` 用错，
`$n` 会与预期不符，当场露出来。

### 2.4 两把名册必须同生成器同口径，否则拒绝比对

差分尺是 `build/timing_roster_diff.sh`。它的判据六条（`report/timing_global.md` §5 原文）：

| 判据 | 内容 |
| --- | --- |
| D1 | 没有任何域从 MET 掉进违例 |
| D2 | 配上的 (域,类型) 对数 ≥ 8（数得出才许出结论） |
| D3 | 没有任何域的**相对余量**掉过 25 %（挡住"别的域被改了而头条没动"） |
| D4 | setup 与 hold 两个维度必须在同一条判据里被配上 |
| D5 | 改后名册不许有空读数 |
| D6 | 扇出清单至少有一行（不然抓手名册是空的） |

而**口径闸门在 slack 之前**：脚本 `:82-85` 与 `:105-139` 写的是"B 侧扇出节整节缺失
（= 另一把生成器）⇒ REFUSE"、"A 里的钟在 B 里消失 = 真口径不一致 ⇒ REFUSE"、
"两侧都 NOWRITE 不许当成丢读数"。同一份脚本的 `:138` 把这件事讲成一句话：
不同口径相减出来的不是代价，是尺子断了。REFUSE 与 RED 是两种判定，退出码也不同
（`:5` 写 `2=REFUSE`）。`report/40-optimization.md` §1 的 B-main 那一行也点名这条纪律：
对照侧必须同生成器，混口径会被判 REFUSE。

改前那一版为什么不能直接拿归档报告凑？因为 `impl_1/*_routed.dcp` 一次构建就被覆盖
（`report/timing_global.md` §5 记过一次这类亏：改前那份 dcp 被下一次构建覆盖了，只能从报告重建），
所以改前侧从归档的 `timing_summary.rpt`
的 Intra Clock Table 用 `build/roster_from_summary.sh` 重建，改后侧从 dcp 直接问探针。
两侧形状因此天然不同——这恰恰是"同一个文件读两遍"的反证。

### 2.5 名册长什么样（两张真表）

**表 A：逐域名册的列与四域实数**（列名与顺序照 `report/timing/roster_baseline.tsv`，数字同源）

| clock | period_ns | wns_setup | tns_setup | nfp_setup | whs_hold | nfp_hold | rel_margin_setup | rel_margin_hold | io_unconstrained_ports | intra_endpoint_total |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `clk_fpga_0` | 10 | 1.850 | 0.000 | 0 | 0.053 | 0 | 0.185000 | 0.005300 | 11 | 15721 |
| `clkout0_1` | 20 | 3.630 | 0.000 | 0 | 0.059 | 0 | 0.181500 | 0.002950 | 11 | 30179 |
| `eth_rxc` | 8 | 0.739 | 0.000 | 0 | 0.052 | 0 | 0.092375 | 0.006500 | 11 | 4835 |
| `sys_clk` | 20 | 14.876 | 0.000 | 0 | 0.222 | 0 | 0.743800 | 0.011100 | 11 | 323 |

同一份件头部还钉着两行口径：`rel_margin_* = wns_* / period_ns`；
`io_unconstrained_ports` 是 `check_timing` 的 HIGH 两类之和，单位是**端口对象**（输入 5 + 输出 6 = 11）。
这两个单位差别后来救过一次错——`report/timing/debt_ledger.md` §6 明写
`report_methodology` 的 TIMING-18 有 7 条，那是 checks/pins 量纲，**与端口数永不相减**。
另外四行 `clkfbout` / `clkfbout_1` / `clkout1_1` / `clkout2` 在名册里是 `NA`，
`report/40-optimization.md` §7 把它的含义写死：状态是"没有同沿路径行"，**不是**"已被证明关不掉"。

**表 B：一个域的 12 档阶梯**（照 `build/evidence/r124_tiers_ladder.txt` 第 18–30 行原样，
`eth_rxc`，周期 8.000 ns，setup）

| 档 | slack | 终点 | 起点 | 数据路径 | 布线 | 布线占比 | 逻辑级数 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.739 ns | `check_buffer_reg[19]/D` | `u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C` | 7.066 ns | 4.130 ns | 58.4 % | 11 |
| 2 | 0.873 ns | `check_buffer_reg[17]/D` | 同上 | 7.036 ns | 4.127 ns | 58.7 % | 11 |
| 3 | 0.961 ns | `check_buffer_reg[18]/D` | 同上 | 6.866 ns | 3.871 ns | 56.4 % | 11 |
| 4 | 1.017 ns | `rows_hit_reg[10]/CE` | `u_eth/u_rx_par/p_eof_reg/C` | 6.649 ns | 5.663 ns | 85.2 % | 4 |
| 5 | 1.017 ns | `rows_hit_reg[11]/CE` | 同上 | 6.649 ns | 5.663 ns | 85.2 % | 4 |
| 6 | 1.017 ns | `rows_hit_reg[8]/CE` | 同上 | 6.649 ns | 5.663 ns | 85.2 % | 4 |
| 7 | 1.017 ns | `rows_hit_reg[9]/CE` | 同上 | 6.649 ns | 5.663 ns | 85.2 % | 4 |
| 8 | 1.019 ns | `rows_hit_reg[12]/CE` | 同上 | 6.648 ns | 5.662 ns | 85.2 % | 4 |
| 9 | 1.019 ns | `rows_hit_reg[13]/CE` | 同上 | 6.648 ns | 5.662 ns | 85.2 % | 4 |
| 10 | 1.019 ns | `rows_hit_reg[14]/CE` | 同上 | 6.648 ns | 5.662 ns | 85.2 % | 4 |
| 11 | 1.019 ns | `rows_hit_reg[15]/CE` | 同上 | 6.648 ns | 5.662 ns | 85.2 % | 4 |
| 12 | 1.041 ns | `rows_hit_reg[6]/CE` | 同上 | 6.623 ns | 5.637 ns | 85.1 % | 4 |

这张表读出来的不是"哪条最紧"，而是**第 4 到第 12 档全在同一族**——这句话后面第 5 节要用它做归因。
其余三域的首档形状同源同件：`clk_fpga_0` 第 1 档 1.850 ns、终点 `lo_reg_0_16/WEA[0]`、
起点 `u_pl/u_arb/owner_eth_reg/C`、route 93.6 %、级数 1（第 35–49 行，**12 档同一只起点**）；
`clkout0_1` 第 1 档 3.630 ns、22 级、route 59.2 %（第 52–65 行）；
`sys_clk` 第 1 档 14.876 ns、5 级、route 74.0 %（第 68–80 行）。
hold 只列首末两档，同一件第 83–89 行：`eth_rxc` 0.052→0.062、`clk_fpga_0` 0.053→0.077、
`sys_clk` 0.222→0.254、`clkout0_1` 0.059→0.075，紧跟一条注——只有 `eth_rxc` 有那条 0.800 带，
四列 hold 不可互比。

### 2.6 报告形状也是量出来的，不是猜的

这一段单独列，因为它是三次实际教训的汇总（全部在 `report/timing_global.md` §5）：

- `route_pct` 恒空：真实行里百分数在**括号内**（`Data Path Delay: 3.498ns (logic … route 2.843ns (81.275%))`），而原先的匹配模式要求 `ns` 后直接跟百分号。
- `get_nets` 认带 `[n]` 位下标的网名时，`[` `]` 是 GLOB 类字符：`rok4[51]_i_1_n_0` 这种最该被抓的广播网会被裸 pattern 判成不存在 ⇒ 集合空、假对照；一律换成 `-filter {NAME eq {…}}`。
- `report_design_analysis` 在本工具里**没有 `-fanout` 模式**（实测件 `build/evidence/r113_help_fanout_console.txt`），设计级高扇出名册只能用 `report_high_fanout_nets -file … -max_nets … -fanout_greater_than …`。前两版探针调了不存在的模式，`catch` 把错误吞了、报告文件没写、行数为 0，差分那侧只能判 D6 未通过。
- `route_status` 里没有"successful"这个词，它是一张净计数表（实物：`build/route_status.rpt` 给 `# of routable nets 20882` / `# of fully routed nets 20882` / `# of nets with routing errors 0`），所以判据写成"路由错误 0 且 全布 == 可布 且 > 0"（`report/timing/gates_g1_g12.md` 的 G5 行）。
- `report_methodology` 的计数只能取它的 SUMMARY 表并与 `Checks found:` 加总一致：件行 `build/evidence/r114_async_netlist_pre_console.txt:101` 打 `METH_SUMMARY checks_found=446`，七类相加闭合（分项 2+1+336+98+1+1+7 见 `report/timing/debt_ledger.md` §6）；整文件 `grep -o` 会把每类多数一遍。
- 这些都不许猜：一条 `help <命令名>` 的批探测只花 40 秒（§1.3），所以"形状先实测"没有成本借口。

---

## 3. 一次只改一个变量的对照法：九把刀，逐把写读数

下面每一条都按同一副骨架写：**改了什么 / 看到什么读数 / 判什么 / 凭据是哪份件 / 为什么不能念成别的**。所有"那一次对照"都指一份具体的件，不指轮次编号。

### 3.1 RGMII 采样钟并进同一棵 BUFG

- **改了什么**：`src/rtl/eth/rgmii_rx.v` 里删掉 `BUFIO`，5 个 IDDR 与下游 fabric 改吃同一只 BUFG
  （现行件第 3 行就是这句话：现在 5 个 IDDR 与下游 fabric 吃同一只 BUFG；那只缓冲在 `:51`，
  例化名 `BUFG_inst`）；同时 `IDELAY_VALUE` 从 15 调到 26。
- **看到什么读数**：最差那族 hold 的时钟偏斜 **+1.616 ns → 同树内 0.013–0.349 ns**。
  这两个数是两份件的原文：`src/constraints/rk_zynq7020.xdc:38` 写
  "起点 IDDR 走 BUFIO（SCD 3.171 ns），终点 fabric FF 走 BUFG（DCD 4.854 ns）⇒ 两棵时钟树差 1.616 ns"，
  同一行给出那条路的预算 8.000 ns 与数据路径 1.855 ns；改后的 0.013 ns 那一端读自
  `build/hold_paths.rpt` 的 `Clock Path Skew` 行（该件 20 条路里最小 0.013 ns、最大 0.259 ns），
  0.349 ns 那一端读自 `build/clock_uncertainty.rpt` 里那条 WHS 0.037 的路。
  结构侧的判据读数：`build/clock_util.rpt:45` 现在是 `| BUFIO | 0 | 16 |`——用量 1 → **0**。
- **判什么**：**采纳**，但收益记结构性，不记数字。WHS 反而没变好：+0.051 → **+0.037**，
  而且最差那一格挪到了 100 MHz 域（`report/40-optimization.md` §2 的采样钟那一行，
  同行给出逐域改后 setup/hold：`eth_rxc` +0.522/+0.049、`clkout0_1` +0.885/+0.048、
  `clk_fpga_0` +2.161/+0.037；资源 LUT 14351 / FF 8075 / BRAM 95 / DSP 19）。
- **为什么不能念成别的**：它消除的不是一个 ns，而是一个机制——`src/constraints/rk_zynq7020.xdc:39-40`
  把这个机制写成了两句：两棵树差 1.616 ns 而数据只有 1.855 ns，"工具垫得出来，但每次布线垫多少是随机的"，
  并且举出同一份 RTL 的两个读数 +0.001 与 +0.052 作为直接证据。
  因此把 +0.051→+0.037 念成"退步"是错的，念成"改结构没用"也是错的（`report/40-optimization.md` §4 同一行）；
  两份件对同一件事各写一个数（`src/rtl/eth/rgmii_rx.v:7` 写的是 1.683 ns），
  这里只登记两个出处，不做调平。

### 3.2 OSD 读侧插一拍

- **改了什么**：`src/rtl/video/osd_overlay.v` 把选中格提前一拍寄存，使 `ch_r` 落分布式 RAM。
- **看到什么读数**：三组，分别来自三个版本，**本篇不把其中任何两组相减**。
  ① 立案时那条锥的全设计形状读自 `report/optimization_log.md:979`：
  `u_pl/u_split_ctrl/prod/CLK → u_pl/u_osd/b_reg[2]/D`，23 级（其中 CARRY4=3、LUT6=12、MUXF7=1）、
  route 75.3 %，同一次读数的设计级 WNS 是 +0.384 ns（同件 `:972`）。
  ② 改前/改后同尺的那一对读数是 `clkout0_1` 最差 **1.130 ns / 23 级 / route 77.5 %** →
  **4.094 ns / 21 级 / 62.8 %**，同一域相对余量 **5.65 % → 20.5 %**，代价 **−6 FF**
  （`report/40-optimization.md` §2 的 OSD 那一行给 1.130/23 → 4.094/21、5.65 %→20.5 % 与 8162（−6）；
  route 占比与 **+2 LUT** 记在 `report/study/timing/90-numbers-index.md` §3.5 那条口径里；
  `data/metrics.csv` 的寄存器行也留了同一笔"少 6 个（OSD 读侧寄存一拍换来的）"）。
  ③ 今天这一族在名册上的形状是 `clkout0_1` 第 1 档 **3.630 ns / 22 级 / route 59.2 %**，
  起点 `u_pl/x_d_reg[20][3]/C`、终点 `u_pl/u_osd/ch_r_reg/ADDRARDADDR[6]`
  （`build/evidence/r124_tiers_ladder.txt:53`）。
- **判什么**：这条属于**同域同锥**，所以按第 0 节那条读法可以念相对余量；
  落地历史一句话记在 `report/timing_global.md:330`（立案 → 读侧插一拍 → 该域当时 18.49 % 相对余量）。
  同一次构建的全局 WNS 是往下走的，件里明写"那是最差格的持有者换了"，不写成损失
  （`report/40-optimization.md` §2 OSD 那一行）。
- **为什么不能念成别的**：这条锥是交付物本体（OSD 是屏上那四行信息），再要收益只能继续砍级数，
  而那属于功能面改动，不在"一次时序改动"的授权范围里（这条边界写在 `report/timing_global.md` §6.3：
  主导项是 22 级里 9 级 CARRY4 的 OSD 地址/字符算术锥，route 只占 59.2 %）。
  另外那一刀落地时顺手把配套的地址变异对照 `osd_addr` 弄钝过——它只改判据的眼睛、不改被验设计的画，
  后来把那条分支拆成两支才把盲区关掉（`report/log/issues.md:10983` 起的这一条把它写成回归并给了修法）；
  这类"修了设计、钝了尺子"的账也要登记，不算已完成。

### 3.3 `dc_fifo` 格雷码链补 `ASYNC_REG`

- **改了什么**：`src/rtl/eth/dc_fifo.v:27` 给四颗格雷码指针同步寄存器打 `(* ASYNC_REG = "TRUE" *)`。
- **看到什么读数**：布线后网表上带该属性的单元 **0 → 56 颗**
  （`report/timing/debt_ledger.md` §4；改前那一半有实物读数
  `build/evidence/r114_async_netlist_pre_console.txt` 的 `marked_true=0`）。
  同一次构建的 WNS **0.445 → 0.739**、WHS 0.050 → 0.052
  （`build/r113_gates.txt:10` 与 `build/r114_gates.txt:10`），而且最差那一格**换了族**——
  变成 `icmp_tx` 的校验和锥。资源逐字中性：14154 / 8188 / 95.5 / 19。
- **判什么**：采纳，但**收益记给"结构账变干净"，不记给 slack**。理由是
  `ASYNC_REG` 是**放置指令**，它改的是工具怎么摆这两级，所以那 +0.294 ns 不记在本改动名下；
  只有资源逐字中性时才能叫免费（`report/40-optimization.md` §4 同名那一行，同一件事写在
  `report/study/timing/90-numbers-index.md` §3.1）。同一行还写明两处代价：相对改前那一版，
  `clkout0_1` 的 setup 相对余量掉 **18.8 %**、`clk_fpga_0` 的 hold 掉 **5.4 %**，
  都在事先登记的 25 % 门槛内，但要写出来。
- **为什么不能念成别的**：同一次落地之后，`report_methodology` 的 **TIMING-10 一条没少**
  （件 `build/evidence/r114_async_netlist_pre_console.txt:100` 那行 `METHROW check=TIMING-10 … count=1`，
  落地后的计数仍为 1，见 `report/timing/debt_ledger.md` §4）。⇒ 那个计数**不是**属性落地与否的替代指标；
  剩下的那一处没有被工具识别为同步器，是一条"未知对象"债，不许圆成"已闭合"。

### 3.4 行覆盖使能独热化（以及另一次针对广播使能的刀）

- **改了什么**：`src/rtl/eth/frame_reasm.v` 里 `rows_hit` 的写使能从三项式改成独热两项式，
  目标是砍掉一根高扇出广播使能网。
- **看到什么读数**：抓手判据达成——`fo=316` 那根网在本轮报告里不存在、
  `rows_hit*/CE` 作为最差终点出现 **0 次**（这两条抄自 `report/log/issues.md:11114`；
  该条目点名的两份判定件 `build/r110_verdict.txt` 与 `build/evidence/r109_setup_paths_baseline.rpt`
  已经不在盘上，所以本篇只按这条台账记录引用，不再复述其中的其他数）。
  那根网当初的读数出处是 `report/log/issues.md:11010`（`build/setup_paths.rpt` 第 59 行
  `rows_hit[15]_i_1_n_0` **fo=316、route 1.784 ns**，终点 `rows_hit_reg[2]/CE`；
  注意：盘上现在这份 `build/setup_paths.rpt` 是更晚一次构建的产物，第 59 行已经不是那根网）。
  资源侧出现一个 **−243 LUT / −8 FF** 的量（`report/40-optimization.md` §2 的资源格给 14119（−243）/8154（−8），
  `build/evidence/r110_attrib.txt` 头部那句"设计里 r110 相对 r109 是 −243 LUT，
  凭据 `build/evidence/r110_notadopted/utilization.rpt`"点的是同一笔）。
  归属侧另跑了一次只综合这一个模块的对照：base LUT 737 / FF 660，cut LUT 671 / FF 642，
  ⇒ **这把刀自己只值 LUT −66 / FF −18**（件 `build/evidence/r110_attrib.txt` 的 `ATTR-DELTA` 行，
  同件头部写着 `|ATTR-DELTA| 远小于 243 ⇒ 那笔账不在这把刀上`）。
- **判什么**：**不采纳、不刷板、不改写结论**。没有归属的那一部分 LUT 不念成收益
  （`report/40-optimization.md` §3 的 V21 行；`data/metrics.csv` 的 LUT 行里同一笔写成
  "其中 −66 能归到行覆盖那一刀，其余没有归属，不念成收益"）。
- **另一次要如实写**：更早针对同一族广播使能（`rok4[51]_i_1_n_0`，fo=305）动过刀，
  **没有真降**——`report/log/issues.md:11354` 的原话是"那根 fo=305 的使能广播……前两次没真降"，
  复核用的是 `report_high_fanout_nets`（本工具没有 `set_max_fanout`，也没有
  `report_design_analysis -fanout`，所以扇出只能这样读，见 `report/timing_global.md` §1 第 2 条与 §5）。
  ⇒ 这条记录的作用是把"扇出高就一定会被降下来"这个假设打掉。

### 3.5 强制复制 239 引脚广播网：机制动了，**否决**

- **改了什么**：`phys_opt_design -force_replication_on_nets {u_pl/u_row/hi_reg_0[0]}`，
  挂在 `STEPS.PLACE_DESIGN.TCL.POST`（钩子文件 `build/tcl/r117_post_place_hook.tcl`）。
  靶子的形状：一根 239 个引脚的广播网，布线 5.690 ns，载荷铺在 99 个 tile 上
  （`report/timing/cut_ledger.tsv` 的 C9 行、`report/timing_global.md` §6.2 的负载清点）。
- **看到什么读数**：机制两处出水口都对上——`pins_before=239 → pins_after=1`、
  `replica_cells=10`，网表里出现 `u_pl/u_arb/owner_eth_reg_replica_7` / `_9` 这类复制单元
  （`build/r117_verdict_declined.txt` 第 3 行；`build/evidence/r117_repl3/b_console.txt:345-346`），
  端点 15,721 → **15,731（+10）**，Slice 寄存器 8,188 → **8,198（+10）**，等式闭合。
  名册差分（同生成器 16 对）逐格读数（`build/r117_verdict_declined.txt:5-12`）：

| 域 / 类型 | 改前 ns | 改后 ns | 相对余量 | 判语 |
| --- | --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.850 | **2.104** | 18.50 → 21.04 % | 赢，而且赢的正是靶子那一格 |
| `clkout0_1` setup | 3.630 | **3.353** | 18.15 → 16.77 % | 跌 |
| `eth_rxc` setup | 0.739 | **0.615** | 9.24 → 7.69 % | 跌（全设计绝对最紧那一格） |
| `eth_rxc` hold | 0.052 | **0.044** | 0.65 → 0.55 % | 跌（全设计最薄那一格） |
| `sys_clk` setup | 14.876 | **14.815** | 74.38 → 74.08 % | 跌 |

  便宜通道上先量过一次，但那一次的条件与官方构建不同：重跑是在**带窗**的那份 DCP 上做的，
  当时 `eth_rxc` 那两格一格没动、其余三域给出 +0.033 / +0.187 / +0.298 的局部赢、代价 +10 只 FF
  （`report/timing_global.md` §6.2 的对照表，件 `build/evidence/r117_repl3/b_console.txt`；
  同一组数也登记在 `report/timing/gates_g1_g12.md` 的 G4 行）。官方构建不带窗，
  `eth_rxc` 于是从"本来就不动"变成"真的掉"——两次读数的差别本身就是这一把刀的产出物。
- **判什么**：**否决（DECLINED）**，按事前登记的严格口径 A2/A3 回滚这一处，
  位流 `beda9298331d` 留档不删、钩子留在树里（`build/r117_verdict_declined.txt` 末段）。
- **为什么不能念成别的**：三条。① 结论不是"这刀没生效"，是"生效了，但代价落在最紧的两个域上"
  （`report/timing/round_r118.md` §三原话）；② 同一份数据上两把尺子给了相反判语——
  `build/timing_roster_diff.sh` 的 D3 用 25 % 门槛，对**同一批 r117 读数**给 `result=GREEN`，
  严格那把给 DECLINED；这件事写在 `build/r117_verdict_declined.txt` 末段（原话点出"两把尺子对同一份数据
  给不同判语"这件事是口径债，不靠改宽任何一方来消除），交付承诺按严格那把判；③ 更早一次同类改动
  （39 根 fo≥200 的网，`REPLICA_CELLS` 0→296，目标族 +0.456 ns）
  也是同一个形状：代价落在 `eth_rxc` 的 hold（0.050→0.035，相对余量 −29.0 %）⇒ 放弃
  （`report/timing_global.md` §4e 的表格，件 `build/evidence/r114_mf/verdict.txt`）。
  三次合起来得到的判断写在 `report/40-optimization.md` §5 的判断 2：
  **"资源便宜"不是采纳理由，"谁的余量被扣了"才是。**

### 3.6 Pblock 被工具拒：只能念"没做成一次对照"

- **改了什么**：给一块区域画约束，`SLICE_X40Y20:SLICE_X66Y52`（7-series 的 pblock 范围必须写
  `SLICE_XnYm`，UltraScale 的 `CLBLM_*` 写法会被拒；`get_property RANGE` 读回来是空的）。
- **看到什么读数**：构建在两分钟内自己拒绝——`WARNING [Place 30-439]`，说进位链半在块内半在块外；
  落点下限实测 `PB_CONTAIN total=1716 inside=1461`，即 **255 个 cell 跑到块外**
  （件 `build/evidence/r113_roll_abc_verdict.txt:7`，同行判语写的是
  **REFUSE（不是红，是没做成单变量）**）。
- **判什么**：这条只能念成"没做成一次对照"，**不能当一条独立负结果**
  （`report/timing/gates_g1_g12.md` 的 G11 行明写这一条在计数里只能算"没做成"；
  `report/40-optimization.md` §3 的 V7 行同一口径）。要修得把共享进位链的
  `u_eth/u_rx_mac` 一起收进来再试。
- **为什么不能念成别的**：还有一条更早的同类记录：给某一组 BRAM 画框那一版，
  目标族本来就不在最差名单 ⇒ 没有可归属的收益对象，而 `eth_rxc` WNS 从 +0.516 落到 +0.363
  （件 `build/evidence/r89exp_timing_summary.rpt`，判定见 `report/40-optimization.md` §3 的 V1 行）。
  两处合起来才构成"物理摆放这条路本项目的实测形状"，而不是一句"Pblock 没用"。
  另外同一次三滚里还有一条负结果：`place_design -directive Explore` 与对照**一格不差**
  （0.445 / 0 of 51135，落点也相同，`report/40-optimization.md` §3 的 V8 行）——
  它的正面价值是排除法，把候选从"换策略"逼到"扇出复制"与"修 Pblock 表达式"两类。

### 3.7 ±0.500 ns 输入窗：挂上就红，退回候选件

- **改了什么**：把 RGMII 收口五个输入（`eth_rx_ctl` + `eth_rxd[3:0]`）第一次写成
  `set_input_delay`，窗取 ±0.500 ns（候选件 `src/constraints/r114_io_async.xdc:39-43`）。
- **看到什么读数**：同一份 `system_top_opt.dcp` 起两次重跑，唯一变量是那份候选 XDC。
  对照滚逐位复现正式构建读数（WNS 0.445 / WHS 0.050 / 失败端点 0，件
  `build/evidence/r114_io_roll_console5.txt:660` 的 `[Route 35-57]` 行）。挂窗那一滚：
  **WHS 0.050 → −2.885**、THS **−14.344**、`[Route 35-57]` 那一行的 WNS 0.437
  （同一件 `:1355`）；逐时钟那一格是 `IHEAD|io_route|wns=0.424|whs=-2.885|fail_setup=0|fail_hold=5`
  （同一件 `:1451`）⇒ **失败 hold 端点 5 个**，最差那一行落在
  `u_eth/u_rgmii/u_rgmii_rx/u_iddr_rx_ctl/D`，**2 级逻辑、route_pct 0.000**（同一件 `:1400`；
  表格版在 `report/timing_global.md` §4d，同表给出其余三域：`clk_fpga_0` setup 1.135→1.155、
  `clkout0_1` 4.467→4.206、`sys_clk` 14.463→14.109，hold 三格 0.058/0.064/0.133，其余三域未受伤）。
  注意 `[Route 35-57]` 的 0.437 与逐时钟那格的 0.424 是两件不同口径的读数，本篇不替它们调平。
  后来正式构建带上更宽的窗（min 1.200 / max 2.800）那一版的四条硬项读数是
  WNS **−0.846**、失败 setup 端点 **5**、WHS **−0.870**、失败 hold 端点 **5**
  （`build/r116_gates.txt:10-13`，同件末行 `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`）。
- **判什么**：**退回候选件**。默认构建不加载，原件与全部证明留在
  `src/constraints/r116_rgmii_input_window.xdc`，一条环境变量开关可复现带窗那一版
  （`report/timing/round_r118.md` §一第 1 条）。
- **为什么不能念成别的**：三条容易念错的地方。① 这**不是回归**：那个 0.050 从来不是设计值，
  它是"RXD/RX_CTL 与 RXC 同时到达"这个隐含假设给的（`report/timing_global.md` §4d 那句"口径改了，账才第一次算对"）；
  ② 落点 2 级逻辑、走线 0 %，所以**不是布线挤的**；③ "两个沿写重了"这个解释被数据否掉——
  只声明上升沿的那份变体（`src/constraints/r114_io_varianta_rise_only.xdc`）读数逐位相同
  ⇒ 沿的条数不是原因（`report/40-optimization.md` §3 的 V9 行；同一件事的另一处记录在
  `report/timing/debt_ledger.md` §2 那句"变体 A 只声明上升沿……读数逐位相同"）。
  还有一条不能顺手做的处置：**没有靠放宽窗把它变成通过**，
  `report/timing/loosen_ledger.tsv` 至今 **0 条数据行**。
  代价同时写明：那 5 个收端点回到"没检查"状态，而**没检查不等于满足**。

### 3.8 拿 BRAM 换 setup：+0.182 对期望 +0.516，判拥塞主导，否决并回退

- **改了什么**：把帧缓存 `mem[0:38399]` 拆成三块 2 的幂深度（省 RAMB36），
  另一腿加一处寄存把级数修回去。
- **看到什么读数**：`eth_rxc` 的 WNS 采纳基线 **+0.516** → 只拆三块 **+0.232** → 拆+寄存 **+0.182**；
  最差路径级数 4 → 9 → **4**；RAMB36 93 → **88**、tile 95 → **90.5**
  （三份件各出各的 `timing_summary.rpt` / `crit_paths.txt` / `utilization.rpt`，
  读数表与判读在 `report/optimization_log.md` §"r90 的结论"那一段）。
  期望值 +0.516 是同一个域改前那一次给的，不是外推的。
- **判什么**：**否决并回退**。关键判语是：级数回到 4 但 setup 没回来，
  最差那条只有 4 级、数据路径延迟 8.741 ns，差在**布线**上而不是逻辑深度上
  （同样的 4 级在采纳基线上是 0.476~0.516）⇒ **拥塞主导**。
  回退后的状态用 md5 钉住，不靠记忆：`src/rtl` 合指纹、台架报告的 `rtl_md5`、板上那一跑的出处三者相同。
- **为什么不能念成别的**：这笔交换的方向本身有问题，量出来才发现——
  省的是 140 片里的 5 片，而 BRAM 拆前拆后都不在压缩点（67.86 % / 64.64 %）；
  付出的是最快那个域（125 MHz）的 setup 相对余量从 6.5 % 掉到 2.3 %，
  而那个域同时也是保持时间最薄的一格。结论一句话写在 `report/40-optimization.md` §5 判断 1：
  **在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的。**
  同一批里"换 FF 买级数"是划算的并已证明 ⇒ 两个方向出自同一次测量，
  差别不是偏好，而是余量落在哪一列。

### 3.9 两档实现策略：一把 +0.013、一把一格不差，**都不采纳**

- **改了什么**：RTL 与 XDC 一字不改，只把实现策略换成
  `Performance_NetDelay_high` 与 `Performance_WLBlockPlacementFanoutOpt`，各一整轮。
- **看到什么读数**：`build/r95b_timing_summary.txt` 给出两档的设计级读数——
  前者 WNS **+0.013** / WHS +0.056，失败端点 0 / 50883；
  后者 WNS +0.553 / WHS 0.049，失败端点 0 / 50883，**与基线一格不差**；
  BRAM 两档都是 95（`report/optimization_log.md` §r95 之后那一节的两档表）。
  两份位流 md5 互不相同、也不同于正式件 ⇒ "策略被应用了"是有凭据的，不是拿默认流程冒充
  （构建日志里各自念出的是**请求的那一档**）。
- **判什么**：**两档都不采纳** ⇒ "靠工具再压时序"这一问题到此关闭。
  前者的方向是不利的（比基线低 0.54 ns，而实测的跨构建摆幅是 0.4 ns，
  所以这句至少不是"在噪声里挑好看的"）；后者按同一条读法只念"没达门槛"，不念"打平"。
- **为什么不能念成别的**：同一条问题线上先量过的是 `Performance_Explore` / `Performance_ExtraTimingOpt`
  那一组：hold 三档 0.046 / 0.051 / 0.051 ⇒ **一位没买到**，而后者把 `eth_rxc` 的 setup 从 +0.516 花到
  **+0.157**（`report/40-optimization.md` §3 的 V3 行；门槛是开跑前写在脚本头部的 WHS ≥ +0.15、WNS ≥ +0.40）。
  布线后 `phys_opt_design -directive AggressiveExplore` 那一次与基线**逐位相同**，凭据不是推断而是工具自己
  那三行日志（`All physical synthesis setup optimizations will be skipped` / `The netlist was not modified`，
  同一件 §3 的 V4 行）。还有一档连读数都没有：`Performance_ExploreWithHierarchy` 在
  `list_property_value strategy` 里就不存在，`set_property` 那一步被拒 ⇒ 这一格登记为 `NOT_MEASURED`，
  **不写成否决**（同一件 §3 的 V5 行原话：把它写成 DECLINE 就是让"没数"长得像"结论"）。
  ⇒ 这一类问题一共点名叫过**五档策略加一次布线后 `phys_opt_design`**：四档有读数且都不达门槛、
  一档被工具直接拒（没读数）、那次 phys_opt 结构性空转。合起来才允许"靠工具再压时序"这句话被关闭。

### 3.10 九把刀的账，一张表收干净

| 那一次对照 | 一句话读数 | 判定 | 凭据 |
| --- | --- | --- | --- |
| 采样钟并进同一棵 BUFG | 偏斜 1.616 ns → 同树 0.013–0.349；`BUFIO` 1→0；WHS +0.051→+0.037 | 采纳（记结构不记数字） | `src/constraints/rk_zynq7020.xdc:38`、`build/clock_util.rpt:45`、`build/hold_paths.rpt` |
| OSD 读侧插一拍 | 同域 1.130/23 级 → 4.094/21 级，相对余量 5.65 %→20.5 % | 可念相对值（同域同锥） | `report/40-optimization.md` §2 的 OSD 那一行、`report/study/timing/90-numbers-index.md` §3.5、`report/optimization_log.md:979` |
| 格雷码链补 `ASYNC_REG` | 网表 0→56 颗；同构建 WNS 0.445→0.739 且换族；资源逐字中性 | 采纳（不记 slack 收益） | `report/timing/debt_ledger.md` §4、`build/r113_gates.txt:10`、`build/r114_gates.txt:10` |
| 行覆盖使能独热化 | LUT −243，其中 −66 能归属 | 不采纳（无归属部分不念收益） | `build/evidence/r110_attrib.txt` |
| 强制复制 239 引脚网 | 赢 1 格跌 4 格（含最紧两格）、+10 FF | **否决** | `build/r117_verdict_declined.txt` |
| Pblock 那块矩形 | `Place 30-439`、`total=1716 inside=1461` | 没做成一次对照 | `build/evidence/r113_roll_abc_verdict.txt:7` |
| ±0.500 输入窗 | WHS 0.050→−2.885、THS −14.344、5 端点 route 0.000 % | 退回候选件 | `build/evidence/r114_io_roll_console5.txt:1355,1400` |
| BRAM 换 setup | +0.516 → +0.182，级数回到 4 | **否决并回退** | `report/optimization_log.md` §r90 结论 |
| 两档实现策略 | +0.013 / 一格不差，位流 md5 互异 | **两档都不采纳** | `build/r95b_timing_summary.txt` |

---

## 4. 把抽头值算出来：这一篇的高潮

### 4.1 为什么不能靠试

`IDELAY_VALUE` 是收口采样点。改之前的值是 26，而带窗之后那一族的 hold 是 −2.885 ns（§3.7）。
想试，就是 32 个档值 × 每档一条链（§1.3 的表给出"一条链约二十分钟"与"整屏台架约 108 分钟"两格），
也就是说试完这条轴要占掉的不是半天，而是一串构建与一串台架的排期。
转折点是一条工具事实：**`set_property IDELAY_VALUE` 在已布线的 DCP 上有效**，
逐档回读 0/4/…/31 全对上 ⇒ **整条扫描不花一次构建**
（件 `build/evidence/r115_window/probe3_console.txt`；读数表与结论行抄在
`report/timing/rgmii_window_model.md` §7.5(3)，"逐档回读全对上"这条判据见
`report/timing/gates_g1_g12.md` 的 G5 行）。

### 4.2 两条实测直线与交点

在带 0.800 hold 带的口径下，同一份 DCP、同一把尺，逐档读数（下表照
`report/timing/rgmii_window_model.md` §7.5(3) 那张表搬）：

| tap | HOLD ns | SETUP ns | min(hold,setup) |
| --- | --- | --- | --- |
| 0 | −2.822 | +2.005 | −2.822 |
| 12 | −2.066 | +0.902 | −2.066 |
| 20 | −1.563 | +0.166 | −1.563 |
| 24 | −1.311 | −0.202 | −1.311 |
| **26（当时的出货值）** | **−1.185** | **−0.386** | **−1.185** |
| 28 | −1.059 | −0.570 | −1.059 |
| **31（器件上限）** | **−0.870** | **−0.846** | **−0.870** |

两条都是直线，斜率直接从表里量出：hold 每档 **+63.0 ps**、setup 每档 **−92.0 ps** ⇒

```
交点 τ = (2.005 + 2.822) / 0.155 = 31.1
```

`min(hold, setup)` 在合法区间 0…31 上的最大值就落在 **τ = 31**，
比 26 抬 **−1.185 → −0.870 = +0.315 ns**（实测，不是预测：同一只 DCP、同一把尺、逐档读数）。
采纳的那半写进 RTL：`src/rtl/top/system_top.v:172` 现在是 `.IDELAY_VALUE(31)`，
`:164` 那一行注释保留着"在这份窗下把 IDELAY_VALUE 从 0 扫到 31"的出处。
片内名册的判据同时给出 `losses=0`——八对 (域,类型) 逐位与改前相同
（`build/evidence/r118_strict_b1.txt` 末行 `B1 pairs_compared=8 losses=0 verdict=GREEN`）。
这一条的读法要卡住：τ 只动 I/O 单元抽头，**不动片内任何一条锥**，
所以片内逐位复现是**中性**，不是收益；收益在片外那 +0.315 ns
（`report/timing/round_r118.md` §一末段与 §四）。

### 4.3 那张"不相交"的图

同一批扫描的读数写成不等式（截距与斜率都来自上表，不是推的，
`report/timing/rgmii_window_model.md` §7.5(4)）：

```
HOLD（带 0.800 那条带） = −2.822 + 0.0630·τ   ⇒ 要 ≥ 0 需要 τ ≥ 44.8
HOLD（去掉带）          = −2.022 + 0.0630·τ   ⇒ 要 ≥ 0 需要 τ ≥ 32.1
SETUP                   = +2.005 − 0.0920·τ   ⇒ 要 ≥ 0 需要 τ ≤ 21.8
器件合法 τ 只有 0 … 31
```

hold 要的 τ 与 setup 要的 τ **区间不相交**；把与窗双重计的那 0.800 ns 带去掉，
也只是把下界从 44.8 挪到 **32.1**，**仍然不相交**（32.1 > 21.8，而且都超出 0…31）。
⇒ 不存在能同时满足两条检查的采样点。这一条是本工程第一次真正做到
"极限判据"的三段齐全（逐段分解有件、独立负结果有条数、差分只红在被新检查的那两格），
判据形状见 `report/timing/gates_g1_g12.md` 的 G12 行。

根因用报告自己的分量再看一遍，结论一致：**两条检查用的钟不是同一个数**——
hold 查慢角钟网络（DCD **5.008 ns**），setup 查快角（DCD **1.597 ns**），
钟网络的角间差 **3.411 ns**，而数据路径的角间差只有 **0.467 ns**。
数据长度是唯一可调量，而它同时受两边约束：

```
带 0.800：  D_slow ≥ 4.763 且 D_fast ≤ 2.762  ⇒ 需要 D_slow/D_fast ≥ 1.73
去掉带子：  D_slow ≥ 3.998 且 D_fast ≤ 2.762  ⇒ 需要 D_slow/D_fast ≥ 1.45
实测（IDELAY 主导）：3.613 / 3.146 = 1.15     ← 两个门槛都够不着
```

为什么加更多抽头反而更糟：IDELAY 是模拟延迟线，几乎不随工艺角缩放，只有 IBUF 那一段缩放
⇒ 加大 τ 只会把这个比值压得更低（同一节末段）。
还有一项加强而不是削弱上面结论的实测：I/O 路的角分配与片内路**相反**
（I/O hold 用慢钟角、I/O setup 用快钟角，这是源同步收口该有的保守方向）。
自己按"最不利钟 + 最不利数据"算一遍，hold 真最坏是 −1.65 而报告给 −1.185，
setup 真最坏是 −0.85 而报告给 −0.386 ⇒ 工具的读数已经比真正的最坏宽松约 0.4–0.5 ns，**仍然是负的**。
这条必须写在"极限判据"旁边，否则后面会有人拿"角分配反了"当理由去改约束或改报告口径
（`report/timing/rgmii_window_model.md` §7.5(6)）。

### 4.4 结论范围：只支持"当前结构下无解"

这一段是整篇里唯一必须逐字小心的地方。允许的写法只到这里：

> 在 `eth_rxc` 那 5 个端点 + **当前捕获钟结构**这一条件下，不存在同时满足两条检查的采样点。

不支持的写法有两条，都写进了不许写的清单（`report/timing/round_r118.md` §四末段、
`report/40-optimization.md` §7）：

- **"换短钟也关不掉"**：不支持。原因是 BUFIO 那一侧只量过慢角（3.171 ns 是 `BUFIO` 的 SCD，
  见 `src/constraints/rk_zynq7020.xdc:38`），**快角落差未量** ⇒ 角间差这件事在短树上是多少不知道。
  件里把这件事写成一条待办的 40 秒只读探针，而不是结论。
- **"板上真实 hold 差额就是 −0.870"**：不支持。窗模型自己登记了一条残余风险——`TskewR` 那一行
  （1.0 / 1.8 / 2.6 ns，并注明板上要让时钟比数据多走 >1.5 且 <2.0 ns）讲的是 **PHY 的接收端**，
  也就是本板发送侧的 PCB 走线要求，把它当成"收口数据相对时钟沿的到达散布"用是**用错了行**
  （这条更正写在 `report/timing/rgmii_window_model.md` §6 开头的警告块与 §7.5(1)；
  现行窗数值只有一处，即 §7.5 的 min 1.200 / max 2.800）。"混行"这个残余风险因此写进了不许写的清单
  （`report/40-optimization.md` §7 的第①条、`report/timing/round_r118.md` §四末段）。

还有第三条同样要写在明处：τ=31 是**报告最优点**，不是**硅片眼心**。真实硅片只活在一个角上，
鲁棒性应该量"能采对沿的 C 区间"有多宽（`report/timing/rgmii_window_model.md` §7.5(7)(8)）：

| τ | 数据侧延迟 D | 能采对沿的 C 区间 | 对器件角包络 [1.597, 5.008] 的覆盖 |
| --- | --- | --- | --- |
| 21 | 3.30 ns | [2.10, 4.50] | 2.40 / 3.41 = 70 % |
| 26（改前值） | 3.61 ns | [2.41, 4.81] | 2.40 / 3.41 = 70 % |
| 31（报告最优） | 3.93 ns | [2.73, 5.13] | 2.28 / 3.41 = 67 % |

⇒ τ=31 换来的是报告数字好看 0.315 ns，代价按件里的说法是"τ=31 比 τ=26 在真实角上更不鲁棒"
（覆盖从 70 % 那一档变成 67 % 那一档），而且它偏离的是已被板子证明能跑的 26。
它的裁决条件本来就写了：**只有 1000M 实流量 `bad=0` 才保留 31**，
一旦 `bad>0` 或 `drop_words>0` 立刻回 26。执行情况登记时不涂绿：
带流 `drop_words=0`，但同一份件里 `pkt_err=?` / `frames_bad=?`
（`build/evidence/r118_board/bitcycle_console.txt`；同一格也抄在
`report/40-optimization.md` §6 最后一行，明写"不许写成 0"）⇒ 那条 `bad=0` **没有闭合**。
把它彻底关掉的唯一路是运行时可调（`IDELAY_TYPE` 从 `FIXED` 换成 `VAR_LOAD` 或加一条写通路，
逐档加载 + 实流量看 `bad`），而这条路**没有做**：`src/rtl/eth/rgmii_rx.v:68` 仍是
`.IDELAY_TYPE ("FIXED")` ⇒ 一次位流只有一个 τ，运行时改不了。

---

## 5. 归因是怎么做的：从"某条路太长"改成"域怎么划"

### 5.1 最差那一格换过主人，两次各留下不同的病

那一次只把 `icmp_tx` 里三处 16 位减法提前一拍寄存（代价 **+48 只 FF**：8079 → 8127，
`report/40-optimization.md` §4 的对应行），结果全设计最差那一格换了主人：
从 `u_icmp_tx/tx_data_num_reg[15] → data_cnt_reg[15]/CE`（10 级、route 64.65 %）
换成 `u_eth/u_rx_par/udp_off_reg[1] → p_good_reg/D`（**9 级，其中 CARRY4 占 5 级**、
logic 43.1 % / route 56.9 %）。那一次的判语写得直白：**新最差是算术深度（UDP 偏移→包有效标志），
不是绕线；要再动它得改算法，不是换策略**（件 `report/optimization_log.md:1042`，
同一节 `:1056` 把"继续换工具策略不再被视为可收益"钉在同一段）。

另一族是同一条路上反复出现的 `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[*]/CE` 使能广播。
它在三个版本里各留了一次读数，本篇不把这三组相减，只用来证明"这一族的病是布线"：

| 那一次对照的读数 | 级数 | route | 件 |
| --- | --- | --- | --- |
| 本族当最差那一格时 0.445 ns | 4 | 84.276 % | `report/timing_global.md` §2 名册表第一行（同表点出中段 `rok4[51]_i_1_n_0` fo=305） |
| 族级探针里这一族 2.006 ns | 4 | 81.287 % | `report/log/issues.md:11300` 引的 `build/r107_reasm_probe.txt` |
| 当前名册第 4–12 档 1.017–1.041 ns | 4 | 85.1–85.2 % | `build/evidence/r124_tiers_ladder.txt:22-33` |

⇒ 三组读数的 route 占比都在 80 % 以上、级数都是 4，而**当前名册的第 4 到第 12 档全在这一族**。

### 5.2 于是结论是域划分，不是"某个加法器太长"

三段读数拼起来就是归因本身（`report/timing/eth_rxc_partition_options.md` §7 第一条）：

1. 第 1–3 档是同一只 `icmp_tx` 校验和锥（11 级、route 约 58 %）；
2. 第 4–12 档**全部**是那只 CE 使能广播（4 级、route 约 85 %）；
3. ⇒ 即便把校验和锥整族搬走，本域会停在 **1.017 ns**，
   所以整族搬走的上界只有 **+0.278 ns**（1.017 − 0.739 = 0.278，同一只数记在
   `report/timing/cut_ledger.tsv` 的 C10 行"接棒的是同域 1.017×8，不是 0.739→1.8"）。
   再往上的瓶颈是这只使能广播，而**拆锥那一类杠杆治不了它**。

对照组是另一个域：`clk_fpga_0` 的前 12 档**全部**同起点 `u_pl/u_arb/owner_eth_reg/C`，
终点是帧缓存 BRAM 的 `WEA`/`ADDRARDADDR` 脚，逻辑只有 1–4 级、route 88.8–93.6 %
⇒ 这个域没有算法锥可拆，能动的是那只高扇出旗标的复制与摆放——而那类刀在本工程已经被量过两次
（`build/evidence/r124_tiers_ladder.txt` 第 48–50 行；两次的判定见第 3.5 节）。
两域合起来，"时序瓶颈"这个抽象词在本项目里被具体成两类东西：**一条被布线主导的 CE 网**，
和**一只高扇出旗标的摆放**，都不是"某个加法器太长"。

### 5.3 摊拍那一刀的实测，与"没量过"这三个字的用处

把校验和从一拍 10 项摊成每拍一项，实测四域（件在 `report/log/issues.md:13716`，
结论行同现于 `report/timing/eth_rxc_partition_options.md` §8 与 `report/technical-document.md` §6.3）：

```
eth_rxc    0.739 → 0.691      （目标族自己往下掉，不是往上）
clk_fpga_0 1.850 → 1.727      （件里写的 −0.123）
clkout0_1  3.630 → 3.799      （件里写的 +0.169）
sys_clk    14.876 → 14.068
hold 四域  0.053/0.052/0.059/0.222 → 0.057/0.051/0.064/0.116
```

判定：**判负回退**。目标族自己往下（0.739 → 0.691），`clk_fpga_0` 与 `sys_clk` 两域的 setup
同时跌，`eth_rxc` 与 `sys_clk` 两格的 hold 也跌；四格里只有 `clkout0_1` 的 setup 变好。
摊完之后接上的最差一族正是那只 CE 广播（`p_eof_reg → rows_hit_reg[*]/CE`，
4 级、route 85.1–85.2 %，见 §2.5 表 B 的第 4–12 档），所以"本族没抬起来、最差换成了布线主导的使能网"
这一句两端都有件。

这一节真正想留给读者的是下一步动作。判完之后去翻台账，问"这类刀以前试过没有"：
`report/timing/cut_ledger.tsv` 的 C10 行状态是 `measured-none`，
注释写着"此前 cut_ledger 与 loosen_ledger 各零行，是台账洞，不等于试过不行"
（`report/timing/loosen_ledger.tsv` 也只有表头 + 注释，数据行 0，见
`report/timing/gates_g1_g12.md` 的 G3 行）。
⇒ 那句"到极限了"**不成立**，能说出口的只有"这一条没量过"。
同一件还给出为什么它便宜不了：改网表 ⇒ 快车道不适用，要一次官方构建，
而同域加一级 FF 会动放置密度——那一次的教训就是赢 1 格跌 4 格。

于是"极限"这句话在本项目里的完整形状被写成一段有限定的话
（`report/40-optimization.md` §7、`report/timing/round_r118.md` §四）：
**在不动架构（捕获钟拓扑）也不动功能（OSD 锥）的前提下**，名册上的每一格要么已为正、
要么被证明了关不掉；非放宽的物理杠杆（策略扫描、同一份 DCP 重跑、Pblock、BRAM 换 setup、
复制广播网、格雷码 `ASYNC_REG`、τ 扫档）已逐处量过并给出收益或判负。
这句话里**没有**"每颗时钟都被证明已到物理极限"——四行 `NA` 的域状态是"没有同沿路径行"。

---

## 6. 采纳条件长什么样

采纳不是"WNS 变好了"，是一组能机械复核的条件。那一次收口的四条判据是起飞前登记在
构建脚本头部的，不接受事后改口径（原文与编号在 `report/timing/round_r118.md` §二）：

| 编号 | 判据 | 落地件 | 实测 |
| --- | --- | --- | --- |
| B1 | 严格名册：4 域 × setup/hold 共 8 对里，任何一格相对改前**不许变小** | `build/evidence/r118_strict_b1.txt` | `pairs_compared=8 losses=0 verdict=GREEN` |
| B2 | 机构中性：构建日志里**没有**复制钩子那三个字符；未约束内部端点仍 0 | `build/r118_verdict.txt` | `B2_hook_absent=0（应为 0）` |
| B3 | 资源中性：寄存器与改前同值 8188，LUT/BRAM/DSP 不变，无 `Place 30-439`，route 干净 | `build/utilization.rpt:35,40`；`build/r118_verdict.txt:13-14`；`build/route_status.rpt` | LUT 14154 / FF 8188 / BRAM 95.5 (68.21 %)；`B3_place30439=0` |
| B4 | 发布门：**判定 24 项里红数恰好 == 1**，而且那一条必须是写明过的 `C5c`；门禁两跑逐字节一致 | `build/r118_gates.txt`、`build/evidence/r118_board/gatesc_summary.txt` | `GATESC done id=identical green=23 red=1` |

四条全过才允许刷板，任一不过就是"板子回刷上一版，这一版记'量过并否决'"。

### 6.1 那条唯一许可的红：`C5c`

- 它在台架件里长这样：`build/tb_v98_report.txt:55`
  `FAIL C5c frame head is not the previous frame's tail | first OFF+BILIN output rows must
  carry their own source row on BOTH sides of the seam`（该文件 `^PASS` 161 行、`^FAIL` 1 行，
  头部带 `top_md5=56c269602e18`，见 `report/40-optimization.md` §8 的 D2 行）。
- 门禁对它的位置：`build/r118_gates.txt:34` 那一行判 FAIL，
  紧跟一句提示"报告里有 1 行 FAIL 没有 PASS 汇总行（台架跑完了、是它自己判红的，
  先读 FAIL 那几行的数）"。
- 它的物理含义是**屏幕最上面那一小条的碎影**：帧头 6 行（`OFF_LINES` 4 + `BILIN_ROWS` 2）
  读到上一帧的几何，本体行一格都不错——逐格读数在
  `build/evidence/r104_c5head_band.txt`（件里那行汇总：本体行 3564 格不符 0、帧头窗 36 格不符 24），
  现象、已定位原因、还没证明什么、现在的处置，四段都写在 `report/08-limits.md` §1。
- 为什么留着不抹平：关掉它要动读口调度、会同时动数据通路，
  而"改前必须红、改后恰好只剩这一条通过"的那条变异对照还不存在 ⇒
  **先建能红的对照，再动 RTL**。留红是有意选择，随检查输出一起交出去，不算通过也不藏。

### 6.2 "检查全绿 ≠ 已验证"，三条理由

1. **那把尺子自己写着不重新跑构建。** `build/gates.sh:33` 那一行的原文是
   "数字全部来自 Vivado 报告本身，不重新跑构建"。⇒ 全绿说明"报告与阈值一致"，
   不说明"报告对应手上这份源码"。同件 `:2` 那一行的新鲜度与 `:3-5` 的三枚 md5 就是用来补这一环的；
   另一次跑同一个脚本时，头部第 6 行直接打出 `WARN 有 RTL 源比 system.bit 新 ⇒ 这份产物不含这些改动`，
   并列名三个源文件（件 `build/r126_gates.txt:6`）——这正是"绿"与"验"分开的实物。
2. **不要相信退出码。** `build/tcl/README.md:19-23` 点名的两支脚本用
   `[file dirname [info script]] ..` 少解析一层，`add_files` 指到不存在的路径，
   **报错之后仍然 exit 0**；同一段给的处置是"跑完必须自己去 `build/` 里核对报告的时间戳，
   不要相信退出码"。同一本 README 的第 4 节还单独列出四条一次性修复脚本"别当模板抄"。
3. **采纳规则与脚本的默认动作是两句不同的话，必须一起念。**
   门禁脚本对"有任何红"的默认动作是拒绝：`build/r118_gates.txt:54` 打的是
   `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；
   而这一版最终被采纳，因为采纳规则第 4 条写的是"红数 == 1 且唯一那条是声明过的 `C5c`"
   （`report/timing/round_r118.md` §二的 B4，同条也抄在 `report/06-validation.md` §3）。
   只念前半句会得出"这版被拒"，只念后半句会得出"这版全绿"——两句都不是事实。

还有一条属于同一类：门禁的**项数本身**是个会漂的数。`build/gates.sh:6-16` 明写
"这里不再写死条数，以本文件里 `say` 的调用次数为准"；而 `data/metrics.csv` 的
"门禁自检项"那一行仍写着 22（那是更早时代的行没跟着改）。两处不一致时的处置写在
`report/40-optimization.md` §8 的 D1 行：**以门禁件为准**（24），指标表属禁改文件，本章节不改它。
读文档的人要知道自己在读哪一把尺子。

### 6.3 板级那一半

采纳的最后一格不是机器给的：`bash build/board_verify.sh --geom --battery` 的原始回显
`build/evidence/r118_board/board_verify_console.txt:66` 打
`RESULT board_verify PASS（判红的步骤：0）`，同一件 `:36` 是 `RESULT PASS geom_check（ok=10 fail=0）`、
`:63` 是 `RESULT PASS uart_cmd_check（105 条命令, 97.9 s）`。
屏上那一行仍由人判：36 行人眼验收在 `board/verify_r87.md`，
其中与碎影有关的 E4/E4r 两行签在 `board/acceptance.md`。
机器判的红可以引用，机器判不了的红不许代签。

---

## 7. 仍然欠的账（一条都不软化成"基本没问题"）

下面五条全部照 `report/study/timing/90-numbers-index.md` §4 的清单列，每条补一份盘上能指的件。停手不让这些账消失，只让它们不再新增。

1. **收口 I/O 的 5 个端点回到"没检查"。** 输入窗退回候选件之后，`eth_rx_ctl` 与 `eth_rxd[3:0]` 没有任何输入延迟约束覆盖 ⇒ 未检查**不等于**满足。件：`report/timing/round_r118.md` §四末段那第三句"不许写"；`build/timing_summary.rpt:154` 那句 "All user specified timing constraints are met" **不包含**这 5 个端点（因为没有任何约束点名它们）；候选原件 `src/constraints/r116_rgmii_input_window.xdc`。
2. **TMDS 四组输出仍是 BARE。** 屏那一路 6 个输出引脚量过并拒绝纳检。为什么不能拿 UG471 的接收窗数来配：那 6 个引脚是**输出**，方向就不对（`report/timing/eth_rxc_partition_options.md` §6 末段与 `report/40-optimization.md` §8 的 D4 行）；源端窗口只能按 HDMI 规范的 TP1 口径引，而按那个口径写成 `set_output_delay` 之后量到的是 `clkout1_1` 整行 **WNS −5.408 / 6 个 setup 违例端点、WHS −1.923 / 6 个 hold 违例端点**（件 `build/evidence/1006d_tmdswindow_timing_summary.rpt:189`；判 DECLINE 的写法与量纲错的原因在 `report/timing/debt_ledger.md` 的追加节）。换成同量纲的问法（已布线成品逐脚 clock-to-pin 到达离散）判 10 项未通过 0（`build/evidence/r119_window_check.txt`），但那两笔新欠账——板级走线/连接器离散、眼图/抖动/占空比/沿——**不能拿"窗已过"来抵**。
3. **角度机读口没上。** 屏上能看当前角度，串口读不回来 ⇒ 眼睛判的那一行不能自动化。读数与误读风险记在 `build/evidence/r111_angle_readback.txt`，方案（走 lane23 的保留位 `[28:20]`、不新增跨域）写在 `report/08-limits.md` §2。这条严格说不是 slack 债，但它是"时序结论要能自动化"的一环，所以列在时序账里。
4. **异步组外四条跨域路缺 `set_max_delay -datapath_only`。** 异步时钟组分三组互斥（`src/constraints/clock_groups_impl.xdc:28-31`），被整组排除的钟对上界**叠不上去**——`report_exceptions` 的表体 A 次 13 行、B 次 13 行，`-datapath_only` 出现 **0 次**（`report/timing/debt_ledger.md` §5、`report/40-optimization.md` §3 的 V10 行）。⇒ 这条债**不能靠加约束消**；要动的是"那一对钟要不要继续整组互斥"这个口径决策，它会改变 WNS 的计算范围，必须单独一次带名册差分的构建，不许顺手做掉。跨域数据目前完全靠结构保证（格雷码 + 两级 / 翻转 + 三级边沿检测，清单在 `src/constraints/clock_groups_impl.xdc:19-24`），STA 不参与。
5. **BUFIO 快角 DCD 未实测。** §4.4 那句结论范围就卡在这里：慢角 3.171 ns 有数（`src/constraints/rk_zynq7020.xdc:38`），快角没有 ⇒ "换短钟也关不掉"这句话**不许写**，一次 40 秒的只读探针欠在前面。

再加两条同源的小账，一起欠着：四个域都没有 setup 项的 `set_clock_uncertainty`（只有 `eth_rxc` 有一条自加的 hold 带 ⇒ 四域 WHS 不可互比，`src/constraints/rk_zynq7020.xdc:50`）；以及 `report_methodology` 的 TIMING-10 仍为 1、那一处没有被识别为同步器的"未知对象"（`report/timing/debt_ledger.md` §4）。补上它们只会让读数变小（把债显形），不会让设计变快。

---

## 8. 如果重来一次会按什么顺序做

第 2 篇那张优先级决策树给的是"按什么性质排"，这里把它翻译成本项目付过学费的时间轴；顺序本身就是结论，括号里是**实测成本**。

1. **立口径，不动刀**：五域表 + 端点总数 + 不确定度覆盖面复查（一次只读探针的量；形状问题每个 40 秒，§1、§2.6）。最贵的一笔浪费是"改完才发现尺子不同"，最便宜的一笔收益是"40 秒问出报告形状"。
2. **建名册与差分尺，并先让差分尺自己红一次**：`-nworst 1 -max_paths 12` + distinct 反读 + 同生成器闸门（只读探针几分钟一次；对照测试是纯脚本量，不占构建）。顺序不能颠倒的原因在 §2.4——两侧口径不一致时相减得到的不是代价，是尺子断了。
3. **把"能不能便宜地量"问到底**：已布线 DCP 上能改的属性优先（τ 整条 0…31 扫描**不花构建**，§4.1）→ 不能改的排快车道（单滚约 7–9 分钟）→ 再不能才排官方构建（一条链约二十分钟，§1.3）。这三档分开用之后，才有本钱承认两把刀"量过并否决"。
4. **只动结构面里"消除机制"的那一类，并且不记数字收益**：采样钟并进同一棵 BUFG（一次官方构建 + 台架约 108 分钟 + 上板一跑）。记账方式见 §3.1：WHS 是 +0.051 → +0.037，没变好，但消掉的是"每次重建掷 ±1 ps 硬币"这个机制。
5. **约束面的债先显形，再决定关不关**：挂真窗那一次（快车道两滚，约 13 分钟）买到的是"那个 0.050 从来不是设计值"这句话（§3.7）；同一步要顺带复查改名后约束的射程（§1.2），否则会把覆盖面丢失念成收益。
6. **扇出/摆放这类物理杠杆，先在便宜通道量，再排官方构建**：三次同类改动（39 根网的复制、那块 Pblock、那根 239 引脚网）合计两次快车道重跑加一次官方构建，全部判负或没做成对照。重来时第 3 步会更早挡住它们——判据问的是"谁的余量被扣了"，而 `eth_rxc` 的 hold 在量过真窗之后已经没有可信余量，这类刀在该域根本不该立案（§3.5、§5.2）。
7. **拿资源换余量的方向，先确认压缩点在哪**：BRAM 换 setup 那一次（两次隔离构建，各约一条链的量）给出的结论是方向本身反了（§3.8）；这笔钱花得值，因为它是"两个方向出自同一次测量"里唯一能证伪方向的那一半。
8. **工具策略扫描放在最前或最后，别放中间**：五档策略加一次布线后 `phys_opt_design`，有读数的每一档约一条链（约二十分钟一条），结论是问题关闭（§3.9）。放中间的成本是它会诱导读者拿跨构建差值当收益，而那正是 §1.3 末段那条纪律要防的。
9. **采纳前把四条判据写在起飞前的脚本头部**：写不出的那一条就是没想清楚的那一条。B1 严格名册 / B2 机构中性 / B3 资源中性 / B4 发布门 + 两跑逐字节（§6）。还有一句不写在判据里但每次都要念的：**判负也要交付**——负结果不进首页成绩，但件不删、钩子留档、否决写清"量到什么、因此判它不行"（`report/40-optimization.md` §3 的 21 条否决与 §6 的缺证据清单就是这条纪律的产物）。

最后把这篇的方法压成三句话，每一句都对应上面某次实测：

- 先问"这是谁的余量"，再问"这条路径多长"——两个域的前 12 档说明瓶颈是一只 CE 广播和一只旗标，不是一只加法器（§5.2）。
- 先问"这条结论的范围到哪"，再决定要不要写下来——"当前结构下无解"与"换短钟也关不掉"之间差一份没做的 40 秒探针（§4.4）。
- 先问"这把尺子与那把尺子是不是同一把"，再决定能不能相减——不同口径的名册相减会被 REFUSE，而同一份数据上严格与宽松两把尺子会给出相反判语（§2.4、§3.5）。

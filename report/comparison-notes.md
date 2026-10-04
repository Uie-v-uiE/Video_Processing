# 口径说明：每个派生量的公式与来源数，以及哪些比较属于不可比

这一页要能让人自己算出"这是收益还是代价"。它回答两件事：**每个派生数是怎么来的**（公式 + 两个原始数各自的出处），
**哪些比较不能做**（跨口径、跨器件、跨约束集、跨单位）。
`report/40-optimization.md` 与 `report/50-results.md` 里出现的每一个比值、百分数、差值都在下面登记；
**无公式的派生量数 = 0**（若读到这里发现有一格没登记，那一条就是不通过项，请指出来）。

## 0. 先读这一格：什么叫收益、什么叫代价（可以照算）

一条差值要写成"收益"，下面四问必须全是"是"。任何一问为"否"，它就只能写成"读到了什么"，不能写成收益。

1. **是同一件东西吗**——两次读数的器件、约束集、生成脚本三项都相同，件名与件头各给一行证据。
   不同就属于不可比，见 §3 的 N1、N2、N10 三行。
2. **是同一条路径吗**——起点单元与终点单元逐字相同。不同则级数、端点族这类结构量可以念，绝对 ns 差不可以
   （P19 与 P11 的后半句就是这一条的两个实例）。
3. **大过测量本身的分辨率吗**——要写成"移动"，绝对差得越过所属那一档的分辨率。这里有两档：
   "跨变体的两次构建之间"与"同一份 DCP 重滚一次"，两个数与出处都记在 Q7，按那一行的适用范围取。
4. **有第二份凭据指着同一件事吗**——机制、归属、端点族里至少两项对得上。只有一个小数时只登记、不声明。

代价用的是同一套四问，而且**必须与收益写在同一行**，一行只讲一侧不算讲完：

- **资源代价**：FF 与 LUT 各多少，并写清是 `LUT as Logic` 还是 `Slice LUTs` 口径（N5），
  以及这份读数能不能归到具体模块（P15 归不到 ⇒ 不采纳；P16/P17 归得到 ⇒ 可以逐层念）。
- **时序代价**：其他时钟域、其他相对余量格子的下降值，与收益同行给出（Q4 那句"这一对必须与 P18 同现"是实例）。
- **告警代价**：`report_methodology` 的告警实例数、检查条数这类**类别计数**也算代价（P5），
  只看触发器与 LUT 两项会漏算。
- **判定代价**：这一刀让哪几条判定标准从通过变成不通过，或者反过来；三态里的"未判"也属于这一类（§5 末行）。

一句总则：**WNS 的绝对差既不能当收益，也不能当损失**。可以声明的是归属与结构量——某一条族的端点数、
级数、最差格换了谁（P18、P20 与 `report/log/changelog_v7.md` 同口径）。
读者按上面四问算一遍，就能判断这一页里每一行"可比／半可比／不可比"的标注是不是站得住。

**约定与记号**：
- "原始数"＝盘上件里被印出来的那一格，引用时点名文件与行/字段。
- "公式"＝由哪两个原始数、按什么算式得到；不做四舍五入以外的处理，凡文件自己印了小数位
  （如 `margin_pct=9.24`）的，一律直接引那一个，**不再重算**。
- Δ 一律写成 `后 − 前`，前后各点名。
- 件名与表名里的 `rNN` 是构建轮次编号，属于文件名的一部分，原样保留；正文叙述不再用它做主语，
  改用下面这四个角色名（每个角色名后面就是它的凭据件，读者可以自己打开核对）：

| 角色名 | 指哪一次构建 | 凭据件 |
|---|---|---|
| 基线那一版 | 相对余量与资源都按它起算的那一次 | `build/evidence/r114_after.txt`、`report/timing/roster_baseline.tsv` |
| 带输入窗那一版 | 多带一份输入窗约束的那一次构建 | `build/evidence/r116_after.txt`、`report/timing/roster_round116.tsv` |
| 撤掉输入窗那一版 | 把那份输入窗撤回去的那一次构建 | `build/evidence/r117_after_roster_probefmt.txt` |
| 板上现役那一版 | 现在烧在板上的那一版（身份行在 `README.md` 首页） | `build/evidence/r118_after_roster_probefmt.txt`、`build/r118_gates.txt` |

单轮次只出现一次的比较（例如 P11–P16），行名里不再写轮次号，改为直接点名两件凭据件——
照着件名读，轮次号自己就在里面。

## 1. 逐时钟名册与余量的定义（下面这些百分比的分母来源）

名册＝逐时钟清单（件名里的 roster 就是它），四个域、每域 setup 与 hold 各一格。

| 派生量 | 公式 | 两个原始数（出处） | 说明 |
| --- | --- | --- | --- |
| `rel_margin_setup` | `wns_setup / period_ns` | 周期取名册 `period_ns` 列；`wns_setup` 取 `report_timing_summary` 的 Intra Clock Table — 件 `report/timing/roster_baseline.tsv` 第 2 行口径注释"rel_margin_* = wns_* / period_ns（§4 E2 强制）" | 定义来自名册自己，不是这一页发明的 |
| `margin_pct` | 同上，由名册生成器打印 | `build/evidence/r118_after_roster_probefmt.txt` 的 `ROSTER\|setup\|clk=…\|period=…\|slack=…\|margin_pct=…` 行 | **这一页直接引用打印值**，不重算（`report/05-timing.md` §1 同口径） |
| `io_unconstrained_ports` | `check_timing -verbose` 的 HIGH 两类之和（端口对象单位） | `report/timing/roster_baseline.tsv` 第 2 行注释：输入 5 + 输出 6 = 11 | 单位是**端口**，与 §7 的 TIMING-18 不同量纲 |
| `unconstrained_endpoints` | `check_timing -verbose` 自己那行 "pins that are not constrained for maximum delay" | `report/timing/debt_ledger.md` §1：实测 0 | 单位是**设计级一个数** |
| **同一个名字下并存两套口径（口径冲突，已登记不合并）** | `rel_margin_*` 是**比值**（如 `0.185000`），`margin_pct` 是**百分数**（如 `18.50`）；两者同量不同单位 | 比值侧：`build/roster/roster_r118.tsv` 第 4 行"口径冲突（两把尺子并存）…**判据 G1/G2 用本表 ⇒ 裁决以本表为准"；百分数侧：`build/roster/roster_r118_probe.tsv` 第 3 行与 `build/evidence/r118_after_roster_probefmt.txt`（百分数侧的件按轮命名，每一轮各有一份） | ⇒ 本节的 Q1/Q2/Q3 里凡引"百分点"的都注明是**打印百分数那一套**给出的；两套的数不相减 |

## 2. 逐条派生量登记

### 2.1 差值类（Δ = 后 − 前）

| # | 派生数 | 公式 | 前（原始数与出处） | 后（原始数与出处） | 可比性 |
| --- | --- | --- | --- | --- | --- |
| P1 | **+0.315 ns**（收口眼心） | `−0.870 − (−1.185)` | tap26 HOLD `Slack (VIOLATED) : -1.185ns` — `build/evidence/r115_window/probe3_console.txt:170` | tap31 HOLD `-0.870ns` — 同件 `:188` | **可比**（同一份已布线 DCP、同一套判定标准、同一端点）；但两数都是**违例** ⇒ 只能写"最差那一档抬了 0.315"，不能写"时序收益 0.315"；登记句 `report/timing/cut_ledger.tsv` C8 行 `expected_gain_ns` 列 |
| P2 | 同一条 tap 直线的斜率 | `HOLD(τ) = −2.822 + 0.0630τ`；`SETUP(τ) = +2.005 − 0.0920τ`；交点 τ=31.1 | 两条式子由 `probe3_console.txt` 的 0…31 全档读数拟合，**式子本身抄自** `report/timing/round_r118.md` §一 与 `report/timing/cut_ledger.tsv` C8 行 | 同左 | 这一页不重新拟合；只引用已登记的式子 |
| P3 | **−0.198125 / −0.115250**（带输入窗那一版相对基线那一版的两格名册差） | `b_rel_margin − rel_margin`（名册差分件自己打印） | `roster_round116.tsv` 第 12 行 a 列 0.092375 / 0.006500 | 同行 b 列 −0.105750 / −0.108750 | **跨构建** ⇒ 名册按 H3"只念不判收益"；判定列仍按 G1+G2 |
| P4 | **−5**（未约束端口） | `6 − 11` | 基线 `io_unconstrained_ports = 11`（`report/timing/roster_baseline.tsv` 各行第 12 列） | 带输入窗那一版 `= 6`（`report/timing/roster_round116.tsv` 第 6–13 行 `b_io_unconstrained_ports` 列） | 可比（同一套 `check_timing` 口径、端口单位） |
| P5 | **−5 / −5**（方法论告警实例） | `441 − 446`；`2 − 7` | `build/evidence/r115_base/methodology.txt:26,36`（446、TIMING-18 7） | 带输入窗那一版那份：`Checks found: 441`、TIMING-18 **2** — 读数登记在 `report/timing/round_r116.md` V5 与 `report/timing/debt_ledger.md` §2 追加节 | 可比（同一份 `report_methodology` SUMMARY 表口径）；警告 与 P4 的"−5"**不是同一件事**，两个 5 不许互相解释 |
| P6 | **+0.254 / −0.277 / −0.124 / −0.008 / −0.061 ns**（撤掉输入窗那一版相对基线那一版五格） | `后 − 前` | `build/evidence/r114_after.txt:31,55,7,51` 与 `report/timing/roster_baseline.tsv`（1.850 / 3.630 / 0.739 / 0.052 / 14.876） | `build/evidence/r117_after_roster_probefmt.txt` 第 1、13、5、6、3 行（2.104 / 3.353 / 0.615 / 0.044 / 14.815） | **可比**（同器件、同约束集、同生成器）；这五个差**登记在** `report/timing/round_r118.md` §三 的"读法"列，这一页只引用 |
| P7 | **+10 = +10 = +10**（C9 的闭合等式） | 端点增量 = replica 数 = 寄存器增量 | `build/evidence/r117_repl3/b_console.txt` 的 `R3_REPLICA_CELLS`、`clk_fpga_0` 端点 15,721→15,731、Slice 寄存器 8,188→8,198（三处逐条抄自 `report/timing/round_r117.md` §二 表） | 同左 | **机制与代价必须互相对上**，对不上就判"看起来动了"；登记句 `report/timing/round_r117.md` §二"闭合等式" |
| P8 | **+0.456 ns**（C1 目标族，基线那一版的当晚） | `0.901 − 0.445` | 两滚同一份 `opt.dcp`；读数登记在 `report/timing_global.md` §4e 表第 3 行（"A 滚 0.445 / B 滚 0.901"），原始件 `build/evidence/r114_mf/verdict.txt` | 同左 | **可比**（同 DCP 单变量 A/B，噪声底 0.000） |
| P9 | **−29.0 %**（`eth_rxc` hold 相对余量，C1 的代价） | `(0.44 − 0.62) / 0.62` | `build/evidence/r114_mf/verdict.txt:29` `margin_pct 0.62` | 同行 `->0.44` | 可比；登记句 `report/timing_global.md` §4e"相对余量 −29.0 % ⇒ 红"（那一格的打印词就是"红"，即不通过） |
| P10 | **+275 FF / +35 LUT**（扇出复制那一刀的 C1 资源代价；同一轮的收口眼心见 P1） | `8463 − 8188`；`10004 − 9969` | `build/evidence/r115_fanout_ab/verdict_header.txt:8` 的 `F7_utilization FF A=8188 … LUT A=9969` | 同行 `B=8463 (+275)`、`B=10004 (+35)` | 可比（两份不同 util.rpt 相减，件里已把 delta 打印出来）；警告 这里的 LUT 是 `LUT as Logic` 口径，与 `build/utilization.rpt` 的 `Slice LUTs 14154` **不是同一列**，两数不相减 |
| P11 | **+1.283 ns**（位图分组那一族） | `2.006 − 0.723` | 改前同端点对 0.723 — `build/r106_critpath_console.txt` 第 103..108 行（登记在 `report/log/issues.md` #230 表） | 改后同端点对 2.006 — `build/r107_reasm_probe.txt`（登记同一行；这一条原先多写了一级 `build/evidence/`，那个路径从未入库，`git log --diff-filter=A -- build/r107_reasm_probe.txt` = 1a120c2b） | **可比**（"同一起点/终点对的两端夹逼"）；同轮的 `WNS 0.723 → 0.725` **不可比**（换了主人） |
| P12 | **+0.356 ns**（校验和摊两拍那一轮） | `1.081 − 0.725` | 改前锥最差 0.725 — `build/r108_cone_before.txt`（登记在 `report/log/issues.md` #231） | 改后同端点对 1.081 — `build/r108_cone_verdict.txt`（同条） | 可比；警告 该轮代价 `WHS 0.050 → 0.035`（`build/r108_gates.txt:12` vs `build/r107_gates.txt:12`）是**同一套全局口径的另一格**，两个数一起念 |
| P13 | **+48 FF / +1 LUT**（条目 #141 的全部代价） | `8127 − 8079`；`14334 − 14333` | 改前那一次：`build/r103_gates.txt:15,16` | 改后那一次：`build/r104_gates.txt:15,16` | 可比（同为"一次构建"口径）；且"隔离滚与正式滚给出同一代价"由 `build/evidence/r105_ab_rolls.txt` 第 12–14 行钉住 |
| P14 | **−11 LUT / +22 FF**（收包链那一刀，相对它的前一版） | `14323 − 14334`；`8149 − 8127` | 前版 `build/r104_gates.txt:15,16` | 后版 `build/r106_gates.txt:15,16` | 可比；归属句在 `data/metrics.csv` 第 8–9 行（"r106 比 r104 少 11 个"、"多 22 个触发器 = 收包链那一刀的代价"——这两句是件里的原文，句中带轮次号） |
| P15 | **−243 LUT / −8 FF / −16 端点**（未采纳的那一刀） | `14119 − 14362`；`8154 − 8162`；`51013 − 51029` | 前版 `build/r109_gates.txt:15,16` 与 `:55`（端点总数 51029） | 后版 `build/r110_gates.txt:15,16` 与 `:55`（51013）；那一次构建的资源原件 `build/evidence/r110_notadopted/utilization.rpt` | **差本身可比，但归属不可写**：那份 `utilization.rpt` 是扁平汇总、无逐层实例行 ⇒ 归不到模块的量不写进首页（`report/log/issues.md` #246）；这一刀因此**不采纳** |
| P16 | **+35 LUT / +34 FF 且闭合到个位**（icmp 瘦身那一轮） | `14154 − 14119`、`8188 − 8154`；逐层侧 `+66 − 31 = +35`、`+46 − 12 = +34` | `build/evidence/r110_setup_paths_baseline.rpt` 与 `build/utilization.rpt` 的那一次快照、`build/evidence/r112_util_attrib.txt`（`system_top 14119→14154`、`u_pl +66/+46`、`u_icmp_tx −31/−12`） | 同件（改后那侧） | 可比 ⇒ **这一轮没有"归不到模块"的余量**（登记句 `report/log/issues.md` #254 第 1 条）；另注：OOC 那腿量到的是 `−40/−12`，与逐层 `−31/−12` 差 9 个属**两口径正常差**（#250 续），不相减当新问题 |
| P17 | **+26 LUT / +34 FF**（同一轮的净账，按腿算） | `(−40) + (+66)`；`(−12) + (+46)` | `build/evidence/r112_ooc_*.txt`：`icmp_tx` 腿 −40 LUT/−12 FF | 同件：`key_debounce` 单实例 +33/+23，**在 `pl_video_top` 里例化两份 ⇒ +66/+46** | 可比（同一套 OOC 口径）；登记句 #250 续："这不是收益 statement，是代价 statement" |
| P18 | **+0.294 ns（头条）** 基线那一版相对它的前一版 | `0.739 − 0.445` | `build/r113_gates.txt:10` | `build/r114_gates.txt:10` | **不写成收益**（`report/log/issues.md` #294 原话："头条那 +0.294 ns 不算这一刀的收益"）；#292 的机理解释是：`ASYNC_REG` 是放置指令，网表被重摆之后 slack 跟着变 |
| P19 | **+2.964 ns（同域最差格换了路径）** `clkout0_1` 那一格 | `4.094 − 1.130`（**同域不同端点对**：改前 `u_split_ctrl/prod → u_osd/{r,g,b}_reg`，改后 `u_pl/x_d_reg[20][7] → u_osd/ch_r_reg/ADDRARDADDR`） | `build/evidence/r109_clk01_before.txt`（登记在 `report/log/issues.md` #234） | `build/evidence/r109_clk01_after.txt`（同条） | 警告 **半可比**：域内最差格自己动了，但端点对换了 ⇒ 级数 23→21 是结构量可念，+2.964 不许当"同一条锥变快" |
| P20 | **+0.126 ns**（带输入窗那一版的 `clk_fpga_0` setup） | `1.976 − 1.850` | `build/evidence/r114_after.txt:31`（1.850） | `build/evidence/r116_after.txt`（1.976；同数登在 `report/timing/roster_round116.tsv` 第 6 行 `b_wns_setup`） | **跨构建 + 跨约束集**（带输入窗那一版多带一份输入窗）⇒ 只念不判收益（H3，且见 §3 N10）；相对余量那一套口径见 Q1 |

### 2.2 比值 / 百分比类

| # | 派生数 | 公式 | 两个原始数（出处） | 可比性 |
| --- | --- | --- | --- | --- |
| Q1 | **带输入窗那一版的 `clk_fpga_0` "+6.8 %"** | `(0.197600 − 0.185000) / 0.185000` | `report/timing/roster_baseline.tsv` 第 6 行 `rel_margin_setup=0.185000` | `report/timing/roster_round116.tsv` 第 6 行 `b_rel_margin_setup=0.197600` | **跨构建**，按 H3 只念不判收益；"+6.8 %" 这个写法**已由** `report/timing/round_r116.md` §零 打印，这一页引用它 |
| Q2 | **带输入窗那一版的 `clkout0_1` "+1.9 %"** | `(0.184900 − 0.181500) / 0.181500` | 同上 第 9 行 0.181500 | 同上 第 9 行 0.184900 | 同 Q1 |
| Q3 | **撤掉输入窗那一版的 "+13.7 % / −16.8 % / −15.4 % / −0.4 %"** | `(margin_b − margin_a) / margin_a`，单位是**相对余量的百分比变化** | `build/evidence/r114_after_roster_probefmt.txt` 各行 `margin_pct` | 同行号 `build/evidence/r117_after_roster_probefmt.txt` | 这些百分数是**差分工具自己打印的**（`build/evidence/r117_roster_diff_vs_r114.txt` 第 25–26 行：`clk_fpga_0/setup:…(相对余量+13.7%)`、`clkout0_1/setup … −7.6%`（在 #328 表里）、`eth_rxc/setup … −16.8%`、`eth_rxc/hold … −15.4%`、`sys_clk/setup … −0.4%`）⇒ 这一页引用，不重算。**工具账**：#289 记的就是这类打印曾经写成 `+-31.7%绝对`（双符号 + 错单位），修过之后 GAIN/COST 才对称成 `相对余量+X%` |
| Q4 | **基线那一版的 "掉 18.8 % / −5.4 %"** | `(0.1815 − 0.2234)/0.2234`；`(0.053 − 0.056)/0.056` | `build/evidence/r113_after_roster_rf.txt`（登记在 `report/log/issues.md` #293：4.467/0.056 与 22.34 %） | `build/evidence/r114_after_roster_rf.txt`（3.630/0.053 与 18.15 %） | 可比（同生成器 `probe_timing_roster.tcl` 两份配对，#291 定的正确配对）；"18.8 %/5.4 %"这两个数是 #293 打印的 ⇒ 这一页引用。**这一对必须与 P18 同现**（收益+代价同行） |
| Q5 | **"5 片 = 140 片里的 3.6 %"** | `93 − 88 = 5`；`5 / 140` | `report/optimization_log.md` 第 625 行表（RAMB36 采纳基线 93 / 拆后 **88**） | 分母 140 = `build/utilization.rpt:107` 的 `Available` 列（器件 RAMB36 tile 总数） | 可比（同为 `utilization.rpt` 口径）；警告 5 是 **RAMB36 单元数**，而 90.5/95 是 **tile 数**，两个单位不同，不能混着念（tile 口径的差是 `95 − 90.5 = 4.5`，同一张表第 626 行） |
| Q6 | **"6.5 % → 2.3 %"** | `wns / 周期 8 ns` | `report/optimization_log.md` 第 662 行原文（"最快那个域（125 MHz）的 setup 余量从 6.5 % 掉到 2.3 %"），其分子是第 650 行的 +0.516 与 +0.182 | 同左 | 该百分数是**登记在原文件里的**，这一页引用不重算；周期 8.000 ns 见 `report/timing/roster_baseline.tsv` 第 12 行 |
| Q7 | **"0.4 ns 放置摆幅"与"噪声底 0.000"的适用范围** | 不是比值，是两套口径各自的分辨率 | 跨变体两次构建之间那条路的 0.4 ns 量级散布（`report/optimization_log.md` 第 598–599 行；解释在 `report/known_issues.md` §二第 1 条） | 同树重复滚实测 0.000（`build/evidence/r105_ab_rolls.txt:37`；标定件 `build/evidence/r115_noise_verdict.txt`） | 警告 **0.4 ns 是"跨变体两次构建之间"的散布，0.000 是"同一份 DCP 重滚"的分辨率** ⇒ 不许拿 0.4 去否掉一个 +0.204，也不许拿 0.000 去支持"任何绝对差都是真的"（`build/evidence/r105_ab_rolls.txt` 第 36–40 行原话） |
| Q8 | **"+20.47 %"这一格 vs "20.5 %"** | 都是 `4.094/20` | `build/evidence/r109_metric_rotation.txt:7`（报告侧打印 `余量%[clkout0_1] 报告=20.47`） | `report/log/issues.md` #234 叙述里写成"20.5 %" | 同一个数、两种小数位 ⇒ 本表以**报告侧打印的 20.47** 为准，叙述里的 20.5 视为同值引用（不改判定标准、不改数） |

## 3. 属于"不可比"的比较清单（跨器件 / 跨口径 / 跨约束集 / 跨单位）

| # | 被禁止的比较 | 为什么不可比 | 允许的写法 |
| --- | --- | --- | --- |
| N1 | **2026-09-18 优化前基线 ↔ 板上现役那一版发布物**的任何相减或"提升 X 倍" | 约束集只有一份 XDC、`set_clock_groups` 当时未含 MMCM 生成钟（跨域 −6.748 那条是**假跨钟**）；无逐时钟名册；无发布前检查项数口径；RTL 规模不同（LUT 10621 vs 14154、FF 20253 vs 8188）；位流身份未钉 md5 | 只定性说"这一族问题被解决"，**不给倍数、不给百分比** |
| N2 | **早期各版（`build/gates_rNN.txt` 那一代，r62 一直到 r94）各行之间的 WNS 相减** | 检查项数一路在长（早期那份就是那个件名，`report/optimization_log.md` 第 607–608 行明写"跨口径拼接会得到假趋势"）；r63b/r99 之间加的是**新数据通路**（功能代价不是优化结果，第 596 行）；逐时钟名册那时还不存在 | `report/50-results.md` §3 那张表整张标"不可比，仅定性"，且三条"不能读成曲线"的原因一条不省 |
| N3 | **四个域的 WHS 互相比大小**（0.052 / 0.053 / 0.059 / 0.222） | 全工程只有一行自加不确定度 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`（`src/constraints/rk_zynq7020.xdc:50`），其余三域一分没扣；量过：统一那条带 ⇒ WHS **−0.747 / 25,742 失败端点**（`report/log/issues.md` #302、`report/timing/uncertainty_hold_ab.md`） | "四域 hold 全为正在**现行约束集**下为真"；"四域 hold 余量差不多"是约束口径造出来的形状，**不是设计事实** |
| N4 | **`io_unconstrained_ports`（端口数）↔ `TIMING-18`（checks 数）** | 两种量纲；`report/timing/debt_ledger.md` §6 原话"两个数永不相减（附录 1 的量纲红线）"。带输入窗那一版实测：端口 11→6 与 TIMING-18 7→2 **各自都是真的** | 两套口径的数**并列念**，不做减法、不互相"对账" |
| N5 | **`LUT as Logic`（如 `build/evidence/r115_fanout_ab/verdict_header.txt` 里的 9969/10004）↔ `Slice LUTs`（14154）** | 同一次 `report_utilization` 里的**不同行/不同口径**（#301 第 3 条记的就是"按记忆的形状 grep"） | 只在同一列内相减（P10） |
| N6 | **`RAMB36/FIFO` 单元数 ↔ `Block RAM Tile` 数** | tile = RAMB36×1 + RAMB18×0.5（`report/04-resources.md` BRAM 口径节） | Q5 那种"单位先对齐再相减" |
| N7 | **工具估算结温 52.6 ℃ ↔ 板读 XADC 61.2–61.7 ℃** | 两个不同对象（一个是 `power.rpt` 在 Ambient 25.0 / `Max Ambient 57.4` 下的估算，`Confidence: Low`；另一个是板上六次读数的极值，且**钉的是 `build/r113_gates.txt` 那一次构建的位流**） | 各自独立陈述；板侧区间"不是精度声明"（`data/metrics.csv` 第 29 行自己写的） |
| N8 | **147 Mbps 板级读数 ↔ 1000M 线速** | 发送端是 512×300@60 的帧率上限，链路虽协商在 1000M，但没把 RX 打到线速（`report/timing/round_r116.md` "V6 的两条未定"第 1 条） | "在真实流量下不丢字"；**不许**把 147 Mbps 的通过念成 1000M 的通过 |
| N9 | **`tb_v98` 判定标准条数跨轮比**（141 ↔ 161） | 头部 `top_md5` 不同源（`2bf2ceeede07` vs `56c269602e18`）⇒ `report/06-validation.md` §2 已判"计数跨轮不可比，以当前件为准" | 只念当前件的 161/1，并说唯一 FAIL 是声明过的 `C5c` |
| N10 | **带输入窗那一版 ↔ 撤掉输入窗那一版／板上现役那一版的名册** | 约束集不同 ⇒ 拿带输入窗的那一版当对照会把"撤掉一条约束"读成收益（`report/timing/round_r117.md` §〇） | 对照换成**基线那一版**，且两端必须同生成器（混口径会被判 REFUSE，#326） |
| N11 | **与第三方/他人作品的数字比较**（这一页未做过） | 这一页没有引入外部性能数；能引的官方材料只有窗口与规范定义（`report/timing/debt_ledger.md` 里那两个当日追加节、`report/io/hdmi_cts_source_window.md`），它们给的是**规范上限**不是"别人的实测成绩" | 与规范上限比时要写明"规范的对象是 Source Connector，本表只覆盖 FPGA 内部到封装脚"（见 N14） |
| N12 | **仿真通过 ↔ 板级实测** | 本机只有 xsim，`sim/prim/` 是自建行为级占位原语；非打包数组越界写 xsim 丢弃而硬件按地址位宽截断（`report/06-validation.md` §2 射程之外三条） | 这一类问题只用硬件读数收口，不用仿真通过收口 |
| N13 | **名册"逐位相同" ↔ "两版是同一份提交物"** | 板上现役那一版的 B1 与基线那一版八对逐位相同，但 HEAD 里的位流当时还是带输入窗那一版那一块（#332 用 `git show HEAD:build/system.bit \| md5sum` 量出来的） | 身份要用**读回 HEAD 的 md5** 钉，不用名册相同来推 |
| N14 | **"窗已过" ↔ "对外接口已合规"** | HDMI CTS 的对象是 Source Connector，`build/evidence/r119_window_check.txt` 覆盖的是 FPGA 内部到封装脚；且板级走线/连接器离散与眼图/抖动/占空比/沿都未量（`report/timing/debt_ledger.md` 的当日收尾追加节把债改成这两笔） | 写"在'只覆盖 FPGA 到封装脚'这一范围内判 10 项红 0"，两笔未量不能用"窗已过"抵 |
| N15 | **"tap 31 最好" ↔ "硅片最好"** | 工具的两个 I/O 检查取**混合角**（hold 慢钟 / setup 快钟），真实芯片只活在一个角上；"钟网络到 IDDR C 脚"的 C **这颗片子没测过**（`report/log/issues.md` #314） | "τ=31 是报告最优"；板侧 `bad`/`drop_words` 才是裁判 |

## 4. 两套口径对同一份数据给不同判语的登记（口径债，不是选择）

| 数据 | 口径 A（严格） | 口径 B（宽松） | 交付承诺按哪套 |
| --- | --- | --- | --- |
| 撤掉输入窗那一版官方名册相对基线那一版 | 预登记的 A2/A3"在名册的 16 对里任何一格 rel_margin 都不许变小" ⇒ **LOSS×4 ⇒ DECLINED**（`build/r117_verdict_declined.txt`、`report/timing/round_r118.md` §二 B1） | `build/timing_roster_diff.sh` 的 **D3** 门槛是"相对余量掉 25 % 以上的域数" ⇒ `result=GREEN`（`build/evidence/r117_roster_diff_vs_r114.txt:17-23`） | **按严格那套**；没去改宽任何一方 ⇒ 把严格判定标准独立成可指路的件 `build/evidence/r118_strict_b1.txt`（`report/log/issues.md` #328） |
| 板上现役那一版名册 | `B1 pairs_compared=8 losses=0 verdict=GREEN`（`build/evidence/r118_strict_b1.txt:9`） | 同件同时刻 `ROSTERDIFF D3 … big_loss=0 result=GREEN`（`build/r118_verdict.txt` 末行） | 两套都给 GREEN ⇒ 写法仍是"逐格 SAME"，不写"提升" |

**规矩**（#328 末段）：差分件念出来时必须同时念"比较了几对 / 其中几对在跌"，
只念 `result=GREEN` 不算把差分念完。

## 5. 发布前检查与阈值本身的口径（防止"通过"被读成"已验证"）

| 项 | 口径来源 | 注意 |
| --- | --- | --- |
| "判定 24 项 / 未判 0 项" | 发布前检查件末行自己打印（`build/r118_gates.txt:53`）；条数以文件内 `say` 调用次数为准，脚本头部明写"不再写死条数"（`report/06-validation.md` §3） | 与 `data/metrics.csv` 第 14 行的"22 项"不同值 ⇒ 差异 D1，以件为准 |
| "23 绿 / 1 红" | `build/evidence/r118_board/gatesc_summary.txt`：`GATESC done id=identical green=23 red=1`，且两跑逐字节一致（这一格是脚本打印的状态词，原样引用） | 唯一红 = 公开声明保留的 `C5c`（`report/known_issues.md` §一 第 1 条），**不是新失败** |
| "发布前检查通过 ≠ 已验证" | 三条件可指路的理由：`build/gates.sh` 头部"数字全部来自 Vivado 报告本身，不重新跑构建"；`build/tcl/README.md` §1"不要相信退出码"；板上现役那一版的 B4 采纳判据与脚本结尾那句"不采纳，保留上一版"是**两条不同口径的句子**（`report/06-validation.md` §3） | 只念对自己有利的那一句 = 把发布前检查当装饰 |
| 三态 | `PASS / FAIL / NOT_MEASURED`；出问题的分支在脚本里有独立 token（`NO-VERDICT-LINE` 退出码 4、`GATES: PARTIAL`、摘要里的 `?`）（`report/06-validation.md` §1） | 读不到输入 = NOT_MEASURED，绝不等于 PASS |

## 6. 无公式派生量的计数与自查命令

| 项 | 值 | 命令（可复跑） |
| --- | --- | --- |
| `report/40-optimization.md` 与 `report/50-results.md` 里出现的比值/百分比/差值条目 | §2 登记 **20 条 Δ（P1–P20）+ 8 条比值（Q1–Q8）= 28 条** | 逐条见这一页 §2 的表；每条都有"公式"列与前后两个出处 |
| **无公式的派生量数** | **0**（这一页未登记则视为不存在；若读到未登记的派生数即为 FAIL） | 人工核对：`grep -n "%" report/40-optimization.md report/50-results.md`，把每一处对上这一页 §2 或"原始数直接来自件"的例外（下列三条） |
| 三处**不算派生量**的百分数（是件里印出来的） | `utilization.rpt` 的 `26.61 / 7.70 / 68.21 / 8.64 / 24.05 / 25.00 / 50.00 / 13.50 / 2.50`（占比列）；名册 `margin_pct`；发布前检查行的 `BRAM 95.5/68.21%`、`Slice LUT 14154/26.61%` | `build/utilization.rpt:35,37,40,106,121,161`；`build/r118_gates.txt:14,15`；`build/evidence/r118_after_roster_probefmt.txt` |

## 7. 与 `report/measurements.md`、`build/roster/` 的交叉核对（判定标准 5）

**时序**：这一页开工时这两样都不存在 ⇒ 当时判 `NOT_MEASURED`（等 P15b/P15c/P16c 落地）。
写作期间 `build/roster/`、`build/parsed/`、`report/measurements.md` 由并行 agent 落地，核对已补跑；
**`build/runs/`（P15c 那份逐轮记录）仍缺** ⇒ 与之的核对仍是 `NOT_MEASURED`。

| 核对项 | 命令（可复跑） | 结果 |
| --- | --- | --- |
| 名册四域八格 | `cut -f1,2,4,5,6,7,8,9,10,13 build/roster/roster_r118.tsv \| grep -v '^#' \| sed '/^$/d' > /tmp/a2.txt`<br>`cut -f1,2,4,5,6,7,8,9,10,13 report/timing/roster_baseline.tsv \| grep -v '^#' \| sed '/^$/d' > /tmp/b2.txt`<br>`diff /tmp/a2.txt /tmp/b2.txt; echo rc=$?` | 实际输出：**`rc=0`（两份逐字节相同）**，各 9 行 ⇒ `build/roster/roster_r118.tsv` 的八格与这里引用的 `report/timing/roster_baseline.tsv`（= 基线那一版）与 `build/evidence/r118_strict_b1.txt` 完全一致：1.850/0.053、3.630/0.059、0.739/0.052、14.876/0.222；`rel_margin_setup` 0.185000/0.181500/0.092375/0.743800；`intra_endpoint_total` 15721/30179/4835/323。**判定标准 5 的"无不同值"在这一项成立** |
| 探针名册 `margin_pct` | `cat build/roster/roster_r118_probe.tsv`（第 2–6、13–14 行） | 与这一页 §2 引用的 `*_after_roster_probefmt.txt` 同源同行号（该 tsv 的 `source_line` 列直接指回原件行号）⇒ 无不同值 |
| 核心指标行 | 逐条对读 `report/measurements.md` §1 与这一页 §5-results §1/§2（WNS 0.739、WHS 0.052、LUT 14154/26.61 %、FF 8188/7.70 %、BRAM 95.5/140 68.21 %、DSP 19/220 8.64 %、Dynamic 2.213 W、结温估算 52.6 ℃、WPWS 0.264、BUFIO 0） | **数值全部相同** ⇒ 判定标准 5 的"无不同值"成立 |
| 行号引用 | `grep -n "Effective TJA\|Max Ambient\|Junction Temperature\|Confidence Level" build/power.rpt` | 当前件给 `:38/:39/:40/:41`；`report/measurements.md` §1 引作 `:37-38` 与 `:40` ⇒ **行号漂移 1 行，数值本身两边一致**（登记为差异 D7，不改判定标准、不改数，交作者裁决由谁统一） |
| 指标表↔报告的不同源 | 读 `report/measurements.md` §5 的 G1/G2/G3 | 与这一页在 `report/40-optimization.md` §8 登记的 D2/D1/D6 **是同一批差异**（141↔161、22↔24 项、57.5↔57.4 ℃）⇒ 两边结论相同：以件为准、不动 `data/metrics.csv` |
| 板级 XADC | `cat build/evidence/r118_serial_raw.txt` | 板上现役那一版空闲态 60.65–60.85 ℃（`report/measurements.md` §1 与 `build/evidence/r118_board/board_verify_console.txt` 同一份原始回显）⇒ `report/50-results.md` §4 那一格已按两版本两工况列出，不相减 |

## 8. 这一页没有做的事

- 没有重算过表里的格：凡文件自己印了差值或百分数（P5/P6/P9/P15/P16/Q3/Q6），本表引用打印值。
- 没有引入外部性能数（N11）。
- 没有把 WNS 的绝对差写成收益或损失（P18/P20、`build/evidence/r118_after.txt:4`）。
- 没有替 `data/metrics.csv` 改数：三处不同值（D1、D2、D6）与一处行号漂移（D7）只登记、不改数、不取舍。

---
name: global-timing-roster
description: 用于时序改动跑完、需要判断收益是全局的还是"拆东墙补西墙"时；当只有 WNS/TNS 一个数被当成进度、或周期不同的几个时钟域把 slack 摆在一起就判不动的场景。
---

# 按时钟域出名册，再逐格差分

## 适用场景

- 改完时序只有全局 WNS/TNS 一个数，就被写成"本轮进步"。
- 改动抬起了它针对的那格，另一域的格掉了——只看全局最差路径就看不见。
- 几个时钟域周期差好几倍，按绝对 slack 排出来的刀口是错的。
- 一个候选要进构建前，需要预先登记"哪些格变差就否决"。

## 使用方法

**动手前先查**：厂商时序约束／实现用户指南里 `report_timing_summary` 的逐时钟表（Intra／Inter Clock Table）字段定义，以及 `report_timing` 的 Slack 行口径；一手资料优先级 用户指南／数据手册 ＞ 应用笔记 ＞ 教程 ＞ 模型记忆。**先跟用户确认**：哪些域允许带违例、目标频率是谁批准的、允不允许动约束——任何放宽都要落"松动台账"并要有批准人，无人批准就一条不松。

名册 = **每个时钟域出名**，setup 与 hold 各一行（或每域一行两列），列固定：

```
clock period_ns src
wns_setup tns_setup nfp_setup
wns_hold  tns_hold  nfp_hold
rel_margin_setup rel_margin_hold        # = wns_* / period_ns
unconstrained_endpoints io_unconstrained_ports
intra_endpoint_total                     # 附加列，加权用；与上一列量纲不同，别合并
```

跑批伪代码（只读，对已布线检查点问一次，几分钟，不用重构建）：

```
open routed dcp            # 读不到就 REFUSE；不许拿综合后/优化后的顶替
foreach clk in [get_clocks -quiet *]:
    per = PERIOD(clk)
    for kind in setup(-delay_type max) hold(-delay_type min):
        report_timing -from $clk -to $clk -nworst 1 -max_paths N -file one.rpt
        抓 Slack / Logic Levels / Data Path Delay 内 route 的百分比 / Destination
        抓不到 -> 该列 NA（不写空：空同时意味着"这域没路径"和"我正则写坏了"）
        per>0 且 slack 可读 -> rel_margin = slack / per
DESIGN wns whs                         # 全局两个数照样打，但只作背景
结论行: ROSTERDIFF rows=<n> comparisons_made=<n> both_NA=<n> reds=<n> PASS|FAIL|NOT_MEASURED
```

差分纪律：本轮 vs 上一轮**同一把尺子**——同工具版本、同 corner、同 `-nworst/-max_paths`、同窗与不确定度建模。判红三件事：① 任一域的 rel_margin 比上一轮小超过阈值；② 任一其余域从 MET 掉进 VIOLATED；③ 两列"没覆盖"计数变大。阈值不许拍脑袋：同一份 DCP 连跑两次空白滚，逐格差就是这把尺子的噪声底，阈值取它（量到 0 才允许写"不许变小"）。

采纳门槛：**赢的那格与可能跌的那格必须一起摆出来再判**；机制证据（改动是否真落到网表／网络上，独立读数）与结果证据（名册差分）分两行写——机制没动打 `MECHANISM_INERT`，不许写成"没有收益"。

**"绝对 WNS 变化既不是收益也不是损失"为什么成立**：① 域周期不同，1 ns 在 8 ns 域是 12.5%、在 20 ns 域是 5%，同一个数在不同域意味着不同的松紧；② 你一动，最差那格常换族（换起点／终点家族），两个数不是同一条路的两个读数，不可归因 ⇒ 只有同族同口径的差值才可当进度，否则只念不判。

**口径不齐就别比**：各域的不确定度／I/O 窗建模不同（一边按单边扩散量、一边按真窗）时，hold 列就是两把尺子 ⇒ 那一格标 `NOT_MEASURED`，不许写进红或绿。

## 失效条件

- 周期列取错一格 ⇒ 整表自洽但整张全错（slack 与 rel_margin 一起跟着错）；防法是拿一两个周期能从规格算出来的域钉外部真值做对照。
- 把空集当通过：某域没有时钟对象、或点名它的约束静默失效 ⇒ 行数为 0 或 slack 读成 inf，必须 `NOT_MEASURED`。
- 差值两端不是两个有指纹的工件（局部捷径滚 vs 正式构建；改前 DCP 已被覆盖）⇒ 只能照抄数字、不许判进度。
- 名册只有全局最差路径：你以为在改的那条路其实已经被别人的路顶掉了。
- 单位混着减：ns 与 % 相减、端点数与端口数相减。
- 征兆：某域行数为 0 而全表绿；`levels`／`route_pct` 列整列空；结论行没有比较次数。

## 已验证效果

以下读数来自某一次具体设计，量级只用于说明形状，随设计而变，不可当普适结论引用。

- 某次量到：一把改动把最差两格的 setup 相对余量抬到 18.5%→19.8% 与 18.2%→18.5%，同时让一个 8 ns 周期域的 hold 从 0.050 掉到 0.035 ⇒ 只看绝对 WNS 是净收益，名册差分判红否决。
- 某次标定：同一份已布线检查点连跑两次空白滚，逐格差 0.000 ⇒ 这把尺子的噪声底可取 0；跨构建的两端则一律标不可比。
- 某次读数：一域 setup 相对余量 74%（14.876／20 ns）与另一域 9%（0.739／8 ns）——绝对 WNS 前者大得多，相对余量前者松得多，按绝对值排刀口会排反。
- 记账形状：8 个域 × 4 个判定列 = 32 次比较，其中 8 格双侧 NA 仍计入比较次数（计数记"做了多少次比较"，不是通过多少）。

## 来源

长自"只看 WNS 会采纳局部变好、别处变差的改动"这一类失败，以及"相对余量比绝对值更适合跨周期比较"的观察；假绿与计数口径同源于 `ruler-fake-greens`、`three-state-verdicts`；约束覆盖面丢失同源于 `constraint-coverage-loss`；窗与不确定度的建模口径归 `constrain-io-and-clocks`，要动时钟结构则走 `clock-tree-changes-checklist`。

# C2 的测量（SKEW-UNC / ISSUES #265 + #295）：四个域的 hold 余量**不可比**，现已量出幅度

只读探针 `build/tcl/r115_uncertainty_hold.tcl`（件 `build/evidence/r115_uncertainty_hold_console.txt`、
`build/evidence/r115_unc/summary_hold_after.txt`）。打开的是**正式构建的已布线 DCP**
（`impl_1/system_top_routed.dcp`），约束只活在这一次 Tcl 会话里：**没有写 XDC、没有回写 DCP、工程一个字没动**（H1 无松动，也无采纳）。

## 1. 读回路只有一条，而且它真的能用

#295 量到"时钟对象没有 `*UNCERT*` 属性、`set_clock_uncertainty` 不返回对象列表"⇒ 只能读报告正文。实测：

| 时钟 | BEFORE（`Clock Uncertainty:` 行） | AFTER（三条 0.800 设上之后） |
| --- | --- | --- |
| `eth_rxc` | **0.800** | 0.800 |
| `sys_clk` | **读不到该行**（NA） | 0.800 |
| `clk_fpga_0` | NA | 0.800 |
| `clkout0_1` | NA | 0.800 |

NA 不是解析失败：探针在同一次读取里打印了该域路径报告的 `Slack (MET) : 0.222ns` / `0.053ns` / `0.059ns` 那行
（正文第一条 Slack 行照抄进 `UNC-NOMATCH` 行），也就是说报告存在、路径存在、**就是没有不确定度那一行**
⇒ 这三个域的 hold 检查**从来没带过那 0.800 的悲观带**。这条正是 `rk_zynq7020.xdc:50` 只写了一个钟的结果。

`UNC_APPLIED n=3` 之外还有一条硬闸：三个目标没全设上就 `exit 4`（否则 AFTER 的差分没意义）。

## 2. 量出来的代价（这是本轮最重要的一个负数）

给 `sys_clk`/`clk_fpga_0`/`clkout0_1` 也垫上同一条 0.800 hold 带之后，设计级 hold 头条变成：

```
WHS = -0.747 ns   THS Failing Endpoints = 25742   WPWS = 0.264 ns   TPWS Failing = 0
（列名取自该报告自己的表头：WHS(ns) THS(ns) THS Failing Endpoints THS Total Endpoints WPWS(ns) …）
```

`-0.747 = 0.053 - 0.800` 逐位对上 `clk_fpga_0` 现在报的那 0.053（件 `report/timing/roster_baseline.tsv` 的 `wns_hold`）
⇒ 这不是新出现的物理问题，是**同一条路径在换尺子之后的读数**。

**结论（三条，都不带板级口吻）**：

1. 名册的 hold 列现在确实是**两把尺子**：eth_rxc 的 0.052 是"垫了 0.800 之后"的数，其余三个域的 0.053/0.059/0.222 是"没垫"的数。
   交付文档里"四域 hold 全为正"这句话在**现行约束集**下是真的，但它**不能**被读成"四个域都有同等的 hold 信心"。
2. 把带子统一（加严方向，H1 允许）会让 25,742 个 hold 端点报失败 ⇒ 这不是违例，是**债的显形**。
   所以这一条**不能由我在夜里采纳**：G3 要求"每条松动/每条会让读数变差的改动都要有批准人"，用户睡了。
   台账见 `report/timing/loosen_ledger.tsv`（本轮 0 条：我没放松任何东西，也没加严到工程里）。
3. 但它必须先被知道，否则下一轮的 C4（补 I/O 窗口）会把两笔债混在一起：
   RGMII 真窗 → hold −2.885（r114 量过，件 `build/evidence/r114_io_roll_console5.txt`）；
   统一悲观带 → hold −0.747（今夜量出）。**两个数来自不同的检查对象，永不相减**（附录 1 的量纲红线）。

## 3. 交给用户决定的一件事

要不要把 `set_clock_uncertainty -hold` 从 eth_rxc 一处扩到四个域（`rk_zynq7020.xdc:50` 那行复制三份，
一条命令一个钟，绝不并名——`get_clocks` 取不到任何一个会让整条命令空转，见该文件 `:43-46` 的旧账）？
- 好处：hold 那一列变成可比的四行，G1 的 hold 判定从此是硬的；
- 代价：交付文档里所有 hold 数字会变难看（25,742 个失败端点会出现在报告里，虽然它们没有物理含义的变化）；
- 我的建议：**在 C3（捕获钟）之后再做**，否则读数会被两笔债同时压着，分不清是哪笔。

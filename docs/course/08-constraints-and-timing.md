# 08 约束与时序收敛：原理 → 实现 → 取舍

## 1. 原理：约束不是"让工具别报错"，是**告诉工具真实的物理关系**

时序报告里的每一个 slack 都是"约束所说的世界"与"真实世界"的差。
所以约束写错，工具不会告诉你——它只会给出一个**自洽但虚假**的结论：

- 少写一条输入窗 ⇒ 工具认为外部数据随时可以变 ⇒ **setup 看着很好，hold 根本不判**；
- 把两朵钟声明成异步组 ⇒ 它们之间的路**从所有报告里消失** ⇒ 跨域同步器的实际延迟没人检查；
- uncertainty 只给 hold 不给 setup ⇒ 这一族的 hold 被额外扣了 0.8 ns，
  而 setup 侧没有对应的余量预算，两把尺子就不对称了。

本工程的四朵钟与它们的关系：

| 钟 | 从哪来 | 周期 | 声明位置 |
|---|---|---|---|
| `sys_clk` | 板载晶振，进 MMCM | 20.000 ns | `src/constraints/rk_zynq7020.xdc:6`` |
| `eth_rxc` | PHY 恢复出的 RGMII 时钟，**是输入引脚上的源同步钟** | 8.000 ns | `:36` |
| `clk_fpga_0` | PS7 IP 在自己的 XDC 里 `create_clock` 的 | 10 ns（100 MHz） | `:65-66` 的说明块 |
| `clkout0_1`/`clkfbout*` | MMCM 输出 | 见名册 | BD/MMCM 生成 |

`clk_fpga_0` 这一行值得单独看：`:65-68` 记录的是"**不要再去 `create_clock` 它**，
它是 PS7 IP 的 XDC 自己建的；再建一次会撞出 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups`"。
工具生成的 IP 约束与手写约束的关系必须**读出来**而不是试出来。

## 2. `set_clock_groups` 的代价：报告里"没有路"不等于"没有路"

`src/constraints/clock_groups_impl.xdc:28`` 把三组钟两两排除（`-asynchronous`），并且这块 XDC 只在实现阶段生效
（`build/tcl/build_system_axigpio.tcl:37`，见 `01`）。
好处是真违例不再出现；坏处是**同步器那几条路也从任何尺子里消失了**。

`src/constraints/r114_io_async.xdc:48-50` 把这件事写得很清楚：

> 现状（r113 量的）：`set_clock_groups -asynchronous` 把三组钟两两排除 ⇒ 这四条跨域路
> 在任何尺子里**都不出现**……全靠布线碰运气。UG949 的口径是：同步器这类路不该完全 false path，
> 应该给 **`set_max_delay -datapath_only`**。

于是有了 `:57-63` 那四条上界（`eth_rxc → clk_fpga_0` 10.000、反向 8.000、
`clk_fpga_0 ↔ clkout0_1` 20.000/10.000）。**关键事实**：这个文件目前**没有被构建加载**
（`01` 第 3.2 节只加载两块 XDC），所以这四条上界还没进报告——
"文件写在仓库里"与"约束生效"是两件事，后者要在 `build/check_timing_verbose.rpt`
或 `report_exceptions` 里读到才算。

## 3. RGMII 输入窗：先量到"根本没写"，再谈值该给多少

`src/constraints/r114_io_async.xdc:36``：

> ⚠ 这一组约束以前**完全不存在**（`set_input_delay` 在整棵 `src/constraints` 里 0 次，
> `#57` 立案时量到的）

`:39-43` 给的是按 RGMII 规范的双沿窗（`-max 0.500 / -min -0.500`，上升沿与下降沿各一组）。
工具端的证据链是两条：`build/report/methodology.rpt:2245` 的 TIMING-18
（"An input delay is missing on eth_rx_ctl relative to the rising and/or falling clock…"）与
`build/check_timing_verbose.rpt:52-61` 的未约束端口清单。

**量到的后果**（这是本章最重要的一条）：挂上真窗以后 hold 立刻变成
`slack = −2.885 ns`，而那条路的逻辑级数是 2、route 占比 0 %
（`report/log/issues.md` 的 r116 那一节）。也就是说 −2.885 **不是 DUT 坏了，是维度变了**——
过去这条路根本不在射程内，挂窗那一刻才开始判它。
所以 r116 的做法是：**把窗作为候选件退回，不在同一轮里同时改 RTL 与改口径**。

顺带一条器件边界：TMDS 那 6 个输出脚的接收窗在 UG471 里只给 `TMDS_33` 属性、**没有接收窗数值**，
所以那 6 个端口的窗是"查过的否定"，不是"还没查"（凭据与推导在
`src/constraints/r119_hdmi_source_window.xdc` / `r119b_hdmi_tp1_pinclk.xdc`，
取的是 HDMI 规范源端 TP1 的口径而不是 UG471，也不是 sink 的 TP2）。

## 4. 读一份时序报告，必须同时读的六个数

只看 WNS 会得出错误结论。本工程固定的读法（名册生成件
`build/tcl/probe_timing_roster.tcl`，产物如 `build/roster_r118_after_eth_rxc_setup.rpt`）：

| 数 | 位置 | 为什么必须看 |
|---|---|---|
| WNS 绝对值 | 汇总第 7 行 | 只是"合不合"，不是"好不好"（周期不同不可比） |
| **相对余量** | WNS / 周期 | `eth_rxc` 的 0.739/8 = 9.24 % vs `clk_fpga_0` 的 18.15 %——**跨域只能比这个** |
| 失败端点数 | 汇总 | 0 才谈得上收敛 |
| 逻辑级数 | 路径详情 | 区分"深度问题（可改 RTL）"与"绕线问题" |
| route 占比 | `Data Path Delay: 7.066ns (logic … route 4.130ns (58.447%))` | 占比高 ⇒ 改逻辑收益有上限 |
| hold 与它的 uncertainty | 同报告 | hold 带不对称时，两朵钟的 WHS **不可直接比** |

**规矩 35**（工程内化的纪律）：跨构建的 WNS 绝对差**既不算收益也不算损失**；
能写的只有"仍收敛、瓶颈在哪一域、代价多少 LUT/FF"。同树重复滚动会被放置确定性骗过去
（`#223` 结案：那对 0.4 ns 差既不同树也不同路），所以只做**单变量 A/B** 或扫策略。

## 5. 快车道：怎么便宜地验一个反事实

改 RTL 的判断要花钱（综合 + 实现 ≈ 一轮 20 分钟以上）。工程里有一条不用重综合的车道：
从 `impl_1/*_opt.dcp` 出发**重跑布局 + 布线**，约 7–9 分钟，
可以判断"这一轮的 WNS 移动是真的还是骰子"——本工具的放置是确定性的
（一次滚动逐位复现了正式构建的数字）。
读法：`open_checkpoint` 之后 `place_design` / `route_design`，再 `report_timing_summary`。
**不要**用它来判定收益归属（那是名册的事），只用它做反事实对照。

## 6. 什么动作是"结构性指令"，不是"优化开关"

`phys_opt_design -force_replication_on_nets`（`01` 第 3.5 节那个 `IMPL_PRPO` 钩子）会**复制驱动**，
于是网表多出 `*_replica` 单元。r117 用官方构建量过：239 引脚的广播网确实被复制了
（机制生效的证据就是这些 replica），但**赢 1 格跌 4 格，含最紧的两格** ⇒ 判负。
同类：`ASYNC_REG` 是结构声明、`ram_style="distributed"` 是结构声明（`02`、`05`），
它们会改变网表形状，所以每次改动都必须重新生成**配对的名册**再差分
（名册必须同生成器配对，混口径会 REFUSE）。

小结：约束这一层的纪律是——**先量到"有没有"，再讨论"给多少"**；异步排除让路消失不是让路变好；
跨域只比相对余量；WNS 绝对差不算收益；结构性指令要用网表证据（replica / INIT / ASYNC_REG 计数）
证明它真的动了。
下一步：`09-verification-system.md`。

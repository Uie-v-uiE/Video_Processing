# 逐时钟时序读数（板上这一版）

组织单位是时钟域，不是"最差那一根路径"。每一格都点名它是哪一件产物的哪一行；产物里
没有的格不补写，也不拿邻近域的数替它答话。这样做的原因只有一个：只看全局最差那条路径会盖住
其他域的退化。规矩与工具在 `report/timing_global.md` §1 第 5 条与 §5。

## 1. 三个量的口径

- **setup slack / hold slack**：`report_timing` 的 `Slack` 行，逐时钟清单对每个域取最差那一格。
- **相对余量 = slack ÷ 周期**：清单文件自己把这个商印成 `margin_pct` 字段（件
  `build/evidence/r118_after_roster_probefmt.txt` 的
  `ROSTER|setup|clk=…|period=…|slack=…|margin_pct=…` 行）。下面直接引用它，不重算、不换算法。
- **端点数**取同一次构建的 `build/timing_summary.rpt`（Intra Clock Table 的
  `TNS Total Endpoints` / `THS Total Endpoints`、Inter Clock Table 的跨域两行）。
  发布前检查件 `build/r118_gates_final.txt` 末段的"端点总数 51135"来自同一次构建；那份件的新鲜度行
  记录位流与时序报告在这一次构建里前后写出，相隔 34 s。
- 产出这三样的工具（`report/timing_global.md` §5 点名）：`build/tcl/probe_timing_roster.tcl`（改后侧，
  只读打开已布线 dcp）、`build/roster_from_summary.sh`（改前侧，从归档的 `timing_summary.rpt` 重建清单）、
  `build/timing_roster_diff.sh`（逐域配对，输出 D1..D6 六类差分结论）。

## 2. 逐时钟清单（板上现在跑的是 r118，板与仓库同一版；位流身份 `build/r118_gates_final.txt` 的
`身份：system.bit md5=cd04907e1369`）

下面"上一版"一律指本仓库此前采纳的那一版，它的清单件是
`build/evidence/r114_after_roster_probefmt.txt`；"复制实验版"指带强制复制广播网的那一版，
记录在 `report/timing/round_r117.md`。两版的构建都留在仓库里，路径见文末清单。

| 时钟 | 周期 ns | setup slack / 相对余量 | hold slack / 相对余量 | 端点 | 该域最差路径（终点 / 级数 / 布线占比） |
| --- | --- | --- | --- | --- | --- |
| `eth_rxc` | 8.000 | **0.739 / 9.24 %** | 0.052 / 0.65 % | 4835 | setup `u_eth/u_icmp/u_icmp_tx/check_buffer_reg[19]/D`，4 级，route 58.447 %；hold `u_eth/u_lm/full_d_reg/D`，1 级 LUT4，route 56.480 % |
| `clk_fpga_0` | 10.000 | 1.850 / 18.50 % | 0.053 / 0.53 % | 15721 | setup `u_pl/u_bilin/u_fb/lo_reg_0_16/WEA[0]`，1 级 LUT6，route **93.584 %**；hold `…axilite_b2s/RD.r_channel_0/rd_data_fifo_0/memory_reg[31][9]_srl32/D`，0 级，route 43.472 % |
| `clkout0_1` | 20.000 | 3.630 / 18.15 % | 0.059 / 0.29 % | 30179 | setup `u_pl/u_osd/ch_r_reg/ADDRARDADDR[6]`，21 级（含 9×CARRY4），route 59.150 %；hold `u_pl/u_pipe/u_sobel/no_right_r_reg[1]/D`，0 级，route 62.683 % |
| `sys_clk` | 20.000 | 14.876 / **74.38 %** | 0.222 / 1.11 % | 323 | setup `u_pl/u_ang/angle_reg[3]/D`，5 级，route 74.015 %；hold `u_pl/u_k2/cnt_reg[8]/D`，0 级，route 50.893 % |
| `clkfbout`、`clkfbout_1` | 20.000 | `slack=NOWRITE` / `margin_pct=NA` | 同左 | 这两行没有 setup/hold；`build/timing_summary.rpt` 只有脉冲宽度行 18.408 ns / 3 端点 | — |
| `clkout1_1` | 4.000 | `NOWRITE` / `NA` | 同左 | 脉冲宽度 2.408 ns / 10 端点 | — |
| `clkout2` | 5.000 | `NOWRITE` / `NA` | 同左 | 脉冲宽度 **0.264 ns** / 3 端点（全设计最小 WPWS 就是这一行） | — |

跨域两行（`build/timing_summary.rpt` 的 Inter Clock Table，这份表里只有这两对）：
`sys_clk → clkout0_1` setup 3.695 / hold 0.200（231 端点）、
`clkout0_1 → sys_clk` setup 14.757 / hold 0.165（19 端点）。
其余跨域对不进这张表：`src/constraints/clock_groups_impl.xdc:28-31` 那条
`set_clock_groups -asynchronous` 把三组钟互相排除，代价与因此留下的未覆盖项见
`report/timing_global.md` §4c。

`NA` 的口径在 `report/timing/debt_ledger.md` §1 已经写过并固定了读法：
"NA 是『这一族没有同沿路径』，不是『我读不到』"。所以这四行这里只报"清单里没有它们的
setup/hold 行"，不报"这四颗钟没问题"——两者的区别见第 7 节。

## 3. 本版与上一版：8 对读数逐位相同

件 `build/evidence/r118_strict_b1.txt` 每行给一对"上一版 / 本版"的同一个读数并带差值字段 `d=+0.000 SAME`，
共 8 对；末行 `B1 pairs_compared=8 losses=0 verdict=GREEN`：`clk_fpga_0` 1.850 / 0.053、
`clkout0_1` 3.630 / 0.059、`sys_clk` 14.876 / 0.222、`eth_rxc` 0.739 / 0.052。
`build/r118_verdict.txt` 的 `R118 B1_strict … verdict=GREEN` 是同一件事的判定行，
`report/timing/round_r118.md` §四把它登记为 B1 这项条件的结论。

这条"逐位相同"不是巧合，也不能读成"这一处改动没生效"：`IDELAY_VALUE` 动的是 I/O 单元里的
抽头，不动片内任何一条锥（`report/timing/round_r118.md` §一），所以片内清单本来就该逐位复现。
它顺带交付的是**可复现性**：同一份网表重跑放置/布线逐位复现，与标定出的 `noise_ns = 0.000`
（`report/timing_global.md` §6.2 末、`report/log/issues.md` #297）是同一条事实。
对照侧必须由**同一个生成器**产出：这一组的配对是
`build/evidence/r114_after_roster_probefmt.txt` → `build/evidence/r118_after_roster_probefmt.txt`
（两个生成器的输出相减会被 `build/timing_roster_diff.sh` 判为无效对照并拒绝，
`report/timing_global.md` §9、`report/log/issues.md` #326）。

## 4. 这一版的收益在片外那一侧：+0.315 ns，而且它是"违例变小"

- **是哪一侧的量**：RGMII 收口"片外数据到达时刻 vs IDDR 捕获沿"那一侧的窗余量，
  **不是**片内任何一格 slack。件 `build/evidence/r115_window/probe3_console.txt`：
  同一份已布线 dcp、同一套测量脚本、带候选窗，`W3S tap26 HOLD … -1.185ns` 与 `W3S tap31 HOLD … -0.870ns`
  相差 0.315 ns；`SETUP` 两行同批（tap26 −0.386 / tap31 −0.846）。
  两条实测直线 `HOLD(τ) = −2.822 + 0.0630τ`、`SETUP(τ) = +2.005 − 0.0920τ`
  写在 `report/timing/round_r118.md` §一，也记在 `report/timing/cut_ledger.tsv` 的 C8 行——
  该行的"预期收益"格原文是 `+0.315(最差格 -1.185 -> -0.870，同一把尺子同一只 DCP 实测)`；
  那个文件里的"尺子"指测量脚本。
- **两条读数都带 `Slack (VIOLATED)`**（件里那四行原文），所以这一格的诚实写法是
  "在这一族被检查的窗上，最差那一档从 −1.185 抬到 −0.870"，**不是** "+0.315 ns 时序收益"。
- **而且它当前不在被约束的接口上**：本版不加载那个输入窗（第 6 节），所以这 0.315 ns 落在一个
  现在没有被约束建模的接口上。这也是这一处的通过条件不能写成"WNS 变好"的原因：τ 只动抽头
  （这条要求在 `report/timing/round_r118.md` §一末登记过）。
- **另一半事实**：`report/log/issues.md` #314 记的是工具口径——两项 I/O 检查各取一个角
  （hold 查慢角、setup 查快角），真实芯片只工作在一个角上，而"钟网络到 IDDR 的 C 脚"那一段延迟
  **这颗片子没有实测过**（件里只有两个角的数）。所以 τ=31 是"报告里最好"的档位，
  不是"硅片上最好"的证明。

## 5. 广播网强制复制：量过、赢了指定那一格、被判不采纳

复制实验版（只带 `IDELAY_VALUE`=31 加上强制复制那根 239 引脚广播网）对上一版清单的实测
（件 `report/timing/round_r117.md` §〇/§三 与 `report/timing_global.md` §9 的同一张表）：

| 域 / 格 | 上一版 | 复制实验版 | 读法 |
| --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.850 ns（18.50 %） | **2.104 ns（21.04 %）** | 赢 +0.254 ns——这正是这一处瞄准的那一格 |
| `clkout0_1` setup | 3.630 ns（18.15 %） | 3.353 ns（16.77 %） | 跌 |
| `eth_rxc` setup | 0.739 ns（9.24 %） | 0.615 ns（7.69 %） | 跌，且这是全设计绝对最紧那一格 |
| `eth_rxc` hold | 0.052 ns | 0.044 ns | 跌，且这是全设计最小的一格 |
| `sys_clk` setup | 14.876 ns | 14.815 ns | 跌 |

机制**没有可疑**：`impl_1/runme.log` 与 `build/r117_a1_read.sh` 两处输出都记到
`u_pl/u_row/hi_reg_0[0]` 从 239 引脚折到 1、长出 10 颗 replica（`report/timing/round_r117.md` §二之二
把 `R117HOOK … pins_before=239 / pins_after=1 replica_cells=10` 两行原文抄在里面，
那一版的位流是 `beda9298331d`）。
⇒ 结论是"**生效了，代价落在含最紧两格在内的四格上**"，不是"这一处没动"。
动手之前预登记的通过条件是严格口径"任何一格相对余量不许变小"
（`report/timing/round_r118.md` §二 B1 那一段），四格跌即不采纳，件
`build/r117_verdict_declined.txt`，登记行 `report/timing/cut_ledger.tsv` 的 C9 行末列
`declined(official r117: clk_fpga_0 1.850->2.104 wins but clkout0_1/eth_rxc/sys_clk four cells lose …)`。

**两套测量脚本对同一份数据给了不同结论**，这件事没有靠改宽任何一方来消除：
`build/timing_roster_diff.sh` 的 D3 门槛是"相对余量掉 25 % 以上的域数"，对复制实验版那组数给
`result=GREEN`；严格那套给 LOSS×4。账记在 `report/log/issues.md` #328，处置是把严格条件
**独立成可指路的件** `build/evidence/r118_strict_b1.txt`，交付承诺按它判
（`report/timing_global.md` §9 第 4 段）。形状与更早一次夜间改动里的 C1 复制相同
（`report/log/issues.md` #288、`report/timing_global.md` §4e：机制动了、目标族 +0.456 ns，
代价是 `eth_rxc` hold 0.050→0.035 ⇒ 放弃）。

## 6. RGMII 输入窗：0…31 全档无解 ⇒ 退回候选件，代价明写

- **为什么退回**：绑上窗之后 `build/gates.sh` 的四条发布硬条件（WNS ≥ 0、失败 setup 端点 == 0、
  WHS ≥ 0、失败 hold 端点 == 0）机械判为未通过，而脚本结尾写死"有未通过项 ⇒ 不采纳，保留上一版"。
  处置是**默认不加载**、原件与全部证明留在仓里当候选件，复现带窗那一版只要
  `VP_R116_IO_WINDOW=1` 再构建一次（构建脚本自己写着理由：
  `build/tcl/build_system_axigpio.tcl:28-52`，加载分支打印
  `VP_R116_IO_WINDOW loaded（…预计 5 个 I/O 端点会红）`，默认分支打印
  `VP_R116_IO_WINDOW off（RGMII 输入窗留在候选件 src/constraints/r116_rgmii_input_window.xdc…）`）。
  这一处**不是放宽**：`report/timing/loosen_ledger.tsv` 里的数据行是 0，那份记录表的两处登记
  （表头注释与 `report/timing_global.md` §8）写的都是"放宽类改动 0 条数据行"，
  其中表头注释那一条来自更早的一次夜间改动。撤掉的是"这一版新增的约束"，
  上一版本来也没有它（`report/timing/round_r117.md` §〇）。
- **为什么它无解**：`report/log/issues.md` #311 的两条区间——
  hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，合法 τ 只有 0…31 ⇒ 不相交；去掉那条 0.800 的带只把下界挪到
  32.1，仍与 21.8 不相交。分量层的同一件事：钟网络 hold 查慢角 DCD 5.008 / setup 查快角 DCD 1.597，
  角间差 **3.411 ns**，而数据侧两角只差 **0.467 ns**（件与推导见
  `report/timing_global.md` §6.1、`report/timing/limit_audit_r116.md`）。
- **代价**：这一版没有窗 ⇒ `eth_rx_ctl` 与 `eth_rxd[3:0]` 这 5 个收端点
  **没有被任何输入延迟约束覆盖**。`report/timing/debt_ledger.md` §2 把那 5 个名字点得很清楚，
  并且写着现行 `eth_rxc` 的 WHS 0.052 是"假设数据恰好在时钟沿到达"量出来的**片内**数，
  不含 PHY→FPGA 走线与 PHY 内部延迟那一段。所以第 2 节那格的读法是"片内这一族 MET"，
  **不是**"收口达标"：没被检查不等于达标（`report/timing_global.md` §9 第 ④ 条、
  `report/timing/round_r118.md` §四末列出的"不许写的第三句"）。
  `build/r118_gates_final.txt` 的 check_timing 一侧也没有替这 5 个端点说"通过"：那一版未通过的
  是另一项——顶层仿真台架 `sim/tb_v98_top_seam.v` 自己的 C5c 判为未通过（帧首若干行在分割线两侧仍带
  上一帧的内容，件 `build/tb_v98_report.txt` 的 `FAIL C5c …` 行与末行
  `RESULT tb_v98_top_seam FAIL nfail=1`），而这 5 格根本不在被检查的集合里。发布前检查判定 24 项，
  除这一项之外全部通过。要留意两处结论的写法不同：检查脚本结尾按"有未通过项"机械印的是
  "不采纳，保留上一版"（`build/r118_gates_final.txt` 末行），而这一版是按预登记的 B4 条件
  （未通过项必须正好 1 个、且就是声明过的 C5c）被采纳上板的（`report/timing/round_r118.md` §二）。
- **还有一处没覆盖**：同一份 `report/timing/debt_ledger.md` §2 记着输出侧有 6 个端口没有
  output delay（`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0]`…`tmds_data_p[2]`），
  合计 `io_unconstrained_ports` = 11，这一半也没有数。

## 7. 这份清单不支持的三类说法

1. **"每个时钟都到边界"这种说法没有依据。** 它实际显示的是：`sys_clk` setup 相对余量 74.38 %、
   323 端点，`report/timing_global.md` §6.3 给它的结论就是"谁都不是：离任何边界都远"；
   `clkout0_1` 那一格顶住它的是 OSD 地址/字符算术锥的**级数**（清单行印 21 级、含 9×CARRY4，
   route 59.150 %），再要收益只能继续砍级数＝改功能，不在时序这一处改动的授权范围里（§6.3）；
   `clkfbout`/`clkfbout_1`/`clkout1_1`/`clkout2` 四行在清单里是 `NOWRITE`/`NA`，
   它们的状态是"没有同沿路径行"，而不是"已被证明关不掉"。
2. **四个域的 WHS 不是同一套约束下量出来的。** 本版只有 `eth_rxc` 在保持方向加了自算的不确定度
   （`set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`，`src/constraints/rk_zynq7020.xdc:50`；
   `report/timing_global.md` §4 "自加不确定度"那一行写的就是这个不对称），其余三域一分没扣。
   ⇒ 第 2 节那四个 hold 数（0.052 / 0.053 / 0.059 / 0.222）只可同域比较，不可跨域比大小；
   "四域 hold 余量差不多"是约束写法造出来的形状，不是设计事实。
   把同一 0.800 带给每个钟量一次的结果是**测量、不是采纳**：
   全设计 WHS −0.747 / 25,742 失败端点（`report/log/issues.md` #302）。
3. **板侧那 5 个端点的真实差额没有数。** 结论不能写成"板上真实 hold 差额就是 −0.870"：
   窗模型自身还有 `TskewR` 那一行可能被混用的残余风险
   （`report/timing/rgmii_window_model.md` §6/§7.5，登记句在 `report/timing/round_r117.md` §四
   与 `report/timing/round_r118.md` §四末"不许写的两句"）。也不能写"换短钟也关不掉"——
   BUFIO 的快角 DCD 还没实测（`report/log/issues.md` #323：本机两本官方手册按
   "同一行既有数字又落在钟语境里"筛，命中 0 页；这句只到"没筛出来"）。

## 8. "到极限"这句话能说到哪一步

能说的范围以指得出件为限（`report/timing_global.md` §9 末与 `report/timing/round_r118.md` §四给的是
同一段）：四个域逐格要么为正、要么被证明了关不掉；非放宽的物理手段（策略扫描、同 dcp 重跑
放置布线、Pblock、BRAM 换 setup、复制广播网 C9、灰码 `ASYNC_REG`、τ 扫档）已逐一量过并给出赢或
不采纳的结论；唯一还能改变结论的是架构那一处（IDDR 吃短捕获钟 + 一级同步 FIFO 再进 BUFG 流水线），
门槛与代价面在 `report/timing_global.md` §7，动手前欠一个 40 秒只读实测（BUFIO 快/慢角 DCD，
`report/log/issues.md` #323）。这里**不包含**"所有时钟都到物理极限"这个结论。

## 依据的产物
- `report/timing_global.md`（§1 方法、§4 约束侧未覆盖项、§4c 异步组、§4e C1 复制、§5 清单工具、§6 逐域极限审计、§7 下一处靶子、§8 松动记录、§9 复制实验与本版两处的结论）
- `report/timing/round_r118.md`
- `report/timing/round_r117.md`
- `report/timing/cut_ledger.tsv`
- `report/timing/debt_ledger.md`
- `report/timing/limit_audit_r116.md`
- `report/timing/loosen_ledger.tsv`
- `report/timing/rgmii_window_model.md`
- `build/evidence/r118_strict_b1.txt`
- `build/evidence/r118_after_roster_probefmt.txt`
- `build/evidence/r115_window/probe3_console.txt`
- `build/r118_verdict.txt`
- `build/r118_gates_final.txt`
- `build/timing_summary.rpt`
- `build/tcl/build_system_axigpio.tcl`
- `src/constraints/rk_zynq7020.xdc`
- `src/constraints/clock_groups_impl.xdc`
- `report/log/issues.md`（#288、#297、#302、#311、#314、#323、#326、#328）

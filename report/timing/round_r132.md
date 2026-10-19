# r132 结果页（现版补账：逐域名册重导、两条候选约束臂、一臂判 NOT RUN）

写于 2026-10-20 凌晨。链子 `build/r132_timing_round.sh` 01:19:07 起飞，基线是板上那一版
（位流 md5 前 12 位 `cb907d3e4898`，2026-10-17 11:35 产出）。这一页只放**有件的数**；
依赖在飞构建的格子标 `【链子跑完后填】`，不提前涂绿（同 `report/timing/round_r118.md` 的规矩）。

## 一、这一轮要量的三件事

1. **现版逐域名册**。上一份名册是 r118 的，中间隔了十几版 RTL；台账 #479 末段挂着
   "逐域名册整份重导"这笔债。报告 1.4 与 3.3 附表念的八对读数，此前没有一件现版的探针件撑着。
2. **两条候选约束臂在现版上的读数**。`src/constraints/r119_hdmi_source_window.xdc` 与
   `src/constraints/r116_rgmii_input_window.xdc` 都是"候选件、默认不加载"，构建脚本里各留一条
   环境变量开关；前者注释自己写着"缺的是一次量名册的构建"，后者上一次量是 r114/r116 的事。
   报告 4.1 第 1 条与 4.2 那句"一挂整个时钟域全红"就吊在这两条臂上。
3. **一只旗标到底是不是高扇出**。现版 clk_fpga_0 最差那条起点是 `u_pl/u_arb/owner_eth_reg/C`，
   1 级逻辑、布线占 92.71 %。报告与 `report/timing/eth_rxc_partition_options.md` 都写着
   "能动的是这只高扇出旗标的复制与摆放"。

## 二、判据（起飞前登记在链子头部，不接受事后改口径）

| 编号 | 判据 | 尺子 |
| --- | --- | --- |
| P1 | 该臂的声明行必须出现在构建控制台（`VP_R1xx_... loaded` 或 `R117HOOK`）；没有 ⇒ 这一臂 NOT PROVEN，不念数 | 隔离目录的 `build_console.txt` |
| P2 | 名册八对（4 域 × setup/hold）逐格对 r132 基线，`margin_pct` 不许变小（严格口径，与 r118 的 B1 同一条） | `build/timing_roster_diff.sh` 加一份逐格念读 |
| P3 | 该臂要量的东西真量到了：A 要 250 MHz 那一族的读数与全设计 WNS/WHS/失败端点；B 要 eth_rxc 的 hold 与 I/O 端点红数 | 隔离目录的 `timing_summary.rpt` |
| P4 | 资源账要念出来；只有复制臂允许 FF 增加，其余不许动 | 隔离目录的 `utilization.rpt` |
| 采纳 | 只有 P2 全过且 P3 显示目标域确实变好的臂进采纳评估，且要第二滚同向（规矩 35）。A/B 是"把欠账量出来"的臂，**红也是结论**，不为了绿去摘约束（H1） | — |

## 三、基线名册（有件：探针 `build/tcl/probe_timing_roster.tcl` 在现版 routed dcp 上只读跑）

探针件 `build/evidence/r132_after_roster_probefmt.txt`（448 行控制台里挑出的 38 行），
逐时钟原件 16 份 `build/roster_r132_<clk>_<setup|hold>.rpt`。

| 域 | 周期 ns | setup slack | hold slack | 最差那条的终点 |
| --- | --- | --- | --- | --- |
| `clkout0_1` | 20.000 | 3.287（16.43 %，22 级） | 0.067 | `u_pl/u_osd/ch_r_reg/ADDRARDADDR[6]` |
| `clk_fpga_0` | 10.000 | 1.571（15.71 %，1 级、布线 92.71 %） | 0.048 | `u_pl/u_bilin/u_fb/lo_reg_0_40/ADDRARDADDR[7]` |
| `eth_rxc` | 8.000 | 0.687（8.59 %，5 级、布线 79.96 %） | 0.004（布线 78.01 %） | `u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][10]/R` |
| `sys_clk` | 20.000 | 14.294（71.47 %） | 0.121 | `u_pl/u_ang/angle_reg[6]/D` |
| `clkout1_1`（TMDS 250 MHz） | 4.000 | `NOWRITE` | `NOWRITE` | — |
| `clkout2`（IDELAY 参考 200 MHz） | 5.000 | `NOWRITE` | `NOWRITE` | — |
| `clkfbout` / `clkfbout_1` | 20.000 | `NOWRITE` | `NOWRITE` | — |

两件事从此有了件：**①** 报告 1.4 与 3.3 附表念的八对数与探针读数逐格相同，不再是"引用上一版名册"；
**②** `NOWRITE` 的含义按 `report/timing/debt_ledger.md` §1 的口径是"这一族没有同沿路径"，
不是"我读不到"——所以"250 MHz 串行域不设检查项"这句话的根据是**没有可量的同沿路径**，
真正欠的是**对外那一段**（源端窗口、走线失配扣除、眼图），那正是臂 A 要量的。

## 四、臂 A（HDMI 源端窗，绑在 `clkout1_1` 上）——量到了，但红得不该算数

链子 01:19:07 起飞、01:34:53 出件（`build/isolated_r132_tmdswindow/`，探针件
`build/evidence/r132_tmdswindow_roster.txt`、差分 `..._diff_vs_r132.txt`、摘要 `..._timing_summary.rpt`）。

- **P1 在位**：控制台里 `VP_R119_TMDS_WINDOW loaded`，窗确实进了实现。
- **`clkout1_1` 从此可量了**：基线是 `NOWRITE`（没有同沿路径），带窗之后
  setup **−5.408 ns**（TNS −32.363，6 个失败端点 / 该族 6 个）、hold **−1.923 ns**（THS −11.455）。
  全设计那句随之变成 `Timing constraints are not met`。
- **别域逐格**（对 r132 基线）：`clk_fpga_0` 1.571→1.585、`clkout0_1` 3.287→4.002、
  `sys_clk` 14.294→14.822 都在涨；`eth_rxc` setup 0.687→**0.554 在缩**（hold 0.004→0.055 在涨）
  ⇒ 严格 P2 不过。差分尺子那边 `D1_no_new_violation new=2 RED`、`D2_pairs_compared pairs=16 GREEN`。

**但这个红不是"我们的 HDMI 输出违反规范"**。摘要里第一条违例路径把原因写死了：

```
Slack (VIOLATED) : -5.408ns     Source: u_pl/u_dvi/u_ser0/u_master/CLK (OSERDESE2, clkout1_1)
Requirement      :  4.000ns     (clkout1_1 rise@4.000 - clkout1_1 rise@0.000)
Data Path Delay  :  2.034ns     Logic Levels: 1 (OBUFDS=1)
Clock Path Skew  : -3.300ns     (SCD 4.991ns 走 MMCM；端口侧 DCD 只有 1.596ns)
```

工具把"一个 4 ns 位周期"当成了规范里"钟到数据"的窗口，而 −5.408 里单是时钟路径偏斜就占 −3.300 ——
比的是不同位槽的沿。取证文档 `report/io/hdmi_cts_source_window.md` 规定的形状是
`create_clock -period 20.000 -name tmds_clk_ref [get_ports tmds_clk_p]` 再对数据口
`set_output_delay ±4.000`：0.20 Tcharacter 是**连接器上**钟与数据的互对偏斜，参考对象只能是面板上
看到的 20 ns 钟。r119 候选件头部那段"参考时钟对象由 pin 反查得到（clkout1_1）"的推理，
把"哪条钟驱动触发器"当成了"对外窗以哪条钟为参考"——在 serdes 输出上这两件事不是一回事。

所以这一臂**不采纳**，但债的形状变了：从"缺一次量名册的构建"变成"**候选件绑错了参考钟**"。
第二版候选件 `src/constraints/r132_hdmi_source_window_v2.xdc`（开关 `VP_R132_TMDS_V2=1`，
默认同样不加载）按文档形状重写，由臂 D 去量，见第六节。

## 四b、臂 B（RGMII 输入窗）

`【链子跑完后填】`。要看的是那 5 个脚（`eth_rxd[0..3]` + `eth_rx_ctl`，上升沿与 `clock_fall` 各一组）
第一次被检查之后 `eth_rxc` 的 hold 与 I/O 端点红数，以及别域是否被牵连。


## 五、臂 C（复制 owner_eth）判 NOT RUN——前提被净表读数否掉

`build/evidence/r132_owner_fanout.txt`（探针 `build/tcl/probe_owner_fanout.tcl`，在同一份 routed dcp 上）：

- `u_pl/u_arb/owner_eth_reg/Q` 驱动的网络叫 `u_pl/u_arb/dbg_src[0]`，**负载 5 个**；
- 高扇出名册（`report_high_fanout_nets`）在 r132 与 r118 两轮里都没有 owner 这一条，
  榜首是 2546 负载的 `u_eth/u_rgmii/u_rgmii_rx/gmii_rx_clk`；
- 所以"复制这只旗标"不会改变布线距离，这一臂要量的东西不成立，省下的一次构建记在这儿，
  免得下次又有人去跑它。

原来那句"能动的是这只高扇出旗标的复制与摆放"是**把"起点是一只旗标"误读成"这是一只高扇出网络"**。
报告附表 r118 那一行与 `report/timing/eth_rxc_partition_options.md` 第 4 节都已按读数改成
"能动的只有摆放"，而摆放这一类刀在本工程量过两次（赢 1 格跌 4 格那两条，见
`report/optimization_log.md` 的 r89 与 r117 小节），要再动得按名册差分重新立案。

## 六、这一轮还欠的四件（不写成做完）

1. **臂 D**：第二版窗（`VP_R132_TMDS_V2=1`，链子 `build/r132_arm_d.sh`）的读数——它才是"对外那一段
   到底差多少"的第一次有效测量；在那之前 4.1 第 1 条仍写"没有结论"；
2. `check_timing -verbose` 的现版件——`build/r115_roster_build.py` 那张名册表的
   `io_unconstrained_ports` 一列要它，r114 那份已经隔了十几版（探针 `build/tcl/probe_check_timing.tcl` 已备好）；
3. 由它生成 `build/roster/roster_r132.tsv` 与探针版 `roster_r132_probe.tsv`（口径见
   `build/roster/roster_r118.tsv` 头部三行注释）；
4. 臂 B 与臂 D 的数落进本页，并把结论回填到报告 1.4 注、4.1 第 1 条与 4.2 那句"一挂就红"。

链子在飞的时候不起台架也不起第二次探针：这台机器 15.7 G 内存，实现线程与 xsim 会互相挤。

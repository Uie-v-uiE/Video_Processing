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
真正欠的是**对外那一段**（源端窗口、走线失配扣除、眼图）。
臂 A 想把这一段变成一次构建里可读的数，结果是把它挂错了容器（见第四节）；
现版能给的读数是臂 D 的逐脚离散。

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
比的是不同位槽的沿。

**这一段我走重了：同一件事 2026-10-04 就量过并写死了结论**，`report/timing/debt_ledger.md`
"追加（2026-10-04 09:4x）"一节与 `report/log/issues.md` #335。当时先把 ±4.000 挂在片内串行钟
`clkout1_1` 上（件 `build/evidence/r119_xdc_loads_probe3.txt`，三条数据道 −3.482 / −3.458 / −3.474），
再**按 `report/io/hdmi_cts_source_window.md 规定的形状**重写一版——参考钟打在钟脚上
（`src/constraints/r119b_hdmi_tp1_pinclk.xdc`：`create_clock -name r119b_tmclk -period 20.000
[get_ports {tmds_clk_p}]` ＋ 对数据口 `set_output_delay ±4.000`），件
`build/evidence/r119_xdc_loads_probe4_pinclk.txt` 三条 −4.897 / −4.873 / −4.890，
工具打印的 Requirement 自己就写着 `4.000ns (r119b_tmclk rise@20.000ns - clkout1_1 rise@16.000ns)`
——换了参考钟，红没换方向。#335 给的是量纲：HDMI 源端 TP1 那条 `Inter-Pair Skew max 0.20 Tcharacter`
是**两个输出脚到达时刻之差的上限**，`set_output_delay` 是**外部接收器的采样窗**，
SDC 里没有 skew 这个容器；"挂错容器得到的红不是设计不合格的证据，放宽它也不是满足规范"。

所以这一臂**不采纳，也不立第二版候选件**：我一度按上面那个形状写好的
`src/constraints/r132_hdmi_source_window_v2.xdc` 已删——它与 r119b 是同一个形状，
再滚一次构建只会把同一个量纲错再量一遍，那一次构建的时间是白花。
债的形状回到 #335 留下的问法：在已布线成品上逐脚量 `tmds_clk_p` 与 `tmds_data_p[0..2]`
（含各自 `_n`）的 clock-to-pin `Data Path Delay` 离散，对回 0.20 `Tcharacter`（4.000 ns）
与 0.15 `Tbit`（0.300 ns）。r119 那轮量过并判 10 项红 0（互对最差 0.065 ns、对内最差 0.001 ns，
件 `build/evidence/r119_pin_skew_probe2.txt` 与 `r119_window_check.txt`）；臂 D 是在**现版**
r132 的 routed dcp 上重跑同一把尺子，见第六节第 1 条。

## 四b、臂 B（RGMII 输入窗）——5 个脚第一次被检查，两个角各差 0.85 ns

链子 01:35 起飞、01:51:10 出件（`build/isolated_r132_rgmiiwindow/`，位流 md5 前 12 位 `64e6af81bd05`；
探针件 `build/evidence/r132_rgmiiwindow_roster.txt`、差分 `..._diff_vs_r132.txt`、
摘要 `..._timing_summary.rpt`）。

- **P1 在位**：执行行是 `VP_R116_IO_WINDOW loaded（RGMII 输入窗已进实现，预期 5 个 I/O 端点会红）`。
  念这条的时候要认得坑：`grep -ao 'VP_R116_IO_WINDOW [a-z]*'` 会**同时抓到构建脚本自己的注释回显**，
  于是打出 `loaded VP_R116_IO_WINDOW off` 这种自相矛盾的串；判 P1 只认不带 `#` 的那一行。
- **八对逐格**（`build/evidence/r132_rgmiiwindow_diff_vs_r132.txt`，16 对全念到）：

| 域/角 | 基线 | 带窗 | 相对余量 |
| --- | --- | --- | --- |
| `eth_rxc`/setup | 0.687 | **−0.846** | −223.1 % |
| `eth_rxc`/hold | 0.004 | **−0.870** | −21860.0 % |
| `clk_fpga_0`/setup | 1.571 | 1.493 | −5.0 % |
| `clk_fpga_0`/hold | 0.048 | 0.064 | +33.3 % |
| `clkout0_1`/setup | 3.287 | 3.953 | +20.3 % |
| `clkout0_1`/hold | 0.067 | 0.067 | 0.0 % |
| `sys_clk`/setup | 14.294 | 13.966 | −2.3 % |
| `sys_clk`/hold | 0.121 | 0.121 | 0.0 % |

  `clkout1_1`、`clkout2`、`clkfbout`、`clkfbout_1` 四族两角仍是 `NOWRITE`，与基线同形状（这一臂不碰它们）。
- **P3 要数的三样**：全设计 WNS −0.846 / TNS −4.135 / 失败端点 **5**，WHS −0.870 / THS −4.270 / 失败端点 **5**，
  总端点 51,032；`eth_rxc` 那一族 intra 的总端点 4,840，其中 setup 与 hold 各红 5 个。
  **红的那 5 个就是窗覆盖的那 5 个脚**：两条最差路径的 Source 直接是端口
  `eth_rxd[0]`（setup）与 `eth_rx_ctl`（hold），Logic Levels 都是 2（IBUF + IDELAYE2），
  route 0.000 ns ⇒ 差的是 I/O 模型那一段，不是 fabric 摆放。
  基线那句"0 个失败端点 / 51,027"里的 51,027 变 51,032，**多出的正好是这 5 个第一次被纳入分析的输入端点**——
  这一格是"检查覆盖变宽"的读数，不是"设计变差"的读数。
- **P4 资源账**：Slice LUTs 14,013（26.34 %）、Block RAM Tile 96/140（68.57 %）、DSP48E1 19、
  Bonded IOB 27 —— 四行与基线逐字相同，这一臂确实只动了约束。
- **严格 P2 不过**：差分尺子给 `D1_no_new_violation new=2 RED`、`D3_margin_cost big_loss=2 RED`
  （`clk_fpga_0/setup` 与 `sys_clk/setup` 也在缩），`D2 pairs=16 GREEN`、`D4/D5/D6 GREEN`，
  `ROSTERDIFF-SUMMARY result=RED`。所以这一臂**不加载**，继续留候选件。

**这条红现在有了现版的数，但它同时把问题推给了窗本身。** 报告 4.2 原来念的是 r114 的
WHS −2.885 / THS −14.344，而那个窗是按 `±0.500` 写的——用的是 `TskewT`（"without delay integrated"）那一行，
把行用错这件事记在 ISSUES #304 与 #309。现版挂的是改对之后的 `[1.2, 2.8]` 窗
（`src/constraints/r116_rgmii_input_window.xdc` 头部三条出处），红到 −0.846/−0.870，
而 `report/timing/rgmii_window_model.md` 第 (3) 节的抽头扫描在同一族上给的 31 档值就是 **−0.870**
（件 `build/evidence/r115_window/probe3_console.txt` 那一族，26 档 −1.185 ⇒ 抬幅 +0.315 是实测）。
两件事同时对上了：**臂 B 复现了扫描末端的那个数**，说明这一臂的读数不是新信息，
而是把扫描结论搬进了一次完整构建的名字里；**但板上这一路是收得下包的**
（30 fps 满带宽推流 300 s 不掉帧、116.7 fps 不丢字节，见报告 3.3 与 3.4），
所以"窗把 5 个脚判红"与"硬件在收"同时成立 ⇒ 至少有一项延迟被计了两次，
或者工具给 IDDR 的边配对与窗的参考沿不合（同一份模型文档第 (2) 节已经在查这件事，
它还留着一处手算 −1.65 与工具 −1.185 的 0.465 ns 分歧没闭合）。
**这一轮的结论写到这儿为止：窗的形状问题没有结论**。报告 4.2 那句"一挂整个时钟域全红"换成现版的两个数，
但不写成"RGMII 收口时序不合格"，也不写成"已经对上"；剩下的分歧记在
`report/timing/rgmii_window_model.md` 第 (2)(3) 节与本页第六节第 5 条，那才是这条债真正的形状。


## 四c、臂 D（逐脚 clock-to-pin 离散）——量到了，16 个读数与 r119 逐字相同

`build/r132_arm_d.sh` 不起构建，只把 `build/tcl/probe_tmds_pin_skew.tcl` 打在板上那一版的
routed dcp 上（会话时间 01:57:36、`open_checkpoint` 指向 `vivado_system/.../system_top_routed.dcp`，
两条都在 `build/r132_pin_skew_console.txt` 里）；判定用新尺子 `build/r132_pin_skew_judge.mjs`，
件 `build/evidence/r132_pin_skew_probe.txt`、`r132_arm_d_verdict.txt`、红能力自证 `r132_arm_d_selftest.txt`。

```
J5 上限可推导   像素钟=50MHz ⇒ Tcharacter=20.000 Tbit=2.000 互对上限=4.000ns 对内上限=0.300ns PASS
J1 计数地板     期望 8 脚×2 角 缺 max=[] 缺 min=[] 未量到行=0 PASS
J2 互对max角    逐道=[0.041, 0.065, 0.049] 最差=0.065ns 上限=4.000 PASS
J3 互对min角    逐道=[0.040, 0.064, 0.048] 最差=0.064ns 上限=4.000 PASS
J4 对内 P/N     max角=[0.001, 0.001, 0.001, 0.001] min角=[0.001, 0.001, 0.001, 0.001] 最差=0.001ns 上限=0.300 PASS
```

红能力：`--self` 造 6 条畸形动红 6 条（少一条数据道、max 角推后 6 ns、min 角推后 6 ns、
对内拉开 0.5 ns、像素钟行改名、件整个不存在）。上限那两个数不手抄，由 `data/metrics.csv`
里"显示像素时钟 50 MHz"那一行现算。

**16 行读数与 r119 那份逐字节相同，这不是读了旧件。** 两条反证都在件里：
① 本次会话时间与 `open_checkpoint` 的路径都在自己的控制台上；
② 相同的原因在臂 A 那份摘要里写着——同一段路径的
`Data Path Delay: 2.034ns (logic 2.033ns (99.951%) route 0.001ns (0.049%))`（
`build/evidence/r132_tmdswindow_timing_summary.rpt` 的 −5.408 那条），
这一段几乎全在 I/O site 与全局时钟缓冲里，取的是原语模型值，不跟着 fabric 布线走。
所以"互对 0.065 ns / 对内 0.001 ns"这两格可以写成**现版读数**，
但它同时说明**这一笔债不会因为换一版 RTL 而变**：真正欠的还是那两笔板级与波形
（连接器上的离散、眼图/抖动/占空比/上升下降），SDC 里没有它们的容器（#335）。
报告 4.1 第 1 条因此只改一件事：把"只量到离散量"后面接上现版的两个数与件名。

## 五b、现版的 `check_timing -verbose` 与名册表（原第六节第 2、3 条）

探针 `build/tcl/probe_check_timing.tcl` 第一版交回一份 196 字节的空件：`puts $fh [check_timing -verbose]`
里那个返回值是**空串**（正文是打印出来的），于是 `build/r115_roster_build.py` 立刻 `ROSTERFAIL`。
仓库里另外两支探针早就是 `-file` 那一形（`build/tcl/c2_scratch_probe.tcl:42`、`build/tcl/mf114_roll.tcl:176`），
改过来之后 3,770 字节的件 `build/evidence/r132_check_timing_verbose.txt` 出来，
收尾链现在会在"没有 SUMMARY 行"时以非零码结束（而不是把红当成失败、或把没跑成当成通过）。

- 名册表 `build/roster/roster_r132.tsv`：8 行，`ROSTER-BUILT rows=8 io_unconstrained_ports=11`。
  四个有 intra 路径的域的 `wns_setup/wns_hold` 与第三节的探针名册**逐格相同**
  （1.571/0.048、3.287/0.067、0.687/0.004、14.294/0.121）——两条独立通道给同一组数，
  这是报告 1.4 那八对读数的第二件凭据。四族 `NA` 就是 `NOWRITE` 那四族，按 §1 口径不是解析失败。
- 对冻结基线 `build/roster/roster_r118.tsv` 相减（`build/evidence/r132_roster_tsv_diff.txt`）：
  `comparisons_made=32 both_NA=8 red=7 verdict=RED`。红在 7 个相对余量格上：
  四个域的 setup 全在缩（`clk_fpga_0` 0.185→0.1571、`clkout0_1` 0.1815→0.16435、
  `eth_rxc` 0.092375→0.085875、`sys_clk` 0.7438→0.7147），hold 有 3 个在缩、
  `clkout0_1/hold` 0.00295→0.00335 在涨。**这一条不是这一轮的损失，也不是收益**：r118 到 r132 之间隔着
  帧边界行标签与缝对齐那几笔 RTL 改动，缩的那几格是加逻辑的账；现版全设计 WNS `+0.687`
  正是从 `eth_rxc/setup` 这一格来的（r118 同一格 0.739，`clk_fpga_0` 那格 1.850→1.571），
  本轮只负责把这两件之间的距离量出来并落进表，不动它，也不给它记功。
  `io_unconstrained_ports` 两轮都是 **11**（输入 5 个 = `eth_rx_ctl` + `eth_rxd[0..3]`；
  输出 6 个 = `led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]`——件里差分对只按 P 腿点名，
  `_n` 那一腿不在列表内），`unconstrained_endpoints` 两轮都是 0
  ⇒ **对外那 11 个脚的覆盖面这十三版没有动过**，这就是 4.1 第 1 条与臂 B 那条债共同的形状。

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

## 六、这一轮改口之后还欠的（不写成做完）

起飞前登记的六件里，**四件已经还掉**：臂 D 有现版读数（四c），
`check_timing -verbose` 有现版件、名册表 `roster_r132.tsv` 已生成并与 r118 相减（五b），
臂 B 与臂 D 的数都落进本页（四b、四c）。剩下这些：

1. **RGMII 窗的形状问题**（四b 末段）。现版给的 −0.846/−0.870 与模型文档 31 档的 −0.870 对上，
   但"板上收得下包"与"窗把 5 个脚判红"同时成立，说明窗里至少有一项延迟被计了两次，
   或者工具给 IDDR 的边配对与窗的参考沿不合。同一份文档还留着一处手算 −1.65 与工具 −1.185
   的 0.465 ns 分歧没闭合。这条债的下一步不是再滚构建，是把窗的参考沿与偏移的加法重推一遍并对回
   `set_data_check` 那一形（`report/timing/rgmii_window_model.md` 第 (2) 节、方案 C 标着"未试，需要用户批准才能碰"）。
2. **`roster_r132_probe.tsv` 没做**。生成它的那支 `build/p15b_parse_reports.py` 把
   `ROUND = "r118"`（第 40 行）和九个输入件名、r118 专属的探针件路径与逐时钟名册模板
   （同文件 `REPORTS` / `R118_PROBE_ROSTER` / `R118_PERCLK_GLOB` 三处）都写死在文件里，
   它的指纹绑定走 `build/provenance.md` 第 5 节的 r118 那批。换版本要么改这支正在被 r118 结论引用的尺子
   （按规矩得单独请求授权），要么另立一件同口径的生成器。本轮先用
   `build/r115_roster_build.py` 那一把（它就是为此设计成收四个命令行参数的），百分数口径那把留在这儿等裁决。
3. **板级那两笔仍然没量**（#335 留下的）：连接器上的互对离散不在本表覆盖范围（本表只到封装脚），
   眼图/抖动/占空比/上升下降 SDC 里没有容器。臂 D  PASS 不能抵这两笔。
4. **回填与同步**：报告 1.4 注、4.1 第 1 条、4.2 那句"一挂整个时钟域全红"要换成现版数；
   Word 快照跟着改；`bash build/gates.sh` 与导出包重跑。臂 B 的 −0.870 目前是**单滚**，
   按规矩 35 它只能当"这条红在现版复现了扫描末端值"来讲，不能当"某刀收益 +0.315"的第二证。

链子在飞的时候不起台架也不起第二次探针：这台机器 15.7 G 内存，实现线程与 xsim 会互相挤。

## 七、这一轮的过程账（一件，写进 ISSUES）

臂 A 的红其实是 16 天前就判完的结论，我按"第一条命中"开了一次不必要的构建，
还差点把第三份会漂的候选件放进仓库。规矩、三条查法与 `git rm` 记在 `report/log/issues.md` #493；
`report/timing/debt_ledger.md` 那条"还欠一次构建量名册"上面已经补了指针。
新尺子 `build/r132_pin_skew_judge.mjs` 的六条红能力对照在 `build/evidence/r132_arm_d_selftest.txt`。

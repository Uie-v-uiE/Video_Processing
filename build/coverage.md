# 约束覆盖面核对（P15b · `build/coverage.md`）

**本轮 = r118**（`build/provenance.md:1`；成品位流 md5 前 12 位 `cd04907e1369` = `build/provenance.md:134`）。
本文只回答一件事：**每一路真实存在的时钟，被哪一条约束、由哪个文件的哪一行覆盖到了**（P15b 铁律 3）。
按名字写的约束一旦名字变了就整条空转，工具不一定提醒 ⇒ 这张表的全部意义是让"哪个名字没人管"每次都能被数出来。
**不重跑构建**：右侧证据全部来自已留档的只读件；所有行号是 2026-10-04 用 `grep -n` 现取的（命令见第 6 节）。
读数边界（这份表不能证明什么）见 `docs/build-notes.md` 第 1 节。

## 1. 本轮到底挂了哪几份 XDC（按入口脚本判，不按目录列表猜）

| 约束文件 | 挂载方式 | 出处 | r118 生效 |
|---|---|---|---|
| `src/constraints/rk_zynq7020.xdc` | `add_files -fileset constrs_1`（综合+实现） | `build/tcl/build_system_axigpio.tcl:19` | 是 |
| `src/constraints/clock_groups_impl.xdc` | 同上 + `set_property used_in_synthesis false` | 同文件 `:24-25` | 是（只实现阶段） |
| `src/constraints/r116_rgmii_input_window.xdc` | env 开关 `VP_R116_IO_WINDOW` | 同文件 `:45-52` | **否**（走 `:51` 的 off 分支） |
| `src/constraints/r119_hdmi_source_window.xdc` | env 开关 `VP_R119_TMDS_WINDOW` | 同文件 `:63-70` | **否**（走 `:69` 的 off 分支） |
| `src/constraints/r114_io_async.xdc` | 发布流程不挂；只被实验脚本 source | `build/tcl/r114_idelay_sweep.tcl:18`、`r114_io_roll.tcl:29`、`r114_io_roll_one.tcl:12` | 否 |
| `src/constraints/r114_io_variantA_rise_only.xdc`、`r114_io_variantB_phy_delay.xdc`、`r115_io_window_candidate.xdc`、`r119b_hdmi_tp1_pinclk.xdc` | `grep -rl <名> build/tcl/*.tcl build/*.sh` **0 命中**（本轮实跑） | —— | 否（无任何一处挂载） |

⇒ 参与覆盖面核对的"已加载约束"= 前两份，共 **2 份**。

## 2. 实现里真实存在的时钟（8 路，名字以报告为准）

`build/timing_summary.rpt` 的 Clock Summary（表头行 162，数据行 164-171）；源与网名对照 `build/clock_util.rpt:59-66`（BUFG 行）与 `:78-85`（Source 行）。

| 时钟名 | Period(ns) | 报告行 | 这个名字是谁给的 | 已加载 XDC 是否按名字提到它 |
|---|---|---|---|---|
| `clk_fpga_0` | 10.000 | `timing_summary.rpt:164` | 不是本仓约束：`rk_zynq7020.xdc:65` 与 `clock_groups_impl.xdc:3` 都写明它由 PS7 IP 自己的 XDC 在 `FCLKCLK[0]` 上 create | 是，但用 `-quiet`（`clock_groups_impl.xdc:30`） |
| `eth_rxc` | 8.000 | `:165` | `rk_zynq7020.xdc:36` `create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]` | 是（`:36`、`:50`、`clock_groups_impl.xdc:29`） |
| `sys_clk` | 20.000 | `:166` | `rk_zynq7020.xdc:6` `create_clock -period 20.000 -name sys_clk [get_ports sys_clk]` | 是（`:6`、`clock_groups_impl.xdc:31`） |
| `clkfbout` | 20.000 | `:167` | 非约束：`grep -rn create_generated_clock src/` **0 命中**；驱动 `u_idelay_clkgen/u_mmcm/CLKFBOUT`（`clock_util.rpt:83`） | **否** |
| `clkfbout_1` | 20.000 | `:168` | 同上，驱动 `u_pl/u_clk/u_mmcm/CLKFBOUT`（`clock_util.rpt:85`） | **否** |
| `clkout0_1` | 20.000 | `:169` | 同上，BUFG 网名 `u_pl/u_clk/clk_pix`（`clock_util.rpt:60`）；RTL 内部 net 名是 `clkout0`（`src/rtl/clocks/clk_gen.v:37`）⇒ 报告名 ≠ RTL 名 | **否** |
| `clkout1_1` | 4.000 | `:170` | 同上，net `u_pl/u_clk/clk_pix5x`（`clock_util.rpt:63`）；TMDS 串行寄存器确实挂在这路上（`build/evidence/r119_ser_clock_probe.txt:49-52` 四条 `SERCLK| … clock=clkout1_1 period=4.000`） | **否**（候选件 `r119_hdmi_source_window.xdc:51-52` 按这个名字引用，但未挂载） |
| `clkout2` | 5.000 | `:171` | 同上，net `u_idelay_clkgen/idelay_clk`（`clock_util.rpt:65`） | **否** |

⇒ 8 路里只有 3 路（`sys_clk`/`eth_rxc`/`clk_fpga_0`）被已加载约束按名字点见过；另外 5 路只能靠 `clock_groups_impl.xdc:31` 的 `-include_generated_clocks sys_clk` 覆盖。

## 3. 逐钟矩阵：声明了什么约束、由哪一行给、生效证据在哪

「声明」列只统计**本轮加载的 2 份 XDC**。「证据」列是 r118 盘上件里的原文行。

| 时钟 | create_clock | set_clock_uncertainty | set_clock_groups | set_input_delay | set_output_delay |
|---|---|---|---|---|---|
| `sys_clk` | `rk_zynq7020.xdc:6` | **无声明**。实测：setup 件有 `Clock Uncertainty: 0.035ns …+ PE`（无 `UU` 项，`build/roster_r118_after_sys_clk_setup.rpt:29`）；hold 件里**整行缺失**（`grep -c 'Clock Uncertainty:' build/roster_r118_after_sys_clk_hold.rpt` = 0） | `clock_groups_impl.xdc:31`（组根 + `-include_generated_clocks`） | n/a（时钟脚） | n/a |
| `eth_rxc` | `rk_zynq7020.xdc:36` | **有**：`rk_zynq7020.xdc:50` `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` ⇒ 证据 `build/roster_r118_after_eth_rxc_hold.rpt:29` = `0.800ns …+ PE + UU`；同一件 `:91/:147/:203` 三处同值。setup 侧 `eth_rxc_setup.rpt:29` = `0.035ns`（公式无 `UU`）⇒ 与"只写 `-hold`"一致 | `clock_groups_impl.xdc:29` | **无**（本轮 0 条）⇒ `build/timing_summary.rpt:99` 记「5 input ports with no input delay (HIGH)」；名字见 `build/check_timing_verbose.rpt:57-61`（`eth_rx_ctl`、`eth_rxd[0..3]`，那份件是 10-03 15:32 的、**不是 r118**，只当名字参照） | n/a |
| `clk_fpga_0` | 无（不由本仓约束创建，见第 2 节） | **无声明**。实测 setup 件 `build/roster_r118_after_clk_fpga_0_setup.rpt:29` = `0.154ns …/ 2 + PE`（无 `UU`）；hold 件该行缺失（`grep -c` = 0）。对照：`build/clock_uncertainty.rpt:25` 那段 10-03 之前（`:9` Date = Wed Sep 30 06:19:21 2026）的 `clk_fpga_0` hold 路径同样没有 uncertainty 行，而同文件 `:98/:107` 的 `eth_rxc` 有 0.800 | `clock_groups_impl.xdc:30`，写的是 `get_clocks **-quiet** clk_fpga_0` | n/a | n/a |
| `clkfbout` | 非约束创建 | 无声明；**且本轮无从实测**：`build/roster_r118_after_clkfbout_setup.rpt:15` 与 `…_hold.rpt:15` 都是 `No timing paths found.` | 只能经 `clock_groups_impl.xdc:31` 的 `-include_generated_clocks` 间接触及；**归属无法证实**（该路在 Intra/Inter 表里都没有 setup/hold 行，`timing_summary.rpt:184`只有脉宽数字） | n/a | n/a |
| `clkfbout_1` | 同上 | 同上（`…_clkfbout_1_setup.rpt:15` / `_hold.rpt:15` 均 `No timing paths found.`） | 同上，无法证实 | n/a | n/a |
| `clkout0_1` | 非约束创建 | 无声明；setup 件实测 `build/roster_r118_after_clkout0_1_setup.rpt:29` = `0.094ns ((TSJ^2 + DJ^2)^1/2) / 2 + PE`（无 `UU`）；hold 件该行缺失（`grep -c` = 0） | `clock_groups_impl.xdc:31` ⇒ **本轮唯一有正面证据的一路**：`build/timing_summary.rpt:198-199` 的 Inter Clock Table 只有 `clkout0_1↔sys_clk` 两行（仍被一起分析），且 `build/cdc.rpt:24-25` 把这两向标成 `Safely Timed` | n/a | n/a |
| `clkout1_1` | 非约束创建 | 无声明；且 `build/roster_r118_after_clkout1_1_setup.rpt:15`、`…_hold.rpt:15` 均 `No timing paths found.` ⇒ 该路在 r118 只受脉宽检查（`timing_summary.rpt:187` 有 `2.408 / 0.000 / 0 / 10`） | 只能经 `:31` 间接触及，**无法证实** | n/a | **无**（本轮）。缺失的直接后果：`build/timing_summary.rpt:106` 记「6 ports with no output delay (HIGH)」，名字含 `tmds_clk_p`、`tmds_data_p[0..2]`（`build/check_timing_verbose.rpt:73-78`）。唯一按 `clkout1_1` 写的窗在 `src/constraints/r119_hdmi_source_window.xdc:51-52`，**未挂载** |
| `clkout2` | 非约束创建 | 无声明；`…_clkout2_setup.rpt:15`、`…_hold.rpt:15` 均 `No timing paths found.` | 只能经 `:31` 间接触及，无法证实 | n/a | n/a |

`set_false_path` 一族（`rk_zynq7020.xdc:55-60`）覆盖的是 `eth_rst_n`/`eth_tx_*`/`eth_txd[*]`/`key1_n`/`key2_n` 六个端口对象，**不覆盖任何时钟名**；它正是把 `no_output_delay` 里 6 个、`no_input_delay` 里 2 个从 HIGH 降级成 MEDIUM 的那几条（`build/timing_summary.rpt:101`、`:108`）。

## 4. 不匹配项（覆盖面丢失的候选，逐条点名）

| # | 不匹配 | 实测证据 | 后果（可判定的说法） |
|---|---|---|---|
| M1 | 报告有 8 路钟，已加载约束只点见过 3 个名字 | 第 2 节表；`build/p15b_parse_reports.py` 的 J2 行 `报告里有这个名字但本轮加载的约束没提过=5 [clkfbout,clkfbout_1,clkout0_1,clkout1_1,clkout2]` | 5 路的覆盖面 100% 依赖 `-include_generated_clocks` 一条；这 5 个名字里任何一个变了，`build/coverage.md` 这一列立刻掉到更少，而构建不会报错 |
| M2 | 生成钟的名字不是约束给的，也不是 RTL 里的网名 | `grep -rn create_generated_clock src/` = 0 命中；`clk_gen.v:37` 的 `clkout0` vs 报告的 `clkout0_1`；`clock_util.rpt:60` 的网名是 `u_pl/u_clk/clk_pix` | 名字由工具产出 ⇒ 例化顺序/改 net 名/re-source MMCM 都可能改名。**这就是改名后静默丢覆盖的形状**，下一次动时钟树必须重跑本文第 3 节 |
| M3 | `clock_groups_impl.xdc:13-17` 注释自陈生成集 = `clkout0_1/clkout1_1/clkout2`（3 路），报告实际有 5 路 | 注释 `:13-17` vs `timing_summary.rpt:167-171` | 文件头的说明已过期 ⇒ 读约束的人会以为 `clkfbout`/`clkfbout_1` 不在组里；本仓里"约束文件的自述"与"报告"不同源时**以报告为准** |
| M4 | `clk_fpga_0` 用 `get_clocks -quiet` 引用 | `clock_groups_impl.xdc:30`；历史账：`rk_zynq7020.xdc:43-45`（把取不到的名字并进同一条命令 ⇒ **整条命令空转**，连 `eth_rxc`/`sys_clk` 一起废）、`rk_zynq7020.xdc:66-70`（`CRITICAL WARNING [Vivado 12-4739]`） | 一旦 PS7 的 FCLK 命名变化，这一组会静默消失 ⇒ 三组两两异步变成两两做 setup 分析，历史上对应 `clock_groups_impl.xdc:16-17` 写的 WNS≈-6.7 假违例形状。本轮的正面证据：`cdc.rpt:17-23` 那 7 行仍写着 `Asynch Clock Groups` ⇒ 此刻 `-quiet` 是取到对象的 |
| M5 | 唯一一条 `set_clock_uncertainty` 只作用于 1/8 路，且只作用 `-hold` 一侧 | `rk_zynq7020.xdc:50`（全仓 `set_clock_uncertainty` 只有这一处，`grep -n` 实测）；生效证据 `roster_r118_after_eth_rxc_hold.rpt:29`；setup 侧与另外 7 路的 hold 侧均无 `UU` 项或整行缺失 | 其余 7 路的 hold 余量全部由工具自己给的数决定；读 WHS 时必须知道"这一路的余量里没有用户不确定度"（见 `docs/build-notes.md` 第 1 节 C 组） |
| M6 | 输出口两类都没有窗：`eth_rxd/eth_rx_ctl`（输入 5 口 HIGH）、`tmds_*`+`led[*]`（输出 6 口 HIGH） | `timing_summary.rpt:99`、`:106`；名字参照 `check_timing_verbose.rpt:57-61`、`:73-78`；对应候选件 `r116_rgmii_input_window.xdc:32-35`（`-clock eth_rxc`）、`r119_hdmi_source_window.xdc:51-52`（`-clock clkout1_1`）均未挂载 | `check_timing` 的 HIGH 条数**不是时序失败**，但它意味着"这些口的时序结论不存在" ⇒ 赛题口径里不能把 8 路内部收敛外推成"设计整体时序收敛" |
| M7 | 候选件独占名 `r119b_tmclk`：在约束里被创建，报告 8 路里没有 | `r119b_hdmi_tp1_pinclk.xdc:24-26`；J2 行 `候选件独占名=1 [r119b_tmclk]` | 一旦挂载，域数从 8 变 9 ⇒ `build/roster/roster_r118.tsv` 与本文第 2 节同时作废，必须一起重建，不能只改一处 |

## 5. 本文自带的判据（一条一行，判定放最后一个字段，打印分母）

复跑：`python build/p15b_parse_reports.py --check`（只读，不写盘；本轮实跑输出见 `docs/build-notes.md` 第 5 节）。

```
C1 时钟名集合对齐：报告 Clock Summary 8 路 == 名册 8 域，缺口 0                 分母=8 判定=PASS
C2 已加载约束按名字点过的时钟数 / 报告时钟数 = 3/8，缺口 5（M1）                 分母=8 判定=FAIL
C3 set_clock_uncertainty 覆盖到的时钟数 = 1/8（M5）                              分母=8 判定=FAIL
C4 set_clock_groups 组归属可被 r118 件证实的时钟数 = 4/8（sys_clk 组根、eth_rxc、
   clk_fpga_0 由 cdc.rpt:17-21 的 Asynch Clock Groups 佐证、clkout0_1 由
   timing_summary.rpt:198-199 佐证）；其余 4 路 No timing paths found ⇒ 读不到  分母=8 判定=NOT_MEASURED
C5 I/O 延迟窗覆盖（输入类 0/1、输出类 0/1，两侧都有 HIGH 未约束口）              分母=2 判定=FAIL
C6 候选件独占名（挂了就会改域数）= 1，当前未影响 r118                            分母=8 判定=PASS
C7 约束文件自述与报告一致性：clock_groups_impl.xdc:13-17 列 3 路 vs 报告 5 路    分母=2 判定=FAIL
C8 本文每个时钟的每条「声明」都能指到 file:line（第 3 节逐格）                   分母=8 判定=PASS
```

判据 C2/C3/C5/C7 是**覆盖面事实**（设计侧缺口，不是解析失败）；C4 是"读不到 ≠ 通过"。
反例证明（会红的形状）：把 `clock_groups_impl.xdc:31` 的 `-include_generated_clocks` 去掉，第 2 节
「已加载 XDC 是否按名字提到它」的 5 路全落空 ⇒ C2 的分母不变而覆盖面为 0；把 `rk_zynq7020.xdc:50`
改名成别的时钟对象 ⇒ C3 计数掉到 0。两处都**不需要重跑构建**就能在本表里看出差别（本表只按名字数）。

## 6. 本文件的复跑取证命令（只读）

```bash
grep -n -E 'create_clock|create_generated_clock|set_clock_uncertainty|set_clock_groups|set_input_delay|set_output_delay' src/constraints/*.xdc
grep -rl 'r114_io_async\|r114_io_variantA\|r114_io_variantB\|r115_io_window\|r119b_hdmi' build/tcl/*.tcl build/*.sh   # 0 命中 = 未挂载
grep -n -E 'add_files -fileset constrs_1|used_in_syn|VP_R11[0-9]' build/tcl/build_system_axigpio.tcl
sed -n '162,171p;181,188p;196,199p' build/timing_summary.rpt                 # Clock Summary / Intra / Inter
grep -n -E 'checking no_input_delay|checking no_output_delay|There are [0-9]+ (input ports|ports)' build/timing_summary.rpt
sed -n '57,85p' build/clock_util.rpt ; sed -n '15,25p' build/cdc.rpt
for f in build/roster_r118_after_*.rpt; do echo "$f $(grep -c 'Clock Uncertainty:' $f)"; done
grep -n 'SERCLK|' build/evidence/r119_ser_clock_probe.txt
```

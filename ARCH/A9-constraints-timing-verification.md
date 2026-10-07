# A9 · 约束、时序收敛与验证体系（实现级拆解）

> 这一卷讲的是**机器怎么知道时序是真的**：哪两份 .xdc 真的进了构建、生效判据长在哪一行、
> 不确定度带到底覆盖哪几颗钟、关键路径怎么归因、82 支台架与 24 项门禁各自咬什么、
> 以及五把文档级尺子各管哪一类说谎。
>
> 与既有文档的分工：`LEARNING/05a` 讲"约束侧有哪些事实"，`LEARNING/05b` 讲"每一刀的账"。
> 那一两卷是**结论表**，本卷是**机构图**：每条判据点名它写在哪个脚本的哪一行、
> 它为什么长那样、它挡的是哪一种具体的事故。凡读数一律照抄报告原文并给行号；
> 凡是算出来的，把算式写出来。
>
> 报告身份先钉住：本卷引用的 `build/report/timing_summary.rpt` 是 `Date : Sun Oct 4 18:54:00 2026`、
> `Design : system_top`、`Design State : Routed` 的那一次（来源：build/report/timing_summary.rpt:4），
> 命令是 `report_timing_summary -file D:/Xilinx/Prj/pro/Video_Processing/build/report/timing_summary.rpt`（来源：build/report/timing_summary.rpt:6）。
> 同批的 `methodology.rpt` / `cdc.rpt` / `utilization.rpt` / `power.rpt` / `clock_util.rpt`
> 的时间戳分别是 18:54:11 / 18:54:03 / 18:54:01 / 18:54:19 / 18:54:20
> （来源：build/report/methodology.rpt:4）（来源：build/report/cdc.rpt:4）（来源：build/report/utilization.rpt:4）
> （来源：build/report/power.rpt:4）（来源：build/report/clock_util.rpt:4）——同一套产物，差在几十秒内。

---

## 1 在用哪两份 .xdc：生效判据有三层

`src/constraints/` 目录里躺着 9 份 .xdc，但一次交付构建只加载 2 份。这三层判据从上到下依次变严，
少任何一层都可能把"文件在目录里"读成"约束生效了"。

### 1.1 第一层：流程脚本里的 `add_files` 有几处

`build/tcl/build_system_axigpio.tcl` 是交付路径唯一的入口（`build/build.tcl` source 它，见该文件第 2 行的说明"交付要求 §4 的主入口 build/build.tcl 就是 source 本文件"，来源：build/tcl/build_system_axigpio.tcl:2）。
它对着 `constrs_1` 只调了四次 `add_files`：

| 调用 | 加载对象 | 生效条件 | 出处 |
| --- | --- | --- | --- |
| 第 1 次 | `rk_zynq7020.xdc` | 无条件，综合 + 实现 | `add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]`（来源：build/tcl/build_system_axigpio.tcl:31） |
| 第 2 次 | `clock_groups_impl.xdc` | 无条件，但只绑实现 | 来源：build/tcl/build_system_axigpio.tcl:36 |
| 第 3 次 | `r116_rgmii_input_window.xdc` | 仅 `VP_R116_IO_WINDOW=1` | 来源：build/tcl/build_system_axigpio.tcl:58 |
| 第 4 次 | `r119_hdmi_source_window.xdc` | 仅 `VP_R119_TMDS_WINDOW=1` | 来源：build/tcl/build_system_axigpio.tcl:76 |

第 3、4 次都包在 `if {[info exists ::env(VP_R116_IO_WINDOW)] && $::env(VP_R116_IO_WINDOW) eq "1"}` 这种环境变量守卫里（来源：build/tcl/build_system_axigpio.tcl:57），
守卫不成立时走 else 分支，只打印一句 `VP_R116_IO_WINDOW off（RGMII 输入窗留在候选件 src/constraints/r116_rgmii_input_window.xdc，原因见上方注释）`（来源：build/tcl/build_system_axigpio.tcl:63）。
`build/tcl/build_pl_full.tcl:22` 那条 PL-only 短路径只加 `rk_zynq7020.xdc` 一份，不是交付路径。

### 1.2 第二层：`add_files` 的返回值上挂着什么属性

`add_files` 会返回文件对象句柄，属性挂在句柄上——这就是本项目里 `is_used` 家族的实际写法
（Vivado 的约束文件用 `used_in_synthesis` / `used_in_implementation` 两个属性表达"在哪个阶段生效"）：

```tcl
set cgxdc [add_files -fileset constrs_1 -norecurse [file join $root src constraints clock_groups_impl.xdc]]
set_property used_in_synthesis false $cgxdc
set_property used_in_implementation true $cgxdc
```

（这三行逐字在来源：build/tcl/build_system_axigpio.tcl:36、来源：build/tcl/build_system_axigpio.tcl:37、来源：build/tcl/build_system_axigpio.tcl:38；
同一个 `set_property used_in_synthesis false` / `used_in_implementation true` 对也挂在候选件上，分别是 :59/:60 与 :77/:78，来源：build/tcl/build_system_axigpio.tcl:59）

机制上要说清一件事：**`used_in_synthesis false` 不是"综合时读一遍、实现时再读一遍"，而是综合阶段这份文件根本不被解析**。
所以"综合阶段的报告里没有 `clk_fpga_0` 这条约束"不是丢了，是设计上就该这样——
`src/constraints/clock_groups_impl.xdc:8` 自己写了这句：`时序数字不受影响：综合阶段这条约束在拆分前**也是失败的**（等于不存在）`（来源：src/constraints/clock_groups_impl.xdc:8）。

### 1.3 第三层：`SCOPED_TO` 类判据——由 fileset 反查实际生效集合

本项目没有手写的约束名单，而是有一支**只读探针把"实现期约束集必须正好是 2 份"做成硬门禁**。
判据在 `build/tcl/r124_tiers_probe.tcl`，它先列两个显式名单：

```tcl
set want [list "src/constraints/rk_zynq7020.xdc" "src/constraints/clock_groups_impl.xdc"]
set banned [list "r119_hdmi_source_window.xdc" "r119b_hdmi_tp1_pinclk.xdc" "r116_rgmii_input_window.xdc" \
                 "r114_io_async.xdc" "r115_io_window_candidate.xdc" "r114_io_varianta_rise_only.xdc" \
                 "r114_io_variantb_phy_delay.xdc"]
```

（来源：build/tcl/r124_tiers_probe.tcl:42 是 `want`，来源：build/tcl/r124_tiers_probe.tcl:43 起是 `banned`，`banned` 跨 43-45 行）

然后它做的是"反查 + 摘除 + 计数"三步，而不是"信注释"：

1. 从 fileset 读实际文件集合：`foreach f [get_files -of [get_filesets constrs_1]] { lappend have [file tail $f] }`（来源：build/tcl/r124_tiers_probe.tcl:47）；
2. 命中 `banned` 的在**内存里** `remove_files $f`，并且脚本头明写"不保存工程，不改仓库里的 .xdc 内容"（来源：build/tcl/r124_tiers_probe.tcl:22）；
3. 重数一遍并判两个方向：少了要 REFUSE（来源：build/tcl/r124_tiers_probe.tcl:64）、
   多了也要 REFUSE——`if {[llength $after] != [llength $want]} { puts "REFUSE: impl constraint count [llength $after] != 2"; set ok1 0 }`（来源：build/tcl/r124_tiers_probe.tcl:66）。

这条判据值得单独记住的地方是**它同时判少和判多**。只判"我想要的在不在"会放过"多挂了一件候选件"，
而多挂一件正是读数变难看时最容易犯的自救动作。`banned` 那 7 个名字就是被明令禁止多挂的名单，
它和 1.1 的表合起来给出一个可复算的结论：**目录里 9 份、加载 2 份、被硬拒绝 7 份**（9 这个数字是本目录 .xdc 的文件数，来源：src/constraints/clock_groups_impl.xdc:1 所在的目录列表见 1.1 表；被拒的 7 份逐名在来源：build/tcl/r124_tiers_probe.tcl:43）。

### 1.4 "文件存在≠生效"的三种具体炸法

这三条不是三种说法，是三种不同的失效机制，各自有各自的现场证据。

| 炸法 | 机制 | 现场只留什么 | 出处 |
| --- | --- | --- | --- |
| 把取不到的钟名并进一条命令 | `get_clocks` 拿不到对象 ⇒ **整条命令空转**，连带把同一条命令里有效的那几组一起废掉 | 一句 warning | 来源：src/constraints/rk_zynq7020.xdc:43 |
| 在综合阶段点名实现期才存在的钟 | `clk_fpga_0` 由 PS7 IP 自己的 XDC `create_clock`（`FCLKCLK[0]`），综合阶段没有这个对象 | `CRITICAL WARNING [Vivado 12-4739] set_clock_groups: No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'` | 来源：src/constraints/rk_zynq7020.xdc:68 |
| 把 Tcl 控制流写进 .xdc | 解析器对 `if`/`puts` 报 `Designutils 20-1307` 并**整块跳过**，守卫静默失效 | 一条 20-1307 | 来源：build/tcl/build_system_axigpio.tcl:72 |

`-quiet` 的位置特别容易误解，这里把它钉清楚：`-quiet` 只压住 `get_clocks` 自己取不到对象时的报错，
压不住"命令因对象集为空而失败"这件事——这条边界写在来源：src/constraints/rk_zynq7020.xdc:66，
下一行（来源：src/constraints/rk_zynq7020.xdc:67）接着写"压不住命令本身"。
于是那条约束的正规解法只剩"按时机分文件"，文件里给的做法是
`把这条约束放进只在 implementation 生效的 XDC`（来源：src/constraints/rk_zynq7020.xdc:73）。

还有一条已经落过地的同类事故留在文件里当反面教材：`eth_rst_n` 是**输出**，
原先那行写的是 `set_false_path -from [get_ports eth_rst_n]`（来源：src/constraints/rk_zynq7020.xdc:52），
每次综合都报 `CRITICAL WARNING [Constraints 18-513] ... -from ... contains no valid`（来源：src/constraints/rk_zynq7020.xdc:53），
是一条"不约束任何东西、只制造噪声"的空约束，已删除，现行写法是 `set_false_path -to   [get_ports eth_rst_n]`（来源：src/constraints/rk_zynq7020.xdc:55）。

### 1.5 逐域 `create_clock` 与实际 slack：谁定义的、读在哪一行

`create_clock` 在本仓只有两条命中顶层端口：

```tcl
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
create_clock -period 8.000 -name eth_rxc [get_ports eth_rxc]
```

（分别来源：src/constraints/rk_zynq7020.xdc:6 与来源：src/constraints/rk_zynq7020.xdc:36；脚位 W17 与 Y19 分别在 :5 与 :20，来源：src/constraints/rk_zynq7020.xdc:5）

其余五颗都不由本仓 `create_clock`：`clk_fpga_0` 由 PS7 IP 建（来源：src/constraints/clock_groups_impl.xdc:3），
频率来自 BD 参数 `CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100}`（来源：build/tcl/build_system_axigpio.tcl:97）；
`clkfbout` / `clkfbout_1` / `clkout0_1` / `clkout1_1` / `clkout2` 是 MMCM 生成钟，
Clock Summary 里它们的缩进层级就把"生成"这件事画出来了（来源：build/report/timing_summary.rpt:167）。

slack 读数全部来自同一份 `build/report/timing_summary.rpt`：设计级那一行的 WNS 0.739 / TNS 0.000 /
失败 setup 端点 0 / 总端点 51135 / WHS 0.052 / THS 0.000 / 失败 hold 端点 0 / 总 51135 /
WPWS 0.264 / TPWS 失败 0 / 总 12634（来源：build/report/timing_summary.rpt:151），
紧接着一句 `All user specified timing constraints are met.`（来源：build/report/timing_summary.rpt:154）。
逐域那一节（Intra Clock Table）一格一格抄如下：

| 时钟 | 周期 ns（来源：Clock Summary 行） | WNS ns | 端点 | WHS ns | 端点 | 出处（Intra 行） |
| --- | --- | --- | --- | --- | --- | --- |
| `clk_fpga_0` | 10.000 / 100.000 MHz（来源：build/report/timing_summary.rpt:164） | 1.850 | 15721 | 0.053 | 15721 | 来源：build/report/timing_summary.rpt:181 |
| `eth_rxc` | 8.000 / 125.000（来源：build/report/timing_summary.rpt:165） | **0.739** | 4835 | 0.052 | 4835 | 来源：build/report/timing_summary.rpt:182 |
| `sys_clk` | 20.000 / 50.000（来源：build/report/timing_summary.rpt:166） | 14.876 | 323 | 0.222 | 323 | 来源：build/report/timing_summary.rpt:183 |
| `clkout0_1` | 20.000 / 50.000（来源：build/report/timing_summary.rpt:169） | 3.630 | **30179** | 0.059 | 30179 | 来源：build/report/timing_summary.rpt:186 |
| `clkfbout` | 20.000（来源：build/report/timing_summary.rpt:167） | 空 | — | 空 | — | 只有 WPWS 18.408 / 3 端点，来源：build/report/timing_summary.rpt:184 |
| `clkfbout_1` | 20.000（来源：build/report/timing_summary.rpt:168） | 空 | — | 空 | — | 来源：build/report/timing_summary.rpt:185 |
| `clkout1_1` | 4.000 / 250.000（来源：build/report/timing_summary.rpt:170） | 空 | — | 空 | — | 只有 WPWS 2.408 / 10 端点，来源：build/report/timing_summary.rpt:187 |
| `clkout2` | 5.000 / 200.000（来源：build/report/timing_summary.rpt:171） | 空 | — | 空 | — | WPWS 0.264 / 3，来源：build/report/timing_summary.rpt:188 |

这张表里三条读法要写死，否则会被念错：

1. **全设计 WNS 0.739 的持有者是 125 MHz 域而不是最快的域**：0.739 同时出现在设计级行（来源：build/report/timing_summary.rpt:151）
   与 `eth_rxc` 行（来源：build/report/timing_summary.rpt:182），而 100 MHz 的 `clk_fpga_0` 有 1.850。
2. **`clkout0_1` 一档装了全设计端点的绝大多数**：30179 对 51135，算式 `30179 ÷ 51135 = 0.5902`，即约 59 %
   （两个操作数分别来源：build/report/timing_summary.rpt:186 与来源：build/report/timing_summary.rpt:151）。
   所以"某一域的 slack 变好了"若指的是 `clkout0_1`，它对全局的影响面天然最大。
3. **空格不是 0，是"这一族没有被计时的端点"**。`clkout1_1` 的 Timing Details 段最直白：

```
Setup :   NA  Failing Endpoints,  Worst Slack   NA  ,  Total Violation   NA
Hold  :   NA  Failing Endpoints,  Worst Slack   NA  ,  Total Violation   NA
PW    :    0  Failing Endpoints,  Worst Slack  2.408ns,  Total Violation  0.000ns
```

（三行逐字在来源：build/report/timing_summary.rpt:945、:946、:947）

它为什么没数，报告里同一节给了原因的形状：这一档只有两条库单元脉宽窗口——
一条 `Min Period`、要求 1.592、实际 4.000、余量 2.408，落点是 `u_pl/u_clk/u_bufg_5x/I`（来源：build/report/timing_summary.rpt:959），
另一条 `Max Period`、要求 213.360、实际 4.000、余量 209.360，落点是 `u_pl/u_clk/u_mmcm/CLKOUT1`（来源：build/report/timing_summary.rpt:960），
来源脚那一行写的也是 `u_pl/u_clk/u_mmcm/CLKOUT1`（来源：build/report/timing_summary.rpt:956）。
全是单元库自己的脉宽窗口，跟数据路径无关。
门禁脚本把这一事实原样念出来，`分组最差` 那段里 `clkout1_1` 那行的 setup 格就是 `setup NAns`、失败端点那格是 `失败端点 NA`（来源：build/r126_gates.txt:30）。

跨域检查的行数也在这份报告里，而且只有两行：`clkout0_1 sys_clk 14.757 … 19` 与 `sys_clk clkout0_1 3.695 … 231`
（来源：build/report/timing_summary.rpt:198 与来源：build/report/timing_summary.rpt:199），
`Other Path Groups Table` 是空表（来源：build/report/timing_summary.rpt:207 是表头，208 之后没有数据行）。
这两行存在恰好证明 `sys_clk` 与 `clkout0_1` 在同一异步组**内部**（组的定义见 §4.1），
而它们与 `eth_rxc` / `clk_fpga_0` 之间不再被计时。

---

## 2 不确定度带：一条命令、两颗钟、三处后果

### 2.1 现行射程只有 1 条、1 个对象、1 个方向

全仓 `set_clock_uncertainty` 只有一条，写在主约束文件：

```tcl
set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]
```

（逐字来源：src/constraints/rk_zynq7020.xdc:50）

三个限定词都是判据的一部分：方向是 `-hold`（所以不参与 setup 检查，文件里那句
`Setup 不受影响，-hold 的不确定性不参与 setup 检查`，来源：src/constraints/rk_zynq7020.xdc:42）、
对象只有 `eth_rxc` 一颗（同一行上方警告说得很硬：把取不到的名字并进同一条命令会让整条空转，来源：src/constraints/rk_zynq7020.xdc:43）、
值是 0.800 而不是最初的 0.500（r79 试验那一档只做到 WHS +0.051，低于自定验收 0.4，于是加严到 0.8，来源：src/constraints/rk_zynq7020.xdc:47）。
这条带的**方向与"放松判据"相反**：它是给 hold 加要求，逼工具把余量做成设计值，
文件里原话是 `这一行方向与"放松判据"相反`（来源：src/constraints/rk_zynq7020.xdc:41），
同一条命令的下一行接着解释为什么 setup 不受影响：`-hold 的不确定性不参与 setup 检查`（来源：src/constraints/rk_zynq7020.xdc:42）。
它还自带一条**退回承诺**：`若这一版关不住时序（出现失败端点），就带着两个数字退回 0.500`（来源：src/constraints/rk_zynq7020.xdc:48）。

### 2.2 这条带在报告里长什么样：UU = 0.800 的那一行

`build/clock_uncertainty.rpt` 是把这条带"读回来"的专门件。它头部就点明自己为什么存在：
`XDC 那句：set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`（来源：build/clock_uncertainty.rpt:3）。
它分两段，各贴一份 `report_timing -delay_type min` 的原文。

第一段读的是**全设计最差那条 min 路径**（命令 `report_timing -delay_type min -max_paths 1 -nworst 1 -return_string`，来源：build/clock_uncertainty.rpt:11），
它落在 `clk_fpga_0`（`Path Group` 那一格写的就是它，来源：build/clock_uncertainty.rpt:25），
读数是 `0.037ns`（来源：build/clock_uncertainty.rpt:20），括号里给的是方向定义 `arrival time - required time`（来源：build/clock_uncertainty.rpt:20），
起点 `u_pl/u_lat/t_commit_reg[0]/C`（来源：build/clock_uncertainty.rpt:21），终点 `u_pl/u_lat/max_cyc_reg[4]/D`（来源：build/clock_uncertainty.rpt:23）。
这一段的账能一路合上：required time 那行是 `-1.344`（来源：build/clock_uncertainty.rpt:68）、
arrival time 那行是 `1.381`（来源：build/clock_uncertainty.rpt:69）、末行 slack 是 `0.037`（来源：build/clock_uncertainty.rpt:71），
算式 `1.381 − 1.344 = 0.037`。这一段里**没有任何 `Clock Uncertainty` 行**——那把带子根本没作用在它身上。

第二段才把范围收到那颗钟上（命令里带 `-from [get_clocks eth_rxc]`，来源：build/clock_uncertainty.rpt:84），
读数是 `0.049ns`（来源：build/clock_uncertainty.rpt:93），而这一条就把带子吃进去了：

```
Clock Uncertainty:      0.800ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE + UU
```

（这一行逐字在来源：build/clock_uncertainty.rpt:107；它下面把五项拆开，`User Uncertainty` 那一项是 0.800ns（来源：build/clock_uncertainty.rpt:112），其余 TSJ/TIJ/DJ/PE 全写 0.000（来源：build/clock_uncertainty.rpt:108））
它进账的位置也在：路径尾部先是 `clock pessimism`、值 `-0.481`（来源：build/clock_uncertainty.rpt:140），
再是 `clock uncertainty`、值 `0.800`（来源：build/clock_uncertainty.rpt:141），然后才是 hold cell 的 `0.091`（来源：build/clock_uncertainty.rpt:142）。

反直觉的那一条到此成立：**"全设计最差 hold"与"吃了带子的那条 hold"不是同一条路**，
两个读数 0.037 与 0.049 各自来源：build/clock_uncertainty.rpt:20 与来源：build/clock_uncertainty.rpt:93。

### 2.3 四域 WHS 为什么互相不可比

把 §2.1 的射程套到 §1.5 的读数上，得到的是四把不一样的尺子：

| 域 | WHS ns | 出处 | 这一格里含 0.800 的自加悲观吗 |
| --- | --- | --- | --- |
| `eth_rxc` | 0.052 | 来源：build/report/timing_summary.rpt:182 | 含（来源：src/constraints/rk_zynq7020.xdc:50） |
| `clk_fpga_0` | 0.053 | 来源：build/report/timing_summary.rpt:181 | 不含 |
| `clkout0_1` | 0.059 | 来源：build/report/timing_summary.rpt:186 | 不含 |
| `sys_clk` | 0.222 | 来源：build/report/timing_summary.rpt:183 | 不含 |
| `clkout1_1` | 无该行 | 来源：build/report/timing_summary.rpt:187 | 不适用（这一档没有被计时的 setup/hold 端点，来源：build/report/timing_summary.rpt:946） |

"0.052 和 0.053 差不多"这句话在这张表里不成立，因为 0.052 是**已经扣掉 0.800 之后**剩下的。
这条禁令有明确的出处，探针脚本的头部原话是
`would be an artifact of the constraint`（来源：build/tcl/probe_uncertainty_uniform.tcl:10），
它上一行点名的正是这件事的成因：`That makes the four per-domain WHS numbers in the roster NOT comparable to each other`（来源：build/tcl/probe_uncertainty_uniform.tcl:8）。

### 2.4 那把带子挂满所有域的对照：设计成"只动一个变量"

`build/tcl/probe_uncertainty_uniform.tcl` 是只读探针：开已布线 dcp（来源：build/tcl/probe_uncertainty_uniform.tcl:19），
先逐钟读 before（来源：build/tcl/probe_uncertainty_uniform.tcl:36），然后**只施加一个变量**：

```tcl
catch { set nset [llength [set_clock_uncertainty -hold $BAND [get_clocks *]]] } uerr
```

（来源：build/tcl/probe_uncertainty_uniform.tcl:44，BAND 默认 0.800 见来源：build/tcl/probe_uncertainty_uniform.tcl:23）

它带两条防空转的判据，这两条比读数更重要：

1. **命中数为 0 就拒绝跑**：`if {$nset == 0} { puts "REFUSE: set_clock_uncertainty 一条也没落上（这一体检没有变量）"; exit 4 }`（来源：build/tcl/probe_uncertainty_uniform.tcl:47）。
   这是 §3 那条"射程"判据在最简单场景下的实现——没有变量就没有实验。
2. **属性要读回来**：`catch { set readback [get_property HOLD_UNCERTAINTY $probeclk] }`（来源：build/tcl/probe_uncertainty_uniform.tcl:51），
   注释写的是"写了但工具没吃"是这类实验最常见的假绿（来源：build/tcl/probe_uncertainty_uniform.tcl:48）。

还有第三条是**口径隔离**：它顺手也读一次 setup 最差值（来源：build/tcl/probe_uncertainty_uniform.tcl:76），
注释给了理由——`同一批路径的最大 slack 不应该因为 -hold 带而变；变了就说明口径没隔离干净`（来源：build/tcl/probe_uncertainty_uniform.tcl:73）。

实跑读数留在 `build/evidence/r115_unc/summary_hold_after.txt`，那份件自己的命令就是
`report_timing_summary -delay_type min`（来源：build/evidence/r115_unc/summary_hold_after.txt:6），
所以它只有 hold 与脉宽两栏——口径与 §1.5 那份全类型汇总不同，不能拿来比 setup。
设计级那一行读到 −0.747 / THS −8112.086 / 失败 25742 / 总 51135，
同一行的 WPWS 仍是 0.264、TPWS 失败 0（来源：build/evidence/r115_unc/summary_hold_after.txt:151）——
脉宽检查不吃 hold 带，这一格不变本身就是"口径隔离干净"的证据；同件下面那句 `Timing constraints are not met.`（来源：build/evidence/r115_unc/summary_hold_after.txt:154）
是设计级判定跟着变了的那一行。逐域：`clk_fpga_0` 为 −0.747、失败 8124、总 15721（来源：build/evidence/r115_unc/summary_hold_after.txt:181）、
`sys_clk` 为 −0.578、失败 310、总 323（来源：build/evidence/r115_unc/summary_hold_after.txt:183）、
`clkout0_1` 为 −0.741、失败 17304、总 30179（来源：build/evidence/r115_unc/summary_hold_after.txt:186），
而 `eth_rxc` 那行仍是 WHS 0.052、失败 0、总 4835（来源：build/evidence/r115_unc/summary_hold_after.txt:182）——它本来就是在 0.800 带下做到正的。
等式核对：`0.053 − 0.800 = −0.747`，三个数分别来源：build/report/timing_summary.rpt:181、来源：src/constraints/rk_zynq7020.xdc:50、
来源：build/evidence/r115_unc/summary_hold_after.txt:181，三边对上。
跨域那两行也跟着变红：`clkout0_1 → sys_clk` 的 WHS 变成 −0.635、失败 18 个（总 19 个，来源：build/evidence/r115_unc/summary_hold_after.txt:198），
`sys_clk → clkout0_1` 变成 −0.600、失败 9 个（总 231 个，来源：build/evidence/r115_unc/summary_hold_after.txt:199）——
对照 §1.5 那两行的正数，这是"带子加满之后跨域路也一起被重算"的直接证据。

最后一条是这类实验的通用警告，脚本头部写着：布线后只改 uncertainty，工具只重算余量、**不重跑布局布线**，
所以 "after" 是"统一悲观模型下的 what-if"，不是重新优化过的设计（来源：build/tcl/probe_uncertainty_uniform.tcl:14）。

### 2.5 setup 侧的带子：一条都没有，这是公开欠账

`set_clock_uncertainty` 全仓只有 §2.1 那一条，方向只有 hold（来源：src/constraints/rk_zynq7020.xdc:50），
所以四个域的 **setup 侧一条不确定度声明都没有**。补它们不会让设计变快，只会让读数变小（把债显形）。
这一条与 §5.8 的否决刀、§6.4 的门禁项一起构成"本项目的 hold 口径是半套"这个事实。

---

## 3 换钟 / 改名为什么会让约束射程静默缩小

### 3.1 机制

`set_clock_uncertainty`、`set_clock_groups`、`set_input_delay`/`set_output_delay` 都是**按名字取对象**的命令。
重源化（换 MMCM、换 BUFG、多例化一个 `clk_gen`、改分频）之后生成钟的名字会变，
旧名字不再命中任何对象；工具不为这个报错，只留一句 warning。
于是同一份 .xdc 覆盖的范围悄悄变小，而 slack 读数"更好看"——**改善是假象，检查减少是事实**。

本仓已经有的名字证据：`clk_gen` 被例化两次，所以 Clock Summary 同时列出
`clkfbout` 与 `clkfbout_1`、`clkout0_1`、`clkout1_1`（来源：build/report/timing_summary.rpt:167，`_1` 那几行是 168-171）。
`_1` 不是人写的，是工具为了区分重名自动加的后缀。**任何写死 `get_clocks clkout0` 的约束在这份工程里现在取不到对象**，
因为报告里存在的名字是 `clkout0_1`（来源：build/report/timing_summary.rpt:169）。
这一步变化连一次"优化"都不需要，只是多例化了一个模块。

### 3.2 三种写法的稳健性可以排出来

| 写法 | 出处 | 换钟后的行为 | 为什么 |
| --- | --- | --- | --- |
| `-include_generated_clocks sys_clk` | 来源：src/constraints/clock_groups_impl.xdc:31 | 稳 | 按拓扑关系抓下游生成钟，不依赖具体生成钟名 |
| `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]` | 来源：src/constraints/rk_zynq7020.xdc:50 | 稳 | `eth_rxc` 是顶层端口钟，名字由本仓 `create_clock -name` 钉死（来源：src/constraints/rk_zynq7020.xdc:36） |
| 候选件里写死 `_1` 后缀的输出窗 | 来源：src/constraints/r119_hdmi_source_window.xdc:51 | **脆** | 再加第三个 MMCM 实例，像素钟可能变成 `clkout0_2`，这条窗会静默脱靶 |

`-include_generated_clocks` 这个后缀不是风格选择而是**假违例的解药**，
文件里记的就是账：少了它，`clk_pix` 会被当成独立时钟去和 `eth_rxc` 做 setup 分析，
历史上是 WNS≈−6.7 的假违例（来源：src/constraints/clock_groups_impl.xdc:16）。
同一处还留了一句反向的纪律：`clk_pix` 与 `clk_pix5x` **有意留在同一组内**，
让 TMDS 并串转换按同步路径做 setup 分析，`声明成异步反而会漏检`（来源：src/constraints/clock_groups_impl.xdc:26）。

### 3.3 把覆盖面变成一行可打印的数

光讲机制不够，本仓把"约束里写的名字"与"实际存在的名字"做成了**差集计数**并打进名册头部。
`build/roster/roster_r118.tsv` 第 4 行整行就是这一件事，它开头是 `# 名册缺口`，
后面一口气给出 `gaps=loaded_xdc=2`、`loaded_declared_clocks=3`、`reported_clocks=8`、`rostered=8`、
`gap=0`、`候选件独占名=1`（来源：build/roster/roster_r118.tsv:4），并在行尾点名算法出处
`build/p15b_parse_reports.py::clock_gap_count`（来源：build/roster/roster_r118.tsv:4）。
同一行还带着那五个"报告里有名字、但本轮加载的约束没提过"的钟名清单。
下面把这一行给的数逐个说清它挡哪种谎：

- `loaded_xdc=2` 复算 §1 的结论（约束份数由 fileset 数出来，不靠注释）；
- `loaded_declared_clocks=3` 是 .xdc 里点过的名字数（`sys_clk`、`eth_rxc` 由本仓 create，`clk_fpga_0` 由组命令点名，见来源：src/constraints/clock_groups_impl.xdc:29-31）；
- `reported_clocks=8` 与 `rostered=8` 相等 ⇒ **名册没有漏档**。这条相等关系正是名册生成器自己的地板：
  行数下限 8（来源：build/roster_from_summary.sh:89 的 `floor>=8`）；
- `gap=0` ⇒ 约束点到的名字全部还存在；这一格一旦从 0 变成非 0，就是 §3.1 那个机制真的发生了；
- `候选件独占名=1`（那个名字是 `r119b_tmclk`）⇒ 有一个钟名只被**没加载**的候选件声明过，它是射程账上明确的一笔；
- 后面那五个名字就是 MMCM 的反馈钟与派生钟（来源：build/report/timing_summary.rpt:167 起那五行 167-171）。

同张名册还钉了一条 `NA` 的语义，这条在所有逐域表上都成立：
`NA = 该域在 Intra Clock Table 里只有名字没有 intra 路径`（来源：build/roster/roster_r118.tsv:2），
同一行后半句把边界画死：`解析失败在本口径里写 NOT_MEASURED`（来源：build/roster/roster_r118.tsv:2）。
逐轮台账把这同一条又念了一次，并列出三个"不是"：`NA` = 该域没有同类路径，**不是**读不到、**不是** 0、**不是**通过（来源：build/runs/ledger.md:29）。
还有一条容易被跳过的口径冲突也写在名册头部——本表 `rel_margin_*` 是**比值**（0.185000 = wns/period，来源：build/roster/roster_r118.tsv:3），
而探针名册的 `margin_pct` 是**百分数**，两把尺子并存、裁决以名册表为准（来源：build/roster/roster_r118.tsv:3）；
名册那一行的 `0.185000` 复算一下就是 `1.850 ÷ 10.000 = 0.185`（两个操作数分别来源：build/report/timing_summary.rpt:181 与来源：build/report/timing_summary.rpt:164）。

### 3.4 三条复查动作（可以照抄）

1. 先建钟名册、再建 slack 名册：把 .xdc 里所有 `get_clocks` 的字面量与报告 Clock Summary 的钟名取交集，
   差集非空先解释差集再看数（这条的机器版本就是 §3.3 那一行）。
2. 把"约束命中数"当读数记账：探针已经在这么干（来源：build/tcl/probe_uncertainty_uniform.tcl:44 数命中，:47 零命中即 REFUSE，来源：build/tcl/probe_uncertainty_uniform.tcl:51 读回属性）。
3. 改钟之后第一次读数**只能用来判射程有没有变小**，不能用来判设计有没有变快——
   这条与 §5.5 的 rule 35 是同一条规矩的两个方向。

---

## 4 跨域约束：现状、结构账与两笔明文欠账

### 4.1 时钟组的实际声明只有 3 行

`clock_groups_impl.xdc` 全文只有一条命令（来源：src/constraints/clock_groups_impl.xdc:28），
三个组各写一行，第三行带 `-include_generated_clocks`（来源：src/constraints/clock_groups_impl.xdc:31）：

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]
```

（逐字在来源：src/constraints/clock_groups_impl.xdc:28 至 :31）

这里的 `-quiet` 是**合法用法**而不是 §1.4 那种踩坑：它挂在唯一那颗"综合阶段不存在、实现阶段存在"的钟上，
而这一份文件本身只在实现阶段生效（来源：build/tcl/build_system_axigpio.tcl:37），
所以取不到对象的情形在这一档里已经不会发生。

### 4.2 结构账：四条跨域路各自靠什么

约束把组间检查关掉之后，跨域正确性只剩结构。这张台账写在同一个文件里（来源：src/constraints/clock_groups_impl.xdc:20 起那四行 20-23）：

| 方向 | 结构 |
| --- | --- |
| `eth_rxc → clk_fpga_0` 视频流 | `dc_fifo`（格雷码 + 2FF，BRAM） |
| `eth_rxc → clk_fpga_0` 帧事件 | 翻转 + 3FF 边沿检测（`ddr_bank_commit`） |
| `clk_pix → clk_fpga_0` 消隐窗 | 3 级像素 + 3FF（`frame_commit_lock`） |
| `clk_fpga_0 → clk_pix` 控制字 | 3FF（`pl_video_top` / `effect_ctrl`） |

这张表的读法要点是：**它不是"已经满足时序"的替代品，而是"不参与时序检查"的替代品**。
组间一旦被排除，`report_timing` 就不会再看这些路，工具能看到的只剩 Inter Clock Table 那两行（来源：build/report/timing_summary.rpt:198）。
`cdc.rpt` 给的又是第三种口径——它是**聚合计数**、不点名信号，
所以顶层文件里那句注释把这把尺子的边界写死了：这份报告不点名信号，只能证明这一类端点变少了，逐信号凭据要写台架（来源：src/constraints/clock_groups_impl.xdc:20 所在文件的配套说明见 §4.4）。

### 4.3 欠账一：`set_max_delay -datapath_only` 一条都没进构建

异步组把组间检查整体关掉之后，那四条跨域路连"数据路径上界"都没有。
候选件里四条界是**写好的**，界值取的是目的钟周期：

```tcl
set_max_delay -datapath_only -from [get_clocks eth_rxc] -to [get_clocks clk_fpga_0] 10.000
set_max_delay -datapath_only -from [get_clocks clk_fpga_0] -to [get_clocks eth_rxc] 8.000
set_max_delay -datapath_only -from [get_clocks clk_fpga_0] -to [get_clocks clkout0_1] 20.000
set_max_delay -datapath_only -from [get_clocks clkout0_1] -to [get_clocks clk_fpga_0] 10.000
```

（逐字分别在来源：src/constraints/r114_io_async.xdc:57、:59、:61、:63；界值口径"目的钟周期"写在来源：src/constraints/r114_io_async.xdc:52）

四条界值与 Clock Summary 的周期一一对得上：10.000 / 8.000 / 20.000（来源：build/report/timing_summary.rpt:164 到 :169 之间那几行）。
这个文件**没有被任何脚本 `add_files`**，所以四条界现在是 0 条生效——
台账把这一条记成"明文欠着的账"而不是"试过不行"（来源：report/timing/debt_ledger.md:98 那句 `没有任何 set_max_delay -datapath_only 给出界`）。
候选件头部还如实留了第五条没写的：`set_bus_skew` 需要点到同步器单元名，而探针在 `get_false_paths` 上死了（该命令在本工具不存在），
所以这一条继续挂着、不写成已做（来源：src/constraints/r114_io_async.xdc:64）。

这条属于"推迟"而不是"否决"，区别要念出来：它一旦挂上，本来在任何尺子里都不出现的路会进名册、头条可能变难看，
所以它是**揭示债**那一类动作，代价是读数变难看，不是设计变慢（口径来源：src/constraints/r114_io_async.xdc:52 那句"不是收益声明"）。

### 4.4 欠账二：11 个 I/O 端口从来没被检查过

`check_timing` 给的是**桶计数**，它不点名，而且**标题与正文的单位不同**——
这是本项目在 I/O 射程上栽过的具体一课：同一个桶给了两个不同单位的数，标题数 pin、正文数 port，而且从不点名是哪几个（来源：build/tcl/probe_io_timing_names.tcl:4）。
现行名册把这一格当成一个读数在记：`io_unconstrained_ports = 11`，单位是端口对象，输入 5 + 输出 6（来源：build/roster/roster_r118.tsv:7），
名册表里每一行都把这 11 重复填在自己的列上（例：clk_fpga_0 那行，来源：build/roster/roster_r118.tsv:10）。

两半各自的账：

| 半 | 端点 | 数字有出处的地方 | 定性 |
| --- | --- | --- | --- |
| 输入 5 | `eth_rx_ctl` + `eth_rxd[0..3]` | 来源：src/constraints/r114_io_async.xdc:12 | 试过绑窗，一绑 hold 就红，退回候选件（§5.8 第二把刀） |
| 输出 6 | `led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]` | 来源：src/constraints/r114_io_async.xdc:13 | `led` 没有可引用的对外窗；TMDS 走源端 TP1 口径，量过并判负（§5.8 第三把刀） |

这里有一条纪律值得抄：给某颗钟"不查"的定性**属于一次放宽**，必须先进放宽账本；
而候选件当时写的是账本仍 0 条，所以那份文件不替 `led` 写任何窗（来源：src/constraints/r119_hdmi_source_window.xdc:47）。
放宽账本今天确实是空的——`report/timing/loosen_ledger.tsv` 只有表头加注释，数据行 0，
注释原话是"一张空表比一张'我替用户批了'的表诚实"（来源：report/timing/loosen_ledger.tsv:6）。

---

## 5 关键路径归因：名册怎么生成、差分怎么判、刀怎么记

### 5.1 三件工具，分工不同，别互相替

| 工具 | 它出什么 | 它的形状约束 | 出处 |
| --- | --- | --- | --- |
| `build/tcl/crit_path.tcl` | setup 侧**摘要**：每条路径一行 slack / 组 / 起点 / 终点 / 级数 | `-nworst 1 -max_paths 8`，一屏读完 | 来源：build/tcl/crit_path.tcl:36 |
| `build/tcl/probe_timing_roster.tcl` | **逐时钟**名册：每颗钟 setup 与 hold 各一行，带 period / slack / margin_pct / levels / route_pct / dest | 遍历 `get_clocks -quiet *` | 来源：build/tcl/probe_timing_roster.tcl:29 与 :81 |
| `build/tcl/r124_tiers_probe.tcl` | 每颗钟**前 12 档**的阶梯（每档不同端点） | 只读、重跑到 route_design、带两道准入门 | 来源：build/tcl/r124_tiers_probe.tcl:20 |

为什么需要后两件，脚本头部写得很直白：`crit_path.tcl` 只把全设计最差那条排第一，
所以每轮看到的都是同一颗 `eth_rxc`，其它三个域是涨是跌没人念（来源：build/tcl/probe_timing_roster.tcl:6）。
名册生成器的成本也给了：在已布线 dcp 上几分钟、不重建，
所以"看全局"这件事是便宜的（来源：build/tcl/probe_timing_roster.tcl:10）。

### 5.2 参数纪律：`-nworst 1 -max_paths N`，并且**从写出的文件里反读 distinct 计数**

`-nworst 1` 的理由不是风格：每条路径只报最坏那一个端点，
不然一屏 8 条里会把同一条锥的兄弟端点重复数（来源：build/tcl/crit_path.tcl:34）。
`-max_paths 8` 定的是"一屏读得完，而且第 2 条就能看出是不是同一条锥"（来源：build/tcl/crit_path.tcl:35）。
名册那一侧把这条纪律换成 `-nworst 1 -max_paths 12`，
并且件头自己写明这一档的含义：`下面每行是一个**不同端点**`（来源：build/evidence/r124_tiers_ladder.txt:13）。

同一件还钉了一条"两种数不能混读"：另一次数的是**端点重数**（`0.739x5` 那一类），
两者不矛盾，同一档的多个位属于同一只锥（来源：build/evidence/r124_tiers_ladder.txt:14），
台账 C10 行把这条写成了正式口径（来源：report/timing/cut_ledger.tsv:11）。

反读 distinct 计数这件事是名册生成器的形状判据：`ROSTER_ROWS=$nrows` 打在最后（来源：build/tcl/probe_timing_roster.tcl:173），
而行数不足由判定器的地板挡：行数下限 8、周期至少 2 个、百分数不许有 NA、周期 × 频率必须约等 1000（来源：build/roster_from_summary.sh:89 起的 S1/S2/S3/S4 四行）。
其中 S4 那条是本项目最实用的一条防呆——它把"周期列取错一格"变成可判红的事：判据是 `周期 × 频率 ≈ 1000`，
而这两个操作数取自同一张表的不同列（来源：build/roster_from_summary.sh:63）。
它防的是这一族最阴的事故：`clk_fpga_0` 那一行里 `$3` 是波形下降沿、不是周期（来源：build/roster_from_summary.sh:62），
`$4` 才是 Period(ns)，取错一格会整张表自洽地错，
只有把外部真值钉上去才抓得住——`eth_rxc` 是 125 MHz RGMII，周期必须是 8.000 ns（来源：build/roster_from_summary.sh:30）。

### 5.3 名册有两条生成器，所以差分前要先对口径

`probe_timing_roster.tcl`（探针，还能带 levels / route_pct / dest）与 `roster_from_summary.sh`
（离线，从报告的 Intra Clock Table 长回来，这三列一律写 NA）是两台生成器（来源：build/roster_from_summary.sh:12）。
为什么要离线那条：改前那一版的 routed dcp 每轮都被覆盖，而 `timing_summary.rpt` 每轮都归档（来源：build/roster_from_summary.sh:9）。

差分脚本 `build/timing_roster_diff.sh` 在动手相减之前有一道**口径闸门**，
它只管三件事：A 侧的钟不许在 B 侧消失、B 侧新增的钟必须 setup+hold 两行齐、扇出节必须同有同无（来源：build/timing_roster_diff.sh:135）。
三种情形分别给三种结局，其中"多出一颗钟"这一支是后来改的，理由很值得记：

- A 里的钟在 B 里**消失** = 真口径不一致 ⇒ REFUSE（整路消失不可能是代价）；
- B 多出的钟 setup/hold **两行齐** = 这一轮把那条路从"没人检查"变成"有窗可检查"，单独打印一行 `ROSTERDIFF-NEWTIMED` 让人看见、不挡（来源：build/timing_roster_diff.sh:128）；
- B 多出的钟**只有半行** = 不是同一把生成器 ⇒ REFUSE。

（三档定义逐条写在来源：build/timing_roster_diff.sh:117）

第一版把这三种情形一律 REFUSE，结果把正当实验挡回去了——
"假拒绝挡掉正当实验"和"射程漂移"是两个方向相反的同族错误，脚本注释把这件事留在了原地（来源：build/timing_roster_diff.sh:109）。
闸门**不管 slack 字段长什么样**：探针那份本来就带散文 `NOWRITE` 这类行，awk 取前导数就够用（来源：build/timing_roster_diff.sh:108）。这条也是踩过之后才放宽的：
一次拿探针名册减离线名册，D3 数出 big_loss=8、D6 念 fanout_rows=0，看着像"别的域被挤坏了"，
其实两侧根本不是一个口径，那份件被改名并在名字里写明别再当裁决读（件名与教训同处，来源：build/timing_roster_diff.sh:106）。

### 5.4 差分的六条判据与事前登记的门槛

差分打印 6 项（`ROSTERDIFF-SUMMARY ... judged=6`，来源：build/timing_roster_diff.sh:215），逐条是：

| 判据 | 它判什么 | 期望 | 出处 |
| --- | --- | --- | --- |
| D1_no_new_violation | 有没有哪个域从 MET 变成违例 | new=0 | 来源：build/timing_roster_diff.sh:206 |
| D2_pairs_compared | 配上的 (时钟,类型) 对数，**防空转** | floor ≥ 8（4 域 × setup/hold） | 来源：build/timing_roster_diff.sh:207 |
| D3_margin_cost | 同域相对余量（slack/period）掉过门槛的域数 | 0 | 来源：build/timing_roster_diff.sh:208 |
| D4_hold_covered | hold 侧至少配上几对 | ≥ 2 | 来源：build/timing_roster_diff.sh:209 |
| D5_no_empty_readings | A 有读数、B 变成空 | 0 | 来源：build/timing_roster_diff.sh:210 |
| D6_fanout_inventory | 扇出名册有没有行 | ≥ 1 | 来源：build/timing_roster_diff.sh:211 |

门槛是**开工前登记的**两个常量：`LOST_PCT=${LOST_PCT:-25}`（相对余量掉两成算代价，来源：build/timing_roster_diff.sh:19）与 `FLOOR_PAIRS=${FLOOR_PAIRS:-8}`，注释写的是至少要配上的对数等于 4 个域 × setup/hold（来源：build/timing_roster_diff.sh:20）。
D5 的口径修过一次，改得很说明问题：以前只要 B 侧那格是 NOWRITE 就计数，
可 MMCM 的反馈钟与辅助输出本来就**两侧都**没有端点，于是合法配对被念成 `empty_in_B=8 RED`；
真正要抓的是"A 有读数、B 变成空"（来源：build/timing_roster_diff.sh:163 至 :166）。
`--self` 一共 11 条对照，其中第 2、3 条正是这套体系存在的理由：
头条没动、但某个域从 MET 掉成违例必须红，标签 `control_other_domain_violates`（来源：build/timing_roster_diff.sh:54）；头条没动、但某域相对余量掉三成也必须红，标签 `control_margin_loss`（来源：build/timing_roster_diff.sh:56）。
第 6 条把 **GAIN 行本身的形状**也当判据：`+-31.7%绝对` 那种双符号加错单位复现出来就判红（来源：build/timing_roster_diff.sh:66）。

### 5.5 那条规矩：绝对 WNS 差不记成收益，也不记成损失

这是全套归因方法的**记账底座**，它有三处一致的表述，可以互相当对照：

1. 台账口径 T2：`WNS 的绝对差本身既不算收益也不算损失`，并且给的是失败端点数而不是"提升了 x ns"（来源：build/runs/ledger.md:15）；
   同一行给的实例是 r114 那轮 `ASYNC_REG` 头条 WNS 0.445→0.739，但最差路径**换了族**，所以那 +0.294 不记在本刀名下（来源：build/runs/ledger.md:15）。
2. 探针件头：`全局 WNS 的绝对差不算收益也不算损失（rule 35）`（来源：build/evidence/r118_after.txt:4）。
3. 差分脚本把它写成机器输出：`绝对差不算收益也不算损失，rule 35`（来源：build/timing_roster_diff.sh:203 那条 `ROSTERDIFF-HEADLINE`）。

它挡住的具体事故是这两类，而且第二类更常见：

- 把"最差那一格的持有者换了"念成"设计变快/变慢"。
- 把一个域改坏了而头条没动——这条是差分光有 rule 35 还不够、必须逐域配对的原因，
  脚本头部原话：规矩 35 早就说过绝对差不算收益也不算损失，
  `但那只挡住了"拿差值吹收益"，没挡住"把一个域改坏了而头条没动"`（来源：build/timing_roster_diff.sh:11）。

只许记的两种账因此是：**同一次构建、同一条锥的相对余量变化**，以及**逐域名册的配对差分**。
名册生成器自己那行注释把这句话说成了"改前名册可以从报告里长回来，不必拿全局 WNS 说事（rule 35）"（来源：build/roster_from_summary.sh:11）。

### 5.6 归因结论：这个瓶颈到底是"什么"

12 档阶梯是归因的原始形状。`eth_rxc` 那 12 行逐档抄自件（来源：build/evidence/r124_tiers_ladder.txt:19 起，档表头见 :18）：

| 档 | slack ns | 终点 | 起点 | 级数 | 出处 |
| --- | --- | --- | --- | --- | --- |
| 1 | 0.739 | `check_buffer_reg[19]/D` | `u_eth/u_icmp/u_icmp_tx/ip_head_reg[4][16]/C` | 11 | 来源：build/evidence/r124_tiers_ladder.txt:19 |
| 2 | 0.873 | `check_buffer_reg[17]/D` | 同上 | 11 | 来源：build/evidence/r124_tiers_ladder.txt:20 |
| 3–12 | 0.961 起 | `rows_hit_reg[*]/CE` 一族 | `u_eth/u_rx_par/p_eof_reg/C` | 4 | 来源：build/evidence/r124_tiers_ladder.txt:21 起 |

三条结论都从这张表直接读出来，而且各自有件：

1. **前 3 档是同一只校验和锥**：三行的起点是同一只 `ip_head_reg[4][16]`（上面三行的起点列，来源：build/evidence/r124_tiers_ladder.txt:19），
   级数 11、route 约 58 %（该行的 route 列，来源：build/evidence/r124_tiers_ladder.txt:19）。
   门禁件 `分组最差` 也独立指到同一只起点（来源：build/r126_gates.txt:32 那行给的正是 `eth_rxc` 0.739）。
2. **拆这只锥的上界只有 +0.278 ns**：算式 `1.017 − 0.739 = 0.278`，
   两个操作数分别是第 4 档与第 1 档的 slack（来源：build/evidence/r124_tiers_ladder.txt:21 与来源：build/evidence/r124_tiers_ladder.txt:19），
   这条上限连同"接棒的是同域 1.017×8，不是 0.739→1.8"一起记在台账 C10 行（来源：report/timing/cut_ledger.tsv:11）。
3. **4 到 12 档整段是那只 CE 使能广播**：级数只有 4、route 85 % 上下（`p_eof_reg` → `rows_hit_reg[*]/CE`，来源：build/evidence/r124_tiers_ladder.txt:21），
   于是"拆锥"这一类杠杆治不了它——能动只剩复制与摆放，而那类已经被量过两次（§5.8）。

`crit_path.tcl` 那份摘要给的是同一件事的另一半证据，8 行里前 3 行同一只锥、后 5 行同一族 CE 终点
（来源：build/crit_paths.txt:5 起，起点列在每行末尾，来源：build/crit_paths.txt:8）。
**两条限定要念**：这个上限受探针归档深度限制（`-max_paths` 那一档只捞得到每族最前的几条，来源：build/evidence/r124_tiers_ladder.txt:13）；
而且台账 C10 行的状态是 `measured-none`，注释写明此前两张台账各零行、是台账洞、不等于试过不行（来源：report/timing/cut_ledger.tsv:11）——
所以"到极限了"这句话不许说。

### 5.7 采纳的刀：三把，没有一把用绝对 slack 邀功

| 刀 | 动在哪 | 量到什么 | 记什么账、不记什么账 | 判据出处 |
| --- | --- | --- | --- | --- |
| `dc_fifo` 四颗灰码 FF 补 `ASYNC_REG` | 属性挂在四颗灰码指针上（来源：src/rtl/eth/dc_fifo.v:27） | 布线后网表上带该属性的单元从 0 变 56 颗（来源：study_docs/main_report_study/timing/02-how-this-project-did-it.md:308），同构建 WNS 0.445→0.739（来源：build/r113_gates.txt:10 与来源：build/r114_gates.txt:10） | `ASYNC_REG` 是放置指令，那 +0.294 不记在本刀名下；只有资源逐字中性才叫免费（来源：study_docs/main_report_study/timing/02-how-this-project-did-it.md:490） | 来源：study_docs/main_report_study/timing/02-how-this-project-did-it.md:490 |
| OSD 读侧插一拍 | `pl_video_top` 的 OSD 读口 | 目标域 `clkout0_1` 相对余量抬升，代价是 +2 LUT / −6 FF | 记"同一次构建、同一条锥的相对余量"；全设计 WNS 掉了只念持有者换了（来源：build/runs/ledger.md:15） | 来源：build/runs/ledger.md:15 |
| `snap_cross.hb_gone` 声明初值 | `src/rtl/eth/snap_cross.v` 把上电值写进声明（来源：src/rtl/eth/snap_cross.v:29） | 上电 FF INIT 从 1'b0 变 1'b1 | 不碰 slack，所以不进收益账；它买的是"断链诊断在上电那一拍不说谎"（状态标签见台账 T7，来源：build/runs/ledger.md:20） | 来源：build/runs/ledger.md:20 |

`cut_ledger.tsv` 的 C1 行给出"机制必须真动了"的判据形状：`REPLICA_CELLS 行必须严格大于对照滚`，
并把复制杠杆的真实代价点名成 `r114 的教训`（来源：report/timing/cut_ledger.tsv:2）。

### 5.8 被否决的刀：连读数一起公开

否决也要有数。下面每把给：动什么、名册差分怎么变、代价、按哪条判据判负。
差分两行都是从归档件里逐字抄的：变差的那一行以 `ROSTERDIFF-COST` 开头、变好的那一行以 `ROSTERDIFF-GAIN` 开头（来源：build/timing_roster_diff.sh:213）。

| # | 刀 | 名册差分（相对余量口径，逐字） | 结局 | 出处 |
| --- | --- | --- | --- | --- |
| 1 | RGMII 输入窗（r116）：5 个收端点第一次绑输入窗 | `eth_rxc/setup:0.739->-0.846ns`、`相对余量-214.4%`、`eth_rxc/hold:0.052->-0.870ns`（来源：build/evidence/r116_roster_diff.txt:16）；同轮 `clk_fpga_0/setup:1.850->1.976ns` 与 `clkout0_1/setup:3.630->3.698ns` 反而变好（来源：build/evidence/r116_roster_diff.txt:17） | 新违例计数 `new=2`（来源：build/evidence/r116_roster_diff.txt:10）⇒ 默认不加载，留在仓里当候选件加全份证明（来源：build/tcl/build_system_axigpio.tcl:53）；撤销的不是约束的正确性，是把它带进发布物这个动作（来源：build/tcl/build_system_axigpio.tcl:55） | 同左 |
| 2 | 强制复制广播网（r117）：`phys_opt_design -force_replication_on_nets` 挂 POST 钩 | 机制动了：`pins_after=1`、`replica_cells=10`（来源：build/r117_verdict_declined.txt:3）；差分五档 `margin_pct 18.50->21.04`（来源：build/r117_verdict_declined.txt:5）、`18.15->16.77`（:7）、`9.24->7.69`（:9）、`0.65->0.55`（:10）、`74.38->74.08`（:11） | 赢 1 格、跌 4 格，含最紧与最薄两格 ⇒ 判 `DECLINED`（来源：build/r117_verdict_declined.txt:13），预登记判据是"任何一格相对余量不许变小"（来源：build/r117_verdict_declined.txt:13） | 同左 |
| 3 | HDMI 源端 TP1 窗（1006d）：`set_output_delay -clock clkout1_1 -max`（来源：src/constraints/r119_hdmi_source_window.xdc:51） | `clkout1_1` 这一轮才第一次有行：`ROSTERDIFF-NEWTIMED clk=clkout1_1`（来源：build/evidence/1006d_roster_diff_vs_r118.txt:1）；代价 `eth_rxc/setup:0.739->0.471(相对余量-36.3%)` 与 `sys_clk/hold:0.222->0.121(相对余量-45.9%)` 等七格（来源：build/evidence/1006d_roster_diff_vs_r118.txt:17），只有 `clkout0_1/setup:3.630->3.945(相对余量+8.7%)` 一格变好（来源：build/evidence/1006d_roster_diff_vs_r118.txt:18） | 判据 D3 数出 `big_loss=2` ⇒ 红（来源：build/evidence/1006d_roster_diff_vs_r118.txt:12），不加载；这一档同时也回答了 §1.5 那个空行：新增的 I/O 窗才创造了被检查的端点 | 同左 |
| 4 | 换 IDDR 捕获钟（C3） | 副本树 `WHS -2.126`，且那 0.800 的带子脱离派生钟覆盖面 | 状态 `rejected-measured`，不进主树（来源：report/timing/cut_ledger.tsv:4） | 来源：report/timing/cut_ledger.tsv:4 |
| 5 | BRAM 换 setup | 采纳基线 +0.516 → 只拆三块 +0.232 → 拆加寄存 +0.182（来源：study_docs/main_report_study/timing/02-how-this-project-did-it.md:443） | 判拥塞主导、否决并回退（来源：study_docs/main_report_study/timing/02-how-this-project-did-it.md:439） | 同左 |
| 6 | Pblock 区域约束 | 没量到：构建在两分钟内自己拒绝（来源：report/40-optimization.md:114） | 只能念"没做成一次对照"，不能当独立负结果；route 侧那条判据会数 `Place 30-439`（来源：report/timing/gates_g1_g12.md:16） | 同左 |
| 7 | ICMP 校验和摊拍（C10） | 只做过差分预验，`+0.278 上限（接棒的是同域 1.017x8，不是 0.739->1.8）`（来源：report/timing/cut_ledger.tsv:11） | 状态 `measured-none`——此前两张台账各零行，是台账洞，不等于试过不行（来源：report/timing/cut_ledger.tsv:11）；且改网表 ⇒ 快车道不适用 | 同左 |

三条判读规则可以一起带走：

- **两把尺子对同一份数据可以给相反判语**，交付承诺按严格那把判；这里"严格"的定义写在判定行 itself：
  `预登记判据 A2/A3 是严格口径（任何一格 rel_margin 不许变小）`（来源：build/r117_verdict_declined.txt:13）。
- **"资源便宜"不是采纳理由，"谁的余量被扣了"才是**——这条从 C1 行的 risk 栏就能读出来：
  复制可能把 hold 挤薄（来源：report/timing/cut_ledger.tsv:2）。
- 台账口径 T3 要求一轮多刀时每个数字能归属到具体改动，归不到的写"未归属"且不写进交付数字（来源：build/runs/ledger.md:16）。
  严格口径的定义是"任何一格相对余量不许变小"（来源：build/r117_verdict_declined.txt:14）。
- **"资源便宜"不是采纳理由，"谁的余量被扣了"才是**——这句是判负那批刀的合起来结论（来源：report/timing/cut_ledger.tsv:2 那行的 risk 栏）。
- 台账口径 T3 要求一轮多刀时每个数字能归属到具体改动，归不到的写"未归属"且不写进交付数字（来源：build/runs/ledger.md:16）。

---

## 6 台架体系：分类、判定形状、24 项门禁与那条常亮的红

### 6.1 82 支的三种角色

`sim/` 下 `tb_*.v` 现量 82 支（来源：sim/README.md:1 那行标题写的就是这个数），清单四列表由生成器从各台架文件头三段注释产出（来源：build/gen_sim_readme.mjs:1）。
三种角色不是一个目录划分，而是三种判据用途：

| 角色 | 例子 | 它判什么 | 出处 |
| --- | --- | --- | --- |
| 单元级 | `tb_crc32`、`tb_cdc_capacity` | 单个模块的算术/协议行为，参数写死在头注释里 | 来源：sim/README.md:53 |
| 顶层级 | `tb_v98_top_seam`、`tb_edge_rim` | 整屏逐像素与边缘条带内容；一份要跑约 108 分钟（来源：data/metrics.csv:15 的"测量条件"栏） | 来源：sim/README.md:50 |
| 变异对照 | `build/sim/mut_control.sh` 的分支 | 判本身有没有力：把修复前的写法机械复原一次，看那条判据红不红 | 来源：build/sim/mut_control.sh:9 |

顶层级那两支被门禁单独钉住，因为它们是**唯一例化顶层**的判据，而第 1 到 14 项不含任何顶层内容级判据
（缺口原话：`#88 那几天"gates 14/14"与"唯一例化顶层的台架红着"是**同时成立**的两件事`，来源：build/gates.sh:310）。

### 6.2 `run_one.sh` 的判定形状：四种 token、三层兜底、五个退出码

判定解析被单独放进一个 `--verdict` 分支，理由是尺子必须能离线被合成日志喂着验（来源：build/sim/run_one.sh:12），
而这两道 REFUSE 排在 verdict 分支之后——解析是纯文本工作，不该要求现场有 Vivado（来源：build/sim/run_one.sh:9）。

主 token 是 `RESULT <tb>`（来源：build/sim/run_one.sh:17）。认不出时依次退三层，每一层都带一条"不许变成万能兜底"的修补：

| 层 | 形状 | 限定与理由 | 出处 |
| --- | --- | --- | --- |
| 兜 1 | `PASS/FAIL <tb>[ ALL]` 顶格 | 只有 FAIL 可以带字段，且必须紧跟 `errors=` 或 `timeout`——判据行里有 `  PASS tb_x c1` 这种形状，放宽会把一条判据当成本台架判定 | 来源：build/sim/run_one.sh:19 |
| 兜 2 | `FAIL <tb> errors=` / `timeout` | 同上，兜底不许变成"谁都能冒充"（#163 那一课） | 来源：build/sim/run_one.sh:23 |
| 兜 3 | `TB RESULT PASS|FAIL`（判定行里没有台架名） | **必须**先确认这份日志里出现过本台架的名字，否则别人的过期日志能替这支台架答复"通过" | 来源：build/sim/run_one.sh:28 |

计数那一层也要容错缩进：十二支台架把每条判据打成 `  FAIL <名字>`，老的 `^FAIL` 看不见它们，
一支真红的台架会被报成"FAIL 行数=0"（来源：build/sim/run_one.sh:33）。
一条判定都没打时打 `NO-VERDICT-LINE` 并退 4（来源：build/sim/run_one.sh:36），
退出码分得很开：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 判红 / 4 认不出判定，
注释给的理由是 `红是结论，"没数"不是结论`（来源：build/sim/run_one.sh:41）。

跑真台架那一侧还有三条防混防假的结构：同一时刻只允许一个 xsim 写 `run.log`，有活的就拒绝启动且不自动杀（来源：build/sim/run_one.sh:57）；
文件清单必须走 `-f` 文件并用 `cygpath -m` 写 Windows 正斜杠路径（来源：build/sim/run_one.sh:72）；
三枚源树指纹先写 `prov.tmp`，**编译两步都过了才 `mv` 成 `prov.txt` 并删掉旧 `run.log`**，
于是编译失败时盘上留下的还是"成对旧"的凭据、冒充不了当前树（来源：build/sim/run_one.sh:101）。
末行的自调必须用绝对路径，因为脚本前面已经 `cd` 进临时目录了（来源：build/sim/run_one.sh:123）。
判定形状自己有一支对照工具：`build/run_one_ce.sh` 五条，其中一条就是"别人的过期日志不许替这支台架答复"（来源：build/sim/run_one.sh:13）。

### 6.3 变异对照：机械复原旧写法，并守住改动行数

`mut_control.sh` 不碰真源：把整棵 rtl 拷到 `/tmp` 再 sed 回旧写法，
拷贝与原件的 diff 必须恰好等于预期行数，多一行少一行都拒绝继续（来源：build/sim/mut_control.sh:14 给出理由）。
守卫的实现是 `[ "$NCH" -eq "$EXPDIFF" ] || { echo "REFUSE: 改动行数 $NCH != $EXPDIFF，复原的不是我预期的那几行。"; exit 4; }`（来源：build/sim/mut_control.sh:124），
判定那一侧只有两种出口：`MUTATION OK`（来源：build/sim/mut_control.sh:147）与 `MUTATION FAILED`（来源：build/sim/mut_control.sh:150）。

`case` 分支现量 7 条，逐个可点行：`pipeline`（来源：build/sim/mut_control.sh:48）、`osd_inchar`（来源：build/sim/mut_control.sh:59）、`osd_addr`（来源：build/sim/mut_control.sh:64）、`osd_inchar_all`（来源：build/sim/mut_control.sh:73）、`bilin_ky_fold`（来源：build/sim/mut_control.sh:82）、`shown_rate_fields`（来源：build/sim/mut_control.sh:92）、`cdc_full_next`（来源：build/sim/mut_control.sh:101）。
这里有一处**尺子自己的名单漂了**，值得当案例记：不认识 mutation 时打印的那句只列了 6 个名字，
漏掉了 `shown_rate_fields`（来源：build/sim/mut_control.sh:111），
而 `data/metrics.csv` 那一行写的是 5 条（来源：data/metrics.csv:16）。
三个数（7 / 6 / 5）互不相同，说明"分支数"这件事在三处各写了一遍、没有一把尺子回头读它——
这正是 §7 那批尺子的射程之外（`metric_recheck` 只认点名三份报告的行，来源：src/host/metric_recheck.mjs:14）。

`osd_addr` 那一支尤其值得抄：它不是反例，而是**一条判据的限度测量**——
把 DUT 读地址整体推到数组外之后那条判据仍然 0，因为判据自己按同一表达式重算索引，看不见 RTL 被改（来源：build/sim/mut_control.sh:65）。
"正例"与"改判据的 mask"的区别也写在那儿：后者只证明计数器会动，前者证明它管的是 DUT 的那道门（来源：build/sim/mut_control.sh:85）。

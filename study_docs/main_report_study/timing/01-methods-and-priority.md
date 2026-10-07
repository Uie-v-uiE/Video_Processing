# 01 · 方法与优先级：能动的五个面、每一刀的代价、以及怎么判断它真的起作用

> 这一篇的射程：把"时序红或紧"之后能做的事列成一张清单，按**约束面 / 结构面 / 物理面 /
> 工具策略面 / 判据与流程面**五个面排开，每条方法写全五栏——它能改什么、代价是什么、
> 怎么判断它真的动了（机制证据）、怎么判断它有没有用（结果证据）、这个项目在这条上量到了
> 什么或者为什么没做。最后给一棵优先级决策树和六条本项目真犯过的错。
>
> 前置：setup/hold 两把尺、WNS/WHS/TNS、逻辑级数与布线占比、时钟不确定度这几件事的定义，
> 以及报告怎么读，都在这一套三篇的第一篇里。这一篇不重讲定义，只把定义换成"能做的动作"。
>
> 读数版本：器件 `xc7z020clg484-2`，工具 Vivado / Vitis 2025.2.1（`data/metrics.csv:2`）。
> 四个受检域的 setup/hold 余量是 `sys_clk` 14.876 / 0.222、`clk_fpga_0` 1.850 / 0.053、
> `clkout0_1` 3.630 / 0.059、`eth_rxc` 0.739 / 0.052（`report/technical-document.md` §2.1 的表，
> 头条 WNS 与失败端点另见 `data/metrics.csv:5` 与 `:7`：0.739、失败 setup 端点 0 / 总端点 51135）。
> 正文里的每个数字后面都跟一条凭据；指不到凭据的句子不写。

---

## 1. 先量后动：三档成本决定了顺序

时序这一侧最贵的不是刀，是**判它有没有动那一趟**。三档成本实测如下（数据包 §2）：

| 动作 | 实测耗时 | 能判什么 | 不能判什么 |
| --- | --- | --- | --- |
| 一次全流程构建（建工程→综合→实现→出位流） | 约 20 分钟（19 分 30 秒；综合 10 分 09 秒、实现含 `write_bitstream` 7 分 22 秒） | 网表级改动的全套后果：名册、资源、告警、位流 | —— |
| 整屏顶层台架 `tb_v98` 一轮 | 约两小时（两份记录分别是 108 与 127 分钟，所以写"约两小时"） | 改网表之后的功能回归 | 单条路的 slack |
| **快车道**：不综合、不改 RTL，只从已实现的 `impl_1/*_opt.dcp` 重跑 place+route | 约 7–9 分钟（`report/timing/score.md:13` 实测一滚 ≈7.5 min；`report/timing/limit_audit_r116.md:78` 写"快车道 8 分钟可预验"） | 约束类改动、物理类改动、`phys_opt` 类改动 | 任何改网表的刀（`report/timing/cut_ledger.tsv` 的 C10 行明写"改网表 ⇒ 快车道不适用，要一次官方构建"） |
| 一次没有 design 的 `help <cmd>` 批探测 | 约 40 秒 | 这条命令在这版工具里到底存不存在、报告长什么形状 | 任何数值 |

快车道的关键性质不是"便宜"，是**确定性**：同一棵树重跑曾逐位复现正式构建的 WNS 读数
（`report/timing/gates_g1_g12.md` 第 35 行那句"快车道在这棵树上复现了正式构建的逐域名册"；
输入那份 DCP 的 md5 前 12 位钉在 `report/timing/baseline_index.md:11`）。放置是确定性的，所以
"两次构建差 0.4 ns"这种跨构建差值不能当收益——0.4 ns 那个摆幅后来被限定成"只适用于跨变体的
两次构建之间"，而同一棵钟树重复试跑的噪声底实测 0.000（`report/40-optimization.md:84`，那一次为"同一棵钟树重复试跑"留下的读数表与三条读法，件 `build/evidence/r105_ab_rolls.txt`）。

**顺序就是这张表推出来的**：

1. 能在快车道上判的事，不要花钱走全流程。约束类、物理类、`phys_opt` 类都在这一档。
2. 必须改网表的事，先在快车道上把"归属"想清楚再花那 20 分钟：改完之后要靠一条差分或一份
   名册判住，判不住的这一刀不排期。
3. 判据本身的形状（报告哪一列是什么、这条命令存在吗）花 40 秒实测，不猜。
4. 台架那一档只在网表真的动了之后付；纯约束/纯物理的对照不配台架。

---

## 2. A 约束面：改的是"检查什么"，不是"跑多快"

约束面的共性：它不改网表、不改放置，因此**几乎都能在快车道上判**。它改的是工具愿不愿意
检查某条路、以及检查时用多悲观的尺子。这一面的第一条纪律是：**读任何 slack 之前，先按名字
复查约束还在不在**——加 MMCM 或重新源化时钟之后，`set_clock_uncertainty`、`set_clock_groups`、
输入延迟可能不再命中任何时钟名而工具不报错（数据包 §3.3）。

### A1 `set_clock_uncertainty` 补齐 hold 带

- **它能改什么**：只改 hold 检查的悲观度。带值加多少，四个域的 WHS 读数就往下挪多少，网表和
  放置一个字不动。
- **代价**：时间上是快车道（7–9 分钟）；交付文档上所有 hold 数字会变难看——统一加严后有
  25,742 个 hold 端点报失败（`report/timing/uncertainty_hold_ab.md` §2）。
- **怎么判断它真的动了（机制证据）**：不能读时钟对象——这一族属性读不回来（`*UNCERT*` 属性为空、
  命令不返回对象列表，`report/timing/uncertainty_hold_ab.md` §1），只能读报告正文里那行
  `Clock Uncertainty:`：BEFORE 是 `eth_rxc` 0.800、其余三域**读不到该行**，AFTER 四域全 0.800
  （件 `build/evidence/r115_unc/summary_hold_after.txt`，探针 `build/tcl/probe_uncertainty_uniform.tcl`）。
  探针另有一条硬闸：三个目标没全设上就 `exit 4`，否则差分没意义。
- **怎么判断它有没有用（结果证据）**：这条不"用"来判，它用"对得上账"来判——量出的 WHS
  −0.747 与 `0.053 − 0.800` 逐位对上（`report/timing/uncertainty_hold_ab.md` §2，0.053 取自
  `report/timing/roster_baseline.tsv` 的 hold 列）。对上了就说明这条带是纯尺子偏移，不是新的物理问题。
- **本项目在这条上量到了什么**：现行工程只有 `src/constraints/rk_zynq7020.xdc:50` 这一条
  `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`——四个受检域里只写了这一只钟，于是
  **四个域的 WHS 互相不可比**：名册 hold 列里 0.052 是"垫了 0.800 之后"的数，0.053 / 0.059 / 0.222
  是"没垫"的数。统一加带那一滚实测 WHS −0.747、失败端点 25,742 ⇒ **两把尺子并存是事实**，
  文档念明比假装可比更接近真相。这一条没写进工程，因为它是揭示债（读数只会变小）而不是变快，
  而且它必须和输入窗那笔债分开跑：RGMII 真窗 → hold −2.885、统一悲观带 → hold −0.747，
  两个数来自不同的检查对象，**永不相减**（`report/timing/uncertainty_hold_ab.md` §3）。

### A2 `set_clock_groups`

- **它能改什么**：决定哪些跨域路被分析。声明成异步的组之间根本不做 setup/hold 检查，
  所以 `build/timing_summary.rpt` 的 Inter Clock Table 只剩两行（`clkout0_1 ↔ sys_clk`），
  这正是 `src/constraints/clock_groups_impl.xdc:28` 那条 `set_clock_groups -asynchronous` 的直接产物。
- **代价**：它同时是遮罩。组间不再被检查 ⇒ 跨域的正确性只剩结构背书。工具面还有一条实测的坑：
  把综合阶段还不存在的钟（PS7 IP 自己 create 的 `clk_fpga_0`）并进同一条命令，
  **整条命令空转**、连带把 `eth_rxc` / `sys_clk` 那几组一起废掉，现场只留一句 warning
  （`src/constraints/rk_zynq7020.xdc` 44–46 行那段注释；`src/constraints/clock_groups_impl.xdc` 单独成文、
  只在实现阶段挂上，挂载点 `build/tcl/build_system_axigpio.tcl:36`）。
- **机制证据**：`report_exceptions` 的行数与 Inter Clock Table 的行集合；命令空转的凭据是"两组一起消失"
  而不是"少一行"。
- **结果证据**：逐时钟名册——组内还剩下的路必须逐条读，不能因为头条变绿就念"跨域没问题"。
- **本项目**：两个约束文件切开的方案是**实测钉死的**。把它们合回去这一刀量过并判负
  （`report/timing/cut_ledger.tsv` 的 C6 行：status = `rejected(measured)`，理由一栏写的就是上面那条空转，
  代价记为"不适用——已被证伪"）。

### A3 输入/输出延迟窗（`set_input_delay` / `set_output_delay`）

- **它能改什么**：让 I/O 端点**第一次被检查**。这条不是提速刀，是"把 11 个未点名端口里的 5 个变成有数"
  （`report/timing/cut_ledger.tsv` C7 行的原文口径）。
- **代价**：挂窗即显形。±0.500 ns 那次：WHS 从 0.050 掉到 **−2.885**、THS **−14.344**，
  5 个失败 hold 端点全在 `u_iddr_rx_ctl/D`，而那条路是 2 级逻辑、route **0.000 %**（数据包 §3.3）
  ⇒ 当场退回候选件。
- **机制证据**：`check_timing -verbose` 里未点名端口归零（件 `build/check_timing_verbose.rpt`）、
  路径报告出现 `Input Delay:` 行、`report_exceptions` 有对应条目。
- **结果证据**：该域 hold 的逐格读数 + I/O 覆盖率台账（`build/check_io_timing_coverage.py`）。
- **本项目**：候选件在盘上但**没有被 `add_files`**（`src/constraints/r114_io_async.xdc`、
  `src/constraints/r115_io_window_candidate.xdc`；生效集只由 `build/tcl/build_system_axigpio.tcl:31,36` 那两行
  和两个环境门控 `:58`、`:76` 决定）。于是收口 I/O 那 5 个端点回到"没检查"状态——这是欠账，
  **未检查不等于满足**（`data/metrics.csv:6` 的 H5 口径）。输出侧 TMDS 四组仍是 BARE，量过并拒绝；
  `build/check_io_timing_coverage.py` 上还有 4 个 BARE 输出端口（`report/timing/eth_rxc_partition_options.md` §8 末段）。
  真正关掉这颗雷的不是窗，是把 IDELAY 抽头定到眼心：在已布线的 DCP 上扫 `IDELAY_VALUE` 0…31
  （`set_property IDELAY_VALUE` 在 DCP 上有效 ⇒ **整条扫描不花构建**），量出 hold 每档 **+63 ps**、
  setup 每档 **−92 ps** 两条实测直线，交点 **τ = 31.1** ⇒ 取整 31，比出货值 26 抬 +0.315 ns
  （数据包 §3.3；件 `build/evidence/r115_window/probe3_console.txt`，扫描脚本 `build/clock_io_delay_scan.py`；
  落点 `src/rtl/top/system_top.v:172` 的 `.IDELAY_VALUE(31)`）。
  同一次扫描还给出一条"无解证明"：带发布窗后 hold 要求 τ ≥ 44.8、setup 要求 τ ≤ 21.8，而器件合法 τ
  只有 0…31 ⇒ 两个集合不相交；去掉与窗双重计的那 0.800 ns 带也只是把下界挪到 32.1，仍不相交。
  根因读数：两只钟的角间差 **3.411 ns**（hold 慢角 DCD 5.008 / setup 快角 1.597）而数据窗口只有
  **0.467 ns**。结论范围**只支持"当前结构下无解"**，不支持"换短钟也关不掉"（BUFIO 快角 DCD 未实测）。

### A4 `set_false_path`

- **它能改什么**：把一条路整条移出分析，比时钟组更粗暴——组还讲"这两只钟异步"，false path 只讲
  "这条路我不看"。
- **代价**：关掉检查等于关掉信息。用在真同步器上之后，那一路的时序从此无从谈起。
- **机制证据**：`report_exceptions` 出现对应条目、被豁免的路从名册里消失（注意本机
  **没有** `get_false_paths`，只有 `report_exceptions`，`report/timing/a1_sources.md:28`）。
- **结果证据**：Design Summary 的总端点计数变化 + 该路的归属是否真的由结构（握手/格雷码/单口）保证。
- **本项目**：现行 6 条执行行在 `src/constraints/rk_zynq7020.xdc`（非注释行实测 6 条）。其中一条改过方向：
  `eth_rst_n` 是输出（`src/rtl/top/system_top.v:42` 声明、`:112` 由上电计数驱动），原先写成 `set_false_path -from [get_ports eth_rst_n]`
  打不中，只能作 `-to` 的终点——这正是"约束写错了、工具不报错"的一类。口径上，同步器这类路
  **不该完全 false path**，应给 `set_max_delay -datapath_only`（`src/constraints/r114_io_async.xdc:50` 那段引 UG949）。

### A5 `set_multicycle_path`

- **它能改什么**：把采样沿假设从"下一拍"改成"后 N 拍"，Requirement 行按 N×周期出现。
- **代价**：这是六条里唯一一条**改了读数的同时也改了行为语义**的：设计本来单拍采却按多拍约束，
  时序变绿而功能变坏，所以它必须有一条能红的台架判据背书，不能只看报告。
- **机制证据**：路径报告的 `Requirement:` 行变成 N×周期、`Setup (Max at ...)` 的时钟沿标注跟着变。
- **结果证据**：该域 WNS 变化 + 整屏台架不新增红。
- **本项目**：**一次都没上过**——全仓 `.xdc` 与 `.tcl` 里 grep 不到 `set_multicycle_path`。
  不上的理由不是没想到，是这一族路在本项目里走的是结构而不是约束：250 MHz 那一域
  （`clkout1_1`，TMDS 串行化 OSERDESE2）本来就**不纳检**（数据包 §1 表格那一格），
  给它配多拍约束不会新增任何被检查的东西。

### A6 `set_max_delay -datapath_only`（异步组外的跨域路）

- **它能改什么**：给组外那条跨域路一个**只比数据段**的上界：路仍被分析，但不吃完整周期，
  于是"必须小于 skew"这类真实要求第一次变得可检查。
- **代价**：读数会新增——本来在任何尺子里都不出现的路会进名册，头条可能变难看。这是揭示债。
- **机制证据**：该路出现在报告里，`Requirement:` 等于写的 max_delay 值、起点终点分属那两个钟。
- **结果证据**：实测数据段延迟与该上界的差（余量）。
- **本项目**：**属欠账**（数据包 §4）。四条路已经写好但在候选件里：
  `src/constraints/r114_io_async.xdc:57,59,61,63`（eth_rxc↔clk_fpga_0、clk_fpga_0↔eth_rxc、
  clk_fpga_0↔clkout0_1、clkout0_1↔clk_fpga_0）。现状是 `set_clock_groups` 把三组钟两两排除，
  这四条跨域路在任何尺子里都不出现，跨域余量**全靠布线碰运气**（该文件 48–53 行的原话）。

---

## 3. B 结构面（改 RTL）：唯一真正改速度的那一面

结构面的共性：**改网表 ⇒ 快车道不适用**，每一刀都要付一次 20 分钟构建 +（要采纳的话）一轮约
两小时的台架。因此这一面的排他纪律最硬：这一刀必须能被**同一条锥的身份**归属，
且别的域不许变差（数据包 §3.5 的 rule 35）。

### B1 插寄存器摊拍（把锥切到两拍）

- **它能改什么**：Logic Levels 下降、该域 slack 上升；副作用是"最差格的归属"可能换到另一族。
- **代价**：+FF（有时 +LUT）；一整轮构建 + 台架。
- **机制证据**：同一条路的 Logic Levels 与起止点锥身份（尺子是 `build/tcl/crit_path.tcl` 与
  `build/tcl/probe_cone_slack.tcl` 那两把，同一口径复跑）。
- **结果证据**：逐时钟名册八格（四域 × setup/hold），要求"本域这条锥真的动了 + 其余域不变差"。
- **本项目量到了什么**：两条正例一条负例。
  正例：OSD 读侧那条 **23 级 / +0.384 ns** 的锥，修法就是在读侧插一级寄存器
  （`src/rtl/video/osd_overlay.v:501-503` 的 `ch_r`；数据包 §3.1）。同一个域、同一把尺子的前后读数：
  **1.130 ns / 23 级 / route 77.5 % → 4.094 ns / 21 级 / 62.8 %**，相对余量 **5.65 % → 20.5 %**，
  代价 **+2 LUT / −6 FF**（数据包 §3.5；−6 FF 那一格另见 `data/metrics.csv:9` 的寄存器行）。
  这里念的是**相对余量**，不是 ns 绝对差——绝对差不算收益也不算损失。
  第二条正例：双线性插值读口调度（级 4/5 那一级，数据包 §3.1），采纳条件同样写的"别的域不许变差"。
  负例：`eth_rxc` 那只校验和锥摊到每拍一项，判负——本族 0.739 → 0.691，而 `clk_fpga_0` 掉 0.123、
  `sys_clk` 14.876 → 14.068（`report/timing/eth_rxc_partition_options.md` §8）。

### B2 把长组合逻辑按级拆开（不加拍，重排级）

- **它能改什么**：锥的深度与形状；理想情况下级数降、slack 升且不新增寄存器。
- **代价**：只改 RTL 的写法，资源可能涨可能跌；仍然要一整轮构建才能判。
- **机制证据**：Logic Levels 逐格变化 + 锥起止点身份不变（换了起点就是另一条路，不能算这条的证据）。
- **结果证据**：名册差分 + 资源归属件。
- **本项目**：`icmp_tx` 的 32 位 IP 校验和拆成"两拍各 5 项"这一刀**只做过差分预验**，没花构建
  （`report/timing/cut_ledger.tsv` 的 C10 行，status 记 `measured-none`，机制证据那一栏把 12 档分布写死了：
  0.739 / 0.873 / 0.961 全出同一只 `ip_head_reg[4][16]`）。反向教训更值钱：**编译期常量抽出发一拍**
  这一刀判负，机制是常量并进同一拍使加法树**变深**，端点只从 4835 减到 4819
  （`report/timing/eth_rxc_partition_options.md` §8）。拆级不等于变浅，要读级数不读意图。

### B3 寄存器复制 / 使能独热化

- **它能改什么**：降一条使能的扇出、缩短它的分发段。
- **代价**：LUT/FF；归属难做——扁平汇总报告给不出逐层数。
- **机制证据**：`report_high_fanout_nets` 复读那根网还在不在。这一族在本项目量到过抓手达成：
  `fo=316` 那根网在该批报告里不存在、`rows_hit*/CE` 作最差终点出现 0 次（`report/40-optimization.md:89`）。
- **结果证据**：名册差分 + **资源归属**：这一刀的 LUT 变化必须能归到这一刀。
- **本项目量到了什么**：行覆盖使能独热化（`src/rtl/eth/frame_reasm.v:154-159` 的 `bank_one[*]` 分支）
  量到 **LUT −243**，但按模块归属只有 **−66** 能记在这一刀名下（OOC 单独综合给的就是 −66 那一小块，
  件 `build/evidence/r110_attrib.txt`；`data/metrics.csv:8` 的 LUT 行把这句原样写着）。
  **其余 177 没有归属 ⇒ 不念成收益**。另一次针对 `fo=316` 广播使能的刀**没真降**
  （`report_high_fanout_nets` 复读过）——抓手判据没达成就不算做过。

### B4 减少扇出广播（工具面：这一版只有三把尺子）

- **它能改什么**：一条驱动几百根引脚的广播网换成多根复制驱动，分发段缩短。
- **代价**：+FF/+LUT；复制会把 hold 挤薄（本项目量到过，见下）。
- **机制证据**：**先看工具面**——这一版 Vivado **没有 `set_max_fanout`**，`help set_max_fanout` 回
  `No topics matched`；`report_design_analysis` **没有 `-fanout` 模式**（实测可用的是
  `-complexity -congestion -timing -routes -logic_level_distribution -routed_vs_estimated -qor_summary`，
  且**是 `-routes` 不是 `-routing`**，`report/timing/a1_sources.md:27-28`）。名字是凭旧记忆写的 ⇒ 差点
  交出一个假结论（`report/log/issues.md` 里那两条工具账：一条写给单变量对照准备的 `set_max_fanout` 在本工具里根本没有、`help` 回 `No topics matched`，另一条写 `report_design_analysis -fanout -limit 12 -interval 4` 什么都没输出 ⇒ 差分判红）。所以扇出只能用 `report_high_fanout_nets` 读。
  `phys_opt_design -force_replication_on_nets` 的机制证据是网表里出现 `*_replica`：件
  `build/evidence/r117_repl3/b_console.txt` 的 `R3_REPLICA_CELLS` 行，闭合等式是网引脚 239→1、
  10 颗 replica、端点 15721→15731（`report/timing/README.md:93`）。
- **结果证据**：**名册差分判它**，不是机制证据。机制动了但差分判红 ⇒ 不采纳。
- **本项目量到了什么**：两次都判负。
  第一次（隔离试跑）：目标族 0.445 → **0.901（+0.456）**，`REPLICA_CELLS` 0→**296**，代价 +31 LUT，
  但 `eth_rxc` hold 0.050 → **0.035**（相对余量 0.62 % → 0.44 %，**−29.0 %**）⇒ `verdict=DECLINE`
  （`report/40-optimization.md:123`，件 `build/evidence/r114_mf/verdict.txt`）。
  买到的那 +0.456 与被拿走的东西落在**同一个域**，而那个域的 hold 已被证明没有可信余量。
  第二次（官方构建）：快车道单变量滚量到局部赢 **+0.033 / +0.187 / +0.298**、代价 +10 FF，
  正式构建里 `clk_fpga_0` 1.850→2.104 涨，而 `clkout0_1` 3.630→3.353、`eth_rxc` 0.739→0.615、
  `sys_clk` 14.876→14.815 三格各跌 ⇒ 不采纳（件 `build/r117_verdict_declined.txt`；
  钩子 `build/tcl/r117_post_place_hook.tcl` 留在盘上但**不挂、不进构建**）。

### B5 `ASYNC_REG`

- **它能改什么**：**放置指令，不是速度指令**——它让同步链的几颗 FF 被放在一起，逻辑功能与时序预算
  都不承诺变化。
- **代价**：资源逐字中性时才算免费；不中性时要单独算账。
- **机制证据**：网表里带该属性的 FF 计数：0 → **56 颗**（`src/rtl/eth/dc_fifo.v:27` 那四颗灰码捕获
  寄存器为起点；`report/40-optimization.md:92`）。
- **结果证据**：名册差分 + 资源中性证明。本项目的读数是：同一次构建 WNS 0.445 → **0.739**
  且**最差换族**（变成 `icmp_tx` 的校验和锥）、资源逐字中性 ⇒ **这个 WNS 变化不记成收益**
  （数据包 §3.1；`report/40-optimization.md:92` 把收益记给"结构账变干净"而不是 slack）。
  另有一条替代指标被证伪：`report_methodology` 的 TIMING-10（Missing property on synchronizer，
  `build/methodology.rpt:35`）**一条没少** ⇒ 那个计数不能当属性落地与否的凭据。

### B6 LUTRAM / BRAM 与 FIFO 载体选择

- **它能改什么**：载体决定谁吃资源，也决定哪一类 methodology 计数在涨，进而改变放置密度与
  该域的关键路径归属。一条 512×100 bit 的存储用触发器实现就是约 5.1 万个 FDRE。
- **代价**：换载体是把压力从一个资源池挪到另一个池，可能顶到另一个门禁。
- **机制证据**：`report_utilization` 的载体行 + 逐层件（`build/util_hier_probe.rpt`）；
  以及 methodology 那两行的计数（SYNTH-5 "Mapped onto distributed RAM because of timing constraints" 336、
  SYNTH-6 "Timing of a RAM block might be sub-optimal" 98，`build/methodology.rpt:32-33`）。
- **结果证据**：该域 slack 与该域名册档位的归属；资源侧要有一条"这个载体是承重的"读数。
- **本项目量到了什么**：打包 FIFO 从触发器改 LUTRAM，Slice Registers **54588 → 9593**
  （`report/log/changelog_v7.md:65`；约 5.1 万个来自那一只 512×100 bit 存储，同文件 `:35`），
  释放约 5 万 FDRE——改之前 DRC 直接报 `FDRE requires 176092, only 107000 compatible sites`
  （`report/log/changelog_v6.md:83-84`，即这条路根本不是"优化"而是"能不能落地"）。
  代价：BRAM 一度顶到 **138.5 / 140 = 98.93 %**（`report/log/changelog_v6.md:191`、
  `report/log/changelog_v7.md:20` 那一行的门禁结论是"不合格"），回落到 90.5 / 140 = 64.64 %
  （`report/log/changelog_v7.md:151`），现行版 **95.5 / 140 = 68.21 %**（`data/metrics.csv:10`）。
  另一笔后续账：打包器 FIFO 在线速连灌下峰值 **512/512 填满** ⇒ 深度降不得，那 400 个 LUT 换不到东西
  （`report/optimization_log.md` 里那条给打包器补 `sv_peak` 峰值探针的记录）。载体选择到此是**资源结论不是速度结论**，
  这一点要念明。

---

## 4. C 物理面：改的是"摆在哪"，不是"怎么连"

### C1 Pblock / 区域约束

- **它能改什么**：把一组单元圈进指定区域，缩短它们之间的分发段。
- **代价**：圈住 = 以后每次改动都少一块可摆放的地；而且**块本身可能不成立**——进位链被切成
  半内半外时工具直接拒。落地要一次正式构建（`report/timing/score.md:65` 给的成本档是 D1＝"实现阶段 XDC，增量构建 ≈ 21 min"）。
- **机制证据**：两端单元坐标真的进了块（`report_timing` 的 Location 列、`PB_CONTAIN` 读数）。
  语法面有两条实测：7-series 的范围**必须写 `SLICE_XnYm`**，UltraScale 的 `CLBLM_*` 会被拒
  （`ERROR: [Vivado 12-28489] pblock resize has invalid range CLBLM_L_X40Y20:CLBLM_R_X66Y52`，
  `report/log/issues.md:11338`）；`get_property RANGE` 读回来是**空的**（同一类"假拒绝挡掉正当实验"，
  `report/log/issues.md:12325`）⇒ 不能拿它判"块没生效"。
- **结果证据**：同尺复跑看该族 slack 与 route 占比，并且别的域不变差；WNS 绝对差不作采纳依据。
- **本项目量到了什么**：`SLICE_X40Y20:SLICE_X66Y52` 那块被工具拒绝——`Place 30-439`（进位链半内半外），
  落点下限实测 `PB_CONTAIN total=1716 inside=1461`（件 `build/evidence/r113_roll_ABC_verdict.txt`，
  `report/40-optimization.md:119`）。三滚的读数是：A 滚（无块、无 directive）逐位复现正式构建 ⇒ 确定解；
  B 滚（加那块）REFUSE、没量到；C 滚（`place_design -directive Explore`）与 A 一格不差。
  ⇒ **结论只能念"没做成一次对照"**，不能当一条独立负结果（`report/timing/gates_g1_g12.md` 的 G11 口径）；
  要修得把共享 carry chain 的 `u_eth/u_rx_mac` 一起收进去再滚一次。
  另一次更早的 Pblock 尝试（圈 `u_cdc` 的 9 块 BRAM）判负的理由不同：目标族那时已不在最差名单
  ⇒ **没有可归属的收益对象**，而 `eth_rxc` 的 +0.516 → +0.363 落在摆幅内，既不称好也不称坏，
  代价还有"新最差路径就贴着被圈的区"（`report/40-optimization.md:113`）。

### C2 高扇出网络与放置拥挤：route % 作为主导项的判读法

- **它能改什么**：判读法本身不改设计，它决定**下一步动 A/B/C 哪一面**。规则：一条路的
  Logic Levels 很小而 route 占比很高 ⇒ 逻辑刀的收益上限低，能动的是复制/摆放/疏解。
- **代价**：40 秒到 8 分钟（只读探针 + 快车道预验），不花构建——这是这一条最划算的地方。
- **机制证据**：`report_design_analysis -congestion`（实测存在该模式）、`report_high_fanout_nets`、
  档位表里每行的 `levels` 与 `route_pct` 两列（`build/evidence/r124_tiers_ladder.txt`）。
  route_pct 的形状要先实测：`Data Path Delay: 3.498ns (logic 0.655ns (18.725%) route 2.843ns (81.275%))`
  ——**百分比在括号里**，第一版解析写成不带括号的样子，于是每一行名册的 `route_pct` 都是空的
  （`build/tcl/probe_timing_roster.tcl` 头部那段 MEASURED shape 注释）。
- **结果证据**：把某族整族搬走之后，该域**接棒者**的 slack——它才是这一面能买到的上限。
- **本项目量到了什么**：两份读数是这一判读法的正面教材。
  `clk_fpga_0` 那 1.850 ns：前 12 档**全部**同起点 `u_pl/u_arb/owner_eth_reg/C`，终点是帧缓冲 BRAM 的
  `WEA`/`ADDRARDADDR` 脚，逻辑只有 1–4 级、布线占 **88.8–93.6 %** ⇒ 这个域没有"逻辑锥"可拆，
  能动的是那只高扇出旗标的复制/摆放（`report/timing/eth_rxc_partition_options.md` §7）。
  另一格同型：`u_pl/u_bilin/u_fb` 那条最差路 1 级逻辑 / 7.060 ns 布线（**93.6 %**），WNS 1.976，
  是四域里唯一"明知未到极限"的（`report/timing/score.md:65`）。
  `eth_rxc` 第 4–12 档全是 `u_eth/u_rx_par/p_eof_reg/C → u_eth/u_reasm/rows_hit_reg[*]/CE`，
  4 级、布线 **85.1–85.2 %**（件 `build/evidence/r124_tiers_ladder.txt`）⇒ 使能广播那一族是物理侧的靶，
  不是拆锥那一类。更早的一版同型读数：六条最窄路径里 4 条是 0–1 级逻辑、route 65–94 %
  ⇒ 当时就判"瓶颈是布线/拥塞不是逻辑深度"（`report/40-optimization.md:81`）。

---

## 5. D 工具策略面：让工具自己再压一档

### D1 实现策略 / directive 扫描

- **它能改什么**：不改输入，换工具内部的布局/布线努力档位。
- **代价**：一滚 7–9 分钟（快车道）或 20 分钟（正式）；真正的代价是**多变量**——一次扫两档会把
  同轮别的单变量性打掉（`report/timing/cut_ledger.tsv` 的 C5 行把"策略/directive 扫描"标为
  `excluded(until C1 measured)`，理由一栏写的就是这句话）。
- **机制证据（"策略被应用了"的凭据）**：构建日志里 `BUILD_STRATEGY` 念出请求的那一档，
  **并且两份位流 md5 互不相同、也不同于正式件**（`report/perf_report.md:437`）。没有这一条，
  读数就可能是"拿默认流程冒充扫描结果"。
- **结果证据**：名册差分 + 摆幅判据：差值要超出跨构建摆幅才不是噪声里挑好看的。
- **本项目量到了什么**：两档都量过、**两档都不采纳** ⇒ "靠工具再压时序"这一类问题关闭
  （`report/optimization_log.md:838-839`、`report/perf_report.md:437`）：
  `Performance_NetDelay_high` WNS **+0.013**，比基线低 0.54 ns，而实测摆幅 0.4 ns ⇒ 超出摆幅，
  这句不是"噪声里挑好看的"，是方向不利；`Performance_WLBlockPlacementFanoutOpt` 与基线**一格不差**
  （位流却不同）⇒ 按 rule 35 只念"没达门槛"，不念"打平"。
  另一格同型负结果：`place_design -directive Explore` 那一滚与不滚**一格不差**
  （件 `build/evidence/r113_roll_ABC_verdict.txt` 的 C 行）。

### D2 `phys_opt` 单独跑

- **它能改什么**：在已布局的网表上做复制/搬迁，不动 RTL。
- **代价**：+FF/+LUT；快车道这一档的报告清单若不显式补 `report_methodology`，那一格永远是未测。
- **机制证据**：`*_replica` 单元与 `REPLICA_CELLS` 计数（见 B4）。这条刀在本项目**确实动了机制**。
- **结果证据**：名册差分；机制证据不能替代它——本项目两次都是机制动了、差分判红。
- **本项目量到了什么**：见 B4 的两条负结果。还有一条方法账：快车道的滚里
  `report_methodology` 那一行**没补** ⇒ 判定表 G4 那一格写的是"未测（不许念成绿）"
  （`report/timing/gates_g1_g12.md:13`）。补了的两列是 `check_timing -verbose` 与
  `report_design_analysis -logic_level_distribution`（`report/log/issues.md` 同段）。

### D3 retiming

- **它能改什么**：把寄存器在组合图里前移/后移，重分布各级深度。
- **代价**：它**跨面**——动的是网表寄存器位置，于是 B 面那条"归属到某条锥"的判据失效；
  同一份网表被重排后，名册里"这条路的起止点身份"可能已经不是原来那条。
- **机制证据**：需要一条"该锥确实被搬过"的网表级证据（寄存器实例名/位置），而不是只看 slack 变好。
- **结果证据**：逐域名册八格 + 归属不丢失。
- **本项目为什么没做**：全仓 `.tcl` / `.sh` / `.v` 里 grep 不到 `retime`。两个理由：①它落在
  "工具自动再压一档"这一格，而那一格已经被 D1 那两档策略的对照关掉；②本项目所有采纳都要求
  能归属到某条锥/某个域，retiming 恰好把归属打散——在没有任何一条差分能判住它之前，
  它连"付一轮构建"的资格都没有。**这条是"没做"，不是"试过不行"**，念法不同。

---

## 6. 优先级决策树：从"这一版时序红/紧"出发

```
红/紧（WNS < 0，或余量薄到不敢再动）
 │
 ├─① 约束还在不在？（40 秒～8 分钟，只读探针 + 报告正文）
 │    按名字复查：set_clock_uncertainty / set_clock_groups / set_input_delay
 │    有没有因为加 MMCM、重新源化时钟而**不再命中任何对象**（工具不报错）。
 │    生效集只看 add_files 那几行：build/tcl/build_system_axigpio.tcl:31,36,58,76
 │    （ls src/constraints/ 给的是候选全集，不是生效集）。
 │    ①命中 ⇒ 先修覆盖面再谈其余；②没命中 ⇒ 进 ②。
 │    花：快车道内判得完，≈7–9 min；不花构建。
 │
 ├─② 最差路径属于谁、主导项是什么？（12 档阶梯，只读探针）
 │    尺子：build/evidence/r124_tiers_ladder.txt 那形状（每域 12 个不同端点 + levels + route_pct）。
 │      route_pct 高（85 % 以上）且 levels ≤ 4 ⇒ **物理/扇出**主导 ⇒ 走 ③-物理
 │      levels 高（20 级量级）且 route_pct 明显低于它 ⇒ **逻辑锥**主导 ⇒ 走 ③-结构
 │      该路起点/终点在 I/O 上 ⇒ 走 ③-约束（窗），但先看 A3 那条"这本来不是约束能关的"
 │    花：≈8 分钟；不花构建。**这一步是全篇最值钱的 8 分钟**。
 │
 ├─③ 按主导项选面，且先在快车道预验
 │    物理/扇出主导：C1（pblock 可行性 7–9 min）、B4（force_replication 7–9 min）、
 │                   D1（策略档 7–9 min 预验，采纳要正式 20 min）
 │    逻辑主导：B1/B2 —— **快车道不适用**，直接付 20 min 构建 + 约两小时台架
 │    约束主导：A1/A2/A6 快车道可判；A3 挂窗是"揭示债"不是收益，要有被拒的准备
 │    花：物理/约束 7–9 min；结构 20 min + 120 min 台架。
 │
 ├─④ 任何一刀都要能被**一条差分或名册**判住（事前登记判据，不许"改了再看报告"）
 │    尺子：build/roster_from_summary.sh（改前那一版从归档报告长回来）
 │          build/tcl/probe_timing_roster.tcl（改后那一版，带 levels/route_pct/dest）
 │          build/timing_roster_diff.sh（配对差分，口径不一致直接 REFUSE）
 │    事前门槛在脚本里：LOST_PCT=25（相对余量掉两成算代价）、FLOOR_PAIRS=8（四域×setup/hold）
 │    判不住 ⇒ 这一轮不排期。花：差分本身几秒钟，贵的还是那一轮构建。
 │
 └─⑤ 判负就退回，并把读数留在文档里
      回退要有凭据：用 md5 等式证明回退干净（BRAM 换 setup 那一刀的退刀就是这么闭的，
      见数据包 §3.4 与 `report/40-optimization.md:114`）。
      负结果一律写成"量到什么、因此判它不行"，不写成成功，也不删掉。
      花：回退 = 再一次构建（20 min）或一次 `git checkout --`（不改工程时后者就够）。
```

三个面的"该不该现在做"用同一句话筛：**这一刀的判据长什么样，写在开工之前**。
写不出判据的（比如 D3 retiming），就登记成"没做 + 为什么没做"，而不是先做了再找判据。

---

## 7. E 判据与流程面：把方法变成可复用的工程

这一面不改设计，改的是"结论能不能被别人复量"。每条仍然给五栏，只是"它能改什么"读作
"它能改变哪一类误判"。

### E1 逐时钟名册：12 档阶梯 + 参数纪律 + 反读 distinct

- **它能改变哪一类误判**："只看头条"。`build/tcl/crit_path.tcl` 把全设计最差那条排第一 ⇒
  每轮看到的都是同一个 `eth_rxc`，其余三个域涨是跌没人念（`build/tcl/probe_timing_roster.tcl` 头部）。
- **代价**：每域 12 档的探针跑在已布线 DCP 上，几分钟；参数写错会产出一份**看起来很长其实只有一档**的名册。
- **机制证据（参数纪律）**：`-nworst 1 -max_paths N`。用 `-nworst 12` 会把同一对 launch/capture 的
  多个边沿组合重复报满 12 行 ⇒ **12 行可能只算 1 档**（`report/log/issues.md:13868` 原话）。
  另一条被实测的形状：`-of_objects [get_clocks X]` 同时拒绝 `-delay_type` 与 `-max_paths`
  （`[Vivado 12-1365]`），可用形状是 `-from $c -to $c`（`build/tcl/probe_timing_roster.tcl` 头部注释）。
- **结果证据**：**从写出的文件里反读 distinct 计数并打印出来**（数据包 §3.5）。件
  `build/evidence/r124_tiers_ladder.txt` 的口径行就是这么写的：`-nworst 1 -max_paths 12` =
  每个端点只取最差一条、共取 12 个端点 ⇒ 每行是一个不同端点；另一次数的是端点重数
  （0.739×5 之类），两者不矛盾，但**不能混读**。
- **本项目量到了什么**：12 档表还带了一道准入门——重跑实现后四域 intra 读数与归档件**逐位相同**
  （0.739 / 1.850 / 14.876 / 3.630，端点 4835 / 15721 / 323 / 30179）⇒ 这份档位表才许当那一版的读数
  （件 `build/evidence/r124_tiers_ladder.txt` 头部；探针 `build/tcl/r124_tiers_probe.tcl`，
  在内存里把窗件 `remove_files` 摘掉、不 save_project）。

### E2 名册必须同生成器配对，否则 REFUSE

- **它能改变哪一类误判**：混口径的差分（一边是 `report_timing_summary` 逐时钟表转出来的行，
  另一边是探针带 levels/route_pct 的行），差分会自洽地给出一个假的红或假的绿。
- **代价**：改前那一版的 routed dcp **每轮构建都被覆盖** ⇒ 必须用转换器从归档的
  `timing_summary.rpt` 把名册长回来，且转换出来的行 `levels/route_pct/dest` 一律 NA
  （缺就明说缺，不编，`build/roster_from_summary.sh` 头部）。
- **机制证据**：`build/timing_roster_diff.sh` 的 REFUSE 分支（两侧口径不一致直接拒，不产结论）；
  它自带 11 条对照，包括"两侧口径不一致要 REFUSE"。
- **结果证据**：配对成功的 (时钟,类型) 对数下限 `FLOOR_PAIRS=8`（四域 × setup/hold）；
  低于 8 对的差分不判。
- **本项目量到了什么**：这条尺子的两个边界都被写成自检：两侧都 `NOWRITE`（MMCM 反馈钟、
  辅助输出本来没有 endpoint）**不许当成丢读数**；A 有读数、B 变 `NOWRITE` **必须红**
  （`build/timing_roster_diff.sh` 自检第 9、10 条）。口径红线另有一句：
  NA 是"这一族没有同沿路径"，不是"我读不到"。

### E3 单变量 A/B

- **它能改变哪一类误判**：把"这轮一共改了三件事带来的差"归给其中一件。
- **代价**：一轮只带一刀 ⇒ 排期变长（本项目有过"一次构建带两刀"的取舍，代价原文写在
  `report/log/issues.md` 那段采纳取舍里：退那一刀要再付一整轮（≈2.5 h），而换回来的是**另一条路**的旧数）。
- **机制证据**：单变量性要**靠文件证明，不靠嘴说**——两份滚脚本的逐行 diff 由
  `report/log/issues.md` 那段工具账逐行描述，并且同段写明它在脚本被改过之后**重新生成**过一次
  ⇒ 引用这种 diff 件要看它自己的生成时间（该 diff 件今天不在盘上，能复量的只有下面那张三滚表）；
  滚脚本首行的 `VARS` 标签写明这一滚只换了哪个变量（件 `build/evidence/r113_roll_ABC_verdict.txt`
  的三行表头就是这个形状）。
- **结果证据**：名册差分逐格念"变好/变差/没量"（数据包 §3.5）。
- **本项目量到了什么**：C2（统一 hold 带）与 C1（复制广播网）**必须分开跑**这条写在台账里
  （`report/timing/cut_ledger.tsv` C2 行 risk 栏的原文就是"必须与 C1 分开跑"，并把单变量写成这条的理由）。
  还有一条由此推出的口径修正：同一输入重跑是确定的，所以"某族从 >1.174 变 0.445"
  不是掷骰子，而是**这两刀改了网表 ⇒ 放置确定地变 ⇒ 邻居那条路的布线跟着变长**的确定性间接代价
  （`report/log/issues.md` 里那段以"同一输入重跑是确定的"开头的更正）。

### E4 快车道当反事实

- **它能改变哪一类误判**："这个改动值不值 20 分钟"在花钱之前没法回答。
- **代价**：快车道的报告清单是按滚配好的，缺哪一列就永远未测（见 D2 的 methodology 那一格）；
  而且它**不能判任何改网表的刀**。
- **机制证据**：同一棵树的 DCP md5 钉住（`report/timing/baseline_index.md:11`）+
  一滚逐位复现正式名册（`report/timing/gates_g1_g12.md:35`）。
- **结果证据**：滚 A/滚 B 的名册差分；噪声底是 0.000（同树重复滚），所以差值非零即可读。
- **本项目量到了什么**：两个用法都有实例——正例是 τ 扫档（在已布线 DCP 上扫 0…31，
  整条扫描**不花构建**，量出两条直线与交点，数据包 §3.3）；反例是 C9 那把复制网：
  快车道量到局部赢 +0.033/+0.187/+0.298，**正式构建判负**（见 B4）⇒ 快车道的结论是
  "值不值得付那一轮"，不是"能不能采纳"。

### E5 WNS 绝对差不算收益也不算损失（要念相对余量）

- **它能改变哪一类误判**：跨构建拿 ns 差当成绩；也改变"把一个域改坏了而头条没动"这一类。
- **代价**：写法变啰——每个结论都要带周期、级数、route 占比与代价（LUT/FF）四件。
- **机制证据**：同一个域自己的关键路径锥真的动了（起止点身份 + levels）。
- **结果证据**：相对余量（slack/period）的前后对照，加上其余域逐格不变差；
  事先登记的代价门槛 `LOST_PCT=25`。
- **本项目量到了什么**：正面写法就是这条——OSD 读侧那一刀：`clkout0_1` 那条
  **1.130 ns / 23 级 / route 77.5 % → 4.094 ns / 21 级 / 62.8 %**，相对余量 **5.65 % → 20.5 %**，
  代价 **+2 LUT / −6 FF**（数据包 §3.5）。反面写法被明确禁止：同一次构建里全局 WNS
  0.721 → 0.605 只允许念"持有者换了"，不许念"变差了"（`report/40-optimization.md:88`）。
  `ASYNC_REG` 那一格（0.445→0.739）同样不记在它名下（见 B5）。

### E6 报告形状先实测再解析

- **它能改变哪一类误判**：解析器安静地返回空字段，于是"读不到"被念成结论。
- **代价**：一次没有 design 的 `help <cmd>` 批探测 ≈40 秒（数据包 §2）；一次形状实测是一小段
  只读探针（`build/tcl/probe_report_shape_pin.tcl` 就是为这件事留的）。
- **机制证据**：命令存在性名册——本机实测**没有** `set_max_fanout`、`report_methodology -rules`
  （只有 `-checks`）、`get_false_paths` / `get_clock_groups` / `get_timing_exceptions`
  （只有 `report_exceptions`）、`get_input_delays` / `get_output_delays`
  （`report/timing/a1_sources.md:28`）。
- **结果证据**：解析器自带 fixture（拿真实归档件钉真值 + 一支变异对照），
  `build/roster_from_summary.sh --self` 就是这个形状：既要能从真件里转出
  `eth_rxc` 0.445 / 0.050 / period 8.000，也要在删掉那一行时**只少这两行**（少更多=整份没读进去）。
- **本项目量到了什么**：三条实测形状进了代码注释——`Data Path Delay` 的百分比写在括号里（见 C2）；
  `report_route_status` 的**文件里没有 "successful" 这个词**，它是一张净计数表 ⇒ 判据改写成
  "路由错误 0 且 全布==可布 且 >0"（`report/timing/gates_g1_g12.md:14`）；
  以及 `build/timing_summary.rpt` 的 Design Summary 表头在第 149 行、逐时钟表在第 179 行起
  （这两行是本次打开该文件核对的，不是从文档抄的）⇒ 行号也要实测。

### E7 `report_methodology` 的计数只取 SUMMARY 表

- **它能改变哪一类误判**：整文件 `grep -o` 会把每类**多数一遍**（数据包 §3.5）。
- **代价**：读表比 grep 慢一点；换来的是可核对性。
- **机制证据**：SUMMARY 表那一页本身（`build/methodology.rpt:26` 的 `Checks found: 446`
  与 `:30-36` 的七行分类）。
- **结果证据**：**加总一致**：446 = 2+1+336+98+1+1+7（件 `build/evidence/r115_base/methodology.txt`，
  同一段引在 `report/timing/gates_g1_g12.md:13`）。加不上就是取错了范围。
- **本项目量到了什么**：现行版七类：DPIR-1 2、LUTAR-1 1、SYNTH-5 336、SYNTH-6 98、TIMING-9 1、
  TIMING-10 1、TIMING-18 7（`build/methodology.rpt:30-36`）。TIMING-18（Missing input or output delay）
  那 7 条就是 A3/A6 那两笔欠账在方法论报告里的影子。

### E8 判据也要有测试：检查全绿 ≠ 已验证

- **它能改变哪一类误判**：尺子坏掉之后所有结论一起失效，而门禁显示绿。
- **代价**：每把尺子要配 fixture + 变异对照；一条判据都不许靠空集通过（`data/metrics.csv:15` 原话）。
- **机制证据**：门禁件的头部声明与自检行（`build/gates.sh:196` 那句"条数以本文件 say 调用为准"；
  各检查脚本的 `--self` 分支）。
- **结果证据**：两跑逐字节一致；唯一那条红是**写明过的** `C5c`（屏顶帧头 6 行读到上一帧的几何，碎影），
  条数 141 = 该件里 `^PASS` 140 行 + `^FAIL` 1 行（`data/metrics.csv:15`；数据包 §3.5）。
- **本项目量到了什么**：一条被记在案的自我打脸：脚本头部就写着"数字全部来自 Vivado 报告本身，
  不重新跑构建"⇒ 门禁绿只证明"报告与文档一致"，不证明"设计又跑了一遍"（数据包 §3.5）。
  另一格同类账：D5/D6 两把（行号锚点、数字对账）此前一直只是手工跑，接进门禁第一次就抓到
  首页四格还是上一版的数（`data/metrics.csv:14` 那一行的括号内原文）。

---

## 8. 六条容易犯的错（全部是本项目的真实教训）

### 错一：拿跨构建的 WNS 差值当收益

同一棵树的快车道重跑曾**逐位复现**正式构建的读数（`report/timing/gates_g1_g12.md:35`），
噪声底 0.000；而 0.4 ns 那个"摆幅"被限定成**只适用于跨变体的两次构建之间**
（`report/40-optimization.md:84`，那一行还写明这条记录因此把口径改了说法）。
⇒ 两次不同构建的 ns 差，第一句该问的是"这两次是同一棵树吗"，不是"涨了多少"。
`ASYNC_REG` 那一格 0.445→0.739 之所以不记在它名下（数据包 §3.1），用的就是这条规矩：
同一次构建里最差格的**归属换了族**，锥没动。

### 错二：把 `ASYNC_REG` 当提速

它是**放置指令**（数据包 §3.1）。落地凭据是网表里带属性的 FF 0→56 颗，
不是 WNS 变了多少；资源逐字中性才算免费。反证同一条：`report_methodology` 的
TIMING-10 计数**一条没少**（`report/40-optimization.md:144`）⇒ 连"这类问题少了几条"都念不了。
把属性打上之后念"结构账变干净"是对的，念"时序被优化了"是错的。

### 错三：以为加约束能救结构问题

±0.500 ns 输入窗那一次：挂窗即 WHS 0.050 → **−2.885**、THS **−14.344**，5 个失败端点全在
`u_iddr_rx_ctl/D`，而那条路是 **2 级逻辑、route 0.000 %**（数据包 §3.3）——失败点在 I/O 采样本身，
不在逻辑深度。窗被退回候选件之后，真正的解法是量两条直线（hold +63 ps/档、setup −92 ps/档，
交点 τ=31.1）并给出**无解证明**（hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，合法 τ 只有 0…31，两集合不相交）。
⇒ 约束面能改"检查什么"，改不了"物理上够不够"；窗显形的那条红本来就不是靠约束能关的。

### 错四：只优化最差那一条而漏掉整族

`eth_rxc` 的前几档是**同一族**：第 1–3 档是同一只 `icmp_tx` 校验和锥（11 级、布线 58.4 %），
第 4–12 档全是 `p_eof_reg/C → rows_hit_reg[*]/CE`（4 级、85.1–85.2 %），件
`build/evidence/r124_tiers_ladder.txt`。⇒ 即便把最差那族整族搬走，本域会停在 1.017 ns，
上限只有 **+0.278 ns**（1.017 − 0.739，同文件与 `report/timing/cut_ledger.tsv` C10 行）。
实际那一刀（校验和摊拍）量到的是：本族 0.739 → 0.691、`clk_fpga_0` 掉 0.123、`sys_clk` 14.876 → 14.068
⇒ 判负（`report/timing/eth_rxc_partition_options.md` §8）。归因结论因此是**域划分**而不是"某个加法器"，
最差换成 `rows_hit` 的 CE 广播（route 87.3 %，数据包 §4）。只看头条那一条路会把结论下在错误的对象上。

### 错五：把上限念成探针的取样深度

归档件里只到 **4 档**（`build/evidence/r118_after.txt` 只有 4 条；"先前归档的档位只有 4 条"这句
写在 `report/timing/eth_rxc_partition_options.md` §7，原因栏点名的就是探针件
`build/tcl/r124_tiers_probe.tcl`）。`-max_paths 4` 的读数只能支持"前 4 档是这样"，
不能支持"这个域到极限了"——第 5 到第 12 档补齐之后才看到接棒者是谁（上面那 85.1–85.2 % 那族）。
同一条纪律的另一半是 `-nworst`：用 `-nworst 12` 会得到 12 行、可能只算 1 档（见 E1）。
⇒ 念"极限"之前先答两件事：**取了几档、这 12 行是几个不同端点**。

### 错六：空档名册与没被 `add_files` 的 xdc，把"读不到"念成"证明不可能"

两半都有件。半一：`ls src/constraints/` 给出的是**候选全集**，生效集只在
`build/tcl/build_system_axigpio.tcl` 的 `add_files` 那几行里（`:31`、`:36`，两个门控的 `:58`、`:76`）；
`r114_io_async.xdc` / `r115_io_window_candidate.xdc` / `r119b_hdmi_tp1_pinclk.xdc` 在盘上但没有任何
`add_files` ⇒ 那四条 `set_max_delay -datapath_only` 是"没上"，不是"上了没用"（欠账见 A6 与数据包 §4）。
半二：名册里的 `NOWRITE` / `NA` 有专门判法——两侧都 NOWRITE 不许当成丢读数，
一侧从有读数变 NOWRITE **必须红**（`build/timing_roster_diff.sh` 自检第 9、10 条）；
`Clock Uncertainty:` 读不到那一行是"从未带过带"而不是解析失败（`report/timing/uncertainty_hold_ab.md` §1
把这条单独证过一遍：同一次读取里报告存在、路径存在、就是没有那一行）。
⇒ "读不到"永远是**先问射程、再问结论**。

---

## 9. 一页速查：五个面 × 时间成本 × 判据

| 面 | 方法 | 花多久 | 机制证据（动了没） | 结果证据（有用没） | 本项目状态 |
| --- | --- | --- | --- | --- | --- |
| A | `set_clock_uncertainty` 补 hold 带 | 快车道 7–9 min | 报告 `Clock Uncertainty:` 行 | −0.747 = 0.053 − 0.800 | 量过未落地；四域 WHS 现不可比 |
| A | `set_clock_groups` | 快车道 7–9 min | `report_exceptions` / Inter Clock 行 | 组内路逐条读 | 两文件切分已定；"合回去"判负 |
| A | 输入/输出窗 | 快车道 7–9 min | `check_timing -verbose` 归零 | 该域 hold 逐格 | 退回候选件；真解是 τ=31 两条直线 |
| A | `set_false_path` | 秒级 | `report_exceptions` | 端点计数 | 6 条执行行；一条方向改过 |
| A | `set_multicycle_path` | 秒级 | `Requirement:` 变 N×周期 | 台架不新增红 | 一次没做（全仓 grep 不到） |
| A | `set_max_delay -datapath_only` | 快车道 7–9 min | 该路进报告 | 数据段 vs 上界余量 | 四条写在候选件里 ⇒ 欠账 |
| B | 插寄存器摊拍 | 构建 20 min + 台架 ≈2 h | 同一条锥 levels | 名册八格 | OSD 读侧 23→21 级已采纳；校验和摊拍判负 |
| B | 拆级/重排组合 | 构建 20 min | levels 逐格 | 名册八格 | 两拍各 5 项只做过预验；常量抽出判负（树变深） |
| B | 独热化使能 | 构建 20 min | `report_high_fanout_nets` 复读 | 名册 + 资源归属 | −243 里只有 −66 有归属 |
| B | 扇出复制（`phys_opt`） | 快车道 7–9 min（正式 20 min） | `*_replica` / `REPLICA_CELLS` | 名册差分 | 两次都判负（同一域被挤薄 / 赢 1 跌 4） |
| B | `ASYNC_REG` | 构建 20 min | 带属性 FF 0→56 | 名册 + 资源中性 | 采纳，收益记结构不记 slack |
| B | FIFO 载体（FF→LUTRAM） | 构建 20 min | 载体行 + SYNTH-5/6 | 该域 slack + 承重读数 | 54588→9593 FF；BRAM 98.93 %→68.21 % |
| C | Pblock / 区域 | 快车道预验 7–9 min；落地 ≈21 min | 单元坐标进块 / `PB_CONTAIN` | 族 slack + route % | 被 `Place 30-439` 拒 ⇒ "没做成一次对照" |
| C | route % 主导判读 | ≈8 min 只读 | levels + route_pct 两列 | 接棒者 slack | 12 档表在手；两格明确是物理靶 |
| D | 策略 / directive | 快车道 7–9 min | `BUILD_STRATEGY` + 位流 md5 | 名册差分 vs 0.4 ns 摆幅 | 两档都量过都不采纳 ⇒ 该类关闭 |
| D | `phys_opt` 单跑 | 快车道 7–9 min | `REPLICA_CELLS` | 名册差分 | 机制动、差分红 ⇒ 不采纳；methodology 格未测 |
| D | retiming | —— | 需网表级归属证据 | —— | 没做（该类被策略对照关掉 + 归属会打散） |
| E | 逐时钟名册 / 差分 / 单变量 / 快车道 / 相对余量 / 形状实测 / SUMMARY 计数 / 尺子自检 | 探针几分钟；尺子自检秒级 | 参数纪律 + fixture | distinct 计数、REFUSE、两跑一致 | 已成件：`build/roster_from_summary.sh`、`build/timing_roster_diff.sh`、`build/tcl/probe_timing_roster.tcl`、`build/tcl/r124_tiers_probe.tcl` |

> 收口一句：这套清单里**被采纳的少、被量过并否决的多**。这不是失败，是这一面本来就该这样收尾——
> 每条否决都留了"量到什么、因此判它不行"的读数（`report/timing/cut_ledger.tsv`、
> `report/40-optimization.md` 的 V 系列表、`build/r117_verdict_declined.txt`），
> 而欠账也照实记着（`report/timing/eth_rxc_partition_options.md` §8 末段与数据包 §4）。
> 下一篇把这里每条方法的"报告怎么读、探针怎么写"落到命令级。

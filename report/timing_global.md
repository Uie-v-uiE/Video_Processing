# 全局时序：按时钟域名册读余量，而不是追着最差那一条改

板上现在跑的是 r118，位流 `build/system.bit` 的 md5 前 12 位是 `cd04907e1369`；本文其余出现的 rNN 都是**产出那份读数时的构建编号**（第 112 版就写 r112），不是叙述用的轮次号。

改时序的判法只有一条：动一处要同时看其余时钟域的余量变化。第 2 节给的是**同一次构建里四个时钟域各自动了多少**，第 4 节是与网表无关但同样属于"时序"的**约束侧欠账**，第 6 节逐域回答"到没到物理极限"。

## 1. 方法（照官方文档的口径，不是自创的规矩）
1. **先看全设计，再看那条路**：`report_timing_summary` 的 Design Timing Summary + **Intra/Inter Clock Table**
   是主表；逐时钟 WNS/WHS/TNS/**失败端点数**与端点总数都要读。WNS 只说"最紧那一条"，
   它换了主语（换到另一个模块甚至另一个时钟）时，绝对差既不是收益也不是损失（本仓库的一条口径，编号 rule 35）。
2. **判"是不是布线/距离问题"看比例，不看感觉**：`Data Path Delay` 那行的 logic/route 百分比 + `Logic Levels`。
   route>80 %、级数≤4 的路，拆逻辑救不了；该动的是**扇出复制**、**控制集/寄存器复制**、**floorplan**（UG949 的 Timing Closure 章、
   Xilinx 官方文章 9410《Suggestions for high fanout signals》列的就是这几类手段与 `MAX_FANOUT`/`report_qor_suggestions` 这条路）。
   问"哪些网该复制"用 `report_high_fanout_nets`（本工具实测：`report_design_analysis` **没有** `-fanout` 模式，见第 5 节）。
   警告 扇出高不一定被工具自动复制（stackexchange 那一条就是"很高的扇出没被复制"），所以要显式给约束并**量结果**。
3. **让工具给建议，别只靠自己盯**：`report_qor_suggestions`（只读）+ 需要时 `source qor_suggestions.rpt` 到一次**隔离**构建里量收益。
4. **约束缺口会伪装成"时序没问题"**：`check_timing` 的 `no_input_delay` / `no_output_delay` 意味着那些端口被当成理想时刻，
   工具根本不优化它们（UG903/UG949 都是这个口径）；`report_methodology` 的 TIMING-9/10（CDC 未识别、同步器缺属性）
   与 `report_cdc` 是**功能性硅风险**的来源，比 WNS 少 0.1 ns 重要得多。
5. **每次改动之后必须交出名册差分**（第 5 节那套工具）：改前后各出一份
   `逐时钟 WNS/WHS + 每域最差 3 族的起点→终点/级数/route%/fo`，任何一条**变差**都要点名是谁，
   不许只念全局 WNS 那一个数。

## 2. r112 那一版的**全设计**读数（一次构建，四域同表）
件：`build/timing_summary.rpt`（Intra Clock Table）、`build/setup_paths.rpt`、`build/hold_paths.rpt`、
`build/r112_reasm_probe.txt`（族级）、`build/evidence/r113_roll_abc_verdict.txt`（物理侧三滚）。

| 时钟 | 周期 | WNS | 相对余量 | WHS | 端点数 | 最差那一格的形状 |
|---|---|---|---|---|---|---|
| `eth_rxc` 125 MHz | 8.000 | **0.445** | **5.56 %** ← 全局最紧 | **0.050** | 4835 | `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[12..15]/CE`，4 级，route **84.276 %**，中段 `rok4[51]_i_1_n_0` **fo=305** |
| `clk_fpga_0` 100 MHz | 10.000 | 1.135 | 11.35 % | 0.056 | 15721 | `u_arb/owner_eth_reg → u_bilin/u_fb/lo_reg_0_24/ADDRARDADDR[3]`，**1 级 LUT3**，route **93.875 %**（fo=269 网络 + BRAM 地址） |
| `clkout0_1` 50 MHz（像素） | 20.000 | **4.467** | 22.34 % | 0.059 | 30179 | `u_mode/mode_q_reg → u_pipe/u_gray/dout_reg[2]/D`，**18 级含 8×CARRY4 + LUTRAM**，route 67.2 % |
| `sys_clk` 50 MHz | 20.000 | 14.463 | 72.3 % | 0.133 | 323 | `u_ang/angle_reg[4] → angle_reg[6]/D`（角度 ±1° 的进位链，最宽的一档） |
| 跨域 `sys_clk↔clkout0_1` | — | 4.399 / 14.276 | — | 0.300 / 0.259 | 231 / 19 | 一条含 **DSP48E1** 的 15 级路（`angle → zmap/y_out`） |
| 脉冲宽度 | — | WPWS 最小 **0.264** | `clkout2`（IDELAYCTRL REFCLK 的 Max Period） | — | 12634 总 | 收包域那颗 5 ns 参考时钟的**上沿宽度**余量最小 |

**同一次构建里"其他地方"动了什么**：
`eth_rxc` 0.713 → **0.445**（−0.268），同一次构建里 `clkout0_1` 3.799 → **4.467**（+0.668）、`clk_fpga_0` 1.186 → 1.135（−0.051）、
`sys_clk` 15.157 → 14.463（−0.694）。全设计失败端点仍 **0**、`check_timing` 无 loops/no_clock。
⇒ 三次重跑实测证明：同一份 `opt.dcp` 重跑 place+route **逐位复现**（不是骰子），所以这几个数是**一次网表改动的确定性重排**，
**四域要一起念**——只念"全局 WNS 余量减小"或者只念"显示域余量增大"都是半句话。

### 2b. r113 对 r112 的名册差分（实测，`build/evidence/r113_roster_diff.txt`）
"全局"的说法就是这个：**八个 (域,类型) 对逐位相同**，不是单个 WNS 数。
```
clk_fpga_0 setup 1.135 -> 1.135   hold 0.056 -> 0.056
clkout0_1  setup 4.467 -> 4.467   hold 0.059 -> 0.059
eth_rxc    setup 0.445 -> 0.445   hold 0.050 -> 0.050
sys_clk    setup 14.463 -> 14.463 hold 0.133 -> 0.133
```
两端的来源是**不同**的：改前那侧由 `build/roster_from_summary.sh` 从归档的 r112 `timing_summary.rpt` 长回来，
改后那侧由 `build/tcl/probe_timing_roster.tcl` 直接问 r113 的 routed dcp（B 侧 slack 带着
`(required time - arrival time)` 后缀、还带级数/route%/终点，A 侧是纯数字 —— 形状不同，才不是把同一个文件读两遍）。
**为什么该相同**：#256 那次修复只改 FF 的 INIT 属性，不改网表结构（同一批 FDRE、同一些连接），
而这台工具的放置/布线是确定性的（#254 已实证：同一份 opt.dcp 重跑逐位复现正式构建的数字）⇒
时序一位不动，只有位流内容变了（`build/system.bit` md5 从 `897fa9d93956` 变成 `b94f4da6cdff`）。
所以 r113 的口径是：**功能修复，时序中性**——四个域、setup 与 hold 两边都是这个结论，不是只看头条。

差分六条里唯一未通过的是 `D6_fanout_inventory`（`fanout_rows=0`）。这条未通过的是检查工具本身，不是设计：
`report_design_analysis -fanout -limit 12 -interval 4` 在那个版本上什么都没写出来，而下游数到 0 行就判未通过 ——
这正是计数下限该有的样子（空产物不许伪装成"这一版没有高扇出"）。探针已改成最素的调用并把
`FANOUT_ERR` / 报告头 20 行念出来；下一次腾出 Vivado（顶层台架跑完之后）重问一次，D6 才真的有意义。

## 3. 下一次改动为什么不再切逻辑，以及"全局"怎么切
   工具自己那份**建议名册**也要念：`probe_timing_roster.tcl` 现在除了扇出，还跑
   `report_qor_suggestions -max_candidates 12` + `write_qor_suggestions`，把 `QORSUG|…` / `QORHINT|…` 落成行
   （UG949 的流程就是"先问工具，再逐条审"）。命令都包在 catch 里：这个版本没有它就明说 `QOR_ERR=`，
   而不是让探针死在半路。**下一次改动的候选顺序 = 工具建议名册 ∪ 扇出/放置抓手，再按域排代价**，
   而不是"哪条最疼改哪条"。
- `eth_rxc` 那条的 6.089 ns 走线里，第一跳 `p_eof`（**fo=8**）就吃 **2.141 ns**：起点 `SLICE_X57Y34`、终点整片 `rows_hit` 在 `X28~X31` ⇒ 距离。
  换实现指令（`place_design -directive Explore`）**一格不差**；Pblock 那块因进位链半内半外**没做成单变量**（1716 里 255 出块）。
- 所以候选只剩两类，都要按全局判据交账：
  ① **扇出复制（官方 9410 那条路）**：目标是 `rok4[51]_i_1_n_0` **fo=305** 与 `u_reasm/wr_en_reg_1` **fo=547** 这两根广播。
     警告 **杠杆的名字是量出来的，不是猜的**（2026-10-03 实测，`build/evidence/r113_help_fanout2_console.txt`）：
     `set_max_fanout` 在本工具里**不存在**（`help` 回 `ERROR: [Common 17-25] No topics matched`），
     `create_qor_suggestion`、`get_properties` 同样不存在（`build/evidence/r113_help_fanout3_console.txt`）。
     同一份 help 里真正写着的是 `phys_opt_design` 的三个旗标：
     `-fanout_opt`（"Do cell-duplication based optimization on high-fanout timing critical nets"）、
     `-force_replication_on_nets`（"Force replication optimization on nets"）、
     `-critical_cell_opt`（"Replicates cells on timing critical nets…"），
     而且 help 明说复制对象名字带 `_replica` ⇒ **"机制动没动"是数得出来的**（正对照必须能红）。
     A/B 因此定成：两滚都 `place_design → phys_opt_design → route_design`，
     **唯一变量**是 B 那滚的 phys_opt 多带 `-force_replication_on_nets {那些网}`
     （入口 `build/r114_replication_ab.sh`，这个检查脚本自带 3 条对照，`--self` 全部通过；
     `MAX_FANOUT` 属性那条路还没验（要开设计 `list_property`），所以现在**不许**写成"已按官方 MAX_FANOUT 做"）。
     它是**实现级**改动（不动 RTL），代价面是复制出来的 cell 会挤占别人 ⇒ 必须看 `report_utilization`、`report_route_status`
     与**其余三域**有没有变差（名册差分 D1..D6）；
  ② 修 Pblock 表达式（把共享进位链的 `u_eth/u_rx_mac` 一起收进来）再滚一次；只允许"加不加这块 Pblock"一个变量（#223）。
- 警告 明确不做：`#179`（icmp_rx 校验和，70.5 % route，量过收益上限低）、`#141`（BRAM 换 setup，量过之后未采纳）、
  `#105` 尾账那类"再插一级"——都是在已经 route 主导的锥上磨逻辑。

## 4. 约束侧欠账（这些也是"其他地方的时序"）
| 项 | 实读（`build/timing_summary.rpt` 的 check_timing / Methodology 两张表） | 含义与处置 |
|---|---|---|
| `no_input_delay` | **5 个输入端口 HIGH**（另有 2 个已被 false path 覆盖 MEDIUM） | 这 5 个口的到达时刻被当理想 ⇒ 工具不优化、也不报违例。要么给 `set_input_delay`（RGMII 那一路是 **同步采样**，`#57` 之后没有 IDELAY 采样窗可言，值要给得讲道理），要么写 `set_false_path -to` 并说明**为什么**是假路。不许留着当"未知" |
| `no_output_delay` | **6 个输出端口 HIGH**（+6 个 MEDIUM 有 false path） | 屏（TMDS）与 SDC/LED 那几路对外没有负载模型 ⇒ 现在报的"MET"不含这一段。要么给 50/60 MHz 像素时钟下的板级窗（先量再写），要么显式豁免并留理由 |
| ↑ 以上两条**现已点名**（`build/check_io_timing_coverage.py`，件 `build/evidence/r113_io_debt.txt`） | 输入侧源码数出 5 个引脚（`eth_rx_ctl` + `eth_rxd[3:0]`），报告念 5；输出侧被点名的裸端口是 **7 个**（= 12 个引脚）：`tmds_clk_p`、`tmds_clk_n`、`tmds_data_p[2:0]`、`tmds_data_n[2:0]`、`led[1:0]`、`eth_mdc`、`eth_mdio`，报告念 6 | 这就是"其他地方"。屏那一路现在报的 MET **不含芯片到面板那一段**；`led`/`eth_mdc`/`eth_mdio` 三组已按 §3.4(b) 写成带行号出处的豁免（`rk_zynq7020.xdc:10-11`、`system_top.v:117`、`system_top.v:116`），剩下的四个 BARE 输出端口名全是屏那一路。**这一行原来那段"源码端是引脚数、报告端是端口数，差值钉成常量 6"的解释是错的**——那是我自己造的量纲差（#251 同族）。读了 `check_timing -verbose` 那份件之后实情是：`checking no_input_delay (7)` = HIGH 点名 5 行 + MEDIUM 点名 2 行，`checking no_output_delay (12)` = HIGH 6 行 + MEDIUM 6 行 ⇒ 小标题与明细**同一个单位**（每个端口位算一个、各点一行），差的是**射程**：小标题数两个严重度，明细只给一个。判据因此换成两条能真对账的：`I7_verbose_selfreconcile`（每段 `There are N …` 必须等于它下面点名的行数，且小标题 = HIGH+MEDIUM 两段之和）与 `I10_names_vs_source`（工具那份 HIGH 名单 vs 我从 RTL+XDC 推出来的那份，输入侧集合相等、输出侧无幽灵名、我判 BARE 的每个引脚都被点名，差分对负端按实测口径除外）。真件两条都判绿，读数件 `build/evidence/1006_d3/io_debt_after_d3.txt`，检查脚本 `--self` 判 10 条 + 12 条对照全过。#259 的名字级那一半到此闭合，仍红的只有 `I3_output_covered bare_out_ports=4`，它由"TMDS 窗量过并被拒绝"这条决定（`report/timing/eth_rxc_partition_options.md` 第 6 节）|
| `TIMING-9` / `TIMING-10` | 1 / 1（r114 复测**仍是 1 / 1**，`Checks found` 仍 446，件 `build/evidence/r113_methodology_baseline.rpt` 对 `build/methodology.rpt`） | "Unknown CDC logic" 与 "Missing property on synchronizer"。**这一格的结论把原先的期望打掉了**：#262 那把 `ASYNC_REG` 确实上了网表（`u_cdc` 底下 84 颗灰码 FF 里 **0 → 56 颗**带属性，件 `build/evidence/r114_async_netlist_pre_console.txt` 与 `build/r114_async_netlist_console.txt`），可 TIMING-10 一条没少，而且它的正文是 `Related violations: <none>`——**不点名对象**。⇒ 不能拿这个计数当"属性上没上"的代理；剩下那 1 条要么指另一对同步器、要么要求源头那一对（`wgray_reg`/`rgray_reg` 也还没带属性），要新鲜 `report_cdc -details` 点名才能定（`build/cdc_details.rpt` 现在还是 9 月 25 日那一份，不能当本版凭据）。另记一句归因：缺属性（#262）与"这一域没复位"（#256）是**两笔不同的账**，原来这行把它们写成同族是含糊的 |
| `TIMING-18`（**此前漏在表外**） | **7** | 这就是 `report_methodology` 自己给 #259 那笔 I/O 欠账记的号（"Missing input or output delay"）。它是**第三个独立来源**：`check_timing` 念 5 输入 + 6 输出（HIGH），源码侧检查脚本念 2 个裸输入端口 / 7 个裸输出端口（= 5 + 12 个引脚），而 `report_methodology` 念 7 —— 三个数各是真的，**单位不一样**，谁也不许替谁解释。r114 的 `check_timing -verbose` 名单要一次把这三个数对到同一套名字上（#267/#259） |
| `TIMING-18` 的**明细**（第三个来源，能点名） | 工具自己念出 7 个引脚：输入 `eth_rx_ctl`、`eth_rxd[0..3]`；输出 `led[0]`、`led[1]`（件 `build/methodology.rpt`，检查脚本 `build/check_io_timing_coverage.py` 的 I8/I9，读数 `build/evidence/r113_io_debt.txt`） | 这个检查现在能做**名字级**对账：I8 判【源码展开的裸输入引脚集合 == methodology 点名的输入集合】⇒ **GREEN（五个名字逐一对上，不是计数撞对）**；I9 判【methodology 点名的输出引脚必须落在被判为 BARE 的输出里】⇒ GREEN。同时开放项从“差 6 位”变成**有名字的 10 个引脚**：`tmds_clk_p`、`tmds_clk_n`、`tmds_data_p[2:0]`、`tmds_data_n[2:0]`、`eth_mdc`、`eth_mdio`（8+1+1）—— methodology **没点名**它们 ⇒ r114 要问的不是“差几个”，而是“这 10 个落在哪个桶、为什么不在 TIMING-18 里”。这个检查自带 9 条对照（删一个点名 ⇒ I8 判未通过；塞幽灵名 ⇒ I9 判未通过；其余 7 条既存）实测 9/9 |
| 上面这张表**自己先闭合** | `Checks found: 446` = 2+1+336+98+1+1+7 | 念法：表的七行加起来必须等于报告自己念的 `Checks found`，对不上就是**漏抄了一类**。这条加进来是因为第一版数类目的时候用 `grep -o` 全文扫，把汇总表那一行本身也数进去了 ⇒ 每类都多 1（337/99/2/2/3/2/8），差点按错数改文档；**报告的形状与计数都要量，同一个错法在两天里出现三次**（#263/#264/#267） |
| `DPIR-1` / `LUTAR-1` | 2 / 1 | 异步驱动 / LUT 驱动异步复位：都是"复位网真不真的可靠"的问题，与 #256 同族 |
| `SYNTH-5` / `SYNTH-6` | **336 / 98** | "因为时序约束才映射成分布式 RAM"——这一类此前没有单独跟进：它说明**BRAM/LUTRAM 的选型在被约束牵着走**（本仓库 BRAM 已经 95.5/140 tile，LUTRAM 4044 个），要单独量一次，不能当噪声 |
| 自加不确定度 | **不对称**：全工程只有一行 `set_clock_uncertainty -hold 0.800 [get_clocks eth_rxc]`（`src/constraints/rk_zynq7020.xdc:50`），其余三域一条都没有 | ⇒ **名册里那四个 WHS 不是同一口径量出来的**：eth_rxc 的 0.050 已经扣掉自加的 0.800，而 clk_fpga_0 的 0.056 / clkout0_1 的 0.059 / sys_clk 的 0.133 **一分没扣**。所以"四域 hold 余量差不多"这句话是**约束口径造出来的假象**，不是设计的事实；纯算术先念一句：0.056−0.800、0.059−0.800、0.133−0.800 全为负。这不是"板子 hold 坏了"——是**没测过**。量它的检查脚本已落地：`build/uncertainty_uniform_ab.sh` + `build/tcl/probe_uncertainty_uniform.tcl`（只读开 routed dcp，同一 0.800 带给每个时钟，逐域念 before/after；判据 U1 逐时钟行数下限、U2 四域不许缺数、U3 带子真落上（applied≥1 且至少一域 after<before）、U4 设计级 setup 与归档 `timing_summary` 的 WNS 对齐（不同源）、U5 负数计数与点名一致、U6 eth_rxc 的 before 与归档 WHS 对齐——对不上就是读错了 dcp）。这个检查自带 `--self` **六条对照**（1 条通过 + 5 处各判未通过一条），第一次跑就把它自己的 `substr` 取偏一位照成"正例也判未通过"，改完才通过 ⇒ 见 #265。**真件还没跑**（要等台架与前面的实验腾出机器），所以这一行现在只到"口径不对称"这一句，不许写成"四域 hold 其实都违例" |

### 4b. r114 的补法（按端口分组，约束的**形式**与数字的**出处**都写死，不填估计值）
| 端口组 | 该给什么约束（形式） | 数字从哪里量/查（不许编） | 补完之后谁来判 |
|---|---|---|---|
| TMDS 六路输出（`tmds_clk_p/n`、`tmds_data_p/n[2:0]`） | 源同步输出：`set_output_delay -clock <输出时钟> -setup/-hold [get_ports {tmds_*}]`，时钟取**驱动这些数据的那颗**（像素时钟 / 其 5× 串化时钟），而不是 sys_clk | 面板端采样窗 = TMDS 接收端的 setup/hold；DVI/HDMI 源同步惯例是"数据沿对齐时钟沿、余量以 UI 计"，具体 ps 要查**这块面板/接收芯片的手册** + 本板走线等长实测（原理图与管脚表在 厂商随板资料（原理图与管脚表，ZYNQ7020 那套），交付包里没有它——本机路径不能当指路）。查不到就退一步：写 `set_max_delay -datapath_only`（限偏斜而不是定死窗），并把为什么这样写在 XDC 注释里 | `build/check_io_timing_coverage.py` 的 I3（不许有裸输出）+ I1/I2（对账仍要成立） |
| `led[1:0]` | 慢速推挽输出，不对外定时序 ⇒ `set_false_path -to [get_ports {led[*]}]` **并写明理由**（灯由人眼读，没有建立/保持窗） | 不需要数字，需要那句理由（写进 XDC 与本文，才算"显式豁免"） | 同上（FALSEPATH 那一档，且豁免表要带理由） |
| `eth_mdc` / `eth_mdio` | MDIO 是 bit-bang 管理口，与 GTXCLK/RXC 无关 ⇒ `set_false_path`（或按 2.5 MHz 上限给一对 `set_max_delay`），理由要写 | Realtek RTL8211F 数据手册的 MDIO 时序（本板 PHY 就是 RTL8211F，见 `report/host_guide.md` 第 14 行） | 同上 |
| RGMII 收口 5 个裸输入（`eth_rx_ctl`、`eth_rxd[3:0]`） | 这一路**已经**是真物理事件，别再拖：`set_input_delay -clock eth_rxc -min/-max` 按 PHY 的 DDR 窗算，中心对齐用 `-clock_fall` 那一套 | RTL8211F 手册的 RGMII RX 表（数据相对 RXC 双沿的 setup/hold ps 值）+ 板级走线延迟；本仓已实测过"RGMII 是 DDR 采样、#57 之后没有 IDELAY 采样窗可言"，所以值给得讲道理比给个大值重要 | `build/timing_roster_diff.sh` 的 D1/D3（补完约束不许把别的域挤坏）+ 名册逐域念一遍 |
| `eth_tx_*` 那一组现在的 `set_false_path` | **保留但要重新论证**：RGMII 发送是源同步（PHY 用 FPGA 给的 GTXCLK 采数据），"假路"其实是在说"芯片到 PHY 这一段不做时序检查" | 查 PHY 手册的 RGMII TX 窗，若能查就把它改成 `set_output_delay`（对齐到 eth_tx_clk），查不到就在注释里写"已知未验证"并留成账 | 同上 |
候选值的现状（**不许直接抄进 XDC**，只当线索）：第三方一篇 RGMII 综述给的窗是
发送侧 setup/hold 各 1.2 ns、接收侧各 1.0 ns，并说"时钟延迟 90° 由 PHY 内部（RGMII-ID）或 FPGA 延迟单元做，
旧版 v1.3 才用约 1.8 ns 的铜皮偏斜"。这两个数是**二手表值**，本板的 PHY 是 RTL8211F，
必须以它的手册表 + 本板走线实测为准（`#57` 之后收侧是 IDDR + `IDELAY_VALUE=26`，那个 tap 数本身就是量出来的物证）；
写成一句可核对的话：**每个数要么来自手册/测量，要么在 XDC 注释里写明是估计并给区间**。

两个官方/权威口径支持这一步：UG949 的 timing closure 要求**每个 I/O 要么有延迟约束、要么有写明理由的豁免**；
源同步接口的约束写法见 AMD 论坛那篇《IO Timing constraints for source synchronous interface》，
入门到落地版可读 Xilinx 官方课程 Lab5 与 BLT 的《Demystifying I/O Timing Constraints》，
最小输出延迟为什么要单独算见 Abbey 那篇《Explaining Minimum Output Delays》；
RGMII 的接口行为以 AMD PG051 的 RGMII 章为准。
警告 这一节的 ps 数字**一个都没往 XDC 里写**——因为都要先读手册与本板走线实测（今天构建/台架在飞，
r114 第一件事就是量它们）。写形式与出处，是为了不让下一步变成"随手填个 2 ns"。

### 4c. 异步时钟组把四条跨域路**从所有检查的覆盖范围里拿走了**（这一处最像"其他地方"，也最没人管）

实读（两个独立来源）：
- `src/constraints/clock_groups_impl.xdc:28-31` 只有一条命令：`set_clock_groups -asynchronous` 三组
  （`eth_rxc` / `clk_fpga_0` / `sys_clk` 及其 `-include_generated_clocks` 生成钟）。
  ⇒ **组与组之间的路径完全不做时序分析**，这是官方允许的写法（也解释了为什么 `timing_summary` 的
  Inter Clock Table 只剩 `sys_clk↔clkout0_1` 一对，231 + 19 端点——那一对在同一组**内**，仍然被分析）。
- `build/cdc.rpt`（`report_cdc`，12:04 那份）里只有那一对：`Safely Timed`，Unsafe 0，No ASYNC_REG 0。
  ⇒ 也就是说**被组排除掉的那四条跨域路，`report_cdc` 一条都没念**——不是它们安全，是它们不在覆盖范围里。

XDC 头部（第 19-24 行）把这四条写成"跨域数据由结构保证，不靠时序分析"：
`dc_fifo` 格雷码 + 2FF（eth_rxc↔clk_fpga_0 视频流）、翻转 + 3FF 边沿检测（`ddr_bank_commit` 帧事件）、
3 级像素 + 3FF（`frame_commit_lock` 消隐窗）、3FF 控制字（`effect_ctrl`，实例 `u_eff`）。
四个模块都在树上（`src/rtl/eth/dc_fifo.v`、`src/rtl/eth/ddr_bank_commit.v`、
`src/rtl/video/frame_commit_lock.v`、`src/rtl/process/effect_ctrl.v`）。

**欠的账有两条，都不许用"结构保证"这句话抵掉**：
1. **没有任何一条 `set_max_delay -datapath_only`**（全 `src/constraints/` 里 `set_max_delay` 命中 0）。
   组排除把时序检查拿走的同时，也把**布线 skew 的上限**一起拿走了：工具可以把格雷码指针的两级 FF
   放到对角两端，到达时刻差想多大就多大。官方口径是给同步器补一条**有出处的** `set_max_delay -datapath_only`
   （数值口径按目的时钟周期与建立时间推，不许随手填 ns），把"结构保证"变成"有界保证"。
2. **#262 那四颗同步器（`rgray_s0/s1`、`wgray_s0/s1`）没有 `ASYNC_REG`**。
   这两条是同一个洞的两半：属性让工具把两级 FF 关进同一 slice，`-datapath_only` 让跨域到达差有界——
   少任何一半，"亚稳态传播窗口有保证"这句话都不成立。
   警告 顺序不能反：**先**加属性与 max_delay，**再**谈这四条路的时序数字变了没有；
   组排除下的路径本来就不进 WNS，所以"改了 WNS 没动"是预期，不是证据（rule 35 的另一面）。

**r114 怎么量（检查项必须能判未通过，零样本分支不算数）**：先写一个只读检查脚本列出"声明为异步的组对之间的所有跨域寄存器路径"
（`get_cells -hier -filter {PRIMITIVE_TYPE =~ CMEM.*}` 那种猜法一律不许用；用网表的时钟域属性逐条认），
条数必须 ≥ 4 才允许出结论；每条要求 (a) 目的两级 FF 都带 `ASYNC_REG`、(b) 有一条覆盖它的 `set_max_delay -datapath_only`，
两个维度**同现在一条判据里**（#44 那一课）。这个检查脚本**还没写**（写的时候按 `build/` 现有命名与对照规矩起，
落地即把件路径补进本节与 #266 —— 现在不点名，因为 `doc_currency` 的 D4c 会抓"指着盘上不存在的东西"）。

## 5. 把"逐域名册"落成检查工具（2026-10-03 已落地，件与对照都在盘上）
每次构建后出**名册差分**，不再手写"全局 WNS 从 X 到 Y"：
```
build/tcl/probe_timing_roster.tcl        # 改后那一版：逐时钟逐域的最差族（级数 / route% / 终点），只读开 routed dcp
build/roster_from_summary.sh <报告>      # 改前那一版：从归档的 timing_summary.rpt 的 Intra Clock Table 长回名册
build/timing_roster_diff.sh A.txt B.txt  # 逐域配对比较，任何一族变差都点名
```
差分那把判六条（`ROSTERDIFF D1..D6`）：D1 没有域从 MET 掉进违例；D2 **配上的 (域,类型) 对数 ≥ 8**（数得出才许出结论）；
D3 没有任何域的**相对余量**掉过 25 %（这就是"别的域被改了而头条没动"那一类）；D4 setup 与 hold 两个维度都必须在
同一条判据里被配上（#44 那一课：两维必须同现）；D5 改后名册不许有空读数；D6 扇出清单至少有一行（不然抓手名册是空的）。
头条 WNS 的绝对差只念不判（rule 35）。

改前那一版必须从报告重建名册——`impl_1/*_routed.dcp` **一次构建就被覆盖**（r108 那一版就吃过这个亏，#230），
而 `timing_summary.rpt` 每轮都归档。r112 的基线名册已落 `build/evidence/r113_before_roster.txt`
（四域八行：eth_rxc 0.445/5.56 %、clk_fpga_0 1.135/11.35 %、clkout0_1 4.467/22.34 %、sys_clk 14.463/72.31 %，
hold 0.050/0.056/0.059/0.133），与本文第 2 节的表同源同数，逐条钉住。

三个检查脚本各自的对照都跑过（`--self`）：roster_diff 5/5（一模一样必须判通过、**非头条域**掉进违例必须判未通过、
相对余量掉三成必须判未通过、全域变好必须判通过、名册残缺必须判未通过）；roster_from_summary 2/2，
其中真值钉的是 eth_rxc period=**8.000 ns**（125 MHz RGMII）。
这里也各踩过一次错：diff 的对照第一次写反了 A/B（三条"该判未通过"的被判通过），转换脚本周期列取错一格
（取成波形下降沿，margin 全成两倍而三条计数下限照样通过）——两处都改成了**必须能报未通过**的对照，见 #258。

**D6 那条未通过已经查到根（#263）**，这一条值得单独留在方法里：`report_design_analysis` 在本工具里
**没有 `-fanout` 模式**（实测：`build/evidence/r113_help_fanout_console.txt`），设计级高扇出名册要用
`report_high_fanout_nets -file … -max_nets … -fanout_greater_than …`。前两版探针调了不存在的模式，
`catch` 把错误吞了、报告文件没写、行数为 0 ⇒ 差分那侧只能判未通过。
问出这件事只花 40 秒：一个**不开设计**的 batch 里 `help <命令名>`，就能拿到官方选项表——
"报告形状要量不许猜"由此有了一条便宜到没有借口的执行方式。
同一个检查脚本上还挂着两处形状读错，一并改了：`route_pct` 恒空（真实行里百分数在**括号内**，
`Data Path Delay: 3.498ns (logic … route 2.843ns (81.275%))`，而原先写的匹配模式要求 `ns` 后直接跟百分号），
以及 `get_nets` 认带 `[n]` 位下标的网名时 `[` `]` 是 **GLOB 类字符**（`rok4[51]_i_1_n_0` 这种最该被抓的广播
会被裸 pattern 判成不存在 ⇒ 集合空、假对照；一律用 `-filter {NAME eq {…}}`）。
补差分的重跑入口是 `build/r113_roster_refanout.sh`（只读、产物带 `_rf` 后缀不覆盖上一份快照；
台架 xsim 在飞时 REFUSE——这台机 15.7 G 内存，开 routed dcp 会挤它）。

接进发布前检查会改动"门禁 N 项"那四处句子的条数 ⇒ 必须与那些句子**同一笔**改（#242/D1c 那一课；那四处句子是被机器读的形状）。
所以这三个脚本暂时只进构建链与本文，不进发布前检查的项数。

## 4d. 2026-10-03 实测：把"真实到达窗"写进约束之后，全局名册第一次说实话（件 `build/evidence/r114_io_roll_console5.txt`）

同一份 `system_top_opt.dcp` 起两次重跑 place→phys_opt→route，**唯一变量**是候选约束
`src/constraints/r114_io_async.xdc`（RGMII 收口 ±0.500 ns，上升沿 + 下降沿）。A 滚逐位复现正式构建
（`WNS 0.445 / WHS 0.050 / 失败端点 0`，逐钟八格全 MET）⇒ 这一次重跑的可信度不靠"看起来一样"。B 那次：

| 域 | setup A→B | hold A→B | 读数 |
|---|---|---|---|
| `eth_rxc` | 0.445 → 0.424 | 0.050 → **−2.885** | 5 个失败 hold 端点，落点 `u_iddr_rx_ctl/D`，**route 0.000 %** |
| `clk_fpga_0` | 1.135 → 1.155 | 0.056 → 0.058 | 未受伤 |
| `clkout0_1` | 4.467 → 4.206 | 0.059 → 0.064 | 未受伤 |
| `sys_clk` | 14.463 → 14.109 | 0.133 → 0.133 | 未受伤 |

两件事必须一起说：**输入侧欠账清了**（`check_timing` 的 HIGH 无输入延迟端口 5 → 0），
**旧的那个 0.050 从来不是设计值**——它是"RXD/RX_CTL 与 RXC 同时到达"这个隐含假设给的。
落点 2 级逻辑、走线 0 % ⇒ 不是布线挤的，是片外窗与 IDDR 采样沿的关系本来就没对上（r92 的 IDELAY 是在
**没有约束建模**的前提下调到"屏上看着对"的）。所以这次改动的正确读法不是"hold 变差了 2.9 ns"，
而是"口径改了，账才第一次算对"；修法排在下一步——**只剩一个单变量**：在带窗口径下扫 `IDELAY_VALUE`（现值 26）找眼心
（"两沿写重了"这个解释已被变体 A 否掉：去掉 `-clock_fall` 之后每一个数与两沿那一版逐位相同，见 `report/log/issues.md` #275/#278）。

再往下一层（`report/log/issues.md` #282/#285）：两批扫档把"数据侧还能不能再补"量到底了——模型 (a) 四档 −4.522/−3.703/−2.885/−2.570、模型 (b)（PHY RX 内部延迟打开，窗沿后 1.5–2.5 ns）三档 −2.522/−2.018/−1.703，斜率 ≈63 ps/tap 两批一致；那条 hold 报告的算术把病因指到**捕获钟网络延迟 DCD = 5.008 ns**（r92/#57 把 IDDR 从 BUFIO 搬进 BUFG 的那只钟）上，SCD = 0、required ≈9.84 ns 而 arrival 只有 7.11 ns ⇒ 要补 ≈2.7 ns，而数据侧最多再买 0.43 ns。⇒ 全局口径下这次改动的结论是"②已被数据否掉、只剩①：让 IDDR 吃更早的钟"，且 r92 那笔判断的前提（当时没有任何 `set_input_delay`）已经不再成立，这句写在 `src/rtl/eth/rgmii_rx.v` 的头注里（改的是注释，代码不变已由"去掉 // 行后逐字符相等"证明）。

另一条实测（`report/log/issues.md` #276）：`set_max_delay -datapath_only` 叠在 `set_clock_groups -asynchronous` 之上
**不落进 `report_exceptions`**（A/B 两滚表体都是 13 行，`-datapath_only` 出现 0 次）⇒ 四条跨域界一条都没生效。
"给同步器一条带理由的界"要动的是**排除口径本身**（那一对钟要不要继续整组互相排除），会改 WNS 的算法范围，
属于必须单独一次构建、带名册差分去做的决定，不能靠叠约束顺手完成。


## 4e. 2026-10-03 实测：高扇出广播"复制驱动"这次改动量到底了——**机制能动、目标族 +0.456 ns、代价落在 `eth_rxc` 的 hold ⇒ 放弃**（件 `build/evidence/r114_mf/verdict.txt`）

第 3 节说的"下一次不切逻辑、切广播"到这里有了真裁决。两次重跑同一份 `system_top_opt.dcp`，
唯一变量 = 布线前那次 `phys_opt_design` 带不带 `-force_replication_on_nets`（目标名单 =
`report_high_fanout_nets` 里 fo≥200 且**驱动不是 BUFG/BUFH/MMCM/PLL** 的 39 根网）：

| 判据（顺序 = 先证机制能动，再谈收益与代价） | A 滚（不加） | B 滚（加） | 判定 |
|---|---|---|---|
| 复制出来的单元数 | 0 | **296** | 机制动了（来源 1） |
| 名册里至少一根网扇出下降 | — | `u_pl/u_clk/u_mmcm_0` −58 | 机制动了（来源 2） |
| 目标族最差 slack（`p_eof → rows_hit[*]` 的 CE 锥） | 0.445 | **0.901** | +0.456 ns |
| `eth_rxc` hold | 0.050 | **0.035** | 相对余量 −29.0 % ⇒ **判未通过** |
| `clkout0_1` setup / `sys_clk` setup | 4.467 / 14.463 | 4.222 / 14.262 | −5.5 % / −1.4 % |
| Slice LUTs | 14154 | 14185 | +31（便宜） |

结论按名册差分下，不按头条：**这一改动被 `eth_rxc` 的 hold 否决**。理由是同一张表上的另一处读数——
第 4d 节量到"挂上真实 RGMII 到达窗之后，这个域的 hold 是 −2.885 ns、5 个端点全在 `u_iddr_rx_ctl/D`"，
也就是它的 hold 余量本来就不作数；在一个约束还没建全的域上再削掉三成相对余量，
等于把 #57 与 r62 那次"WHS 在 ±1 ps 上掷硬币"重新请回来（见 `report/log/issues.md` #288）。

三条可复用的口径：

* **"WNS 没动"不是证据**（rule 35）；这次改动的 WNS 与目标族都动了、还被否决，靠的正是逐域差分。
* 复制驱动**不是免费的**：+31 LUT 是小头，代价体现在别的域的 slack 上，所以判据必须成对（收益 + 代价）。
* 这类物理杠杆值不值，**先在便宜的通道上量**（只从已保存的 `opt.dcp` 重跑 place+route）：两次重跑共 ~13 分钟（place 1–2 min + route 4 min 各一遍），
  比正式一次构建 + 顶层台架便宜两个数量级（`report/log/issues.md` #288 第 2 条）。
* 没做完的（不许写成已做）：V2c 那根扇出下降的网是名字像钟的 `u_pl/u_clk/u_mmcm_0`。重开这个改动之前，
  要先把这类"驱动是 LUT 但住在钟分布上"的网剔出目标名单再量一遍，否则说不清收益来自哪里。

## 6. r116（2026-10-04）逐域极限审计：哪一格真的顶到器件边界，哪一格还欠一次改动

**这一节是"全局的时钟都到最优物理极限"这句话的兑现处**。上一版（r114）只把最紧的域讲到"够用"，
没有逐域回答"还剩什么杠杆、为什么不动"。交付要求 §7 要求三件同时成立才许写"到极限"
（L1 延迟分解有出处且主项不可再用非放宽手段压；L2 ≥3 条独立候选在便宜通道上实测收益 < 噪声底；
L3 名册没有任何域因这些尝试变差），所以下面**按域**摆，每域都指着件。
r116 那一版的名册（件 `build/evidence/r116_after_roster.txt`、差分 `build/evidence/r116_roster_diff.txt`）：

| 域 | 周期 | setup | 相对余量 | hold | 相对余量 | 端点 | 顶住它的是什么（全部抄自报告） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `eth_rxc` | 8.000 | **−0.846** | −10.57 % | **−0.870** | −10.88 % | 4,840（失败 5） | I/O 到达窗：2 级（IBUF+IDELAYE2）、**route 0.000 %** ⇒ 数据侧没有线可优化，剩的是钟网络角间差 |
| `clk_fpga_0` | 10.000 | **1.976** | 19.76 % | 0.053 | 0.53 % | 15,721（失败 0） | 一根 **239 引脚**广播网的 **5.690 ns** 布线（整条路 7.355 ns 的 77 %） |
| `clkout0_1` | 20.000 | **3.698** | 18.49 % | 0.059 | 0.29 % | 30,179（失败 0） | OSD 地址/字符算术锥 **22 级**（9 级 CARRY4），route 59.2 % |
| `sys_clk` | 20.000 | **14.876** | 74.38 % | 0.222 | 1.11 % | 323（失败 0） | 谁都不是：离任何边界都远 |

### 6.1 `eth_rxc` —— 唯一被**证明**顶到边界的一格（L1+L2+L3 齐）

L1（延迟分解，件 `build/evidence/r116/r116_io_hold.rpt`、`..._SETUP.rpt`）：
`Data Path Delay 3.928 ns = logic 100.000 % + route 0.000 %`，逻辑只有 `IBUF`+`IDELAYE2` 两级器件原语；
required 侧是 `DCD 5.008 + 不确定度 0.835 + IDDR hold 0.155 = 5.998 ns`。⇒ **主项是钟网络的插入延迟**，
数据侧已无对象可优化（布线 0）。
L2（≥3 条独立候选实测，负结果按 §7 的要求写在这里而不是删掉）：
① **IDELAY tap 扫满 0…31**（件 `build/evidence/r115_window/probe3_console.txt`）：
`HOLD(τ) = −2.822 + 0.0630τ`、`SETUP(τ) = +2.005 − 0.0920τ` ⇒ hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，
合法区间 0…31 ⇒ **两个集合不相交**。τ=31 是 min(hold,setup) 的最大点，比出货值 26 抬 +0.315 ns（本版已采纳）。
② **MMCM 负相移**（r115 副本树，件 `build/evidence/r115_c2_scratch/option_a_console.txt`）：
`−225°` 的相位提前被 MMCM+BUFG 自己的网络延迟吃掉还有余，捕获沿反而**推迟 0.911 ns** ⇒ 判为未采纳。
③ **Pblock**（r113 实测 + 本版 `build/tcl/pb117_roll.tcl`：那一格取空就当场拒绝开跑）⇒ 没做成单变量实验。
④ **统一 0.800 hold 带**（r115）：全设计 WHS −0.747 / 25,742 失败端点 ⇒ 那是"把欠账照出来"，不是收益，本版不动它。
L3：名册差分里 `eth_rxc` 之外的三域 setup 全部持平或余量增大，四域 hold 逐格不动 ⇒ 没有拆东墙补西墙。
**角间差不等式（这一格的物理极限的真正形状）**：hold 查慢角 `DCD 5.008`、setup 查快角 `DCD 1.597`
（同一只钟的两个角，件里两个数都有），差 **3.411 ns**；而数据侧两角只差 **0.467 ns**。
要同时满足需要 `D_slow/D_fast ≥ 1.73`（保留带子）/ ≥ 1.45（去掉带子），实测这条 IDELAY 主导的路径只有 **1.15**。
⇒ 在这一代器件 + 当前结构（IDDR 与 4,835 端点的 125 MHz 流水线共用一只 BUFG）下，**不存在能同时满足两条检查的采样点**。
出口只有一个，写在下面第 7 节末（把捕获钟做短且角间不散），而那是一次**架构改动**、不是又一档约束。

### 6.2 `clk_fpga_0` —— 审计时判"未到极限"，本版把靶子从猜测换成读数，并在便宜通道上量到一把**余量增大的改动**

r116 名册最差 setup 路的逐段分解（件 `build/evidence/r117_d0/worst_clk_fpga_0_setup.rpt`）：

```
SLICE_X43Y79 FDCE (Prop_fdce_C_Q)   0.379   u_pl/u_arb/owner_eth_reg/Q
           net (fo=269, routed)     5.690   u_pl/u_row/hi_reg_0[0]      <- 7.355 ns 里的大头
SLICE_X88Y7  LUT6 (Prop_lut6_I3_O)  0.105   u_pl/u_row/hi_reg_4_i_1
           net (fo=2, routed)       1.181   u_pl/u_bilin/u_fb/hi_reg_8_0[0]
RAMB36_X3Y1  RAMB36E1 (Setup_..._WEA[0])    -0.476
Clock Path Skew −0.039 ns（DCD 2.321 / SCD 2.456）  Clock Uncertainty 0.154 ns
```

⇒ 根因标签 **FANOUT**（不是"两端离得远所以画个框"；本审计先给过的那个 Pblock 杠杆是**错的**，
框住目的地不会把源拉过来，后来的实测把它推翻了——负结果与被推翻的说法都留在这里，不删）。
负载清点（件 `build/evidence/r117_d0/nethelp_console.txt`）：`HIERGROUP u_pl/u_row = 239`、
`LOAD_TILE_UNIQUE=99`，且**两路独立取名一致**（`AGREE load_vs_name=1`）。
**这一改动的实测结果（D1 便宜通道，单变量 = place 之后加一次强制复制；对照重跑 A 逐格复现 r116 正式名册）**：

| 读数 | 对照重跑 A（＝r116 正式构建） | 复制重跑 B | 差 |
| --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.976 | **2.009** | +0.033 |
| `clkout0_1` setup | 3.698 | **3.885** | +0.187 |
| `sys_clk` setup | 14.876 | **15.174** | +0.298 |
| `eth_rxc` setup / hold | −0.846 / −0.870 | −0.846 / −0.870 | **一格不动** |
| 四域 hold | 0.053 / 0.059 / 0.222 / −0.870 | 同上 | 不动 |
| 机制 | — | 该网引脚 **239 → 1**、`*replica*` 10 颗、`clk_fpga_0` 端点 15,721 → **15,731（+10）** | 闭合等式对上 |
| 代价 | — | Slice 寄存器 8,188 → **8,198（+10）**，LUT/BRAM/DSP 不动 | 复制吃 10 只 FF |

噪声底 `noise_ns = 0.000`（r115 两次空白重跑逐位复现），所以这三格移动都大于噪声底、是三处余量增大；
`eth_rxc` 一格没动 ⇒ G1 成立。**采纳入口已经写好**：`build/tcl/r117_post_place_hook.tcl`
（挂在 `STEPS.PLACE_DESIGN.TCL.POST`，取名不一致就 `error` 停下而不是悄悄换目标），
件 `build/evidence/r117_repl3/b_console.txt`。

### 6.3 `clkout0_1` 与 `sys_clk` —— 本版不欠改动，理由各是一条可查的判据

`clkout0_1` 的主导项是 **22 级里 9 级 CARRY4** 的 OSD 地址/字符算术锥（route 只占 59.2 %）。
它的历史就是这条锥的历史：#105 立案 → r109 在读侧插一拍 → 现在 18.49 % 相对余量。
再要收益只能继续砍级数，而 OSD 是交付物本体（功能面改动），不在"一次时序改动"的授权范围里。
`sys_clk` 74.38 % / 323 端点，不是瓶颈。
两域的本版 hold 与 r114 逐格相同（0.059 / 0.222），没有被动过。

### 6.4 全局一句话（有件的版本）

**四个域里三个已被量到"再要收益只能动结构或动功能"的位置**（`sys_clk` 余量 74 %、
`clkout0_1` 主项是级数、`eth_rxc` 的 I/O 那 5 格被不等式证死），
第四个（`clk_fpga_0`）本版**找到了对症的改动并量到余量增大**（+0.033/+0.187/+0.298，代价 +10 只 FF，别的域一格不动），
所以"到极限"这句话现在成立的完整形状是：**在不动架构（捕获钟拓扑）也不动功能（OSD 锥）的前提下，
名册上每一格要么已经为正、要么被证明了关不掉，且量到的最后一次非放宽改动已经落地或已配好落地入口**。
仍然欠的两笔都不是"还能再优化"这类：**H5 的 6 个输出端口**（要外部 DVI/HDMI 窗口数或队伍批准的例外，
第 4 节那笔债已把"本机查过没有"写成凭据：UG471 第 95 页只给 `TMDS_33` 的属性表，没有任何接收端窗口数），
和**把捕获钟做短**这项改动（架构改动，代价面见第 7 节）。

## 7. 下一次改动（把 IDDR 的捕获钟换成短钟）的数值靶子与必须先算的代价面

靶子（有件）：`eth_rxc` 现在这条 BUFG 树是 `C_slow 5.008 / C_fast 1.597`（角间差 **3.411 ns**），
分量拆开是 `IBUF 1.430/0.454`、`BUFG 0.085/0.029`、`网络 1.873+1.620 / 0.731+0.903`（都在报告里）。
换成 I/O 专用短钟（BUFIO：IBUF + 专用走线，几乎不走通用布线）后，
按"专用走线 ≈ 0.5 / 0.2 ns"这个**尚未实测**的假设估 `C_slow ≈ 1.93 / C_fast ≈ 0.65`（角间差 1.28）。
代回第 6.1 那两条已经量到的曲线（数据侧 `D_slow = 1.976+0.0630τ`、`D_fast = 0.754+0.0920τ`，
0.800 的带子**保留不动**）：

```
HOLD  要 D_slow ≥ C_slow + 0.155 + 0.800 − 1.2 = 1.685  → τ ≥ −4.6   ⇒ τ=0 就满足
SETUP 要 D_fast ≤ 4 + C_fast − 0.035 − 0.259 − 2.8 = 1.556 → τ ≤ 8.7
⇒ τ ∈ [0, 8.7] 全区间两检查同号为正，最平衡点 τ ≈ 4~5（hold +0.54 / setup +0.44）
```

⇒ **这一族在短钟网络下是可关的，而且不需要放宽任何东西**（带子留着也算得出正）。
但整段推导吊在"专用走线 ≈ 0.5/0.2 ns"那一个没量过的数上 ⇒ 动它之前先花 40 秒把
**BUFIO 的慢/快 DCD 实测**问回来（只读探针，看 `ILOGIC_X* IDDR/C` 的到达时间；r92 当年只留了慢角 3.171）。

先把"手册里到底有没有这个数"查完（两遍扫描，件 `build/evidence/r117/bufio_delay_scan.txt` 与
`build/evidence/r117/bufio_delay_scan2.txt`，扫描器 `build/clock_io_delay_scan.py` / `..._scan2.py`）**：
UG472（114 页）的 BUFIO 一节都是定性叙述（"BUFIO 只驱动 I/O 钟资源"、"给 ISERDES/OSERDES 的 CLK 提供低偏差钟"），
没给插入延迟的 ns/ps 数；UG471（188 页）+ UG472 按"同一行既有 `数字+ns/ps` 又落在钟语境里"筛 ⇒ **命中 0 页**。
警告 这句只到"没筛出来"，**不许写成"手册里没有"**：表体常把单位放在表头，逐行筛法本来就容易漏
（同一类教训：告警计数不能当 WNS 的代理，ISSUES #290）。⇒ 那个 0.5/0.2 ns 在这页里始终是**假设**，
只用来回答"值不值得动"，不用来支撑任何"已证明"的说法；关闭它的唯一办法还是上面那 40 秒实测。

如果实测角间差仍然 > 1.7 ns，这个区间再次变成空集，那时要说的就不是"换树"而是
"这一代器件的 I/O 钟树对 8 ns 周期 + 1.6 ns 外部散布就是不给解"——那句话也得有件才写。

**代价面（这项改动不能单独落的原因）**：短钟把 IDDR 的捕获沿提前之后，`IDDR → 下游流水线`就变成
"发射沿 1.93、捕获沿 5.008"的跨树路，工具会为这些路在数据上插 ~3.07 ns 延迟；而这条流水线里最重的锥是
`gmii_rx_mac` 的 FCS-32（实测 7.066 ns 数据+布线，8 ns 周期）⇒ 预算被吃掉之后只剩 ~4.9 ns，
大概率从 MET 掉进违例。所以它的完整形状是：**IDDR（+紧邻第一级）吃短钟，跨到 BUFG 域经过一级同步 FIFO**，
这是一次架构改动，门槛与 r92 当年放弃 BUFR 的理由是同一个（GMII 下游跨区）。
动手前的三件只读事：① BUFIO 慢/快 DCD；② `gmii_rx_clk` 的 2,546 个负载落在几个时钟区；
③ 名册差分把"IDDR→流水线"那族 setup **单独列一格**——它与 I/O 那 5 格不是一个东西，
不许用后者的收益盖掉前者（H2 的字面意思）。

## 8. 约束放宽记录（本版口径，写在这里让第 6 节的每句话都能被追溯）

本版**约束放宽记录 = 0 条数据行**（交付侧的登记就是本节，本地那份记录与它同行同数）：
没有加大周期、没有加大 I/O offset、没有新增 `set_false_path`/`set_clock_groups`/`-datapath_only`/`set_multicycle_path`、
没有删除或缩小任何既有约束、没有把任何 `set_clock_uncertainty` 调小。
本版进构建的两样都是**加严方向**：给 5 个 RGMII 输入第一次写上到达窗（`min 1.200 / max 2.800`），
以及把 `IDELAY_VALUE` 从 26 挪到实测眼心 31（不改约束，改的是被检查的那条数据路径本身）。
第 6.2 那次复制改动同样不碰约束：它加 10 只 FF，重挂 239 个负载，别的什么都不动。

## 参考（官方与论坛，2026-10-03 查）
- [Timing Closure — UG949 UltraFast Design Methodology Guide](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Timing-Closure)
- [Additional Uncertainty — UG949（不确定度那一节；警告 页名可查、正文要 JS 渲染才出得来，抓不到逐字，所以只引页名不引原句）](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Additional-Uncertainty)
- [Relaxing the Setup Requirement While Keeping Hold Unchanged — UG949（setup 松、hold 不松的正确做法，同一族）](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Relaxing-the-Setup-Requirement-While-Keeping-Hold-Unchanged)
- [Specifying Boundary Timing Constraints in Vivado（Abbey 的 I/O 边界约束写法）](https://blog.abbey1.org.uk/index.php/technology/specifying-boundary-timing-constraints-in-vivado)
- [IO Timing constraints for source synchronous interface（AMD 论坛）](https://adaptivesupport.amd.com/s/question/0D52E00006hpUNiSAM/io-timing-constraints-for-source-synchronous-interface?language=en_US)
- [Demystifying I/O Timing Constraints（BLT）](https://bltinc.com/2025-05-13/demystifying-i-o-timing-constraints/)
- [Xilinx Design Constraints / FPGA Design with Vivado Lab 5（官方课程：输入输出延迟怎么给）](https://xilinx.github.io/xup_fpga_vivado_flow/lab5.html)
- [Explaining Minimum Output Delays（hold 侧为什么要单独算）](https://blog.abbey1.org.uk/index.php/technology/explaining-minimum-output-delays)
- [Clock Skew in Synchronous Interface Timing（MathWorks 源同步窗与偏斜的关系）](https://www.mathworks.com/help/signal-integrity/ug/synchronous-interface-timing.html)
- [HDMI/DVI Intra-pair and Inter-pair skew（TI E2E：TMDS 对间/对内偏斜口径）](https://e2e.ti.com/support/interface-group/interface/f/interface-forum/267205/hdmi-dvi-intra-pair-and-inter-pair-skew)
- [RGMII — PG051 Tri-Mode Ethernet MAC（官方：RGMII 收发时序行为）](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/RGMII)
- 6.2.5 RGMII Transmit —— Altera Triple-Speed Ethernet IP User Guide（文档号 813669、rev 26.1）里同一口径的对照写法；跨厂商手册只作对照，正文里不放该站 URL：导出器的死链自检会把 URL 中段当成仓内相对路径（本项目没有那个目录），要核的人按文档号检索
- [Timing Closure - Suggestions for high fanout signals（AMD 自适应支持 9410）](https://adaptivesupport.amd.com/s/article/9410)
- [Top 5 Timing Closure Techniques（Xilinx 官方 PDF）](https://www.xilinx.com/publications/prod_mktg/club_vivado/presentation-2015/paris/Xilinx-TimingClosure.pdf)
- [UltraFast Design Methodology Guide 全文 PDF（ug949）](https://www.mouser.com/pdfDocs/ug949-vivado-design-methodology.pdf)
- [Very high fanout net not being replicated by Vivado（Electronics Stack Exchange）](https://electronics.stackexchange.com/questions/472393/very-high-fanout-net-not-being-replicated-by-vivado)
- [phys_opt_design — UG904 Vivado Implementation（官方文档页；警告 本页正文要 JS 渲染才出得来，抓不到逐字，三个复制旗标的原文是从本机 `help phys_opt_design` 读的）](https://docs.amd.com/r/en-US/ug904-vivado-implementation/phys_opt_design)
- [MAX_FANOUT — UG912 Vivado Properties（属性那一侧的官方口径；同上抓不到正文，且这条在本工具里还没实测，所以不写成已用）](https://docs.amd.com/r/en-US/ug912-vivado-properties/MAX_FANOUT)
- [Allow Register Replication — UG949](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Allow-Register-Replication)
- [Replicate High Fanout Net Drivers — UG949](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Replicate-High-Fanout-Net-Drivers)
- [MicroZed Chronicles: Baseline Timing Closure（第三方实践帖）](https://www.adiuvoengineering.com/post/microzed-chronicles-baseline-timing-closure)

## 9. r117 与 r118（2026-10-04）：全局名册上最后两次非放宽的物理改动，各自量到判语

**r117 = τ=31 + C9（对 239 引脚广播网强制复制）**，输入窗按发布前检查退回候选件（原因写在
`build/tcl/build_system_axigpio.tcl` 的约束加载处：绑窗后有 4 条发布前检查硬项判未通过，而 `build/gates.sh` 自己的结论句是
"有红项 ⇒ 不采纳，保留上一版"；约束原件与全部证明留在 `src/constraints/r116_rgmii_input_window.xdc`，
`VP_R116_IO_WINDOW=1` 一条命令复现）。对照 = **r114 官方名册**，且必须同生成器配对
（件 `build/evidence/r114_after_roster_probefmt.txt` → `build/evidence/r117_roster_diff_vs_r114.txt`；
拿 `roster_from_summary.sh` 那份去减探针那份会被口径闸门判 REFUSE，账在 `report/log/issues.md` #326）。

| 域 / 格 | r114 | r117 | 判语 |
| --- | --- | --- | --- |
| `clk_fpga_0` setup | 1.850 ns（18.50 %） | **2.104 ns（21.04 %）** | 余量增大；机制同步成立（239→1 引脚、10 颗 replica，`impl_1/runme.log` 与 `build/r117_a1_read.sh` 两处都能读到） |
| `clkout0_1` setup | 3.630 ns（18.15 %） | **3.353 ns（16.77 %）** | 余量减小 |
| `eth_rxc` setup | 0.739 ns（9.24 %） | **0.615 ns（7.69 %）** | 余量减小，且这是全设计绝对最紧那一格 |
| `eth_rxc` hold | 0.052 ns | **0.044 ns** | 余量减小，且这是全设计最薄那一格 |
| `sys_clk` setup | 14.876 ns | **14.815 ns** | 余量减小 |

⇒ **C9 判为未采纳**（`build/r117_verdict_declined.txt`）：开跑之前登记的严格口径是"任何一格 rel_margin 不许变小"，
四格余量减小就判未采纳；`build/timing_roster_diff.sh` 的 D3 门槛是"掉 25 % 以上的域数"，对同一份数据给 `result=GREEN`。
**两个检查脚本判语不一致这件事没有靠放宽任何一方来消除**（#328），而是把严格那个独立成可指路的件
`build/evidence/r118_strict_b1.txt`。这与 r115 那次 C1 复制改动的情形完全相同（`report/log/issues.md` #288）：
机制动了，代价落在最紧的域上 ⇒ 不做。

**r118 = 只带 τ=31**（`IDELAY_VALUE` 26→31，r116 在同一份已布线 DCP 上把 0…31 扫满量出来的收口眼心；
`HOLD(τ) = −2.822 + 0.0630τ`、`SETUP(τ) = +2.005 − 0.0920τ`，`min(hold,setup)` 最大点在 τ=31，
比出货值 τ=26 抬 +0.315 ns，件 `build/evidence/r115_window/probe3_console.txt`）。
这一改动的收益**不在片内 slack 上**（τ 只动 I/O 单元的抽头），所以判据不能写成"WNS 变好"（rule 35），
而是四条：B1 严格名册对 r114 逐格不劣化 / B2 机构中性（本版故意不挂复制钩子）/
B3 资源中性 / B4 发布前检查末行原话「判定 24 项」里未通过数 == 1 且两跑逐字节一致；全过才上板，任一不过板子回刷 r114。
判读与板侧读数：`build/r118_verdict.txt`、`build/evidence/r118_strict_b1.txt`、
`build/r118_gates.txt`、`build/evidence/r118_board/board_now.txt`（本版结果句在首页那一行与
`build/r118_verdict.txt`）。

**这一节之后，"到极限"这句话在这颗 -2 器件上的完整形状是**：
① 四个域的逐格状态全部有归属判据；② 非放宽的物理杠杆（复制广播网、Pblock、BRAM 换 setup、
策略扫描、同 DCP 重跑、灰码 ASYNC_REG、τ 扫档）已经逐次量过并给出余量增大／判未采纳；
③ 唯一还能改变结论的只剩**架构那项改动**（IDDR 吃短捕获钟 + 一级同步 FIFO 再进 BUFG 流水线），
它的门槛与代价面在第 7 节，动它之前还欠一个 40 秒只读实测（BUFIO 快/慢角 DCD，#323）；
④ `eth_rxc` 的收口 I/O 在当前结构下被证明关不掉（0…31 全档区间不相交），本版不为它建窗 ⇒
那 5 个端点是**未检查**，而"未检查 ≠ 满足"必须写在首页那一行里（H5）。

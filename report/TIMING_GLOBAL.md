# 全局时序（不是"追着最差那一条改"）——方法 + 这一版的真值 + 我此前漏掉的账

写在前面：这份文件是被一句批评逼出来的——"你不要这么一根筋，改时序的时候也要考虑其他地方的时序"。
下面第 2 节就是那句话的正面回答：**同一轮里四个时钟域各自动了多少**，第 4 节是我一直在漏的**约束侧欠账**。

## 1. 方法（照官方文档改的，不是我自己发明的规矩）
1. **先看全设计，再看那条路**：`report_timing_summary` 的 Design Timing Summary + **Intra/Inter Clock Table**
   是主表；逐时钟 WNS/WHS/TNS/**失败端点数**与端点总数都要读。WNS 只说"最紧那一条"，
   它换了主语（换到另一个模块甚至另一个时钟）时，绝对差既不是收益也不是损失（本仓库规矩 35 的同一条）。
2. **判"是不是布线/距离问题"看比例，不看感觉**：`Data Path Delay` 那行的 logic/route 百分比 + `Logic Levels`。
   route>80 %、级数≤4 的路，拆逻辑救不了；该动的是**扇出复制**、**控制集/寄存器复制**、**floorplan**（UG949 的 Timing Closure 章、
   Xilinx 官方文章 9410《Suggestions for high fanout signals》列的就是这几类手段与 `MAX_FANOUT`/`report_qor_suggestions` 这条路）。
   ⚠ 扇出高不一定被工具自动复制（stackexchange 那一条就是"很高的扇出没被复制"），所以要显式给约束并**量结果**。
3. **让工具给建议，别只靠自己盯**：`report_qor_suggestions`（只读）+ 需要时 `source qor_suggestions.rpt` 到一次**隔离**构建里量收益。
4. **约束缺口会伪装成"时序没问题"**：`check_timing` 的 `no_input_delay` / `no_output_delay` 意味着那些端口被当成理想时刻，
   工具根本不优化它们（UG903/UG949 都是这个口径）；`report_methodology` 的 TIMING-9/10（CDC 未识别、同步器缺属性）
   与 `report_cdc` 是**功能性硅风险**的来源，比 WNS 少 0.1 ns 重要得多。
5. **每一刀改完必须交"名册差分"**（本仓库的新规矩，见第 5 节）：改前后各出一份
   `逐时钟 WNS/WHS + 每域最差 3 族的起点→终点/级数/route%/fo`，任何一条**变差**都要点名是谁，
   不许只念全局 WNS 那一个数。

## 2. r112 这一版的**全设计**读数（一次构建，四域同表）
件：`build/timing_summary.rpt`（Intra Clock Table）、`build/setup_paths.rpt`、`build/hold_paths.rpt`、
`build/r112_reasm_probe.txt`（族级）、`build/r113_roll_ABC_verdict.txt`（物理侧三滚）。

| 时钟 | 周期 | WNS | 相对余量 | WHS | 端点数 | 最差那一格的形状 |
|---|---|---|---|---|---|---|
| `eth_rxc` 125 MHz | 8.000 | **0.445** | **5.56 %** ← 全局最紧 | **0.050** | 4835 | `u_rx_par/p_eof_reg → u_reasm/rows_hit_reg[12..15]/CE`，4 级，route **84.276 %**，中段 `rok4[51]_i_1_n_0` **fo=305** |
| `clk_fpga_0` 100 MHz | 10.000 | 1.135 | 11.35 % | 0.056 | 15721 | `u_arb/owner_eth_reg → u_bilin/u_fb/lo_reg_0_24/ADDRARDADDR[3]`，**1 级 LUT3**，route **93.875 %**（fo=269 网络 + BRAM 地址） |
| `clkout0_1` 50 MHz（像素） | 20.000 | **4.467** | 22.34 % | 0.059 | 30179 | `u_mode/mode_q_reg → u_pipe/u_gray/dout_reg[2]/D`，**18 级含 8×CARRY4 + LUTRAM**，route 67.2 % |
| `sys_clk` 50 MHz | 20.000 | 14.463 | 72.3 % | 0.133 | 323 | `u_ang/angle_reg[4] → angle_reg[6]/D`（角度 ±1° 的进位链，最宽的一档） |
| 跨域 `sys_clk↔clkout0_1` | — | 4.399 / 14.276 | — | 0.300 / 0.259 | 231 / 19 | 一条含 **DSP48E1** 的 15 级路（`angle → zmap/y_out`） |
| 脉冲宽度 | — | WPWS 最小 **0.264** | `clkout2`（IDELAYCTRL REFCLK 的 Max Period） | — | 12634 总 | 收包域那颗 5 ns 参考时钟的**上沿宽度**余量最小 |

**这一轮"其他地方"动了什么（这就是被我漏掉的那半句话）**：
`eth_rxc` 0.713 → **0.445**（−0.268），同一轮 `clkout0_1` 3.799 → **4.467**（+0.668）、`clk_fpga_0` 1.186 → 1.135（−0.051）、
`sys_clk` 15.157 → 14.463（−0.694）。全设计失败端点仍 **0**、`check_timing` 无 loops/no_clock。
⇒ 三滚实测证明：同一份 `opt.dcp` 重跑 place+route **逐位复现**（不是骰子），所以这几个数是**一轮改网表的确定性重排**，
**四域要一起念**——只念"全局 WNS 掉了"或者只念"显示域涨了"都是半句话。

### 2b. r113 对 r112 的名册差分（实测，`build/evidence/r113_roster_diff.txt`）
这一行就是"全局"该有的说法，不是我抄的一个 WNS 数：**八个 (域,类型) 对逐位相同**。
```
clk_fpga_0 setup 1.135 -> 1.135   hold 0.056 -> 0.056
clkout0_1  setup 4.467 -> 4.467   hold 0.059 -> 0.059
eth_rxc    setup 0.445 -> 0.445   hold 0.050 -> 0.050
sys_clk    setup 14.463 -> 14.463 hold 0.133 -> 0.133
```
两端的来源是**不同**的：改前那侧由 `build/roster_from_summary.sh` 从归档的 r112 `timing_summary.rpt` 长回来，
改后那侧由 `build/tcl/probe_timing_roster.tcl` 直接问 r113 的 routed dcp（B 侧 slack 带着
`(required time - arrival time)` 后缀、还带级数/route%/终点，A 侧是纯数字 —— 形状不同，才不是把同一个文件读两遍）。
**为什么该相同**：#256 那把修复只改 FF 的 INIT 属性，不改网表结构（同一批 FDRE、同一些连接），
而这台工具的放置/布线是确定性的（#254 已实证：同一份 opt.dcp 重跑逐位复现正式构建的数字）⇒
时序一位不动，只有位流内容变了（`build/system.bit` md5 从 `897fa9d93956` 变成 `b94f4da6cdff`）。
所以这一轮的口径是：**功能修复，时序中性**——四个域、setup 与 hold 两边都是这个结论，不是只看头条。

差分六条里唯一红的是 `D6_fanout_inventory`（`fanout_rows=0`）。这条红的是**我的工具**，不是设计：
`report_design_analysis -fanout -limit 12 -interval 4` 在那个版本上什么都没写出来，而下游数到 0 行就判红 ——
这正是计数地板该有的样子（空产物不许伪装成"这一版没有高扇出"）。探针已改成最素的调用并把
`FANOUT_ERR` / 报告头 20 行念出来；下一次 Vivado 窗口（顶层台架跑完之后）重问一次，D6 才会真的有意义。

## 3. 下一刀为什么不再切逻辑，以及"全局"怎么切
   工具自己那份**建议名册**也要念：`probe_timing_roster.tcl` 现在除了扇出，还跑
   `report_qor_suggestions -max_candidates 12` + `write_qor_suggestions`，把 `QORSUG|…` / `QORHINT|…` 落成行
   （UG949 的流程就是"先问工具，再逐条审"）。命令都包在 catch 里：这个版本没有它就明说 `QOR_ERR=`，
   而不是让探针死在半路。**下一刀的候选顺序 = 工具建议名册 ∪ 扇出/放置抓手，再按域排代价**，
   而不是"哪条最疼改哪条"。
- `eth_rxc` 那条的 6.089 ns 走线里，第一跳 `p_eof`（**fo=8**）就吃 **2.141 ns**：起点 `SLICE_X57Y34`、终点整片 `rows_hit` 在 `X28~X31` ⇒ 距离。
  换实现指令（`place_design -directive Explore`）**一格不差**；Pblock 那块因进位链半内半外**没做成单变量**（1716 里 255 出块）。
- 所以候选只剩两类，都要按全局判据交账：
  ① **`MAX_FANOUT` / QoR 建议**（官方 9410 那条路）：目标是 `rok4[51]_i_1_n_0` **fo=305** 与 `u_reasm/wr_en_reg_1` **fo=547** 这两根广播。
     它是**约束级**改动（不动 RTL），代价面是复制出来的 cell 会挤占别人 ⇒ 必须看 `report_utilization`、`report_route_status` 与**其余三域**有没有变差；
  ② 修 Pblock 表达式（把共享进位链的 `u_eth/u_rx_mac` 一起收进来）再滚一次；只允许"加不加这块 Pblock"一个变量（#223）。
- ⚠ 明确不做：`#179`（icmp_rx 校验和，70.5 % route，量过收益上限低）、`#141`（BRAM 换 setup，量过被否）、
  `#105` 尾账那类"再插一级"——都是在已经 route 主导的锥上磨逻辑。

## 4. 约束侧欠账（这些是"其他地方的时序"，此前我没当真）
| 项 | 实读（`build/timing_summary.rpt` 的 check_timing / Methodology 两张表） | 含义与我打算怎么处理 |
|---|---|---|
| `no_input_delay` | **5 个输入端口 HIGH**（另有 2 个已被 false path 覆盖 MEDIUM） | 这 5 个口的到达时刻被当理想 ⇒ 工具不优化、也不报违例。要么给 `set_input_delay`（RGMII 那一路是 **同步采样**，`#57` 之后没有 IDELAY 采样窗可言，值要给得讲道理），要么写 `set_false_path -to` 并说明**为什么**是假路。不许留着当"未知" |
| `no_output_delay` | **6 个输出端口 HIGH**（+6 个 MEDIUM 有 false path） | 屏（TMDS）与 SDC/LED 那几路对外没有负载模型 ⇒ 现在报的"MET"不含这一段。要么给 50/60 MHz 像素时钟下的板级窗（先量再写），要么显式豁免并留理由 |
| ↑ 以上两条**现已点名**（`build/check_io_timing_coverage.py`，件 `build/evidence/r113_io_debt.txt`） | 输入侧：源码数出的 5 位（`eth_rx_ctl` + `eth_rxd[3:0]`）与报告的 5 **对账相等**（两个独立来源）。输出侧被点名的裸端口是 **7 个**：`tmds_clk_p/n`、`tmds_data_p[2:0]`、`tmds_data_n[2:0]`、`led[1:0]`、`eth_mdc`、`eth_mdio` | 这就是"其他地方"。屏那一路现在报的 MET **不含芯片到面板那一段**，而 MDIO/LED 连"我是假路"这句话都没写过。源码端 12 位与报告端 6 位差的那 6 位钉在判据 I7 里等解释（要靠 `check_timing -verbose` 问 Vivado，本轮构建在飞 ⇒ 记 #259，r114 补） |
| `TIMING-9` / `TIMING-10` | 1 / 1 | "Unknown CDC logic" 与 "Missing property on synchronizer"：`ASYNC_REG` 少在一处 ⇒ 这跟今天那笔**根因**（#256：这一域根本没复位）是同一族的结构账 |
| `DPIR-1` / `LUTAR-1` | 2 / 1 | 异步驱动 / LUT 驱动异步复位：都是"复位网真不真的可靠"的问题，与 #256 同族 |
| `SYNTH-5` / `SYNTH-6` | **336 / 98** | "因为时序约束才映射成分布式 RAM"——这条我之前一直没管：它说明**BRAM/LUTRAM 的选型在被约束牵着走**（本仓库 BRAM 已经 95.5/140 tile，LUTRAM 4044 个），要单独量一次，不能当噪声 |
| 自加不确定度 | hold 侧 **0.8 ns**（`set_clock_uncertainty` 的策略） | 报出来的 WHS 0.050 是"按这个严口径"剩下的量，念数字时必须带着这句 |

### 4b. r114 的补法（按端口分组，约束的**形式**与数字的**出处**都写死，不靠我拍脑袋）
| 端口组 | 该给什么约束（形式） | 数字从哪里量/查（不许编） | 补完之后谁来判 |
|---|---|---|---|
| TMDS 六路输出（`tmds_clk_p/n`、`tmds_data_p/n[2:0]`） | 源同步输出：`set_output_delay -clock <输出时钟> -setup/-hold [get_ports {tmds_*}]`，时钟取**驱动这些数据的那颗**（像素时钟 / 其 5× 串化时钟），而不是 sys_clk | 面板端采样窗 = TMDS 接收端的 setup/hold；DVI/HDMI 源同步惯例是"数据沿对齐时钟沿、余量以 UI 计"，具体 ps 要查**这块面板/接收芯片的手册** + 本板走线等长实测（原理图与管脚表在 `D:\Xilinx\Resource\ZYNQ7020\Board_Resource`）。查不到就退一步：写 `set_max_delay -datapath_only`（限偏斜而不是定死窗），并把为什么这样写在 XDC 注释里 | `build/check_io_timing_coverage.py` 的 I3（不许有裸输出）+ I1/I2（对账仍要成立） |
| `led[1:0]` | 慢速推挽输出，不对外定时序 ⇒ `set_false_path -to [get_ports {led[*]}]` **并写明理由**（灯由人眼读，没有建立/保持窗） | 不需要数字，需要那句理由（写进 XDC 与本文，才算"显式豁免"） | 同上（FALSEPATH 那一档，且豁免表要带理由） |
| `eth_mdc` / `eth_mdio` | MDIO 是 bit-bang 管理口，与 GTXCLK/RXC 无关 ⇒ `set_false_path`（或按 2.5 MHz 上限给一对 `set_max_delay`），理由要写 | Realtek RTL8211F 数据手册的 MDIO 时序（本板 PHY 就是 RTL8211F，见 `report/HOST_GUIDE.md` 第 14 行） | 同上 |
| RGMII 收口 5 个裸输入（`eth_rx_ctl`、`eth_rxd[3:0]`） | 这一路**已经**是真物理事件，别再拖：`set_input_delay -clock eth_rxc -min/-max` 按 PHY 的 DDR 窗算，中心对齐用 `-clock_fall` 那一套 | RTL8211F 手册的 RGMII RX 表（数据相对 RXC 双沿的 setup/hold ps 值）+ 板级走线延迟；本仓已实测过"RGMII 是 DDR 采样、#57 之后没有 IDELAY 采样窗可言"，所以值给得讲道理比给个大值重要 | `build/timing_roster_diff.sh` 的 D1/D3（补完约束不许把别的域挤坏）+ 名册逐域念一遍 |
| `eth_tx_*` 那一组现在的 `set_false_path` | **保留但要重新论证**：RGMII 发送是源同步（PHY 用 FPGA 给的 GTXCLK 采数据），"假路"其实是在说"我不检查芯片到 PHY 这一段" | 查 PHY 手册的 RGMII TX 窗，若能查就把它改成 `set_output_delay`（对齐到 eth_tx_clk），查不到就在注释里写"已知未验证"并留成账 | 同上 |
两个官方/权威口径支持这一步：UG949 的 timing closure 要求**每个 I/O 要么有延迟约束、要么有写明理由的豁免**；
源同步接口的约束写法见 AMD 论坛那篇《IO Timing constraints for source synchronous interface》，
入门到落地版可读 Xilinx 官方课程 Lab5 与 BLT 的《Demystifying I/O Timing Constraints》，
最小输出延迟为什么要单独算见 Abbey 那篇《Explaining Minimum Output Delays》；
RGMII 的接口行为以 AMD PG051 的 RGMII 章为准。
⚠ 这一节的 ps 数字**一个都没往 XDC 里写**——因为都要先读手册与本板走线实测（今天构建/台架在飞，
r114 第一件事就是量它们）。写形式与出处，是为了不让下一步变成"随手填个 2 ns"。

## 5. 把"别一根筋"落成工具（2026-10-03 已落地，件与对照都在盘上）
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

改前那把从报告长回来是必须的——`impl_1/*_routed.dcp` **一次构建就被覆盖**（r108 就吃过这个亏，#230），
而 `timing_summary.rpt` 每轮都归档。r112 的基线名册已落 `build/evidence/r113_before_roster.txt`
（四域八行：eth_rxc 0.445/5.56 %、clk_fpga_0 1.135/11.35 %、clkout0_1 4.467/22.34 %、sys_clk 14.463/72.31 %，
hold 0.050/0.056/0.059/0.133），与本文第 2 节的表同源同数，逐条钉住。

三把尺子各自的对照都跑过（`--self`）：roster_diff 5/5（一模一样必须绿、**非头条域**掉进违例必须红、
相对余量掉三成必须红、全域变好必须绿、名册残缺必须红）；roster_from_summary 2/2，
其中真值钉的是 eth_rxc period=**8.000 ns**（125 MHz RGMII）。
这里也各踩过一刀：diff 的对照第一次写反了 A/B（三条"该红"的绿了），转换脚本周期列取错一格
（取成波形下降沿，margin 全成两倍而三条地板照样绿）——两条都改成了**必须动**的对照，见 #258。

接线进门禁会改"门禁 N 项"那四处句子的条数 ⇒ 必须与那些句子**同一笔**改（#242/D1c 那一课），
所以这三把暂时只进链子与本文，不进门禁计数。

## 参考（官方与论坛，2026-10-03 查）
- [Timing Closure — UG949 UltraFast Design Methodology Guide](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Timing-Closure)
- [IO Timing constraints for source synchronous interface（AMD 论坛）](https://adaptivesupport.amd.com/s/question/0D52E00006hpUNiSAM/io-timing-constraints-for-source-synchronous-interface?language=en_US)
- [Demystifying I/O Timing Constraints（BLT）](https://bltinc.com/2025-05-13/demystifying-i-o-timing-constraints/)
- [Xilinx Design Constraints / FPGA Design with Vivado Lab 5（官方课程：输入输出延迟怎么给）](https://xilinx.github.io/xup_fpga_vivado_flow/lab5.html)
- [Explaining Minimum Output Delays（hold 侧为什么要单独算）](https://blog.abbey1.org.uk/index.php/technology/explaining-minimum-output-delays)
- [Clock Skew in Synchronous Interface Timing（MathWorks 源同步窗与偏斜的关系）](https://www.mathworks.com/help/signal-integrity/ug/synchronous-interface-timing.html)
- [HDMI/DVI Intra-pair and Inter-pair skew（TI E2E：TMDS 对间/对内偏斜口径）](https://e2e.ti.com/support/interface-group/interface/f/interface-forum/267205/hdmi-dvi-intra-pair-and-inter-pair-skew)
- [RGMII — PG051 Tri-Mode Ethernet MAC（官方：RGMII 收发时序行为）](https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/RGMII)
- [6.2.5 RGMII Transmit（Altera TSE 手册同一口径的对照写法）](https://docs.altera.com/r/docs/813669/26.1/triple-speed-ethernet-ip-user-guide-agilextm-3-and-agilextm-5-fpgas-and-socs/rgmii-transmit)
- [Timing Closure - Suggestions for high fanout signals（AMD 自适应支持 9410）](https://adaptivesupport.amd.com/s/article/9410)
- [Top 5 Timing Closure Techniques（Xilinx 官方 PDF）](https://www.xilinx.com/publications/prod_mktg/club_vivado/presentation-2015/paris/Xilinx-TimingClosure.pdf)
- [UltraFast Design Methodology Guide 全文 PDF（ug949）](https://www.mouser.com/pdfDocs/ug949-vivado-design-methodology.pdf)
- [Very high fanout net not being replicated by Vivado（Electronics Stack Exchange）](https://electronics.stackexchange.com/questions/472393/very-high-fanout-net-not-being-replicated-by-vivado)
- [MicroZed Chronicles: Baseline Timing Closure（第三方实践帖）](https://www.adiuvoengineering.com/post/microzed-chronicles-baseline-timing-closure)

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

## 3. 下一刀为什么不再切逻辑，以及"全局"怎么切
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
| `TIMING-9` / `TIMING-10` | 1 / 1 | "Unknown CDC logic" 与 "Missing property on synchronizer"：`ASYNC_REG` 少在一处 ⇒ 这跟今天那笔**根因**（#256：这一域根本没复位）是同一族的结构账 |
| `DPIR-1` / `LUTAR-1` | 2 / 1 | 异步驱动 / LUT 驱动异步复位：都是"复位网真不真的可靠"的问题，与 #256 同族 |
| `SYNTH-5` / `SYNTH-6` | **336 / 98** | "因为时序约束才映射成分布式 RAM"——这条我之前一直没管：它说明**BRAM/LUTRAM 的选型在被约束牵着走**（本仓库 BRAM 已经 95.5/140 tile，LUTRAM 4044 个），要单独量一次，不能当噪声 |
| 自加不确定度 | hold 侧 **0.8 ns**（`set_clock_uncertainty` 的策略） | 报出来的 WHS 0.050 是"按这个严口径"剩下的量，念数字时必须带着这句 |

## 5. 把"别一根筋"落成工具（新规矩，写在这里等着实现）
每次构建后自动出**名册差分**（不再手写"全局 WNS 从 X 到 Y"）：
```
build/tcl/probe_timing_roster.tcl   # 每域最差 3 族：起点/终点/级数/route%/最大 fo；只读，开 routed dcp
build/timing_roster_diff.sh A.txt B.txt  # 逐条对齐，任何一族变差都点名；比较次数==被对齐条数（数得出才许出结论）
```
判据三句话：①改的那族自己动了多少；②**其余三域与它们的最差族有没有变差**；③资源/拥塞（`route_status`、`utilization`）与
失败端点数。三条缺一不写首页。接线进门禁会改"门禁 N 项"那四处句子的条数 ⇒ 必须与那些句子**同一笔**改（#242/D1c 那一课）。

## 参考（官方与论坛，2026-10-03 查）
- [Timing Closure — UG949 UltraFast Design Methodology Guide](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Timing-Closure)
- [Timing Closure - Suggestions for high fanout signals（AMD 自适应支持 9410）](https://adaptivesupport.amd.com/s/article/9410)
- [Top 5 Timing Closure Techniques（Xilinx 官方 PDF）](https://www.xilinx.com/publications/prod_mktg/club_vivado/presentation-2015/paris/Xilinx-TimingClosure.pdf)
- [UltraFast Design Methodology Guide 全文 PDF（ug949）](https://www.mouser.com/pdfDocs/ug949-vivado-design-methodology.pdf)
- [Very high fanout net not being replicated by Vivado（Electronics Stack Exchange）](https://electronics.stackexchange.com/questions/472393/very-high-fanout-net-not-being-replicated-by-vivado)
- [MicroZed Chronicles: Baseline Timing Closure（第三方实践帖）](https://www.adiuvoengineering.com/post/microzed-chronicles-baseline-timing-closure)

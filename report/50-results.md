# 结果与指标

对应赛题条目"结果与指标表"与"取得可测量的性能表现，并给出与基线的对比"（逐条落点在
`report/submission-checklist.md`）。
本章**只搬运**：数值、单位、测量条件、次数/时长、证据文件五列全部照 `data/metrics.csv`
与 `build/` 盘上件的原样抄，章内不重算、四舍五入或换算单位。
派生量（比值、百分比）的公式与两个原始数在 [`comparison-notes.md`](comparison-notes.md)；
逐批次的优化过程与被否决的方案在 [`40-optimization.md`](40-optimization.md)。

## 0. 基线与可比性前置（先定这个，否则下面每一格都会被读成"提升"）

**本作品的当前发布物 = r118**，位流身份 `cd04907e1369`（`build/r118_gates.txt:3`、
`build/evidence/r118_bit_md5.txt`；板上就是这一块，见 `build/evidence/r118_board/board_now.txt`）。

**基线分两把，可比性不同**（"基线"就是用来作差的参照版本）：

| 基线 | 定义 | 指纹 | 口径 | 与当前发布物的关系 |
| --- | --- | --- | --- | --- |
| **B-main** | **第 114 批**（件名 `r114`，`build/evidence/r114_after.txt:3` 位流 `7142a1fbf082`） | 树 `top=56c269602e18 rtl=07570b1ac1b4`（`build/evidence/r114_after.txt` 与 `build/evidence/r118_tree_fp.txt` 同一枚）；名册由 `build/tcl/probe_timing_roster.tcl` 同一份生成器产出（`build/evidence/r114_after_roster_probefmt.txt`、`build/evidence/r118_after_roster_probefmt.txt`） | 约束集两份（`src/constraints/rk_zynq7020.xdc` + `src/constraints/clock_groups_impl.xdc`）；无 RGMII 输入窗；器件 `xc7z020clg484-2`（`-2 PRODUCTION`） | **同器件、同约束集、同生成器 ⇒ 可比**；比的是"同一个时钟/同一条锥自己动没动" |
| **B-early** | 2026-09-18 那一版"优化前基线" | 无位流 md5 记录 | 无逐时钟名册、无检查项数口径、约束集只有一份 XDC、`set_clock_groups` 当时未含 MMCM 生成钟、RTL 规模不同 | **不可比，仅定性**（拿跨口径的两个数相减当提升是禁止的形状，见 `report/comparison-notes.md` §3） |

**贯穿三张表的一条读法**（`build/evidence/r118_after.txt:4` 头部原文，`40-optimization.md` §1 引的是同一句）：
全局 WNS 的绝对差不算收益也不算损失；只有同域同锥的两端读数才写成"变化"。

**记录文件说明**：规划中的逐批次记录目录 `build/runs/` 还没落地（不存在），所以本表逐格指向原件路径。
已经落地的 `build/roster/`（`build/roster/roster_r118.tsv`、`build/roster/roster_r118_probe.tsv`）、
`build/parsed/`、`report/measurements.md` 与本表做过交叉核对，结果与不同源登记在
`report/comparison-notes.md` §7；`build/runs/` 落地后本表改为引用它。

## 1. 结果与指标表（照赛题表头；表头与 `data/metrics.csv` 同列）

表头：**指标名称 | 类别 | 数值 | 单位 | 测量条件 | 测试次数或时长 | 证据文件**

| 指标名称 | 类别 | 数值 | 单位 | 测量条件 | 测试次数或时长 | 证据文件 |
| --- | --- | --- | --- | --- | --- | --- |
| 器件与工具链 | 共用条件 | xc7z020clg484-2 / Vivado+Vitis 2025.2.1 | — | 全部行的共用条件；`build/utilization.rpt` 头部 `Design : system_top`、`Device : xc7z020clg484-2`、`Speed File : -2`、`Design State : Routed` | 一次声明 | `build/system.bit`、`build/utilization.rpt` 报告头 |
| 显示像素时钟 | 核心 | 50 | MHz | 面板 1024×600；H_TOTAL 1344、V_TOTAL 625 ⇒ 场频 59.5 Hz；由 PL 侧 MMCM 从 50 MHz 输入合成 | 约束一次生效 | `src/constraints/` 与 `build/timing_summary.rpt` |
| 显示分辨率与场频 | 核心 | 1024×600 @59.5 | — | 双窗输出（左窗原图 / 右窗处理图） | 连续显示 | `board/verify_r87.md` 第 1 行 |
| 全局 setup WNS | 核心 | **0.739** | ns | 失败 setup 端点 0 / 总端点 51135；板上这一版 bit `cd04907e1369`；**本版不带 RGMII 输入窗** | 一次布线后报告 | `build/r118_gates.txt:10`、`build/evidence/r118_after.txt:7` |
| 全局 setup 失败端点 | 核心 | 0 | 个 | 总端点 51135；片内路径零违例；**收口 I/O 那 5 个端点当前无输入窗 = 未检查**（未检查不等于满足） | 一次布线后报告 | `build/r118_gates.txt:11` |
| 全局 hold WHS | 核心 | **0.052** | ns | 失败 hold 端点 0 / 总端点 51135；WPWS 0.264；这一格是片内族 | 一次布线后报告 | `build/r118_gates.txt:12` |
| `eth_rxc`（8.000 ns）setup / hold | 核心（逐时钟） | 0.739 / 0.052 | ns | 名册行 `margin_pct=9.24 / 0.65`；该域 4835 端点、失败 0 | 一次布线后报告（只读开 routed dcp） | `build/evidence/r118_after_roster_probefmt.txt` 第 5–6 行 |
| `clk_fpga_0`（10.000 ns）setup / hold | 核心（逐时钟） | 1.850 / 0.053 | ns | `margin_pct=18.50 / 0.53`；15721 端点；setup 那格 route **93.584 %**、1 级 LUT6 | 同上 | 同上 第 1–2 行 |
| `clkout0_1`（20.000 ns）setup / hold | 核心（逐时钟） | 3.630 / 0.059 | ns | `margin_pct=18.15 / 0.29`；30179 端点；setup 那格 21 级（含 9×CARRY4） | 同上 | 同上 第 13–14 行 |
| `sys_clk`（20.000 ns）setup / hold | 核心（逐时钟） | 14.876 / 0.222 | ns | `margin_pct=74.38 / 1.11`；323 端点 | 同上 | 同上 第 3–4 行 |
| `clkfbout`/`clkfbout_1`/`clkout1_1`/`clkout2` | 核心（逐时钟） | `NOWRITE` / `NA` | — | 名册里这两族没有同沿路径行；**"NA"不等于"这一族没问题"** | 同上 | 同上 第 7–12、15–16 行；读法写在 `report/timing/debt_ledger.md` §1 |
| 跨域两行 `sys_clk↔clkout0_1` | 核心 | setup 3.695 / hold 0.200（231 端点）；setup 14.757 / hold 0.165（19 端点） | ns | `build/timing_summary.rpt` 的 Inter Clock Table 里就这两对；其余跨域对被 `set_clock_groups -asynchronous` 整组排除 | 一次布线后报告 | `report/05-timing.md` §2（引同一件） |
| Slice LUT 占用 | 资源 | 14154（26.61 %） | 个 | 实现后 Routed 报告 | 一次构建 | `build/utilization.rpt:35` |
| Slice 寄存器占用 | 资源 | 8188（7.70 %） | 个 | 同上 | 一次构建 | `build/utilization.rpt:40` |
| Block RAM Tile 占用 | 资源 | 95.5 / 140（68.21 %） | tile | = RAMB36/FIFO 93（66.43 %）+ RAMB18 5（1.79 %）×0.5；帧缓存由 64-bit 宽 + 乒乓两块拼出 | 一次构建 | `build/utilization.rpt:106,107,109` |
| DSP48 占用 | 资源 | 19 / 220（8.64 %） | 个 | 用在缩放/旋转的坐标乘法与 gamma 计算 | 一次构建 | `build/utilization.rpt:121` |
| LUT as Memory（分布式 RAM） | 资源 | 4185（24.05 %） | 个 | 与 `report_methodology` 的 SYNTH-5 = 336 条同源（"因为时序约束才映射成分布式 RAM"） | 一次构建 | `build/utilization.rpt:37`；`build/methodology.rpt:32` |
| BUFGCTRL / MMCME2_ADV / Bonded IOB / IDELAYE2 | 资源 | 8/32（25.00 %）/ 2/4（50.00 %）/ 27/200（13.50 %）/ 5（2.50 %） | 个 | 同一份 Routed 报告 | 一次构建 | `build/utilization.rpt:161` 等；逐行原文见 `report/04-resources.md` 占用表 |
| 整屏逐像素判据（当前件） | 核心 | **^PASS 161 行、^FAIL 1 行**，判定 `RESULT tb_v98_top_seam FAIL nfail=1` | 条 | 头部 `top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4`；唯一那条 FAIL 是公开声明保留的 `C5c`（#98） | 一次台架 | `build/tb_v98_report.txt:1,199`；`report/known_issues.md` §一 第 1 条 |
| 发布前检查（当前件） | 自检 | **判定 24 项 / 未判 0 项；23 通过 / 1 未通过** | 项 | 未通过的那一项 = 顶层台架里声明过的 `C5c`；两跑逐字节一致 | 每批构建后一次，两跑 | `build/r118_gates.txt:53`、`build/evidence/r118_board/g2c.txt`、`build/evidence/r118_board/g3c.txt`、`build/evidence/r118_board/gatesc_summary.txt`（`GATESC done id=identical green=23 red=1`） |
| 实现后动态功耗 | 资源 | 2.213 | W | `Dynamic (W)` 那一行；片上合计 2.391 W 在同一份报告；工具置信度 **Low**（无仿真活动文件输入） | 一次构建 | `build/power.rpt:36,33,41` |
| 结温（工具估算） | 资源 | 52.6 | ℃ | Ambient 25.0 ℃、`Max Ambient (C) 57.4`；**这是估算，不是板上读数** | 一次构建 | `build/power.rpt:40,39,127` |
| 板级复验 | 实测 | `RESULT board_verify PASS（判红的步骤：0）`；geom `ok=10 fail=0`；串口电池 105 条命令 | — | 2026-10-04 那一次；命令带 `--round=r118` 批次标签 | 一次上板 | `build/evidence/r118_board/board_verify_console.txt` |
| 人眼判据 E6（上电那一度） | 验收 | 读 **0**（队员原话「0度」） | — | 断电 ≥10 s 冷上电 + 只跑三步 JTAG 链 + 全程不碰 KEY1/KEY2，看屏第二行 `ROT:` | 一次 | `build/evidence/r118_eyes/`（`state.txt`、`step1_boot.txt`、`step2_program_pl.txt`、`step3_app.txt`、`uart_stat.txt`） |

**这一格里没有填的东西**（`data/metrics.csv` 自己就这么写的，本章不代填）：
端到端时延那一行有两格——第 20 行标"未报/—/待复测"，第 25 行标 33.34 ms（一轮 600 帧）；
两者同表并列时**不许把 33.34 当成当前这一版的复核值**（第 20 行明写"本表不填没有复核过的数"）。

## 2. 优化前后对比表（同口径那把：B-main 第 114 批 → 发布物第 118 批）

这一张表的诚实形状是：**这一版把片内名册保持成与基线逐位相同，收益落在片外那一侧**。
把它写成"WNS 提升了 X"就是把账记反（`report/timing/round_r118.md` §一末：
τ 只动 I/O 单元抽头 ⇒ 判据不能写成 WNS 变好）。

| 指标 | 基线第 114 批（`7142a1fbf082`） | 发布物第 118 批（`cd04907e1369`） | 差 | 口径 | 证据 |
| --- | --- | --- | --- | --- | --- |
| `eth_rxc` setup / hold | 0.739 / 0.052 ns | 0.739 / 0.052 ns | **+0.000 / +0.000（SAME）** | 同器件、同约束集、同生成器 | `build/evidence/r118_strict_b1.txt` 第 5–6 行 |
| `clk_fpga_0` setup / hold | 1.850 / 0.053 ns | 1.850 / 0.053 ns | +0.000 / +0.000（SAME） | 同上 | 同上 第 1–2 行 |
| `clkout0_1` setup / hold | 3.630 / 0.059 ns | 3.630 / 0.059 ns | +0.000 / +0.000（SAME） | 同上 | 同上 第 3–4 行 |
| `sys_clk` setup / hold | 14.876 / 0.222 ns | 14.876 / 0.222 ns | +0.000 / +0.000（SAME） | 同上 | 同上 第 7–8 行 |
| 严格名册判定 | — | `B1 pairs_compared=8 losses=0 verdict=GREEN` | — | 判定条件 B1 事先登记在 `build/r118_chain.sh` 头部（"任何一格相对第 114 批不许变小"） | `build/evidence/r118_strict_b1.txt:9`；`build/r118_verdict.txt` |
| 宽松名册判定（另一套标准） | — | `ROSTERDIFF D3_margin_cost big_loss=0 … result=GREEN`（16 对） | — | D3 的门槛是"掉 25 % 以上的域数"；两套标准门槛不一致这件事记在 #328 | `build/r118_verdict.txt` 末行；`build/evidence/r118_roster_diff_vs_r114.txt:20,24` |
| Slice LUT / FF / BRAM / DSP | 14154 / 8188 / 95.5 / 19 | 14154 / 8188 / 95.5 / 19（B3 判资源中性） | 逐字相同 | 同一份 Routed 报告口径 | `build/utilization.rpt:35,40,106,121`；`build/r114_gates.txt` 同类行 |
| 全局 WNS / WHS | 0.739 / 0.052 | 0.739 / 0.052 | +0.000 | **绝对差本身既不算收益也不算损失** | `build/r114_gates.txt`、`build/r118_gates.txt:10,12` |
| 失败 setup / hold 端点 | 0 / 0（51135） | 0 / 0（51135） | 0 | 同一次构建的两个计数 | `build/r118_gates.txt:11,13` |
| `report_methodology` | 446 / 7 类 | **446 / 7 类**（撤窗后的诚实读数） | 0 | 同一份报告口径（`report_methodology` SUMMARY 表，只从表里取数） | `build/methodology.rpt:26,30-36` |
| 未约束端口（`check_timing` HIGH 两类之和） | 11（输入 5 + 输出 6） | 11（本版未绑窗 ⇒ 回到基线值） | 0 | 端口对象单位；**与 `TIMING-18` 的 7 条不同量纲，永不相减** | `report/timing/roster_baseline.tsv` 第 2–3 行口径注释；`report/timing/debt_ledger.md` §2/§6 |
| 板级 `board_verify` | 通过（未通过步骤 0，第 114 批那一次） | 通过（未通过步骤 0，geom 10/0、105 条命令） | 两条独立证据链 | 同一脚本、同一批次标签约定（不给 `--round` 就判未通过而不写文件） | `report/log/issues.md` #294；`build/evidence/r118_board/board_verify_console.txt` |
| **片外那一侧（本版真正的收益）** | `IDELAY_VALUE=26`：带窗口径下最差 hold 档 **−1.185 ns** | `IDELAY_VALUE=31`：同一份已布线 DCP、同一套读数 **−0.870 ns** | **+0.315 ns**（两数相减，公式见 `report/comparison-notes.md` §1） | 警告 两条读数都带 `Slack (VIOLATED)` ⇒ 诚实写法是"最差那一档从 −1.185 抬到 −0.870"，**不是** "+0.315 ns 时序收益"；且本版不加载那把窗 ⇒ 这 0.315 落在当前没有被约束建模的接口上 | 件：`build/evidence/r115_window/probe3_console.txt` 第 170 行（`W3S tap26 HOLD Slack (VIOLATED) : -1.185ns`）与第 188 行（`W3S tap31 HOLD … -0.870ns`）；登记行 `report/timing/cut_ledger.tsv` C8；口径与限定句在 `report/05-timing.md` §4 与 `report/timing/round_r118.md` §一 |

**同口径的另一组对照（被否决的那一版，留在表里不删）**：第 117 批（τ=31 + C9 强制复制 239 引脚网）
相对第 114 批是 `clk_fpga_0` setup 1.850→**2.104**（赢），而 `clkout0_1` 3.630→3.353、
`sys_clk` 14.876→14.815、`eth_rxc` 0.739→0.615、`eth_rxc` hold 0.052→0.044 四格跌 ⇒
严格判定条件不过、按事先约定的规则 H7 回滚（`build/r117_verdict_declined.txt`、
`build/evidence/r117_roster_diff_vs_r114.txt`）。回滚的那一版没进发布物，但它的数是有件的读数。

## 3. 优化前后对比表（长程轨迹；**跨口径 ⇒ 不可比，仅定性**）

下面每一行都只列**那一批自己的件里的数**，行与行之间不相连：约束集、检查项数、
功能规模在同期都在变（`report/optimization_log.md` 第 596 行明写
"第 62 批到第 63b 批之间加的是新数据通路，LUT/BRAM 的增量是功能的代价，不是优化的结果"）。
所以这张表**不能读成收益曲线，也不能读成"越优化越差"**。

| 批次 | 这一批的可核查记录 | WNS (ns) | 失败 setup 端点 | WHS (ns) | BRAM (tile/%) | Slice LUT | Slice 寄存器 | DSP | 动态 (W) | 检查口径 | 证据 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-09-18 前 | 异步组未含 MMCM 生成钟 + `sync_fifo` 异步复位 | 逐域：clk_fpga_0 +2.077 / eth_rxc +0.214 / sys_clk +14.897 | 跨域 `eth_rxc→clkout0_1` **−6.748 FAIL（假跨钟）** | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | 那时还没有发布前检查 | `report/optimization_log.md` 第 13–18 行 |
| 2026-09-18 后 | 约束 + RTL 两批改动（详见 `40-optimization.md` §2 第 2 行） | 逐域 +0.865 / +0.111 / +14.445 / clkout0_1 +1.882；全设计"约束全满足" | 0 | NOT_MEASURED | 83（59.29 %） | 10621（19.96 %） | 20253（19.03 %） | 13（5.91 %） | 2.071（总 2.240） | 那时还没有发布前检查 | `report/optimization_log.md` 第 57–76 行 |
| 第 62 批（`r62`） | V9 几何参数化上板 | +0.792 | 0 | +0.001 | 96 / 68.57 % | 12958（24.36 %） | 9491 | NOT_MEASURED | 2.201 | 早期文件名形如 `build/gates_r62.txt`，项数与今日不同口径 | `report/optimization_log.md` 第 586 行 |
| 第 63b 批 | 双线性读口接入（功能） | +0.918 | 0 | +0.052 | 97 / 69.29 % | 14116（26.53 %） | 9856 | NOT_MEASURED | 2.204 | 同上 | `report/optimization_log.md` 第 587 行 |
| 第 75 批 | OSD 字格几何挪一拍（#96）；**最近一次检查全通过且已成套留档** | +0.287 | 0 | +0.041 | 97.5 / 69.64 % | 14776（27.77 %） | 10018 | NOT_MEASURED | 2.209 | `build/r75_gates.txt` | `report/optimization_log.md` 第 588 行 |
| 第 84 批 | 回滚 `max_fanout`，两处改动的贡献分开 | **−0.094** | **16** | +0.056 | 95 / 67.86 % | 14360（26.99 %） | 8073 | NOT_MEASURED | 2.205 | `build/r84_gates.txt` | `report/optimization_log.md` 第 589 行 |
| 第 86 批 | 诊断计数器使能改喂寄存过的事件（#124） | −0.135 | **2**（16→2 才是这一处的账） | +0.053 | 95 / 67.86 % | 14358（26.99 %） | 8075 | NOT_MEASURED | 2.205 | `build/r86_gates_final.txt` | `report/optimization_log.md` 第 590 行 |
| 第 88 批 | `dc_fifo` 满判据改用当前写指针 | +0.516 | 0 | +0.051 | 95 / 67.86 % | 14358（26.99 %） | 8075 | NOT_MEASURED | 2.205 | 18 项判定 + **2 项未判 ⇒ `PARTIAL`**（#141） | `report/optimization_log.md` 第 592 行；`build/r88_gates_partial.txt` |
| 第 92 批 | #57：IDDR 改吃 BUFG、`IDELAY_VALUE` 15→26 | +0.522（仍 `eth_rxc`） | 0 / 50885 | +0.037 | 95 | 14351 | 8075 | **19** | NOT_MEASURED | 20 项 / 1 项未通过（`C5c`） | `report/optimization_log.md` 第 715–726 行 |
| 第 94 批 | 几何两处（#104 小数位、#93 旋转态钳进 fit） | 0.553 | 0 / 50883 | 0.049 | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | 20 项 / 1 项未通过 | `report/optimization_log.md` 第 785–800 行；`build/r94_gates.txt`（`#179` 补件那一次） |
| 第 99 批 | 五处（#209/#128/#185/#186/#188/#201） | +0.284 | 0 / 50867 | +0.051 | 95 | 14330 | 8078 | 19 | 2.213 | 19 通过 / 1 未通过（同一条 `C5c`） | `report/optimization_log.md` 第 958–966 行 |
| 第 103 批 | `zoom_mapper` #189（全在组合逻辑里） | +0.608 | 0 / 50868 | +0.053 | 95 / 67.86 % | 14333（26.94 %） | **8079（与上一版触发器一字未动那一版相同）** | NOT_MEASURED（第 99、97 批那两版记的是 19） | 2.212 | 20 项判定（`build/r103_gates.txt:48` 念"判定 20 项"） | `report/optimization_log.md` 第 1004–1035 行；`build/r103_gates.txt:10,12,14,15,16` |
| 第 104 批 | **#141**：`icmp_tx` 三处 16 位减法提前一拍寄存 | 0.812 | 0 / 50948 | 0.053 | 95 / 67.86 % | 14334（26.94 %） | **8127（+48，这一处的全部代价）** | NOT_MEASURED | 2.211 | 22 项（`build/r104_gates.txt`） | `build/r104_gates.txt:10,12,14,15,16,17`；`report/optimization_log.md` 第 1041–1052 行 |
| 第 106 批 | 收包链那一处（`udp_off+8`／`+len-1` 提前一拍） | 0.723 | 0 | 0.051 | 95 / 67.86 % | 14323（26.92 %，比第 104 批 −11） | 8149（+22） | NOT_MEASURED | 2.214 | 22 项 / 1 项未通过 | `build/r106_gates.txt:10,12,14,15,16,17` |
| 第 107 批 | 行覆盖位图分 5 组降广播 | 0.725（**换主人**，不是变好；目标族同端点对 0.723→2.006） | 0 | 0.050 | 95 / 67.86 % | 14323（与第 106 批逐字相同） | 8156（+7） | 19 | 2.213 | 22 项 / 1 项未通过 | `report/log/issues.md` #230；`build/r107_gates.txt` |
| 第 108 批 | IP 首部校验和摊成两拍各 5 项 | 0.721 | 0 | **0.035（这一处付的 hold）** | 95 / 67.86 % | 14360（26.99 %） | 8168 | NOT_MEASURED | 2.212 | 22 项 / 1 项未通过 | `report/log/issues.md` #231；`build/r108_gates.txt:10,12,14,15,16,17` |
| 第 109 批 | `osd_overlay` 选中格提前一拍寄存（`clkout0_1` 23→21 级） | 0.605 | 0 | 0.049 | **95.5 / 68.21 %** | 14362（27.00 %） | 8162（−6） | NOT_MEASURED | 2.214 | 24 项（这一批**不采纳**） | `report/log/issues.md` #234；`build/r109_gates.txt:10,12,14,15,16,17` |
| 第 110 批 | 改动 4① 独热化（`fo=316` 那根网消失） | 0.713 | 0 | 0.042 | 95.5 / 68.21 % | **14119（−243，归不到模块）** | 8154（−8） | NOT_MEASURED | 2.214 | 24 项 = 21 通过 / 3 未通过（"还没采纳"的正常形状） | `report/log/issues.md` #246；`build/r110_gates.txt:10,12,14,15,16,17` |
| 第 112 批 | 两处：`key_debounce` 武装门 + 校验和累加器 32→20 位 | 0.445（归属换族；同轮净账 **+26 LUT / +34 FF**） | 0 / 51135 | 0.050 | 95.5 / 68.21 % | 14154（+35） | 8188（+34） | NOT_MEASURED | 2.213 | 24 项 | `report/log/issues.md` #250/#254；`build/evidence/r112_verdict.txt`；`build/r112_gates.txt:10,12,14,15,16,17` |
| 第 113 批 | `hb_gone` 声明上电初值 | 0.445（**八对逐位相同 ⇒ 时序中性**） | 0 / 51135 | 0.050 | 95.5 / 68.21 % | 14154 | 8188 | NOT_MEASURED | 2.213 | 24 项 | `report/timing_global.md` §2b；`build/r113_gates.txt:10,12,14,15,16,17` |
| **第 114 批 = B-main** | `dc_fifo` 格雷码 `ASYNC_REG` + 初值 | 0.739 | 0 / 51135 | 0.052 | 95.5 / 68.21 % | 14154 | 8188 | 19 | 2.213 | **24 项 = 23 通过 / 1 未通过**，两跑逐字节一致 | `report/log/issues.md` #294；`build/r114_gates.txt` |
| 第 116 批（带窗那一版，未采纳） | RGMII 输入窗 + τ=31 | **−0.846**（5 个 I/O 端点第一次被检查） | **5** | **−0.870** | 95.5 / 68.21 % | 14154 | 8188 | NOT_MEASURED | 2.213 | 24 项，四条发布硬项未通过 | `build/r116_gates.txt:10-17`；`report/timing/roster_round116.tsv` |
| **第 118 批 = 发布物** | 只带 τ=31 | 0.739（**与第 114 批逐位相同**） | 0 / 51135 | 0.052 | 95.5 / 68.21 % | 14154 | 8188 | 19 | 2.213 | 24 项 = 23 通过 / 1 未通过（唯一未通过 = 声明过的 `C5c`） | `build/r118_gates.txt:10-17,53`；`build/utilization.rpt` |

**这张表不能读成曲线的三条原因**（`report/optimization_log.md` 第 594–612 行，一条都不省）：
1. 行与行之间不只有优化：新增功能（第 63b 批的双线性读口、第 99 批的 `shown_rate`）的 LUT/FF/BRAM 增量是**功能代价**。
2. WNS 的绝对值差不是收益也不是损失：等价源码两次构建之间实测摆过 0.4 ns 量级（该节的原话），
   而第 105 批那次"同一棵钟树重复试跑"量到的读数是 **0.000**（`build/evidence/r105_ab_rolls.txt` 第 37 行），
   两个数的适用范围不同 ⇒ 不许拿前者去否掉后者，也不许拿后者去支持"任何绝对差都是真的"。
3. 失败端点数与 WNS 要一起看：第 84 批的 −0.094/16 端点与第 86 批的 −0.135/2 端点，
   只看 WNS 一列会把"锥被切开、最差位换人"误读成整体恶化。

## 4. 次要指标表

| 指标 | 数值 | 单位 | 条件与适用范围 | 证据 |
| --- | --- | --- | --- | --- |
| SD 本地播放帧率 | 29.8 – 30.0 | fps | 512×300 RGB565 预转换帧序列（板上不做解码）；100 帧滑窗；串口 115200-8N1；两个滑窗样本 | `data/metrics.csv` 第 12 行 → `build/evidence/r87_boot_stat_drain.txt` |
| UDP 入口负载（**口径不是实测带宽**） | 9.2 | MB/s | 512×300×2 B × 30 fps 的计算值（≈74 Mbps）；实测吞吐的读数出口在 OSD 第三行与 lane23 回读 | `data/metrics.csv` 第 13 行；`report/perf_report.md` |
| ETH 入流零丢包（演示工况） | 0 | 丢帧/坏帧 | 512×300、限速 15 MB/s、目标 30 fps；PL 侧收包链自己数的；600 帧一轮，实测帧率 30.007 fps | `data/metrics.csv` 第 22 行；`report/perf_report.md` |
| ETH 入流 300 秒长跑 | 0 | 丢帧/坏帧/重复帧 | 同工况连续 300 s；实测 29.99 fps、帧间隔平均 33.34 ms；9000 帧 | `data/metrics.csv` 第 23 行 |
| 入流过载点 | ≥116.7 | fps | 不限速、目标 120 fps 时仍未丢字（≈36 MB/s、287 Mbps）；**这一版没顶到丢字那一点 ⇒ 不给"PL 能扛多少 fps"** | `data/metrics.csv` 第 24 行 |
| 端到端时延（一轮 600 帧） | 33.34（min/avg/max 20 / 33.34 / 51） | ms | 起点=上位机发送时刻、终点=示相机位录到上屏；同轮墙钟交付 29.79 fps；**与第 1 张表里"未报/待复测"那一格并列时不给当前这一版借用** | `data/metrics.csv` 第 20、25 行 |
| 帧间隔抖动 | 33.33（min/avg/max 22 / 33.33 / 45） | ms | 30 fps 限速工况；抖动上界来自显示扫描与读口调度 | `data/metrics.csv` 第 26 行 |
| 第 116 批带流读数（真实流量，非线速） | `drop_words=0`、`pkt_err=0`、`frames_bad=1` 不增长，两个读数一致 | — | 512×300@60 ≈ **147 Mbps**、50 s / 3001 帧 / 66.3 万包；警告 **147 Mbps 不等于 1000M 线速**，这条只证"真实流量下不丢字"；`frames_bad=1` 的归属已由回刷第 114 批的改前/改后对照查清（四读数逐格相同） | `report/timing/round_r116.md` §三 V6 与"V6 的两条未定"第 0 条；`build/evidence/r116_board/health_*.json` |
| 第 118 批带流读数 | `drop_words=0`（两次，`eth_live=1 owner_eth=1`） | — | **同一次摘要里 `pkt_err=? frames_bad=? drop_seen=?` 三格没读出来 ⇒ NOT_MEASURED**，不许写成 0，也不许拿上一版的两次读数替它答 | `build/evidence/r118_board/bitcycle_console.txt`；`report/log/issues.md` #318；`report/06-validation.md` §4 |
| 越界读写的机会计数 | 190464 | 拍 | OSD 字模索引在 1024×600 有效区整屏走一遍时越出数组上界的拍数；这道"最少触发次数"让"屏上没现象"与"真的被门住了"可区分 | `data/metrics.csv` 第 17 行；`build/evidence/r86_osd_t18_teeth_addr.txt` |
| 缩放范围 | 0.25 – 2.00（八档） | 倍 | `ZOOM_X100 = 25 33 50 75 100 133 150 200`；手动/自动呼吸/Fit 三种来源，倍率与来源都可从 lane23 回读 | `data/metrics.csv` 第 18 行；`board/verify_r87.md` |
| 片源与仲裁 | 3 路 + AUTO | — | ETH（PL 硬件收包链）/ SD（PS 读裸帧）/ TEST（自研动态图卡）；拔线与拔卡都已在板上复验 | `data/metrics.csv` 第 19 行 |
| 片上结温（板读 XADC） | 当前版：**60.65 – 60.85**；第 113 批：61.2 – 61.7（`data/metrics.csv` 第 29 行原样） | ℃ | 警告 **两个版本、两种工况**：当前版那两条取自 `build/evidence/r118_serial_raw.txt`（`[TEMP] degC=60.65 …` 与 `… 60.85 …`），而 `report/measurements.md` §1 明写那一次是**空闲态**（`uart_stat.txt` 的 `frames=4398` 两次不变）⇒ 不是满载结温；第 113 批那一行带的是 `bash build/board_verify.sh --geom --battery` 负载。**区间都是被跟踪原始回显的极值，不是精度声明**；跨批次/跨工况不相减（`report/comparison-notes.md` N7） | `build/evidence/r118_serial_raw.txt`；`build/evidence/r113_temp_lines.txt`、`build/evidence/r113_serial_raw.txt`；`report/measurements.md` §1 |
| 变异对照分支 | 5 | 条 | `build/sim/mut_control.sh`：一次变异只许让它声称要抓的那一条判为未通过 | `data/metrics.csv` 第 16 行 |
| 人眼判据（验收表） | 36 | 行 | 全功能上板验收表；屏幕现象只能由人判，机器判据不冒充眼睛 | `data/metrics.csv` 第 21 行；`board/verify_r87.md` |
| 当前版眼睛判过的两格 | E6 读 **0**；E4 原话「现在屏幕没问题了四角都在屏幕内」 | — | E6 的**对照那一半仍未做**（按住 KEY1 应读 1），表里登记为"未判"；E1/E2/E3 的点头分属第 92、93、103 批 ⇒ 不给当前这一版借用 | `build/evidence/r118_eyes/`；`report/06-validation.md` §5；`board/acceptance.md` |
| `ASYNC_REG` 落地计数（结构指标，不是时序指标） | `u_cdc` 下带属性 FF **0 → 56** 颗（84 颗触发器型里） | 颗 | 警告 这条**不能**拿 `report_methodology` 的 TIMING-10 计数当替代：落地后 TIMING-10 仍是 1（#290）；可长期依赖的读数是 `report_cdc -details`，它点名到具体那对触发器 | `report/timing/debt_ledger.md` §4；`build/evidence/r114_async_netlist_pre_console.txt`、`build/evidence/r114_async_reg_post.txt` |
| `report_methodology` 明细 | `Checks found: 446` = DPIR-1 2 + LUTAR-1 1 + SYNTH-5 336 + SYNTH-6 98 + TIMING-9 1 + TIMING-10 1 + TIMING-18 7 | 条 | 七项相加必须等于报告自己念的那个数；只从 SUMMARY 表取数（`grep -o` 全文扫会把每类多算一次，#263/#264/#267 三天里踩过同一个坑三次） | `build/methodology.rpt:26,30-36` |
| 读数噪声（这套读数的分辨率） | `noise_ns = 0.000` | ns | 只对"同一份 `opt.dcp` 的隔离试跑"成立（B4 标定）；跨构建不适用 | `report/log/issues.md` #297；`build/evidence/r115_noise_verdict.txt` |

## 5. 这张表里没有填的东西（以及为什么空着）

| 空格 | 状态 | 原因 |
| --- | --- | --- |
| 逐实例 BRAM/DSP 归属（当前版） | **NOT_MEASURED**（`report/04-resources.md` 写的是【未实测】） | `build/utilization.rpt` 只给合计 95.5 tile / 19 DSP，不带实例层次；分层件 `build/util_hier.rpt` 是更旧一批的产物，未与本报告同批重生成 ⇒ 不当当前值念 |
| 实测入口吞吐（MB/s） | NOT_MEASURED | `data/metrics.csv` 里没有哪一行直接写"实测 MB/s"（第 13 行是负载口径、第 22/23 行是帧率与丢帧计数） |
| 收口 I/O 那 5 个端点的**板级真实差额** | NOT_MEASURED | 当前版没有窗 ⇒ 静态时序分析不检查；窗模型自身还有 `TskewR` 混行风险 ⇒ 不许写"板上真实 hold 差额就是 −0.870" |
| 输出侧 6 个端口（`led[0..1]`、`tmds_clk_p`、`tmds_data_p[0..2]`）的对外窗 | 欠账仍在 | 2026-10-04 那条追加节纠正方向（本作品是 **Source**，对应 HDMI CTS 的 TP1 源端眼图而不是接收窗）；同日晚些时候取到数（互对偏斜 max 0.20 `Tcharacter` ⇒ 50 MHz 档半窗 ±4.000 ns）后仍欠**一次带窗量名册的构建**；候选件默认不加载（`VP_R119_TMDS_WINDOW=1`）。逐条可引用性判定在 `report/io/hdmi_cts_source_window.md` |
| 1000M 线速下的零丢包 | NOT_MEASURED | 第 116 批那次带流是 147 Mbps（源是 512×300 的帧率上限），没把 RX 打到线速 |
| 当前版的 `pkt_err` / `frames_bad` / `drop_seen` | NOT_MEASURED（件里显式打 `?`） | `report/log/issues.md` #318 把"读不出来的字段"显式化；不许写 0、不许借用上一版 |

## 6. 与既有章节的口径一致性

| 引用的数 | 本表 | 既有章节 | 判定 |
| --- | --- | --- | --- |
| 0.739 / 0.052 / 14154 / 8188 / 95.5 / 19 / 2.213 W | §1、§2 | `report/04-resources.md`、`report/05-timing.md` §2、`data/metrics.csv` 第 5–11 行 | 一致（同一批件） |
| 名册 8 对逐位相同 | §2 | `report/05-timing.md` §3、`report/timing/round_r118.md` §四 | 一致（同一件 `build/evidence/r118_strict_b1.txt`） |
| 检查 24 项 / 23 通过 1 未通过 | §1、§3 | `report/06-validation.md` §3、`report/timing/round_r118.md` §五 | 一致；但与 `data/metrics.csv` 第 14 行的"22 项"**不同值** ⇒ 已登记为差异 D1，以检查件为准 |
| 整屏逐像素判据 161/1 | §1 | `report/06-validation.md` §2（同一件同一次 `grep -c`） | 一致；与 `data/metrics.csv` 第 15 行的"141 条"**不同值** ⇒ 差异 D2（不同源、跨批次不可比） |
| 其余几笔不同值（"3 类 vs 7 类"、第 117 批位流身份、`Max Ambient` 57.4/57.5） | §3、§2 | 见 `40-optimization.md` §8 差异清单 D3/D5/D6 | 全部以证据文件为准，未自行取舍 |
| 与 `build/roster/roster_r118.tsv`、`report/measurements.md` 的交叉核对 | §1、§2 | 八格名册 `diff` 给 `rc=0`（逐字节相同）；指标行数值全同；唯一新登记的是 `build/power.rpt` **行号漂移 1 行**（值相同） | 判定条件 5 对这两样成立；对仍缺失的 `build/runs/` 为 `NOT_MEASURED`。命令与输出贴 `report/comparison-notes.md` §7（D7） |

## 7. 本章依据的产物

`data/metrics.csv`、`build/utilization.rpt`、`build/timing_summary.rpt`、`build/methodology.rpt`、
`build/power.rpt`、`build/clock_util.rpt`、`build/cdc.rpt`、`build/tb_v98_report.txt`、
`build/{r103,r104,r106,r107,r108,r109,r110,r112,r113,r114,r116,r117,r118}_gates.txt`、
`build/evidence/`（`r105_ab_rolls.txt`、`r112_verdict.txt`、`r114_after.txt`、`r114_after_roster_probefmt.txt`、
`r115_noise_verdict.txt`、`r115_window/probe3_console.txt`、`r116_after.txt`、`r116_board/`、
`r117_after.txt`、`r117_after_roster_probefmt.txt`、`r117_bit_md5.txt`、`r118_after.txt`、
`r118_after_roster_probefmt.txt`、`r118_strict_b1.txt`、`r118_bit_md5.txt`、
`r118_board/`、`r118_eyes/`、`r113_temp_lines.txt`、`r113_serial_raw.txt`、
`r114_async_netlist_pre_console.txt`、`r114_async_reg_post.txt`）、
`build/r117_verdict_declined.txt`、`build/r118_verdict.txt`、`build/r118_chain.sh`、
`build/roster/roster_r118.tsv`、`build/tcl/probe_timing_roster.tcl`、
`report/timing/roster_baseline.tsv`、`report/timing/roster_round116.tsv`、
`report/timing/cut_ledger.tsv`、`report/timing/debt_ledger.md`、`report/timing/round_r116.md`、
`report/timing/round_r118.md`、`report/timing/round_r117.md`、
`report/optimization_log.md`、`report/timing_global.md`、`report/perf_report.md`、`report/known_issues.md`、
`report/comparison-notes.md`、`report/log/issues.md`、`report/04-resources.md`、`report/05-timing.md`、
`report/06-validation.md`、`report/submission-checklist.md`、
`board/verify_r87.md`、`board/acceptance.md`、`src/constraints/rk_zynq7020.xdc`。

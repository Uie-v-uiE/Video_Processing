# 实测指标表（P16c）

## 0. 口径声明（先读这三句再用这张表）

1. **表头的出处**：`指标名称 / 类别 / 数值 / 单位 / 测量条件 / 测试次数或时长 / 证据文件` 这七列的名字与列序
   **逐字照赛题 §3.2.5.2 那张"表头可直接套用"的汇总表**。本仓库里对这一条的引用落在两处，都可复核：
   `report/log/contest_checklist.md:140`（"按 `§3.2.5.2` 那张'表头可直接套用'的汇总表格式建 `data/metrics.csv`（列：指标名称 / 类别 / 数值 / 单位 / 测量条件 / 测试次数·时长 / 证据文件）"）
   与 `data/metrics.csv:1`（CSV 表头逐字行，与上面那七列逐字相同）。
   **列名列序不改**；本表只是把它排成 Markdown 并逐轮全列，机器可读的那一份仍是 `data/metrics.csv`。
2. **本包按更严自证**（比条文多的四条，每条都有可判的形态）：
   ① 每行"证据文件"必须**此刻真实存在**，逐个 `test -f`，命中率在第 3 节打印；指到目录 = 0 容忍。
   ② 同一指标**换过版本就全部列出**（含更差的那几轮），不许只挑最好的一行。
   ③ **"计数器 = 0"的板侧读数必须同一份读数里带 `eth_live=1`**，否则数值填 `—`、类别填"未报"
     （出处 `report/log/issues.md:12782` 的 #316 规矩①）。
   ④ 每个数旁边写清**它是哪一轮构建/哪一次板级会话**的读数；跨轮相减得来的差只念不判（出处 `board/acceptance.md:24` 的"规矩 35"）。
3. **本表不改 `data/metrics.csv`**（禁区）。需要引它的数值时**逐字引 + 注明出处行的行号**，
   并且每次引用前后各跑一次那条尺子（第 6 节），确认没有把它的红带出来。

**测量条件那一列的六个要素**（当时抄自旧包模板 `report-forms/metrics-table.md` 的"测量条件必填，六件齐全"那一行；那份模板在 2026-10-04 c7b325f 重建技能包时没保留、**现不存在**，只报数不指路，六项逐字列在下面这行）：
①硬件型号 ②数值精度/定点位宽 ③输入规格（分辨率/帧率/负载）④软件版本 ⑤FPGA 时钟频率 ⑥功耗模式。
缺任何一项就写 `【待补】`，并在同一格里说明"缺它这行数字不能和谁比"。

共用条件（下面所有行的默认取值，逐行只写与它不同的地方）：
**①硬件** `xc7z020clg484-2`（Zynq-7020 CLG484 速度等级 2；`build/power.rpt:9` 的 `| Device : xc7z020clg484-2 |` 回读）；
**④软件** Vivado + Vitis `2025.2.1`（`build/power.rpt:3` 的 `Tool Version : Vivado v.2025.2.1 (win64) Build 6403652`；`board/acceptance.md:8` 的版本句）；
**⑤时钟** 显示域 `clkout0_1` 50 MHz / 处理域 `clk_fpga_0` 100 MHz / 收包域 `eth_rxc` 125 MHz / 板输入 `sys_clk` 50 MHz
（逐时钟周期取自 `build/timing_summary.rpt` 的 Clock Summary，由 `node src/host/metric_recheck.mjs` 读回，
我今天那一跑打印 `周期[eth_rxc] 首页=8 报告=8`，件 `build/evidence/p16c/metric_recheck_before.txt:16`）；
**⑥功耗模式** 板上没有 DVFS / 低功耗档，PS 上电 + PL 由 JTAG 供电后就是唯一一种状态；
工具侧的功耗读数一律注明"无仿真活动文件输入 ⇒ 置信度 Low"（`build/power.rpt:40,42`）。

## 1. 指标表

| 指标名称 | 类别 | 数值 | 单位 | 测量条件 | 测试次数或时长 | 证据文件 |
|---|---|---|---|---|---|---|
| 器件与工具链 | 共用条件 | xc7z020clg484-2 / 2025.2.1 | — | ①`build/power.rpt:9` 的 Device 行；④同一份报告头 `:3` 的 Tool Version 行；②③⑤⑥不适用（这是一行声明不是一个测量）；`data/metrics.csv:2` 逐字念"本作品全部脚本可在 2025.2.1 从零复现，见 report/build.md" | 一次声明 | `build/power.rpt`、`build/system.bit`、`data/metrics.csv` |
| 全局 setup WNS（本版 r118） | 核心 | 0.739 | ns | ①共用 ②工具报出的 slack，小数三位；单位 ns ③对象=已布线后的整设计（`Design State: routed`，`build/power.rpt:10`），与输入帧率无关 ⑤逐时钟：`eth_rxc` 0.739（这一格就是全设计 WNS）⑥静态。失败 setup 端点 0 / 总端点 51135。警告 本版**不带** RGMII 输入窗 ⇒ 收口那 5 个端点未检查，所以这一行的含义是"片内路径零违例 + 收口 I/O 当前无窗"，不是"收口已通过"（`data/metrics.csv:5` 逐字：`失败 setup 端点 0 / 总端点 51135；板上 r118 bit cd04907e1369；本版不带 RGMII 输入窗`） | 一次布线后报告（2026-10-04 04:37 那一滚） | `build/timing_summary.rpt`、`build/evidence/r118_bit_md5.txt` |
| 全局 setup WNS（r97） | 核心 | 0.720 | ns | 同①④；位流 `ef03eea4886e`（`board/acceptance.md:48` 点名的 r97 身份行）；含自加的 0.8 ns hold 不确定度那一句在 `acceptance.md:59` | 一次布线后报告（2026-09-30 19:52 构建） | `build/r96_gates.txt`、`board/acceptance.md` |
| 全局 setup WNS（r96） | 核心 | 0.749 | ns | 同①④；位流 `76d6442991e0`（`board/acceptance.md:30`）；逐时钟那一轮念的是 `eth_rxc 0.749/0.049`、`clk_fpga_0 1.755/0.051`、`clkout0_1 0.840/0.062`、`sys_clk 14.272/0.121`（`acceptance.md:41`） | 一次布线后报告（2026-09-30 17:07 构建） | `build/r96_gates.txt`、`board/acceptance.md` |
| 全局 setup WNS（r94） | 核心 | 0.553 | ns | 同①④；位流 `a1465f29c9e4`、源 `rtl_md5=526321488fed`（`board/acceptance.md:8`） | 一次布线后报告 | `board/acceptance.md` |
| 全局 hold WHS（本版 r118） | 核心 | 0.052 | ns | ②小数三位 ③失败 hold 端点 0 / 总端点 51135；`data/metrics.csv:7` 逐字：`失败 hold 端点 0 / 总端点 51135；WPWS 0.264；这一格是片内族（本版无输入窗）` ⑤归属本轮在 `eth_rxc`（`build/evidence/p16c/metric_recheck_before.txt:21` 打印 `whs[eth_rxc] 首页=0.052 报告=0.052`）⑥静态 | 一次布线后报告 | `build/timing_summary.rpt` |
| 全局 hold WHS（r97 / r96 / r94） | 核心 | 0.033 / 0.049 / 0.049 | ns | 同一指标的三个历史轮，逐轮位流不同（r97 `ef03eea4886e`、r96 `76d6442991e0`、r94 `a1465f29c9e4`）；警告 这三格与本版 0.052 之间**不许相减念收益**（规矩 35） | 各一次布线后报告 | `board/acceptance.md`、`build/r96_gates.txt` |
| 逐时钟 setup 余量（本版 r118） | 核心 | eth_rxc 0.739 / clk_fpga_0 1.850 / clkout0_1 3.630 / sys_clk 14.876 | ns | ②小数三位 ③对象=各时钟域内路径 ⑤四域周期 8 / 10 / 20 / 20 ns ⑥静态；余量占比 9.24 % / 18.5 % / 18.15 % / 74.38 %（分子=该域 WNS、分母=该域周期，两个数都来自同一份报告，不许人脑补分母——出处 `src/host/metric_recheck.mjs:146-148` 那段注释记录的 12 % 除错周期的教训） | 一次布线后报告 | `build/timing_summary.rpt`、`build/evidence/p16c/metric_recheck_before.txt` |
| 逐时钟 hold 余量（本版 r118） | 核心 | eth_rxc 0.052 / clk_fpga_0 0.053 / clkout0_1 0.059 / sys_clk 0.222 | ns | 同上六件；`eth_rxc` 那一格是**加过 0.800 ns hold 不确定度之后**剩下的量，`clk_fpga_0` 那一格是同沿 min 检查的裸余量 ⇒ 两格不可直接比大小（`board/README.md:22-27` 明写这条，出处 `build/clock_uncertainty.rpt`） | 一次布线后报告 | `build/timing_summary.rpt`、`build/clock_uncertainty.rpt` |
| 脉冲宽度 WPWS / 失败端点 | 核心 | 0.264 / 0 of 12634 | ns / 个 | ②小数三位 ③时钟组检查，与输入帧率无关 ⑤全部时钟域 ⑥静态；`data/metrics.csv` 没有单独这一行，数值直接取报告表体第 9–12 列 | 一次布线后报告 | `build/timing_summary.rpt` |
| 收口 I/O 端点的检查覆盖 | 核心 | 5 个端点未检查 | 个 | ①共用 ③对象=`eth_rxd[3:0]`+`eth_rx_ctl`；本版无 `set_input_delay` 窗 ⇒ **未检查不等于满足**（H5）；带窗那一版的完整证明留在 `report/timing_global.md` 第 6 节 | 一次布线后报告 | `build/timing_summary.rpt`、`src/constraints/r116_rgmii_input_window.xdc`、`build/evidence/r115_window/probe3_console.txt` |
| 显示像素时钟 | 核心 | 50 | MHz | ①共用 ②工具从 Clock Summary 读出的 Frequency 列 ③对象=PL 侧 MMCM 的那一路输出 ④2025.2.1 ⑤`clkout0_1` 周期 20.000 ns ⑥静态；由 `metric_recheck` 的 `显示像素时钟` 规则对回报告（今天那一跑 `OK  row=显示像素时钟 csv=50 report=50`） | 约束一次生效 | `build/timing_summary.rpt`、`build/evidence/p16c/metric_recheck_before.txt` |
| 显示分辨率与场频 | 核心 | 1024×600 @ 59.5 | — | ①共用 + 面板 1024×600 ②`H_TOTAL=1344`、`V_TOTAL=625` ⇒ 50 MHz ÷ 1344 ÷ 625 = 59.5 Hz（不是 50 Hz，出处 `board/README.md:13`）③双窗输出（左窗原图 / 右窗处理图，缝位由 `split` 控制字决定）④2025.2.1 ⑤50 MHz 像素域 ⑥无 DVFS；`data/metrics.csv:4` 逐字同值 | 连续显示 | `board/README.md`、`data/metrics.csv` |
| Slice LUT 占用（本版 r112 读数沿用，构建 = r118） | 资源 | 14154（26.61 %） | 个 | ①共用 ②报告直接计数，可用 53200 ③对象=实现后整设计 ④2025.2.1 ⑤与时钟无关 ⑥静态；逐轮走势（全部列出，不挑最小）：r94 14374 → r96 14388 → r97 14379 → r103 14333 → r104 14334 → r106/r109 14323 → r110 −243 → r112 14154 级附近 → 本版报告 14154。`data/metrics.csv:8` 逐字念这一串差值并自己声明"这些差都是从各轮报告相减得来的，不是重跑的" | 一次构建（实现后报告） | `build/utilization.rpt`、`data/metrics.csv` |
| Slice 寄存器占用（本版） | 资源 | 8188（7.70 %） | 个 | 六件同上（可用 106400）；逐轮：r94 8074 → r96 8077 → r97 8079 → 本版 8188；`data/metrics.csv:9` 把 +46/−12 拆到两只 `key_debounce` 与累加器位宽上 | 一次构建 | `build/utilization.rpt`、`data/metrics.csv` |
| Block RAM Tile 占用（本版） | 资源 | 95.5 / 140（68.21 %） | tile | 六件同上；警告 **口径差**：r94/r96/r97 三行在 `board/acceptance.md:24,41,59` 都念成"95 tile"，本版报告这一格是 `95.5`（半块瓦片），两者不是同一个写法，不当回归念 | 一次构建 | `build/utilization.rpt`、`board/acceptance.md` |
| DSP48 占用（本版） | 资源 | 19 / 220（8.64 %） | 个 | 六件同上；用在缩放/旋转的坐标乘法与 gamma（`data/metrics.csv:11`）；r94/r96/r97 三行同为 19 ⇒ 这一格跨轮不动 | 一次构建 | `build/utilization.rpt` |
| 实现后动态功耗（本版） | 资源 | 2.213 | W | ①`build/power.rpt:9` Device 行 ②工具估算，小数三位 ③**无仿真活动文件输入 ⇒ Confidence Level = Low**（`power.rpt:40`，`Setting File / Simulation Activity File` 都是 `---`，`:42`）④2025.2.1 ⑤逐时钟翻转率由工具自估 ⑥`Grade: commercial`、`Process: typical`（`power.rpt:11-12`）；逐轮：r94/r96/r97 均 2.206 W → 本版 2.213 W（`data/metrics.csv:27` 自己标注那一轮是 r109） | 一次构建 | `build/power.rpt` |
| 片上合计功耗（本版） | 资源 | 2.391 | W | 同上六件；同一份报告的 `Total On-Chip Power (W)` 行（`:33`），与上一行是**同一次估算的两个口径**，不许相加 | 一次构建 | `build/power.rpt` |
| 结温估算（本版） | 资源 | 52.6 | ℃ | 同上；⑥`Effective TJA 11.5 ℃/W`、`Max Ambient 57.4 ℃`（`power.rpt:37-38`）。警告 `data/metrics.csv:28` 写的是 `Max Ambient 57.5 ℃` 而报告现在印 **57.4** ⇒ 该行不在 `metric_recheck` 射程（`fromPower()` 只取 Dynamic 与 Junction），所以尺子不红但两处不同源，见第 5 节 G3 | 一次构建 | `build/power.rpt`、`data/metrics.csv` |
| 片上结温（板读 XADC，本版 r118） | 实测 | 60.65 – 60.85 | ℃ | ①共用，板上真实结温 ②`[TEMP]` 回显给两位小数，另有 `raw` 12 位码与 `vccint` mV ③输入=**空闲态**（`uart_stat.txt:1` 回读 `frames=4398` 两次不变，上位机没在推流）⇒ 不是满载结温 ④`ps_app.elf` md5 `d0b07f84`（`board_verify_console.txt:6`）⑤50/100/125 MHz 都在跑 ⑥无 DVFS；**区间是 2 条被跟踪原始回显的极值，不是精度声明** | 一次板级校验里的 2 条 `[TEMP]`（地板 2） | `build/evidence/r118_serial_raw.txt`、`build/evidence/r118_board/board_verify_console.txt` |
| 片上结温（板读 XADC，r113） | 实测 | 61.15 – 61.71 | ℃ | ①共用 ②同上 ③那一轮带着 `board_verify --geom --battery` 的负载 ④位流 `b94f4da6cdff`（`data/metrics.csv:29` 逐字：`板上这一版 **r113**（bit md5 \`b94f4da6cdff\`）2026-10-03 14:32 三步 JTAG 刷入`）⑤同 ⑥同；六条极值，不是精度声明 | 一次板级校验（6 条 `[TEMP]`） | `build/evidence/r113_temp_lines.txt`、`build/evidence/r113_serial_raw.txt` |
| 片上结温（板读 XADC，r110 / r104 / r97） | 实测 | 60.63 – 60.68 / 61.72 – 61.98 / 63.13 – 63.38 | ℃ | 三轮各 2 / 4 / 3 条 `[TEMP]`；r97 那一次明写"抓的时候 SD 本地播放在跑，不是空载"（`build/board_temp_r97.txt:5`）⇒ **工况不同，三行不可比**，`data/metrics.csv:29` 自己就写了"差属工况与热身差异、别当收益或回归" | 各一次串口电池 | `build/evidence/r110_serial_raw.txt`、`build/evidence/r104_temp_lines.txt`、`build/board_temp_r97.txt` |
| 时钟结构：BUFIO 用量 | 核心 | 0 | 只 | ①共用 ②`report_clock_networks` 的直接计数 ③对象=已布线网表 ④2025.2.1 ⑤覆盖 8 条时钟（`clock_util.rpt:59-66` 的 g0..g7）⑥静态；改前那一份是 1（`board/acceptance.md:25`）；`BUFGCTRL = 8`（`:43`）；这一条是 #57 的**结构**判据，不靠 slack 碰运气 | 一次构建 | `build/clock_util.rpt` |
| 时钟结构：`eth_rxc` 的 BUFG 负载 | 核心 | 2544 | 个 | 同上六件；本版 `clock_util.rpt:61` 的 `2544`；r94 那一行念的是 2478（`acceptance.md:25`）⇒ 逐轮读数，不同源不比较 | 一次构建 | `build/clock_util.rpt` |
| 最差 20 条 hold 路径的时钟偏斜 | 未报 | — | — | 这一格有读数出口（`build/hold_paths.rpt`），但**本版没有逐条重读**：`board/acceptance.md:42` 自己写明"这一轮没有逐条重读（那是 r92 那一次的读法，文件也还在盘上）" ⇒ 按 P00"读不到不等于 PASS"填 `—`；缺它这行数字不能和 r94 那一轮的 0.013~0.349 ns 比 | 待复测 | `build/hold_paths.rpt`、`build/r88_clock_util.rpt` |
| ETH 入流零丢包（演示工况，上位机侧那一轮） | 实测 | 0 | 丢帧 / 坏帧 | ①共用 ②PL 收包链自己数的计数（不是上位机推的数）③512×300 RGB565、限速 15 MB/s、目标 30 fps ④【待补】（`report/perf_report.md` 那一节只给工况表行，没钉那一轮的 `system.bit`/`ps_app.elf` md5 ⇒ 缺它，这行的 0 不能和板上任何一版的 0 比，只能和同一篇 PERF 报告里的其它行比） ⑤`eth_rxc` 125 MHz ⑥无 DVFS；`report/perf_report.md:165` 表行 = `30 fps、限速 15 MB/s（演示工况） \| 600 \| 600.0 \| **0** \| **0** \| 0 \| 33.33 ms \| **30.007**` | 一轮 600 帧 | `report/perf_report.md`、`data/metrics.csv` |
| ETH 入流零丢字（本版 r118，带真实流量） | 实测 | 0 | 丢字 / 坏包 | ①共用 ②lane 读回的 JSON 字段 ③512×300 RGB565 @60 fps 不限速 ≈147 Mbps（`sender_r118build.log:1-2` 回读 `[TX] -> 192.168.1.10:5001  512x300 RGB565 @60fps  pace=0.0 MB/s`、`3001 帧 / 50.02 s = 60.00 fps`）④`ps_app.elf d0b07f84` ⑤`eth_rxc` 125 MHz，同一份读数里 `eth_live=1 owner_eth=1` ⑥无 DVFS；警告 147 Mbps 的绿**不许念成 1000M 线速的绿**（发送端帧率是上限，源只有 512×300；出处 `report/log/issues.md:12790` 规矩②） | 同一会话内两次读数（04:46:37 / 04:47:02） | `build/evidence/r116_board/health_r118build_a.json`、`build/evidence/r116_board/health_r118build_b.json`、`build/evidence/r118_board/bitcycle_console.txt` |
| ETH 入流零丢字（本版 r118，空闲态） | 未报 | — | 丢字 | 同一判据的另一份读数，`board_verify_console.txt:21` 印 `drop_words → 0`，但同一份读数的 `:18` 是 `"eth_live":0 … "why":"没有流"` ⇒ **零样本通过**，按本表口径③不填 0，填 `—`；缺 `eth_live=1` 这一格不能和上一行的带流读数并列成"两个 0" | 待复测（要带流重读） | `build/evidence/r118_board/board_verify_console.txt`、`report/log/issues.md` |
| ETH 入流 300 秒长跑 | 实测 | 0 | 丢帧 / 坏帧 / 重复帧 | 六件同"演示工况"那行（④同样【待补】，缺它这行的 300 s 长跑归不到任何一块位流名下）；连续 300 s，实测量 29.99 fps、帧间隔平均 33.34 ms（`report/perf_report.md:170` 表行） | 9000 帧 / 300 s | `report/perf_report.md`、`data/metrics.csv` |
| 入流过载点 | 未定 | ≥ 116.7 | fps | 六件同上（④【待补】⇒ 这个"≥116.7 fps 未丢字"不能与任何带位流身份的轮次互证）；不限速、目标 120 fps 时仍未丢字（≈36 MB/s 有效载荷、287 Mbps）；**这一版没顶到丢字那一点 ⇒ 不给"PL 能扛多少 fps"的数字**（`report/perf_report.md:179-181`、`data/metrics.csv:24`） | 960 帧 | `report/perf_report.md` |
| UDP 入口负载 | 口径 | 9.2 | MB/s | ①共用 ②`512×300×2 B × 30 fps` 的**计算值**（≈74 Mbps）③输入规格就在算式里 ④⑤⑥**不适用**（这是一行算式不是一次测量，给它填 ④⑤⑥ 只会让人以为它与实测行同口径）；`data/metrics.csv:13` 逐字：**这是负载口径不是实测带宽**，实测吞吐的读数出口在 OSD 第三行与 lane23 回读；同一张表的显示读那一行是 `≈18.3 MB/s`（`report/perf_report.md:150`） | 一次计算 | `report/perf_report.md`、`data/metrics.csv` |
| 端到端时延（上位机发出 ↔ 屏上出现） | 核心 | 33.34 | ms | ①共用 ②min/avg/max 三位（20 / 33.34 / 51 ms）③30 fps 限速一轮 ④同一轮墙钟交付 29.79 fps ⑤`eth_rxc` 125 MHz + 显示 50 MHz ⑥无 DVFS；测量起点=上位机发送时刻，终点=示相机位录到该帧上屏（`data/metrics.csv:25`） | 一轮 600 帧 | `report/perf_report.md`、`data/metrics.csv` |
| 端到端时延（屏上那一格 ↔ 回读计数，同源一致） | 实测 | true | 判据 | ①共用（板上 r118）②`lat.osd_ms_matches_tot` 是一个布尔判据 ③空闲与带流两种状态各读过（带流两次：`tot_ms 10.356/osd_ms 10`、`tot_ms 5.888/osd_ms 5`）④`ps_app.elf d0b07f84` ⑤时延计数的 `ns_per_cycle=10`（100 MHz 域）⑥无 DVFS；`board/acceptance.md:21` 那一行（`Latency=6ms` ↔ `tot/100000=6`）的凭据是 r92 的件，不借给本版 | 三次读数（1 次空闲 + 2 次带流） | `build/evidence/r118_board/board_verify_console.txt`、`build/evidence/r116_board/health_r118build_a.json` |
| 帧间隔抖动 | 核心 | 33.33 | ms | ①共用 ②min/avg/max = 22 / 33.33 / 45 ms ③30 fps 限速工况 ④【待补】（同一轮没钉位流身份 ⇒ 这个抖动数不能和 r118 的任何读数并列成"同一版"） ⑤`eth_rxc` 125 MHz ⑥无 DVFS；抖动上界来自显示扫描与读口调度，不来自调度器（`data/metrics.csv:26`） | 一轮 | `report/perf_report.md`、`data/metrics.csv` |
| SD 本地播放帧率（r87 那一轮） | 实测 | 29.8 – 30.0 | fps | ①共用 ②100 帧滑窗读数，给到三位小数 ③512×300 RGB565 预转换帧序列（板上不做解码），SD 卡 FAT32 ④【待补】（`build/evidence/r87_boot_stat_drain.txt` 没有钉 `ps_app.elf` 的 md5 ⇒ 缺它这行不能和本版 r118 的 SD 读数比，只能当 r87 那一版的独立读数） ⑤显示 50 MHz ⑥无 DVFS；串口 115200-8N1；`build/evidence/r87_boot_stat_drain.txt:4-5` 逐字 = `[SD] frame 1900: last 100 frames 29.956 fps (since play 29.836)` / `[SD] frame 2000: last 100 frames 29.815 fps (since play 29.833)` | 两个滑窗样本 | `build/evidence/r87_boot_stat_drain.txt`、`data/metrics.csv` |
| SD 本地播放帧率（本版 r118） | 未报 | — | fps | 本版只回读到 `[STAT] … sd=1 frames=4398 playing=1`（`uart_stat.txt:1`、`uart_stat2.txt:1-2` 两次 3 s 间隔 `frames` 不变），没有 100 帧滑窗那一行 ⇒ 填 `—`；缺它这行数字不能和 r87 那两行比，也不能宣称"SD 一路在这一版仍然 30 fps" | 待复测（要板子在场） | `build/evidence/r118_eyes/uart_stat2.txt`、`build/evidence/r118_board/board_verify_console.txt` |
| 串口命令电池（本版 r118） | 功能正确性 | 105 | 条 | ①共用 ②逐条 ok/红计数 ③命令串覆盖 105 条（含"该拒的必须拒"那一族，如 `split px 9999`）④`ps_app.elf d0b07f84` ⑤与帧率无关（读的是控制口）⑥无 DVFS；97.9 s 跑完；捕获件 `board/uart_script_capture.txt` 此刻在盘上但**不随包**（`.gitignore:134 board/uart_*.txt` 命中）⇒ 随包复核用 `board_verify_console.txt:63` 那一行 | 一次电池（97.9 s） | `build/evidence/r118_board/board_verify_console.txt`、`build/evidence/r118_serial_raw.txt` |
| 串口命令电池（逐轮） | 功能正确性 | 100 / 105 / 105 / 105 | 条 | 同一判据四轮全列：r94 100 条 / 93.1 s（`board/acceptance.md:17`，件 `build/r94_batt.txt:106`）→ r96 105 条 / 97.7 s（`acceptance.md:37`）→ r97 105 条 / 97.8 s（`acceptance.md:55`，件 `build/evidence/r97_batt_recheck.txt`）→ 本版 105 条 / 97.9 s；条数从 100 涨到 105 是因为 #105/#177/#178 那几组新判据（`acceptance.md:37` 明写），**不是同一把尺子漂了** | 各一次电池 | `build/r94_batt.txt`、`build/evidence/r97_batt_recheck.txt`、`board/acceptance.md` |
| 几何"最后一跳" geom_check | 功能正确性 | ok=10 fail=0 | 条 | ①共用 ②`ok`/`fail` 条数 ③命令→像素域 lane23/CFG_DATA0 ④`ps_app.elf d0b07f84` ⑤像素域 50 MHz ⑥无 DVFS；逐轮全列：r94 `ok=8 fail=0`（`acceptance.md:18`）→ r96 `ok=8` → r97 `ok=10`（新增 G5/G5b，`acceptance.md:56`）→ 本版 `ok=10`；本版 G5b 明写"四次里至少真的钳住一次——不然 G5 是空判据 钳住=4/4"（`board_verify_console.txt:31`）⇒ 这一条不是空集通过 | 一次运行（约 6 s） | `build/evidence/r118_board/board_verify_console.txt`、`build/r94_geom_check2.txt`、`build/evidence/verify_0930_1845.geom.txt` |
| 整屏逐像素判据（本版那一次跑） | 核心 | 162 | 条 | ①仿真树（非板上）②逐格像素判定条数 = `^PASS` 161 行 + `^FAIL` 1 行 ③顶层台架 `tb_v98_top_seam`，与板上的 512×300 双窗同形状 ④`fpver=norm1 top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4 date=2026-10-04T01:47:53+08:00`（文件第 1 行）⑤台架时钟与 RTL 同树 ⑥不适用；唯一那行 FAIL 是**声明过**的 `C5c`（`:55`），对外口径写在 `report/known_issues.md` 第 1 节 | 一次台架 | `build/tb_v98_report.txt`、`report/known_issues.md` |
| 整屏逐像素判据（`data/metrics.csv` 那一行） | 核心 | 141 | 条 | **逐字引 `data/metrics.csv:15`**：`与 r104 同一批的顶层台架（build/tb_v98_report.txt 头部 # provenance fpver=norm1 top_md5=2bf2ceeede07 tb_md5=36d0de483e6d rtl_md5=8997a62b75ba，编译时戳、日期 2026-10-02 01:15）；141 = 该文件里 ^PASS 行数 140 加 ^FAIL 行数 1`；警告 它点名的就是上一行那份文件，而文件的 provenance 串与条数都已经换过（本版 162 / `top_md5=56c269602e18`）⇒ 这一格是**指标表与报告不同源**的实物证据，见第 5 节 G1 | 一次台架（约 108 分钟） | `data/metrics.csv`、`build/tb_v98_report.txt` |
| 门禁自检项数（本版） | 自检 | 24 | 项 | ①**不适用**（这是检查器射程，不是硬件量）②项数 + 绿/红计数 ③一条命令跑：时序/资源/端口宽度/CDC/文档编码与时效 + 两个钉 md5 的整屏台架 + 排练=讲稿抽取 + 检查器自带的变异对照 ④`build/gates.sh` 当前版 ⑤⑥**不适用**（同一行⑤⑥对一把文本尺子没有含义）；`build/r118_gates.txt:53` 逐字 = `判定 24 项、未判 0 项`；`:54` = `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；`build/evidence/r118_board/gatesd_summary.txt:1` = `GATESD done id=identical green=23 red=1`。**项数逐轮全列**：r104 = 判定 20 项（`build/r104_gates.txt`）→ 本版 24 项 | 每轮构建后一次（定版要求两跑逐字节一致） | `build/r118_gates.txt`、`build/evidence/r118_board/gatesd_summary.txt`、`build/r104_gates.txt` |
| 门禁自检项数（`data/metrics.csv` 那一行） | 自检 | 22 | 项 | **逐字引 `data/metrics.csv:14`**：`门禁自检项,自检,22,项,…**第 20 项 = 行号锚点（D5 line_cite_check）、第 21 项 = 数字对账（D6 metric_recheck）**…`；本版件印的是 **24 项** ⇒ 该行是 r104 时代的射程，见第 5 节 G1。缺"哪些项在射程里"这半，22/24 这两个数不能互相替换着念 | 每轮构建后一次 | `data/metrics.csv`、`build/r118_gates.txt` |
| 数字对账射程（metric_recheck，D6） | 自检 | 114 | 个数 | ①**不适用**（同上）②被判的数的条数（首页层 60 / csv 层 54）③输入=三份报告 + `data/metrics.csv` + 两份首页 ④`src/host/metric_recheck.mjs` 当前版 ⑤— ⑥—；我今天那一跑的原文汇总 = `== 数字对账：判 114 个数（首页层 60 个／解析到 10/10 行；红 0）／csv 认领 10/10 行／其余 18 行不点名这三份报告 ==`，`OK` 行 70 条、`RED` 行 0 条、`rc=0` | 我这次为写这份文档跑的 1 次（正跑 + `--self` 由门禁跑） | `build/evidence/p16c/metric_recheck_before.txt`、`build/gates.sh` |
| 变异对照分支 | 功能正确性 | 5 | 条 | ①仿真树 ②分支条数 ③`build/sim/mut_control.sh` 的五支：pipeline / osd_inchar / osd_addr / osd_inchar_all / bilin_ky_fold ④`build/sim/mut_control.sh` 当前版 ⑤— ⑥—；规矩是"一次变异只许红它声称红的那一条"，红不了或红多了都算失败（`data/metrics.csv:16`） | 每判据一支 | `build/sim/mut_control.sh`、`data/metrics.csv` |
| 越界读写的机会计数 | 功能正确性 | 190464 | 拍 | ①仿真树 ②拍数 ③OSD 字模索引在 1024×600 有效区整屏走一遍时越出数组上界的拍数（最大索引 255 = 位宽上限）④— ⑤显示 50 MHz 域 ⑥—；这道"机会地板"让"屏上没现象"与"真的被门住了"两种说法可区分（`data/metrics.csv:17`） | 一次台架运行 | `build/evidence/r86_osd_t18_teeth_addr.txt`、`data/metrics.csv` |
| 帧头窗的逐格错位（C5c 那一族） | 实测（台架） | 8 | 格 | ①仿真树 + 板上复看 ②逐格（显示行 × 源行）③屏顶 6 个显示行（`OFF_LINES` 4 + `BILIN_ROWS` 2）：顶部前 4 行显示源行 2 而定义要 0/0/1/1 ④`rtl_md5=8997a62b75ba`（r104 那一棵树）⑤显示 50 MHz ⑥—；**本体行一格都不错**（`report/known_issues.md` 第 1 节逐字） | 一次逐格扫描 | `build/evidence/r104_c5head_band.txt`、`report/known_issues.md` |
| 屏顶位移随每帧角度步数 | 实测（台架） | 45° k=1/2/7 最大 5/9/31 源像素；60° 最大 6/10/31；168° 最大 5/9/31 | 源像素 | ①仿真树 ②逐格取 \|Δx\|、\|Δy\| 的较大者，另给平均值 ③屏顶那一带、k = 每帧角度步数 ④`rtl_md5` 同 r105 那一滚 ⑤显示 50 MHz ⑥—；k=0 那一档三个角度各扫两遍**逐位相同**（1112/1366/1018 个有效格）⇒ 台架自己不漂；`RESULT … PASS cells=49152 pairs=12` | 一次台架（k=0 两遍对照） | `build/r105_tb_head_rot_displace.txt`、`report/known_issues.md` |
| 缩放范围 | 功能 | 0.25 – 2.00（八档） | 倍 | ①共用 ②`ZOOM_X100 = {25,33,50,75,100,133,150,200}`（定点整数 ×100）③手动档 / 自动呼吸档 / Fit 档三种来源 ④`src/ps/main.c:173` 那张表 ⑤`clk_fpga_0` 100 MHz（缩放系数在像素域）⑥无 DVFS；倍率与来源都可从 lane23 回读（本版回读 `data/metrics.csv:18` 那句 + `board_verify_console.txt:19` 的 `"inv_scale":256,"x100_actual":100`） | 逐档演示 | `board/verify_r87.md`、`build/evidence/r118_board/board_verify_console.txt` |
| 片源与仲裁 | 功能 | 3 路 + AUTO | — | ①共用 ②通路数 ③ETH（PL 硬件收包链）/ SD（PS 读裸帧）/ TEST（自研动态图卡）④— ⑤`eth_rxc` 125 MHz + 显示 50 MHz ⑥无 DVFS；AUTO 下的切换与回落由链路健康自诊断引擎驱动 | 现场演示 + 台架 | `board/verify_r87.md`、`report/perf_report.md` |
| 片源仲裁交接耗时 | 实测（台架） | 208 – 481 | ms | ①台架（`frozen_r32_sdfix`）②逐条记录里的单次交接值 ③停流→交回 PS / 推流→接管 / 再推流（可逆）三类 ④r32 那一棵树 ⑤— ⑥—；判据共 11 遍：**九遍七条全绿、2 遍红**（修复前 / 中途配置，同文件保留）；设计预算 200 ms（判"没流"）+ 20 ms（让位静默）≈220 ms ⇒ 相容；**报区间的理由是判据的时间分辨率 = 采样周期（100 / 300 ms 两种写法），不挑最小那个念**（`report/perf_report.md:223` 逐字） | 11 遍（含 2 遍红） | `build/frozen_r32_sdfix/arb_handover_r32b.json`、`report/perf_report.md` |
| 旋转钳下的小数命中率 | 功能正确性 | ≈ 0.27 %（10 / 3726） | 像素占比 | ①仿真树 ②逐像素 ③缩放 0.5× + 自动旋转，S1/S2/S3 三段 ④`build/r103_tb_zoom_frac.txt` 那一次 ⑤像素域 50 MHz ⑥—；警告 这条**发生率**直接限定了眼睛那一格的意义："这种稀疏度本来就不保证肉眼抓得到"（`board/acceptance.md:70` 逐字） | 一次台架 | `build/r103_tb_zoom_frac.txt`、`board/acceptance.md` |
| 人眼判据条目数 | 验收 | 36 | 行 | ①共用 ②行数 ③全功能上板验收表，每条给命令、预期现象、以及"这一行不通意味着什么" ④— ⑤— ⑥—；屏幕现象只能由人判，机器判据不冒充眼睛（`data/metrics.csv:21`）。本文件另有一份按 r118 逐条重录的版本：`board/signoff.md` 第 2 节的 **10 条眼睛项**（PASS 8 / NOT_MEASURED 2） | 一次上板 | `board/verify_r87.md`、`board/acceptance.md`、`board/signoff.md` |
| 端到端时延（未报那一行） | 未报 | — | — | **逐字引 `data/metrics.csv:20`**：`这一格有读数出口（OSD 的 Latency lane 与 JTAG 回读），但**本表不填没有复核过的数**：读数方法与逐轮记录在 board/verify_r87.md 与 build/evidence/，取到可信值之前不占权重也不宣称`；本表在"同源一致"那一行只填了**判据 `true`**，没有把时延绝对值当成这一版复核过的数 | 待复测 | `board/verify_r87.md`、`data/metrics.csv` |

## 2. 多轮对照（同一指标的逐轮读数，一张表看清"没挑最好的一行"）

| 指标 | r87 | r92 | r94 | r96 | r97 | r101 | r103 | r104 | r108 | r110 | r113 | r118（本版） | 板上签收过 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 位流 md5（前 12） | — | — | `a1465f29c9e4` | `76d6442991e0` | `ef03eea4886e` | — | — | `680f38f5794c` | `25bf35a9900e` | `2bf95588978f` | `b94f4da6cdff` | `cd04907e1369` | `build/evidence/r118_bit_md5.txt` |
| 全设计 setup WNS (ns) | — | — | 0.553 | 0.749 | 0.720 | — | — | — | — | — | — | **0.739** | `build/timing_summary.rpt` |
| 全设计 hold WHS (ns) | — | — | 0.049 | 0.049 | 0.033 | — | — | — | — | — | — | **0.052** | 同上 |
| 失败端点 / 总端点 | — | — | 0 / 50883 | 0 / 50887 | 0 / 50890 | — | — | — | — | — | — | **0 / 51135** | 同上 |
| Slice LUT | — | — | 14374 | 14388 | 14379 | — | 14333 | 14334 | — | −243 vs r109 | 14154 级 | **14154** | `build/utilization.rpt`、`data/metrics.csv:8` |
| Slice 寄存器 | — | — | 8074 | 8077 | 8079 | — | — | — | — | — | — | **8188** | `build/utilization.rpt` |
| 动态功耗 (W) | — | — | 2.206 | 2.206 | 2.206 | — | — | — | — | — | — | **2.213** | `build/power.rpt:36`、`board/acceptance.md:24,41` |
| 片上结温 XADC (℃) | — | — | 63.38（r97 轮，见右） | — | 63.13–63.38 | — | — | 61.72–61.98 | — | 60.63–60.68 | 61.15–61.71 | **60.65–60.85** | 各轮 `[TEMP]` 件（第 1 节四行） |
| 串口电池条数 / 时长 | — | — | 100 / 93.1 s | 105 / 97.7 s | 105 / 97.8 s | — | — | — | — | — | 105 / 97.6 s | **105 / 97.9 s** | `board/acceptance.md:17,37,55`、`data/metrics.csv` 无此行 |
| geom_check | — | — | ok=8 | ok=8 | ok=10 | — | — | — | — | — | 10/0 | **ok=10** | `board_verify_console.txt:36` |
| 门禁项数 / 红项 | — | — | — | — | — | — | — | 判定 20 / 1 红 | — | — | — | **24 / 1 红** | `build/r104_gates.txt`、`build/r118_gates.txt:53` |
| 眼睛判据 E1–E6 | PASS(r92) | PASS | — | — | — | PASS(E5) | PASS(E2) | PASS(E4 碎影) | PASS(E4r) | — | PASS(E6) | PASS(**E4a**、**E6**) | `board/acceptance.md:66-105`、`board/signoff.md` 第 2 节 |

警告 这一节的空单元格就是"那一轮没重跑过这一格"，**不是 0、也不是"通过"**。
`board/acceptance.md:9-10` 立的规矩原样适用：`把某一行的数当"这一版验过"之前，先看这一行有没有"r94"字样`。

## 3. 证据文件存在性核对

核对命令（原样可复跑，也是 `report/acceptance-recipes.md` 的 R9；分三桶，只有 A 桶必须为 0）：

```bash
cd <仓库根>
for doc in report/measurements.md board/signoff.md report/acceptance-recipes.md board/signoff-questions.md; do
  A=0;B=0;C=0;T=0
  while read -r p; do T=$((T+1)); [ -f "$p" ] && continue
    case "$p" in *"("*|*"*"*|*"NN"*|*"<"*|*"（"*) B=$((B+1));; *"/") C=$((C+1));; *) A=$((A+1)); echo "A MISS $p";; esac
  done < <(grep -o '`[^`]*`' "$doc" | tr -d '`' | grep -E '^(build|board|data|src|sim|report)/' \
           | sed -E 's/:[0-9].*$//' | sort -u)
  echo "$doc 点名=$T 命中文件=$((T-A-B-C)) A(真缺)=$A B(写法/占位)=$B C(目录)=$C"
done
```

我今天这一跑的实际输出（件 `build/evidence/p16c/evidence_existence.txt`，逐条分桶都在里面）：

**A. 只看本表的"证据文件"列**（逐格抽出、去掉 `:行号` 后 `test -f`）：

```bash
awk -F'|' '/^\| /{ n=NF-1; if(n>=7) print $n }' report/measurements.md \
  | grep -oE '`(build|board|data|src|sim|report)/[^`、]+`' | tr -d '`' \
  | sed -E 's/:[0-9].*$//' | sort > /tmp/ev2.txt
tot=$(wc -l < /tmp/ev2.txt); miss=0
while read -r p; do [ -f "$p" ] || { miss=$((miss+1)); echo "MISS $p"; }; done < /tmp/ev2.txt
echo "证据文件列逐格点名=$tot 缺=$miss 唯一=$(sort -u /tmp/ev2.txt | wc -l)"
```

实得：`证据文件列逐格点名=122 缺=0 唯一=48`（48 个唯一路径逐个 `test -f` 全命中）
⇒ **命中率 122/122 = 100 %，指到目录或空指的行数 = 0**（P16c 质量判据 1）。

**B. 四份文档全文**（正文里也会提到目录与通配写法，所以分三桶，只有 A 桶必须为 0）：

| 文档 | 点名的唯一路径 | 逐个 `test -f` 命中 | A 真缺 | B 写法（通配/占位） | C 目录写法 |
|---|---|---|---|---|---|
| `report/measurements.md` | 56 | 55 | **0** | 0 | 1 |
| `board/signoff.md` | 53 | 50 | **0** | 0 | 3 |
| `report/acceptance-recipes.md` | 38 | 32 | **0** | 4 | 2 |
| `board/signoff-questions.md` | 20 | 18 | **0** | 0 | 2 |

B 桶是通配/占位写法（`rNN_*`、`<本轮>/…` 这类配方正文里教的形状），C 桶是只说"这一族件放在哪"的目录句；
两桶的逐条清单原样列在件 build/evidence/p16c/evidence_existence.txt 里，本文不复述目录名——
复述会把它们变成新的点名，清点就永远在数自己。

警告 **这四行的数是这一跑的快照，而且清点把自己也算进射程**（本仓库的同类事故登记在 `report/log/issues.md` 的 #333：
"射程会自动把我新造的文件算进去"）。往这几份文档里多写一条点名路径，下一跑的"点名/命中"就会变——
那不是回归；要盯的是 **A 桶恒为 0** 与 **第 ① 段那 122/0/48**。




## 4. 与 `data/metrics.csv` 的关系

- **我没有改它**：本次只新建 `report/measurements.md` 与另外三份文档（`board/signoff.md`、`board/signoff-questions.md`、`report/acceptance-recipes.md`）。
  核对方式 = 第 6 节那把尺子在我写文档前后各跑一次；**实际跑出的是三个读数**：`判 114 个数…红 0`/`rc=0` → `判 86 个数…红 4`/`rc=1` → `判 117 个数…红 0`/`rc=0`。
  中间那次红**不是这几份新文档造成的**（`metric_recheck` 只读 `data/metrics.csv` 加三份 `.rpt` 加两份 `README`，见 `src/host/metric_recheck.mjs:50,73,86,211,287,289`），
  而是同一仓库里另一个写入者在我两次跑之间连续重写 `README.md`（14278 B / mtime 08:50 → 45715 B / 12:19，到我这条为止它还在被改）；
  逐条归因写在 `board/signoff.md` 第 4 节 L14，四份原始输出在 `build/evidence/p16c/`（`metric_recheck_before.txt`、`_after.txt`、`_final.txt`、`_final2.txt`）。
  警告 首页层从 60 个数变成 63 个数也是这条重写带来的：**分母自己动了**，所以本表引用首页时只引那一格说了什么，不把行号当锚用。
- **逐字引用格式**：先给 `data/metrics.csv` 这个路径，再在它后面接冒号与那一行的行号；引号里就是那一行原文。第 1 节里凡是"逐字引"三个字出现的地方都给了行号
  （`:2 :4 :5 :6 :7 :8 :9 :11 :13 :14 :15 :16 :17 :18 :20 :21 :24 :25 :26 :27 :28 :29`）。
- 尺子的射程：**只有点名那三份报告的行会被判**（`timing_summary.rpt` / `utilization.rpt` / `power.rpt`），
  `src/host/metric_recheck.mjs:320` 的 `NAMED` 正则决定射程；其余行被计成 `其余 18 行不点名这三份报告`。
  ⇒ 第 5 节那三条差异全落在射程外，**尺子不会替我红**，所以我手工登记。

## 5. 本表登记到的三条"指标表 ↔ 报告"不同源（都是文档侧，不是功能侧）

| # | 差异 | 两边原文 | 尺子为什么没抓 | 后续 |
|---|---|---|---|---|
| G1 | `data/metrics.csv:15` 写"整屏逐像素判据 141 条"，而它点名的 `build/tb_v98_report.txt` 现在数出 **162**（161 `^PASS` + 1 `^FAIL`），provenance 也从 `top_md5=2bf2ceeede07 / date=2026-10-02 01:15` 换成 `top_md5=56c269602e18 / date=2026-10-04T01:47:53` | 见第 1 节那两行 | 该行"证据文件"列点名的是 `build/tb_v98_report.txt`，不在 `NAMED` 正则里 ⇒ 算"不点名这三份报告" | 交裁决（问题清单第 2 轮 Q4）；我不动 `data/metrics.csv` |
| G2 | `data/metrics.csv:14` 写门禁"22 项"，本版件 `build/r118_gates.txt:53` 印"判定 24 项、未判 0 项" | 同上 | 同上（该行点名 `build/gates.sh`） | 与 G1 一并交裁决 |
| G3 | `data/metrics.csv:28` 写 `Max Ambient 57.5 ℃`，`build/power.rpt:38` 现在印 `57.4` | 同上 | `fromPower()` 只取 `Dynamic (W)` 与 `Junction Temperature (C)` 两格 ⇒ 这一格不在射程 | 与 G1 一并交裁决；顺带记：想让这类数有人读，就得在 `metric_recheck` 的 power 规则里**加**一格（不许减地板） |

## 6. 复跑（第三方照抄就能复核）

```bash
# 1) 时序/资源/功耗三个数对回报告（本表第 1 节的核心行）
node src/host/metric_recheck.mjs | tail -3
# 2) 整屏逐像素判据的条数与那条故意留红的 C5c
grep -c '^PASS' build/tb_v98_report.txt; grep -n '^FAIL' build/tb_v98_report.txt
# 3) 门禁一把跑（项数与红绿以它打印的那一行为准，本表不复制）
bash build/gates.sh | tail -3
# 4) 板上板级一把跑（要板子在场、COM6 空闲；本仓库只走 JTAG，不写 QSPI）
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom
# 5) 温度那一格的逐条原始回显（不靠手抄）
cat build/evidence/r118_serial_raw.txt
```

**测量条件缺项的总清单**见 `board/signoff.md` 第 4 节与本文件第 5 节；`【待补】` 的计数与位置在交付报告里报出。

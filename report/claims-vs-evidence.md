# 交付文档断言 ↔ 凭据件 对账表（claims-vs-evidence）

## 0. 这一页是什么、不是什么

板上现在跑的是 r118，位流 `build/system.bit` 的 md5 前 12 位是 `cd04907e1369`；下表里"板上这一版"指的都是它。

- **是什么**：一张**对账表**。左列是交付文档里已经写出去的断言，中间是仓库内被认为证明它的凭据文件，
  再右是按行打开该文件后读到的逐字片段（含行号），最右是判定。
- **不是什么**：它**不是重新测量**。本表不产生新读数、不重跑构建/台架/发布前检查/上板脚本，
  也**从不把某个数字当作自己的权威**：每个数字都只指向写着它的那份凭据；判定说的是"件里读不读得到、
  与断言合不合"，不是"这个数对不对"。要判数字本身，跑生成该件的那套检查即可。
- **三态词汇**（沿用 `report/06-validation.md` §1 与 `board/signoff.md` §0 的口径，只有三个值）：
  - `PASS` = 在该行点名的凭据文件里**逐字读到了**片段；或该断言本身就是"某事未做/未判"，
    而件里逐字写着那句未做/未判。
  - `FAIL` = 件在盘上，但读出的与断言**不符**：数值不同、件名或行号指错、"逐字"不成立、
    或断言已被同族件**更正**过、或断言已被盘上实况推翻（文档过期）。
  - `未见凭据` = 交付文档确实写了这句，但仓库内**找不到承载它的件**（件不在盘上，或存在过的件
    未被 git 跟踪 ⇒ 随包时不会带上）。这是**缺口**不是失败，每行写明补上它需要哪一件。
- **被引片段的取舍**：片段里出现的取证钟点（几时几分几秒）属于原始记录件的内容，本表只留行号与读数，
  不再复述时刻。片段点名的凭据件一律原样写；凡盘上没有的那一份（被 `.gitignore` 挡住的本地串口捕获件、
  技能包重建前的旧条目名），就地在同一行写明"不随包"或"已不存在"，不改写它的路径形状。
- **三个名字的所指**（本表按被引文档的原话写，解释一次）：**终审** = `report/final-gate.md` 那 12 项交付自检
  C1–C12；**门禁** = `build/gates.sh` 的发布前检查项（末行 `GATES: …`）；**尺子** = 具体的检查脚本，
  本表一律写成脚本名与它的 `--self`／对照例。"绿／红"是这些脚本自己打印的用词，引文里原样保留。
- **走过的文件**（断言只从这些文件取；每个行号都是按行打开核对过的行）：
  `README.md`、`README_EN.md`、`report/README.md`、`report/01-overview.md`、`report/02-architecture.md`、
  `report/03-algorithm.md`、`report/04-resources.md`、`report/05-timing.md`、`report/06-validation.md`、
  `report/07-skill-distillation.md`、`report/08-limits.md`、`report/reproduce/README.md`、
  `report/README.md`、`report/40-optimization.md`、`report/50-results.md`、`report/60-failure-analysis.md`、
  `report/70-reproduce.md`、`report/background_and_novelty.md`、`report/known_issues.md`、
  `report/optimization_log.md`、`report/perf_report.md`、`report/timing_global.md`、
  `report/known-limitations.md`、`report/final-gate.md`、`report/submission-checklist.md`、
  `board/acceptance.md`、`board/signoff.md`。
  凭据件可以是任何仓库内路径（含 `report/log/`、`build/evidence/`、`data/`、`src/`）——**本表不修改任何件**。
- **计数**（用第 3 节那条命令现数即可复算）：**行数=60　PASS=43　未见凭据=6　FAIL=11**。

## 1. 对账表

| 断言（逐字或紧摘要） | 出处 文件:行 | 凭据件（仓库内路径） | 在该件里能 grep 到的关键行（逐字片段） | 判定 |
| --- | --- | --- | --- | --- |
| 「现在屏幕没问题了四角都在屏幕内」（E4 四角在屏内） | board/acceptance.md:76；report/known-limitations.md:68；report/06-validation.md:179 | build/r104_tb_zoom_fit_corners_console.txt（机器那一半）＋ board/acceptance.md:76（原话本体） | 第 3 行 `PASS cov angle=45 inv_fit=492 swept=153600 A_corners=4 B_corners=0 A_srcx=0..511 A_srcy=0..299`；第 7 行 `RESULT tb_zoom_fit_corners PASS`；第 11 行 `VERDICT tb_zoom_fit_corners: RESULT tb_zoom_fit_corners PASS`＋`FAIL 行数=0`＋`PASS 行数=6`。警告 件只证"四角落在源窗内"，屏上那一半只有队员原话 | PASS |
| E4 的另一半（左缘沿对角的宽彩条）没有队员原话 | board/signoff.md:226 | board/acceptance.md:76 | `**这一格原本那半仍未判**（45°/60° 时四角在不在屏内、左缘有没有沿对角的宽彩条）` | PASS |
| 冷上电屏上 `ROT:` 读「0度」（E6），且机器侧三步链 rc=0 | report/known-limitations.md:68；report/06-validation.md:117-124；board/acceptance.md:98 | build/evidence/r118_eyes/handoff8.txt、state.txt、step1_boot.txt、step2_program_pl.txt、step3_app.txt、uart_stat.txt | handoff8.txt:5 `* **E6 判了**：队员 2026-10-04 冷上电（断电 ≥10 s）+ 只跑三步 JTAG 链 + 全程不碰 KEY1/KEY2，屏第二行 `ROT:` 读 **0**（原话「0度」）。`；state.txt:6-8 三行 `rc=0`；step1:6 `DDR_ECHO: 10000000:   5A5AA5A5`；step2:33 `PROGRAMMED xc7z020_1 <- （仓库根）/build/system.bit`；step3:3 `DOW: ok`；uart_stat:1 `[STAT] ctrl thr=80 src=1 ... geom=00400000 osd=1`。警告 原话件是**人眼转写**，不是屏幕机读 | PASS |
| "屏上 `ROT:` 读 0" 这一格可被机器复核 | report/08-limits.md:53-42（同页自述仍读不到） | 盘上没有能读角度的件：build/evidence/r118_eyes/uart_stat.txt 是唯一 STAT 回读，件内无 angle/ROT 字段 | `grep -n "0度\|ROT:" build/evidence/r118_eyes/uart_stat.txt` 无命中；能定它的件 = 按 `build/r113_angle_lane_plan.md`（在盘上）把 lane23 保留位 `[28:20]` 做成机读口之后的一次 lane/`STAT` 读数件 | 未见凭据 |
| E6 对照那一半（按住 KEY1 应读 1）**仍未做** | report/06-validation.md:126；report/08-limits.md:40 | board/acceptance.md:98；board/signoff.md:261 | ACCEPTANCE:98 `**对照那一半仍未做**：上电后按住 KEY1 到链子跑完再松手、那一读应当是 1 度——它需要你再断一次电，所以这一条只登记"未判"，不写成过`；signoff:252 `### E6b 对照组：上电后按住 KEY1 直到链跑完，那一读应当是 1 度` | PASS |
| 「拔网线后画面在 ≤0.5 s 自己让位到 SD、`SRC:` 变成 `SD`」 | report/01-overview.md:30 | 找过 data/measured/board_measure_r08.md、build/evidence/r116_board/、board/evidence_r29/、build/evidence/r118_board/：没有任何一件写着"拔线→`src=` 换到 SD 用了多少 ms" | 最接近的是板级链路读数 board_measure_r08.md:125 `| …（该行首列是拔线那一刻的时刻） | 566 | 77572 | 1547（该秒被切断） | alive |`；能定它的件 = 一次带时刻标注的拔线→`[STAT] src=` 翻转记录（`build/board_verify.sh --stream` 那一族目前测的是**停流**不是**拔线**） | 未见凭据 |
| 板级三态、**拔线可逆性**、`gapclr` 对账见 OVERNIGHT R08–R10 | report/background_and_novelty.md:53 | data/measured/board_measure_r08.md | 第 117 行的节标题 `## 拔线实验（…，每秒一次采样，`--test move` 15 fps）`（括号里是采样的起止时刻）；第 135 行 `插回后 `stall_ms` 立即归零，**全程没有重启板子或重下 bit** —— 自动恢复成立。`。警告 版本：2026-09-22 V7.6 那一版，不是板上这一版 | PASS |
| 「三片源自适应仲裁是**可逆的**」凭据 `src_arb.v` 与 `tb_v796_src_arb.v`；以及「`link_active = \|s_pkts\|`，拔线不清零」 | report/01-overview.md:62；README.md 的「项目简介（这个系统做什么）」一节 | sim/tb_v796_src_arb.v＋build/l1_console_r52.txt；src/rtl/eth/eth_udp_video_top.v | l1_console_r52.txt:324 `RESULT tb_v796_src_arb PASS`（r52 那一跑，非本版）；eth_udp_video_top.v:384 `        else        link_active_r <= \|s_pkts[15:0];`（全件无清零支路，与断言同形） | PASS |
| `--stream` 九条全绿：接管 365 ms／停流交回 67 ms／可逆 182 ms，件写 `build/evidence/verify_0930_1845.txt` | report/perf_report.md:446；report/optimization_log.md:907 | 断言点名的 verify_0930_1845.txt **里没有这三行**；真件是 build/evidence/verify_0930_1848.arb.txt | `grep -c "可逆\|365 ms" build/evidence/verify_0930_1845.txt` = 0；1848.arb.txt:15 `  PASS  V2 接管时限  推流后 owner_eth→1 用时 365 ms（门限 2000）`、:17 `  PASS  V4 停流交回  停流后 owner_eth→0 用时 67 ms（门限 1500）`、:19 `  PASS  V6 可逆（再推又接管）  再推流后 owner_eth→1 用时 182 ms（门限 2000）`、:21 末段 `[ARB] 结论：九条全过` | FAIL |
| 电池 **105 条 / 97.7 s** 全过 | report/perf_report.md:446 | build/evidence/verify_0930_1845.txt | 第 57 行 `RESULT PASS uart_cmd_check  (105 条命令, 97.7 s, 捕获 board/uart_script_capture.txt)`（点名的这份捕获件是工具本机重写、被 `.gitignore` 的 `board/uart_*.txt` 规则挡住的本地件，不入库也不随包） | PASS |
| 板上这一版的板级复验：geom ok=10、105 条、未通过步骤 0；且脚本头明写"**不刷板子**""与电池分开取证" | README.md 的「上板与验证」一节；report/06-validation.md:83-90 | build/evidence/r118_board/board_verify_console.txt；build/board_verify.sh | console:36 `RESULT PASS geom_check（ok=10 fail=0）`；:63 `RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`（同一份本地串口抓取件，被 `.gitignore` 挡住，不入库也不随包）；:66 `RESULT board_verify PASS（判红的步骤：0）`（脚本原话里的"判红"= 未通过项）；board_verify.sh:21 `# 不做什么：不刷板子。三件套（bit/xsa/elf）的下载顺序见 README.md 的"复现三步"第 3 步（xsdb`；:9 `#   与电池分开取证：电池看**回显**，这一条看**像素域真值**` | PASS |
| r118 带流 `drop_words=0`（两次，`eth_live=1 owner_eth=1`），而同一次摘要里 `pkt_err=? frames_bad=? drop_seen=?` 三格是 NOT_MEASURED | report/50-results.md:146；report/06-validation.md:97-99；report/reproduce/README.md:151 | build/evidence/r118_board/bitcycle_console.txt | :13 `  a: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=?`；:14 同形 `b:` 行 | PASS |
| r116 带流读数 `drop_words=0`、`pkt_err=0`、`frames_bad=1` 不增长，件 `build/evidence/r116_board/health_*.json` | report/50-results.md:145 | build/evidence/r116_board/health_t12.json、health_t34.json（glob 里另三件是拒读） | 两件第 1 行内均含 `"drop_words":0`、`"pkt_err":0`、`"frames_bad":1`、`"eth_live":1`。警告 同一个 glob 还罩着 health_live1.json／health_live2.json／health_idle.json，那三件读出的是 `[HEALTH] xsdb(cur) 退出码 1` 与 `[HEALTH] 先确认 JTAG 与 hw_server 可用` ⇒ glob 里既有读数也有拒读 | PASS |
| 「`drop_words=0` 第一次是**零样本通过**（`eth_live=0`），带流重测才作数」；S8 空闲态那一读因此记 NOT_MEASURED | report/06-validation.md:134-94；report/reproduce/README.md:147；board/signoff.md:314 | report/log/issues.md；build/evidence/r118_board/board_verify_console.txt | ISSUES:12782 `### #316 r116 夜：`drop_words=0` 第一次是**零样本通过**（`eth_live=0`），带流重测才作数（02:14）`；board_verify_console:18 `  lane30 src_state → {"eth_tb_ok":1,"eth_live":0,...,"mode":"AUTO","why":"没有流"}`、:21 `  drop_words → 0` | PASS |
| E3「移动白线与红块连续、无撕裂」**过**（原话"现在都很正常"） | board/acceptance.md:91 | build/evidence/r92_eye_capture2.txt | :3 `[STAT] ctrl thr=80 src=1 zoom=1 bilin=1 zsel=4 zman=1 pub=0 sd=1 frames=4398 playing=1 sel=000 gm=0.00 (PL owns UDP datapath) mode=0 geom=40400000 osd=1`；:8 `>> split 50`。警告 版本 r92；件只记设态，"无撕裂"是眼睛判的 | PASS |
| 「#170/#171 的**板级** abort 注入仍是模块级凭据齐、板级空着」（拷贝中途被打断后撕裂帧不再显示） | board/acceptance.md:61；board/signoff.md:168-162 | 盘上没有板级注入读数；signoff 自己写着没有任何一份 r118 件把它写成一次判据运行 | 能定它的件 = 一次 `build/board_verify.sh` 带 `--drop-packet` 注入 ＋ 同轮 `eth_ready` 读回（`report/optimization_log.md:908` 也把这格登记为"欠一格"） | 未见凭据 |
| 「E1/E2/E3/E4/E4r/E5/E6 在 `board/acceptance.md` 本次实读都有"谁点的头 + 什么时候 + 原话"」 | report/60-failure-analysis.md:497 | board/acceptance.md:89-98 | :71 `**过（同上，原话"现在都很正常"）**`；:76 `**过（"四角在不在屏内"这一半 2026-10-04 08:3x 由队员判完，原话「现在屏幕没问题了四角都在屏幕内」**`；:98 `**过（2026-10-04 07:52 前，队员原话「0度」）**` | PASS |
| 全设计 setup WNS **0.739 ns**／WHS **0.052 ns**／失败端点 **0 / 51135** | README.md 关键数字表中「全设计 setup WNS」那一行；report/04-resources.md:42；report/50-results.md:39；report/60-failure-analysis.md:285 | build/timing_summary.rpt；build/r118_gates.txt；data/metrics.csv | timing_summary.rpt:151 `      0.739        0.000                      0                51135        0.052        0.000                      0                51135        0.264        0`；r118_gates.txt:10 `  WNS (ns)               0.739        >= 0                         PASS`；metrics.csv:5 `全局 setup WNS,核心,0.739,ns,失败 setup 端点 0 / 总端点 51135；板上 r118 bit cd04907e1369` | PASS |
| 逐时钟 setup/hold：`eth_rxc` 0.739/0.052、`clk_fpga_0` 1.850/0.053、`clkout0_1` 3.630/0.059、`sys_clk` 14.876/0.222 | README.md 关键数字表中「逐时钟 setup 余量」那一行与「保持时间」那一行；report/05-timing.md:30 | build/evidence/r118_after_roster_probefmt.txt | 第 5 行内 `slack=0.739ns` 与 `margin_pct=9.24`（该件用竖线分列：`ROSTER`／`setup`／`clk=eth_rxc`／`period=8.000`，故此处只引不含竖线的两段）；第 1 行内 `slack=1.850ns`；第 3 行内 `slack=14.876ns` | PASS |
| r118 相对 r114：**8 对逐位相同、losses=0** | report/05-timing.md:44-49 | build/evidence/r118_strict_b1.txt；build/r118_verdict.txt | strict_b1 末行 `B1 pairs_compared=8 losses=0 verdict=GREEN`；r118_verdict.txt:2 `R118 B1_strict B1 pairs_compared=8 losses=0 verdict=GREEN` | PASS |
| LUT 14154（26.61 %）／FF 8188（7.70 %）／BRAM 95.5（68.21 %）／DSP 19（8.64 %） | README.md 关键数字表中「BRAM / LUT / FF / DSP」那一行；report/04-resources.md:11-16 | build/utilization.rpt | :35 `\| Slice LUTs                 \| 14154 \|     0 \|          0 \|     53200 \| 26.61 \|`；:40 `\| Slice Registers            \|  8188 \|`；:106 `\| Block RAM Tile    \| 95.5 \|`；:121 `\| DSPs           \|   19 \|` | PASS |
| 同一张表的表头写着「原文片段（该行）」＝逐字引文 | report/04-resources.md:9-11 | build/utilization.rpt | 件里那一行是 `\| Slice LUTs                 \| 14154 \|     0 \|          0 \|     53200 \| 26.61 \|`（列间为对齐空格）；文档引的 `\| Slice LUTs \| 14154 \| 0 \| 0 \| 53200 \| 26.61 \|` 逐字 grep **不中**（`grep -c` = 0）⇒ 数值 PASS、"逐字"这一句 FAIL | FAIL |
| `methodology.rpt` 报告头 `Checks found: 446`；SYNTH-5 336／SYNTH-6 98／TIMING-18 7／DPIR-1 2 | report/04-resources.md:49-56；report/40-optimization.md:87 | build/methodology.rpt | :26 `             Checks found: 446`；:32 `\| SYNTH-5   \| Warning  \| Mapped onto distributed RAM because of timing constraints \| 336    \|`；:36 `\| TIMING-18 \| Warning  \| Missing input or output delay                             \| 7      \|`（同样有空格折叠问题，见上一行） | PASS |
| 动态 **2.213 W**（片上合计 2.391 W）、估算结温 **52.6 °C**、工具置信度 **Low** ⇒ 是估算不是实测 | README.md 关键数字表中「功耗」那一行；report/04-resources.md:66 | build/power.rpt | :36 `\| Dynamic (W)              \| 2.213        \|`；:33 `\| Total On-Chip Power (W)  \| 2.391        \|`；:40 `\| Junction Temperature (C) \| 52.6         \|`；:41 `\| Confidence Level         \| Low          \|` | PASS |
| 功耗那一行的指路是「`data/metrics.csv` 第 20–21 行」 | README.md 关键数字表中「功耗」那一行 | data/metrics.csv | 第 21 行是 `人眼判据,验收,36,行`、第 22 行是 `ETH 入流零丢包（演示工况）,实测,0,丢帧 / 坏帧`；功耗两行实际在 :27 `实现后动态功耗,资源,2.213,W` 与 :28 `结温估算,资源,52.6,℃`。警告 同页其余指路按"数据行"数法自洽（第 4–6 行=WNS 族、第 11 行=SD 帧率）⇒ 只有这一格指错 | FAIL |
| 显示 1024×600 @ **59.5 Hz**（不是 50 Hz）；SD 本地播放 **29.8 – 30.0 fps** | README.md 的「关键数字与出处」一节；report/01-overview.md:32 | data/metrics.csv | :3 `显示像素时钟,核心,50,MHz,面板 1024×600；H_TOTAL 1344、V_TOTAL 625 ⇒ 场频 59.5 Hz`；:4 `显示分辨率与场频,核心,1024×600 @59.5`；:12 `SD 本地播放帧率,实测,29.8 – 30.0,fps`。警告 终审 C2 判的是"点名的证据件在盘上"，不是"数值复算过"（`build/evidence/r120_final_gate.txt`:2） | PASS |
| 本版不带 RGMII 收口输入窗 ⇒ 那 5 个 I/O 端点**未检查**，未检查不等于满足；窗退回候选件 1.200/2.800 | README.md 关键数字表中「全设计 setup WNS」那一行；report/04-resources.md:46-47；README_EN.md:70 | data/metrics.csv；src/constraints/r116_rgmii_input_window.xdc | metrics.csv:6 `全局 setup 失败端点,核心,0,个,总端点 51135；片内路径为零违例；收口 I/O 的 5 个端点当前无输入窗 = 未检查（H5：未检查不等于满足）`；候选件 :32 `set_input_delay -clock eth_rxc -min  1.200 [get_ports {eth_rxd[*] eth_rx_ctl}]`、:33 同形 `-max  2.800` | PASS |
| 带窗那一版的证明：tap 0-31 内 hold 与 setup 区间不相交（hold ≥ 44.8、setup ≤ 21.8；钟树角间差 3.411 ns、数据侧 0.467 ns），件点名 `build/evidence/r115_window/probe3_console.txt` | README_EN.md:70 | 点名的件里**只有原始 slack/skew 读数**，没有那四个导出数；导出数在 report/timing/rgmii_window_model.md:324,326,332-333（而 `docs/` 不随包） | probe3_console.txt:107 `W3S tap0 HOLD Slack (VIOLATED) :        -2.822ns Data Path Delay:        1.976ns Clock Path Skew:        5.008ns Clock Uncertainty:      0.835ns`、:111 `W3S tap0 SETUP Slack (MET) :             2.005ns`；rgmii_window_model.md:324 `HOLD (带 0.800)  = −2.822 + 0.0630·τ   ⇒ 要 ≥ 0 需要 τ ≥ 44.8`；`grep -n "44.8\|3.411" build/evidence/r115_window/probe3_console.txt` 无命中 | FAIL |
| HDMI 源端逐脚实测：互对最差 **0.065 ns**（限 4.000）、对内最差 **0.001 ns**（限 0.300） | report/known-limitations.md:13 | build/evidence/r119_window_check.txt | :8 `W7 互对离散max角     判 8 项 上限=4ns(0.20×20.000) 逐道偏差=[-0.041,-0.065,-0.049]ns 最差=0.065ns PASS`；:10 `W9 对内离散          判 10 项 上限=0.3ns(0.15×Tbit=2.000ns) 逐对P-N=[-0.001,-0.001,-0.001,-0.001]ns 最差=0.001ns PASS` | PASS |
| 同一句里补的「凭据件**含 5 份输入的现算 md5 头**」 | report/known-limitations.md:14 | 点名的 r119_window_check.txt **没有 md5 头**（11 行全是 W1–W10 ＋ 汇总行）；md5 头在 build/evidence/r120_window_check.txt:2-6 | r120_window_check.txt:1 `HEAD 输入件指纹（现算，非手抄）`、:7 `HEAD 读数器=nodev24.21.0 输入件=5 缺件=0 判 5 项`；`grep -n "md5" build/evidence/r119_window_check.txt` 无命中 | FAIL |
| 眼图、抖动、占空比、边沿速率**未实测**（`【未实测】`） | report/known-limitations.md:16 | 仓库内没有示波器／探头类采集件 | 断言本身就是"没做"，也没有任何件声称做过；门槛已写在 report/io/hdmi_cts_source_window.md:33 `眼图至少累计 **400,000 UI**；占空比／电平类至少 **10,000** 条波形；示波器最短记录长度 **16 M**` | 未见凭据 |
| 器件与工具版本 **Vivado/Vitis 2025.2.1（build 6403652）＋ xc7z020clg484-2**，唯一权威源 `report/declarations.md` | report/known-limitations.md:73；report/final-gate.md:18 | report/declarations.md；build/evidence/r115_window/probe3_console.txt | declarations.md:9 `part: xc7z020clg484-2`、:10 `vivado: 2025.2.1`、:11 `vivado_build: 6403652`；probe3_console.txt:3 `  **** SW Build 6403652 on Thu Mar 19 … GMT 2026`（被引工具横幅里那一串是该构建的生成时刻，逐字在件里） | PASS |
| 整屏逐像素判据：`^PASS` **161** 行＋`^FAIL` **1** 行；判据名去重 **47** 个；`sim/` 下 `tb_*.v` 共 **82** 支 | README.md 的「项目简介（这个系统做什么）」与「关键数字与出处」两节（「限制与未通过项」一节已并进 `report/08-limits.md` 与 `report/known-limitations.md`，首页只留 `C5c` 那一格读数与指路）；report/06-validation.md:37-25；report/reproduce/README.md:68 | build/tb_v98_report.txt；sim/ | `grep -c "^PASS" build/tb_v98_report.txt` = 161、`grep -c "^FAIL"` = 1；第 55 行 `FAIL C5c frame head is not the previous frame's tail`；`grep "^PASS"` 取第 2 列 `sort -u` = 47；`ls sim/tb_*.v | wc -l` = 82（这一格原先读到的 81 支是新增 `sim/tb_icmp_tx_cksum.v` 之前的数）；第 1 行 `# provenance fpver=norm1 top_md5=56c269602e18 tb_md5=1c918c92200f rtl_md5=07570b1ac1b4` | PASS |
| 「一条主判据前面都挂一条**空集守卫**……没有样本的绿不许存在」 | report/06-validation.md:32-36 | build/tb_v98_report.txt | :18 `PASS C4a rows judged \| this (angle, zoom) cell must actually have content rows, else C4b below means nothing`；:14 `... false-green on an empty set (#78)` | PASS |
| 发布前检查末行 `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；24 项 = 23 绿／1 红、两跑逐字节一致 | README.md 的「限制与未通过项」一节；report/final-gate.md:41-42；report/06-validation.md:48-56 | build/r118_gates.txt；build/r118_gates_final.txt；build/evidence/r118_board/gatesc_summary.txt | r118_gates.txt:53 末段 `# 结尾必须把**范围**一起念出来：判定 24 项、未判 0 项。`、:54 `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；gatesc_summary.txt:1 `GATESC done id=identical green=23 red=1`；r118_gates_final.txt:3 `身份：system.bit md5=cd04907e1369` | PASS |
| 「`build/gates.sh` 里 `say` 的调用共 **24 处**（`grep -c` 数出）」 | report/06-validation.md:51-52 | build/gates.sh | 按同一条命令数出 `grep -cE "^[[:space:]]*say " build/gates.sh` = **28**（`grep -c "say "` = 34）；24 是**运行时** `NSAY`（gates.sh:173 `NSAY=0`、:177 `    NSAY=$((NSAY+1))`）⇒ 静态调用点与运行时项数不相等（if/else 多支共用一项），把两者划等号这句不成立 | FAIL |
| 唯一那条红 = 声明过的 `C5c`；采纳判据是"除声明项外无红"；且"改前必须红、改后恰好绿"的变异对照**还不存在** | report/known-limitations.md:30-35；report/08-limits.md:9-10,23；report/known_issues.md:49 | build/r118_gates.txt；build/tb_v98_report.txt；report/known_issues.md；build/evidence/r104_c5head_band.txt | r118_gates.txt:34 `  顶层台架 tb_v98    top=56c269602e18 FAIL行=1 指纹(norm1):fresh fresh fresh 同一次跑且无 FAIL      FAIL`；known_issues.md:12 `### 1. 帧头若干行的读侧绕回（`#98`）—— 顶层台架上唯一一条故意留红的判据`、:49 `改后恰好绿这一条"的变异对照（本项目的规矩），而那条对照还没建。**留红是有意选择：`；r104_c5head_band.txt:26 `C5  judged=3564 bad=0 \| head rows=36 wrong=24 (OFF_LINES=4, col=512)` | PASS |
| 三态 token 是脚本自己打印的（`NO-VERDICT-LINE`、`GATES: PARTIAL`、`RESULT board_verify FAIL`），且"红是结论，没数不是结论" | report/06-validation.md:9-18 | build/sim/run_one.sh；build/gates.sh；build/board_verify.sh | run_one.sh:36 `        echo "VERDICT $TB: NO-VERDICT-LINE（这支台架一条判定都没打，去数判据条数）`；:41 `    # 3 与 4 必须分开：红是结论，"没数"不是结论（#163/#164 那一族的另一半）。`；gates.sh:584 `    echo "GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行）`；board_verify.sh:265 `echo "RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳"` | PASS |
| 「无凭据直接判红，不判'没发现所以干净'」（两项 NOLOG）＋读不到时 `FATAL 解析不到` 且 `exit 2` | report/06-validation.md:71-75；report/reproduce/README.md:132 | build/gates.sh | :212 `    say "端口宽度警告 8-689" "NOLOG" "无凭据=未验" 0`；:232 `    say "多驱动 net 8-685x" "NOLOG" "无凭据=未验" 0`；:164 `        case "$x" in ""\|NA) echo "FATAL 解析不到 \$v —— 报告格式变了？不要拿空值当 0 判绿"; exit 2;; esac`；:32 `    [ -f "$f" ] \|\| { echo "FATAL 缺报告：$f"; exit 2; }` | PASS |
| 终审 C1–C12 = 绿 **8**／红 **3**／未测 **1**，"有红项，不得提交"；逐格 C1 比过=88 冲突=0、C2 行=28 全指到=28、C4 违规=286 豁免=22、C6 条目=58 一致=yes、C12 绿=12 加总=12/12 | report/final-gate.md:18-30；report/submission-checklist.md:15,19,23,27 | build/evidence/r120_final_gate.txt | :16 `GATES 终审 C1–C12：判定 12 项 绿=8 红=3 未测=1 有红项，不得提交 FAIL`；:1 `... 比过=88 同值抄写=0+88 器件冲突=0 版本冲突=0 引文豁免=1 PASS`；:2 `... 行=28 全指到=28 缺或无路径=0 PASS`；:7 `... 跟踪文件=3601 违规=286 点名豁免=22 ... FAIL`；:9 `C6 技能包索引一致 判 6 项 rc=0 gen_index --check 条目=58 判 58 项 一致=yes PASS PASS`；:15 `... 绿=12 红=0 未测=0 判据行=12 加总对账=12/12 PASS`。警告 同目录 r120_final_gate_2.txt:13 读作 `绿=4 红=6 未测=2`——两份都在盘上且都被跟踪，"哪一份是本轮"没有任何件自称 | PASS |
| 「红项不靠放宽判据消除：用诱饵文件与 10 条 `--self` 对照证明改后的尺子仍然会红（`--self` 判 10 项 PASS）」 | report/final-gate.md:37 | 盘上没有这把尺子的 `--self` 输出件：`grep -rln "check_repo_consistency" build/evidence/` 无命中；件内的 10 例是**代码**（build/checks/check_repo_consistency.mjs:130 `function selftestC2()` 起的 6 条 ＋ 4 条 C3 对照），不是运行结果 | 能定它的件 = 一次 `node build/checks/check_repo_consistency.mjs --self` 的落盘转录（建议 `build/evidence/r120_consistency_self.txt`）＋ 那枚诱饵文件本身（现在不在树里） | 未见凭据 |
| C1「改成只有取值不同才算红，并用一个诱饵文件证明它仍会红」 | report/known-limitations.md:51 | 诱饵文件与运行转录都不在仓库内；且脚本自述的 `--self` 射程不含 C1 | build/checks/check_repo_consistency.mjs:14 `const SELF = process.argv.includes('--self');   // --self 只跑 C2 的对照例，不做全仓扫描（免得自检本身要读 3000+ 份文件）` | 未见凭据 |
| 「`report/repro-check.md` 的**逐条实跑读数**：PASS=91／FAIL=30／未测=32」（终审 C9 判红） | report/final-gate.md:26；report/known-limitations.md:39 | build/evidence/r120_final_gate.txt；report/repro-check.md；build/checks/check_repo_consistency.mjs | 件:12 `C9 A/B/C 路径复现演练 判 9 项 PASS=91 FAIL=30 未测=32 FAIL` 确在；但 mjs:266 的实现是 `const nm = (rc.match(/NOT_MEASURED/g) \|\| []).length, pass = (rc.match(/ PASS/g) ...` ⇒ 数的是**全文 token 出现次数**；被数的那件自己写着条数：repro-check.md:37 `| 两轮相加 | 81 | 61 | 1 | 19 |`，:38 `**以本表 43 / 38 两个分母为准**` ⇒ 91/30/32 不是条数口径 | FAIL |
| 「30 条 FAIL **没有逐条归因**」 | report/submission-checklist.md:22；report/known-limitations.md:40 | report/repro-check.md §3 的红项表（按条登记处） | 那里逐条登记的是 R2、R9、R15、R16 一族：:147 `| R16 | **本件第一轮的内部计数不自洽（判据② 的分母与 §1 的表对不上）** |`；在这件里按"30 条 FAIL"数不到 30 行 FAIL。要定它 = 把 C9 改成逐条状态计数，或在 `report/repro-check.md` 补一张 30 行的归因表 | 未见凭据 |
| 技能包门禁 **12 项全绿、无红无未测**，两跑逐字节一致；脚本自测 **判 40 项 pass=6 fail=0 nm=0** | report/final-gate.md:38-40；report/submission-checklist.md:23 | build/evidence/r120_gates_skill_a.txt、..._b.txt；build/evidence/r120_selftest.txt | 两件 :13 同为 `GATES 技能包：判定 12 项 绿=12 红=0 未测=0 —— 全绿：无红项、无未测项 PASS`；`cmp` 两跑无输出（逐字节一致）；selftest:7 `SELFTEST node=v24.21.0 scripts=6 判 40 项 pass=6 fail=0 nm=0 PASS` | PASS |
| 「判据 selftest：`该脚本此刻不存在` ⇒ `NOT_MEASURED`」＋「索引由目录生成 ⇒ 待验证（要等条目到位再跑一次 `--check`）」 | report/07-skill-distillation.md:46-47 | 本表写下这一行时，被引断言点名的自检脚本 skills/scripts/selftest/run_all.sh 在树里存在且被 git 跟踪（技能包 2026-10-04 按交付要求重建后这一条旧条目名已不存在，同一职责的现入口是 skills/_meta/run-all-checks.mjs，两个名字都不是"没有脚本"）＋ build/evidence/r120_selftest.txt；build/evidence/r120_final_gate.txt | selftest:7 `SELFTEST node=v24.21.0 scripts=6 判 40 项 pass=6 fail=0 nm=0 PASS`；final_gate:9 `C6 技能包索引一致 判 6 项 rc=0 gen_index --check 条目=58 判 58 项 一致=yes PASS PASS` ⇒ 交付文档那两格已被件推翻（口径过期） | FAIL |
| 「本轮 C12 实跑 `绿=7 红=4 未测=1`，其中 G11 selftest 未落地、26 张平铺卡未迁移」 | report/README.md:31 | 本表写下这一行时，这条读数只在一份尚未被 git 跟踪的临时转录里读得到（`git status` 当时显示它是未跟踪件，`git ls-files` 里没有它 ⇒ 随包不可能有它）；现在同一串 `绿=7 红=4 未测=1` 在两份被跟踪的件里读得到（见第 2 节末尾点名的两件），但断言里"G11 selftest 未落地、26 张平铺卡未迁移"那两半在任何件里都没有 ⇒ 判定仍是 | 未见凭据 |
| 签核表 **29 条**（19 机器＋10 眼睛）＝ 25 PASS／0 FAIL／4 NOT_MEASURED，且给出复跑核对命令 | board/signoff.md:311-305 | board/signoff.md（该文件自带的核对命令复算） | :302 `观察项分母 = 29 条（S1..S19 = 19 条机器判据 + E1/E2/E3/E4a/E4b/E4c/E4r/E5/E6/E6b = 10 条眼睛判据）`；核对结果：`grep -c '^### [SE]'` = 29、`grep -c '^- 判定：PASS'` = 25、`grep -c '^- 判定：FAIL'` = 0（无命中，与断言一致）、`grep -c '^- 判定：NOT_MEASURED'` = 4；五个字段行计数各 = 29 | PASS |
| 「被记为 PASS 但无回读或无证据的条目数 = **0**」 | board/signoff.md:354 | build/evidence/p16c/evidence_existence.txt | :2 `# 分桶：A=真指路且不在盘上（必须 0）；B=写法（通配/占位）；C=目录写法（不是某行的证据取值）`；:10 `board/signoff.md 点名=53 命中=50 A(真缺)=0 B(写法)=0 C(目录)=3` | PASS |
| 变异对照分支 **5 条**，规矩是"一次变异只许红它声称红的那一条" | report/50-results.md:151；data/metrics.csv:16 | build/sim/mut_control.sh | :107 `REFUSE: 不认识 mutation '$MUT'（现有：pipeline \| osd_inchar \| osd_addr \| osd_inchar_all \| bilin_ky_fold \| cdc_full_next）`；`grep -cE "^(pipeline\|osd_inchar\|osd_addr\|osd_inchar_all\|bilin_ky_fold)\)" build/sim/mut_control.sh` = 5。警告 该行点名的"证据文件"是脚本本体，不是某次运行的件 | PASS |
| H5 那一半：**6 个输出端口没有任何 `set_output_delay`**（`led[0]`、`led[1]`、`tmds_clk_p`、`tmds_data_p[0..2]`） | report/08-limits.md:53-49 | build/evidence/r113_io_debt.txt（随包）＋ report/timing/debt_ledger.md:143（**不随包**） | r113_io_debt.txt:25 `IODEBT-PORT led              output  bits=2   BARE`、:26 `IODEBT-PORT tmds_clk_p       output  bits=1   BARE`、:28 `IODEBT-PORT tmds_data_p      output  bits=3   BARE`；:42 `IODEBT I4_baseline_no_growth  report=in_bare:5,in_fp:2,out_bare:6,out_fp:6 must_not_exceed=5,2,6,6 GREEN`；debt_ledger.md:143 `| no_output_delay 里"没有任何 output delay 的端口" | 6（HIGH） | **6**（`led[0] led[1] tmds_clk_p tmds_data_p[0..2]`）`。警告 随包那件的 `bare_out` 名单还含 `tmds_*_n／eth_mdc／eth_mdio`，与 `check_timing` 的 HIGH 缺口 6 是两套量纲，不可相加 | PASS |
| 「**一条 `set_output_delay` 都还没进约束**」 | report/08-limits.md:71 | report/io/hdmi_cts_source_window.md；src/constraints/；build/tcl/build_system_axigpio.tcl | 该文 :5 `本轮**没有改动任何代码或约束文件**。` 成立；但 `grep -c "set_output_delay" src/constraints/*.xdc` 读出 r119_hdmi_source_window.xdc = **3**、r119b_hdmi_tp1_pinclk.xdc = **2**、r116_rgmii_input_window.xdc = **1** ⇒ 准确说法是"没进**默认构建**"：build_system_axigpio.tcl:63 `if {[info exists ::env(VP_R119_TMDS_WINDOW)] && $::env(VP_R119_TMDS_WINDOW) eq "1"} {`、:69 `  puts "VP_R119_TMDS_WINDOW off（候选件 src/constraints/r119_hdmi_source_window.xdc，缺的是一次量名册的构建）"` | FAIL |
| 「不许写'已按 HDMI CTS 校验'」：CTS 表不可公开，凡 CTS 部分全是转述（代理） | report/08-limits.md:66-68 | report/io/hdmi_cts_source_window.md | :7 `> 先说结论的诚实边界：**HDMI CTS（Compliance Test Specification）本身不公开**，它挂在 HDMI Adopter Extranet 上（见第四节原文引用）。`；:86 `下面每条都标了数从哪一行回来。**没有一条是 CTS 表**（CTS 表不可公开，见第四节）；凡"代理值"我都写代理。` | PASS |
| 行为缺陷表：SD 播放中拔卡 ⇒ 永久冻帧、插回不恢复（ISSUES #94，只记录未修）；收侧 ARP/ICMP 没有错误源（#205 仍欠） | report/known-limitations.md:69,83 | report/log/issues.md | :3614 `## #94（2026-09-26 17:1x）SD 播放中**拔卡**：画面永久冻在最后一帧，插回也不恢复`；:8220 `### `#205`（中）：收侧 ARP/ICMP 这一支没有任何错误源` | PASS |
| 行为缺陷表：ping 应答器上板几分钟后变哑（**与载荷长度无关**），状态"板级判据仍未验" | report/known-limitations.md:70 | report/log/issues.md（同族的后续两处） | :9003 `## 2026-10-01 17:3x **#218 找到根因**：一条 `ping -l 0` 就能把 ICMP 接收机永久楔死（#216 的解答，#188 的板级答案）`；:9012 `- 复位后 `ping -n 4` 连测 7 轮全 **4/4**（应答器健康，不会自己变哑）；`；:9019 `**更正我自己**：昨晚到今天下午我写过"变哑与载荷长度无关"，那是**错的方向**`；:9676 `⇒ 板上那份 `ping 应答器几分钟后变哑`（#216/#188）的阴影**没有回来**。凭据 `build/r104_board_ping.txt`` ⇒ 交付文档那一行把已被更正的口径又抄了一遍，且"未验"与 :9676 的凭据件相抵 | FAIL |
| 报告分章 FAIL：`10-background`、`20-principle`、`30-partition-if`、`novelty-claims`、`prior-art-search` 五章未落地（`ls report \| grep -E '^(10\|20\|30)'` = 0 行）；终审 C3 死引用 = **3** 条（其中一条是 `report/README.md → report/claims-vs-evidence.md`） | report/submission-checklist.md:17；report/final-gate.md:20；report/README.md:26 | report/ 目录本身＋build/evidence/r120_final_gate.txt | final_gate:6 `C3 文档内路径存活 判 3 项 扫=204 份 检查路径引用=1154 死引用=3 豁免=碎片95/运行期6/台账205 FAIL`；那一行 `例:` 三条点名的是 `docs/` 那层的旧名（该层今日 0 个跟踪件，`git ls-files docs/ \| wc -l` = 0），逐条读件 :6，本行不重抄；report/README.md:26 `**三份都不在盘上** ⇒ 归 **P19（进行中）**`；`ls report` 确实无 `10-/20-/30-` 三件。警告 本文件写下后，第三条死引用的"路径存活"半边成立，但 C3 转绿要下一轮重跑那把尺子 | PASS |
| 许可与再分发 FAIL：「`report/` 与 provenance-and-licenses 一页未写（P20 截停）」 | report/submission-checklist.md:26 | 盘上现状 ＋ `git status --short report/` ＋ `docs/` | `report/` **此刻在盘上**（13613 B），而 `git status --short report/` = `?? report/`（未被跟踪）⇒ "未写"已被盘上实况推翻；`docs/provenance*` 仍是 `No such file or directory`。因未被跟踪，"不随包"这半边仍成立（导出器从 `git archive HEAD` 起步） | FAIL |
| 工程本体计数：`src/rtl/` 80 个 `.v`、`sim/` 137 个跟踪文件、`board/` 76 个、`src/ps/` 3 个 `.c/.h`；学习文档**不随包**（`report/study/`、`docs/walkthrough/` 0 个跟踪文件） | report/submission-checklist.md:9-14,31 | 仓库索引本身（`git ls-files`）＋ build/evidence/r113_precompile_fp.txt | `git ls-files "src/rtl/*.v" \| wc -l` = 80；`git ls-files sim \| wc -l` = 137；`git ls-files board \| wc -l` = 76；`git ls-files src/ps` = 5 个，其中 `.c/.h` 恰 3 个（main.c／sd_play.c／sd_play.h）；`git ls-files report/study docs/walkthrough \| wc -l` = 0；fp 件:2 `files=80`（r113 那一跑，与当前值相同） | PASS |
| 红项 R2 保留：`data/metrics.csv` 写 141 条、盘上那份是 161/1；冲突 5 也登记：`board/README.md` 复述 WNS 0.720／0 of 50890 而现件是 0.739／0 of 51135 | README.md 的「限制与未通过项」一节（原引内容在本版 README 已无对应段落）；report/70-reproduce.md:150 | data/metrics.csv；build/tb_v98_report.txt；board/README.md；build/timing_summary.rpt | metrics.csv:15 `整屏逐像素判据,核心,141,条`（自述 `141 = 该文件里 ^PASS 行数 140 加 ^FAIL 行数 1`，头部 `top_md5=2bf2ceeede07`）vs 盘上件 :1 `top_md5=56c269602e18` ⇒ 两份不同源；board/README.md:94 `| 全设计时序 | setup WNS **0.720 ns** / hold WHS **0.033 ns` ＋ `失败 setup/hold 端点 **0 / 50890**` vs timing_summary.rpt:151 那行的 0.739…51135 ⇒ 冲突为真且已登记 | PASS |
| 逐字抄自脚本用法头的行号锚点（`build/sim/run_one.sh:2/:11/:58/:117`、`build/gates.sh:11-12/:96/:363`、`build/board_verify.sh:113-114`、`build/tcl/build_system_axigpio.tcl:45`） | report/reproduce/README.md:10-15,55-77,100-106 | build/sim/run_one.sh；build/gates.sh；build/board_verify.sh；build/tcl/build_system_axigpio.tcl；build/tb98_report.sh | run_one.sh:2 `# 快速单台架回归（绕开全量 run_sim.tcl 的两分钟编译），用法：run_one.sh <tb_name>`、:11 `# `--verdict <tb> <run.log>`：**只解析判定**，不起仿真、不碰 xsim。`、:117 `#   现在退出码：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 **判红** / 4 认不出判定行。`；gates.sh:11 `#   bash build/gates.sh                 # 读 build/ 里当前这套报告（= 最近一次构建）`、:96 `CDCBASE=${CDCBASE:-build/cdc_baseline.txt}`；board_verify.sh:114 `[ -f "$VP_XSDB" ] \|\| { echo "REFUSE: 找不到 xsdb（当前 $VP_XSDB）`；build_system_axigpio.tcl:45 `if {[info exists ::env(VP_R116_IO_WINDOW)] && $::env(VP_R116_IO_WINDOW) eq "1"} {` | PASS |
| 「用法头里唯一一条由这支脚本自己写出的调用形式（`build/tcl/build_system_axigpio.tcl:247` 逐字）」＋「全文 grep 只命中第 247 行那一处」 | report/reproduce/README.md:26,37,219 | build/tcl/build_system_axigpio.tcl | 第 247 行实际是 `set bad_addr 0`；那句串在 **:265** `# 所以留一个只建 BD 就退出的口子：`vivado -mode batch -source 本脚本 -tclargs bd_only`。`（`grep -n "mode batch"` 全件仅此一处），:266 才是 `if {[lindex $argv 0] eq "bd_only"} { puts "BD_ONLY_DONE"; exit 0 }` ⇒ 断言的"逐字"成立、**行号指错三处**（:26、:37、:219） | FAIL |
| OSD 共 5 行，`N_LINES = 5` 见 `src/rtl/video/osd_overlay.v:19` | report/01-overview.md:29 | src/rtl/video/osd_overlay.v | :19 `    parameter N_LINES = 5,` | PASS |
| 「本表**按行记版本**……把某一行的数当'这一版验过'之前，先看这一行有没有 rNN 字样」⇒"机器判据 10 条全部通过"不能整体算 r118 | report/06-validation.md:102-105；board/acceptance.md:112 | board/acceptance.md | :8 `本表**按行记版本**：第 1/2/3/5/9/10 行是 r94（板上那一份位流 `a1465f29c9e4`，源 `rtl_md5=526321488fed`）`；:112 `- 机器判据 10 条全部通过（第 10 条是 #57 的结构判据），凭据都在表里点名；`；:58-59 那两行的读数点名 `build/board_temp_r97.txt` 与 WNS 0.720／0 of 50890 ⇒ 版本确实分属 r94/r96/r97 | PASS |
| 板上现在跑的是当前这一版位流，身份 `cd04907e1369`，由三步 JTAG 链刷入；首页那句还给了一个刷入时刻（本表不复述） | README.md 的「限制与未通过项」一节；README_EN.md:70；board/signoff.md:35 | build/evidence/r118_board/board_now.txt；build/evidence/r118_bit_md5.txt；build/evidence/r118_board/bitcycle_console.txt | board_now.txt:1 `板上现在 = r118（刷入时刻见该件首行，bit_cycle rc=0 board_verify rc=0）`（**这句自己在件里**）；bitcycle_console.txt:5-6 两步各带自己的时刻，写的是 `2) program_pl build/evidence/r118_bit/system.bit` 与 `pl rc=0 PROGRAMMED=2`；board_verify_console.txt:1 的抬头同样带时刻（`== board_verify … ==`）；bit_md5:1 `cd04907e1369` ⇒ 位流身份 PASS；但首页正文那句刷入时刻在任何日志件里都没有对应行（各件的时刻只记到三步链自身的动作）⇒ signoff.md:26 已把这半句挂进问题清单 Q3 | FAIL |
| 结论"现在不能宣称交付终审全绿"，三条红＋一条未测都写明缺什么 | report/final-gate.md:32-35；report/submission-checklist.md:17,22,26,27-30 | build/evidence/r120_final_gate.txt | :16 `... 绿=8 红=3 未测=1 有红项，不得提交 FAIL`；:6/:7/:12 三条 FAIL 与 :8 一条 `NOT_MEASURED`（`C5 许可与卫生机检 判 5 项 被调脚本 300 s 未返回`）逐条在件里 ⇒ 没有任何一件被读成"全绿" | PASS |

## 2. 未见凭据那 6 行汇总（缺口，不是失败）

| # | 缺的断言 | 出处 | 补上它需要的凭据 |
| --- | --- | --- | --- |
| 1 | 屏上 `ROT:` 读 0 可被机器复核 | report/08-limits.md:53-42 | 机读角度口落地后的一次 lane/`STAT` 读数件（方案件 `build/r113_angle_lane_plan.md` 已在盘上） |
| 2 | 拔网线 ≤0.5 s 让位到 SD 的时间量 | report/01-overview.md:30 | 一次带时刻标注的"拔线→`[STAT] src=` 翻转"板级记录（现有 `--stream` 那族测的是停流不是拔线） |
| 3 | #170/#171 的板级 abort 注入 | board/acceptance.md:61；board/signoff.md:168-162 | 一次带 `--drop-packet` 注入 ＋ 同轮 `eth_ready` 读回的板级件 |
| 4 | 眼图／抖动／占空比／边沿速率（HDMI 源端合规） | report/known-limitations.md:16 | 示波器 TP1 采集件（采集门槛已写在 `report/io/hdmi_cts_source_window.md`:33） |
| 5 | `check_repo_consistency.mjs --self` 判 10 项 PASS ＋ 诱饵文件 | report/final-gate.md:37；report/known-limitations.md:51 | 该命令的落盘转录 ＋ 诱饵文件本身；另需先修 `--self` 的覆盖范围（脚本 :14 自述只含 C2/C3，不含 C1） |
| 6 | 「30 条 FAIL 未逐条归因」里的那 30 条 | report/submission-checklist.md:22 | 把 C9 改成逐条状态计数，或在 `report/repro-check.md` 补一张 30 行归因表 |

另有一条与"未见凭据"同级、但形态是"写下本表时那份件还没入库"的：`report/README.md:31` 那句 `绿=7 红=4 未测=1`
当时只落在**未被 git 跟踪**的读数里（`git ls-files` 里没有它 ⇒ 随包不可能有它），故在主表里判 `未见凭据`。
盘上现在能被包带走的同类读数有两处，指的都是技能包那 12 项：`build/evidence/r120_final_gate_2.txt`:12
`C12 技能包门禁（G1–G12 调用） 判 12 项 绿=7 红=4 未测=1 FAIL` 与 `build/evidence/r119_gates_now.txt`:13
`GATES 技能包：判定 12 项 绿=7 红=4 未测=1 —— 有红项，不提交 FAIL`；而主表那一行要证的"其中 G11 selftest
未落地、26 张平铺卡未迁移"那两半，两件里都没有 ⇒ 缺口从"读不到这个数"收窄成"读不到那两半"，判定仍保持
`未见凭据`，等下一轮把那一跑整条落到一个被跟踪的件名下再改。

## 3. 重算这张表计数的唯一一条命令

在仓库根执行（只读本文件，不调用任何检查工具）：

```bash
f=report/claims-vs-evidence.md
echo "行数=$(grep -cE '\| (PASS|FAIL|未见凭据) \|$' $f) \
PASS=$(grep -cE '\| PASS \|$' $f) \
未见凭据=$(grep -cE '\| 未见凭据 \|$' $f) \
FAIL=$(grep -cE '\| FAIL \|$' $f)"
```

这条命令只认"行尾那一格是三态词之一"，而第 2 节的表格行与正文行都不以三态词收尾，所以不会误计。
本表把片段里的竖线一律写成 `\|`，避免与列分隔符混同；若某行的判定格里追加了说明文字，
这条命令会漏计那一行——所以本表的判定列**只放三态词**，说明一律写在片段列里。

## 4. 未走完的名单（后续从这里接着做）

断言来源**整份未抽**的文件：

- `report/architecture.md`、`report/modules.md`、`report/build.md`、`report/commands.md`、
  `report/command_precedence.md`、`report/defaults.md`、`report/demo_script.md`、`report/host_guide.md`、
  `report/llm_collab.md`、`report/ai_collaboration.md`、`report/ps_vs_pl.md`、`report/rotation_and_effects.md`、
  `report/board_pins.md`、`report/comparison-notes.md`、`report/90-open-items.md`（这张表只借它做旁证）
- `report/02-architecture.md`、`report/03-algorithm.md`、`report/README.md`（只走了 :46 的三态口径那一句）
- `report/io/`、`report/collaboration/`、`report/figures/`、`report/study/`、`report/timing/` 下的 md
  只作为**凭据件**读过，未从中抽断言（`report/timing/` = 19 个跟踪件、`git ls-files report/timing/ \| wc -l`，随包，是否算交付文档需要先定）

已抽但**只做抽样**的文件（同一文件里还有未走的断言）：

- `README.md` §6 三条复现路径的每条命令状态（只走 §1 表与 §2 红项 R2）
- `README_EN.md` 与 `README.md` 的互译一致性（只核英版数字，未逐行对中文行）
- `board/acceptance.md` 机器判据 10 行的逐行凭据（只抽 :8、:58-59、:61、:71、:76、:92-98、:112）
- `board/signoff.md` S1–S19 的逐条五件（只走 S1、S11、S12、S15、S16、S18 与第 5 节计数）
- `report/40-optimization.md` 的逐轮采纳行（只走第 114 版那一行的 methodology 数）
- `data/metrics.csv` 其余行的"数值 vs 现件"（只走第 3、4、5、6、12、15、16、21、22、27、28 行；
  其余行由交付自检 C2 判"指得到"，本表不替它判数值）

重跑就会改变读数的行：主表里所有以 `build/evidence/r120_*.txt` 为凭据的行（交付自检的三份读数件互不相同：
8/3/1、4/6/2、以及当时没入库的 7/4/1），以及 `build/tb_v98_report.txt` 的 161/1 与 `data/metrics.csv`:15 的 141
（两个不同 md5 的跑）。

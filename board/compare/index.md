# `board/compare/` · 比对表与比对脚本输出索引

规矩：**比对由脚本产出，不靠眼看**（P16b 铁律 6）。本目录每一份 `.txt/.csv` 都是**现跑现落**的脚本输出，
件头两行 `# CMD:` / `# RUN_AT:` 就是复跑入口；正文是脚本原样输出（唯一例外：`cdc-golden_compare-console.txt`
里那行"写出路径"含本机用户名，已按 P23 第 1 节替换成 `<本机临时目录，含用户名，按 P23 第 1 节省略>`，
其余字节未动）。

用的尺子全部是**仓库里已有的**（没有另起炉灶）：

| 尺子 | 位置 | 射程 | 本轮是否真跑 |
| --- | --- | --- | --- |
| `golden_compare.mjs` | `skill/scripts/golden_compare/golden_compare.mjs` | 两张键值/CSV 表逐键逐值 + 容差 + 三态；退出码 0/1/2/3 = PASS/FAIL/NOT_MEASURED/前置不满足 | 跑了 2 次（CDC 正例 + 名册交叉核对） |
| `r115_roster_build.py --diff` | `build/r115_roster_build.py`（名册对名册，G1/G2 判据） | 逐时钟相对余量与两列债务 | 跑了 3 次（正式 / 输错形状 / `--self`） |
| `metric_recheck.mjs` | `src/host/metric_recheck.mjs`（首页与 `data/metrics.csv` 逐数对回报告） | 只认点名 timing_summary / utilization / power 的行 | 跑了 1 次 |
| `temp_formula_check.mjs` | `src/host/temp_formula_check.mjs` | 固件定点换算式 ↔ BSP 浮点参考式，全 65536 码段 + 4 个锚点 + 3 支变异 | 跑了 1 次 |
| `ddr_stale.mjs` | `src/host/ddr_stale.mjs` | JTAG 回读的 DDR dump ↔ 发送端自描述图案（逐 16 bit lane） | 跑了 2 次（两份 dump） |
| `manifest §6 摘要核验` | `data/golden/manifest.md` 自己给的命令 | 参考件规范化 sha256 ↔ manifest 登记值 | 跑了 1 次（13 行全算） |
| `grep -c` 计数尺 | `build/tb_v98_report.txt` 的行形状（`metrics.csv:15` 自己定义的"条数"口径） | 台架条数 | 跑了 1 次 |

## 输出清单与判定（判定放在每行最后一个字段）

| # | 件 | 比对对象（A ↔ B） | 分母（脚本打印的"判 N 项"） | 三态计数 | 判定 |
| --- | --- | --- | --- | --- | --- |
| V01 | `cdc-golden_compare-console.txt` + `cdc-golden_diff.csv` | `build/CDC_BASELINE.txt` ↔ `build/frozen_r23_srcseen/cdc.rpt`（Critical 行） | 判 18 项（C1 键 4 + C2 键值 8 + C3 归属 4 + C4 解析面 2） | 未判 0、红 0 | **PASS** |
| V02 | `roster-diff-baseline-vs-r116e1.txt` | `docs/timing/roster_baseline.tsv` ↔ `build/evidence/r116_roster_e1.tsv` | comparisons_made=32（其中 both_NA=8 ⇒ 实际比 24 对） | red=2 | **RED**（`eth_rxc` 的 `rel_margin_setup -0.198125`、`rel_margin_hold -0.115250`） |
| V03 | `roster-golden_compare-crosscheck.txt` | 同 V02 的两端，但换 `golden_compare` 这把尺子 | 判 44 项（C2 判 27） | 红 1 | **FAIL**（容差 0 ⇒ 任何变动都算超；口径不同，见下方"尺子适用面"） |
| V04 | `roster-diff-selfcheck.txt` | 尺子自己的 5 条对照（含注入红） | SELFRESULT GREEN，rc=0 | — | **PASS**（证明 V02 那把尺子能变红） |
| V05 | `roster-diff-wrong-input-shape.txt` | 同 V02，但 B 侧误喂 `docs/timing/roster_round116.tsv` | comparisons_made=32 red=0 | — | **NOT_MEASURED**（输入形状错：round 件的前 13 列是 A 侧自身 ⇒ 尺子在比 A↔A，全绿是假的） |
| V06 | `ddr-stale-15fps-dump.txt` | 板上 DDR 回读（frameid 图案）↔ 发送端图案定义 | 两 bank × 六带 = 12 带 + 帧号分布 2 行 | 命中 100.0 %、6 带全 0.0 %、连续丢 2 lane | **PASS（有条件）**：见"取样口径"行 |
| V07 | `ddr-stale-wordid-dump.txt` | 板上 DDR 回读（wordid 图案，`data/measured/ddr_dump.out`）↔ 图案定义 | 1 bank 段 × 六带 | 命中 100.0 %、六带全 0.0 % | **PASS（有条件）**：**只有单帧**（所有 lane 帧号 = 0），证明落位不证明连续无损 |
| V08 | `metric-recheck.txt` | `data/metrics.csv` + 根 README 首页 ↔ 它们各自点名的报告 | 判 114 个数（首页层 60、csv 认领 10/10 行） | 红 0；**其余 18 行不在该尺射程内** | **PASS**（射程内）／其余 18 行 **NOT_MEASURED** |
| V09 | `temp-formula-check.txt` | 固件定点式（`src/ps/main.c` 现读常数）↔ BSP 浮点参考式 | 全 65536 码 + 4 锚点 + 3 变异对照 | 温度最大偏差 3 ‰°C（容差 5 ‰°C） | **PASS** |
| V10 | `golden-digest-verify.txt` | `data/golden/` 13 件磁盘字节 ↔ `manifest.md` 登记值 | 13 行 | OK 13 / FAIL 0 | **PASS**（参考件本身未被改动） |
| V11 | `tb98-count-vs-metrics-claim.txt` | `data/metrics.csv:15` 的"141 条"↔ 盘上台架件的 `^PASS+^FAIL` | 现算 161 + 1 = 162；`grep -rl` 该 CSV 点名的指纹 = **0 件** | 摘要不符 | **NOT_MEASURED**（基准件已被覆盖；不许拿 162 冒充 141，也不许拿 141 当本轮数） |
| V12 | `soak300-lane-delta.txt` | `board/evidence_r41/metrics_r41_soak300.json` 的 `before`/`after` 两组 lane 回读 ↔ `report/PERF_REPORT.md` §6b 那句话 | 14 个字段做差；件内自带 `metrics` 块另给 8 个反推量（`avg_gap_ms`/`fps_from_gap`/`fps_wall`/`verdict_no_word_lost`） | `drop_words`/`cdc_episodes`/`pkt_err`/`frames_bad` 增量 = 0/0/0/0；`pkts` 增量 1,989,000（与报告那句逐字相符）；`frames_bad` 的 before 是 **1261 不是 0** | **PASS（对报告那句）**＋**一行必须纠正的口径发现**：见下面"300 s 长跑那一格" |

## 300 s 长跑那一格（V12 抓到的口径混写）

`report/PERF_REPORT.md:197-199` 写的是"9000 帧 / 1,989,000 个 UDP 包 / 5.02 分钟，
`drop_words`、`cdc_episodes`、`frames_bad` 三个计数器全程增量为 0，**帧间隔** `min/avg/max = 20 / 33.34 / 51 ms`"
—— V12 的差值把它逐字段核上了（`pkts` 增量正好 1,989,000、三个增量 0、`gap_min/gap_max` = 20/51）。

但 `data/metrics.csv:25` 那一行把同一个 **33.34 ms 挂到了"端到端时延"**上，还补了"终点 = 示相机位录到该帧上屏"。
两件实物都不支持那个终点：① 33.34 是 `gap_sum/gap_segments = 300057/8999`（件内自报 `avg_gap_ms=33.3434`），
是**帧间隔**不是时延；② 仓库里**没有任何示相机/采集卡导出件**（`find` 全仓只有 `skill/verdict_line_must_print_scope.md` 一个文件名撞了"scope"）；
③ `report/PERF_REPORT.md:190-192` 自己写着真时延那一行"数字等那一轮读完再往这行填"，凭据是 `sim/tb_v90_latency.v` + r52 冻结目录。
⇒ 处置：`端到端时延` 在 `board/raw-vs-golden.md` 记 **A6 = `NOT_MEASURED`**（缺"起点=发送时刻、终点=屏上出现"的可复核件），
33.34 ms 只在"帧间隔"这一行出现；两行不合并（铁律 4：同一指标换口径另起一行）。我不改 `data/metrics.csv`（禁区），只登记。

另两个增量非零但不在判据射程里的字段，如实记下来：`stall_ms 65535 → 6002`（65535 是 16 bit 饱和值，
不是"停了 65.5 s"）、`flags 2 → 18`。⇒ 引用这一轮时不许把这两个数当"改善"念。

## 口径声明（先定义再测；同一指标换口径就另起一行）

1. **台架条数口径**：条数 = `grep -c '^PASS'` + `grep -c '^FAIL'`（`data/metrics.csv:15` 自己就是这么定义的）。
   换个数法（只数 PASS、或把 `C*` 判据名去重）得到的就不是同一个量 ⇒ 换数法要另起一行。
2. **相对余量口径**：`rel_margin_* = wns_* / period_ns`（名册文件头第 2 行钉死），分母来自名册同一行，不允许人脑补周期。
   V02 的两条红就是这一格算出来的。
3. **both_NA 口径**：两侧都没有该读数（`clkfbout` 一族本来没有 intra 路径）⇒ **不算比过**，只进 `both_NA=8`，
   所以 V02 的"实际比了 24 对"= 32 − 8。
4. **DDR 丢字口径**：分母 = 153600 个 16 bit lane（每 bank），"命中"= 该 lane 的值等于图案期望值；
   **取样时长/次数**：V06 = 推 200 帧后停 + 等 500 ms 再读（两 bank 各 1 帧主导 + 2 个残留 lane）；
   V07 = 件里没有配套控制台 ⇒ 帧数与"是否在推流中读"= `【待补】`。
5. **温度口径**：`degC×1000 = (raw*503975 >> 16) − 273150`，截断两次，容差 ±5 ‰°C（V09 打印）；
   串口 `[TEMP]` 的 `osd=61C` 与 `gpio=0x61` 是**同一读数的两种舍入**（℃ 取整 / 8 bit 量化），不是三次独立测量。
6. **ping 口径**：分母 = 发出的 echo 请求数，超时与无应答都算失败；RTT 粒度 1 ms（上位机 OS）⇒
   任何"< 1 ms 的时延"说法不能引这条（详见 `board/conditions/card-failures-sd-icmp-jtag.md` 卡 D）。
7. **仿真时间 ≠ 板级时间**：VCD/台架的 1 ps 时基与板上固件 ms 时基不同口径，两栏之间不做减法（P16b 铁律 7）。

## 尺子适用面（新读数先归因，别急着怪设计）

- V03 用 `golden_compare` 比名册时，**C3 的"最差行"取的是最大值**（该尺为"代价越大越差"设计的）；
  相对余量这类"越小越差"的量在这里方向是反的 ⇒ V03 只能当"有没有差异"的旁证，
  **判定仍以 V02 那把专门尺为准**。这是尺子射程，不是设计缺陷。
- `golden_compare` 的 kv 模式**不认表头**：V03 的"黄金=9 行"里含一行假键 `clock`（11 个值不可解析）⇒
  该表的分母被抬高 1 行。要干净比就得先把 TSV 转成它认识的形状（我没有转，因为转了就换了输入件）。
- V05 是本目录里唯一一条"**假绿**"演示：同一把尺子喂错形状的输入会得到 `red=0 verdict=GREEN`，
  与 V02 的 `red=2 verdict=RED` 相差整整两条红 ⇒ 登记进来就是为了下次别把 GREEN 念错。
- `cdc.rpt` 的正例（V01）钉的是 **r23 冻结件与它自己点名的来源**，与 r118 无关 ⇒
  它 PASS 不等于"本版 CDC 无新增"（本版 CDC 由门禁第 6 项另读，见 `board/logs/index.md` L05 的 green=21 red=3）。

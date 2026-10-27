# `skill/references/` 候选来源表（proposed sources）

本表是给 `_meta/sources.md` 的**候选行**（本任务只允许写 `skill/pitfalls/` 与 `skill/references/`，所以先落在这里）。
每行四列：`结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目`。
本层不是判据：这些行只说明"某事实去哪确认"，不证明该事实成立。
来源类型：`件`=本仓库真实工件（本次打开）；`代码`=本次打开过的脚本；`台账`=本次打开过的 `report/log/ISSUES.md` 小节；`实跑`=本次执行并记下输出的命令；`网`=本次真正抓取到的页面；`未核实`=没拿到可打开的来源。

## 用在 `build-report-field-map/`

| 结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目 |
|---|---|---|---|
| `report_timing_summary` 件的 Design Timing Summary 数据行在 `:151`，列序为 WNS/TNS/TNS失败EP/TNS总EP/WHS/THS/THS失败EP/THS总EP/WPWS/TPWS/TPWS失败EP/TPWS总EP（12 列） | 件 `build/timing_summary.rpt:145,149,151`（类型=件）；实跑 `awk 'NR==151{for(i=1;i<=NF;i++) printf "%d=[%s]\n",i,$i}'` ⇒ `1=[0.739] … 12=[12634]` | 2026-10-04 | build-report-field-map、report-field-parse-breaks |
| 同一件里 Clock Summary 在 `:162-171`、Intra Clock Table 在 `:179-188`、Inter Clock Table 在 `:196-199`、Other Path Groups 在 `:207-209`（本轮该组为空） | 件 `build/timing_summary.rpt`（直读，类型=件） | 2026-10-04 | build-report-field-map |
| 逐时钟行里 `clkfbout`/`clkfbout_1`/`clkout1_1`/`clkout2` 四行的数值列是**空的**，这正是门禁分组解析对它们打出 `NA` 的原因（成因本轮未查，只登记两个读数） | 件 `build/timing_summary.rpt:184-188` + 实跑 `build/gates.sh:279-284` 的 awk 输出 | 2026-10-04 | build-report-field-map、report-field-parse-breaks |
| `report_utilization` 表在 `-F'|'` 下 $2=名字、$3=Used、$7=Util%；Slice LUTs `:35`=14154/26.61、Slice Registers `:40`=8188/7.70、Block RAM Tile `:106`=95.5/68.21、DSPs `:121`=19/8.64、`DSP48E1 only` `:122` 无 Util% 列 | 件 `build/utilization.rpt:33-40,100-123`；代码 `build/gates.sh:76-82` | 2026-10-04 | build-report-field-map |
| `report_power` 的 `\| Dynamic (W) \|` 在 `:36`（2.213）、Total On-Chip `:33`（2.391）、Junction `:40`（52.6）、Confidence `:41`（Low）、Ambient `:127`（25.0） | 件 `build/power.rpt`（直读，类型=件） | 2026-10-04 | build-report-field-map |
| `report_route_status` 的路由错误网线数在 `:10`，取法是"该行最后一个纯数字"（本轮实跑取到 `0`） | 件 `build/route_status.rpt:1-11`；代码 `build/gates.sh:87-88`；实跑 `grep -a … \| grep -oE '[0-9]+' \| tail -1` | 2026-10-04 | build-report-field-map |
| `report_cdc` 的末五列恒为 Endpoints/Safe/Unsafe/Unknown/No-ASYNC_REG；`No Common Primary Clock` 4 token、`Safely Timed` 2 token | 件 `build/cdc.rpt:15-25`；代码 `build/gates.sh:97-100`；实跑 `rows` 式子得两行 Critical 配对 | 2026-10-04 | build-report-field-map |
| `report_clock_util` 的全局时钟资源表在 `:41-49`：BUFGCTRL 8、BUFH 0、BUFIO 0、MMCM 2、PLL 0 | 件 `build/clock_util.rpt:40-50`、`:53` | 2026-10-04 | build-report-field-map |
| `report_methodology` 的 `Checks found: 446`（`:26`），规则计数表在 `:28-36`，且本轮 `grep -ac "CRITICAL WARNING"` = 0 | 件 `build/methodology.rpt:24-37`；实跑 grep | 2026-10-04 | build-report-field-map |
| `data/metrics.csv` 第 5–7 行的 WNS/WHS/失败端点与本轮回读的 `build/timing_summary.rpt:151` 一致 | 件 `data/metrics.csv`（直读）、件 `build/timing_summary.rpt:151` | 2026-10-04 | build-report-field-map |

## 用在 `checker-convention-shapes/`

| 结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目 |
|---|---|---|---|
| `build/gates.sh` 的三态收尾与退出码：`GATES: 有红项（判定 N 项）` rc=1 / `GATES: PARTIAL —— …有 M 项未判` rc=1 / `GATES: ALL PASS（N 项全部判定）` rc=0 | 代码 `build/gates.sh:173-183,581-586`（类型=代码，直读） | 2026-10-04 | checker-convention-shapes、checker-ran-on-nothing |
| `build/gates.sh` 读不到值时 `FATAL … exit 2`（缺报告、解析不到变量、读不到 timing 行三种），且会把最像的三行原样打出来 | 代码 `build/gates.sh:31-33,71-75,162-166` | 2026-10-04 | checker-convention-shapes |
| `sim/run_one.sh` 退出码口径 0/1/2/3/4；`NO-VERDICT-LINE` 走 rc=4；`REFUSE: 已经有 xsim 在跑` 走 rc=3；`CE-FATAL 读不到 …` 走 rc=2 | 代码 `sim/run_one.sh:16,36-44,47,58-60,97,100,113-124` | 2026-10-04 | checker-convention-shapes |
| 同一支 `--verdict` 的两端都能被喂合成日志离线验（`build/run_one_ce.sh` 八条对照，`SELF PASS/SELF FAIL` 两种收尾） | 代码 `build/run_one_ce.sh:71-72`；实跑 `bash sim/run_one.sh --verdict …` 得 rc=3 与 rc=4 | 2026-10-04 | checker-convention-shapes |
| `build/board_verify.sh` 的总判定：`RESULT board_verify PASS（判红的步骤：0）` rc=0 / `FAIL nred=$NRED` rc=1 / `REFUSE: 找不到 xsdb` rc=2；子判据用"命令 rc + stdout 里的 `RESULT PASS …`"两重确认 | 代码 `build/board_verify.sh:114,244,252-256,263,265` | 2026-10-04 | checker-convention-shapes |
| 扫描面地板的形状：`FLOOR BAD … violations=0 可能是没看而不是没违规`（rc=1）/`FLOOR OK instances=… width_compared=…`（rc=0），地板默认 100/280 | 代码 `build/ports_floor.sh:13-25` | 2026-10-04 | checker-convention-shapes、checker-ran-on-nothing |
| 判据自己的五个反例（T1 真件必须红、T2 反例的反例必须绿、T3 新增配对必须红、T4 基线坏行必须红、T5 基线缺失必须红），全部合期望才 rc=0 | 代码 `build/gates_cdc_test.sh:12-20,25,27,65` | 2026-10-04 | checker-convention-shapes |
| 实验轮次的三档判定词：`word()` 把 rc=0→ADOPT、rc=2→NOT_MEASURED、其余→DECLINE（"报告没读出来"不等于否决） | 代码 `build/r95_timing_round.sh:105-121` | 2026-10-04 | checker-convention-shapes |
| `MECHANISM_INERT` 与"没有收益"必须分开写；读数缺失一律 RED | 代码 `build/r115_fanout_ab.sh:41,85,89`、`build/r117_chain.sh:12` | 2026-10-04 | checker-convention-shapes |
| 末列取值的三种真实写法（`awk 'NF{print $NF}'`、`$(NF-4)/$(NF-2)`、`-F'\t' '$NF=="RED"'`） | 代码 `build/rim_gate_ce.sh:57`、`build/gates.sh:100`、`build/r115_c2_verdict.sh:79` | 2026-10-04 | checker-convention-shapes |
| D5 的硬错只有四类，其余进 soft/need 且不影响退出码；本轮实跑打印 `D5: CLEAN（… 硬错 0 条 …）` | 代码 `src/host/line_cite_check.mjs:21-22,160-215`；实跑 `node src/host/line_cite_check.mjs` | 2026-10-04 | checker-convention-shapes、assertion-not-in-any-file |

## 用在 `tool-version-drift/`

| 结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目 |
|---|---|---|---|
| 本包引用的一切报告都出自 `Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026` | 件 `build/timing_summary.rpt:3`、`build/utilization.rpt:3`、`build/cdc.rpt:3`、`build/clock_util.rpt:3`、`build/methodology.rpt:3`、`build/power.rpt:3`；实跑 `grep -h "Tool Version" build/*.rpt \| tr -s ' ' \| sort -u` 归一后只剩 1 行 | 2026-10-04 | tool-version-drift、build-report-field-map |
| 声明侧口径：Vivado/Vitis 2025.2.1；上位机取证工具需要 Node 24；器件 `xc7z020clg484-2` | 代码 `report/BUILD.md:11,15`；件 `data/metrics.csv:2`、`build/utilization.rpt:8` | 2026-10-04 | tool-version-drift |
| 主机侧版本（本次实跑）：Node `v24.21.0`、Python `3.12.10`、bash `5.2.37(1)-release (x86_64-pc-msys)` | 实跑 `node --version` / `python --version` / `bash --version` | 2026-10-04 | tool-version-drift |
| Vitis / xsdb 的版本串在被跟踪件里没出现 ⇒ 该格留空并写明原因 | 实跑检索（负结果）：`build/*.rpt` 与 `build/evidence/*` 未见 `Vitis v.` 字样 | 2026-10-04 | tool-version-drift |
| `-filter {… eq …}` 报 `[Common 17-263]`，`==` 与 `=~` 可用；`-quiet` 会吞掉语法错只留空集 | 件 `build/evidence/r114_idelay_prop_console4.txt:63`、`build/evidence/r114_idelay_set_console.txt:53-55`；台账 `report/log/ISSUES.md` #279 | 2026-10-04 | tool-version-drift、tcl-query-empty-means-broken-ruler |
| `phys_opt_design` 本版 31 个选项，`-skeleton_clustering` 不在其中；未知选项报 `[Common 17-170] Unknown option` | 件 `build/evidence/r117_d0/nethelp_console.txt:395,402-407`；件 `build/evidence/r115_window/console2.txt:177`；台账 #319 | 2026-10-04 | tool-version-drift |
| `get_false_paths`/`get_timing_exceptions`/`get_clock_groups` 在本工具里不是命令（`info commands *exception*` 只回 `report_exceptions`） | 件 `build/evidence/r114_cmds_console.txt:13-18`；台账 #277 | 2026-10-04 | tool-version-drift |
| `report_clock_timing` 在 2025.2.1 的 7 系列批处理里不存在 | 台账 `report/log/ISSUES.md`（该文件第 6468 行）；本轮未在别的版本上验过 ⇒ 只写这一版 | 2026-10-04 | tool-version-drift |
| `set_input_delay` 把 `-min` 与 `-max` 合写一条会报 `[Common 17-165] Too many positional options …`，报错点名的端口列表不是过错方 | 台账 `report/log/ISSUES.md` #308（该文件第 12657–12665 行） | 2026-10-04 | tool-version-drift |
| `set_property IDELAY_VALUE` 在已布线 DCP 上有效 ⇒ 扫档位不必重跑构建 | 台账 `report/log/ISSUES.md` #310；件 `build/evidence/r114_idelay_sweep_console.txt` | 2026-10-04 | tool-version-drift |
| Tcl `catch` 的返回码与消息分开放：成功 0（TCL_OK），`varName` 收的是消息（TCL_ERROR 时为错误信息）；异常码 1/2/3/4 = ERROR/RETURN/BREAK/CONTINUE | https://www.tcl-lang.org/man/tcl8.6/TclCmd/catch.htm（类型=网，本次抓取并读到上述内容）；本地印证台账 `report/log/ISSUES.md` #327 | 2026-10-04 | tool-version-drift、exit-zero-nothing-written |
| UG901 / UG904 / UG1399 / UG949 与 PG/DS 类文档正文本轮没打开（`docs.amd.com` 抓取只返回"需要启用 JavaScript"）⇒ 相关格写 `未核实` | 未核实（类型=未核实；本轮抓取尝试记录在上一行与本页 F 组） | 2026-10-04 | tool-version-drift |

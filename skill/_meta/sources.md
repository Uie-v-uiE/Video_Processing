## 目录

- 检索台账（技能包里每一条工具行为断言的出处）
- 一、本会话（2026-10-04）我自己打开核对过的行
- 二、外部检索（等待逐条落表）
- 三、已知"不能公开引用"的部分（如实登记，不伪装）

# 检索台账（技能包里每一条工具行为断言的出处）

四列固定：**结论一句话 | 来源（URL 或本地路径，含行号）| 核对日期 | 用在哪个条目**。
规则：条目正文里凡关于 Vivado/Vitis/xsim/xsdb/工具行为的说法，必须能在本表找到一行；
找不到就把那句改成 `【未核实】`，不要写成事实。合并请求：各目录的 `_proposed-sources.md` 由
`skill/scripts/check/gates.mjs` 的 G8/G9 与"台账行数 ≥ 正文断言数"这条判据核到，不许静默吞掉。

## 一、本会话（2026-10-04）我自己打开核对过的行

| 结论一句话 | 来源 | 核对日期 | 用在哪个条目/文件 |
| --- | --- | --- | --- |
| 赛题对目录/文件名的要求是"小写字母、数字、下划线或连字符，不得出现中文、空格或特殊字符"（§3.3.5.4） | `report/log/CONTEST_CHECKLIST.md:21`（该文件存的是赛题摘录） | 2026-10-04 | `_meta/naming-and-format.md` G1、`_meta/sources.md` |
| 编号对应关系：文件名要求 §3.3.5.4、工具版本 §3.3.3.1、技能包 §3.3.5.2（此前记错过一次） | `report/log/CONTEST_CHECKLIST.md:82` | 2026-10-04 | `_meta/naming-and-format.md` 条文依据表 |
| 推荐结构非强制，采用其他组织方式须在 `README.md` 给出目录对照说明 | `report/log/CONTEST_CHECKLIST.md:120` | 2026-10-04 | 交付根 `README.md` 的目录对照一节 |
| 通用 PYNQ Skill 单独加分；本作品是裸机 + Vivado/Vitis 原生流程，不用 PYNQ | `report/log/CONTEST_CHECKLIST.md:124` | 2026-10-04 | `runtime/` 各条目的"PYNQ 对位写法"栏 |
| 本包写成的工具版本是 Vivado / Vitis 2025.2.1 | `report/BUILD.md:11`（版本注记另见 `report/PERF_REPORT.md`） | 2026-10-04 | `_meta/naming-and-format.md` 第 4 节、所有条目的"前置条件" |
| 共用条件行：器件 `xc7z020clg484-2` / Vivado+Vitis 2025.2.1 | `data/metrics.csv:2` | 2026-10-04 | `references/` 版本漂移页、`scripts/report_metrics/` |
| 上板三步链的顺序是 `ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl`，且 E6 判据就按这三步跑 | `board/ACCEPTANCE.md:92-97` | 2026-10-04 | `runtime/pl-programming-and-verify/` |
| 冷上电后 hw_server 未重新枚举时 `targets -set 1` 会死在 `tid2ctx`；枚举表出来后原脚本一字未改就过了 | `report/log/ISSUES.md` #332 末段 + 件 `build/evidence/r118_eyes/STATE.txt`、`build/tcl/probe_target_select.tcl` | 2026-10-04 | `pitfalls/`（xsdb/JTAG 那一类）、`runtime/` 的失败分叉 |
| Tcl `catch` 的变量存的是**返回码**，拿它和哨兵字符串比较会把成功的运行读成失败 | `report/log/ISSUES.md` #327 + `build/tcl/r117_post_place_hook.tcl` 的修法 | 2026-10-04 | `pitfalls/tcl-catch-rc/`（或同名条目） |
| 门禁的最终形状：判定 24 项 = 23 绿 / 1 红，唯一红是声明过的 `C5c`，两跑逐字节一致 | `build/r118_gates_final.txt`、`build/evidence/r118_board/gatesc_summary.txt` | 2026-10-04 | `evals/` 增益记录、`scripts/check/gates.mjs` 的期望基线 |
| 编码自检尺子在 `src/host/doc_enc_check.mjs`（UTF-8 无 BOM 异常、无截断多字节字符） | 本会话实跑输出"扫了 435 个手写文件：全部干净" | 2026-10-04 | `_meta/naming-and-format.md` R10、G12 |
| 行号引用尺子在 `src/host/line_cite_check.mjs`（硬错 0 / 命中 360 / soft 148） | 本会话实跑输出 `D5: CLEAN` | 2026-10-04 | `references/` 判据形状速查、G8 |

## 二、外部检索（等待逐条落表）

`skill/pitfalls/_proposed-sources.md`、`skill/prompts/_proposed-sources.md`、`skill/references/_proposed-sources.md`
里是这三类撰写者**真正打开过**的来源行（`ls skill/*/_proposed-sources.md` 现算 = 3 份；
`templates`、`runtime`、`scripts` 三类**没有交回 proposal 文件**，这是缺口，不是没列出来）。
合并进本表的动作由 `build/r119_merge_sources.py` 做（`--check` 证幂等），
台账行是否可解析由 `skill/scripts/check/gates.mjs` 的 G8 判（G8 只管"外链必须有台账行"，不做合并）。
**没有来源行的外部 URL 一律不得进入条目正文。**

HDMI CTS（源端 TP1 眼图掩模）那条线单独记在 `report/io/hdmi_cts_source_window.md`（含公开可引用性边界），
本表只登记它被哪个条目引用，避免两处抄同一组数字。

## 三、已知"不能公开引用"的部分（如实登记，不伪装）

| 结论 | 状态 |
| --- | --- |
| HDMI CTS 的正式表格文本只发给 HDMI Adopter（NDA），公开渠道能拿到的是规范正文与仪器厂商应用笔记的转述 | 以 `report/io/hdmi_cts_source_window.md` 的逐条判定为准；凡代理值必须标注"第三方实测代理"，不得写成"已按 CTS 校验" |

<!-- BEGIN MERGED PROPOSED SOURCES -->

下面这张表由 `build/evidence/r119_merge_sources.py` 从各目录的 `_proposed-sources.md` 合并（条数=129）。
各目录那份原件保留不删——它是撰写者的原始台账；本表只是让 G8 的"外链必须有行"能在一处核对。

| 结论一句话 | 来源 | 核对日期 | 用在哪个条目 |
| --- | --- | --- | --- |
| Vivado 2025.2.1 的 `-filter` 表达式里 `eq` 不是合法操作符，会报 `ERROR: [Common 17-263] There was a syntax error while parsing filter expression: 'REF_NAME eq IDELAYE2' at position '9'` | 件 `build/evidence/r114_idelay_prop_console4.txt:63`（类型=件） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 同一份 DCP 上把操作符换成 `==` 立刻数到 5 颗 `IDELAYE2`（打出 `IDELAY_N=5`），证明上一版"0"是过滤器坏 | 件 `build/evidence/r114_idelay_set_console.txt:53-55`（类型=件） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `-quiet` 会把上述语法错吞掉，只留下空集合 ⇒ "我的尺子坏了"看起来等于"设计里没有" | 台账 `report/log/ISSUES.md` #279（该文件第 11920–11945 行，类型=台账+件同行） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 网对象用 `-hier` 全名、`-filter "NAME == {全名}"`、`-filter "FULL_NAME == {全名}"` 三种写法都恒回 0，只有不带 `-hier` 的分层路径直取回 1；负对照回 0 | 件 `build/evidence/probe_mf114_netname_console.txt:94,97,100,103,106`（类型=件） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 那些 nets 的 `NAME` 属性打出来就是分层全名，而 `FULL_NAME` 是**空**，所以 `NAME ==` 比的不是同一个东西 | 台账 `report/log/ISSUES.md` #286（该文件第 12089 行起，"F2/F4 恒空不是名字对不上"段） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `get_nets -quiet *`（不带 `-hier`）只回 1000 个顶层网 ⇒ 全设计扇出扫描会得到假干净 | 台账 `report/log/ISSUES.md` #286（同一节"顺带三条射程事实"第 2 条） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `get_property FANOUT [get_nets …]` 返回空 ⇒ "网对象自带扇出读数"这个来源不存在 | 台账 `report/log/ISSUES.md` #286（同一节第 1 条） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 网名字里的方括号是 GLOB 类字符，裸 pattern 会把 `rok4[51]_i_1_n_0` 判成"不存在" | 台账 `report/log/ISSUES.md`（该文件第 11545–11546、11574 行） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `phys_opt_design` 在 2025.2.1 有 31 个选项，`-skeleton_clustering` 不在其中（`present=0`），`-force_replication_on_nets`/`-fanout_opt`/`-retime` 在（`present=1`） | 件 `build/evidence/r117_d0/nethelp_console.txt:395,402-407`（类型=件） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 传未知选项时报 `ERROR: [Common 17-170] Unknown option …`（同一族报错在 `read_xdc -unmerged` 上也出现） | 件 `build/evidence/r115_window/console2.txt:177,209,241,273`；台账 `report/log/ISSUES.md` #319 | 2026-10-04 | tcl-query-empty-means-broken-ruler、assertion-not-in-any-file |
| `get_nets -of [get_pins <驱动引脚>]` 与报告里打印的段名不是同一个对象（7 引脚 vs 239 引脚），选目标网要两路独立取名同名 | 台账 `report/log/ISSUES.md` #320（该文件第 12831 行起） | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| Tcl 的 `catch {…} var` **返回整数结果码**（成功 0=TCL_OK），`var` 收的是消息（`TCL_ERROR` 时为错误信息）；把哨兵字符串与返回码共用一个变量会把成功读成失败 | https://www.tcl-lang.org/man/tcl8.6/TclCmd/catch.htm（类型=网，本次已抓取并读到 0/1/2/3/4 的定义）；本地印证 `report/log/ISSUES.md` #327 | 2026-10-04 | exit-zero-nothing-written |
| 钩子里的 `puts` 落在 run 自己的 `impl_1/runme.log`，链子只 grep 顶层控制台就会把"机制动了"读成 `MECHANISM_INERT` | 台账 `report/log/ISSUES.md` #327（"A1 的出水口"段）；件 `build/r117_a1_read.sh` 的两处读法 | 2026-10-04 | exit-zero-nothing-written、tcl-query-empty-means-broken-ruler |
| `build_system.tcl`、`build_pl_full.tcl` 用 `[file dirname [info script]] ..` 少解析一层，`add_files` 指向 `build/src/...` 而**报错之后仍然 exit 0** | 代码 `build/tcl/README.md:19-23`（类型=文档/代码，本次打开）；台账另记 `report/log/ISSUES.md` #22/#41 | 2026-10-04 | exit-zero-nothing-written |
| UTF-8 BOM（`EF BB BF`）让 Vivado 批处理在第一行报 `invalid command name "？#"`；本仓只有下板那条路径全中带 BOM | 台账 `report/log/ISSUES.md`（该文件第 431–434 行） | 2026-10-04 | console-codepage-verdict-shift、exit-zero-nothing-written |
| `rm -rf` 报 `Device or resource busy` 之后脚本继续走完并打印"导出成功"；改法是失败必须停并提示先数文件数 | 代码 `build/make_submission.sh:723,731-733`；台账 `report/log/ISSUES.md` 2026-10-02 03:3x 一节 | 2026-10-04 | exit-zero-nothing-written |
| 隔离构建脚本在 sed 没生效时 REFUSE 并删除临时 Tcl（不留下半份产物） | 代码 `build/roll_isolated.sh:22,27,30`（本次打开） | 2026-10-04 | exit-zero-nothing-written |
| 板级链的 rc=0 不证明它动过板子：没起 `hw_server` 时 `targets -set 1` 报 `Invalid target`，脚本照样 exit 0 | 台账 `report/log/ISSUES.md`（该文件第 9000–9001 行）；代码 `build/board_verify.sh:116-118` 的同族注释 | 2026-10-04 | exit-zero-nothing-written |
| `report_timing -file /tmp/…` 在 Vivado 侧失败并报 `ERROR: [Common 17-37] Directory in which file … does not exist [/tmp/kx/r114sweep]`；Vivado 的 `/tmp` 不是 bash 的 `/tmp` | 件 `build/evidence/r114_idelay_sweep_console.txt:688,1275,1876`；台账 `report/log/ISSUES.md` #280 末段 | 2026-10-04 | win-bash-path-split |
| `xvlog` 的编译清单必须走 `-f` 文件；文件内容必须是 Windows 正斜杠路径（`cygpath -m`），写 `/d/…` 会 `Can not find file`，因为 `-f` 文件内容不被 MSYS 换算 | 代码 `sim/run_one.sh:67-72`（本次打开）；台账 `report/log/ISSUES.md` 第 9193 行 | 2026-10-04 | win-bash-path-split |
| 清单拼在命令行上会被 Windows 命令行长度上限截成"参数太多"，而 `xv.log` 里连 `ERROR` 都没有，最后只剩 `Cannot find design unit` | 代码 `sim/run_one.sh:67-69` 注释；台账 `report/log/ISSUES.md` 第 556、2755 行（类型=台账；本次未复现长清单现场 ⇒ 数值部分 `【未实测】`） | 2026-10-04 | win-bash-path-split |
| 脚本 `cd` 进运行目录后 `$0` 的相对路径解析不了，自调会 rc=127（仿真其实跑完） | 代码 `sim/run_one.sh:120-123`；台账 `report/log/ISSUES.md` 第 6859 行 | 2026-10-04 | win-bash-path-split |
| `export A=1 && cmd &` 会把整个列表放进后台子 shell；每次工具调用都是新 shell；node 眼里的 `/tmp/…` 是 `C:\tmp\…` | 台账 `report/log/ISSUES.md` #317（该文件第 12793 行起） | 2026-10-04 | win-bash-path-split |
| MSYS 的 `ps -W` 把 Windows 映像名截成路径前缀（`D:\Sof…`），`grep vivado.exe` 恒不匹配；真值要用 `tasklist //FI "IMAGENAME eq vivado.exe"` | 台账 `report/log/ISSUES.md` #244（该文件第 11100–11106 行）；代码用法 `sim/run_one.sh:57-59` | 2026-10-04 | who-else-writes-this-artifact、win-bash-path-split |
| 同一时刻第二个 `run_one.sh` 不会让第一个停下，两个 xsim 往同一份 `run.log` 写；那份报告的头部 md5 全对而正文来自两跑 ⇒ 脚本改为门口数进程并 `exit 3` REFUSE | 代码 `sim/run_one.sh:50-61`；台账 `report/log/ISSUES.md` 2026-09-27 12:48 一节 | 2026-10-04 | who-else-writes-this-artifact |
| `bash <脚本> \| tail -45` 放后台时输出文件是 0 字节（管道等结束才刷），中途读等于什么都没看到 | 台账 `report/log/ISSUES.md`（该文件第 4394 行所在的"流程账"段） | 2026-10-04 | who-else-writes-this-artifact |
| `ls -l --time-style=+%H:%M` 在这台 MSYS 上给的时间不可信；判"何时被写"只认 `stat -c '%y'` | 台账 `report/log/ISSUES.md` 2026-10-02 00:46 一节（第 9550、9565–9567 行） | 2026-10-04 | who-else-writes-this-artifact |
| 构建脚本原地覆盖 `build/system.bit`、`system.xsa` 与那几份 `.rpt`：文件名不变、内容变 | 代码 `report/BUILD.md:182`（§7 首段，本次打开） | 2026-10-04 | who-else-writes-this-artifact |
| 门禁用 mtime 差判"是不是同一套"（>600 s 报 WARN），并用 `find src/rtl -newer <bit>` 报"产物比源码旧" | 代码 `build/gates.sh:36-57`（本次打开） | 2026-10-04 | who-else-writes-this-artifact |
| xsim 的 `$display`：字符串字面量赋给定宽向量或作为 task 实参时每字节 bit7 被清；字段超长时丢的是头部（左边截）⇒ 判据标签只写 ASCII | 台账 `report/log/ISSUES.md`（该文件第 1938–1941、6566–6568 行）；同族 `skill/bench_verilog_subset.md` | 2026-10-04 | console-codepage-verdict-shift |
| GBK 控制台把一整句中文渲染成"一大长串空白"；实测同一条回复 204 字节里 90 个是 0x80+ 字节、`0x20` 只有 22 个 | 台账 `report/log/ISSUES.md`（该文件第 5810–5811、5844 行） | 2026-10-04 | console-codepage-verdict-shift |
| Vivado/Windows 侧的 `ping` 等原始输出是 GBK，落盘前用 `iconv` 转 UTF-8，否则编码检查会当它是坏编码 | 台账 `report/log/ISSUES.md`（该文件第 9677、9799–9807 行） | 2026-10-04 | console-codepage-verdict-shift |
| 本仓编码检查只扫手写扩展名 `.md .v .c .h .mjs .sh .ps1 .tcl`，`*.txt` 原始回显一律不扫；`.ps1`/`.tcl` 允许**第 0 个字符**是 BOM | 代码 `src/host/doc_enc_check.mjs:10-13,25,35`（本次打开） | 2026-10-04 | console-codepage-verdict-shift |
| 非 ASCII 的机器可读 token 在 GBK 控制台上会把一次崩溃渲染成一条"红"/"空白"（本仓结论：token 一律 ASCII） | 台账 `report/log/ISSUES.md`（第 2731、5235、6570 行的同族说明）；**官方页面本次未打开 ⇒ 该行只作为本仓约定陈述** | 2026-10-04 | console-codepage-verdict-shift |
| `report_timing_summary` 的 `Design Timing Summary` 数据行列序：$1=WNS、$3=TNS Failing Endpoints、$5=WHS、$7=THS Failing Endpoints、$8=THS Total Endpoints | 件 `build/timing_summary.rpt:149-151` + 本次实跑 `awk` 字段表（见 report-field-parse-breaks §7） | 2026-10-04 | report-field-parse-breaks、references/build-report-field-map |
| `report_cdc` 的 Critical 行末五列恒为 Endpoints / Safe / Unsafe / Unknown / No-ASYNC_REG，所以从尾巴数（`$(NF-4)`、`$(NF-2)`）；CDC Type 的 token 数会变 | 代码 `build/gates.sh:97-100`；件 `build/cdc.rpt:15-18` + 本次实跑输出 | 2026-10-04 | report-field-parse-breaks |
| `report_route_status` 的 `# of nets with routing errors` 那行是 `… : 0 :`，取最后一个纯数字字段 | 代码 `build/gates.sh:87-88`；件 `build/route_status.rpt:10` + 本次实跑（读回 `0`） | 2026-10-04 | report-field-parse-breaks |
| `report_utilization` 的表在 `-F'|'` 下行首有空字段：$2=名字 $3=Used $4=Fixed $5=Prohibited $6=Available $7=Util% | 代码 `build/gates.sh:76-82`；件 `build/utilization.rpt:33-40,106,122` | 2026-10-04 | report-field-parse-breaks、references/build-report-field-map |
| 分组最差那层用 `/^Setup :/` 时冒号是独立字段，所以取 `$8` 才是 Worst Slack；`From Clock`/`To Clock` 取 `$3` | 代码 `build/gates.sh:279-284`；本次实跑输出 + `build/timing_summary.rpt:218-222,354-358,533-537` | 2026-10-04 | report-field-parse-breaks、references/build-report-field-map |
| 首页取数器正则不给符号位时，负 slack 读成 null ⇒ "写对也红、写错也红"，射程为零；修法是可可选符号位 + U+2212 折叠 | 代码 `src/host/metric_recheck.mjs:46`；台账 `report/log/ISSUES.md` #321（该文件第 12854 行起） | 2026-10-04 | report-field-parse-breaks、checker-ran-on-nothing |
| `set_input_delay` 把 `-min` 与 `-max` 写在同一条命令里报 `ERROR: [Common 17-165] Too many positional options when parsing …`，而报错点名的是端口列表 | 台账 `report/log/ISSUES.md` #308（该文件第 12657–12665 行） | 2026-10-04 | references/tool-version-drift、tcl-query-empty-means-broken-ruler |
| `set_property IDELAY_VALUE` 在**已布线 DCP** 上有效 ⇒ 扫档位不必重跑构建 | 台账 `report/log/ISSUES.md` #310（该文件第 12700 行）；件 `build/evidence/r114_idelay_sweep_console.txt` | 2026-10-04 | references/tool-version-drift |
| `report_clock_timing` 在 2025.2.1 的 7 系列批处理里不存在（`invalid command name`） | 台账 `report/log/ISSUES.md`（该文件第 6468 行） | 2026-10-04 | references/tool-version-drift |
| `sim/run_one.sh` 的退出码口径：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 判红 / 4 认不出判定；`--verdict` 分支排在工具存在性检查**之前**，可离线读旧日志 | 代码 `sim/run_one.sh:8-9,14-45,113-124` + 本次实跑（rc=3 与 rc=4 各一次） | 2026-10-04 | checker-ran-on-nothing、references/checker-convention-shapes |
| `build/gates.sh` 的三态收尾：`GATES: 有红项（判定 N 项）` exit 1 / `GATES: PARTIAL —— 判定 N 项全过，但有 M 项未判` exit 1 / `GATES: ALL PASS（N 项全部判定）` exit 0；读不到值时 `FATAL … exit 2` | 代码 `build/gates.sh:162-166,180-183,581-586` + 件 `build/evidence/r118_board/gatesc_summary.txt`（历史读数） | 2026-10-04 | checker-ran-on-nothing、references/checker-convention-shapes |
| `build/board_verify.sh` 的总判定 token：`RESULT board_verify PASS（判红的步骤：0）` exit 0 / `RESULT board_verify FAIL nred=N …` exit 1 / `REFUSE: 找不到 xsdb …` exit 2 | 代码 `build/board_verify.sh:114,263,265`（本次打开） | 2026-10-04 | references/checker-convention-shapes、checker-ran-on-nothing |
| 一轮把 README 写成 0 行的机制：`io.open(path,"w")` 已经把文件截成 0 行才抛异常 ⇒ 批量写文档必须"先全算好再一次性写 + 写前断言行数不变" | 台账 `report/log/ISSUES.md` #329（该文件第 13012–13034 行，含第 13020 行那句） | 2026-10-04 | assertion-not-in-any-file |
| 检查器扫描集会自动把新造的文件算进射程：本仓 D5 扫 `.`/`report`/`report/log`/`skill`/`board` 下所有 `.md`（`report/log/`、`report/study/` 除外） | 代码 `src/host/line_cite_check.mjs:33-40`（本次打开）；台账 `report/log/ISSUES.md` #333 | 2026-10-04 | assertion-not-in-any-file、references/checker-convention-shapes |
| D5 的硬错只有四类（文件不在树里 / 行号越过文件末尾 / D5b 例化者列 / D5d 逐字回声对不上），其余进 soft/need 不影响退出码 | 代码 `src/host/line_cite_check.mjs:22,160-215`；本次实跑输出 `D5: CLEAN（… 硬错 0 条 …）` | 2026-10-04 | assertion-not-in-any-file、references/checker-convention-shapes |
| 只读评审的采信口径：只有能指回 `file:line` 的发现进正文，其余降级为候选或不采信（16 条 ⇒ 8 进正文、4 降 CANDIDATE） | 台账 `report/log/ISSUES.md` #125（该文件第 5402 行起）；做法在 `skill/read_only_review_agent.md` | 2026-10-04 | assertion-not-in-any-file |
| 三代数据面的划分对比（网口/收包/拼帧/显示/右屏/PS 角色 × v1/v2/v3）与"数据面放 PL、控制面留 PS"的结论是表格形状，不是散文 | `report/PS_VS_PL.md`（mtime 2026-10-01 08:06）§1、§3 | 2026-10-04 实读 | `prompts/hw-sw-partition` |
| 软硬件交界被写成"通道 / 地址 / 方向 / 位域 / 源码行号"四列，且明写"PS 不中转任何 ETH 视频字节" | `report/ARCHITECTURE.md` §3（2026-10-01 08:46） | 2026-10-04 实读 | `prompts/hw-sw-partition`、`templates/interface-contract` |
| 负载口径与实测吞吐分记两行（"这是负载口径不是实测带宽"） | `data/metrics.csv`（2026-10-04 06:23）"UDP 入口负载,口径" 行 | 2026-10-04 实读 | `prompts/hw-sw-partition`、`templates/report-forms` |
| 划分依据与接口的落点在交付对照表里被点名（软硬件协同那一行） | `report/log/CONTEST_CHECKLIST.md`（2026-10-01 08:06）§1"软硬件协同"行 | 2026-10-04 实读 | `prompts/hw-sw-partition`、`templates/project-skeleton` |
| 时序判据要按每个时钟域列名册并交"名册差分"，全局 WNS 换了主语时绝对差不算收益也不算损失 | `report/TIMING_GLOBAL.md`（2026-10-04 04:49）§1 第 1/5 条、§2、§2b | 2026-10-04 实读 | `prompts/report-to-bottleneck`、`prompts/single-variable-ab`、`templates/report-forms` |
| 四域同表的实测读数（`eth_rxc` 0.445 / 5.56 %、`clk_fpga_0` 1.135 / 11.35 %、`clkout0_1` 4.467 / 22.34 %、`sys_clk` 14.463 / 72.3 %）与同轮一进一出的移动 | `report/TIMING_GLOBAL.md` §2（同一构建） | 2026-10-04 实读 | `prompts/report-to-bottleneck` |
| route 占比高（阈值 80 %）且级数少的路，拆逻辑救不了；该动扇出复制/控制集复制/floorplan | `report/TIMING_GLOBAL.md` §1 第 2 条、§3 | 2026-10-04 实读 | `prompts/report-to-bottleneck` |
| 逐域名册的 13 列与口径（`rel_margin = wns / period`、`io_unconstrained_ports` = check_timing 两类之和） | `docs/timing/roster_baseline.tsv`（2026-10-03 22:45）文件头 + 列名行 | 2026-10-04 实读 | `prompts/report-to-bottleneck`、`templates/report-forms/timing-readout.md` |
| 差分表列名（`b_*` 对照、四条 `_delta`、`verdict`）与"只有一行 RED"的判定形状 | `docs/timing/roster_round116.tsv`（2026-10-04 03:27） | 2026-10-04 实读 | `templates/report-forms/timing-readout.md` |
| 下一刀候选表的列结构（根因/手段/预期收益/影响域/机制证据/风险/代价档/状态）与状态取值 | `docs/timing/cut_ledger.tsv`（2026-10-04 04:31）C1–C9 行 | 2026-10-04 实读 | `prompts/report-to-bottleneck`、`templates/report-forms/optimization-compare.md` |
| 四个域里只有 `eth_rxc` 的报告带 `Clock Uncertainty: 0.800` 那一行；补齐三条之后设计级 `WHS = -0.747 / 25742 个失败端点` ⇒ hold 余量跨域不可比 | `docs/timing/uncertainty_hold_ab.md`（2026-10-03 23:20）第 1/2 节 | 2026-10-04 实读 | `prompts/report-to-bottleneck`、`templates/report-forms` |
| 未点名端口要把"计数"变成"逐端口点名 + 计数地板"（I1–I6，含"空转不许当绿"） | `build/check_io_timing_coverage.py`（2026-10-03 13:54）头部注释 | 2026-10-04 实读 | `prompts/report-to-bottleneck` |
| 噪声底 `noise_ns=0.000`、A 滚名册与基线逐格相同、B 滚 `REPLICA_CELLS` 0→310、F5 红四格 ⇒ 该刀拒绝 | `docs/timing/README.md`（2026-10-04 03:28）时间线与结论两节 | 2026-10-04 实读 | `prompts/single-variable-ab` |
| 同一份 `opt.dcp` 重跑 place+route 逐位复现（不是骰子）⇒ 检查点复算是合法对照 | `report/TIMING_GLOBAL.md` §2 末段、`report/log/ISSUES.md` #254 | 2026-10-04 实读 | `prompts/single-variable-ab`、`prompts/report-to-bottleneck` |
| 复制类手段"机制动没动"可数（复制对象名带 `_replica`），且 `set_max_fanout` 在该工具里不存在（`help` 回 `No topics matched`）⇒ 杠杆名要读 help 原文 | `build/r114_replication_ab.sh`（2026-10-03 13:20）头部；`report/TIMING_GLOBAL.md` §3 | 2026-10-04 实读 | `prompts/single-variable-ab`、`prompts/report-to-bottleneck` |
| 单变量 A/B 的判读顺序 V1/V2/V2b/V2c/V3/V4/V5 与 `MECHANISM_INERT` 口径、"头条 WNS 绝对差只念不判" | `build/r114_replication_ab.sh` 头部判读段 | 2026-10-04 实读 | `prompts/single-variable-ab` |
| 那一滚的执行记录里有 `R3_AGREE/R3_BEFORE/R3_AFTER/R3_REPLICA_CELLS/R3_MECHANISM_INERT` 与 10 行 `ROW` | `build/evidence/r117_repl3/B_console.txt`（2026-10-04 03:00）；核对命令 `grep -o "R3_[A-Z_]*" … \| sort -u`（实跑 2026-10-04，返回 8 个 token） | 2026-10-04 实跑 | `prompts/single-variable-ab` |
| 判据"改前必须红"的机器化：拷整棵 RTL 到临时目录机械复原旧写法，diff 行数超出就拒绝继续；一次变异只许红它声称红的那几条 | `sim/mut_control.sh`（2026-10-01 07:40）头部注释 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/script-template` |
| 机会计数 190464 拍 / 最大索引 255、第一版判据因激励只停在格子里而计数为 0、只拆一道门仍然绿 ⇒ 门有两道 | `report/LLM_COLLAB.md`（2026-10-02 02:16）例 2；`data/metrics.csv`"越界读写的机会计数"行 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/report-forms` |
| 判据标签被 100 字节容器按字节从左边截断 ⇒ 一条判据在日志里"消失"；新写判据标签一律 ASCII | `report/LLM_COLLAB.md` 例 6（#162）、`skill/criterion_blind_spot.md`（2026-10-01 08:06）触发第 7 条 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/script-template` |
| 收尾解析把一支真红台架报成 `NO-VERDICT-LINE + FAIL 行数=0`（红与"没数"长得一样），候选解析器被"不许让过期日志替本台架答复"这条反例打回 | `sim/run_one.sh`（2026-10-01 07:40）`--verdict` 分支注释；`report/LLM_COLLAB.md` 例 6；#163/#164 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/script-template` |
| 台架脚本退出码分五态：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 判红 / 4 认不出判定行，"3 与 4 必须分开" | `sim/run_one.sh` 第 40、112–119 行 | 2026-10-04 实读 | `templates/script-template` |
| 门禁退出码与三态收尾（`GATES: ALL PASS（N 项全部判定）`/`GATES: 有红项`/`GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判`），且行首换词让下游冻结自动拒绝 | `build/gates.sh`（2026-10-02 23:06）收尾 20 行；`report/LLM_COLLAB.md` 例 5 | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 逐项四列打印式 `printf "  %-22s %-12s %-28s %s\n"` 与 `NSAY/NNA` 计数 | `build/gates.sh:175`（`say()`，实读定位） | 2026-10-04 实读 | `templates/script-template` |
| 读报告的行正则必须允许数字带符号；读不到时把最像的三行原样打出来（r60 那次 TNS 是负数导致"读不到"顶替了 WNS −0.482/19 个失败端点） | `build/gates.sh:62-77`（第 1 项注释与 awk） | 2026-10-04 实读 | `templates/script-template` |
| 射程/命中地板写进判据（D5 `命中 >= 300`、D6 `判 >= 30 个数 / 首页 >= 20 / 百分数 >= 6 / csv 认领两半相等`）——"扫不到的尺子也报硬错 0 条，那是空转不是绿" | `build/gates.sh` 第 20/21 项（`build/gates.sh:508`、`:537` 附近）；`src/host/metric_recheck.mjs`（2026-10-04 03:07）头部 | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 判断脚本成不成要用 `cmd > file 2>&1; echo rc=$?`，永不读被 pipe 掉的命令的状态；`set -e` + `pipefail` 会让兜底分支没机会执行 | `report/LLM_COLLAB.md` 例 4（#133/#106） | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 工具定位走环境变量、找不到在第一步 REFUSE 并念出变量名；实跑输出 `REFUSE: 找不到 xvlog（当前 …）` + `rc=2`，且拒绝发生在 `mkdir`/`sed` 之前 | `report/BUILD.md`（2026-10-02 09:23）§1 表格与末段实跑两行 | 2026-10-04 实读 | `templates/script-template`、`templates/project-skeleton` |
| 一次只测一件事（同树重复滚 = 零散布），"多变量会把单变量性打掉"的候选直接 excluded | `report/log/ISSUES.md` #223（结案行实读）；`docs/timing/cut_ledger.tsv` C2/C5 行 | 2026-10-04 实读 | `prompts/single-variable-ab` |
| 新红了先退回未改状态、用同一版台架再跑一遍比红名单（含台架 md5 也要一致） | `skill/ab_revert_control_run.md`（2026-10-01 08:06）动作 1–5；#113 | 2026-10-04 实读 | `prompts/single-variable-ab` |
| 只读评审代理 + 回读门槛（代理每条结论必须能在盘上指出行号，指不出写"未证实"） | `report/LLM_COLLAB.md` 第 5 节表、例 2 | 2026-10-04 实读 | `prompts/hw-sw-partition`、`prompts/criterion-before-code` |
| 交付导出四条判据：按引用留凭据 / 被否决轮次不进包 / 交付名工程化并生成新旧名对照 / 导出后自检不过就不落盘 | `build/make_submission.sh`（2026-10-02 21:35）头部 | 2026-10-04 实读 | `templates/project-skeleton`、`templates/report-forms` |
| 目录/文件名口径（小写字母、数字、下划线或连字符，不得出现中文、空格或特殊字符）与"采用其他组织方式须在 README 给出目录对照说明" | `report/log/CONTEST_CHECKLIST.md:21`、`:120`（实读定位） | 2026-10-04 实读 | `templates/project-skeleton` |
| 仓库实际目录树（顶层 `src/ sim/ build/ board/ data/ report/ skill/`；`src/` 下 `constraints/ host/ ps/ rtl/`；`data/` 下 `golden/ measured/`；`report/` 下有 `log/`） | 实跑 `ls` 与 `ls src data report board sim`（2026-10-04，仓库根） | 2026-10-04 实跑 | `templates/project-skeleton` |
| 指标表七列表头逐字为 `指标名称,类别,数值,单位,测量条件,测试次数或时长,证据文件` | 实跑 `head -1 data/metrics.csv`（2026-10-04） | 2026-10-04 实跑 | `templates/report-forms/metrics-table.md` |
| 验收表按行记版本、读数用原文摘录、未盖章的行显式写"没有盖章"并给补法 | `board/ACCEPTANCE.md`（2026-10-04 08:39）机器判据节与 r96 节 | 2026-10-04 实读 | `templates/report-forms/acceptance-record.md` |
| 人眼判据 36 行、每条给"命令 → 该看见什么 → 看不见意味着什么"，且"读开机态要先清缓冲" | `board/VERIFY_r87.md`（2026-10-01 08:06）开头节；`data/metrics.csv`"人眼判据,验收,36"行 | 2026-10-04 实读 | `templates/report-forms/acceptance-record.md` |
| 协作记录的五栏（提示词原话 / 第一版回答 / 推翻它的读数 / 取证方式变化 / 落成的规矩）与"事实能按编号在同仓库查到" | `report/LLM_COLLAB.md` 开头声明与例 1–6；`report/AI_COLLABORATION.md`（2026-10-02 03:07） | 2026-10-04 实读 | `templates/report-forms/collab-record.md` |
| 优化过程与**没采纳**的那些写在同一份文档 | `report/OPTIMIZATION_LOG.md`（2026-10-02 01:27）；`report/log/CONTEST_CHECKLIST.md` §1 同项行 | 2026-10-04 实读 | `templates/report-forms/optimization-compare.md` |
| 复位值/默认档要从主机侧初始化代码逐条 grep，并配"屏上/回读怎么验"一列；开机做一次写图案再读回的配对自检 | `report/DEFAULTS.md`（2026-10-01 23:49）§1 | 2026-10-04 实读 | `templates/interface-contract` |
| 窗口式读回必须"一组自洽"：新成员排在第一个字之后、快照取自读法本身、可信位为 0 时既不判红也不判绿；实测形状"8 组里 3 组破""`trusted=600 violated=0`" | `skill/atomic_register_window_readback.md`（2026-10-01 08:06）动作 2/4/5/6/7 | 2026-10-04 实读 | `templates/interface-contract` |
| 越界写仿真丢、硬件按地址位宽截断 ⇒ "声明初值 ≠ 上电值"，台架天生看不见这一类 | `report/LLM_COLLAB.md` 例 1 第五版 | 2026-10-04 实读 | `templates/interface-contract`、`prompts/criterion-before-code` |
| 技能卡自检器只把标题形如 `# S<数字>` 的 `.md` 当卡片（六节 + ≤120 行 + README 计数行核对）⇒ 本批次新目录用 frontmatter + `## n.` 八节，不进那把尺子的射程 | `build/check_skill_cards.py`（2026-09-30 22:30）`REQUIRED/MAX_LINES/cards()` 实读 | 2026-10-04 实读 | 本目录全部条目（写作口径） |
| 交付文档扫描范围含 `skill/`（编码检查）与 `skill` 文档目录（行号引用检查，代码扩展名 `.v .c .h .mjs .sh .tcl .ps1`） | `src/host/doc_enc_check.mjs`（2026-10-02 09:23）`SCOPE` 行；`src/host/line_cite_check.mjs`（2026-10-03 02:22）`DOC_DIRS/CODE_EXT` 行 | 2026-10-04 实读 | 本批次全部条目（自检口径） |
| 脚本模板自身实跑：`bash -n` 无输出；不带槽位运行打印 `REFUSE: 没设报告目录（当前 REPORT_DIR=）` 且 `rc=3`；`--self` 打印 `SELF: 全绿（7 条）` 且 `rc=0` | `skill/templates/script-template/script-template.sh`（本次写入并实跑，2026-10-04） | 2026-10-04 实跑 | `templates/script-template` |
| 一次真实调试：反例最初用 `env` 传变量，本机 `PATH` 上的 `env` 垫片吞掉子进程输出 ⇒ 全部反例 rc=0（假绿）；改为生成 `export` 包装脚本并要求收尾行首词对上 | 实跑 `type env`（返回 `/c/Users/wenqu/.local/bin/env`）与两次 `--self`（第一次 5 条 FAIL、第二次全绿 7 条） | 2026-10-04 实跑 | `templates/script-template` |
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
<!-- END MERGED PROPOSED SOURCES -->

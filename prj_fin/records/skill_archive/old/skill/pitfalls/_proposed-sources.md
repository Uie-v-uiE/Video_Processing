# `skill/pitfalls/` 建议来源表（proposed sources）

本表是给 `_meta/sources.md` 的**候选行**，不是 `_meta/` 本身（本任务只允许写 `skill/pitfalls/` 与 `skill/references/`）。
每行四列：`结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目`。
来源类型标注：`件`=本仓库里的一份真实工件（我本次打开过）；`代码`=本次打开过的脚本；`台账`=本次打开过的 `report/log/ISSUES.md` 小节；`网`=本次真正抓取过的网页；`未核实`=本次没拿到可打开的来源。

| 结论一句话 | 来源 URL 或本地路径 | 核对日期 | 用在哪个条目 |
|---|---|---|---|
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
| xsim 的 `$display`：字符串字面量赋给定宽向量或作为 task 实参时每字节 bit7 被清；字段超长时丢的是头部（左边截）⇒ 判据标签只写 ASCII | 台账 `report/log/ISSUES.md`（该文件第 1938–1941、6566–6568 行）；同族 `skill/references/bench-verilog-subset/SKILL.md` | 2026-10-04 | console-codepage-verdict-shift |
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
| 只读评审的采信口径：只有能指回 `file:line` 的发现进正文，其余降级为候选或不采信（16 条 ⇒ 8 进正文、4 降 CANDIDATE） | 台账 `report/log/ISSUES.md` #125（该文件第 5402 行起）；做法在 `skill/prompts/read-only-review-agent/SKILL.md` | 2026-10-04 | assertion-not-in-any-file |
| UG901 / UG904 / UG1399 / UG949 这四份厂商文档：**本包本轮没有打开过**（`docs.amd.com` 页面本次抓取返回"需要启用 JavaScript"，取不到正文） | 未核实（类型=未核实；本轮抓取记录见 references 侧来源表） | 2026-10-04 | references/tool-version-drift（标记为 NOT_MEASURED） |

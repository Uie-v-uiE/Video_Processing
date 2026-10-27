# 版本绑定的事实行（上一级是 `SKILL.md`）

规则：每行只写"这一版上量到过"的形状。本队同时只见过一个 Vivado 版本（`2025.2.1 (win64) Build 6403652`），
所以"其他版本"那一律留 `空（未同时见过两个版本）`，不填猜测——这既是本页的口径，也是 P06 铁律 4 的要求。
**本页不是判据**：要下结论请引用该行点名的件路径本身或 `evals/` 记录。

## 目录

- A 组：命令与选项的存在性
- B 组：报错码与报错文本的归属（谁在说谎）
- C 组：报告件的字段与列名
- D 组：主机侧（shell / 码页 / Node / Python）
- E 组：换版本 / 换家族时要重跑的清单
- F 组：厂商文档（本轮状态）

## A 组：命令与选项的存在性

| 事实 | 2025.2.1 (win64) 实测 | 其他版本 | 出处 | 来源类型 | 核对日期 | 支撑条目 |
|---|---|---|---|---|---|---|
| `phys_opt_design` 的选项集合 | 31 个选项；`-force_replication_on_nets`/`-fanout_opt`/`-critical_cell_opt`/`-placement_opt`/`-retime`/`-directive` present=1；`-skeleton_clustering`/`-rewire`/`-replication_count`/`-cell_opt`/`-shift_registers` present=0 | 空（未同时见过两个版本） | 件 `build/evidence/r117_d0/nethelp_console.txt:395,402-407` | 件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| 传未知选项时的答语 | `ERROR: [Common 17-170] Unknown option '-unmerged', please type 'read_xdc -help' for usage info.`（`read_xdc -unmerged` 实测） | 空（同上） | 件 `build/evidence/r115_window/console2.txt:177,209,241,273`；台账 `report/log/ISSUES.md` #319 | 件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `-filter` 表达式里的合法操作符 | `eq` 报语法错（见 B 组第一行）；`==` 与 `=~` 在本版可用（同一份 DCP 实测两种写法结果不同） | 空（同上） | 件 `build/evidence/r114_idelay_prop_console4.txt:63`、`build/evidence/r114_idelay_set_console.txt:53-55` | 件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `get_false_paths` / `get_timing_exceptions` / `get_clock_groups` | **不是本工具的命令**：`info commands *exception*` 只回 `report_exceptions` | 空（同上） | 件 `build/evidence/r114_cmds_console.txt:13-18`；台账 `report/log/ISSUES.md` #277 | 件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `report_clock_timing` | 在 7 系列批处理里**不存在**（`invalid command name`） | 空（只在这一版/这一家族见过） | 台账 `report/log/ISSUES.md`（该文件第 6468 行） | 台账 | 2026-10-04 | references/tool-version-drift |
| `open_hw_manager` / `open_hw_target` | 是 **Vivado** 的命令；在 xsdb 里 `source` 会撞 `invalid command name "open_hw_manager"` | 空（未同时见过两个版本） | 代码 `build/tcl/README.md:33`；台账 `report/log/ISSUES.md`（该文件第 8999 行） | 代码+台账 | 2026-10-04 | exit-zero-nothing-written |
| Tcl `regexp` 的模式串以 `-` 开头 | 必须先用 `--` 终止选项解析，否则报 `bad option "-datapath_only": must be -all, -about, ...` | 空（同上） | 台账 `report/log/ISSUES.md` #277（该文件第 11870–11884 行） | 台账 | 2026-10-04 | tcl-query-empty-means-broken-ruler |

## B 组：报错码与报错文本的归属

| 事实 | 2025.2.1 (win64) 实测 | 其他版本 | 出处 | 来源类型 | 核对日期 | 支撑条目 |
|---|---|---|---|---|---|---|
| `ERROR: [Common 17-263] There was a syntax error while parsing filter expression: 'REF_NAME eq IDELAYE2' at position '9'` | 由 `-filter {… eq …}` 触发；同一查询带 `-quiet` 时**只留空集合**，错误被吞 | 空（未同时见过两个版本） | 件 `build/evidence/r114_idelay_prop_console4.txt:63`；台账 `report/log/ISSUES.md` #279 | 件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `ERROR: [Common 17-37] Directory in which file hold_0.rpt is to be written does not exist [/tmp/kx/r114sweep]` | 由 `report_timing -file /tmp/…` 触发（Vivado 侧的 `/tmp` 不是 bash 的 `/tmp`） | 空（同上） | 件 `build/evidence/r114_idelay_sweep_console.txt:688,1275,1876`；台账 #280 末段 | 件 | 2026-10-04 | win-bash-path-split |
| `ERROR: [Common 17-165] Too many positional options when parsing 'eth_rxd[3] …'` | 由 `set_input_delay -clock … -min A -max B [get_ports …]`（两条写进一条）触发；**被点名的端口列表不是过错方** | 空（同上） | 台账 `report/log/ISSUES.md` #308（该文件第 12657–12665 行） | 台账 | 2026-10-04 | tcl-query-empty-means-broken-ruler |
| `invalid command name "？#"` | 由 UTF-8 BOM（`EF BB BF`）开头的 `.tcl` 在第一行触发 | 空（同上） | 台账 `report/log/ISSUES.md`（该文件第 431–434 行） | 台账 | 2026-10-04 | console-codepage-verdict-shift |
| 系统码页读 `.tcl` 时，UTF-8 中文注释可打断解析（报错把整个 `foreach` 体当命令，位置是 body line 5） | 本版本实测一次（`build/tcl/r115_window_true_probe.tcl`） | 空（同上；`.xdc` 是否同样危险本轮 **未量**） | 台账 `report/log/ISSUES.md` #307 | 台账 | 2026-10-04 | console-codepage-verdict-shift |
| `targets -set 1` 在没起 `hw_server` 时报 `Invalid target`，而外层脚本照样 `exit 0` | Vitis 侧观察（版本串见 D 组备注：Vitis 版本未在被跟踪件里出现） | 空（未同时见过两个版本） | 台账 `report/log/ISSUES.md`（该文件第 9000–9001、13094 行） | 台账 | 2026-10-04 | exit-zero-nothing-written |

## C 组：报告件的字段与列名

| 事实 | 2025.2.1 (win64) 实测 | 其他版本 | 出处 | 来源类型 | 核对日期 | 支撑条目 |
|---|---|---|---|---|---|---|
| 器件写法在两份报告里不一致：`7z020-clg484`（timing）vs `xc7z020clg484-2`（utilization） | 同一版构建的两份件实测 | 空（未同时见过两个版本） | 件 `build/timing_summary.rpt:8`、`build/utilization.rpt:8` | 件 | 2026-10-04 | build-report-field-map |
| `Speed File : -2  PRODUCTION 1.12 2019-11-22`（速度模型自带日期戳） | 实测 | 空（同上） | 件 `build/timing_summary.rpt:9`、`build/cdc.rpt:9` | 件 | 2026-10-04 | tool-version-drift |
| `report_timing_summary` 的 Design Timing Summary 只有一条数据行，列序 12 列 | 实测（$1 WNS、$3 TNS 失败端点、$8 THS 总端点、$12 TPWS 总端点） | 空（同上） | 件 `build/timing_summary.rpt:149-151` + 本次 `awk` 字段表实跑 | 件+实跑 | 2026-10-04 | report-field-parse-breaks |
| `report_cdc` 的 `No Common Primary Clock` 占 4 个 token、`Safely Timed` 占 2 个 ⇒ 固定列号会读错 | 实测（`build/cdc.rpt:17` vs `:24`） | 空（同上） | 件 `build/cdc.rpt:15-24`；代码 `build/gates.sh:97-100` | 件+代码 | 2026-10-04 | report-field-parse-breaks |
| `report_methodology` 的 `Checks found: 446`，其中七条规则全为 Warning ⇒ `CRITICAL WARNING` 行数 0 | 实测（本次 `grep -ac "CRITICAL WARNING"` = `0`） | 空（同上） | 件 `build/methodology.rpt:26,28-36` | 件+实跑 | 2026-10-04 | checker-ran-on-nothing |
| `report_timing_summary` 内嵌的 methodology 表自带"可能不是最新"的提示行 | 实测 | 空（同上） | 件 `build/timing_summary.rpt:54` | 件 | 2026-10-04 | who-else-writes-this-artifact |
| `set_property IDELAY_VALUE <档>` 在**已布线 DCP** 上有效（扫档位不必重跑构建） | 实测（0/13/26/31 四档，5 颗 IDELAYE2 一次改全，读回逐颗打印） | 空（同上） | 台账 `report/log/ISSUES.md` #310（该文件第 12700 行）；件 `build/evidence/r114_idelay_sweep_console.txt` | 台账+件 | 2026-10-04 | tcl-query-empty-means-broken-ruler |

## D 组：主机侧（shell / 码页 / Node / Python）

| 事实 | 本次实测值 | 出处 | 来源类型 | 核对日期 | 支撑条目 |
|---|---|---|---|---|---|
| Node | `v24.21.0`（`report/BUILD.md:15` 声明"需要 Node 24"，同主版本线） | 本次 `node --version` 实跑 + 代码 `report/BUILD.md:15` | 实跑+代码 | 2026-10-04 | tool-version-drift |
| Python | `Python 3.12.10` | 本次 `python --version` 实跑 | 实跑 | 2026-10-04 | tool-version-drift |
| Bash | `GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)` | 本次 `bash --version` 实跑 | 实跑 | 2026-10-04 | win-bash-path-split |
| 工具入口位置由环境变量给（`VP_VIVADO_BIN`/`VP_XSDB`/`PS_CC`/`PS_BSP`/`PS_OUT`），仓库内不写绝对路径 | 代码 `report/BUILD.md:22-31`（变量表） | 代码 | 2026-10-04 | win-bash-path-split |
| `xvlog/xelab/xsim` 只在 `vivado.bat -mode batch -source` 里可用；批处理要带 `-nojournal -log <路径>` | 代码 `skill/prompts/round-work-loop/SKILL.md` §4.1（原旧整包外壳 `SKILL.md` 的第 71–72 行，2026-10-04 退役时逐字搬入该条目）；本轮**未重跑仿真** ⇒ 该格属"仓库声明"，非本次实跑 | 代码 | 2026-10-04 | win-bash-path-split |
| Vitis / xsdb 的版本串在被跟踪件里**没有**出现（本轮检索 `build/*.rpt`、`build/evidence/*` 未见 `Vitis v.` 字样） | 本轮检索结果（负结果，如实登记） | 实跑检索 | 2026-10-04 | tool-version-drift |

## E 组：换版本 / 换家族时要重跑的清单

| 触发 | 需要重跑/重判的东西 | 出处（本仓口径） | 核对日期 | 支撑条目 |
|---|---|---|---|---|
| 换 Vivado/Vitis 版本 | `ps7_init`、BD 地址、实现策略、**全部门禁数字** | `skill/prompts/round-work-loop/SKILL.md` 的"环境事实"一节（本次打开） | 2026-10-04 | tool-version-drift |
| 换器件家族（7 系列 ↔ UltraScale+ ↔ Versal） | `IDDR/IDELAYE2/IDELAYCTRL/OSERDESE2/MMCME2_BASE` 一类原语整段失效；报告列名与 `report_cdc` 的 token 形状要重量 | 同上；列名实测见 C 组 | 2026-10-04 | build-report-field-map |
| 只换主机 OS（Windows ↔ Linux） | `tasklist`/`cygpath` 整段作废；`/tmp` 视图合一后 `Common 17-37` 那一支不再出现 | 台账 `report/log/ISSUES.md` #244、#280、#317 | 2026-10-04 | win-bash-path-split |

## F 组：厂商文档（本轮状态）

| 想确认的事 | 权威出处 | 本轮状态 | 核对日期 | 支撑条目 |
|---|---|---|---|---|
| 综合（UG901）/ 实现（UG904）/ Vitis HLS（UG1399）/ UltraFast 方法学（UG949）里的具体条款 | 文档号按赛题 3.3.7 点名 | **未核实**：本轮抓取 `docs.amd.com` 只得到"需要启用 JavaScript"，没读到正文 ⇒ 不填章节号、不填结论 | 2026-10-04 | tool-version-drift |
| 本设计用到的 IP 的产品指南（PG 编号）、器件手册/封装电气（TRM、DS） | 待定 | **未核实**：本轮没有打开任何 PG/DS 文档；编号一律留空（赛题口径也是"编号一律【核对】后再写"） | 2026-10-04 | tool-version-drift |
| Tcl `catch` 的返回码语义（0=TCL_OK；`var` 收消息；1/2/3/4 = ERROR/RETURN/BREAK/CONTINUE） | https://www.tcl-lang.org/man/tcl8.6/TclCmd/catch.htm | **已打开并读到该段**（本轮唯一成功抓取到的外部正文；本地印证 `report/log/ISSUES.md` #327） | 2026-10-04 | exit-zero-nothing-written |
| AMD 中文社区论坛（`adaptivesupport.amd.com`）用于"这是普遍现象还是本队环境特有"的判断 | 论坛检索页 | **本轮未取到可用正文**（搜索结果只给链接列表，未打开具体答复）⇒ 凡"是否普遍"的判断在本包一律不写 | 2026-10-04 | tool-version-drift |

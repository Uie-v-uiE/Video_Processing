# `prompts/` 条目的来源账（提交给 `skill/_meta/sources.md` 的候选行）

我无权写 `skill/_meta/sources.md`，所以本次每一条"关于工具行为/流程/数字"的说法都在这里留一行：
结论一句话 | 来源（本地路径或 URL）| 核对日期 | 用在哪个条目。

核对方式说明（避免读者以为我做了我没做的事）：

- "实读"= 本次会话用 Read/`sed -n`/`grep` 打开过该文件并抄了原文行。
- "实跑"= 本次会话真的执行过那条命令，输出摘要写进行里。
- 本次**没有访问任何外部 URL**（没有翻 UG 文档、没有翻 GitHub）；所以凡是需要官方文档原文支撑的说法，
  我在条目正文里都写成"从你手上的指南/报告取"或标 `【未实测】`/`【未核实】`，没有引用文档编号。
- 文件日期取 mtime（`stat -c '%y %n'` 实跑于 2026-10-04，仓库 `D:/Xilinx/Prj/pro/Video_Processing`）。

| 结论一句话 | 来源（本地路径或 URL）| 核对日期 | 用在哪个条目 |
|---|---|---|---|
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
| 判据标签被 100 字节容器按字节从左边截断 ⇒ 一条判据在日志里"消失"；新写判据标签一律 ASCII | `report/LLM_COLLAB.md` 例 6（#162）、`skill/pitfalls/criterion-blind-spot/SKILL.md`（2026-10-01 08:06）触发第 7 条 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/script-template` |
| 收尾解析把一支真红台架报成 `NO-VERDICT-LINE + FAIL 行数=0`（红与"没数"长得一样），候选解析器被"不许让过期日志替本台架答复"这条反例打回 | `sim/run_one.sh`（2026-10-01 07:40）`--verdict` 分支注释；`report/LLM_COLLAB.md` 例 6；#163/#164 | 2026-10-04 实读 | `prompts/criterion-before-code`、`templates/script-template` |
| 台架脚本退出码分五态：0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 判红 / 4 认不出判定行，"3 与 4 必须分开" | `sim/run_one.sh` 第 40、112–119 行 | 2026-10-04 实读 | `templates/script-template` |
| 门禁退出码与三态收尾（`GATES: ALL PASS（N 项全部判定）`/`GATES: 有红项`/`GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判`），且行首换词让下游冻结自动拒绝 | `build/gates.sh`（2026-10-02 23:06）收尾 20 行；`report/LLM_COLLAB.md` 例 5 | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 逐项四列打印式 `printf "  %-22s %-12s %-28s %s\n"` 与 `NSAY/NNA` 计数 | `build/gates.sh:175`（`say()`，实读定位） | 2026-10-04 实读 | `templates/script-template` |
| 读报告的行正则必须允许数字带符号；读不到时把最像的三行原样打出来（r60 那次 TNS 是负数导致"读不到"顶替了 WNS −0.482/19 个失败端点） | `build/gates.sh:62-77`（第 1 项注释与 awk） | 2026-10-04 实读 | `templates/script-template` |
| 射程/命中地板写进判据（D5 `命中 >= 300`、D6 `判 >= 30 个数 / 首页 >= 20 / 百分数 >= 6 / csv 认领两半相等`）——"扫不到的尺子也报硬错 0 条，那是空转不是绿" | `build/gates.sh` 第 20/21 项（`build/gates.sh:508`、`:537` 附近）；`src/host/metric_recheck.mjs`（2026-10-04 03:07）头部 | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 判断脚本成不成要用 `cmd > file 2>&1; echo rc=$?`，永不读被 pipe 掉的命令的状态；`set -e` + `pipefail` 会让兜底分支没机会执行 | `report/LLM_COLLAB.md` 例 4（#133/#106） | 2026-10-04 实读 | `templates/script-template`、`prompts/criterion-before-code` |
| 工具定位走环境变量、找不到在第一步 REFUSE 并念出变量名；实跑输出 `REFUSE: 找不到 xvlog（当前 …）` + `rc=2`，且拒绝发生在 `mkdir`/`sed` 之前 | `report/BUILD.md`（2026-10-02 09:23）§1 表格与末段实跑两行 | 2026-10-04 实读 | `templates/script-template`、`templates/project-skeleton` |
| 一次只测一件事（同树重复滚 = 零散布），"多变量会把单变量性打掉"的候选直接 excluded | `report/log/ISSUES.md` #223（结案行实读）；`docs/timing/cut_ledger.tsv` C2/C5 行 | 2026-10-04 实读 | `prompts/single-variable-ab` |
| 新红了先退回未改状态、用同一版台架再跑一遍比红名单（含台架 md5 也要一致） | `skill/pitfalls/ab-revert-control-run/SKILL.md`（2026-10-01 08:06）动作 1–5；#113 | 2026-10-04 实读 | `prompts/single-variable-ab` |
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
| 窗口式读回必须"一组自洽"：新成员排在第一个字之后、快照取自读法本身、可信位为 0 时既不判红也不判绿；实测形状"8 组里 3 组破""`trusted=600 violated=0`" | `skill/runtime/atomic-register-window-readback/SKILL.md`（2026-10-01 08:06）动作 2/4/5/6/7 | 2026-10-04 实读 | `templates/interface-contract` |
| 越界写仿真丢、硬件按地址位宽截断 ⇒ "声明初值 ≠ 上电值"，台架天生看不见这一类 | `report/LLM_COLLAB.md` 例 1 第五版 | 2026-10-04 实读 | `templates/interface-contract`、`prompts/criterion-before-code` |
| 技能卡自检器只把标题形如 `# S<数字>` 的 `.md` 当卡片（六节 + ≤120 行 + README 计数行核对）⇒ 本批次新目录用 frontmatter + `## n.` 八节，不进那把尺子的射程 | `build/check_skill_cards.py`（2026-09-30 22:30）`REQUIRED/MAX_LINES/cards()` 实读 | 2026-10-04 实读 | 本目录全部条目（写作口径） |
| 交付文档扫描范围含 `skill/`（编码检查）与 `skill` 文档目录（行号引用检查，代码扩展名 `.v .c .h .mjs .sh .tcl .ps1`） | `src/host/doc_enc_check.mjs`（2026-10-02 09:23）`SCOPE` 行；`src/host/line_cite_check.mjs`（2026-10-03 02:22）`DOC_DIRS/CODE_EXT` 行 | 2026-10-04 实读 | 本批次全部条目（自检口径） |
| 脚本模板自身实跑：`bash -n` 无输出；不带槽位运行打印 `REFUSE: 没设报告目录（当前 REPORT_DIR=）` 且 `rc=3`；`--self` 打印 `SELF: 全绿（7 条）` 且 `rc=0` | `skill/templates/script-template/script-template.sh`（本次写入并实跑，2026-10-04） | 2026-10-04 实跑 | `templates/script-template` |
| 一次真实调试：反例最初用 `env` 传变量，本机 `PATH` 上的 `env` 垫片吞掉子进程输出 ⇒ 全部反例 rc=0（假绿）；改为生成 `export` 包装脚本并要求收尾行首词对上 | 实跑 `type env`（返回 `/c/Users/wenqu/.local/bin/env`）与两次 `--self`（第一次 5 条 FAIL、第二次全绿 7 条） | 2026-10-04 实跑 | `templates/script-template` |

## 还缺的来源（我没查、条目里也不该当作事实的事）

| 待补事项 | 为什么现在不能写 | 需要谁做什么 |
|---|---|---|
| UG901 / UG904 / UG949 / Tcl 命令手册里"瓶颈定位与方法学检查"的章节号与原文 | 本次未访问任何 URL，也没有本地副本 ⇒ 按铁律不许凭记忆写文档编号 | 要引用就给我 PDF 或允许我上网核对，之后把行加进本表 |
| 赛题指南 §3.3.5.4 那张"推荐目录表"的原文 | 仓库里没有该表副本，只有 `report/log/CONTEST_CHECKLIST.md` 的转述与两处引文 | 需要指南原文才能填对照表的左列（条目里已写成"照抄你的指南原文"） |
| 高扇出/复制手段在其他器件家族（UltraScale+ / Versal）的命令与属性名 | 本仓库只在这颗器件与该版本工具上实测过（含"某条命令不存在"的负结果） | 换家族后要重跑 help 探针，再把结论加进 `prompts/report-to-bottleneck` 的平台相关行 |
| 四个 prompt 模板的"同一模板连跑 3 次"记录 | 本次未跑任何 agent 会话 ⇒ 各条目第 7 节都写 `【待验证】`，还差 3 次/条 | 需要真实跑三次并把输出文件名写进 evals |

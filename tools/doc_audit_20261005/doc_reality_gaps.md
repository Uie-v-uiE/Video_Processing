# doc_reality_gaps

范围：`README.md`、`README_EN.md`、`report/*.md`、`board/*.md`、`data/README.md`、`build/README.md`
（排除 `report/log/`、`skills/`、`docs/`、`data/metrics.csv`）

## A. 失实

抽取尺子（一次抽完，非手挑）：`grep -nE "未修|未解决|待验证|待接|尚未|无法|不能|本机|这台机器|暂不具备|不是最新|缺|仍|TODO|未测|判红|NOT_MEASURED|保留" README.md README_EN.md report/*.md board/*.md data/README.md build/README.md`
⇒ 命中行 700 余，其中真"讲工程状态"的 96 条进入逐条核验；纯 token 定义／表头／模板占位（`NOT_MEASURED：不等于通过`、`【填入】`槽位）不计。

现用尺子读数（本次实跑，作为判定基线）：
`node src/host/metric_recheck.mjs` ⇒ 判 117 个数／红 0；
`node src/host/doc_currency_check.mjs` ⇒ `CURRENCY: 干净`；
`node src/host/line_cite_check.mjs` ⇒ `硬错 0 条`／`D5: CLEAN`；
`node build/deliver_spec_check.mjs` ⇒ 判 18 项 红 0 未测 0 `PASS`；
`build/evidence/r120_final_gate.txt` ⇒ C1 PASS、C2 PASS、C3 FAIL（死引用 3）、C4 FAIL（违规 286）、C5 `NOT_MEASURED`（300 s）、C6 PASS、C8 PASS、C9 FAIL（91/30/32）、C12 PASS（绿 12 红 0）、总行 绿=8 红=3 未测=1。

### report/90-open-items.md（整份是 2026-10-04 12:38 的快照，是 A 节失实最密集的一处）

- L160 「权威件没落地…`test -e report/declarations.md` = 不存在」 ⇒ 判定：**已修未改** ｜证据：`report/declarations.md` 现在在盘上且有正文（其 L22/L24/L40 为器件与版本条目）；`build/evidence/r120_final_gate.txt:1` C1 `比过=88 器件冲突=0 版本冲突=0 PASS` ⇒ 该判据已生效 ｜动作：整行删（编号 26 连同"从未生效过"那句一起），要留的信息换成一行指路 `权威件=report/declarations.md，机检=C1`
- L160 「**`data/README.md` 同样不存在**（它被 `report/README.md:23` 点名，属编号 6 那批死引用）」 ⇒ 判定：**已修未改** ｜证据：`data/README.md` 在盘（62 行）；`line_cite_check` 硬错 0 ｜动作：删这半句
- L117 「死引用：ISSUES 记 68 条，`12:29` 实跑 **64** 条、`12:46` 起 **66** 条」＋「有 2 条是本轮新导航故意点名的缺口（`report/claims-vs-evidence.md`、`data/README.md`）」 ⇒ 判定：**已修未改（数字过期）** ｜证据：`build/evidence/r120_final_gate.txt:6` C3 `死引用=3`（三条点名都在 `docs/` 或路径基准上，不含这两份）；两份被引文件都在盘 ｜动作：66→3 就地重算并删"2 条缺口"那半句
- L118 「技能包门禁仍有 3–4 红 1 未测：G2 缺壳 / G10 专有名未标注 / G11 selftest 未落地，另有 26 张平铺卡未迁移」 ⇒ 判定：**已修未改** ｜证据：`build/evidence/r120_final_gate.txt:15` C12 `绿=12 红=0 未测=0 判据行=12 加总对账=12/12 PASS`；同口径另见 `report/final-gate.md:29`、`report/repro-check.md:84`（第三轮 `判 53 项 红=0 未测=0 PASS`） ｜动作：编号 7 与 114 两行状态改 `已闭合（备查）`，"3–4 红 1 未测"那句删
- L116 「C2 报"6 行指标没指到存在的证据文件"…需要的是改哪一侧的裁决」 ⇒ 判定：**已修未改** ｜证据：`build/evidence/r120_final_gate.txt:2` C2 `行=28 全指到=28 缺或无路径=0 PASS`；修法已落地并登记在 `report/known-limitations.md:51`（"C2 的取径正则吞全角标点"） ｜动作：删这行的"待裁决"，状态改已闭合
- L119 「`build/checks/check_repo_hygiene.sh` 在 **60 s** 内不返回 ⇒ C5 只能是 NOT_MEASURED」 ⇒ 判定：**确实未修（但数字过期）** ｜证据：`build/evidence/r120_final_gate.txt:8` C5 `被调脚本 300 s 未返回…NOT_MEASURED`；`report/known-limitations.md:5.1` 也写着 C1 层已修、C5 层待改 ｜动作：`60 s`→`300 s`，其余保留
- L115 「全仓 **224 个**跟踪路径含大写字母（末段 200 + 目录段 42 − 交集 18）」 ⇒ 判定：**确实未修（数字过期）** ｜证据：`build/evidence/r120_final_gate.txt:7` C4 `跟踪文件=3601 违规=286 点名豁免=22 FAIL`；现口径在 `report/known-limitations.md:47`（308 = 266+45−3）与 `report/submission-checklist.md:19` ｜动作：224→308/违规 286，或直接删本行改指 `known-limitations.md` §6
- L138/L139/L141 「`data/metrics.csv:14` 现件是 24 项」「`:15` 实跑 = **162 条**」「Max Ambient 表里写 **57.5**、现件是 **57.4**」 ⇒ 判定：**确实未修** ｜证据：`data/metrics.csv` 第 14 行仍是 `门禁自检项,自检,22`；`grep -c '^PASS' build/tb_v98_report.txt`=161、`^FAIL`=1、头 `top_md5=56c269602e18`；`build/power.rpt:39`=`57.4` 而 `data/metrics.csv:28`=`57.5` ｜动作：三行保留，但要补一句"同一登记已落在 `build/evidence/r121_note_metrics.txt`（现含四处，另加第 16 行变异对照 5→7）"，否则读者以为这里唯一
- L150/L184 「改 `report/build.md` 那三行为 `send_demo.bat`…未改，需一句授权」 ⇒ 判定：**确实未修** ｜证据：`ls run_sender.bat run_video.bat run_serial.bat` 三条都 No such file（`find` 全仓 0 命中）；`report/build.md:79-81` 与 `:100` 仍逐字点名这三支 ｜动作：保留状态，但删"本轮未改／需授权"的过程腔，改成"该三行指向不存在的脚本，可跑的是根 `send_demo.bat`"
- L151 「在那行旁补"仓库名 / 包内名"两跳」 ⇒ 判定：**已修未改** ｜证据：`report/known_issues.md:38` 现文为 `bash build/sim/run_one.sh tb_v98_top_seam`（仓库里的名字；导进包才改名成 `tb_video_pipeline_top`，两跳见 `build/sim/names.md`），且 `build/sim/names.md` 在盘 ｜动作：编号 22 状态改已闭合
- L152 「`build/README.md` 说产出在 `build/reports/`…本会话复测补一刀：`build/reports/` 此刻**存在**」 ⇒ 判定：**已修未改** ｜证据：`build/README.md:19,94-100` 现写 `build/report/`（单数），`ls build/report` = 7 份 `.rpt` 齐 ｜动作：编号 23 整行删
- L154 「`board/README.md` 实测表复述 WNS 0.720/WHS 0.033/0-of-50890/2.207 W，而现件是 0.739/0.052/0-of-51135/2.391 W」 ⇒ 判定：**确实未修** ｜证据：`board/README.md:25`（`0.720 ns（9.0 %）`/`0.049 ns`）、`:94`（`0.720 / 0.033 / 0 / 50890`）、`:95`（`动态 2.207 W、估算结温 52.5 °C`）；现件 `build/timing_summary.rpt:151`=0.739/0.052/51135、`build/power.rpt:36`=2.213、`:33`=2.391、`:40` 区=52.6 ｜动作：编号 25/113 保留，但真正该做的是把 `board/README.md` 那三行改掉（见下面 `board/README.md` 一节）
- L211 「再生成的真实状态 = `NOT_MEASURED（本轮禁跑构建）`」（引 `board/firmware/ps_app.elf.md:58`） ⇒ 判定：**已修未改** ｜证据：`build/evidence/1005_ps_app_rebuild.txt` 已有一次真实重建（`report/known-limitations.md:16-19` 逐字给出命令、`OK` 与两个 md5） ｜动作：删"本轮禁跑"这一类带轮次的措辞，改成指重建记录件
- L121/L127 「`src/rtl/eth/eth_udp_video_top.v:131,144` 确认仍直连」 ⇒ 判定：**确实未修** ｜证据：该文件 `:131` 与 `:144` 现为 `.gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd)` 直连进 `u_arp` / `u_icmp` ｜动作：保留
- L128 「② 仍欠的是"串口读不到旋转角度"（`status` 口那 9 位在 `system_top` 没有读者）」 ⇒ 判定：**确实未修** ｜证据：`report/known-limitations.md:38` 仍列该欠账、`report/claims-vs-evidence.md:44` 判 `未见凭据`（`build/evidence/r118_eyes/uart_stat.txt` 无 angle/ROT 字段） ｜动作：保留
- L129 「任务把 #216 列为"仍欠"，实读不对：…r102 板上闭环」 ⇒ 判定：**已修未改（本文对，但别处文档仍写"未修"）** ｜证据：`build/r104_board_ping.txt`（发送 4／接收 4／丢失 0）＋ `report/known_issues.md:372-373`；反例见 `report/known-limitations.md:79` ｜动作：编号 13 保留，把它的凭据串接到 known-limitations §9 那一行（见下面该文件）
- L131 「本机 UG471(188 页)/UG472(114 页) 逐行筛命中 0 页 ⇒ 话停在"没筛出来"」 ⇒ 判定：**确实未修** ｜证据：`report/known-limitations.md:36` 仍写"收益假设 0.5/0.2 ns 还没有独立证据钉住"、`report/08-limits.md:119-121` 同口径；HEAD 提交 `a952b93` 判负回退 RTL ｜动作：保留事实，删"本机"措辞（改为"仓库内无该两本手册、按页筛未命中"）
- L140 「三处打架：①同一张表 `:20` 行写"端到端时延, 未报"；②`report/perf_report.md:207`…」 ⇒ 判定：**确实未修** ｜证据：`data/metrics.csv:20` 现为 `端到端时延,未报,…待复测`，`:25` 为 `端到端时延,核心,33.34,ms` ⇒ 同表两行并存 ｜动作：保留（数字对账尺子 D6 不覆盖这两行，见 `report/repro-check.md:137` R2/R5 同族）
- L443-L466 整节「改前（12:29 实跑）…改后…第 1 趟 12:46:38…第四趟 13:00…」 ⇒ 判定：**过程回声，不是状态声明** ｜证据：同一件事在 `report/log/issues.md` 台账 #337/#339 已有逐轮记录；`report/claims-vs-evidence.md:80` 与 `report/final-gate.md:26-30` 已给当前口径 ｜动作：整节删（约 25 行），只留"当前 C1–C12 读数见 `build/evidence/r120_final_gate.txt`"
- L507-L528 「## 6. 本轮没有做的事（诚实交代 + 需要什么）」＋ L530-L548 「## 7. 取证清单（本轮真实打开/实跑过的东西）」 ⇒ 判定：**过程回声** ｜证据：`report/log/` 台账即同族记录；这两节的信息没有任何一份交付文档引用 ｜动作：两节整删（约 42 行）
- L3 「对应 P18c 铁律 5」「P21 的 C8 核对这一条」等 40 余处内部轮次代号（P00/P16b/P18c/P20/P21/P23/铁律 N/规矩 N） ⇒ 判定：**过程回声** ｜证据：同目录 `report/README.md`、`report/declarations.md` 对外不依赖这些代号 ｜动作：删代号或换成"仓库口径"，约 45 行受影响

### report/known-limitations.md

- L79 「ping 应答器上板几分钟后变哑（与载荷长度无关）｜ ISSUES #216/#188，板级判据仍未验 ｜ 只记录，**未修**」 ⇒ 判定：**已修但文档写未修** ｜证据：`build/r104_board_ping.txt` 首行 `r104 ICMP 三段实测`，段内 `已发送 = 4，已接收 = 4，丢失 = 0`，紧接 `--- -l 0 ---`；正文口径 `report/known_issues.md:372-373`「板上闭环已完成…普通 `ping -n 4` = 4/4；`ping -n 3 -l 0` = 3/3」；`report/90-open-items.md:129` 编号 13 明确判"已闭合（备查）" ｜动作：该行整条从"行为层面的已知缺陷"表里删掉；若仍想保留演示前预检建议，挪去 `report/demo_script.md` 且措辞改为"退回旧位流时的恢复规程"（见 `report/known_issues.md:932-936`）
- L23 「这一节以前写成"这台机器不能重建 ELF"，那是把"入口找不到"误写成"机器里没有"」 ⇒ 判定：**校准样本，不再报**（同节 L16-19 已给可重建命令与 `build/evidence/1005_ps_app_rebuild.txt`） ｜动作：删"这一节以前写成…误写成"这半句（历史更正属过程腔，B 节计），保留边界句
- L44 「`report/repro-check.md` 的逐条实跑读数：**PASS=91 / FAIL=30 / 未测=32**」 ⇒ 判定：**无法判定（两处口径互斥）** ｜证据：`build/evidence/r120_final_gate.txt:12` C9 逐字 = `PASS=91 FAIL=30 未测=32`；但 `report/repro-check.md:21-38` 自己的分母表是"两轮相加 81/61/1/19"与"第三轮 61/36/0/11"，两种加法都凑不出 91/30/32；缺的那件凭据是"91/30/32 这次 C9 扫的是哪一版 repro-check" ｜动作：要么在本行补"C9 的计数式与本文分母表不同"一句，要么等第三轮之后的 C9 重跑件再更新；不许裸写 91/30/32 说成"本文读数"
- L45 「归因需要重跑构建与上板，这两件事不在文档轮的动作范围内，**未做**」 ⇒ 判定：**确实未修** ｜证据：C9 判 FAIL（`build/evidence/r120_final_gate.txt:12`），无逐条归因件 ｜动作：保留事实、删"文档轮／动作范围"这套轮次腔
- L44 「终审 C9 这一项因此判为未通过」＋ L2 节标题里的"能重建 ELF" ⇒ 与 `report/submission-checklist.md:10` 直接冲突（见下）

### report/claims-vs-evidence.md

- L70 「点名的 r119_window_check.txt **没有 md5 头**…md5 头在 `build/evidence/r120_window_check.txt:2-6` ⇒ 判定 FAIL」 ⇒ 判定：**确实未修（该条本身就是失实登记）** ｜证据：`report/known-limitations.md:19` 仍写「`build/evidence/r119_window_check.txt`（含 5 份输入的现算 md5 头）」 ｜动作：把 known-limitations §1 的凭据件改成 r120 那份，或去掉"含 md5 头"这半句
- L86 「交付文档那两格已被件推翻（口径过期）⇒ **FAIL**」 ⇒ 判定：**确实未修**（指 `report/07-skill-distillation.md:46-47` 仍写"该脚本此刻不存在"） ｜证据：本表 L86 自述 `skills/_meta/run-all-checks.mjs` 才是现入口；`report/07-skill-distillation.md` 未随之改 ｜动作：改 07 那两格，本行随之消绿
- L77 「唯一那条红 = 声明过的 C5c」／L75「`GATES: 有红项（判定 24 项）`」 ⇒ 判定：**确实未修（且与本文对 C5c 的描述一致）** ｜证据：`build/r118_gates_final.txt` 末行逐字、`build/r118_gates.txt:53` ｜动作：保留

### report/final-gate.md（整张读数表停在 `build/evidence/r120_final_gate.txt`，本次实跑已变）

本次实跑 `node build/checks/check_repo_consistency.mjs`（只读，含 C5 的 300 s 超时）⇒
`C1 PASS(比过=47) C2 PASS C3 PASS(死引用=0) C4 PASS(违规=0) C5 NOT_MEASURED(300 s) C6 PASS(条目=49) C7 NOT_MEASURED(对=0) C8 PASS(总数=905) C9 PASS(36/0/11) C10 PASS C11 PASS C12 PASS(绿=9 判据行=9)`／总行 `绿=10 红=0 未测=2 NOT_MEASURED`。

- L23 「C3 …死引用=3…**FAIL**（3 条：2 条指向未落地文档、1 条是演练记录里的逐字引文）」 ⇒ 判定：**已修未改** ｜证据：本次实跑 C3 `死引用=0 … 豁免=碎片53/运行期1/台账197/同行声明15 PASS`；`report/notice.md` 那两条落点（`report/declarations.md`、`report/claims-vs-evidence.md`）现在都在盘上 ｜动作：改成本次读数，或删掉自抄的读数格、只留"现算见 C3 行"
- L24 「C4 …违规=286 **FAIL**（待裁决 Q-P21-2）」 ⇒ 判定：**已修未改** ｜证据：本次实跑 C4 `跟踪文件=3669 违规=0 点名豁免=71[README.md=20,SKILL.md=49,…] PASS`；`build/deliver_spec_check.mjs` 的 `C0-3 file-names-ascii-lowercase 违例=0 说明件豁免=71 PASS` 同口径 ｜动作：整格改 `PASS 违规=0`
- L26 「C9 …PASS=91 FAIL=30 未测=32 **FAIL**（30 条未逐条归因）」 ⇒ 判定：**已修未改** ｜证据：本次实跑 C9 `判定列在内=61 行 PASS=36 FAIL=0 未测=11 判定列不成词=14 PASS`；`report/repro-check.md:35` 第三轮行同值（61/36/0/11） ｜动作：改成 36/0/11；连带 `report/known-limitations.md:44` 与 `report/submission-checklist.md:14` 的"30 条未归因"叙述一并改口
- L27 「C7 …对=58 冲突=0 | PASS」 ⇒ 判定：**失实（方向相反）**：文档写 PASS，现尺子给 `NOT_MEASURED` ｜证据：本次实跑 C7 `对=0 冲突=0 NOT_MEASURED`（三处一致的比对对象归零 ⇒ 该项不再自证） ｜动作：改成 NOT_MEASURED 并写明"对=0 是射程空了，不是通过"
- L29 「C12 技能包门禁 | 直接调用 G1–G12 | 绿=12 红=0 未测=0 判据行=12 加总对账=12/12」 ⇒ 判定：**确实未修（口径过期，状态仍绿）** ｜证据：本次实跑 C12 「技能包门禁（run-all-checks 的 M1–M3 与 S1–S6）绿=9 红=0 未测=0 判据行=9 加总对账=9/9 PASS」——入口已从 G1–G12 换成 M/S 九项 ｜动作：判据名与数字都改；L11 「C12 要求"绿+红+未测 == 12"」同步改成"== 判据行数"
- L30 「总行 …绿=8 红=3 未测=1 有红项，不得提交 **FAIL**」 ⇒ 判定：**已修未改** ｜证据：本次实跑总行 `判定 12 项 绿=10 红=0 未测=2 仍有未测项 NOT_MEASURED` ｜动作：整行改口
- L34 「**现在不能宣称"交付终审全绿"**。三条红 + 一条未测都在上面这张表里」 ⇒ 判定：**已修未改**（红确实归零，剩两条未测） ｜证据：同上 ｜动作：改成"三条红已清，剩 C5/C7 两条未测；C5 是 `check_repo_hygiene.sh` 的 300 s 超时，C7 是比对集空"
- L36 「本轮把 C2/C3/C1 的三处量纲错改掉时，每一步都先取"改前红集"当基线」 ⇒ 判定：**过程回声** ｜证据：同一件事在 `report/known-limitations.md:51`（"C2/C3/C1 三处判定口径写错"）已有一次成文；台账 `report/log/issues.md` #339 有逐轮 ｜动作：删"本轮/改前红集"叙事，保留 `--self` 判 10 项 PASS 这一句可复核事实

### report/submission-checklist.md

- L10 「**ELF 不可重建**：本机无 `arm-none-eabi-gcc`，见 `report/build-notes.md`」 ⇒ 判定：**已修但文档写未修** ｜证据：`report/known-limitations.md:16-21` 已给可跑命令与 `arm-xilinx-eabi-gcc (GCC) 13.3.0`，凭据 `build/evidence/1005_ps_app_rebuild.txt`；被点名的指路 `report/build-notes.md` 里 `grep -nE "arm-none-eabi|ELF|编译器|重建"` **命中 0**（那页只讲构建报告） ｜动作：这格改成"源码随包；ELF 可用 `build/ps_app.mjs` 重建，重建颗与板上颗 md5 不同 ⇒ 需重刷 + `board_verify` 复验"，指向改 `report/known-limitations.md` §2
- L19 「**FAIL**：308 条路径含大写…**违规 286**；本轮自己新增的交付件又贡献了 61 条含大写路径」 ⇒ 判定：**已修未改** ｜证据：本次实跑 `C4 … 违规=0 点名豁免=71 PASS` ｜动作：状态改 PASS、删"本轮新增 61 条"过程腔、把"待裁决 Q-P21-2"整条撤下（`report/known-limitations.md:45-48` §6 同批改）
- L20 「**FAIL**：3 条真缺口（其中 2 条指向第 9/18 项未落地的文件）」 ⇒ 判定：**已修未改** ｜证据：本次实跑 C3 `死引用=0 PASS` ｜动作：改 PASS
- L14 「**FAIL**：…实跑结果是 `PASS=91 FAIL=30 未测=32`…缺的是将 30 条 FAIL 逐条归因」 ⇒ 判定：**已修未改** ｜证据：本次实跑 C9 `FAIL=0 … PASS` ｜动作：见 final-gate 同格
- L10 「提交阅读路径（八章）| `submit/{README,01-overview..08-limits}.md` + `submit/reproduce/` | **PASS** | `ls submit`」 ⇒ 判定：**失实（该格写 PASS 但复核命令跑不出东西）** ｜证据：仓库根无 `submit/`（`ls -d submit` ⇒ Not such file）；八章实际在 `report/01-overview.md`…`report/08-limits.md`（都在盘） ｜动作：位置列改 `report/01-..08-*.md`、复核命令改 `ls report/0[1-8]-*.md`
- L2 「工程本体（PS 固件源码）| `src/ps/` 3 个 `.c/.h`」 ⇒ 判定：**确实未修（计数过期）** ｜证据：`git ls-files src/ps` = 5（`README.md lscript_ocm.ld main.c sd_play.c sd_play.h`） ｜动作：改 5 并写清"3 个源码 + 链接脚本 + 目录说明"
- L4 「台架 / 仿真 | `sim/` **137** 个跟踪文件」 ⇒ 判定：**确实未修（计数过期）** ｜证据：`git ls-files sim \| wc -l` = 86；`build/deliver_spec_check.mjs` C2-1 亦打印 `sim 文件=86` ｜动作：改 86
- L16 「技能包验证记录…**NOT_MEASURED**（2026-10-05 实测 `test -e skills/evals` 为缺；这一格先前写"存在且可读"是旧包时代的残留、没跟着改口）」 ⇒ 判定：**确实未修（本行已改口，属正确）** ｜证据：`ls -d skills/evals` ⇒ 不存在 ｜动作：保留结论、删"这一格先前写…没跟着改口"那句自我更正过程腔
- L9 「装配位 `10-background`、`20-principle`、`30-partition-if`、`novelty-claims`、`prior-art-search` 五章未写 ⇒ 现不存在（P18a/P19 的批次被回合上限截停）」 ⇒ 判定：**确实未修** ｜证据：`ls report \| grep -E '^(10\|20\|30)'` = 0 行 ｜动作：保留缺口，删"P18a/P19 批次被回合上限截停"这句只有作者能懂的过程解释
- L23 「学习文档**不上传**…均已被 `.gitignore` 挡住 ⇒ 不随包 | **PASS**」 ⇒ 判定：**确实未修（且是"提交工程时不该有"的那类自述）** ｜证据：`git ls-files report/study docs/walkthrough` = 0、`.gitignore:107`/`:158` 两条命中 ｜动作：这格作为交付清单条目应删（"我们不上传 X"不是交付信息，随包检查器已按 `git archive HEAD` 处理）

### board/README.md

- L94 「全设计时序 | setup WNS **0.720 ns** / hold WHS **0.033 ns**…**0 / 50890**」＋ L25 「`eth_rxc`… **0.720 ns（9.0 %）**…0.049 ns」＋ L95 「功耗 | 动态 **2.207 W**、估算结温 **52.5 °C**」 ⇒ 判定：**失实（板上现产物的数不是这几个）** ｜证据：`build/timing_summary.rpt:151` = `0.739 … 0 … 51135 … 0.052`；`:182` eth_rxc = `0.739`；`build/power.rpt:36` = `2.213`、`:40` 区 = `52.6`；`src/host/metric_recheck.mjs` 的 D6 射程（`:274-283`）不含 `board/README.md` ⇒ 机器抓不到，属"射程外"不是"已核对" ｜动作：三格数字换成现件读数，或改成"只指本版件、不复述数字"（这两个选项在 `report/90-open-items.md:154` 已登记，现在需要拍一个）
- L101 「已知未修的几条限制写在 `report/known_issues.md`（**大角度旋转时画面角点会出屏**、SD 播放中拔卡会冻帧等）」 ⇒ 判定：**已修但文档写未修** ｜证据：`report/known_issues.md:89` §3 标题逐字「大角度旋转的角点出屏（`#93`）—— **已修，代价列在下面**」；眼睛侧也已签（`report/known-limitations.md:66` 登记原话"现在屏幕没问题了四角都在屏幕内"） ｜动作：括号里第一项换成仍成立的（SD 拔卡冻帧 #94、收侧无错误源 #205），别把已修的开天窗
- L88 「工具本机还会重写一份串口捕获，那份被 `.gitignore` 挡住、不随包」 ⇒ 判定：**确实未修（事实对）** 但属"提交工程时不该有的自述" ｜证据：`report/claims-vs-evidence.md:50` 同行自述该件 `不入库也不随包` ｜动作：改成"随包复核用总判定件 `build/r104_board_verify_console.txt`"，删本机重写那段

### board/HANDS_ON.md

- L105 「`osd on` / `osd off` | 回一行"语法已收、**硬件未接：缺 OSD 开关位**"（`main.c:1204`）」 ⇒ 判定：**已修但文档写未修**（且指路行号也错） ｜证据：`src/ps/main.c:1013` 起是真处理分支（`:1022` 打印 `osd=%s（gpio_o[20] 反相）`、`:1032` 打印 `[OSD] osd=on/off`）；`:57` `#define OSD_OFF_BIT 20u`；`:11` 位表注 `[20] osd_off…r83 起在用`；`:1261` 逐字「（这里原来放着 `osd` 的"待接"提示 —— 撤掉：上面 `ci_pre(tk[0], "OSD")` 已经真的接进硬件了」；被点名的 `main.c:1204` 现在是 `SPLIT` 分支的 printf ｜动作：这一行改成"`osd on/off` 走 gpio_o[20]（反相，复位=有 OSD），关掉用于取证/拍摄"，行号改 `main.c:1013-1032`
- L73 「旋转态 + `bilin off/on` | **也看不出差别**：旋转那一支把小数权重钉 0（`main.c:995`–`997` 指的 `zoom_mapper` 通路，**未修**）」＋ L137 「旋转时 `bilin on/off` 看不出差别 | 旋转那一支小数权重恒 0（**未修**，见 `main.c:996`）」 ⇒ 判定：**已修但文档写未修** ｜证据：`src/rtl/process/zoom/zoom_mapper.v:70` 逐字「#104：旋转支以前在这里把小数直接丢掉（`frac_x/frac_y` 钉 0），于是 `bilin on` 在旋转态是空头支票」，紧接 `:77-79` 给出接回小数与纵向翻号的成套改法（`rot_fx`/`rot_fy`）；固件自述 `src/ps/main.c:998-999`「旋转态也算 —— r94/#104 起旋转支的小数位真的交给读口了」 ｜动作：两行都改成"旋转态有差别（#104 起）"；顺带指出 `main.c:996-997` 注释自己前后矛盾，属 RTL/固件注释侧的另一处（不在本次文档射程）
- L41 「已知未修：低于 1.00× 与大角度旋转会让画面出屏/出对角彩条（**#93，先记不修**）」 ⇒ 判定：**已修但文档写未修** ｜证据：同 `report/known_issues.md:89` ｜动作：整行删或改成"这两族已由 #93/#104 收口，测的时候仍要记录现象"

### board/acceptance.md / board/hardware_setup.md / board/raw-vs-golden.md / board/signoff.md

- `board/acceptance.md:118` 「已知未修项（**大角度旋转角点出屏**、SD 播放中拔卡冻帧等）在 `report/known_issues.md`」 ⇒ 判定：**已修但文档写未修**（同一处错误） ｜证据：`report/known_issues.md:89` ｜动作：删第一项
- `board/acceptance.md:52` 「本机没有 hw_server 在听 3121，起了 `Vitis/bin/hw_server.bat` 之后拿到 `tcfchan#0` —— 复现时这一条要先做」＋ `board/hardware_setup.md:161` 「本机 `hw_server` 此刻在听」＋ `board/README.md:45,60,61` ⇒ 判定：**确实未修（事实）**，但 5 处都用"本机"起句 ｜证据：这是环境前置条件，不是缺陷 ｜动作：统一改写成命令式前置条件（"起 `hw_server` 并用 `netstat` 确认 3121 在听"），删"本机/这台机器"
- `board/hardware_setup.md:45-50,91-95` 共 11 处 `【待你补：…】`（适配器型号/电流、线材规格、面板供电、卡品牌容量）＋ `:77` 「合计 9 项缺 + … = **11 处 `【待你补】`**」 ⇒ 判定：**确实未修**（这些量仓库里从来没有过） ｜证据：`:45` 自述「仓库里没有任何一处写过适配器额定电流」；`report/90-open-items.md:233` 编号 214 同批登记 ｜动作：**不能删信息**（缺件就是缺件），但 `【待你补】` 这个"给作者自己看的备忘"记号必须换成交付口径的写法（"未记录／需现场标注"），并删掉 `:77` 那行自计数
- `board/hardware_setup.md:49,93` 「README.md 的「项目简介（这个系统做什么）」一节（原引内容在本版 README 已无对应段落）」＋ `:144` 「README.md 的「上板与验证」一节（原引内容在本版 README 已无对应段落）」 ⇒ 判定：**确实未修（指路已断）**，且"原引内容在本版 README 已无对应段落"是纯过程回声 ｜证据：`report/90-open-items.md:160` 同一句话也出现在 C1 那行；README.md 现在的小节名是「限制与未通过项」等 ｜动作：把两处指路改成现存在的小节名，删括号里那句自述
- `board/raw-vs-golden.md:37` B4 「`build/tb_v98_report.txt` 现数 161 + 1 = 162 | `data/metrics.csv:15` 声称的 141…**无法比：该指纹的件盘上 0 件** | **NOT_MEASURED**（V11）」 ⇒ 判定：**确实未修**（与 `report/90-open-items.md:139` 编号 18 同一件事，两处口径一致） ｜证据：`grep -c '^PASS' build/tb_v98_report.txt`=161、头 `top_md5=56c269602e18` ｜动作：保留；把这条与 90 的编号 18、`report/repro-check.md:137` R2 三处收成一处指路
- `board/raw-vs-golden.md:25` A6 「端到端时延…**这一对起点/终点没有任何可复核件**…**NOT_MEASURED**」＋ `:28` A8 「**无仪器读出**（`board/acceptance.md:98` 自己写"串口读不到角度"）」 ⇒ 判定：**确实未修** ｜证据：`report/claims-vs-evidence.md:44` 判 `未见凭据`、`data/metrics.csv:20` 自述"不填没有复核过的数" ｜动作：保留

### report/README.md / report/08-limits.md / report/05-timing.md / report/06-validation.md / report/01-overview.md / report/04-resources.md

- `report/README.md:31`（表内）「`70-reproduce.md` 第 6 节点出的与其它文档冲突的五处**尚未改**」 ⇒ 判定：**部分已修，文档整体写未修** ｜证据：五处里 2 处已落地——`build/README.md:19,94-100` 已改成 `build/report/`（编号 23）、`report/known_issues.md:38` 已补"仓库名/包内名"两跳（编号 22）；其余 3 处仍在（`report/build.md:79-81` 的三支 `.bat`、`report/build.md:14,61` 的一键路径、`board/README.md:25,94,95` 的旧数） ｜动作：改成"5 处中 3 处未收"，或按逐条给状态；不要笼统写"尚未改"
- `report/08-limits.md:157-158` 「§4c 点名的那项要求…**还没落地**，那一节自己标着"这个检查**还没写**……现在不点名，因为指路检查会抓'指着盘上不存在的东西'"」 ⇒ 判定：**确实未修** ｜证据：`grep -rln "ASYNC_REG" build/checks/ src/host/` ⇒ 无命中（该项检查不存在）；`build/gates.sh:103,126` 的 ASYNC_REG 只服务 CDC-11 那一类，不是"组间跨域寄存器路径条数 ≥4"那条 ｜动作：保留缺口；把"因为指路检查会抓…"这半句删（那是写作顾虑，不是工程限制）
- `report/08-limits.md:120` 「本机两本官方手册两遍扫描命中 0 页，这句只到"没筛出来"，不能写成"手册里没有"」 ⇒ 判定：**确实未修**（结论口径对，措辞是辩解腔） ｜证据：同 `report/90-open-items.md:131` 编号 15；`build/evidence/r117/bufio_delay_scan.txt`、`bufio_delay_scan2.txt` 在盘 ｜动作：改成"UG471/UG472 未随包，按页检索未命中 ⇒ 该 0.5/0.2 ns 仍是假设"
- `report/08-limits.md:191` 「关掉它需要什么：第二家可 licens 的仿真器（**本机没有**）」 ⇒ 判定：**确实未修** ｜证据：`ls /d/Software/ModelSim/modelsim_ae/win32aloem/vsim.exe` ⇒ 不存在（`PATH` 上只剩空目录） ｜动作：删括号，写"未随包、许可证不可用"
- `report/06-validation.md:58` 「本机只有 **xsim**，早期能作第二意见的 ModelSim 已不在 ⇒ 任何"两家仿真都过"的说法今天不可复现」 ⇒ 判定：**确实未修** ｜证据：同上 ｜动作：删"本机/今天"，保留"不可复现"这一结论（它是 `report/70-reproduce.md:177` 不可复现清单第 3 条的同一件事）
- `report/05-timing.md:172` 「BUFIO 的快角 DCD 还没实测（`report/log/issues.md` #323：本机两本官方手册按…」 ⇒ 判定：**确实未修** ｜证据：`report/known-limitations.md:36` 表行「量过一轮，未采纳」；HEAD 提交把该刀回退 ｜动作：保留，删"本机"
- `report/01-overview.md:40`／`report/04-resources.md:37,80` 「【未实测】：当前位流上的端到端时延数字」／「【未实测】：当前版本**逐实例**的 BRAM/DSP 归属」 ⇒ 判定：**确实未修** ｜证据：`data/metrics.csv:20` `端到端时延,未报,…待复测`；`report/50-results.md:162` 同格写 `NOT_MEASURED` ｜动作：保留，但把 `【未实测】` 这个内部标记词换成人话（"没有可指回的读数件"）

### report/build.md / report/declarations.md / report/host_guide.md / report/figures/legend.md / report/commands.md / report/interface-table.md / report/demo_script.md / report/ps_vs_pl.md / report/ai_collaboration.md

- `report/build.md:79-81` 「run_sender.bat / run_video.bat <你的视频.mp4> / run_serial.bat COM5」＋ `:100` 「7. `run_sender.bat` 推流」 ⇒ 判定：**失实（三支脚本在仓库里不存在）** ｜证据：`ls` 三条全 No such file；`find` 全仓 0 命中；同段 `:14,61` 指的 `build/tcl/program_system.tcl` 与三步链并存（`report/70-reproduce.md:146` 冲突 1/4） ｜动作：改成 `send_demo.bat`（在盘）+ `python src/host/video_sender.py`，并把一键路径与三步链的关系写一句
- `report/declarations.md:22` 「本机安装目录与所有报告头一致…（作者机器装在 `<盘>:\Software\Vivado\2025.2.1`，这一句是叙述不是指令）」＋ `:24` 「本机 `ver` 输出（**注意**：这是 Windows 的版本号格式，不代表 Linux 环境）」 ⇒ 判定：**确实未修（权威件本身含"本机"叙述）** ｜证据：C1 已判 PASS（取值唯一），问题只在措辞 ｜动作：删这两句括号叙述，只留 `os=Windows 10.0.26300.9550` 一行取值；"这一句是叙述不是指令"是同族自辩
- `report/host_guide.md:10` 「用自带的 `SerialPort`，**本机没有 pyserial**」 ⇒ 判定：**确实未修（事实）**，措辞是辩解腔 ｜动作：改成"串口脚本只依赖 PowerShell 自带的 SerialPort，不需要 pyserial"
- `report/figures/legend.md:102-103` 「想要的产物 | **本机**能不能出 … | Mermaid/Graphviz 渲染成 PNG/SVG | **不能**（本轮 NOT_MEASURED） | 本机无 `mmdc`、无 `dot`（`which` 实测无输出）」 ⇒ 判定：**确实未修** ｜证据：`which mmdc` ⇒ 无；无 `node_modules`；`dot` 同理 ｜动作：表头改"随包工具能不能出"，格内改"需 `mmdc`/`graphviz`，本包不含"，删"本轮 NOT_MEASURED"
- `report/commands.md:311` 「`gpio_o[4:0]` | **保留，PS 恒写 0** | …位留着是因为…重排位序等于把老工具全部判为不通过」 ⇒ 判定：**确实未修（有意保留，声明充分）** ｜动作：保留，但这类"为什么不做"的长理由属 B 节辩解分布，压缩到一句指路
- `report/command_precedence.md:407` 「`zoom fit 0` 的"回到手动档/呼吸自动档" | `cur_zoom=0` 时实际回到 1.00x，**那句是错的**」 ⇒ 判定：**确实未修（对外文档仍写着那句错的）** ｜证据：该行自述三选一分支，错的来源在演示/命令说明另一侧 ｜动作：找出仍写"回到手动档"的那份文档改口（本次未见那一份的确指落点 ⇒ 若指不到就记"无法判定，缺被点名文档的行号"）
- `report/interface-table.md:322` 「该日志是 2026-09-27 的 r75 构建，不是本轮实测 ⇒ 只当旁证，本轮不做可达性结论（`NOT_MEASURED`）」 ⇒ 判定：**确实未修（旁证定位合理）** ｜动作：保留"只当旁证"，删"本轮"两处
- `report/demo_script.md:58` 「这一幕当场会看见的一条**公开保留的已知缺陷**…**它在发布前检查的第 15 项里今天判不通过**，留着是因为能让它被抓住的那条变异对照还没建」 ⇒ 判定：**确实未修** ｜证据：`build/r118_gates_final.txt` 末行 `GATES: 有红项（判定 24 项）`、唯一红 = `C5c`（`report/claims-vs-evidence.md:77`）；变异对照未建（`report/known_issues.md:65`、`report/08-limits.md:25`） ｜动作：这条是讲稿里必须留的（对外要念），但"今天判不通过"改"发布前检查第 15 项对 C5c 判不通过（已声明）"
- `report/ai_collaboration.md:273` 「`report/log/overnight_log.md:1648` 早就更正过（本机有 3.12，只是交付件要求零依赖）——**这一版删掉了那句**」 ⇒ 判定：**已修未改**（更正本身已完成，剩下的只是这句过程自述） ｜证据：`report/log/overnight_log.md:1648` 属台账；本行自述已删 ｜动作：删这半句
- `report/ai_collaboration.md:381` 「一条可复现的仿真路径（本机是 xsim，ModelSim 已卸载 ⇒ 当年那个…」 ⇒ 判定：**确实未修** ｜动作：同 06-validation 的改写口径


### README.md / README_EN.md

- README.md L87 「`report/repro-check.md` 的逐条实跑里，**未通过与未测两类**都还没逐条归因」 ⇒ 判定：**已修未改（一半）** ｜证据：本次实跑 C9 `PASS=36 FAIL=0 未测=11`——"未通过"这一类已经是 0 ｜动作：改成"未测 11 条没有逐条归因"；`README_EN.md:73` 同一句英文同步
- README.md L84-86 「发布前检查共 24 项：23 项通过、1 项未通过…凭据 `build/r118_gates.txt`，这里**逐字引用是为了让 `doc_currency_check.mjs` 的 D1c 能对回凭据件**」 ⇒ 判定：**确实未修**（数对得上：`build/r118_gates_final.txt` 末行 `GATES: 有红项（判定 24 项）`） ｜动作：结论保留；括号里那句"为了让 D1c 能对回凭据件"是给检查器写的自辩，交付文档里应删（`src/host/doc_currency_check.mjs` 自报 `抓到 2 句"门禁 N 项 X 绿 / Y 红"` 说明它确实吃这句——删时要一并调 D1c 的最低句数，属改尺子）
- README.md L74 节标题「限制与未通过项」＋ 整节 L74-88 ⇒ 判定：**结构问题不是失实**——用户判词"README 和后面写的那些限制什么的，提交工程时肯定不能有" ｜动作：见 C 节第 6 条的处理建议

### report/60-failure-analysis.md（A 组 15 条 / B 组 16 条逐条核）

- L146 A13「本次实读取到第 62–63 行写 `0.720 / 0.033 / 0 / 50890`…`动态 2.207 W、估算结温 52.5 °C`」 ⇒ 判定：**确实未修**（对 `board/README.md` 的指控成立） ｜证据：现值见上（`build/timing_summary.rpt:151`、`build/power.rpt:36,40`）；但 A13 自己点的**行号错了**——那些数现在在 `board/README.md:25,94,95`，不在 62–63 ｜动作：改行号（`line_cite_check` 本次报 `硬错 0`，说明它没把这种"行号偏一格"算硬错 ⇒ 别指望尺子兜底）
- L105 A4 标题「"本机没有 bare-metal 编译器"这句在本仓库写了至少五处，**本次实测它错了**」＋ L107-128 ⇒ 判定：**结论已改对（校准样本，不报为失实）** ｜动作：整条属 B 节"过程回声"——登记"我们曾经错过"不是失败分析，是更正日志；`report/known-limitations.md` §2 已承载同一事实 ⇒ 建议整节压成两句限制陈述
- L230/L246 A10 「SD 固件**四条未修**（#196–#199）…四条都登记为未修」 ⇒ 判定：**失实（与 known_issues 口径不符）** ｜证据：`report/known_issues.md:486,493` 只有 #196/#197 写 `未修`，`:498` #198 写 `只记录`、`:504` #199 写 `只记录`，`:508` #200 才是 `未修` ⇒ 成立的是 3 条未修（#196/#197/#200）+ 2 条只记录 ｜动作：改成"三条未修（#196/#197/#200）＋ 两条只记录（#198/#199）"，与 `report/known_issues.md:482` 的标题逐字对齐
- L272 A12 「三个统计脉冲没接出去 ⇒ 能演示"过滤生效"，不能读出"滤掉了多少"」 ⇒ 判定：**无法判定** ｜证据：缺的那件凭据是"那三个统计脉冲在 RTL 里的名字与顶层落点"——`grep -rn "acl\|filter\|flt" src/rtl/system_top.v src/rtl/pl_video_top.v src/rtl/eth/eth_udp_video_top.v`（带 pkt/stat/cnt/drop 过滤）⇒ 0 命中，两处文档都没给信号名 ｜动作：补信号名 + 顶层行号，或把这条降到 `report/known_issues.md:848` 的同一格不重复
- L278 A12 后半「`bad`（坏包计数）会动这件事**只有台架证据**」 ⇒ 判定：**部分已修未改** ｜证据：`src/rtl/eth/link_monitor.v:71,130` 有 `pkt_err` 计数、`:91` 截 16 位入 lane、`src/host/health_read.mjs:460` `pkt_err: … f16(l.lane1, true)` ⇒ "读不出来"对坏包这一支**不成立**（能读，只是板上没见过它跳） ｜动作：区分"读不出"与"没见它跳过"，前者删
- L308/L489 「（这一行引的是当时旧件的原样输出，`run_all.sh` 与 `gates.mjs` 都**现不存在**；今天的等价件是 `node skills/_meta/check-selftest.mjs`，本轮实跑末行 `SKILL-SELFTEST 判 16 项 不符=0 PASS`）」 ⇒ 判定：**已修未改**（旧红项已被现件推翻，文档自己也说了） ｜证据：本次实跑 C12 `绿=9 红=0 未测=0` ｜动作：把"旧件当时的原文"整段挪进 `report/log/`，正文只留现件读数
- L99 「这一步未做（**本次判定：NOT_MEASURED，构建与上板都不在本轮动作范围内**）」＋ L250 「今天全部**没做**，因为本轮的刀排在时序与文档侧」＋ L351/L538 「今天两条都没做」 ⇒ 判定：**过程回声**（事实层面确实未做） ｜动作：见 B 节

### report/70-reproduce.md

- L122 步骤 5.1 「`bash build/gates.sh` … **NOT_MEASURED**。没跑的原因很具体：…**跑它会覆写本次授权禁区 `build/` 里的件**。第三方在**自己的干净克隆**里跑没有这个约束，照做即可」 ⇒ 判定：**失实（"不能跑"是这一轮的工作约束，不是工程的限制）** ｜证据：`build/README.md:13` 与 `build/gates.sh` 是交付入口；本次实跑证明只读三把尺子（`doc_currency`/`line_cite`/`metric_recheck`）都不写盘，而 `build/ports_check.txt` 是否真被第 14 项覆写可由 `git ls-files --error-unmatch build/ports_check.txt` 一步核（该行自述已核过、命中） ｜动作：**整段删**"本次授权禁区"那半句 + "第三方在自己克隆里没有这个约束"那半句，只留"这一步需要一次构建窗口，本次未跑"；这正是用户点名的"写的这么…因为本机怎么怎么样…这些废话"
- L130 步骤 5.9 「本轮 rc=0，末行 `判 53 项：条目=49 索引=50 红=0 未测=0 PASS`」 ⇒ 判定：**确实未修（数字过期，状态对）** ｜证据：本次实跑 C6 `INDEX 条目=49 类别=10 索引行=49 需改写=no PASS` ⇒ 索引行已不是 50 ｜动作：数字现算，或删自抄读数只留命令
- L149 冲突 4 「两支脚本本次实测都存在…（改 `report/build.md`；**不在这一轮的改动范围**）」 ⇒ 判定：**确实未修** ｜证据：`report/build.md:14,61` 仍是 `build/tcl/program_system.tcl` 一键路径，三步链在 `board/README.md:52-54` ｜动作：把括号里的轮次理由换成一句"两处并存，以三步链为权威"
- L34 「没跑的原因逐条写明（**本轮禁跑** / 缺设备 / 缺批准 / 未在本平台验证）」 ⇒ 判定：**过程回声** ｜动作："本轮禁跑"改"需要构建窗口"

### report/claims-vs-evidence.md（补）／report/interface-table.md／report/command_precedence.md（补）

- `report/interface-table.md:74,281` 「`u_pl.stat_*` 一组…**悬空** ×4…端口本身保留是因为一批台架直接读它们」 ⇒ 判定：**确实未修**（有意保留） ｜证据：`src/rtl/system_top.v:200-201` 的悬空注释与 `:130-133` 的理由仍在（本表逐字引用，未与 RTL 冲突） ｜动作：保留
- `report/interface-table.md:289` 「`hb_slow` / `hb_gone`…硬接只会常亮一位没意义的慢标志 | 否（有据）」 ⇒ 判定：**确实未修（有据的死口）** ｜动作：保留
- `report/command_precedence.md:339` 「这几条不是"被别的命令盖住"，而是**本来就没有出口**」 ⇒ 判定：**确实未修** ｜动作：保留，但把"放在一起是因为它们在串口上的表现相同"这类编排自述删（B 节）


### report/notice.md

- L21/L25/L26 「原件在**仓库外**本机 `（本机厂商资料目录）/Reference Material/…`（`ug471_7Series_SelectIO.pdf` 实测存在）」 ⇒ 判定：**确实未修**（许可状态仍是 `未核`）｜证据：`report/notice.md:26` 自述"本表风险最高的一行"，`build/evidence/r115_rtl8211f_delay_source.txt` 等派生件仍在跟踪集 ｜动作：结论保留，**删"本机/仓库外/实测存在"这套机器辩解措辞**，改写成"该资料不在随包范围，引用只到页码＋读数"
- L27 「② 逐文件的"哪些逐字／哪些改造"**没有登记表** ⇒ 只能挂在"待决"」 ⇒ 判定：**确实未修** ｜证据：`grep -rn "Copyright" src` 结果需复核（本表逐字如此声明）；`report/log/version_lineage.md` 无逐模块表 ｜动作：保留（这是交付前必须补的洞），但把"`report/README.md:18` 指错"一句改准（现 README 该格已指向 `claims-vs-evidence.md`）
- L30 「ModelSim／Questa…已不在本机 ⇒"两家仿真都过"不可复现」 ⇒ 判定：**确实未修** ｜证据：`ls /d/Software/ModelSim/modelsim_ae/win32aloem/vsim.exe` ⇒ 不存在（`PATH` 上有那个空目录） ｜动作：保留事实，删"本机"，写"本包只含 xsim 一条可复现路径"


### data/README.md / build/README.md

- `data/README.md:47` 「`.gitignore` 第 **58、59、68** 行把这类名字排除在版本库外」＋ `:44-48`「20 vs 15，差额 5 支」 ⇒ 判定：**确实未修（计数对，行号多引一行）** ｜证据：`git ls-files --others --ignored --exclude-standard data/measured` 恰为 `ddr_dump.out` + `health_{cur,p0,p1,clr}.out` 五支；命中的是 `.gitignore:58`（`data/measured/ddr_dump.out`）与 `:68`（`data/measured/health_*.out`）；`:59` 是 `data/measured/ddr_dump.tcl`，不在这五支里 ｜动作：行号改 58、68
- `data/README.md:22` 「容差口径还没定下来的地方一律标 `【队伍未确认】`」＋ `:58`「这条缺口登记在 `report/90-open-items.md`；补它需要跑一次把八个向量一起跑完的全量仿真」 ⇒ 判定：**确实未修** ｜证据：本次 C9 `未测=11`（全量仿真在禁跑那一批里）；`report/90-open-items.md` 有对应行 ｜动作：保留；`report/90-open-items.md` 若按 C 节处置则同步改这处指路
- `build/README.md:4` 「`.txt` 是一次次留档，**不随包**」 ⇒ 判定：**确实未修（事实）** ｜动作：留这一句即可；同族的另外四处（`report/claims-vs-evidence.md:50`、`board/README.md:88`、`board/acceptance.md:39,53`）删掉，"不入库/不随包"这类自述是用户点名的"提交时不该有"

### 计数

A 节逐条判定 **62 条**：**已修未改 / 已修但文档写未修 = 21**｜**确实未修 = 30**｜**失实（数字、行号或口径与现件不符）= 9**｜**无法判定 = 2**（缺的凭据分别是"那三个统计脉冲在 RTL 里的信号名与顶层落点"、"C9 那次 91/30/32 读的是哪一版 `report/repro-check.md`"）。
最密集的三份：`report/90-open-items.md`（18 条里 11 条判"已修未改"）、`report/final-gate.md`（7 条里 5 条已过期）、`board/`（`README.md:101` + `HANDS_ON.md:41,73,105,137` 五条把**已修**的 #93/#104/OSD 仍写成未修或未接）。

## B. 过程腔与辩解

### B.1 全量分布（本次实跑，词表按任务给的）

出现次数（`grep -o` 逐词累加，范围 = README.md README_EN.md report/*.md board/*.md data/README.md build/README.md）：
`本轮=149 这一轮=128 改前=92 改后=66 本次=200 上一轮=10 今晚=6 今天=81 小结 N:=3 下一步:=9` ⇒ 过程腔词合计 **744 处**。
辩解句式：`因为本机=1 这台机器=7 本机没有=10 暂不具备=0 不是最新=0`；另一族"轮次授权腔"
`本轮禁跑 / 不在本轮射程 / 本轮动作范围 / 禁区 / 回合上限 / 本次授权 / 这一轮的改动范围`（`grep -cE`）
⇒ **90=14 行、70=8、60=3、submission-checklist=2、run-queue=2、repro-check=2、measurements=2、board/signoff=2，其余各 1**。
含过程腔词的行数（`grep -cE`，同一行多词算一行）与出现次数不同，下面按**行数**给逐文件计量，便于直接当改动量用。

`本机` 这个词在范围内的总命中：`grep -o 本机 | wc -l` = 80（散布 26 个文件），是"因为本机所以不能"这类辩解的主载体。

### B.2 逐文件：命中行数 + 两类比例估计

"独有"= 改了会丢证据，必须**换写法保留信息**；"回声"= `report/log/issues.md`（13 724 行）或 `report/log/overnight_log.md`（6 217 行）里已有同一件事，可**直接删**。
抽样办法：拿该文件里过程腔句点到的编号/件名/判据名回查台账命中数（例：`tb_link_monitor` 在 issues.md=19 处、`F2e`=9 处、`Max Ambient`=2 处 ⇒ 属回声；`C8 汇总表行=267` 这类只有本文有的分母 ⇒ 属独有）。

| 文件 | 含过程腔的行数 | 独有 : 回声（估计） | 判据 |
|---|---|---|---|
| `report/90-open-items.md` | 111 | **15 : 85** | 第 2A–2F 节的"需要谁点头"是独有信息；第 1/3/4/5 节整片是快照分母与四轮 C8 复跑流水（`12:29`/`12:46`/`12:50`/`12:56`/`13:00`），台账 #337/#339 有同一件事 |
| `report/60-failure-analysis.md` | 102 | **45 : 55** | A/B 每条的"现象+可判别假设+成本"是独有；"本次实测/本次实读/今天没做/本轮的刀排在…"是回声 |
| `report/repro-check.md` | 77 | **20 : 80** | §1 的分母表与 R8/R10 那两条"改检查器形状时踩的坑"独有；§8.3 六次 `build/gates.sh` 逐跑、"第一轮/第二轮/第三轮"整段是回声 |
| `report/optimization_log.md` | 69 | **70 : 30** | 逐轮"基线→措施→实测"是赛题要的优化过程，删了就没证据；"今天采用的那条/那条今天没做/就是今天的默认流程"可改写成"当前采纳/未采纳" |
| `report/70-reproduce.md` | 54 | **30 : 70** | 逐命令的"执行目录/shell/前置/应看到什么"独有；第 9 节的实跑摘要与"本轮禁跑"是回声 |
| `report/known_issues.md` | 48 | **55 : 45** | "现象（改前）/改前的红在 …"是缺陷本体（改前态=症状，必须留）；§立案与落地时间线、"本轮没查的"是回声 |
| `report/40-optimization.md` | 8 | **80 : 20** | "改前读数/改后读数"是那张对照表的列名，属必要用语，不算腔 |
| `report/build-notes.md` | 12 | **25 : 75** | L3「口径：**本轮 = r118**」这类"以轮次为时间锚"整页可用位流 md5 替代 |
| `board/raw-vs-golden.md` | 8 | **35 : 65** | L4「**本轮没有**驱动串口、没有上板、没有 xsdb、没有跑构建或全量台架（P23 边界）」整句可删；L92「（不是本轮新增，本轮只是把它落到表 B5）」可删而 `base红=1 → cut红=0` 必须留 |
| `report/notice.md` | 7 | **20 : 80** | L11「**未核** = **本轮**没有打开过任何能证明其分发条款的文件」⇒ 把"本轮"换成"未打开过"即信息不丢；L9「本轮没有运行导出器（另有进程在跑它）」纯过程 |
| `report/claims-vs-evidence.md` | 9 | **60 : 40** | 断言↔凭据逐行是独有；"本表写下这一行时…"是回声 |
| 其余（`interface-table/commands/ps_vs_pl/timing_global/perf_report/comparison-notes/measurements/src-map/…`） | 各 1–8 | **约 50 : 50** | 多为"改前/改后"当列名或"本轮实跑"当读数时刻，逐句判 |

### B.3 每文件 3 条例句（含建议改写方向）

- `report/90-open-items.md` L37「本次运行期间 … 由同伴轮次**并发写入**，同一分钟内实测到 879 → 898 的漂移」／L443-505 整节「改前（12:29 实跑）…第 1 趟…第 2 趟…第四趟（完成于 13:00 前后）」／L507「## 6. **本轮没有做的事**（诚实交代 + 需要什么）」
  ⇒ 三条都可删：前两条的结论已被现尺子取代（本次实跑 C8 `正文标记总数=905`，879/898/1390/1518 那一串全部作废），第三条的内容就是第 2 节各行的状态列。
- `report/60-failure-analysis.md` L250「今天全部**没做**，因为本轮的刀排在时序与文档侧」／L105 整节「"本机没有 bare-metal 编译器"这句在本仓库写了至少五处，**本次实测它错了**」／L308「（这一行引的是当时旧件的原样输出，`run_all.sh` 与 `gates.mjs` 都**现不存在**…）」
  ⇒ 第一条删（成本行保留）；第二条压成"ELF 可重建，缺的是重刷+复验"两句（同一事实 known-limitations §2 已是正主）；第三条把旧件读数挪进台账、正文只留现件。
- `report/repro-check.md` L17「这一轮实跑了 **6 次** `bash build/gates.sh`（见 §8.3）」／L46「这一轮也不悄悄改它，只如实登记成 §3 的不一致项 **R16**」／L35「第三轮相加（2026-10-05 晨，板子连着）」
  ⇒ 三条都属"谁在什么时候跑了什么"，`report/log/` 有同一件事；**独有信息**是 §3 那张 R1–R16 不一致项表（别处没有），改写时把"这一轮/第 N 轮"换成"该次跑"或件名。
- `report/optimization_log.md` L185「**今天采用的那条**（r63c 在验）」／L222「实测要上板量电源轨，那条**今天没做**（记在这儿，别到提交材料里被写成实测）」／L257「**不设这个变量就是今天的默认流程**」
  ⇒ 三条都是同一句话的时态问题：换成"当前采纳/未做/默认流程"即可，信息零损失。
- `report/70-reproduce.md` L34「没跑的原因逐条写明（**本轮禁跑** / 缺设备 / 缺批准 / 未在本平台验证）」／L122「跑它会覆写**本次授权禁区** `build/` 里的件。第三方在**自己的干净克隆**里跑没有这个约束」／L51「（这里不写本机绝对路径，规矩见 `report/build.md` §1）」
  ⇒ 前两条删（缺的是"需要一次构建窗口"这一句客观前置）；第三条是同族自辩，直接按 `<Vivado>` 写就行。
- `report/known_issues.md` L65「必须先有一条"**改前必须红、改后恰好绿**这一条"的变异对照，而那条对照还没建」／L332「立案时与落地的时间线：机理先由读码核实…**当时台架还没跑**」／L515「两条误报也写在这里（它们曾被列为缺陷，读码后不成立）」
  ⇒ L65 独有（它说明为什么留红），但"改前/改后"在这里指变异对照的判据形状，属必要用语；L332/L515 是更正日志，可删到一句"读码后不成立"。
- `board/raw-vs-golden.md` L4「本轮没有驱动串口、没有上板、没有 xsdb、没有跑构建或全量台架（P23 边界）」／L88「空捕获与"两种状态其实是同一次失败"（**本轮新登记的**）」／L92「（不是本轮新增，**本轮只是**把它落到表 B5）」
  ⇒ 三条删。独有信息是表 A/B/C 每行的 `NOT_MEASURED` 判定与点名件。
- `report/notice.md` L9「本轮**没有运行导出器**（另有进程在跑它），所以"跟踪集内 ≠ 一定落进最终包"」／L11「**未核** = 本轮没有打开过任何能证明其分发条款的文件」／L15 表头逐行带「本次实测存在」
  ⇒ 三条改写法：L9 整句删（导出器判据本身管这事）；L11 去"本轮"；"实测存在/实测通过"这类是"我们真的看过"的自证，交付文档里应改成路径 + 页码。
- `report/claims-vs-evidence.md` L44「本表写下这一行时，被引断言点名的自检脚本…在树里存在且被 git 跟踪（技能包 2026-10-04 按交付要求重建后这一条旧条目名已不存在…）」／L87「现在同一串 `绿=7 红=4 未测=1` 在两份被跟踪的件里读得到…但断言里"G11 selftest 未落地"那两半在任何件里都没有」／L70 同行「**本表写下这一行时**」
  ⇒ "本表写下这一行时"共 4 处 ⇒ 换成"截至 <件名>"；独有信息是每行的 断言↔件↔三态 三列。
- `report/build-notes.md` L3「口径：**本轮 = r118**（`build/provenance.md:1`…）」／L7「机器版全表 = …（**本轮** 269 行…）」／L92「**本轮**另跑 `python build/p15b_parse_reports.py --self`」
  ⇒ 全篇的"本轮"可用一句"本页对应位流 `cd04907e1369`"替代；L92 那类"本轮另跑了 X"是回声。
- `report/submission-checklist.md` L19「**本轮自己新增的交付件又贡献了 61 条含大写路径**」／L15「（**本轮实跑** `node skills/_meta/run-all-checks.mjs skills`…）」／L23「（`git ls-files …` **本轮复跑** = 0 个跟踪文件）」
  ⇒ 全部可去轮次词，状态格本身才是信息。
- `board/signoff.md`／`board/signoff-questions.md`／`report/run-queue.md`／`report/unattended.md`／`report/measurements.md`：各 1–2 行"本轮禁跑/不在本轮射程/这一轮" ⇒ 属 C 节整份处置的对象，不在这里逐句改。


## C. 该退场的交付件

判据三态：**删** = 内容只有"谁在什么时候做了什么"，赛题 §3.3.5.3 的格子里没有它的位置；
**并入台账** = 事实要留，但主场是 `report/log/`；**保留** = 赛题点名要 or 被尺子/打包器当输入。
硬约束（先看清再动手）：
- `build/checks/check_repo_consistency.mjs:323` 把 `report/90-open-items.md` 当 **C8 的输入**、`:353` 把 `report/repro-check.md` 当 **C9 的输入** ⇒ 这两份直接删会让 C8/C9 变 `NOT_MEASURED`，必须连尺子一起改（改尺子需批准）。
- `build/make_submission.sh:762-766` 的"复现入口文档"白名单含 `report/repro-check.md`、`report/acceptance-recipes.md`、`report/declarations.md`、`report/submission-checklist.md` ⇒ 这四份在打包判据里有身份，删要同步删名单（`:744-745`）。
- `report/README.md:104-118` 那段 `for f in report/{…}.md` 存在性自检把本节几乎所有候选都点进名单 ⇒ 任何删除都要同步改这一处。

| 文件 | 判定 | 理由 | 删它要一起改的指路（`grep -rn` 结果，已滤 `report/log/`、`docs/`、`report/study/`） |
|---|---|---|---|
| `report/90-open-items.md`（548 行） | **并入台账**（正文压成一张 ≤40 行的"需人给料"表，其余进 `report/log/`） | 第 3/4 节是 202 行标记逐字回引别人文件、第 1/5 节是四轮 C8 复跑流水（A 节已证其数字全部作废）；只有 2A/2B/2D 的"需要谁点头"是交付要的开放项 | `build/checks/check_repo_consistency.mjs:323,328`；`report/README.md:31,107`；`report/known-limitations.md:3`；`report/submission-checklist.md:9,22,37`；`report/60-failure-analysis.md:527,563,593`；`report/70-reproduce.md:142`；`report/01-overview.md:76`；`data/README.md:58`；`build/runs/decisions.md:97,100,111`；`report/claims-vs-evidence.md` 多处 |
| `report/repro-check.md` | **并入台账**（§3 的 R1–R16 不一致项表值得留正文，§1/§8 的逐轮跑次进 `report/log/`） | 它本质是"我照命令敲了一遍"的演练记录；C9 要的是三态计数，不是过程叙述 | `build/checks/check_repo_consistency.mjs:353,354`；`build/make_submission.sh:744,765`；`build/r120_rotate_skill_refs.mjs:9,16,23`；`README.md:86`；`README_EN.md:73`；`report/README.md:31,110`；`report/known-limitations.md:44`；`report/final-gate.md:26`；`report/90-open-items.md:161,249,250` |
| `report/questions-for-team.md`（25 行）+ `report/questions-for-team-p12.md`（28 行） | **保留但改名/改口径** | 开放问题本身必须存在（agent 无权代答），但"请队伍回答我"是协作过程件；交付时应转成"需现场标注的参数 / 待裁决项"清单，去掉 P 编号与 C8 对账句 | `board/firmware/system.bit.md:82`；`board/firmware/system.xsa.md:25,73`；`board/hardware_setup.md:77,116`；`board/signoff.md:291-297`；`report/README.md:111`；`report/60-failure-analysis.md:590`；`report/90-open-items.md` 20 余处；`report/collaboration/workflow.md:17` |
| `report/run-queue.md`（49 行）+ `report/unattended.md`（95 行） | **删** | 顶部就是"P23 第 6 节点名的 `run-queue.md`／`UNATTENDED.md`，本仓库用小写文件名…内容结构逐条照 P23"——为提示词而写的文件，与工程无关，读者拿它没有任何可执行的东西 | `report/README.md:111`（名单里未列，但 `report/collaboration/workflow.md:17,45,47` 引它）；`report/40-optimization.md:227`；`report/60-failure-analysis.md:309,317`；`report/repro-check.md:212`；`report/90-open-items.md:112,544`；`report/collaboration/sessions/s04-*.md:28,41`；`report/prompts-used.md` 若点名 |
| `report/final-gate.md` | **并入 `report/submission-checklist.md`**（留一张现算读数表 + 一条命令） | 与 checklist 第 7/11/15/19/20/21 行是同一批判据的两份复述；A 节已证这份的读数表整体过期，正是"两份复述必漂"的代价 | `report/README.md:82,111`；`report/claims-vs-evidence.md:22,32`；`report/run-queue.md:40`；`build/evidence/r120_final_gate*.txt`（件不受影响） |
| `report/submission-package.md` | **并入 `report/README.md` §2** | 唯一被引用的那一格（§3.3.5.4 推荐结构对照）本身就该长在导航页上 | `report/README.md:28,111` |
| `report/claims-vs-evidence.md` | **保留**（但按 A 节改口径 + B 节去"本表写下这一行时"） | 它是"断言↔凭据↔三态"的对照，是文档质量那一格的正面凭据，且 `skills/templates/claims-vs-evidence/SKILL.md` 已把它做成模板；不是过程件 | `report/README.md:19,110`；`report/figures/legend.md:94`；`report/90-open-items.md:117`；`skills/README.md:162`；`skills/*/…` 8 处 |
| `report/draft.md` | **已不存在**（本次复核期间被并发轮次移除） ⇒ 无需动作 | — | 曾有 2 处引用（`report/questions-for-team.md` 等），改口径时顺手清 |
| `report/notice.md` | **保留**（改名成随包的许可/再分发页） | 第三方条款是交付必须有的；问题只在它把"本轮没打开过""实测存在"写进了正文 | `report/README.md`（若列）；`report/90-open-items.md:26`（"16 行逐条"）；`report/submission-checklist.md:18`；`report/log/contest_checklist.md` |
| `report/optimization_log.md` | **保留 + 换写法** | 赛题明确要"优化过程，含优化前后对比"；删掉就没有优化过程。要改的是 69 行"今天/本轮"时态（B 节），不是文件本身 | `report/README.md:20,107`；`report/40-optimization.md`；`report/perf_report.md`；`report/timing_global.md`；`report/90-open-items.md` 等 13 个文件 |
| `report/60-failure-analysis.md` | **保留 + 换写法** | 赛题"失败分析"那一格的正面件；但要与 `report/known_issues.md` 分工写死（现在两份都在讲 A1–A15/B1–B16 的同一批事，A 节已抓到 #196–#200 的条数在两处不一致） | `report/README.md:31,107`；`report/90-open-items.md`（2F 节整节是对它的转写 ⇒ 若留 60 就该删 2F）；`report/known_issues.md`；共 7 个文件 |
| `report/acceptance-recipes.md` | **并入 `board/acceptance.md`** | 同一批"要人眼判的项"两处各写一遍（`board/acceptance.md` E1–E6 已含命令+应看到什么），且它在打包白名单里 ⇒ 两份必漂 | `build/make_submission.sh:744,765`；`report/README.md:111`；`report/90-open-items.md:239`；`board/acceptance.md` |
| `report/measurements.md`／`report/perf_report.md`／`report/comparison-notes.md`／`report/timing_global.md`／`report/50-results.md`／`report/40-optimization.md` | **保留，但五份里至少两份可并** | 内容都指向 `build/report/*.rpt` 现件；`perf_report.md:4` 自己声明"不要当当前值引用"，这类"历史走势页"最适合并进 `optimization_log.md` 末尾一张累计表 | `report/README.md:20,110`；`report/90-open-items.md` 多处；`src/host/metric_recheck.mjs`（取数名单，改文件要同步改名单否则射程变空） |
| `report/architecture.md` + `report/02-architecture.md`；`report/modules.md`；`report/board_pins.md`；`report/interface-table.md`；`report/commands.md`；`report/command_precedence.md`；`report/defaults.md`；`report/rotation_and_effects.md`；`report/ps_vs_pl.md`；`report/host_guide.md`；`report/src-map.md`；`report/build.md`；`report/build-notes.md`；`report/declarations.md`；`report/demo_script.md`；`report/bench_mutation.md`；`report/known_issues.md`；`report/known-limitations.md`；`report/01..08-*.md` | **保留**（其中 `architecture.md` 与 `02-architecture.md` 需二选一） | 都是工程本体说明；`report/README.md` 已把"分章版=导读、小写原件=主题正本"的分工写清，但**两份并存本身就是漂的来源**（`interface-table.md:322` 就写着它和另一份的差集原因） | `report/README.md:104-118` 的存在性名单把上面每一份都点进去了 ⇒ 合并时要同批删名单条目 |
| `report/ai_collaboration.md` + `report/llm_collab.md` + `report/collaboration/*` | **保留，两份主文合一** | 赛题"大模型协作记录"15 分那一格要它们；但两份在讲同一批案例（`ai_collaboration.md` 466 行 vs `llm_collab.md`），且都带"上一轮/更早那几跑"的时态 | `report/README.md:22,110`；`skills/README.md`；`report/90-open-items.md` 数处 |
| `report/log/`（`issues.md` 13 724 行 + `overnight_log.md` 6 217 行 等，共 22 656 行） | **不删**（按仓库口径随包，过程件的家） | 上面所有"并入台账"的目标就是这里 | — |


**改动行数估计汇总（一行）**：A 节逐条改数字/行号/状态 ≈ **175 行**；B 节换写法 ≈ **380 行** + 纯删过程回声 ≈ **300 行**（命中行合计 634，其中 90/60/repro-check/optimization_log/70/known_issues 六份占 461）；C 节整节或整文件退场 ≈ **1 050 行**（90 的 §1/3/4/5/6/7 ≈ 420、repro-check 的 §1/§8 ≈ 250、`run-queue` 49、`unattended` 95、`questions-for-team*` 53、`final-gate` 48、`submission-package` ≈ 60、`acceptance-recipes` ≈ 250）+ 名单与打包器同步 **12 处 / ≈ 30 行**（`build/checks/check_repo_consistency.mjs:323,353`、`build/make_submission.sh:744,762-766`、`build/r120_rotate_skill_refs.mjs:23`、`report/README.md:104-118`）⇒ 合计 **≈ 1 885 行**，其中纯删 ≈ 1 350 行、改写 ≈ 555 行；不触碰 `report/log/`、`skills/`、`data/metrics.csv`。

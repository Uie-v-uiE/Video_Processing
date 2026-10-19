# 无人值守运行台账（P23 第 6 节点的 `UNATTENDED.md`，本仓库用小写文件名）

命名差异声明：P23 原文写的是 `RUN_REPORT.md / 90-open-items.md / UNATTENDED.md / report/unattended.md`。
赛题 3.3.5.4 要求目录与文件名纯英文小写，因此文件名改成
运行汇总件（旧名 docs/ 这一层，2026-10-04 改名波已并入 report/；那一份汇总还没落盘，故此处不写路径）、`90-open-items.md`（旧件，内容已并入 `report/90-open-items.md`）、`report/unattended.md`（本台账）、`unattended.md`（旧件，内容已并入本台账第五节）。
**内容结构逐条照 P23，只改文件名大小写。** 本台账是"实际执行过的动作清单"，与 `git log --stat` 必须对得上。

## 一、本轮（2026-10-04 09:1x–11:4x 本机时间）我自己执行过的动作

### 只读探测与量测
| 动作 | 命令或脚本 | 产出件 |
| --- | --- | --- |
| HDMI 源端窗的时钟身份反查 | `build/tcl/probe_ser_clock.tcl` 等 6 支只读探针（`probe_tmds_clocks`、`probe_tmds_launch_clock`、`probe_clock_networks`、`probe_r119_xdc_loads`、`probe_report_shape_pin`、`probe_tmds_pin_skew`） | `build/evidence/r119_*.txt`、`r119_clock_networks.rpt` |
| 候选约束 load 前后对照（两次） | `read_xdc` 后跑 `report_timing -to`，看 `Path Group` 与 `Requirement` | `r119_xdc_loads_probe3.txt`（−3.482/−3.458/−3.474 ns）、`r119_xdc_loads_probe4_pinclk.txt`（−4.897/−4.873/−4.890 ns） |
| 报告形状测量（写解析之前） | `build/tcl/probe_report_shape_pin.tcl` | `r119_shape_tmds_data_p_0_.txt`（第 22 行是 `Data Path Delay`，**没有** `data arrival time` 这一行） |
| 已布线成品的逐脚 clock-to-pin 离散 | `build/tcl/probe_tmds_pin_skew.tcl` 打在 `system_top_routed.dcp` | `r119_pin_skew_probe2.txt`（互对最差 0.065 ns、对内 0.001 ns）；失败的第一版 `r119_pin_skew_probe.txt` 一并保留 |
| 窗件尺子 | `node build/r119_window_check.mjs` 与 `--self` | `build/evidence/r119_window_check.txt`：判 10 项红 0；`--self` 十条畸形各自动红、两条缺输入报 `NOT_MEASURED`；两跑逐字节一致 |
| 仓库门禁 | `bash build/gates.sh` × 2 | 两跑逐字节一致；判定 24 项、23 绿、**1 红 = 已声明的 C5c**（顶层台架 `tb_v98` FAIL 行=1） |
| 技能包门禁 | `node 旧条目名 scripts/check/gen_index.mjs（盘上无此路径）` + `gates.mjs`（两个都是 2026-10-04 c7b325f 重建前的旧包件名、**现不存在**；今天这一格由 `skill/_meta/build-index.mjs` + `skill/_meta/check-skill-package.mjs` 承担）| 最近一次：判定 12 项 = 9 绿、**2 红（G2 缺壳、G10 专有名未标注）**、1 未测（G11 selftest） |
| 敏感信息扫描 | `git grep -lI -e <用户名> -e <本机名>` 全仓 / 只看向导类文件 | 结果记进 ISSUES #336：工具产出原件 814 份含 `Host :`/临时绝对路径；手写文档 2 份含临时路径 |
| 位流身份读回 | `md5sum build/system.bit` = `cb907d3e4898…`（r132 这一轮；门禁件尚未重跑） | 支撑 `system_top_routed.dcp` 与板上位流同轮的**推断**（目录与时间戳对应，非工具指纹绑定） |

### 我写/改的文件（全部随下列提交入库）
- `8627be5`：`src/constraints/r119_hdmi_source_window.xdc`（改写成纯 SDC）、
  `src/constraints/r119b_hdmi_tp1_pinclk.xdc`（新建，只作探针输入，不进任何开关块）、
  `build/r119_window_check.mjs`、`build/tcl/probe_*.tcl` 6 支、`build/evidence/r119_*` 全部读数件、
  `build/tcl/build_system_axigpio.tcl`（开关块注释：守卫为何不放 .xdc）、
  `report/io/hdmi_cts_source_window.md`、`report/io/hdmi_tp1_sdc_measurement.md`、
  `report/timing/debt_ledger.md`（两节追加）、`report/log/issues.md`（#335）、
  `board/acceptance.md`（E4 眼睛签收按队员原话补记）、`README.md`、`.gitignore`、`build/make_submission.sh`。
- `b1424cd`：`submit/`（README + 八章 + reproduce/）、`unattended.md`（旧件）、`90-open-items.md`（旧件）。
- `384a0b3`：`unattended.md`（旧件）、`90-open-items.md`（旧件）、`report/log/issues.md`（#336）、
  `旧条目名 _meta/entry-template.md（盘上无此路径）` 的本机绝对路径脱敏（该件是重建前的旧包名，c7b325f 之后**现不存在**；本行是当时那一笔提交动了什么的清单，只报数不指路）。
- 未提交（agent 半成品，故意留在工作树）：`skill/` 各类目新条目、`scripts/`、`data/` 新目录、
  `board/` 新文档、`docs/` 各章、`report/` 各新章节、`build/` 新工件。
- 删除动作（有证明才删）：四份 `skill/{pitfalls,prompts,references,templates}/_MANIFEST.md`。
  删除前核对：三份共 30 条路径行**全部被生成索引覆盖（未覆盖 = 0）**，其"口径说明"文字已整体迁入
  `skill/README.md` 正文区（生成块之外）。理由：`_MANIFEST.md` 违反 3.3.5.4 的小写命名，且手写第二份索引必然与
  `gen_index.mjs` 漂移（G1 因此判红 3 项 → 现 0 项）。
- 追加目录：`旧条目名 _meta/sources.md（盘上无此路径）`（178 行，插 4 项目录；旧包件名，**现不存在**，本行只报当时的改动不指路）、
  `旧条目名 templates/project-skeleton/project-skeleton.md（盘上无此路径）`（114 行，插 8 项目录；旧包件名，**现不存在**——同一条目重建后的路径是 `skill/templates/project-skeleton/templates/skeleton.md`），这一改动是为了过 G6。

### push 状态
`git push origin HEAD:main` 成功：`f5897d7..384a0b3`（10:47 本机，直连即可，未用代理）。
`384a0b3..157d332`（10:47 之后，直连）。`157d332..ab640e9`（**10:31 UTC / 12:31 本机：直连被 `Recv failure: Connection was reset` 拒绝，
改用逐命令代理 `git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=… push` 成功**）。
**代理只在那一条命令里生效，没有写进任何 git 配置**：紧随其后 `git config --get http.proxy`、
`--get https.proxy`、`--global --get http.proxy` 三条都返回空（原文已贴进当轮输出），因此队伍要求的"用完取消"没有遗留项可取消。
本轮没有设置过任何持久代理，也未改 `git config` 的任何键（P23 禁止改配置，未越线）。

## 二、派出的子任务（P23 第 4 节：作者与审计分离）

技能包：`skill-mig-a/b/c/d/e`（扁平卡迁移，28 张）、`skill-scripts-selftest`（5 份 SKILL.md + selftest/run_all.sh）、
`p02-prompts-gap`（补 4 个提示词模板）、`p03-templates-gap`（补 4 个案例模板）。
交付物：`p12-readme`、`p13-src-docs`、`p14-sim`、`p15a-build`、`p15b-roster`、`p15c-ledger`、
`p16a-board`、`p16b-compare`、`p16c-signoff`、`p17-data`、`p18a-report`、`p18b-results`、`p18c-failures`、
`p19-novelty`、`p20-licenses`、`p22-collab-archive`。
统一约束（写在每条提示词里）：不改 `src/` 行为、不放宽判据、不删已入库件、不跑构建/台架/串口/刷板、
不 commit/push、需要队伍答的进 `report/questions-for-team-p<nn>.md` 并在正文留 `【队伍未确认】`。

## 三、我没有做、也不假装做过的事

- 没跑完整构建，没刷板，没动串口，没动 `data/metrics.csv` 的任何数值。
- 没有把两个 HDMI 候选约束带进默认构建（开关仍是关），因此**没有**"已按 CTS 校验"这类结论。
- 没有改写 git 历史、没有强推、没有 `--no-verify`。
- 没有替队伍签收任何需要眼睛的验收项。
- 814 份工具产出原件里的主机名**没有**去改（改了就不是凭据），改为分类登记并提请裁决（#336）。

## 四、r120 装配段（同日 12:2x–14:2x，提交 `1c4e26b` → `8a3d58d`）

跑过并留件的命令（全部只读或产出读数件）：

| 命令 | 用途 | 件 |
| --- | --- | --- |
| `node build/r119_window_check.mjs`（两跑 diff） | 窗件 + 成品离散读数，本轮补回 5 份输入的 md5 头 | `build/evidence/r120_window_check.txt` |
| `node 旧条目名 scripts/check/retire_flat.mjs（盘上无此路径）` → `--apply` | 旧扁平卡删除前的映射/八节/出处证明，与之后的退役 | 输出转录在提交说明；映射表 `build/evidence/r120_migration_map.txt`（`retire_flat.mjs` 是重建前的旧包件名，**现不存在**；本行是当时跑过并留件的清单，只报数不指路）|
| 一次性 skill 指路改写器（`--check`→`--apply`→再 `--check`） | 指路改口四条规则，改前 165 处、改后 0 处（幂等） | 本台账即其效果见证（该脚本跑完即废，已随 r120 轮次清理） |
| `node 旧条目名 scripts/check/gen_index.mjs（盘上无此路径）` + `--check` | 技能包索引重写与一致校验（条目 58 是当时旧件的读数） | 同上（`gen_index.mjs` **现不存在**；现役件 `skill/_meta/build-index.mjs` 本轮判 `条目=49`）|
| `node skill/_meta/check-skill-package.mjs --full` ×2 | 技能包 12 项门禁，两跑逐字节一致 | `build/evidence/r120_gates_skill_a.txt`、`..._b.txt`（`gates.mjs` **现不存在**，两件转录是当时的凭据）|
| `bash skill/_meta/run-all-checks.mjs` | 6 把脚本尺子 40 条对照（含反例与缺件 NOT_MEASURED） | `build/evidence/r120_selftest.txt`（`run_all.sh` **现不存在**；现役等价件 `skill/_meta/run-all-checks.mjs` 本轮判 `判 9 项 自测件=6 红=0 未测=0 PASS`）|
| `node build/checks/check_repo_consistency.mjs --self` | 终审 C2/C3/C9 的对照例（现算 `判 28 项 PASS`＝C2 造 6 例 + C3 造 17 例 + C9 造 5 例，每条都能动） | 输出转录在提交说明（本轮落盘件：`build/evidence/1006_c3_scope_selftest.txt`） |
| `node build/checks/check_repo_consistency.mjs --list` | 全仓终审 C1–C12 定版读数 | `build/evidence/r120_final_gate.txt` |
| `node build/r120_src_map.mjs` | 源码地图现算（盘上文件数 vs `git ls-files` 对账） | `report/src-map.md` |

本轮提交（都已 `git push` 到 `main`，代理只以**逐命令**方式给一次，`git config --get http.proxy` 与 global 均查回为空）：
`b6f7445`（P16/P18/P22 交付件 + 终审三处量纲错）、`99afe73`（技能包重构与门禁全绿）、
`8a3d58d`（P21 三件套 + 源码地图 + C1/C12 两处判据缺陷 + 数字对账）。

**这一段仍欠、且不假装做过的**：
1. `report/{10-background,20-principle,30-partition-if}.md`、`report/{prior-art-search,novelty-claims}.md`、
   `report/claims-vs-evidence.md`、`report/`、provenance-and-licenses 一页：派发批次到回合上限，这些文件没有产出。
2. 终审 C3 剩 3 条死引用、C4 命名违规 286、C9 复现 30 条 FAIL 未逐条归因、C5 卫生机检整脚本 >300 s，因此
   **交付终审不是全绿**（`build/evidence/r120_final_gate.txt`：绿 8 / 红 3 / 未测 1）。
3. 需要眼睛与手的行（E6 的"按住 KEY1"那一半、拔卡观感、按键手感）仍未由人签。
4. 改名 308 条含大写路径、脱敏 814 份工具产出原件：都是不可逆/连带面，等裁决（Q-P21-2、Q-P20-2），未擅动。

## 五、还没跑完的队列项（照旧 `unattended.md` 原表搬过来）

旧 `unattended.md` 那张表一共 28 行，点名只搬状态没到"已交付"的 13 行，每一格连状态词一起照原文抄，
没改写、没并成句子。剩下 15 行（P01、P04、P05、P06、P07、P09、P15a、P15b、P16b、P16c、P17、P18b、P18c、
P21、P22）没往这里搬 —— 那些行里也有各自的读数，删原文件之前要不要一并搬，需发起者判定。

原表顶上的口径说明（照原文抄在本页下方那一段，即 `report/unattended.md` §五 的「口径说明」）与本页 3–5 行说的是同一件事，两份措辞不一样，都照原文留着，
需发起者判定要不要只留一份：

口径说明：P23 原文把四个交付物写成 `RUN_REPORT.md / 90-open-items.md / UNATTENDED.md / report/unattended.md`。
本仓库采用**小写文件名**（赛题 3.3.5.4 的硬性命名要求优先于提示词里的示例大小写，
差异记录在 `report/unattended.md` 顶部），内容结构逐条照 P23。

来源：队伍的提示词集 `skill_prompts/README.md`（在本机文档目录里，**不随包**）的建议顺序
（工程支线 P13→P14→P15a→P15b→P15c→P17→P16a→P16b→P16c→P12；技能支线 P00→P01→P05→P04→P02→P07→P03→P06→P08→P09；
收尾 P11→P18a→P18b→P18c→P19→P22→P10→P20→P21）。

| 任务 | 目标文件（点名范围） | 依赖 | 状态 |
| --- | --- | --- | --- |
| P02 提示词工作流 | `skill/prompts/*` | P01 | 已交付 8 条（4 支模板 + 本轮迁入的 `eye-acceptance-loop`、`llm-fpga-debug-workflow`、`read-only-review-agent`、`round-work-loop`）；全部 `待验证`——每条都还欠"同一模板连跑 3 次"的 evals 记录 |
| P03 案例模板 | `skill/templates/*` | P01 | 已交付 4 条；**均未经空目录演练**（各条目 §7 明写"模板未经空目录验证"，不宣称可直接使用） |
| P08 验证与增益 | `skill/_meta/`（旧包的 `skill/evals/` 那一层在 2026-10-04 c7b325f 重建后从未入库、不随包）| P04/P05 | 部分交付（协议与两跑原始件、陌生人演练与第三方审计各一份都在 `skill/_meta/` 一侧，条目级验证状态见 `skill/_meta/validation.md`）；**缺的是"同一模板连跑 3 次"的增益对照**，各条目 §7 一律 `【待验证】`，不念成已验证 |
| P11 学习文档 | 本地学习文档那一层（**不随包**，`.gitignore` 已列） | P13/P15b | 11 个文件已交付，5 篇因缺前置未写 |
| P13 `src/` … | … | 部分（`report/interface-table.md` 已落 1509 行；`report/src-map.md` 本轮由 `build/r120_src_map.mjs` 现算生成，83 文件 × 4 列；`src-audit` 装配页未写，`git ls-files` 与盘上都没有这一件 ⇒ 现不存在；契约头改动受 B1 约束） |
| P14 `sim/` … | … | 部分（`sim/README.md` 已落；回归清单目录与 `verification-claim` 装配页都未写，两者从未落盘 ⇒ 现不存在。"验证声明"只能停在"逐台架判据 + 门禁"这一档） |
| P15c 逐轮台账 … | … | 部分（`build/runs/ledger.md`、`build/runs/decisions.md` 在盘；两轮派发都被 150 回合上限截停 ⇒ 逐轮指针目录未核，缺口记在未决项） |
| P16a 板级可复原 … | … | 进行中（`board/hardware_setup.md` 已落并随包；三件身份改由 `build/provenance.md` 与 `board/measured/` 的 IDENTITY 块承担——原先那层身份摘要卡已随目录精简删掉、不随包；`bringup-checklist.md` 从未落盘 ⇒ 现不存在） |
| P12 根 README … | … | 部分（`report/repro-check.md` 已出，判定读数是 `判定列在内=61 行 PASS=49 FAIL=0 未测=12 判定列不成词=0`（终审 C9 现跑）；14 行没有判定词的表格已补齐（判定列搬回末列），缺的是那 12 行未测，逐条构成见 `report/08-limits.md` 第 13 节。更早一版 C9 按全文 token 计数读出 `PASS=91 FAIL=30 未测=32`，这一错位登记在 `report/claims-vs-evidence.md`） |
| P18a 原理与划分 … | … | 未交付（`report/figures/` 已建；`20-principle.md`、`30-partition-if.md` 未写——批次到 150 回合上限，已登记不假装完成） |
| P19 背景与创新点 … | … | 未交付（`10-background.md`、`prior-art-search.md`、`novelty-claims.md`、`report/claims-vs-evidence.md` 未写；立意与主张强度本就依赖 Q-P19-1/Q-P19-2 的队伍回答） |
| P10 报告里技能包两章 | `report/07-skill-distillation.md`（submit 侧）与 P22 配对 | P08/P09/P22 | 部分（`report/07-skill-distillation.md` 已成文） |
| P20 许可与声明 … | … | 部分（`LICENSE` 在、`build/checks/check_repo_hygiene.sh` 在、`report/declarations.md` 本轮交付；**`report/` 本轮交付**：16 行第三方件，其中 12 行标 `未核`，风险最高的是第 12 行（厂商资料抄件与原理图裁图在跟踪集内）与第 13 行（`src/rtl/eth` 25 个文件无版权头、逐文件"逐字／改造"没有登记表）⇒ 处置写成 Q-P23-1；provenance 逐轮指纹页仍未单独成页；卫生机检整脚本 >300 s 未跑完 ⇒ 终审 C5 记 NOT_MEASURED，慢点定位到 C5 断链层，见 ISSUES #339 末段） |

阻塞项（写在这里而不是藏起来）：

- B1 `src/` 契约头（P13 允许的唯一直接修改）**本轮不做**：本仓库的文档尺子 D5 按行号锚点核对引用，
  给 51 个源文件加文件头会让全部行号下移、D5 大面积变红；这是一次"改结构"动作，需要单独一轮并先备好还原能力。
  已进 `report/90-open-items.md` §2A 编号 1（Q-P13-1）。
- B2 旧 `docs/` 那层（P12/P15b/P16c/P20/P21 点名）与既有 `report/` 的分工：那层的 19 件名册与台账已在 90b0391c 整体改名进 `report/timing/`（`git ls-files docs/ \| wc -l` = 0，`git ls-files report/timing/ \| wc -l` = 19）；剩下的关系只有：只做加法，不搬移，
  避免第二次"docs→report 改名轮"（该动作历史上两次退回）。
- B3 任何需要重跑 127 分钟顶层台架或完整构建的数字：一律 `【待实测】`，不许用旧轮次顶替。

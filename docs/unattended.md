# 无人值守运行台账（P23 第 6 节点的 `UNATTENDED.md`，本仓库用小写文件名）

命名差异声明：P23 原文写的是 `RUN_REPORT.md / questions-for-team.md / UNATTENDED.md / docs/run-queue.md`。
赛题 3.3.5.4 要求目录与文件名纯英文小写，因此落地为
`docs/run_report.md`（待装配完汇总）、`docs/questions-for-team.md`、`docs/unattended.md`（本文件）、`docs/run-queue.md`。
**内容结构逐条照 P23，只改文件名大小写。** 本文件是"实际执行过的动作清单"，与 `git log --stat` 必须对得上。

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
| 技能包门禁 | `node skill/scripts/check/gen_index.mjs` + `gates.mjs` | 最近一次：判定 12 项 = 9 绿、**2 红（G2 缺壳、G10 专有名未标注）**、1 未测（G11 selftest） |
| 敏感信息扫描 | `git grep -lI -e <用户名> -e <本机名>` 全仓 / 只看向导类文件 | 结果记进 ISSUES #336：工具产出原件 814 份含 `Host :`/临时绝对路径；手写文档 2 份含临时路径 |
| 位流身份读回 | `md5sum build/system.bit` = `cd04907e1369…`（与 r118 记录一致） | 支撑 `system_top_routed.dcp` 与板上位流同轮的**推断**（目录与时间戳对应，非工具指纹绑定） |

### 我写/改的文件（全部随下列提交入库）
- `8627be5`：`src/constraints/r119_hdmi_source_window.xdc`（改写成纯 SDC）、
  `src/constraints/r119b_hdmi_tp1_pinclk.xdc`（新建，只作探针输入，不进任何开关块）、
  `build/r119_window_check.mjs`、`build/tcl/probe_*.tcl` 6 支、`build/evidence/r119_*` 全部读数件、
  `build/tcl/build_system_axigpio.tcl`（开关块注释：守卫为何不放 .xdc）、
  `report/io/hdmi_cts_source_window.md`、`report/io/hdmi_tp1_sdc_measurement.md`、
  `docs/timing/debt_ledger.md`（两节追加）、`report/log/ISSUES.md`（#335）、
  `board/ACCEPTANCE.md`（E4 眼睛签收按队员原话补记）、`README.md`、`.gitignore`、`build/make_submission.sh`。
- `b1424cd`：`submit/`（README + 八章 + reproduce/）、`docs/run-queue.md`、`docs/questions-for-team.md`。
- `384a0b3`：`docs/run-queue.md`、`docs/questions-for-team.md`、`report/log/ISSUES.md`（#336）、
  `skill/_meta/entry-template.md` 的本机绝对路径脱敏。
- 未提交（agent 半成品，故意留在工作树）：`skill/` 各类目新条目、`scripts/`、`data/` 新目录、
  `board/` 新文档、`docs/` 各章、`report/` 各新章节、`build/` 新工件。
- 删除动作（有证明才删）：四份 `skill/{pitfalls,prompts,references,templates}/_MANIFEST.md`。
  删除前核对：三份共 30 条路径行**全部被生成索引覆盖（未覆盖 = 0）**，其"口径说明"文字已整体迁入
  `skill/README.md` 正文区（生成块之外）。理由：`_MANIFEST.md` 违反 3.3.5.4 的小写命名，且手写第二份索引必然与
  `gen_index.mjs` 漂移（G1 因此判红 3 项 → 现 0 项）。
- 追加目录：`skill/_meta/sources.md`（178 行，插 4 项目录）、
  `skill/templates/project-skeleton/project-skeleton.md`（114 行，插 8 项目录）——为过 G6。

### push 状态
`git push origin HEAD:main` 成功：`f5897d7..384a0b3`（10:47 本机，直连即可，未用代理）。
`384a0b3..157d332`（10:47 之后，直连）。`157d332..ab640e9`（**10:31 UTC / 12:31 本机：直连被 `Recv failure: Connection was reset` 拒绝，
改用逐命令代理 `git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=… push` 成功**）。
**代理只在那一条命令里生效，没有写进任何 git 配置**：紧随其后 `git config --get http.proxy`、
`--get https.proxy`、`--global --get http.proxy` 三条都返回空（原文已贴进当轮输出）⇒ 队伍要求的"用完取消"没有遗留项可取消。
本轮没有设置过任何持久代理，也未改 `git config` 的任何键（P23 禁止改配置，未越线）。

## 二、派出的子任务（P23 第 4 节：作者与审计分离）

技能包：`skill-mig-a/b/c/d/e`（扁平卡迁移，28 张）、`skill-scripts-selftest`（5 份 SKILL.md + selftest/run_all.sh）、
`p02-prompts-gap`（补 4 个提示词模板）、`p03-templates-gap`（补 4 个案例模板）。
交付物：`p12-readme`、`p13-src-docs`、`p14-sim`、`p15a-build`、`p15b-roster`、`p15c-ledger`、
`p16a-board`、`p16b-compare`、`p16c-signoff`、`p17-data`、`p18a-report`、`p18b-results`、`p18c-failures`、
`p19-novelty`、`p20-licenses`、`p22-collab-archive`。
统一约束（写在每条提示词里）：不改 `src/` 行为、不放宽判据、不删已入库件、不跑构建/台架/串口/刷板、
不 commit/push、需要队伍答的进 `docs/questions-for-team-p<nn>.md` 并在正文留 `【队伍未确认】`。

## 三、我没有做、也不假装做过的事

- 没跑完整构建，没刷板，没动串口，没动 `data/metrics.csv` 的任何数值。
- 没有把两个 HDMI 候选约束带进默认构建（开关仍是关），因此**没有**"已按 CTS 校验"这类结论。
- 没有改写 git 历史、没有强推、没有 `--no-verify`。
- 没有替队伍签收任何需要眼睛的验收项。
- 814 份工具产出原件里的主机名**没有**去改（改了就不是凭据），改为分类登记并提请裁决（#336）。

---
name: tool-version-drift
description: 查"哪些事实绑在哪个工具版本上"的速查表：当同一条命令换了 Vivado/Vitis/xsim/Node/Python 之后选项名、命令名、报错码或报告列名变了；症状包括 Common 17-170 Unknown option、Common 17-263 filter 语法错、invalid command name、报告件头 Tool Version 与你以为的不一致，或换版本后门禁数字整批作废。
---

## 1. 一句话用途

版本相关事实，逐行绑版本。

## 2. 适用场景

- 当一条 Tcl/工具命令报 `Unknown option`、`invalid command name`，而你有理由怀疑它属于版本差异时。
- 当要把某个读数写进交付文档，而该文档的"共用条件"行需要点名工具与器件时。
- 当换 Vivado 补丁号或换主版本线，你要判断"哪些数与哪些脚本要重跑"时。
- 当同一命令在两个版本上行为不同，而你需要**分版本写两行**而不是写一句含糊话时。
- 当需要确认本包某条工具结论的核对日期与出处件时。

## 3. 不适用 / 失效条件

- **本层不是判据**：本页只回答"是什么、去哪确认"；结论由 `evals/` 记录或实测输出给。
- 不适用：与版本无关的事实（例如"读不到输入不等于通过"这类纪律）。
- 失效：本页凡"两个版本只见过一个"的行，另一格留空并注明原因；换到你没测过的版本时，那行对你就是 `NOT_MEASURED`。
- 不适用：厂商官方文档号（UG901 / UG904 / UG1399 / UG949）——本包本轮**没有打开过**这四份的正文，`docs.amd.com` 抓取只返回"需要启用 JavaScript"，所以相关格写 `未核实`。
- 不许越界：本页不新增"未被实测或文档确认过的处置办法"；处置办法住在 `skill/pitfalls/` 与条目正文里。

## 4. 前置条件

- 能读报告件头：`awk 'NR<=12' build/timing_summary.rpt`（本仓所有 `.rpt` 前 12 行是身份块）。
- 能跑版本自报：`node --version`、`python --version`、`bash --version`（本次都实跑了，见 §7）。
- 仓库里的版本声明位置：`report/BUILD.md` §1 表格、`data/metrics.csv` 第 2 行（共用条件行）、`skill/prompts/round-work-loop/SKILL.md` 的"环境事实"一节。
- 若要确认某命令是否存在：`info commands <名或模式>` 落件（本仓形状 `build/evidence/r114_cmds_console.txt`）。

## 5. 使用方法

1. 读身份块并把五个字段抄进本轮记录：`Tool Version` / `Date` / `Command` / `Design` / `Device` + `Speed File`。
   完成后应看到：与 `build/timing_summary.rpt:3-10` 同样的八行（本次实读到 `Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026`）。
2. 对每个"命令行为"结论，去 `version-bound-rows.md` 找它绑的版本行。
   完成后应看到：该行点名了件路径或代码路径；没有点名的行按 `未核实` 处理。
3. 需要确认命令/选项是否存在时，先落一份 `help` 或 `info commands` 清单再写判定脚本
   （本仓形状：`build/evidence/r117_d0/nethelp_console.txt:395` 数到 31 个选项，`:404` 判 `-skeleton_clustering present=0`）。
   完成后应看到：present=0/1 的逐行清单，且判定器把用到的选项对回它。
4. 换版本时重跑的清单（本仓口径）：`ps7_init`、BD 地址、实现策略、**全部门禁数字**（出处 `skill/prompts/round-work-loop/SKILL.md` 的"环境事实"一节）。
   完成后应看到：一轮新构建 + 一套新冻结件；旧件的读数只作历史对照。
5. 换器件家族时重判的清单：7 系列原语 `IDDR/IDELAYE2/IDELAYCTRL/OSERDESE2/MMCME2_BASE` 一类的存在性与约束可用性
   （同出处）；UltraScale+/Versal 上的对应原语名与报告列名要重量。
   完成后应看到：你写下"哪些行是平台相关"，而不是把旧行的数字搬过去。
6. 每次交付前核对本包引用的版本串与件头一致（先把空白归一，否则一份件多打一个空格就会多出一行）：
   `grep -h "Tool Version" build/*.rpt | tr -s ' ' | sort -u`。
   完成后应看到：一行（同一版）；出现多行 = 混了两版报告的件，须停下分清哪份来自哪一次构建。

## 6. 判读与失败分叉

- 步骤 1：
  通过 = 八行齐全且版本串与 `report/BUILD.md` §1 声明一致。
  失败 = 不一致 ⇒ `FAIL`，文档念的版本与实际产出不符，先改文档（不是改判据）。
  读不到输入 = 件头缺失/文件 0 字节 ⇒ `NOT_MEASURED`，该件不能当凭据。
- 步骤 2：
  通过 = 找到绑版本的行。
  失败 = 该格只有"两版都一样"这类没实测的说法 ⇒ `FAIL`，把该结论降级为 `未核实`。
  读不到输入 = `version-bound-rows.md` 里该行留空 ⇒ `NOT_MEASURED`，那一格本轮就是没测，照抄会造出假事实。
- 步骤 3：
  通过 = 选项/命令在清单里存在。
  失败 = `present=0` ⇒ `FAIL`，这一滚/这一探针根本没执行到位（本仓代价：两次 8 分钟空滚，`report/log/ISSUES.md` #319）。
  读不到输入 = 清单文件不存在 ⇒ `NOT_MEASURED`，先补 40 秒探针。
- 步骤 4/5：
  通过 = 你按清单重跑并留下新件。
  失败 = 只改了文档中的版本号 ⇒ `FAIL`，数字仍然来自旧版工具。
  读不到输入 = 那台机器上没有对应版本 ⇒ `NOT_MEASURED`，明写"换版本后要重跑什么"而不下结论。
- 步骤 6：
  通过 = 只有一行。
  失败 = 多行 ⇒ `FAIL`，说明 `build/` 混着两版报告的件；按 `skill/pitfalls/who-else-writes-this-artifact/SKILL.md` 定身份。
  读不到输入 = 没有 `.rpt` ⇒ `NOT_MEASURED`。

## 7. 已验证的效果

- 本次实跑的版本自报（2026-10-04，同一台 Windows + Git Bash 主机）：
  `node --version` → `v24.21.0`；`python --version` → `Python 3.12.10`；`bash --version` → `GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)`。
- 本次实跑的版本一致性核对：`build/timing_summary.rpt:3`、`build/utilization.rpt:3`、`build/cdc.rpt:3`、
  `build/clock_util.rpt:3`、`build/methodology.rpt:3`、`build/power.rpt:3` 六件的 `Tool Version` 全是
  `Vivado v.2025.2.1 (win64) Build 6403652 Thu Mar 19 19:48:24 GMT 2026`；
  对 `build/*.rpt` 全量跑步骤 6 的那条命令：`tr -s ' '` 归一后只剩 **1 行**，
  不归一时是 2 行（`build/power.rpt:3` 的 `| Tool Version     :` 多两个空格的对齐写法）⇒ 这就是步骤 6 要先归一的原因。
- 声明与实读对照：`report/BUILD.md:11` 写 `Vivado / Vitis | 2025.2.1`、`report/BUILD.md:15` 写"需要 Node 24"（本次 `v24.21.0` 同主版本线）、
  `data/metrics.csv:2` 的共用条件行写 `xc7z020clg484-2 / Vivado+Vitis 2025.2.1`。
- 未实测的行（如实留空）：Vitis/xsdb 自己的版本串**没有**在本仓库任何被跟踪件里出现过（本轮检索 `build/*.rpt` 与 `build/evidence/*` 未见 `Vitis v.` 字样）
  ⇒ `【未实测】`；UG901 / UG904 / UG1399 / UG949 四份文档正文未打开 ⇒ `未核实`；
  PG 类 IP 产品指南与器件手册编号本轮没有核对对象 ⇒ 全部留 `未核实`，不填猜测。

## 8. 提炼来源与边界

- 来源：本包 `version-bound-rows.md` 逐行给出的件/代码路径（本次打开过）；仓库声明位置 `report/BUILD.md` §1、`data/metrics.csv` 第 2 行、`skill/prompts/round-work-loop/SKILL.md` 的"环境事实"一节；台账动机 `report/log/ISSUES.md` #279/#319/#277/#308/#310 与第 6468 行。
- 引用关系：被 `skill/pitfalls/report-field-parse-breaks/SKILL.md` §8、`skill/pitfalls/tcl-query-empty-means-broken-ruler/SKILL.md` §8、
  `skill/references/build-report-field-map/SKILL.md` §3/§4 引用。
- 候选来源行在 `skill/references/_proposed-sources.md`。
- 边界：本页记录的是"本队在 2025.2.1 + win64 + MSYS 上量到的形状"；换版本线（例如 2026.1）、换主机（Linux）、
  换家族（UltraScale+/Versal）时，`version-bound-rows.md` 的每一行都要重新判定，只有"每条结论必须绑一个可打开的出处"这条方法可迁移。

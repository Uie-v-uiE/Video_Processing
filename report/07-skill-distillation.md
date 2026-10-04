# 07 · 技能包的提炼过程：从哪些失败或观察中总结、如何验证有效、边界如何确定

本章的数字口径以 `../data/metrics.csv` 与 `build/report/*.rpt` 为准；重复写出是为了让这一章能单独读懂。
这一章对应赛题 §3.3.5.3 点名的两节（技能包的提炼过程 / 大模型协作记录），与 `skills/` 目录互相印证：每条技能旁边点名的证据文件
都必须在盘上存在，读数旁边放它的产物路径；被证伪的判断与原判断一起留着，不删负结果。

## A. 从哪些失败或观察中总结

来源类别分四种：`一次事故` / `反复出现的症状` / `量出来的差异` / `外部资料`。

| 技能（条目路径见 `skills/README.md` 的一览表；下面这些名字是技能包重建前的条目名，现役条目在同一张一览里） | 来源类别 | 点名证据 |
| --- | --- | --- |
| `skills/pitfalls/checker-ran-on-nothing/` | 反复出现的症状 | `report/log/issues.md` 第 330 条（检查脚本在等的判定行，那一跑根本没有产出）、第 194 条（第 14 项没有计数下限） |
| `skills/pitfalls/report-field-parse-breaks/` | 一次事故 | `report/log/issues.md` 第 331 条（首页身份句加了 Markdown 粗体，`ADJ_RNN` 跨不过 `**` ⇒ 检查抓到 0 句） |
| `skills/pitfalls/tcl-query-empty-means-broken-ruler/` | 反复出现的症状 | `report/log/issues.md` 第 327 条（`catch` 存的是**返回码**，把成功的运行读成失败）、同族三次错结论记在同文件"Vivado Tcl 探针"那一族 |
| `skills/prompts/criterion-before-code/` | 量出来的差异 | 两次"先定判定标准再动代码"把没有依据的猜测挡在前面：`report/log/issues.md` 里第 88 与第 147 条那一段，和 `sim/tb_icmp_rx_len.v` 那条台架记录 |
| `skills/prompts/single-variable-ab/` | 量出来的差异 | 同一棵树重跑一次逐格复现基线 ⇒ `noise_ns=0.000`（件 `build/evidence/r115_*`），以及同一份 `opt.dcp` 重跑 place+route 逐位复现正式构建的读数（件 `build/evidence/r117_d0/`） |
| `skills/prompts/report-to-bottleneck/` | 量出来的差异 | 瓶颈重定位那一次：`build/evidence/r117_d0_console.txt` 量到真正的靶子是 239 引脚的广播网（FANOUT），不是先前指的 pblock |

被证伪的判断与推翻它的那次运行一起列在下面，原判断不改写、也不删：

1. 当时的判断是"钩子让 `phys_opt_design` 失败"。推翻它的是读回 `catch` 存的其实是返回码：改成
   `set rc [catch … emsg]` 后同一次运行是成功的（`report/log/issues.md` 第 327 条；修法在
   `build/tcl/r117_post_place_hook.tcl`）。
2. 当时的判断是"那一刀（代号 C9，做法是给那根广播网强制加一份寄存器复制）赢了"（只在已布线设计上重跑布局与布线的对照里，三格 +0.033/+0.187/+0.298）。推翻它的是
   官方构建跑完后的逐格对比（那份表在交付文档里叫"名册"，即逐时钟、逐端点的最差值清单）：含最紧两格在内四格变差（`report/timing/round_r117.md`、`report/timing_global.md` §9）
   ⇒ 这一版不采纳，钩子退回环境变量门后（`IMPL_POST_PLACE_HOOK`）。
3. 当时的判断是"发布前检查里 23 绿/1 红（这是那支脚本自己的写法：多少项通过、多少项未通过）的第二条未通过是文档坏了"。实际原因是留给 `issues.md` 的那份
   `.md` 备份被交付文档一致性检查（脚本里的 D5 项）当成扫描对象（`report/log/issues.md` 第 333 条）。这里能总结出的事实是
   **"新写进仓库的文件会自动进入检查脚本的范围"**，所以快照只落 `*.txt` 或直接交给 git。
4. 当时的判断是"负 slack 会被读成一个数"。实测那支检查脚本把负值读成 `null`，文档写对了也判未通过（`report/log/issues.md` 第 321 条），
   于是给检查脚本补了符号这一维，而不是改文档。

## B. 如何验证有效

验证口径：**同一模型、同一上下文、同一工具版本，绕过与使用技能包各跑一次**（借 §3.1.5.2 的基线口径），
被控制的变量在记录里列全。协议与字段见 `skills/_meta/distillation-process.md` 第二节（四道门），陌生人可照跑的复跑命令见
`skills/_meta/validation.md`（旧名 `evals/README.md`、`evals/runbook.md` 在 2026-10-04 c7b325f 重建技能包后**现不存在**，本行只报旧名不指路）。

下面只列**实际做过**的运行，三种状态分开计数：

| 验证 | 命令 | 证据 | 状态 |
| --- | --- | --- | --- |
| 文本检查脚本的确定性（同一输入两次跑逐字节一致） | `node src/host/doc_enc_check.mjs` ×2、`node src/host/line_cite_check.mjs` ×2 | `skills/evals/raw/doc_enc_pass1.txt`、`doc_enc_pass2.txt`、`line_cite_pass1.txt`、`line_cite_pass2.txt`（`cmp -s` 逐字节一致）—— 这四份是当时留在旧包 `evals/raw/` 的原始件，2026-10-04 c7b325f 重建技能包时连同 `evals/` 一层撤下、**现不存在**，本行只报当时的留档名不指路 | 已复跑 |
| 技能包装配检查 G1–G12 真的会判未通过（旧包 12 项；现役那支判 53 项）| `node skills/scripts/check/gates.mjs`（现不存在）→ 现役 `node skills/_meta/check-skill-package.mjs skills` | 当时旧包 `gates.mjs` 的首轮输出（件现不存在，本行只报数不指路）：G1 违规=13、G6 越界=3、G7 表列与实际不同源、G8 死链=4 —— 四条全部可复现，随后逐条判"确实存在 / 是检查脚本自己的维度错" | 已复跑（含未通过项） |
| 索引由目录生成、手改会被抓 | `node skills/_meta/build-index.mjs skills --check`（旧名 `gen_index.mjs --check`，件现不存在，本行只报旧名）| 与写入后的 README 比对；不一致 exit 1 | 已复跑：这次实跑 `INDEX 条目=49 类别=10 索引行=49 需改写=no PASS`，rc=0 |
| 判定标准 selftest 正反例 | `bash skills/scripts/selftest/run_all.sh` | 该脚本此刻不存在 ⇒ `NOT_MEASURED` | 未复跑（被点的脚本不在盘上） |

上表第 2 行的处置过程本身就是一条自我纠错的记录：G1 把赛题自己规定的 `README.md` / `SKILL.md` 大写名当成违规、
G7 的两个操作数取自两套"什么算条目"的定义（`gates.mjs` 与 `gen_index.mjs` 各数各的），
G8 把 `{a,b}.tcl` 这种简写记法当路径。**修法是把检查脚本的量纲改对（同一生成器、同一扩展名判定标准、大写专名白名单），
不是把通过门槛调低**；改完之后仍然剩下的未通过项（缺 `SKILL.md` 的条目、条目里的本队专有名、缺 selftest）一律保留。

## C. 边界如何确定

边界分三层（恒成立 / 平台相关 / 版本相关）：

| 层 | 内容 | 谁负责写清失效条件 |
| --- | --- | --- |
| 恒成立 | "先配能红的判据再改代码""三态判定""读不到 ≠ 通过""一条判据一行、判定放最后一个字段""差分判据成对" | 每条 `SKILL.md` 的第 2/3/6 节 |
| 平台相关 | 器件家族（7 系列 ↔ UltraScale+ ↔ Versal）、端口类型（TMDS_33 / 差分 / LVCMOS）、驱动形态（BD 的 AXI GPIO ↔ MIO）、缓存层级（PS 的 SLC/OCM ↔ 纯 PL） | 各条目第 3 节 + 第 8 节"迁移要改哪几处" |
| 版本相关 | Vivado/Vitis 2025.2.1 的报告字段位置、`report_methodology` 的 SUMMARY 形状、xsim 的 SystemVerilog 子集 | 各条目第 4 节写明版本，第 3 节写明"报告字段漂了就重新量形状" |

不写"适用于所有 AMD 器件"这样的话。迁移证据目前**没有**跨板卡记录：当时留作迁移证据的 `skills/evals/migration/` 在 2026-10-04 c7b325f 重建技能包时连同 `evals/` 一层撤下，**现不存在**
（`ls` 可核），这里写的是"当前不具备迁移条件 + 需要什么"，不声称里面已经写了什么。
需要的是第二块板卡（KU5P 那块板在手，但仓库里的 KU5P 工程已按 2026-09-28 的决定删除）
或第二个可套用的子功能（例如把 `skills/prompts/criterion-before-code` 用在一个从未走过该流程的子功能上）。

## D. 大模型协作记录（同一章要求的另一半）

- 原始轨迹在本仓库里以两种形式存在：`report/log/issues.md`（每条工具或判断事故，编号即时间轴）与
  `report/log/overnight_log.md`（按小时的决策与读数）。本章引用它们的方式是**点名编号**，不转述成"讨论后决定"。
- 智能体工作流：这次交付由一个主 agent 加若干**只看文件、不共享上下文**的子 agent 完成，
  每个子 agent 的产物落进自己的目录（`skills/pitfalls/`、`skills/prompts/`、`skills/templates/`、
  `skills/runtime/`、`skills/scripts/`、`submit/`），主 agent 负责装配与发布前检查；
  子 agent 的自述一律当**待复核的断言**处理——这正是 `skills/_meta/check-skill-package.mjs` 存在的原因（旧包里那个装配检查叫 `gates.mjs`，件现不存在）。
- 审计：第三方 AI 的审计提示词原样存在 `skills/prompts/`（见其中"交给审计员的提示词"那一节），
  审计报告回来后逐条判"确实存在 / 不成立 / 需裁决"，修完必须重跑 G1–G12。

## 本章依据的产物

`report/log/issues.md`、`report/log/overnight_log.md`、`report/timing/round_r117.md`、`report/timing/round_r118.md`、
`report/timing_global.md`、`build/tcl/r117_post_place_hook.tcl`、`skills/README.md`、`skills/_meta/writer-contract.md`（旧名 `naming-and-format.md`）、
`skills/_meta/entry-map.md`（旧名 `sources.md`）、`skills/_meta/distillation-process.md`（旧名 `evals/README.md`）、`skills/_meta/validation.md`（旧名 `evals/runbook.md`）、旧包 `evals/raw/` 那批原始件——括号里这些旧名在 2026-10-04 c7b325f 重建技能包后**现不存在**，本行只报当时依据的名不指路、
`skills/_meta/check-skill-package.mjs`、`skills/_meta/build-index.mjs`（旧名 `gates.mjs`、`gen_index.mjs` 现不存在，只报旧名）

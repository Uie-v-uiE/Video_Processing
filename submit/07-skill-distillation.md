# 07 · 技能包的提炼过程：从哪些失败或观察中总结、如何验证有效、边界如何确定

对应赛题 §3.3.5.3 点名的两节（技能包的提炼过程 / 大模型协作记录）。
这一章与 `skill/` **互相印证**：每条技能旁边点名的证据文件必须在盘上存在，
本章不复制数字，所有读数旁边放它的产物路径。

## A. 从哪些失败或观察中总结

来源类别只允许四种：`一次事故` / `反复出现的症状` / `量出来的差异` / `外部资料`。

| 技能（条目路径见 `skill/README.md` 的一览表） | 来源类别 | 点名证据 |
| --- | --- | --- |
| `skill/pitfalls/checker-ran-on-nothing/` | 反复出现的症状 | `report/log/ISSUES.md` #330（等待器等的是本轮没产出的 verdict）、#194（第 14 项没有计数地板） |
| `skill/pitfalls/report-field-parse-breaks/` | 一次事故 | `report/log/ISSUES.md` #331（首页身份句加了 Markdown 粗体，`ADJ_RNN` 跨不过 `**` ⇒ 判红抓到 0 句） |
| `skill/pitfalls/tcl-query-empty-means-broken-ruler/` | 反复出现的症状 | `report/log/ISSUES.md` #327（`catch` 存的是**返回码**，把成功的运行读成失败）、同族三次错结论记在同文件"Vivado Tcl 探针"那一族 |
| `skill/prompts/criterion-before-code/` | 量出来的差异 | 两次"先写判据"把我自己的错guessing 判红：`report/log/ISSUES.md` 里 #88/#147 那一段与 `sim/tb_icmp_rx_len.v` 的立案记录 |
| `skill/prompts/single-variable-ab/` | 量出来的差异 | 空白滚逐格复现基线 ⇒ `noise_ns=0.000`（件 `build/evidence/r115_*`），以及同一份 `opt.dcp` 重跑 place+route 逐位复现正式构建读数（件 `build/evidence/r117_d0/`） |
| `skill/prompts/report-to-bottleneck/` | 量出来的差异 | r117 的靶子重排：`build/evidence/r117_d0_console.txt` 量到真靶是 239 引脚广播网（FANOUT），不是先前指的 pblock |

**允许并保留"当时判断错了"的轨迹**（这是这一章最有说服力的部分）：

1. 断言"钩子让 `phys_opt_design` 失败" ⇒ 否掉它的实验：读回 `catch` 存的其实是返回码，改成
   `set rc [catch … emsg]` 后同一次运行是成功的（`report/log/ISSUES.md` #327；修法在
   `build/tcl/r117_post_place_hook.tcl`）。
2. 断言"C9 复制刀赢了"（快车道三格 +0.033/+0.187/+0.298）⇒ 否掉它的实验：官方构建跑完后
   严格名册显示含最紧两格在内四格变差（`docs/timing/ROUND_r117.md`、`report/TIMING_GLOBAL.md` §9）
   ⇒ 判负，钩子退回 env 门后（`IMPL_POST_PLACE_HOOK`）。
3. 断言"门禁 23 绿/1 红 里第二条红是文档坏了"⇒ 实际原因是我给 `ISSUES.md` 留的那份 `.md` 备份
   被 D5 当成交付文档扫（`report/log/ISSUES.md` #333）。教训不是"备份不该留"，而是
   **"我自己造的文件会进入尺子的射程"**，所以快照只落 `*.txt` 或直接交给 git。
4. 断言"负 slack 会读成数字"⇒ 实测那把尺子把负值读成 `null`，写对了也红（`report/log/ISSUES.md` #321），
   于是给尺子补了符号维而不是改文档。

## B. 如何验证有效

口径：**同一模型、同一上下文、同一工具版本，绕过/使用技能包各跑一次**（借 §3.1.5.2 的基线口径），
被控制的变量在记录里列全。协议与字段见 `skill/evals/README.md`，陌生人可照跑的复跑步骤见
`skill/evals/runbook.md`。

本章只写**实际做过**的运行，三态分开计数：

| 验证 | 命令 | 证据 | 状态 |
| --- | --- | --- | --- |
| 文本尺子的确定性（同一输入两次跑逐字节一致） | `node src/host/doc_enc_check.mjs` ×2、`node src/host/line_cite_check.mjs` ×2 | `skill/evals/raw/doc_enc_pass1.txt`、`doc_enc_pass2.txt`、`line_cite_pass1.txt`、`line_cite_pass2.txt`（`cmp -s` 逐字节一致） | 已复跑 |
| 装配门禁 G1–G12 真的会红 | `node skill/scripts/check/gates.mjs` | 首轮输出：G1 违规=13、G6 越界=3、G7 表列与实际不同源、G8 死链=4 —— 四条全部可复现，随后逐条判定"确实存在 / 是我的尺子维度错" | 已复跑（含红项） |
| 索引由目录生成、手改会被抓 | `node skill/scripts/check/gen_index.mjs --check` | 与写入后的 README 比对；不一致 exit 1 | 待验证（要等条目全部到位后跑一次 --check 才算过） |
| 判据 selftest 正反例 | `bash skill/scripts/selftest/run_all.sh` | 该脚本此刻不存在 ⇒ `NOT_MEASURED` | 待验证 |

上面第 2 行的处置结果本身是一次自我纠错的现场：G1 把赛题自己规定的 `README.md` / `SKILL.md` 大写名当成违规、
G7 的两个操作数取自两套"什么算条目"的定义（`gates.mjs` 与 `gen_index.mjs` 各数各的），
G8 把 `{a,b}.tcl` 这种简写记法当路径。**修法是把尺子的量纲改对（同一生成器、同一扩展名判据、大写专名白名单），
不是把地板调低**；改完之后仍然剩下的红（缺 `SKILL.md` 的条目、条目里的本队专有名、缺 selftest）一律保留为红。

## C. 边界如何确定

三分表（恒成立 / 平台相关 / 版本相关）：

| 层 | 内容 | 谁负责写清失效条件 |
| --- | --- | --- |
| 恒成立 | "先配能红的判据再改代码""三态判定""读不到 ≠ 通过""一条判据一行、判定放最后一个字段""差分判据成对" | 每条 `SKILL.md` 的第 2/3/6 节 |
| 平台相关 | 器件家族（7 系列 ↔ UltraScale+ ↔ Versal）、端口类型（TMDS_33 / 差分 / LVCMOS）、驱动形态（BD 的 AXI GPIO ↔ MIO）、缓存层级（PS 的 SLC/OCM ↔ 纯 PL） | 各条目第 3 节 + 第 8 节"迁移要改哪几处" |
| 版本相关 | Vivado/Vitis 2025.2.1 的报告字段位置、`report_methodology` 的 SUMMARY 形状、xsim 的 SystemVerilog 子集 | 各条目第 4 节写明版本，第 3 节写明"报告字段漂了就重新量形状" |

不写"适用于所有 AMD 器件"这样的话。迁移证据目前没有跨板卡记录，`skill/evals/migration/` 里
写的是**当前不具备迁移条件 + 需要什么**（第二块板卡或第二个可套用的子功能）。

## D. 大模型协作记录（同一章要求的另一半）

- 原始轨迹在本仓库里以两种形式存在：`report/log/ISSUES.md`（每条工具/判断事故，编号即时间轴）与
  `report/log/OVERNIGHT_LOG.md`（按小时的决策与读数）。本章引用它们的方式是**点名编号**，不转述成"我们讨论后决定"。
- 智能体工作流：本次交付本身由一个主 agent + 若干**只看文件、不共享上下文**的子 agent 完成，
  每个子 agent 的产物落进自己的目录（`skill/pitfalls/`、`skill/prompts/`、`skill/templates/`、
  `skill/runtime/`、`skill/scripts/`、`submit/`），主 agent 负责装配与门禁；
  子 agent 的自述一律当**待复核的断言**处理——这正是 `skill/scripts/check/gates.mjs` 存在的原因。
- 审计：第三方 AI 的审计提示词原样存在 `skill/prompts/`（见其中"交给审计员的提示词"那一节），
  审计报告回来后逐条判"确实存在 / 不成立 / 需裁决"，修完必须重跑 G1–G12。

## 本章依据的产物

`report/log/ISSUES.md`、`report/log/OVERNIGHT_LOG.md`、`docs/timing/ROUND_r117.md`、`docs/timing/ROUND_r118.md`、
`report/TIMING_GLOBAL.md`、`build/tcl/r117_post_place_hook.tcl`、`skill/README.md`、`skill/_meta/naming-and-format.md`、
`skill/_meta/sources.md`、`skill/evals/README.md`、`skill/evals/runbook.md`、`skill/evals/raw/`、
`skill/scripts/check/gates.mjs`、`skill/scripts/check/gen_index.mjs`

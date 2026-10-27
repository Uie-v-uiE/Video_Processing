---
name: symptom-router
description: 用于只知道自己"看到了什么现象"、不知道该从本包哪一条开始读时；也用于把别人报的症状快速分派给某个专业条目、或需要一条"这属于哪一类问题"的判据的场景。
---

# 症状路由表（先分派，再动手）

## 适用场景

拿到一句话现象（"屏幕上方有几行慢一帧""hold 余量像掷硬币""检查器全绿但现场还是坏"），
需要 30 秒内决定：这是时序、约束、运行时、尺子、包完整性，还是必须先问人的决定。
也用于派工——给一个 agent 或队员分派"这类活"时，条目名比口头描述可靠。

## 使用方法

按症状查表；**每一行的"先搜什么"是动手前的检索动作，不是可选项**（详见 `where-to-search`）。

| 症状 | 先读这条 | 动手前先搜 / 先确认 |
|---|---|---|
| 只盯最差路径，改完别处变差 | `timing/global-timing-roster` | 搜本工具按时钟域出摘要的命令；确认"别的域不许变差"的阈值 |
| 报告读不出瓶颈类型 | `timing/localise-worst-path` | 先用只读探针打印报告**形状**，再写解析 |
| 关键路径是深逻辑锥 | `timing/fix-logic-depth` | 先算这条锥的收益上限，再决定要不要开构建 |
| 布线占比高 / 某网扇出很大 | `timing/reduce-fanout-and-congestion` | 确认工具是否有复制驱动与扇出报告命令 |
| hold 读数每次构建都跳 | `timing/constrain-io-and-clocks` | 先查该端口是否根本没建窗（未检查≠满足） |
| 换了时钟来源后"时序突然变好" | `timing/clock-tree-changes-checklist` | 逐条按名回查点该时钟的约束是否还生效 |
| 板子加载后行为对不上仓库 | `runtime/overlay-load-and-verify` | 先确认读回身份的办法；确认允许刷写 |
| 写了寄存器读不回来 / 默认档不符 | `runtime/register-map-and-readback` | 先查该寄存器的读写属性与复位值出处 |
| 数据半新半旧、首块或尾块坏 | `runtime/dma-and-cache-coherency` | 先查本平台缓存维护操作的方向与对齐要求 |
| 偶发撕裂 / 慢一帧，负载相关 | `runtime/external-memory-bandwidth-account` | 先把所有竞争者列全再算账 |
| 现场只能靠眼睛判 | `runtime/board-liveness-readback` | 先问：这条允许人判吗？补读口要不要单独一轮 |
| 上位机常量与寄存器表不一致 | `runtime/host-bindings-from-contract` + `scripts/contract-to-host` | 确认表是唯一真源，代码由表生成 |
| 改前没红、改后不知赢在哪 | `verify/bench-expectations-first` | 先在**未改**的树上跑同一把尺子 |
| 检查器全绿但真实行为红 | `verify/checker-selftest` | 看夹具是否绕过了提取层；重跑真件 |
| 某判据从来没红过 | `verify/mutation-controlled-coverage` | 配一条能动变异对照，或标"未配对照" |
| 0 条比较却报通过 | `verify/three-state-verdicts` | 加计数地板；空集判 `NOT_MEASURED` |
| 比对结果对不上期望 | `verify/golden-reference-compare` | 查容差与豁免的键（必须按期望值作键） |
| 命令返回 0 却什么都没发生 | `pitfalls/tcl-and-probe-traps` | 打印集合大小与非空断言 |
| 一个 grep 命中就下结论 | `pitfalls/ruler-fake-greens` | 先证明那条分支可达 |
| 构建跑完结果与源不符 | `pitfalls/build-artifact-races` | 查在飞改源、孤儿进程、同名覆盖 |
| 文档改口后出现怪句/表格碎 | `pitfalls/doc-rotation-damage` | 每条规则断言行数或长度变化 |
| 数字对不上别处同名指标 | `pitfalls/constraint-coverage-loss` | 射程由遍历现算并打印每层计数 |
| 交付包被指"点名的件不在" | `pitfalls/package-integrity` | 跑 `scripts/repro-drill`，看死引用数 |
| 不知这一轮该产出什么 | `workflow/one-round-work-loop` | 确认本轮边界（只做一件事？） |
| 要改 RTL | `workflow/before-an-rtl-change` | 六项前置检查逐条读 |
| 要上板 / 刷写 / 动外设 | `workflow/before-touching-hardware` | 确认哪些动作需要用户同意 |
| 不知该先查哪份资料 | `where-to-search` | — |
| 不知哪些该问人 | `workflow/confirm-with-user-first` | — |

**用法约定**：这张表只做分派，不做结论。落到具体条目后，以该条目的
`使用方法`/`失效条件` 为准；表里没列出的症状说明本包还缺一条，按
`_meta/authoring-standard.md` 的四道门补条目并回填本表（漏列一条时索引检查会红）。

## 失效条件

- 症状描述本身就是结论时（"这就是约束问题"）——先把它还原成可观测现象再查表，
  否则你会顺着预设找证据。
- 多条同时命中：按"能伤硬件 / 不可逆"优先，其次"会让读数不可信"（尺子类），最后才是效率类。
- 表格与条目内容冲突时以条目为准；冲突意味着这条目改过而表没改，属于"改口没改完"，
  应跑一次全文对账（见 `pitfalls/doc-rotation-damage`）。
- 本表不覆盖架构级取舍（用什么器件、买什么板卡）——那是需要人定的部分。

## 已验证效果

未量过，属建议。自查方式：任取 3 条本表行，把"症状"原样作为唯一输入去问一个
没参与过的 agent，它应能只凭 `description` 命中同一条目；命中不一致就说明某条
`description` 写成了做法而不是触发条件。

## 来源

长自两类观察：① 报告里点名的问题与真实根因不同层（约束缺失 vs 尺子假绿 vs 设计缺陷），
需要一张"先分派"的表；② 派工时用口头描述导致同一症状被分派到不同条目。
表的结构借自外部技能框架里"按症状索引技能"的做法。

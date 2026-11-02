# 大模型协作记录

这份记录说明模型在项目中承担了什么、哪些建议被台架或板上读数修正，以及最后留下了哪些可复核的落点。它不是聊天摘抄，重点在“判断—验证—修正”的链条。

## 1 怎么读

1. `sessions/` 的六张卡按工作线分：架构、以太网、显示、时序、验证、交付。
2. `corrections.md` 是纠错轨迹，每条按“错误断言 → 否定它的实验 → 更正后的结论”写。
3. `prompts-used.md` 是实际用过的提示词，以及事后看哪些写法有效。
4. `workflow.md` 是主 agent 与只读子 agent 的分工和验收规则。
5. `metrics.md` 只记能从包内重算的数量；`redaction.md` 说明原始导出为什么不在包里。
6. `recent-cases.md` 是最后一批修正的索引。

## 2 角色

| 角色 | 负责 |
|---|---|
| 人 | 定目标、拍板架构、判断画面、上板验收、决定提交边界 |
| 主 agent | 读跨文件关系、改 RTL/PS/台架、跑检查、写文档、装配提交树 |
| 只读子 agent | 单点核查：找文件、查调用、审文档、比对报告；结论回到主 agent 复核 |

子 agent 的自述不作为完成证据。它说“改好了”不算数，主 agent 要打开文件、看命令输出、看判定行。

## 3 工作循环

```text
问题 → 读代码与证据 → 提出候选改法 → 改前判据先红
     → 打补丁 → 台架/实现/上板复验 → 记录边界
```

四条红线：

- 判据第一次跑就绿，要先怀疑激励是空集。
- 没有判定行的日志只算过程记录，不算通过。
- 模型生成的时序数字、板级读数必须回到报告或日志核对。
- 人眼验收、比赛模板和提交系统字段不交给模型。

## 4 证据落点

| 内容 | 位置 |
|---|---|
| 设计取舍与实现 | `report/design-report.md`、`src/rtl/`、`src/ps/` |
| 验证与判据 | `report/verification.md`、`sim/`、`sim/results/` |
| 时序、资源、功耗 | `report/optimization.md`、`build/reports/` |
| 板级读数 | `board/measured/`、`board/acceptance.md` |
| 关键 Issue 台账 | `report/issues/key-issues.md` |
| 技能包 | `skill/`、`report/skill-distillation.md` |
| 交付与复现 | `report/reproduction.md`、`README.md` |

## 5 脱敏

原始会话导出含本机路径、临时目录和工具输出，不随包。随包的是会话卡、提示词、纠错记录、工作流和指标；每一条结论都尽量落到包内可打开的文件或判定行。详见 `redaction.md`。

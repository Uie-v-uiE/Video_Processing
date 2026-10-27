# 文档写法：这套包按什么标准重写

这份说明写给审阅者和后续维护者。它解释为什么有些文档读起来像工程笔记，有些读起来像论文，以及哪些内容是故意保留的。

## 两条主规则

**第一，不要 AI 味。** 具体表现是：用顿号把一堆短句堆成一条长链；每段都用“一是、二是、三是”排比；用破折号加引号做金句收尾；每段都要拔高一句；括号里再套括号。这些写法看起来整齐，读起来累，而且会把工程判断藏进修辞里。改写后的文档用完整句子，长短交替，连接词用“因此、也就是说、需要说明的是、这里”，不用口号。

**第二，不写没人会读的数据。** 每一步的 ps 数、分频比、扇出计数、md5 前缀、字节数、编程耗时、位段清单、引脚清单、内部判据编号、百分比的百分比，这些数据对写作者有用，对读者没有用。保留的是评委真会问的数：分辨率、帧率、零丢包结果、延迟契约、资源百分比、通过和失败条数。数据表、命令表和接口表不受这条限制，因为它们本来就是查的，不是读的。

**第三，该展开就展开。** 把压缩从句拆成完整句子，字数会变多，这是对的。判断标准不是字数，而是“一个工程师会不会这样写”。如果一句话里塞了三个因果、两个括号和一个编号，读者得回读两遍，那就该拆。

## 哪些文档被重写，哪些没有

**读者向的正文被重写了。** 根 `README.md`、`README_EN.md`、`report/technical-report.md`、`report/innovation.md`、`report/01-overview.md` 到 `08-limits.md`、`report/README.md`、`report/background_and_novelty.md`、`report/ps_vs_pl.md`、`report/rotation_and_effects.md`、`report/demo_script.md`、`report/judge_qa_xiaosai.md`、`report/70-reproduce.md`、`report/technical-document-contest.md`、`board/README.md` 和 `data/README.md` 按上面的规则重写，数字更新到 r152。

**证据与过程记录保留原样，只加历史标记。** `report/known_issues.md`、`report/optimization_log.md`、`report/perf_report.md`、`report/timing_global.md`、`report/50-results.md`、`report/claims-vs-evidence.md`、`report/commands.md`、`report/repro-check.md`、`report/log/` 和 `report/collaboration/` 是台账、原始读数和会话记录。把它们按“好读”重写，等于改证据；所以只在开头标明它属于哪一轮，当前结论指向哪里。技能包 `skill/` 是通用条目，不是本项目报告，也不按本项目的数字改写。

**参考表保持表格式。** `report/interface-table.md`、`report/commands.md`、`data/metrics.csv`、`sim/README.md` 的台架清单，本来就是查表用的；它们需要准确和可检索，不需要散文。

## 当前与历史的分界

当前版本是 r162。凡是写“当前”“本版”“板上这一版”的地方，必须能指到 r162 的位流、报告或上板读数。历史台账在标题或开头注明它绑定哪一轮，读者不会把 r132 的 WNS 当成今天的数。

读不到、没测过、未验证的内容写“未测”或“未验证”，不写成“通过”。端到端时延、断电自启、高低温、PHY 眼图都属于这一类。

## 审阅清单

拿到一份文档，按下面几问过一遍：

1. 这段话一个工程师会不会这样写？有没有为了整齐而牺牲信息？
2. 每个数字都有读者吗？它在正文里回答了哪个问题？
3. “当前”的数是不是 r162？历史台账有没有标轮次？
4. 结论有没有证据路径？读不到的地方有没有写“未测”？
5. 表格和正文有没有互相矛盾？改了一处，另一处有没有跟着改？

五问都过，才算这份文档可以交出去。

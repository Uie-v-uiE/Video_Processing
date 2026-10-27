# 离线验证：没有板子、没有 Vivado 时能证明什么

## 适用范围

作品要写“已验证效果”，但手上此刻没有板子、没有对应版本的 Vivado，或者要在自己电脑上
先证明代码不是编造的。也适用于把技能包交给陌生队伍时，让对方在没有硬件的前提下复算
全部结论。

## 使用方法

三层，从弱到强，每层都必须带**能判红的阴性对照**：

| 层 | 工具 | 能证明 | 不能证明 |
|---|---|---|---|
| 语法/静态语义 | `scripts/api_lint.py` | API 名字与用法是否存在于 v3.1、偏移对齐、DMA 上限、缓存同步缺失、控制通路当数据通路 | 时序、真实性能、PL 行为 |
| 行为复算 | `scripts/run_offline.py` + `scripts/harness/pynq_stub` | 逐字错误串、对齐拒绝、TLAST 缺失导致永不出结果、漏 `sync_from_device()` 读到脏数据 | 硬件语义、并发、时钟 |
| 数据/工件 | `scripts/hwh_inspect.py`、`scripts/contract_gen.py`、`scripts/golden_compare.py`、`scripts/measure_report.py` | 地址与寄存器来自设计、生成代码可解析且不被误报、比对与豁免能挡住错误、占位数字不会被当成绿灯 | 设计是否正确实现算法 |

一条命令跑完并落证据：

```bash
python3 scripts/run_all.py            # 写 evals/results/tool_evidence.txt
python3 scripts/pkg_check.py --selftest   # 证明本包的自检规则真的能判红
```

`api_lint.py` 统计的是**比较次数**：输出
`checked=<N> red=<R>`，且 `N=0` 时退出码为 2（NOT_MEASURED），绝不用“没报错”冒充通过。
`assets/fixtures/bad/` 里 11 份错误样本由另一个会话独立写出（作者没有看到检查器与 API
面），`api_lint.py --self` 用它们的 `expected.tsv` 复算召回：静态召回 **10/11**，唯一漏检
被显式标为 `STATIC-OUT-OF-SCOPE`（TLAST 属于行为问题）。这 11 份样本写的是板上路径，在笔记本上多半 `NOT-EVALUABLE`，
`run_offline.py --self` 把它们排除在分母之外而不算成“检出”。

给新板卡/新工具版本扩展时：

```bash
python3 scripts/hwh_inspect.py your_design.hwh --require address --require registers
python3 scripts/api_lint.py assets/examples            # 正确示例必须保持 0 红
python3 scripts/pkg_check.py                           # 包结构自检
```

## 失效条件

- 桩件不是仿真器。它的 `NOT MODELLED` 清单写在
  `scripts/harness/pynq_stub/pynq/__init__.py`：真实时序、真实缓存行行为、device-tree、
  fpga_manager 编程、中断、内核地址重映射、PL 时钟使能。任何“桩件绿灯”都不能写成
  “上板验证过”。
- 桩件的 API 面来自 `scripts/api_surface.json`，钉在 PYNQ v3.1。镜像换成 4.0 或板子换成
  Versal 后，这份面必须重新取证，否则检查器会把对的代码判成错的。
- `assets/fixtures/hwh/*.hwh` 是**合成但按 schema 构造**的样本，不是 Vivado 输出（见
  `assets/fixtures/hwh/provenance.md`，其中有 U1–U13 未确认属性名清单）。用真实 `.hwh`
  跑一遍 `hwh_inspect.py` 才算完成板卡侧取证。
- 本包不依赖 Vivado，所以综合/实现报告里的数字（LUT、WNS）必须由使用者自己实测填进
  `metrics.csv`；`measure_report.py` 只保证判定形状与占位值不会蒙混。

## 已验证效果

2026-10-10 在本机实测（Windows / Python 3.12 / 无 Vivado / 无板），全部可由
`python3 scripts/run_all.py` 复算（输出与命令行一起写进 `evals/results/tool_evidence.txt`）：

```
selftest_stub: checked=28 red=0
checked=21 red=0
checked=21 red=0
checked=21 red=0
contract_gen --self: checked=12 red=0 PASS         # 含删属性阴性对照
golden_compare --self: checked=7 red=0 PASS            # 含失效豁免阴性对照
measure_report --selftest: checked=7 red=0 PASS        # 含占位值/缺失/重复阴性对照
mutations_red=21/24
hwh_fixture_check: checked=87 red=0 PASS
route_summary --self: checked=5 red=0 PASS             # 独立性这条规则的破坏样本，含「真发的对仍须可用」阴性对照
gated=22 deviations=4 probes=10
```

## 可发现性（路由）是怎么测的，以及为什么不能用一个数说话

`evals/route_eval.py` 有两种仪器，**必须分开引用**：

1. **词法代理**（BM25/余弦，CJK 字符二元组 + ascii 词）只测字面重合。它是**下界**，不是结论。
   构建它时测到两个会骗人的退化：只有 12 行时，恰好落在**单独一行**里的中文虚词二元组
   （还是、哪个、怎么）拿到最大 idf，一个词就决定了 16 条盲测里的 4 条；短行在同等重合下
   压过长行。修法是把 idf 换成从背景语料（`references/*.md`，不含任何题目答案）统计并按
   词频剔除通用词，`--no-background` 可以复现退化本身。
2. **语义路由**才是部署路径：`--dump-questions` 导出**去掉答案**的题面，交给只读过
   `SKILL.md`、没读过任何条目的全新代理去选，再用**同一份度量代码**判分
   （`--predictions evals/results/route_llm_post.jsonl`）。

三套标准答案的**权重不同**，本包按最低权重的那套说话：

| 集合 | 来历 | 能证明什么 | 词法 strict | 语义 strict（绑定到当前表的代理） |
|---|---|---|---|---|
| set1 | 路由器行文时参照 | 只作回归护栏，高分近乎同义反复 | 0.83 | 0.92（代理 i/k/l，NOT GATED：case #8 存在记录在案的歧义） |
| set2 | 盲写、之后被它的失败模式引导补过路由词 | 已退化成调参集，只报历史值 | 1.00 | 1.00（代理 i、k、l） |
| set3 | 改动之前盲写，改动期间未逐条看过 | **唯一能给改动作证的干净留出集** | 0.50 | 0.94（i）/ 0.89（k、l），三个代理都绑定了当前表的 sha256 |

`evals/route_summary.py` 的门禁取 set3 绑定代理里的**最差值** 0.89（取 max 就是让运气好的
读者替全表背书），并要求评分者一致性不低于 `agreement=` 0.95 这一档（实测
`route_summary: sets=3 routers=3 cert_strict_worst_of_N=0.89 agreement=0.98 distinct_reasons=100/100 PASS`，Cohen
κ 记在 `evals/results/routing_summary.md`）——一致性差说明表本身有歧义，任何一个代理的准确率
都不该单独引用。独立性是**审出来的**而不是假定出来的：每条预测必须带逐条 `reason`，两份文件
逐字节相同、或全部案例的理由一字不差，该对就从一致性统计里剔除（不是给它打 1.00）；绑定代理
只剩 1 个、或所有对都被剔除时，工具直接给 `agreement=NA` 与 `NOT_MEASURED`（退出码 2），
不会打印 1.00。`distinct_reasons=N/M` 把理由多样性一并印出来，读者自己看证据；而它只能证明
「没粘贴」，不能证明「两个人」，残余局限写在 `evals/routing_protocol.md` 第 5 节。否定题
（STM32 的两线总线、Vivado 时序收敛）在 set3 上三个代理都 2/2 拒答；set1 那条“PyPI 上叫
`pynq` 的串口库”曾有代理误路由，据此在 `SKILL.md` 的「不适用」里点名了这个同名陷阱。

一处流程缺陷留在这里当反面教材：语义代理 A/B 是在我改 `SKILL.md` 路由词的**同时**跑的，
严格说它们读的可能是改动前或改动后的表，所以之后重新冻结了一份快照再跑第三个代理
（`route_llm_post.jsonl`）。并发修改评测对象是无效测量，不是小瑕疵。

## 来源

`scripts/api_surface.json`（v3.1 取证表，含 27 条“名字不存在”条目与逐字错误串）、
Xilinx/PYNQ tag v3.1 源码、PYNQ v3.1 文档、`assets/fixtures/hwh/provenance.md`。

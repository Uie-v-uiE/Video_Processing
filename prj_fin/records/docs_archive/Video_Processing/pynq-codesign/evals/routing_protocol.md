# 路由证据的复现协议（evals/routing_protocol.md）

这份文件的存在理由：`evals/results/route_llm_*.jsonl` 是**大模型代理**产出的，不是脚本产出的。
不写清协议，评审看到的就是「凭空多了三个文件，然后它们给自己打了 0.94」——那是自我打分，
不是证据。下面把「谁读了什么、按什么指令答、怎么判、哪里不可信」全部落在纸上。

## 0. 一句话

题目由盲写会话出，答案由**只读过 `SKILL.md`** 的全新代理选，判分用 `evals/route_eval.py`
里同一套度量代码，汇总与门禁用 `evals/route_summary.py`（取三个代理的**最差值**）。

## 1. 出题（谁写的答案表，凭什么盲）

三套 `evals/routing_heldout{,2,3}.tsv`，每套的来历与权重见 `references/offline-verification.md`
的路由小节。要点：出题会话只拿到竞赛指南 3.3 节选 + 12 个条目**文件名**（不含任何描述、
不含路由表文字），并被要求把问题写成「凌晨一点崩溃的学生口吻」、**故意回避**术语。
每套含 2 条否定题（非 AMD MCU 外设、Vivado 时序收敛），期望答案是 `NONE`。

三列格式：`问题 <TAB> references/<file>.md <TAB> 依据（含可选 ALT:references/<other>.md）`。
`ALT:` 由出题者自己标注「另一个也算对」，用来把「表格确有二义」与「路由错了」分开计：
`strict` 只认首选，`acceptable` 认首选 ∪ ALT。

## 2. 导出题面（保证看不到答案）

```bash
python3 evals/route_eval.py --cases evals/routing_heldout3.tsv --dump-questions evals/results/questions3.txt
```

输出 `id<TAB>问题`，**不含**答案列；`--dump-questions` 遇到已存在的目标文件会**拒绝覆盖**
（退出码 1），防止把陈旧答案喂给新代理。`evals/results/questions{,2,3}.txt` 就是这三份被
剥掉答案的题面，也是路由代理唯一被允许读的题面。

## 3. 路由代理的指令契约

给每个代理的指令等价于下面这段（措辞可换，约束不可少）：

- 你是 skill loader。读 `SKILL.md`（或它的一份**冻结快照**），包括 `何时使用`/`不适用`。
- **禁止**打开：`references/` 下任何文件、`README.md`、`assets/`、`scripts/`、任何名字含
  `heldout` 的文件、任何 `routing_report*` / `ab_*` / `tool_evidence.txt` / 别人的 `*.jsonl`。
  想开条目来消歧义 = 禁止；歧义本身就是被测量的东西。
- 每题给 `choice`（12 个 `references/*.md` 之一，或 `NONE`）、`second`、`confidence`，
  并且**必须**给一条 `reason`：一句话说清「凭 `SKILL.md` 的哪一行选它」。`reason` 是独立性的
  唯一可审痕迹——只有标签的两份文件无法与「一份文件改个名字」区分。随包文件里这条理由写作
  `why`（同义，工具两个键名都认）；缺任何一条，`route_summary` 直接 `NOT_MEASURED`（退出码 2），
  不给一致性数字。`NONE` 由代理依 `不适用` 自行判断，既不假定「每题都有答案」，也不因题目难
  就答 `NONE`。
- 产出 `evals/results/route_llm_<tag>.jsonl`：50 行、`{"set","id","choice","second",
  "confidence","reason"}`、按 (set,id) 排序、id 覆盖 1:0-13 / 2:0-15 / 3:0-19。
- 交回前自检：行数、JSON 可解析、`choice`/`second` 拼写合法、无重复、id 齐全；
  并**如实报告**是否违反过禁令。

判 `NONE` 的正确性时，`route_eval.py` 在语义模式下用「是否漏进答案」而不是词法分数阈值，
因为分数概念在这里不存在。

## 4. 判分与汇总

```bash
python3 evals/route_eval.py --cases evals/routing_heldout3.tsv \
  --report evals/results/routing_llm_report3.md --predictions evals/results/route_llm_post.jsonl
python3 evals/route_summary.py
```

`route_summary.py` 复用 `route_eval.py` 的 `evaluate/summarise/verdict_of`，所以汇总里的数
与各套单独跑的数不可能各说各话。它还计算两两代理的 exact-choice 一致率与 Cohen κ
（表太歧义 → 一致率低 → 任何单个代理的准确率都不该被引用）。门禁：
`set3 三代理最差 strict ≥ 0.75` **且** `一致率 ≥ 0.6`。

一致性之前默认「两个文件就是两个人」。这个默认被实测推翻过：把 `route_llm_g.jsonl` 复制成
`route_llm_h.jsonl`，工具照样给一致性 1.00 并判 PASS——一份工作交两遍就能过独立门。所以现在
`route_summary` 在算 κ 之前先审独立性，审不过就**剔除这一对**（不是给它打 1.00）：

1. 两个文件逐字节相同（sha256 相等）；
2. 或者全部共同案例的 `reason` 一字不差（重新序列化过、字节不同的粘贴也一样能抓出来）；
3. 或者任何一条绑定预测没有 `reason`——这时候根本没有可供审计的痕迹，直接 `NOT_MEASURED`。

所有对都被剔除时判定为 `NOT_MEASURED`（退出码 2），只有一个绑定代理时同样是 `NOT_MEASURED`，
绝不打印 1.00。判定行同时打印 `distinct_reasons=N/M`（最薄的那一对上，去重后的理由数 /
两个代理的理由总条数），读者可以自己去 `routing_summary.md` 的成对表里核对。
`skill_sha256` 绑定（预测必须带当前 `SKILL.md` 的指纹，否则降级为历史数据）行为未改，实测有效。

## 5. 已知缺陷与不可信之处（不许删）

1. **代理与作者同族**。路由代理与本包作者是同一模型家族，一致性只证明「表格不歧义」，
   不排除共享先验。真实部署里读表的可能是别的模型，本包没有跨家族复现。
2. **并发修改评测对象**。`route_llm_a.jsonl` / `route_llm_b.jsonl` 是在我改写 `SKILL.md`
   路由行的**同时**跑的，严格说它们读的可能是改动前或改动后的表——所以事后冻结了
   `SKILL.md` 的一份快照另跑第三个代理（`route_llm_post.jsonl`）。教训写在这里：评测期间
   必须给代理一个快照，改动与测量不能并发。A/B 只作「改动前」的历史参考。
3. **词法代理会骗人**，两种方向都会。12 行小表上，恰好只落在一行的中文虚词二元组会拿到
   最大 idf 并决定 4/16 条盲测；`--no-background` 可复现该退化。修好后 set3 词法仍只有
   0.50，而真实部署路径 0.94~1.00——所以本包把词法定为**下界**，不参与通过判定。
   这是文档里唯一一处「一个指标显著低于另一个」，把它当缺陷读还是当校验读，评审自己判断。
4. **样本量**。n=14/16/20，否定题各 2 条。够用来发现「表格根本指错方向」，不够用来支撑
   任何小数点后的比较；0.92 与 0.94 之间的差别不应被解读成任何事。
5. **题目同源风险**。三套题都由会话按同一份指南节选出，题型分布偏向指南 3.3.2 列举的
   方向（Overlay / register_map / DMA / 软硬件划分）；真实提问可能落在别处，本包的
   `何时使用` 已声明不覆盖哪些。
6. **独立性检查只能证伪，不能证实**。第 4 节排除的是「粘贴」——逐字节相同、或逐条理由一字
   不差。它**不能**证明两份 `reason` 出自两个独立作者：同一模型家族分两次作答，理由会写得
   处处不同、选择却处处相同，`distinct_reasons` 照样满格、一致性照样 1.00。
   要把独立真正钉死，只能换一个模型家族或换人重跑一遍（见本节第 1 条），本包没有做到这一步，
   所以一致性在这里读作「没有互相抄」，不读作「两个人各说各话」。

## 6. 换题目/换板卡时怎么复用这套协议

出题会话、路由代理、判分脚本三者解耦：把 `--cases` 换成自出的 tsv，`--dump-questions` 重新
导出剥答案题面，让代理只读**你那份** `SKILL.md`，再 `--predictions` 判分。
唯一必须一起搬走的是 `route_eval.py`（度量）与本文件（禁令契约）；`references/` 不必搬。

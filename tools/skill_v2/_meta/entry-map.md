# 条目地图（技能包的"哪些活需要技能"清单）

写条目的唯一入口。每个条目**先读 `_meta/authoring-standard.md`**，再按本文件对应行写。
本文件同时是"提炼过程"的证据：每条给出**它长自哪一类观察**（通用表述，不写轮次号、不写工程名）。

约定：条目路径 = `<类别>/<name>/SKILL.md`；`name` = 目录名 = frontmatter `name`；
索引行格式 = `` | `类别/name/SKILL.md` | 一句话（什么时候用） | ``（README 双向一致是机器判据）。

## workflow（顺序纪律与提示词工作流）

| name | 这条解决什么 | 长自哪一类观察 |
|---|---|---|
| start-a-fpga-project | 拿到题目到"能综合出第一版位流"之间的最短路径 | 多次发现前期没查器件资源上限与板级时钟归属，后期全是返工 |
| research-before-code | 动手前该查什么、查到什么程度、怎么记出处 | 把模型记忆当事实写进文档，被厂商文档页码打脸；NDA 材料不能引但二手转述可以，边界要写清 |
| confirm-with-user-first | 哪些决定必须问人、怎么问才可被一次否决 | 自作主张改外观/口径/演示顺序被打回；也有一味确认把能定的事拖了一轮 |
| one-round-work-loop | 一轮的标准节拍与产出物清单 | 长夜里"改了但没量""量了但没落件""落件但没改口"三类断链反复出现 |
| before-an-rtl-change | 改 RTL 前的六项前置检查 | 无台架先改、构建在飞时改源、回滚说不清（位流从没进版本库那次） |
| before-touching-hardware | 上板、刷写、外设操作前的前置与禁区 | 无工具链却写了"板上已修复"；串口被别的进程占用；只读寄存器被当可写；改板载存储未经同意 |

## timing（时序与约束）

| name | 这条解决什么 | 长自哪一类观察 |
|---|---|---|
| global-timing-roster | 为什么必须按域出名册而不是只修最差路径 | 只看 WNS 会采纳"局部变好、别处变差"的改动；相对余量比绝对值更适合跨周期比较 |
| localise-worst-path | 读 `report_timing` 定位瓶颈类型 | 报告字段（各级延迟、逻辑/布线占比、时钟树分量）形状靠猜错过三次判读 |
| fix-logic-depth | 锥太深的标准修法与收益上限先算 | 拆锥/插拍之前没算过"这条路最多能抬多少"，白花构建时间 |
| reduce-fanout-and-congestion | 高扇出与拥塞的识别与机制证据 | 复制驱动"机制动了但时序没赢"；没区分机制判据与结果判据 |
| constrain-io-and-clocks | I/O 窗、时钟、不确定度、异步组的建立顺序 | 出货流程里没有 input/output delay 却报出好看的 hold；把单向扩散量当双边窗 |
| clock-tree-changes-checklist | 动 MMCM/BUFIO/BUFR/重新源化的清单 | 换钟后三条点名该钟的约束静默失效，把"覆盖面丢失"当成收益 |

## runtime（片上运行时范式，Pynq 类流程通用）

| name | 这条解决什么 | 长自哪一类观察 |
|---|---|---|
| overlay-load-and-verify | 位流/可重构设计加载与校验的最小闭环 | 只 program 不读身份 ⇒ 板与仓库对不上；重载会把 PS 楔死需知恢复路径 |
| register-map-and-readback | 一张 register_map 撑起写/读/文档/台架 | 写了寄存器没读回口 ⇒ 现场无法自证；默认值与文档默认档不一致 |
| dma-and-cache-coherency | DMA 搬运 + 缓存一致性的封装与错案定位 | 数据"半新半旧"、首块坏尾块坏，全是 clean/invalidate 方向与对齐问题 |
| external-memory-bandwidth-account | 外存带宽预算与竞争者清点 | 两个通路抢同一块内存导致画面撕裂，先算账就看得见 |
| board-liveness-readback | 板级在线判活与可观测量上引 | 串口分词陷阱、无回显时的替代读数、"命令成功≠状态改了" |
| host-bindings-from-contract | 从接口契约生成主机侧调用与测试骨架 | 手工维护主机代码与寄存器表长期漂移，必须同源生成 |

## verify（尺子）

| name | 这条解决什么 | 长自哪一类观察 |
|---|---|---|
| bench-expectations-first | 先按现代码推期望、在**未改**树上跑绿 | 两次"改前红"其实是我猜错期望，DUT 是无辜的 |
| golden-reference-compare | 黄金参考比对的容差、豁免、空集规则 | 豁免名单按被测信号 key ⇒ 把别的用例买通了；零样本分支真空通过 |
| checker-selftest | 每个检查器自带 --self 与变异对照 | 收紧判据后没重跑真件；`--self` 全绿而真实行为红（夹具绕过了提取层） |
| three-state-verdicts | PASS/FAIL/NOT_MEASURED 与计数地板 | "没扫到"被写成通过，是本项目最大的一族账 |
| mutation-controlled-coverage | 正对照必须能动、覆盖维度要同现 | 一个"永远绿"的判据掩盖了未刺激的维度组合 |

## rtl（写法纪律）

| name | 这条解决什么 | 长自哪一类观察 |
|---|---|---|
| cdc-and-async-discipline | 跨域：单口、灰码、同步链、属性 | 报告点名≠真混域，也≠真没事；要看例化者与落点归属 |
| reset-and-clocking-plan | 复位策略、时钟域归属、上电初值 | 靠"上电值"修状态机被工具折叠；复位清单与实际寄存器数不符 |
| width-and-overflow-audit | 位宽/截断/越界要有可算的界 | 六处"能算的界"没断言，全部变成现场现象才被发现 |
| resource-vs-timing-tradeoffs | 资源换时序的实测与代价面 | BRAM 换 setup 量下来被判负；部分收益要写清归因来源 |

## prompts（可直接粘贴的提示词模板）

| name | 这条解决什么 |
|---|---|
| algo-to-hw-sw-partition | 从算法描述推导软硬件划分 |
| synthesis-report-bottleneck | 从综合/实现报告定位瓶颈并要求给可验判据 |
| spec-to-rtl-checklist | 从接口规格反推 RTL 骨架与待定项 |
| review-adversarially | 让另一个模型审计产出，规则式、逐条给件、禁编造 |

## pitfalls（踩坑清单：触发条件/现象/定位步骤/根因/修法/预防）

| name | 这条解决什么 |
|---|---|
| tcl-and-probe-traps | 探针自己骗你（空集、过滤读空、属性不存在、报告形状靠猜） |
| ruler-fake-greens | 尺子的假绿（空集、X 当 0、单位不同相减、射程漂移、把通过数当比较数） |
| build-artifact-races | 构建与证据件的竞态（改在飞脚本、0 字节日志、孤儿进程、同名覆盖） |
| doc-rotation-damage | 批量改口对文档的破坏（截断、破表、打断可跑命令、行号漂移） |
| constraint-coverage-loss | 约束射程静默收窄（改名、重源化、生成时钟、命令里一个错名全线空转） |
| package-integrity | 交付包完整性（死链、绝对路径、点名件未随包、自删暂存、空目录） |

## templates（案例模板）

| name | 这条解决什么 |
|---|---|
| project-skeleton | 目录骨架 + 最小可构建脚本 + 报告落点约定 |
| round-diary | 一轮的记录模板（立案/尺子/件/差分/结论/欠账） |
| claims-vs-evidence | 声明—证据对照表（每行有件或标未核） |
| acceptance-and-eye-check | 验收与眼睛判据配方（命令 + 前置 + 每个"否"的含义） |

## scripts（校验脚本：件 + fixture + --self，三件套齐了才算数）

| name | 这条解决什么 |
|---|---|
| gate-runner | 多判据门禁跑批：三态、判 N 项、红即非 0 退出 |
| golden-compare-tool | 文本/CSV 黄金比对（容差 + 按期望 key 的豁免 + 计数地板） |
| metrics-collector | 从综合/实现报告自动采集资源与时序 ⇒ 指标表 + Markdown 报告 |
| contract-to-host | register_map（表）⇒ 主机头文件/脚本常量/测试骨架，同源生成 |
| repro-drill | 复现演练：文档点名的件是否真在盘上、命令是否能对上目录 |
| evidence-ledger | 证据台账：把每轮的件、命令、读数、结论落成一个可核对文件 |

## references（速查表：先分派、先查哪儿）

| name | 这条解决什么 |
|---|---|
| symptom-router | 只知症状时，30 秒内决定这属于哪一类问题、该读哪条、动手前先搜什么 |
| where-to-search | 四类事实对应的一手出处、引用记法、二手转述与受限表格的边界 |

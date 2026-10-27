# 技能包 v3：与大模型协作做 FPGA / 数字设计

一句话：把一轮真实 FPGA 工程里被反复纠正的做法写成**别人能直接用**的条目。
判它好坏只看一件事——一支没参与过的队伍拿到这个目录，能不能不问原作者就用在**自己的题目**上（§3.3.5.2）。

## 30 秒接入

1. 整目录放进你的工程。正文是纯文本，三件工具只依赖 Node，没有安装步骤。
2. 先读 `symptom-router/SKILL.md`：手上只有症状时，用它决定读哪条、动手前先搜什么。
3. 按需加载单条；要细节再打开该条目自带的 `references/`，要判据就运行它的 `scripts/`。
   不要一次读整包（29 条正文 ≈ 57k 字符，一次读进来就把三级加载省下的预算全花掉）。

条目是**一层布局**：`<条目名>/SKILL.md`。分组不靠目录、靠 frontmatter 的 `metadata.kind` / `metadata.topic`，
因为"两层嵌套目录会不会被发现"没有任何实现担保；分派关系由下面的索引现算。

## 术语（本包自造词，先定义再用）

| 词 | 含义 |
| --- | --- |
| 尺子 | 一个能输出判定词的机器判据（脚本、台架、门禁） |
| 判红 | 尺子给出 `FAIL`；一条从不判红的尺子等于没有 |
| 三态 | `PASS` / `FAIL` / `NOT_MEASURED` 三种判定 |
| 未测 | `NOT_MEASURED`：没做成比较（空集、读不到、解析失败、格式不含该维度） |
| 地板 | 一条判据要求的最低比较次数；地板要能调高来验证它会红 |
| 射程 | 一次扫描实际覆盖的对象集合；射程变窄是静默失效 |
| 真空通过 | 比较数为 0 却报通过 |
| 证据件 | 落盘、可复跑、带命令与版本或被引结论的文本件 |
| 落件 | 把读数写成证据件 |
| 改口 | 把引用旧数字/旧命名的地方全部改掉 |
| 改前红 | 在**未改动**的树上跑新判据得到的红，作为本轮凭据 |
| 台架 | 能自动判定通过与否的仿真或上板测试 |
| 变异对照 | 故意注入缺陷、验证判据会红的那一次运行 |
| 名册 | 按时钟域逐条列出的时序余量表 |
| 门禁 | 一次改动要同时通过的多条判据 |
| 快车道 | 不动源码、不开整轮构建就能拿到对照读数的便宜路径 |

## 适用范围 / 使用方法 / 失效条件 / 已验证的复用结果

**适用范围**：与题目、器件、EDA 版本解耦的协作纪律与判据形状；条目内路径都相对本目录，
命令只点到工具名与开关。赛事 §3.3.2 点名的五类通用技能（Overlay 加载与校验、寄存器映射范式、
DMA 与缓存一致性、接口契约→主机侧代码、黄金参考与资源采集工具）都有对应条目，
其中 PYNQ 那四条**接口事实核到官方文档与源码、但未在本队板卡实跑**——各自的
`已验证效果` 都明写了这一点，引用前请按那条给的配方现做一次。

**使用方法**：上面 30 秒接入三步；写作与改条目的规矩见 `_meta/authoring-contract.md`。

**失效条件（整包级，四条）**

| 什么变了 | 要做什么 |
| --- | --- |
| 换 EDA 主版本 | 命令形状类条目（`depth-vs-routing-cut`、`io-clock-constraints`、`vivado-tcl-probe-traps`）要先重跑再引用 |
| 换 PYNQ 大版本 | 接口名与默认值在两代之间不兼容甚至相反，先跑条目里给的探测配方 |
| 工程没有可回读口 | `board-liveness-readback` 与 PYNQ 那组退化成 checklist，先建回读口 |
| 你的判据名与本包不同 | `ruler-teeth-and-empty-sets` 讲的是"这把尺子会不会漏判"，检查项名字要换成你自己的 |

**已验证的复用结果**（三条命令，读数可复跑；数字随条目增删而变，别抄这里的数，自己跑一遍）

```bash
node _meta/check-package.mjs .          # 结构：五节齐、通用性、索引现算、每条有评测用例、术语已定义
node _meta/check-package.mjs . --self   # 上面那把尺子自带的能红对照（含"带声明就不该报"的正对照）
node evals/route-eval.mjs .             # 症状→条目 的词面命中率；--self 证明它能红
```

本包当前实跑读数：条目 29；`check-package` 逐条与全包判定全绿（红 0、未测 0），其自测 `判 25 项 不符=0`；
`route-eval` 自测 `判 4 项 不符=0`，真实评测 `判 35 项 正例=30 top1 命中=29 top3 命中=29 命中率=96.7% 负例=5/中5`
（唯一未命中的一条是"报告被自己的遍历扫进射程、自指读数"，它被词面派到了 `io-clock-constraints`；这是**已知未修**，不当成已验证）。两件工具：`contract-to-host-bindings` 自测 `判 8 项`、`golden-frame-compare` 自测 `判 7 项`。

没被证明的东西也写清楚：**增益**（带这条 vs 不带这条，少走多少弯路）没量过，测法与门槛见 `evals/gain-ab.md`；
**陌生人演练**只做了自检，没做过"没参与过的人照条目走一遍"。这两项是本包的已知缺口，不写成已验证。

## 赛题四型的对应关系（§3.3.5.2）

| 赛题型 | 本包条目（`metadata.kind` 就是这个值） |
| --- | --- |
| 提示词工作流 | 三条 `prompt-*` 可粘贴模板 + `round-work-loop` / `start-to-first-bitstream` / `ask-before-irreversible` / 各方法条目 |
| 案例模板 | `contract-to-host-bindings` 的表模板、两条工具条目的用法形状 |
| 校验脚本 | `contract-to-host-bindings`、`golden-frame-compare`、`_meta/check-package.mjs`、`evals/route-eval.mjs` |
| 踩坑清单 | `ruler-teeth-and-empty-sets`、`doc-rotation-damage`、`delivery-package-integrity`、`artifact-provenance-binding`、`clock-change-constraint-reach` 等 |

## 索引

由 `_meta/build-index.mjs` 从条目现算；手写清单会随目录变深静默变窄，所以这一段不许手改。
判据 `I1` 直接把 README 里这段与现算结果逐字比对，不一致就红。

<!-- INDEX:BEGIN -->

### 提示词工作流（赛题 §3.3.5.2 四型之一）

| 条目 | 什么时候用 | 领域 | 带 references / scripts |
| --- | --- | --- | --- |
| `anchor-bench-before-edit/SKILL.md` | 要改 RTL、台架或生成脚本却还没有任何能红的判据时 | 验证与台架 | — / — |
| `ask-before-irreversible/SKILL.md` | 下一步要做不可逆或对板载存储有副作用的动作、要改动人会直接看到的画面与演示顺序、或决定带有许… | 流程纪律 | — / — |
| `board-liveness-readback/SKILL.md` | 上板调试或现场演示时需要不重启、不复跑整批测试就判断"板载程序还活着吗、状态真的改了吗"，或… | 片上运行时 | — / — |
| `depth-vs-routing-cut/SKILL.md` | 时序报告的判读结论是"这条路要么太深要么太挤"、准备插拍或加资源换速度之前 | 时序与约束 | 有 / — |
| `external-memory-bandwidth-account/SKILL.md` | 判断片外存储/主存的带宽是否够用，或出现画面撕裂、整帧慢一拍、偶发丢样、"只在别的通路忙时才… | 片上运行时 | — / — |
| `global-timing-roster/SKILL.md` | 时序改动跑完需要判断收益是全局的还是"拆东墙补西墙"时 | 时序与约束 | — / — |
| `io-clock-constraints/SKILL.md` | 给对外接口建立时钟与输入/输出窗时 | 时序与约束 | — / — |
| `prompt-adversarial-review/SKILL.md` | 把已完成的产出交给另一个模型或会话审计时 | 判据与尺子 | — / — |
| `prompt-algo-to-hw-partition/SKILL.md` | 拿到一段算法描述就要决定哪些运算落硬件、哪些留软件，而吞吐需求、延迟预算与片上存储的账还没算… | 流程纪律 | — / — |
| `prompt-report-to-bottleneck/SKILL.md` | 综合与实现报告已经跑出来、报告读不出瓶颈类型、要定位它属于哪一类原因时 | 时序与约束 | — / — |
| `pynq-overlay-load-verify/SKILL.md` | 在 PYNQ 里加载 Overlay 之后需要证明"板上跑的确实是这份产物"时 | PYNQ | 有 / — |
| `pynq-register-map-readback/SKILL.md` | 给可编程逻辑侧寄存器定稿、需要用 `register_map` 写主机侧读写、或出现"文档写… | PYNQ | 有 / — |
| `round-work-loop/SKILL.md` | 开始一轮 FPGA 改动、需要把"改了什么、拿什么证明、结论落在哪件上"一次钉死时 | 流程纪律 | — / — |
| `start-to-first-bitstream/SKILL.md` | 接手一个新题目后不知从哪一步下手、第一版位流迟迟跑不通、约束与顶层反复返工时 | 流程纪律 | — / — |
| `symptom-router/SKILL.md` | 只知道"看到了什么现象"、不知道该从本包哪一条读起时 | 速查 | — / — |
| `three-state-verdicts/SKILL.md` | 编写或修改任何判据、门禁、比对脚本需要规定输出形状时 | 判据与尺子 | — / — |
| `width-and-overflow-audit/SKILL.md` | 出现截断、越界、回绕、饱和这类数值边界行为，或位宽与深度由参数推导、结果与软件参考对不上时 | RTL | — / — |

### 案例模板（赛题 §3.3.5.2 四型之一）

| 条目 | 什么时候用 | 领域 | 带 references / scripts |
| --- | --- | --- | --- |
| `project-skeleton/SKILL.md` | 新开一个 FPGA/数字设计工程、或接手他人散乱工程，需要先把目录骨架、一条命令跑完的构建脚… | 流程纪律 | — / — |

### 校验脚本（赛题 §3.3.5.2 四型之一）

| 条目 | 什么时候用 | 领域 | 带 references / scripts |
| --- | --- | --- | --- |
| `contract-to-host-bindings/SKILL.md` | 接口契约表（寄存器 + 位段 + 单位 + 责任方）已定稿、需要主机侧调用代码与测试骨架跟着… | 片上运行时 | — / 有 |
| `golden-frame-compare/SKILL.md` | 手里有一版黄金参考文本（逐行输出、CSV、报告摘录、帧统计）需要机器判定"这轮输出与期望是否… | 验证与台架 | — / 有 |

### 踩坑清单（赛题 §3.3.5.2 四型之一）

| 条目 | 什么时候用 | 领域 | 带 references / scripts |
| --- | --- | --- | --- |
| `artifact-provenance-binding/SKILL.md` | 把"报告/位流/日志"与"产生它的那棵树"绑起来时 | 验证与台架 | — / — |
| `cdc-and-async-reg/SKILL.md` | 设计里出现两个及以上时钟域、或复位与数据来自异步源，静态检查报出成串跨域警告、上板出现偶发单… | RTL | — / — |
| `clock-change-constraint-reach/SKILL.md` | 新建时钟、插入 MMCM/PLL、把某个钟重新源化、改时钟或端口名之后 | 时序与约束 | — / — |
| `delivery-package-integrity/SKILL.md` | 要把交付包/发布目录打包、剪枝、核对完整性时 | 流程纪律 | — / — |
| `doc-rotation-damage/SKILL.md` | 一轮里要把措辞、命名或口径贯穿到许多文档、清单、注释与提交信息时 | 流程纪律 | — / — |
| `pynq-dma-buffer-coherency/SKILL.md` | 给 PYNQ 的 AXI DMA / AXI CDMA 写搬运封装，或出现"数据半新半旧""… | PYNQ | 有 / — |
| `pynq-video-frame-pipeline/SKILL.md` | 用 PYNQ 的帧通路（AXI VDMA / HDMI 包装层）跑图像时 | PYNQ | — / — |
| `ruler-teeth-and-empty-sets/SKILL.md` | 新写或修改任何检查器/门禁/导出脚本之前，或出现"自检全绿但真实运行红""某条判据从来没红过… | 判据与尺子 | — / — |
| `vivado-tcl-probe-traps/SKILL.md` | 写探针或脚本查询网表对象、读取属性、解析工具报告时，出现"命令返回 0 却什么都没发生""没… | 速查 | — / — |

<!-- INDEX:END -->

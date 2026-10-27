# `report/` 导读

`report/` 放四类东西：给评委读的报告、支撑结论的读数、复现说明，以及过程记录。三类文档的性质不同，读法也不同。第一类是结论，第二类是证据，第三类是账本；账本里的数字只对当时那一轮构建负责，不能拿来当当前值。

**当前版本的结论在 [`technical-report.md`](technical-report.md)。** 它把问题、架构、几何、可观测性、时序、验证和落地写在一份正文里。`01` 到 `08` 是按主题展开的章节，内容与正文一致，细节更多。两者冲突时以正文的取舍为准，再回到分章章节核对证据。

## 评委的阅读顺序

1. [`../README.md`](../README.md)：项目是什么、三条可当场验的承诺、当前读数。
2. [`technical-report.md`](technical-report.md)：完整技术报告。
3. [`innovation.md`](innovation.md)：一页纸的创新点与落地方向。
4. [`demo_script.md`](demo_script.md)：现场演示怎么敲、看到什么算通过。
5. [`judge_qa_xiaosai.md`](judge_qa_xiaosai.md)：常见问题的回答口径。
6. 需要追问细节时，再按下面的主题表翻。

这份包的写法标准写在 [`writing-style.md`](writing-style.md)：读者向正文按“说人话、不堆没人读的数据”重写，证据台账保留原样并标明轮次。重写范围、导出内容与检查项在 [`doc-audit.md`](doc-audit.md)。

## 按问题找文档

### 想从头学一遍、或把项目喂给网页 AI

| 文档 | 回答什么 |
|---|---|
| [`architecture_learning_guide.md`](architecture_learning_guide.md) | 十四章学习手册：从像素与时序讲起，到几何、插值、效果链、CDC、验证、调试和从原型到产品 |
| [`project_teardown_and_bugfix.md`](project_teardown_and_bugfix.md) | 整体拆解与 13 个缺陷案例的修复过程，按“现象、根因、判别、修法、证据”写，可直接作为问答语料 |
| [`innovation_and_landing.md`](innovation_and_landing.md) | 创新点、亮点、带宽账、真实落地场景与适用边界、答辩口径 |
| [`contest_requirements_map.md`](contest_requirements_map.md) | AMD 赛道 3.3.5.1–3.3.5.5 逐条对照、命名要求与提交清单 |
| [`poster_variants.md`](poster_variants.md) | 四个海报候选的尺寸、风格、适用场合与选用口径 |

### 项目是什么、为什么这样做

| 文档 | 回答什么 |
|---|---|
| [`01-overview.md`](01-overview.md) | 板子做什么、三个工程问题、关键数字、三项可复核主张 |
| [`background_and_novelty.md`](background_and_novelty.md) | 同类做法与本项目形态的差别，创新点从哪里来 |
| [`abstract_contract.md`](abstract_contract.md) | 已提交的作品简介，作为合同逐句对照现场能否兑现 |
| [`ps_vs_pl.md`](ps_vs_pl.md) | 为什么像素通路放在 PL，PS 只做什么 |

### 怎么搭、怎么算

| 文档 | 回答什么 |
|---|---|
| [`02-architecture.md`](02-architecture.md) | 数据流、时钟域、片源仲裁、DDR 乒乓、控制面 |
| [`03-algorithm.md`](03-algorithm.md) | 几何逆映射、双线性、六级效果链、OSD、打包 |
| [`rotation_and_effects.md`](rotation_and_effects.md) | 定点算术、旋转与窗口卷积的细节 |
| [`src-map.md`](src-map.md) | 每个 RTL 模块的端口、时序假设、被谁例化 |
| [`interface-table.md`](interface-table.md) | 寄存器、地址与命令的机器可读表 |

### 跑出了什么数

| 文档 | 回答什么 |
|---|---|
| [`04-resources.md`](04-resources.md) | LUT/FF/BRAM/DSP 的去向，BRAM 为什么紧 |
| [`05-timing.md`](05-timing.md) | 逐时钟 WNS/WHS、准静态跨域约束、RGMII 物理边界 |
| [`06-validation.md`](06-validation.md) | 四层验证各答什么、哪些判据能红、仿真答不了什么 |
| [`50-results.md`](50-results.md) | 历史轮次的结果表（r118/r132），**不是当前值** |
| [`perf_report.md`](perf_report.md)、[`optimization_log.md`](optimization_log.md) | 逐轮优化过程与被否决的方案，历史账本 |
| [`timing_global.md`](timing_global.md)、[`05-timing.md`](05-timing.md) | 逐时钟名册与当前时序结论 |

### 怎么验、怎么复现

| 文档 | 回答什么 |
|---|---|
| [`70-reproduce.md`](70-reproduce.md) | 从零构建、仿真、上板、比对结果的逐命令步骤 |
| [`build.md`](build.md) | 工具版本、构建命令、失败时先看哪份日志 |
| [`../sim/README.md`](../sim/README.md) | 台架清单、跑法、判定行 |
| [`../board/README.md`](../board/README.md) | 上板工程、JTAG 三步链、串口脚本、实测输出 |
| [`host_guide.md`](host_guide.md) | 上位机推流、仪表、自检工具 |
| [`acceptance-recipes.md`](acceptance-recipes.md) | 需要人眼判的验收项与前置条件 |
| [`board_pins.md`](board_pins.md) | 引脚、时钟来源与约束文件的对应关系 |

### 哪里还不行

| 文档 | 回答什么 |
|---|---|
| [`08-limits.md`](08-limits.md) | 185° 残留、RGMII I/O 未约束、hold 口径、BRAM 架构边界、固件易失 |
| [`known_issues.md`](known_issues.md) | 缺陷台账与有意保留的未通过项 |
| [`60-failure-analysis.md`](60-failure-analysis.md) | 未解决与未测试问题的现象、假设、判别方法和成本 |
| [`90-open-items.md`](90-open-items.md) | 未决项快照 |

### 技能与协作

| 文档 | 回答什么 |
|---|---|
| [`07-skill-distillation.md`](07-skill-distillation.md) | 技能包从哪里来、怎么验证、边界在哪 |
| [`../skill/README.md`](../skill/README.md) | 技能条目索引 |
| [`llm_collab.md`](llm_collab.md) | 大模型协作的四个案例与工作流 |
| [`collaboration/`](collaboration/) | 提示词原文、纠错轨迹与逐会话档案 |

## 当前版本与历史账本

当前候选是 r171，位流 md5 前 12 位 `9734f3ec3019`，XSA `f4d4425138a2`，PS 固件 `9ff967573b32`。时序是 WNS 1.341 ns、WHS 0.025 ns，TNS=THS=0；资源是 LUT 14 967（28.13%）、FF 9 095（8.55%）、BRAM 98（70.00%）、DSP 19 颗。r171 于 2026-10-22 19:11 用冷启动流程烧入；FLASH/health GREEN（`flash_20261022_1911.txt`、`health_20261022_1912.txt`），105 条串口电池 98 s PASS（`build/uart_r171_battery_final.txt`），1 Hz 遥测 13 秒 11 包（`build/telemetry_r171_final.txt`）；`sd file 1`+`play` 续播判据回 621（老固件 108，`build/evidence_r171/uart_r171_play_final.txt` / `uart_r169b_play_resume.txt`）。连续流 8.00 秒 240 帧、30.00 fps 与三阶段自检取自 r159（ETH/PS 通路自 r159 起未改）。

门禁复跑：r171 门禁 24 项 23 绿 / 1 红（`build/r171_gates.txt`，原始输出 `build/r171_gates_raw.txt`）。唯一红项是顶层台架门禁，两个原因都不是设计缺陷：① 源码指纹自检 F3/F4 需要 `.git` 跟踪面（本工作区不是 git 仓库，`git ls-files` 为 0，桥接表引用的提交取不出来）；② quick 台架的 `RESULT` 行带 `(quick_c17)` 后缀，门禁只认无后缀整行（全量 75 分钟那一档才会打出）。台架本身 39 条 PASS、0 FAIL，顶层报告的三枚指纹都是当前树。时序、资源、功耗、端口、CDC、边缘条带、行号锚点、数字对账、命令长度、温度公式、文档时效 D1b/D1c 均通过；`GATES: 有红项` 如实保留，没有写成 `ALL PASS`。

`50-results.md`、`perf_report.md`、`optimization_log.md`、`timing_global.md` 保留的是 r118/r132 那些轮次的原始读数与优化过程。它们仍然有用，因为能看出一个改动当时为什么被采纳或被否决；但里面的 WNS、LUT、BRAM 不是当前值。凡是拿当前数字的地方，一律以 `technical-report.md` 和 `04/05/06` 三章为准。

## 证据在哪

时序与资源报告在 `build/r162/`；完整视频台架日志在 `build/msim/video_pipeline_top.log`；上板读数在 `board/measured/` 与 `board/README.md`；缺陷与过程记录在 `report/log/`。这些文件是证据，不是叙述；引用时给出文件名和当时的版本身份，不把不同轮次的数字拼在一起。

这份索引只指盘上存在的文件。如果你按路径找不到某一项，那说明文档该改，不是文件该补。

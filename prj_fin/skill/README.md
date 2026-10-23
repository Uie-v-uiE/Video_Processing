# 技能包：与大模型协作做 FPGA / 数字设计

这套技能包是从本项目开发过程中提炼出来的做法，不是 FPGA 教材，也不是本项目的说明书。
判它好不好用只看一件事：另一支队伍、另一块板、另一个题目，拿到目录能不能直接用起来。

## 四类内容

| 赛题类型 | 入口 | 内容 |
|---|---|---|
| 提示词工作流 | `prompts/` | 从算法描述推软硬件划分、从综合报告定位瓶颈、单轮改动闭环、对抗式评审、只读审查 |
| 案例模板 | `templates/` | 工程骨架、接口契约、报告表单、脚本模板 |
| 校验脚本 | `scripts/` | 黄金比对、指标采集、寄存器映射检查、复现检查、契约生成 |
| 踩坑清单 | `pitfalls/` | 判据假绿、CDC、约束覆盖、文档轮换、构建竞态、工具探针陷阱等 |
| 框架专项 | `frameworks/` | Vivado/板卡侧与 PYNQ Overlay 两条通用技能；PYNQ 卡不绑定本项目，作为通用技能单独提交 |

另有 `runtime/`（板上运行时事实）、`references/`（速查表）、`zynq-video-rtl-debug/`（L0–L4 分层调试）和 `frameworks/`（Vivado/板卡、PYNQ 两条框架专项）。

## 条目正文

每条 `SKILL.md` 按固定六节写：

1. 一句话用途
2. 适用场景
3. 不适用 / 失效条件
4. 前置条件
5. 使用方法
6. 判读与失败分叉

对应赛题 §3.3.5.2 的四件事：适用范围看第 2 节；使用方法看第 5 节；
失效条件看第 3 节；已验证效果看第 6 节的完成判据与失败分叉。条目的来源（从哪次失败或观察提炼）
写在每条的出处/来源段和 `_meta/sources.md`。

## 30 秒接入

1. 整个目录放进自己的工程或 agent 的技能目录；正文是纯文本，脚本只依赖 Node。
2. 先看下面的“症状 → 条目”，再按需打开单条；不要一次读整包。
3. 要新增条目，按 `_meta/entry-template.md` 的六节写，并逐条核对第 6 节的完成判据。

## 症状 → 条目

| 症状 | 先看 |
|---|---|
| WNS 是负的，不知道该动算术、扇出还是布局 | `references/wns-logic-vs-route-lever/SKILL.md` |
| 判据第一次跑就绿，但缺陷还在 | `pitfalls/checker-ran-on-nothing/SKILL.md`、`pitfalls/criterion-blind-spot/SKILL.md` |
| CDC/资源数字变了，不知道是谁 | `pitfalls/cdc-pair-baseline-gate/SKILL.md` |
| 文档说“当前版本”，实际是上一版 | `pitfalls/artifact-freeze-and-freshness/SKILL.md` |
| 台架红了，硬件看着是对的 | `references/bench-self-inflicted-reds/SKILL.md` |
| 上板没画面、没反应、ping 不通 | `zynq-video-rtl-debug/SKILL.md`、`runtime/board-eth-uart/SKILL.md` |
| 回读的一组数不自洽 | `runtime/atomic-register-window-readback/SKILL.md` |
| 算出来的 fps/带宽好得不像话 | `pitfalls/metrics-gap-sum/SKILL.md` |
| PYNQ Overlay 加载、寄存器、DMA、中断出问题 | `frameworks/pynq-overlay-development/SKILL.md` |
| Vivado/Vitis 工程、BD、约束、上板分诊 | `frameworks/fpga-board-development/SKILL.md` |

## 索引

### `prompts/`（8 条）
- `prompts/criterion-before-code/SKILL.md`
- `prompts/eye-acceptance-loop/SKILL.md`
- `prompts/hw-sw-partition/SKILL.md`
- `prompts/llm-fpga-debug-workflow/SKILL.md`
- `prompts/read-only-review-agent/SKILL.md`
- `prompts/report-to-bottleneck/SKILL.md`
- `prompts/round-work-loop/SKILL.md`
- `prompts/single-variable-ab/SKILL.md`

### `templates/`（4 条）
- `templates/interface-contract/SKILL.md`
- `templates/project-skeleton/SKILL.md`
- `templates/report-forms/SKILL.md`
- `templates/script-template/SKILL.md`

### `scripts/`（5 条）
- `scripts/contract_gen/SKILL.md`
- `scripts/golden_compare/SKILL.md`
- `scripts/regmap_check/SKILL.md`
- `scripts/report_metrics/SKILL.md`
- `scripts/repro_check/SKILL.md`

### `pitfalls/`（24 条）
- `pitfalls/ab-revert-control-run/SKILL.md`
- `pitfalls/arbiter-pending-pulse/SKILL.md`
- `pitfalls/artifact-freeze-and-freshness/SKILL.md`
- `pitfalls/assertion-not-in-any-file/SKILL.md`
- `pitfalls/baremetal-standard-startup/SKILL.md`
- `pitfalls/cdc-pair-baseline-gate/SKILL.md`
- `pitfalls/checker-ran-on-nothing/SKILL.md`
- `pitfalls/combinational-block-misses-task-reads/SKILL.md`
- `pitfalls/console-codepage-verdict-shift/SKILL.md`
- `pitfalls/criterion-blind-spot/SKILL.md`
- `pitfalls/derived-clock-port-mux/SKILL.md`
- `pitfalls/exit-zero-nothing-written/SKILL.md`
- `pitfalls/failing-read-prints-geometry/SKILL.md`
- `pitfalls/frameid-loss-signature/SKILL.md`
- `pitfalls/metrics-gap-sum/SKILL.md`
- `pitfalls/prove-change-is-free-by-bitstream-header/SKILL.md`
- `pitfalls/pulse-toggle-cdc/SKILL.md`
- `pitfalls/report-field-parse-breaks/SKILL.md`
- `pitfalls/rotate-window-target-domain/SKILL.md`
- `pitfalls/sim-hw-divergence-array-writes/SKILL.md`
- `pitfalls/switch-feature-two-level-evidence/SKILL.md`
- `pitfalls/tcl-query-empty-means-broken-ruler/SKILL.md`
- `pitfalls/who-else-writes-this-artifact/SKILL.md`
- `pitfalls/win-bash-path-split/SKILL.md`

### `runtime/`（8 条）
- `runtime/atomic-register-window-readback/SKILL.md`
- `runtime/board-eth-uart/SKILL.md`
- `runtime/dma-cache-coherency/SKILL.md`
- `runtime/host-bindings-and-reports/SKILL.md`
- `runtime/pl-load-verify/SKILL.md`
- `runtime/register-map/SKILL.md`
- `runtime/udp-offset-reasm/SKILL.md`
- `runtime/zynq-ddr-bandwidth/SKILL.md`

### `references/`（7 条）
- `references/bench-self-inflicted-reds/SKILL.md`
- `references/bench-verilog-subset/SKILL.md`
- `references/build-report-field-map/SKILL.md`
- `references/checker-convention-shapes/SKILL.md`
- `references/tool-version-drift/SKILL.md`
- `references/verdict-line-must-print-scope/SKILL.md`
- `references/wns-logic-vs-route-lever/SKILL.md`

### `zynq-video-rtl-debug/`（1 条）
- `zynq-video-rtl-debug/SKILL.md`

### `frameworks/`（2 条）
- `frameworks/fpga-board-development/SKILL.md`
- `frameworks/pynq-overlay-development/SKILL.md`

共 59 条。

## 验证与边界

- 每条都写“完成判据”和“失败分叉”，判据必须能被打红；只写正向判据的条目不算通过。
- 原始评估记录和团队信息不随包；验证口径写在每条第 6 节的完成判据与失败分叉。
- 工具版本相关的字段位置会漂移（本项目的验证环境是 Vivado/Vitis 2025.2.1），换版本要重新量形状。
- 7 系列的 IDELAY/BUFIO/ODDR 用法不能直接搬到 UltraScale+；跨板卡迁移需要重新验证。

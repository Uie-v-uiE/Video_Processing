---
name: pynq-codesign
description: PYNQ（Zynq-7000 / PYNQ-Z2）软硬件协同设计与上板调试技能包。当需要在 PYNQ 板上加载 Overlay 并校验、从 .hwh 取地址与寄存器映射、用 MMIO 读写自造 IP、用 DMA 搬图像或采样帧并处理缓存一致性、决定 PS/PL 划分与 HP/GP 端口选择、在板上做自检并留存实测数据，或出现“overlay 加载成功但寄存器全读 0”“DMA does not support unaligned transfers”“recvchannel.wait() 永久挂住”“读回旧帧/脏数据”“换板卡或换题目后代码失效”“pynq.lib.i2c / pl_device_transfer 这类不存在的 API”等症状时使用。也适用于生成主机侧绑定（Python/C/测试骨架）、黄金参考比对、性能与资源指标自动成表，以及为嵌入式竞赛提炼通用 PYNQ 技能包。不用于 Vivado 综合、实现与静态时序收敛本身。
license: MIT
compatibility: PYNQ v3.1 (Carlisle) on Zynq-7000 PYNQ-Z2; reads UltraScale+/ZynqMP .hwh too. Vivado/Vitis 2025.2 or 2026.1 for design work. 工具只用标准库，实测环境是 Windows / Python 3.12（其他 Python 版本未实测，不作断言）；跑检查不需要板子也不需要 Vivado。不适用 PYNQ 4.0（Z1/Z2 已移除）。
metadata:
  version: 1.0.0
  domain: embedded-fpga-pynq
  competition-track: 全国大学生嵌入式芯片与系统设计竞赛 2026 AMD 自主选题赛道（初级组）
---

# PYNQ 协同设计与上板调试

## Overview

把 PYNQ 上最容易翻车的四件事变成**可复算的步骤**：Overlay 是否真的绑定、寄存器地址从哪来、
DMA 与缓存一致性怎么做、性能数字凭什么可信。每条知识都绑定一条命令与一个能判红的判据：
判定行统一为 `checked=<N> red=<R> PASS|FAIL`，`checked=0` 一律算 `NOT_MEASURED`（退出码 2），
不用“没报错”冒充通过。

## 何时使用

- 第一次把 block design 放上 PYNQ 板；或 `Overlay(...)` 后 IP 读不到、全 0、抛奇怪异常。
- 要用 `MMIO` 读写自造 IP，但不知道基址/偏移/位段该从哪里取证。
- 用 DMA 搬一帧数据：对齐、`buffer_max_size`、TLAST、`sync_from_device()`。
- 要写设计报告的“软硬件划分依据”“实测数据”“复现说明”。
- 要给大模型布置 PYNQ 任务，并检验它的回答有没有编造 API。
- 要把经验沉淀成竞赛 `skill/` 目录（指南 3.3.5.2 的通用 PYNQ Skill 加分项）。

不适用（问这些请别指望本包）：

- Vivado 综合/实现的收敛技巧与约束写法本身（用 UG901/UG904/UG949）；本包只讲到「导出 `.bit`
  与 `.hwh` 所需的那点约束」为止。
- PYNQ 4.0 的板子（本包 API 面钉在 v3.1，4.0 已移除 Z1/Z2 的板定义）。
- **PyPI 上那个叫 `pynq` 的串口库**（树莓派/ESP 的 pyserial 封装），与本框架同名不同物；
  「pynq 读不到串口数据/波特率不对」这类问题不在本包射程内。
- PS 侧 UART/SPI/CAN 等硬外设的驱动与波特率配置（v3.1 的 `pynq.lib` 不再导出 uart/spi/pwm
  封装，本包也不讲裸 `mmap` 写串口）。
- 非 AMD/Xilinx 器件的外设写法：STM32 HAL、ESP32、Arduino 的 I2C/SPI/ADC 初始化与从机地址。

## 核心工作流

```bash
# 0. 先跑一遍，确认工具在你的机器上能跑（无需板子、无需 Vivado）
python3 scripts/run_all.py                    # 证据写入 evals/results/tool_evidence.txt

# 1. 从设计文件取证（设计侧要点见 references/design-to-bitstream-hwh.md）
python3 scripts/hwh_inspect.py build/design.hwh --format md \
  --require address --require registers --require clocks --require dma

# 2. 由设计生成主机侧绑定与测试骨架（契约不合法直接 REFUSE）
python3 scripts/contract_gen.py --hwh build/design.hwh --ip video_kernel_0 \
  --out-dir build/generated

# 3. 写 PS 侧代码，随时静态检查（v3.1 的 API 面来自 scripts/api_surface.json）
python3 scripts/api_lint.py src/ps_app.py

# 4. 没有板子时先在离线桩件上跑行为验证；有板子时同一份脚本直接上板
python3 scripts/run_offline.py --script assets/examples/dma_frame_loopback.py --expect-ok
ssh xilinx@192.168.2.99 'sudo python3 /home/xilinx/design/dma_frame_loopback.py'

# 5. 结果与黄金参考比对（比较次数与失效豁免都会被点名）
python3 scripts/golden_compare.py board_out.hex data/golden.hex --format hex --tol 0

# 6. 指标成表并判绿（占位值、缺失指标、冲突重复值都不会被当成通过）
python3 scripts/measure_report.py data/metrics.csv --require fps,wns,luts --md
```

## 知识条目路由

| 你要做什么 / 出现什么症状 | 读哪个条目 |
|---|---|
| 从 RTL/HLS 核心走到可加载的 `.bit + .hwh`：板文件与器件字符串、FCLK 驱动、流接口 TLAST 接线、`C_SG_LENGTH_WIDTH`、地址段与导出验收。「刷了新版镜像连我们板子的定义都翻不着」「vivado 导出的东西拷到板上就拿不到」 | `references/design-to-bitstream-hwh.md` |
| `Overlay()` 加载、`.bit/.hwh` 配对、`ip_dict`、`reset/free/pr_download`。「按块设计里的实例名去拿，报找不到这个 key」「加载没报错，写进去读回来全是 0」「这俩文件版本是不是没对上」 | `references/overlay-load-and-verify.md` |
| 基址/偏移/位段从哪来、`register_map`、`MMIO` 边界；从 `.hwh` 自动生成主机侧调用代码、C 头文件与测试骨架（`contract_gen.py`）。「偏移是 0x0 还是 0x18 全靠猜」「控制位在哪一位没人说过」「那坨 xml 人肉读不动」 | `references/register-map-from-hwh.md` |
| DMA 搬运、对齐、`buffer_max_size`、分块、TLAST、`allocate` 与缓存一致性；`wait()` 挂死。「一次搬一整帧嫌太大」「拆完又说要按倍数对齐」「尾巴那截丢了」「读回来还是上一次那批数，手动刷一道才变新」「死在那句等它传完上」 | `references/dma-and-buffer-coherency.md` |
| 这段放 PS 还是 PL、HP/GP/ACP 选哪个、带宽账怎么写。「哪块扔 PL 哪块留 PS 吵翻了」「主频拉到 150 也喂不饱那条口」 | `references/ps-pl-interface-choice.md` |
| 上板登录、权限、无网、板上 pytest、实测数据留存。「ssh 进去跑我们的脚本一路 permission denied」「pip 连不上站只能拿 U 盘拷」「管理员号一起 python 就炸，普通号读不到设备文件」 | `references/board-access-and-self-test.md` |
| PL 侧并行 IO、方向掩码、I2C 外设、PL 中断通知 PS（控制/采集类题目）。「配了读出来永远是高，说有个方向的东西没设」「自己敲时钟那两根线」「想让 ARM 收到通知，不想一直轮询」 | `references/gpio-iic-and-interrupt.md` |
| 不知道从哪查起（按症状分诊表）；`AttributeError: no attribute`、疑似抄了不存在的 API 名字、报错原文逐字定位 | `references/pitfall-triage.md` |
| 给大模型下指令并检验回答。「怎么让大模型别瞎编 API」「它每次给的写法都不一样」 | `references/prompts-for-llm-collaboration.md` |
| 工程目录骨架、纯英文文件名、构建与上板留痕、报告三段；黄金参考比对（`golden_compare.py`，容差/豁免/失效豁免）、性能与资源数据自动采集并成表（`measure_report.py`）。「手抄进 word，有俩数压根没测出来就画了个横杠」「到底对了几处、哪几处飘了」「目录是不是得纯英文」 | `references/project-skeleton-and-metrics.md` |
| 没有板子/没有 Vivado 时如何证明结论可信；手上没板先在桩件上比 | `references/offline-verification.md` |
| 每条断言的出处、文档与源码冲突、未证实项。「这个版本说法到底从哪来的」「报告里要不要写死版本号」 | `references/sources.md` |

行里「」内是队伍实际会说的话（症状、口语、不含术语），不是术语；按症状问也应当命中该行——真实路由器是大模型读整张表，不是字符串匹配。

## 工具清单

每个脚本都有 `--help`，非交互、可用 `--json`/`--report` 取结构化输出，退出码约定一致：
`0` 通过、`1` 有红、`2` `NOT_MEASURED`/被拒绝。

| 脚本 | 作用 | 自检 |
|---|---|---|
| `scripts/api_lint.py` | 静态检查板侧 Python 是否用了 v3.1 不存在的 API 与错误用法 | `--self` |
| `scripts/hwh_inspect.py` | 读 `.hwh`：实例、地址段、寄存器与位段、时钟、DMA 上限与对齐 | `--require` |
| `scripts/contract_gen.py` | 由 `.hwh` 生成 Python/C 绑定与测试骨架，含工件 sha256 绑定 | `--selftest` |
| `scripts/run_offline.py` | 在离线桩件上执行板侧脚本并按断言行计数 | `--self` |
| `scripts/golden_compare.py` | 黄金比对：容差、豁免按期望值作键、失效豁免点名 | `--self` |
| `scripts/measure_report.py` | `metrics.csv` → 判定表；占位值与缺失指标变 `NOT_MEASURED` | `--selftest` |
| `scripts/pkg_check.py` | 本包自检：格式规范、文件名 ASCII、条目四节、无占位符、链接可达 | `--selftest` |
| `scripts/run_all.py` | 一次跑完并落证据文件（两阶段：数字对账放到证据写完之后） | — |
| `scripts/cleanroom_check.py` | 把本包复制到临时空目录再跑一遍，证明不依赖开发机路径与既有产物 | — |
| `scripts/surface_dump.py` | 在你自己的板/镜像上导出真实导出面，与钉扎面 diff，并能产出 `api_lint --surface` 可用的面 | `--offline-stub` |

`scripts/` 就这 10 个。度量本包自身的脚本在 `evals/`（`route_eval.py`、`route_summary.py`、
`ab_gain.py`），协议与不可信之处写在 `evals/routing_protocol.md`，结论表在
`evals/results/routing_summary.md`——它们不是给题目用的工具，别混进提交物的 `skill/` 说明里。

## 判定与写作约定

- 只写能被复算的结论：命令 + 输出 + 文件位置。理论值必须标“理论峰值”。
- 不能证明的部分显式写出（`references/sources.md` 有“未证实项”一节）。
- 引用一律给可打开的 URL 与版本；文档与源码冲突时两处并列（见 `sources.md` 的冲突表）。
- 目录内除 `README.md`、`SKILL.md` 外，文件名全小写 ASCII（指南 3.3.5.4 要求）。

## 换题目、换板卡的用法

本包不含任何具体算法：示例只做 overlay 加载、寄存器读改写、DMA 回环与分块。
迁移到新题目/新板卡时的顺序：**第 0 步 `surface_dump.py`（先确认这块镜像的导出面与
本包钉扎的 v3.1 是否一致；不一致就 `api_lint --surface <你导出的面>`，别拿别的板子的事实判你的代码）**
→ `hwh_inspect`（取你的设计事实）→ `contract_gen`（生成你的绑定）→
把 `assets/examples/*.py` 里的实例名换成你的 → `api_lint` + `run_offline` → 上板。
`assets/fixtures/hwh/` 提供三份不同设计（两种 DMA 参数、一块非 Z2 器件），同一份工具零修改
即可报出不同上限与对齐要求，这就是“通用”的证据。

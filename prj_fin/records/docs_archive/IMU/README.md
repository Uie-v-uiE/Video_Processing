# 共享单车北斗可信电子围栏（科技创意类）

多径导致“停在停车点却被判违停扣费”→ **先判位置可信，不可信则不扣费**。

## 主交
- 参赛PPT：`docs/参赛PPT_共享单车北斗可信电子围栏.pptx`
- 图文说明：`docs/作品图文说明_共享单车北斗可信电子围栏.docx`
- 证据图PNG：`out/fig_png/`

- `docs/方案报告_共享单车北斗可信电子围栏.docx`
- `docs/项目完整讲解大纲.md`
- `docs/提交材料清单.md`

## PC 仿真（主证据）
```powershell
& $env:MIMO_PYTHON src\sim\run_fence_eval.py
```
- 指标：`out/fence_metrics.csv`
- 图：`out/evidence_fence/`

| 场景 | 旧逻辑误扣 | 本方案(三态门控) |
|------|------------|--------|
| 城市多径 | 84% | 11% |
| 多径+欺骗 | 74% | 0% |

## 增强层 PLTG（创新点：保护级感知 + 零速聚合 + 分级降级）
方法、实验与失效模式：`docs/创新点_PLTG_保护级感知可信围栏.md`

| 策略 | 误扣率 | HOLD(停摆)率 | 自动判决率 | 期望代价 |
|---|---|---|---|---|
| 旧逻辑 | 13.3% | 0% | 100% | 4.84 |
| 三态门控(已交付) | 0.17% | 44.0% | 56.0% | 1.78 |
| PLTG(GNSS-only) | 0% | 75.4% | 24.6% | 2.35 |
| **PLTG+3路侧锚点** | **0%** | **2.6%** | **97.4%** | **0.08** |

- C 参考实现：`fpga/software/plfg_window.c`（纯 stdio/math，无 numpy/scipy）
- 跨语言一致性：`python src/sim/crosscheck_c.py` → `out/pl_crosscheck.md`（363 历元判决动作 100% 一致，δ 偏差 <2e-7）
- 交付前自检：`python src/check_project.py`（21 项，含文档数字与 CSV 一致性硬检）

要点：门限由**虚警预算**标定（χ²/保护级）而非经验值；锁车静止先验把 HOLD 变成**3 s 延迟定案**；
围栏几何作为**对偶假设检验**的两侧；GNSS 不可判时降级到与卫星无关的锚点测距。

## 板端（加分）
- 源码：`fpga/software/fence_eval.c` + `fence_testset.h`
- 统一工程：`vitis_ila/`
- 平台：`fpga/vitis/platform/`
- 一键：`fpga/run_classic_ok.tcl`（mrd 0x150a4）
- 说明：`docs/VITIS_SCREENSHOT.md`、`out/board/VERIFIED.md`

## 目录
- `docs/` 报告与讲解（含 `创新点_PLTG_保护级感知可信围栏.md`）
- `src/sim/` 仿真（`integrity.py`/`plfg.py`/`run_pl_eval.py` 为增强层）
- `out/` 指标与证据图
- `fpga/` 板端源码与脚本
- `vitis_ila/` Vitis 统一工作区
- 根目录 PDF/XLS：板卡手册


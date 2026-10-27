# 工程骨架、数据留痕与报告模板

## 适用范围

开一个新题时把目录、构建脚本、上板留痕与报告结构一次定下来，使“他人从零复现”与
“数据真实完整”这两项（合计 35 分权重）不靠临场补救。换题目直接复制本骨架即可。

## 使用方法

### 目录骨架（对齐指南 3.3.5.4，文件名全小写 ASCII）

```text
<project_name>/
├── README.md                 # 项目简介 + 三步复现命令
├── src/                      # RTL / HLS / PS 侧 python
│   └── ps_app/
├── sim/                      # 仿真脚本与结果（含 self-check 的判定行）
├── build/                    # 可复现构建脚本 + .bit .hwh .xsa + 综合实现报告
│   ├── run_build.tcl
│   └── generated/            # contract_gen.py 的输出（绑定与测试骨架）
├── board/                    # 上板脚本、实测输出、日志
│   └── logs/
├── data/                     # 测试图/采样数据与 golden 参考
│   ├── golden/
│   └── metrics.csv
├── skill/                    # 本技能包（或指向它的说明）
└── report/                   # 设计报告 + 大模型协作记录
```

约束：所有目录名/文件名只用小写字母、数字、下划线、连字符（指南 3.3.5.4）；中文只出现在
文件正文里。唯一例外是 `README.md` 与 `SKILL.md` 的约定俗成大写名，因为指南自身的目录示例
就用 `README.md`。

### 构建与上板的留痕约定

1. 构建只有一条入口：`build/run_build.tcl`（`vivado -mode batch -source build/run_build.tcl`），
   脚本里显式写 `set part xc7z020clg400-1` 一类的器件声明并保证可复现；产物固定落到 `build/`。
2. 每次上板跑一份带 `checked=/red=` 判定行的脚本，把 stdout 原样存进 `board/logs/`。
   模板要求脚本自己打印计数，而不是靠人眼看。
3. `data/metrics.csv` 表头固定为：

   ```text
   name,value,unit,spec,source
   fps,61.8,frames/s,min:60,board/logs/run_2026-10-10.txt
   luts,18342,cells,max:53200,build/reports/synth_1.json
   wns,0.318,ns,min:0,build/reports/timing_1.rpt
   board,PYNQ-Z2,-,declare,README.md
   ```

   `spec` 只能是 `min:N` / `max:N` / `range:A-B` / `eq:N` / `declare`；
   `source` 必须是能打开的文件。校验：

   ```bash
   python3 scripts/measure_report.py data/metrics.csv --require fps,luts,wns --md
   ```

4. 比对类结论走 `scripts/golden_compare.py`，豁免文件必须写成 `<index>\t<期望值>`，
   期望值变了还留着豁免会被报成 `STALE-WAIVER` 并计入红。
5. 演示脚本（3 分钟）：一条命令加载 → 一条命令跑 → 一条命令判绿；任何需要“先手动点三下”
   的步骤都是复现风险，写成脚本。

### 报告里必须出现的三段

- **划分依据**：三段论 + 带宽账（理论值要标注），见
  `references/ps-pl-interface-choice.md`。
- **优化前后对比表**：同一 `metrics.csv` 的两份快照（`--json-out` 生成，便于 diff）。
- **失败分析**：仍未解决的场景 + 用哪条命令能复现它；把 `board/logs/` 的原始片段贴进去，
  不要只写结论。

## 失效条件

- 用 UltraScale+/Versal 或 PYNQ 4.0 时，端口清单、器件字符串与 API 面都要重新取证
  （见 `references/sources.md` 的版本钉扎）。
- 骨架里的 `build/run_build.tcl` 只是约定位置，本包**不提供** Vivado 构建脚本内容：
  本机无 Vivado，任何未跑过的 tcl 都不能写成“已验证”。
- `metrics.csv` 若把理论峰值填成实测（`source` 指向报告而非日志），`measure_report.py`
  无法识别语义造假——它只保证形状、来源与判定；语义由写报告的人负责。

## 已验证效果

```bash
python3 scripts/measure_report.py --selftest    # checked=7 red=0 PASS
python3 scripts/golden_compare.py --self        # checked=7 red=0 PASS
python3 scripts/measure_report.py assets/templates/metrics_spec.csv
                                                # checked=7 red=0 not_measured=5 NOT_MEASURED
```

阴性对照：占位值、缺失必填指标、同名冲突值都不得判绿；空表模板必然 `NOT_MEASURED`——
也就是说“还没测”在工具层面就不可能伪装成通过。需要 Vivado 的构建步骤本机未实测。

## 来源

指南 3.3.5.1、3.3.5.3、3.3.5.4、3.3.5.5（赛题指南 PDF，随队分发，此处只按章节号引用）；
`PYNQ-Z2` 器件字符串 `-part xc7z020clg400-1` 见上游构建脚本
<https://github.com/Xilinx/PYNQ/blob/v3.1/boards/Pynq-Z2/petalinux_bsp/hardware_project/pynqz2.tcl>。

# 目录骨架模板（照抄后删掉用不上的层）

命名规矩：目录名与文件名只用小写字母、数字、下划线或连字符；中文只出现在文件正文里。

```text
<project_name>/
├── README.md                 # 项目简介 + 从零复现步骤（含硬件搭建、环境、比对）
├── src/
│   ├── rtl/                  # Verilog/VHDL 源码
│   ├── ip/                   # IP 与 block design 脚本
│   └── ps/                   # PS 侧软件（C / Python / Notebook）
├── sim/
│   ├── tb_*.v                # 台架
│   ├── run_one.sh            # 一条命令跑一个台架：sim/run_one.sh <台架名>
│   └── anchor/               # 改前红落点（未改动树上的红色读数，与台架同轮归档）
├── build/
│   ├── run.sh                # 非交互构建：综合→实现→位流，日志与报告落点固定
│   ├── tcl/                  # 只读探针与实现脚本（全文 ASCII）
│   └── report/               # 综合/实现报告（资源、时序、关键路径）
├── board/
│   ├── load_and_run.sh       # 上板：加载 + 打印判活/回读
│   └── evidence/             # 实测输出与截图（大件不入库要同行声明）
├── data/
│   ├── golden/               # 黄金参考（只读位置，不与产物同名轮换）
│   └── inputs/               # 测试激励与已知坏样本（变异对照用）
├── skill/
│   ├── README.md             # 每项写：适用范围 / 使用方法 / 失效条件 / 已验证效果 / 来源
│   └── <条目名>/SKILL.md      # 一层布局；分组靠 frontmatter 的 metadata.kind
└── report/
    ├── design-report.md      # 设计报告（含优化前后对比表、失败分析）
    └── collaboration/        # 大模型协作记录：提示词、回答、自我纠错轨迹
```

## 每层要回答的问题

| 层 | 陌生评审会问 | 你要能立刻指出的东西 |
| --- | --- | --- |
| `build/` | 怎么从零出位流？ | `bash build/run.sh` + 日志与报告路径 |
| `sim/` | 功能正确性怎么确认？ | 一条命令 + 本轮改前红 + 判据读数 |
| `data/golden` | 与什么比？ | 参考的来源与比对的容差、豁免键 |
| `board/evidence` | 板上真的跑了吗？ | 实测输出 + 判活字段 + 件与树的绑定 |
| `report/` | 数字从哪来？ | 每个数字点名一个可复跑件 |
| `skill/` | 这些经验别人能用吗？ | 条目 + 索引 + 机器判据的实跑读数 |

## 三条"骨架成立"的判据形状

```bash
bash build/run.sh                      # 从零跑通，退出码与判定词分开读（脚本可能 rc=0 而日志 FAILED）
node skill/../golden.mjs <产物文本> data/golden/ref.txt   # 或本包 golden-frame-compare 那条脚本
git worktree add /tmp/clean-check HEAD # 在干净检出上核对 README 点名的件是否都在（克隆后没有＝死链）
```

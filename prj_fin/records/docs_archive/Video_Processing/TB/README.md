# TB —— Verilog 台架与 SystemVerilog 台架教程

面向"会写 Verilog RTL、但没系统写过 testbench"的读者。两份正文 + 一套能跑的例题。
**文中所有工具行为都是本机实测**（Vivado xsim 2025.2.1、ModelSim SE-64 2020.4），不是手册转抄。

## 1. 三份文档怎么读

| 文件 | 内容 | 适合什么时候读 |
|---|---|---|
| `01-verilog-tb.md` | 仿真调度与竞态、台架六个部件、**系统任务/函数全表**（显示/时间/控制/随机/文件/转换/波形/plusargs）、编写手法（驱动采样相位、task 语义、记分板四规则、BFM、看门狗、规模分档）、视频类 DUT 专门手法、**22 条陷阱清单**、与本工程 `sim/` 82 支台架的口径对照 | 先把"为什么 `#1` 采样"搞懂，再背表 |
| `02-systemverilog-tb.md` | SV 相对 Verilog 的**语言层/结构层差别**、SV 的仿真函数与内建方法、约束随机与覆盖率语义、六件套手法（interface/clocking、virtual if、class 化、断言、判据能红、program/并发）、**优劣势诚实清单**、**43 行逐条实测支持矩阵**、从 `v06` 渐进改造到 `sv05` 的六步路线、SV 专属 20 条陷阱 | 决定"要不要上 SV、上到哪一步为止"时读 |
| `examples/README.md` | 11 支台架清单（6 Verilog + 5 SV）、三条命令跑法、plusarg 用法、实测矩阵摘要、以及**例题里抓到的 7 个真问题** | 动手 |

建议顺序：`01` §0–§3 → 跑 `examples/v/v01..v06` → `02` §1–§4 → 跑 `examples/sv/*` → 回头读
`01` §4/§5 与 `02` §5/§6/§8。

## 2. 一分钟跑起来

```bash
cd D:/Xilinx/Prj/Video_Processing/TB/examples
export VP_VIVADO_BIN=D:/Software/Vivado/2025.2.1/Vivado/bin      # 不设则用脚本默认值
bash run_v.sh  v02_clock_reset        # Verilog 台架 → xsim
bash run_sv.sh sv02_interface         # SystemVerilog 台架 → xsim -sv
bash run_ms.sh sv/sv02_interface      # 同一支台架 → ModelSim，看工具差异
```

判定行形状与本工程 `sim/` 一致：`VERDICT <tb>: PASS || FAIL 行数=0`。
退出码：**0 绿 / 3 判红 / 1 编译或例化失败 / 4 没有判定行**（`$finish` 不会给 xsim 非零码，判定必须靠判据行）。

## 3. 一图看懂两份文档的分界

| 关心的问题 | Verilog 的答案 | SV 的答案 | 出处 |
|---|---|---|---|
| 采样读到旧值 | 下降沿驱动 + 上升沿 `#1` 采样（人守纪律） | `clocking` + `default input #1step`（语法保证） | `01` §3.2 / `02` §4.1 |
| 总线信号散成十几根 | `reg/wire` + 层次引用 | `interface` + `modport` | `02` §4.1 |
| "这条规则不许违反" | 过程 `if` + `errors++` | 并发断言 / `bind` 检查器 | `02` §4.4 |
| 怎么知道测到了 | 穷举 + 判据计数闭合 | `covergroup`/`bins`/`cross` | `02` §3.4 |
| 随机激励 | `$random`/`$urandom` + 手写分布 | `rand` + `constraint` + `randomize()` | `01` §2.4 / `02` §3.3 |
| 判据可信吗 | 故意改期望值看会不会红 | 恒假性质 + `force` 注入 + `$assertoff` 对照 | `02` §4.5 |

## 4. 本机工具口径（最要紧的四条）

1. **xsim 的 SV 是子集**：`let`、`default disable iff`、覆盖率 `report()`、`D'(句柄)` 都不支持；
   `virtual interface` 作 **task 形参** 会让 `xelab` 直接崩栈（成员写法正常）。
   完整 43 行实测表见 `02` §6。
   另外 **队列方法 `min()`/`max()`/`find_max()` 会让 `xelab` 崩栈**（`sort()/unique()/sum()` 正常），
   `join_any`/`disable fork`/`semaphore`/带类型 `mailbox #(T)` 在 xsim 上都是好的。
2. **xsim 的 plusargs**：只认 `--testplusarg KEY=VALUE`，且命令行上 `=` 会被拆开——
   必须放进 `-f` 选项文件里各占一行（`run_v.sh`/`run_sv.sh` 已这么处理）。
3. **并发断言里紧跟性质的语句块是"通过动作"**，失败动作必须写 `else`；
   写反了会得到"数字漂亮、结论相反"的 checker（`02` §4.4，实测证据在 `sv04` 注释里）。
4. **ModelSim 控制台会把 UTF-8 打成 `?`**：判据词保持 ASCII（`PASS/FAIL/INFO/VERDICT`），
   中文只用于注释与说明行——本工程 `sim/` 的约定正好与此一致。

## 5. 这套教程与 `sim/`、`skills/` 的关系

- `sim/` 的 82 支台架是**生产件**：判据口径、退出码、日志留档、`prov.txt` 源树指纹，
  全部由 `build/sim/run_one.sh` 与 `run_sim.tcl` 驱动。本教程的 `examples/` 刻意沿用同一套
  判定形状（对照表见 `01` §6），所以从这里学到的写法可以直接搬进 `sim/`。
- `examples/rtl/` 是**教学用最小被测**，不是工程 RTL 的副本：语义对齐（行缓存的环形槽位、
  FIFO 的 `full/empty` 生成、时序发生器的 `de` 译码），但规模小、可单文件跑。
- `skills/` 里那些"与题解耦的做法条目"讲的正是本教程 §3/§4 层面的通用手法；
  两边若措辞不同，以 `sim/`、`build/sim/` 的可执行口径为准。

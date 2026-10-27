# examples/ —— 11 支可跑的台架（6 支 Verilog + 5 支 SystemVerilog）

每一支都是**自包含**的：只依赖本目录 `rtl/` 下的教学用最小被测模块，
不需要 Vivado 工程、不需要 `src/rtl`。所有台架在本机两条工具链上都跑绿：

| 台架 | 讲什么 | 被测 | xsim 2025.2.1 | ModelSim SE-64 2020.4 |
|---|---|---|---|---|
| `v/v01_system_tasks.v` | 显示/时间/格式符家族，`$strobe` 与 `$monitor` 的时机，`$finish(1)` | —— | 绿 | 绿 |
| `v/v02_clock_reset.v` | 时钟三种写法与非整数周期取整、异步复位同步释放、采样错拍、双时钟域 | `ex_sync_fifo` | 绿 | 绿 |
| `v/v03_scoreboard.v` | 自检台架：黄金模型、`===` 比较、判据计数、X 态判据、穷举 65544 条 | `ex_rgb565` | 绿 | 绿 |
| `v/v04_file_io.v` | `$readmemh/$writememh/$fopen/$fwrite/$fscanf/$fgets/$fflush/plusargs/$dumpvars` | `ex_sync_fifo` | 绿 | 绿 |
| `v/v05_random_stress.v` | 随机激励：种子可复现、RNG 分布自校、拒绝采样上限、随机背压、随机复位注入 | `ex_sync_fifo` | 绿 | 绿 |
| `v/v06_video_raster.v` | 视频光栅激励、坐标自描述像素、行缓存引导期 X 判据、断流看门狗、排空对账 | `ex_line_delay` | 绿 | 绿 |
| `sv/sv01_types.sv` | SV 类型与语法糖：`typedef/enum/struct`、队列、关联数组、动态数组、`string`、`case inside`、流操作、`foreach` | `ex_rgb565` | 绿 | 绿 |
| `sv/sv02_interface.sv` | `interface/modport/clocking`（`#1step`）、两套视角采样、接口内不变量断言 | `ex_sync_fifo` | 绿 | 绿 |
| `sv/sv03_class_tb.sv` | class 化台架：`rand`+`constraint`+`randomize`、`mailbox #(T)`、driver/monitor/scoreboard、`covergroup` | `ex_sync_fifo` | 绿 | 绿 |
| `sv/sv04_sva.sv` | 断言三用法：模块内、`bind`+checker、**反面对照**；`$asserton/$assertoff` 有效性验证 | `ex_video_timing` | 绿 | 绿（故意违例会有 Error 计数） |
| `sv/sv05_video_agent.sv` | 综合：约束随机视频帧 + 接口时钟块 + 类化 driver/monitor + 流下标记分板 | `ex_line_delay` | 绿 | 绿 |

> 表格里的"绿"是退出码 0（台架自己打了 `VERDICT <tb>: PASS`），不是"我看着像对的"。

---

## 一、三条命令

```bash
cd D:/Xilinx/Prj/Video_Processing/TB/examples
export VP_VIVADO_BIN=D:/Software/Vivado/2025.2.1/Vivado/bin       # 不设则用脚本里的默认值
export VP_MODELSIM_BIN=D:/Software/ModelSim/modelsim/win64

bash run_v.sh  v03_scoreboard          # Verilog 台架（不加 -sv，纯 Verilog-2001 口径）
bash run_sv.sh sv03_class_tb           # SystemVerilog 台架（xvlog -sv）
bash run_ms.sh sv/sv03_class_tb        # 同一支台架换 ModelSim，对照工具差异
```

放大规模 / 传种子（xsim 只认 `--testplusarg`，脚本已把它转成 `-f` 选项文件的形状）：

```bash
bash run_v.sh v05_random_stress +FULL            # 3000 → 20000 拍
bash run_v.sh v05_random_stress +SEED=1234       # 复现某一轮随机
bash run_sv.sh sv03_class_tb +N=800              # 事务数
bash run_sv.sh sv05_video_agent +NFR=20          # 随机帧数
bash run_ms.sh v/v05_random_stress +SEED=9 +FULL # ModelSim 侧直接吃 +KEY=VALUE，实测生效
```

产物在 `work_v/<tb>/`、`work_sv/<tb>/`、`work_ms/<tb>/`：`xv.log`（分析）、
`xe.log`（例化）、`run.log`（仿真原始输出）、VCD、以及台架写的文件
（`capture.log`、`rt.log`、`ram_dump.hex`）。

退出码沿用工程 `build/sim/run_one.sh` 的口径：**0 绿 / 3 判红 / 1 编译或例化失败 / 4 没有判定行**。
（注意：`$finish` 本身不会给 xsim 非零退出码，判定完全靠台架打出的 `VERDICT` 行。）

---

## 二、目录

```text
examples/
├── run_v.sh          # Verilog 台架 → xsim（不加 -sv）
├── run_sv.sh         # SV 台架 → xsim -sv
├── run_ms.sh         # 任一支台架 → ModelSim 批处理（对照工具支持）
├── rtl/              # 教学用最小被测模块（与工程 src/rtl 语义对齐，但不是同一份代码）
│   ├── ex_sync_fifo.v      # 16 格同步 FIFO：level/full/empty、写满吞写
│   ├── ex_rgb565.v         # RGB888→RGB565 打包 + de 透传
│   ├── ex_line_delay.v     # 环形行缓存，延迟 LINES 行（工程 raw_line_delay 的形状）
│   └── ex_video_timing.v   # 小光栅时序发生器（x/y/hs/vs/de/frame_done）
├── data/             # $readmemh/$fscanf/$fgets 的输入文件
│   ├── vectors.hex         # 含 // 注释、@10 稀疏地址（未覆盖槽位保持 X）
│   ├── bits.bin            # $readmemb 用
│   └── cmds.txt            # $fgets 逐行读的命令表
├── v/                # 6 支 Verilog 台架
└── sv/               # 5 支 SystemVerilog 台架
```

---

## 三、读的顺序（按你的情况排的）

1. **先读 `v/v01` + `v/v02`**：把"系统任务怎么用"和"时钟/复位/采样相位"一次过掉。
   这两支是后面所有台架的地基。文档：`../01-verilog-tb.md` §2、§3.1、§3.2。
2. **再读 `v/v03`**：自检台架的形状——黄金模型、判据计数、`===`、X 当判据、失败行自带上下文。
   这是"能跑"到"可信"的分界。文档 §3.4。
3. **`v/v04`（文件与数据）** 与 **`v/v05`（随机激励）**：
   `v05` 的注释里写了自己踩过的两个坑（模型与激励不同决策点、入队写到队头），
   那是这一类台架最贵的一课。文档 §2.4、§2.5、§3.6。
4. **`v/v06`（视频光栅）**：与本工程 `sim/` 里大量台架同构——
   坐标自描述像素、消隐可调、引导期 X 判据、断流看门狗、排空对账。文档 §4。
5. **`sv/sv01` ↔ `v/v03` 对照读**：同一批判据，代码量差在哪一目了然。文档 `02` §2.2。
6. **`sv/sv02` ↔ `v/v02` 对照读**：`clocking` 如何把 `#1` 这种人肉纪律变成语法。`02` §4.1。
7. **`sv/sv03`**：class + `randomize` + `mailbox` 的最小可用结构，以及三个必须避开的坑
   （`forever` 参与 `join`、驱动无视 `full`、句柄共享不 `clone`）。`02` §4.3。
8. **`sv/sv04`**：断言作为规格，含"判据必须能红"的完整机制（恒假性质 + `force` 注入 +
   `$assertoff/$asserton` 对照）。`02` §4.4、§4.5。
9. **`sv/sv05` ↔ `v/v06` 对照读**：`02` §8 那张六步改造表就是照着这两支写的。

---

## 四、本机实测的两条工具口径（值得先看一眼）

### 4.1 xsim 的 SV 是子集

`02-systemverilog-tb.md` §6 有一张 43 行的逐条实测表。最要命的几条：

| 特性 | xsim 2025.2.1 | ModelSim SE-64 2020.4 |
|---|---|---|
| `let` 断言表达式宏 | 分析过、**例化拒**（43-3980） | ✓ |
| `default disable iff` | 分析过、**例化拒** | ✓ |
| `covergroup` 的 `report()` / 覆盖率数据库 | **不存在**（10-2991） | ✓ |
| `virtual interface` 作为 task 形参 | **xelab 崩栈**（EXCEPTION_ACCESS_VIOLATION） | ✓ |
| `program` 里实例化 `interface` | 例化拒（10-8608） | ✓ |
| `clocking` 里同信号既 input 又 output | 拒（10-2934） | ✓ |
| `clocking` 里 `output` 方向的信号被**读** | 拒（10-3226） | ✓（同为 LRM 口径） |
| 队列方法 `min()`/`max()`/`find_max()` | **`xelab` 崩栈**（`sort()/unique()/sum()` 正常） | ✓ |
| `join_any` / `disable fork` / `semaphore` / `mailbox #(T)` | ✓ 全通过 | ✓ |
| `'{default:0}` 用于动态数组 | 例化拒 | ✓ |
| 断言"无 `else` 的动作块"语义 | 是**通过**动作（实测恒真执行 3 次、恒假 0 次） | 同左 |
| `$display` 里的 UTF-8 中文 | ✓ 正常 | 控制台变 `?` |

**结论**：想用 SV 的完整语义（覆盖率数字、`let`、约束随机的全部技巧），
本机就有 ModelSim 可以当参照；只用 xsim 时按 `02` §5.3 的"安全子集"写。

### 4.2 一些"手册与实现不一致"的地方（都实测过）

- `%u` 在 xsim 打成二进制（不是无符号十进制）；`%H` 仍打小写。
- `$time` 把 13.57ns **四舍五入**成 14；`%t` 默认标度不可读，先 `$timeformat`。
- `$countones/$onehot/$onehot0/$isunknown` 在 xsim 的 **Verilog 模式下直接拒绝**，要 `-sv`。
- `join_any`/`disable fork` 在纯 Verilog 模式下是语法错（属 SV）。
- `task automatic` 在 xsim 的 Verilog 模式下被宽松接受，但**别依赖**（跨工具会炸）。
- xsim 的 plusargs：`+KEY` 被拒，只认 `--testplusarg`；而命令行上
  `--testplusarg KEY=VALUE` 里的 `=` 会在参数解析时被拆开（实测报
  `Expected a switch but found 8`）。可用形状是选项文件：
  `-R` / `--testplusarg` / `KEY=VALUE` 各占一行，然后 `xsim snap -f xsim_opts.f`。
  `run_v.sh`、`run_sv.sh` 已自动这样组装参数，用法照旧写 `+SEED=7 +FULL`。

---

## 五、这几支台架里"抓到的真问题"

留档用的台架的价值就在于抓错，例子也不例外：

1. **`rtl/ex_sync_fifo.v` 的 `full` 晚一拍**：原写法 `full <= (level == DEPTH)` 而写门控用当拍
   `full`，导致写满后还能再吞一笔。是 `v/v04` 的溢出判据（`level=17`、`full=0`）抓出来的，
   改成按"下一状态" `nxt_level` 生成 flag 后转绿。
2. **`v/v05` 自己把模型写错**：跳拍的激励分支（背压空转、复位注入）绕过了黄金模型推进，
   3000 拍红 1537 条，看着像 DUT 天崩。修法是把"激励 + 模型"合并到同一个下降沿决策点。
3. **`v/v06` 的容量账**：行缓存按 `y*MAX_W` 索引却只分配了 4 行，超出后写入静默丢弃 →
   尾部若干行输出 X。改成环形 `slot = y % LINES`（工程 `raw_line_delay` 的真实形状）后正确。
4. **`sv/sv01` 的 992 条假红**：`px565_t` 写成 `{logic [4:0] r, g, b}`（5+5+5）而 RTL 是
   5+6+5，字段整体错开。→ "结构体字段宽度必须与 RTL 位切一致，写完先打一笔核对"。
5. **`sv/sv02` 的 4 条 ModelSim Error**：断言写成了"激励纪律"（full 期间不许举 `wr_en`）
   而不是**不变量**；而这个设计的合法行为恰恰是"full 时举 wr_en、写被吞"。
   → 断言要断"系统必须成立的性质"。
6. **`sv/sv04` 的 256 次"通过"被当成违例**：并发断言无 `else` 的动作块是**通过动作**。
7. **`sv/sv05` 行边界那一拍的假红**：`de_o` 来自上一拍而 `dut.y` 已 +1，
   需要 `$past(dut.y, 1)` 对齐。

每一条在源码注释里都留了"现象 → 根因 → 修法"，读注释比读文档更快回到当时的现场。

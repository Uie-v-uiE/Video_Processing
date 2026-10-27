# 01 · Verilog 台架：仿真函数、系统任务与编写手法

> 读这一份需要：会写 Verilog RTL（`always`/`reg`/`wire`/模块例化/参数），不需要会写台架。
> 所有代码都在 `examples/` 里能跑；所有"工具行为"都是本机 **Vivado 2025.2.1 xsim** 与
> **ModelSim SE-64 2020.4** 实测得到的，不是抄手册。实测口径见 `README.md`。

---

## 目录

- [§0 先把"仿真在做什么"讲清楚](#0-先把仿真在做什么讲清楚)
- [§1 一支台架的六个部件](#1-一支台架的六个部件)
- [§2 系统任务与系统函数全表](#2-系统任务与系统函数全表)
- [§3 编写手法：从能跑到可信](#3-编写手法从能跑到可信)
- [§4 视频/图像类 DUT 的台架专门手法](#4-视频图像类-dut-的台架专门手法)
- [§5 陷阱清单（本机实测过的都标了来源）](#5-陷阱清单本机实测过的都标了来源)
- [§6 与本工程 `sim/` 82 支台架的口径对照](#6-与本工程-sim-82-支台架的口径对照)

---

## §0 先把"仿真在做什么"讲清楚

写台架 90% 的怪事（"我明明写了它却没读到"、"值对但时序差一拍"、"波形对日志错"）都来自
不理解**事件调度**。Verilog 仿真的每个时刻（time step）不是一瞬间，而是一串**区（region）**：

```text
      ┌── Active ──────────┬── Inactive ──┬── NBA ─────────┬── (之后) ─┐
时间 →│ 阻塞语句/连续赋值   │ #0 里的语句   │ 非阻塞 <= 落值  │ 输出/监视  │
      │ 沿触发的 always     │              │                │ $strobe   │
      └────────────────────┴──────────────┴────────────────┴───────────┘
```

三条直接推论，贯穿全部台架写法：

1. **同一拍里，非阻塞赋值写完读不到新值。**
   `wr_en <= 1'b1; if (wr_en) ...` 里的 `if` 在 Active 区跑，读到的还是旧值。
   这就是 `examples/v/v05_random_stress.v` 第一版模型错位的根因（注释里写了全过程）。
2. **DUT 在沿上采到的是"沿之前"的值。**
   所以台架的采样点必须**错开**：`@(posedge clk); #1;` 或 `@(negedge clk)`，
   或者干脆用 `$strobe`（它在时间步末才算值）。
3. **`#0` 只跨 Active→Inactive，不跨 NBA。** 想用 `#0` 躲竞争是躲不干净的，
   要么给真实的小延时（`#1`），要么改用采样语义（`$strobe`/SV 的 clocking block）。

另外两个基础概念：

- **仿真时间 ≠ 墙钟时间。** `$time`/`$realtime` 给的是仿真时间；跑多久是工具的事。
  本报告里 `v03` 穷举 65536 组，仿真时间约 655µs，墙钟只花几秒。
- **X 不是错误值，是"还不知道"。** 台架最重要的能力之一是把 X 当成**合法期望**
  （行缓存的引导期必须输出 X，见 `examples/v/v06_video_raster.v`），
  同时把"本该已知却是 X"当成硬故障。两者用 `===`/`!==` 区分，不能用 `==`。

---

## §1 一支台架的六个部件

任何台架，不管多简单，都由这六块拼成。缺任何一块，仿真结论就会打折：

| 部件 | 作用 | 少了会怎样 | 例子文件里的位置 |
|---|---|---|---|
| ① `` `timescale `` | 定时间单位与精度 | 沿的相对位置、取整行为随编译顺序变 | 每个文件第一行 |
| ② 时钟 | 提供节拍 | —— | `always #5 clk = ~clk;` |
| ③ 复位 | 给 DUT 一个已知起点 | 第一帧/第一笔数据全不可信 | `repeat(3) @(posedge clk); @(negedge clk) rst_n = 1;` |
| ④ 激励 | 把输入推到 DUT | —— | `task drive_and_sample(...)` |
| ⑤ 检查（记分板） | 逐条判据比对 | 波形看到 ≠ 判过；人眼回归不可复用 | `expect565(...)`、`errors` 计数 |
| ⑥ 收尾 + 看门狗 | 打判定行、限时收场 | 卡死的仿真永远不出结论 | `VERDICT` 行、独立 `initial` + `$finish` |

最小可用骨架（可直接抄，`examples/v/v02_clock_reset.v` 是它的展开版）：

```verilog
`timescale 1ns/1ps
module tb_xxx;
    localparam integer TCLK = 8;              // 周期 8ns

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    integer     errors = 0;                   // ⑤ 判据计数
    integer     i;

    always #(TCLK/2) clk = ~clk;              // ② 时钟

    dut #(.W(8)) u (.clk(clk), .rst_n(rst_n), /* … */);   // 被测

    initial begin : stim                      // ③+④+⑤
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;          // ③ 异步复位、同步释放
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            din <= i;                          // ④ 非阻塞驱动：与 DUT 采样点错开
            #1;                                //    采样前错开 1ns：等 NBA 落定
            chk(i);                            // ⑤ 一条判据一次红
        end
        if (errors == 0) $display("PASS tb_xxx ALL");
        else             $display("FAIL tb_xxx errors=%0d", errors);
        $display("VERDICT tb_xxx: %s || FAIL 行数=%0d", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

    initial begin                             // ⑥ 看门狗：独立进程，到点强停
        #1_000_000;
        $display("VERDICT tb_xxx: FAIL timeout");
        $finish;
    end
endmodule
```

要点：

- **`errors` 计数 + 一条 `VERDICT` 收尾行**。这是把"仿真"变成"回归"的分界线：
  脚本只 grep 一行就能判绿/红，不必读整段日志。
- **看门狗是独立 `initial`**，不是主流程里的一个分支。主流程卡在 `wait()` 上时，
  只有独立进程能收场。
- **`$finish` 会把所有进程一起杀掉**。所以收尾对账（`in_cnt == out_cnt` 之类）必须在
  `$finish` **之前**，而且要给 DUT 留排空时间——`v06` 第一次就少了排空，
  记分板少检 4 笔，靠 `in/out` 计数对账才暴露。

---

## §2 系统任务与系统函数全表

按用途分组。"本机行为"列写的是实测差异，手册与实现不一致时以实现为准。

### 2.1 显示与打印

| 名字 | 语义 | 何时用 | 本机行为 |
|---|---|---|---|
| `$display` | 打印并换行，**立即**按当前值取参数 | 绝大多数判据行 | 支持 |
| `$write` | 打印不换行 | 拼一行、打表头 | 支持 |
| `$strobe` | 在**当前时间步末尾**取值再打印 | 同一拍内多处改同一信号，想看终值 | 支持（实测：同拍先 `a=11` 再 `a=22`，`$display` 打 11、`$strobe` 打 22） |
| `$monitor` | 监视列表，**任一参数变化**就整条重打 | 交互调试；回归里慎用（日志会爆） | 支持；被监视量赋值前先 `$monitoroff` 才干净 |
| `$displayb/-o/-h` | 等价于 `%b/%o/%h` | 少用 | 支持 |
| `$fdisplay/$fwrite/$fstrobe/$fmonitor` | 上面几个的"到文件"版 | 落档对拍、逐字节留档 | 支持 |
| `$fflush` / `$fflush(fd)` | 把缓冲刷到盘 | **每写完关键行就刷** | 支持；不刷就崩溃丢尾部 |
| `$fclose(fd)` | 关通道 | 收尾 | 支持 |

#### 格式符（`$display` 家族）

| 符 | LRM 含义 | xsim 实测 | 用法提示 |
|---|---|---|---|
| `%b` / `%o` / `%h` | 二/八/十六进制 | ✓ | 判据行首选 `%h`（短） |
| `%H` | **大写**十六进制 | ✗ 仍打小写（`8'hA5` → `a5`） | 想大小写一致就自己保证 |
| `%u` | 无符号十进制 | ✗ 打成二进制（`8'hA5` → `10100101`） | 别用 `%u`，用 `%0d` |
| `%d` | 十进制（按符号性） | ✓ | `8'hA5` 无符号→165；有符号→-91 |
| `%s` | 字符串 | ✓ | `reg [8*N:1]` 未用的高位会打成**大片空格**；用 `%0s` 裁掉 |
| `%t` | 时间 | ✓ 但默认标度不可读：`1234.5ns` 打成 `1235000` | 先 `$timeformat` 再用 `%0t` |
| `%e`/`%f`/`%g` | real | ✓ | 打印耗时/斜率用 |
| `%c` | 单字符 | ✓ | 串口/ASCII 协议台架有用 |
| `%m` | 当前作用器的**层次路径** | ✓ | 失败行自带路径，省一半定位时间 |
| `%l`/`%v` | 逻辑值/信号强度 | 不建议依赖 | 工具差异大，用前先验 |
| `%0d`、`%8d`、`%-8d`、`%08d` | 最小宽/右对齐/左对齐/补零 | ✓ | 打表用 `%-8s` 起列 |
| `x`、`z` 的呈现 | 视格式而定 | `%h` 下 `4'b1x0z` → `X`、`4'bz1z0` → `Z`（单字符、大写） | 判据别指望 `x/z` 的字符串形状稳定 |

**判据行的推荐形状**（工程 `sim/` 82 支台架都走这个格式，照抄即可）：

```verilog
$display("FAIL %0s got=%h exp=%h t=%0t path=%m", tag, got, exp, $time);
```

自带五件信息：**哪条判据、实值、期望值、时刻、层次路径**。红了不必重跑就能定位。

### 2.2 时间族

| 名字 | 类型 | 用途 | 注意 |
|---|---|---|---|
| `$time` | `time`（64 位无符号） | 当前仿真时间，按**时间单位**取整 | 实测 `13.57ns` 处 `$time` → `14`（四舍五入），不是截断 |
| `$stime` | 32 位 | 短时间回归 | 长跑会回绕 |
| `$realtime` | `real` | 需要小数时刻（算耗时、算频率） | 用它做差再打印 real |
| `$timeformat(u, w, s, m)` | —— | 改 `%t` 的显示 | **必须在 `$monitor` 之前设**，否则老 monitor 行还是旧格式 |
| `$printtimescale(scope)` | —— | 打印某作用域的 unit/precision | 本机输出 `Timescale of (tb) is 1ns/1ps.` |
| `$time` 与 `` `timescale `` | —— | 单位/精度由**每个文件**各自声明 | 多文件混编时，取全局最小精度；非整数周期会被取整 |

`` `timescale `` 与"非整数周期"的关系值得单独说一句：
`1ns/1ps` 下 `#3.2` 是精确的 3200ps；`1ns/1ns` 下 `#3.2` 变成 `3`。
所以想跑 6.4ns（156.25MHz）这类周期，**必须**把精度写到 `1ps` 或更小。
`examples/v/v02_clock_reset.v` 用两个不同频率的时钟演示了这点（PROBE 行）。

### 2.3 仿真控制

| 名字 | 语义 | 备注 |
|---|---|---|
| `$finish` / `$finish(0/1/2)` | 结束仿真。级别 0 只退、1 打文件行号、2 打仿真器状态 | 级别参数实测有效（xsim 打 `$finish called at time : … Line 176`） |
| `$stop` | 挂起进入交互 | 批跑链（`xsim -R`）里会把进程停住，**别在回归里用** |
| `$fatal`、`$error`、`$warning`、`$info` | SV 的消息任务 | 在 xsim 上对 `.v` 也接受，但严格说属 SV；见 02 文档 |
| **退出码** | —— | **`$finish` 无论判定如何都返回 0**。判定必须由台架打行、脚本 grep（`VERDICT`/`FAIL`），这就是工程 `run_one.sh` 的作 |

### 2.4 随机族

| 名字 | 返回 | 用法与坑 |
|---|---|---|
| `$random` / `$random(seed)` | 32 位**有符号** | 带参数时用该值重置内部链。要无符号就取绝对值或改 `$urandom` |
| `$urandom` | 32 位**无符号** | 严格说属 SV-2005，xsim 在 Verilog 模式下也接受（工程 `sim/` 有用） |
| `$urandom_range(a, b)` | 区间内整数 | 含端点；`$urandom_range(0,1)` 是"一半一半" |
| `$random % N` | —— | **不要这样取模**：有符号 + 偏置，分布歪。用 `$urandom_range` |
| `{$random, $random}` | 64 位 | 拼更宽随机数的常规写法 |

四条必守（`examples/v/v05_random_stress.v` 逐条实现）：

1. **打印种子，并允许命令行给种子**：
   ```verilog
   if (!$value$plusargs("SEED=%d", seed)) seed = $urandom;
   $display("INFO SEED=%0d （红了重放：把 SEED=%0d 交给 --testplusarg）", seed, seed);
   ```
   否则随机回归红了就是永久谜案。
2. **随机数先取值存变量再用**。`buckets[$urandom_range(0,9)] = buckets[$urandom_range(0,9)] + 1;`
   左右是两个不同的数，桶会自己飘走。
3. **拒绝采样必须有尝试上限**。裸 `while (1) if (cond) ...` 一旦约束太紧，仿真永不停。
4. **随机数发生器是量具，先自校**：抽 2 万次分 10 桶，min/max 落在预期带外就先怀疑量具。

### 2.5 文件族

| 名字 | 语义 | 实测要点 |
|---|---|---|
| `$fopen(name)` / `$fopen(name, "w"/"a"/"r")` | 打开，返回句柄；0=失败 | 文本/二进制模式由工具决定；工程里只做文本够用 |
| `$fwrite` / `$fdisplay` / `$fmonitor` / `$fstrobe` | 写到句柄 | 同 `$display` 家族的差别（换行/时机） |
| `$fflush` / `$fclose` | 刷/关 | **关键行之后必刷** |
| `$fgets(v, fd)` | 读一行到 `reg [8*N:1]` | 返回读到的字符数；`%s` 打印会带 NUL 空格 → 用 `%0s` |
| `$fscanf(fd, fmt, out...)` | 格式化读 | **到 EOF 返回 -1**（实测），必须据此跳出，否则死循环 |
| `$feof(fd)` / `$ferror(fd)` | 文件尾/错 | `$feof` 只对文本通道可靠 |
| `$readmemb/$readmemh(file, mem)` | 加载数组 | 文件里支持 `//`、`/* */` 注释与 `@hh` 稀疏地址；**未被覆盖的槽位保持 X**；数据位宽由**数组元素位宽**决定；越界报 WARNING |
| `$writememb/$writememh(file, mem, lo, hi)` | 落档数组 | 闭区间 `[lo, hi]`；用来与黄金文件 `diff` |

**路径口径**（非常常见的坑）：`$fopen`/`$readmemh` 里的相对路径按**仿真进程的工作目录**解析，
不是 `.v` 文件所在目录。`examples/run_v.sh` 因此在跑之前把 `data/` 拷进运行目录，台架里只写裸文件名。

一份能演示全套用法的台架：`examples/v/v04_file_io.v`（`$readmemh` → FIFO → `$fwrite` 落档 →
`$fscanf` 读回自己写的表做"文件自环"校验 → `$writememh` 存镜像）。

### 2.6 类型转换与检查族

| 名字 | 语义 | 备注 |
|---|---|---|
| `$signed` / `$unsigned` | 改符号性，不改位型 | 有符号 `8'hA5` 用 `%0d` 打是 -91；无符号 165 |
| `$rtoi` / `$rtoreal` / `$itor` | real ↔ int | 除法是整数除，写 `/4.0` 才得小数 |
| `$bitstoreal` / `$realtobits` | real ↔ 64 位位型 | 打日志/存浮点用；实测 `41.25` 往返一致 |
| `$realscale` / `$realprecision` | 工具相关 | 不建议依赖 |
| `$countones` / `$onehot` / `$onehot0` / `$isunknown` | 判位型 | **xsim 的 Verilog 模式拒绝这几个**（报 `not allowed in this dialect; use SystemVerilog mode`）。要用就 `-sv`，或者自己写函数 |
| `$onehot` 类自写版 | —— | Verilog 台架里手写更安全：`function bit onehot(v); ... $countones` 不可用时用 `for` 数 1 |
| `$bits` | 位宽 | 属 SV |
| `$typename`、`$cast` | 属 SV | 见 02 文档 |

工程里最常用的自写检查函数（Verilog 通用，跨工具零风险）：

```verilog
function automatic bit is_unknown;   // automatic 属 SV，xsim 宽松接受；保守写法去掉它
    input [63:0] v;
    integer j;
    begin
        is_unknown = 1'b0;
        for (j = 0; j < 64; j = j + 1) if (v[j] === 1'bx || v[j] === 1'bz) is_unknown = 1'b1;
    end
endfunction
```

### 2.7 波形与调试

| 名字 | 语义 | 本机行为 |
|---|---|---|
| `$dumpfile("x.vcd")` / `$dumpvars(0, tb)` | 输出 VCD | **xsim 真会产出 .vcd**（实测 7.6KB）；`0` = 递归全部层 |
| `$scope/$upscope/$enddefinitions` | 手工组织 VCD 层次 | 基本绝迹，别学 |
| Vivado GUI 波形 | 走 `.wdb` | 更常用：`xelab -debug typical` 后在 xsim 里 `log_wave -r *`，或 `run_simulation` 直接看 |
| `force` / `release` | 过程内强制信号 | 台架里用于**故障注入**（`examples/sv/sv04_sva.sv` 用它造 `de` 违例，验证断言真的能红）；注意 `force` 的右值是**表达式**，`force a = c + 1;` 是非法的 |
| 层次引用（`dut.u_sub.level`、`dut.set_raster(...)`） | 读/调 DUT 内部 | Verilog 台架最强的定位手段，SV 里没有对等替代（SV 靠 `bind`） |
| `$test$plusargs("KEY")` / `$value$plusargs("KEY=%d", v)` | 命令行开关/取值 | **xsim 只认 `--testplusarg`，裸 `+KEY` 会被拒**；而且命令行上写 `--testplusarg KEY=VALUE` 时那个 `=` 会在参数解析时被拆开（实测报 `Expected a switch but found 8`）。可用形状：**选项文件**里 `--testplusarg` 与 `KEY=VALUE` 各占一行，再用 `xsim snap -f xsim_opts.f` 跑（`run_v.sh`/`run_sv.sh` 就是这么做的） |

### 2.8 编译期工具

| 名字 | 用法 |
|---|---|
| `` `define `` / `` `undef `` | 全局宏。台架里只用于"规模常量"，别用它做逻辑 |
| `` `ifdef `` / `` `else `` / `` `endif `` | 可选段（如 `+DBG` 的打印）。回归里要保证两条路径都编过 |
| `` `timescale `` | 见 §2.2 |
| `localparam` / `parameter` | 台架参数一律 `parameter integer`，`+` plusarg 覆盖 |
| `specify`/`$setup`/`$hold`/`$width` | 时序检查族，台架几乎不用（现代流程交给 SDC + STA + SV 断言） |

---

## §3 编写手法：从能跑到可信

### 3.1 时钟与复位的写法

| 写法 | 何时用 | 代价 |
|---|---|---|
| `always #5 clk = ~clk;` | 单时钟、固定频率 | 频率硬编码 |
| `always #(TCLK/2) clk = ~clk;` | 参数化 | 精度必须到 ps，否则非整数周期被取整 |
| `initial begin clk=0; forever #(T/2) clk=~clk; end` | 跑一半改频率（CDC、频偏测试） | 需要 `forever` 与判据进程分开 |
| 异步复位**同步释放**：`repeat(2) @(posedge clk); @(negedge clk) rst_n=1;` | 一律推荐 | —— |
| 直接在 `t=0` 拉高 `rst_n` | **别用** | 复位释放与第一个沿同刻，DUT 采到什么看运气 |

为什么在 **negedge** 释放复位：让释放点离采样沿半个周期，无论 DUT 用哪种沿敏感 always
块，都不会出现"这一沿一边复位一边采"的竞态。`v02` 就是这么写的。

### 3.2 驱动与采样的相位（台架的核心纪律）

Verilog 没有 clocking block（那是 SV 的），所以相位纪律只能靠人守。三种可行方案：

| 方案 | 写法 | 优点 | 缺点 |
|---|---|---|---|
| **A. 下降沿驱动 + 上升沿后 1ns 采样**（本报告 `v03`/`v04`/`v05` 用这个） | `@(negedge clk) din = v; ... @(posedge clk); #1; got;` | 彻底避开竞争；`#1` 只与时间单位有关 | 满占空比时钟下 `#1` 需大于 NBA 延迟 |
| B. 上升沿**非阻塞**驱动，下一沿看结果 | `@(posedge clk) wr_en <= 1;` | 与 RTL 风格一致 | 同拍读 `wr_en` 读到旧值，模型极易错位（`v05` 第一版就栽在跳拍分支上） |
| C. `$strobe` 采样 | `@(posedge clk) $strobe("v=%h", val);` | 时间步末取值，天然躲 NBA | `$strobe` 不能赋值，只能打；判据要另写 |

**方案 A 的标准 task 形状**（把它当成肌肉记忆抄进每支新台架）：

```verilog
task drive_and_sample;
    input [15:0] v;
    input        de;
    begin
        @(negedge clk);  din = v; de_i = de;   // 阻塞：这是"下一拍生效的输入"
        @(posedge clk);  #1;                   // DUT 已采，NBA 已落
    end
endtask
```

配套的两条纪律：

- **一个信号只有一个进程驱动**。`rst_n` 若在两个 `initial` 里都改，先后次序未定义
  （`v05` 的复位注入因此改成"主循环发请求、激励进程执行"）。
- **握手类信号要举恰好一拍**。`v04` 早期版本读回整体错位，就是因为 `rd_en` 举成
  了连续电平，FIFO 每拍都在弹，而台架两拍才采一次。正确形状：

  ```verilog
  @(posedge clk); rd_en <= 1'b1;   // 本沿 DUT 还看不到（NB 未落）
  @(posedge clk); rd_en <= 1'b0;   // 这一沿真弹了一个；同时关掉，只弹一次
  #1;                              // 再采样
  ```

### 3.3 task / function 的真实语义（Verilog 里最容易被骗的一处）

- **Verilog 的 task/function 默认是 `static`**：所有调用共用同一份局部变量。
  递归调用、或从多个并发进程同时调同一个 task，局部量会互相踩。
  工程 `sim/xtest.v` 那 20 行隔离实验研究的就是"函数在拼接里被调 4 次"时
  `integer` 形参/位切的行为——同一个坑。
- `automatic` 关键字属 SV（xsim 在 `-sv` 下都接受；纯 Verilog 模式建议不要依赖）。
  **保守做法**：task/function 里不要留需要跨调用保持的局部量；要状态就放模块级变量。
- function **不能有延时**，task 可以。所以"检查"写成 function，"激励"写成 task。
- task/function 的形参方向要写全（`input`/`output`/`inout`）。`input` 形参是拷贝，
  改它不影响调用者。
- **字符串参数用定宽位向量**：`input [8*24:1] tag;` + `%0s`。这是 Verilog 没有
  `string` 类型时给判据打标签的标准手法（`v03` 就这么做）。

### 3.4 自检记分板的四条设计规则

1. **一条判据最多红一次**。红多行会把"失败条数"变成"重复条数"，回归脚本没法定退出码。
   （工程 `run_one.sh` 数的是 `^ *FAIL` 行数，缩进也认，所以判据行不许换行。）
2. **判据必须能红**（falsifier）。每加一条判据，同时想清楚"什么情况下它会红"；
   最好在台架里留一条"故意违反"的腿，跑一次证明它会红。
   `examples/sv/sv04_sva.sv` 的 `p_falsifier` + `force dut.de` 就是这个用法的完整示范。
3. **成功不打印，失败自带上下文**。`v03` 穷举 65544 条判据，屏幕上只有 6 行 ——
   日志体积与判据数解耦，才敢把规模开到全空间。
4. **覆盖数也要对账**。`v06` 收尾判 `checked == V_ACTIVE*H_ACTIVE*NFRAMES`：
   "少检查"是比"检查不过"更危险的失效模式，只有计数能发现。

黄金模型的原则：**与 RTL 走不同的实现路径**。
`v03` 里 RTL 是位切 `{r[7:3], g[7:2], b[7:3]}`，模型是十进制 `r/8, g/4, b/8`。
两边同时错的概率远低于复制粘贴 RTL 的"模型"。

### 3.5 层次引用与内部状态检查

Verilog 台架的独门优势：直接看 DUT 里面。

```verilog
if (dut.level !== expected_count) ...          // 读内部计数
dut.set_raster(0, 0);                          // 调 DUT 里的 task（帧沿归零坐标）
force dut.de = 1'b1;  ...  release dut.de;     // 注入违例，验证检查器
```

代价：**台架与 RTL 内部结构耦合**，改名就会红。使用原则——
只在"外部观测无法区分两种错法"时才用内部引用，并在注释里写明为什么必须用。

### 3.6 队列、内存与简易 BFM（没有 class 怎么做面向对象的事）

Verilog 里手工搭一个 FIFO 型队列（`v04`/`v05` 的做法）：

```verilog
integer model[0:DEPTH-1];      // 环形队列
integer mp, mc;                // 队头指针 + 存量
// 入队：model[(mp+mc)%DEPTH] = v; mc++;
// 出队：v = model[mp];        mp = (mp+1)%DEPTH; mc--;
```

三个必踩的坑，提前记：

- 入队位置是 `(mp+mc)%DEPTH`，**不是** `mp`。写成 `model[mp]` 会把队头数据盖掉
  （`v05` 初版就是）。
- 台架的容量账必须自己算：`DEPTH=16` 的 FIFO 一次灌 24 笔必然吞 8 笔，
  于是"整体错位"看起来像 DUT 坏了。`v04` 现在把 `n_put` 限制到 12，并**另开一段**
  专门做溢出判据。
- 模型推进点必须与激励推进点在**同一个时钟沿**，且不能被跳拍分支绕过（§3.2）。

总线 BFM 的最小形状（一主一从的握手，Verilog 版）：

```verilog
task bus_write; input [15:0] a; input [31:0] d; begin
    @(negedge clk); awvalid = 1; awaddr = a; wvalid = 1; wdata = d;
    @(negedge clk);
    while (!awready || !wready) begin            // 背压：等就绪，别假设一拍通过
        awvalid = awready ? 1'b0 : 1'b1;
        wvalid  = wready  ? 1'b0 : 1'b1;
        @(negedge clk);
    end
    awvalid = 0; wvalid = 0;
end endtask
```

### 3.7 并行与"多过程"结构

Verilog-2001 有 `fork/join`，**没有** `join_any` 和 `disable fork`（SV 才有，实测
`join_any` 在纯 Verilog 模式下直接语法错）。Verilog 里的等价手法：

- 并行启动后各自跑到 `$finish`：多个 `initial` 就是并行，这是最常用形态；
- 要"等第一个完成"：用标志位 + `while (!flag) @(posedge clk);`；
- 要"超时打断"：看门狗 `initial` 里 `$finish`（代价是整场结束，不能只停一支）。

### 3.8 超时、卡死与"静默失败"

三类看门狗，按成本从低到高：

1. **全局超时**：`initial begin #T; $display("VERDICT tb: FAIL timeout"); $finish; end`
2. **活性看门狗**：计数"多少拍没有任何前进"，超阈值就收场
   （`v06` 的 `stall` 计数器，视频台架尤其需要——它卡死时波形一片平静）。
3. **进度打印**：每 N 笔打一行 `INFO progress`，长跑时用来区分"慢"和"死"。
   注意热循环里的 `$display` 会显著拖慢仿真，取里程碑打即可。

### 3.9 让规模可控，让回归可分档

```verilog
if ($test$plusargs("FULL")) n_iter = 20000; else n_iter = 3000;   // 快慢两档
if ($value$plusargs("SEED=%d", seed)) ;                            // 种子
```

工程 `sim/` 的跑法是把 `SIM_ARGS="+FULL"` 传给 xsim（`run_sim.tcl` 在 Vivado 的 Tcl 里
`exec xsim …`，参数不会被 `=` 拆开；在 bash 里直接 `xsim.bat --testplusarg KEY=VALUE` 就会被拆，
所以 `run_v.sh`/`run_sv.sh` 统一改走 `-f` 选项文件）。
建议的三档：`smoke`（几十拍，秒级）→ `default`（分钟级）→ `full`（全空间/长随机，夜里跑）。

### 3.10 仿真性能的现实约束

| 手段 | 效果 |
|---|---|
| 判据只在失败时打印 | 大得多（`$display` 是串格式化，很贵） |
| 数组规模别乱给 | `v06` 早期行缓存数组按"整帧"给，写成 `4*MAX_W` 却按 `y*MAX_W` 索引 → 越界丢数据。**容量账 = 语义账** |
| 只记录需要看的信号 | xsim 用 `log_wave` 精确选信号，比 `-w` 全打快 |
| 长向量交文件 | `$readmemh` + `$writememh` 对拍比 `for` 循环里现算快且可复核 |
| 穷举 vs 随机 | 全空间可穷举（16 位内）就穷举；超出就随机 + 定角点 + 覆盖率闭合 |

---

## §4 视频/图像类 DUT 的台架专门手法

工程里 82 支台架一大半是视频通路，这几条是这类 DUT 独有的：

### 4.1 激励按"光栅"组织，不按"总线"组织

```verilog
for (row = 0; row < V_ACTIVE; row = row + 1) begin
    blank(hblank);                                  // 行消隐（长度可随机，探串列边界）
    for (col = 0; col < H_ACTIVE; col = col + 1)
        pixel({row[7:0], col[7:0]});                // ★ 像素值自带坐标
end
blank(vblank * H_TOTAL);                            // 帧消隐
```

- **像素里塞坐标**（`{row, col}`）而不是塞随机数：任何一格错位，从 `got=%h` 就能读出行列。
  `v06` 的失败行 `输出第 35 行第 26 列 got=xxxx exp=211a` 就是这么自解释的。
- **消隐期长度是可调参数**。很多 bug（列错位、越界填黑、拷贝越窗）只在消隐长度变化时现形，
  所以把 `hblank`/`vblank` 做成变量甚至随机的，比固定值有用得多。
- **DUT 的 x/y 只在 `de` 上推进**（工程里 `raw_line_delay` 就是这语义），
  所以行内 `de` 拍数必须**正好等于** DUT 的 `MAX_W`；短了行不推进，长了行溢出。
  这条限制要写进台架注释（`sv05` 把它写进了 constraint，见 02 文档 §8）。

### 4.2 记分板坐标系必须与 DUT 一起归零

DUT 的 `y` 在帧沿被复位（或由台架调 `set_raster` 归零），记分板的 `out_row` 也必须归零。
`v06` 的 `frame_mark` 就是这个同步手段：

```verilog
dut.set_raster(0, 0);       // 层次引用：通知 DUT 归零
frame_mark  = 1'b1;         // 同一时刻通知记分板归零（采集线程下一个沿消费它）
```

另一种更稳的做法：**把"输出流"按下标编号**，期望值 = `in[k - LINES*W]`，
坐标系根本不需要重建（`sv05` 的 `line_model` 就是这个模型，它对"丢掉整行"也成立）。

### 4.3 引导期的 X 是判据，不是噪声

行缓存的前 `LINES` 行必须输出 X（还没写过）。台架要**主动断言它是 X**：

```verilog
if (pix_o !== {DATA_W{1'bx}}) begin ... end     // 引导期不该有"看起来对"的值
```

反过来说：引导期结束（`y >= LINES`）之后还出现 X，就是硬故障——这条适合写成断言
（`sv05` 的 `a_no_x_in_steady`，注意跨拍采样要用 `$past(dut.y,1)` 对齐，见 02 文档 §8）。

### 4.4 逐像素对账 + 计数对账

两个都要，缺一个就会漏：

```verilog
if (in_cnt !== out_cnt) ...;                                   // 收一拍就该吐一拍
if (checked !== V_ACTIVE*H_ACTIVE*NFRAMES) ...;                // 覆盖数闭合
```

`v06` 第一次跑红，就是因为 `$finish` 抢在最后一行输出落地之前，`checked` 少 4 笔；
加了 `#200` 排空 + 这两条对账才把它变成一条明确判据。

---

## §5 陷阱清单（本机实测过的都标了来源）

按"踩到时的现象"排序，前三条最容易让人怀疑人生：

1. **模型与 DUT 错位，红了上千条**——跳拍的激励分支绕过了模型更新（`v05`），
   或模型入队写到队头（`wp` 写错）。→ 见 §3.2/§3.6。
2. **位宽/字段对齐造成的假红**——把 16 位向量塞进 5+5+5 的结构体，字段整体错开
   （`sv01` 早期 992 条假红）。→ **结构体字段宽度必须与 RTL 位切一致**，写完先打一笔。
3. **检查位宽窄于被检信号**——`level` 是 5 位，task 形参给了 8 位，高 3 位读成 X：
   `FAIL level_after_10_wr got=Xa exp=0a`（`v02`）。→ 形参按 `ADDR_W:0` 声明。
4. **握手信号举成连续电平**——`rd_en` 一直为 1，DUT 每拍弹、台架两拍采 → 整体错位（`v04`）。
5. **容量账算错**——一次灌入超过 FIFO 深度，多余写被吞，判据"看起来是 DUT 错"（`v04`）。
6. **RTL 的 `full/empty` 晚一拍**——`full <= (level == DEPTH)` 而写门控用当拍 `full`，
   于是写满后还能再吞一笔（`v04` 的溢出判据抓到，改成用下一状态 `nxt_level` 才算 flag）。
   → 这是**真 RTL bug**，台架的价值所在。
7. **`$finish` 太早**——尾部若干拍没被检查。→ 排空 + 计数闭合（§4.4）。
8. **`while (1)` 拒绝采样**——约束太紧时仿真永不停。→ 必带尝试上限 + 失败判据（§2.4）。
9. **数组越界静默丢数据**——行缓存按 `y*MAX_W` 索引却只分配了几行。→ 索引式与容量一起复核。
10. **记分板坐标系不跟帧归零**——第 2 帧起整体错位。→ `frame_mark` 或流下标模型（§4.2）。
11. **Verilog 关键字当名字**——`buf`（门原语）、`small`（实指数标度）都报语法错（本机各踩一次）。
12. **无位宽的字面量至少 32 位**——`got !== "xxxx"`（`'hxxxx` 实为 `32'h0000_xxxx`）与 16 位
    值永不相等 → 引导期判据假红。写 `!== {DATA_W{1'bx}}` 或逐字段比。
13. **`$fscanf` 到 EOF 返回 -1**，不当 -1 处理就死循环（xsim 实测）。
14. **文件不刷就丢尾部**——崩溃/超时后日志缺最后几行，误判"没跑到"。→ 关键行后 `$fflush`。
15. **`$monitor` 与 `$timeformat` 顺序**——先 `$monitor` 后 `$timeformat`，
    已有 monitor 行不会重排。
16. **`%u`/`%H` 在 xsim 不按 LRM**（分别打成二进制/小写）。判据行只用 `%b %o %h %d %s %t %0d`。
17. **`$time` 会四舍五入到时间单位**（13.57ns → 14）。要小数用 `$realtime`/`%t`。
18. **`%t` 默认标度不可读**（1234.5ns 打成 `1235000`）→ 台架第一句就 `$timeformat`。
19. **plusargs 形状**——xsim 只认 `--testplusarg`，`+KEY` 直接拒；且 `KEY=VALUE` 必须
    放进 `-f` 选项文件里分行写，命令行上写会被 `=` 拆开（实测）。
20. **`$finish` 不影响 xsim 退出码**——判定必须靠 grep 判据行，不能靠 exit code。
21. **`task automatic` / `$countones` 等在纯 Verilog 模式的行为**——
    `automatic` xsim 宽松接受，`$countones` 家族则直接拒；ModelSim 两者都接受。
    跨工具时要么统一 `-sv`，要么完全不用。
22. **`fork/join` 里等不齐**——`forever` 线程会让 `join` 永不返回（`sv03` 在 xsim 上表现为卡死）。
    Verilog 里干脆别用 `fork`，多个 `initial` 即可。

---

## §6 与本工程 `sim/` 82 支台架的口径对照

本教程的 `examples/` 与工程 `sim/` 用同一套约定，读懂一边就读懂另一边：

| 口径 | 工程里的实现 | 本教程例子 |
|---|---|---|
| 判定行 | 末行 `VERDICT <tb>: <判定> || FAIL 行数=<n> || PASS 行数=<m>` | 每个 `v0x`/`sv0x` 末尾同形状 |
| 判据行 | `` `PASS <标签>` / `FAIL <标签> / <说明> / <读数>`，允许缩进 | `PASS level_after_10_wr = 0a` 等 |
| 退出码 | `run_one.sh`：0 绿 / 1 编译或例化失败 / 2 拒启 / 3 判红 / 4 没有判定行 | `run_v.sh`、`run_sv.sh` 沿用同一套 |
| 看门狗 | 例如 `tb_icmp_tx_cksum.v` 的 6ms 看门狗，到点打 `RESULT <tb> FAIL timeout` | `v05`/`v06` 独立 `initial` + `$finish` |
| 全量输出留档 | `/tmp/kx/<tb>.run/run.log`（屏幕只回放 80 行） | `work_v/<tb>/run.log` |
| 源树指纹 | 同目录 `prov.txt`（顶层/台架/`src/rtl` 三枚校验和 + 时刻） | 未做（教程里靠 `git`/目录固定） |
| 单实例约束 | xsim 同刻只允许一个跑，脚本在门口拒绝第二个 | `run_v.sh` 不检查，靠使用者 |
| 编译清单走 `-f` | Windows 命令行长度上限，`xvlog -f files.f` | `run_v.sh` 直接列文件（例子少） |
| 判据能红 | `skills/` 与各台架里的 `FALSIFIER`/反面对照条目 | `sv04` 的 `p_falsifier` + `force` 注入 |
| 台架通过 ≠ 板上通过 | `board/acceptance.md` 单独列人眼项 | 同（本教程只证 RTL 行为） |

工程 `sim/tb_sync_fifo.v` 与 `examples/v/v02_clock_reset.v` 测的是同一类 DUT，
把两支对着读，能一眼看出"工程口径"与"教程口径"的差在哪：前者把每条判据都打进屏幕，
后者把成功判据静默、只留 `VERDICT` 一行——两种选择各自的理由在 §3.4。

下一份：`02-systemverilog-tb.md`（SV 相对 Verilog 的语言差别、SV 的仿真函数与手法、优劣势与迁移路线）。

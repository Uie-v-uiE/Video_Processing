# 02 · SystemVerilog 台架：差别、函数、手法与优劣

> 前置：`01-verilog-tb.md`。这一份不重复讲"什么是 NBA"，只讲 SV 把它变成了什么。
> 全部结论来自本机 **Vivado 2025.2.1 xsim** 与 **ModelSim SE-64 2020.4** 的实测：
> 每个"支持/不支持"都是逐条编译+例化+跑出来的，例子在 `examples/sv/`。

---

## 目录

- [§1 先摆正位置：SV 在台架上的增量是什么](#1-先摆正位置sv-在台架上的增量是什么)
- [§2 语言层差别（不只是 V 多了几个关键字）](#2-语言层差别不只是-v-多了几个关键字)
- [§3 SV 的仿真函数与方法](#3-sv-的仿真函数与方法)
- [§4 SV 台架手法（六件套）](#4-sv-台架手法六件套)
- [§5 优劣势：诚实清单](#5-优劣势诚实清单)
- [§6 本机工具支持矩阵（逐条实测）](#6-本机工具支持矩阵逐条实测)
- [§7 怎么把工具链接起来](#7-怎么把工具链接起来)
- [§8 从 `v06` 到 `sv05`：渐进改造的六步](#8-从-v06-到-sv05渐进改造的六步)
- [§9 SV 台架专属陷阱清单](#9-sv-台架专属陷阱清单)

---

## §1 先摆正位置：SV 在台架上的增量是什么

一句话：**Verilog 台架的可靠性靠人守规矩，SV 台架的可靠性靠语法守住。**

对照三件具体的事：

| 台架里的问题 | Verilog 的答案 | SystemVerilog 的答案 |
|---|---|---|
| 采样时刻（读到旧值/读到半更新值） | 纪律：下降沿驱动、上升沿 `#1` 采样 | `clocking` 块把采样/驱动时刻写进类型，`default input #1step output #1` |
| 总线信号一多就散（`wr_en/wr_data/full/...` 满文件） | 一堆 `reg/wire` + 手工层次引用 | `interface` + `modport`，一线一根、方向编译期检查 |
| "这条规则只在特定条件下成立" | `if (...) errors = errors + 1;` 靠人记得写 | `assert property`（并发断言）——规格本身成为可执行代码，且能被覆盖率统计 |

再补一句现实判断：**SV 的 class/约束随机/覆盖率是"规模化回归"的入口**，
但如果只测一支 20 行的组合逻辑模块，Verilog 台架（如 `examples/v/v03_scoreboard.v`）
写得干净就够用，SV 反而是负担。选型看 §5、§8。

---

## §2 语言层差别（不只是 V 多了几个关键字）

### 2.1 编译与类型系统的差别（这些决定"为什么会突然编不过"）

| 差别 | 说明 | 台架里的后果 |
|---|---|---|
| **强类型 / 表达式位宽规则** | SV 里 `int` 是 32 位两态、`bit` 是 2 态、`logic` 是 4 态；赋值/比较规则更严 | `bit [7:0] b; b = 8'hx;` → b 变成 `00`，**X 被静默吞掉**。台架里凡是可能承载未初始化值的信号，一律 `logic` |
| **`logic` 统一 `reg`/`wire`** | 一个声明既能过程赋值又能连续赋值（单驱动前提下） | 不再有"这里该 `reg` 还是 `wire`"的问题；但也失去了"多驱动会被工具立刻骂"的提示 |
| **自动作用域** | 类、`automatic` 函数/任务默认自动存储 | 修掉了 Verilog `task` 静态局部量被并发调用互踩的坑（工程 `sim/xtest.v` 研究的就是这一族） |
| **声明位置** | 块内变量声明**必须**排在语句之前（工具实测） | `initial begin a=1; int b; end` 在 xsim 直接语法错。写台架时先写声明段 |
| **成员分隔符** | 打包结构体成员之间用 **`;`**，不能用 `,` 再重复类型 | `struct packed {logic [4:0] r, logic [5:0] g;}` 报语法错；`{logic [4:0] r; logic [5:0] g;}` 才对 |
| **包（package）** | 类型/常量/函数集中一处，`import` 进作用域 | 类必须放进包（或在包可见处）；`package` 里不能放层次结构 |
| **编译单元** | 多个文件可共享一个编译单元，`$unit` 作用域存在 | `xvlog -sv` 会把 `.v` 也按 SV 解析——SV 保留字更多，老名字可能撞（本机 `buf`/`small` 只是开胃菜） |

### 2.2 数据类型的差别（台架代码量差在这儿）

| 需要存的东西 | Verilog 写法 | SV 写法 |
|---|---|---|
| 一段文本/标签 | `reg [8*24:1] tag;` + `%0s`（还要小心高位 NUL 打成空格） | `string s;` + `s.len()` / `s.substr()` / `s.toupper()` |
| 变长队列 | `integer q[0:N-1]; int wp, rp, cnt;` 手搓环形指针 | `int q[$];` → `q.push_back()/pop_front()/size()/sort()` |
| 按地址计数 | 手写哈希或大数组 | `int hist[string];` → `hist.exists(k)`, `hist.num()`, `hist.delete(k)` |
| 一帧的行缓冲 | 定长数组 + 手工索引 | `px_t rowbuf[]; rowbuf = new[w*h];`（动态数组） |
| 像素/包头 | 位切 `{r[7:3],g[7:2],b[7:3]}`，字段宽度靠数指头 | `typedef struct packed {logic [4:0] r; logic [5:0] g; logic [4:0] b;} px565_t;` 可整体当 16 位，也可 `p.g` 访问 |
| 状态机状态 | `localparam S_IDLE=2'd0; ...` 打出来是 0/1/2 | `typedef enum logic [1:0] {IDLE,RUN,DONE} st_t;` + `st.name()` 直接给符号名 |
| 初始化一片存储 | `for` 循环 | `'0`、`'{default:0}`（**注意：`'{default:}` 不能用于动态数组**，本机实测非法） |
| 通配/范围匹配 | `casez` + 位掩码 | `case … inside`、`if (v inside {[8:15], 20})` |
| 位流打包 | 手工移位拼接 | 流操作符 `{>>{a, b, c}}`、`{<<{packed}}`（xsim 要求先落成变量再打印，见 §6） |

**四个必须记住的语义细节：**

1. `'0` / `'1` / `'x` / `'z` 是"按被赋值对象的宽度填充"，写期望值极省事：
   `if (px_o !== 'x) ...` 只在"全 X"时成立。
2. `==` 遇 X 返回假（判不出），`===` 才是四态精确比较。**记分板一律 `===`/`!==`**。
3. `int`/`bit` 是 2 态：拿它接 DUT 的 `logic` 输出，X 会**静默变 0**，
   于是"未初始化导致读 0"这类 bug 被台架掩盖。→ 承载 DUT 输出的字段一律 `logic`。
4. `unique case` / `priority case` 不只是注释：它让工具生成"完备性检查"，
   漏分支/重叠分支会被报出来（替代 `full_case`/`parallel_case` 那套老 pragma）。

### 2.3 结构层的差别

| 结构 | Verilog | SV |
|---|---|---|
| 接口 | 一堆端口 + 手工层次引用 | `interface`/`modport`/`clocking`/`default clocking` |
| 并发控制 | `fork/join` | `fork/join`、`join_any`、`join_none`、`disable fork`、`wait fork` |
| 检查器 | 过程 `if` | 并发/立即断言、`checker` 结构、`bind` 非侵入挂载 |
| 台架分离 | 全塞 `module tb` | `program` 块（与 DUT 天然分域，且**自动去掉一类竞态**）、类、包 |
| 对象 | 没有 | `class`/继承/虚方法/参数化类/句柄（引用语义，不是拷贝！） |
| 覆盖率 | 没有 | `covergroup`/`coverpoint`/`bins`/`cross`/`option` |

> 句柄语义是新手最常见的坑：`a = b;` 之后 `a.x++` 会改到 `b.x`。
> 想独立就得自己写 `clone()`（`examples/sv/sv03_class_tb.sv` 里的 `clone_it()`）。

---

## §3 SV 的仿真函数与方法

### 3.1 新增/增强的系统任务与函数

| 名字 | 作用 | 台架里的典型用法 | 本机实测 |
|---|---|---|---|
| `$sformatf(fmt, …)` | 返回**字符串**（不打印） | 失败行组装、把上下文塞进队列/对象、给判据起动态标签 | xsim/ModelSim 都可用（工程 `sim/` 已有 Verilog 台架在用） |
| `$display("%p", obj)` | 聚合值打印（结构体/数组/队列整体形状） | `'`{r:31,g:0,b:31}` 这种可读输出，省去逐字段拆 | 可用，见 `sv01` 输出 |
| `$cast(dst, src)` | 运行期向下转型（返回成功/失败） | 事务基类 → 派生类 | xsim 支持 `$cast`；**但 `D'(b)` 这种静态类型转换语法被拒** |
| `$bits(expr)` | 位宽 | 参数化打包/校验宽度闭合 | 需 `-sv` |
| `$low/$high/$size`（数组方法族） | 数组边界 | 老代码里 `$size` 多，SV 推荐 `arr.size()`/`arr.num()` | 可用 |
| `$countones/$onehot/$onehot0/$isunknown` | 位型检查 | 判"独热/含 X"，比手写循环短 | **xsim 纯 Verilog 模式拒绝**，`-sv` 下可用（实测） |
| `$signed/$unsigned` | 同 Verilog | —— | 一致 |
| `$urandom` / `$urandom_range` / `$random` | 随机 | 与 Verilog 相同，但 SV 还能对 `rand` 变量走约束求解 | 一致 |
| `$test$plusargs/$value$plusargs` | 命令行 | 同 Verilog（xsim 只认 `--testplusarg`，且 `KEY=VALUE` 要经 `-f` 选项文件） | 一致（ModelSim 的 `vsim` 直接吃 `+KEY=VALUE`） |
| `$asserton/$assertoff/$assertkill` | 断言开关（可按实例/按类型） | "故意关掉检查器证明它真的在起作用"（`sv04` 用了这段） | 可用，效果实测正确 |
| `$error/$warning/$info/$fatal` | 统一消息族 | 断言失败动作首选 `$error`（工具会计数） | 可用 |
| `$sampled/$rose/$fell/$stable/$changed` | 采样值函数 | 断言里跨拍对齐（`sv05` 的行边界就靠 `$past`） | 可用 |
| `$get_coverage`/`$coverage_status` 等覆盖率 API | 读覆盖率 | 想自动化收数才需要 | **xsim 无 covergroup 数据库；`cov.report()` 都不存在**（实测报错） |
| `let`（表达式宏） | 一行式可复用布尔表达式 | 比 `` `define `` 安全 | **xsim 明确不支持**（`ERROR 43-3980 … "Let" is not supported yet for simulation`）→ 只能退回 function |
| `default disable iff` | 统一复位屏蔽 | 断言写法更短 | **xsim 不支持**（同 43-3980）→ 逐条断言显式写 `disable iff` |

### 3.2 内建方法（类型自带，不是系统函数）

```systemverilog
// string
s.len(); s.toupper(); s.substr(0,3); s.atoi(); s.replace_all("a","b");
// 队列 q
q.push_back(v); q.push_front(v); q.pop_front(); q.insert(i,v); q.delete();
q.size(); q.sort(); q.reverse(); q.sum(); q.min(); q.find_first();   // 后四个是 SV 的内置排序/查找
// 关联数组 a
a.exists(k); a.num(); a.delete(); a.first(idx); a.next(idx);
// 动态数组 d
d = new[n]; d.size();
```

`sv01_types.sv` 把 `string`/队列/关联数组/动态数组四条都用上了，
对照 `v03_scoreboard.v` 的 `reg [8*24:1]` + 环形指针写法，代码量差异一眼可见。

### 3.3 约束随机：`randomize()` 是一整套子求解器

```systemverilog
class frame_txn;
    rand int unsigned h, hblank, vblank;
    rand bit          drop_lead_row;
    constraint c_geom  { h inside {[3:12]}; }                    // 集合约束
    constraint c_blank { hblank inside {[0:6]}; vblank inside {[1:3]}; }
    constraint c_soft  { soft drop_lead_row == 0; }               // 可被冲掉的偏好
    constraint c_dist  { h dist {3 := 1, [4:9] := 6, 12 :/ 2}; }   // 权重：:= 等权、:/ 总权重
endclass

t = new(id);
if (!t.randomize()) $display("FAIL randomize 失败（约束矛盾）");     // 返回值必须判
```

必须知道的几条求解语义（都影响台架正确性）：

- **`randomize()` 会返回 0**。不判返回值，就会拿着上一轮的值继续跑，测试看起来"过了"。
- `inside {[a:b]}` 是集合，`dist` 里 `:=` 与 `:/` 不同（前者每项权重、后者总分给整段）。
- `soft` 是偏好，硬约束冲突时会被放弃——用它给"绝大多数正常场景"打底，
  再用硬约束造边界。
- 想让某个字段这一轮不随机：`t.x.rand_mode(0);`（比新建一个类省事得多）。
- 内联约束：`t.randomize() with { h == 12; };`——同一条事务做变体扫描的正规写法。
- **约束的边界必须与 DUT 的参数一致**。`sv05` 里"行宽必须等于 DUT 的 `MAX_W`"
  被写成注释与文档，因为 DUT 是按列回绕计行的：`w` 一变，坐标系就漂。
  约束随机不能造"物理上不存在"的激励。
- 求解器随机性也是量具：和 Verilog 一样要打印种子、支持复现（工具机制不同，
  xsim 走 `--testplusarg`/环境种子；商用仿真器有 `+ntb_random_seed` 一类）。

### 3.4 覆盖率：把"测到了吗"变成数字

```systemverilog
covergroup cg_txn @(posedge clk);
    option.per_instance = 1;
    cp_data : coverpoint data_seen iff (bus.wr_en && !bus.full) {
        bins zero = {8'h00}; bins lo = {[8'h01:8'h7F]};
        bins hi = {[8'h80:8'hFE]}; bins allone = {8'hFF};
    }
    cp_gap : coverpoint gap_seen { bins g0 = {0}; bins g1_3 = {[1:3]}; bins g4_6 = {[4:6]}; }
    cross cp_data, cp_gap;          // 交叉：边界值 × 边界间隔
endgroup
cg_txn cov = new();
```

- `bins` 让"分布"成为一等公民：随机跑了 20 万笔不等于测到了 0x00 与 0xFF。
- `iff` 限定采样条件（只在"真正被 DUT 收下"的那一拍算覆盖）。
- `cross` 是把两类边界组合起来的地方，工程里大量"只在 A 边界+B 边界同时出现才炸"的 bug
  靠这一条暴露。
- **采样时刻要显式控制**（`@(posedge clk)` 或 `cov.sample()`）。`sv03` 就把
  `cov.sample()` 放在 monitor 消费者线程里，让"覆盖率"跟着"真实观测"走。
- ⚠ 本机：xsim **语法接受、但没有覆盖率数据库**，`cov.report()` 直接例化失败。
  要读数字请走 ModelSim（`examples/run_ms.sh`）。

---

## §4 SV 台架手法（六件套）

### 4.1 interface + modport + clocking

```systemverilog
interface fifo_if #(parameter int DW = 8)(input logic clk);
    logic wr_en, rd_en, full, empty;
    logic [DW-1:0] wr_data, rd_data;

    clocking cb @(posedge clk);
        default input #1step output #1;      // ★ 采样在沿前最后一步，驱动在沿后 1ns
        input  full, empty, rd_data;
        output wr_en, rd_en, wr_data;
    endclocking
    clocking ob @(posedge clk);              // 监视侧：只 input
        default input #1step;
        input  wr_en, wr_data, full, empty;
    endclocking

    modport mst (clocking cb, input full, empty, rd_data, output wr_en, rd_en, wr_data);
    modport mon (clocking ob);
endinterface
```

三条实测纪律：

1. **`clocking` 里声明成 `output` 的信号不能被读**（xsim 报 `10-3226`，与 LRM 同口径）。
   所以要"看自己驱动的值"，就单开一套 input clocking（`ob`）。
2. **同一信号既 input 又 output 的写法 xsim 拒**（`10-2934 already declared`）。
3. **`#1step` 是关键**：它把"沿前的最后一个仿真步"作为采样窗，
   这一句就把 `01` 文档 §3.2 里那套 `@(posedge clk); #1;` 的人肉纪律变成了语法。

用 `sv02_interface.sv` 对 `v02_clock_reset.v`：同一支 FIFO，台架少了全部 `#1`，
读回顺序判据完全一致。

### 4.2 virtual interface：句柄怎么传

```systemverilog
class driver;
    virtual fifo_if vif;                     // ★ 成员变量
    function new(virtual fifo_if v); vif = v; endfunction
    task automatic run(int n);
        vif.cb.wr_en <= 1'b1;                // 通过 clocking 驱动
        @(vif.cb);
    endtask
endclass
```

- 类里访问接口要靠 `virtual <interface>` 句柄，**构造时传入、存成成员**。
- ⚠ **本机实测**：把 `virtual if` 当 **task/function 的形参**，xsim 的 `xelab`
  会在建数据流图阶段直接崩（`EXCEPTION_ACCESS_VIOLATION`）；成员变量写法正常。
  ModelSim SE-64 2020.4 对两种写法都能跑。→ 见 §6 表第 12 行。
- `modport` 也能做句柄类型（`virtual fifo_if.mst`），约束更紧，但工具差异更大。

### 4.3 class 化台架的最小形状（不上 UVM 也能受益）

```
generator ──mailbox──▶ driver ──▶ DUT ──▶ monitor ──mailbox──▶ scoreboard
                                            └────────────────▶ covergroup
```

`examples/sv/sv03_class_tb.sv` 就是这个形状，300 笔约束随机事务，
driver/monitor/scoreboard 三个类 + 三个 `mailbox #(txn)`。三条从 Verilog 迁移时最实用的经验：

1. **`forever` 线程不许放进 `join`**。`fork drv.run(); mon.run(); join` 里
   `mon.run()` 是 `forever`，`join` 永远等不齐 → xsim 表现为"跑到 INFO 之后卡死"。
   要么 `join_any + disable fork`，要么把监视线程写成**有界**循环（`sv03` 用的这个）。
2. **驱动必须尊重背压**。`while (vif.cb.full) @(vif.cb);` 一行，
   省掉记分板"被吞的写要不要算一笔"的两难。随机回归里，这比多写 100 行判据有用。
3. **期望队列要 `clone`**。句柄是引用；把同一个 `txn` 塞进两个 mailbox，
   driver 改了字段，期望值跟着变——判据就瞎了。`sv03` 的 `exp2sb.put(t.clone_it())` 就为此。

### 4.4 断言：把规格写成代码

```systemverilog
default clocking cb @(posedge clk); endclocking

p_de_in_active: assert property (@(posedge clk) disable iff (!rst_n)
                    de |-> ((y >= V_ACT_LO) && (y <= V_ACT_HI)))
    else begin viol++; $error("FAIL de 在视区外：x=%0d y=%0d t=%0t", x, y, $time); end
```

必须写对的三件事，都是本机踩出来的：

- **紧跟性质的语句块是"通过动作"，失败动作必须写 `else`。**
  xsim 实测：恒真性质 + 无 `else` 的动作块执行了 3 次；恒假性质 + 同样写法执行 0 次
  （工具只自己打了 `ERROR: Assertion failed.`）。
  于是把违例计数写进"通过动作"的 checker 会数出 256 次通过、0 次失败——完全反了。
- **`disable iff` 要逐条写**（xsim 不支持 `default disable iff`）。
- **单位要想清楚**：`vs`/`hs` 是行/场级信号，一条"宽度是 2"的性质实际是
  `V_SYNC * H_TOTAL` 拍。`sv04` 第一版按拍数了行，红 2 次。

跨拍配对的写法（`sv05` 的真实修正）：

```systemverilog
// ✗ 错：pix_o/de_o 是本拍寄存出来的，而 dut.y 在行尾那一拍已经 +1
(de_o && dut.y >= LINES) |-> (pix_o !== 'x)
// ✓ 对：坐标退回一拍的采样值
(de_o && $past(dut.y, 1) >= LINES) |-> (pix_o !== 'x)
```

**bind + checker：不动被测一行代码的挂载式检查**（`sv04` 用法）：

```systemverilog
bind ex_video_timing video_checker u_chk (
    .clk(clk), .rst_n(rst_n), .x(x), .y(y), .de(de), .frame_done(frame_done)
);
// 之后在台架里读计数：dut.u_chk.viol_de_outside
```

`bind` 在 xsim 上分析、例化、运行都正常；层级访问要写成 `dut.u_chk.…`
（绑定的实例挂在**每个目标实例**下面，不在顶层）。

### 4.5 判据必须能红：把这条做成机制

`sv04` 里的完整套路，值得抄进任何一支 SV 台架：

1. 一条**恒假性质**（`p_falsifier: assert property (@(posedge clk) (de |-> !de))`），
   它的 `else` 计数必须 > 0，否则说明检查器是摆设；
2. **`$assertoff` → 造违例 → 计数不动 → `$asserton` → 再造 → 计数必须加**，
   一次同时验证"开关有效"和"检查有效"；
3. 造违例用 `force dut.de = 1'b1;`（`force` 的右值必须是**表达式**，
   `force a = c + 1;` 在部分工具里非法——写 `force a = 1'b1;` 这种最稳）。

### 4.6 `program`、`checker`、并发块

- `program` 块的本意是把台架与 DUT 分成两个域，工具会自动处理一类竞态
  （台架输出在 Observed region 之后驱动）。⚠ 本机：xsim 分析接受，
  但**在 program 里实例化 interface 会被拒**（`10-8608 … is not a checker and cannot be
  instantiated in program`）→ 结论：接口在 module 里例化，需要 program 就只放流程代码。
- `checker` 结构（`checker my_chk(...); endchecker`）在 xsim 上未实测收益，
  工程里用 `bind` + `module` 检查器等价实现更保险（`sv04` 就是这个形状）。
- `fork ... join_any` + `disable fork` + `wait fork`：做"任一完成即收场"的并发腿，
  是 Verilog 里根本做不到的（`join_any` 在纯 Verilog 模式直接语法错，实测）。

---

## §5 优劣势：诚实清单

### 5.1 SV 的真实收益

| 收益 | 具体到什么程度 |
|---|---|
| 竞态被语法消灭 | `clocking` + `#1step` 之后，`v0x` 里那些 `#1` 全消失，读回顺序判据不变（`v02` ↔ `sv02` 对照） |
| 信号成组、方向编译期检查 | `modport` 把"台架不该驱动 `full`"变成编译错误，而不是三天后的一次假红 |
| 规格成为可执行代码 | `assert property` + `bind`：检查器与被测一起交付，回归自动带上，不依赖人记得写 `if` |
| 覆盖率闭合 | `covergroup`/`cross` 把"跑了很多"和"测到了"分开——随机回归没有覆盖率就是抽奖 |
| 抽象与复用 | `package` + 类 + 参数化：同一套 agent 服务多支台架；事务可以 `clone`、可以派生变体 |
| 表达力 | `string`/队列/关联数组/`$sformatf`/`%p`：`v04` 的 20 行字符串处理在 `sv01` 是 3 行 |
| 错误定位 | `$urandom` 种子 + 对象 `sprint()` + 断言自带时刻/层次：红了能重放、能读上下文 |

### 5.2 SV 的真实代价（别听宣传）

| 代价 | 本机证据 |
|---|---|
| **工具子集差异极大** | §6 一整张表：`let`、`default disable iff`、`cov.report()`、`D'(x)`、program 里实例接口、virtual if 作形参…… xsim 全部不行；ModelSim 全行 |
| **失败模式更难懂** | 不是"报语法错"，而是 `xelab` 直接 `EXCEPTION_ACCESS_VIOLATION` 崩栈（几十个 `Verific::…` 帧），普通人根本猜不到是"`virtual if` 当实参" |
| 编译/例化更慢 | SV 包 + 类 + 断言要建更大的数据流图；工程 `run_sim.tcl` 一次编 82 支 Verilog 台架要几分钟，SV 化后只会更久 |
| **2 态类型造成漏检** | `int`/`bit` 吞 X：DUT 输出未初始化时台架读到 0，判据"通过"。必须刻意用 `logic` 承载 DUT 输出 |
| 断言写反比 Verilog 更隐蔽 | "无 `else` 的动作块是通过动作"这条，写错后 checker 数字漂亮、结论完全反（§4.4） |
| 调试门槛 | 对象在波形里不是一个信号；要么 `$sformatf` 落日志，要么用工具的对象视图（xsim 较弱） |
| 约束求解不可预测 | 同一份约束在不同工具给的分布不同；回归"换工具就红"多半是种子/求解器差异 |
| 团队技能曲线 | class/mailbox/covergroup/`bind` 是四门独立知识；UVM 再叠一层。**别一上来就 UVM** |
| 与 Verilog RTL 混编 | `xvlog -sv` 把所有文件按 SV 解析，保留字更多（本机 `small`/`buf` 只是开胃）；老代码可能突然编不过 |

### 5.3 什么时候用哪个（工程判断）

| 场景 | 建议 |
|---|---|
| 单模块、组合/短流水、判据 ≤ 20 条 | Verilog（`v03` 形状）足够，写得干净比 SV 花哨更有价值 |
| 有总线协议/握手时序、要防竞态 | SV 的 `interface` + `clocking`，**这一步最划算** |
| 要随机激励 + "测到了吗"的可证明性 | SV 约束随机 + `covergroup`，并且必须有第二工具链读覆盖率 |
| 长期维护的验证资产（多个 DUT 复用） | SV 类化 agent；再上 UVM 之前先把 `sv03` 这套手写结构吃透 |
| 只用 xsim、且不允许换工具 | 走 SV 的"安全子集"：`logic`/`typedef`/`struct`/`interface`/`clocking`/断言，**不碰** class 形参传虚接口、`let`、覆盖率 API |
| FPGA 工程里做顶层长测（如视频流回归） | Verilog 台架 + `+FULL` 分档，或 SV 但保持单文件；把精力放在判据闭合（`sv05` 的流下标模型） |

---

## §6 本机工具支持矩阵（逐条实测）

口径：**分析** = `xvlog -sv` 通过；**例化** = `xelab` 通过；**运行** = 台架打印出预期判据。
表里三个勾依次对应这三关；只有一个勾表示"只过了分析"。全部行都是本机逐条跑出来的，
`examples/` 那 11 支台架在两家工具上 22 次运行全绿（判定行 `VERDICT …: PASS`，不是"看着像对"）。
ModelSim 列为 **SE-64 2020.4**（本机 `D:/Software/ModelSim`）。

| # | SV 特性 | xsim 2025.2.1 | ModelSim SE-64 2020.4 | 绕法 / 备注 |
|---|---|---|---|---|
| 1 | `logic`/`int`/`bit`/`byte` | ✓✓✓ | ✓✓✓ | 一致 |
| 2 | `always_ff`/`always_comb`/`always_latch` | ✓✓✓ | ✓✓✓ | 一致 |
| 3 | `typedef`/`enum`/`struct packed`/`union` | ✓✓✓ | ✓✓✓ | 成员分隔必须 `;`；`enum` 的 `.name()` 两边都可用 |
| 4 | 队列 / 关联数组 / 动态数组 | ✓✓✓ | ✓✓✓ | `'{default:0}` **不能用于动态数组**（xsim 报错），改 `foreach` 初始化 |
| 5 | `string` + 内建方法（`len/toupper/substr`） | ✓✓✓ | ✓✓✓ | 一致 |
| 6 | `'0`/`'1`/`'x`、赋值模式 `'{…}` | ✓✓✓ | ✓✓✓ | 逐元素 `'{…}` 里**不许混 `default`**（xsim 报"positional mixed"） |
| 7 | `case … inside`、`inside` 操作符 | ✓✓✓ | ✓✓✓ | 一致 |
| 8 | 流操作 `{>>{}}`/`{<<{}}` | ✓/✓/✓ | ✓✓✓ | xsim 要求先落成变量再进 `$display`（否则报"需要显式类型转换"） |
| 9 | `$countones/$onehot/$isunknown/$bits` | ✗（Verilog 模式）/✓（`-sv`） | ✓ | 混编时统一加 `-sv` |
| 10 | `$sformatf`/`$cast`/`%p` | ✓✓✓ | ✓✓✓ | 一致 |
| 11 | `package` + `import` | ✓✓✓ | ✓✓✓ | 类必须可见于包；`import` 放模块作用域更稳 |
| 12 | `class`/继承/虚方法/`new` | ✓✓✓ | ✓✓✓ | 一致 |
| 13 | **`virtual interface` 作为类成员** | ✓✓✓ | ✓✓✓ | 推荐写法 |
| 14 | **`virtual interface` 作为 task 形参** | 分析✓ / **例化崩**（`EXCEPTION_ACCESS_VIOLATION`） | ✓✓✓（实测 `M1 ok`） | xsim 改成员写法（`sv03`/`sv05` 全按成员写） |
| 15 | `rand`+`constraint`+`randomize()`（`inside`/`dist`/`soft`/`rand_mode`） | ✓✓✓ | ✓✓✓ | `sv03` 300 笔、`sv05` 随机帧都绿 |
| 16 | `interface`/`modport`/`clocking`（`#1step`/`default`） | ✓✓✓ | ✓✓✓ | 同信号不许既 input 又 output；`output` 项不可读 |
| 17 | `program` 块 | ✓✓✓ | ✓✓✓ | 但 program **内不能实例化 interface**（见第 18 行） |
| 18 | program 里实例化 interface | 分析✓ / 例化 ✗（`10-8608 not a checker`） | ✓ | 接口放 module 顶层 |
| 19 | 并发断言（`\|->`/`\|=>`/`##`/`[*n]`/`$rose`/`$past`/`disable iff`） | ✓✓✓ | ✓✓✓ | 失败动作必须写 `else`；`disable iff` 要逐条 |
| 20 | 立即断言 `assert(expr)` / `assert #0(…)` | ✓✓✓ | ✓✓✓ | 适合"过程式判据 + 统一计数" |
| 21 | `cover property` | ✓✓✓ | ✓✓✓ | 覆盖性质可用，与覆盖率数据库是两件事 |
| 22 | `default clocking` | ✓✓✓ | ✓✓✓ | 一致 |
| 23 | **`default disable iff`** | 分析✓ / **例化 ✗**（43-3980 未实现） | ✓ | 逐条断言写 `disable iff` |
| 24 | **`let`** | 分析✓ / **例化 ✗**（43-3980 未实现） | ✓ | 退回 `function automatic` |
| 25 | `covergroup` 定义与 `sample()` | 分析✓/例化✓/采样✓ | ✓✓✓ | xsim 能编译能跑，但**没有数据库** |
| 26 | **`cov.report()`/覆盖率读取 API** | ✗（`10-2991 'report' is not declared`） | ✓ | 覆盖率数字只能在 ModelSim/Questa/VCS 侧读 |
| 27 | `bind` + 检查器模块 | ✓✓✓ | ✓✓✓ | 层级名是 `<实例>.<bind 实例名>` |
| 28 | `checker` 结构 | 分析✓（未做运行收益验证） | ✓ | 工程上用 `bind`+module 更保险 |
| 29 | `fork` / `join_any` / `join_none` / `disable fork` / `wait fork` | ✓✓✓ | ✓✓✓ | 纯 Verilog 模式下 `join_any` 这类是语法错（实测） |
| 30 | `mailbox`（含带类型的 `mailbox #(T)`） | ✓✓✓ | ✓✓✓ | `sv03` 三个类型化 mailbox 正常 |
| 31 | `semaphore` 的 `get()/put()` | ✓✓✓ | ✓✓✓ | 实测两个并发进程互斥顺序正确 |
| 32 | `$asserton/$assertoff/$assertkill` | ✓✓✓ | ✓✓✓ | `sv04` 用它做"开关有效性"判据 |
| 33 | `unique`/`priority case` | ✓✓✓ | ✓✓✓ | 违例报告格式两家不同 |
| 34 | 静态类型转换 `px565_t'(px_o)`（packed） | ✓✓✓ | ✓✓✓ | 位向量 ↔ 结构体可用 |
| 35 | 静态类型转换 `D'(b)`（class 句柄） | ✗（语法错 near `.`） | ✓ | 用 `$cast(d, b)` |
| 36 | 中文/UTF-8 在 `$display` | ✓ 正常输出 | 控制台变 `?`（日志乱码） | 判据词保持 ASCII（`PASS/FAIL/INFO`），中文留给注释 |
| 37 | `xvlog -sv` 编 `.v` 文件 | ✓ | ✓（`vlog -sv`） | 但保留字变多：`buf`/`small`/`logic`… 撞名即语法错 |
| 38 | 队列方法 `sort()` / `unique()` / `sum()` | ✓✓✓ | ✓✓✓ | `sv01` 与逐条探针实测通过 |
| 39 | **队列方法 `min()` / `max()` / `find_max()`** | 分析✓ / **例化崩栈**（`EXCEPTION_ACCESS_VIOLATION`） | ✓ | xsim 上退回手写 `for` 求极值；其余 `find_*` 系列未逐个验证，别赌 |
| 40 | `foreach (q)`（不带下标形式） | ✗（语法错） | ✗ | 一律写 `foreach (q[i])` |
| 41 | `q = new[n]` 赋给队列 | ✗（`10-8636`：`new` 只给类/covergroup/动态数组） | ✗ | LRM 同口径；队列用 `push_back`/`delete` |
| 42 | 关联数组 `num()` / `exists()` / `delete()` | ✓✓✓ | ✓✓✓ | 自增前先 `exists` 判一次，跨工具更一致 |
| 43 | `$bits(...)` | ✓✓✓（需 `-sv`） | ✓✓✓ | Verilog 模式下 xsim 直接拒 |

---

## §7 怎么把工具链接起来

### 7.1 xsim（Vivado）

```bash
V=D:/Software/Vivado/2025.2.1/Vivado/bin
"$V/xvlog.bat" -sv rtl/*.v tb/sv03_class_tb.sv        # -sv：.v/.sv 都按 SV 解析
"$V/xelab.bat" sv03_class_tb -s snap
# plusargs：命令行上 "--testplusarg KEY=VALUE" 的 = 会被拆开，必须走选项文件
printf -- '-R
--testplusarg
SEED=7
' > xsim_opts.f
"$V/xsim.bat"  snap -f xsim_opts.f
```

Vivado 工程内：`set_property file_type "System Verilog" [get_files xxx.sv]`，
或让扩展名 `.sv/.svh` 自动识别；`run_simulation -type behavioral` 走的仍是上面三步。

### 7.2 ModelSim（本机已装，作为 SV 的"完整语义参照"）

```bash
MS=D:/Software/ModelSim/modelsim/win64
"$MS/vsim.exe" -c -do run.do     # vlib work; vlog -sv <files>; vsim -c <top>; run -all; quit -f
```

两个实测要点：

- **路径必须是 `D:/…` 风格**，MSYS 的 `/d/…` 会报 `vlog-7 Failed to open design unit file`
  （`examples/run_ms.sh` 里为此用 `pwd -W`）。
- 控制台把 UTF-8 打成 `?`：判据词保持 ASCII，中文注释留在源码里。

`examples/run_ms.sh sv/sv03_class_tb` 与 `examples/run_sv.sh sv03_class_tb` 跑的是同一支台架，
一条命令就能对比"子集 vs 完整 SV"。

### 7.3 与工程现有 Verilog 回归共存

工程 `build/sim/run_one.sh` 现在用 `xvlog -f files.f`（Verilog 模式）。
要混进 SV 台架，最小改动是**按扩展名分流**：

```tcl
# files_sv.f 里只放 .sv/.svh；其余保持 Verilog 模式
xvlog -f files.f              ;# Verilog RTL + Verilog 台架
xvlog -sv -f files_sv.f       ;# SV 台架（引用同一批 RTL）
```

这样 82 支 Verilog 台架一行不动，新增的 SV 台架也不被 `-sv` 保留字波及。
注意 xelab 需要同一快照里能解析到全部单元，`.v` 与 `.sv` 分两次分析是支持的。

---

## §8 从 `v06` 到 `sv05`：渐进改造的六步

同一支被测（行缓存 `rtl/ex_line_delay.v`），两支行台架（`v/v06_video_raster.v` ↔
`sv/sv05_video_agent.sv`）。改造顺序就是推荐的学习顺序——**每步都能独立验收**，
不要一次把六步全做完再调。

| 步 | 改什么 | 立刻得到的好处 | 风险 |
|---|---|---|---|
| 1 | `reg/wire` → `logic`；常量加类型（`localparam int`）；`integer` → `int` | 编译期更强，少一类隐式位宽错 | `int` 是 2 态，DUT 输出别用 `int` 接 |
| 2 | 判据行改 `$sformatf` + `string`，队列存失败上下文 | 日志可读、可排序、可二次统计 | 无 |
| 3 | 类型化：`typedef struct packed {logic [7:0] row; logic [7:0] col;} px_t;` | 位切不再数指头；`%p` 直接打出 `'{'row:3, 'col:12}` | 字段宽度必须与 RTL 一致，写完**先打一笔核对**（`sv01` 为此红过 992 条） |
| 4 | `interface vid_if` + `clocking cb/mcb`：驱动侧、采集侧分开 | 所有 `#1` 消失；采样窗由 `#1step` 保证；采集与驱动两套视角互不干扰 | 同信号不许既 input 又 output；`output` 项不可读 |
| 5 | 检查逻辑改成断言：`a_no_de_in_reset`、`a_no_x_in_steady`（记得 `$past`） | 规格写进接口/检查器，随例化自动生效，不用记得在循环里写 `if` | 失败动作必须 `else`；`disable iff` 逐条写 |
| 6 | 激励与检查拆成类：`frame_txn`（约束随机）+ `vdrv` + `vmon` + `line_model` | 行高/消隐/丢行都能随机；流下标模型让"丢掉一整行"这种结构变化也不会错位 | `virtual if` 只能当成员；`forever` 线程别放 `join` 里 |

改完之后与 `v06` 的行为差异（实测）：`v06` 的判据是"输出第 (r,c) 格 = 源第 (r-2,c) 格"，
依赖台架每帧把坐标系归零；`sv05` 用**全局像素流下标** `out[k] == in[k - LINES*MAX_W]`，
丢行、变行高都不需要重建坐标系——这是 SV 抽象带来的**判据鲁棒性**提升，而不只是少写几行。

---

## §9 SV 台架专属陷阱清单

（`01` 文档 §5 那 22 条依然全部适用，这里只列 SV 新增的）

1. **无 `else` 的断言动作块是"通过动作"** → 违例计数全打在 pass 分支上，数字漂亮、结论反了。
2. **`virtual interface` 当 task 形参**：xsim 上 `xelab` 崩栈，ModelSim 正常。
3. **`int`/`bit` 吞 X**：期望"未初始化=失败"的判据静默通过。承载 DUT 输出用 `logic`。
4. **跨拍配对忘了 `$past`**：`de_o` 来自上一拍、`dut.y` 已经 +1，行边界那一拍报假红。
5. **`'{default:0}` 用在动态数组**：xsim 直接例化失败，`foreach` 初始化才有。
6. **结构体成员用逗号续写类型**：`{logic [4:0] r, logic [5:0] g;}` 语法错，成员必须 `;` 分隔。
7. **打包结构体字段宽度和 RTL 位切不一致**：整体错位，判据大面红（`sv01` 992 条）。
8. **`clocking` 里 `output` 信号被读**：`10-3226`，监视侧要单开 input clocking。
9. **program 里实例化 interface**：xsim `10-8608`。接口放 module。
10. **`forever` 线程参与 `join`**：等不齐，表现为"跑到某条 INFO 之后没输出"（不是报错）。
11. **驱动无视 `full`/背压**：写被吞，期望队列与实际永远差几笔 → 死循环或错位。
12. **句柄共享**：同一对象塞两个 mailbox，一侧改，另一侧的期望跟着变。要 `clone`。
13. **`randomize()` 返回值不判**：约束矛盾时拿着旧值继续跑，"过了"但什么都没测。
14. **约束与 DUT 参数脱节**：随出了物理上不存在的帧（行宽 ≠ `MAX_W`），红得莫名其妙。
15. **断言单位混淆**：`vs` 的"宽度 2"是 2 行 = `2*H_TOTAL` 拍。
16. **依赖 `let`/`default disable iff`/覆盖率 API**：xsim 三者都没有（§6 表 23/24/26）。
17. **`D'(b)` 静态类转换**：xsim 语法错，改 `$cast`。
18. **`-sv` 下老名字撞保留字**：`buf`、`small`、`logic`、`bit`… 本机两个都踩过。
19. **`cov.sample()` 时机与观测不同步**：覆盖率数了驱动意图而不是总线事实。
20. **换工具就红**：种子/求解器分布差异。判据要写成"分布是否闭合"，不要写死某一轮序列。

---

## 附：两份文档的分工

- `01-verilog-tb.md`：调度/竞态/系统任务全表/Verilog 手法/视频台架专门手法/22 条陷阱/工程口径。
- 本文：SV 增量在哪、有哪些函数与方法、六件套手法、优劣与选型、**本机逐条实测矩阵**、
  从 Verilog 台架渐进改造的路线、SV 专属陷阱。

想动手就按 `README.md` 的"三条命令"跑起来，改 `examples/` 里的文件再跑——
所有例子的判据行都能被 `run_v.sh`/`run_sv.sh`/`run_ms.sh` 认出来。

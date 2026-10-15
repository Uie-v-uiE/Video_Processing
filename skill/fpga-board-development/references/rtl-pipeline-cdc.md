# RTL — 流水线对齐、跨时钟域、被工具"优化掉"的沉默

## 1. 延迟只有一个真源

深度写两处字面量，改动就会只中一处。反例（真实工程里最常见的形态）：

```verilog
// proc.v
parameter LATENCY = 3;                 // 只在注释里被读，正文一次没用过
// top.v
proc #(.LATENCY(3)) u_proc (...);      // 又写一遍
localparam ALIGN = 3;                  // 第三遍，靠注释说"必须等于 LATENCY"
```

`LATENCY` 是个死参数的判据很简单——把它改成 9，仿真行为一格都不变。让深度真的由参数决定：

```verilog
localparam int PROC_L = 3;             // 唯一真源
reg [7:0] dly [0:PROC_L-1];
genvar gi;
generate
    for (gi = 0; gi < PROC_L; gi = gi + 1) begin : g_dly
        // 每级都从参数派生，改一处就全链路一起动
    end
endgenerate
parameter  WIN_TAP_LAG = 2,               // 与那条延迟链同源：下面这两个数改一处，
           PROC_L      = 1;               // ALIGN 自己跟着变（I1 的单一真源就这么落地）
localparam ALIGN = WIN_TAP_LAG + PROC_L;   // 偏移是算出来的，不是抄来的
```

**"两处都对上"不是证据。** 结构上没有东西（编译期检查、断言、bench）守住那个注释时，它就是巧合。
自查做法：对参数名与其值各 grep 一次，列出"同一个数字在几处出现"和"声明后从未被使用的参数"，两份清单都要留。

## 2. 门控信号必须与数据同拍

用数据流的位置去做选择/计数/打标记时，控制链也要走到同一级。

```verilog
// 错：col 在输入时刻递增，mux 在输出时刻选择 —— 边界会偏 LATENCY 列
always @(posedge clk) if (px_in_valid)  col <= col + 1;
assign px_out = (col < split_col) ? raw_q : edge_px;

// 对：要么把 split_col 也算到输出侧，要么让 col 按输出节拍走
always @(posedge clk) if (px_out_valid) col <= col + 1;   // 并在帧/行首按同一节拍清零
```

现象对照：左右两半"不是同一列输入像素"、边界偏移量正好等于流水线深度、行末少一列——
这三类症状都**先查**门控是否同拍，但不要停在这里：行末少一列同样可能来自行 FIFO 欠载、下游
反压（`TREADY` 拉低时行尾那一拍被 valid 门掉）、或 stride/pitch 与实际行宽不匹配；边界偏移
同样可能来自坐标换算的除数取整。把"这一类都归它"当成结论是过度收窄。

## 3. 用探针实测深度，别信头注释

一次注入一个脉冲，数它在输出侧第几拍出现。这是延迟争论最常用的仲裁办法，但它有前提：
**无反压、单一路径、时钟一直在跑**。有 stall、旁路支路或多路径时，单脉冲量到的是**最小**延迟，
拿它去对齐消隐窗就错。所以两种负载各测一次（连续灌满 vs 中间插若干 invalid 拍），两个数都记下来。

```verilog
// tb：喂一个 valid 脉冲（数据全 0，只标记位置），在输出侧数拍
int found = -1;
@(posedge clk); px_in_valid <= 1; @(posedge clk); px_in_valid <= 0;
for (int i = 1; i <= 16; i++) begin
    @(posedge clk);
    if (px_out_valid && found < 0) found = i;
end
if (found != LATENCY) $error("latency probe: got %0d expect %0d", found, LATENCY);
```

**这段是 SystemVerilog，不是 Verilog-2001**：`int`、`var` 型循环这类 SV 构造在只给 `-2012` 的
编译里就会红（`xvlog` 默认模式下本机取到 `[VRFC 10-2939] 'int' is an unknown type`，见 `verification.md`
§1 那条）。**但选项名要按各家工具现取**：ModelSim 那一侧 `vlog -2012 <文件>` 直接被拒——
`** Error (suppressible): (vlog-1902) Option "-2012" is not a valid option for this tool.`、
`Errors: 1`、rc=1，而同一个 `mempart.v` 给 `-sv` 是 `Errors: 0, Warnings: 0`、rc=0。
**两臂只差那一个选项名**，所以那次 rc=1 不是文件坏了，是选项不存在——照抄别家的版本号写法就会卡在这一步。
     **但 `$error` 不在这一类**：单独取过，一个用 `integer` + `$error(...)` + `$finish` 的文件默认 `xvlog` 退 0、不打任何 ERROR —— 早先那句"`$error` 也会红"是把它和 `int` 混在一起了。
     所以要么整个 bench 用 `-sv` 编，要么把 `int found` 换成 `integer found`（`$error` 可以留着）
加一条自己的判定行——**别让它只在你的工具链里"应该能过"**。

同一段探针也用来量**有效位与数据是否同拍**：`px_out_valid` 拉高那一拍 `px_out` 上的值必须属于
同一个输入像素。常见缺陷是 valid 比自己的数据早 1 拍（valid 链少打了一级），流不连续时症状最重。

## 4. 跨时钟域：先判"是不是真跨域"，再选机制

判据来自网表与例化关系，不来自警告文本。逐条只问三个问题：驱动寄存器实际挂在哪个钟网（要穿过
门控钟、派生钟、未约束的物理输入去追）、接收寄存器挂在哪个、两侧是否相同。相同就是假警，
把两个实例名和各自钟写进记录；不同才谈机制。

**`report_cdc` 报 0 条不等于安全**——工具认不出的钟（门控出来的、MMCM/PLL 派生但没进时钟模型的、
被当成同源的两个物理输入）在它的模型里不构成跨域；网表里那条路径确实存在，只是没人检查它。
这版工具的说明里就把话讲明了（本机实测原文）：

```
INFO: [Timing 38-314] The report_cdc command only analyzes and reports clock domain crossing
paths where clocks have been defined on both source and destination sides. Ports with no input
delay constraint are skipped. Please run check_timing to verify there are no missing clock
definitions in your design, nor any unconstrained input port.
```

也就是说：**两侧都没进时钟模型的路径、以及没加输入延迟约束的端口，它直接跳过**。跳过不是通过。
所以先看 `check_timing`（`no_clock` 计数应为 0）再谈 `report_cdc` 的结果。
验收口径写成"**真跨域条目数 = 有机制覆盖的条目数，逐条对得上**"，不写"零警告"。

### 4.1 单向事件——用翻转位，但要看清它的速率上限

脉冲宽度短于目的时钟周期就整拍消失。48 MHz 源域的一拍（20.8 ns）短于 27 MHz 目的域的一拍，
采样相位还会遍历全部偏移，症状是"有时生效有时不生效、换个频率又不出现了"。

```verilog
// 源域：每次事件翻一位（翻转位永远至少撑一个源周期）
always @(posedge src_clk or negedge src_rst_n)
    if (!src_rst_n) ev_tog <= 1'b0; else if (ev) ev_tog <= ~ev_tog;

// 目的域：同步 + 边沿检测；三级的中间两级之间不许有组合逻辑
(* ASYNC_REG = "TRUE" *) reg [2:0] s;
always @(posedge dst_clk or negedge dst_rst_n)
    if (!dst_rst_n) s <= 3'b0; else s <= {s[1:0], ev_tog};
wire ev_dst = s[1] ^ s[2];
```

**它保证的是"不因脉冲太窄而丢"，不保证"事件密集时不合并"。** 两个事件落在同一个目的周期里，
电平翻出去又翻回来，目的域一个沿都看不见 —— 事件速率上限就是**每个目的周期 1 次**。
实测（`(* ASYNC_REG *)` 三级链照抄上面这段，48 MHz 源 / 27 MHz 目的，事件每 1 个源周期发一次）：
`src_events=209 dst_events=25`，也就是丢了约 88%（25/209，分母取源侧计数）。事件速率可能超过 1/目的周期的，一律走握手或
异步 FIFO，不要用翻转位；速率低于上限时它与频率比无关，这点才是它的价值。
`ASYNC_REG` 是 Xilinx 的属性名，别的厂商工具另有写法或另有流程，照抄前先确认。

### 4.2 多位量三选一

- **握手**（req/ack，或"数据先稳、再翻 req"）：延迟换安全。数据必须保持到**对方确实已经取走**为止：
  没有 ack 的单向 req，数据要撑过"req 同步两级 + 边沿检测 + 对方采样"这一整个往返；有 ack 的，
  源端**看到 ack 之后**才允许换数据。只写"目的端在 req 之后至少一个周期里数据仍在"是不够的——
  目的钟比源钟慢时那个窗口会不够长。
- **异步 FIFO**：多位数据的默认答案。指针各自同步，**full 在写域生成**（拿同步过来的读指针算），
  **empty 在读域生成**（拿同步过来的写指针算）。把 full 做到读域是最常见的写反之一。
- **准静态 + 显式稳定窗口**：只适合"整帧才改一次"的配置字。此时把纪律写成可检查的东西
  （多少周期不变、由谁保证），而不是 XDC 注释里一句 "quasi-static"。

格雷码只解决"指针必须跨域"这一步：二进制加到 2 的幂那档会连着翻多位，采在中间就拿到既不是旧值
也不是新值的数，误差量级可达整表深度；格雷码相邻只差一位，误差被压到一格。位宽：地址 A 位
（深度 2^A）时指针与其格雷码都要 **A+1 位**，多出的最高位专门区分满与空。编码必须在**源域、送出
之前**；在接收端才编码等于没做。同步过来的指针本就带一两拍滞后，深度与水位要按这个滞后留余量。

### 4.3 复位

异步复位要做"异步断言、同步释放"。为什么 false_path 会把复位余量的检查一起带走（工具层面的解释）
在 `constraints-timing.md` §3；本页只取落在 RTL 侧的那句结论：**给复位网络加 false_path =
明确放弃验证它的复位余量**，不是"复位那部分还有人查"。想保留验证就改用有界约束（`set_max_delay`）。`report_methodology` 综合后就能跑，而且它的规则集里
**确实有与复位/时钟结构相关的条目**（本机早期那次跑出的"已检查"列表含 `RTSTAT-1`、`REQP-1`、`AR-1`，都 0 violations）。**但要记下第二种形状**：另一路同一类设计用 `-file` 取，报告里**只列有发现的那些规则**（复核那一路报的是 `Checks found: 14`，行是 `TIMING-6/7/8/16/18` 这种；**那是它的读数**，本包只认自己那次的形状），`RTSTAT-1`/`REQP-1`/`AR-1` 三行**根本不出现**——所以"某条规则没出现"既可能是没跑、也可能是跑了没违例，**不能用它的存在与否当门**；能当门的是"这份报告有没有你关心的那条 violation 行"。另外两条要记住：条目名里**没有 "reset" 这个词**，
别用搜 "reset" 的方式判断它查没查；以及"0 violations"只说明这版这套规则没报警，
不等于你的复位同步做得对（它看的是结构模式，§4.3 的异步断言/同步释放仍要自己按机制核）。
确认 `rst_n` 来自哪个域、同步器自身的复位释放是否安全，这两条不靠它。

## 5. 三种"沉默的假绿"

1. **约束指向不存在的对象。** 症状是流程全绿而那块逻辑其实没人检查；命中计数怎么写、工具打的
   原局长什么样，都记在 `constraints-timing.md` §2。在本页语境里要做的只有一件事：改过例化名或
   端口名之后，把与这块逻辑同名的每一条约束单独数一遍命中数，取到 0 就按死约束处理。
2. **输入被绑成常数，整块被常量传播删掉。** 症状是"这块逻辑相关的 CDC/时序条目一条都没被点名"——
   因为网表里它不存在。检查该输入有没有真实驱动（顶层是否 `1'b0` 硬接、端口表里根本没有这个信号）。
3. **隐式位宽与悬空。** 存储器字选接到没写位宽的线网（`wire raw_q = raw_sr[ALIGN-1];`）是 1 位线网，
   这一路从此只输出像素的最低位（本机：`w=fa` → `s=0`，`w=f9` → `s=1`，两个仿真器一致）。
   未赋值的输出端口是浮空；声明并连出去却没人用的信号被综合裁掉，报告依然全绿。

   两种写法看着都像"截了一下"，性质完全不同：`wire s = wide_sig;` 能编译、只留最低位（**静默**）；
   而对存储器整体做位部分选择是**编译期就红**的，只是**报错号随编译模式变**——
   不加 `-sv` 时**同一行连报两条**：`[VRFC 10-3627] part-select of memory 'mem' is not allowed` 与
   `[VRFC 10-395] cannot assign an unpacked type to a packed type`（本机逐字取到，两条都带
   `[memsel.v:7]`，随后 `[VRFC 10-8530] module 'memsel' is ignored due to previous errors`、`xvlog` rc=1）；
   加了 `-sv` 只剩 `[VRFC 10-395]` 那一条。
   两种模式都红，但**脚本按 `10-3627` 匹配会在 `-sv` 模式下整个漏掉这一行**。会悄悄出事的永远只是前者。

   `` `default_nettype none `` 让拼错的信号在编译期就炸，而不是变成一根隐式 1 位线网——
   但它**同时会把 ANSI 端口也判红**：本机 `module m(input clk, ...)` 这种裸端口在 `none` 之下报
   `[VRFC 10-1103] net type must be explicitly specified for 'clk' when default_nettype is none`。
   所以用它就要把端口写成 `input wire clk`（或整份文件按 `-sv` 编），否则第一条错是你没预料到的
   一片端口错，反而掩盖了真正要找的那个拼写错。

自查是三个 grep：位宽声明与实例化端口的宽度并排、`get_ports`/`get_pins` 命中的名字、被声明却没读过的信号。它们只给候选位置，每条都要人工确认；
对 VHDL 与脚本语言写的上位机，Verilog 侧的正则一概不适用，那一族要另找工具，别套用。

**但"这块逻辑还在不在"不能靠 grep RTL 回答，要在网表上数。** 一份综合后的设计（`open_checkpoint`
之后）取到的形状是这样，可以直接照抄成判据。**下面四个数属于同一份、同一阶段
网表**（那份 8 位计数器的综合结果；**这时调试核已经 create+connect、但还没 `implement_debug_core`**——在同一会话取到 `get_cells -quiet *` 与 `-hier *` 都是 35、`-hier */D` 是 8、`MARK_DEBUG==1` 的网络 1 个；换成实现之后的网表这些数全变，见 `constraints-timing.md` §6）：换设计、或换成实现之后的网表，
`*/D` 与 `get_cells` 的数都会变——**它们是形状示例，不是可以搬走的常数**：

```tcl
open_run synth_1                              ;# 或按 `onchip-debug.md` §2.1 的第 ⑨ 步打开一份 dcp
# 先把"这是哪一份、哪一阶段"打进同一屏，否则下面四个数就只是四个匿名整数
# （报告归属哪一阶段的规矩在 `constraints-timing.md` §4 第 1 条；步骤属性名怎么现取归 §3 那张表，
#  这里只把设计名与 run 名钉在屏幕上，directive 那一格到 §3 现取现打）：
puts "DESIGN=[current_design]  RUN=[get_property NAME [current_run]]"
# 阶段本身没有可靠的对象属性可取（design/run 上不存在 DESIGN_STATE 这一族属性），
# 所以用报告头那行钉阶段：`report_utilization -return_string` 里 grep `Design State :`；
# **没有这一行对上号，上面四个数就只是四个匿名整数**。
llength [get_cells -quiet *]                  ;# 本机这一份 31（另一路复核在同一类设计上报 24——**那是别人的读数，别当本包的数引用**；两个数都只服务于各自那份网表）
llength [get_cells -quiet -hier NOPE_NOT_HERE] ;# 0，而且 -quiet 下不回任何告警文本
llength [get_pins  -quiet -hier */D]          ;# 8
;# **这一条数的是 D 引脚，不是触发器位数**：锁存器的数据脚也叫 D。
;# 本机**另一份**设计（不是上面那 8 位计数器那份）："5 位使能寄存器 + 3 位异步复位 + 2 位异步置位 + 4 位锁存器"，给 **14**，逐个取父单元
;# 的 `REF_NAME` 是 `LDCE LDCE LDCE LDCE FDRE FDRE FDRE FDRE FDRE FDCE FDCE FDCE FDCE FDCE`
;# （综合把异步**置位**那一组也化成了 FDCE，所以 `FDPE` 一个都不剩）。
;# **只数 `*/D` 会把锁存器算成触发器**；而按 `== FDRE` / `== LDCE` 各数一次**同样错**：
;# 本机 `== FDRE` = 5、`== LDCE` = 4，加起来 9，既不是触发器位数（10）也不是总数（14）——
;# 漏掉的那 5 个 FDCE 正好被"锁存器别算进来"的减项掩盖了一半，这种**两个错互相掩盖**的形状最难发现。
;# 按族分才对：`-filter {REF_NAME =~ FD*}` = **10**（真触发器位数）、`{REF_NAME =~ LD*}` = **4**；
;# 10+4=14 与 `*/D` 的总数对上——**这个合计就是拆分自身的正向对照**，不成立就说明还有第三族。
llength [get_nets  -quiet -hier -filter {MARK_DEBUG == 1}]   ;# 1（标记随 dcp 一起存下来）
;# 这条是本页与 `onchip-debug.md` §2 共用的规范写法，改这里要同步那一页的指向句。
;# 三种过滤写法本机都取到同一个集合：{MARK_DEBUG == 1}、{MARK_DEBUG == true}、裸 {MARK_DEBUG}。
```

三条读数要知道：**`-quiet` 建议带，但原因不是"`llength` 会数到告警的词数"**——实测
`catch {get_pins NOPE_NO_PIN} g` 得到返回码 0、`llength $g`=**0**、`string length $g`=0：
**告警是打到日志的，交回来的仍是空集合**（`get_cells`/`get_files` 同形）。
本页与 `constraints-timing.md` §7 第 4 条旧文写过"文本被当结果返回、`llength` 数的是词数"，
那个机制不成立，已按实测改掉。带 `-quiet` 真正的用处是**日志卫生**：不让
`No ... matched` 这类告警混进你随后要 grep 的那份日志。判据本身一直是 `llength`，
不带 `-quiet` 它也不会被污染——所以这一条是卫生要求，不是判据要求；
**别拿"搜模块名搜不到"当结论，也别拿"搜得到"当结论——它取决于综合有没有把层次 flatten**：
本机一份小设计 `get_cells -hier *cnt*` 取到 **0** 个（综合后只剩 `FDRE`/`LUT` 这类原语名），
另一路复核在同一类 8 位计数器上报 **18** 个命中（`u_cnt/cnt_reg[7:0]` 这类层次名留着了）——
     **那是别人的读数，本包没在自己的设计上复现，别引用它**；这里能主张的只有"它取决于有没有 flatten"。
所以这条只能用来解释"为什么搜不到"，**不能用来证明"逻辑被删了"**；
所以"搜模块名搜不到"推不出"逻辑被删了"，要换成**它驱动的那个寄存器/端口**去搜；
以及判断"被常量传播删掉"的正向对照是同一条命令搜一个已知存在的名字（本机用 `*ila*`，取到 1 个）。
名字里带 `[n]` 的，按 `constraints-timing.md` §4 那条**加花括号**写（`get_nets {q[3]}`）——
本机在 `catch {…}` 里两种写法都取到了同一个网，但那不构成"不用加括号"的依据，
因为 `catch` 自己的花括号已经挡住了替换。

## 6. 流水线的延迟要花得起：消隐预算

流式（行/帧同步 + 消隐）接口里，插在源与汇之间的每一级流水都不只是"晚几拍出来"：

- **同步标志与数据必须一起延**。hsync/vsync/de 走的是另一条链时，数据延了 N 拍而同步没延，
  接收侧的行边界就错位，症状是整幅画面横向偏移、或每帧开头几列是上一帧的尾巴。
- **消隐期是延迟的预算上限**。行尾到下一行首之间只有 hblank 那么多拍，流水深度加到超过它，
  行缓冲就会在行末溢出/欠载（症状：每行右边缺几列，或行 FIFO 的假满）。
- **行缓冲深度要吸收两侧的速率差**。写入侧一个像素一拍、读出侧平均慢于/快于写入侧时，
  深度余量至少覆盖一整行的最大累积偏差，加上读写指针跨时钟域带来的 1~2 拍滞后。

改深度时把这三条一起算，不要只算"边界偏几列"。反过来，看到"画面滚动/整帧偏一行"，
先查同步标志的延迟与消隐预算，再怀疑数据通路。

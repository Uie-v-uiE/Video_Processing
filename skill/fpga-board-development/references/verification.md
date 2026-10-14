# 仿真与判据 — 让 bench 真的能红

## 1. 判定行是契约

bench 只打**一条**结论行，格式固定、纯 ASCII，判定词紧跟在前缀之后：

```verilog
integer checks, errors;
// ...  stimulus 跑完之后：
if (checks == 0)       $display("TB_RESULT NOT_RUN checks=%0d errors=%0d", checks, errors);
else if (errors == 0)  $display("TB_RESULT PASS checks=%0d errors=%0d", checks, errors);
else                   $display("TB_RESULT FAIL checks=%0d errors=%0d", checks, errors);
$finish;
```

契约的三条内容，脚本侧照此解析：

- 以 `TB_RESULT` 开头的行**必须恰好有一条**；找不到就按 `NOT_RUN` 处理，不要按 0 处理。
- 判定词是这一行的**第二个字段**。不要把判定词放到行末——人写的说明、参考文件名里都可能出现
  `PASS`/`FAIL` 字样，按"行尾取词"或"输出里含 PASS"解析都会误取。
- 计数（`checks`、`errors`）必须在行里。`checks==0` 的绿是假绿：断言根本没被触发（时钟没跑、
  握手条件永不成立、实例名写错）。

**退出码不能当判据。** 本机实测（ModelSim 2020.4 与 xsim 都这样）：`$fatal(1,...)` 触发、
transcript 里打出 `TB_RESULT FAIL` 与 `** Fatal` 之后，`vsim -c` 与 `xsim` 仍然返回 **0**；
而编译/elaborate 出错反而返回非 0（本机取到的是 **ModelSim 那侧**：顶层模块找不到时 `vsim -c` 给 **12**；
**xsim 这一侧单独复现过了**：同一份 bench 跑完并印出判定行 `FAIL checks=40 errors=40`
之后 `xsim sim --runall` 的退出码仍是 **0**，PASS 那一臂也是 0——两臂同码，
所以退出码连"这次到底判成还是判坏"都不区分）。
所以流水线的红绿只能靠解析 `TB_RESULT` 那一行。

**`Errors:` 汇总行只有 ModelSim 有。** `xvlog`/`xelab` **不打印** `Errors: N, Warnings: N` 这种总结行
（本机 `grep -c "^Errors:"` 为 0），它们只逐条打 `ERROR:`；所以 xvlog 侧**数 `^ERROR:` 行**。
它的退出码只回答"编译/elaborate 这一阶段有没有报错"，**不参与判定行那层的红绿**
（本节开头那条对 `xsim`/`vsim` 成立，对跑完仿真但判定 FAIL 的情况同样成立）。
把"看 `Errors:` 计数"抄到 Vivado 工具上，得到的是一个永远为 0 的读数。

SystemVerilog 写法要不要 `-sv`，**两个工具的答案不一样**，别一句话概括：

- `xvlog`：`final` 块不加 `-sv` 报 `[VRFC 10-4982] syntax error near 'begin'` 并退 1，加了退 0。
  但 `int` 单独出现时给的是 `[VRFC 10-2939] 'int' is an unknown type`（不是语法错）。
  **`$fatal` 不需要 `-sv`**——xvlog 与 vlog 都接受它，本机不加 `-sv` 也能跑并打出 Fatal。
- ModelSim 的 `vlog` 按**文件扩展名**自动切：同一段含 `final`/`int`/`logic`/`$fatal` 的代码放进
  `.sv` 文件，不加 `-sv` 也是 `Errors: 0`；放进 `.v` 才报 `Errors: 5` 并退 2。
  所以"vlog 必须加 -sv"这句在本机不成立，成立的是"文件名与内容要配套"。

用 Verilog-2001 就按上面那样在 `$finish` 前打印；上 SystemVerilog 就整个工程统一（扩展名、`-sv`、
工具默认三者一致），别一半一半。

## 2. 参考模型必须与 RTL 不同源

把 RTL 的算式抄进 tb 的模型，它永远同意，等价于没有模型。三种独立化办法，任选其一即可：

- 换算法：RTL 用排序网络/移位累加，模型直接排序后取中值 / 用行为级乘加。
- 换表示：RTL 定点 Q 格式，模型用浮点算完再量化，容差按量化步长推。
- 换次序：RTL 流水重叠，模型按整幅一次算完。

然后**把契约显式写进模型**：延迟多少拍、有效位与数据是否同拍、边界那一拍给什么。模型与 RTL 只在
数值上一致而时序相位不一致，症状正是"值都对、图还是错的"。

## 3. 例化层次要覆盖到问题会出现的那一层

只例化叶子模块的 bench 结构上看不见顶层对齐、门控相位、乒乓切换这些缺陷。改顶层相关逻辑时，
bench 里必须有一个顶层实例（或被测模块 + 它实际连接的延迟链一起例化）。

## 4. 变异对照——一条没红过的判据不算验收

改完 bench 绿了，做一次破坏看它会不会红：

```bash
# 三选一的破坏，bench 必须 FAIL；破坏完记得还原
sed -i "s/8'd255/8'd254/" rtl/proc.v        # 改一个常数
#  某一级的 <= 少打一级                       # 改深度
#  阈值比较的方向反过来                        # 改判据
```

`sed -i` 在 Windows 上不是原生可用的（本机走的是 Git Bash 才有它）。同样的破坏在 PowerShell 里写成：

```powershell
(Get-Content rtl\proc.v) -replace "8'd255", "8'd254" | Set-Content rtl\proc.v
```

两种都用过之后要 `git diff`/`fc` 确认**只改了那一处**——破坏式对照最怕顺手改了两个地方，
红了也不知道是哪个造成的。含中文注释的文件不要用 shell 的重定向去改：编码链路会把注释弄坏，
用编辑器改完再存。

**破坏必须只改语义、不改变编译可行性。** 把 `8'd255` 写成 `8.d255` 那种"破坏"得到的是语法红
（`Digits must follow decimal point in real`），它证明不了判据能抓功能错，却会被记成"I6 已完成"。
所以流程是：改完先确认编译仍然 0 error，再看 bench 是否红。

留档那次"红"的读数（哪个改动、哪条断言、报了什么），写进改动记录。天然难配对照的存在性检查，
就明写"未配对照"，不要为凑红造假。

## 5. X / Z 与未初始化

数组元素默认 X、**标量也默认 X**——这条本机在两个仿真器上都实测过：`reg` 标量、`integer`、
存储器元素在 0 时刻读出来全是 X（`PROBE10 ii=x rs=x rv=xxxxxxxx arr0=xxxxxxxx`），
**只有 SV 的 2 态类型（`bit`/`byte`）才默认 0**。所以"标量默认 0"这种说法只对 2 态类型成立，
不要拿它推断未驱动 `reg` 的读数——否则会以为某个没写的寄存器"应该是 0"，而它其实是 X。

比对器里含 X/Z 的项记 `NOT_RUN` 或 `FAIL`，禁止在提取层把它折成 0（折了就变成假绿）。
数组没写过的地址读出来是 X，是"这块逻辑从没被驱动"的直接证据，不要屏蔽。
两个仿真器都有影响默认初值的开关（名字本包没核实过，所以不给），**做法是量而不是背**：
写一个不初始化的 `reg [7:0] x;` 与一个没写过的数组元素，在你这一版上打印 0 时刻的值，
读回来的形状就是后面所有判据的基准。RTL 侧与网表侧要各测一次——`glbl` 的全局置复位会让两边不同
（见 §8）。

## 6. 跨时钟域的 bench 要扫相位，并且要限速

单相位仿真是抽签。两个钟按真实周期跑，并扫描初始相位（或随机相位 + 长回归），断言三件事：

1. 数据腿：**同步后锁存到的值必须等于某一条合法命令**。新旧混合的"脏字"（写了 0x55 读到 0x35）
   就是撕裂，出现一次即红。在数据各位上加不对称的传输延迟来模拟布线偏差。
2. 事件腿：在**事件速率不超过每个目的周期 1 次**的前提下，每次事件恰好一次更新（丢与重都算失败）。
   这条速率前提必须写进 bench 的注释——超过上限时事件被合并是翻转位方案的**正确行为**，
   把它当失败会让人去改一个没坏的东西（详见 `rtl-pipeline-cdc.md` §4.1 的实测数字）。
3. 对照实验：把源端脉冲压到短于目的周期，**旧的脉冲直采写法必须红**；同一 bench 下翻转位/握手写法
   在限速条件下必须绿。这一对红绿是这个改动的可复现证据，比口头解释硬。

亚稳态本身仿真读不出来（仿真里没有真实的建立/保持违例与随机的 X），别用"仿真没出现 X"当安全证据。

## 7. 黄金比对与容差

先化同维再比（都折成拍数或都折成时间），容差由维度推出来并注明来源。钉一个"上次残差"当容差，
症状是稳绿、一换频率就红（或反过来永不红）。豁免名单按（用例，期望项）作键并打印每次命中，
按信号名作键会串到别的用例上静默吸收失败。

## 8. RTL 仿真绿 ≠ 网表行为一致：把这一层也变成读数

这一层很多人跳过，因为它要**同一份 bench 跑两个对象**。跳过它的代价是"bench 全绿、板上坏"
里有一类永远查不到根因。

取网表（本机实跑；综合这一步用什么都行，能拿到结构网表即可——批处理里最常见的是
工程流程 `launch_runs synth_1`，或者直接 `synth_design -top <顶层> -part <part>` 之后再
`write_verilog`）：

```tcl
write_verilog -mode funcsim ./sim/netlist_func.v   ;# 综合之后；本机产出 235 行、里面是 FDRE/LUT1 这类原语
write_sdf ./sim/top.sdf                            ;# 本机 306 行。**上面那条跑法不读它**：
;#   funcsim 是功能网表，不带时序标注；要让仿真读 SDF 得另出 timesim 网表并给 xelab 传 SDF 选项，
;#   而那一组选项名没有核过（`-sdf_lib_name` 已实测是 `Unknown option`）。
;#   要注时序先 `xelab -help` 查出这一版可用的写法，别照抄网上的 `-sdf ty(...)`。
```

`write_verilog -mode timesim -sdf_lib_name …` 里 `-sdf_lib_name` 在本机这版是
`Unknown option`——选项名照旧要现查（`write_verilog -help` 的语法行里有 `-mode`，没有它）。

命令行把网表跑起来（本机跑通的顺序，非工程流程）：

```bash
cd sim                                # 上面两条产物在这里；不 cd 就用 sim/ 前缀写全
xvlog netlist_func.v ns_tb.v
xvlog <安装根>/Vivado/data/verilog/src/unisims/<原语>.v   # 逐个补网表里出现的原语
xvlog <安装根>/Vivado/data/verilog/src/glbl.v             # 非必需（网表自带 glbl）；要的是下一行 xelab 的顶层里有 glbl
xelab --timescale 1ns/1ps ns_tb glbl -s sim_net           # glbl 要和 bench 一起当顶层
xsim sim_net -R
```

`ns_tb.v` 就是 §9 那份 bench **换掉被测对象**之后的同一个文件：把实例化的 RTL 顶层名换成
`netlist_func.v` 里那个网表顶层名，判定行与检查点一个字都不动——这一层的意义就在"一个字都不动"。
本机跑过的产物名是 `netlist_func.v` / `ns_tb.v` 这一对，`vlog`/`xelab` 都按当前目录找文件，
所以块首那行 `cd` 不是装饰。

- 原语清单不是背的，从网表里 grep 出来：本机这份需要
  `BUFG FDRE IBUF LUT1 LUT2 LUT3 LUT4 LUT5 OBUF` 九个。
  **完备性的判据不是"我列全了"**，而是 `xelab` 不再报未声明的模块：它每报一个
  `ERROR: [VRFC 10-2989] '<名字>' is not declared` 就补那一个（或干脆把
  `data/verilog/src/unisims/` 整个目录都 `xvlog` 进去，慢但一次到位），
  直到出现 `Built simulation snapshot` 为止。
- 那个 `data/verilog/src/unisims/` 目录在安装树里的位置有两种写法（本机
  `<根>/2025.2.1/Vivado/data/...` 与 `<根>/2025.2.1/data/...` 都被工具自己用过），
  路径不存在时先 `ls` 一下安装根，别照着记忆拼。
- **`glbl`：要的是"它在 `xelab` 的顶层表里"，不是"安装树那份被编译"**（这句纠正了本机先前的一次 A/B）。
  `write_verilog -mode funcsim` 出来的网表**自己就带一份 `module glbl`**（`xvlog` 日志里有
  `analyzing module glbl`）。重做的一对是：
  A：编 `网表 + tb + unisims`（**不**编安装树的 `glbl.v`），`xelab … tb glbl` → **rc=0**、
  `xa.log` 里就有 `Compiling module work.glbl`（用的正是网表自带那份），仿真照跑出判定行；
  B：同样不加安装树那份，但 `xelab` 顶层**只给 `tb`** → 立刻
  `ERROR: [VRFC 10-2989] 'glbl' is not declared [.../unisims/OBUF.v:43]`，退 1。
  **先前那次 A/B 把两件事一起改了**（同时换了"编译哪份 glbl"和"顶层给不给 glbl"），
  于是得出"unisim 引用的是安装树那一份"这个错推断。控制变量重做后结论是：
  **变量只有一个——`glbl` 必须在 `xelab` 的顶层里**；编译安装树那份无害但非必需。
  报错位置在库文件里而不是你的代码里，第一次看到会误以为网表坏了——按这条对号入座。
- 走工程流程的那些命令（`launch_simulation`、`export_simulation`、`compile_simlib`）本包**没跑过**，
  具体选项要在你机器上取一次；但**手工这条路（`write_verilog -mode funcsim` + `xvlog`/`xelab`/`xsim`）
  本机现在是跑通了的**，配方与两臂读数在本节末尾——所以网表仿真这件事不必等 `compile_simlib`。

**本机实测到的两类差异**，两类都是"同一 bench、同一时刻，两边结果不同"（下面引用的每一行都
按 §1 的契约写：`TB_RESULT <判定词> checks=… errors=…`，判定词紧跟前缀，**中间没有冒号**——
带冒号的写法会让 `awk '{print $2}'` 取到 `:`，红绿都解析成 `NOT_RUN`）：

1. **初始化窗口：`RTL 与网表都有窗口` 这一格是复现到的；`只有网表侧有` 这一格不要当结论用**——
   要主张它，得在同一份设计上给出网表侧多出的那段 x 窗口的长度。
   前一次记的一次观察是：bench 在 `#12` 检查"复位释放后 `q==0`"，RTL 侧打
   `TB_RESULT PASS checks=12 errors=0`、网表侧打 `TB_RESULT FAIL checks=12 errors=1`
   （失败那条的观察文本是 `reset q= x`，它不是判定行），把检查点推晚之后网表侧才 PASS。
   **把同一份 bench（`rst` 全程拉住，每 5 ns 采一次，并先印 t=0 的值）在两个仿真器、
   两种描述上各跑一遍**，四个组合都是"x 只出现在 t=0，第一个采样点就已经有定义值"，
   那条 RTL / 网表的不对称**没有复现**：

   | 被仿的东西 | xsim（`--runall`） | ModelSim 2020.4（`vsim -c`） |
   |---|---|---|
   | RTL 行为级设计 | t=0 `xxxxxxxxx`；首个已知值在 10 ns（第一个 posedge） | 与左同 |
   | `write_verilog -mode funcsim` 的网表 | t=0 `xxxxxxxxx`；首个已知值在 **5 ns**（第一个采样点） | 与左同 |

   也就是说 **funcsim 的触发器直接吃 `INIT`，不等 GSR 落地**，而且这一条在 xsim 与 ModelSim 上表现一致。
   所以能站住的判据不是"网表侧要等到 100 ns"，而是**两臂都不能在第一个采样点之前下结论**：
   检查点要放到"复位释放且至少走过一个时钟沿"之后，并把**首个检查点的仿真时刻**跟判定行一起印出来。
   窗口宽度仍然要**读，不要背单位**：安装树那份
   `<安装根>/Vivado/data/verilog/src/glbl.v` 第 4 行是 `` `timescale 1 ps / 1 ps ``、
   第 8 行 `parameter ROC_WIDTH = 100000`，第 64 行附近 `#(ROC_WIDTH)` 才把 `GSR_int` 放下——
   **也就是 100 ns，不是 100 µs**（本页早先写的是 100 µs，把数放大了 1000 倍；同一份文件里还有
   `GRES_WIDTH = 10000` / `GRES_START = 10000`，那是另一个 10 ns 宽的窗口）。
   而且 `write_verilog` 出来的网表里也带一个 `module glbl`，**它的 timescale 才是仿真时生效的那份**，
   所以配一条 `grep -n "timescale\|ROC_WIDTH" <实际编译进去的那份 glbl>` 一起看。
   **没跑通的分支要说清卡在哪一步，测到的部分要记全**：带 SDF 的时序仿真这一臂停在
   卡点逐个是（都是自己的读数）：`write_verilog -mode timesim -sdf_anno true -sdf_file <路径>`
   **rc=0 但不生成任何 `.sdf`**（绝对路径、相对路径两种都试过，仿真时炸
   `[XSIM 43-3230] Could not open sdf file`）——**SDF 是另一条命令 `write_sdf <file>` 写的**
   （它存在，选项里有 `-cell`/`-process_corner`/`-mode`）；补上 `write_sdf` 之后网表 8542 字符、
   SDF 27101 字符都在，`xsim` 仍报 `[XSIM 43-3462] Unable to annotate SDF delays in the design`
   并以 **rc=1** 退出（本机少见地非 0，别以为 xsim 永远 0）。
   所以"带 SDF 时 GSR 会不会把 x 窗口撑开"这一问，要等工程流里 `config_simulation` 配好之后才答得了。
   补一条同样属于的取得：`xelab --sdfmax "/实例=文件"` 经 `cmd //c` 传参时
   会被拆开（本机三种实例写法都得到 `Cannot find design unit add4_nt.sdf in library work`），
   而网表内嵌 `$sdf_annotate` 的写法能找到文件却报 `43-3462 Unable to annotate SDF delays`——
   **本机在这一步连试三次都没通，就停在这里**（三次同一条错误：`Cannot find design unit add4_nt.sdf
   in library work`，rc=1——`--sdfmax /dut=<file>`、`--sdfmax dut=<file>`、以及走 `.bat` 传参各一次）。
   记下三条可查的事实：`--sdfmax` 的取值形态不能凭猜；内嵌 `$sdf_annotate` 的写法能找到文件但报
   `43-3462 Unable to annotate SDF delays`；所以**这条路要修就得走 Vivado 工程流的 `launch_simulation`/
   `export_simulation`（本包没跑过）**，别把任何未跑通的写法写成"这样就能注入 SDF"。

   而那次不对称观察也许就来自那一类设置——没有证据前别写成结论。
   落在窗口里的检查点测的是初始化行为，不是设计行为；判据要么把检查点放到 GSR 之后，
   要么显式改 `glbl` 的参数并把这一条写进记录。（这类"网表红"很容易被误读成综合改坏了逻辑。）
2. **结构不是一一对应。** 源码写的是 `{cin,r} <= {1'b0,r} + a`，本机那份 funcsim 网表里
   **没有 `CARRY4`**，加法被映射成 LUT 链。所以拿网表的层次/原语去反推源码写法会错，
   反过来也一样：探针名字、网表节点名与 RTL 信号名的对应关系要单独核（`onchip-debug.md` §3）。

判据能不能红：把 RTL 里的 `+ a` 改成 `+ 1`（其余不动），同一 bench 立刻
`TB_RESULT FAIL checks=38 errors=38`。**又用一份独立的小 bench 复做了一遍这件事**
（8 位加 8 位、期望值用逐位进位的软件加法器算，与设计里那个 `+` 不同形）：
好臂 `TB_RESULT PASS checks=40 errors=0`、把 `+ b` 换成 `+ 9'd1` 的坏臂
`TB_RESULT FAIL checks=40 errors=40`，两臂 `xsim` 退出码都是 0——**判据能红、退出码不红**，
这条链条在同一台机器上第二次独立成立。
**同一份 bench 现在两侧都跑过、两侧都能红**（把网表臂搭起来了，不需要 `compile_simlib`）：
把设计改成 `+ 9'd1` 之后**重出网表**再跑，
网表好臂 `TB_RESULT PASS checks=40 errors=0`、网表坏臂 `TB_RESULT FAIL checks=40 errors=40`，
**四臂（RTL 好/坏 + 网表好/坏）的 `xsim` 退出码本机逐一取过，全是 0**。所以"两侧共用一份检查逻辑，任何一侧行为变化都会红"这句现在是读数不是推定。

网表臂在这台机器上的可用配方（`xc7z020clg400-1`、2025.2.1；`write_verilog -mode funcsim` 出 8214 字符）：

1. `xvlog` 一次编三组：**funcsim 网表**、**tb**、**网表用到的那几个 unisim 源**
   （本机这份是 `IBUF OBUF BUFG LUT1…LUT6 FDRE CARRY4 GND VCC INV`，在
   `data/verilog/src/unisims/<名字>.v`）。**安装树的 `data/verilog/src/glbl.v` 不必编**——
   网表自带 `module glbl`（见上面重做的那条 A/B）。缺 unisim 时的原话是
   `[VRFC 10-2063] Module <IBUF> not found while processing module instance` +
   `〈_IBUF[0]_inst 〉`（`BUFG` 同形）——**这条是 `xelab` 打的、rc=1；
   `xvlog` 那一步 rc=0、一句 2063 都不会打**（本机重取）。只盯 xvlog 的输出会以为编译过了、其实没有。
2. **`xelab` 的顶层要给两个**：`xelab -s simn tb glbl`。只给 `tb` 会在原语源码里炸
   `[VRFC 10-2989] 'glbl' is not declared [OBUF.v:43]` +
   `[XSIM 43-3322] Static elaboration of top level Verilog design unit(s) … failed`——
   unisim 的 Verilog 源引用 `glbl` 的信号，需要 `glbl` **作为独立顶层被 elaborate**，不是被谁例化。
   这一条最容易卡住半天，而且报错位置在库文件里、不在你的 tb 里。
3. `xsim simn --runall -log run.log` 跑完；**两臂退出码都是 0**（红绿只在 `TB_RESULT` 那一行）。
4. **`timescale` 有两种坏法，本机都见过**：
   - 一部分模块声明、一部分不声明 → `xelab` 报
     `[XSIM 43-4099] Module <add4> doesn't have a timescale but at least one module in design has a
     timescale`，判定行拿不到（本机第一次撞到的就是这形状）；
   - **全都不声明** → `xelab`/`xsim` 都 **rc=0、仿真照跑**，但时间单位跟着网表自带 `glbl` 的
     `1 ps / 1 ps` 走，整轮跑进 GSR 窗口，打出来是 `TB_RESULT FAIL checks=40 errors=40`
     而**一行 ERROR 都没有**。
   规则：**tb 与设计模块都写明 `` `timescale``**，再加一条自检——**把首个检查点的仿真时刻
   （`$realtime`/`$time`）跟判定行一起印出来**，单位一错当场看得见。


## 9. 最小跑批命令

**先确认这一族命令在你那儿是怎么被找到的**，因为两边不对称（本机 Windows + Git Bash 逐条实测）：
`command -v vlog`、`command -v vsim`、`command -v vlib` 三条**都命中**
（指向 ModelSim 的 `win64` 目录），而 `command -v xvlog`、`command -v xelab`、`command -v xsim`
三条**都不命中**——它们在 `<Vivado 安装>/Vivado/bin/` 里存在（连 `.bat` 一共 6 个条目），
本包所有跑批都是用**完整路径**调 `vivado.bat`，xsim 那一族要先把那个 `bin/` 放进 PATH 才成句。
同一次扫描的其余对照：`command -v ls`/`grep`/`cat`/`md5sum`/`sed`/`awk`/`python` 都命中，
`command -v python3` **不命中**——`python3` 是**板端**那侧的解释器，别在主机上照抄。
所以抄下面任何一段之前，先在自己的机器上逐条 `command -v <工具>` 取一次读数：
它决定你写裸命令名还是全路径，而"命令名写着对、机器上找不到"这种失败不会给你别的提示。

```bash
vlog -work work rtl/*.v sim/tb.v
vsim -c -transcript ms.log -do "run -all; quit" work.tb   # 非交互跑完，并把日志落成 ms.log
```

`-transcript` 不是可选的：本节上面那条提取管道读的就是 `ms.log`，不加这一句它就没有输入文件。
（`-work work` 能不能省掉 `vlib work`/`vmap` 没有定论——跑通过的只有直接带 `-work work` 的 `vlog`；
在自己的机器上第一次跑时把这两条预备命令也试一遍。）

```bash
xvlog -sv rtl/*.v sim/tb.v              # 含 final/int 之类 SV 构造时要带 -sv（$fatal 不需要，见 §1）
xelab --relax work.tb -s simv
xsim simv --runall                      # 非交互跑完（--R 是同义；本机两臂都实测到 rc=0）
                                        # 想送自定义 Tcl：xsim simv -tclbatch cmds.tcl（cmds.tcl 里写 run -all / exit）
                                        # **`xsim simv -tcl` 在 2025.2.1 是无效开关**：
                                        # 它打 `Unexpected option encountered : tcl` 加整页 usage、rc=1，
                                        # 什么都不跑——旧脚本里的 `-tcl` 换成 `-tclbatch`（带文件）或 `--runall`。
```

**同一族命令跑综合后网表（本机实测过，两臂都能出判定行）**：

```tcl
# 先出网表（Vivado 批处理里）：synth_design 之后
write_verilog -mode funcsim -force ./sim/netlist_func.v
# 再仿：unisims 只给用到的那几个（缺一个就报 VRFC 10-2063 Module <X> not found）
xvlog $VIVADO/data/verilog/src/unisims/IBUF.v \
      $VIVADO/data/verilog/src/unisims/OBUF.v \
      $VIVADO/data/verilog/src/unisims/BUFG.v \
      $VIVADO/data/verilog/src/unisims/LUT1.v  $VIVADO/data/verilog/src/unisims/LUT2.v \
      $VIVADO/data/verilog/src/unisims/LUT3.v  $VIVADO/data/verilog/src/unisims/LUT4.v \
      $VIVADO/data/verilog/src/unisims/LUT5.v  $VIVADO/data/verilog/src/unisims/LUT6.v \
      $VIVADO/data/verilog/src/unisims/FDRE.v  $VIVADO/data/verilog/src/unisims/CARRY4.v \
      $VIVADO/data/verilog/src/unisims/GND.v   $VIVADO/data/verilog/src/unisims/VCC.v \
      $VIVADO/data/verilog/src/glbl.v \
      ./sim/netlist_func.v sim/tb.v
xelab -s simn tb glbl                   # 顶层必须给两个：只写 tb 会在 unisim 源里报
                                        # [VRFC 10-2989] 'glbl' is not declared [OBUF.v:43]
xsim simn --runall -log run.log         # 判定行还是只看 run.log 里的 TB_RESULT；rc 恒 0
```

**同一张 funcsim 网表换 ModelSim**（本机实测过，同样不需要 `compile_simlib`；`vlog` 会打
`Errors: 0, Warnings: N` 这种汇总行，`xvlog` 不会——见 §1）：

```bash
vlib work
vlog -sv -work work <安装根>/Vivado/data/verilog/src/unisims/IBUF.v `
                       …（网表实际用到的那几个，逐个列）… `
                       <安装根>/Vivado/data/verilog/src/unisims/INV.v `
                       <安装根>/Vivado/data/verilog/src/glbl.v `
                       sim/netlist_func.v sim/tb.v
vsim -c -nolog -do "run -all; quit" work.tb work.glbl   # 顶层同样要给两个，只给 tb 会在 glbl 引用处失败
```

```bash
iverilog -g2012 -o build/sim/tb rtl/*.v sim/tb.v && vvp build/sim/tb
```

三条跑法里，ModelSim 那条与 Vivado 那条（`xvlog`/`xelab`/`xsim`）是给过完整非交互批跑、有读数的；
`iverilog` 那条要自己装了才能验，本文不给它结论。下面这些坑是前两条跑出来的：

- `xelab` 的 `--relax` **不是必需的**：本机不加它也能 `Built simulation snapshot`。加了不出错，
  但别以为少了它跑不通是设计有问题。
- 判定行的**提取管道是仿真器特有的**，不能一条通吃：`xsim` 的输出里 `TB_RESULT` 顶格在第一列，
  `grep -m1 '^TB_RESULT'` 有效；`vsim` 的 transcript 每行带 `# ` 前缀（而且是 CRLF），
  同一条 `'^TB_RESULT'` **命中 0 次**。ModelSim 侧要写成
  `grep -m1 'TB_RESULT' ms.log | sed 's/^# //' | awk '{print $2}'`。
  换仿真器时先确认"这条 grep 打得中吗"，取法：拿一份已知有判定行的日志跑一遍，
  命中数必须是 1（这就是 §4 的正向对照用在提取层）。
- `xvlog` 不加 `-sv` 编译含 `final`/`int` 的 tb：`ERROR: [VRFC 10-4982] syntax error near 'begin'`
  且退出码非 0；加了 `-sv` 退 0。但 **`$fatal` 单独出现时不需要 `-sv`**（两个工具都接受、都能跑）。
  ModelSim 的 `vlog` 按扩展名自动切：同一段代码放 `.sv` 不加 `-sv` 也是 `Errors: 0`，
  放 `.v` 才报 `Errors: 5`。
- **`xsim` 与 `vsim` 在判定失败时退出码都是 0**（实测：transcript 里明明印了
  `TB_RESULT FAIL` 与 `** Fatal`，`$?` 仍是 0）。所以批处理脚本里红绿只能这样取：
  （注意这是**仿真器**那一侧的"返回码不可信"；构建/报告命令的同一形状是另一件事，
  看 `constraints-timing.md` §4 第 4 条——两处都别拿返回码当门。）

  ```bash
  xsim simv --runall | tee build/sim/tb.log
  grep -m1 '^TB_RESULT' build/sim/tb.log | awk '{print $2}'   # PASS / FAIL / NOT_RUN
  ```

判定不依赖仿真器的输出格式，只依赖第 1 节那条结论行；但换仿真器仍要完整重跑一遍——`-sv` 的默认
值、`$finish`/`$fatal` 的行为、退出码语义三家都不同。

`vlog`/`xvlog`/`vsim` 报 "command not found" 或 "No such file or directory"，通常是 PATH 或没
source 工具的设置脚本；这跟"`vivado -mode batch` 的 Tcl、xsdb、仿真器批处理是**三套命令集**"
（`SKILL.md` §5 开头那一条）是两类不同的错，别互相甩锅。波形与日志写到工程目录之外，
否则"目录清洁"类检查会被自己的输出弄红。

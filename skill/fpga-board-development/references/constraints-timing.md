# 约束与时序 — 建立时钟模型、证明约束命中、判断值不值得重跑构建

本页的 Tcl 写法与报告字段名，凡标"本机实测"的都是在这台机器上跑出来的读数（Vivado 2025.2.1，
装在 `<安装根>/Vivado/bin`，不在 PATH 上）；没有标注的那几句是常规写法，用前先取一次形状再写判断。

**取形状只能用 `-help` 或直接调用，不能用 `info commands`。** 这版工具的命令是**懒注册**的：
新开会话（或还没打开工程）时 `info commands` 对着一堆确实存在的命令返回空——实测
`wait_on_run`、BD 那一串、`open_hw_manager` 全都查不到名字，而它们在正确上下文里都能跑
（`open_hw_manager` 那一批是在 `load_features labtools` 之后才出现名字）。反过来说，
"查不到名字"推不出"这版没有"。真正能定的是**调用结果**：印用法 = 在；
`invalid command name` = 这个名字在这条路径上不可用（本机一对对照读数：未注册时
`create_bd_design -help` 照样打出 `Description:` 用法，而 `write_project_xpr -help`
报 `invalid command name "write_project_xpr"`，`load_features` 前后都一样）。
注意 `[Common 17-25] No topics matched` 是**另一路** `help <名字>`（Tcl 帮助系统）的报法，
别把两种否定形状当同一条判据互相换用。
用 `-help` 时留意别名：`wait_on_run -help` 打出来的标题是 `wait_on_runs`（同一条命令的另一个名字），
别因为标题不等于你敲的就判它不存在。

## 1. 先有时钟模型，再谈时序

没有进时钟模型的对象，工具不会去分析它——路径**未被检查**不等于**满足**。第一件事是把所有真实
钟源出名册：

```tcl
create_clock -name clk_sensor -period 37.037 [get_ports clk]
report_clocks            ;# 名字与周期逐条和设计意图对上
check_timing             ;# 重点看 no_clock、unmatched、no_input_pause 这几类条目是不是空
```

**MMCM/PLL 输出脚上的时钟，工具一般已经从时钟网络自己推导出来了**（`report_clocks` 里能看到）。
所以别一上来就在综合时钟管理 tile 的输出脚上手工 `create_generated_clock`——那是 UG903 不推荐的
做法（会撞车，非要用得加 `-add`）。`create_generated_clock` 的正当用途是给**逻辑里分频或选择出来
时钟**建模，例如：

```tcl
create_generated_clock -name clk_half -source [get_ports clk] -divide_by 2 \
    [get_pins u_div/q_reg/Q]
```

例化名、层级、`top` 变了之后，按 pin/cell 名写的约束会静默失效，症状就是"换了时钟来源，时序突然
变好"——那不是收益，是那片路径没人检查了。**每次改时钟来源或改层级，都要按名逐条回查依赖它的约束
还在命中对象。**

## 2. 每条约束要自己出命中数

```tcl
# 反例：端口/例化名改过之后，下面两条展开成空集合，工具打条 warning 就继续跑到全绿
set_false_path -from [get_ports cfg_strobe]
set_false_path -from [get_ports cfg_data*]
```

判定标准是**命中集合是否为空**，不是"有没有红"，也不是"日志好不好看"。数命中用 Tcl 原语：

```tcl
llength [get_ports -quiet cfg_strobe]     ;# 0 => 这条约束什么都没约束
get_ports -quiet cfg_strobe               ;# 空集合同样说明问题
```

非 0 只是第一层，**数量也要与设计意图对上**：端口集合是**按位展开**的——本机一个 4 位输出端口
在 `[get_ports]` 里是 `q[0] q[1] q[2] q[3]` 四个对象，不是一个。所以命中数写着"应为 1"而实际是 4
（或反过来）都是问题，判据是把期望的位数一起写进那条检查里。

`sizeof_collection` 是这类判据的常见写法，**在这版上它不可用**：本机 2025.2.1 打开工程后调用
`sizeof_collection [get_ports -quiet clk]` 报 `invalid command name "sizeof_collection"`，
`sizeof_collection -help` 也是同一句（不是"没注册"那种空返回，是这个名字本身不可用）。
而 `llength` 是 Tcl 原语，一直可用——所以判据写成 `llength`，不要写成前者。两种错法都记一下：
写成 `sizeof_collection([get_ports ...])` 这种函数调用形式，任何版本都是错的（Tcl 用空格分隔）；
以及把网上抄的集合命令当通用原语，先按本节前两句的办法验一次。

还有一条与"空集合"同形但不同因的，而且**这两个命令的行为不一样**（把两条都重取过）：

- `list_property_value <属性> [get_files 不在工程里的.xdc]` → **也是抛**，不是回空：本机
  `[Common 17-56] 'list_property_value' expects exactly one object got '0'`（rc=1）；
  同一句换成**在工程里**的文件、但属性名不存在 → 另一个编号
  `[Common 17-43] The object type 'file' does not have a property 'NOPEPROP'`（rc=1）；
  属性名合法且对象恰好一个时，它给的是**该属性的取值清单**（本机 `USED_IN` 交出 558 字符、
  几十个合法值，rc=0）。所以**别抄"这一句给空串、不报错"那种写法**：
  `list_property_value` 只有在"合法属性但确实没有可列值"那种对象上才可能回空，
  而"名字不存在"与"对象不存在"这两条**都抛**，都会打断后面所有读数。
  判"这个属性名查不到"之前先数对象（`llength`），再包 `catch`。
  又补一格：`list_property_value [get_ports -quiet 不存在] IOSTANDARD` → 返回码 **1**、
  `[Common 17-161] Invalid option value 'IOSTANDARD' specified for 'object'.`——
  **它把属性名当成非法值报出来，一个字都不提"对象集合是空的"**，
  所以照着消息文本去找属性名会找错方向；"先数对象"在这一格同样是唯一能红的那一步。
- `list_property <空集合>` → **抛异常**：`ERROR: [Common 17-56] 'list_property' expects exactly one
  object got '0'`。同一句换成 8 个对象（`list_property [get_pins -quiet -hier */C]`，本机 8 条）
  还是 17-56，只是尾巴变成 `got '8'`——**这个命令要恰好一个对象**，多了少了都抛。
  在 pins/cells/files 三种对象上都取到同一句。

两条合起来的规矩：先 `llength [get_files X]` 确认对象在**且只有一个**，再问属性；
`catch` 要包住 `list_property` 本身（不包就断整轮——自己的三次实证：一句
`expr $pcw/1` 的 `invalid bareword "PCW_"`、一句读没赋值的 `$wv2` 的 `can't read "wv2"`、
一句对空集合的 `current_bd_design`，每次都把**那一行之后所有读数**整段抹掉，日志里只剩前半截；
包了 `catch` 的那些步则一条不丢。见 `onchip-debug.md` §2 那条 `17-55`）。
另有一个编号 `[Common 17-423] (property list) would need more arguments...`，
本机是在"属性表达式没给对象"那种写法上取到的；**同一句问法换 run 对象又是第四个编号**
（`list_property [get_runs -quiet 不存在的名字]` → `[Common 17-58] '' is not a valid first class
Tcl object.`——**引号后面没有逗号**：本机第一版探针把消息 `split` 之后用 `,` join 打印，
于是抄出一个工具从没打过的逗号。**抄日志文本之前先确认它是整行打印还是被拆过**。
取法与逐条读数见 `vivado-build-run.md` §5）。**同一个"问法不对"会有不同编号，
所以别按编号分类，按"它抛了 / 它回空"分类**，这一步和数命中数是同一件事，不是额外仪式。

工具在约束找不到对象时打的是**可搜的原文**，本机实测（把两条指向不存在端口的
`set_false_path` 和一条指向不存在实例的 `create_generated_clock` 交给 2025.2.1）：

```
CRITICAL WARNING: [Vivado 12-4739] set_false_path:No valid object(s) found for
                  '-from [get_ports wr_strobe]'. [.../top.xdc:2]
CRITICAL WARNING: [Vivado 12-4739] create_generated_clock:No valid object(s) found for
                  '-source [get_pins u_mmcm/CLKIN1]'. [.../top.xdc:4]
```

**但"找不到对象"的文案不止这一种**：同一版本本机也拿到过 `WARNING: [Vivado 12-481] No ports matched
'...'` 与 `[Vivado 12-584] No ports matched ...`（同页 §7 就有两条是这种形状），调试端口那一族更是
`WARNING: [Vivado 12-1423] ...` **配一个返回 0**——所以某些资料里的 `No ports matched` 并不是"没这回事"，
只是**这一条约束**在这一次用的说法。更值得记住的是同一次运行里，这三条 CRITICAL WARNING 在日志
第 53/56/60 行，而第 214 行照样印：

```
Synthesis finished with 0 errors, 0 critical warnings and 0 warnings.
```

**观察到的事实是：摘要那行与日志里的 CRITICAL WARNING 不一致**（原因我没有证据，可能是摘要只统计
综合阶段而不含约束处理阶段）。结论只有一条：摘要行不能当"日志干净"的证据。
而**搜文案只能当线索，不能当判据**——上面那段就是原因：文案至少有 `No valid object(s) found`、
`No ports matched`、`12-1423`（配返回 0）三种，漏搜一种就是一条假绿。判据一律是
**逐条约束自己数命中集合**（上面那段 `llength [get_ports -quiet …]` / `get_pins` / `get_cells`），
文案搜索只用来定位"是哪一条约束"，不用来宣布"没有死约束"。

## 3. `set_false_path` 的射程与代价

它只表达"这条路径不必按同步关系算"，不会替你补同步机制，也不会让多位总线变得一致。三个反复出现的
代价：

- **豁免铺宽**：会把"同步器最后一级 → 宽扇出逻辑"这种**真该计时**的路径一起消掉，之后保持余量
  好看毫无意义。豁免范围要收到"异步输入 → 同步器第一级"这一小段。
- **连复位检查一起关**：命中路径上的 setup/hold/recovery/removal 全部取消。所以"给复位加了
  false_path"= 放弃验证复位余量，别以为还有人在查（见 `rtl-pipeline-cdc.md` §4.3）。
- **数据腿裸奔**：多位数据跨域时，走线偏差不因为删了检查就消失。数据腿用有界约束：

  ```tcl
  set_max_delay -datapath_only -from <源寄存器> -to <目的寄存器> <周期>
  ```

  这里的 `<周期>` 用**目的时钟周期**（慢的那一侧），`-datapath_only` 表示只约束数据路径延迟、不牵连
  时钟路径。**两个钟有共同来源时 `-datapath_only` 不会自己挑时钟对**：本机对同一对钟
  先得到 `ERROR: [Constraints 18-510] A clock pair with common or internal edges must be specified
  with the option -clock_pairs`，加上 `-clock_pairs [get_clocks slow_clk] [get_clocks fast_clk]`
  之后 `Requirement` 才真的变成 40.000 ns（不加时它压根没落地，而 `set_max_delay` 那句本身看着是成功的）。
  所以这类"看起来收下了"的有界约束，判据是那条路径的 `Requirement` 变成你要的数，不是命令返回。**判它有没有落地不能用 `report_exceptions`**：本机两条 `set_max_delay`（一条寄存器到寄存器
  跨域、一条带 `-quiet`）都没出现在那张表里——那张表收的是多周期/false path/case analysis 这一族。
  有界约束的读数是那条路径的 `Requirement`（§4 的 `report_timing` 头部）。
- **总线偏斜这一族：命令在、写法与判据都换了。** 存在性用 `-help` 问（本机 `set_bus_skew -help`
  与 `report_bus_skew -help` 都打出用法行——这比 `info commands` 有返回强，后者只能作正向读数）。
  **`-skew` 不是选项**：skew 值是**按位置**给的，
  `set_bus_skew -from [get_pins -quiet -hier */C] -to [get_pins -quiet -hier */D] 2.0` 返回 0，
  而照网帖写 `… -skew 2.0` 得到 `[Common 17-170] Unknown option '-skew'`。
  对象也挑：`-to` 给了枚举不到的模式，报的是
  `[Vivado 12-4739] set_bus_skew:No valid object(s) found for '-to [get_cells -quiet {f_r_reg[*]}]'`
  ——**注意它把你的表达式原样回显**，这是这条命令最好用的地方（拿回显对『我到底约束了谁』）；
  始点定义不符另一条是前面那个 `[Constraints 18-513]`。
  **落地判据是 `report_bus_skew` 的 Summary 表**，列名本机取到的是
  `Id Position From To Corner Requirement(ns) Actual(ns) Slack(ns)`：
  有你那一行（按 `From`/`To` 认，`Position` 会变）说明约束在跑，`Slack ≥ 0` 说明达标；
  表的第二节还会把那条 `set_bus_skew …` 原句印一遍。取文本要 `-return_string` 或 `-file`
  （§4 第 5 条：默认调用的返回串是空的）。
  本机那次读数 `Requirement 2.000 / Actual 1.942 / Slack 0.058` 是**综合阶段**的
  （报告头 `Design State : Synthesized`），没有布线延迟，`Actual` 基本是估算——
  这一族的签字仍然要等实现之后（页首那条）。命令与对象都不合用时才退回 `set_max_delay` 兜。

同步链**内部**（第一级→第二级）是全同步的，必须继续按时序检查。放宽了多少条路径，写进改动记录
——**怎么数不在本节**：例外表的前后差与那条路径 `Requirement` 的变化在 §9，
"每加一条豁免就记一次豁免量"这条规矩的约束文件版本在 §8 第 7 条。

## 4. 读报告只看这几个数，且分清是哪一阶段

```tcl
report_timing_summary -delay_type min_max -max_paths 10 -file build/reports/timing.rpt
report_timing -from {u_win/state_reg[3]/C} -to {u_proc/mag_reg[7]/D} -path_type full_clock_expanded
check_timing
```

`check_timing` 的输出本身就带条目计数，形如 `1. checking no_clock (0)`——括号里的数字就是该类
未约束对象的数量，直接读它，不要只看它有没有红。

要把报告读进脚本而不是落文件：多数 `report_*` 收 `-return_string`（本机在
`report_timing`、`report_timing_summary`、`report_clocks`、`report_io`、`report_exceptions`、
`report_clock_interaction`、`report_property` 上都试通了），配 `lsearch -inline -glob`
按行取字段即可。**但注意**：`-return_string` 返回的是报告正文，命令失败时它返回的是那段
`ERROR:` 文本而不是异常——先判 `string match ERROR*` 再解析，否则你会去解析一句错误信息里的数字。

`-from/-to` 的对象名带位索引时**必须加花括号**（`{u_win/state_reg[3]/C}`）：`[3]` 不加括号会被 Tcl
当命令求值。`report_design_analysis` 这类分析命令的**选项名会漂**：本机 2025.2.1 实测
`-analyze`、`-num_paths`、`-high_fanout` 全部报 `Unknown option`，而同一条命令确实存在、
**同一条命令的 `-congestion` 与 `-complexity` 也实测可用**（§6 有它们的正例与"表体只有说明行"
读数）——这就是"命令在、选项不在"的一对最好控制实验：同一次会话里一条通过、三条被拒。所以
第一次用之前先 `report_design_analysis -help` 取一次本机可用的选项，再写进脚本；把别人给的选项
原样抄进来，最可能的结果是命令在、选项不在。

| 字段 | 位置 | 含义 |
|---|---|---|
| WNS | `report_timing_summary` 的 Design Summary（max） | 最差建立裕量；<0 就是违例 |
| TNS | 同上 | 违例总量，决定"修一条够不够" |
| 失败端点数 | 同上 | 一片还是几条；1 条和 5000 条的修法不同 |
| WHS / THS | **min** 那一栏 | hold 违例；移位链、复制驱动之后常见 |

三条口径 + 两条"报告文本到底怎么拿到手"的读法（合起来五条）：

1. **综合阶段的时序数字是推测值**（没有真实布线延迟），只能用来提前发现明显做不到的逻辑锥；
   "时序收敛"这句话只能由 implement 完成后的报告说。
2. 建立与保持要一起看：只取 `-delay_type max` 的报告里 hold 那栏是空的或没有违例，
   **不代表 hold 干净**。要么 `-delay_type min_max`，要么另跑一次 `-delay_type min`。
3. 报告要与**烧进板子的那一次 impl** 对应：`.rpt` 与 `.bit` 一起记哈希并放在一起，
   否则你可能拿上一版的干净报告给这一版签字。
4. **"报告里没找到路径"与"这条路径不存在"是两件事，而这两件事又都和"你没把文本拿到手"是三件事。**
   `report_timing` **没有路径时也返回 `TCL_OK`、`catch` 返回码为 0**；它只印一条
   `INFO: [Timing 38-72] No paths found`（加了 `set_clock_groups` 之后同一件事换编号，
   本机见到 `38-481`），而 **`-quiet` 把这条 INFO 也吞掉、返回码仍是 0**。
   还抓到 `-quiet` 更狠的一格，方向相同、机制不同：把 `-from` 指到一个**不存在的钟**上
   （工具先打 `WARNING: [Vivado 12-627] No clocks matched 'c1'` 与
   `INFO: [Vivado 12-626] No clocks found. Please use 'create_clock'…`，集合是空的），
   不带 `-quiet` 的那一句 rc=**1**、`-return_string` 长度 **0**；
   同一句加 `-quiet` 之后 rc=**0**、返回串照样长度 **0**。
   **也就是 `-quiet` 能把"这条命令失败过"这件事本身抹掉**，那一格的 0 连失败都不留痕迹——
   只更坐实了下面那句：判据只能取文本与对象计数，返回码在这条命令上什么都不是。
   顺带一条撞到的钟对象事实：**给同一个端口连建两条 `create_clock`**
   （本机 `c1` 周期 10、`c2` 周期 14 都打在 `clk` 上）之后 `get_clocks *` 只剩 **`c2`** 一条，
   前一条不留痕迹；接着 `set_clock_groups -asynchronous -group [get_clocks c1] -group [get_clocks c2]`
   报 `[Vivado 12-5201] set_clock_groups: cannot set the clock group when only one non-empty group remains.`
   ——所以"两条时钟"要落在**两个不同的端口/网络**上，且写完立刻 `get_clocks *` 数一遍
   （上面那一串空集合报错的根因就是这里）。
   所以"返回码 0"上有三个都能成立的解释：有路径 / 没路径 / 你没把文本拿在手里——
   **用返回码当门等于没装门**。方向写反、对象名被改动（§7 第 2 条、§8 那套连锁）都会落进
   "没路径"这一支，而它们要修的是不同的东西。
   仿真器那侧也有一条形状一样、原因不同的规矩（`xsim`/`vsim` 判 FAIL 时退出码仍是 0，
   见 `verification.md` §1）——两边都是"读文本，不读返回码"，但别把一条的实测数字搬到另一条。

5. **两条独立的轴：捕获轴（`-return_string` / `-file`）与噪声轴（`-quiet`）。** 同一份设计上
   把四格都取到了（`string length`）：

   | 写法 | 返回串长度 |
   |---|---|
   | `report_timing -setup`（顶层，不套 `catch`） | **0** |
   | `catch {report_timing -setup} m` | **0** |
   | `report_timing -setup -return_string` | 4875 |
   | `report_timing -setup -quiet -return_string` | **4882** |

   那 7 个字符的差**取到一次同样的 +7**（`report_timing_summary -return_string` 给 7837/7844，
   `report_timing` 给 4153/4160），而 §7 第 6 条数过报告头的第 6 行就是
   `| Command      : <这条命令原样回显>`——` -quiet` 恰好 7 个字符，
   所以最合理的解释是**多出来的是命令回显、不是正文**（这仍不是逐行 diff，
   把长度差本身当证据依旧不对）。这一格要的主张只是"两格都非零、都给全文"。
   真要按 `-quiet` 生效取证，去看**消息**少没少
   （`38-72` 那条 INFO 在不在日志里），而不是去数字符。

   **结论**：`-quiet` 吞的是**消息**（那条 `38-72`/`38-481` 的 INFO 和别的
   告警），**不是返回串**——带 `-return_string` 时它照样把全文给你。所以
   **在这一族命令里**（`report_timing`/`report_clocks`/`report_utilization`）"拿到空串"不能读成"工具没给"，只能读成"你没要求它把文本交出来"**；
   **但这条不是全族共用的**：`report_ip_status -return_string` 在**没有 IP 实例**的工程里给 rc=0、长度 0（表照旧打到日志），同一句在有 IP 的工程里给 2234 字符全文——所以长度为 0 先问"有没有可报的东西"，再问"捕获坏没坏"（逐条见 `vivado-project-bd.md` §2.1）——
   每个要解析的报告都要在自己这版上取一次长度，别把一个命令的捕获规矩搬给另一个。
   而"`-quiet` 会把判据吞掉"这句话仍然成立，只是被吞的是**你要靠搜索的那句话**，不是整份报告。
   可用的两种捕获：`-return_string` 自己解析，或 `-file x.rpt` 再读
   （本机对 `report_timing`/`report_clocks`/`report_utilization` 都确认 `-file` 真生成文件；
   `report_clocks` 的对照是 0 对 1419）。
   本页第 4 条以前写的"`-quiet` 时输出长度 0、普通调用长度 866"两个数**都与这轮不符**，
   最可能是那一次本来就在 `-return_string` 形式下取的——**引用之前自己重取**。

## 5. 值不值得再开一轮构建

综合/实现是小时级任务。开构建之前先估收益上限：

1. 从 `report_timing` 拿这条锥的逻辑级数与最大延迟分量，看数据路径延迟占周期的比例。
2. 如果这一锥改完的估计收益明显够不到违例量，就把它**排在后面**而不是排第一——注意这是排序依据，
   不是"不会出结果"的停止条件：同一轮里别的路径、拥塞与复制驱动可能一起变化。
3. 收益类型分清楚——插一级寄存器是**改延迟分配**、复制高扇出是**改布线**、换时钟源是**改约束射程**，
   三者的复现口径不同，不要把"读数变好"当成"这类改动有效"。
4. 只盯 WNS 会漏：改完要按时钟组逐条比"别的组不许变差"，每组的 WNS 都抄下来。

## 6. 利用率

`report_utilization` 在综合后的设计上能跑（本机一份 8204 字符）。
**分层那张表的名字不是 `-hierarchy`**：在综合后的设计上把写法都取了一遍——

- `report_utilization -hierarchy` → `[Common 17-170] Unknown option '-hierarchy'`（返回码 1，
  而 **`-return_string` 交回来的就是那行 ERROR 本身**，107 字符；`report_clock_utilization -hierarchy` 同形）。
  所以"拿到非空串"**不等于**"拿到报告"——这一族要判的是 `catch` 的返回码，不是串长。
- `report_utilization -hier` → 第三种形状：`ERROR: '-hier' option is ambiguous and matches
  'hierarchical', 'hierarchical_depth', 'hierarchical_min_primitive_count', 'hierarchical_percentages'`。
- 正确写法是 **`-hierarchical`**，而且它**不要求先布局布线**：综合后调用返回 0、表体就有内容
  （本机 `| cnt | (top) | 6 | 6 | 0 | 0 | 8 | 0 | 0 | 0 |`；**实现之后同一份设计取到 1556 字符**——
  列名与行内容**与综合后那张一模一样**，多出来的只有表尾这一行说明：
  `* Note: The sum of lower-level cells may be larger than their parent cells total, due to
  cross-hierarchy LUT combining`。所以**阶段差在这张表上体现为脚注而不是数字**，
  别拿"数字变了"当"已经取到实现后的表"的证据；要证明阶段，看报告头的 `Design State`）。
  **本页早前写过"`-hierarchy` 在没布局布线的设计上抛 `17-53 Cannot get report for design not
  placed or routed`、分层视图只属于实现之后"——那条按同样的步骤没能复现**（复现不出来的是那个
  错误号，也是那个阶段限制）。阶段受限的是另一族：`report_design_analysis -congestion` 未布线时
  只打说明行（本节末尾）。
- `-cells cnt` → `[Common 17-162] Invalid option value specified for '-cells'`（要传**对象集合**：
  `-cells [get_cells -quiet *]` 返回 0）；`-pblocks [get_pblocks -quiet NOPE]` **也**是 17-162，
  不是"空集合"那一族错误——**选项值不合法与对象不存在，工具用的是同一个号**。

70%/80% 这类上限是**能不能布得下**的经验阈值，不是
功能正确性；换器件、换布局策略后要重新取数。BRAM/DSP 的占用与"推断成了什么"直接相关：源里一段
简单的数组读写可能被推成 BRAM 也可能被推成 LUTRAM，看报告里那一行的名字，不要凭猜。

**要一个"插调试核到底占了多少"的数，能走的是差值法**（它给的是上界，不是核的净成本——见下面第三个前提）：同一份源、同一 part 全名、同一策略
与 directive 快照，跑两版构建（不带探针 / 带探针），比两份 `report_utilization` 的**同类行**。
三个前提别忘：两份必须**同阶段**（综合后与实现后的数不能相减，本页页首那条）；
策略与 directive 快照要一致（取法在 `vivado-build-run.md` §7 第 3 条，那条才是 run 属性快照；
§4 讲的是 part/VLNV/驱动 tcl/产物四件）；**带探针那一版通常会抑制优化**（多出来的网络与约束
会让布局器改主意），所以减出来的差值**不等于**核的净成本——它的含义是「这一版整体贵了多少」。
要拿净成本就得让两版只差调试核这一件事、其余全部相同。**这组对照本机做成过一次**：
两臂同一份 `cnt.v`、同 part、同一步骤序列（`synth_design` → `create_clock -period 10` →
`write_checkpoint` → `open_checkpoint` → `place_design` → `route_design`），B 臂只多了
"一颗 ILA + 自动 `dbg_hub`"这一件事（两臂各自独立会话，避免共享临时目录互相锁住——
同一会话里连跑两臂时第二臂的 `synth_design` 会撞 `[Designutils 20-411] … could not be deleted
and may be locked`，那样出来的差值不能用）。差值：
`LUT as Logic` 6→950、`LUT as Memory` 0→85、`Slice Registers` 8→1810、`Block RAM Tile` 0→0.5、
`Bonded IOB` 10→10（没动）；时序侧 `WNS` 7.746→3.773、`WHS` 0.191→**−0.887**
（hold 失败端点 0→2、TNS −1.373），端点总数 8→3467。
**这是一份设计的差值，不是"核的成本表"**：换探针位宽/深度、换设计、走没走 `opt_design` 都会动数
（上面那张三行表里"综合阶段 1093 LUT"与本组"路由完成后 950+85"是**不同阶段**，
既不能互相校对更不能相减）。报它的时候必须连同"两臂只差哪一件事"一起报，
否则又退回上界那个含糊说法；这一对数没做过第二份设计，**别当通用常数搬**。
单个层次占多少，用上面那条 `-hierarchical`（综合后就给得出）。
**"插一个调试核到底贵多少"本机有数了**（一份 8 位计数器 `cnt`、`xc7z020clg400-1`、2025.2.1，
一路 `create_debug_core u_ila_dbg ila` + 连 `clk`/`probe0` + `dbg_hub` 自动加进来；
两臂都给了 `create_clock -period 10` 并各自跑完 `place_design` + `route_design`）：

| 取数时机 | Slice LUTs | LUT as Memory | Slice Registers | Block RAM Tile | BUFG |
|---|---|---|---|---|---|
| 纯综合，没核 | 6 | 0 | 8 | 0 | 1 |
| 核已 create+connect、`write_checkpoint` 后重开 | 6 | 0 | 8 | 0 | 1 |
| `implement_debug_core` 之后 | 1093 | 85 | 1810 | 0.5 | 2 |

**时序那一侧的两臂读数更要紧**（同一份设计、布线完成之后取）：

| 臂 | WNS | WHS | hold 失败端点 | setup 端点总数 | 最差路径的 Requirement |
|---|---|---|---|---|---|
| 没核 | 7.865 | 0.212 | 0 | 8 | 10.000 ns（`fast` 那一路） |
| 带核 | 3.775 | **−0.653** | **2**（TNS −1.077） | 3467 | **33.000 ns**，路径起点在 `dbg_hub/inst/BSCANID.u_xsd…` |

这两臂**各自在两个独立会话里跑过一遍**（同一份脚本、同一份 dcp），`report_timing_summary` 的那一行
两次逐字符相同——所以这组数不是单次侥幸；但**换设计、换 part、换探针宽度都要重取**，
本包的规矩仍然是"引用报告字段之前先在自己的机器上打一次真实形状"。

这张表要带走三件事：① **中间那一行是坑**——核建好、连好、甚至存了 checkpoint，
`report_utilization` 都还看不到它（它这时是黑盒占位），所以"插了核占用没变"推不出"核没插上"；
判"插上了"要看 `implement_debug_core` 之后的数；**数 `get_cells` 时必须带 `-hier`**。
同一会话里落地前后各取一遍（`xc7z020clg400-1`、2025.2.1）：

| 读数 | `implement_debug_core` 之前 | 之后 |
|---|---|---|
| `llength [get_cells -quiet *]` | 35 | **35（一模一样）** |
| `llength [get_cells -quiet -hier *]` | 35 | **3592** |
| `llength [get_pins -quiet -hier */D]` | 8 | **1993** |
| `catch implement_debug_core` 的返回码 / 结果串 | — | **rc=0 / `CDC-15#11`** |

所以两件事同时成立：**不带 `-hier` 的 `get_cells` 根本看不见核落地**（它数的是顶层单元），
而这条命令的返回码为 0、结果串永远长那个样子——**成不成的证据只有 `-hier` 那一族与占用表**。② **调试核会自己带进一个新的钟域**：
带核那一臂最差 setup 路径的 `Requirement` 是 33.000 ns、挂在 `dbg_hub` 里 BSCAN 那条路上，
它不在你的功能约束里，却在同一份报告里跟你的路径混排——**"插核之后冒出来的新违例"要先问是不是它的**
（`onchip-debug.md` §2 的读回判据管这件事）。③ **hold 是被它带出来的**：没核那一臂 WHS 0.212 干净，
带核同一份设计 WHS −0.653、两个端点失败——**这正是"调试版的数字不能给交付签字"的具体形状**，
不是抽象告诫（`SKILL.md` §1 第 3 条）。

两条边界要说清：这些是**同一份小设计、同一会话**的数，不是"只差 `MARK_DEBUG`"的两版构建对照
（上面差值法那三个前提在这里都不成立），换器件、换核宽、换探针数都会变；
它们能给的只是**量级**（一个 ILA + `dbg_hub` 在一颗 7z020 上是 10^3 个 LUT / 10^3 个 FF 这一档，
相对设计本身贵两到三个数量级），**不能**拿来给交付版签字——交付要的是自己那份设计、实现之后的两次构建差值。
"哪一块区域最挤"不是占用表答的，是 `report_design_analysis` 那一族——**本机实测这版有 `-congestion`
与 `-complexity`（都返回 0），而没有 `-placement`、`-clock_summary`、`-unconstrained`
（各报 `[Common 17-170] Unknown option`）**。要点不在"有没有这个选项"，在**空表长什么样**：
综合后调 `-congestion`，它返回 0、表头齐全
（`Direction Type Level Congestion Window Combined LUTs Avg LUT Inputs LUT LUTRAM Flop MUXF RAMB DSP CARRY SRL Cell Name`），
但表体只有一句 `* The design has not been placed, hence congestion data is not available...`；
`-complexity` 在小设计上同理打 `* No complexity report generated as cells satisfying given conditions
are not present in the design.`。**这两句说明行才是判据**：返回码与"文件生成了"都不区分
"没数据"和"数据过关"。要拿到有内容的拥挤表，只能在 `place_design` 之后取
（这条阶段规矩只属于 `-congestion`/`-complexity` 这一族；上面 `-hierarchical` 那条**不是**同类，
它的"要等实现之后"已经被实测推翻，别再拿两者类比）。

## 7. 物理与 IO 约束：电平、时钟输入、没约束的脚

时序约束管"多快"，这一节管"接错没接错"。接错的典型表现不是报错，而是**功能时对时不对、
换个温度或换块板子就坏**（后半句是这类问题的常见叙事与机理，**不是本机的读数**——本机没有板子，
也没做过温度或换板实验；这一节的判据全部走"报告里能不能数出来"，不依赖这句话）。

```tcl
set_property PACKAGE_PIN H16 [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_p]
create_clock -period 10.000 -name sys_clk_p [get_ports clk_p]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PULLTYPE PULLUP     [get_ports btn_n]
report_io
```

规则：

1. **电平标准由 bank 电压决定，不是由你想用哪个标准决定。** 先确认这个脚落在哪个 bank、
   那个 bank 的 `VCCO` 从哪来（Zynq 的 PS bank 由设计里的 PS 配置定，PL bank 由板子供电定）。
   判据是原理图/IO 分配表，不是"以前这个工程写过 `LVCMOS33`"。没写 `IOSTANDARD` 的脚不等于
   没电平——工具会按 bank 给一个默认值（本机一个未约束的输入脚 `get_property IOSTANDARD`
   读回 `LVCMOS18`），所以"读回有值"不能当"我约束过"的证据。
2. **属性名要按对象查，且随方向变。** 判据是 `list_property [get_ports <name>]` 与
   `list_property_value <属性> [get_ports <name>]`。**问之前先确认对象存在**：
   `catch {list_property <空集合>}` 不是返回空，是**抛异常**（`[Common 17-56] expects exactly one
   object got '0'`；给它 8 个对象同样抛，只把 `got '0'` 换成 `got '8'`——见本节前部那条，
   那里还把 `list_property_value` 的回空行为与它分开列了）。脚本里它会直接打断后面所有读数
   （本机就打断过一次）。所以顺序是 `llength [get_ports -quiet X]` → **等于 1** 才问属性。
   本机在一个**未约束输入脚**上把"名字查清单"这件事查成了一个更不好受的形状，三个状态按顺序取：
   写任何东西之前 `list_property [get_ports clk]` 给 **62** 项——`PULLTYPE`、`IN_TERM`、`PACKAGE_PIN`、
   `IOSTANDARD` 都在，`PULLUP`/`PULLDOWN`/`SLEW`/`DRIVE`/`TERMINATION` 都**不在**；
   **只**补一句 `set_property IOSTANDARD LVCMOS33`（这一变量单独隔离过，免得和下一句混成"一次改两个"）
   之后**还是 62 项、`PULLUP` 还是不在**；再跑网上最常见的那句 `set_property PULLUP true`——
   返回码 **0**、`get_property PULLUP` 读回 **1**，而**清单变成 63 项、`PULLUP` 就在里面了**。
   也就是说 **`list_property` 是"这个对象当前暴露了什么"，不是"允许写什么"的白名单**：
   写之前不在、写完就在，它抓不住这一条；读回值更抓不住（读回来就是你刚写进去的那个字）。
   真正会红的是**另一族错误号**：`set_property CLOCK TRUE [get_ports clk]` →
   `ERROR: [Netlist 29-177] Cannot set property 'CLOCK' because the property does not exist.`
   ——不是 `[Common 17-*]` 那一族，所以按 17-* 去认"名字写错了"会整个错过它。
   这一族的名字检查因此要写成两问：**①** 这个对象**现在**暴不暴露这个名字（`list_property`，**在写之前**取）；
   **②** 写的时候有没有 `29-177`。两问都过才叫"这个名字对这类对象能用"；
   `PULLUP true` 属于"过了②、没过①"，要换成 ①里本来就有的 `PULLTYPE PULLUP`
   （**这一条本机补测过**：未加约束的输入脚写之前 `list_property` 给 62 项、`PULLUP` 不在其中（0）、
   `PULLTYPE` 在（1）；`set_property PULLTYPE PULLUP` rc=0 且 `get_property PULLTYPE` 读回 `PULLUP`，
   清单变 63。同一次会话再写 `set_property PULLUP true` **也** rc=0、读回 `1`——
   两条都"写得进去"，但只有前一条在写之前就在清单里，这正是①与②要分开问的理由），
   而不是靠读回值给自己宽恕。
   方向差异这条复现：同一份设计的输出脚 `q[0]` 给 **65** 项、含 `SLEW`/`DRIVE`，输入脚两项都没有；
   差分脚、XPHY 脚没查。每类都查一次再写进脚本，属性名与取值都别抄。
3. **差分时钟输入：负端不需要你再写一条 `create_clock`。** 实测给 `clk_n` 也建了一条时钟，
   工具**不报错**，`report_clocks` 里就并列出现 `sys_clk_p` 与 `sys_clk_n` 两条同周期记录；
   同时负端不填 `PACKAGE_PIN` 也会被自动配到正端所在的对上（本机自动给出 `IO_L13N_T2_MRCC_35`，
   标记 FIXED）。所以这里的判据不是"有没有报错"（没有），是 **`report_clocks` 里每个真实钟源
   只应该出现一次**。
4. **换板子 = 重核整张引脚表**，不是改那一两行。而且"删掉 `PACKAGE_PIN` 让它报未分配"这条**不成立**：
   本机留了 5 个未分配引脚跑综合与 `report_io`，没有打任何"未分配"提示（只有
   `Synth 8-7129` 之类的无负载提示）。可数的判据是自己取：

   ```tcl
   llength [get_ports -quiet -filter {PACKAGE_PIN == ""}]   ;# 未分配的端口数
   llength [get_ports -quiet]                               ;# 总数
   ```

   两者之差就是这次真的被约束过的引脚数；换板后先让这两个数对上再谈别的。
   两个配套读数要知道：反方向的 `-filter {PACKAGE_PIN != ""}` 在结果为空时会打
   `WARNING: [Vivado 12-584] No ports matched ...` 并返回空集——那是"真的没有"，不是过滤器写错；
   而 `get_package_pins` 这类"从器件侧列可用脚"的查询，本机在工程模式下取不到任何东西
   （三种写法都空，喂给 `get_property` 还报 `[Common 17-161] Invalid option value ''`），
   所以"哪些脚已被占用"只能从自己那几份 XDC 里数。
   **`-quiet` 是日志卫生，不是判据保护**：空集合时不带它，命令打一条
   `WARNING: [Vivado 12-481] No ports matched '...'` / `[Vivado 12-584] No ports matched ...`
   **到日志**，交回来的仍是空集合（本机实测：`catch {get_pins NOPE} g` → rc=0、`llength $g`=0、
   `string length $g`=0）。本页早前那句"`llength` 数的是那句话的词数"不成立，已按实测改。
   真正的污染发生在**你之后拿这份日志做文本判定时**——告警行会冒充一次命中。
   另一条相关：`report_io` 里**根本不列没有 `PACKAGE_PIN` 的端口**（本机 28 个未分配端口在报告里
   出现 0 次），所以"report_io 里找不到这个脚"推不出"这个脚不存在/没被用"，只能反过来说。
5. **未使用的输入要显式处理**（上拉/下拉用第 2 条查到的那个名字，或在外接电路上解决）。
   悬空输入的代价是功耗与偶发翻转，不是编译错误——**这半句是机理，本机没有可引用的电流或翻转读数**；
   所以它的判据只能是"这个脚上有属性值"
   （读回）与"report_io 里它的方向/标准符合预期"，不是"综合没报错"。
6. **IO 时序要有基准时钟。** `set_input_delay`/`set_output_delay` 不写 `-clock` 时，实测打的是
   `INFO: [Constraints 18-632] set_input_delay: No clock object specified, the clocks will be
   automatically identified`——是"把所有时钟都拿来自动识别"，不是"随便挑一个"，多个时钟源时
   整批失真。写完要证明认的是哪一个：`get_property CLOCK [get_ports X]` **不能**用（`CLOCK`
   不在端口属性清单里，设与不设都读回空，永远不会红）。可判的读数在报告头里，实测形状是：

   ```
   Source:                 a
                             (input port clocked by sys_clk  {rise@0.000ns fall@5.000ns period=10.000ns})
   Destination:            r_reg[1]/D
                             (rising edge-triggered cell FDRE clocked by sys_clk  {rise@0.000ns fall@5.000ns period=10.000ns})
   Path Group:             sys_clk
   Requirement:            10.000ns  (sys_clk rise@10.000ns - sys_clk rise@0.000ns)
   ```

   `clocked by` 后面那个名字就是它认的参考钟。`Path Group` **不能**当凭据：本机见过两种形态——
   `Path Group: sys_clk` 与 `Path Group: 3`（加了 clock group/false path 之后多为数字编号），
   所以它有时是钟名有时是组号。
   **`Requirement: 5.000ns` 那一格已经收回**（原先写成"`-max 2.0` 没写 `-min` 时 hold 侧的
   Requirement 是工具补的、补成 5.000"）：这一条**两次独立复现都不成立**——本机一份只有
   `create_clock -period 10` + `set_input_delay -max 3 [get_ports din*]` 的设计，
   `report_timing -delay_type min -return_string` 交回 2844 字符、**整段里一条 `Requirement:` 行都没有**，
   只有 `Slack: inf`；另一路复核用 `-max 2.0` 重做，同样"865 字符、无 `Requirement:`"。
   那个 5.000 的真实身份是**周期的一半，即下降沿时刻**：它出现在报告头
   `{rise@0.000ns fall@5.000ns period=10.000ns}` 那一段（就是上面那段里的 `fall@5.000ns`），
   不是 Requirement 行。所以现在的写法是：**别把下降沿时刻当工具补的需求**。
   **但 min 报告到底给不给 `Requirement:` 行，本机有两个都真实、互相冲突的形状**，
   分别对应两种输入：①只有 `create_clock -period 10`、没有任何 IO min/max 约束的设计，
   `-delay_type min` 给 `Requirement: 0.000ns` + `Slack (MET) : 0.140ns`（下面"对照的一格"那条）；
   ②同一族设计但**加了 `set_input_delay -max`（没写 `-min`）**之后，`-delay_type min`
   交回的是**没有 `Requirement:` 行、只有 `Slack: inf`** 的段。
   差在哪一个变量本机还没分开（候选：报告挑中的路径是 IO 路径还是寄存器间路径、`-max` 只写半边是否
   让整条 hold 路径变成"无需求"），**在两臂拆开之前，不要把"min 一定有 Requirement 行"写进脚本**——
   要么先打印整段再决定读哪一行，要么显式把 `-min` 写上。
   取 min 报告的那条命令**必须写成 `-delay_type min`**：`report_timing -min` 现在被直接拒绝
   （`ERROR: [Common 17-170] Unknown option '-min', please type 'report_timing -help' for usage info.`，
   本机同一形状再次撞到时是以异常交回、`catch` 里能看到这条 17-170），所以旧记录里那个 `-min`
   不是能跑的原文，抄之前先换写法。
   对照的一格：单钟、只有 `create_clock -period 10` 而没有任何 min 约束时，
   `-delay_type min` 给 `Requirement: 0.000ns  (clk rise@0.000ns - clk rise@0.000ns)` 与一条
   `Slack (MET) : 0.140ns`——**hold 需求默认就是 0**，不要把它读成"这一侧没检查"。
   **但同一份设计上再叠一条 `set_clock_uncertainty 0.5`（不带方向）之后，这一格变成
   `Requirement: 0.000ns` 配 `Slack (VIOLATED) : -0.360ns`**（`Clock Uncertainty: 0.500ns` 这一段
   这时才出现在 min 报告里；max 侧那条从 `0.035ns` 变 `0.535ns`，见 §11）。
   **所以"hold 需求默认 0"说的是需求那一栏，不是"hold 这一侧不会红"**：判 hold 看的是
   `-delay_type min` 报告里的 `Slack` 与失败端点数，不是 `Requirement` 是不是 0。
   （这一格与 §11 那条是同一个实验的两个读数：设之前 `0.140ns`、设之后 `-0.360ns`，
   两次都是同一份综合后网表、同一对端点。）
   同一件事在 `check_timing` 里有对应数字：`10. checking partial_input_delay (1)`。
   输出路径的字样取决于那个脚有没有被绑到真钟上：设过 `set_output_delay -clock <钟>` 之后
  `report_timing -to <port>` 印 `Destination: dout[1]` 加一行
  `(output port clocked by sys_clk {rise@0.000ns fall@5.000ns period=10.000ns})`；
  没绑就印 `(clock source "virtual")`。两种都实测到，共同点是**没有 `Source: … clocked by`
  那一行**——所以"读 Source 下面那行"只对输入侧成立，输出侧读 Destination 下面那行。
   还有三条会吞掉判据的（`report_timing` 没有路径时仍返回 `TCL_OK`、`-quiet` 会把那条
   `No paths found` 一起吞掉而返回码仍是 0）——那是读报告那一节的第 4 条，见 §4；
   这一节只用到它的结论：**"报告里没这条路径"与"这条路径不存在"是两件事，都得从输出文本判**。
   报告头能看出这份报告是哪个阶段出的（§4 第 1 条），但**这些字段是按 `| 名字  : 值` 的表格排版打印的**：
   数过 `report_timing_summary -file` 那份报告的前 8 行，依次是 Copyright 行、分隔线、
   `| Tool Version : Vivado v.2025.2.1 (win64) Build 6403652 …`、`| Date : …`、`| Host : …`、
   **`| Command      : report_timing_summary -file <路径>`（第 6 行）**、`| Design : cnt`、`| Device : 7z020-clg400`。
   `Command` 与冒号之间有一串对齐空格，所以**按 `Command:` 整串去 grep 打不中**（本机取到 0 次），
   要搜就搜 `Command` 或者直接看第 6 行。这一行还顺手回答"那一次到底带了哪些选项"——
   `-quiet` 之类的字面就写在这里。阶段那一栏不在这 8 行里：读的是正文的
   `Design State : Synthesized`（写法与取法见 §4 第 1 条，那句"只有布局布线之后的数字才算时序收敛"靠它定位）。
7. **输出摆率/驱动强度不是性能旋钮。** 改摆率/驱动（属性名按第 2 条在你这类脚上查出来的那个）
   会影响 SI 与开关噪声，动它的结论要落回"这条约束改动前后各自的时序读数"（§4），
   而不是"看着更稳"。
8. `report_io` 是**这一版实现**的 IO 清单：换 part、改 bank 电压后要重新取，
   并让报告与比特流同源落档（§5 那条同样适用）。它存在的判据是命令本身能跑通并输出大段文本
   （本机 `-return_string` 取到约 119 KB），不是"文件生成了"。

## 8. 约束文件的求值顺序：谁后算谁赢

工具按**求值顺序**读约束，不是按你往工程里添加的顺序。顺序由两件事决定：`PROCESSING_ORDER`
（取值就是 `EARLY NORMAL LATE` 三种）先分组，同组内再按表里的 `Index`。同一个对象上，后求值的
约束覆盖先求值的那条是**正常行为**——"我明明写了 `PACKAGE_PIN`，实现用的却是另一个脚"通常是这个，
不是工具抽风。

把顺序变成能读的东西：

```tcl
report_compile_order -constraints
get_files -compile_order constraints -used_in synthesis
```

前一条印 `synthesis` 与 `implementation` 两张表，表头是
`Index  File Name  Used_In  Scoped_To_Ref  Scoped_To_Cells  Processing_Order  Out_Of_Context  Full Path
Name`；后一条是同一信息的机器可读形式，返回值直接是排好序的文件列表。实测对照（三个文件按
board → design → timing 的顺序加进 `constrs_1`，再把 `timing.xdc` 设成 `EARLY`、`design.xdc` 设成
`LATE`）：

```
get_files -of_objects [get_filesets constrs_1]           ;# board design timing
get_files -compile_order constraints -used_in synthesis  ;# timing board design
```

`-compile_order` 的取值写错会报 `[Common 17-162] Invalid option value specified for '-compile_order'`，
而 `-used_in` 与它**必须成对**给。另一条要留神的：`report_compile_order -fileset <名字>` 在
2025.2.1 打 `WARNING: [Vivado 12-3460] ... deprecated in favor of '-of_objects <fileset>'`——
选项会漂，用 `-help` 取一次本版本可用的写法。

规则：

1. **按时钟域与物理域切文件，不按心情切。** 站得住的切法是：一份设计侧（时钟、时钟组、豁免、
   多周期）＋ 一份板侧（`PACKAGE_PIN`/`IOSTANDARD`/IO 时序）＋ 每个 IP 一份带 `SCOPED_TO_REF` 的。
   理由不是整洁：换板子只重核板侧那份（§7 第 4 条），设计侧那份跟着 RTL 走。
2. **"文件在工程里"不等于"它参与了这次构建"。** 开关就在文件对象上：

   ```tcl
   set_property USED_IN_SYNTHESIS 0    [get_files board_b.xdc]   ;# 只退出综合
   set_property USED_IN_IMPLEMENTATION 0 [get_files board_b.xdc] ;# 只退出实现
   set_property IS_ENABLED 0           [get_files board_b.xdc]   ;# 整个文件不参与
   get_property IS_ENABLED [get_files board_b.xdc]               ;# 读回 0
   ```

   `USED_IN_SYNTHESIS`/`USED_IN_IMPLEMENTATION` 置 0 与 `IS_ENABLED` 置 0 的效果**不一样**，
   这一点是分开的两次读数：把两个 `USED_IN_*` 都设成 0，`report_compile_order -constraints`
   **照样列出这个文件**（只是那两个阶段不再吃它的约束，且不告诉你）；把 `IS_ENABLED` 设成 0
   才让它从两张表里消失。所以"文件还在表里"不能推出"它的约束被应用了"，
   也不能推出"没被应用"——**判阶段以两个 `USED_IN_*` 为准，不以 `USED_IN` 那个汇总字符串为准**
   （实测两个旗标都为 0 时，`USED_IN` 仍然打印 `synthesis implementation`）。
   回到 §2 的那条老规矩：想知道约束有没有落到对象上，数命中集合，别看文件清单。
   （顺带一条同名陷阱：文件对象上**没有** `SOURCE` 属性。报错文案随模式变：工程流里是
   `[Common 17-54] The object 'file' does not have a property 'SOURCE'`，
   在 OOC/非工程那一侧是 `[Common 17-124] 'set' has no attribute named 'SOURCE'`——
   两句都是同一个意思，别因为文案不同以为是另一个问题。能列出的属性里有 `USED_IN`、
   `USED_IN_SYNTHESIS`、`USED_IN_IMPLEMENTATION`、`IS_ENABLED`、`IS_GENERATED`、
   `PROCESSING_ORDER`、`SCOPED_TO_REF`、`SCOPED_TO_CELLS`、`FILE_TYPE`、`FILESET_NAME`。）
3. **作用域要显式。** `SCOPED_TO_REF`/`SCOPED_TO_CELLS` 为空就是全局约束。给某个 IP 内部引脚写的约束
   留在全局作用域，展开成空集合→ 回到 §2 的命中数判据；反过来把只想作用一处的约束写成全局，
   会连带命中同名网络。
4. **生成物不要手改。** Block Design 带出来的 `.xdc` 有 `IS_GENERATED` 属性（自己 `add_files`
   进去的是 `0`），重新生成时会被覆盖。要在它之后改口的做法是另加一份自己的文件并设
   `set_property PROCESSING_ORDER LATE [get_files my.xdc]`，而不是编辑生成物。
5. **多变体不要靠注释切换引脚。** 两块板 = 两份 `board_*.xdc`，同一时刻只让一份在表里
   （用第 2 条的开关关掉另一份）。表里同时躺着两份 `PACKAGE_PIN` 就等于等着被后写的那份覆盖。
   可机器判的口径：`get_files -compile_order constraints -used_in synthesis` 返回的那条列表里
   **只应该出现一份**板侧文件；换板时改的是"哪一份开着"，不是文件内容。
   也别想在 XDC 里用 `if` 选板——**受管理的约束文件不收控制流**，实测：

   ```
   CRITICAL WARNING: [Designutils 20-1307] Command 'if' is not supported in the xdc constraint file.
                     [.../cond.xdc:1]
   ```

   而同一句 `catch {read_xdc cond.xdc}` 的返回值照样是那个文件名，**不是错误**——所以 try/catch、
   退出码、"命令没红"都看不出这件事，只有日志里那条 CRITICAL WARNING 能看出来（§2 的老规则：
   数告警条目本身）。要控制流就把它放到工程外的 tcl 里：`read_xdc -unmanaged <文件>`
   （本机 `-help` 的语法行是 `[-cells] [-ref] [-quiet_diff_pairs] [-mode] [-unmanaged] [-no_add]
   [-quiet] [-verbose] <files>`，同一份带 `if` 的文件这样读入就不再打 20-1307）；
   或者挂到 `STEPS.<STEP>.TCL.POST` 上——那个钩子收的是**脚本文件路径**，不是内联 Tcl
   （`vivado-build-run.md` §5）。
6. **XDC 救不了 RTL。** 豁免类命令（`set_false_path`、`set_clock_groups -asynchronous`、
   `set_disable_timing`、`set_case_analysis`）减少的是**被检查的路径数量**，不改变硬件行为。
   加之前先取基线读数：

   ```tcl
   report_clock_interaction   ;# 每对时钟当前是怎么处理的
   report_exceptions          ;# 被豁免/被多周期覆盖的路径清单
   ```

   `set_clock_groups -asynchronous` 写宽了（把整片设计的钟一股脑分组）之后时序报告必然好看，因为
   跨组路径整批不再检查。这类"改善"没有对应的物理机制，不能写成已修好。一条豁免的正当依据是
   **设计上确实异步**（两个钟没有共同来源、且没有硬件同步机制），不是"这条路径 WNS 是负的"。
7. 每加一条豁免就记下它豁免了多少条路径（`report_exceptions` 的前后差），与 §3 的"放宽范围写进
   改动记录"是同一条要求的两个入口。

## 9. 时序例外三件套：各自消掉什么，以及"没消到东西"长什么样

三条都会让报告变好看，消掉的东西不一样。共同点是**它们都登记在同一张可查的表里**——
所以"加了例外但什么都没管到"这件事有读数，不必靠猜。

```tcl
set_multicycle_path -setup 2 -from [get_clocks slow_clk] -to [get_clocks fast_clk]
set_multicycle_path -hold  1 -from [get_clocks slow_clk] -to [get_clocks fast_clk]
set_case_analysis 0 [get_ports rst_n]
report_exceptions              ;# 每条例外一行，看 Status 列
report_clock_interaction       ;# 每对钟怎么被处理
```

实测读数（本机 2025.2.1，`fast_clk` 10 ns / `slow_clk` 40 ns，数据只从 fast 流向 slow，
上面那两条 MCP 因此方向写反了）：

```
Position  From                   Through  To                     Setup     Hold     Status
7         [get_clocks slow_clk]  *        [get_clocks fast_clk]  cycles=2  -        Non-existent path
8         [get_clocks slow_clk]  *        [get_clocks fast_clk]  -         cycles=1 Non-existent path
```

- **判据是"我那条在不在表里 + 它管的那条路径活着没有"，不是 `Status` 那一列的字。**
  本机对"死例外"观测到**两种**形态，且与你怎么写对象有关：
  - 用**时钟名**给 `-from/-to`、方向写反（那两个钟都存在、但这个方向没路径）→ 印 `Non-existent path`
    （上面那个例子就是这种）；
  - 用**针/单元**给而不存在的路径（例如指到反向的那对寄存器）→ 整行**不出现**，或出现了但 `Status`
    是空白；`-ignored` 那张表里也没有（本机一次 `-ignored` 输出 67 字符，两条死例外一条都不在）。
  反过来，**活着的例外 `Status` 是空白**。所以按 `Status` 的字样判"生效没有"两头都会错：
  空白既可能是"活着"也可能是"没被列出来"，`Non-existent path` 不是必然出现。
  比这张表硬的是**这条约束所覆盖的那条路径的 `Requirement`/`Slack`**（取法见 §4 的
  `report_timing -from … -to …`）——但**三种约束留下的痕迹不一样，别用一种读法套全部**：
  多周期会把 `Requirement` 真的挪走（本机 10.000 → 20.000，见本节末那张三行表），
  `set_false_path` 则让这条路径**从报告里整个消失**（读不到 `Requirement` 不等于"没生效"，
  也不等于"路径不存在"——要靠加约束前后各取一次同一对 `-from/-to` 来分开（两次都必须用
  `-return_string` 或 `-file` 取文本，§4 第 4、5 条：普通调用的返回串是空的）。
  默认表（`report_exceptions`）只列"应用到 setup/hold 检查上的例外"（`-help` 原话）；
  `-ignored` 是合法选项但 **`-help` 里不列它**。一条例外都没有时印 `No valid timing exceptions found.`。
  `Position` 编号随设计已有例外数量变，按 `From`/`To` 的时钟名认自己那条。
  没有 `-summarize` 这个选项（`[Common 17-170] Unknown option`）。
- 多周期是 **setup 与 hold 两笔**，但**不是"先只有一行"**：本机只给
  `set_multicycle_path -setup 2 -from … -to …`（没有写 `-hold`）之后，默认表里就已经是**两行**——
  `Setup cycles=2` 与 `Hold cycles=0`。也就是说 hold 那一笔是工具跟着 setup 自己推的默认值，
  不是留在 1；要改它必须再显式 `set_multicycle_path -hold M`（本机补了 `-hold 1` 之后第二行
  变成 `cycles=1`）。判"hold 到底停在几"就读这一列，别按"我只写了一笔所以只改了一半"去猜。
- `set_case_analysis` 宣布"这个脚恒为某个值"，于是以它为起点的路径不再分析。它改的只有分析：
  外部真会动的脚被这么钉住，就把错误藏起来了。用之前先说清"这个脚在系统里真的不会动"依据是什么。
- 多钟设计的默认行为有原文，逐字是（本机，一句话到句号结束，中间用 "or" 不是斜杠）：

  ```
  WARNING: [Timing 38-164] This design has multiple clocks. Inter clock paths are considered valid unless explicitly excluded by timing constraints such as set_clock_groups or set_false_path.
  ```

  ——**跨钟路径默认被当成合法同步路径计时**。注意打它的时机：实测是 `report_timing`（跨钟方向）与
  `report_clock_interaction` 会打，`synth_design` 与 `report_timing_summary` 一次都没打——
  所以"没看到这句"不代表只有一个钟。
- `report_clock_interaction` 是**按有向时钟对**一行（两个钟 = 四行，`A→A`、`B→B`、`A→B`、`B→A`）。
  表头是**两行**的：上一行给分组名（本机是 `Clock Interaction`、`Constraint Type`），
  下一行才是字段名（`Path Classification`、`Inter-Clock Constraints`）——按其中一个词去找另一列，
  会以为它不存在。要读的两列是"这一对钟被怎么归类"（本机见过 `Clean`、`No Common Clock`）与
  "被怎么处理"（本机见过 `Timed`、`Timed (unsafe)`、`Ignored`、`False Path`、
  `Asynchronous Groups`）。**`-return_string` 会把表头丢掉**，只剩数据行，所以脚本里按列号取。
  豁免只改它自己那一向的行。本机两向都有真路径时的三组读数：

  | 加了什么 | `slow→fast` 那行 | `fast→slow` 那行 |
  |---|---|---|
  | 只有两个 `create_clock` | `No Common Clock` + `Timed (unsafe)` | `No Common Clock` + `Timed (unsafe)` |
  | `set_false_path -from slow -to fast` | `Ignored` + `False Path` | 仍然 `Timed (unsafe)` |
  | `set_clock_groups -asynchronous -group … -group …` | `Ignored` + `Asynchronous Groups` | `Ignored` + `Asynchronous Groups` |

  这就是 §3 说的"豁免铺宽"在报告里的样子：**只写一个方向的 `false_path`，把带数据的那个方向留在
  unsafe 里**；反过来 `clock_groups` 一次铺两组，两侧一起不检查。两种都要看这张表才知道落到哪。
- **三种约束在 `Requirement` 上留下的痕迹不一样，本机在同一份双钟设计上取过对照数**
  （**另一份**设计，`slow` 40 ns / `fast` 10 ns，数据从 slow 流向 fast，路径
  `s_r_reg[0]/C → f_r_reg[0]/D`，综合后 `report_timing -from/-to`
  这一对寄存器各 8 个都取到）。**别把这张表与上面那条"方向写反 → `Non-existent path`"混起来**：
  那一次的设计里数据只走 fast→slow，所以给 `slow→fast` 写的多周期管不到任何东西、表里印
  `Non-existent path`；本份设计里同一个方向是**有真路径的**，所以三行读数都有意义。
  两处的共同教训是：**先确认你要豁免/放宽的那个方向上真有路径**，再谈例外有没有落地——
  而"有没有路径"这件事只能用 `report_timing -from/-to` 的文本证明（§4 第 4、5 条的捕获写法）。

  | 加了什么 | 那对 `-from/-to` 的报告 | `Requirement` | `Slack` |
  |---|---|---|---|
  | 只有两个 `create_clock` | 有一条路径 | `10.000ns (fast rise@10.000ns - slow rise@0.000ns)` | `8.563ns` |
  | `set_false_path -from slow -to fast` | **整条路径没有了**（连 `Slack`/`Requirement` 两行都不印） | 读不到 | 读不到 |
  | `set_multicycle_path 2 -setup -from slow -to fast` | 有一条路径 | `20.000ns (fast rise@20.000ns - slow rise@0.000ns)` | `18.563ns` |

  三件事要从这里分开读：**false path 不是"把 Requirement 改成另一个数"，是把这条路径从分析里拿走**，
  所以它的判据是"加约束前后各取一次同一对 `-from/-to`，前者有读数、后者没有"——这正是 §4 第 4 条
  那条"报告里没有 ≠ 路径不存在"的**唯一能区分两者的写法**（不加前一次读数，"没了"这两种成因分不开）。
  **多周期则在 `Requirement` 上看得见**（10 → 20，`Slack` 同步 +10 ns = 一个 `fast` 周期），
  这组数**推翻了本页先前的一处说法**（"多周期之后 `Requirement` 一动不动"，以及
  "`11.429 → 38.571` 这一对数是 false path 造成的"——那一对来自另一次有界约束的读数，
  38.571 也不等于 slow 侧一个周期 40.000）。
  还有一条判据是**不能用的**：`INFO: [Timing 38-519]`——本机在普通 `report_timing` 里也见过它，
  出现与否不区分豁免有没有落地。
  把它改成有界约束或显式豁免，是一次要记录的设计决定（§3），不是自动收益。
- 缺了 `-clock` 的 IO 延迟、只写 `-max` 没写 `-min` 的半边约束，都会在 `check_timing` 里留数字：
  本机同一份设计给出 `5. checking no_input_delay (1)` 与 `10. checking partial_input_delay (1)`。
  括号里的数就是还欠多少（§7 第 6 条的另一半读法）。

## 10. 方法学与 DRC 报告：抓"全绿但没被检查"那一类

WNS 好看只说明**被检查的那些路径**满足要求。`report_methodology` / `report_drc` 抓的是另一类：
逻辑存在但根本没进时钟模型、约束指向空集、结构可疑。本机实测 `report_methodology`
（综合后，一个**没写任何时钟约束**的设计）的 SUMMARY 形状：

```
             Netlist: rsttop
           Floorplan: design_1
       Design limits: <entire design considered>
              Max checks: <unlimited>
              Checks found: 8
+-----------+------------------+-----------------------------+--------+
| Rule      | Severity         | Description                 | Checks |
| TIMING-17 | Critical Warning | Non-clocked sequential cell | 8      |
```

读法与判据：

1. **按 `Severity` 分组数条数**，不是"有没有红"。上面这就是教科书式的"全绿但没检查"：
   综合成功、时序报告也好看，而有一批寄存器**根本没进时钟模型**——对应 §1 要求先把钟出名。
   **但 `Checks found: 8` 数的是"检查条数"，不是"寄存器个数"**：这一族（TIMING-17
   `Non-clocked sequential cell`）通常一条对一个 cell，本机那份设计也正是 8 条对 8 个不同对象，
   所以数值相等；**这个相等不是命令保证的**（一条规则对一个对象出多条检查在别的规则里就有）。
   要写进判据就去数报告明细里 TIMING-17 那几行的**对象列去重**，别拿 SUMMARY 的 `Checks` 当 cell 数。
   `Critical Warning` 不为 0 时，每条都要落进改动记录，写明"这条我不处理的理由"。
2. **条目名是缩写，不含 "reset"/"clock" 这种完整单词**（本机见过的有 `TIMING-17`、`RTSTAT-1`、
   `REQP-1`、`AR-1`）。用关键词 grep 报告来判"它查没查 X"一定出错：先把 `Rule` 整列打出来，
   再对着该版本的规则说明看，不要望文生义。
3. `report_drc` 也能跑，但 `-return_string` 拿到的**第一行是版权头**，表头和数据在后面；
   写解析时按表头字符串定位，别假设第一行是数据。
4. **`report_methodology` 不是任何阶段都能跑。** 本机在"当前内存里 link 着的设计"上跑得通
   （上面那个 SUMMARY 就是那么来的），而在**打开一个综合 dcp 之后再跑**得到的是
   `ERROR: [Common 17-53] User Exception: Methodology could not be found in the design.`
   同一份网表、换个打开方式就没数据。所以拿它当门之前，先确认它这一次真的产出了表：
   判据是输出里那行 `Rules Checked:` 或 `Checks found:` 在不在，不是命令有没有被调用。
5. **阶段要钉住**：综合后的条目集合与布局布线后不是同一批，报告要与那一次 run 同源落档
   （§4 第 1 条、§5）。做成 run 的一部分（`STEPS.<STEP>.TCL.POST` 指向一个脚本文件，
   见 `vivado-build-run.md` §5）比事后手点可信。

## 11. 不确定度与抖动：参数对象给错时工具不都拦

`set_clock_uncertainty`、`set_input_jitter`、`set_system_jitter`、`set_propagated_clock` 这四条
在本机都存在，但**参数对象与写法有讲究**，逐条是实测的：

| 写法 | 本机结果 |
|---|---|
| `set_clock_uncertainty 0.5 [get_clocks fast]` | 收下 |
| `set_clock_uncertainty -hold 0.2 [get_clocks fast]` | 收下（setup 与 hold 分开给） |
| `set_clock_uncertainty -setup 1.25 -hold 0.3 [get_clocks slow]` | **报错** `[Common 17-165] Too many positional options when parsing 'slow'`——两个方向想一起给就别指望它 |
| `set_clock_uncertainty -low 0.4 …` | `Unknown option '-low'`（没有这种方向名） |
| `set_input_jitter 0.3 [get_clocks fast]` | **报错** `[Common 17-161] Invalid option value 'fast' specified for 'input_jitter'`——**这条不是"它不接受时钟对象"，是本页原先把参数顺序写反了**：`-help` 的语法行是 `set_input_jitter [-quiet] [-verbose] <clock> <input_jitter>`，**时钟在前、数值在后** |
| `set_input_jitter [get_clocks fast] 0.3` | **返回 0**（按 `-help` 的顺序重取）——所以这一族的写法判据是 `-help` 的语法行，不是某一次报错的措辞 |
| `set_input_jitter -setup 0.2 [get_clocks fast]` | `Unknown option '-setup'`（`[Common 17-170]`）：它没有方向开关，与 `set_clock_uncertainty` 的 `-setup/-hold` 不一样 |
| `set_system_jitter 0.1` | 收下（全局，不带对象） |
| `set_propagated_clock [get_clocks fast]` | 综合后也收下，**但收下不等于按传播算** |
| `set_clock_uncertainty 0.5 [get_pins <某个寄存器的 C 脚>]` | **返回 0、不报错**——对象类型错了它也不拦（本机取的是 `q_r_reg[0]/C`） |
| `set_clock_uncertainty 0.5 [get_pins <不存在的名字>]` | **报错** `[Vivado 12-4739] set_clock_uncertainty:No valid object(s) found for '-objects …'`，后面跟一整段 `Resolution:`——对象集合为空它拦，对象类型错它不拦 |

**写这一族命令时 `[0]` 是 Tcl 的地雷**：`[get_pins q_r_reg[0]/C]` 这种**不加花括号**的写法，
解释器会先去看 `0` 是什么命令。本机就是被它掀掉过一次会话（那一轮剩下的十几条读数全没打印）。
要么 `[get_pins {q_r_reg[0]/C}]`，要么先把名字放进变量再传——放进变量这条还顺便能让 `llength`
先判"取到了几个对象"，正是上面最后一行的判据。

所以判"设上了没有"不看返回码，看 `report_clocks`：

```
Clock     Period(ns)  Waveform(ns)  Attributes  Sources
fast      10.000      {0.000 5.000} P           {clk}
...
fast      fast        0.500      0.200     rf -> rf        ;# 这一对钟的 setup / hold 不确定度
```

两个读数：`Attributes` 里出现 **`P`** 才是已传播（该报告的图例就是 `P: Propagated`；
综合阶段传播通常还没生效，别把"命令收了"读成"在按传播算"）；下面那行的两个数字才是这一对钟
被扣掉的 setup/hold 不确定度。**给错对象类型的那条（`[get_pins …]` 指到寄存器脚）在这两处都不留痕迹**，
所以"命令收了 + 表里没变"就是它给你过的全部信号；真正会当场报错的只有**对象集合为空**那一种
（上面最后的 `12-4739`）。这两者的差别就是"为什么要自己数 `llength` 而不是听返回码"。

**`Requirement` 会不会被不确定度扣掉，取决于端点取法。** 本机的读数是：**不会**——四种取法、九条
setup `Requirement` 读数全部停在 `10.000ns`，动的只有报告里的 `Clock Uncertainty:` 那一段。
（曾经有一处流传的说法是"`set_clock_uncertainty 0.5` 会把 `Requirement` 从 `10.000ns` 扣成 `9.500ns`、
再 `-setup 0.5` 扣成 `9.000ns`，hold 侧从 `0.800ns` 拉到 `0.300ns`"——**这一族数字在本机任何取法下都没有
出现过，不要引用**；同一条里"用 `report_timing -min` 去读 hold"的写法本身就不存在，见 §7 第 6 条。）

取法与读数：一份单钟设计（`create_clock -period 10` 打在端口上，
`set_clock_uncertainty 0.5 [get_clocks fast]`）用 `report_timing -setup -file` 取三次，
最差路径 `Requirement` 都是 `10.000ns`，只有 `Clock Uncertainty:` 那一段（含 `Total Input Jitter (TIJ)` 等分项）在变。
**同一台机器上后来又取了一遍，这一遍是布线完成的设计、四种写法各种一次**
（不带方向 `0.5`、`-setup 0.7`、`-hold 0.3`、再叠 `set_propagated_clock`）：
`Requirement` 四次**全都是 `10.000ns`**，动的只有 `Clock Uncertainty:` 那一段
（`0.035 → 0.535 → 0.735`，加了 propagated 之后仍是 `0.735`）；
`report_timing -delay_type min` 那一侧的 `Requirement` 是 `0.000ns`，也没被 `-hold 0.3` 拉负。
再一份**综合后、未布局**的单钟设计（`create_clock -period 10` 打在端口 `clk` 上、
一个 8 位计数器），默认报告读到 `Requirement: 10.000ns  (clk rise@10.000ns - clk rise@0.000ns)` 与
`Clock Uncertainty:      0.035ns  ((TSJ^2 + TIJ^2)^1/2 + DJ) / 2 + PE`、`Slack (MET) : 7.524ns`；
`set_clock_uncertainty 0.5 [get_clocks clk]`（rc=0）之后**同一条 `Requirement` 还是 `10.000ns`**，
变的是那一段：`0.035ns → 0.535ns`，并且多出一行 `User Uncertainty         (UU):    0.500ns`，
`Slack` 从 `7.524ns` 变成 `7.024ns`（报告串长 `4843 → 4894`，多出来的就是 `UU` 那一行）。
**判这一格要用数值，不能用"报告里有没有 `Clock Uncertainty:` 那一段"**——没设不确定度时那段本来也在
（`0.035ns` 就是工具默认模型给的），"有这一段"前后都为真，永远不红，正是 `SKILL.md` §1 那条
"判据必须能红"要排除的写法；要前后各取一次**全文并比数值**。
min 侧同一份设计：设之前 `Requirement: 0.000ns  (clk rise@0.000ns - clk rise@0.000ns)`、
`Slack (MET) : 0.140ns`，且**这一段整个不存在**（`0.035` 那个默认值只加在 max 侧）；
`set_clock_uncertainty 0.5`（不带方向）之后 `Requirement` 仍是 `0.000ns`，但这段出现了
（`0.500ns`，同样带 `UU: 0.500ns`）而 `Slack` 变成 **`Slack (VIOLATED) : -0.360ns`**。
**所以"hold 需求默认是 0"读成"hold 这一侧不会被不确定度打红"是错的**：不带方向的那条命令两侧都加，
`Requirement` 那一栏一个字不改，红的是 `Slack`。
**所以这一节里能点名的 setup `Requirement` 读数一共 11 条，分布在五次会话里**：那三份 `-file` 报告 3 条、
另一路独立复核 1 条、布线完成设计的四种写法各 1 条（共 4）、更早那份综合后设计（钟名 `c`）1 条、
这份综合后设计（钟名 `clk`，上面逐值抄的就是它）前后各 1 条（共 2）。
**加起来没有一条被扣下来**；另有一路独立复核在同一形状的网表上自己重跑了一遍前后两读，
拿到的也是 `0.035 → 0.535`、`Slack 7.524 → 7.024`（连报告串长 `4843 → 4894` 都一致），
这一路不计进条数，只当"不是某一次会话的偶然"的旁证。
留在这一节的规矩因此是三条可执行的：

- 先看 `Clock Uncertainty:` 那一段（那里是确定度的**记账处**），再看 `Requirement`；
- 比的是那一段里的**数值**，不是"有没有这一段"（默认值 `0.035ns` 让"有这段"前后都为真），
  也不是那一段的**存在与否**——min 侧唯一会变的存在性就是"设过不带方向的 `0.5` 之后它才出现"；
- 要在自己的设计上确认"`Requirement` 有没有被它扣掉"，就用同一对 `-from/-to`
  取**加约束前 / 加约束后**两个文本（§4 第 4、5 条的捕获写法）。两处不一致时先怀疑端点取法，
  但**别把"我怀疑工具没生效"写成结论**——就是那个"怀疑"没被排除的一方。

什么时候该手动给不确定度：只有当你手上有**钟源的真实抖动数据**（晶振 datasheet 的 period jitter、
时钟芯片的输出 jitter、MMCM 的实测贡献）时才给，并且把它按来源记进改动记录——
按报告的口径它记的是检查预算里的一个扣项（具体扣在哪一格见上一段：只确认了
`Clock Uncertainty:` 那一段在变），把 `set_clock_uncertainty` 调大调小**不改变任何硬件行为**，
它是分析预算，不是时序收敛的旋钮。反过来，"WNS 太紧所以给不确定度设成 0"就是把 §8 第 6 条
那种"消掉检查"换个名字做；跨钟的那一侧该走 §3 的有界约束或 §9 的显式豁免。
派生钟（MMCM/PLL 之后）的工具默认模型通常已经含 jitter 估计，先按 §1 取一次 `report_clocks`
读数再决定要不要覆盖它。


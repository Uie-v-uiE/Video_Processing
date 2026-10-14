# 构建与运行：run 模型、策略、可重复产物

覆盖"从 RTL 到比特流这段机器活怎么开、怎么让它自己交出证据"。
约束本身在 `constraints-timing.md`；工程与 BD 结构在 `vivado-project-bd.md`；
在飞构建与产物竞态在 `board-bringup.md` §5。

## 1. run 是对象，不是一条命令的历史

```tcl
# A. 纯 RTL 工程
create_project -force build ./prj/build -part <你的 part>
add_files  [glob src/rtl/*.v]
add_files -fileset constrs_1 ./constraint/top.xdc
set_property TOP eth_udp_video_top [current_fileset]
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
get_property STATUS  [get_runs impl_1]
```

BD 工程在 `launch_runs` 之前要多一步——**BD 本身不是综合的输入，综合读的是文件集里的源**：

```tcl
set w [make_wrapper -files [get_files top.bd] -top]   ;# 成功时打回 wrapper 文件路径
file exists $w                                        ;# BD 没连全时这里回 0，$w 里是错误链
add_files $w                                          ;# 用它返回的那个路径，不要按 *.gen/… 手拼
set_property TOP top_wrapper [current_fileset]
```

手拼那个路径是本页另一条规矩的反例（run 目录与生成文件路径一律**现取**，见 §5 末条；
`make_wrapper` 的选项与位置参数怎么给，规范写法在 `vivado-project-bd.md` §2）。
`set_property TOP` 那一行写完要回读一次：`get_property TOP [current_fileset]` 必须把你给的那个名字
原样打回来；wrapper 的模块名是工具按 BD 名生成的，**不是你以为的那个**——这一条与 §1 规则清单里
那条"只有 BD、没有 wrapper 的工程跑不出比特流"合起来，才是"BD 工程能综合"的判据，
单看 `set_property` 返回 0 不算。

规则：

- **只有 BD、没有 wrapper 的工程跑不出比特流。** 加了 `create_bd_design` 就直接
  `launch_runs`，失败点通常在综合"找不到顶层"或者出来一个空壳。判据是这次真正参与编译的源清单：
  `get_files -compile_order sources -used_in synthesis`（机器可读形式；这一对选项的用法与取值
  写错时的报错见 `constraints-timing.md` §8），wrapper 在里面才算这一步成立。
- **`launch_runs` 之后要 `wait_on_run` 再读 `STATUS`。** 只看 `launch_runs` 返回成功没有意义：
  它只是把任务发出去。`STATUS` 是**字符串**，而且本机 2025.2.1 观测到**两类形态**，不要按一种去套：
  单步形态 `<步骤名> <状态>`（`synth_design Complete!`、`synth_design ERROR`）与
  整个 run 的状态词（`Not started`、`Scripts Generated`、`Out-of-date`、`Suspended`、`Completed`、
  `Synth Design complete`）。所以判"这次到底成没成"要读**最后那一步**对应的那条，
  并把这一串值原样抄进记录；产物文件的时间戳是第二道读数（比较对象：它要晚于你最后一次
  `launch_runs`，不是"看起来是新的"）。
- **`get_property <不在清单里的属性名> <对象>` 不报错。** 本机实测：`get_property PROBES_FILE
  [get_runs impl_1]` 与一个瞎写的名字返回**同样**的 `WARNING: [Common 17-673]` 加空值，而
  `list_property [get_runs impl_1]` 里根本没有这一项。所以"读回来是空"永远不能单独当结论——
  先用 `list_property <对象>` 确认属性名在清单里，再谈它等于什么。
  判"这一版有没有调试核"用的是 `.ltx` 与 `get_hw_ilas`，见 `onchip-debug.md` §3。
- **不要用 GUI 里点出来的设置当基线。** GUI 的选项落在工程文件里，看不见就等于"没设"。
  要可重复就把它们写成 `set_property`（下一条），并在记录里留这份 tcl。
- 策略与单步选项都是 run 对象的属性，用 `get_property` 读回来，不要凭记忆描述：

```tcl
set_property STRATEGY Performance_Explore        [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
get_property STRATEGY [get_runs impl_1]          ;# 读回来确认这次到底是哪个
```

## 2. 策略名与 directive 名要在你这版里查，不要抄

工具会随版本增删策略。**取当前版本真实可选值**：

```tcl
list_property_value STRATEGY [get_runs impl_1]
list_property_value STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]
```

（本机 2025.2.1 的实测输出里有 `Performance_Explore`、`Performance_NetDelay_high`、
`Performance_Retiming`、`Area_Explore`、`Congestion_SpreadLogic_high`、`Flow_Quick`、
`Vivado Implementation Defaults` 等；综合侧有 `Flow_PerfOptimized_high`、`Flow_AreaOptimized_high`、
`Flow_RuntimeOptimized`。换版本先重跑这两条，不要沿用这里的名字。）

规则：

- **一次只动一个变量**：换策略与改约束与改 RTL 不要混在同一次跑里，否则"变好了"无法归因。
- 策略换完要 `reset_runs` 再 `launch_runs`，并且**留下两次跑的报告**再比较；
  只比 WNS 一个数不叫比较（阶段与口径见 `constraints-timing.md` §4）。

## 3. 步骤属性一览：策略、directive、钩子位、报告位

每个步骤都有钩子与报告位（这些属性名在本机 2025.2.1 实测存在）：

| 属性 | 用途 |
|---|---|
| `STEPS.<STEP>.TCL.POST` | 该步骤结束后要执行的**脚本文件路径**（不是内联 Tcl，见 §5）——用它把 `report_timing_summary`、`report_methodology`、`report_utilization` 落成文件 |
| `STEPS.<STEP>.REPORTS` | 该步骤默认要生成的报告集 |
| `STEPS.<STEP>.IS_ENABLED` | 这步跑不跑（如 `PHYS_OPT_DESIGN`、`POWER_OPT_DESIGN`） |
| `STEPS.<STEP>.ARGS.DIRECTIVE` | 该步的 directive（值用 §2 的 `list_property_value` 查） |
| `STEPS.<STEP>.ARGS.MORE OPTIONS` | 追加原始参数；**用了它就要在记录里写用了什么**，否则复现时少条件。属性名含空格，整条要写成 `{…}`；值也有坑：本机 `set_property {STEPS.PLACE_DESIGN.ARGS.MORE OPTIONS} {-g x}` 报 `Unknown option '-g x'`，改成带前导空格的 `{ -g x}` 或嵌套大括号 `{{-g x}}` 才收下并能读回 |
| `STEPS.INIT_DESIGN.TCL.PRE` | 读入设计前挂钩（例如生成派生约束文件） |

`<STEP>` 不要背，从属性名里现取（本机 2025.2.1 的 `impl_1` 数出 9 个）：

```tcl
lsort -unique [regexp -all -inline {STEPS\.[A-Z0-9_]+\.} [join [list_property [get_runs impl_1]] \n]]
```

实测那 9 个是 `INIT_DESIGN`、`OPT_DESIGN`、`POWER_OPT_DESIGN`、`PLACE_DESIGN`、
`POST_PLACE_POWER_OPT_DESIGN`、`PHYS_OPT_DESIGN`、`ROUTE_DESIGN`、`POST_ROUTE_PHYS_OPT_DESIGN`、
`WRITE_BITSTREAM`——注意有"布线后的 phys opt"而没有"布线后 power opt"这一档，
换版本或换 flow 都要重跑上面那条。directive 的可选值同样现取，实测确有返回：

```tcl
list_property_value STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]
;# 本机含 Explore、WLDrivenBlockPlacement、ExtraNetDelay_high、AltSpreadLogic_*、RuntimeOptimized…
list_property_value STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]
;# 本机含 Explore、NoTimingRelaxation、MoreGlobalIterations、Quick、RQS、AggressiveExplore…
```

规则：**"时序收敛"这类结论必须由 run 自己生成的报告支撑**，不能由事后手点的一次
`report_timing_summary` 支撑——后者可能来自另一个 run、另一个策略、甚至改约束之前。
报告里自带命令回显行与 `Design State`（表头那一行排版是 `| Command      :`，对齐空格使
`grep "Command:"` 打不中；这两个字段怎么读在 `constraints-timing.md` §7 第 6 条，
阶段归属看同页 §4 第 1 条），run 目录的 `runme.log`
同样按 `Command` 那一行记着**这一步真正执行的参数**——想知道"那一次跑的到底是哪个 directive"，
读的是这份日志，不是你现在 `get_property` 回来的设置（属性是当下值，会跟着你改）。

## 4. 可重复性：四件必须钉住的事

1. **part 写全名**（含封装与速度等级），换 part 是另一件事，不是换个字。
2. **IP 的 VLNV 与参数**：钉法见 `vivado-project-bd.md` §2 第 3 条（`report_ip_status` 那一族），
   参数快照的取法在同页 §3 末条；改参数是一次变更，不要混在同一次构建里。
3. **驱动构建的那份 tcl 进版本库**，GUI 里点的设置一律用 `set_property` 重写一遍；
   `write_project_xpr` 这版**没有**这条命令——否定证据的原文是
   `invalid command name "write_project_xpr"`，而且**加不加 `load_features` 都一样**；
   `info commands` 那一路单独不足为凭（它对确实存在的命令也回空，见 `SKILL.md` 的"用法"）。
   需要工程快照就用 `get_property` 把关键属性打成一份文本。
4. **产物与来源同目录**：`.bit`/`.xsa`/约束快照/报告放同一个带时间戳的目录，
   记录里写哈希。哈希只回答"文件换没换"，不回答"板上跑的是不是它"（后者见 `board-bringup.md` §1）。

## 5. run 自己交证据：钩子的值是一段脚本文件的路径，不是内联 Tcl

这条最容易踩，因为**设的时候不报错**。实测（2025.2.1）把一段内联 Tcl 交给 `TCL.POST`：

```tcl
set_property STEPS.SYNTH_DESIGN.TCL.POST {report_timing_summary -file t.rpt} [get_runs synth_1]
;# set_property 本身返回成功，只留下两条 WARNING：
;#   [Runs 36-525] Unable to set the post hook file '...' for run step Synth
;#   [Runs 36-540] Run directory synth_1 does not exist. Can not find Tcl hook script file '...'
launch_runs synth_1
;# ERROR: [Project 1-1965] Hook script file <把那串 Tcl 当文件名拼出来的路径> ...
```

工具把属性值当**脚本文件名**去找（本机在 run 目录还没建出来时就是上面那条 `36-540`），
而钩子**执行时**的工作目录是那个 run 目录——这两件事不同层：属性值怎么解析由工具定，
钩子内部写的相对名落在 run 目录。**但属性值里的相对路径是按 run 目录解析的，不是按工程目录**，
为此撞到过一次硬失败：

```tcl
set_property STEPS.ROUTE_DESIGN.TCL.POST ./tcl/post_route.tcl [get_runs impl_1]
launch_runs impl_1 -to_step route_design -jobs 4
;# ERROR: [Project 1-1965] Hook script file <工程>/q2/q2.runs/impl_1/tcl/post_route.tcl
;#        used in Run: impl_1 and Step: Route Design does not exist     ← 拼在 run 目录上找的
;# 之后 STATUS 冻在 `Scripts Generated`、runme.log 根本没有、什么也没跑；
;#   综合那一步（`STEPS.SYNTH_DESIGN.TCL.POST`）另有复核报过同一条 1-1965，本包只复现了 route 这一臂
```

正确写法是给一个真的、入库的脚本文件，并把**绝对路径**交给属性：

```tcl
# <工程>/tcl/post_route.tcl —— 这份内容本身要进版本库，属性只给路径
puts "HOOK_ROUTE_DONE"                                  ;# 判据用的标记行
report_timing_summary -file hook_timing.rpt             ;# 相对名 => 落在 run 目录里
```

```tcl
# 建工程之后：给绝对路径，别给 ./tcl/…
set_property STEPS.ROUTE_DESIGN.TCL.POST [file normalize ./tcl/post_route.tcl] [get_runs impl_1]
```

换成绝对路径之后本机这一臂的读数：`launch_runs` rc=0、`STATUS` 走到 `route_design Complete!`、
run 目录里出现 `hook_timing.rpt`；钩子里额外追加写了一行 `pwd=` 到 `hook_marker.txt`，
那行打出来正是 `…/q2/q2.runs/impl_1`——**"钩子执行时的工作目录 = run 目录"与
"属性值按 run 目录解析"是同一件事的两面**，所以钩子想引用工程里的别的东西，得把绝对路径自己带进去
（放在 run 目录里、或再传一个属性）。
**注意这一步的默认报告不一定同处**：综合那份叫 `top_utilization_synth.rpt` 且落在**综合 run** 的目录里，
把它当"实现那一步的兄弟文件"看是错的归属。

判据不是"`set_property` 过了"，也不是"`STATUS` 说这一步完成了"。要成立的是**两条**：
① 钩子确实在**你指定的那一步**跑过——run 目录里出现 `hook_timing.rpt`，且 `runme.log` 里有
`HOOK_ROUTE_DONE` 这一行；② **那份报告说的是实现之后的设计**——打开它读表头的
`| Command      :`（本机数过：它在第 6 行，且 `Command` 与冒号之间有一串对齐空格，
按 `Command:` 整串去 grep 打不中）与正文的 `Design State`（字段怎么读在 `constraints-timing.md` §7 第 6 条，阶段归属在同页 §4 第 1 条）。
只满足 ① 是不够的：钩子挂在 `SYNTH_DESIGN` 上同样打印标记行、同样产出 `hook_timing.rpt`，
而那份报告是 `Design State : Synthesized` 的推测值——正是 `SKILL.md` §1 第 3 条不许拿去签字的那种数字。
`STATUS` 完成与钩子跑没跑、跑在哪一步，是三件事。

run 目录的路径现取，不要手写 `*.runs/<run>/`：`get_property DIRECTORY [get_runs synth_1]`
本机给 `.../prj/pg.runs/synth_1` 这种绝对路径。同一层还有 `GEN_REPORTS_PARALLEL`、
`REPORT_STRATEGY`、`INCREMENTAL_CHECKPOINT.DIRECTIVE`、`AUTO_INCREMENTAL_CHECKPOINT.DIRECTORY`
这些名字（本机 `list_property [get_runs impl_1]` 共 98 项）——属性名会随版本漂，先列再引用。
**但 `list_property` 既不吃空集合、也不吃多对象——它是抛异常不是回空**：本机在 ports/pins/cells/files
上取到的是同一句 `[Common 17-56] 'list_property' expects exactly one object`，尾巴跟着对象数
（`got '0'` / `got '8'`），会把脚本后面所有读数打断。分类按"它抛了 / 它回空"，不按编号——
同一个"问法不对"还有另一个编号（`constraints-timing.md` §2 末段把这两条与 `list_property_value`
回空行为列在一起）。**run 这一族单独撞过了，而且编号是第四个**：在一个只有
`synth_1 impl_1` 的工程里——
`list_property [get_runs -quiet nope_not_here]` → 返回码 **1**、
`[Common 17-58] '' is not a valid first class Tcl object.`（空集合在这里变成"空字符串不是对象"；
**注意这个读数是怎么被探针自己改坏的**：本机第一版把消息 `split` 之后用 `join ","` 打印，于是文本里多出一个不存在的逗号——
**抄日志之前先看它是用什么形状打出来的**）；
`list_property [get_runs -quiet *]`（2 个对象）→ 返回码 **1**；
`list_property [get_runs -quiet synth_1]` → 返回码 **0**、**63** 项（对照 `impl_1` 的 98 项：
**同一命令、两种对象，可读属性数量差很多**，别把一边的清单当另一边的）。
三种形状合起来说：`list_property` 只在"恰好一个对象"时给你属性表，其余都是抛。
所以顺序永远是把 `list_property` 包进 `catch`、先 `llength [get_runs -quiet impl_1]` 判对象在**且只有一个**、再问属性。
本节与 §7 的快照配方都吃这一条。

## 6. 想并行跑两版对比：`create_run` 不接受把第二个实现 run 挂在实现 run 上（要挂在综合 run 上）

`create_run` 存在，本机的语法行是
`create_run [-constrset] [-parent_run] [-part] -flow <arg> [-strategy] [-report_strategy] [-pr_config] [-dfx_mode] [-rm_instance ...]`。
照最自然的想法做——"从 `impl_1` 再开一个 `impl_2`，两个策略同时跑"——本机直接拒绝：

```
ERROR: [Common 17-69] Command failed: Child Implementation run always needs either pr_config or rm_instance
```

`-pr_config`/`-rm_instance` 是部分重配那条路上的参数，普通工程没有它们，`get_runs` 之后还是
`synth_1 impl_1`。**这条错误是有用的读数**：它在告诉你 `-parent_run` 给错了对象。
限制是**按步骤类型**的，不是一刀切：本机建第二个**综合** run 是合法的
（`create_run synth_2 -parent_run synth_1 -flow {Vivado Synthesis 2025}` 直接返回 `synth_2`），
不合法的只有"再挂一个实现 run 到实现 run 上"。所以要 A/B 比较综合策略，
连这个也可以：两个综合 run，各带自己的实现 run。
并行的正确形状是**把第二个实现 run 挂在综合 run 上**（本机实测通过）：

```tcl
create_run impl_2 -parent_run synth_1 -flow {Vivado Implementation 2025} -strategy Performance_ExploreWithRemap
get_runs                              ;# synth_1 impl_1 impl_2
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_2]
get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [get_runs impl_2]   ;# Explore
get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]   ;# Default —— 两个 run 互不影响
launch_runs impl_1 impl_2 -jobs 2 -to_step write_bitstream
```

上面那个策略名**是验证过能用的一版本里的值**（`create_run … -strategy Performance_ExploreWithRemap`
建出 `impl_3`，`get_property STRATEGY` 读回同名），但**别把它当可抄的常数**：
本机 `list_property_value STRATEGY [get_runs impl_1]` 给 **33** 个值，首条
`Vivado Implementation Defaults`、末条 `Flow_Quick`，换工具版本就是换一份清单——取法就是这条命令。

`-flow` 那个字符串同样**不要抄别人的**：本机这一版是 `Vivado Implementation 2025`，带年份。
取自己机器上的值有确定办法（本机实测）：`list_property [get_runs impl_1]` 里**就有 `FLOW` 这一项**，
`get_property FLOW [get_runs impl_1]` 直接回 `Vivado Implementation 2025`，照它写就不会猜
（但 `list_property_value FLOW` 给的是**空清单**，所以这条路只能读现值、不能枚举合法值）。
还有一件撞上的事：**工程模式里 `create_project` + 设好 top 之后，`synth_1`/`impl_1` 已经存在**，
再 `create_run synth_1 …` 得到 `[Common 17-69] A run named 'synth_1' already exists`——
新建对比 run 时用别的名字，不要先删再建。
`launch_runs impl_1 impl_2 -to_step write_bitstream -jobs 2` 本机**真的把两个 run 一起发出去了**
（`-jobs` 在多 run 形式下可用；它的含义见下一条总并行度的成本）。三条配套读数各说一件事：

- **`-jobs` 是总并行度**：两个完整实现同时跑意味着两份内存（本机一次 `synth_design` 峰值约 1.8 GB，
  实现更高），笔记本上 `-jobs 2` 更可能互相拖慢而不是加速。
- **`current_run` 在 `launch_runs` 之后返回 `impl_1`**——并行时"当前 run"只有一个，
  读属性要显式 `[get_runs impl_2]`；两份产物在不同 run 目录，比较时各自取报告（§5 的钩子按 run 生效）。
  **这与 `board-bringup.md` §5 那条"并行跑两个构建要连工程目录都分开"不是同一件事**：那条管的是
  两个工程副本或两个会话同时跑（共享目录会互相覆盖）；同一工程里的两个 run 各有 `.runs/<run>/`，
  共享的是**源文件与 XDC**，所以这一侧的规矩变成"在飞期间别改源"（§5 的竞态同因）。
- **重复启动已在跑的 run 会给清楚的一句**：
  `ERROR: [Common 17-69] Command failed: Runs 'impl_1', 'impl_2' are already running and cannot be relaunched.`
  （`-scripts_only` 撞上同状态也是这句，不是另一句。）

**"不认这个选项"的编号别当检索键**：本机 `launch_runs impl_1 -zzq 2` 报的是
`[Common 17-170] Unknown option '-zzq'`，`set_input_jitter -setup …` 也是 `17-170`；
**本页早前写的那条 `[Common 17-127] Unknown option 'jobs'` 没能复现**：按它当时的条件重跑
（`impl_2` 并不存在），结果不是报"不认这个选项"，而是**安静地接受**（见下面那条坑）。所以搜日志按
`Unknown option` 这几个字，别按编号——编号会随命令与上下文换。

**更要防的是"成功了但没提交你要的那个 run"**：`launch_runs impl_1 impl_2 -jobs 2`
在 **`impl_2` 根本不存在**的情况下返回码 0、不打印任何提示。也就是说 `launch_runs` 的成功
只证明"它接了能接的名字"。两步补上：

- 发之前**逐个名字**数：`[llength [get_runs -quiet impl_1]] + [llength [get_runs -quiet impl_2]]`
  要等于 2。**不能写成 `get_runs -quiet impl_1 impl_2`**——`get_runs` 只吃一个模式，本机取到
  `ERROR: [Common 17-165] Too many positional options when parsing 'impl_2', please type 'get_runs -help' for usage info.`
  且返回码 **1**；这种句子通常是脚本里的判据第一步，它一抛，后面所有读数都不再打印（同一个陷阱族见本节
  那条"把 `list_property` 包进 `catch`、先数对象再问属性"与 `vivado-project-bd.md` §2 第 6 条）。
  这里带 `-quiet` 是为了**日志卫生**
  ——不带时它只是往日志里多打一条"没匹配上"的告警，`llength` 拿到的仍是空集合
  （本机实测 `catch {get_pins NOPE} g` → rc=0、`llength $g`=0；判据那一侧见 `constraints-timing.md` §7 第 4 条）。
  真正的坑不是数字被污染，是**数对了却没发出去**。
- 发之后**逐个**读 `get_property STATUS [get_runs impl_2]`。少这一步，你等的是 `impl_1`，
  比的却是两个 run 的产物。

`reset_run`（单数）与 `reset_runs`（复数）在工程模式里**都可用**（本机各跑通一次）。

只想看生成的脚本长什么样（不真跑）：`launch_runs ... -scripts_only` 本机可用，
它把 run 目录与 `runme.log` 的骨架建出来，用来检查钩子路径、 directive 有没有落进去。

两条命令名的坑（都是 `SKILL.md`"用法"里那条懒注册的表现）：`reset_runs` 在非工程 batch 里查得到名字，
`reset_run` 查不到，可是工具的报错文案让你用的正是 `reset_run`——
**先按工具给你的那句话去敲，再用 `-help` 确认**。
`wait_on_runs`（复数）与 `current_run` 存在；`wait_on_run` 是别名，`-help` 打印的标题是复数那个。
前面有命令失败过之后再调 `wait_on_runs`，得到的是
`[Common 17-39] 'wait_on_runs' failed due to earlier errors.`——与 `vivado-project-bd.md` 说的同一个道理：
`17-39` 是下游外壳，真错在它上面第一条。

## 7. 交给别人一份构建：能证明的是产物，不是"板上跑它"

`§4` 第 4 条的哈希只回答"文件换没换"。要让另一个人**复核同一版构建**，交接包里要有这五件，
缺一条对方就只能猜：

1. 驱动构建的那份 tcl（含 §5 的钩子脚本本体，不是"我点过 GUI"）；
2. part 的全名 + 工具版本（换版本=换证据，见 `constraints-timing.md` 页首）；
3. run 的属性快照：`foreach p [list_property [get_runs impl_1]] { puts "$p=[get_property $p [get_runs impl_1]]" }`
   的原始文本（策略、directive、`IS_ENABLED`、`MORE OPTIONS` 都在里面）；
4. 约束文件那一份的原样副本（不是"和工程里一样"）；
5. 产物哈希表（`.bit`/`.xsa`/报告），并写明 JTAG 下载是易失的——
   对方拿到这些也**证明不了**板子上跑的是它，那要靠 RTL 里的版本寄存器读回（`SKILL.md` §1 第 5 条）。

跨机器复现不上时，先按这份清单逐条 diff，再怀疑工具：绝大多数"同一工程两台机器结果不同"
落在第 1、2 条（GUI 点出来的设置没进 tcl、版本或速度等级不同），不是综合器不稳定。

## 8. 失败与竞态的判读

| 现象 | 真实含义 | 下一步 |
|---|---|---|
| `launch_runs` 立刻返回但没有任何产物 | 它只是提交任务 | 读 `STATUS` 与 run 目录日志 |
| `launch_runs` 返回 0、日志里连一条提示都没有 | 你给的部分 run 名**不存在**，它只是没接（§6 本机实测） | 按名字各数一次 `llength [get_runs -quiet <名字>]` 加起来够数再重发；几个名字塞进同一条 `get_runs` 会抛 `17-165`（§6 第一条），也别改命令写法 |
| `STATUS` 里某步是 `<步骤名> ERROR` | 该步内失败（这一步之后的都没跑） | 打开该步日志的 `ERROR:` 行，不要看总日志尾巴 |
| `launch_runs` 报 `[Common 17-69] ... Run 'synth_1' needs to be reset before launching` | 这个 run 已经有产物/状态，改完东西不重置不让重跑 | 按它给的话用 `reset_run`（单数）或 `reset_runs`（复数）再 `launch_runs`；跳过这步的结果是"改了没重跑" |
| `wait_on_run` 返回但 `STATUS` 仍未完成 | 超时/队列异常/子进程还在 | 再看一次 `STATUS`；别急着重发同一命令 |
| 重跑同一 run 结果"莫名变好" | 上一跑的产物被复用 | `reset_runs` 后重跑，比较前后报告 |
| 同一策略重跑两次，报告只差两行 | 本机一组读数：`reset_runs impl_1` 之后 `launch_runs impl_1 -to_step route_design` 再跑一遍，两份 `report_timing_summary` 各 **337 行**，逐行比只落在 **2 行**上——第 4 行 `Date` 与第 6 行命令回显（因为 `-file` 给了两个不同路径），而 WNS `7.746`、TNS `0.000` 两边**逐字相同** | **别把读数差异当"正常波动"吸收掉**：同机、同版本、同策略、`reset_runs` 干净重跑本来就该一致，**差出第三行就是有一个输入变了**（directive、工具版本、IP 版本、增量状态、part 重选）——去查那一个变量，而不是再跑第三次凑多数。"这一处改动值不值得再开一轮"是另一问，走 `constraints-timing.md` §5（它估收益上限，不比读数） |
| 并行两个 run 抢同一份中间文件 | 竞态 | 串行，或用不同 run 名；见 `board-bringup.md` §5 |
| 探针脚本自己把会话弄死，而且死在**下一行无关命令**上 | 本机实测的最小对照：六行脚本（定义一个过程、`read_verilog cnt.v`、`synth_design`、`puts`）**只换过程名**——叫 `try` 时第一条 `read_verilog` 报 `[Common 17-685] Unable to load Tcl app xilinx::xsim` 加 `[Common 17-69] Command failed`，`-mode batch` 直接 rc=1，后面每条读数全没打印；叫 `tcall` 时同一份脚本 rc=0、`synth_design` rc=0 | 探针脚本别覆盖 Tcl 内建/工具已占用的名字；见下面那段"名字占用"的取法 |
| `catch` 抓到的 msg 字段只有一条包装 | 真错在它上面那一行 | 见 `onchip-debug.md` §1 规则第一条末尾（`17-39` 包住 `44-199` 那次）；判据要落错误编号就去日志里取上一条 `ERROR:` |

批处理启动本身也要留证据：`-mode batch -nojournal -log <文件> -source <tcl>`，
`tcl` 里**不要在末尾 `exit` 之外再抛错**——`source` 中途报错时后面的命令不会执行，
所以关键读数要放在最前面打印。

**"名字占用"这件事在探针脚本里是一个可查的项，不是运气。** 本机两次被它掀掉会话，取法固定三条：

```tcl
# 1) 先看你要定义的过程名在这版工具里是不是已经有名字（Tcl 内建或已装载的应用命令）
puts "PROBE-COLLIDE <try> = [info commands try]"        ;# 打出 try 就是撞了
# 2) 撞了就换名；再把这条探针本身当成一次回归：换名前后各跑同一份脚本，比 rc
# 3) 打印名字时用 <[list $n]> 包起来，空读数才看得见边界
foreach n {read_verilog xvlog xelab xsim exec} {
  puts "PROBE-NAME <[list $n]> = [info commands $n]"
}
```

本机那一轮的第 3 条读数是 `read_verilog`/`exec` 有名字而 `xvlog`/`xelab`/`xsim` 三个全空
（`onchip-debug.md` §1 记过同一种"空读数要用有名字的样本括住"的做法；`SKILL.md` §1 第 9 条）。
第 1 条在**新会话**里对 `try` 打出的是 `try`——它就是 Tcl 8.6 的内建命令（本机 `[info patchlevel]`
是 `8.6.13`），而内建命令被自己的 `proc` 顶掉之后，受影响的不一定是调用它的那行，
而是**任何内部用到它的工具代码**（这次是 `read_verilog` 去惰性装载 `xilinx::xsim` 那一路）。
所以这条规矩的写法是：**探针脚本里每个 `proc` 名字先查一次再用**，别靠"这名字没人用吧"。

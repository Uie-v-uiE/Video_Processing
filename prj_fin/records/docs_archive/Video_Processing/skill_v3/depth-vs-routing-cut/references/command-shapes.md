# Vivado 命令与报告形状（实测表）

本表收的是**命令与文本形状**这类"猜就会错"的事实，来源是一次次失败的滚动与只读探针，
版本为 2025.2.1（7 系列 / Zynq-7000 器件；换版本要重测）。
用法约定：写解析前先按本表核对形状；本表没收录的就用只读探针打印原文，**不要按记忆写正则**。

## 目录

- 报告字段怎么读
- 扇出与复制
- 方法学与未约束端口
- 约束命令的选项集（实测有/无）
- Tcl 取对象与字符串
- 便宜的探针车道
- 官方文档取不到时怎么办

## 报告字段怎么读

| 事实 | 症状/后果 |
| --- | --- |
| `report_timing` 的占比在**括号内**：`Data Path Delay: 3.498ns (logic 0.655ns (18.725%) route 2.843ns (81.275%))` | 按 `route <n>ns <p>%` 写模式永远读空，而计数地板照样绿 |
| `report_timing_summary` 表头与数值行的字段数不同（单空格切分给 53 vs 157）⇒ 两边都用 `regexp -all -inline {\S+}`；取回后 0=WNS、2=setup 失败端点、4=WHS、6=hold 失败端点 | 按表头列序索引数值行会读到空或错列 |
| 分隔行是每列一组 `-------  -------` ⇒ 跳过分隔要用**前缀判断**，不是"全是横线"的正则 | "全横线"匹配不到带空格的真实分隔行 |
| 设计级 WNS 在 `| Design Timing Summary` 之后第 **7** 行（第 5 是表头、第 6 是分隔） | 按"表头下一行"取数会取到分隔行 |
| `report_route_status` 没有 "Route Timing Met" 这种词，行形如 `# of fully routed nets............. : 20907 :` | 搜关键词得到空集，被读成"没布线完" |
| 读不到的字段要打印 `NA`，不能打印 `0` 或空 | 空值被当成 0 是"假绿"的头号来源 |

## 扇出与复制

- **没有** `set_max_fanout`、`create_qor_suggestion`、`get_properties` 这些命令
  （`help` 批处理实测：`ERROR: [Common 17-25] No topics matched`）。
  扇出复制是实现阶段可选项，不是约束命令。
- 高扇出清单：`report_high_fanout_nets -file … -max_nets N -fanout_greater_than N [-timing] [-load_types] [-clock_regions]`。
  `-fanout_greater_than N` **含 N**。正文行形状就是三格 `| 网路径 | 扇出 | 驱动类型 |` ⇒ 按三格解析，
  别按"第一个整数＋一个带斜杠的串"（那会把报告自己的命令行读成一张网）。
- `report_design_analysis` **没有 `-fanout` 模式**；可用模式是
  `-complexity/-congestion/-timing/-routes/-logic_level_distribution/-routed_vs_estimated/-qor_summary`。
  `-congestion` 会给"No congestion windows are found above level 5"——那是有效的**负读数**，不是解析失败。
  `-routes` 不接受 `-from/-to`。
- **对象侧读不到扇出**：`get_property FANOUT [get_nets …]` 为空；`llength [get_pins -of $net]` 数的是引脚，
  与报告给的扇出可以差很多。⇒ 扇出差分只能比两份 `report_high_fanout_nets`，
  或用复制体后缀作为"机制动了"的第二来源。
- `phys_opt_design` 实测**有**的选项（部分）：`-force_replication_on_nets`、`-fanout_opt`、`-critical_cell_opt`、
  `-placement_opt`、`-retime`、`-directive`、`-critical_pin_opt`、`-hold_fix`、`-aggressive_hold_fix`、
  `-clock_opt`、`-routing_opt`、`-lut_opt`、`-bram_*`/`-dsp_*`/`-uram_*`。
  实测**没有**的：`-skeleton_clustering`、`-rewire`、`-replication_count`、`-cell_opt`、`-shift_registers`、
  `-hold_buffer_insertion`、`-aggressive_replication`。
  写错时命令在 `catch` 里**静默什么都不做** ⇒ 采纳前把 `help <cmd>` 的选项清单落进当轮证据件，
  并用"复制体计数变化"作为正对照。

## 方法学与未约束端口

- `report_methodology` 的权威计数在 **SUMMARY 表**（`| RULE | Severity | Description | Checks |`），
  且表内各行相加必须等于上方的 `Checks found: N`——不相等就是你漏了一类。
  整文件 `grep -o 'RULE-n'` 会把摘要行自己也数进去，每类 +1。
- 过滤开关是 `-checks`（**没有** `-rules`）。
- 详情条目会点名对象（例如某类 I/O 缺窗会写出具体端口名），`check_timing` 只给计数——
  所以按名字的第三来源是 methodology，不是 check_timing。
- 只有 `check_timing -verbose` 会给**未约束端口的权威名单**；原句形状：
  输入侧 "There are N input ports with no input delay specified. (HIGH)"、
  输出侧 "There are N ports with no output delay specified."（措辞不对称，别按同一模板解析）。
- **三种单位、三个数**：`check_timing` 数端口、methodology 数检查/引脚、RTL 端口表数位 ⇒ 永远不许相减。
- 时序例外**不是可查询对象**：没有 `get_false_paths`/`get_clock_groups`/`get_timing_exceptions`，
  只有 `report_exceptions`；其正文行以序号开头、不打印 `-datapath_only` ⇒ "界生效了没"只能靠两次滚动的差分。

## 约束命令的选项集（实测有/无）

- `set_input_delay`/`set_output_delay`：**没有** `-setup`/`-hold`，**没有** `-clock_edges`；
  DDR 的第二沿是另写一条 `-clock_fall`；`-min` 与 `-max` **必须各一条**（合写报"参数过多"，
  而报错把矛头指向端口列表）。
- 实测：只写上升沿版本与写双沿版本给出**完全相同**的数字 ⇒ `-clock <clk>` 已覆盖该钟的工作沿；
  别靠"多写一对命令"补 DDR 覆盖，也不要在 hold 变红时怪那多出来的一对。
- `set_max_delay -datapath_only` 叠在 `set_clock_groups -asynchronous` 的同一对时钟上：**例外行 0 条**。
  界值不能叠在被排除的对上，只能收窄排除范围（而那会改变 WNS 的计算对象）。
- `ASYNC_REG` 是**布局指令**不是注释：加上后相关寄存器被收进同一族片、资源与警告计数不变，
  而设计级 WNS/WHS 都动了 ⇒ "只改属性是时序中性的"是错的；中性的是资源与警告。
- `set_property IDELAY_VALUE` 在**已布线检查点**上就能改并被读回（一次实测每档约 +63 ps 的 hold、
  -92 ps 的 setup，量级随设计变）⇒ I/O 延时/相位这类问题先在 DCP 上扫完再开构建。
- pblock：范围要写 `SLICE_XnYm:SLICE_XnYm`（UltraScale 的 `CLBLM_*` 写法在这里被拒）；
  `get_property RANGE <pblock>` 读到空 ⇒ 拿它当硬门会**误拒**合法实验；
  真正的存在性检查是逐单元 `get_property SITE` 是否落在 `get_sites -of_objects $pb`；
  边界切断进位链时放置器把单元留在块外（实验从单变量变多变量）。

## Tcl 取对象与字符串

- 网络按**纯层次路径**取：`get_nets -quiet <path>` 可靠；
  `-filter "NAME == {全路径}"`、`FULL_NAME ==`、`-hier -filter "NAME == {叶名}"` **都返回空**，
  而 `get_property NAME` 打印的正是那个路径 ⇒ 取完必须回读名字核对，不一致就拒绝，
  别让空集合冒充"约束没起作用"。
- `get_cells` 只接受**一个**位置模式（`get_cells a* b*` 报"Too many positional options"）。
- 含 `[12]` 的名字模式是 glob 字符类：`off_reg[12]` 会匹配 `off_reg1`/`off_reg2` ⇒ 转义或验 `llength`。
- `get_nets -quiet *` 不加 `-hier` 只返回顶层网 ⇒ 喂给扇出扫描得到"没有高扇出"的假干净。
- `expr` 里不许直接写 `info exists`（`invalid bareword`）；用 `if {[info exists …]} {}`。
- `!~` 不是 Tcl 表达式运算符（用 `string match`）；解析错误只在那一行才炸，可能前面的长任务已经跑完。
- 以 `-` 开头的模式要给 `regexp` 加 `--`，否则被当选项（这条曾把三条滚动带偏，而真因是打字）。
- `clock format -format %F_%T` 不加花括号会打印出字面 `%F_`；写 `-format {%Y-%m-%d_%H:%M:%S}`。
- **`.tcl` 全文要 ASCII，含注释**：Vivado 按系统码页解码，UTF-8 尾字节能吞掉后面的 `{` 或 `"`。
  `puts` 标签尤其要 ASCII，否则控制台把崩溃读成一条"红"。
- 从 Tcl 生成含方括号的别的语言文本（PowerShell 静态调用、JS 下标、正则字符类）时，
  双引号里的 `[` 是**命令替换** ⇒ 要么 `\[` 要么用花括号引号。报错里出现"你没写过的那个命令名"就是它。
- `get_hw_devices` 在 `open_hw_target` 之前是空 ⇒ 空集合不等于"板子没供电"。
- Vivado 眼里的 `/tmp` 不是 bash 的 `/tmp` ⇒ 用 `cygpath -w` 传路径；`tclsh` 没有 `-c`；
  `vivado -source /dev/stdin` 读不到 heredoc ⇒ 先落成真文件。

## 便宜的探针车道

- `help <cmd>` 在一个不开设计的批处理里约 40 秒 ⇒ 用它量"选项到底有没有"，而不是猜。
- 检查点：`*.runs/synth_1/<top>.dcp`、`impl_1/<top>_opt.dcp`、`_placed`、`_physopt`、`_routed`。
  从 `_opt.dcp` 重跑 place+route 约 7–9 分钟 ⇒ 这是判断"跨构建的 WNS 移动是不是真的"最便宜的反事实车道。
- 只读探针要打印：设计是否打开、取到几个对象、每条命令的 rc；三者缺一，读数不作数。

## 官方文档取不到时怎么办

文档站是 JS 单页应用：直接 HTTP 取一个文档页只会拿到"请启用 JavaScript"，
**那不是"文档不存在"的证据**。真 PDF 走文档站的 `khub/documents/<id>/content` 端点，或用浏览器工具，
或本地安装目录里的文档。永远不要据一次 shell 抓取失败下结论"查不到资料"，
也不要引用一份自己没真取到的文档。

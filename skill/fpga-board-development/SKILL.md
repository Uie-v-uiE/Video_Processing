---
name: fpga-board-development
description: 用于 Verilog/VHDL 加 Vivado/Vitis 的 PL-PS 工程改动与调试。写或改可综合 RTL、对齐流水线延迟与门控同拍、处理跨时钟域与复位、写物理约束与时序约束并读时序报告（WNS/TNS/失败端点/命中计数/死约束）、组织 Vivado 工程与 Block Design（文件集、IP、地址、改名、导出 .xsa）、跑构建与策略（launch_runs/策略/directive/让 run 自己交报告）、造自检 testbench 与参考模型、跑 xsim/ModelSim/iverilog、生成并烧写比特流（JTAG 易失与 QSPI/SD 自启的区别）、插 ILA/VIO 并管 JTAG 通道与 hw_server、判断板上到底在跑哪一版、分诊「设了没反应」「写一笔就把 CPU 卡住」「位置偏 vs 颜色偏」「偶发一拍错值」，以及跑综合后网表仿真（`glbl`/GSR 窗口）与带 SDF 的时序仿真（`launch_simulation -mode/-type`、注解成没成看 `XSIM 43-3451/43-3452`、tb 的 `file_type`）、`report_timing` 说没有路径而返回码仍是 0、`reset_run` 与两个策略并行对比、`bootgen` 出的镜像起不来、`MARK_DEBUG` 设了读不回来、给 run 加自动出报告的钩子，以及判断一个结论需要哪一级读数；「控制侧全通、搬运/引擎侧一步不动」的两路钟分诊、`validate_bd_design` 点名没接的时钟引脚、`CONNECTED_BD_PINS` 取到空值、`.ltx` 与比特流是否同批（`file mtime` 只到秒）、ILA/VIO 端口属性清单逐端口不同。PYNQ 运行时（Overlay/寄存器/DMA/中断/缓冲区）用 pynq-overlay-development。不用于纯软件项目、与硬件无关的脚本、器件采购选型。
license: MIT
---

# FPGA / Zynq 工程改动与调试（Vivado 侧）

## 用法

先按第 4 节的症状只打开命中的那一页，不要一次读全部参考文件。
工具版本不同，命令名与报告字段位置就不同：**要解析哪份报告或要用哪个命令，先在机器上取一次它的
真实形状**（`report_* -help`、`list_property`、`list_property_value`、把报告头几行打出来），再写判断。
取形状用 `-help` 或**直接调用看它报什么**；不要用 `info commands` 判"这版有没有这条命令"——命令是
懒注册的。判存在性只看 `<命令> -help` 的报法，本机有一对能分开两种情况的读数：
`create_bd_design -help` 在**没开工程、没 `load_features`** 时照样打出 `Description:` 用法行
（而同一时刻 `info commands create_bd_design` 是空），`load_features ipintegrator` 之后名字才出现在
`info commands` 里；`write_project_xpr -help` 加不加 `load_features` 都报
`invalid command name "write_project_xpr"`。所以 **`info commands` 空不足为凭，`-help` 能打出用法就是存在；
只有 `invalid command name` 才是否定证据**（在你要用的那个上下文里试——`load_features` 的那几个合法特性名见
`references/onchip-debug.md` §1）。别把另一路 `help <命令>`（Tcl 帮助系统）混进来，它对同样的东西会给
`[Common 17-25] No topics matched`。同理，`get_property` 遇到"名字不对"有**两种本机都遇到过的报法，
而哪种对应哪一类对象并不由名字的形状预测**：`get_property CLOCK [get_ports X]` 回空并跟一条
`[Common 17-673]` 告警；`get_property PROBE_TYPE [get_debug_ports dbg_hub/clk]`（钟端口没有这个属性）
报 `[Vivado 12-4442] Invalid property name`，是 **ERROR——不包 `catch` 就把整个 batch 会话从那一行截断**，
后面所有读数都不会打印（对象取空时同理，`[Common 17-55] expects at least one object`）。
所以"读回来是空"和"这句没报错"都不能当依据，**判"这个名字在这层存在不存在"只看
`list_property <这个对象>`**——它是逐对象的，不是全局表。
这条还**分对象族**，两边的失败形状不一样：run 对象上读一个编出来的属性名（本机试的是 `IS_IMPL`）
给的是 **rc=0 + 空串、一句错都不报**（同一会话读 `NAME` 返回 `impl_1`，证明那条 `get_property` 在干活）；
上面那种 `12-4442` 只出现在 debug port 那一族。所以"空串"永远分不清是值为空还是名字不存在。
工具不在 PATH 不等于没装：Vivado 命令行在 `<安装根>/Vivado/bin`，ModelSim 在 `<安装根>/modelsim/win64`。

## 1. 九条硬规则（结论与读数的配对）

1. **语法过了 ≠ 连接对了。** 判"没告警"数的是日志里的 CRITICAL WARNING **条目本身**，
   不是摘要那行计数——同一份日志可以同时出现"3 条 CRITICAL WARNING"和
   "0 errors, 0 critical warnings"。
2. **功能对 = 自检 bench 打出判定行，且它被一次人为破坏弄红过。** 一条出生以来没红过的判据
   不构成证据；仿真器的**退出码不可信**（`$fatal` 触发、transcript 明写 FAIL 时退出码仍为 0）。
3. **"时序收敛"只认 implement 之后、且与烧进板子的那一次 impl 同源**的报告；综合阶段的是推测值。
   建立与保持要一起取（WNS 与 WHS）。
4. **约束按名字命中才生效。** 每条约束自己出命中计数（`llength [get_ports -quiet X]`；
   这版 `sizeof_collection` 调用就报 `invalid command name`）。**"指向不存在的东西"没有一条固定文案**，
   本机见过的形状：`CRITICAL WARNING: [Vivado 12-4739] ... No valid object(s) found for ...`、
   `WARNING: [Vivado 12-481]` / `[Vivado 12-584] No ports matched '...'`（过滤器空结果），
   调试端口那一族则是 `WARNING: [Vivado 12-1423] No ChipScope debug ports matched '...'` 返回 0、
   错要到下一句才以 `[Vivado 12-1420] Debug port '' was not found.` 冒出来。
   所以判据一律是**命中集合的大小**，不是"日志里有没有某句话"。
5. **板上跑哪一版，只认 RTL 里版本寄存器的读回。** 产物哈希只回答"文件换没换"；
   JTAG 下载是易失的，重启后跑的是启动介质里那一版（还得启动模式引脚真指向它）。
6. **"改好了" = 同一条命令改前能复现、改后不复现，两份读数都留下。** 只改完看一眼不算。
7. **给数字要给口径**：同一口径重复若干次的原始读数，写明计数窗口、时钟频率、取最差还是中位。
8. **一次改动跨 RTL / 固件 / 上位机三个域，就分三处收证据**，不许合成一句"改完验证通过"。
9. **三种"看着像读数"的东西不是判据**：命令返回码（**"名字合法、对象/方向不对"才可能返 0**，
   §7 那条 `set_property PULLUP true [get_ports <输入脚>]` 就是这种——把它查得更细：
   这个名字**写之前不在 `list_property` 清单里、写完之后就在了**，所以"清单里没有"与"能读回值"
   都抓不住它；真会红的是写的时候那句 `[Netlist 29-177] Cannot set property 'CLOCK' because the
   property does not exist.`；
   而**同一个"名字不存在"的错，按对象类型换的是整族编号**——本机在工程流里取到
   文件对象 `[Common 17-142] Invalid property name 'NOPEATTR'…`（rc=1）、
   run 对象 `[Common 17-54] The object 'run' does not have a property 'NOPEATTR'`（rc=1）、
   端口对象则是上面那条 `[Netlist 29-177]`（rc=1）——
   **所以"名字写错了"不能按一个编号前缀去搜**，要搜的是文本本身
   （`does not exist` / `Invalid property name` / `does not have a property`）；
   另要注意**空集合本身也会抛**：`set_property PULLUP true [get_ports -quiet clk]` 在还没综合的
   工程里给 `[Common 17-161] Invalid option value '' specified for 'objects'`，
   看着像属性错，其实是对象为空——同一族陷阱是
   `list_property_value [get_ports -quiet 不存在] IOSTANDARD`，它把**属性名**报成非法值
   （`Invalid option value 'IOSTANDARD' specified for 'object'.`），一个字不提集合为空）；
   `write_debug_probes` 没有调试核也返 0 且不生成文件（本机连返回值都取到了：msg 就是
   `<工作目录>/out.ltx` 这个**并不存在**的路径，同会话里 `write_hw_ila_data out.ila` 反而 rc=1
   报 `44-235`——**同一个"写文件"动作里两条命令的空/红形状不一样，别互相推断**），`bootgen` 命令行写错也返 0——
   但**这一条只在 `bootgen.bat` 上成立**：本机同一句 `-arch bogus` 走 `bin/bootgen`（`#!/bin/bash` 那个包装）
   回的是 rc=**1**，错误文本两边一模一样。脚本里"用返回码兜住 bootgen"要先定你调的是哪个入口）；
   `get_property` 读回的空（名字在这层不存在、与本来就没值，**两种都可能只回一个空**，
   按上面"用法"那段用 `list_property` 分开它们）；
   "工程/文件清单里有这一项"（`USED_IN_*` 全 0 时约束文件照样列在表里）。
   合格的判据是一个**会随你的改动而变**的量：命中集合的大小、报告里的某个字段、文件是否真存在、
   读回来的位值。**读不到就写 `NOT RUN`**——空集、解析失败、读回口本来没实现，一律不算通过。

## 2. 六条不变量（改之前成立，改之后必须重新检查）

- **I1 流水线深度只有一个真源。** 与它对表的偏移（延迟链、消隐窗、有效位拖拍）必须由同一个参数
  导出。改深度后先列出"同一个数字在几处出现"（grep 参数名），别只改一处。
- **I2 门控信号与数据同拍。** 用数据流做选择/计数/打标记时，控制信号要延迟到与它门控的数据同一拍。
  数据链加深而控制链没跟，症状就是"边界偏了几列/几行"。
- **I3 控制字位序是 ABI。** RTL 位定义、固件写出的字、上位机掩码三处必须同源。只改一处不报错，
  只会静默错位；新增位往高位加，不重排。
- **I4 约束按名字命中。** 改例化名/端口名/包一层 wrapper 之后，约束可能指向空集合而流程全绿。
- **I5 板上身份要能读回来。** 版本/构建号寄存器 + 自由运行计数器；两者也是分诊树的第一手读数。
- **I6 判据必须能红。** 见 §1 第 2 条。给它做最小破坏（翻一位、删一行、改一个参数），把那次红的
  读数留着。

## 3. 改动节拍

1. 写下这次改什么、预期看到什么、可能影响哪几处（三行）。
2. 只动一个域；跨域拆两轮。
3. 在**未改**的树上先跑一次判据拿"改前红"，再改，再跑同一判据。
4. 静态 → 仿真 → 综合/实现 → 上板，按这个顺序；每级留它自己的读数。
5. 上板前确认产物身份与烧写方式；上板后把读数写回记录。

同一方向连续三次没能改变可观测结果，就停止叠加尝试，把问题换一层（软件 → 网表 → 约束 →
工具/硬件），并说明剩下没排除什么。

## 4. 症状分诊

每行只给**一个**入口小节（最能判别的那一节），不给范围——范围里总有一节是别行也用过的，等于没指。
进了那一节再顺着它内部的引用往外走。

| 症状 | 先读 |
|---|---|
| 不知道该收哪一级读数、"通过/没问题"这句话能不能说 | 本文件 §1 |
| 报"不认这个命令"、命令在 GUI 里有点过的按钮 | 本文件 §5 |
| 要不要先拿现场确认（擦 Flash、抢占 JTAG/串口、复位别人的板） | 本文件 §5 |
| 这问题本包到底答不答 | 本文件 §6 |
| 改深度/加一级寄存后，**设计本身**的偏移对不上 | `references/rtl-pipeline-cdc.md` §1 |
| 边界偏了几列/几行：数据链加深、控制信号没跟着拖拍 | `references/rtl-pipeline-cdc.md` §2 |
| **位置/时间**偏：错列、错行、慢一帧 | `references/rtl-pipeline-cdc.md` §3 |
| 复位网络怎么做（异步断言、同步释放）、给复位那一路加例外之后还剩谁在查 | `references/rtl-pipeline-cdc.md` §4.3 |
| 偶发一拍错值、标志丢或重复、假满假空、值是个没定义过的中间数 | `references/rtl-pipeline-cdc.md` §4 |
| 单bit跨钟只给电平、要判断翻转位够不够快（会不会漏拍） | `references/rtl-pipeline-cdc.md` §4.1 |
| 多位量跨钟：握手、异步 FIFO、格雷码三选一怎么挑 | `references/rtl-pipeline-cdc.md` §4.2 |
| 消隐/延迟预算花不起、加了级就丢行；**画面滚动/整帧偏一行** | `references/rtl-pipeline-cdc.md` §6 |
| 逻辑像被优化掉了：块在网表里不存在、读回恒 0、搜模块名搜不到 | `references/rtl-pipeline-cdc.md` §5 |
| **`validate_bd_design` 红了但不知道缺什么**、`make_wrapper` 报 `12-5158`/`BD 41-1031`、`assign_bd_address` 报 `BD 5-126`、给连接命令加了 `-quiet` 之后"rc=0 却没连上" | `references/vivado-project-bd.md` §2.2 末段（那五条 `41-249`/`41-758`/`41-1356`/`41-1031`/`5-699` 的成套形状） |
| **要跑带 SDF 的时序仿真**（注解成没成看 `43-3451/43-3452`、`xelab` 里没有 `--sdfmax`、tb 要设 `file_type SystemVerilog`） | `references/verification.md` §8 末尾那条"带 SDF 的时序仿真这一臂现在通了" |
| 时序红了，要看 WNS/TNS/失败端点、分清是哪一阶段的数；`report_timing` 说没有路径而返回码仍是 0 | `references/constraints-timing.md` §4 |
| 换了时钟源/加了 `create_generated_clock` 突然变好 | `references/constraints-timing.md` §1 |
| 一条约束到底命中了没有（命中集合是否为空） | `references/constraints-timing.md` §2 |
| `set_false_path` 该管到哪、有没有顺手把数据路也豁免了 | `references/constraints-timing.md` §3 |
| 改了这条约束，时序**最多**能好到多少？值不值得再等实现 | `references/constraints-timing.md` §5 |
| 要一个占了多少的数：资源放不下、某个块占比离谱、分层占用怎么取、哪个阶段才给得出 | `references/constraints-timing.md` §6 |
| 引脚电平不对、bank 电压、差分时钟输入、属性在这个脚叫什么 | `references/constraints-timing.md` §7 |
| XDC 层面：加了没生效/被另一条覆盖、一块工程两版板、生成约束能不能手改 | `references/constraints-timing.md` §8 |
| 加了 multicycle / false_path / case_analysis，不确定管到东西没有 | `references/constraints-timing.md` §9 |
| `report_methodology` / `report_drc` 一堆规则号，哪些要处理 | `references/constraints-timing.md` §10 |
| 给时钟加不确定度/抖动、`set_propagated_clock` 生效没有 | `references/constraints-timing.md` §11 |
| bench 绿了但判据出生以来没红过 | `references/verification.md` §4 |
| bench 全绿但现场坏：参考模型与 RTL 同一套算式 | `references/verification.md` §2 |
| bench 全绿但现场坏：tb 只例化了子模块，没覆盖出错那层 | `references/verification.md` §3 |
| **同一份 bench 在 RTL 绿、综合后网表不绿**、`glbl`/GSR 窗口（复位值在网表侧对不上、头一段全是 `x`）、缺 unisim 库、**要跑带 SDF 的时序仿真**（`launch_simulation -mode/-type`、生成的 `xelab` 里没有 `--sdfmax`、`43-3451/43-3452` 才是注解成功的读数、tb 的 `file_type SystemVerilog`） | `references/verification.md` §8 |
| 红绿到底怎么取：`-sv`、退出码恒 0、判定行怎么 grep | `references/verification.md` §1 |
| 仿真里出现 X/Z、未初始化把比较吞了 | `references/verification.md` §5 |
| CDC 要扫相位的 bench 怎么写（**撕裂**、偶发一拍错位在仿真侧就抓这里） | `references/verification.md` §6 |
| 比对要逐位等还是给容差、容差从哪推、豁免名单按什么作键 | `references/verification.md` §7 |
| 非交互跑批的具体命令（`xvlog`/`xelab`/`xsim`、`vsim -c`、`iverilog`） | `references/verification.md` §9 |
| 工程结构、文件集与编译顺序、源没进综合 | `references/vivado-project-bd.md` §1 |
| BD 的验证与 cell 改名的连锁 | `references/vivado-project-bd.md` §2 |
| 把 BD 倒成脚本、**PS 配置项的 `PCW_*` 参数名**去哪查、IP 版本状态表与 `upgrade_*` 的坑 | `references/vivado-project-bd.md` §2.1 |
| **自己的 RTL 进了 BD 却拿不到地址/连不上接口**（`BD 41-1285` 协议不匹配、`assign_bd_address` 没落点、`OFFSET` 读回来是空） | `references/vivado-project-bd.md` §2.2 |
| 导出 `.xsa` 与整组配套、交给 PS 侧的那份文件 | `references/vivado-project-bd.md` §3 |
| BD 里改了但重新生成后没生效；或**下一个会话里 BD 的 cell/地址全都数不到**（没 `save_bd_design`） | `references/vivado-project-bd.md` §4 |
| run 的状态怎么读（`STATUS` 那一串）、`launch_runs` 立刻返回却什么都没 | `references/vivado-build-run.md` §1 |
| 策略名与 directive 名怎么在**自己这版**里查 | `references/vivado-build-run.md` §2 |
| 这个 run 上有哪些属性可读可写（`list_property`）、时序报告落在哪个 `STEPS.*` 属性、"跑到某步自动执行"的那位叫什么 | `references/vivado-build-run.md` §3 |
| 产物不可重复、part/VLNV/tcl/目录四件事 | `references/vivado-build-run.md` §4 |
| 想让 run 自己把时序报告落盘（钩子写内联 Tcl 不生效） | `references/vivado-build-run.md` §5 |
| 两个策略想并行对比、`create_run -parent_run` 报 `17-69`、`reset_run` 与 `reset_runs` 该敲哪个 | `references/vivado-build-run.md` §6 |
| 命令明明在（`-help` 打得开），选项却报 `Unknown option`；或 `launch_runs` 返回 0 却没提交你要的那个 run | `references/vivado-build-run.md` §6 |
| 把构建交给同事、或**同一工程两台机器结果不同**，要能复核同一版 | `references/vivado-build-run.md` §7 |
| 构建中途报错、报 `needs to be reset` 不让重跑、重跑把上一版产物复用、run 之间抢同一份中间文件、同一策略重跑两次报告**差出第三种行** | `references/vivado-build-run.md` §8 |
| 连不上板、JTAG 通道被占、对象链找不到 target；离线跑 `hw_*` 一律先报 `44-235` | `references/onchip-debug.md` §1 |
| 插了探针之后时序变差、能不能拿调试版的数字当交付结论 | `references/onchip-debug.md` §2 |
| 核是怎么进网表的：IP 那条路与网表手术那条路的命令名与坑 | `references/onchip-debug.md` §2.1 |
| 抓取与触发这一族有哪些名字、为什么本机给不出参数级用法、七步顺序长什么样 | `references/onchip-debug.md` §2.2 |
| 抓到的信号名全对不上、怎么证明抓的是这一次的版本；只想确认一个位在不在动 | `references/onchip-debug.md` §3 |
| 在线调试根本帮不上的四种情况（DDR 负载、现场无 JTAG、总线卡死、长期判版本） | `references/onchip-debug.md` §4 |
| 板上到底跑哪一版、产物哈希能回答什么 | `references/board-bringup.md` §1 |
| 烧进去当时对、重启就没了 | `references/board-bringup.md` §2 |
| BOOT.bin 生成对不对、`bootgen` 报成功但起不来 | `references/board-bringup.md` §2.1 |
| 上电自检顺序、每步要哪个读数 | `references/board-bringup.md` §3 |
| 寄存器"设了没反应"（软件写 PL 寄存器，不是 XDC） | `references/board-bringup.md` §4 |
| **写一笔就把 CPU 卡住/整机僵住**（没返回，不是没生效） | `references/board-bringup.md` §4 第 0 步 |
| 边构建边烧写、产物被同名覆盖 | `references/board-bringup.md` §5 |
| 丢数据/超时/未命中这些路径怎么变成可观测的（每道门一个只增计数器、读回通路、把判据人为造红） | `references/board-bringup.md` §6 |
| 插调试核之后占用与时序变了、取证完要不要重出一版不含调试核的 | `references/board-bringup.md` §7 |
| 要一个"插核到底占了多少 LUT/BRAM"的数（`-hierarchical` 的正确拼法、哪个阶段取得到、那三行读数怎么用） | `references/constraints-timing.md` §6 |
| AXI 层报错：SLVERR/DECERR、未对齐、地址段不认 | `references/zynq-pynq.md` §2.1 |
| 地址不是常数、offset 按字节、同一 IP 里只差一位的寄存器名 | `references/zynq-pynq.md` §2 |
| C 代码里先写数据再写使能位，PL 读到旧值；打印的该是读回来的值还是写进去的值；中断使能该在哪一步打开 | `references/zynq-pynq.md` §3 |
| cache 维护方向写反（flush 与 invalidate 用颠）、"第一次对、第二次读到旧的"、长度不足一行的尾巴 | `references/zynq-pynq.md` §3 |
| PS 读写 PL 走哪条路、HP 口与 GP 口的区别 | `references/zynq-pynq.md` §1 |
| 控制侧寄存器全通、搬运侧一步不动：这个 IP 有几路时钟引脚、各驱动哪些接口（`validate_bd_design` 的 `BD 41-758`、`CONFIG.ASSOCIATED_BUSIF`） | `references/zynq-pynq.md` §1 |
| 帧缓冲的提交点与换页时机（什么时候把这块缓冲交给 DMA/PL、什么时候翻页） | `references/zynq-pynq.md` §4 |
| `DMA.transfer()` 没抛异常、`ip_dict` 里也有这个地址，为什么还不能说 PL 做了那件事（PS↔PL 的三层各算哪一层） | `references/zynq-pynq.md` §7 |
| Overlay 与 `.bit/.hwh/.xsa/.dtbo` 配套、重下载后对象失效 | `references/zynq-pynq.md` §6 |
| **颜色/通道**偏：偏色、红蓝互换、缺通道、发灰削顶、渐变台阶 | `references/zynq-pynq.md` §8 |
| 想知道**我这一台**上有哪些 Python 名字可用（`dir(pynq)`、`inspect.signature`、`ip_dict` 现取一次） | `references/zynq-pynq.md` §5 |
| 抛出的文本已经点到中断引脚名（`No Pin of name`、`Interrupt(...)` 构造失败） | `pynq-overlay-development` |

表里有几组行天生会互相抢读者，判别条件写死在这里，不要靠"感觉像"：

- **"优化掉了" vs "探针抓不到"**：先分清是**信号在网表里不存在**还是**信号存在但调试链路没接上**
  （`onchip-debug.md` §3：`.ltx` 与比特流不同批、探针名与 RTL 名不对应）。前者不是靠猜：
  `rtl-pipeline-cdc.md` §5 末尾给了在网表上数的四条 `llength [get_cells/-pins/-nets …]`
  （含"`-quiet` 只是日志卫生、判据一直是 `llength`"、"模块名不会出现在原语名里"与那条正向对照）；
  要拿网表的**文本**做 grep 就走 `verification.md` §8 的 `write_verilog -mode funcsim`。
  判据是"网表里数得到吗"，不是"ILA 里看不看得到"。
- **"bench 全绿但现场坏" vs "RTL 绿但网表不绿"**：前者是同一条 bench 在**两个不同层次**的例化上
  结论不同（tb 层次不够 / 参考模型同源，`verification.md` §2、§3）；后者是**同一个例化换了对偶模型**
  （行为级 RTL vs 带 SDF/GSR 的网表，`verification.md` §8）。分诊动作不同：前者改 tb，后者把网表跑起来。
- **"位置偏" vs "颜色偏"**：位置类走 `rtl-pipeline-cdc.md` §3（先实测深度），颜色/通道类走
  `zynq-pynq.md` §8。两边都"偏几列"时先看偏的是**几何**还是**分量**——几何偏找时序与消隐，分量偏找
  通道顺序与位宽截断。
- **"边界偏几列"（§2）vs "每一列都偏同样几列"（§3）**：这两行都会报"偏 N 列"，判据是**偏的范围**——
  只有开头/结尾几列不对、中间全对 → 门控信号没跟数据同拍（§2）；整幅一起平移、中间也错 →
  延迟深度本身数错了（§3，先用那里的单脉冲探针量真实深度再谈改哪)。
- **"偶发一拍错值"（§4）vs "某个值恒 0/恒读不到"（§5）**：CDC 的症状是**大部分时候对**、偶尔抓到一拍
  中间态；如果每一位每个采样点都一样（永远 0、永远 F），那不是时钟域，去 §5 查逻辑还在不在网表里。
- **"`launch_runs` 返回 0 却什么都没跑"（§1 与 §6 两行都像）**：先数对象——`llength [get_runs -quiet <名字>]`
  为 **0** 就是"你要跑的那个 run 根本不存在"（§6：静默没提交，含并行 run 那一族）；数得到、
  但读不懂它到哪一步了 → §1（`STATUS` 那一串的读法）。这一问在两行之间做，别看措辞。
- **改了例化名/端口名之后"突然全绿"**：三行都可能像（约束命中为空、时钟模型变了、逻辑被优化掉）。
  按能被最快推翻的顺序走：① `llength` 取命中集合（`constraints-timing.md` §2，空就是它）；
  ② 报告里那条路径还在不在（`constraints-timing.md` §4 第 4 条，`No paths found` 而返回码 0 也是"没了"）；
  ③ 两条都正常才去 `rtl-pipeline-cdc.md` §5 查常量传播。
- **"两次读数不一样"的三行**：**同机同版本同策略的干净重跑本来就该逐字一致**——本机一组读数把这条
  钉住了（`reset_runs` 后重跑，两份 337 行的 `report_timing_summary` 只差 `Date` 与命令回显两行，
  WNS/TNS 逐字相同，判据与"差出第三行该查哪五个变量"在 `vivado-build-run.md` §8）。
  所以**"差一点点"不是要吸收掉的波动，而是有输入变了的证据**；先 diff 再决定要不要重跑，
  别再跑第三次凑多数。换了机器或版本=先 diff 交接五件套的前两条
  （`vivado-build-run.md` §7：驱动 tcl、part 全名含速度等级）；"改完这一处值不值得再开一轮"
  才是 `constraints-timing.md` §5（估收益上限，它不比读数差异）。
- **ILA 那一组行的问法是"我现在缺什么"**：缺命令名→§2.1；缺"这个数字算哪个版本、能不能拿它签字"
  →§2；缺触发与落盘→§2.2；只是想看一个位在不在动→§3（VIO 通常占得比 ILA 少——**这个成本差要自己数**，数
  字走 `constraints-timing.md` §6 的差值法；且它同样是网表变更）。
  再往外分：**要数字**（占了多少、放不下、分层占用怎么取）→`constraints-timing.md` §6
  （分层那张表的正确拼法是 `-hierarchical`，综合后就给得出）；**要做决定**（值不值得插、插完时序变了算哪一版、
  取证完要不要重出一版干净的）→`board-bringup.md` §7。
- **`KeyError`/拿不到 IP 的三行**：错在 **Python 侧句柄**（overlay 对象、`ip_dict` 键空间）→
  去 `pynq-overlay-development`；错在**配套件不同批**（`.bit`/`.hwh`/`.dtbo` 混版）→`zynq-pynq.md` §6；
  错在**BD 里 cell 改过名**（下游 `.hwh`/`xparameters.h` 还留旧名）→`vivado-project-bd.md` §2。
- **"半新半旧/尾巴坏"的两行**（`zynq-pynq.md` §3 与 §4）：**症状词是重叠的**（"不足一行的尾巴"两行都像），
  所以别按词判，按那一问判：**"这笔搬运有没有先被证明完成了"**——没证明过就先归 §4（提交点与完成判据，
  症状可能就是压根没搬）；已经用状态位/计数证明搬完了、错的却是"第一次对第二次旧"或"尾部半新半旧"，
  归 §3（cache 维护的方向与行粒度）。§3 那一节自己就写着"漏了的症状是'半新半旧'或首块/尾块坏"，
  两行的分工在这一问上，不在词汇上。
- **"PL 没做事"的三行按"哪一层没动"分**：写进去的字读不回、或读回来是对的而现象不变→
  `board-bringup.md` §4（五步把"到没到 PL"逐层数出来）；字读得回、`ip_dict` 里也有这个地址、
  `transfer()` 不抛异常，但效果没有→`zynq-pynq.md` §7（PS↔PL 三层各算哪一层）；
  **只有"控制侧全通、搬运/引擎侧一步不动"这一种形状**才先去 `zynq-pynq.md` §1 数那两路钟——
  它回答的是"这一路钟在不在"，前两行回答的是"这笔走到哪一层"，问的不是同一个问题。
- **"名字去哪查"的四类**：`PCW_*`（BD 里 PS 配置项）→`vivado-project-bd.md` §2.1；
  IP 的 VLNV/版本→同页 §2.1 的 `report_ip_status`；Python 侧运行时名字
  （`dir(pynq)`、`ip_dict`）→`zynq-pynq.md` §5，**名单本身**在 `pynq-overlay-development`；
  PS 侧 C 驱动 API（`XIxxx_` 那一族）不在本包，取法见 §6 的"驱动层"那一行。
  四类都叫"名字"，取法完全不一样，别用一类的办法去答另一类。
- **BD 那一组六行按"卡在哪一步"分**：源根本没进综合/编译顺序不对→§1；cell 改过名、下游
  `.hwh`/约束/PS 取 IP 全乱→§2；要把 BD 变成可重跑的脚本、查参数名、看 IP 版本状态或动 `upgrade_*`
  →§2.1；**自己的 RTL** 进了 BD 却连不上接口/拿不到地址→§2.2（PS 主口连 AXI4-Lite 从端被
  `BD 41-1285` 拒掉那一支也在这一节，它给的桥是 SmartConnect）；要交一份给 PS 侧（`.xsa` 整组）→§3；
  改完重新生成还是不生效（含"地址对不上"）→§4。"升级了 IP 之后地址段变了"跨三节：升级这个动作与
  状态表在 §2.1；**怎么算分配成功**按 §2.2 那张两行对象表取前后读数——看目标地址空间下面新长出来的
  `SEG_*` 段和它的 `OFFSET`，**不是**看你传进去的那条从端段（那条的 `OFFSET` 分配成功后仍是空、
  `USAGE` 两边同为 `register`，拿它当判据会一直判不通过）；取完对不上再去 §4 那张表（它给的两个成因是手动挪过段、
  导出用的是改之前那份）。
- **数"某个东西有几条/在不在"之前，先说清数的是哪个对象**：`.bd` 文件、`write_bd_tcl` 倒出来的脚本、
  还是 cell 在内存里的属性，是三个不同的对象，工具不会替你对齐。本机同一份设计在三个时刻取过这三个对象，
  给出的是三组数（文件里没有 / dump 里有 / `get_property` 读得到），
  把"文件里还没出现"读成"这一步没算出来"就会把功劳记给错的阶段——
  先看 `vivado-project-bd.md` §2.1 那张三行表再决定你要数哪一个。
- **设计侧的三种"空读数"分属三页，别互相顶替**：约束对象集合为空→`constraints-timing.md` §2；
  时序路径为空→同页 §4 第 4 条；例外表里自己那条整行消失→同页 §9。
  三者的修法不同，而工具在三种情况下都可能一副"没报错"的样子。
  第四种空读数不属于设计、属于工具自己：**`info commands <精确名>` 给 0 只表示"这个包此刻没加载"**。
  本机 `wait_on_run` 连 `auto_load` 都读 0，调用它却能走到
  `[Common 17-162] Invalid option value specified for '-runs'`；同一批 BD 命令在 `create_project` 之后
  仍读 0、只被**调用过一次**（哪怕失败在 `17-53 No open project`）就全部变 1。
  `hw_*` 那一族给的是一个可以直接抄的形状：本机把 15 个 `hw_*`/`get_hw_*` 名字在一个全新 batch 会话里
  数一遍是 **0/15 有名字**，`load_features labtools` 之后 **15/15**；而**没 `load_features` 的同一台机器上**
  第一条就调 `get_hw_ilas` 照样 rc=0（空串），调完之后 `info commands get_hw_ilas` 才有名字。
  所以"这条命令不存在"只认一个信号：`invalid command name "<名字>"`
  （三相位读数与取法在 `onchip-debug.md` §2；`hw_*` 这一族的 0/15→15/15 与那条空串反例在 §1）。
  **但反方向也有坑：命令名会被前缀认出来**，本机 `catch {save_project} e` 打的不是
  `invalid command name`，而是 `save_project_as` 的选项错
  （`[Common 17-163] Missing value for option 'name', please type 'save_project_as -help' …`），
  而同一次会话里 `[info commands save_project]` 是空的、`save_project_as` 有名字。
  **少打一截不会失败，会去执行另一条命令**——所以判存在性要用**完整且精确**的名字调它，
  名字短了得到的红/绿都不属于你以为那条命令（写探针脚本时同理：先 `info commands <全名>` 取
  候选列表，看到的不止一个就要改调用形式，别赌唯一前缀）。
  **第五种要单独记：探针脚本自己覆盖了一个同名的内建/工具过程**，症状是死在**下一行无关命令**上。
  本机那组对照是六行脚本（定义过程 → `read_verilog` → `synth_design` → `puts`），**只换过程名**：
  叫 `try` 时 `read_verilog` 报 `[Common 17-685] Unable to load Tcl app xilinx::xsim`、
  整个 batch rc=1、后面一条读数都没打印；叫 `tcall` 时同一份脚本 rc=0。
  防它很便宜：脚本里每个要定义的 `proc` 名先 `[info commands <名>]` 查一次，**有输出就是撞名**
  （`try` 在 Tcl 8.6.13 上返回 `try`），A/B 取法在 `vivado-build-run.md` §8。

同一句话可能同时像两行时，**先按能被推翻的那一侧查**：先确认抓来/烧进去的是这一次的比特流
（`onchip-debug.md` §3、`board-bringup.md` §1），再谈设计里的延迟。

## 5. 命令边界与不可逆动作

- **三套命令集别混。** ① Vivado 工程流程/硬件管理器 Tcl（`create_project`、`launch_runs`、
  `report_*`、`open_hw_manager`、`connect_hw_server`、`program_hw_cfgmem`）；② xsdb/Vitis 连
  hw_server 那一侧（`connect`、`targets`、`fpga -file`、`mrd`/`mwr`、`rst`）；
  ③ 仿真器批处理（`xvlog`/`xelab`/`xsim`、`vlog`/`vsim -do`）。报"不认这个命令"先怀疑跑错了控制台：
  本机在 Vivado Tcl 里 `mrd -help` 与裸 `mrd` 都报 `invalid command name "mrd"`（这才是"这条路径上没有"
  的读数），`help mrd` 那一路给 `[Common 17-25] No topics matched 'mrd'`——它只说明帮助主题里没有这条，
  不要拿它当 `-help` 的判决。
  两条具体的"名字不存在"：xsdb 2025.2.1 里**没有** `cfgmem`/`pcfgmem` 这条子命令
  （`invalid command name`），烧配置 Flash 走 Vivado 侧的 `program_hw_cfgmem`；
  `ps7_init` 也不是任何控制台的内建命令，它是 Vitis 生成的 `ps7_init.tcl`/`ps7_init.c` 里的过程，
  安装树里搜不到现成文件——要用它得先有那份生成物。
  硬件管理器那一族的命令（`program_hw_cfgmem`、`connect_hw_server`、`get_hw_targets`）
  在 `load_features labtools` 之后才注册（同上一条懒注册陷阱）。
- 长构建不要串行等：改代码的同时把上一版跑完；但**在飞构建期间不要动它的源**，也不要同名覆盖产物
  （`references/board-bringup.md` §5）。
- 需要现场确认后才能做：擦写 QSPI/配置 Flash、改板上调试器/FT2232 的 EEPROM、擦 SD 镜像或引导区、
  复位正被别人使用的板卡或 JTAG 通道、抢占已被占用的串口。为什么危险——擦除不可逆，且"板上跑什么"
  从此由启动介质决定。PYNQ 运行时侧还有两件同类的（往 `/sys/kernel/config/device-tree/overlays` 写、
  改启动镜像/板级设置），见 `pynq-overlay-development/SKILL.md` 的"危险动作"；两边清单合起来看，
  任何一边都不暗示另一边是安全的。
- hw_server 允许多个只读客户端；互斥的是**写类操作**与第二个 hw_server 进程。串口独占。
- 插调试核（ILA/VIO）是一次**网表变更**，插完之后构建要重跑一遍才算数：走 IP 那条路要重综合，
  走网表手术那条路本机只测到"综合之后插核 → 存盘 → 重开 → `implement_debug_core` → 出 `.ltx`"
  这一串，**整轮实现没跑过**（`references/onchip-debug.md` §2.1 末段把这条界线写明了）。
  所以两种路都要自己把完整构建再跑一遍才算交付版：**带探针那一次的读数不能替交付那一次签字**。

## 6. 边界：这几类问题本包不给答案，只给下一步

| 不答的 | 为什么不给 | 下一步怎么取 |
|---|---|---|
| 部分重配 / PR（DFNX、局部重配的加载与握手流程） | 命令与属性表随器件族变，本页只覆盖到 7 系列这一层的通用形状 | 在支持 PR 的 part 上开工程，用 `-help`/`report_*` 取本版本的表；成文侧读 UG908/UG995 原文 |
| Vitis 侧 app 工程、FSBL 源码生成、`xsct` 脚本面 | 那是 PS 软件开发那一层，本包只给到"启动镜像产物"这一层（`board-bringup.md` §2.1） | 在 `xsct` 里 `help` 取命令表；判命令存在性时注意"用法"一节说的懒注册陷阱 |
| PS 侧的存储器测试（boot ROM / FSBL 的 memtest 配置项、DDR 训练边界测试） | 属于固件配置那一层，本包只给"怎么写 pattern 才有覆盖"的口径（`board-bringup.md` §3 第 2 步），不代它列命令与开关 | 读 UG821（FSBL）与该板的 DDR 初始化设置，或在自己的 app 里实现带地址变化与大步长抽查的测试函数 |
| 用 Tcl 把 RTL 打包成 IP（接口定义、`xgui`、打包命令面） | 本包只核实到"模块引用进 BD 之后**没有接口**"这一步（`vivado-project-bd.md` §2.2）；打包那一族本机只核到"`ipx -help` 报 `invalid command name "ipx"`"这一条负读数，其余名字没逐个 `-help` 过（`info commands ipx*` 为空只是线索，按"用法"那条不算否定证据） | 用 GUI 的 Package IP；要写脚本就在要用它的上下文里逐条 `<命令> -help` 取一次名单，只有 `invalid command name` 才写"不存在"；接口 VLNV 用 `get_bd_intf_pins <现成IP>/*` 读真名，不要拼 |
| PS 侧 C 驱动 API 的**名单**（`XIxxx_` 那一族在这块板上到底有哪些） | 那是驱动层：名字由 XSA 里放了哪些 IP 决定，本包只给"哪些层要各自收证据"，没核实过安装树里可直接读的路径 | 在 Vitis 侧生成 FSBL/app 之后看 `xparameters.h` 与它引到的驱动源码——那份就是这一族的唯一清单；别按猜的安装路径写脚本，也别把别的板子的 `XI...` 名字搬过来 |
| 器件选型、IBIS/封装/电源完整性、板级布线 | 不在工具读数里 | 原理图 + 厂家手册，本包不替代 |
| 硬件本体故障（供电、上拉、烧掉的脚） | 工具看不见 | 先用 `board-bringup.md` §3 的读数把"软件侧/工具侧"分掉，再用万用表 |
| PYNQ 运行时（Overlay / 寄存器 / DMA / 中断 / 缓冲区 API） | 另一层 | `pynq-overlay-development`，从它 `SKILL.md` 的"§3 路由"进（那张表也是每行一个小节） |

## 7. 参考文件（按需读）

- `references/rtl-pipeline-cdc.md` — 延迟真源与探针实测、门控同拍、CDC 机制选择（翻转位速率上限、
  握手保持、异步 FIFO 满空生成域、格雷码位宽）、复位、隐式位宽与悬空/截断、综合期常量传播。
- `references/constraints-timing.md` — 时钟与派生时钟、每条约束自己出命中数、`set_false_path` 的真实
  射程与代价、报告字段读法与阶段归属（**含"`report_timing` 说没有路径而返回码仍是 0"`**）、
  要不要再来一轮、利用率、**物理与 IO 约束**、**约束文件的
  求值顺序与覆盖**（`report_compile_order -constraints`、`USED_IN`/`IS_ENABLED`/`SCOPED_TO_*`、
  生成物与多变体、豁免写宽的判据）、**时序例外三件套**（`report_exceptions` 的行存在性、
  `report_clock_interaction` 的两个方向、setup/hold 两笔）、**方法学与 DRC 的规则号怎么分级**、
  **不确定度与抖动**（`set_clock_uncertainty`/`set_input_jitter`/`set_system_jitter` 各要什么对象，
  以及 `Requirement` 为什么会随端点取法变）。
- `references/vivado-project-bd.md` — 文件集与编译顺序、BD 的验证与地址、cell 改名的连锁、IP VLNV
  与升级、**自己的 RTL 进 BD（模块引用只给平铺端口）**、`write_bd_tcl` 的自述定位、PS/IP 参数名怎么筛、
  导出整组配套、"改了没生效"对照表。
- `references/vivado-build-run.md` — run 对象模型、策略与 directive 怎么查当前版本的真值、
  用 `STEPS.*` 钩子让 run 自己交报告（**钩子收脚本文件路径**）、可重复性四件事、并行 A/B 的可行形状、
  交给同事的构建包、失败与竞态判读。
- `references/onchip-debug.md` — hw_manager 对象链与 JTAG 通道独占、`MARK_DEBUG` 的可达性只能逐个读回
  判、网表侧插核的命令族与那条**没板子也能跑通到 `.ltx`** 的顺序、VIO 在同一条路上的端口清单与它
  读不出来的那一格、`report_debug_core` 那张表什么时候才有判读价值、探针描述文件必须与比特流同批
  （要比时间戳，旧 `.ltx` 会让 `file exists` 假绿；而这一族只有写的命令、没有读内容的命令）、
  什么时候不该用在线调试。
- `references/verification.md` — 判定行是契约、参考模型独立性、层次覆盖到问题会出现的那一层、变异对照、
  X/Z 与未初始化、CDC bench 扫相位、黄金比对与容差、**RTL 绿不等于网表绿（网表仿真的库与 `glbl`/GSR 坑）**、
  最小跑批命令。
- `references/board-bringup.md` — 板上身份（有几块可单独重配就要几份读回号，重配后成对取读数）、
  JTAG/配置 Flash/运行时 overlay 三类区别、`bootgen` 的
  产物形状与"生成成功"能撑到哪、上电自检顺序、
  "设了没反应"分诊（含第 0 步"这笔写返没返回"）、把每道门变成可数的读回口、在飞构建竞态、ILA 代价。
- `references/zynq-pynq.md` — PS↔PL 三条通路各自怎么证、**同一个 IP 的时钟引脚各有几路、哪一路驱动
  哪个接口**、地址与 offset 单位、缓存维护与对齐、
  DMA 完成判据、Overlay 与 `.bit/.hwh/.xsa/.dtbo` 配套、位置偏 vs 颜色偏的分开分诊。

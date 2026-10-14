# 上板调试：ILA / VIO / hw_manager 与 JTAG 通道

覆盖"探针与在线读写"这一层。**代价**（要不要插、插了会改占用/布线/时序）这一页不给数——
量级那一组本机读数（一个 ILA + 自动 `dbg_hub` 在 7z020 上是 `10^3` 个 LUT/FF 这一档，
取数不需要板子，`report_utilization` 就够）在 `constraints-timing.md` §6，那里还写了那三行的适用边界；
"取证完要不要重出一版不含调试核的"这类规矩在 `board-bringup.md` §7。这一页只讲怎么把它开起来、
怎么确认看到的东西是这一次的。

## 1. 先确认对象链，再谈波形

Vivado 里从工具到板子是一串对象，每一环都可能连错，而且错法各不相同。

**下面"对象链"那几条要 `hw_server` 加板上器件；而注册时机与 `load_features` 的特性名不需要硬件，
在 batch 会话里就能核对**（这两类读数的成本差很远，别因为前半段跑不动就跳过整节）。
离线（没开 `open_hw_manager`、或没有 target）时
任何 `hw_*` 命令都先报
`ERROR: [Labtoolstcl 44-235] The labtools system is not initialized. You must execute 'open_hw_manager' to initialize the labtools system prior using this command.`
**在到达它自己的参数检查之前**就停住——所以离线只能核命令名与 `-help` 语法，
核不了"这个选项这么给行不行"。把下面这段当可跑清单之前，先确认你此刻有板子。

```tcl
open_hw_manager
connect_hw_server                      ;# 默认本机 hw_server；跨机器要 -url
open_hw_target
get_hw_targets                        ;# 看到几个 target？
get_hw_devices                         ;# 板上认到的器件（链上多个 FPGA/ARM 时必看）
program_hw_devices [get_hw_devices 点名一颗粒]
                                       ;# 别写 [get_hw_devices]：不带过滤就是把链上所有器件都给它
                                       ;# （这句按的是它的参数形状；多器件链是否同形要自己试出来）
close_hw_target
close_hw_manager
```

规则：

- **`connect_hw_server` 成功不代表你的板子在链上。** 判据是 `get_hw_targets` /
  `get_hw_devices` 的数量与名字，不是命令没报错。
- **一条 JTAG 通道上互斥的是写类操作（下载、擦写）与第二个 hw_server 进程；只读客户端可以共存**
  （口径见 `SKILL.md` §5）。抢不到时先列出谁在用（另一个 Vivado、`hw_server` 的另一个会话、
  Vitis/xsdb），**不要靠反复重连试探**——那会把对方会话搞成半死状态。
- **命令族分两种注册时机，别混。** ① `hw_*` 那一族（`open_hw_manager`、`get_hw_probes`、
  `read_hw_ila_data`）在新开 batch 会话里 `info commands` 查不到名字，`load_features labtools`
  之后才有。② 网表侧那一族（`create_debug_core`、`connect_debug_port`、`write_debug_probes`、
  `implement_debug_core`、`report_debug_core`）**在没 `load_features` 的新会话里就已经有名字**
  （本机在一个**没开工程、没 `load_features`** 的 batch 会话里 `read_verilog`+`synth_design` 之后
  直接跑通 `create_debug_core`/`connect_debug_port`/`write_checkpoint`）。
  两类都用 `<命令> -help` 当正向读数（`get_debug_ports`/`get_debug_cores` 只证网表侧的对象，
  `get_hw_probes`/`get_hw_ilas` 才对应 `hw_*` 那一侧，别拿前者当后者的存在性判据）。
  要判某条命令在这版存不存在，用 `<命令> -help`：要么印用法，要么报 `invalid command name
  "<命令>"`（`[Common 17-25] No topics matched` 是另一路 `help <命令>` 的报法，两种别混用）。
  同理，工程类命令（BD 那一串、`wait_on_run`）在没打开工程时 `info commands` 查不到名字，
  但 `create_bd_design -help` 那时也已经能打出用法（见 `SKILL.md` 的"用法"）。

  **上面 ①② 两条结论用的是 `info commands` 的正向读数，不是反向**："查到名字"⇒ 这条路径上确实
  已注册，这个方向可信；"查不到名字"什么都推不出（①那一族就是活例子：名字查不到而 `-help` 打得开）。
  所以这两条与"不要用 `info commands` 判存在性"不冲突——被禁止的只是拿**空结果**当否定证据。
- `load_features` 只认这几个特性名，写错会连清单一起给你：
  `[Common 17-220] No such feature 'netlist'. Available features are: hsi ipintegrator ipservices
  labtools simulator xhub`。要 BD 那一族用 `ipintegrator`，要硬件管理器/ILA 那一族用 `labtools`；
  **没有 `netlist` 这个特性**（不少脚本里写着它）。
- 一个工程里多个 `.bit`、或板上是菊花链时，`program_hw_devices` 的目标要**显式取**，
  不要接受默认第一个。
- 易失与持久要分清：JTAG 下载掉电即失（SD/QSPI 里的版本才会回来），见
  `board-bringup.md` §2。

## 2. 插探针是一次设计变更

`mark_debug` 一类的做法要点三件事：

1. 属性打在**网络**上（`set_property`），并且要确认这一层在综合后还在：改名、加 wrapper 之后
   层级变化会让探针落空（改 cell 名 → 实例名与按名写的约束全部连锁，见 `vivado-project-bd.md` §2
   第 2 条；wrapper 那一层见同节代码块里 `add_files …_wrapper.v` 那行的注释"wrapper 不加进文件集，
   综合看不见它"，以及紧随其后的 `make_wrapper` 选项解析那两句）。
2. 加了探针 = 改了网表 = **要重跑构建**，并可能改变时序结果。所以调试版与交付版
   是两个构建，别拿调试版的时序数字当交付结论（报告归属哪一次构建见 `constraints-timing.md` §4
   第 1、3 条；层级变了要回查约束命中是同页 §2）。
3. 探针的位宽与采样深度直接吃 BRAM。想抓满一帧与只想看一个跳变，是两个不同的配置，
   先想清楚要回答的问题再插。

属性是否可用、叫什么，用工具问而不是背：`list_property [get_nets <name>]` 里有没有
`MARK_DEBUG`，`list_property_value MARK_DEBUG [get_nets <name>]` 给的取值字面量是 **`1 0`**，
不是 `true/false`。判"标上了没有"= `get_property MARK_DEBUG` 读回 `1` **且**消息里没有

```
CRITICAL WARNING: [Chipscope 16-3] Cannot debug net 'clk'; it is not accessible from the fabric routing.
```

`set_property` 返回 0 不代表标记成功。**本机有两种"被拒"和一种"成了"，返回码全都是 0**：

| 打在网络上的名字 | `set_property MARK_DEBUG 1` 的返回码 | 读回 | 消息里 |
|---|---|---|---|
| `clk`（全局时钟网） | 0 | `0` | `CRITICAL WARNING: [Chipscope 16-3] Cannot debug net 'clk'; it is not accessible from the fabric routing.` |
| `q[3]`（寄存器的某一位） | 0 | `0` | 同一条 `16-3`，名字换成 `q[3]` |
| `clk_IBUF`（普通布线网） | 0 | **`1`** | 无 |

所以判据只有读回值这一条。**括号里那份"它是什么"是本机事后写的说明，不是工具给的理由**：
工具在这一格给的全部信息就是 `16-3` 那一句 `not accessible from the fabric routing`。
**可达与否是逐网判的，名字的形状预测不了结果**：同一份综合后的网表里，
本机把 `clk_IBUF_BUFG`、`rst_IBUF`、`p_0_in[0]` 三个名字都设成功并读回 `1`（带方括号的位名也能成），
而 `clk` 与 `q[3]` 都读回 `0` 并各留一条 `16-3`。
**也不要照 RTL 的名字猜网表的名字**：那份设计里根本没有 `q_reg`、`q_reg[0]`、`q_reg[7:0]` 这些网络
（`get_nets -quiet` 一律返回 0 个），寄存器的位是以 `q[0]…q[7]` 的形式出现的。所以顺序必须是
先 `get_nets *` 枚举、再逐个设、逐个读回——"枚举"这一步就是判据的来源。
**而"对空集合取属性"不是拿到空值，是把整个脚本打死**：本机对一个 `get_nets -quiet` 枚举不到对象的网名
继续取 `MARK_DEBUG`，得到 `ERROR: [Common 17-55] 'get_property' expects at least one object.`（后面还带一条
`Resolution: If [get_<value>] was used to populate the object...`），**batch 会话当场退出**，
后面十几条读数一条也不会打出来。所以逐个读回之前要先 `llength` 判这次到底取到了对象；
批量脚本里每一条 `get_property` 都包 `catch`，否则你失去的不是这一格读数，是全部读数
（`SKILL.md` §1 第 9 条说的"读不到就写 `NOT RUN`"，在这种截断下最容易变成"没打印＝通过"）。
**同一个编号会出现在两种角色里，别看编号判断严重程度**：`[Common 17-55]` 本机也取到
`can't read "wr_clk_period": no such variable` 那种——它是工具处理自己生成的 xdc 时打的，
一次构建里能数出 10 条而**会话照常跑完**（§2.1 那三行读数就是这么来的）。
决定会不会截断的是"这条错误有没有从脚本顶层抛出"，不是编号。
写 `true`/`false` 也接受，读回会归一成 `1`/`0`（`list_property_value` 给的合法字面量就是 `1 0`）。
要数"这次到底标了几个"，用集合而不是数日志——**那条命令与它的三种过滤写法都记在
`rtl-pipeline-cdc.md` §5 末尾那段**（连同"`-quiet` 只影响日志卫生、判据是 `llength`"的理由与正向对照），本页不重抄一遍。

### 2.1 核是怎么进网表的（两条路，命令名本机核过）

**版本与名字都要现取**，别写死：

```tcl
get_ipdefs -filter {NAME =~ *ila}
;# 本机给三条：xilinx.com:ip:axis_ila:1.3  xilinx.com:ip:ila:6.2  xilinx.com:ip:system_ila:1.1
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_0
;# 不给 -version 就取默认版本，返回 .xci 路径；这一步是"工程里有核"
```

另一条路是直接对**已综合的网表**动手术，这一族命令在本机都存在（且不需要 `load_features`，见 §1）：
`create_debug_core`、`create_debug_port`、`connect_debug_port`、`connect_debug_cores`、
`disconnect_debug_port`、`delete_debug_core`、`delete_debug_port`、`modify_debug_ports`、
`report_debug_core`、`implement_debug_core`、`write_debug_probes`。
本机 `-help` 打出来的语法行（**照这个抄，别照博客抄**）：

```
create_debug_core   [-quiet] [-verbose] <name> <type>
connect_debug_port  [-channel_start_index <arg>] [-quiet] [-verbose] <port> <nets>...
modify_debug_ports  [-probes <args>] [-quiet] [-verbose]
```

`connect_debug_port` 的 `<nets>...` 是**必填的位置参数**，语法行少抄一个就变成"命令存在但用不了"；
`-method` 这个选项在这版**已经没有了**（`ERROR: [Common 17-170] Unknown option '-method'`），
网上老脚本里 `modify_debug_ports -method ...` 那一行要改。
`report_debug_core` **不接受位置参数**：`report_debug_core u_ila_dbg` 报
`[Common 17-165] Too many positional options when parsing 'u_ila_dbg'`——裸调它就把整个设计里
所有核的参数表与 channel 表打出来（列里有 `MARK_DEBUG` 与 `Net Name`）。
**但别把那张表当成连接判据（本机的一份读数就是反例）**：在 `implement_debug_core` **之前**取它，
即使 `connect_debug_port` 一个字没报错、`MARK_DEBUG` 与 `Net Name` 两格也还是空的——核这时还是
"建了没落地"的状态（就是 §2.1 里那条 `12-5829`（核建了但没 implement 那一坑）的同一件事）。所以顺序是：
先按 §2 的读回判"网可达"，落地之后再取一次这张表，才有判读价值。
`connect_debug_cores` 的选项表取到了（3756 字符）：语法行是
`connect_debug_cores -master <args> -slaves <args> [-quiet] [-verbose]`，说明是"把 debug slave 核
连到 master（debug bridge / debug hub，且 master 要配成 From BSCAN To DebugHUB 模式）"，
并且**只能连同一 region 里的主从**（PR 场景下这条会限制你能连谁）。
它解决的是"核已经建好、要把整批 slave 挂到 hub"，与 §2.1 那条逐个 `connect_debug_port` 不是同一层——
**它的用法没有可抄的来源**：`-help` 只给你选项表与"同 region 主从"这条限制，没有示例。
第一次用要在自己的设计上跑一次连接，然后回读拓扑确认它真挂上了。

**可行的顺序**（不主张步骤最少；这串在没有硬件的会话里按序可行，终点是一份真存在的 `.ltx`；
⑤ 属于另一条路上的读数点；两条臂的差别只在 ⑦。
注意只跑到 ⑩ `implement_debug_core` 就停**不会产出 `.ltx`**——那种走法取的是占用三行，
那组数与它的适用边界在 `constraints-timing.md` §6）：

```tcl
read_verilog ./cnt.v                          ;# ① 或者 open_checkpoint / open_run 之后
synth_design -top cnt -part <你的 part>       ;#    拿到"打开的网表"
set_property MARK_DEBUG 1 [get_nets clk_IBUF] ;# ② 读回必须是 1（§2 上面那条）
create_debug_core u_ila_dbg ila               ;# ③ dbg_hub 会被自动加进来
get_debug_ports                               ;# ④ 取小写名字：本机三条——u_ila_dbg/clk、u_ila_dbg/probe0、dbg_hub/clk
create_debug_port u_ila_dbg probe             ;# ⑤ 要第二个槽位才需要（打回的名字形状见下面 VIO 那条）
connect_debug_port u_ila_dbg/probe0 [get_nets -hier -filter {MARK_DEBUG == 1}]
                                              ;# ⑥ 连到刚标上的那批网
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
                                       ;# ⑦ 连**缓冲后**的钟网。连顶层 `clk` 时连接同样静默，
                                       ;#    而 implement 有时过有时不过（下面那条 A/B 统计是全部四次）
write_checkpoint -force ./post_synth.dcp      ;# ⑧ 存盘——"存出文件"本身还不够
open_checkpoint ./post_synth.dcp              ;# ⑨ 重新打开它才算"已保存的设计"
implement_debug_core                          ;# ⑩ 核进入网表（日志出现 dbg_hub_CV/u_ila_dbg_CV）
write_debug_probes -force ./design             ;# ⑪ 产出 design.ltx；判据见 §3
```

五条只有跑过才知道的形状：

- ⑧ 之后直接 ⑩ 会被拒：`ERROR: [Common 17-69] Command failed: Design needs to be saved before
  implementing debug cores.`——**`write_checkpoint` 写出一个文件并不满足它**，本机是靠 ⑨
  `open_checkpoint` 重新打开同一份 dcp 才过去的。工程流程里对应的说法是把它放到 `opt_design`
  之后（那条路本文未验证，别默认它与上面等价）。
- ⑨ 之后 `get_debug_cores` 仍然给 `dbg_hub u_ila_dbg`：核信息与标记是随 dcp 走的，
  不需要在重开后重建。
- **⑦ 要连的应当是"缓冲之后"的那个钟网；而"连错会不会当场告诉你"没有可靠判据**——
  同一份设计、同一条十一步，`dbg_hub/clk` 分别连顶层输入网 `clk` 与 `clk_IBUF_BUFG`，累计读数是这样：

  | `dbg_hub/clk` 连到 | `connect_debug_port` | 走到 `implement_debug_core` | `.ltx` |
  |---|---|---|---|
  | `clk` | 不报错 | **4 次里 1 次失败、3 次通过**。失败那次给 `ERROR: [Common 17-69] Command failed: Implement Debug Core has failed.`，前面还有一条 `ERROR: [Chipscope 16-578] Check "…/dc_drv.0/vivado.log"` | 失败那次没有（只剩 `17-39` 下游）；通过那三次都产出 |
  | `clk_IBUF_BUFG` | 不报错 | 通过（返回码 0；**结果串**是 `CDC-15#11`，`catch` 第二个变量拿的是结果不是错误号） | 产出 |

  三条读数都要带走：① **两臂的 `connect_debug_port` 都静默**，这一步不能靠"没报错"判；
  ② **`clk` 那一臂是"有时候会过"**——这是最坏的一种不确定：过一次，人就会把它当正确做法。
  所以本页只能主张"连 `clk_IBUF_BUFG`，并在自己的设计上跑到 `file exists` 再认"，
  **不能主张"连 `clk` 必然失败"**（本机证不了这句，早期那次失败的成因至今没找到）；
  ③ 那族 `17-55` / `17-1548` 告警（`xsdbm_cc_late_late.xdc`、`can't read "wr_clk_period"`）
  **两臂都是 10 条，一条没消**——与 ⑦ 连没连无关。这一族的 `17-55` 消息文本是
  `can't read "wr_clk_period"`，**与 §2 那条 `expects at least one object` 只是同编号、不同事**：
  它们是工具内部打的、会话活得下来；从你脚本顶层抛出的那类才会截断。那次实验的设计里没写任何 `create_clock`，
  所以最合理解释仍是"生成的 Debug-Hub 约束在解析一个不存在的基准钟"，
  **但这句还是推的**：要证它，给自己有 `create_clock` 的设计取同一组数。
- **ILA 核自己也有一个 `clk` 端口，而这条十一步没连它——它照样全绿。** 本机只建一个 ila 核之后
  `get_debug_ports` 给**三条**：`dbg_hub/clk`、`u_ila_dbg/clk`、`u_ila_dbg/probe0`；
  上面那串只连了 hub 那一路与探针那一位。落地之后 `implement_debug_core` 返回 `CDC-15#11`、
  `.ltx` 照样产出（本机那份是 1737 字节 / 48 行），而读回来的 `pins[]` 里**只有 `probe0` 一条**。
  也就是说 **`u_ila_dbg/clk` 空着不会让这条链子在任何一步报错**。它会不会让上板抓不到波形，
  只能上板判；所以这一格别留给运气：把三条端口都列出来，该连的逐个连上、
  逐个 `puts` 记账——这与上面 `PORT_WIDTH` 那条是同一类坑（工具不催你，形状还各不相同）。
- 按 §1 的口径，那类告警要按**条目数**数（`SKILL.md` §1 第 1 条）。

六个实测到的坑：

- **端口名是小写的。** `get_debug_ports` 给 `u_ila_dbg/probe0`、`u_ila_dbg/clk`、`dbg_hub/clk`；
  照 Xilinx 文档示例里的大写 `CLK` 去连，第一步是**静默的**：
  `WARNING: [Vivado 12-1423] No ChipScope debug ports matched 'u_ila_dbg/CLK'.` 返回 0，
  真错在下一句 `connect_debug_port` 里：`ERROR: [Vivado 12-1420] Debug port '' was not found.`
  所以先 `get_debug_ports` 取名字、再拿 `llength` 当判据，不要照抄任何文档里的大小写。
  **也别把这条推广到全工具**：BD 那一族的通配是**不分大小写**的——本机 `get_bd_pins dma0/*CLK*`
  照样取回四条全小写的 `*_aclk`（见 `zynq-pynq.md` §1）；同一时刻调试端口这一族对大写 `CLK`
  一个都不匹配。大小写敏不敏感是**按命令族试出来的**，不是一条规律推全部。
  另一个同形状的静默：`get_debug_ports u_ila_dbg`（拿核名当过滤）**返回空集合**并打
  `WARNING: [Vivado 12-1423] No ChipScope debug ports matched 'u_ila_dbg'.`——
  要列某个核的端口，从裸 `get_debug_ports` 的清单里按 `NAME` 挑，别指望位置参数。
- `create_debug_core` 要**打开的网表**（其 `-help` 自述 "can only be added to an open netlist design"）。
  本机在"综合到内存、没上板"的设计里跑通：返回核名，`get_debug_cores` 给出 `dbg_hub u_ila_dbg`
  （Debug Hub 自动加进来，实际类型是 `labtools_xsdbm_v3`，而工具自己的帮助文本还写着 `v1`）。
- 调试端口的属性清单是**逐端口**的，不是一张全局表。数据探针那一族本机读到
  `CLASS NAME PORT_WIDTH PROBE_TYPE` 四条——**没有 `CONNECTED_TO`/`NETS`/`WIDTH`
  这些想当然的名字**（写了报 `[Vivado 12-4442] Invalid property name CONNECTED_TO. Use the
  'list_property' command...`）。四条都可读：本机新建的 `u_ila_dbg/probe0` 是 `CLASS=debug_port`、
  `PORT_WIDTH=1`、`PROBE_TYPE=DATA_AND_TRIGGER`。而 **`dbg_hub/clk` 上就没有 `PROBE_TYPE`**：
  对本机 `get_debug_ports` 的清单里那一个端口取它，报
  `[Vivado 12-4442] Invalid property name PROBE_TYPE. Use the 'list_property' command to find
  properties supported by the debug_port dbg_hub/clk object`——**这条 ERROR 不包 `catch` 就会把
  batch 脚本从那一行截断**（本机第一次撞它就是这个下场：循环里第二个端口撞上它，后面十几条读数一条
  也没打出来）。**换个写法同一批读数就全拿到了**：每条 `get_property` 都包进 `catch` 之后，本机对
  三个端口逐个取一个不存在的属性名，每个都正常返回那段错误文本而不是中断会话（下面 VIO 那条就是那次）。
  所以批量取属性只有两种安全写法：逐条 `catch`，或先对**这个对象** `list_property` 再按清单取。
  **"探针连上了哪个网"没有属性可读，而两条后备路都比想象中弱**（本机实测）：
  `report_debug_core` 有一次在 `implement_debug_core` 之后**整段返回空**（0 行，也不报错）；
  `.ltx` 是 **JSON**（`open`+`read` 读回来过：`ltx_root.ltx_data[].debug_cores[]` 里每个核带
  `type`/`name`/`uuid`/`pins[]`，pin 带 `name`/`id`/`type`/`direction`/`nets[]`），
  可 `nets[]` 里写的是 `u_ila_dbg/probe0[0]` 这种**核内名字**，不是你连进去的设计网名。
  所以这一格既不能靠属性、也不能靠这两条后备路：**把网名在连接那一步自己 `puts` 进日志**，
  这是本页能给的唯一稳妥做法（读 `.ltx` 本身要回到 shell/Tcl 的 `open`，见 §3 那条"只有写的命令"）。
- **`PORT_WIDTH` 是会咬人的那条读数**：本机把 `connect_debug_port` 连到 1 位网上它仍是 `1`，
  `create_debug_port` 新建的 `probe1` 也是 `1`，**连一个 8 位网不会把它变成 8**（这条路没有自动加宽
  这回事，`create_debug_port` 也没有宽度参数）。所以"我要看一整组 8 位"在这条路上
  没有隐式的解：要么每位一个槽（`probe0…probe7`，逐个 `create_debug_port` 再逐个连），
  要么走 IP 那条路按名字设宽（`CONFIG.C_PROBE<k>_WIDTH`，本机在 IP 路径上验证过设 4 读回 4）。
  第三条路 `modify_debug_ports -probes <args>` **只到选项表为止，用法不能照抄**：
  语法行是 `modify_debug_ports [-probes <args>] [-quiet] [-verbose]`，描述写的是
  "Modify **routed** probe connections to debug cores"（**它管的是已布线之后的改连**，
  与建核时连探针不是同一件事）；把核端口当位置参数传进去直接得
  `[Common 17-165] Too many positional options when parsing 'clk_IBUF_BUFG'`——**这条命令没有位置参数**。
  `-probes` 的取值说明在 `-help` 的表里被截断（只到 "debug core pin, channel index,"），
  所以它能不能一次改多位、与逐个 `create_debug_port` 的效果是否同形，仍要在自己的设计上试出来再写进流程。
  判"槽宽够不够"就读 `get_property PORT_WIDTH <端口>`——**别拿"连上没报错"当依据**：
  连一位上去同样不报错，症状是抓到的值永远只有一位。
- 核"建了但没 implement"时 `write_debug_probes` 是 **rc=1**：
  `ERROR: [Vivado 12-5829] Unable to generate LTX file since debug core UUIDs are unavailable for
  unimplemented cores.` 与"完全没有核"（rc=0 且不落文件，见 §3）是两种不同的失败，别混。
- **VIO 走的是同一条网表手术路，但它的端口清单与 ILA 不一样**（本机在同一份综合后的 `cnt` 网表上）：

  ```tcl
  create_debug_core u_vio_dbg vio        ;# 打回 u_vio_dbg；dbg_hub 照例被自动加进来
  foreach p [get_debug_ports -quiet] {   ;# 本机 3 条：dbg_hub/clk、u_vio_dbg/clk、u_vio_dbg/probe0
    puts "AC|name=<[get_property NAME $p]> props=<[list_property $p]>"
  }
  create_debug_port u_vio_dbg probe      ;# 打回全名 u_vio_dbg/probe1
  ```

  三条读数：

  1. **钟端口（`dbg_hub/clk`、`u_vio_dbg/clk`）的属性清单是 `CLASS NAME PORT_WIDTH` 三条，
     数据探针才是四条**（多一个 `PROBE_TYPE`）——这就是上面"属性清单是逐端口的"那条的出处。
  2. `DIRECTION` 在这三个端口上**一个都没有**（本机逐个取过，一律 `12-4442`），所以"这个 VIO 位是
     板端输入还是输出"在 Tcl 侧读不出来，只能按你建它时的意图与硬件管理器那一侧对齐。
     这是本页关于 VIO 的一个真实缺口：**怎么把输出位接到设计里的某个驱动，要在自己的设计上试一次才定得下来**。
  3. `create_debug_port u_vio_dbg probe` 打回的是**全名** `u_vio_dbg/probe1`（不是短名 `probe1`），
     所以新增槽位之后重新 `get_debug_ports` 认名字，别拿返回值去拼路径。

  **这一条只主张到"核建得出来、端口清单长这样"**：本机那次在往下走到 `implement_debug_core`
  之前就被上面那条 `17-55` 截断了（一个未包 `catch` 的 `get_property`）。所以不要把 ①…⑪ 那串
  当成"vio 也一路通"的证据——它在 vio 上验证到的只到 ③④⑤。

**这条路要不要回到综合重跑一次？** 本机走出来的形状是"**综合 → 标记 → 建核 → 连 → 存 → 重开 →
`implement_debug_core` → 写 `.ltx`**"，中间**没有**"再综合一次"这一步（`MARK_DEBUG` 是在
`synth_design` 之后才设的，核也是那时才建的）。但这只说明**命令顺序可行**：那份 `.ltx` 来自一个
没跑实现的网表，与任何比特流都不同批（§3 的判据正是要卡住这件事）。所以交付流程里插了核还是
要把实现跑完，而"跑实现时核由谁插入"（`opt_design` 自动做，还是这里手写）没有对照实验可依，
在自己的构建上取一次 `report_utilization` 与 STATUS 再下结论。

**这些名字不存在**（`-help` 都报 `invalid command name`）：`gen_debug_core_sinks`、
`read_hw_debug_cores`、`close_hw_debug_files`。正向对照同一次跑：同一批读数里
`info commands` 对 `create_debug_core`、`connect_debug_port`、`implement_debug_core`、
`write_debug_probes`、`report_ip_status` 各给 **1**（`-help` 返回码 0），
`info commands *debug_core*` 还列出 `connect_debug_cores`、`delete_debug_core`、`get_debug_cores`、
`report_debug_core` 共 6 个——**看得见名字的那次扫描同时看不见这三个**，所以"没有"是读数不是猜。
再加一条更狠的：`info commands *hw_debug*` 交出 **0 个**（`*close_hw*` 只交出 `close_hw` 一个），
所以"`…_hw_debug_…` 这一族"在 Vivado 批处理里不是漏了几个名字，是整族不在。

### 2.2 抓取与触发：命令是 `run_hw_ila` / `wait_on_hw_ila`

下面这些名字逐个 `-help` 都打得出用法（在 `load_features labtools` 之后的会话里问的）；
这份清单的意思是"**这几条在**"，**不声称"这版只有这些"**（`info commands` 那种封闭清单不可作凭）：

**为什么"不可作凭"，把它测出来了。** `info commands <精确名>` 给出 0 **不等于"这条命令不存在"**，
它只说明"这个包此刻还没被装进命名空间"。本机按三个相位逐一取过：
`create_bd_design`、`connect_bd_net`、`validate_bd_design`、`assign_bd_address` 在裸会话读 0，
`create_project` 之后**仍然读 0**，而**只要调用过一次**——哪怕那一次失败在
`[Common 17-53] User Exception: No open project…`——同一批名字立刻变 1
（`*bd_*` 的 glob 计数在同一台机器上依次是 **3 → 58 → 61**，所以"扫得到多少"本身也是相位的函数）。
硬件管理器那一族同理：`connect_hw_server`、`open_hw_target`、`program_hw_cfgmem`、`get_hw_ilas`、
`run_hw_ila` 先都读 0，调用一次 `connect_hw_server`（它失败在
`[Labtools 44-235] The labtools system is not initialized. You must execute 'open_hw_manager'…`）
之后五个一起变 1。`auto_load` 也补不全：把两份文档 ```tcl 代码块里出现的 **71** 个命令名逐个问一遍，
70 个能经 `info commands` 或 `auto_load` 落实，**唯独 `wait_on_run` 两条路都读 0**，
而调用它得到 `[Common 17-162] Invalid option value specified for '-runs'`——**命令在，是我的参数不对**。
于是判"这个名字不存在"的**唯一信号是 `invalid command name "<名字>"`**
（本机 `program_cfgmem`、`ipx`、`export_bd_tcl`、`md5sum` 走的都是这一条），不是计数为 0。
想验"在不在"也别真去调用一条会做事的命令：用 `eval $name` 批量试探时**真的执行了一次
`add_files`**（回 `[Vivado 12-403] No files or directories specified`）并把批处理打断在那里，
后面 70 个名字一个都没问成——要只解析不执行就用 `auto_load`。

```
apply_hw_ila_trigger  current_hw_ila  current_hw_ila_data  get_hw_ilas  get_hw_ila_datas
read_hw_ila_data  reset_hw_ila  run_hw_ila  upload_hw_ila_data  wait_on_hw_ila
write_hw_ila_data  display_hw_ila_data
```

**没有 `arm_hw_ila_trigger`、`run_trigger`、`current_hw_trigger`、`get_hw_ila_cores`**
（网上与旧脚本里常见这几个名字；本机 `-help` 一律报 `invalid command name "<那个名字>"`（这类逐条否定本机都是包在 `catch` 里取的——不包的话第一条 ERROR 就把会话截掉，剩下的名字你根本没问到），
不是 `[Common 17-25]`——那一句是 `help <名字>` 那一路的报法）。
**这四条的同一次正对照**：`info commands *hw_ila*` 交出 12 个名字（`apply_hw_ila_trigger`、
`current_hw_ila`、`current_hw_ila_data`、`display_hw_ila_data`、`get_hw_ila_datas`、`get_hw_ilas`、
`read_hw_ila_data`、`reset_hw_ila`、`run_hw_ila`、`upload_hw_ila_data`、`wait_on_hw_ila`、
`write_hw_ila_data`），`info commands *trigger*` 在全命令空间里只交出 1 个（还是
`apply_hw_ila_trigger`）——**扫描看得见别的名字时这四个是 0，才叫"没有"**；
而且要的不是"这版只有这些"那种封闭清单（可见集合随 `load_features` 变），要的是"这条在不在"。
名字也别按后缀猜：这一族里存在的是 `get_hw_ilas`，**不是** `get_hw_ila_cores`。
所以一次抓取的正确形状是**七步**，缺一步就落在"对着工具自己认为 current 的那个核起抓、
而且从没布过触发"上：

```tcl
get_hw_ilas              ;# ① 认对象（可能不止一个核）
current_hw_ila           ;# ② 必要时显式指定，别接受默认
apply_hw_ila_trigger     ;# ③ 布触发条件
run_hw_ila               ;# ④ 起抓
wait_on_hw_ila           ;# ⑤ 等这一次抓取结束（判"等到没有"就用它）
upload_hw_ila_data       ;# ⑥ 取回数据
write_hw_ila_data        ;# ⑦ 落盘（.ila/.csv/.vcd）
```

①…⑦ 这七条都能 `-help` 打出用法；**顺序与"谁是等待者"只能按各自帮助文本的描述排**——
离线时它们全部停在 `44-235`（§1 开头），所以第一次连上板子时要逐个跑一遍，再固化进脚本。
落盘是 `write_hw_ila_data`。本机 `-help` 的语法行是

```
write_hw_ila_data  [-force] [-csv_file] [-vcd_file] [-legacy_csv_file] [-quiet]
                   [-verbose] <file> [<hw_ila_data>] [<hw_ila_data>]
```

`<file>` 在前、`hw_ila_data` 是**可选且可重复**的（帮助文本说不给就取当前那份数据——**这是描述，
不是本机测到的行为**），别把第二个 token 抄成
`<hw_ila_data_object(s)>...`；要 CSV/VCD 用那两个开关，别自己转（帮助原文：默认扩展名
`.ila`，`-csv_file` 默认 `.csv`，`-vcd_file` 默认 `.vcd`）。
**"不给 `<file>` 会报缺参数"这句离线证不了**：没有 labtools 会话时它在参数检查之前就停在
`[Labtoolstcl 44-235]`（见 §1 开头）——所以参数级行为要么有板子要么别写。
判"触发有没有等到"用 `wait_on_hw_ila`，别用 `sleep`+看一眼：那正是 `board-bringup.md` §5
说的"等待本身不是判据，`wait_on_run` 之后仍要读 STATUS"在抓取这一侧的同一件事。
`run_hw_ila -file` 是另一样东西（它的 `-help` 文本写着 trigger-at-startup、不给扩展名时补 `.tas`）；
这是**帮助文本的内容**，离线到不了参数检查（§1 开头），别当实测行为搬用。也别和 `.ila` 数据文件混。

核的配置能读也能写（本机）：`set_property CONFIG.C_PROBE0_WIDTH 4 [get_ips ila_0]` 读回 4。
**探针个数那个属性叫 `CONFIG.C_NUM_OF_PROBES`**（有 `OF`；`CONFIG.C_NUM_PROBES` 不存在）。
**不要用"`list_property` 之后过滤 `CONFIG.*PROBE*`"数槽位**：本机 `ila:6.2` 这样过滤出
**3076** 条（`C_PROBE0..C_PROBE1023` × `_WIDTH`/`_TYPE`/`_MU_CNT`，再加 4 条），
那是最大槽位表不是已用数量；已用的数量读 `CONFIG.C_NUM_OF_PROBES`（默认 1），
实际连上去的探针用 `get_debug_ports` 的数量判。
**问一个不存在的 CONFIG 名字，拿到的未必是"没有这个属性"**：本机 `get_property CONFIG.C_NUM_PROBES`
回的是 `ERROR: [Common 17-39] 'get_property' failed due to earlier errors.`——这句是外壳，
真因在它上面那一条；名字对不对要用 `list_property` 的清单判，不是用这条报错的措辞判。
VIO 那一侧的对象命令是 `get_hw_vios`（本机存在）；只是判"某个位在不在动"，用 VIO 比插 ILA **通常**便宜（**这个成本差要自己量**：本页只对 ILA 的占用有数，见 `constraints-timing.md` §6；别把它当成选型依据，要就在自己的设计上各建一版取差值） 便宜。

## 3. 读回来的数据要能证明是这一次的

```tcl
clock seconds                      ;# 起点要在这一步之前取（用法见本节末规则列表第二条）
write_debug_probes -force ./dbg/design.ltx ;# 文件名是位置参数；路径按下面规则与 .bit 同目录同前缀
file exists  ./dbg/design.ltx      ;# 0/1；三行 file 命令里只有它不因"文件不在"而报错
file mtime   ./dbg/design.ltx      ;# epoch 秒（本机取到 1791980135 这一类）
file stat    ./dbg/design.ltx s    ;# s(mtime)/s(size) 一起取；完整键名见下一段
get_hw_ilas                        ;# 这条要 §1 那一串先跑通（有板子）；别把整段贴
```

`file mtime`/`file stat` 在本机可用，而 **`md5sum` 不是 Vivado 的 Tcl 命令**
（`invalid command name "md5sum"`）——**正对照是同一条扫描**：`info commands *md5*` 交出 **0 个**，
而同一类扫描问 `info commands *cfgmem*` 在没加载 `labtools` 的裸批处理会话里交出 **1 个**（`write_cfgmem`）、
`load_features labtools` 之后交出 **8 个**（逐条名单见 `board-bringup.md` §2 那一行）——
**两个读数都非 0，所以 `*md5*` 那个 0 是"这一族不在"，不是"这次没扫到"**。
要在 Tcl 里比"是不是的产物"，取 `mtime`+`size` 这一对，
真要比哈希得回到 shell 侧（`board-bringup.md` §1 那套）。

两条只有把这几句真敲一遍才会遇到的形状：

- **`file mtime` 与 `file size` 在文件不存在时是 ERROR，不是 0**：本机对一条不存在的路径取到的是
  `could not read "./w/nope.ltx": no such file or directory`，而同一句的 `file exists` 与 `file writable`
  都回 `0` 且不报错。**所以顺序是先 `file exists` 再 `file mtime`**——反了的话脚本在那一行死掉，
  你拿到的是"判据没打印出来"，最容易被人读成"检查过了"（`SKILL.md` §1 第 9 条那一类）。
- `file stat` 给本机这一套键：`atime ctime dev gid ino mode mtime nlink size type uid`——
  **是 `mode` 不是 `perm`**，按习惯写 `s(perm)` 取到的是 `can't read "s(perm)": no such element in array`。
  `mtime` 只有**秒级**（本机隔 1.2 s 写的两个文件，两个 mtime 相差 1）。

前五行的对象都在**工程/网表会话**这一侧（`clock`/`write_debug_probes`/`file`），最后一行属于 `hw_*` 那一侧、要 `open_hw_manager` 之后才有对象——
一个会话里整段贴上去，最后一行只会拿到 `44-235`。

工具这边的名字要按它给的来用。本机 `write_debug_probes -help` 的语法行是

```
write_debug_probes  [-cell <arg>] [-no_partial_ltxfile] [-force] [-quiet] [-verbose] <file>
```

`-cell` **带参数**（给个不存在的实例名报
`ERROR: [Vivado 12-4881] Invalid value for option -cell, unable to find any cell with hierarchal
instance name ???<名字>`），打印的选项表里**没有** `-file` 这一项。但论坛里常见的 `-file <路径>`
实测也返回 0——**别把"没报错"读成"支持"，也别把它解释成"解析器吞掉未知选项"**：本机同一句给
`-zzqtest` 会报 `[Common 17-170] Unknown option '-zzqtest'`，给 `-file` 不报，而当时设计里没有核、
两种写法都不落文件，所以这份数据分不开"被接受"与"被吞"。能站住的是另一条读数：
**裸调 `write_debug_probes`（一个参数都不给）报 `[Common 17-163] Missing value for option 'file'`**
——说明位置参数 `<file>` 底层就是一个名为 `file` 的选项。结论一句：**`file exists` 单用不构成判据，
成立的是三条一起**——带 `-force` 写、`file exists` 为真、`file mtime` 落在窗口里
（窗口怎么取、以及"同目录同前缀"为什么恰好会让第一条假绿，都见下面规则列表第二条）。
写法用位置参数；不带 `-force` 且目标已存在时会怎样没有定论，所以别把它当默认安全项——要么显式带
`-force`，要么在自己的设计上先试一次再决定。
`-file` 能不能用不取决于某一次没报错。
产物扩展名是 `.ltx`（帮助原文："Debug probes file name (default extension is .ltx)"，
**并且本机实测到**：跑完 §2.1 的 ⑩ 之后给 `write_debug_probes -force ./noext`，返回
`.../noext.ltx` 且该文件真存在——扩展名是工具补的，不是它报错）。
ILA 数据是 `.ila`（`read_hw_ila_data`/`write_hw_ila_data` 的帮助都写明缺省扩展名 `.ila`）。
这一族 `-help` 里出现过的缺省扩展名只有 `.ltx`、`.ila`、`.csv`、`.vcd`、`.tas`；
别的资料里的 `.ldebug` 没在这版的 `-help` 里读到（本机没做全盘文件名搜索，别把这句当"不存在"）。

数据面同理，`read_hw_ila_data` 读的是**文件**，不是硬件：

| 想做的事 | 用哪个名字 | 依据 |
|---|---|---|
| 列会话里的 ILA | `get_hw_ilas` | `read_hw_ila_data` 的 See Also 一栏 |
| 从板上取一次触发后的数据 | `upload_hw_ila_data` | 同上 |
| 把取到的数据落成文件 | `write_hw_ila_data` | 同上 |
| 之后离线看这份文件 | `read_hw_ila_data <文件>` + `display_hw_ila_data` | 同上 |

网上抄来的调试命令名要先到 `-help` 里过一遍再写进脚本（否定证据的原文形状见 §2.2 那条）。

规则：

- **"写探针描述文件"这件事可以成功返回而不产生任何文件。** 设计里没有调试核时，
  `write_debug_probes` 返回 0、打印 `INFO: [Chipscope 16-244] No debug cores were found`，
  目标目录里什么都没有；加了 `-quiet` 连这条 INFO 都看不见（本机实测：`-quiet` 时一行都不印）。
  **所以这一步别加 `-quiet`**：要一起看的是 `file exists` 与消息里有没有 `16-244` 两件事；
  退出码只在区分"有核没 implement"（`12-5829`，rc=1）时才有信息，单独拿它当判据正是
  `SKILL.md` §1 第 9 条列的那类假读数。
  两种失败都拿不到 `.ltx`，但一句是"你没插"、一句是"插了没落地"，修法不同。
- **探针描述文件（`.ltx`）必须与板上跑的比特流同一次构建。** 版本不同时的症状是
  "能连上、有波形、但每个信号都对不上"，比连不上更难查。落地做法：与 `.bit` 放同一目录、同前缀。
  **而"同目录同前缀"恰好让 `file exists` 这一条失去信息**：前一次留下的同名 `.ltx` 会让它读起来是绿的，
  实际是旧构建的。所以这一步是三条一起：带 `-force` 写、写完 `file exists` 为真、
  `file mtime` 落在****的窗口里。少了第三条，判据检查的是文件名，不是构建身份。
  "窗口"要落成一个可比较的数，不要写成"看起来是新的"：在开跑之前取一次 `clock seconds` 记为 `T0`，
  判 `mtime >= T0`；拿不到 `T0` 时用同一次构建的 `.bit` 的 `file mtime` 当参照，判 `.ltx` 不早于它。
  两条边界要写进结论：① `mtime` 是**秒级**的（本机 1.2 s 之差只读出 1 秒），同一秒内产生的两个产物
  用它分不开，这时要连 `size` 一起报；② 这套读数证明的是"这个文件在这轮被写过"，
  仍然不是"它与板上那份 `.bit` 同批"——同批由 `board-bringup.md` §1 的指纹记账管。
- **没有任何命令读 `.ltx` 的内容**（这一族里只有写的那条）。本机 `-help` 试过 `read_ltx`、`get_ltx`、
  `report_debug_probes`、`list_debug_probes`、`read_debug_probes`、`get_debug_probes_file`、`read_hw_ltx`
  七个名字，一律 `invalid command name "<那个名字>"`；**正对照是同族里确实存在的三条**——
  `write_debug_probes`、`read_hw_ila_data`、`get_hw_ilas`，它们的 `-help` 都正常返回。
  形状是"**`.ila` 有读的口，`.ltx` 只有写的口**"：要把探针名拿出来比对，要么在硬件管理器里加载它
  （要有板子，见 §1），要么把它当文件读。**后者本机做过**：在 Vivado Tcl 会话里 `open`/`read`/`close`
  取回全文并 `split` 过——**`.ltx` 是 JSON**，根是 `ltx_root`，往下 `ltx_data[]` → `debug_cores[]`，
  每个核带 `type`/`name`/`spec`（还有落地过的核才有 `uuid` 与 `core_location`），核下 `pins[]` 带
  `name`/`id`/`type`/`direction`/`nets[]`。**但 `nets[]` 里是 `u_ila_dbg/probe0[0]` 这种核内名字**，
  不是你连进去的设计网名（这条的坑与补救写在 §2.1 的 ILA 那条）。哈希那一步仍然回 shell 做。
- **触发条件要先证明会满足。** 起抓与等触发的是 `run_hw_ila` + `wait_on_hw_ila`（§2.2 的七步；
  本机无板，这两条只按各自 `-help` 的描述排，第一次有板时实测一遍，见 §1 开头），
  `upload_hw_ila_data` 只负责把数据取回来；而 `read_hw_ila_data` 读的是**文件**——
  读不到只说明文件不在，不能当成"没触发"的证据（同 `board-bringup.md` §4
  里"等不到"与"没发生"的区分）。
- 判"某位有没有在动"，优先用 VIO 强制/观察一个你能完全控制的信号，再用 ILA 抓时序细节。
  两者成本不同：**这句是结构性说法，不是本机测到的数**——ILA 那一路要 BRAM 与采样时钟、
  VIO 那一路不采波形，所以通常占得少；具体占多少只能按 `constraints-timing.md` §6 的
  差值法仍要在自己的设计上取；本机已经把"带调试核跑完布局布线"这一样取到了（占用与两臂的 WNS/WHS 见 `constraints-timing.md` §6，那里同时写了它们能不能签字）。

## 4. 什么时候不该用在线调试

| 情况 | 为什么 | 代替做法 |
|---|---|---|
| 问题只在真实内存/带宽下出现（DDR 竞争、HP 口拥塞） | 探针的采样会改负载，插了就不复现 | 用可数的门（计数器、丢帧计数）在软件侧统计，见 `board-bringup.md` §6 |
| 现场没有 JTAG（只有 SD/QSPI 自启） | 物理上连不上 | 把状态搬到串口打印或寄存器回读 |
| 现象是"一笔访问把 CPU 卡死" | 总线挂住时调试链路也受影响 | 按通路问题处理，见 `board-bringup.md` §4 |
| 需要长期在客户现场判版本 | 不能每次接调试器 | 版本/构建号寄存器（`board-bringup.md` §1）；再加一个自由运行计数器证明"时钟活着"，见 `SKILL.md` §2 的 I5 |

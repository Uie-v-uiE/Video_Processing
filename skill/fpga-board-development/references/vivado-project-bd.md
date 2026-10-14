# Vivado 工程与 Block Design：结构、改名、地址、导出

这一页管"设计怎么在 Vivado 里组织起来、什么时候会悄悄变形"。
RTL 本身在 `rtl-pipeline-cdc.md`，约束在 `constraints-timing.md`，构建运行在
`vivado-build-run.md`，上板调试在 `onchip-debug.md`。

## 1. 文件集是唯一的真相源

工程里有三个容易混的东西：**源文件**、**文件集（fileset）**、**run**。同一个模块被两个文件集
都引用时，综合出来的网表来自哪一个不由你决定，由 `launch_runs` 用的那个 run 决定。

```tcl
add_files src/rtl/bar.vh
# 头文件的类型：本机实测 `add_files ./hdr_bar.vh` 之后**不写任何 set_property**，
# `get_property FILE_TYPE [get_files hdr_bar.vh]` 已经是 `Verilog Header` —— 这一族会自动认。
set_property FILE_TYPE {Verilog Header} [get_files bar.vh]   ;# 只有认错了才需要显式改；先读一次再决定要不要设
update_compile_order -fileset sources_1
get_files -compile_order sources -used_in synthesis         ;# include 解析后的真实编译顺序```

`get_files` 只有**一个**位置参数（模式），`get_files foo VH` 这种写法报
`Too many positional options`；要按属性筛就用 `-filter`（本机确认可用的一条形如
`get_files -filter {NAME =~ *fix*}`，别的写法先 `-help`）。
`report_compile_order -fileset <名字>` 在 2025.2.1 会打
`WARNING: [Vivado 12-3460] ... deprecated in favor of '-of_objects <fileset>'`，用 `-of_objects` 或直接 `get_files`。
`-compile_order`/`-used_in` 这一对选项的用法与取值写错的报错，记在 `constraints-timing.md` §8。

规则：

- **改了文件类型或 include 顺序之后，`report_compile_order` 要重新跑一次并留下输出**——用 `-file`，不要用 `-return_string` 交差：本机在工程里试 `-fileset sources_1` 与 `-constraints` 两种写法，都是 **rc=1、返回串只有 113 字符、首行就是 `ERROR:`**（表根本没出来）。**留下输出之后还要读一次长度/行数**，否则你留下的是一个错误页。
  综合期报 "module not found" 或某个 `define 看不到，九成是这里，不是 RTL 写错。
- **同一份 RTL 不要在工程里出现两份副本**（旧修改常留一份 `*_fix.v`）。判据：
  `get_files -filter {NAME =~ *fix*}` 有结果就说明有歧义源；要么删要么显式排除，
  别让"哪份生效"变成需要记住的事。
- 顶层要用 `set_property TOP` 显式指定，而不是"文件名排第一"。

## 2. Block Design：验证与改名是两个独立动作

```tcl
create_bd_design top
current_bd_design top
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 dma0
# 另一端的 cell 名（这里叫 stream_src）与它的接口名都要先用
# `get_bd_intf_pins <cell>/*` 列出来，别照抄本页的名字
connect_bd_intf_net [get_bd_intf_pins dma0/S_AXIS_S2MM] [get_bd_intf_pins stream_src/S_AXIS]
connect_bd_net [get_bd_pins dma0/s_axi_lite_aclk] [get_bd_pins ps7/FCLK_CLK0]
create_bd_port -dir I -type rst ext_reset_n
create_bd_port -dir I -type clk fclk -freq_hz 100000000   ;# 单位是 Hz：本机把 100 传进去，读回 CONFIG.FREQ_HZ 就是 100（=100Hz）
validate_bd_design
assign_bd_address
export_bd_design [get_files top.bd] -dir ./bd_out   ;# 生成设计源，供非工程流程复用
make_wrapper -files [get_files top.bd] -top
add_files ./top.gen/sources_1/bd/top/hdl/top_wrapper.v   ;# wrapper 不加进文件集，综合看不见它
```

`make_wrapper` 的公开语法行里文件是**位置参数**（`<files>`），`-files` 这台机器上照收（旧写法，
取到一次：`-help` 的选项表里**没有** `-files`，但它照样接受）；`-b` 被拒
（`[Common 17-170] Unknown option '-b'`）——所以选项解析严格到什么程度也要自己试，
别把某份资料里的开关当规范，先 `-help`。
**还有一件撞到的事**：BD 没连全时 `-top` 会失败，而失败是**一条错误链**——
`[BD 41-758]`（没接的时钟脚）→ `[BD 41-1031] Hdl Generation failed` →
`[Vivado 12-5158] Failed to make wrapper ... Top wrapper not generated`，最外面套
`[Common 17-39] ... failed due to earlier errors`。这条链本机原样取到过一次。
**失败时那个变量根本不会被赋值**（实测：`catch {set wv2 [make_wrapper …]} $wv2` 之后
下一行读 `$wv2` 得到 `can't read "wv2": no such variable`，批处理当场断在这里）——
错误文本进的是 `catch` 的第二个参数，不是被赋值的那个。所以判据要写成两件事：
先 `if {![info exists w]} → 失败`（`info exists` 要的是**变量名**，写成 `$w` 会把它当路径去查；
或者把 `set` 整个包在 `catch` 里、失败时先给它赋空串），
再 `file exists`。**「这一行没报错」和「它返回了路径」是两件事**，中间还差一次显式的存在性检查。
反面也成立：`-files` 给的是**空集合**时它 rc=0、返回**空串**（本机对不存在的 `.bd` 取到
`rc=<0> len=<0>`，前面只有一条 `WARNING: [Vivado 12-818] No files matched …`）——
所以 `file exists` 那道检查在这两种失败里都是唯一能红的判据。
对照写法（本机跑通、返回真路径并且文件存在）：

```tcl
set w ""
if {[catch {set w [make_wrapper -files [get_files top.bd] -top]} msg]} {
  puts "WRAPPER-FAIL $msg"          ;# 真正的错误文本在 msg 里
} elseif {![file exists $w]} {
  puts "WRAPPER-MISSING <$w>"       ;# rc=0 但空串/路径不存在，都走这一支
} else {
  puts "WRAPPER-OK $w"
}
```
`export_bd_design -dir ./bd_out` 实测在 `./bd_out` 下建出一个 `*.srcs` 结构（不是单个 hwh/xsa）。
BD 想倒成 Tcl 脚本用的命令名是 `write_bd_tcl`，**没有** `export_bd_tcl` 这种拼法
（`invalid command name`、`info commands export_bd_tcl` = 0；`make_bd_tcl` 同样是 0）。
正对照就在同一个前缀里：`info commands *bd_tcl*` 只交出 **1** 个（`write_bd_tcl`），
而 `info commands *bd_design*` 交出 **12** 个、其中就有上一句用的 `export_bd_design`——
**同一个 `export_bd_*` 形状下一条在一条不在，所以那条"没有"是扫描读数，不是拼写偏好**。

规则：

1. **`validate_bd_design` 通过 ≠ 地址已分配。** 它是接口/时钟/复位一致性检查；
   地址那一层是 `assign_bd_address` 的事。两者都要过，顺序也是这个顺序。
   反过来也成立：BD 没连全（PS 没配置、时钟没接）时 `validate_bd_design` 会以
   `[Common 17-39] 'validate_bd_design' failed due to earlier errors.` 收尾——
   这句只说明"前面还有 ERROR 没处理"，去看它上面第一条，不要拿它当验证器坏了。
   本机实测的第一条真错长这样：
   `ERROR: [BD 41-758] The following clock pins are not connected to a valid clock source:
   /ps7/M_AXI_GP0_ACLK /ps7/S_AXI_HP0_ACLK`，另有一条 `WARNING: [BD 41-2670] Found an incomplete
   address path …`。同一个 `17-39` 外壳也会套在 `connect_bd_net`、`generate_target`、
   `make_wrapper` 上（本机都遇到）——**它们是同一条前面错误的下游**，不要分别去修。
   **而"使能一个 HP 口"不是改一个属性那么小**：本机把 `CONFIG.PCW_USE_S_AXI_HP0 {1}` 设进去之后
   `validate_bd_design` 连红两次——即使已经把 `FCLK_CLK0 → ps7/S_AXI_HP0_ACLK` 接上**仍然红**，
   因为 `get_bd_pins ps7/*HP0*` 一次交出 **45** 个脚（`ACLK` 只是其中一个，剩下的 `AR*`/`AW*`/`W*`/`R*`/`B*`
   与 `*COUNT`、`*ISSUECAP1_EN` 全要有落点）。这类"开一个端口"的改动要按**整组接口**估工作量；
   改完先数 `validate` 报出来的清单有多长，再决定这条路值不值得走（不需要 HP 就别开）。
2. **改 BD 里 cell 的名字 = 改网表层级。** 之后 `.hwh/.xsa` 里的实例名、约束里的
   `get_cells` 路径、PS 端按名字取 IP 的代码全部要跟着改。症状是"PS 侧 `KeyError`/拿不到 IP"
   或"约束命中 0 个对象"，而不是任何编译错误。改名之后必做两件事：重新导出、
   按 `constraints-timing.md` §2 重跑一遍每条约束的命中数。
3. **`-vlnv` 写全版本。** 只写 `xilinx.com:ip:axi_dma` 会解析成"这版工具里的那个默认版本"，
   换工具版本就换 IP。要可重复就把 VLNV 钉死，并用 `report_ip_status` 看哪些 cell 落后于
   工具推荐的版本——**落后不是错误**，升级 IP 才会改参数默认值，所以升级是一次变更，
   不能和别的改动混在同一次构建里。
4. **引脚与接口名要从这个 IP 上列出来，不要背。** 例：`axi_dma:7.1` 的流接口是
   `S_AXIS_S2MM`（从端）与 `M_AXI_S2MM`（主端 AXI 口），**没有** `M_AXIS_S2MM`——按后者写
   `get_bd_intf_pins` 返回空集合，`connect_bd_intf_net` 就连了个寂寞。复位口同理，
   实测这个 IP 上是 `/dma0/axi_resetn`、`mm2s_prmry_reset_out_n` 这一批带 `n` 的名字：
   `get_bd_pins dma0/*reset*`。极性与 IP 的复位参数不一致，最典型的症状是"能综合、能上电、
   永远不出复位"。
5. **`create_bd_port` 没有 `-polarity` 这个选项**（实测 `[Common 17-170] Unknown option`）：
   极性靠端口命名与外面的连接逻辑表达，不是靠一个开关。`-type clk` 不给 `-freq_hz` 时
   BD 会打频率未知的告警（`BD 5-670`），后面时钟约束就对不上——把频率写全。

6. **接口协议不匹配是硬失败，而且真实原因不在 `catch` 的返回值里。** 本机 Zynq-7000 的 PS 主口是
   **AXI3**：`get_property CONFIG.PROTOCOL [get_bd_intf_pins ps7/M_AXI_GP0]` = `AXI3`，
   `gpio0/S_AXI` = `AXI4LITE`，于是直连得到
   `ERROR: [BD 41-1285] The protocols of the interfaces '/ps7/M_AXI_GP0'(AXI3) and '/gpio0/S_AXI'(AXI4LITE) are incompatible. They cannot be connected.`
   而 `catch` 里只剩 `[Common 17-39] 'connect_bd_intf_net' failed due to earlier errors.`——
   **判据是日志里那条 41-1285，不是返回值**。读协议只有 `CONFIG.PROTOCOL` 这一条路：
   同一个对象上 `PROTOCOL`、`INTERFACE_PROTOCOL` 本机都回空，`VLNV` 两边同为
   `xilinx.com:interface:aximm_rtl:1.0`（分不出 AXI3/AXI4LITE），`MODE` 只分主从。
   桥接用 SmartConnect：`get_ipdefs -quiet *smartconnect*` 本机给 1 个（`xilinx.com:ip:smartconnect:1.0`），
   而 **`xilinx.com:ip:axi_smc:1.0` 这台 2025.2.1 报 `[BD 5-390] IP definition not found`**
   （同一条扫描 `*axi_smc*` = **0** 个、`*protocol_converter*` = 1 个 `xilinx.com:ip:axi_protocol_converter:2.1`，
   所以那个 0 是名字读数，不是搜索坏了）。插进去之后两端连接 rc=0、`validate_bd_design` rc=0、
   `make_wrapper` 出真路径（完整链见 §2.2 末尾）。
   **但插了 SMC 之后它两个口的 `CONFIG.PROTOCOL` 仍读 `AXI4`**——这个属性写的是 IP 自己声明的接口，
   不能拿来预测"这条连接会不会被拒"；能预测的只有"中间那颗是不是协议桥"。

### 2.1 让 BD 可重跑：脚本、参数名、状态表

**手工建 BD 的序列可以重跑，但"把现有 BD 倒成脚本"这件事工具自己就不背书。**
`write_bd_tcl -force ./bd_out.tcl` 实测能出 230 行、里面确有 `create_bd_cell`，
而它开头那段生成注释自己写着：

```
################################################################
# This is a generated script based on design: psbd
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################
```

所以它的定位是"可读的起点"，不是可重复性的凭据：要拿它当构建脚本，得自己验一遍
（新建工程 → source 它 → `validate_bd_design`/`assign_bd_address` → 与手工版的
`get_bd_pins`、地址表逐项比）。**"参数带没带进 dump"取决于它有没有被记成"改动"**，
在同一份设计（ps7 + smartconnect + gpio，连接/时钟/地址都做掉、`validate_bd_design` rc=0）上
做了一次只差一个属性的 A/B：

| dump | 行数 | 字符 | `PCW_` 次数 | `PCW_ACT` 次数 |
|---|---|---|---|---|
| A：链已连好、地址已分配、**跑过 `validate_bd_design`**，没手动设过 PCW | 252 | 9231 | **1** | **0** |
| B：在 A 之后 `set_property CONFIG.PCW_USE_S_AXI_HP0 {1}` | 256 | 9499 | **2** | **0** |

A 里那唯一一条是 `CONFIG.PCW_FPGA_FCLK0_ENABLE {1}`——**不是我写的**。它到底是谁写进去的，
按"一次一个变量"查清了（同一份设计，三个时刻各取一份 dump）：
时钟线接完、地址也分完但**还没 validate** 的那一份里 `PCW_` 是 **0**；
跑一次 `validate_bd_design`（rc=0）之后再取，变 **1**，名字正是 `CONFIG.PCW_FPGA_FCLK0_ENABLE`；
`save_bd_design` 之后仍是 1。**所以是"验证"这一步把 PS7 的派生参数算出来并记进 BD，
`write_bd_tcl` 才有东西可写**——不是时钟连线（三种接法各测过一轮，全 0），
也不是 `make_wrapper`/`generate_target`（这两个前后 `PCW_` 计数与字符数一字不变，9231→9231→9231）。
对"能不能拿 dump 当构建脚本"的直接影响：**同一份 BD 在 validate 之前倒出来的脚本会少掉这些派生参数**，
照它重建出来的东西与你刚验证过的那份不是同一份——要倒就倒在 validate 之后。

**但"记进 BD"这件事分两条通道，数错了对象会把功劳记错人**（同一份 ps7 + smartconnect + gpio，
连接与地址都做掉、**没有手动设过任何 `CONFIG.PCW_*`**，在三个时刻各读一次，
读的是"文件里的条数"与"dump 里的条数"两个不同对象）：

| 时刻 | `write_bd_tcl` 的 dump | `.bd` 文件 | `get_property CONFIG.PCW_FPGA_FCLK0_ENABLE [get_bd_cells ps7]` |
|---|---|---|---|
| assign + `save_bd_design`，**还没 validate** | `PCW_` **0** 次（241 行 / 9101 字符） | `PCW_` **0** 次（8686 字节） | 读不出（那时还没有） |
| `validate_bd_design`（rc=0）之后、**没再 save** | `PCW_` **1** 次、`PCW_FPGA_FCLK0_ENABLE` 在里面（242 行 / 8947 字符） | **仍是 0 次、8686 字节一字不变** | **`1`** |
| 再 `save_bd_design` | 同上 1 次 | `PCW_` **1** 次（9621 字节 / 302 行） | `1` |

所以两条要分开写：**算出派生参数的是 `validate_bd_design`**（它在内存里就把 `PCW_FPGA_FCLK0_ENABLE`
填上了，`get_property` 当场读得到、`write_bd_tcl` 当场能倒出来），
**把它写进 `.bd` 文件的是 `save_bd_design`**。
推论是取数纪律：**要在文件里数参数，就得在你关心的那个时刻之后先 save 一次再读文件**，
否则读到的是上一次保存时的形状。两种会把功劳记错的样子：
一是把"save 之后才出现的条数"当成"save 算出来的"（其实是 validate 在内存里算的），
二是**自己手动 `set_property CONFIG.PCW_*` 三条、save 之后文件里 `PCW_` 32 次 / `PCW_ACT` 23 次**，
就以为那一整片是工具派生的——**那一组数是你自己写进去的值被序列化，跟派生不派生无关**
（同一份设计重做时不手动设任何东西，validate 之前文件里就是 0）。
顺带把 `PCW_ACT` 那条读数的射程收窄：上面手动设过配置的那一臂里，`.bd` 文件有 23 处 `PCW_ACT`，
而 `write_bd_tcl` 的 dump 里是 **0**——所以"dump 里没有 `PCW_ACT`"与"`.bd` 里没有"是两件事，
按下面那条把属性名读回来的判据（`list_property [get_bd_cells ps7]`）才不会串。
两件事因此要分开：`write_bd_tcl` 只写"被记为改动"的 PCW 参数；automation 落成默认值的那一大批
**不进 dump**（本机另一次只有 automation 加一颗 gpio 的设计，dump 241 行、`PCW_` **0** 次）。
而 **`CONFIG.PCW_ACT_*` 在本机的 dump 里一次都没出现过（两个臂都是 0）**——那句
"设过之后 dump 里出现一整片 `CONFIG.PCW_ACT_*`"是**把对象记错了**：`PCW_ACT_*` 是 cell 上
**可读的属性名**（`list_property [get_bd_cells ps7]` 里就有 `CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ`，
见本节末），不是 dump 的内容。**属性存在 ≠ dump 里有**，两边都要自己数：
`grep -c PCW 文件` 或 `set n [regexp -all {PCW_} $txt]`。
顺带记一条 Tcl 计数本身的坑：`regexp -all` 的次数在**返回值**里，第三个参数拿到的是
**第一次匹配到的文本**——本机把它写成 `expr $pcw/1` 之后炸 `invalid bareword "PCW_"`，
整批脚本从那一行断掉，后面的读数全部没取到（这一条与 §2 第 6 条"错误文本与返回值分家"是同族）。
`export_bd_tcl` 在本机不存在（`invalid command name`），能用的只有 `write_bd_tcl`；
它的选项也别背：`write_bd_tcl -no_simplification` 报 `[Common 17-170] Unknown option`，
本机用成功的只有 `-force <路径>`。

**参数名要从对象上筛，不背。** 本机两个 IP 的对照就够说明问题：`axi_dma:7.1` 的 cell 有 39 个属性，
其中 **26 个以 `CONFIG.` 开头、25 个是 `CONFIG.c_*` 这种小写形式**（`CONFIG.c_include_sg`、
`CONFIG.c_addr_width`…），**所以"这个 cell 的属性都是参数"是错的**——剩下 13 个是
`CLASS`/`LOCATION`/`ALLOWED_SIM_MODELS` 这类对象属性（把三份计数都取过：39 / 26 / 25）；
`processing_system7:5.5` 的 cell 有 891 个属性，出现了大写的 `CONFIG.PCW_*`
（如 `CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ`）。**属性集合由 IP 自己决定，不由你的记忆决定**，
所以"这类参数一般都叫 X"的推断会在换 IP 那一刻失效。可用写法是筛 + 逐个读：

```tcl
llength [list_property [get_bd_cells ps7]]
foreach p [list_property [get_bd_cells ps7]] {
  if {[string match CONFIG.*CLK* $p]} { puts $p }
}
get_property CONFIG.<筛出来的名字> [get_bd_cells ps7]     ;# 按名字读，通配形式不展开
```

引脚同理：`get_bd_pins ps7/*` 本机给 62 个，`FCLK_CLK0` 是 `/ps7/FCLK_CLK0`。
`apply_bd_automation` 的 `-rule`/`-config` 组合不要猜，`apply_bd_automation -help`
里印的是 `-rule <arg> [-config <args>] -dict <arg> -opts <arg>`；PS 没配置就
`validate_bd_design` 会失败并留下 `[Common 17-39] 'validate_bd_design' failed due to earlier
errors.`——这句是"前面有错没处理"，不是验证器本身坏了，往上翻第一条 ERROR。

`report_ip_status` **不是一行一个 cell**：它是带框的表，前面还有几行说明
（`IP Status Summary / Your project uses 1 IP…`），单元格会折行。真实列名是
`Instance Name | Status | Recommendation | Change Log | IP Name | IP Version | New Version |
New License | Original Part`（本机那行：`psbd_ps7_0 | Up-to-date | No changes required | *(1) |
ZYNQ7 Processing | 5.5 | 5.5 (Rev. 8) | Included | xc7z020clg400-1`）——
第三列是 **Recommendation**、第四列是 **Change Log**（`*(1)` 是脚注指针，不是"推荐"）。
判"要不要升级"读 Status 与 Change Log，不是读有没有红。
**`-return_string` 的两种长度都是真的，判别条件在工程里有没有 IP**（把两边都重取过）：
  - 工程里**没有 IP 实例**时 → `string length $r` = **0**（本机一份只有 RTL 的工程）；
  - `create_ip axi_gpio 2.0` 之后同一句 → 返回 **2234 字符**，开头就是报告横幅与表头。
所以**别把这条写成"开关坏的、只能去抓日志"**——那是把"没有 IP"读成"没捕获到"。
正确读法：先看长度，长度为 0 时先用 `get_ips`/`llength [get_ip_insts …]` 证明确实没有 IP，
再决定是去抓 stdout 还是接受"这张表本来就是空的"。
**这条与 `constraints-timing.md` §4 第 5 条不是矛盾，而是"捕获规矩不是全族共用的"**：
那一格量的是 `report_timing`，它给 `-return_string` 就交全文（4875/4882 两个数都非零）；
`report_ip_status` 同样加了这个开关却交空串。**所以别把任一命令的实测长度当默认**——
每个要解析的报告都在自己这版上取一次长度（`string length` 打一行就够），再决定是解析返回值还是抓日志。
工具的升级动作是 `upgrade_ip` / `upgrade_project`（本机都实跑过）；
`upgrade_project` 在已经是新版时打 `[INFO] Project 1-1969 ... 0 IPs were upgraded; 0 IPs failed
to upgrade, exiting script.` 并**不再执行后面的命令**（这是本机早期那次取到的形状）；
两遍重跑却**既没打 `1-1969`、后面的 `report_ip_status` 也照跑**（返回 2234 字符那张表）。
两种都记下：这条命令**不能当流水线里的一环**——它可能悄悄终止脚本，也可能什么都不打。
要"升级前后各取一次表"，就分两个会话/两条命令跑，中间用 `file` 落盘，别指望同一段脚本走到底。

### 2.2 把自己的 RTL 放进 BD：模块引用只给平铺端口，接口不会自己长出来

先问一遍这一族有哪些名字（**这是正向读数**：列出来的那些确实已注册；查不到的什么都推不出，
判存在与否仍然用 `-help`），也别抄任何清单（包括本页）：

```tcl
load_features ipintegrator
info commands *bd_*        ;# 本机给 58 条：connect_bd_intf_net、assign_bd_address、
                           ;# get_bd_addr_spaces、get_bd_addr_segs、make_bd_intf_pins_external、
                           ;# create_bd_addr_seg、exclude_bd_addr_seg、report_bd_diffs、
                           ;# replace_bd_cell、upgrade_bd_cells、validate_bd_design_performance …
```

模块引用这条路是通的（本机实跑）。**前提是这个模块已经在工程里**：顺序是
`add_files ./regs.v` → `create_bd_cell -type module -reference regs myregs`；
没有前一步时 `-reference` 找不到模块（工具回的是"名字解析不到"那一族错误，不是"cell 建不出来"）。

```tcl
add_files ./regs.v                                 ;# 模块得先进工程，光有文件在磁盘上不算
create_bd_cell -type module -reference regs myregs    ;# 返回 /myregs
get_bd_pins myregs/*
;# /myregs/clk /myregs/rst_n /myregs/s_axi_awready /myregs/s_axi_awvalid  —— 就是 RTL 端口的平铺名字
get_bd_intf_pins myregs/*                             ;# 空
```

**关键读数在最后一行：模块引用 cell 没有接口。** 端口名叫 `s_axi_*` 也不会被识别成 AXI 从接口，
于是所有下游自动化都没有落点：`apply_bd_automation -rule xilinx.com:bd_rule:axi4` 找不到接口
（`[BD 5-156] Expected 1 or more objects...`）、`assign_bd_address` 也找不到，
症状是"模块进 BD 了、地址表里永远没有它、PS 侧读写不到"，而每一步都不算编译错误。
两个容易看错的地方：工具会把 `clk`/`rst_n` **推断成信号接口**
（`INFO: [IP_Flow 19-5107] Inferred bus interface 'clk'/'rst_n'`，同一条路上还连带打了
`WARNING: [IP_Flow 19-5661] Bus Interface 'clk' does not have any bus interfaces associated with it`
与 `WARNING: [IP_Flow 19-11770] Clock interface 'clk' has no FREQ_HZ parameter`）——
**但这些是打包/目录那一层打的，不是你的 cell 长出了接口**：本机在同一个 cell 上取到的计数是
`get_bd_pins mycnt/*` = 5、`get_bd_intf_pins mycnt/*` = **0**。所以"日志里出现了 `clk` 的
interface 字样"不能当"这个 cell 有接口引脚"的证据，判据只有 `llength [get_bd_intf_pins …]` 这一条。
（那两条 `19-11770`/`19-5661` 反而有用：它们告诉你**推断出来的那个钟接口没有频率**，
这正是 `zynq-pynq.md` §1 那条"没给 `-freq_hz` 的钟口 validate 不报"的另一半读数。）而"空集合有没有声音"这件事重取过，**旧文写反了**：
`get_bd_intf_pins myregs/*` 与 `get_bd_intf_pins myregs/s_axi` **两种写法都打**
`WARNING: [BD 5-232] No interface pins matched 'get_bd_intf_pins myregs/...'`
（消息里把你的整条表达式原样回显），而**交回来的仍是空集合、`catch` 返回码 0**。
所以这条告警是**日志里的噪声**，不是判据：判"有没有接口"永远用
`llength [get_bd_intf_pins -quiet …]`（`-quiet` 在这里的作用只是不把这条告警写进你之后要 grep 的日志，
见 `constraints-timing.md` §7 第 4 条那段的实测说明）。
"那我自己造一个接口行不行"——对模块引用 cell 也不行，本机三条路都是死的：
`create_bd_intf_pin … [get_bd_cells myregs]` 报 `Too many positional options`，
`current_bd_instance [get_bd_cells myregs]`（工具在 `-help` 里给的正规做法）报
`[BD 5-128] /myregs is not a hierarchical cell`，`make_bd_intf_pins_external` 只回
`INFO: [BD 5-409] No interface pins to be made external for /myregs`。
同理这些名字在本版**不存在**（都报 `invalid command name`）：
`get_bd_interface_pins`、`get_bd_interfaces`、`get_bd_addr_ranges`、`get_bd_addr_segments`、
`report_interface_port_usage`、`report_addr_map`、`list_bd_icfg_gpins`、`get_file_types`、
`ipx*`（非工程打包那一族）。正确的名字是 `get_bd_intf_pins` 与
`get_bd_addr_spaces`/`get_bd_addr_segs`。

三条真能走的路，按代价排：

1. **逐根手工连**（`connect_bd_net`）。能连、能 `validate`，但没有地址段——
   寄存器堆的握手得自己写，PS 侧也就只能走你自己引出去的 AXI-Lite 从口。
2. **让端口被识别成接口**：本机试过在 RTL 端口上写属性
   `(* XILINX_INTERFACE = "S_AXI: MODE=SLAVE, ADDR_WIDTH=32, DATA_WIDTH=32, ..." *)`，
   结果 `get_bd_intf_pins <cell>/*` **仍然是空**——所以这条不是"写个属性就完事"的 Tcl 方案。
   已识别的入口是 GUI 的 Interface Port Identification，或把这段 RTL 打包成 IP
   （打包那一族的命令名本机取过一对：负读数 `ipx -help` 报 `invalid command name "ipx"`、
   `info commands ipx` = **0**；正对照是同一条扫描问 `info commands ip*`，交出 **1** 个
   （`iphys_opt_design`），问 `ipconfig` 也是 **0**——**这一族在这台 2025.2.1 的批处理命令空间里
   确实看不见，而扫描本身看得见 `ip` 开头的名字**。注意这仍然只否定"命令名"，不否定打包这件事本身。
   见 `SKILL.md` 边界表）。
   `make_bd_intf_pins_external` / `make_bd_pins_external` 这两条命令存在，但**给它们一个空集合时
   它们静默返回成功**（本机：对不存在的 `a1/S_AXI` 调用，返回空、不报错），
   所以"命令没报错"在这里也不是证据——先 `llength [get_bd_intf_pins …]` 非 0 再谈外部化。
   识别成接口之后，`apply_bd_automation -rule xilinx.com:bd_rule:axi4` 与
   `assign_bd_address` 才有落点（本机对现成 IP 跑通了这一条）。
3. **用现成 IP 顶住接口**（`axi_gpio:2.0` 这类，本机 `create_bd_cell` 直接给出 `/gpio0/S_AXI`），
   自定义逻辑放在它外面。改动最小，代价是多一层地址映射。

顺带三条本机读数，都支持"名字与数量都要现取"：PS 的脚在**未配置**时 `get_bd_pins ps7/*` 给 62 个，
`apply_bd_automation` 配置完是 106 个；`get_property CONFIG.*` 那种通配读法在 PS 上给的是**空**，
要读参数得按名字（`CONFIG.PCW_USE_S_AXI_HP0` 这类能设也能读回 1）；
地址空间名**不会**变多也不会改名：本机未配置与配置之后 `get_bd_addr_spaces` 都是
`/gpio0/S_AXI /ps7/Data`；资料里常见的 `Data2` 本机从未出现。
**而 `M_AXI_GP0` 两种取法都不是可用的对象路径**——把前一次"`M_AXI_GP0` 是它下面的段名"那句否掉了：
当空间问，`get_bd_addr_spaces ps7/M_AXI_GP0` 给**空集合**；当段问，`get_bd_addr_segs ps7/M_AXI_GP0/*` 给
**0 条**；同一份设计问 `ps7/Data/*` 给 **1 条** = `/ps7/Data/SEG_gpio0_Reg`（`OFFSET 0x41200000`、
`RANGE 0x00010000`、`USAGE register`）。**被分配的段挂在空间名下面，段名由工具按 `SEG_<cell>_<intf>` 生成**，
不从主口名派生；这一条在 `save_bd_design` 之后重开会话再取，四条读数一字不变
（对照 §4 那张表里"下一个会话里 BD 改动全不见了"那一行——没保存才是那个形状的原因）。
现成 IP 那条路上，**`-config` 里必须给 `Master`**（把前一次写下的"裸 `{Clk_Auto {}}` 就成功"推翻了）：

```tcl
apply_bd_automation -rule xilinx.com:bd_rule:axi4 \
    -config {Master {/ps7/M_AXI_GP0} Clk_Auto {}} [get_bd_intf_pins gpio0/S_AXI]
;# 本机 rc=0：新建 /ps7_axi_periph 与 /rst_ps7_50M 两颗 cell，
;#   `llength [get_bd_intf_nets]` 从 2 变 4，/ps7/Data 下长出 SEG_gpio0_Reg @ 0x41200000 / 0x00010000

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Clk_Auto {}} \
    [get_bd_intf_pins gpio0/S_AXI]
;# 本机 rc=1（单从端、什么都没连的干净设计上也一样红），真因在错误码上面那一行：
;#   Internal error: unable to extract CONFIG.Master from parameters.
;#   ERROR: [BD 41-2168] Errors found in procedure apply_rule:
;#   catch 的返回值仍然只有 [Common 17-39] 'apply_bd_automation' failed due to earlier errors.
```

**两处的 rc 与真因是分开的**，所以这一族的判据一律是"日志里紧挨着错误码的那一行，加后面读回来的量"。
前提仍然是**接口已经存在**（现成 IP 有，模块引用没有），这正是上面那条分岔口。
另外这条自动化**没替 `gpio0/s_axi_aclk` 接线**（本机读它的 `NET` 给空），
`validate_bd_design` 因此还是红的（`BD 41-758` + `WARNING: [BD 41-2670] incomplete address path`）；
把 FCLK_CLK0 手动接到 `gpio0/s_axi_aclk` 与 `ps7/M_AXI_GP0_ACLK` 之后同一条命令才回 0。

顺序与判据（每一步的判据都是"读回来会变的那个量"，不是返回码）。**先查协议再连**：
Zynq-7000 的 GP0 是 AXI3，直接连 AXI4-Lite 从端是硬失败（§2 第 6 条），
本机跑通的完整链是把 SmartConnect 放在中间：

```tcl
llength [get_bd_intf_pins <cell>/*]                        ;# 0 → 先解决接口，后面全都无从落点
get_property CONFIG.PROTOCOL [get_bd_intf_pins ps7/M_AXI_GP0]   ;# 本机 AXI3
get_property CONFIG.PROTOCOL [get_bd_intf_pins gpio0/S_AXI]     ;# 本机 AXI4LITE
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smc0
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins smc0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc0/M00_AXI]  [get_bd_intf_pins gpio0/S_AXI]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins gpio0/s_axi_aclk]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins smc0/aclk]
get_bd_addr_segs gpio0/S_AXI/*    ;# 段名现取：本机是 `/gpio0/S_AXI/Reg`（大写 R）
assign_bd_address -offset 0x41200000 -range 64K \
    -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs gpio0/S_AXI/Reg]
get_bd_addr_segs ps7/Data/*       ;# 判据在这里：多出一条 `/ps7/Data/SEG_gpio0_Reg`、OFFSET=0x41200000
validate_bd_design                ;# 本机 rc=0
make_wrapper -files [get_files top.bd] -top   ;# 本机 rc=0，返回 …/topbd.gen/sources_1/bd/topbd/hdl/topbd_wrapper.v
```

`get_bd_addr_spaces` 本机两次都给 `/gpio0/S_AXI /ps7/Data`（空间名一律现取）。

**这一串里有几个名字是别的资料常用、本版不认的**（都是直接调用取到的读数，不是搜出来的）：
`create_bd_design -part <part> top` → `[Common 17-170] Unknown option '-part'`（part 从工程来，
命令只收名字）；`make_extract_pins ps7 -extract pcw` → `invalid command name "make_extract_pins"`
（教程里"把 PS 的 PCW 引脚拉出来"那一步在这版不存在）。**这一条的正向对照是同一次会话里 PS 的引脚本来就在**：
`connect_bd_net [get_bd_pins ps7/FCLK_CLK0] [get_bd_pins ps7/M_AXI_GP0_ACLK]` 直接 rc=0，
`get_bd_pins ps7/FCLK_CLK0` 也取得到对象——所以那个 `invalid command name` 不是"PS 还没展开所以看不见引脚"，
是这条命令本身没有。`ps7/FCLK_CLK0` 与 `ps7/M_AXI_GP0_ACLK` 直接 `connect_bd_net` 即可，本机就是这么连绿的。

**别在这条链上用 `-quiet`，它会让你把失败的连接读成成功**（本机自己踩的：给
`connect_bd_intf_net`/`connect_bd_net` 都加了 `-quiet`，两条 rc=0 就往下走，结果后面
`assign_bd_address` 报 `[BD 5-126] Cannot assign </gpio0/S_AXI/Reg> into Address Space </ps7/Data>`，
去掉 `-quiet` 重取才知道连接那步根本没成）。同一条链上的失败形状是成套出现的，认这几条就够：

- `[BD 41-249] Net '<名>' already has a source port '/<某口>' connected to it; Another source port
  cannot be connected to this net.` —— 把 `create_bd_port -dir I` 的板级输入接到 `ps7/FCLK_CLK0`
  就是这条（`FCLK_CLK0` 自己**是源**，两个源不能进同一根网）。
- `[BD 41-758] The following clock pins are not connected to a valid clock source:` 后面**逐行点名**
  （本机列过 `/ps7/M_AXI_GP0_ACLK` 与 `/ps7/S_AXI_HP0_ACLK`）——这条才是 validate 红的真成因。
- `CRITICAL WARNING: [BD 41-1356] Slave segment </gpio0/S_AXI/Reg> is not assigned into address
  space </ps7/Data>. Please use Address Editor to either assign or exclude it.` —— "没分配"的信号；
  它出现时 `validate_bd_design` 可以 rc=0 也可以红，两件事别合并判。
- 红的时候后面还会跟 `[BD 41-1031] Hdl Generation failed for the IP Integrator design <路径>`，
  再后面才是 `ERROR: [Vivado 12-5158] Failed to make wrapper … Top wrapper not generated for
  'verilog' language.`——**`make_wrapper` 的这条是最末梢**，按它去查 wrapper 就找错地方了；
  而 `catch` 交回来的 msg 只有包装句 `[Common 17-39] 'make_wrapper' failed due to earlier errors.`，
  真信息在上面（同 `onchip-debug.md` §1 那条 `17-39` 的规则）。
- `[BD 5-699] No address segments matched '<整条表达式>'` 是**空集合**的读数；本机另看到紧跟一句
  `INFO: [BD 41-3093] Triggering Legacy Auto Assign Algorithm`，而整条 `assign_bd_address` 仍然
  **rc=0**（这就是把段名大小写写错时"什么都不发生"的形状，见本节末那条）。

本机把几种写法都试过，两种失败、一种半失败，原文如下：

```tcl
assign_bd_address -offset … -target_address_space [get_bd_addr_spaces /ps7/Data] \
    [get_bd_intf_pins gpio0/S_AXI]
;# ERROR: [BD 5-112] No addressable objects to be assigned. Please check '-objects' and/or
;#        '-target_address_space' options are valid.   ← 对象要给**地址段**，不是接口引脚
assign_bd_address -offset … -target_address_space [get_bd_addr_spaces /ps7/Data] \
    [get_bd_addr_segs gpio0/S_AXI/Reg]
;# ERROR: [BD 5-126] Cannot assign </gpio0/S_AXI/Reg> into Address Space </ps7/Data>
;#        ← 对象对了，但主口到它没有物理通路（没连 interconnect/没连 M_AXI_GP0）；
;#          同一次 validate 会打 WARNING: [BD 41-2670] Found an incomplete address path …
assign_bd_address                        ;# 裸跑
;# INFO: [BD 41-3093] Triggering Legacy Auto Assign Algorithm —— 返回 0，
;#    但本机核对保存下来的 .bd：/ps7/Data 里只有 PS 自己的段，GPIO 根本没被映射。
```

还有一条同族的静默成功，撞到的是**大小写**：

```tcl
assign_bd_address [get_bd_addr_segs gpio0/S_AXI/reg0]
;# WARNING: [BD 5-699] No address segments matched 'get_bd_addr_segs gpio0/S_AXI/reg0'
;#   ← 集合是空的、命令 rc=0，本机随后数 `get_bd_addr_segs *` 没有增加。
;#     真名是 `/gpio0/S_AXI/Reg`（大写 R，来自 `get_bd_addr_segs gpio0/S_AXI/*`）。
```

**所以顺序是先连、后分配**（或者用带 `Master` 的 `apply_bd_automation -rule xilinx.com:bd_rule:axi4`
让它连），而"分配成功没有"要看在**目标地址空间下面**新长出来的那条段
（`get_bd_addr_segs ps7/Data/*` 多出一条 `SEG_gpio0_Reg` 且它的 `OFFSET` 有值），
不是看你传进去的那条从端段。`USAGE` 也不是这条判据：本机两条对象的 `USAGE` 都是 `register`。

段的属性名现取：本机 `list_property` 两次给出同一套
`ACCESS CLASS EXEIMG MEMTYPE NAME OFFSET PATH RANGE SECURE USAGE`（`-quiet` 在这里帮不上忙——
属性不存在时它连警告都不给，只回空。自己就撞了一次：按 `ADDRESS_VALUE` 去读基址，
rc=0、回空，而这个根本不在上面那套名字里，读到的空与"没分配"无关）。
**空 `OFFSET` 这件事找到了 owner，
那句"有两种含义"是错的**：BD 里有两类同名不同物的段对象。

| 对象 | `PATH` | `OFFSET` | `RANGE` | 它是什么 |
|---|---|---|---|---|
| `/gpio0/S_AXI/Reg` | 空 | 空，**分配成功之后仍然空** | IP 声明的默认段大小，本机 `0x00001000` | assign 的**输入** |
| `/ps7/Data/SEG_gpio0_Reg` | 就是它自己 | 分配到的基址，本机 `0x41200000` | 跟随 `-range`，本机 `0x00010000` | assign 的**输出** |

前一次"一次读到 4 个 `OFFSET`、其中 3 个为空"按这张表就有了正确解释：那三个是从端声明的那一类，
**不是"没分配"也不是"被排除"**。"被排除段本来就没有 `OFFSET`"这一支要自己排除一次才看得到；
要用的时候在同一份设计上跑一次 `exclude_bd_addr_seg` 再回来读 `USAGE` 与 `OFFSET`
（`info commands *bd_addr*` 本机交出 6 条：`get_bd_addr_segs assign_bd_address exclude_bd_addr_seg
create_bd_addr_seg get_bd_addr_spaces include_bd_addr_seg`，两条排除/包含都在）。
`RANGE` 有值只说明 IP 声明了默认段大小，不代表分配过——上表第一行就是反例。
想核对"谁连了谁"：本机 `info commands report_bd*` 只交出 **1** 个（`report_bd_diffs`），
`report_bd_connectivity` 是 rc=1 的不存在命令；接口级用 `llength [get_bd_intf_nets]`，
标量脚用 `get_property NET [get_bd_pins <cell>/<pin>]`。

地址空间名不随配置变多：本机在未配置、以及跑过
`apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR"}`
之后，`get_bd_addr_spaces` 两次都是 `/gpio0/S_AXI /ps7/Data`；资料里常见的 `Data2` 本机从未出现。
`assign_bd_address -help` 的选项集（现取，别背）：`-target_address_space -boundary
-master_boundary -external -dict -import_from_file -export_to_file -export_gui_to_file -offset
-range -base_high -with_locktype -with_name -force -quiet -verbose [<objects>...]`。

改名会让段的路径一起变（段名从接口路径派生，`/<cell>/<intf>/Reg` 这种），
旧地址、旧 `xparameters.h` 名字全部作废（§2 第 2 条）。改 RTL 端口名之后，
`validate_bd_design` 会按 `<cell>/<port>` 点名没连的时钟脚（本机印过 `/myregs/clk`，
同时也点 `/ps7/M_AXI_GP0_ACLK`、`/gpio0/s_axi_aclk`——**这份清单随 PS 配置变**，
别把它当固定表），这一条是红的，不是静默。

## 3. 交给 PS 侧的那份文件：一次导出的整组

PS/软件侧要的是**同一批**产物。`.xsa` 走 `write_hw_platform`。
`export_bd_design` 导出的是**BD 的设计源**：本机看到它建出一棵目录树
（几次运行分别看到 `<dir>/<bd>.gen/…`、`<dir>/<bd>.sint/…`、`<dir>/modrefs/…`、
`<dir>/export_operation_runs/`、`<dir>/<n>.srcs/…` 这些前缀——**别去记这个形状**），
返回值是那个 `.bd` 的路径而不是新文件，而且它**不接受 `-force`**（`Unknown option '-force'`）。
共同点是里面**没有 `.hwh`/`.xsa`/`.dt`**（几次一致）：它不是 hw handoff 的出口。
`.hwh` 属于 BD 的输出产物那一类，第一次用之前在这台机器上把它的实际路径与扩展名取出来
（`generate_target`/输出产物目录）再写脚本，不要照抄别处的目录结构。

`write_hw_platform` 的形式先问一次（`-help`），本机实测的三条：
只有一个位置参数（输出文件名），多传 `[get_files top.bd]` 报 `Too many positional options`；
**先前这里写"必须先设 `platform.name`/`platform.board_id`，否则报 User Exception"——在
一个只做了 BD、两个属性都没设的工程上跑 `write_hw_platform -fixed -force out.xsa`：rc=0，
文件也真生成了（1502 字节）**，所以不要把"先设 platform.*"当 precondition 引用（判成功只有一招：看文件在不在、多大）。
`-include_bit` 也不是"一条提示后继续"：同一工程没跑过 bitstream 时它是
`ERROR: [Common 17-69] Command failed: Unable to get BIT file from implementation run. Please ensure
implementation has been run all the way through Bitstream generation.`，**rc=1 且不产出 .xsa**。
同一条失败在不同前置状态下给的文本并不一样（这里是 `17-69` 的 ERROR，另处见过
`INFO: [Projectvivado 1-1937] No bit file available…` 的形状），两者关系没有可引的证据，
所以判据只认"返回码 + 文件在不在"，不认消息文本。
**同一族的 `1-xxxx` 在本机出现过两个类别名**：上面 §2.1 那条 `upgrade_project` 是
`[Project 1-1969]`，导出这一族是 `[Projectvivado 1-1937]` / `[Projectvivado 1-1040]`。
为什么不同本机没有解释，所以**按消息文本搜，别按类别名搜**——按 `Project` 搜会漏掉
导出这一族的失败读数。

**两个属性都设了也不保证出 `.xsa`。** 本机一个 Zynq7 工程在这之后仍然失败，报的是
`ERROR: [Projectvivado 1-1040] Failed to get Source File object for dynamic region BD` 与
`ERROR: [Platform 74-31] Error parsing hpfm stream.`，目录里一个 `.xsa` 都没有
（BD 的输出产物/hwh 不齐时就卡在这里）。所以判"导出成功"只能是**去看文件在不在**，
不是看命令返回；顺带一条纠正：**`write_hw_platform` 没有 `-return_string`**——本机两次都是
`ERROR: [Common 17-170] Unknown option '-return_string'`（`-help` 的选项表里也没这个开关）；
它正常返回的是**写出的路径字符串**。先前这里记的"回 `TCL_TRUE`"是误读，删掉。

规则：

- **`.bit` 与 `.xsa/.hwh`、`.dtbo` 必须同一次导出。** 分别导出 = 地址与中断映射可能来自两个
  版本，表现是 PS 侧读寄存器不报错但值不对。落地做法：把这三件一起放进一个带时间戳的目录，
  并在记录里写它们的哈希（哈希只回答"文件有没有换"，不回答"板上跑的是不是它"，
  后者见 `board-bringup.md` §1）。
- 换 part 或换工具小版本之后，先 `upgrade_project`，再 `validate_bd_design` + 重跑实现，
  不要假设旧工程在新工具里产物等价。
- **IP 的参数默认值会变。** `report_ip_status` 告诉你哪些 cell 需要处理。改参数前要存的不是
  "一条命令的快照"，而是**逐个名字**的读数：`get_property CONFIG.* [get_bd_cells dma0]` 这种
  通配写法**不会展开**，实测静默返回空——照着它做前后对比，你 diff 的是两个空表。可用的是
  先 `list_property [get_bd_cells dma0]` 把 `CONFIG.` 开头的名字列出来（本机这个 IP 有 26 个），
  再按名字取（`get_property CONFIG.c_include_sg [get_bd_cells dma0]` → `1`），
  或者一次倒全部：`report_property -return_string [get_bd_cells dma0]`。

## 4. 常见的"改了没生效"

| 症状 | 先看 | 别做 |
|---|---|---|
| BD 里改了 IP 参数，板上行为没变 | 是否重新生成输出产物并重启了 run；`validate_bd_design` 是否报错被忽略 | 别用"再编一次"当检查，看这次的日志有没有真的跑 |
| **下一个会话里 BD 改动全不见了**（cell、地址、连接一起为空） | 有没有 `save_bd_design`。本机一组读数：一个只做了 create/connect/validate 的会话结束后，`.bd` 仍是 **317 字节**的桩；`open_project` + `open_bd_design` 之后 `get_bd_cells *` 给 **0**、`get_bd_intf_pins ps7/*` 给 **0**、`get_bd_addr_spaces` 为空，**而 `create_bd_cell` 照样 rc=0**（于是你在新会话里"又建了一遍"，谁都没报错）；同一次补一句 `save_bd_design` 之后，同一个文件变 **2186 字节** | 别拿"命令没报错"判断改动还活着；先数 cell，再看地址 |
| 新增端口综合后被剪掉 | 端口是否连到 BD 外部/顶层是否保留（未连的顶层端口会被优化） | 别加 `keep` 来掩盖没连这件事 |
| 约束突然命中 0 个对象 | cell 改名、`make_wrapper` 之后层级多了一层 | 别改约束正则来"让它命中"，先确认层级 |
| 地址对不上 | `assign_bd_address` 之后是否又手动挪段；导出是不是改之前的 | 别手改地址去迁就软件 |
| 同一份源被编进去两次 | `get_files` 与 `report_compile_order` 的输出对不上 | 别靠文件名先后猜 |

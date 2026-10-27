# 01 一条命令到位流：Tcl 构建

## 1. 先讲原理：一位位流是怎么来的

FPGA 上没有"编译后就跑"这回事。从 RTL 到板上跑的比特流，中间是四个不可跳过、且**每一步都可能失败**
的阶段：

1. **综合（synthesis）**：把 Verilog 变成由查找表、触发器、进位链、块 RAM 构成的网表。
2. **实现（implementation）**：优化 → 布局 → 布线。只有到了这一步，"这条路径要几纳秒"才是实测值——
   综合阶段的延时全是估算。
3. **比特流（bitstream）**：把布局布线的结果编成器件能加载的文件。
4. **硬件平台（XSA）**：把 PS 侧的配置（时钟、外设、引脚复用）连同位流一起导出，给软件工具链用。
   位流与 XSA **必须来自同一次实现**，否则软件按一套引脚/时钟跑、硬件是另一套。

`build/tcl/build_system_axigpio.tcl` 把这四步串成一条命令，并把该留的报告落在 `build/` 里
（文件头 `:3-6` 自己列了产出清单）。

## 2. Tcl 只需要五个语法点

Vivado 的命令行就是 Tcl 解释器，脚本里出现的东西只用到这几条规则：

| 写法 | 含义 | 工程里的例子 |
|---|---|---|
| `set x value` | 赋值；变量读出来是 `$x` | `set part xc7z020clg484-2`（`:16`） |
| `[ 命令 ]` | **命令替换**：先执行方括号里的命令，把它的返回文本代回原位 | `[file join $root build]`（`:17`） |
| `{ ... }` | 不做替换的原文块，用于 `if { ... }` 的条件与 `list` | `if {![file exists $bit]} {` |
| `$::env(NAME)` | 读环境变量——脚本的可调项全部从这里进来 | `if {[info exists ::env(VP_PROJ_SUBDIR)] && ...}`（`:13`） |
| 一行一条命令 | 没有分号也无所谓；换行就是分隔 | 全文 |

两个和 shell 混用时最容易踩的点：`$()` 在 Tcl 里**不存在**，只有 `[]`；`$x` 是取变量，
`$::env(x)` 才是环境变量。

## 3. 逐步拆开这个脚本

### 3.1 定位自己，再定位仓库根

```tcl
set root [file normalize [file join [file dirname [info script]] .. ..]]   # :11
set outdir [file join $root build]                                          # :17
```

`[info script]` 是脚本自己的路径，往回两级就是仓库根。**为什么非要这样算**：脚本里所有路径都必须
相对于工程根，写死绝对路径会让这份交付物在别人的机器上直接不可用（仓库里有一条机检
`grep` 绝对路径的审计，交付层要求 0 命中）。
代价是"放错目录就指错"：同目录曾有两支兄弟脚本按往回**一级**算根，结果 `add_files` 指向不存在的
目录而**退出码仍是 0**——脚本"成功"跑完，工程里一个源文件都没有。教训是：
**任何构建脚本要在结尾自查它自报的产物数量**，而不是相信退出码。

### 3.2 建工程、导源、两块 XDC 的分工

```tcl
create_project $proj_name $proj_dir -part $part -force          # :21
foreach d {util clocks video process process/rotate process/zoom process/bilin axi hdmi eth} { ... }
add_files -norecurse $rtl_files                                # :30
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]
set cgxdc [add_files -fileset constrs_1 -norecurse .../clock_groups_impl.xdc]
set_property used_in_synthesis false $cgxdc                     # :37
set_property used_in_implementation true  $cgxdc
```

- `target_language Verilog`（`:22`）钉死导出语言，避免工程把网表导成 SystemVerilog 再被别的工具误读。
- `-norecurse`：只收点名的文件，不让 Vivado 顺着目录结构把 `sim/` 里的台架也收进综合。
- **两块 XDC 为什么要拆开**：`rk_zynq7020.xdc` 是引脚与真实时钟定义，综合阶段就要看见（推断
  IO 基元与时序约束范围）；`clock_groups_impl.xdc` 讲的是"这几个时钟互相异步"，它只在实现阶段
  有意义，综合阶段挂上反而会让综合按错误的时钟关系做复制/复制选择。这就是 `used_in_synthesis false`
  与 `used_in_implementation true` 的用途。
- 同一族还有两把"待验收"的窗：`r116_rgmii_input_window.xdc`（`:57-63`）与
  `r119_hdmi_source_window.xdc`（`:75-81`），都由环境变量开关。默认**不进构建**——挂上它们会
  改变 hold 判定，必须先由门禁与名册裁决（详见 `08-constraints-and-timing.md`）。

### 3.3 处理系统（PS）不是 RTL，是 BD

```tcl
create_bd_design design_1                                        # :84
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 ...  # :87
```

Zynq 的 PS 是硬核，PL 侧只留一个接口 IP。`apply_bd_automation` 会读板级预设（DDR、MIO、
GP 口位宽），把 PS7 的配置一次设好。**AXI GPIO 就在这个过程中挂到 GP0**——文件名里的
`axigpio` 说的就是这件事：本工程的控制字走 `axi_gpio` 而不是自造从设备，
代价是位宽受限、好处是不动 BD 也能加控制位（见 `02-gamma-principle-to-rtl.md` 第 5 节）。

### 3.4 跑综合，并且**验它真跑完了**

```tcl
launch_runs synth_1 -jobs 4                # :306
wait_on_run synth_1                        # :307
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { ... }   # :308
```

`wait_on_run` 只保证"跑这件事结束了"，**不保证成功**。必须读 `PROGRESS` 或 `STATUS`；
只查 `wait_on_run` 的写法会把一次失败的综合当成正常继续，最后在布线那步报一句完全看不出根因的错。

### 3.5 实现策略与两个钩子

```tcl
if {[info exists ::env(IMPL_STRATEGY)] ...}          # :317  换实现策略
if {[info exists ::env(IMPL_POST_PLACE_HOOK)] ...}   # :328  布局之后、布线之前插一段自定义 tcl
if {[info exists ::env(IMPL_PRPO)] && ... eq "1"}    # :341  强制复制高扇出网的物理优化
```

这三处是"时序专项"实验的入口：策略档、布线下扫描、复制驱动（`phys_opt_design
-force_replication_on_nets`）都是**单变量**地换，其余字节不动，否则量不出收益归谁。

### 3.6 出位流、开实现、落报告

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4      # :353
open_run impl_1                                          # :361
report_timing_summary -file [file join $outdir timing_summary.rpt]   # :362
report_utilization  -file [file join $outdir utilization.rpt]        # :363
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]  # :371
```

- `open_run impl_1` 之后再 `report_*`：不打开这次实现的内存态，报告读的就是**上一版**工程，
  数字会自己骗人。
- `-include_bit` 让 XSA 里带位流，软件工具链刷新板时能一次性对上号；
  `:356-358` 会先确认位流文件真的存在再往下走。
- 报告族里除了时序与资源，还有 `cdc.rpt` / `methodology.rpt` / `power.rpt` /
  `route_status.rpt` / `clock_util.rpt`（文件头 `:5-6` 声明），
  外加两把自用的机检产物 `width_warnings.txt`、`multi_driven.txt`（`:398`、`:403`）——
  它们是"位宽截断"和"一个信号被两个模块驱动"这两类静默错误的来源清单。

## 4. 怎么自己跑一遍

```bash
# 一次性：告诉脚本 Vivado 在哪
export VP_VIVADO_BIN=/path/to/Vivado/2025.2.1/bin
cd build/tcl && "$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build_system_axigpio.tcl
```

（`report/build.md:58` 给的是同一条命令的 Windows 写法；`build/r100_chain.sh:26` 是夜里链子里的调用形式。）
产物落在 `build/`：`system.bit`、`system.xsa`、上面那几份报告。
不想碰正式工程与正式产物时，用环境变量把两条路径各自挪开：

```bash
VP_PROJ_SUBDIR=vivado_system_probe VP_OUTDIR=build/probe_dir bash build/roll_isolated.sh
```

`build/roll_isolated.sh` 的做法值得学：**不复制那 400 行构建脚本**（两份一样的脚本必然漂），
而是原地用 sed 把 `set outdir` 换成隔离目录，临时脚本仍留在 `build/tcl/`
（`:12-14`，"因为脚本里的 `root` 是按自己所在位置往回两级算的，换个目录就会指向别处"）。

## 5. 三种最常见的失败长相

| 现象 | 真实含义 | 先看哪一行 |
|---|---|---|
| `Cannot find design unit` | 台架/顶层不在编译清单里，通常是新加了文件却没进清单 | `build/sim/run_one.sh:64-65` 的 `find` 口径 |
| 脚本退出码 0，但工程里没有源文件 | 根路径算错一级 | `:11` 与脚本所在目录 |
| `timing_summary.rpt` 里的数和板上表现不符 | 报告和位流不是同一次实现 | `open_run` 是否在 `report_*` 之前（`:361`） |

小结：这条命令的全部要点是"路径自算、阶段自证、报告跟在 `open_run` 之后、实验只换一个变量"。
下一步：`02-gamma-principle-to-rtl.md`。

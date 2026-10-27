# 50 · Tcl 教程：从零到能读懂并改本项目的构建脚本

> 读者假设：会写一点 C，没学过 Tcl，也没系统用过 Vivado 命令行。
> 目标：带你在 `vivado -mode tcl` 里跑通最小例子，然后能独立看懂本仓库
> `build/tcl/*.tcl`、`sim/*.sh`、`build/gates.sh`、上板的 `*.tcl`，并且能改。
> 全文只讲事实与踩过的坑，不讲排场。引用的行号都是我刚 Read 过的。

## 1. Tcl 是什么、为什么 FPGA 工具全用它

Tcl（"Tool Command Language"）是一个**解释器**：给它一行文本，它就执行一行。Vivado、Vitis 的
xsdb、Quartus 的 `quartus_sh` 这些 EDA 工具都拿它当脚本语言，因为它们真正想要的是"能动态调用
内部命令的命令行"，而 Tcl 的设计恰好是 **一切皆命令，命令的语法由命令自己解释**——和 C 差别很大。

### 1.1 命令即函数：没有"表达式"这种特殊东西

C 里 `a = b + 1;` 是表达式、`+` 是运算符；Tcl 里没有运算符，只有一条命令 `+`，写作
`set a [expr {$b + 1}]`。一条 Tcl 语句永远是 `命令名 参数1 参数2 ...`，参数间用**空白**分隔。
`set`/`puts`/`if`/`expr`/`incr`/`lappend`/`string`/`file`/`info`/`catch`/`source` 都是命令，
没有谁是"关键字"。所以 `if` 后面那一大块括号只是 `if` 的普通参数，由 `if` 自己解析——理解这点，
后面所有"为什么要加大括号"的问题都有答案了。

### 1.2 `{}` 与 `[]` 与 `$`：三者作用完全不同

这是新人最容易混的地方，逐条对上：

| 符号 | 名字 | 作用 | 一句话记忆 |
|---|---|---|---|
| `$name` | 变量替换 | 把变量的**值**取出来 | "我要它的内容" |
| `[cmd ...]` | 命令替换 | 先执行方括号里的命令，把它的**返回值**塞回原处 | "先算这段，把结果放这儿" |
| `{...}` | 引用（bracing） | 里面的 `$` 和 `[]` 在**这一层**不被展开，整块原样交给命令 | "这一坨别动，原文递过去" |

例子（可直接粘进 `vivado -mode tcl`）：

```tcl
# 例 1：$ 取内容，[] 执行并拿返回值
set a 5
set b [expr {$a * 2}]     ;# [] 先跑 expr，把 10 返回给 set b
puts "a=$a b=$b"          ;# 打印：a=5 b=10
```

`{}` 与 `" "`（双引号）的区别很关键：双引号里的 `$` 和 `[]` **会**被展开，大括号里的**不会**
（除非命令自己再 eval）。所以 `set b [expr {$a * 2}]` 用 `{}` 包住算术，是让 `expr` 自己处理 `$a`，
而不是被外层提前替换成一串数字（后者既慢又容易被特殊字符坑到）。

### 1.3 set / puts / if / for / foreach / proc：六个就够日常

```tcl
# 例 2：set 赋值 + puts 输出（puts 默认带换行，"puts -nonewline" 不带）
set name "zynq_video_sys"
puts -nonewline "project="   ; puts $name
# 例 3：if / elseif / else——判断与条件表达式都写在 {} 里
set wns -0.42
if {$wns < 0} { puts "时序红（WNS=$wns）" } elseif {$wns == 0} {
    puts "刚好卡平" } else { puts "时序满足" }
# 例 4：C 风格的 for
for {set i 0} {$i < 3} {incr i} { puts "i=$i" }
# 例 5：foreach——Tcl 里最常用，遍历列表
foreach d {util clocks video hdmi eth} { puts "dir=$d" }
# 例 6：proc 定义函数；return 返回；参数列表里可写默认值 {c 0}
proc max3 {a b {c 0}} {
    if {$a > $b && $a > $c} { return $a }
    if {$b > $c}            { return $b }
    return $c
}
puts "max=[max3 4 9 7]"     ;# max=9
```

### 1.4 列表（list）：Tcl 的"数组"其实是字符串

Tcl 的列表就是一个**用空格分隔的字符串**，但里面有嵌套和特殊字符时用 `{}` 包住元素。
它不是 C 的数组，别用下标思维，用列表命令族：`list` / `lappend` / `lindex` /
`llength` / `lsearch` / `foreach`。

```tcl
# 例 7：增删查一个列表
set files {}                       ;# 空列表
lappend files src/rtl/top/pl_video_top.v
lappend files src/rtl/top/system_top.v
puts "共 [llength $files] 个文件，第一个是 [lindex $files 0]"
if {[lsearch -exact $files src/rtl/top/system_top.v] >= 0} {
    puts "有顶层"
}
```

字符串相关命令：`string length` / `string match`（glob 通配，如 `*S00*`）/
`string tolower` / `split` / `format`。本项目脚本里到处是 `string match` 和 `format`。

### 1.5 大括号不能省，分号与换行的规则

**规则一：`if` / `for` / `foreach` / `proc` 的代码块必须用 `{}` 包住，且 `{` 必须和
命令在同一行。** 因为 `{` 是"这条命令的一个参数"的开头；你把 `{` 换到下一行，解释器
认为 `if {$x}` 已经是一条完整命令，于是报错或做出你没想到的事。这正是"从 C 过来最
先撞的墙"：C 的 `{` 在哪都行，Tcl 不行。

```tcl
# 例 8：错误示范——把 { 换行
if {$wns < 0}
{                      ;# ← 解释器会在这里报 "missing close-brace" 或把 { 当命令
    puts red
}
# 正确写法：{ 紧跟在条件后面同一行
if {$wns < 0} { puts red }
```

**规则二：换行 = 一条语句结束。** 默认情况下，一个换行就代表命令结束，不需要分号。
分号 `;` 的作用是"把多条命令写在同一行"。`#` 开头是整行注释，` ;#` 是行尾注释
（本项目脚本满屏的 ` ;#` 就是行尾说明）。

```tcl
# 例 9：分号把多条塞一行；;# 后面是注释
set a 1; set b 2; puts [expr {$a + $b}]   ;# 打印 3
```

### 1.6 catch：EDA 脚本的"try"，也是本项目很多判错的来源

Tcl 没有 try/throw，取而代之的是 `catch {代码块} 错误信息变量`：块里出错 `catch` 返回非 0，
并把错误文本写进变量。Vivado 命令大量用 `catch` 把"这个命令可能不支持"吞掉。

```tcl
# 例 10：catch 吞掉一个可能失败的命令
if {[catch {report_power -file /tmp/nope.rpt} err]} {
    puts "report_power 失败了：$err"
}
```

⚠ 双刃剑：`catch` 吞了错，退出码就正常了——本项目那条"根目录少解析一层却仍 exit 0"
的坑（第 3 节）本质上就是错误被吞后没人看返回值。**养成"跑完自己去核对产物时间戳"的习惯，
别信退出码。**

### 1.7 怎么开始敲

Windows（PowerShell/CMD，反斜杠）与 Git-Bash（正斜杠）都进同一个交互 Tcl：

```
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat -mode tcl      # CMD/PowerShell
/d/Software/Vivado/2025.2.1/Vivado/bin/vivado -mode tcl          # Git-Bash
```

提示符 `%`/`>` 后直接粘例 1~例 10。`exit` 退出。

## 2. Vivado 非工程流 vs 工程流：同一件事的两种写法

Vivado 干活有两条路，理解它们的区别，你才看得懂仓库里为什么有两种脚本。

### 2.1 工程流（project mode）——本项目主线用这个

先"建一个 `.xpr` 工程"，把 RTL / 约束 / Block Design 登记进去，再用 `launch_runs` 让
后台跑综合/实现。好处是可复跑、可换策略、产物落在固定的 `.runs` 目录里。核心命令序列：

```tcl
create_project myproj ./projdir -part xc7z020clg484-2 -force
add_files -norecurse [glob src/rtl/*.v]                 ;# 加 RTL
add_files -fileset constrs_1 -norecurse top.xdc         ;# 加约束
set_property top system_top [current_fileset]           ;# 指定顶层
launch_runs synth_1 -jobs 4                             ;# 后台综合
wait_on_run synth_1                                     ;# 阻塞等它跑完
open_run impl_1                                         ;# 把实现的 design 读进内存
report_utilization  -file build/utilization.rpt
report_timing_summary -file build/timing_summary.rpt
write_bitstream -force build/system.bit
```

逐条对应本项目真实行（都在 `build/tcl/build_system_axigpio.tcl`）：建工程 `:9`、加 RTL `:18`、
加约束且只对实现生效 `:24`~`:26`、综合并等 `:243`~`:244`、实现到出 bit `:277`~`:278`、
`open_run`+出报告 `:285`~`:294`、导出含 bit 的硬件平台 `:295` `write_hw_platform ... system.xsa`。

### 2.2 非工程流（core / no-project mode）：一次性算完就撤

不开工程，直接 `read_verilog` → `synth_design` → `opt_design` → `place_design` →
`route_design` → `report_*`，全在一个进程里线性跑完。适合探针、小规模对比。本项目微探针
`build/tcl/micro_rd.tcl` 就是这一类：

```tcl
# build/tcl/micro_rd.tcl:39~:55（节选）
if {[catch {synth_design -top $top -part xc7z020clg484-2} e]} { puts "SYNTH_FAIL $e"; exit 1 }
report_utilization -file [file join $dir util_m$mode.rpt]
if {[catch {opt_design} e]}    { puts "OPT_FAIL $e"; exit 1 }
if {[catch {place_design} e]}  { puts "PLACE_FAIL $e"; exit 1 }
if {[catch {phys_opt_design -directive AggressiveReplication} e]} { puts "PHYSOPT_SKIP $e" }
if {[catch {route_design} e]}  { puts "ROUTE_FAIL $e"; exit 1 }
puts [report_timing -delay_type max -max_paths 12 -nworst 2 -return_string]
```

### 2.3 为什么要两种写法

工程流的 `launch_runs` 是**后台多作业**（能 `-jobs 4`、能单独 `reset_run` 重跑某步、产物结构
固定），所以正式构建/换策略/留报告都走它；非工程流的 `report_timing` 能直接 `-return_string`
把结果拿进 Tcl 变量继续判断（`build/tcl/micro_rd.tcl:53`、`:55`），适合"我只要一个数、不想开
工程"。注意 `read_xdc`/`current_project`/`open_run` 只在工程流里有意义，报 "no current project"
多半是流选错了。

## 3. 本项目的构建入口（逐段讲 build/tcl 真实脚本）

先 `ls build/tcl`（我实际看到的），规范入口只有一个：

```
build/tcl/build_system_axigpio.tcl      ← 今天唯一在用的全量构建
build/tcl/build_system.tcl              ← ⚠ 坏脚本（少解析一层，见下）
build/tcl/build_pl_full.tcl             ← ⚠ 同类坏脚本
build/tcl/create_project.tcl            ← ⚠ 同类坏脚本（V7 遗留）
build/tcl/synth_pl_only.tcl             ← ⚠ 同类坏脚本
build/tcl/sweep_impl_strategy.tcl       ← 实现策略扫描
build/tcl/micro_rd.tcl                  ← 非工程流探针
build/tcl/program_pl.tcl ps_jtag_boot.tcl set_src.tcl program_and_check.tcl  ← 上板
build/tcl/hold_paths.tcl crit_path.tcl cdc_who.tcl read_run_result.tcl       ← 只读报告
```

仓库自己的说明在 `build/tcl/README.md:8`~`:23`，我把它的结论原样转述给你：
**只认 `build_system_axigpio.tcl`，别信退出码。**

### 3.1 build_system_axigpio.tcl 做哪几步

从仓库根跑（脚本内部全相对路径）：

```
D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat -mode batch -source build\tcl\build_system_axigpio.tcl
```

它依次做：
1. **定位根目录** `:2` `set root [file normalize [file join [file dirname [info script]] .. ..]]`
   ——`[info script]` 得自身路径，`[file dirname]` 拿到 `build/tcl`，再 `.. ..` 退两级到仓库根（正确层数）。
2. **建工程 + 收集 RTL** `:9`~`:18`：`foreach d {util clocks video ... eth}` + `glob` 拼清单，
   `add_files`；参数来自脚本头部 `$part`（`:5`）、`$proj_dir`（`:3`）。
3. **建 Block Design**（PS7 + 三路 AXI GPIO + 两路 interconnect）`:28`~`:195`。
   三路 GPIO 的基址在 `:187`~`:195` 被**钉死**成 `0x41200000 / 0x41210000 / 0x41220000`，
   紧接着 `:202`~`:216` 自己回读地址图核对，错就 `exit 1`（第 6 节会用到这三个地址）。
4. **只建 BD 的快出口子** `:222` `if {[lindex $argv 0] eq "bd_only"}`——
   参数通过 `-tclargs` 传进来：`... -source build\tcl\build_system_axigpio.tcl -tclargs bd_only`。
5. **综合 / 实现** `:243`~`:278`：`launch_runs synth_1` → 判 PROGRESS → `launch_runs impl_1`。
   实现策略从**环境变量** `IMPL_STRATEGY` 选（`:254`~`:260`），见第 4 节。
6. **出报告**：bit 复制 `:284`，`open_run impl_1` 后落
   `timing_summary.rpt`/`utilization.rpt`/`cdc.rpt`/`methodology.rpt`/`power.rpt`/
   `route_status.rpt`/`clock_util.rpt`（`:286`~`:294`），`write_hw_platform` 出 `system.xsa`（`:295`）。
7. **顺带扫多驱动/宽度警告** `:304`~`:333`：把综合日志里的 `Synth 8-689`、`multi-driven net`
   数出来写进 `width_warnings.txt`、`multi_driven.txt`，供门禁第 8 项读。

报告落点：`$root/build/`，也就是 `build/`。你构建完，去 `build/` 里核对这些 `.rpt` 的时间戳。

### 3.2 ⚠ 那个"die 在 add_files 却仍 exit 0"的坑

这就是第 1.6 节说的"错误被吞 + 没人看返回值"的真人版。看两个脚本的第 2 行：

```tcl
# build/tcl/build_system_axigpio.tcl:2   （正确：退两级到仓库根）
set root [file normalize [file join [file dirname [info script]] .. ..]]

# build/tcl/build_system.tcl:2            （错误：只退一级，停在了 build/）
set root [file normalize [file join [file dirname [info script]] ..]]
```

`build_system.tcl` 的 `[file dirname [info script]]` 是 `build/tcl`，再 `..` 只到 `build`，
于是 `$root` 变成 `.../Video_Processing/build`，`$root/src/rtl/...` 根本不存在。

**它死在哪：** `build/tcl/build_system.tcl:18` `add_files -norecurse $rtl_files`。
因为 `$root` 错了，`:14`~`:16` 的 `glob -nocomplain [file join $root src rtl ...]` 找不到
任何文件（`-nocomplain` 让找不到也**不报错**，只返回空），`$rtl_files` 成了空列表 /
指向 `build/src/...` 的不存在路径，`add_files` 抛错；再往后的 `:19` 加约束同样指向不存在的路径。

**为什么退出码还是 0：** `add_files` 抛的是 Tcl 运行时错误，脚本从没用 `catch`/返回值去
检查它，批处理模式下 Vivado 把错误打到 stdout 后，`-source` 的这层调用并不会把非零码
回传给 shell。README 里也点名了这件事——`build/tcl/README.md:19`~`:23`：

> 两个"根目录少解析一层"的陷阱脚本：`build_system.tcl`、`build_pl_full.tcl` 用
> `[file dirname [info script]] ..`（少一层 `..`），`add_files` 指向 `build/src/...` 而
> **报错之后仍然 exit 0**（ISSUES #22 / #41 记过两次）。同一类 bug 在 `create_project.tcl`、
> `synth_pl_only.tcl` 里也还在。

在 `build/tcl` 里 `grep 'file dirname \[info script\]'` 数一遍第 2 行你会发现：
`build_bitstream.tcl:8`、`build_pl_full.tcl:2`、`fix_bd_and_top.tcl:2`、`create_project.tcl:9`、
`synth_pl_only.tcl:3` 都是"少一层 `..`"，其余（`build_system_axigpio`、`micro_rd`、`sweep`、
`program_*`、`hold_paths`）都是正确的 `.. ..`。**只跑 `.. ..` 那一族。**

**怎么发现自己踩到了**（任一即可，不要只信退出码）：① 看 stdout 有没有 `add_files ... does
not exist` / `[Vivado 12-3163]`（特征就是"报错在 add_files，却像正常结束"）；② 构建完去
`build/` 核对报告时间戳，没更新 = 没真跑成；③ 抄对根目录后紧跟一行自检
`if {![file exists [file join $root src rtl]]} { puts "ROOT WRONG: $root"; exit 1 }`——
少解析一层时它立刻红，退出码也就真实非零了。（另注：`build_system.tcl` 还会用 `puts $fp`
**生成** `system_top.v`（`:113`~`:209`），且没有三路 AXI GPIO，是 V7 旧流程，别拿它构建。）

## 4. 实现策略与时间预算

### 4.1 策略是什么、怎么在 Tcl 里选

实现（implementation）阶段有多套预置"策略"（strategy），如 `Performance_Explore`、
`Performance_ExplorePostRoutePhysOpt`、`Performance_ExtraTimingOpt`、`Performance_BalanceSLRs`、
以及默认的 `Vivado Implementation Defaults`。策略只是给 place/route 一组旋钮（directive），
不改你的网表。

工程流里选策略有两种写法。① 直接给 run 设属性（`build/tcl/sweep_impl_strategy.tcl:43`）：
```tcl
set_property strategy Performance_Explore [get_runs impl_1]
```
② 本项目的做法：从**环境变量**读，且一定要把名字打进日志。看
`build/tcl/build_system_axigpio.tcl:254`~`:260`：
```tcl
if {[info exists ::env(IMPL_STRATEGY)] && $::env(IMPL_STRATEGY) ne ""} {
  if {[catch {set_property -dict [list strategy $::env(IMPL_STRATEGY)] [get_runs impl_1]} e]} {
    puts "BUILD_STRATEGY_REJECTED $::env(IMPL_STRATEGY) : $e"
    exit 1
  }
}
puts "BUILD_STRATEGY [get_property STRATEGY [get_runs impl_1]]"
```
Git-Bash 里就这么传：`IMPL_STRATEGY=Performance_Explore vivado -mode batch -source build/tcl/build_system_axigpio.tcl`。
脚本头部 `:249`~`:253` 解释了为什么不做成硬编码：**产物必须自己带着出身**——
同一个 RTL 在不同策略下数字不同，几个月后没人记得手里这颗 bit 是哪档出来的，所以策略名
要进日志。

### 4.2 为什么换策略 WNS 像掷硬币

WNS（Worst Negative Slack，最差负裕量，ns，`<0` 即违例）。同一份网表、只换策略，WNS 会上下跳，
因为策略改的是**布局/布线的搜索方向**，而拥塞、扇出、SLR 分布对每档的反馈不同——工具没有
"最优解"，只有"这一档启发式找到的解"。`build/tcl/build_system_axigpio.tcl:236`~`:241` 的注释
就是实测：`Performance_ExtraTimingOpt` 把某组从 −0.485 抬到 +0.788（转好）但另一条仍红；历史
结论 "R07：`Performance_Explore` 与默认策略产出逐位相同的 bit ⇒ 那不是个可选项"。**换策略前先
看是不是 RTL 的锅**（4.3），别拿策略救本质性的长路径。

`build/tcl/sweep_impl_strategy.tcl` 把这件事系统化：`open_project`（`:21`）复用已有工程，
`foreach s $strats`（`:39`）逐个 `reset_run` → 设策略 → 只重跑 `impl_1`（不重综合），
WNS/WHS/失败端点/是否全满足/功耗写进带时间戳的汇总表（`:28`、`:36`、`:91`）。两处教训值得抄：
报告**优先读磁盘上构建自己那份** `*_timing_summary_routed.rpt`（`:59`~`:65`，`:56`~`:58` 说
2025.2.1 里 `-check_summary_only` 不存在，重跑反而毁掉已完成的数）；收尾把策略**还原**
（`:97`），免得下次构建悄悄继承了最后扫过的那档。

### 4.3 用报告定位失败端点属于哪个模块

WNS 是个数字，你要知道**是谁**违例。三条命令配合：

```tcl
report_methodology -file build/methodology.rpt   ;# 方法学问题（CDC、锁存器、超限扇出等）
report_timing -setup -late -name_from_pins \
    -max_paths 20 -nworst 5 -file build/setup_late.rpt   ;# 关键：-late = 时序收敛后的布线级
```

`build/tcl/build_system_axigpio.tcl:290` 就是构建顺手落 `methodology.rpt`。看时序报告时每条路径
有 `Source`/`Destination` 引脚名，形如 `u_pl/u_rd/u_sched/.../reg/Q → u_pl/.../RAMB36.../ADDRARDADDR[5]`，
前缀 `u_pl/…` 直接告诉你在哪个模块实例下。按模块聚合用 `report_utilization -hierarchical`
（`build/tcl/micro_rd.tcl:45`）；精确点名某条路用 `get_pins -hier -filter {NAME =~ *ADDRARDADDR*}`
再 `report_timing -to $pins`（`build/tcl/micro_rd.tcl:58`~`:62` 是活教材）。`-late` 别漏：`-early`
是综合级估算，只有 `-late` 是布线后真实数字。

## 5. 仿真侧的 Tcl：xsim / xelab / xsim -tclbatch

### 5.1 三件套的分工

- `xvlog`：把 Verilog 源**编译**进工作库（`xsim.dir/work`）。
- `xelab`：把某个 testbench ** elaborate**（连线、解析参数）成一个可执行快照 `-s snap`。
- `xsim`：**跑**那个快照。`xsim snap -R` 从头跑到 `$finish`；
  `xsim -tclbatch run.tcl` 进 Tcl 控制台，能 `run -all`、看波形。

在 `xsim` 交互/批处理控制台里的 Tcl 命令（与 Vivado 那套是同一语言，不同命令集）：

```tcl
run -all                      ;# 跑到台架自己 $finish
get_objects -r *              ;# 列出可访问的信号对象（调试用）
add_wave /add_layer           ;# 加波形（GUI/xsim 脚本里）
get_value u_pl/status         ;# 取某信号当前值
```

### 5.2 本项目的两个仿真入口

- **全量回归** `sim/run_sim.tcl`：用 Vivado 的 Tcl 调 `exec xvlog/xelab/xsim`，跑法
  `vivado -mode batch -nojournal -log sim/xsim.log -source sim/run_sim.tcl`（`sim/run_sim.tcl:6`）。
  它 glob 整棵 `src/rtl` + `sim/tb_*.v` 一次编译（`:34`~`:59`），逐台架 `xsim` 并 grep `PASS/FAIL`
  汇总（`:106`~`:123`）；判据很硬：**没有 PASS/FAIL 断言行就判失败**（`:116`~`:121`），防"什么都没测却绿了"。
- **单台架快速跑** `sim/run_one.sh <tb名>`：shell 脚本不是 Tcl，但门禁凭据是它产的，必须懂（见 5.3）。

### 5.3 为什么台架用 shell 包一层：编译前盖 md5

关键需求：门禁第 15 项要证明"这份报告是**当前这份树**跑出来的"，而不是拿昨天的旧报告冒充。
做法是**在编译发生之前**记下被测源码的指纹。看 `sim/run_one.sh:36`~`:47`：

```bash
# sim/run_one.sh:43~:47 —— 编译（第 48 行 xvlog）之前先写 prov.txt
RTLALL=$(cd "$ROOT" && find src/rtl -name '*.v' | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-12)
{ echo "top_md5=$(md5sum $ROOT/src/rtl/top/pl_video_top.v | cut -c1-12)"
  echo "tb_md5=$(md5sum $ROOT/sim/$TB.v 2>/dev/null | cut -c1-12)"
  echo "rtl_md5=$RTLALL"
  echo "date=$(date -Iseconds)"; } > prov.txt
$V/xvlog -f files.f > xv.log 2>&1          # ← 第 48 行，编译在 md5 之后
```

注释 `:36`~`:42` 讲清了两件事：为什么"盖"要在编译前（事后补 md5 = 把今天的指纹盖在昨天的日志
上），为什么不止 `top_md5` 一枚（改窗口级模块时 `pl_video_top.v` 一字节没动，顶层 md5 仍"对得
上"，所以再加整棵 `src/rtl` 的合指纹 `rtl_md5`）。谁消费这几枚 md5？`build/gates.sh` 的门禁第
15 项（`:264`~`:286`）：把树里的现值重算（`TOPWANT/TBWANT/RTLWANT`，`:264`~`:266`），从报告头
`sed` 出当初记的值（`TOPYES/TBYES/RTLYES`，`:267`~`:269`），三个都必须相等，且正文不能有 `FAIL `
行、必须有 `RESULT tb_v98_top_seam PASS` 汇总行（`:270`~`:286`）；任一对不上就判红。同一形状用在
`tb_edge_rim`（`:302`~`:318`）。**shell 包一层，就是要在 xvlog 之前拿到 md5 并和 run.log 绑定**——
纯 Tcl 的 `run_sim.tcl` 没有这个动作。

### 5.4 run_one.sh 里另外两个真坑（顺带记）

- `sim/run_one.sh:19`~`:23`：同一时刻只允许一个 xsim 写同一个 run 目录，否则两次跑的行
  混进一份 `run.log`，认 md5 也救不了"正文来自两个进程"。所以门口用
  `tasklist //FI "IMAGENAME eq xsim.exe"` 探活，有就 `exit 3` 拒绝启动。
- `sim/run_one.sh:30`~`:35`：文件清单**必须走 `-f files.f`**，不能拼在命令行上——台架多了
  会被 Windows 命令行长度上限截断，且 `xv.log` 里连 ERROR 都没有。而清单文件里必须写
  **Windows 正斜杠路径**（`cygpath -m`），因为命令行参数会被 MSYS 自动换算、但 `-f` 文件内容不会。

## 6. 上板调试：Vitis xsdb / hw_server

### 6.1 先起 hw_server 再起 xsdb，为什么顺序重要

`hw_server` 是**真正持有 JTAG 线缆**的进程（默认监听 TCP `localhost:3121`），`xsdb` 只是连它的
Tcl 客户端。hw_server 没起就 `connect` 会连不上（`build/board_verify.sh:73` 把"health_read 没有
输出"就归因到"hw_server 没起？"）；两个 hw_server 抢同一根线，后起的报"设备被占用"。所以顺序
永远是：**确认一个 hw_server 在跑 → 再 xsdb → 再 connect**。Vivado 工程流的 `open_hw_manager`
会自己拉起/复用一个 hw_server，这也是 `build/tcl/program_pl.tcl:14` `connect_hw_server
-allow_non_jtag` 能直连的原因。

### 6.2 targets / ps7 / ta 的层次

Zynq 的 JTAG 链在 xsdb 里是一棵树，`ta`（target handle）就是每个节点的编号：

```
xsdb% targets              ;# 列树：1 PS7(zynq) → 2 PS → 3/4 ARM 核 → 5 PL(xc7z020)
xsdb% targets -set -filter {name =~ "*#0"}   ;# 选到 A9 核 0（也可 targets 3 按编号切）
```

`targets -set N` 切换"当前操作哪个核"。本项目的 `targets -set -filter {name =~ "*#0"};
catch {stop}`（`build/tcl/set_src.tcl:18`~`:19`、`build/tcl/ps_jtag_boot.tcl:70`~`:71`）就是把
A9 核 0 选出来并暂停它，好安全地读写内存/寄存器。

### 6.3 fpga / rst -processor / ps7_init 的作用

- `rst -system` / `rst -processor`：复位整颗芯片 / 只复位处理器。`build/tcl/ps_jtag_boot.tcl:57`~`:58`
  先 `targets -set 1` 再 `catch {rst -system}`，注释 `:56` 说这是 DAP 卡住时的自救。
- `fpga build/system.bit`：把位流下载到 PL（工程流里等价物是 `program_hw_devices`，
  见 `build/tcl/program_pl.tcl:24`~`:25`）。
- `ps7_init.tcl`：Vitis/构建生成的 **PS 上电初始化脚本**（DDR 控制器、时钟、MIO 复用）。没有
  FSBL 自己跑时用它把 PS 拉起：`build/tcl/ps_jtag_boot.tcl:62`~`:67` 就是 `source $psinit` →
  `ps7_init` → `ps7_post_config`。它满屏是 `mwr -force 0XF8000008 ...` 这类寄存器写
  （`vitis/platform/hw/sdt/ps7_init.tcl:2`，`0xF8000008` 是 SLCR 解锁寄存器）——`mwr` 的实战。
  该脚本找 `ps7_init.tcl` 的顺序也值得学（`:20`~`:45`）：命令行参数 / `PS7_INIT` 变量 →
  已解出的 `build/ps7_init.tcl` → 从 `build/system.xsa`（zip，条目名 `ps7_init.tcl`）自动解包。

### 6.4 mrd / mwr 读写 PL 寄存器（用本项目真实 AXI-Lite 地址）

`mwr -force <addr> <value>` 写、`mrd -force <addr> <count>` 读。本项目三路 AXI GPIO 基址钉死在
`build/tcl/build_system_axigpio.tcl:187`~`:190`，与固件 `xparameters.h` 的
`XPAR_AXI_GPIO_0/1/2_BASEADDR`（`vitis/.../include/xparameters.h:80`、`:96`、`:112`）一致：

| 外设 | 基址 | 方向 | 用途 |
|---|---|---|---|
| axi_gpio_0 | `0x41200000` | 输出 | V7 那条 32bit 控制字（效果/阈值/片源…） |
| axi_gpio_1 | `0x41210000` | 只读 | PL 侧链路健康快照 |
| axi_gpio_2 | `0x41220000` | 双通道输出 | V8 扩展控制字（通道 1 在 +0x0，通道 2 在 +0x8） |

AXI GPIO 数据寄存器偏移（BSP `xgpio_l.h:72`~`:75`）：通道 1 数据 `+0x0`、三态 `+0x4`、通道 2
数据 `+0x8`。所以：

```tcl
# 写控制字（本项目 set_src.tcl 的真实动作，build/tcl/set_src.tcl:20~:21）
mwr -force 0x41200000 0x000B0000
puts "GPIO0 = [mrd -force 0x41200000 1]"

# 读回健康快照 / 第二条控制字两个通道
mrd -force 0x41210000 1          ;# GPIO1 输入快照
mrd -force 0x41220000 1          ;# GPIO2 通道1
mrd -force 0x41220008 1          ;# GPIO2 通道2（DATA2 偏移 +0x8）
```

⚠ `build/tcl/build_system_axigpio.tcl:89`~`:90` 与 `build/ps_app.mjs:7` 都强调：固件里这些基址
是**硬编码 literal**，BSP 不重生成 `xparameters.h`，所以地址一挪，现象不是编译失败而是"写了没
反应"——最难查那类。这就是构建脚本要 `assign_bd_address -offset` 钉死、再自己回读核对
（`:192`~`:216`）的原因。`dpc`（data program counter）打印当前 halt 的 A9 核停在哪条指令：
`stop` → `dpc` 判断固件跑飞还是卡住；`build/tcl/set_src.tcl:19` `catch {stop}` 后写寄存器、
`:22` `catch {con}` 再放开就是 halt→poke→resume。DDR 通不通也自检：`build/tcl/ps_jtag_boot.tcl:72`~`:73`
`mwr -force 0x10000000 0x5A5AA5A5` 再 `mrd` 读回比。上板推荐顺序（`build/tcl/README.md:16`、
`build/tcl/ps_jtag_boot.tcl:16`）：`ps_jtag_boot` → `program_pl` → `set_src` → 推流 → 回读。

## 7. Tcl 在 Windows / WSL / Git-Bash 下的坑

### 7.1 路径分隔符：`\` 与 `/` 混用

Tcl 认 `/`；Windows 原生工具（vivado.bat、xvlog）给的是 `\`。混用时最常见的是把
反斜杠当转义符。本项目实测的日志 `retry_open_nr.log:4`：
```
Retry open file channel in 250 ms for file: D:/Software/Vivado/2025.2.1/Vivado\scripts\builtin.tcl
```
前半 `/` 后半 `\` 拼在一起——这类混合路径在 Tcl 里要靠 `file join`/`file normalize` 统一，
别手拼。构建脚本里所有路径都用 `[file join $root src rtl ...]`
（`build/tcl/build_system_axigpio.tcl:14` 等）就是为了别踩这个。

### 7.2 `$env()` 与 Git-Bash 的路径换算

Tcl 读环境变量：`$::env(NAME)`（本项目用它读策略，`build/tcl/build_system_axigpio.tcl:254`）。
Git-Bash 里传给 Windows exe 的路径会被 MSYS 自动换算（`/d/x` → `D:\x`），但——
**这个换算不穿 `-f 文件` 的内容**。`sim/run_one.sh:33`~`:35` 就是这个真实事故：命令行参数
会换算，而清单文件里写 `/d/...` 让 xvlog 报 "Can not find file"，最后用
`printf '%s\n' $SRC | cygpath -m -f - > files.f` 把清单转成 Windows 正斜杠 `D:/...` 才对。所以给
Tcl 写绝对路径一律 `/` 或 `file join`，别把 Bash 的 `/d/...` 直接塞进 Tcl 字符串。

### 7.3 反斜杠续行：Tcl 不认，且放进 list 会变脏

Bash/C 用行尾 `\` 续行，Tcl 不用——`if {..} {` 之后没闭合就自然跨行，根本不需要反斜杠。在
`set_property -dict [list ...]` 这种跨行块里，续行靠 **`{}` 内部自然跨行**（每行以 `\` 结尾、
中间不放 `#`，见 `build/tcl/build_system_axigpio.tcl:40`~`:63`）。`build/tcl/build_system_axigpio.tcl:38`~`:39`
专门记了这个坑：dict 里**不能夹注释行**——`{}` 里的裸文本会变成 list 的元素（作者"第一次就这么
把脚本写坏了"）。

### 7.4 把命令塞 -source / -tclargs 时的引号嵌套

命令行里给 Tcl 传参数：`vivado -mode batch -source x.tcl -tclargs <额外参数>`，脚本里用
`$argv` 取（`build/tcl/build_system_axigpio.tcl:222` `[lindex $argv 0]`）。坑在引号：外层
CMD/PowerShell、内层 Tcl、再内层字符串，三层各吃各的。稳妥两条：① 参数用不带空格的单词（如
`bd_only`、策略名）；② 在 Tcl 里跑带参数的外部命令别把整条拼成字符串再 `eval exec`（极易二次
解析），用 `exec cmd arg1 arg2` 分参数形式。`build/tcl/ps_jtag_boot.tcl:31`~`:40` 的做法很典型：
与其在一行里塞 PowerShell 的多层引号，它选择**把脚本写进临时 `.ps1` 文件**（`puts $fh` 逐行、
里面 `\$` 转义 PowerShell 变量），再 `exec powershell -File $ps1`，把引号嵌套彻底分开。

## 8. 给自己写脚本的模板

下面两份骨架可直接改名用。每条命令后面都注明了作用。

### 8.1 (a) 一次完整构建 + 出报告的 build.tcl

仿照 `build_system_axigpio.tcl` 的**工程流**骨架，剥掉 BD 细节，保留新人需要的主干：

```tcl
# build.tcl —— 工程流的最简完整构建骨架（剥掉 BD 细节，保留主干）
# 用法（仓库根下）：vivado -mode batch -nojournal -log build/build_console.log -source build/build.tcl
# 1) 定位仓库根并自证（抄 axigpio 的正确写法；缺这一行就会犯第 3.2 节的坑）
set root [file normalize [file join [file dirname [info script]] .. ..]]
if {![file exists [file join $root src rtl]]} { puts "ROOT WRONG: $root"; exit 1 }
set proj_dir [file join $root vivado_system]      ;# 工程放哪
set outdir   [file join $root build]              ;# 报告/bit 落哪
file mkdir $outdir                               ;# 确保输出目录存在
# 2) 建工程 + 加源文件与约束（-force：同名就重来）
create_project zynq_video_sys $proj_dir -part xc7z020clg484-2 -force
set_property target_language Verilog [current_project]          ;# 输出语言
set rtl {}
foreach d {util clocks video process axi hdmi eth} {            ;# 遍历各子目录收集 *.v
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl $f }
}
lappend rtl [file join $root src rtl top system_top.v]         ;# 顶层也进清单
add_files -norecurse $rtl                                     ;# 登记 RTL
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]  ;# 约束
set_property top system_top [current_fileset]                  ;# 指定顶层模块
update_compile_order -fileset sources_1                        ;# 让工具排编译顺序
# 3) 综合：后台跑 + 等待 + 判 PROGRESS（判进度而非 $?）
launch_runs synth_1 -jobs 4                                     ;# 起综合，4 作业
wait_on_run synth_1                                            ;# 阻塞等结束
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
  puts "SYNTH FAILED [get_property STATUS [get_runs synth_1]]"; exit 1 }
# 4) 选实现策略（可选，从环境变量来，并把名字打进日志——出身可见）
if {[info exists ::env(IMPL_STRATEGY)] && $::env(IMPL_STRATEGY) ne ""} {
  if {[catch {set_property strategy $::env(IMPL_STRATEGY) [get_runs impl_1]} e]} {
    puts "STRATEGY_REJECTED $e"; exit 1 }
}
puts "BUILD_STRATEGY [get_property STRATEGY [get_runs impl_1]]"
# 5) 实现到出 bit
launch_runs impl_1 -to_step write_bitstream -jobs 4            ;# 一路做到 bitstream
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
  puts "IMPL FAILED [get_property STATUS [get_runs impl_1]]"; exit 1 }
# 6) 收 bit 进 build/ 并出报告（open_run 后才能 report_*）
set bit [file join $proj_dir zynq_video_sys.runs impl_1 system_top.bit]
if {![file exists $bit]} { set bit [lindex [glob -nocomplain \
      [file join $proj_dir zynq_video_sys.runs impl_1 *.bit]] 0] } ;# 顶层名可能不同，兜底
file copy -force $bit [file join $outdir system.bit]             ;# 复制到 build/
open_run impl_1                                                 ;# 读进内存才能出报告
report_timing_summary -file [file join $outdir timing_summary.rpt] ;# 时序总览
report_utilization  -file [file join $outdir utilization.rpt]    ;# 资源占用
catch {report_methodology -file [file join $outdir methodology.rpt]}  ;# 方法学
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]  ;# 给 Vitis
close_project
puts "BUILD DONE bit=[file join $outdir system.bit]"
exit 0
```

### 8.2 (b) 一次上板回读若干寄存器的 peek.tcl

仿照 `set_src.tcl` / `ps_jtag_boot.tcl`，做成**只读**探针，用 xsdb 跑（不是 vivado）：

```tcl
# peek.tcl —— 连上板、halt A9、回读三路 AXI GPIO 与 DDR 自检值（只读探针，用 xsdb 跑）
# 用法（先确保 hw_server 在跑，见 6.1）：xsdb.bat peek.tcl
catch {connect -host localhost -port 3121} ce       ;# 连 hw_server；已在跑则直接复用
puts "CONNECT: [string trim $ce]"
targets -set 1                                       ;# 切到 PS 顶层，准备复位/取核
targets -set -filter {name =~ "*#0"}                ;# 选 A9 核 0（按名过滤，不写死编号）
catch {stop}                                         ;# halt 该核，安全读内存/外设
# 三路 GPIO 的数据寄存器（基址与 build_system_axigpio.tcl:187~:190 / xparameters.h 对齐）
foreach {name addr} {
  GPIO0_CTRL 0x41200000      ;# 输出：V7 32bit 控制字
  GPIO1_HEALTH 0x41210000    ;# 只读：链路健康快照
  GPIO2_CH1 0x41220000       ;# 双通道：通道 1
  GPIO2_CH2 0x41220008       ;# 通道 2 数据在 +0x8（XGPIO_DATA2_OFFSET）
} { puts "PEEK $name($addr) = [mrd -force $addr 1]" } ;# 逐个回读并打印
mwr -force 0x10000000 0x5A5AA5A5                     ;# DDR 通路自检：写魔数（对照 ps_jtag_boot.tcl:72）
puts "DDR_ECHO(0x10000000) = [mrd -force 0x10000000 1]"  ;# 读回比
puts "PC_BEFORE_RESUME = [dpc]"                      ;# 打印当前 PC，判断核停在哪
catch {con}                                          ;# 恢复运行，别把核留在 halt 态
exit 0
```

要点复述：`mrd`/`mwr` 用 `-force` 是因为外设/DDR 未映射时会拒绝访问，`-force` 强行读写；
读完一定 `con` 放开核，否则你下次连上来是个停住的处理器，容易误判成"固件卡死"。

# 01 · 构建链逐段拆解：工具是怎么一步步走到那颗 `.bit` 的

> 这一章不跑 Vivado：全套写作期间的硬约束是**只读**（任何构建命令都不许起，因为有实现可能在写同一棵树）。
> 它做的是同一件事的静态版本：**按工具的执行顺序**把构建脚本走一遍，
> 每一段回答三个问题——这段在工程对象上动了什么、失败了会留下什么话、产物落在哪。
>
> 全文的行号都来自本次实际打开过的文件。主脚本是
> `build/tcl/build_system_axigpio.tcl`：全文 **413 行**，下面简称**主脚本**；
> 它的行号如果不带文件名，一律指这一支文件。
> 交付口径的入口 `build/build.tcl` 正文只有一行 source（`build/build.tcl:9`），
> 所以"读 `build.tcl`"等于"读主脚本"，`build/README.md` 第 1.1 节的表也是这么标的
> （`build/README.md:22-23`）。

---

## 1. 全景：一张表看完 13 段

| # | 段 | 在干什么 | 关键行 | 动到的对象 | 产物 |
|---|---|---|---|---|---|
| 0 | 根目录解析 | 把 `info script` 折成仓库根 | `build/tcl/build_system_axigpio.tcl:11` | — | 两个变量 |
| 1 | 输出目录与工程名 | `VP_PROJ_SUBDIR`/`VP_OUTDIR` 覆盖默认 | `:12-19` | — | `file mkdir` |
| 2 | 建工程 | `create_project … -force` | `:21-22` | project 对象 | `vivado_system/zynq_video_sys.xpr` |
| 3 | 挂 RTL | 目录 foreach + glob | `:24-30` | `sources_1` | — |
| 4 | 挂约束 | 主 XDC + **只在实现生效**的 XDC | `:31-38` | `constrs_1` + `used_in_*` | — |
| 5 | env 门 | 两个候选 XDC 开关 | `:57-64`、`:75-82` | 同上（可选） | 日志里两行 `puts` |
| 6 | 建 BD | PS7 + 3×GPIO + 2×interconnect | `:84-210` | `design_1` | BD 文件 |
| 7 | 端口改名 | diff 法（不信返回值） | `:212-236` | BD 外部端口 | `PORT … -> …` |
| 8 | 地址钉死 | `assign_bd_address -offset` + 数值回读 | `:238-274` | 地址段 | `ADDR_LOG` 行 |
| 9 | 校验并保存 | `validate_bd_design` / `save_bd_design` | `:273-278` | BD | `BD_ONLY_DONE`（可选） |
| 10 | wrapper 与顶层 | `make_wrapper` + `set_property top` | `:279-289` | `sources_1` / fileset top | `WRAPPER:` 行 |
| 11 | 综合 → 实现 | 三个实现旋钮 + 两次 launch | `:301-354` | runs | `…runs/synth_1`、`…runs/impl_1` |
| 12 | 产物与报告 | bit 拷贝、7 份报告、xsa | `:356-374` | 归档 | `build/system.bit`、`build/system.xsa`、`build/*.rpt` |
| 13 | 两份凭据 | 扫 runme.log 数警告 | `:375-409` | 文本件 | `width_warnings.txt`、`multi_driven.txt` |

一句话概括这条链的形状：**前 10 段全是"往工程对象上写元数据"，一次综合都没跑；
真正烧时间的只有第 11 段；而最容易出错的是第 6-8 段（BD）**——
因为 BD 配错要等第 11 段跑到一半才炸，代价是 20 分钟。
主脚本正是为这件事留了一个只建 BD 就退出的口子（`:278`）。

---

## 2. 第 0 段：仓库根是怎么算出来的，以及它为什么是第一号陷阱

```
set root [file normalize [file join [file dirname [info script]] .. ..]]
```

`build/tcl/build_system_axigpio.tcl:11`。**两个 `..`**：`info script` 的目录是 `build/tcl`，
往上两层才是仓库根。

这不是风格问题，是本仓点名过的**一类 bug**：`build/tcl/build_pl_full.tcl:6` 写的是一个 `..`，
于是 `root` 落到 `build/`，后面 `add_files` 指向不存在的 `build/src/...`
（`build/README.md:31-33` 与 `build/tcl/README.md:19-23` 都在说这件事）。
更糟的是**它报错之后仍然 `exit 0`** ⇒ 判构建成败不能看退出码。

本仓给出的操作口径就写在同一处：
**判成败只看 `build/` 里产物的修改时间**（`build/README.md:33`）。
这条不是洁癖——脚本里到处是 `catch`（`:365-370` 那五份报告全都包在 `catch` 里），
`catch` 吞掉的错误不会体现在退出码上。

**把这一条读成一条通用规矩**：凡是用 `info script` 反推根目录的脚本，
第一眼看 `..` 的个数与脚本所在层数是否匹配。这一族 bug 的静默性来自
"`add_files` 找不到文件"在批处理模式下不是 fatal。

## 3. 第 1 段：默认值全部可以被环境变量改写

```
set proj_subdir vivado_system
if {[info exists ::env(VP_PROJ_SUBDIR)] && $::env(VP_PROJ_SUBDIR) ne ""} { … }   :12-13
set outdir [file join $root build]
if {[info exists ::env(VP_OUTDIR)] …} { set outdir [file normalize [file join $root $::env(VP_OUTDIR)]] }  :17-18
file mkdir $outdir                                                                                    :19
```

**"不设就是不切，默认行为必须与历史一致"**——这句是整套 `VP_*` 门的统一设计语言，
在 `:6`（文件头参数说明）、`:300`、`:312-316`、`:324-327`、`:337-340` 各写了一次。
它服务的判据是**单变量对照**：分步验证时把工程指到别处（例如 `build/isolated_1006_d_tmdswindow/`
这种目录，盘上确实有），**不碰正式工程**，也就不污染"板上那一颗"的身份。

`VP_OUTDIR` 的另一个作用是让同一支脚本能往归档目录重出报告，
`build/report.tcl:13-14` 用的是同一套覆盖逻辑，只是默认目录不同
（主脚本默认 `build/`，`report.tcl` 默认 `build/report/`）。**同一个 `VP_OUTDIR` 名字、两支脚本、两个默认值**——
这一条很容易踩，所以第 11 节会再点一次。

---

## 4. 第 2 段：建工程

```
create_project $proj_name $proj_dir -part $part -force      :21
set_property target_language Verilog [current_project]      :22
```

三个数在这里被定死，且**都是后续判据的口径来源**：
`$part = xc7z020clg484-2`（`:16`）、`$proj_name = zynq_video_sys`（`:15`）、
`$proj_subdir = vivado_system`（`:12`）。
`时序专章` 的 §0 身份表逐项核对的就是这三个值，
并且特意用 `build/timing_summary.rpt` 头部的 `Speed File : -2 PRODUCTION` 做**交叉核对**，
"不是照抄别处"。

`-force` 的含义要认清：**它会重建这个工程目录里的工程对象**。
这正是 `VP_PROJ_SUBDIR` 存在的理由——想在别的目录试一刀又不动正式工程，
就不能让两支构建指同一个 `$proj_dir`。

## 5. 第 3 段：RTL 是怎么进 `sources_1` 的

任务点名的那一段就是这里：

```
24  set rtl_files {}
25  foreach d {util clocks video process process/rotate process/zoom process/bilin axi hdmi eth} {
26    foreach f [glob -nocomplain [file join $root src rtl $d *.v]] { lappend rtl_files $f }
27  }
28  lappend rtl_files [file join $root src rtl top pl_video_top.v]
29  lappend rtl_files [file join $root src rtl top system_top.v]
30  add_files -norecurse $rtl_files
```

`:25` 是**目录列表那一行**，`:26` 是每个目录里的 glob，`:30` 才真正入集。
读这四行要读出五个隐含事实：

1. **列表是 10 个目录，不含 `top`。** `top/` 里三个文件，本构建只要两个
   （`:28-29` 逐条点名），第三个 `pl_demo_top.v` **不进工程**。
   它活在另一条链上（`build/tcl/build_pl_full.tcl:22` 把 top 设成 `pl_demo_top`），
   而那条链因为有第 2 段那个 `..` bug 不能当入口用。
   所以：**在 `src/rtl/top/` 里放一个文件，不等于它被综合了。**
2. **`glob` 是单层匹配、不递归。** 所以 `process`、`process/rotate`、`process/zoom`、
   `process/bilin` 四个条目必须并列写全（`:25`）。少写一个子目录 = 那个子目录整个不进工程。
3. **`-nocomplain` 让"目录不存在/一个文件都没匹配上"变成静默。**
   这一族失败不报错、不警告、`rtl_files` 只是短了几条。
   ⇒ 改目录名或挪文件之后，**必须自己核对文件数**，别信构建成功。
   本次实测各目录 `.v` 件数（`ls src/rtl/<dir>/*.v | wc -l`）：
   util 7、clocks 1、video 17、process 10、rotate 4、zoom 4、bilin 3、axi 3、hdmi 3、eth 25
   ⇒ foreach 收 77 只，加 `:28-29` 两只 = **79 只进 `sources_1`**（不含 BD wrapper）。
4. **`-norecurse` 是"引用不搬文件"。** 不加它 Vivado 会把源文件复制进工程目录，
   于是仓库里那份和工程里那份从此各活各的。
5. **文件集成员顺序不等于编译顺序。** 真正理顺序的是 `:289` 的
   `update_compile_order -fileset sources_1`；顶层由 `:288` 的
   `set_property top system_top [current_fileset]` **点名**决定。
   ⇒ "哪个模块是顶层"这件事与 `:25` 那个列表的顺序无关，这是好事，
   但也意味着**改列表顺序不会影响产物**，别把它当可调项。

`src/rtl/video/` 里 17 只文件全被 glob 收进来，其中有几只是**没人例化的遗留件**
（`src/rtl/video/frame_buffer.v:2-3` 与 `src/rtl/video/line_cache.v:2-3` 自己就在文件头写着
"本树无人例化"）。它们进工程 → 进综合 → 因为没人引用而被优化掉。
本仓专门有一支找这类件的工具：`build/orphan_rtl.sh`（`build/README.md` 第 1.4 节的表里点名）。
⇒ 读构建链要分清**"在文件集里"、"被例化"、"在位流里"是三件事**。

## 6. 第 4 段：约束加载，以及"为什么这条要拆成只在实现阶段生效"

```
31  add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]
36  set cgxdc [add_files -fileset constrs_1 -norecurse [file join $root src constraints clock_groups_impl.xdc]]
37  set_property used_in_synthesis false $cgxdc
38  set_property used_in_implementation true $cgxdc
```

`:32-35` 那四行注释就是这件事的完整因果，这里把它摊开成一条推理链：

1. `src/constraints/clock_groups_impl.xdc:28-31` 是一条 `set_clock_groups -asynchronous`，
   三个 group 里有一个是 `-group [get_clocks -quiet clk_fpga_0]`。
2. **`clk_fpga_0` 不是本仓写的约束造出来的**，它是 PS7 IP 自己的 XDC 从 BD 配置推的
   （`src/constraints/clock_groups_impl.xdc:3`；`build/tcl/build_system_axigpio.tcl:97` 的
   `PCW_FPGA0_PERIPHERAL_FREQMHZ {100}` 才是它的源头）。
   ⇒ 综合阶段还没有 IP 实例化 ⇒ 这个钟对象**不存在**。
3. `-quiet` 只能压住 `get_clocks` 的报错，**压不住命令本身失效**
   （`src/constraints/rk_zynq7020.xdc:66-70` 原话）。后果是两层：
   每个 run 吃一条 `CRITICAL WARNING [Vivado 12-4739] set_clock_groups:
   No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'`，
   而且**整条命令不生效**——`eth_rxc`/`sys_clk` 那两组一起废掉。
4. **为什么不用 `if` 守卫？** 因为 XDC 文件里不许写 Tcl 控制流。
   解析器逐行报 `[Designutils 20-1307] Command 'if' is not supported in the xdc constraint file`
   然后**把整块跳过，而 `read_xdc` 仍然 rc=0**（`build/tcl/build_system_axigpio.tcl:72-74`，
   实测凭据 `build/evidence/r119_xdc_loads_probe2.txt`）。
   ⇒ 这一条比 `12-4739` 更阴险：**"防呆"失效而且不报错。**
5. 于是唯一解法是**按时机分文件**：`add_files` + `used_in_synthesis false`
   （`src/constraints/clock_groups_impl.xdc:5` 就是这句的复述）。

**这条拆分不改任何时序数字**，理由写在 `build/tcl/build_system_axigpio.tcl:35`
与 `src/constraints/clock_groups_impl.xdc:8`：综合阶段这条约束在拆分前**也是失败的**
（等于不存在），拆出去只是把噪声去掉。
这是一个很好的思维模型：**"约束按生效阶段分文件"是纯净收益的整理，
因为它把"本来就在发生的事"变成"写在工程属性里的事"。**

顺带记住 `used_in_synthesis false` 的第二种用法（下一段），它比时钟组那次更有意思。

---

## 7. 第 5 段：六个环境变量门，各自开什么

先把开关表列全（默认列 = 一个变量都不设 = 出货档，口径与 `build/README.md:103-113` 一致）：

| 变量 | 开什么 | 判断行 | 不设时日志念什么 |
|---|---|---|---|
| `VP_R116_IO_WINDOW=1` | RGMII 收口 5 个输入的候选输入窗进实现 | `:57-64` | `VP_R116_IO_WINDOW off（…留在候选件…）` |
| `VP_R119_TMDS_WINDOW=1` | HDMI 源端 TP1 窗进实现 | `:75-82` | `VP_R119_TMDS_WINDOW off（…缺的是一次量名册的构建）` |
| `VP_STOP_AT=project` | 建完工程/源/约束就退，综合留给 `build/synth.tcl` | `:301-305` | 一路跑到 bit |
| `IMPL_STRATEGY` | 换 `impl_1` 的策略；非法名先 `BUILD_STRATEGY_REJECTED` 再 `exit 1` | `:317-323` | `BUILD_STRATEGY Vivado Implementation Defaults` |
| `IMPL_POST_PLACE_HOOK` | 给 `STEPS.PLACE_DESIGN.TCL.POST` 挂一支外部 tcl | `:328-336` | `BUILD_POST_PLACE_HOOK none` |
| `IMPL_PRPO=1` | 打开 post-route phys_opt 并设 `AggressiveExplore` | `:341-352` | `BUILD_PRPO off` |
| `VP_OUTDIR` / `VP_PROJ_SUBDIR` | 归档目录 / 工程子目录 | `:18` / `:13` | `build/` / `vivado_system` |

### 7.1 两个候选约束共同的结构

四行是一样的：`if {env==1}` → `add_files -fileset constrs_1` →
`used_in_synthesis false` → `used_in_implementation true`（`:58-60`、`:77-78`）。

**这里要理解的是"为什么默认关"，三个理由强度不同，别混着念：**

### 7.2 `VP_R116_IO_WINDOW`：约束是对的，但不能带进发布物

`:40-56` 那一整块注释是一次完整的论证，压缩成三步：

1. **约束本身是对的**：数来自 RTL8211F-CG Table 60 的**发射端**两行 + 原理图 strap
   （`src/constraints/r116_rgmii_input_window.xdc:8-17`；min 1.200 / max 2.800）。
   这一族端口在此之前**从来没被检查过**（`build/tcl/build_system_axigpio.tcl:40`、
   xdc `:5`），所以绑窗是**只加严不放宽**。
2. **加严之后本仓自己的发布门禁有 4 项机械判红**：WNS ≥ 0、失败 setup 端点 == 0、
   WHS ≥ 0、失败 hold 端点 == 0（判据本体在 `build/gates.sh:197-200`），
   而 `gates.sh` 末尾的规矩是"有红项 ⇒ 不采纳，保留上一版"。
   ⇒ **这个设计只有在"RGMII 输入不被检查"的前提下才过发布门禁**（`:47-48`）。
3. **而且这一族在合法 0…31 全档内关不掉**：hold 要 τ ≥ 44.8、setup 要 τ ≤ 21.8，
   根因是两只钟的角间差 3.411 ns vs 数据 0.467 ns（`:50-52`，
   推导在 `收口输入窗模型` §7.5）。

于是结论的形状很特别（`:53-56`）：**撤销的不是"约束的正确性"，是"把它带进发布物"这个动作**；
件留在仓里当**候选件 + 全份证明**，复现只要一个环境变量。
`:55-56` 还写了重新加载的前置条件（换成短钟那一刀落地之后）。

**这一刀的方法论值得单独抄走**：`:44` 明说这是"门禁读数逼出来的决定，
**不是把约束改掉换绿灯**"。同一页上"只加严不放宽"与"默认不加载"并存，
靠的是把这两件事分成"约束对不对"和"进不进发布物"两个独立判断。

### 7.3 `VP_R119_TMDS_WINDOW`：默认关的理由是"还没量"，不是"会红"

`:66-74`。这一件的关的理由与 r116 **完全不同**，别串了：

- r116 是**量过了、且量出来会红**，所以不进发布物；
- r119 是**一次都还没量**：`:70` 写"新增约束必须先用一轮构建量名册（别域不许变差），
  量过之前带进发布物就是用声明代替测量"。
- 而且 `:79` 的 `puts` 直接写成"这一轮的量还没做，**别念成已采纳**"——
  日志文本本身承担了一部分防误读的职责。

`:72-74` 还留了一条工具口径：这一版**不在 `.xdc` 里放 Tcl 守卫**，
因为 2026-10-04 实测解析器会报 `Designutils 20-1307` 并整块跳过（rc=0）；
守卫改成 Tcl 侧 + 一把只读尺子 `build/r119_window_check.mjs`（`--self` 有 6 条能红的对照）。

两件合起来给出一条通则：**候选件不是"未完成的代码"，是"已写好但缺一次测量的凭据"。
它的状态必须由日志和文档写清，不能靠"看起来在仓里=已生效"来推断。**
判"某个约束到底进没进这一版位流"的唯一硬办法，是看那一次构建日志里念的是
`loaded` 还是 `off`（`:61-63`、`:79-81`），或看盘上 XDC 的 `used_in_*` 属性。

### 7.4 `VP_STOP_AT=project`：把最贵的一段切开

```
if {[info exists ::env(VP_STOP_AT)] && $::env(VP_STOP_AT) eq "project"} {
  puts "VP_STOP_AT_PROJECT_DONE proj=$proj_dir"; close_project; exit 0 }      :301-305
```

这个门**放在 BD、地址、wrapper 全做完之后、`launch_runs synth_1` 之前**——
位置本身就是设计：工程文件、IP、源、约束都进文件集了，综合还没开始。
两支分步入口就是靠它实现的：`build/create_project.tcl:8` 与
`build/add_sources.tcl:9` 都只做一件事——`set ::env(VP_STOP_AT) project` 然后 source 主脚本。

`build/add_sources.tcl:2-3` 说明了为什么这两个入口**共用第一段**：
"建工程与导源在主脚本里是同一个阶段（BD 不存在时源文件无处可挂），
因此本入口与 `create_project.tcl` 共用第一段，**源清单只有一份**"。
⇒ 这是防"两份清单漂开"的结构做法：不是复制一份再同步，是根本不复制。
`build/README.md:24-25` 把两者的产出分别写成"xpr 与 sources_1、constrs_1、run 列表"
和"工程内 sources_1、constrs_1 与各约束的 `used_in_*` 属性"。

### 7.5 `IMPL_STRATEGY` / `IMPL_POST_PLACE_HOOK` / `IMPL_PRPO`：产物自己带出身

三个旋钮共用一条规矩，`:313-316` 写得很直白：
**"为什么做成外部传 + 一定把名字打进日志，而不是直接改这一行"**——
采纳判据要"同一份 RTL + 某个策略"**两次独立构建同方向**，
而策略一旦写死进脚本，过几个月没人知道眼前这颗 bit 是哪一档出来的。
`:324-325` 补了同一逻辑的另一半：**r116 那一版位流的复现路径不能被事后改写。**

三处 `puts` 因此不是装饰，是判据：

| 旋钮 | 打进日志的那行 | 位置 |
|---|---|---|
| 策略 | `BUILD_STRATEGY <名字>` | `:323` |
| 钩子 | `BUILD_POST_PLACE_HOOK <路径>` 或 `none` | `:333`、`:335` |
| PRPO | `BUILD_PRPO on AggressiveExplore` 或 `off` | `:349`、`:351` |

三个都带**拒绝出口**：`BUILD_STRATEGY_REJECTED`（`:319`）、`BUILD_HOOK_REJECTED`（`:330`）、
`BUILD_PRPO_REJECTED`（`:346`），三处都在 `catch` 里判、判不过 `exit 1`。
⇒ 非法值不会"退回默认继续跑"，会**停**。（对比：`r119` 的守卫是"静默跳过"，
两者的差别正是"错的时候你希望它停还是继续"。）

**钩子为什么挂在 `PLACE_DESIGN.TCL.POST`**，`:326-327` 给了唯一理由：
快车道滚（`build/evidence/r117_repl3/b_console.txt`）就是在 place 之后、route 之前
做的这一次强制复制，**把同一个动作放在官方 run 的同一个位置才是单变量**。
被挂的那支件做的事也写在它自己头上：
`build/tcl/r117_post_place_hook.tcl:7-9`（"Wired in by … as
`set_property STEPS.PLACE_DESIGN.TCL.POST`"）、`:11`（force-replicate **ONE** broadcast net
`u_pl/u_row/hi_reg_0[0]`）。它的裁决结果在 `那一轮的逐轮页` 第三节：**否决**
（目标域赢 +0.254 ns，但 `clkout0_1`/`eth_rxc` 三格跌）。

**PRPO 单独开一档的理由是它不动网表**（`:337-340`）：
`优化流水账` §4 量到全设计 WNS 由两条**布线主导**（route 占 60~67 %）的路径轮流决定，
而 post-route phys_opt **只动物理结果** ⇒ 这一档不需要重跑 RTL 台架。
"哪些改动需要重跑哪些台架"这件事，在这里是靠**改动作用的层次**来判的，不是靠"小心为上"。

`:291-297` 那一段是同一个旋钮的**退役记录**：`Performance_ExtraTimingOpt`
曾把 `clk_pix→clk_pix5x` 从 −0.485 抬到 +0.788 但仍红，
于是旋钮被撤、注释留档，还补了一条历史结论
（"`Performance_Explore` 与默认策略产出逐位相同的 bit ⇒ 那不是个可选项"）。
**旋钮留在文件里当注释，不留在工程里当默认。**

---

## 8. 第 6 段：BD 是整条链上最脆弱的一段

### 8.1 PS7 三步

```
create_bd_design design_1                                                     :84
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 …          :85
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" … apply_board_preset "0"} $ps         :87-88
```

注意 `apply_board_preset "0"`——**不套板级预设**，全部配置项靠 `:96-119` 那张手写字典。
这是这套构建里最"手写"的一块，也是最容易写坏的一块。

### 8.2 那张 `-dict` 为什么不能夹注释

`:94-95` 是血的教训的原文：
"这个 dict 里**不能夹注释行**：整块是一个 `set_property -dict [list …]`，
行续 `\` 之间出现的裸文本会变成 list 的元素（我第一次就这么把脚本写坏了）"。
⇒ 所有解释性文字只能放在块**外面**（`:90-93`、`:128-146` 就是这么放的）。
`Tcl` 的 `[list]` 没有"注释"这个语法类别，这是纯语法事实，但只有踩过才知道。

字典里值得读的不是每一行，而是**三段推理**：

- **`:90-93` MIO 认领的冲突账**：开 `PCW_GPIO_MIO_GPIO_ENABLE` 是为了读板上两个 PS 按键
  （原理图网络名 `PS_MIO0_KEY1`/`PS_MIO12_KEY2`），
  而"老配置只有 EMIO GPIO=0、MIO GPIO 根本没开 ⇒ 那两个脚电气上存在但固件读不到"。
  随后逐条列出 MIO 0/12 没被占用的依据（QSPI=1..6、UART0=10..11、ENET0=16..27(+MDIO 52..53)、
  SD0=40..45(+CD 9)）。**"这个脚能不能用"要拿别的iperipheral的占用范围来回答，不是拿感觉。**
- **每脚四行的必要性**（`:93`）：`PULLUP/IOTYPE/DIRECTION/SLEW` 缺了
  `validate_bd_design` 会报 IOTYPE 未设 ⇒ 报错点离写作点很远，只能靠"少写一行试一次"发现。
- **`:100` 一行的分量**：`PCW_USE_S_AXI_HP0 {1}` + `PCW_S_AXI_HP0_DATA_WIDTH {64}`
  决定了第 00 章 §4 整条数据面存在。**一个 BD 参数就是一条通路的全部使能。**

### 8.3 三条 GPIO：为什么不"用到再加"

`:121-155` 建 `axi_gpio_0`（32 输出）、`axi_gpio_1`（32 输入）、`axi_gpio_2`（**双通道 ×32 输出**）。
理由全在 `:138-146`：`gpio_0` 的位已经用到只剩 9 位空，而 V8 的算法选择字就要 9 位、
后面 Gamma 与分割线还要 30 多位 ⇒ **把 64 位一次开出来（通道 2 现在故意不接）**，
因为"**动一次 BD = 地址、约束、全套门禁重来**"。
同一处还承诺"老工具（`build/tcl/set_src.tcl` / `src/host/health_read.mjs` / …）读写的
`gpio_0` 位序一个都没动"。

⇒ 这一段教的是**BD 的成本模型**：BD 改动不是"加两个 ip"，
是**地址图 + 约束 + 门禁三件事同时重来**。所以容量要一次预留、位序一旦发布就不许动。

`axi_gpio_1` 的注释（`:128-130`）是同一模型的另一个方向：
"不新增 AXI 从地址之外的任何东西：lane 号走已有的 `GPIO_0`（`gpio_o[31:27]`），
数据走这条 ⇒ BD 里只多一个 ip、多一条 `M01_AXI`"。**能复用总线就不新开地址。**

### 8.4 时钟/复位网络与接口连接

`:162-175` 一条 `connect_bd_net` 把 `FCLK_CLK0` 扇到 14 个引脚（含
`processing_system7_0/S_AXI_HP0_ACLK`、`M_AXI_GP0_ACLK`），`:177-188` 是 reset 的同一套。
`connect_bd_net` 一次列 14 个对象 ⇒ 少列一个不会报错，会在 `validate_bd_design`
或更晚的综合阶段以别的形态出现。**"整条链共用一只钟"这件事在这套设计里是显式声明的，
不是推断的**——这也是第 00 章 §4 里 PL/AXI 全在 `clk_fpga_0` 上、
只有收口在 `eth_rxc`、显示在 `clk_pix` 的结构成因。

`:198-199` 把 `axi_mem_intercon/M00_AXI` 接到 `S_AXI_HP0`；
`:201` `make_bd_intf_pins_external` 把 interconnect 的 S00 引出成 PL 侧主口，
`:202-204` 再用 `foreach`+`string match *S00*` 把它改名成 `M_AXI_HP0`
（这里用了 `catch`，允许某个端口改名失败——与下面 §8.5 那次教训的处理方式不同，值得对比）。

`:206-210` 建 BD 外部时钟端口，**注意 `-freq_hz 100000000`**：
这是"100 MHz"在这套代码里出现的第二处（第一处是 `:97` 的 `PCW_FPGA0_PERIPHERAL_FREQMHZ`）。
两处一个是 IP 配置、一个是 BD 端口的元数据，**用途不同但值必须一致**，
这类"同一物理量写在两处"正是漂移的来源，读的时候要有意识。

`:238` 是另一处常被忽略的：**`catch {set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_HP0}
[get_bd_ports FCLK_CLK0]}`**——它把 AXI 接口挂到那只钟上，
影响的是**接口相关路径的时序分析归属**。它被包在 `catch` 里，
意思是"这一条设不上也不要停"。⇒ 属于"知道它存在比知道它写什么更重要"的一类。

### 8.5 端口改名：不能信返回值、不能按子串匹配

`:212-235`。注释把两条踩过的路都写了：

- `make_bd_pins_external` 的**返回值在这里实测为空**（r45 第二次试跑），
  于是 `get_bd_ports {}` 报 "No ports matched"，脚本按判据自己停了；
- **不能按子串匹配**：双通道 GPIO 的两个端口都叫 `gpio_io_o*`，
  子串循环会把第二个也命名成 `GPIO_0_tri_o`，冲突被 `catch` 吞掉之后
  端口留着自动名 ⇒ 顶层例化时报的错看起来像"凭空少一个端口"。

解法是**集合 diff**：`:217-221` 定义 `proc bd_port_names {}` 取当前端口名集合，
`:228-233` 每次调用前后各取一次、diff 出唯一新增者、数量不等于 1 就打
`PORT_LOOKUP_FAILED` 并 `exit 1`（`:232`）。

这段是整条链里我最想让下一位读者抄走的写法：
**当一个工具的返回值不可信时，不要"包一层 catch 继续"，
而要换一个自己可验证的判据，并且让"验不出来"成为硬失败。**

四行映射也值得一读，因为它暴露了同一族冲突的另一半：
`:222-227` 把 `axi_gpio_2/gpio_io_o` 叫成 `GPIO_2_tri_o`、把 `axi_gpio_2/gpio2_io_o`
叫成 `GPIO_3_tri_o`——**一个 GPIO IP 的两个通道对外是四个端口名**，
而 RTL 侧的接线在 `src/rtl/top/system_top.v:84-87`
（`GPIO_0_tri_o`/`GPIO_1_tri_i`/`GPIO_2_tri_o`/`GPIO_3_tri_o`）。
**改名表与 RTL 端口表是两处独立声明，一致靠人保证**——这正是
`build/gates.sh` 第 14 项"顶层接线（端口名对得上、输入都没悬空）"存在的理由
（`build/gates.sh:253` 的注释，"V8-5 的教训"）。

### 8.6 地址：钉死 + 回读 + **数值**比较

```
assign_bd_address                                                             :239
foreach {seg want} { axi_gpio_0/S_AXI/Reg 0x41200000 … } {
  assign_bd_address -offset $want -range 64K \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs $seg] -force }   :243-251
```

然后是一整段**回读校验**（`:252-274`），里面埋着两个自己踩过的坑：

1. **段对象要从地址空间里取**（`:259-260`）：
   `get_bd_addr_segs axi_gpio_0/S_AXI/Reg` 取到的是**接口定义**，它的 `OFFSET` 是空的
   ⇒ 上一次这里判红是查询写错了，不是地址没钉上。
   现写法：`:261` 的 `get_bd_addr_segs -quiet -of_objects $aspace -filter "NAME =~ *SEG_${cell}_Reg*"`。
2. **比较必须在数值上做**（`:264-265`）：`OFFSET` 属性经数字一走就显示成十进制
   （`0x41200000` → `1092616192`），字符串比对必然红。
   现写法是 `scan [string tolower $got] "%x" gv` 两边各自转数值再比（`:266-271`）。
3. 还有一条诊断改进（`:253-256`）：**先把整张地址图打出来**（`ADDRMAP … = …`），
   因为上次查不到偏移时只能看到 `got=`（空串），
   看不出"是查询写错了还是地址真没钉上"。

失败出口是 `:274`：`if {$bad_addr} { puts "ADDRESS PINNING FAILED"; exit 1 }`。
`:257-258` 那句"为什么不能让它自动排"是这一段的落点：
**BSP 不会重新生成 `xparameters.h`，固件里基址是硬编码的；
地址一挪，现象不是编译失败而是"写了没反应"——最难查的那一类。**
对端在固件里：`src/ps/main.c:48`（`AXI_GPIO_BASE 0x41200000u`）、
`:77`（`AXI_GPIO_CFG_BASE 0x41220000u`）。
⇒ 这两处一致性**没有任何工具在管**，只有这支脚本的回读在管。

### 8.7 校验、保存，以及那个"bd_only 快检"

```
validate_bd_design                                              :273
if {$bad_addr} { puts "ADDRESS PINNING FAILED"; exit 1 }        :274
save_bd_design                                                  :275
if {[lindex $argv 0] eq "bd_only"} { puts "BD_ONLY_DONE"; exit 0 }   :278
```

`:276-277` 说清了为什么留这个口子：
"BD 配置写错（IP 的参数名、引脚名、MIO 认领）本来 3 分钟就能验出来，
不必等 20 分钟的综合+实现。" 跑法写在 `build/README.md:88`（第 1 步"BD-only 快检"）。
⇒ **这是整条链上性价比最高的一刀**：把最贵的失败挪到最便宜的时刻。

注意 `:278` 用的是 `$argv` ⇒ 它靠命令行参数（`-tclargs bd_only`），
与前面所有 `VP_*`（靠环境变量）是两套传参通道。这个区别在实际操作里会咬人：
`build/create_project.tcl:8` 那种"入口脚本设 env"的方式**设不出 `bd_only`**。

## 9. 第 7-10 段：wrapper、顶层、综合

```
make_wrapper -files [get_files design_1.bd] -top                              :279
set wrap [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]  :280
if {![file exists $wrap]} { set wrap [lindex [glob -nocomplain … .srcs …] 0] } :281-283
add_files -norecurse $wrap                                                    :284
set_property top system_top [current_fileset]                                 :288
update_compile_order -fileset sources_1                                       :289
```

`:280-283` 是一个**路径猜测 + 回退**：Vivado 在不同版本/设置下把生成的 wrapper
放在 `.gen` 或 `.srcs` 下，脚本先赌 `.gen`、赌不中就 glob `.srcs`。
`:285` 把最终选中的路径打成 `WRAPPER: …` 行——**又一条"产物带出身"的日志**。
`:286` 顺手念一句 `TOP: system_top.v (maintained, includes PL ETH)`。

`:288` 是全链**最关键的一行命名**：顶层是 `system_top`，不是 `pl_video_top`、
不是 `pl_demo_top`。`build/README.md:22` 的对照表也这么写（`set_property top system_top`）。
`pl_video_top` 是 `system_top` 里的一个例化（`src/rtl/top/system_top.v:2-3` 的文件头
把这一层的组成说全了：`design_1_wrapper` + `clk_gen` + `eth_udp_video_top` + `pl_video_top` + `snap_cross`）。

综合入口只三行：

```
launch_runs synth_1 -jobs 4            :306
wait_on_run synth_1                    :307
if {[get_property PROGRESS …] ne "100%"} { puts "SYNTH FAILED …"; exit 1 }   :308-311
```

**判成败看的是 `PROGRESS` 属性而不是退出码**——与第 0 段那条规矩一脉相承。
分步版本在 `build/synth.tcl`：先验 `xpr` 存在（`build/synth.tcl:11` 缺则
`NO_PROJECT` + `exit 1`）、`open_project`、**`reset_run synth_1`**（`:13`）、
launch/wait、同样按 `PROGRESS` 判（`:16-18`）。

## 10. 第 11 段：实现

```
launch_runs impl_1 -to_step write_bitstream -jobs 4       :353
wait_on_run impl_1                                        :354
```

`-to_step write_bitstream` 意味着**一次 launch 跑到 bit**，
而 `build/impl.tcl:21` 的分步版本只到 `route_design`（位流交给 `build/gen_bit.tcl`）。
两条路的差别不只是"少一步"，还有**报告口径**：`build/impl.tcl` 跑完时
`:361` 的 `open_run impl_1` 那一类读报告动作并没有发生，
所以分步链必须再走 `build/report.tcl` 或 `gen_bit.tcl` 才谈得上产物齐。

三个旋钮（策略/钩子/PRPO）都插在这一段之前，理由见 §7.5。
另外值得记的一条：`build/tcl/sweep_impl_strategy.tcl` 是"同一份网表逐个策略重跑 `impl_1`"
的工具，它**复用现有 `.xpr`、不重建 BD、不重跑综合**（`build/tcl/sweep_impl_strategy.tcl:3`），
档位由 `SWEEP_STRATS` 覆盖，**收尾把 `impl_1` 的 strategy 恢复成扫描前的值**（`:5`），
汇总落 `build/sweep_summary_<时间戳>.txt`（`:4`）。
⇒ "扫完之后工程属性被改过"是一个真实风险，这一族脚本把恢复写进了自己的收尾。

## 11. 第 12 段：产物去向

```
set bit [file join $proj_dir ${proj_name}.runs impl_1 system_top.bit]         :356
if {![file exists $bit]} { set bit [lindex [glob -nocomplain …impl_1 *.bit] 0] }  :357-359
file copy -force $bit [file join $outdir system.bit]                          :360
open_run impl_1                                                               :361
… 7 份 report …                                                               :362-370
write_hw_platform -fixed -include_bit -force -file [file join $outdir system.xsa]  :371
catch {close_project}                                                         :372
puts "BIT: …" / "XSA: …"                                                      :373-374
```

要点四条：

1. **`.bit` 在工程目录里的名字是 `system_top.bit`（顶层名），拷出来才叫 `system.bit`。**
   `:357-359` 那个 glob 回退承认了一件事：这个文件名不是稳定的（不同版本会带后缀/换名）。
2. **`-include_bit`**（`:371`）让 `.xsa` 里带位流。
   这不是可有可无：板侧三步链要用同一个 `.xsa` 起 PS + 编 PL（`build/tcl/ps_jtag_boot.tcl`，
   用途见 `build/README.md` 第 1.3 节），少了 `-include_bit` 就要多烧一次。
3. **`open_run impl_1` 是读报告的前提**（`:361`）：
   报告要的是**已实现设计**，不是工程；少了这一行后面 7 条 `report_*` 全部失效。
4. **`write_hw_platform` 写在报告之后**——所以一次构建里
   `.xsa` 的时间戳晚于 `timing_summary.rpt` 是正常顺序。
   反过来，`build/gates.sh:51-53` 那个"bit 与报告相差超过 10 分钟就当它不是一套"的新鲜度检查
   （判据本体 `build/gates.sh:47-49`）依赖的正是"一次构建里 bit 先写、报告只差几十秒"这个事实。
   ⇒ 这段顺序是**被门禁依赖的**，改脚本时挪顺序会让新鲜度判据变成噪声源。

另一条落盘路径：`build/gen_bit.tcl` 把 bit 与 xsa 拷到 **`board/`**
（`build/gen_bit.tcl:12`，可用 `VP_BIT_DIR` 改写目标：`:13`），
并且它会**自己补跑**缺的那一步：`impl_1` 里没 bit 就 `launch_runs … -to_step write_bitstream`
（`:17-20`），还没有就 `write_bitstream -force`（`:22-24`），
最后 `ARTIFACT_MISSING` 判据保证两份产物都在（`:29-31`）。
⇒ **出货档默认 `build/system.bit` + `build/system.xsa`**（这两个是被 git 跟踪的，
本次 `git ls-files` 实测只有这两件在库，`board/` 下那两份不在），
`board/` 那一份是"给板侧脚本用的拷贝"。

冻结那一层的清单在 `build/freeze_evidence.sh:62-66`：
`system.bit / system.xsa / ps_app.elf` + 7 份 `.rpt` + `multi_driven.txt` /
`width_warnings.txt` / `ports_check.txt` + 台架与门禁件。
同文件 `:60-61` 写了一条好原则：
**"盖章对象 = 目录里实际存在的文件"**，不是维护第二份名单
（"补这一次，下一次加件照样漏"）。

## 12. 第 12.5 段：7 份报告，以及"谁是文档数字的唯一出处"

主脚本一次落 7 份（`:362-370`）：

| 报告 | 生成行 | 谁读它 |
|---|---|---|
| `timing_summary.rpt` | `:362`（**无 catch**） | `gates.sh` 的第 1 项、逐时钟名册、`metric_recheck` |
| `utilization.rpt` | `:363`（**无 catch**） | `gates.sh` 第 2 项（BRAM/LUT/寄存器）、`metric_recheck` |
| `cdc.rpt` | `:365` catch | `gates.sh` 第 6 项（与基线**行集合**比） |
| `methodology.rpt` | `:366` catch | `gates.sh` 第 4 项（CRITICAL WARNING 计数） |
| `power.rpt` | `:368` catch | `gates.sh` 第 3 项 + `metric_recheck` |
| `route_status.rpt` | `:369` catch | `gates.sh` 第 5 项（routing errors == 0） |
| `clock_util.rpt` | `:370` catch | 时钟树/区域读数（第 00 章 §1.1 用的那张 BUFG 表） |

**三件事必须分清：**

1. **必备 vs 可选，门禁与脚本的口径不一样。**
   主脚本只对前两份不包 `catch`（`:362-363`），后五份失败会被 `catch` 吞掉；
   `build/report.tcl:20-24` 是同一形状，而它的**验收只查两份**
   （`build/report.tcl:27-29`：`timing_summary.rpt`、`utilization.rpt` 缺才 `REPORT_MISSING` + `exit 1`）。
   但 `build/gates.sh:43-45` 要求的是 **四份**：
   `timing_summary / utilization / power / route_status`，缺任何一份 `FATAL 缺报告` + `exit 2`；
   `methodology.rpt` 与 `cdc.rpt` 则走 `naa` 分支（`build/gates.sh:206`、`:209`）——
   **文件不在 ⇒ 那一项"没门禁"，不是红也不是绿**（#164：空结果曾被当合法的 0 念成 PASS）。
   ⇒ 一个数能不能被引用，取决于它所在的那份报告属于哪一档。
2. **交付文档的"唯一出处"只有三份。**
   `src/host/metric_recheck.mjs:14` 明写：只判点名了
   `timing_summary` / `utilization` / `power` 的行；认不出的行算未判并打印条数（`:15`）。
   它读的表是 `data/metrics.csv`（`src/host/metric_recheck.mjs:19`），
   最后一列"证据文件"就是落款位。**这是"文档数字 → 报告"这条唯一被机器核对过的通道。**
3. **归档件与活件是同一批名字、两个目录。**
   活件在 `build/`（下一次构建原地重写），归档件在 `build/report/`（`build/report.tcl` 能整批重出）。
   `build/README.md:122` 给的引用建议是"引用报告时**优先指 `build/report/` 那一份**"——
   因为它的生命周期与构建解耦。本次实测 `build/report/` 下正好 7 份 `.rpt`。
   这条一致性有尺子：`build/deliver_spec_check.mjs` 的 C4/C4b 判
   "`build/report/` 归档件与脚本一一对应、且件里真有条目"
   （`build/deliver_spec_check.mjs:361` 那句注释就是理由：
   C4 只看文件名，"那判的是文件名不是内容"）。

还有一族**逐时钟名册**报告，出处是探针而不是构建：
`build/tcl/probe_timing_roster.tcl:39` 写死了文件名形状
`build/roster_${label}_${nm}_${kind}.rpt`，`:113` 另有一型
`build/roster_${label}_fanout.rpt`。⇒ **文件名是拼出来的，所以能预测。**
但也正因此，**预测出来的名字可以完全合律而盘上根本没有**：
本次实测存在的是 `build/roster_r118_after_clk_fpga_0_setup.rpt` 这一族 7 份，
而 `build/roster_r118_after_fanout.rpt` **不在仓里**（`ls` 直接报 No such file）。
⇒ 交付文档里点任何名册件，必须是那次跑真落过的件。
这是"每个数字点名它的报告"最容易翻车的地方：**报告名可推导 ≠ 报告存在。**

## 13. 第 13 段：两份凭据为什么必须与报告同一次生成

`:375-409`。这一段在**跑完实现之后**，读的是 run 目录里的 `runme.log`：

```
foreach lg [glob -nocomplain [file join $proj_dir [file tail $proj_name].runs * runme.log]]   :384
  … if {[string match "*Synth 8-689*" $line]} { incr wcount; lappend wseen … }                :388
  … if {[string match "*multi-driven net*" $line]} { incr mcount; … }                         :394
set wf [open [file join $outdir width_warnings.txt] w] … close $wf                            :398-401
set mf [open [file join $outdir multi_driven.txt] w] … close $mf                              :403-406
```

**为什么单独落文件，而不是让 `gates.sh` 去 grep 最新日志**（`:376-379`）：
以前出现过"报告是 A 版、日志是 B 版"的错配——那一刻这一项绿得没有意义。
凭据与报告同一次生成、一起进冻结目录，才是"这一套 bit 没有宽度问题"的证明。
这一条与 `build/gates.sh:47-53` 的新鲜度判据是同一个思想的两半：**把"同一套"变成机器可判的事**。
（门禁侧的对应项：`build/gates.sh:210`（第 8 项 Synth 8-689）、
`build/gates.sh:233`（第 13 项多驱动 Synth 8-6859/8-6858）。）

两类被数的警告各自为什么值得单列：

- **`Synth 8-689`（端口宽度不匹配）扫的是综合 `runme.log`，带 file:line**（`:379`）。
  来历是 `system_top` 里 `wire [5:0] dbg_src` 接在 8 bit 端口上，综合只给一条警告，
  于是 lane 的模式高位被静默吞掉（读出来永远 0/1），**而当时七项门禁全绿**
  （`build/gates.sh:210-212`）。⇒ 工具早就报了，是**没人读警告**，所以把它变成门禁项。
- **多驱动 net 必须单独数**（`:389-393`），因为综合与仿真的语义**相反**：
  综合的处理是"保留常量那一侧、忽略逻辑那一侧" ⇒ bit 里那根线恒 0；
  而**仿真按进程后写覆盖，行为看起来完全正确**。
  原话："这是『台架全绿、硬件不工作』最省事的一条路"，
  并且给了具体标本（2026-09-24 踩在 `border_r` 上：
  旗标链的复位被同时写进两个 always 块，ISSUES #61）。
  ⇒ **一个警告值不值得进门禁，判据是"它的静默失效模式是否恰好是仿真查不出来的那种"。**

`multi_driven.txt` 当前内容是 `0`（`build/multi_driven.txt`，1 行）——
`gates.sh` 第 13 项读的就是这个文件，而不是再去 grep 日志。

## 14. 分步入口、别当入口的东西、失败定位顺序

### 14.1 五支分步入口各自的默认停点

| 入口 | 干什么 | 关键行 | 停在哪 |
|---|---|---|---|
| `build/build.tcl` | 全量（等价主脚本） | `build/build.tcl:9` | 到 bit + 7 份报告 |
| `build/create_project.tcl` | 只建工程与导源 | `:8` 设 `VP_STOP_AT=project` | `:301-305` 那个出口 |
| `build/add_sources.tcl` | 同上（共用第一段） | `:9` | 同上 |
| `build/synth.tcl` | 只跑综合 | `:13` `reset_run synth_1` | `PROGRESS` 判定 |
| `build/impl.tcl` | 只跑实现到 route | `:21` `-to_step route_design` | `:23-25` |
| `build/report.tcl` | 只重出 7 份报告 | `:18-24` | `:27-31` |
| `build/gen_bit.tcl` | 只补 bit + 拷到板侧 | `:17-26` | `:29-33` |

五支 `build/*.tcl` 的头部都带同一套六要素（作用 / 前置条件 / 产出物 / 关键参数 / 退出码），
这是交付规格 C4 判的"头部要素"（`build/deliver_spec_check.mjs:337`）。

### 14.2 不要当入口用的东西（每条都有点名理由）

- `build/tcl/build_pl_full.tcl`：根解析少一层 ⇒ `add_files` 指向不存在的 `build/src/…`
  （`build/README.md:31-33`）。它自己还会把 top 设成 `pl_demo_top`（`build/tcl/build_pl_full.tcl:23`）。
- `build/tcl/README.md:4-6` 提到的 V7 流程 `create_project.tcl` + `build_bitstream.tcl`、
  以及 `:19-23` 点名的 `build_system.tcl`、`synth_pl_only.tcl`——
  **这四支在盘上已经不存在**（本次实测：`build/tcl/` 下无 `create_project.tcl`/`build_system.tcl`，
  全仓 `find . -name "synth_pl_only*"` 为空）。
  那页 README 的"这一页只写今天还在用的"承诺在这里已经漂了。
  ⇒ **文档指路也要对回盘上件**；引用文档里的脚本名之前先 `ls`。
  本仓管这件事的尺子是 `src/host/doc_currency_check.mjs`（D2：文档点名的目录必须在盘上，`:19`）。
- `build/tcl/README.md:47-55` 列的一次性修复脚本
  （`apply_cdc_report.tcl`、`fix_bd_and_top.tcl`、`rebuild_opt.tcl`、`rebuild_zoom_out.tcl`）
  原话是"当年只修某一个版本的 BD/顶层，没有任何脚本或现行文档调用它们，
  留在这里只为可追溯；**新工作不要基于它们改**"。
- `build/` 根下那批 `rNN_*` 链脚本（`build/r118_chain.sh` 等）：
  `build/README.md:79-81` 写得很直白——"**它们不是可复用的工具**，
  是因为交付文档按名字引着它们当某一刀的凭据才留在仓里；
  读的时候按『当时那一步的现场』读，别照抄里面的默认路径当现行流程"。

### 14.3 失败了按什么顺序看（这一份是可以直接照做的）

`build/README.md:94-97` 给的顺序，落到本次读过的具体日志行：

1. 先在**这一次构建自己的 console 件**里 grep 五个停机标记：
   `SYNTH FAILED`（`:309`）、`ADDRESS PINNING FAILED`（`:274`）、
   `PORT_LOOKUP_FAILED`（`:232`）、`BUILD_STRATEGY_REJECTED`（`:319`）、
   `BUILD_HOOK_REJECTED`（`:330`）、`BUILD_PRPO_REJECTED`（`:346`）。
   命中哪个就是哪一步停的。
2. 一条都不中、而缺末行 `SYSTEM BUILD DONE`（`:411`）→ 再看
   `…runs/synth_1/runme.log` 与 `…runs/impl_1/runme.log`。
3. BD 配错这一类根本不该走到第 2 步：先跑 `bd_only`（第 9 步的 `-tclargs bd_only`）。
4. 判"构建到底成没成"：看 `build/` 下产物的 mtime，不看退出码（§2）。

这些 `puts` 文本本身是**接口**，不是给人看的闲聊：
第 14 项门禁和 `build/board_verify.sh` 都靠这些字样定位停点。
⇒ 改脚本时把 `puts` 改了措辞，会静默改掉一组判据的射程。

---

## 15. 把这条链讲清楚的三条结论

1. **"构建脚本"的真正产物不是 `.bit`，是一组可核对的声明**：
   工程 part、顶层名、哪些约束在哪个阶段生效、用了哪档策略、挂了哪个钩子。
   所以本仓把这些全部 `puts` 进日志、并把两份警告计数落成文件（§7.5、§13）。
   一句 `:316` 的话可以当这一章的题眼：**产物自己带着它的出身。**
2. **约束与代码的差别，在于它有两个生效阶段。**
   一旦明白 `used_in_synthesis false` 是一个**可声明的属性**而不是一个技巧，
   "为什么拆文件"、"为什么 r116/r119 都拆"、"为什么拆分不改时序数字"三件事就同时解释了。
   配套的三条工具口径：**XDC 里不许有控制流**、**`-quiet` 压不住命令失效**、
   **取不到对象会让整条命令空转**。这三条都是量出来的，不是文档里查来的。
3. **默认值就是发布决策。** 六个环境变量里两个决定"约束进不进这一版位流"，
   三个决定"实现走哪一档"，而**不设 = 出货档**。
   这不是省事，是一种记录方式：把"我们不带这件"这个决定
   写成一个可复现的命令（`VP_R116_IO_WINDOW=1` 再构建一次），
   而不是写成一次被删掉的改动。

## 16. 自检题

1. `add_files` 的目录列表在哪一行？`top/` 为什么不在这个列表里？
   `src/rtl/top/pl_demo_top.v` 在这条链上被综合了吗？（`:25`、`:28-29`）
2. `glob -nocomplain` 会怎么骗你？把 `src/rtl/eth` 改名成 `src/rtl/ethernet` 之后
   构建会失败吗？你用什么办法发现自己错了？（`:26`、§5 第 3 点）
3. `set_property used_in_synthesis false` 在这支脚本里被用了几次？
   每一次的理由分别是什么？（`:37`、`:59`、`:77`）
4. 为什么"综合阶段拿不到时钟组"这件事不改变时序数字，
   却值得单独一个文件？如果 XDC 里允许写 `if`，还会拆吗？（`:32-35`，
   `src/constraints/rk_zynq7020.xdc:62-75`）
5. `VP_R116_IO_WINDOW` 与 `VP_R119_TMDS_WINDOW` 都默认关，
   两次的理由差别在哪？哪一个是"量过会红"，哪一个是"还没量"？（`:47-56` vs `:70-71`）
6. `IMPL_STRATEGY` 为什么不能写死在脚本里？非法策略名会发生什么？（`:313-322`）
7. `bd_only` 与 `VP_STOP_AT` 是两套传参通道，各是什么？
   为什么 `build/create_project.tcl` 设不出 `bd_only`？（`:278`、`build/create_project.tcl:8`）
8. 端口改名为什么不能信 `make_bd_pins_external` 的返回值、
   也不能按子串匹配？现在的验法是什么，验不出来怎么办？（`:212-235`）
9. 地址回读为什么要先 `scan … %x` 再比数值？
   直接字符串比会怎样、为什么之前那次判红不是"地址没钉上"？（`:259-271`）
10. `gates.sh` 要求四份报告必在，主脚本只对两份不包 `catch`，
    `report.tcl` 只验两份——这三处不一致各是因为什么？
    （`build/gates.sh:43-45`、`build/tcl/build_system_axigpio.tcl:362-363`、
    `build/report.tcl:27-29`）
11. 为什么"报告是 A 版、日志是 B 版"这件事必须靠一个落盘文件来防，
    而不是靠"记得同一次跑"？（`:375-379`）
12. 有人递给你一条 `build/roster_r118_after_fanout.rpt`。
    这个文件名合律吗？它在仓里吗？你据此能说什么、不能说什么？（§12 末）

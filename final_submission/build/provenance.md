# 来源卡（provenance）—— 本轮成品 = r118

> 这张卡只回答一件事：**仓库里现在这套 `board/project/system.bit` / `.xsa` / 报告，是哪一版源码、哪一版工具、
> 哪一档旋钮、在什么时刻生出来的。** 数字解读归实现报告本身，轮次台账归 `docs/`，本卡不重复。
> 本卡里每一个值都写"从哪个文件哪一行/哪次实跑取到的"，没取到的写 `【待实测】` 或 `NOT_MEASURED`。
> 本卡**不预测**任何重建结果：本轮没有跑任何构建、没有 place/route、没有覆盖任何已入库产物。

## 0. 这卡说的是哪一版

| 项 | 值 | 出处 |
|---|---|---|
| 轮次号 | r118 | `仓库留档 r118_chain.sh（剪枝件，不随包）:25`（`NN=118`） |
| 板上现在跑的版本 | r118（刷入 2026-10-04 04:49:50） | `仓库留档 r118_board（归档件，不随包）/board_now.txt:1` |
| 位流身份 | `md5(前 12) = cd04907e1369` | `board/output/r118_bit_md5.txt`、`仓库留档 r118_verdict.txt（剪枝件，不随包）:1`、`仓库留档 gates.txt（剪枝件，不随包）:3` 三处独立同值；本卡第 5 节当场重算 |
| 工作区与 HEAD 是否同一份 | 同一份（下列 12 个产物 `git status --porcelain` 全空） | 实跑：`git status --porcelain board/project/system.bit board/project/system.xsa board/project/ps_app.elf build/{timing_summary,utilization,power,route_status,methodology,cdc,clock_util}.rpt build/{width_warnings,multi_driven}.txt` → 空输出；`git cat-file -s HEAD:board/project/system.bit` = 2202122 = 盘上字节数 |

## 1. 源码指纹（编译**之前**采集，绑内容不绑行尾）

尺子**只有一把**，就是仓库自带的 `build/rtl_fingerprint.sh`（`fpver=norm1`：每份 `.v` 先 `tr -d '\r'`
再取 md5，行格式固定 `<32位md5>  <相对路径>`，按 C 排序后合一次 md5 取 12 位）。
定义与"为什么不能直接用磁盘字节的 `find|md5sum`"写在该脚本文件头（`build/rtl_fingerprint.sh:1-23`）。
**本卡不另起一条指纹口径**；任何与本卡不符的指纹都是另一把尺子，先对齐尺子再对齐数。

采集时刻与命令（逐字）：

```bash
bash build/rtl_fingerprint.sh > board/output/r118_tree_fp.txt 2>&1   # 仓库留档 r118_chain.sh（剪枝件，不随包）:27
```

采集到的值（`board/output/r118_tree_fp.txt` 原文，四行）：

```
fpver=norm1
files=80
top=56c269602e18
rtl=07570b1ac1b4
```

顺序证据：链脚本第 27 行先采指纹、第 30 行才起 Vivado；`仓库留档 r118_console.txt（剪枝件，不随包）:1` 打印
`[r118 04:18:25] 指纹 rc=0 top=56c269602e18 rtl=07570b1ac1b4`，而构建会话横幅
（`仓库留档 r118_build_console.txt（剪枝件，不随包）:6`）是 `Start of session at: Sun Oct  4 04:18:27 2026` —— **指纹早 2 秒**。

事后重算（本卡写完后当场跑，两次）：

```bash
bash build/rtl_fingerprint.sh > /tmp/fp_run1.txt 2>&1
bash build/rtl_fingerprint.sh > /tmp/fp_run2.txt 2>&1
cmp /tmp/fp_run1.txt /tmp/fp_run2.txt          # rc=0 ⇒ 逐字节一致
diff /tmp/fp_run1.txt board/output/r118_tree_fp.txt   # rc=0 ⇒ 与 r118 采集那份一致
```

本次实跑结果：`rc1=0 rc2=0`、`cmp rc=0`、`diff rc=0`，值为 `files=80 / top=56c269602e18 / rtl=07570b1ac1b4`。

与 git 的对账（判据 4）：`git diff --stat src/` 空（跟踪内容零改动），`git log -1 --format=%h -- src/rtl`
= `cc017e6`。⇒ 当前树的 norm1 指纹 = r118 采集的指纹，**没有"行尾差 vs 内容差"要分辨的情形**。
唯一需要点名的偏差：`src/constraints/` 下有 2 个未跟踪的候选件
（`r119_hdmi_source_window.xdc`、`r119b_hdmi_tp1_pinclk.xdc`，本机时间 09:20 / 09:30，
**不是本卡这次写的**）。它们不在 `src/rtl/` 扫描面内（尺子只看 `src/rtl/*.v`），所以不动指纹；
但它们也**不在 r118 位流里** —— r118 的约束集是 `rk_zynq7020.xdc` + `clock_groups_impl.xdc`
（`build/tcl/build_system_axigpio.tcl:19-26`），两个候选件按 `VP_R116_IO_WINDOW` /
`VP_R119_TMDS_WINDOW` 开关加载且默认关（同文件 `:45-70`）。

**指纹的射程要说清**：这把尺子量的是 80 份 `src/rtl/*.v`。它**不覆盖** BD 配置、`src/ps` 固件源码、
构建脚本本身、工具版本。所以"指纹相同"只等于"PL 的 RTL 相同"，不等于"这一版整套可复现"。
构建脚本这一维本轮就出现了真实缺口：`build/tcl/build_system_axigpio.tcl` 的字节数与内容在 r118
之后被改过（今天 09:25，工作区状态 `M`，未提交），改的是新增 `VP_R119_TMDS_WINDOW` 那一档默认关的分支
⇒ **今天这份入口脚本 ≠ 生出 r118 那份入口脚本**，尽管默认路径逐字等价（两档开关都不设就是不挂）。

## 2. 工具版本（原文照抄，不按记忆）

构建横幅（`仓库留档 r118_build_console.txt（剪枝件，不随包）:1-6`，逐字）：

```
****** Vivado v2025.2.1 (64-bit)
  **** SW Build 6403652 on Thu Mar 19 19:48:24 GMT 2026
  **** IP Build 6403511 on Thu Mar 19 12:41:45 MDT 2026
  **** SharedData Build 6403650 on Thu Mar 19 14:02:13 MDT 2026
  **** Start of session at: Sun Oct  4 04:18:27 2026
```

| 工具 | 版本串 | 出处 | 说明 |
|---|---|---|---|
| Vivado | v2025.2.1 (64-bit)，SW Build 6403652 | 上面行 1-2 | 本次安装位置在盘上核对到 `.../2025.2.1/Vivado/bin/vivado.bat` 存在（本机路径不入库） |
| Vitis / xsdb | 【未核实】 | 本卡没在跟踪件里找到 Vitis 的版本串；板上链只用 `VP_XSDB` 指到 `xsdb.bat` | 要补一次 `xsdb.bat -Version` 的原文，别拿 Vivado 的版本冒充它 |
| arm-none-eabi-gcc（PS 固件） | 【未核实】 | `仓库里的 ps_app.mjs（工具，不随包）:10,26` 只说明编译器由 `PS_CC` 给、没有版本断言 | 与 ELF 那一行一起补（见第 5 节末） |
| 器件 | `xc7z020clg484-2` | `build/tcl/build_system_axigpio.tcl:5` | 设备库在场性本次用盘上核对：`<Vivado>/data/parts/installed_devices.txt（不随包）` 内 grep 到 `xc7z020clg484`（大小写敏感的完整器件名列 `xc7z020`、`xc7z020clg484`、`xc7z020i`）。**注意：没有任何构建脚本做这一步断言**，兜底是 `create_project -part` 自己报错 |

**版本偏离声明（P15a 铁律 5 要求的那一行）**：本工程的声明版本是 **2025.2.1**，不是赛题推荐的 2026.1。
差异需要在报告里说明；本卡的构建链没有对版本做等值断言（第 6 节"缺"那一栏登记），
换到别的 2025.2.x 或 2026.1 时**指纹仍然可比，但时序数字、报告形状、甚至器件库内容都不保证可比**。

## 3. 策略 / 旋钮 / 种子

构建日志里自己念出来的（逐字，行号是 `仓库留档 r118_build_console.txt（剪枝件，不随包）` 的）：

| 旋钮 | r118 实际取值 | 日志行 | 若 unset 的默认语义 |
|---|---|---|---|
| 实现策略 `IMPL_STRATEGY` | `Vivado Implementation Defaults` | `:1756` `BUILD_STRATEGY Vivado Implementation Defaults` | 不设 = 工程默认策略 |
| 布局后钩子 `IMPL_POST_PLACE_HOOK` | `none` | `:1766` `BUILD_POST_PLACE_HOOK none` | 不设 = 不挂（入口 `:309-317`） |
| 布线后物理综合 `IMPL_PRPO` | `off` | `:1779` `BUILD_PRPO off` | 不设 = r64b 那一档流程（入口 `:322-333`） |
| RGMII 输入窗 `VP_R116_IO_WINDOW` | `off` | `:39` `VP_R116_IO_WINDOW off（…留在候选件 src/constraints/r116_rgmii_input_window.xdc…）` | 不设 = 不加载（`:45-52`） |
| HDMI 源端窗 `VP_R119_TMDS_WINDOW` | **该档在 r118 之后才存在**，r118 日志里没有这一行 | 负结果：`grep -a VP_R119_TMDS_WINDOW 仓库留档 r118_build_console.txt（剪枝件，不随包）` 无命中 | 入口脚本今天（09:25）才加这一档 ⇒ 复现 r118 不需要设它，但**复现 r118 用的脚本字节与现在不同**（第 1 节末） |
| 并行度 | `launch_runs synth_1 -jobs 4`、`launch_runs impl_1 -to_step write_bitstream -jobs 4` | `:255`、`:1780` | 写死在入口脚本里 |
| 随机种子 | **本流程没有设置任何 seed 参数** | 负结果：`grep -in "seed" 仓库留档 r118_build_console.txt（剪枝件，不随包）` 无命中 | ⇒ 跨次构建不保证逐位相同；本仓库的"同方向两次独立构建"这一判据形态就是为绕开这一点（入口 `:293-297` 的注释记着理由） |

BD 侧的可复现关键值：三个 AXI GPIO 从地址钉死 `0x41200000 / 0x41210000 / 0x41220000`，
r118 日志回读 `ADDR_LOG … num_ok=1`（`:209-211`）；四个外部端口改名成功（`:161-167`）。
这两组是"产物自己带出身"的凭据，重建后必须仍然逐字吻合，否则 BD 配置漂了。

## 4. 起止时间戳（全部来自日志/盘上时间，不用记忆）

| 时刻（本机） | 事件 | 出处 |
|---|---|---|
| 2026-10-04 04:18:25 | 源码指纹采集完（rc=0） | `仓库留档 r118_console.txt（剪枝件，不随包）:1` |
| 2026-10-04 04:18:27 | Vivado 批处理会话起 | `仓库留档 r118_build_console.txt（剪枝件，不随包）:6` |
| 2026-10-04 04:19:26 | `Launched synth_1`（含 6 个 OOC IP 并行） | 同文件 `:275`、`:283` |
| 2026-10-04 04:29:35 | `synth_1 finished` | 同文件 `:1743` |
| 2026-10-04 04:29:37 | `Launched impl_1` | 同文件 `:1781` |
| 2026-10-04 04:36:59 | `impl_1 finished` | 同文件 `:2619` |
| 2026-10-04 04:36:56 | `system.bit` 写出 | `stat` 盘上 mtime |
| 2026-10-04 04:37:57 | 会话退出（`Exiting Vivado`）；`width_warnings.txt` / `multi_driven.txt` 同分钟落盘 | 文件末尾行、盘上 mtime |
| 2026-10-04 04:37:58 | 链脚本记 `构建 rc=0` | `仓库留档 r118_console.txt（剪枝件，不随包）:3` |
| 2026-10-04 04:45:26 → 04:47:07 | 刷板一轮（JTAG `rst -system` → `ps_jtag_boot` → `program_pl` → 读回） | `仓库留档 r118_board（归档件，不随包）/bitcycle_console.txt` 首末行 |
| 2026-10-04 04:49:50 | 板上确认为 r118 | `仓库留档 r118_board（归档件，不随包）/board_now.txt:1` |

分阶段墙钟耗时与"这些数怎么算出来的"见 `build/README.md` 的耗时表（同一批日志，不重复取数）。

## 5. 产物清单（路径 + 两枚摘要 + 落盘时刻 + 是否入库）

摘要**本卡当场真算**：`md5sum <f> | cut -c1-12` 与 `sha256sum <f> | cut -c1-16`。

| 路径 | md5(12) | sha256(16) | mtime | 入库 | 身份 |
|---|---|---|---|---|---|
| `board/project/system.bit` | `cd04907e1369` | `204f5498e091c98c` | 10-04 04:36:56 | 是（`d420db6` 起） | **r118 成品位流**，与第 0 节三处独立同值一致 |
| `仓库留档 r118_bit（归档件，不随包）/system.bit` | `cd04907e1369` | `204f5498e091c98c` | 10-04 04:45:26 | 是 | 同上的采纳副本（`仓库留档 r118_chain.sh（剪枝件，不随包）:95` 拷的） |
| `仓库留档 r118_bit（归档件，不随包）/md5.txt` | — | — | 10-04 04:45 | 是 | 随副本走的身份条 |
| `board/project/system.xsa` | `934ebdbaa13b` | `ffc3eda9e35c6764` | 10-04 04:37:55 | 是 | r118 的硬件平台（`write_hw_platform -fixed -include_bit`，入口 `:352`） |
| `build/reports/build_timing_summary.rpt` | `8ff1201d17ae` | `7291d41286cb5a97` | 10-04 04:37:30 | 是 | r118 |
| `build/reports/build_utilization.rpt` | `7dd1932b2d2a` | `c1655e31fa1bd037` | 10-04 04:37:30 | 是 | r118 |
| `build/reports/cdc.rpt` | `443785a20f42` | `e6cef709d6b87eb3` | 10-04 04:37:32 | 是 | r118 |
| `build/reports/methodology.rpt` | `645029c4dafe` | `442be25df5812836` | 10-04 04:37:40 | 是 | r118 |
| `build/reports/power.rpt` | `e7be51c9e05b` | `c8d0a5c3dab2463a` | 10-04 04:37:48 | 是 | r118（**估算**，无仿真活动文件、无实测） |
| `build/reports/build_route_status.rpt` | `a6d3822c92d7` | `76074eed5c3f9768` | 10-04 04:37:48 | 是 | r118 |
| `build/reports/clock_util.rpt` | `22ce2506d78d` | `25b44ac649300dd4` | 10-04 04:37:49 | 是 | r118 |
| `build/reports/width_warnings.txt` | `21438ef4b9ad` | `13bf7b3039c63bf5` | 10-04 04:37:57 | 是 | 内容 `0`（`Synth 8-689` 计数，入口 `:379-383`） |
| `build/reports/multi_driven.txt` | `21438ef4b9ad` | `13bf7b3039c63bf5` | 10-04 04:37:57 | 是 | 内容 `0`（多驱动 net 计数，入口 `:384-387`）；与上一行同摘要 = 两个文件都只装一个字符 `0`，**不是"同一份内容被复制"**，要区分就看行数以外的字节 |
| `board/project/ps_app.elf` | `d0b07f84a068` | `307158926058e1a1` | **2026-10-01 00:12:44** | 是 | **不是 r118 生的**：r118 那一轮没重编 PS 应用（链脚本里没有 `node 仓库里的 ps_app.mjs（工具，不随包）`，`仓库留档 r118_chain.sh（剪枝件，不随包）` 全文无 `ps_app`）。它只和 r118 的位流"在同一块板上一起跑过"（`仓库留档 gates.txt（剪枝件，不随包）:5` 把它与 bit/xsa 并列打身份，`build/board_verify` 下板用的就是它） |
| `board/output/r118_tree_fp.txt` | 指纹记录 | — | 10-04 04:18 | 是 | 第 1 节 |
| `仓库留档 r118_build_console.txt（剪枝件，不随包）` | 构建日志（237 729 B） | — | 10-04 04:37 | **否（未跟踪）** | 第 2/3/4 节的唯一出处 ⇒ 见第 6 节缺口 G3 |

## 6. 「证据文件与报告必须成对提交」—— 声明与本轮配对状态

**规矩（这一条不许打折）**：一份报告（`.rpt`）与它的证据文件（当轮构建日志 / 门禁件 / 台架件 /
指纹记录）必须**成对提交**。只有报告没有日志 ⇒ 那份报告声称的"出自哪一版源码、哪一档旋钮"
无法核对，**另一份不存在时这一份也不可信**；只有日志没有报告 ⇒ 读数没有落点。
两者单独出现时，读者要按"未配对"处理，不得引用来支持任何结论（哪怕它 `GATES: ALL PASS`）。

r118 的配对核对（本卡逐个打开确认，不看文件名猜）：

| 报告 | 配对证据 | 在不在 | 是否入库 |
|---|---|---|---|
| 上面 9 份 `build/*.rpt` | 构建日志 `仓库留档 r118_build_console.txt（剪枝件，不随包）` | 在 | **未入库** ⇒ 缺口 G3 |
| 同上 | 门禁件 `仓库留档 gates.txt（剪枝件，不随包）` = `仓库留档 gates.txt（剪枝件，不随包）`（`cmp` 逐字节相同，本次实跑） | 在 | 未入库（`git ls-files` 未命中） |
| 同上 | 指纹 `board/output/r118_tree_fp.txt` | 在 | 已入库 |
| 位流 | 采纳副本 + `md5.txt` | 在 | 已入库 |
| 台架（第 15 项 `tb_video_pipeline_top`） | 该轮门禁念的指纹是 `top=56c269602e18` = **当前树**，但门禁行末判语是 `FAIL` | 报告在 | 见下 |

本轮门禁的真实读数（**照抄原文，不加解释**）：`仓库留档 gates.txt（剪枝件，不随包）` 共 23 行结尾 `PASS`、
1 行结尾 `FAIL`，末行 `:54` 是 `GATES: 有红项（判定 24 项）—— 不采纳，保留上一版`；
唯一红的那一行是 `:34`
`顶层台架 tb_video_pipeline_top    top=56c269602e18 FAIL行=1 指纹(norm1):fresh fresh fresh 同一次跑且无 FAIL      FAIL`。
链脚本的采纳口径要求"红数 == 1"（`仓库留档 r118_chain.sh（剪枝件，不随包）:91`），而它 04:42 那一次跑出门禁
`绿=21 红=3` 并当场写下"不采纳（B1 或 B4 不过）：板子回刷 r114"（`仓库留档 r118_console.txt（剪枝件，不随包）:10`）；
最终采纳记录在 `仓库留档 r118_board（归档件，不随包）/board_now.txt` 与 `gatesc/gatesd_summary.txt`
（`green=23 red=1`）。**两条相反口径的句子都在库里，本卡都点名，不挑一句念。**

### 缺口登记（这一版**没有**做到的事，逐条）

| # | 缺口 | 后果（可判定的说法） |
|---|---|---|
| G1 | 没有 `build/evidence_r118/` 成套冻结目录，也没有该轮的 `MANIFEST.md5` | 现行尺子 `build/freeze_evidence.sh` 要求门禁 `GATES: ALL PASS` 才肯冻结（`:26-30`），而 r118 的门禁是 `有红项` ⇒ r118 按现有规矩**不可冻结**，只能靠本卡逐个指路。最后一次成套冻结是 `仓库留档 （归档件，不随包）`（盘上 mtime 序） |
| G2 | `board/project/ps_app.elf` 与 r118 位流**不同源**（差 3 天），且它的构建日志没找到配对 | 任何"这套 ELF 是这一版位流的固件"的说法都不成立；要说"板上就是这两件"只念 `board_now.txt` |
| G3 | 构建日志与门禁件未入库，而 9 份 `.rpt` 与位流已入库 ⇒ **报告侧入库、证据侧未入库**，正好是本节上面那条规矩要防的形状 | 别人 clone 下来只有报告，无法核对旋钮与时刻；本卡第 2/3/4 节的行号引用在远端仓库里会指到不存在的文件 |
| G4 | 无 seed 设置，跨次逐位相同不成立 | 见第 3 节末；采纳判据必须是名册/同方向两次，不能是 md5 相等 |
| G5 | 本卡的"从零复现"能力**未演练**（见第 7 节） | 只能声明"来源可核对"，不能声明"可复现" |

## 7. 本轮没跑的那些事（不许用历史日志冒充刚跑过）

| 项 | 状态 | 缺的具体是哪一次运行 |
|---|---|---|
| 从零演练（独立副本目录，一条命令出全套产物） | `NOT_MEASURED` | 缺一次在**独立目录副本**里跑 `build/rNN_chain.sh` 的同形链、并留下它自己的构建日志 + 门禁件 + 目录名。本轮按边界不跑构建（板上与仓库当前都是 r118，任何重建都会换掉已采纳产物） |
| 重跑同一命令不覆盖上一次归档 | `FAIL`（现状即不满足，对照表里 A2/A3 那两行，再加上本行下一列那句 `file copy -force`） | 入口脚本对 `board/project/system.bit` 是 `file copy -force`（`build/tcl/build_system_axigpio.tcl:341`）、对工程目录是 `create_project … -force`（`:9`）⇒ 第二次运行**原地覆盖**，不产生第二个目录名 |
| 残留进程防护被人为触发一次 | `NOT_MEASURED` | 配方与"该由谁触发、触发后应看到什么"写在 `仓库留档（探针输出，不随包）`；本轮不与队伍的设备/会话冲突 ⇒ 未触发。被它挡住的验证一律 `NOT_MEASURED`，不当回归、不覆盖 |
| 版本等值断言、器件库断言、磁盘余量探测 | `FAIL`（现有脚本没做，不是本轮没测） | 逐条对回脚本的哪一行做了/没做，见 `build/README.md` 的自探测清单 |

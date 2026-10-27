---
name: pl-load-verify
description: 把"位流刷进去了"变成可判读数。当 Vivado/Vitis 自己报完成但 PS 侧读回全 0、串口一个字节不回、DONE 状态不明，或需要按"复位值→短读写→递增长度→满速流"分层确认 PS↔PL 地址通路、核对加载顺序（先起 PS / 再编 PL / 后重下应用）与加载前后的对拍件时使用。面向 JTAG 调试器 + 裸机（无 Linux 驱动）形态；PYNQ 形态见本条对位表。
---

## 1. 一句话用途

分层证明 PL 已配置且地址通路真的读得回来。

## 2. 适用场景

- 当 `program_hw_devices` / 工具链跑完没有报错，但读回目标寄存器得到 `0x00000000` 或调试器直接卡住时。
- 当板子"上一次还能用、这次不能用了"，需要判断坏在 PS 初始化、PL 配置、还是应用侧时。
- 当刷完位流之后串口/控制台不再应答，而 JTAG 里处理器核仍显示 `Running` 时。
- 当交付件里有 `.bit`/`.xsa` 而没有可执行的启动介质（SD 镜像、Linux 驱动），加载只能靠调试器完成时。
- 当需要一套"加载前后各留一个可对拍的东西"（镜像摘要 + 回读值）来支撑"已上板"这个结论时。
- 当要判断"地址映射覆盖不到目标段"还是"从设备根本没在位流里"这两类不同故障时。

## 3. 不适用 / 失效条件

- 不适用 Linux 侧固件加载形态（`fpga-mgr` / device-tree overlay / `/sys/class/fpga_manager`）：那条路径的判据在内核日志与 `state` 属性里，本条的命令与判据都不成立。
- 不适用只有部分重配置（PR / Partial Bitstream）而无全量刷写流程的设计：本条的"顺序不可交换"断言是按全量配置的复位行为写的，PR 前置条件不同。
- 不适用调试器被占用（`hw_server` 端口被别的会话连走）或多板共链的环境：本条所有"读不到输入"分支都要先排除这两件事。
- 不适用本条之外的器件家族自带的判据：Zynq-7000 的 `DONE`/startup 状态文本、`xc7z020` 设备选择都是本仓示例取值，UltraScale+/Versal 的报文字符串与器件名不同（见表 5-B）。
- 若目标地址段在互联里根本没被 assign（表 5-A 的 L1 层读不出任何值且调试器不返回），本条的后续层全部无意义 —— 先回构建侧修地址映射。

## 4. 前置条件

- 工具与版本：本条在 Vivado / Vitis 2025.2.1 + Zynq-7020（`xc7z020clg484-2`）下写成（版本出处 `report/BUILD.md` §1、`data/metrics.csv` 第 2 行）。换版本要重核表 5-C 的报文字符串。
- 需要的输入文件：待刷的位流（本仓 `build/system.bit`）、PS 初始化脚本 `ps7_init.tcl`（本仓不单独存放，从 `build/system.xsa` 里自动解出，见 `build/tcl/ps_jtag_boot.tcl`）、应用镜像（本仓 `build/ps_app.elf`）。
- 需要的权限或硬件连接状态：JTAG 线缆在线且 `hw_server` 可达（默认 `localhost:3121`）；12V 电源上电；串口终端未被别的进程占用；调试器进程有对该 hw_server 的访问权。
- 环境变量（不写死机器路径）：`VP_XSDB` 指到 `xsdb.bat`、`VP_VIVADO_BIN` 指到 `Vivado/bin`、可选 `VP_BIT` 指到别处的位流、可选 `PS7_INIT` 显式给 `ps7_init.tcl` 路径。缺 `VP_XSDB` 时本仓脚本在第一步就 `REFUSE`（`report/BUILD.md` §1 表 + `build/board_verify.sh`）。

## 5. 使用方法

### 5-A 分层通路确认（顺序即判据，层与层不许跳）

| 层 | 确认动作 | 通过判据 | 失败时先看什么 |
| --- | --- | --- | --- |
| L1 已知复位值 | 对目标从设备做一次纯读（`mrd <基址>`），不发任何命令、不跑任何软件 | 调试器在 1 s 内返回一行 `地址: 值`，且值等于该口的复位默认 | 读挂住 / 无返回 ⇒ 先确认 PL 已配置（表 5-C 的 DONE 行）与互联地址段是否 assign 到该基址；这一步不需要任何应用配合，读不出就是地址通路本身不通 |
| L2 写图案读回 | 往同一口的保留字段写一个图案，再读回比对 | 回读逐位等于写入图案 | 回读恒 0 或恒 F ⇒ 该从设备不在这份位流上（elf/bit 不配套）；回读只低位对 ⇒ 端口线宽被吞，去查顶层那根线的声明宽度 |
| L3 单条短传输 | 让 PL 处理一次"一发一收"的最小事件（本仓：翻转一次发布位，屏上重画一帧） | 状态位或回读口出现这一次事件的痕迹 | 无痕迹 ⇒ 时钟域与复位释放顺序（FCLK 是否起来、`FCLK_RESET0_N` 极性）；有痕迹但值错 ⇒ 回到 L2 |
| L4 长度与吞吐递增 | 把负载按档提高（本仓 15 → 30 → 60 fps） | 每档的计数器单调不减且零丢 | 高档才错 ⇒ 搬运窗口/带宽；低档就错 ⇒ 回到 L3 |
| L5 满速持续流 | 不限速跑一轮（本仓 `--pace-mbps 0`，约 147 Mbps） | 同一份读数里"活着"位与"零丢计数"同时成立 | 只有满速错 ⇒ 是排队/背压，不是通断；"零计数"在链路不活时读到的是零样本，不算通过（见 §6 末行） |

L1 必须是第一层：它是这条链里唯一不依赖任何软件配合、也不需要应用先跑起来的判据。

### 5-B 加载动作与顺序依赖（显式断言：顺序不可交换）

1. 加载前核对镜像身份，别按文件名认它：

   ```bash
   md5sum build/system.bit
   cat build/evidence/r118_bit/md5.txt        # 本仓示例存档路径，需按自身工程替换
   ```

   完成后应看到：两行 md5 前 12 位相同。不同 ⇒ 去 `build/frozen_*/` 或 `build/evidence/rNN_bit/` 取那一版，不要硬下（同名不同内容的位流在本仓发生过两次，见 `report/BUILD.md` §7 规矩 2）。

2. 起 PS（含一次系统复位）：

   ```bash
   "$VP_XSDB" build/tcl/ps_jtag_boot.tcl
   ```

   完成后应看到：`PS7_INIT_FILE:`、`RST_SYSTEM: ok`、`PS7_INIT: ok`、`PS7_POST_CONFIG: ok`、`DDR_ECHO: 10000000:   5A5AA5A5`、末行提示下一步是 `program_pl.tcl`。

3. 编 PL：

   ```bash
   "$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl
   ```

   完成后应看到：配置前的 `is not programmed (DONE status = 0)`、配置后的 `INFO: [Labtools 27-3164] End of startup status: HIGH`、`PROGRAMMED <器件> <- <位流>`、Vivado `exit 0`。想拿别处的位流做对照：`VP_BIT=<路径>` 前缀式赋值再跑同一条命令。

4. 重下应用（只复位核、不动 PL）：

   ```bash
   "$VP_XSDB" build/tcl/ps_app_reload.tcl
   ```

   完成后应看到：`RST_PROC:` / `DOW: ok` / `PC_BEFORE_CON: 0x00000000` / 若干寄存器采样行 / `RESUME: ok` / `FLOW_DONE`。再用串口确认应用真的进了 `main`：

   ```bash
   powershell -File board/uart_cap_once.ps1 -Seconds 20
   ```

   应看到开机横幅那一行（本仓为 `[BOOT] video_pipeline PL-UDP control plane`，换题目后是自身的横幅）。

顺序断言与违反后的可观察征兆（三条都是可判定的，不是建议）：

- **PS 初始化必须在编 PL 之前**：`ps7_init` 负责 DDR 与 FCLK；未跑它就编 PL，则 L3 之后所有依赖 FCLK 域的通路都不动，且 `ps7_init.tcl` 的 tcl 版本不含 FSBL 才会写的 SLCR 类寄存器（`build/tcl/ps_jtag_boot.tcl` 文件头记着这条限度：正常交付流程仍应走 FSBL/ELF）。
- **`ps_jtag_boot.tcl` 含 `rst -system`，跑过它就必须重下位流**（`report/BUILD.md` §3 第 4 步）；反过来 `ps_app_reload.tcl` 只做 `rst -processor`，位流、控制字、正在跑的数据流都不受牵连。违反后的征兆不是报错，而是"工具全绿、板子却对着已经不存在的 PL 空转"。
- **换应用不要退回带 `rst -system` 的那支脚本**：那会把配好的位流冲掉，连带要求重编 PL + 重写控制字 + 重推流（`build/tcl/ps_app_reload.tcl` 文件头写的就是这个动机）。

### 5-C 校验闭环（"工具无报错"不等于加载成功）

加载前后各留一个可对拍的东西，两个都要留：

- 前：镜像摘要（步骤 5-B 第 1 步的 md5 对拍，落件如 `build/evidence/r118_bit/md5.txt`）。
- 后：回读值 + 状态文本。本仓把"位流里有没有这个从设备"做成了应用开机自检：写图案到保留字段再读回，成功打 `[CFG] ... ok`、失败打 `[CFG!] ...`（`src/ps/main.c` 的 `main()` 开头一段）。**只数工具 rc 为 0 不数回读值，是这类流程最常见的假绿。**

### 5-D 高危：处理器仍在访问 PL 地址空间时重编 PL

断言（平台无关的措辞）：当 PS/SoC 侧软件正在敲 PL 地址空间（轮询寄存器、等待总线响应）时对 PL 重新编程，会让 PS 侧总线或调试通路挂死；此时 JTAG 里核仍显示 `Running`，而控制台一个字节都不回 —— "看起来还活着"恰恰是它的症状。

恢复顺序（彻底断电是兜底，不是第一步）：`rst -system`（或先 halt APU）→ 重新初始化 PS → 重编 PL → 重载应用 → 重新起流量再读数。

- 本仓取证：`report/log/ISSUES.md` `#315`（2026-10-04 01:49）—— 三步链自己报全绿之后串口哑掉，`targets` 显示两个 A9 均 `(Running)`；用 `build/tcl/r116_jtag_recover.tcl` 的 `rst -system` 恢复后串口立刻回 1428 字节，凭据 `build/r116_recover_console.txt`。
- 该故障在别的器件家族/别的加载通路（Linux 固件加载、PR 通路）上的表现与恢复粒度是否相同：`【未在本队取证】`。

### 5-E PYNQ 对位写法

| 本条步骤 | PYNQ 形态（对位写法） | 版本相关列（适用版本 / 需核对） |
| --- | --- | --- |
| 5-B 第 3 步：调试器编 PL | `from pynq import Overlay` + `Overlay("【填入】.bit")`；文档明写实例化即隐式下载，`download=False` 可只建对象不下载，之后 `base.download()` 显式下载 | PYNQ v2.5.1（`pynq_libraries/overlay.html` 原文），v2.7+/v3.x 的等价写法 `【核对】` |
| L1 前的"镜像身份"对拍 | 无 PYNQ 内置等价物；仍要自己留 `.bit` 摘要。官方文档同时要求 overlay 必须成对提供 `.bit` 与硬件元数据文件（原文："a .bit and .tcl must be provided for an overlay"） | 该句出自 PYNQ v2.5.1 文档；新版本是否仍要求 `.tcl`（改为 `.hwh`/`.xsa` 流程）`【核对】` |
| L1/L2 读复位值、写图案读回 | `Overlay` 建好后按名取 IP 块：`add_ip.read(0x20)` / `add_ip.write(0x10, 4)`，或按字段名 `add_ip.register_map.a = 3` | PYNQ v2.5.1（`overlay_design_methodology/overlay_tutorial.html`）；寄存器名由设备树驱动，字段名与位序随版本/硬件描述文件而变 `【核对】` |
| 判"这份位流里到底有没有这个从设备" | `base.ip_dict` 里没有这个 IP 名 ⇒ 硬件描述里就没有，不必等到读回 0 才发现 | PYNQ v2.5.1 |
| 加载后"活着没"的读数 | 本仓的 lane 窗口读数在 PYNQ 下换成 `MMIO(IP_BASE_ADDRESS, ADDRESS_RANGE)` + `mmio.read(ADDRESS_OFFSET)`（基址与范围来自设备树） | PYNQ v3.1（`pynq_libraries/mmio.html`）；v2.5.1 同名类的参数写法 `【核对】` |
| 顺序断言（先 PS 后 PL 后应用） | PYNQ 里 PS 侧就是 Linux，`Overlay` 调用发生在驱动已就绪之后，因此 5-B 的前两条顺序被运行时吸收；只剩"重编 PL 前先停掉正在访问 PL 地址空间的用户进程"这一条仍然成立 | 与 PYNQ 版本无关的流程约束 |

## 6. 判读与失败分叉

| 命令 | 通过 → 下一步 | 失败 → 下一步 | 读不到输入 |
| --- | --- | --- | --- |
| `md5sum build/system.bit` | 进 5-B 第 2 步 | 与存档 md5 不符 ⇒ 从 `build/frozen_*/` 取那一版；取不到就停，别下当前这份 | `NO BIT` ⇒ `NOT_MEASURED`：位流不在（构建没跑/被覆盖），等于"没测"，不等于加载成功 |
| `"$VP_XSDB" build/tcl/ps_jtag_boot.tcl` | 进编 PL | `CONNECT:` 有报错 ⇒ `hw_server` 未起或端口被占；`RST_SYSTEM` 非 ok ⇒ 调试通路本身坏了，先解决它再做任何判读 | `NO ps7_init.tcl` ⇒ `NOT_MEASURED`：先确认 `.xsa` 在位（脚本会从里面自动解出），缺件就是缺件 |
| `"$VP_VIVADO_BIN/vivado.bat" -mode batch -nojournal -source build/tcl/program_pl.tcl` | 进 L1 | `NO xc7z020 IN CHAIN` ⇒ 链上器件名/`hw_server` 版本不对（本仓示例值，需按自身器件名改） | `REFUSE: 找不到 xvlog`/找不到 vivado ⇒ `NOT_MEASURED`：设 `VP_VIVADO_BIN` 后重跑，未跑不等于通过 |
| L1 `mrd <基址>` | 进 L2 | 挂住或无返回 ⇒ 回 5-C 查 DONE 行与地址段 assign；返回全 0 ⇒ 记下"这份位流里可能没有这个从设备"这个候选，进 L2 用图案证它 | 拿不到调试器输出 ⇒ `NOT_MEASURED`，不许把"没读到"写成"读回 0" |
| L2 写图案读回 | 进 L3 | 回读恒 0/恒 F ⇒ 从设备不在位流上（elf/bit 不配套）；只有低位对 ⇒ 顶层线宽吞了高位，本仓同族事故记录在 `report/log/ISSUES.md` `#57` | 图案读不到 ⇒ `NOT_MEASURED` |
| 串口 `board/uart_cap_once.ps1` | 进 L4 | 零字节但核 `(Running)` ⇒ 按 5-D 的恢复顺序走一遍再判 | 端口被占 ⇒ `NOT_MEASURED`：先释放 COM 口 |
| L5 满速一轮 | 记录进报告 | 只在满速错 ⇒ 查背压/排队，不是通断问题 | 计数读不出来 ⇒ `NOT_MEASURED`，并且：`drop_words=0` 在链路不活（`eth_live=0`）时是零样本通过，**判红而不是判绿**（`report/log/ISSUES.md` `#316`） |

三态只有 `PASS` / `FAIL` / `NOT_MEASURED`；表里凡是 `NOT_MEASURED` 的行都不计入通过。

## 7. 已验证的效果

- 用它之后（加载链路本身）：
  - 复跑命令：`bash build/r116_bit_cycle.sh <标签> [位流路径]`（它按 `rst -system → ps_jtag_boot → program_pl(VP_BIT) → ps_app_reload → 带流读两次` 串起来）。
  - 输入路径：`build/evidence/r118_bit/system.bit`（摘要 `build/evidence/r118_bit/md5.txt` = `cd04907e1369`）。
  - 期望输出：日志里 `boot rc=0`、`pl rc=0 PROGRAMMED=2`、`app rc=0 FLOW_DONE=1`，且两次带流读数 `eth_live=1 owner_eth=1 drop_words=0`。
  - 实际输出摘要：`build/evidence/r118_board/bitcycle_console.txt`（2026-10-04 04:45:26 起，逐行 `recover rc=0` / `boot rc=0` / `pl rc=0 PROGRAMMED=2` / `app rc=0 FLOW_DONE=1` / 读数 a、b 两次 `eth_live=1 owner_eth=1 drop_words=0`）；原始控制台在 `build/evidence/r116_board/cycle_r118build.log`，同一次跑里还带着 Vivado `INFO: [Labtools 27-3164] End of startup status: HIGH` 与 `DDR_ECHO: 10000000:   5A5AA5A5`。⇒ 判定 PASS。
- 用它之后（开机自检式的"从设备在不在位流上"闭环）：
  - 复跑命令：`"$VP_XSDB" build/tcl/ps_app_reload.tcl` 后 `powershell -File board/uart_cap_once.ps1 -Seconds 20`。
  - 输入路径：`build/ps_app.elf` + 当轮位流。
  - 期望输出：横幅里出现 `[CFG] axi_gpio_2 @41220000 ok`（基址是示例取值）。
  - 实际输出摘要：`build/frozen_r45_v8morph/uart_r45_banner.txt` 第 5 行正是这句话（该冻结集日期 2026-09-24）；`build/frozen_r48_osdsrc/uart_r48_boot.txt` 里两条自检同时成立（`axi_gpio_2` 与 gamma 窗口）。⇒ 判定 PASS。
- 不用它的基线（这一步省掉了什么）：`report/log/ISSUES.md` `#315` 记录的正是"没做 5-D 前置复位"的一次 —— 三步链 rc 全 0、`board_verify` 红 3 条，之后才回推出"刷 PL 前先 `rst -system`"这条改动。⇒ 有凭据，判定 PASS。
- 表 5-A 的 L4/L5 递增长度：本仓只做过"零样本读数"与"满速一轮"两端，中间档位的逐档判据 `【待验证】`（要跑的是：同一份位流下把帧率按档提上去，每档留一份读数件）。
- UltraScale+ / Versal、Linux 固件加载形态下的同类判据：`【待验证】`，本仓无对应件，5-E 之外的对位写法不宣称可用。

## 8. 提炼来源与边界

- 来源证据（点名文件，不复述过程）：
  - `build/tcl/program_pl.tcl`（器件选择、`DONE status = 0` 与 `End of startup status: HIGH` 这两行、`VP_BIT` 覆盖）
  - `build/tcl/ps_jtag_boot.tcl`（`ps7_init.tcl` 三级寻找顺序、从 `.xsa` 自动解包、DDR 写读自检 `DDR_ECHO`、"tcl 版 ps7_init 不含 FSBL 才会写的寄存器"这条限度）
  - `build/tcl/ps_app_reload.tcl`（`rst -processor` 与 `rst -system` 的分界、`PC_BEFORE_CON`/`CPSR` 判据）
  - `build/r116_bit_cycle.sh` 文件头与 `build/evidence/r116_board/cycle_r118build.log`、`build/evidence/r118_board/bitcycle_console.txt`（分层读数的实跑形状）
  - `build/tcl/r116_jtag_health.tcl` / `build/tcl/r116_jtag_recover.tcl` / `build/r116_recover_console.txt`（5-D 的判据与恢复动作）
  - `report/log/ISSUES.md` `#315`（重编 PL 弄哑控制台）、`#316`（零样本通过）、`#57`（线宽吞高位）、`#22`（脚本 root 少一级 `..`，只在板前才暴露）
  - `report/BUILD.md` §1–§3、§7（工具定位、上板顺序、冻结与 md5 对拍三条规矩）
- 恒成立 / 平台相关 / 版本相关怎么分：流程顺序（L1→L5、PS→PL→应用、前后各留对拍件）恒成立；器件名 `xc7z020`、地址 `0x41200000`、报文字符串属平台与版本相关，集中在表 5-A/5-E 与 §4，不要混进正文断言。
- 不再适用的条件：改用 Linux 驱动加载（判据移到内核侧）；只做部分重配置；调试器通路被独占；目标器件没有 `DONE`/startup 状态这类可读回文本；应用侧没有开机自检回读（此时 L2 必须人工做，本条的闭环那一半不成立）。
- 迁移到新题目/新板卡要改的几处：① 器件选择字符串与位流路径；② 从设备基址与"哪个字段是保留位可以拿来写图案"；③ 应用侧开机自检那一句的期望文本；④ 串口的抓取命令与端口号；⑤ 表 5-E 的 PYNQ 版本列（v2.5.1 / v3.1 之外一律先 `【核对】` 再写死）。

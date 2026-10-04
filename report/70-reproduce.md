# 70 · 复现说明（他人从零开始完整执行的操作步骤）

对应赛题 §3.3.5.3 的"复现说明：一份可供他人从零开始完整执行的操作步骤"。
与仓库根 `README.md` 的"复现三步"**同源**：这里把那三步展开成逐命令，并在第 6 节列出五处不一致及权威判定。
`README.md`、`report/build.md`、`build/README.md`、`board/README.md` 不在这次的改动范围里，冲突只登记并给出应改动作。

**从零到屏幕出现画面的顺序**就是下面这几条命令，按顺序敲，每条后面写清了敲完该看到什么；
每条的完整前置、shell 与判读在上板那一节（第 4 节）的对应行里。

1. 接线与上电（上板那节的接线自检行）：12 V 适配器、HDMI 到 1024×600 面板、USB-C 到板载 FT4232、网线接 PL 网口。
   看到：屏亮，OSD 五行出现在画面上。
2. `node --version`（环境自检那节的第一行）——看到 `v24.`；工具不在 `PATH` 就按同节的变量说明改走 `VP_VIVADO_BIN`。
3. `netstat -an -p TCP | grep 3121`——看到一行 `LISTENING`；没有这一行就先起 `hw_server`，否则后面每一步的 `CONNECT:` 都会空。
4. `ping -n 4 192.168.1.10`——看到 4 个应答，说明板子已经起来、网口通。
5. `vivado -mode batch -source build/tcl/build_system_axigpio.tcl`（构建那节）——看到脚本按四件事播报，结束时
   `build/` 里有 `system.bit`、`system.xsa` 与那几份 `.rpt`。第一次跑这一条最花时间，一条构建的墙钟是几十分钟量级。
6. `<Vitis>/bin/xsdb.bat build/tcl/ps_jtag_boot.tcl`——看到 `RST_SYSTEM: ok` 与 `DDR_ECHO: 10000000: 5A5AA5A5`。
7. `vivado -mode batch -source build/tcl/program_pl.tcl`——看到 `PROGRAMMED xc7z020_1` 与 `End of startup status: HIGH`；
   这一步之后屏上出现 OSD。顺序不能换：位流没烧之前应用起不来。
8. `<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl`——看到 `DOW: ok` / `CON: ok` / `FLOW_DONE`，串口打出
   `[BOOT] video_pipeline PL-UDP control plane`。
9. `send_demo.bat` 或 `python src/host/video_sender.py --demo --fps 25`——看到**屏幕上半是原图、半是处理后画面**，
   OSD 的 `SRC` 走到 ETH。这一步就是"画面出来了"。
10. `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom`——看到末行
    `RESULT board_verify PASS（判红的步骤：0）`，把刚才那一屏的画面用机器判定再钉一遍。

第 3 节（台架仿真）不在这条出画面路径上，可以先跳过；第 5 节是把读回来的数字对回原件，第 8 节列出哪些步骤第三方验不了。

## 0. 判定口径（先看这一段，否则最后一列会被误读）

- 每条命令后面有 **本次判定**，只允许三态（这一列是给读的人分辨"哪一步真跑过"的）：
  - `PASS` —— 这一轮真跑了这条（或它的只读等价式），输出摘要与退出码贴在文末第 9 节；
  - `FAIL` —— 跑了且判为不通过，原文照贴，不弱化；
  - `NOT_MEASURED` —— **没跑**。没跑的原因逐条写明（本轮禁跑 / 缺设备 / 缺批准 / 未在本平台验证）。
    读不到输入就记 `NOT_MEASURED`，不记 `PASS`。
- 步骤里没有"自行配置""视情况调整""按需修改"。缺的信息一律写成 `【不可复现，原因 …】`，并在第 8 节说明第三方因此验不到什么。
- 执行目录一律写相对路径（`<仓库根>` 指本仓库克隆到本地的那一层目录）；
  shell 一律写明是 **Git Bash (MSYS2, sh)** 还是 **cmd/PowerShell**——两者的路径与 `python`/`python3` 不通用（第 7 节）。
- 没有板子时的最短路径 = 第 1 节全部 + 第 5 节（四条只读检查在包内也能跑）；出画面需要第 4 节的板子与人。

---

## 1. 环境自检（八步，全部只读，无需批准）

| # | 命令 | 执行目录 / shell | 所需外部设备与状态 | 完成后应看到什么 | 本次判定 |
|---|---|---|---|---|---|
| 1.1 | `node --version` | `<仓库根>` / Git Bash | 无 | `v24.`（`report/build.md` §1 写的"需要 Node 24"）| **PASS**：`v24.21.0` |
| 1.2 | `python --version` 与 `python3 --version` | `<仓库根>` / Git Bash | 无 | 至少一条给 3.x；**MSYS 上通常是 `python`，不是 `python3`**（第 7 节）| **PASS/FAIL 两态**：`python` → `Python 3.12.10`；`python3` → `command not found`，**rc=127** |
| 1.3 | `bash --version` 与 `git --version` | `<仓库根>` / Git Bash | 无 | `GNU bash, version 5.x…-release (x86_64-pc-msys)`、`git version 2.x` | **PASS**：`5.2.37(1)-release (x86_64-pc-msys)`、`2.52.0.windows.1` |
| 1.4 | `which vivado vivado.bat xsdb xsdb.bat arm-none-eabi-gcc` | `<仓库根>` / Git Bash | 无 | 若五条全 `no … in (…)` ⇒ 工具不在 `PATH`，**必须**改用 `VP_VIVADO_BIN` / `VP_XSDB` / `PS_CC`（`report/build.md` §1 的变量表）| **PASS**：五个全部未命中（`which` rc=1）⇒ 本仓库走变量，不走 `PATH` |
| 1.5 | `ls <Vivado>/bin/vivado.bat <Vitis>/bin/xsdb.bat`（`<Vivado>`/`<Vitis>` 换成实际安装目录）| `<仓库根>` / Git Bash | 无 | 两行路径都列出来 = 工具在位 | **PASS**：两份都存在（这里不写本机绝对路径，规矩见 `report/build.md` §1）|
| 1.6 | `<Vivado>/bin/vivado.bat -version` | `<仓库根>` / Git Bash | 无（不建工程、不读板）| 打印 `vivado v2025.2.1 (64-bit)` 与 `SW Build …`；**版本必须是 2025.2.1 或文档里另记的版本**，否则时序/资源数不可比（`skills/references/tool-version-drift`）| **PASS（附一条未核实）**：版本串打印正确，但**退出码 = 1**。原因本次未查 ⇒ 标 `【未核实】`；读 `-version` 的判据应是版本串，**不是 rc** |
| 1.7 | `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe --version` | `<仓库根>` / Git Bash | 无 | `…(GCC) 13.3.0`，rc=0 ⇒ 编 PS 应用的能力**在**（这一条推翻本仓多处"本机没有 bare-metal 编译器"的说法，见 `report/60-failure-analysis.md` A4）| **PASS**：rc=0，`arm-xilinx-eabi-gcc.exe (GCC) 13.3.0` |
| 1.8 | `netstat -an -p TCP \| grep 3121` | `<仓库根>` / Git Bash 或 cmd | 无（只问本机监听）| `TCP 0.0.0.0:3121 0.0.0.0:0 LISTENING` ⇒ `hw_server` 在听；**没有这一行就别往下走上板**，第 4 节第一步会 `CONNECT:` 空（这条形状出自 `board/acceptance.md` r96 那一行的教训与 `board/hardware_setup.md` 的探测表）| **PASS**：命中 1 行 `LISTENING` |

**六支入口脚本的语法自检**（只读，不执行）：

```bash
bash -n build/gates.sh build/board_verify.sh build/sim/run_one.sh build/sim/mut_control.sh \
        build/freeze_evidence.sh build/make_submission.sh
```

执行目录 `<仓库根>` / Git Bash。完成后应看到：**没有任何输出**（`bash -n` 只在语法错时说话）。
本次判定 **PASS**：六支全部静默通过（逐支跑过，每支打印一行 `bash -n OK <名字>`）。

---

## 2. 构建（出位流 / XSA / 报告）

> 本节整节 **NOT_MEASURED**：这一轮的动作范围里不含跑构建（要队伍批准）。
> 下面每条都写清了执行目录、shell、前置与期望，第三方可以直接照做；每条后面写明本次没跑的原因。

| # | 命令 | 执行目录 / shell | 前置与外部状态 | 完成后应看到什么 | 本次判定 |
|---|---|---|---|---|---|
| 2.1 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl` | `<仓库根>` / Git Bash 或 cmd（`vivado` 换成 `<Vivado>/bin/vivado.bat` 全路径，或把 `bin` 加进 `PATH`）| 磁盘余量（一轮实现会写 `vivado_system/`）、无第二个 Vivado 在跑（`report/log/issues.md` 的 #234/#251 记过"改正在跑的脚本 / 起第二个实例"两类自己弄坏构建的情况）| 脚本自己按四件事播报：建工程 → 收 RTL/约束/BD（清单 `build/tcl/set_src.tcl`）→ 综合 → 实现出位流；产物 `build/system.bit`、`build/system.xsa`、`build/*.rpt`（**平铺在 `build/`**，见第 6 节冲突 3）；中途失败会打印停在哪一步且不留下半套 | `NOT_MEASURED`（本次禁跑构建）|
| 2.2 | `md5sum build/system.bit` | `<仓库根>` / Git Bash | 2.1 跑过，或盘上已有本版位流 | 32 位 md5；拿它认身份，**不认文件名**（`report/known_issues.md` §3"位流与固件不入库/靠 md5 认身份"那条）| **PASS**：本次读到 `cd04907e1369…`，与 `build/r118_gates.txt` 的身份行 `system.bit md5=cd04907e1369` 逐字相同 ⇒ 盘上那份就是 r118 |
| 2.3 | `python build/build_ps_app.py`（或 `node build/ps_app.mjs`）| `<仓库根>` / Git Bash | 需 `PS_CC`（1.7 那条路径）与 `PS_BSP`（默认指仓库内 `vitis/platform/…/bsp`）；**不想动交付件时把 `PS_OUT` 指到别处**（`report/build.md` 变量表明写这条）| 产出 `ps_app.elf` 并通过四道自检（入口==`_boot`、`_vector_table`==0x0、`.text` ≥ 20 KB、五个符号都在）；任一不过 ⇒ 非零退出，因为"链接成功"不等于可执行 | `NOT_MEASURED`（本次禁跑构建；`PS_CC` 未设时它第一步 REFUSE 的文案本次实读在 `report/build.md` 里，未实跑验证）|
| 2.4 | `bash build/freeze_evidence.sh rNN` | `<仓库根>` / Git Bash | 2.1 完成且发布前检查无未通过项 | 成套拷进 `build/frozen_rNN_<短名>/` 并写 `MANIFEST`；**发布前检查有未通过项时它会 REFUSE**（`GATES: ALL PASS` 才允许出现，否则打 `PARTIAL` 或有红项 ⇒ 拒绝归档）| `NOT_MEASURED`（本次既不跑构建也不改盘内 `build/`）；今天盘上门禁是**有红项**那一支（见 5.1）⇒ 照做会得到 REFUSE，这是预期行为不是故障 |

**为什么这一节只能整节 `NOT_MEASURED`**：一条构建的墙钟是几十分钟量级，且会原地覆写 `build/system.bit`、`*.rpt`
这些**被文档按身份引用的件**。这一轮的动作范围把构建划在禁跑内，所以这一节给的是操作步骤 + `NOT_MEASURED`，不是"已验证"。

---

## 3. 仿真（台架，不在出画面路径上）

> 本节 **NOT_MEASURED**（本轮禁跑台架）。命令、前置、期望写全，跑法与判读同源 `sim/README.md`。

| # | 命令 | 执行目录 / shell | 前置 | 完成后应看到什么 | 本次判定 |
|---|---|---|---|---|---|
| 3.1 | `export VP_VIVADO_BIN=<Vivado>/bin` 然后 `bash build/sim/run_one.sh tb_v98_top_seam` | `<仓库根>` / Git Bash | 1.4/1.5 确认了 `<Vivado>/bin` 里有 `xvlog`；**不能有别的 xsim 活着**（`run_one.sh` 自己会拒，两个 xsim 会往同一个 `run.log` 里写）| 末行一条 `RESULT tb_v98_top_seam PASS` 或 `FAIL nfail=N`；**当前树的期望值是 `FAIL nfail=1`，红在 `C5c`**（这一条是声明过、故意留红的判据，见 `report/60-failure-analysis.md` A1）| `NOT_MEASURED`（禁跑台架；顶层那支一轮约 2 小时）|
| 3.2 | `bash build/sim/run_one.sh tb_head_rot_displace` | 同上 | 同上 | `RESULT … PASS cells=49152 pairs=12` 这种形状；它只例化 `zoom_fit` + `zoom_mapper`，1~2 分钟 | `NOT_MEASURED` |
| 3.3 | `bash build/sim/run_one.sh tb_link_monitor` | 同上 | 同上 | **期望值是只红一条 `F2e B`**（`sum=518 > 2x130`）；若你看到更多红，说明你那棵树弄坏了别的 ⇒ 这条能把你和"历史红"分开（`report/60-failure-analysis.md` A2）| `NOT_MEASURED` |
| 3.4 | `bash build/sim/run_sim.tcl`（全量批跑，Vivado 模式）| `<仓库根>` / cmd 或 Git Bash | 1.4 之后；目录里 81 支 `tb_*.v` 全收（本次实测计数）| 每支一份判定行；**"放一支坏台架在目录里，每次批跑都会被它拖住"**（`sim/README.md`）——今天那支就是 3.3 | `NOT_MEASURED`（禁跑台架全量）|
| 3.5 | `bash build/sim/mut_control.sh <tb名> <判据名>` 或 `bash build/run_one_ce.sh` | `<仓库根>` / Git Bash | 不动 `src/rtl`（它拷到 `/tmp` 下做变异体）| 一条判定说自己抓住了缺陷，凭据是"把缺陷装回去它必须转成不通过"；这类对照还必须有一条**正向对照是通过的** | `NOT_MEASURED`（属台架动作）|

---

## 4. 上板（JTAG 三步 + 串口 + 推流）

> 本节 **NOT_MEASURED**：本轮禁跑刷板与串口。前置条件只读地验了一半（网络与 hw_server，见下表 4.0/4.1），
> 板子是否上电、COM6 是否被占、HDMI 是否接了 1024×600 面板，本次没有确认。这一节就是"从零到画面"那几步。

| # | 命令 | 执行目录 / shell | 所需外部设备与状态 | 完成后应看到什么 | 本次判定 |
|---|---|---|---|---|---|
| 4.0 | 接线自检：12 V 适配器、HDMI 到 **1024×600** 面板、USB-C（板载 FT4232：通道 A = JTAG、通道 B = UART ⇒ Windows 的 **COM6**）、网线接 **PL 网口** | 板前 / 人手 | 一次只插一块板的 USB-C（两块板被写成同一序列号 ⇒ `hw_server` 只出一个 target，`board/hardware_setup.md` 明写）；PC 侧 IP 配成 `192.168.1.100/24` | 屏亮并出现 OSD 五行；串口能连 | **PARTIAL**：PC 侧本次实测 `ipconfig` → `192.168.1.100 / 255.255.255.0`（PASS）；板侧三项本次**未确认**（这一轮不碰串口、不看屏）⇒ `NOT_MEASURED` |
| 4.1 | `netstat -an -p TCP \| grep 3121`（前置，不是可选）| `<仓库根>` / Git Bash | 无 | 3121 在听；没在听就先起 `<Vitis>/bin/hw_server.bat` | **PASS**（同 1.8）|
| 4.2 | `ping -n 4 192.168.1.10` | `<仓库根>` / cmd 或 Git Bash | 网线已插、板已上电、PS/PL 至少一路已起来 | 4 个应答；板 IP 的**唯一出处是 `src/rtl/eth/arp.v` 里的 `BOARD_IP` 参数**（本次实读第 30 行 `parameter BOARD_IP = {8'd192, 8'd168, 8'd1, 8'd10};`），**不是任何人记忆里的那个地址** | **PASS**：本次 `ping -n 2 -w 1000` 得 **发送 2 / 接收 2 / 0 % 丢失，平均 1 ms**；`arp -a` 学到 `192.168.1.10 → 00-11-22-33-44-55 动态`（与 `BOARD_MAC` 一致）⇒ 板上 ICMP 应答器活着（`#216/#218` 那一族在板上这一版上未复现）。注意 本次输出是 **cp936 中文**，在 MSYS 里直接 `grep` 会当二进制；要用 `… \| iconv -f cp936 -t utf-8` 才读到（这条差异写进第 7 节）|
| 4.3 | `<Vitis>/bin/xsdb.bat build/tcl/ps_jtag_boot.tcl` | `<仓库根>` / **cmd**（`.bat` 启动器；Git Bash 里也能调但要写全路径）| 4.0 + 4.1 | `RST_SYSTEM: ok` / `PS7_INIT: ok` / `PS7_POST_CONFIG: ok` / `DDR_ECHO: 10000000: 5A5AA5A5` | `NOT_MEASURED`（禁跑刷板）|
| 4.4 | `vivado -mode batch -source build/tcl/program_pl.tcl` | 同上 | 4.3 之后；**顺序不能换**（`board/README.md` §2 明写 PL 没烧之前应用起不来）| `PROGRAMMED xc7z020_1 <- …/build/system.bit` 与 `End of startup status: HIGH`；只走 JTAG，**不写 QSPI/SPI flash、不碰 EEPROM** | `NOT_MEASURED` |
| 4.5 | `<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl` | 同上 | 4.4 之后 | `DOW: ok` / `CON: ok` / `RESUME: ok` / `FLOW_DONE`，串口出现 `[BOOT] video_pipeline PL-UDP control plane` | `NOT_MEASURED` |
| 4.6 | `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom` | `<仓库根>` / Git Bash | 4.3–4.5 完成；**COM6 一次只能被一个程序占用**（自己开着终端占着时脚本会拒绝，那不是板子坏了）| 四段依次过：开机回读 / 寄存器与健康位 / 几何最后一跳 / 串口命令电池；末行 `RESULT board_verify PASS（判红的步骤：0）`，且里面 `RESULT PASS uart_cmd_check（105 条命令, …）` 与 `RESULT PASS geom_check（ok=10 fail=0）`。任何一段判红整段停住并打印是哪一段 | **NOT_MEASURED**（本次禁跑串口）。**注意**：不设 `VP_XSDB` 时它按 `report/build.md` 的设计**第一步 REFUSE 并念出变量名**，不是去找 RTL 的错——这是刻意的（`ISSUES #273` 记过链子里它因环境没传而 REFUSE 的那次）|
| 4.7 | `send_demo.bat`（双击或命令行）推一段自带测试视频；或 `python src/host/video_sender.py --demo --fps 25` | `<仓库根>` / **cmd**（`.bat`）| 4.2 通（它先 ping）；网线在 PL 口 | 屏上半原图、半处理后；`SRC` 走到 ETH。**没装 ffmpeg 时它发内置测试图**，两种都缩放到 512×300（根 README 的说法，本次未实跑）| `NOT_MEASURED`（属上板 + 推流动作）|
| 4.8 | `bash board/cmd_overflow_probe.sh`（A3 那条的板级探针）| `<仓库根>` / Git Bash | 板 + 串口；**发 O2 那一档之前必须备好断电恢复**（#233 的教训：破坏性激励要挑没人用板子的时间窗）| 基线拿不到时它打印 `PROBE-REFUSE` 而不是判绿——这是它该有的行为 | `NOT_MEASURED` |

---

## 5. 结果比对（把读回来的数字对回原件）

| # | 命令 | 执行目录 / shell | 前置 | 完成后应看到什么 | 本次判定 |
|---|---|---|---|---|---|
| 5.1 | `bash build/gates.sh` | `<仓库根>` / Git Bash | `build/` 里有本版的 `timing_summary.rpt`/`utilization.rpt`/`power.rpt`/`route_status.rpt`（缺任何一份它 `FATAL 缺报告` rc=2）| 末行只有三种：`GATES: ALL PASS（N 项全部判定）` / `GATES: PARTIAL —— 判定 N 项全过，但有 M 项因缺凭据未判` / `GATES: 有红项（判定 N 项）`。**项数以它自己打印的为准，别抄文档** | **NOT_MEASURED**。没跑的原因很具体：它第 14 项执行 `python build/check_ports.py --dup > build/ports_check.txt`（本次实读该行在 `build/gates.sh` 第 253 行），而 `build/ports_check.txt` 是**已入库文件**（`git ls-files --error-unmatch` 命中）⇒ 跑它会覆写本次授权禁区 `build/` 里的件。第三方在**自己的干净克隆**里跑没有这个约束，照做即可。注意 另有一条自己踩过的坑：`bash build/gates.sh > build/<轮次>_gates.txt` 会在第一项判定之前截断第 18 项要读的基准件（这条路径里的 `rNN` 是轮次占位，盘上并不存在这个字面名；脚本头部写明正确姿势是先重定向到 `/tmp` 再 `cp`）|
| 5.2 | `node src/host/metric_recheck.mjs`（D6：数字对账）| `<仓库根>` / Git Bash | 只读 `data/metrics.csv` + `README.md` + `build/*.rpt` | 末行 `== 数字对账：判 N 个数 … 红 0 ==`，rc=0 | **PASS**：本次输出 `判 114 个数（首页层 60 个／解析到 10/10 行；红 0）／csv 认领 10/10 行`，rc=0 |
| 5.3 | `node src/host/doc_currency_check.mjs`（D1–D4b：文档时效）| 同上 | 无 | `CURRENCY: 干净`，rc=0 | **PASS**：本次 rc=0；它同时念出基准 `D1b bit md5=cd04907e1369 → r118_gates.txt`、`D1c … PASS=22 / FAIL=1 / 判定项数=24` ⇒ 与 5.1 那条"项数以脚本自己打印的为准"是同一件事的两面 |
| 5.4 | `node src/host/line_cite_check.mjs`（D5：交付文档行号锚点）| 同上 | 无 | `D5: CLEAN（硬错 0）`，rc=0 | **PASS**：本次 `扫 209 份交付文档 … 硬错 0；锚点命中 1051；候选 384` |
| 5.5 | `node src/host/doc_enc_check.mjs`（手写件 UTF-8 / 坏字）| 同上 | 无 | `扫了 N 个手写文件：全部干净`，rc=0 | **PASS**：本次 `521 个手写文件：全部干净` |
| 5.6 | `python build/check_io_timing_coverage.py build/timing_summary.rpt` | 同上 | 无 | 九行 `IODEBT I1..I9 … GREEN/RED` + 末行 `result=` | **FAIL（真实红，不是脚本坏）**：本次 `I3_output_covered bare_out_ports=7 want=0 RED`、`I7 … RED`、`result=RED`，rc=1。含义见 `report/60-failure-analysis.md` A6 |
| 5.7 | `python build/check_ports.py --dup` | 同上 | 无 | 一行汇总 `instances=… width_compared=… violations=0 PASS` | **PASS**：本次 `instances=222 modules=80 skipped=0 width_compared=562 violations=0 PASS`，rc=0。（它同时解释了 5.1 为什么我不动盘：这条命令的产物就是被门禁读走的那份文件）|
| 5.8 | `node build/r119_window_check.mjs --self` 与 `node build/r119_window_check.mjs` | 同上 | 前者不需输入件；后者需 `build/evidence/r119_pin_skew_probe2.txt` | `--self`：造的每条畸形都**各自**动红，缺输入报 `NOT_MEASURED` 而不是绿 | **PASS**：本次 `--self` → `造 10 条畸形动红 10 条；缺输入 2 条报 NOT_MEASURED 2 条 PASS`，rc=0 |
| 5.9 | `node skills/_meta/check-skill-package.mjs skills`（技能包装配检查；旧包的 `gates.mjs` 在 2026-10-04 c7b325f 重建后**现不存在**，本行只报旧名不指路）| 同上 | 无 | 每条一行、判定在最后一列；末行三态计数 | **PASS**：本轮 rc=0，末行 `判 53 项：条目=49 索引=50 红=0 未测=0 PASS`。旧包那一版的 12 项读数（绿=9 红=2 未测=1；红在 `G2` 缺壳与 `G10` 专有名，未测在 `G11` 缺 selftest）是重建前的凭据，逐字见 `report/60-failure-analysis.md` A14；`G11` 那一维今天的等价命令是 `node skills/_meta/check-selftest.mjs`，本轮实跑末行 `SKILL-SELFTEST 判 16 项 不符=0 PASS` |
| 5.10 | `bash build/gates.sh build/evidence_rNN`（复核某一套归档件）| 同上 | 那目录里成套报告 | 同一套判定打在**那一版**产物上 | `NOT_MEASURED`（同 5.1，且它读归档目录里缺的文件时会回落到 `build/`）|
| 5.11 | `bash build/make_submission.sh`（导出提交包）| `<仓库根>` / Git Bash | 发布前检查无未通过项才该导（`#240`：采用之前跑它会把**未采用**的位流打进包）| 包落在**仓库外**的目录；`_pruned.txt` 逐条写剪了什么；包内所有"路径式指路"自检，指不到就拒绝落盘 | `NOT_MEASURED`（禁跑；且今天门禁有红项，照做也导不出）|

**包内能直接跑的检查只有四项**（`doc_enc_check`、`line_cite_check`、`doc_currency_check`、`metric_recheck`，根 README 自己写了这条边界，
并且说 D1b 那一层在包里会念"本目录没有 bit 产物 ⇒ 这一层不判"——那是**声明不可判，不是通过**）；
`ps_hb_check`、`board_verify` 与需要 RTL 源重跑的台架**要回仓库跑**。

---

## 6. 与根 README 及既有文档的冲突清单（权威 = 实际能跑通的那份）

下面 5 条都是本次实测得出的，别人的文件一条没动，应改动作逐条登记进 `report/90-open-items.md`。

| # | 冲突 | 两份说法 | 权威判定（依据 = 本次真跑/真读到的输出）| 应改的动作（谁做）|
|---|---|---|---|---|
| 1 | 上位机三支 `.bat` | `report/build.md` §2 让跑 `src\host\run_sender.bat`、`run_video.bat <mp4>`、`run_serial.bat COM5` | **以根 README 为权威**：本次实测 `find . -name "run_*.bat"` 只命中 `vivado_system/**/runme.bat`（Vivado 自己的），`src/host/` 下无 `.bat`；而根 README 用的 `send_demo.bat` 实测存在 | 把那三行改成指向 `send_demo.bat` + `python src/host/video_sender.py`（改 `report/build.md`；**非本次授权**）|
| 2 | 台架名 | `report/known_issues.md` §1 的复现命令写 `bash build/sim/run_one.sh tb_video_pipeline_top` | **仓库内以 `sim/tb_v98_top_seam` 为权威**：本次实测仓库里没有名为 `tb_video_pipeline_top.v` 的台架文件；`tb_video_pipeline_top` 是导出时的改名（`build/sim/names.md`、`build/make_submission.sh` 的 `NAME_MAP`）| 该命令旁加一句"仓库名 = `tb_v98_top_seam`，包内名 = 此名"（已随本轮落在 `report/known_issues.md` §1 那一行）|
| 3 | 报告落哪 | `build/README.md` 说构建产出 `build/reports/` 里那六份 `.rpt` | **以盘上实测为权威**：本次 `ls build/reports` → `No such file or directory`；六份报告平铺在 `build/`（`build/timing_summary.rpt` 等实测存在）。根 README 已写明"仓库平铺、提交包里展平进 `build/reports/`，同一批文件两种摆法" | `build/README.md` 那句补上"仓库内平铺"这一半（改 `build/README.md`；不在这一轮的改动范围）|
| 4 | 下载 bit 用哪支 tcl | `report/build.md` §2 用 `build\tcl\program_system.tcl`；根 README 与 `board/README.md` 用三步 `ps_jtag_boot → program_pl → ps_app_reload` | **以三步链为权威**（交付口径、且 `board/acceptance.md` 每一版的行 1 都是按这三步记的）。两支脚本本次实测**都存在**，所以这不是缺失而是两条路并存 | `build.md` 那行标注"老的一键下载路径，与三步链的关系 …"（改 `report/build.md`；不在这一轮的改动范围）|
| 5 | 板上现在跑哪一版的数字 | `board/README.md` 实测表写 WNS `0.720` / WHS `0.033` / `0 / 50890` / `2.207 W`，点名 `build/timing_summary.rpt`、`build/power.rpt` | **以报告原件 + 根 README 为权威**：本次实读 `build/timing_summary.rpt` = `0.739 / 0.052 / 0 / 51135`，`build/power.rpt` = `Total On-Chip Power (W) 2.391`；`metric_recheck` 本次判红 0 但它的取数名单（实读脚本 `:274-283`）不含 `board/README.md` ⇒ 那两行在对账检查的覆盖范围外，不是脚本漏判 | 两个选项：把该表改成只指本版件不复述数字，或把它纳入 D6 的覆盖范围（改 `board/README.md` 或 `src/host/metric_recheck.mjs`；**都不在这一轮的改动范围**）⇒ 已作为 A13 进 `report/60-failure-analysis.md` |

**另有一处不算冲突但必须一起念**：根 README 的"关键数字"第一行写着
"本页不作门禁全绿声明……只以 `bash build/gates.sh` 打印的那一行为准"。这一轮的第 5.1 条没跑，
所以这里给不出"复现成功 = 全部通过"的说法；一律以脚本自己打印的那一行为准。

---

## 7. 平台差异（Windows/MSYS ↔ Linux，逐条实测/逐条标注）

| 事项 | Windows + Git Bash（本次实测）| Linux | 复现时怎么办 |
|---|---|---|---|
| `python` / `python3` | `python` → 3.12.10；`python3` → **command not found（rc=127）** | `【未在 Linux 验证】` | 这里的命令一律写 `python`；照 `report/build.md`/`host_guide.md` 抄 `python3` 前先 `which python3`。两条文档命令名差异登记在第 6 节之外的开放项（P21 收口）|
| 路径写法 | `<Vivado>/bin` 在 Git Bash 里是 `/d/...` 这种；脚本内部一律用 `$(dirname "$0")/..` 回算仓库根，**不需要设仓库根**（`report/build.md` §1 给了这条的正对照）| 同一套脚本应可跑，但**没验过** | 变量：`VP_VIVADO_BIN`、`VP_XSDB`、`PS_CC`、`PS_BSP`、`PS_OUT`、`VP_BIT`、`IMPL_POST_PLACE_HOOK`、`VP_R116_IO_WINDOW` |
| `.bat` 启动器 | `xsdb.bat`、`vivado.bat`、`send_demo.bat` 必须是 Windows 批处理入口 | Linux 侧对应的是 `xsdb`、`vivado` 可执行文件，**`send_demo.bat` 在 Linux 上跑不了** | `【未在 Linux 验证】`：Linux 用户改用 `python src/host/video_sender.py --demo --fps 25`（`report/host_guide.md` 的命令表），不给未经检验的等价命令 |
| 控制台编码 | Windows 控制台中文按 **cp936** 落：本次 `ping`/`ipconfig` 的中文在 MSYS 里是乱码，`grep` 会把整段当二进制；本次用 `… \| iconv -f cp936 -t utf-8` 读到 | Linux 一般是 UTF-8，`iconv` 不需要 | 读工具原始回显时**先按字节判断编码**（这也是仓里 `doc_enc_check` 只扫手写件、不扫 `*.txt` 原始回显的原因）|
| 换行 | 仓库用 `.gitattributes` 把源码与脚本钉成 `eol=lf`，**不钉 `*.txt`/`*.rpt`**（`known_issues.md` §16 的 #202：按磁盘字节算指纹被 CRLF 翻车过一次）| 同上 | 指纹一律用 `build/rtl_fingerprint.sh` 的**去 CR 内容指纹**（`fpver=norm1`），不要在别处再算一遍 |
| 进程探测 | `ps -W` 看不到 Windows 进程名（`#244`）| `ps` 正常 | 判断"有没有 xsim 在跑"要看工具自己的工作目录（`/tmp/kx/<tb>.run/`），不要只看日志文件 0 字节 |

---

## 8. 不可复现清单（铁律 4：缺信息就明写，并说清第三方因此验不到什么）

| # | 步骤 | 状态 | 第三方因此**无法**验证的东西 |
|---|---|---|---|
| 1 | `board/hardware_setup.md` 的接线表里 21 处 `【待你补】`（适配器型号/电流限流、USB-C/HDMI/网线规格、面板品牌型号、SD 卡容量速度等级、板是否从 USB 取电、屏与板是否共地等）| `【不可复现，原因：这些参数只能由队伍/持板人给，本仓任何文件里都没有；这里不猜引脚、不猜电压、不猜线材】` | 第三方无法判断"自己照做的接线是否等价"，尤其是"上电顺序与供电是否安全"这一类；只影响第 4 节，不影响第 1/5 节 |
| 2 | 位流/固件的二进制身份 | 板上那一版可用 `md5sum build/system.bit` 对回 `build/r118_gates.txt`（本次已对上）；**更早那一版（`known_issues.md` §20 的版本戳里写着是哪一版）那份位流不在 git 里**| 无法在不重构建的前提下复现"回到那一版"这一 A/B；要 A/B 就得取回那一版源再重建（约 20 分钟）|
| 3 | 第二家仿真器的第二意见 | `【不可复现，原因：本机只有 xsim 可跑；ModelSim 目录在 `PATH` 上（本次实测看到目录）但许可那次判 inconsistent，这一篇未复测】` | 凡"两家仿真都过"的说法都不可复现；`report/known_issues.md` §3 已明说这条 |
| 4 | 黄金参考图 | `【不可复现，原因：`data/golden/` 没有可一键重跑的生成脚本，只能人工比对】` | 不能说"与黄金参考逐像素一致"；整屏判据靠的是台架自己算的期望值，不是 golden |
| 5 | 人眼判据 E1–E6 | `【不可复现（对无屏的人），原因：屏幕读数不属于机器判据】` | 尤其 `ROT:` 那一格今天**没有机读**（`status` 那 9 位在 `system_top` 无读者）⇒ E6 只能由人判，机器复现不了（`report/60-failure-analysis.md` B4）|
| 6 | PHY 内部 RX 延迟现值 / MDIO 读 | `【不可复现，原因：app 里没有 MDIO 读命令】` | 无法验证"PHY 会不会把 FCS 错帧丢掉"（A 组 A8 / B 组 B1 的前提高于判据）|

---

## 9. 本次实跑命令与输出摘要（分母与凭据集中在这里，便于逐条核对）

| 命令 | 退出码 | 输出摘要（逐字或截断）|
|---|---|---|
| `node --version` | 0 | `v24.21.0` |
| `python --version` | 0 | `Python 3.12.10` |
| `python3 --version` | **127** | `/usr/bin/bash: line 1: python3: command not found` |
| `bash --version \| head -1` | 0 | `GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)` |
| `git --version` | 0 | `git version 2.52.0.windows.1` |
| `which vivado vivado.bat xsdb xsdb.bat arm-none-eabi-gcc` | 1 | 五条全部 `no … in (…)`（`PATH` 上无 Xilinx 工具）|
| `<Vivado>/bin/vivado.bat -version` | **1** | 前两行 `vivado v2025.2.1 (64-bit)` / `SW Build 6403652`（完整横幅那一行带着构建日期与时刻，逐字在终端输出里）；rc=1 的原因本次未查（`【未核实】`）|
| `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe --version` | 0 | `arm-xilinx-eabi-gcc.exe (GCC) 13.3.0` |
| `find /<盘>/Software -maxdepth 8 -name arm-none-eabi-gcc.exe` | 0 | 命中 1 行：`…/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe`（前台 2 分钟未返回，改后台跑满）|
| `bash -n` × 6 支入口脚本 | 0 | 无输出（逐支打印 `bash -n OK <名>`）|
| `node src/host/doc_enc_check.mjs` | 0 | `扫了 521 个手写文件：全部干净` |
| `node src/host/line_cite_check.mjs` | 0 | `D5: CLEAN（退出码只由硬错决定…）`；`扫 209 份交付文档 … 硬错 0 条；锚点命中 1051 条；候选 384 条` |
| `node src/host/doc_currency_check.mjs` | 0 | `CURRENCY: 干净`；`D1b 基准：bit md5=cd04907e1369 → r118_gates.txt`；`D1c 基准：r118_gates.txt 行尾 PASS=22 / FAIL=1 / 判定项数=24` |
| `node src/host/metric_recheck.mjs` | 0 | `== 数字对账：判 114 个数（首页层 60 个／解析到 10/10 行；红 0）／csv 认领 10/10 行／其余 18 行不点名这三份报告 ==` |
| `node skills/scripts/check/gates.mjs` | **1** | `GATES 技能包：判定 12 项 绿=9 红=2 未测=1 —— 有红项，不提交 FAIL`；红项 `G2 … 不合=13`、`G10 … 未标注=9`；未测 `G11 … 缺 skills/scripts/selftest/run_all.sh`；`G9 降级标记计数 判 86 项 总309 填入=190 待验证=48 未核实=10 未实测=61`（本节是 §5/§9 那一次实跑的逐字转录：被点的 `gates.mjs` 与 `run_all.sh` 都是 2026-10-04 c7b325f 重建前的旧包件，**现不存在**，只报当时读数不指路；今天复跑等价命令 `node skills/_meta/check-skill-package.mjs skills` 得 `判 53 项：条目=49 索引=50 红=0 未测=0 PASS`）|
| `python build/check_io_timing_coverage.py build/timing_summary.rpt` | **1** | `IODEBT I3_output_covered bare_out_ports=7 want=0 RED`；`IODEBT I7_unit_reconcile … RED`；`IODEBT-SUMMARY … judged=9 … result=RED` |
| `python build/check_ports.py --dup` | 0 | `CHECK PORTS: instances=222 modules=80 skipped=0 width_compared=562 violations=0 PASS` |
| `node build/r119_window_check.mjs --self` | 0 | `对照总结：造 10 条畸形动红 10 条；缺输入 2 条报 NOT_MEASURED 2 条 PASS` |
| `md5sum build/system.bit`（取前 12 位）| 0 | `cd04907e1369`（与 `build/r118_gates.txt` 身份行一致）|
| `md5sum build/ps_app.elf`（取前 12 位）| 0 | `d0b07f84a068`（与 `build/r118_gates.txt` 身份行一致；`git log -1 --format=%ci -- build/ps_app.elf` = `2026-09-29`（原始提交时间戳以 `%ci` 打全，这里只留日期），早于 `src/host/ps/main.c` 的 #167 那次提交 `2026-10-02`）|
| `netstat -an -p TCP \| grep 3121` | 0 | `TCP 0.0.0.0:3121 0.0.0.0:0 LISTENING` |
| `ping -n 2 -w 1000 192.168.1.10` | 0 | 中文 cp936 输出；统计行经 `iconv` 读出 `发送 = 2，接收 = 2，丢失 = 0 (0% 丢失)`、`平均 = 1ms` |
| `ipconfig \| iconv -f cp936 -t utf-8` | 0 | `IPv4 地址 … : 192.168.1.100` / `子网掩码 … : 255.255.255.0` |
| `arp -a 192.168.1.10` | 0 | `192.168.1.10  00-11-22-33-44-55  动态`（接口 192.168.1.100）|
| `grep -n link_monitor build/gates.sh` | 1 | **零命中**（⇒ `tb_link_monitor` 长期不通过且不在发布前检查的覆盖范围里，A2）|
| `grep -n "cmd_len" src/host/ps/main.c` | 0 | 第 1515 行 `if (cmd_len > 0 && cmd_len < CMD_BUF) { cmd_buf[cmd_len++] = '\n'; }`（源码已修，ELF 未重建 ⇒ A3）|
| `ls` 存在性核对（26 个被文档点名的脚本/件）| — | 23 存在、**3 缺失**：`src/host/run_sender.bat（未写）`、`run_video.bat`、`run_serial.bat`（第 6 节冲突 1）|
| 分母计数 | — | `sim/tb_*.v` = **81**；`src/rtl/**/*.v` = **80**；`build/evidence/` 条目 = **671**；`build/tcl/` = **110**；`build/evidence/*.batt.txt` = **36** |

**逐命令的三态计数（第 1–5 节共 37 条编号命令行）**，由下面这条命令现算，不靠记忆：

```bash
grep -E '^\| [0-9]+\.[0-9]+ \|' report/70-reproduce.md | awk \
 '{if ($0 ~ /\*\*PARTIAL\*\*/) p2++; else if ($0 ~ /\*\*PASS/) p++;
  else if ($0 ~ /\*\*FAIL/) f++; else if ($0 ~ /NOT_MEASURED/) n++; else o++}
  END {printf "PASS=%d FAIL=%d PARTIAL=%d NOT_MEASURED=%d 未归类=%d 行=%d\n", p,f,p2,n,o,NR}'
```

本次实跑输出：`PASS=17 FAIL=2 PARTIAL=1 NOT_MEASURED=17 未归类=0 行=37`（四类相加 = 行数，无漏计）。
三件要一起念：① **跑过的 = 17 + 2 = 19 条**，其中 2 条是真未通过（5.6 的 I/O 覆盖欠账、5.9 的技能包装配检查）——
"复现跑通了"不等于"复现结果是绿的"；② **`NOT_MEASURED` = 17 条**，逐条写明了是"禁跑"还是"缺料"；
③ 1 条 `PARTIAL`（4.0 接线自检）= PC 侧已实测、板侧本次未确认。

上面那行读数是当时那一次跑的记录。技能包在 2026-10-04 c7b325f 重建之后，装配检查那一行的判定由 `FAIL` 改成 `PASS`
（旧包件的读数仍原样贴在那一格与第 9 节），所以现在重跑同一条计数命令得到的是 `PASS=18 FAIL=1 PARTIAL=1
NOT_MEASURED=17 未归类=0 行=37`，行数不变、跑过的仍是 19 条。两处都贴出来，是为了让读的人一眼看见
"哪一格变过、为什么变"，而不是把旧读数抹平。
第 8 节的 6 条"不可复现"不计入上面的分母（它们是缺输入/缺授权，不是一条待跑的命令）。


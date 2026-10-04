# 复现：构建 → 台架 → 门禁 → 上板复验

这一页只放**逐字抄自脚本自己用法头**的命令，每条后面点名它出自哪一支脚本的哪一行。
我在头里没找到的命令一律标 **`【未核实】`** 并说明找过哪里——不为凑齐四阶段补一条"看起来对"的命令。

## 0. 前置：工具怎么定位（本节不写任何一台机器的绝对路径）

| 变量 | 指哪儿 | 谁读它 | 不设会怎样（脚本自己打印的那一句） |
| --- | --- | --- | --- |
| `VP_VIVADO_BIN` | `<Vivado>/bin` | `build/sim/run_one.sh:46-47`；`build/r116_bit_cycle.sh:12`（有本机默认值但仍检查） | `REFUSE: 找不到 xvlog（当前 $V）。设 VP_VIVADO_BIN=<Vivado>/bin 再跑（report/build.md）` |
| `VP_XSDB` | `<Vitis>/bin/xsdb.bat` | `build/board_verify.sh:113-114`；`build/r116_bit_cycle.sh:13` 是 `${VP_XSDB:?需要显式给 xsdb.bat 路径（机器相关，不写死）}` | `REFUSE: 找不到 xsdb（当前 $VP_XSDB）。设 VP_XSDB=<Vitis>/bin/xsdb.bat 再跑（report/build.md）`；bit_cycle 那一支直接 `REFUSE no xsdb` |
| `VP_BIT` | 要下进 PL 的那块位流 | `build/r116_bit_cycle.sh:29`（给定位流路径时用它包 `VP_BIT` 调 `build/tcl/program_pl.tcl`） | 不设就用 `build/system.bit`（同支脚本头第 5 行） |

**仓库根不用设**：`sim/*.sh` 与 `build/*.sh` 按自己所在位置往回算根
（实现就是 `build/sim/run_one.sh:48` 那行 `ROOT="$(cd "$(dirname "$0")/.." && pwd)"`），
`build/tcl/*.tcl` 用 `[file dirname [info script]] .. ..`（`build/tcl/build_system_axigpio.tcl:2`）。
`report/build.md` §1 把这条做成了可跑的对照：拿一个不存在的 `VP_VIVADO_BIN` 去跑
`bash build/roll_isolated.sh`，拒绝发生在 `mkdir`/`sed` **之前**，`rc=2`。
⚠ `VP_XSDB` 要**显式赋值**（别把 `export` 关进子 shell），否则 `board_verify.sh` 一进来就 REFUSE
一步不走——`report/log/issues.md` #317 记的正是这个形状。

---

## 阶段 1 构建

**用法头里唯一一条由这支脚本自己写出的调用形式**（`build/tcl/build_system_axigpio.tcl:247` 逐字）：

```
vivado -mode batch -source 本脚本 -tclargs bd_only
```

"本脚本"就是 `build/tcl/build_system_axigpio.tcl`；这一条**只建 BD 就退出**，
注释给的理由是"BD 配置写错（IP 的参数名、引脚名、MIO 认领）本来 3 分钟就能验出来，不必等 20 分钟的综合+实现"。

**完整构建（综合 + 实现 + `build/system.bit` + `build/system.xsa` + 那几份报告）的调用形式：`【未核实】`。**
找过哪里：这支脚本的第 1–7 行（头里只有一句 `# System with AXI GPIO on GP0 + PL ETH video sink`）、
全文 `grep -n "usage|用法|-mode batch"`（只命中第 247 行那一处）、没有任何 `puts "用法…"` 行。
同一支入口在**文档**里有记录（不满足本章"逐字抄自脚本用法头"，所以只指路不照抄）：
`report/build.md` §2、`build/tcl/README.md` §1。后者还钉了一句要一起读的警告——
"要构建只认 `build_system_axigpio.tcl`；跑完必须自己去 `build/` 里核对报告的时间戳，
**不要相信退出码**"（同节点名两支历史脚本 `add_files` 指错路径、报错之后仍 exit 0）。

构建侧可选变量（逐个出自脚本自己的 `::env(...)` 读取处）：`VP_R116_IO_WINDOW`（`:45`，
设 `1` 才加载 RGMII 收口那把输入窗，候选件 `src/constraints/r116_rgmii_input_window.xdc`）、
`IMPL_STRATEGY`（`:280-282`）、`IMPL_POST_PLACE_HOOK`（`:291-296`，r117 那把复制钩子的入口）、
`IMPL_PRPO`（`:304`）。**四个都不设**就是本轮出货那条路径
（`report/timing/round_r118.md` §二 B2 判的就是"构建日志里没有 `R117HOOK`"）。

**跑完应看到**（token 全是这支脚本自己的 `puts`）：`BD_ONLY_DONE`、`WRAPPER: …`、
`TOP: system_top.v (maintained, includes PL ETH)`、`BUILD_STRATEGY …`、`BUILD_POST_PLACE_HOOK none`、
`BUILD_PRPO off`、`WIDTH_WARNINGS count=0 -> …`、`MULTI_DRIVEN count=0 -> …`、`BIT: …`、`XSA: …`、
末行 `SYSTEM BUILD DONE`；不设窗时还有一句
`VP_R116_IO_WINDOW off（RGMII 输入窗留在候选件 …原因见上方注释）`。
**不该看到**：`PORT_LOOKUP_FAILED`、`ADDRESS PINNING FAILED`、`SYNTH FAILED`、
`BUILD_STRATEGY_REJECTED`、`BUILD_HOOK_REJECTED`、`BUILD_PRPO_REJECTED`。
`build/ps_app.elf` 的重编（`build/tcl/README.md` §1 末提到的那一步）**不在本章四阶段里**：
r118 没重编应用，门禁身份行就是证据——`build/r118_gates_final.txt` 的 `ps_app.elf md5=d0b07f84a068`
与上一版同一枚。

## 阶段 2 台架

**用法头逐字**（`build/sim/run_one.sh:2`，原文）：

```
run_one.sh <tb_name>
```

`sim/` 下 `tb_*.v` 共 81 支（本次 `ls sim/tb_*.v | wc -l` 数出）。另有一条**离线判读入口**，
用法头逐字（`build/sim/run_one.sh:11`）：

```
--verdict <tb> <run.log>
```

注释写着它"只解析判定，不起仿真、不碰 xsim"，所以尺子自己的对照实验能喂合成日志跑。

**门禁第 15 项要的那份整屏报告**，两条命令都在脚本里印着：`build/gates.sh:363` 打印的生成提示逐字是
`bash build/sim/run_one.sh tb_v98_top_seam … && bash build/tb98_report.sh`
（`…` 处是那句"退出码 3 = 台架判红，1 = 编译失败，4 = 认不出判定"的括号注）；
`build/tb98_report.sh:4` 的用法头逐字是

```
bash build/tb98_report.sh [那份 run.log]
```

**全量回归入口 `build/sim/run_sim.tcl` 的调用形式：`【未核实】`。** 找过哪里：`build/sim/run_one.sh:2` 只说它的存在
（"绕开全量 run_sim.tcl 的两分钟编译"）而没有给调用串；`build_system_axigpio.tcl`、`build/gates.sh`、
`build/board_verify.sh`、`build/r116_bit_cycle.sh` 四支的头里也都没有它；
`report/build.md` §2 有那两行，但那是文档不是脚本用法头。

**跑完应看到**：`RESULT <tb> PASS`，或本轮那一份的
`RESULT tb_v98_top_seam FAIL nfail=1`（这一条是**声明过**的红 `C5c`，读法见 `report/06-validation.md` §2）；
每支末尾由 `build/sim/run_one.sh` 自己补的统一收尾行 `VERDICT <tb>: … || FAIL 行数=N || PASS 行数=M`；
退出码 **0 绿 / 1 编译或例化失败 / 2 REFUSE / 3 判红 / 4 认不出判定**（`:117` 那行给的表）。
**不该看到**：`REFUSE: 已经有 xsim 在跑（它会把行写进同一份 run.log）`（`:58`）——这台机器上同时
只能有一个 xsim 在写那个目录，脚本**拒绝启动而不自动杀**（注释写了为什么）；`XVLOG FAILED`、
`XELAB FAILED`、`VERDICT <tb>: NO-VERDICT-LINE`（"没数"不是"过了"）。留档件 `build/tb_v98_report.txt`
头部那行 `# provenance fpver=norm1 top_md5=… tb_md5=… rtl_md5=…` 就是门禁用来判
"这份报告与当前这份顶层是同一次跑"的凭据（机制写在 `build/sim/run_one.sh:73-95` 的注释里）。

## 阶段 3 发布门禁

**用法头逐字**（`build/gates.sh:11-12`，两条原文）：

```
bash build/gates.sh                 # 读 build/ 里当前这套报告（= 最近一次构建）
bash build/gates.sh build/frozen_r19_arb   # 读某一组成套冻结件
```

可选变量 `CDCBASE`（`:96`，默认 `build/cdc_baseline.txt`）：CDC 那条判据拿它当**配对集合**基线。

⚠ 脚本头部第 14–20 行专写了一条**自毁陷阱**：不要把它的输出直接重定向成它自己要读的那份
`build/rNN_gates.txt`——`>` 会在第一项判据跑之前就把那个文件截断，而第 18 项恰恰要拿
"盘上最新且 ALL PASS 的那一份"当基准。它给的正确姿势是两步：先重定向到临时目录里的一份、
跑完之后再 `cp` 到位（要留旧份就先留备份）。

**跑完应看到**（三种结尾逐字来自 `build/gates.sh:582-586`；`$NSAY`/`$NNA` 由脚本自己数）：

```
GATES: ALL PASS（$NSAY 项全部判定）
GATES: PARTIAL —— 判定 $NSAY 项全过，但有 $NNA 项因缺凭据未判（见上面 n/a 行），这一版不作"过门禁"
GATES: 有红项（判定 $NSAY 项）—— 不采纳，保留上一版
```

本轮那一版的实际结尾在件里：`build/r118_gates_final.txt` 末行 `GATES: 有红项（判定 24 项）—— 不采纳，
保留上一版`，倒数第二行把范围一起念出来"判定 24 项、未判 0 项"；24 项 = 23 绿 / 1 红，
唯一红是声明过的 `C5c`；两跑逐字节一致的凭据是 `build/evidence/r118_board/g2c.txt`、`g3c.txt`、
`gatesc_summary.txt`（`GATESC done id=identical green=23 red=1`）。
⚠ 采纳判据（`report/timing/round_r118.md` §二 B4：红数 == 1 且两跑一致）与脚本那句"不采纳"
是两条不同口径的句子，要一起念——理由在 `report/06-validation.md` §3。
**读不到输入时不该看成通过**，脚本自己给的四种形状：缺报告 → `FATAL 缺报告：…` 且 `exit 2`（`:31-33`）；
解析不到数字 → `FATAL 解析不到 $v —— 报告格式变了？不要拿空值当 0 判绿` 且 `exit 2`（`:161-166`，
读不到时还把候选行原样打出来）；缺凭据文件 → `say … "NOLOG" "无凭据=未验" 0`；
整套目录里缺某份报告 → `naa … 这一项没门禁`，于是结尾只能是 `GATES: PARTIAL`。

## 阶段 4 上板复验

**用法头逐字**（`build/r116_bit_cycle.sh:4`，原文）：

```
bash build/r116_bit_cycle.sh <标签> [位流路径]
```

同支头第 5 行："不给位流就是 `build/system.bit`（当前出货那份）"。它做的是"刷某一份位流 +
推 50 秒真实流量 + 读硬件健康计数（A/B 对照用）"，头部还写死了两条理由：为什么要先系统复位
（`#315`：app 在跑的时候重刷 PL 会把控制台弄哑）、为什么必须带流读数
（`#316`：`drop_words=0` 在 `eth_live=0` 时是零样本通过，不算测过）。

**跑完应看到**（token 全来自这支脚本的 `say` 行，件 `build/evidence/r118_board/bitcycle_console.txt`）：
`recover rc=0`、`boot rc=0`、`pl rc=0 PROGRAMMED=2`、`app rc=0 FLOW_DONE=1`、`读 A rc=0`、`读 B rc=0`、
摘要行 `a: eth_live=1 owner_eth=1 drop_words=0 pkt_err=? frames_bad=? drop_seen=?`（b 行同）、末行 `done`。
摘要里那三个 `?` 是**没读出来的字段**、不是 0（`report/log/issues.md` #318 把读不出来的字段显式化成 `?`）。
`DDR_ECHO:` 那一支：脚本判的是 `grep -q 5A5AA5A5`（`:27`），没过就打 `REFUSE DDR_ECHO 没过`；
它等的正是 `ps_jtag_boot.tcl` 打印的 `DDR_ECHO: 10000000: 5A5AA5A5`
（两处实例：`build/evidence/r118_eyes/step1_boot.txt` 与 `board/acceptance.md` 机器判据表第 1 行）。
其它失败形状：`REFUSE no xsdb`（`:20`）、`REFUSE 没烧进去`（`:32`）。

**推流那一串**（同一支脚本**体内**第 37–38 行，逐字，不在头里）：

```
python src/host/video_sender.py --demo --seconds 50 --fps 60 --pace-mbps 0 --no-ping
```

`src/host/video_sender.py` 的 **`--help` 全文输出：`【未核实】`。** 找过哪里：
`report/host_guide.md` §2 那张表（第 32 行只描述 `--demo` / `--input` / `--fps` / `--pace-mbps` 的语义）、
同文第 48 行的参数表**明写**"下表是 `video_sender.mjs` 的；`udp_push.py` 的参数用 `--help` 看"、
根目录 `send_demo.bat`（它只跑 `python src\host\video_sender.py --demo`，自己打的是
`[DEMO] ping board 192.168.1.10 then push built-in test pattern for 12 s`）。
上面那一串里每个参数名都能在 `src/host/video_sender.py` 的 argparse 段（`:42-52`）逐条对上，
所以这一串是可跑的；缺的只是"整份 help 文本"这个凭据。

**板级机器判据**——用法头那六行，**命令部分逐字**（每行 `#` 后面的注释有删节，全文以
`build/board_verify.sh:4-16` 为准；另外头里那条 `--battery` 写的是"97 条 = V8 的 71 + V9 的 20 + #77 的 6"，
而本轮件里它自己打的是 `105 条命令`——两处不同时刻，念的时候带上各自那份件）：

```
bash build/board_verify.sh              # 只跑不需要推流的那几项（读回口 + 开机自检）
bash build/board_verify.sh --stream     # 再加：推流 → 仲裁交接 → 停流交回（要 ~2 min）
bash build/board_verify.sh --battery    # 再加：串口命令电池（会改板上控制字并复原）
bash build/board_verify.sh --geom       # 再加：V9 几何自动化的"最后一跳"（lane23 + CFG_DATA0）
bash build/board_verify.sh --round=r104  # 必给：…没有轮号就**判红而不写文件**
bash build/board_verify.sh --self        # 只跑判据自己的五条对照（不碰串口、不需要板子）
```

本轮 r118 用的组合是 `--geom --battery --round=r118`
（`report/timing/round_r118.md` §二"采纳"那一行）。可选变量 `TEMP_FLOOR`（`:42`，默认 2）是 `[TEMP]` 行数地板。

**跑完应看到**（件 `build/evidence/r118_board/board_verify_console.txt` 原文）：
`RESULT PASS geom_check（ok=10 fail=0）`、
`RESULT PASS uart_cmd_check  (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`、
`[SERIAL] 落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）`、
`ok   V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`，末行
`RESULT board_verify PASS（判红的步骤：0）`；红那一支是
`RESULT board_verify FAIL nred=$NRED ⇒ 这一版不能采纳`（`:265`）。
两条必须一起读的形状：① 这支脚本**不刷板子**（头里"不做什么"那一节明写，下载顺序它指给
`report/build.md` §3），刷板是上面那支 bit_cycle 或人来做；
② 它自己打的 `drop_words → 0` 那一次 `eth_live` 是 `0`（件里 lane30 那行写着 `"why":"没有流"`），
所以那一条**不算带流已验**——带流那一读在上面那支脚本的摘要里。

**手工三步 JTAG 的调用形态：`【未核实】`。** 找过哪里：`build/board_verify.sh` 的用法头
（它只指路"三件套（bit/xsa/elf）的下载顺序见 README.md 的'复现三步'第 3 步与 `report/build.md` §3"）、
`build/r116_bit_cycle.sh` 的用法头（头里只有 `<标签> [位流路径]`；三步
`build/tcl/ps_jtag_boot.tcl` → `build/tcl/program_pl.tcl` → `build/tcl/ps_app_reload.tcl`
写在它的**体内** `:22-34`）、以及 `board/acceptance.md` E6 的前置那一格（点名三步与"全程不碰
KEY1/KEY2"，但没有命令行）。⇒ 照本页跑阶段 4 就用
`bash build/r116_bit_cycle.sh <标签> [位流路径]`，它自己会把三步跑掉；要单独手工重跑某一步，
本章不补一条我没找到出处的命令。

**眼睛那一半不是命令。** `board/acceptance.md` E1–E6 给的是判法与条件；2026-10-04 在 r118 上
由队员点头的是 E4（「现在屏幕没问题了四角都在屏幕内」）与 E6（「0度」，件 `build/evidence/r118_eyes/`），
E6 的对照那一半登记为**未判**。屏幕读数不属于机器判据，也不进门禁。

---

## 出处一览与三条实测坑

| 阶段 | 命令（逐字） | 出处（用法头行） | 关键 token |
| --- | --- | --- | --- |
| 1 只建 BD | `vivado -mode batch -source 本脚本 -tclargs bd_only` | `build/tcl/build_system_axigpio.tcl:247` | `BD_ONLY_DONE` |
| 1 完整构建 | `【未核实】`（文档记录：`report/build.md` §2、`build/tcl/README.md` §1） | 头里没有 | `SYSTEM BUILD DONE` / `BIT:` / `XSA:` / `WIDTH_WARNINGS count=` |
| 2 台架 | `run_one.sh <tb_name>`；`--verdict <tb> <run.log>` | `build/sim/run_one.sh:2`、`:11` | `RESULT <tb> PASS/FAIL`、`VERDICT …`、rc 0/1/2/3/4 |
| 2 整屏留档 | `bash build/tb98_report.sh [那份 run.log]` | `build/tb98_report.sh:4`（调用串亦见 `build/gates.sh:363` 的生成提示） | `# provenance fpver=norm1 top_md5=…` |
| 3 门禁 | `bash build/gates.sh`；`bash build/gates.sh build/frozen_r19_arb` | `build/gates.sh:11-12` | `GATES:` 三态 |
| 4 刷板 + 带流 | `bash build/r116_bit_cycle.sh <标签> [位流路径]` | `build/r116_bit_cycle.sh:4` | `5A5AA5A5`（`DDR_ECHO`）、`PROGRAMMED=`、`FLOW_DONE=`、`done` |
| 4 板级机器判据 | `bash build/board_verify.sh --round=rNN`（`--stream`/`--battery`/`--geom`/`--self`） | `build/board_verify.sh:4-16` | `RESULT PASS geom_check`、`RESULT PASS uart_cmd_check`、`RESULT board_verify PASS（判红的步骤：0）` |

三条会让复现"看起来失败"的实测坑（都在件里有账）：
① 第一次连不上板先看 `hw_server`——`board/acceptance.md` r96 那一节第 1 行写着
"`CONNECT:` 空 ⇒ 本机没有 hw_server 在听 3121，起了 `Vitis/bin/hw_server.bat` 之后拿到 `tcfchan#0`"，
并把"复现时这一条要先做"钉在表里；② 刚断电重上电时链子可能还没重枚举 ⇒ 第一步死在 `targets -set 1`，
`build/r116_bit_cycle.sh` 会打 `REFUSE DDR_ECHO 没过`（现场记录与恢复过程在
`build/evidence/r118_eyes/state.txt` 末段那三行注释）；③ 门禁的输出别重定向回它自己要读的那份
`rNN_gates.txt`（阶段 3 的 ⚠）。

## 本章依据的产物
- 五支脚本的用法头与被引行：`build/tcl/build_system_axigpio.tcl`（`:1-7`、`:2`、`:45`、`:247`、
  `:280-296`、`:304`、末尾 `puts` 群）、`build/sim/run_one.sh`（`:2`、`:11-12`、`:46-48`、`:58`、`:73-95`、`:117`）、
  `build/gates.sh`（`:11-12`、`:14-20`、`:31-33`、`:96`、`:161-166`、`:175-183`、`:363`、`:582-586`）、
  `build/board_verify.sh`（`:4-16`、`:21-25`、`:42`、`:113-114`、`:263-265`）、
  `build/r116_bit_cycle.sh`（`:4-9`、`:12-13`、`:20`、`:22-34`、`:27`、`:29`、`:32`、`:37-38`）、
  以及 `build/tb98_report.sh:4`
- 件：`build/r118_gates_final.txt`、`build/evidence/r118_board/`（`g2c.txt`、`g3c.txt`、
  `gatesc_summary.txt`、`board_verify_console.txt`、`bitcycle_console.txt`、`board_now.txt`）、
  `build/evidence/r118_eyes/`（`state.txt`、`step1_boot.txt`、`step2_program_pl.txt`、`step3_app.txt`）、
  `build/tb_v98_report.txt`
- 其它：`report/build.md` §1/§2/§3、`build/tcl/README.md` §1/§2、`report/host_guide.md` §2 与第 48 行、
  `board/acceptance.md`（机器判据表第 1 行、r96 那节、E4/E6 与 E6 前置）、`report/timing/round_r118.md` §二、
  `report/log/issues.md` #315/#316/#317/#318、`src/host/video_sender.py`、`send_demo.bat`、
  `src/constraints/r116_rgmii_input_window.xdc`

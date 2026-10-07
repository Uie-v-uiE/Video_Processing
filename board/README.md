# `board/` —— 上板工程 · 运行脚本 · 实测输出

三块分别是下面第 1、2、3 节。所有命令都在**仓库根**执行；本目录的脚本一律用环境变量接工具，文件里没有写死的机器路径。

## 0. 先认版本：板上这一版是哪一版

| 件 | md5 前 12 位 | 在仓库哪里 |
|---|---|---|
| `build/system.bit` | `cd04907e1369` | 跟踪件（`git ls-files build/system.bit` 有输出） |
| `build/system.xsa` | `934ebdbaa13b` | 跟踪件 |
| `build/ps_app.elf` | `57fa442a7eaf` | 跟踪件 |

这三份二进制在 `build/`、**不在这里**：`board/` 放的是工程文本、脚本与读数。
上表是 2026-10-06 19:36 用 `md5sum build/system.bit build/system.xsa build/ps_app.elf` 现量的，同一组数也印在 `board/measured/flash_20261006_1936.txt` 的 IDENTITY 段。

有一处不吻合要提前知道：`build/gen_bit.tcl:12` 的归档目录默认值就是 `board/`，`:25-26` 会往那里写 `system.xsa` 与 `system.bit`。照默认跑一次 `vivado -mode batch -source build/gen_bit.tcl`，
本目录会长出两份**未跟踪**的二进制（`.gitignore` 不挡它们）。用 `VP_BIT_DIR=build` 跑，或者跑完删掉—— 入库的那两份始终以 `build/` 为准。

重编出来的 ELF 是另一颗，它没上过板；两颗的 md5 与 `.text`/`.rodata` 大小记在 `build/evidence/1005_ps_app_rebuild.txt`。 2026-10-06 把 PS 应用重链到 DDR 之后重编的那颗（md5 `57fa442a7eaf`）就是现在板上跑的这颗，10-05 那颗没上过板、已被它取代；要用自己重编的件，就得重刷 + 跑一次第 2 节末尾那条 `board_verify`。

## 1. 上板工程

| 打开什么 | 里面是什么 | 字节 |
|---|---|---:|
| `board/zynq_video_sys.xpr` | Vivado 工程：器件 `xc7z020clg484-2`、源码清单、约束、BD 单元格、run 外壳 | 50 917 |
| `board/zynq_video_sys.srcs/` | 10 份工程源件：`design_1.bd`（块设计）+ `design_1.bda` + 8 份 IP `.xci` | 643 529 |
| `board/vitis_platform/vitis-comp.json` | Vitis 平台描述：两个 domain（`zynq_fsbl` / `standalone_ps7_cortexa9_0`）、两颗 `ps7_cortexa9`、OS 清单、`flow=EMBEDDED` | 2 087 |
| `board/vitis_platform/resources/` | 3 份 `qemu_args.txt`（顶层一份、两个 domain 各一份） | 4 633 |

**这四份的形状是两支脚本复制并当场验证出来的**，逐条 `VERIFY` 输出在 `board/measured/stage_2026-10-05.txt`：

```bash
vivado -mode batch -nojournal -log board/flash/stage.log -source board/tcl/stage_board_projects.tcl
PS_CC=<…>/arm-none-eabi-gcc.exe bash board/scripts/stage_vitis_platform.sh
```

| 这支验什么 | 打印出来的判据 | 本机前置 |
|---|---|---|
| `stage_board_projects.tcl` | 器件 `xc7z020clg484-2`、14 条 run、86 份源件 + 2 份约束、`missing_files=0 of 88`；关掉工程后把 Vivado 写回的工程头 `Path="…"` 改回仓库相对名，再数还有几行带盘符（实量 0），删掉打开时长出的 `*.cache`、`*.hw` | `vivado_system/` 已建好 |
| `stage_vitis_platform.sh` | 找得到副本里的 BSP、`hw/system.xsa` 与 `fsbl.elf` 在，判据是**链得出非空 ELF**（不是"md5 等于仓库那颗"，原因见上面那句重建件），跑完把 16 MB 平台正文删回入库那 4 份文本件 | 仓库根 `vitis/platform` 带 BSP（2026-10-07 起随仓库交付；重建路见下面那段） |

**`.xpr` 里 81 处引用写成 `$PPRDIR/../src/...`，所以这份工程只能放在 `board/` 这一层。** 往深里挪一级，`src/rtl` 与 `src/constraints` 就全部指不回来。
**工程本体自 2026-10-07 起随仓库交付**：仓库根的 `vivado_system/` 是这份工程的一份**能直接打开的快照**（`.xpr` + `.srcs` + `.gen/` 的 output products + `.runs/` 含 `system_top_routed.dcp`，`du -sh` 实量 86 M），`vitis/` 是配套的 Vitis 平台（53 M）；这两棵一起 `git add` 清点出 2473 支新跟踪文件。这三棵生成树的体积与支数在 2026-10-05 10:40 量过一次：`.gen` 36 M / 133 支、`.runs` 52 M / 222 支、`.cache` 3.1 M / 34 支，合计 389 支，而且 `.runs` 随构建进度会长，是个动目标。现在前两棵入库，`.cache` 与 `*.ip_user_files/`、`.Xil/`、`*.jou`、`*.log`、`*.str` 这些重跑就长回来的噪声仍不入库。`.xpr` 里另有 12 处 `$PGENDIR/...`——包括提交包里这两棵带的是**整棵副本**，位置在包内板级目录下的同名两子里；包里的活文档指路已由导出器改成包内那一层，但 `board/scripts/` 与 `build/` 里的**脚本正文**写的仍是仓库布局的位置，在包里照着脚本跑要先把这两棵的名字前面加上一层板级目录。
`sources_1/bd/design_1/hdl/design_1_wrapper.v` 和 6 个 BD IP 的 OOC 目录，都在这一类里——指的就是 `.gen/` 这一层，所以 clone 之后不必先跑构建；换 Vivado 小版本或 `.gen` 与 `.xpr` 对不上时，以下面这条 Tcl 重建为准。

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl      # 工程 + BD + 综合 + 实现 + bit + XSA + 7 份报告
vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only   # 只建到 BD 就退（第 278 行打 BD_ONLY_DONE）
```

这一支第 21 行就是 `create_project $proj_name $proj_dir -part $part -force`、第 84 行 `create_bd_design design_1`，头注释点名它一路出到 `system.bit / system.xsa` 与 7 份报告（`timing_summary utilization cdc methodology power
route_status clock_util`）：上面那 11 份工程文本本来就是从它长出来的，收进来只为让人不必先跑完一整条构建流程 才能看见块设计与 IP 配置。它把工程建在 `vivado_system/`，与本目录这两份是同一形状
（`.gitignore` 末尾那一段自 2026-10-07 起改成"工程入库、只挡噪声"；早先它是整目录挡掉 `vivado_system/`、任意层级的 `vivado/` 与 `VITIS/` —— 后者在 Windows 上连 `vitis/` 一起挡，所以父目录被排除时里面的文件放不回来，这也是本目录那两个副本当年**不叫** `vivado/` 与 `vitis/` 的原因）。
`.xci` 里带着生它的那台机器的 IP `PROJECT_ID` 与 Vivado 小版本，换小版本会要 `upgrade_ip`。

重编 PS 应用。编译器在 Vitis 安装树里、只是不在 PATH 上（本会话实核：`which arm-none-eabi-gcc` 无命中，而 `<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe --version` 回
`arm-xilinx-eabi-gcc.exe (GCC) 13.3.0`），所以下面两个变量都得给全路径：

```bash
PS_CC=<…>/arm-none-eabi-gcc.exe PS_BSP=<仓库根>/vitis/platform/ps7_cortexa9_0/standalone_ps7_cortexa9_0/bsp \
node build/ps_app.mjs                                             # 产物：build/ps_app.elf
```

那个 BSP（16 MB / 983 支）现在随 `vitis/` 一起入库，clone 之后 `PS_BSP` 直接指得到；只有手上没有这份平台时才做一次手工 New Platform：
Vitis → New → Platform → 选 `build/system.xsa` → BSP 勾 `uartps` / `xsdps` / `xgpiops` → Generate，把生成出来的 `standalone_ps7_cortexa9_0/bsp` 指给 `PS_BSP`（这段说明的原件在 `build/ps_app.mjs:14-17`）。
`board/vitis_platform/vitis-comp.json` 里 `configuration.xsa` 那一个字段被从本机的绝对路径改写成仓库相对的 `build/system.xsa`，其余逐字照抄平台上那份。

## 2. 运行脚本

### 2.1 一把跑的（`board/scripts/` 与 `board/tcl/`）

| 命令 | 做什么 | 动板子吗 |
|---|---|---|
| `VP_XSDB=<…>/xsdb.bat VP_VIVADO_BIN=<…>/bin bash board/scripts/board_flash.sh` | 按顺序跑 起 PS → 配 PL → 下应用，末尾回读一次 AXI GPIO 证明位流真的上了 | **会**：第 1 步就是 `rst -system`，会冲掉在板的位流 |
| 同上，末尾加 `--check` | 只做前置检查与只读扫链：工具在不在、三件套的 md5、JTAG 链上看得见的目标 | 不会 |
| `VP_XSDB=<…>/xsdb.bat bash board/scripts/board_health.sh` | 只读拍一张健康快照：串口 `stat,temp,stat` → `mrd` GPIO 与 DDR 头 8 字 → 三条异常向量，四件判完落一份件 | 不会 |
| `bash board/scripts/make_boot_image.sh` | 把 FSBL + 位流 + 应用打成 `board/flash/BOOT.bin`（生成件，不入库，跑一次就有），并打印四件 md5（bootgen 的 `.bif` 只认"一行一个文件、不带逗号不带属性"） | 不会 |
| `VP_HW_URL=<host:port> vivado -mode batch -source board/tcl/flash_qspi.tcl` | `create_hw_cfgmem` → `program_hw_cfgmem` 把 `BOOT.bin` 写进板载 W25Q256，`PROGRAM.VERIFY` 是硬件回读比对；`VP_QSPI_PART` 选 flash 型号（默认按 `get_cfgmem_parts` 的 `COMPATIBLE_PARTS`），`VP_FLASH_OFFSET` 选起始地址，那一次写入的读数在 `board/measured/flash_qspi_2026-10-05.txt` | **会**：擦写 flash |
| `vivado -mode batch -source board/tcl/stage_board_projects.tcl`、`PS_CC=<…> bash board/scripts/stage_vitis_platform.sh` | 第 1 节那两支：复制上板工程并当场验证打得开、链得出 | 不会 |

前两支（`board_flash.sh` / `board_health.sh`）都把同一份内容打成 stdout、并落成 `board/measured/<名字>_<YYYYMMDD_HHMM>.txt`，件的第一段就是跑动那一刻的 IDENTITY（时间、git HEAD、三件套 md5），末行是 `FLASH:` / `HEALTH:` 的
GREEN/RED 总判定；判红会点名是哪一步、哪一项，不会安静地少跑一段。 `VP_XSDB` 不给或指不到就 `REFUSE` 并退 2（口径抄自 `build/board_verify.sh:118`）。

### 2.2 单步工具（留在 `board/` 这一层，名字外面在指）

| 文件 | 什么时候用它 | 外面谁按这个名字指它 |
|---|---|---|
| `boot27c.tcl` | 想一次把 PS 和应用拉起来、不介意重刷位流：`rst -system` → `ps7_init` → `dow build/ps_app.elf` → `con`，PC 在下前后都打 | `build/tcl/ps_app_reload.tcl` 的文件头用它解释"为什么换应用不该走这条" |
| `pswhy.tcl` | 板子没反应时先读 `pc/lr/sp/cpsr` 与 `0x11488/0x1148c/0x11490` 三条异常向量，别猜 | `board/scripts/board_health.sh` |
| `rdbck.tcl` | 读回 AXI GPIO_0（`0x41200000`）那一个字，确认控制字落板了 | `board/scripts/board_flash.sh`；`build/make_submission.sh:87` |
| `rdddr.tcl` | 同时读 GPIO 一个字与 DDR 头 8 个字，分开"控制字没写进去"与"数据没落内存" | `board/scripts/board_health.sh` |
| `serial_bytes.ps1` | 串口按字节抓，绕开编码猜测 | `.gitignore:148` 明写它的输出不入库 |
| `uart_cap_once.ps1` | 串口一发一收：`-Port COM6 -Seconds 8 -Drain -Cmds "stat,temp,stat"` | `build/board_verify.sh:154,172`、`src/host/arb_handover_test.mjs`、`build/tcl/ps_app_reload.tcl` |
| `uart_cmd_script.ps1` | 把一份清单逐条灌进 COM6 并分段收回显（`-Cmds` 会按空格拆词，带参数的命令必须走这支） | `src/host/uart_cmd_check.mjs:35`、`src/host/geom_check.mjs:45`、`build/tcl/r116_jtag_recover.tcl` |
| `cmd_battery_v81.txt` | 105 条串口命令的清单本体（改过的一律在结尾改回来） | `src/host/uart_cmd_check.mjs:37` 的默认输入 |
| `cmd_overflow_probe.sh` | 串口命令缓冲越界一字节的两端夹逼探针（O1/O2 两个夹逼位）；它只夹逼、不修复 | `src/ps/main.c:1492` 那句"板级指纹见 … 的 O1/O2"、`report/60-failure-analysis.md:97` |
| `ddr_churn_probe.mjs` | 读 DDR 翻帧：`VP_XSDB=<…>/xsdb.bat node board/ddr_churn_probe.mjs` | `build/make_submission.sh`、`report/` 若干处 |
| `demo_rehearsal.txt` | 演示时照着敲进板子的那一份，从 `report/demo_script.md` 抽出来 | `build/gates.sh:484` 拿它比对讲稿、`src/host/demo_cmds.mjs:42` 是它的默认落点 |

### 2.3 上板之后一把验收（机器能判的那一半）

```bash
VP_XSDB=<…>/xsdb.bat bash build/board_verify.sh --battery --geom --round=r118
```

开机回读 → 读回口 → 105 条串口命令电池 → 几何"最后一跳"，日志留 `build/evidence/`，末行形如 `RESULT board_verify PASS（判红的步骤：0）`。`--round=` 必须给：
没有版本身份的一手回显会被判红而不是写成一份名字叫旧轮的凭据（`build/board_verify.sh` 头部 #179）。 `--stream`（仲裁交接，约 2 分钟）与 `--self`（只测判据本身、不碰板子）两个开关见同一文件头。

两条使用注意点：**COM6 一次只能被一个程序占着**（自己开着终端时脚本会拒绝，不是板子坏了）；**要看寄存器就先停止推流**，流在跑时读到的计数是中间值。

## 3. 实测输出

| 件 / 目录 | 是什么 | 怎么复跑 |
|---|---|---|
| `board/measured/`（10 份 / 38 870 B，本次逐份 `wc -c` 现量） | 第 1、2 节这几支在本目录实跑的落点：`flash_20261005_1026.txt`（`--check`，GREEN）、`flash_20261005_1030.txt`（三步全跑，GREEN）、`flash_20261006_1936.txt`（r125 那一次的三步全跑，首页 IDENTITY 那组三件套 md5 就印在它的第一段）、`health_20261005_1025.txt`（HEALTH: RED，红在最后一判）、`health_20261005_1031.txt`（HEALTH: GREEN）、`flash_qspi_2026-10-05.txt`（写进板载 QSPI 那一次：Erase/Program/Verify 三段成功、137 s、当时踩的三个坑）、`qspi_vendor_control_2026-10-06.txt`（**写入自己的镜像之前的对照**：出厂那版镜像在同一块 flash 上起到 `U-Boot 2023.01`，⇒ 这颗板子本来就从 QSPI 起得来）、`qspi_coldboot_2026-10-06_fsbl_from_flash.txt`（镜像头没带 bootloader 标记那一次：`Boot mode is QSPI`→`QSPI is in 4-bit mode`→`DMA Done !`→`FPGA Done !` 都有，但没有 `SUCCESSFUL_HANDOFF` ⇒ 位流从 flash 起来了、应用没交接）、`qspi_coldboot_selfboot_ok_2026-10-06.txt`（修好头部之后：同一串之后接着 `SUCCESSFUL_HANDOFF` 与两条 `[CFG]` ⇒ 断电自启整条成立）、`stage_2026-10-05.txt`（第 1 节两支的 `VERIFY` 输出，逐字照抄） | 就是那几支脚本；`health_20261005_1025.txt` 留着，它是 `pub=` 那个活位会把判据弄红这条修正的现场凭据。断电自启那两份的结论列在技术文档"位流（PL 配置）"那一节（成立与不成立各一份，两份都在包里）。工程字节数不是常量——`.xpr` 每被打开一次 Vivado 就重写它，第 1 节那一格（50 917）记的是这一跑之后的数 |
| `board/evidence_r29/`（17 份 / 14 694 B） | r29 那天的**串口原始抓包** 16 份：SD 挂载、播放速率、拔卡与拔线时的仲裁交接 | `board/uart_cap_once.ps1`；哪一份支撑哪条结论写在同目录 `README.md` 里 |
| `board/evidence_r41/`（14 份 / 48 690 B） | 七个场景各一对 json+md：`clean30` `drop200` `drop2000` `nopause60` `nopause120` `soak300` `soak300b` | `node src/host/metrics.mjs --out board/evidence_r41 --tag r41_<场景>`（默认输出目录名就是 `src/host/metrics.mjs:164` 那个形状） |
| `board/compare/`（13 份 / 22 925 B，本次 `wc -c` 逐份现量） | 判据复核的输出：温度公式、指标重算、名册差分、DDR 陈旧字 | 12 份件的头两行是 `# CMD:` 与 `# RUN_AT:`。本次逐份实核过：**7 份**那一行就是能直接跑的命令、点名的脚本在树里（`src/host/ddr_stale.mjs` 两份、`src/host/metric_recheck.mjs`、`src/host/temp_formula_check.mjs`、`build/r115_roster_build.py` 三份）；**2 份**（`cdc-golden_compare-console.txt`、`roster-golden_compare-crosscheck.txt`）那两行照抄的是当时那把参考图比对器在自己机器上的落点，而那把尺子已经不在仓里（`git ls-files \| grep golden_compare` 只回到这两份捕获自己）⇒ 这两判要复跑得先把尺子补回来，比对读数本身仍以 `board/compare/` 这 13 份件为准；**3 份**（`golden-digest-verify.txt`、`soak300-lane-delta.txt`、`tb98-count-vs-metrics-claim.txt`）那一行是"这个数怎么现算"的说法、不是整条命令，其中 `soak300-lane-delta.txt` 把脚本正文原样附在自己的件尾。第 13 份 `cdc-golden_diff.csv` 是差分辨识表，本来就没有 `# CMD:` 行 |
| `board/verify_r87.md` | r87 那一版的全功能上板验收单：每条给命令、该看见什么、看不见意味着什么 | `data/metrics.csv` 有 5 行的证据列指它，所以这个名字不能改 |
| `build/evidence/r128_serial_raw.txt`、`build/evidence/verify_1007_1421.txt`（同族另有 5 份：`.boot.txt` / `.geom.txt` / `.batt.txt` / `.health.json` / `.serial.raw`） | 2026-10-07 14:21 那一跑的机器判定与**原始串口回显**（不靠手抄）：`RESULT PASS geom_check（ok=10 fail=0）`、`RESULT PASS uart_cmd_check (105 条命令, 97.2 s)`、`RESULT board_verify PASS（判红的步骤：0）`；开头三行是当时板上那三件的 md5 与时间（`cd04907e…` / `934ebdba…` / `57fa442a…`），与第 0 节那一格逐个字符相同 | `VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --geom --battery --round=rNN`。`--round` 必须给：没给轮号时脚本**不写**那份原始回显并判红（`build/board_verify.sh:178`），因为一份没有版本身份的读数第二天就会被念成旧轮的凭据 |

`health_20261005_1025.txt` 与 `health_20261005_1031.txt` 是隔着 `flash_20261005_1030.txt` 那一次刷板、一头一尾拍的。 两边对读能确认刷完之后板子真的又跑起来了，而不是停在某个地方：`[TEMP] degC` 62.01 → 60.20（XADC 在动）、
`pswhy` 读到的 `pc` `0000f464` → `00007554`（核在 .text 里走）、AXI GPIO 控制字两边同为 `0x000F5000`。 同一条 `[STAT]` 里的 `frames=4398` 两边也同值，但**这个同值不说明冻帧**：它打的是
`src/ps/sd_play.c:811` 的 `sd_frame_total()`（`src/ps/main.c:1386` 那一行送进格式的），语义是"当前这个文件一共有多少帧"，按构造就是静态字段。要判断通路活不活，看能动的字段（`pub=`、`pc`、`degC`）。

生成的与实测的分界：**`board/measured/`、`board/evidence_r29/`、`board/evidence_r41/`、`board/compare/`、`board/verify_r87.md` 是从板子或板上读数算出来的**；`board/zynq_video_sys.*`、`board/vitis_platform/`
是 Vivado/Vitis 写出来的工程文本；`board/scripts/` 与 §2.2 那一张表是人写的脚本。
`board/uart_capture.txt` 与 `board/uart_script_capture.txt` 是本机每次跑都重写的捕获，被 `.gitignore:135-136` 挡着、不入库也不随包；要随包复核看 `build/evidence/` 里那一份。

## 4. 只能由人眼判的

机器判不了屏幕，所以这三条不预先写成通过：分割线两侧是同一条帧的两种处理状态、几何关系一致；缩放或旋转时不出现整行错位；OSD 各格读数与串口读回一致。
逐格签收状态与"谁点的头、什么时候、原话"记在 `acceptance.md` 与 `signoff.md`；接线、供电、跳线与 COM 口的实际观察在 `hardware_setup.md`；原图与金标比对那一格的状态在 `raw-vs-golden.md`。
已知未修的限制不在这里重复，看 问题清单。

## 5. 复现顺序

```
第 0 节认版本 → 1) vivado -mode batch -source build/tcl/build_system_axigpio.tcl   （或者直接开 board/zynq_video_sys.xpr）
              → 2) node build/ps_app.mjs                                          （要改 PS 侧才需要）
              → 3) bash board/scripts/board_flash.sh --check                       （只读，先确认链是活的）
              → 4) bash board/scripts/board_flash.sh                               （真的把三件套放上板，JTAG）
              → 5) bash board/scripts/board_health.sh                              （只读快照，落 board/measured/）
              → 6) VP_XSDB=<…>/xsdb.bat bash build/board_verify.sh --battery --geom --round=<这一版>
              → 7) bash board/scripts/make_boot_image.sh                           （可选：要断电自启才做）
              → 8) VP_HW_URL=<host:port> vivado -mode batch -source board/tcl/flash_qspi.tcl
                   然后把启动模式拨到 QSPI、断电重上（这一步只有人手能做）。
                   实测：拨回 QSPI 断电重上，串口依次出 `Boot mode is QSPI` → `FPGA Done !` → `SUCCESSFUL_HANDOFF` → `[CFG] … ok`，
                   SD 自动播起片、ETH 那一路也出画面 ⇒ 演示可以只靠断电上电。凭据与修法见 `report/technical-document.md` §8.3；上面 4) 的 JTAG 三步仍然可用。
```

第 1 节那两支（`stage_board_projects.tcl` / `stage_vitis_platform.sh`）不在这一列：它们不改板子，改的是 `board/` 这份工程本身。

发布前的检查不在本目录：`bash build/gates.sh`。读数以它打印的那一行为准，本页不复述任何一条门禁条数。

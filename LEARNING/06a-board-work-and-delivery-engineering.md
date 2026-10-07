# 06a 上板实操与交付工程化（06 的第一半）

> 本篇只讲两件事：**板子怎么被真实地跑起来并判过**（A 半），**交付物怎么被尺子逼着不说谎**（B 半）。
> 经验总结与数字索引在 `06b`，本篇不重复。
> 全篇不碰硬件：所有上板动作都来自 `board/` 与 `build/` 里的留档与脚本原文，没有一次现场操作。
> 每个数字后面括号里点的是**来源 `文件:行号` 或留档件**；核不到来源的句子宁可删掉不写。

---

## A. 上板实操（可照着做，全部来自留档）

### A1. 结论先说

- 上板是一条**固定顺序的三步 JTAG 链**，不是一次性动作：`ps_jtag_boot` → `program_pl` → `ps_app_reload`，顺序换了必失败（`board/scripts/board_flash.sh:18-22`）。
- 会改板上状态的只有两步：`board_flash.sh`（第 1 步就 `rst -system`）与 `flash_qspi.tcl`（擦写板载 QSPI）；其余脚本全是只读（`board/README.md:72-79`）。
- 断电自启走 QSPI，**必须人手把启动档拨到 QSPI 再断电重上**，这一步没有脚本能替（`board/README.md:147-147`）。
- 判"板子活着"用的是**只读快照** `board_health.sh`；判"这一版对"用的是 `build/board_verify.sh --battery --geom --round=<这一版>`，末行是 `RESULT board_verify PASS（判红的步骤：0）` 那种形状（`board/README.md:103-107`）。

### A2. 三步 JTAG 链：真实脚本名、执行顺序、每步产出

一把跑的外壳是 `board/scripts/board_flash.sh`，环境变量 `VP_XSDB`（`<Vitis>/bin/xsdb.bat` 绝对路径）与 `VP_VIVADO_BIN`（`<Vivado>/bin`）两个必填，脚本里**不写死任何机器路径**（`board/README.md:3`、`board/scripts/board_flash.sh:6-11`）。

| 步 | 被调的 .tcl | 用什么工具 | 做什么 | 判它成功的标记 |
|---|---|---|---|---|
| 0（只读） | `build/tcl/scan_jtag.tcl` | `vivado.bat -mode batch` | `open_hw_manager` / `connect_hw_server` / `open_hw_target` 后只打印清单，没有 `rst`/`con`/`mwr` | 链上器件行 ≥2（`arm_dap` + `xc7z020`），`board/scripts/board_flash.sh:79-87` |
| 1 | `build/tcl/ps_jtag_boot.tcl` | `xsdb -quiet` | `rst -system` + `ps7_init` + DDR 自检；**会冲掉 PL 上现有位流** | `DDR_ECHO: 10000000: 5A5AA5A5`，`board/scripts/board_flash.sh:91-92,119` |
| 2 | `build/tcl/program_pl.tcl` | `vivado.bat -mode batch`（不是 xsdb） | 把 `build/system.bit` 配进 PL | 打印 `PROGRAMMED`，`board/scripts/board_flash.sh:94-96,120` |
| 3 | `build/tcl/ps_app_reload.tcl` | `xsdb -quiet` | `rst -processor` + `dow build/ps_app.elf` + `con` | 打印 `DOW: ok`，`board/scripts/board_flash.sh:101-102,121` |
| 回读 | `board/rdbck.tcl` | `xsdb -quiet` | `mrd 0x41200000`（AXI GPIO_0）取一个控制字 | rc=0；PL 没配上时这条取不到数，所以它是"三步真落地"的最短判据，`board/scripts/board_flash.sh:104-105` |

顺序为什么不能换（`board/scripts/board_flash.sh:18-22`）：第 1 步的 `rst -system` 会把已配好的位流冲掉，所以它之后必须重下 bit；`program_pl` 之前下应用是下不进去的，因为 PL 的 AXI 从机还不存在；第 3 步只 `rst -processor`，因此"只换应用、不想重刷 PL"时单独跑那一步就够。

三条**内容**判据（`DDR_ECHO` / `PROGRAMMED` / `DOW: ok`）的口径是"每一步该留下的那行读数在不在"，而不是"有没有跑完"。这个差别是有代价换来的：`board/measured/flash_20261005_1030.txt` 那一次三步 rc 全是 0，却因为 `DDR_ECHO` 那行的**字面空格**判红——xsdb 的 `mrd` 排版在地址后是一到多个空格，判据因此改成 `[[:space:]]+`（`board/scripts/board_flash.sh:116-119`）。

实跑两遍的留档（`board/scripts/board_flash.sh:12-15`、`board/README.md:115`）：
`board/measured/flash_20261005_1026.txt` = 只加 `--check`，`FLASH: GREEN`，没有任何写动作；
`board/measured/flash_20261005_1030.txt` = 三步全跑，`FLASH: GREEN`，里面留着 `RST_SYSTEM`/`PS7_INIT`/`DDR_ECHO=5A5AA5A5`/`PROGRAMMED xc7z020_1`/`DOW: ok` 与末尾 GPIO 回读。
退出码：0 = 三步全 rc=0 且回读到 GPIO；1 = 某一步 rc 非 0（末行 `FLASH: RED` 点名第几步）；2 = `REFUSE`（`board/scripts/board_flash.sh:16`）。

`--check` 为什么是真只读：它换的是 `scan_jtag.tcl`。上一版这里指的是 `build/tcl/r116_jtag_health.tcl`——**仓库里从来没有这个文件**，xsdb 直接报 `couldn't read file`；而判据抓的两个标记其实出自 `r116_jtag_recover.tcl`，那支是**发系统复位**的：既指错文件，又把"复位"藏进了只读路径（台账 #405，`board/scripts/board_flash.sh:75-78`）。现在的规矩是：被调文件不在就 `REFUSE` 并退 2，**缺件不是红，是没量过**（`board/scripts/board_flash.sh:80-82`）。

### A3. QSPI 烧写：喂法、`PROGRAM.FILES` 的白名单、擦除前置

`board/tcl/flash_qspi.tcl` 把启动镜像写进板载 W25Q256（`create_hw_cfgmem` → `program_hw_cfgmem`），一次擦 + 写 + 回读约 3–6 分钟（`board/tcl/flash_qspi.tcl:7`），那一次的读数在 `board/measured/flash_qspi_2026-10-05.txt`：Erase/Program/Verify 三段成功、137 s、当时踩的三个坑（`board/README.md:78,115`）。

- **`PROGRAM.FILES` 只收 `.bit`/`.bin`/`.mcs`，不收 ELF**。这是实测出来的：报 44-518 `Valid file type extension .mcs or .bin`（`board/tcl/flash_qspi.tcl:84-85`）。代码里的处理是这样：先按 `switch [file extension $img]` 分流——喂 `.bit`/`.mcs`（原料）才 `lappend … PROGRAM.ZYNQ_FSBL $fsbl` 并打 `FEED_MODE 原料 ⇒ 由工具打镜像，FSBL 单独给`；其它扩展名（默认那颗 ``BOOT.bin`（产物，不入库）`）走 `default`，打 `FEED_MODE 原样写盘（$img 已是完整 BOOT.bin，含 FSBL+位流+应用）⇒ 不设 ZYNQ_FSBL`（`board/tcl/flash_qspi.tcl:95-103`）。位流与应用两颗各自做存在性检查并打成 `FEED_BIT`/`FEED_APP` 两行（`:41-49`），缺任一 `REFUSE`（`:45-47`）。
- **镜像套镜像这个坑要写死在注释里**：Vivado 的 cfgmem 与 `program_flash -fsbl` 都是"给原料、工具自己打镜像"的接口，`PROGRAM.ZYNQ_FSBL` 会把 FSBL 与启动头**包到 FILES 前面**；把已经打好的 `BOOT.bin` 当 FILES 喂进去，flash 开头的分区表就成了垃圾。证据是让 FSBL 从 JTAG 自己念（那份 QSPI 烧写期间的串口留档没随包留下）：`Boot mode is QSPI` / `FlashID=0xEF 0x40 0x19 WINBOND 256M Bits` / `QSPI is in 4-bit mode`，然后 `Partition Count: 30064771079`（= `0x700000007`，垃圾）→ `INVALID_LOAD_ADDRESS_FAIL`，`FSBL Status=0xE0000000`。最阴的地方在于：两次 program 的 `Verify Operation successful` 比的都是工具自己拼出来的东西 ⇒ 对**可启动性零证明**（`board/tcl/flash_qspi.tcl:33-40`）。
- **擦 QSPI 必须先在 JTAG 档**。脚本侧的第一道是链：`flash_qspi.tcl` 开场就要 `connect_hw_server` + `open_hw_target` 成功、且链上数得出 `xc7z020*`，否则 `REFUSE`（`open_hw_target` 那句错误消息写着"板子没上电或 JTAG 链空"，`REFUSE` 那句写着"hw_server 看到的是空链"）（`board/tcl/flash_qspi.tcl:55-63`）。这一道拦的是**链不通**；**档不对**由工具自己拦，报的是 `[Xicom 50-100]`，见 A5 那条，两件事别混着讲。
- flash 型号默认 `mx25l25645g-qspi-x4-single`，不是板子丝印那支 `w25q256jw*`：丝印是 W25Q256FV，但 Vivado 部件库里 `w25q256jw*` 的 `COMPATIBLE_PARTS` 只列 `zynquplus`，拿去配 zynq7000 会在 program 那一步报 `[Labtoolstcl 44-655]`；同为 32 MB / x4 的 macronix 档实测擦写与回读校验都过（`board/tcl/flash_qspi.tcl:22-25`，`board/measured/flash_qspi_2026-10-05.txt`）。
- 属性名要按对象**实际支持**的列表来设：2025.2.1 的 `hw_cfgmem` 没有 `PROGRAM.BBF_FILE` 与 `PROGRAM.START_ADDRESS`（写死会 17-142 中断），所以先 `list_property` 再逐个设，缺的只报 `SKIP`（`board/tcl/flash_qspi.tcl:79-82,104-111`）；成败只看 `program_hw_cfgmem` 的返回码，因为该版本 `hw_cfgmem` 没有 `STATUS` 属性（17-54）（`board/tcl/flash_qspi.tcl:114-118`）。
- 运行期标签保持 ASCII：Vivado Tcl 按系统码页读 `.tcl`，CJK 的 `puts` 会吃掉字节并把控制台变成 grep 眼里的二进制（`board/tcl/flash_qspi.tcl:17-18`）。

`BOOT.bin` 由 `board/scripts/make_boot_image.sh` 打：把 FSBL + 位流 + 应用打成一个文件并打印四件 md5；bootgen 的 `.bif` 只认"一行一个文件、不带逗号不带属性"（`board/README.md:77`）。
那一次实跑的镜像是 2 408 732 字节、md5 `2f7ee28f482d61488ced9c1413a71dfe`，FSBL 是 `0a1c57b2398029f20bc0abd2f2db4b22`，位流 `cd04907e1369da35d21c4090d552f5ee`，当时那颗 PS 应用是 `d0b07f84a0683db203086fb816ac71d7`（`board/measured/flash_qspi_2026-10-05.txt:5-9`）；
注意这颗应用与仓库现在跟踪的那颗不同：10-06 把 PS 应用重链到 DDR 之后重编出的 `57fa442a7eaf` 才是现在板上跑的这颗，10-05 那颗没上过板、已被取代（`board/README.md:11,19`）。
写入结果的三段 `Erase/Program/Verify Operation successful` + `[Labtoolstcl 44-377]` + `PROGRAM_RC 0`，耗时 137 s（`program_hw_cfgmem` 的 elapsed），完整日志 `board/flash/flash_qspi_6.log` 是仓库外本机件、`*.log` 在 `.gitignore` 里所以不随包（`board/measured/flash_qspi_2026-10-05.txt:15-21`）。

那次踩到的三个障碍原样记在同一份件的第 27-35 行，且"都写进脚本注释了，避免下一个人重踩"（`:27`）：
① bootgen 对 Zynq-7000 的 bif 只接受 `the_design:` + 花括号里逐行一个文件，带逗号、带 `[boot]`、带 `configuration` 三种写法都判 syntax error（`:28-29`）；
② 部件必须选 `COMPATIBLE_PARTS` 里含 zynq7000 的那一支（`:30-32`）；
③ 必须设 `PROGRAM.ZYNQ_FSBL`，缺它报 `[Labtools 27-3203] FSBL file not found`（`:33-35`）。

**`Verify successful` 不等于能自启**：那一步是**从 flash 读回逐字节比对**，不是主机侧比对，所以"片上内容与 `BOOT.bin` 一致"这句它是证据；至于"断电后能自己起来"，还要把启动模式拨到 QSPI 再上电一次才算量过（`board/measured/flash_qspi_2026-10-05.txt:23-25`）。

### A4. hw_server、断电重上、COM6：三类"链是活的"故障

- **`hw_server` 才是真正持有 JTAG 线缆的进程**（默认监听 TCP `localhost:3121`），`xsdb` 只是连它的 Tcl 客户端；没起就 `connect` 连不上，两个 `hw_server` 抢同一根线时后起的报"设备被占用"。所以顺序永远是：确认一个 `hw_server` 在跑 → 再 `xsdb` → 再 `connect`（`study_docs/main_report_study/learn/50_tcl_tutorial.md:403-410`）。Vivado 工程流的 `open_hw_manager` 会自己拉起/复用一个，这是 `build/tcl/program_pl.tcl:14` 的 `connect_hw_server -allow_non_jtag` 能直连的原因（同处 `:408-410`）。
- **症状与定位**：`connect` 成功但 `targets`/`mrd` 报 `Invalid target` ⇒ `hw_server` 没起来（xsdb 的裸 `connect` 不总会自动拉），手动起 `Vivado/bin/hw_server`（这个名字**没有 `.exe`**），等几秒（`study_docs/main_report_study/05_验证与上板/03_上板流程与踩坑.md:104`）。演示前清单里同一条写成"第一句 `Invalid target` ⇒ `hw_server` 没起"（`study_docs/main_report_study/demo_video_3min_20261005.md:30`）。工具侧把它固化成判据：`health_read` 没有输出就归因到"hw_server 没起？A9 没在跑？"，并且**这一项直接计入判红数**，因为读回口拿不到 json ⇒ 后面所有"读回来对不对"的判据都不成立，这一版不能算验过（`build/board_verify.sh:73,216-217`）。
- **冷上电后句柄还没重新枚举**：`build/evidence/r118_eyes/state.txt:13-16` 记 07:39 那一次死在 `targets -set 1`——那是 `hw_server` 冷上电后还没重新枚举链路；等它枚举成 `1=APU / 2=ARM#0 / 3=ARM#1 / 4=xc7z020` 之后**原脚本一字未改就过了**。结论是"冷上电后第一步就 REFUSE" ≠ 板子或脚本坏了，先用只读探针 `build/tcl/probe_target_select.tcl` 重连一次看枚举表，再决定要不要动脚本（`report/acceptance-recipes.md:101-103`，出处 `report/log/issues.md:13095-13097`）。
- **判"链空"到底是没电还是坏**：`build/r88_jtag_scan.txt:39-52` 是正向凭据——USB 侧（Composite Device / Serial Converter A / B / COM6）全部 `OK`，而 `scan_jtag` 报 `ERROR: [Labtools 27-2269] No devices detected on target localhost:3121/xilinx_tcf/Xilinx/0ABC01A`，结论原话「缺的是**板子供电**，不是驱动/线/PC」（`board/hardware_setup.md:126-130`）。这也解释了硬顺序：**先接 12 V 再接 USB-C**，反过来会在"USB 已枚举、板未上电"的状态下产生 `No devices detected`（同处 `:126`）。
- **COM6 怎么来的**：板载 USB-C 调试桥是 FTDI FT4232，通道 A = JTAG/SWD DAP、通道 B = UART ⇒ Windows 上的 **COM6 @115200**（`board/hardware_setup.md:47`）；`report/acceptance-recipes.md:10` 把所有"发命令"的位置统一约定为 COM6 115200-8N1。取口用不打开串口的方式：`powershell "[System.IO.Ports.SerialPort]::GetPortNames()"` 回 `COM6`——枚举不等于打开（`board/hardware_setup.md:164`）。
- **共享冲突**：COM6 一次只能被一个程序占着，自己开着终端占着时脚本会拒绝，**那不是板子坏了**（`board/README.md:109`）；PowerShell 侧的表现是 `UnauthorizedAccessException`（`report/host_guide.md:141` 原句："`COM6` 不能同时被别的终端占着，否则 PowerShell 报 `UnauthorizedAccessException`"）。与它并列的第二条注意点别混：**要看寄存器就先停止推流**，流在跑时读到的计数是中间值（`board/README.md:109`）。同一条冲突的另一半是"另一块板会撞"：两块板的 FT2232 被写成同一个序列号 `0ABC01`，Windows 只能给其中一个保留实例名、另一个退回总线位置名，`hw_server` 用串口号拼 cable URL 于是**同名的第二根线根本不产生第二个 target**，表现是"两块板抢端口"；重启 `hw_server`（杀进程 → 等 8 s → 重扫）后仍然只有 `0ABC01A` 一个 target、`open_hw_target` 报 `[Labtools 27-2269] No devices detected`。给出的办法是**一次只插一块板的 USB-C**，不动 EEPROM（`report/log/overnight_log.md:973-982`、`board/hardware_setup.md:147`）。写板载 FT2232 EEPROM 在本项目列为**不做**的风险步骤（同处）。

### A5. 拨码与启动档：ON=0、只在上电采样、以及一条不能当证据的寄存器

- 实测拨码表与采样时机：**`JTAG 00 / QSPI 10 / SD 11`，ON=0，只在上电采样**（`report/log/issues.md:14088`，它是"板子无罪"那串证据里的一条：厂商 `BOOT.BIN` 在 JTAG 档写进同一颗 flash、拨到 `1 0` 冷上电 ⇒ `DONE` 亮 + 串口打出 `U-Boot 2023.01 ... CPU: Zynq 7z020 / SF: Detected w25q256 ... total 32 MiB`，原文存 `board/measured/qspi_vendor_control_2026-10-06.txt`，捕获窗口内 6 054 字节、落盘后 6 429 字节，多的部分是换行转换，`report/log/issues.md:14085-14089`）。
- "只在上电采样"的后果有两条：拨完码必须断电重上，热插不生效；也正因如此，**改了拨码这件事没法用软件读回来**（`LEARNING/04:351-354`，同一结论）。
- **`MODE_PIN_M[2:0]` 两档都读 111，所以不能当拨码证据**：只读探针 `build/tcl/probe_pl_done_state.tcl` 两档各读一次，QSPI 档那份 `BIT08/09/10 = 1 1 1`（`board/measured/pl_config_state_qspimode_2026-10-06.txt:33-35`）、`CONFIG_STATUS=01010110000100000111111111111100`（`:24`，那一行是空白分列的 `REGISTER.CONFIG_STATUS … 0101…`）、`BOOT_STATUS` 那行 bit0=1（`:53`）；JTAG 档 `CONFIG_STATUS=01010110000000000001111100001100`、`BOOT_STATUS=0`，件头直接写明 `# NOT discriminating: MODE_PIN_M[2:0] reads 111 in both runs, so the mode-pin bits alone cannot tell the DIP`（`board/measured/pl_config_state_jtagmode_2026-10-06.txt:3-6`）。**能判别的只有** DONE(内部/引脚)、EOS、GWE/GHIGH/GTS_CFG_B、CPU0_STATUS_VALID，两档之间这四项 1→0（同处 `:5`）。
- 为什么需要这支探针：擦写 QSPI 前必须知道拨码在哪一档，而 `program_flash` 的拒绝只在控制台出现过、没留凭据；flash 里有有效镜像 ⇒ 冷上电后 STATUS 是"已配置"这一族，拨在 JTAG 档则没人配置它。这条判据只 `report_property`，不发复位、不写任何东西，所以对在跑的系统零副作用（`build/tcl/probe_pl_done_state.tcl:6-9`）。
- 硬写不认档的后果：`[Xicom 50-100]` 明说当前档不支持，硬写会"成功"但结果不可信；17:00 那次 x1 写在 QSPI 档做，报的 Erase/Program/Verify 全部作废。同处还记了 `program_flash -erase_all` 在这颗片上失败、扇区擦可以（`report/log/issues.md` 第 406 条末段，经 `LEARNING/04:483` 汇总）。

### A6. 板级校验：`board_verify.sh` 的各开关判什么、"判红数为 0"是什么意思

真实入口是一条命令（`board/README.md:103`）：

```bash
VP_XSDB=<…>/xsdb.bat bash build/board_verify.sh --battery --geom --round=r118
```

它是"上板之后一把验收（机器能判的那一半）"：**开机回读 → 读回口 → 105 条串口命令电池 → 几何"最后一跳"**，日志留 `build/evidence/`，末行形如 `RESULT board_verify PASS（判红的步骤：0）`（`board/README.md:106`）。
脚本自己不刷板子——文件头"不做什么"那一条写明三件套下载故意留给人一步一步确认（`build/board_verify.sh:25-29`）。

各开关的射程（`build/board_verify.sh:8-20`）：

| 开关 | 判的是哪一层 | 备注 |
|---|---|---|
| （不给开关） | 只跑不需要推流的那几项：读回口 + 开机自检 | `:8` |
| `--stream` | 再加：推流 → 仲裁交接 → 停流交回 | 要约 2 min（`:9`） |
| `--battery` | 串口命令电池：会改板上控制字并复原，复原由 `STAT` 的 `geom=` 兜底 | 条数在两处口径不同：脚本头写 97 条（= V8 的 71 + V9 的 20 + #77 的 6，`:10-11`），留档实跑是 105 条（`report/06-validation.md:119` 那份 console 与 `board/cmd_battery_v81.txt` 的"105 条"一致，见 `board/README.md:95`）⇒ 以件里的实测行为准 |
| `--geom` | V9 几何自动化的"最后一跳"（`lane23` + `CFG_DATA0`） | 与电池**分开取证**：电池看**回显**，这一条看**像素域真值**（`:12-13`） |
| `--round=` | 原始串口回显那份必须写成 `build/evidence/r<本轮>_serial_raw.txt` | 没有轮号就**判红而不写文件**（#179：脚本自带默认值会把今天的数写成一份名字叫旧轮的假凭据，`:14-16`） |
| `--self` | 只测判据本身、不碰板子的五条对照 | 见下一段 |

**"判红数为 0"的含义**：这一行不是"跑完了"，而是每一步的红项计数器为零。留档那一次的完整末段（`report/06-validation.md:117-122`）：
`RESULT PASS geom_check（ok=10 fail=0）`、`RESULT PASS uart_cmd_check (105 条命令, 97.9 s, 捕获 board/uart_script_capture.txt)`、`ok V9-6 温度格三方对账：4 条 [TEMP] 的 degC↔osd↔gpio 全部自洽`、`[SERIAL] 落点=build/evidence/r118_serial_raw.txt 行数=4 [TEMP]=2 判定=绿（地板 2）`、`RESULT board_verify PASS（判红的步骤：0）`。
判红会点名是哪一步、哪一项，不会安静地少跑一段（`board/README.md:81-82`）；红项计数器 `NRED` 是真实累加的，例如"读回口拿不到 json"就直接 +1，理由是后面所有判据都不成立（`build/board_verify.sh:216-217`）。

**它自己留一份被跟踪的原始串口回显**（#220 的工具那一半，`build/board_verify.sh:37-52`）：这条规矩的成因值得记——`[TEMP] degC=… raw=… vccint=… osd=…C` 这类**只有固件周期性打出来**的读数，此前是作者从本机那份"不在提交包里、也不进 git"的捕获里**手抄**进 `build/evidence/` 的，于是"板上这一刻的温度"这条交付数字的凭据是一份抄件，工具自己不产它 ⇒ 别人复现时拿不到同一件东西（`:38-40`）。现在三条判据每条都能红：① 抓到的内容必须**非空**（COM6 被别的终端占住时 `powershell` 照样返回 0，空捕获以前会算绿）；② `[TEMP] degC=<数字>` 的行数 ≥ `TEMP_FLOOR`（默认 2）；③ 落到盘上那份必须**能用 UTF-8 解**（固件中文回显是 GBK；GBK 原样进 git，下一轮 `doc_enc` 就红在编码上，而那一红长得像"文档坏了"不像"捕获没转码"）（`:41-45`）。
`--self` 就是给这三条判据配的反例：造空捕获 / 两行 ASCII / 只有一行 / GBK 转码后 / GBK 未转码 五种 fixture，要求五条全部形符期望且地板 5/5；第四条与第五条是**一对**——少了"没转码那份必须红"，就没有"转码这件事真在被判"的证据（`:17-20,83-108`）。
这里还留了一条通用尺子纪律：不能写 `$(grep -ac … || echo 0)`，因为 grep 数出 0 时**也打印 0 并且退出码 1**，式子给出 `"0\n0"` 两个字符，`[ … -lt 1 ]` 报 "integer expression expected"，而那**正是**空捕获该有的判红——它变成了一条 shell 错误然后往下走成绿（`:54-57`）。

### A7. 片上温度：XADC 实测与工具估算功率是两个量

- **XADC 实测**（板上固件打出来的）：r97 那一版 2026-09-30 22:23，三条 `[TEMP]` 读数 `degC=63.38 / 63.17 / 63.13`，同一份里 `raw=`、`vccint=997mv/998mv`、`osd=63C`、`gpio=0x63`（`build/board_temp_r97.txt:8-10`）。抓的时候**SD 本地播放在跑**（末一条 `[STAT]`：`frames=4398 playing=1 src=1`），不是空载（`:4`）；工况不同（空载 / SD 在播 / 电池负载）的温度**不可比**（`report/acceptance-recipes.md:117`）。
- 读数被三方对账而不是被单点信任：`V9-6 温度格三方对账` 判的是串口十进制、屏上 `TEMP` 格的 BCD、写进 gpio 的那一位**同拍一致**，所以"屏上写的数"与"串口打印的数"是同一个来源（`build/board_temp_r97.txt:12-15`，判据原文另见 `report/06-validation.md:120`）。
- **工具估算**（另一条独立来源）：`build/power.rpt` 的 `1. Summary` 那张表给 `Total On-Chip Power (W) 2.391`、`Dynamic (W) 2.213`、`Device Static (W) 0.178`、`Effective TJA (C/W) 11.5`、`Max Ambient (C) 57.4`、`Junction Temperature (C) 52.6`、`Confidence Level Low`（`build/power.rpt:33-41`）；`system_top` 那一行功率也是 `2.213` W（`:164`）。置信度 Low 的直接原因是 I/O 节点活动性：`More than 75% of inputs are missing user specification`（`:112`），而设计实现状态与钟活动性都是 High（`:110-111`）。
- **口径（被追问就两个都给）**：工具那一侧现在读的是估算结温 52.6 ℃（`build/power.rpt:40`，置信度 Low、无仿真活动文件），r97 那份留档快照当时写的是 52.5 ℃（`build/board_temp_r97.txt:16`，属那一版构建的读数，留档不改）；板上 XADC 实测是 63 ℃ 级（`:8-10`）。工具估算与片上实测是**独立来源**，本仓库不拿其中一个去"验证"另一个（`build/board_temp_r97.txt:17`）。同处还记了用户 2026-09-30 的观察"基本稳定在 64 ℃ 左右"与这里的 63.1–63.4 ℃ 同量级（`:18`）。
- 另一组留档读数：刷板前后各拍一张健康快照，`[TEMP] degC` 62.01 → 60.20，这一格在动说明 XADC 在跑（`board/README.md:122`）。同一段还示范了怎么读一张快照不误判：`frames=4398` 两边同值**不说明冻帧**（`board/README.md:123`），它打的是"当前这个文件一共有多少帧"，即 `sd_frame_total()`（`src/ps/sd_play.c:811`，经 `src/ps/main.c:1386` 送进格式），按构造就是静态字段；要判断通路活不活得看能动的字段（`pub=`、`pc`、`degC`）（`board/README.md:124`）。

### A8. 人眼判据作为一层证据：为什么"眼睛"要登记、签收怎么记

机器判不了屏幕，所以有三条**不预先写成通过**：分割线两侧是同一条帧的两种处理状态、几何关系一致；缩放或旋转时不出现整行错位；OSD 各格读数与串口读回一致（`board/README.md:132`）。
逐格签收状态与"谁点的头、什么时候、原话"记在 `board/acceptance.md` 与 `board/signoff.md`；接线、供电、跳线与 COM 口的实际观察在 `board/hardware_setup.md`；原图与金标比对那一格的状态在 `board/raw-vs-golden.md`（`board/README.md:133`）。

签收记录的形状是**原话 + 时间 + 当时状态**三件，不是"通过/不通过"。几个真实的例子：
- E1/E3：队员 2026-09-30 06:2x 原话"现在都很正常"，凭据到 `board/acceptance.md:89,71`（`report/acceptance-recipes.md:26`）。
- E4a：原话「现在屏幕没问题了四角都在屏幕内」，r118 已判（`report/acceptance-recipes.md:248`）。
- E6：原话就一个字「0度」，判法明写"只看屏第二行 `ROT:` 那一格"（`report/acceptance-recipes.md:36`）。
- 反面教材同层登记：`board/acceptance.md:90` 里那句"当时**标记线有没有关**我没问到，所以'缝两侧'那一判是在标记状态未证下给的"（`report/acceptance-recipes.md:74`）——前提没锁住时结论不许升，只能写"仍未定归属"（`:71`）。
- 眼睛的射程也要登记：本仓库量过的唯一可分辨差分是"每帧换角 = 0 档 vs ≥1 档"；连续量（位移多少源像素、发生率百分之几）交给台架量（`report/acceptance-recipes.md:192-196`）。"眼睛在'宽窄'这一档是饱和的"这句写在 `report/known_issues.md` 第 1 节末尾（`:197`）。
- 现象发生率本来就低时，A/B 的"没看到"不等于"没有"——例：#189 台架量到约 0.27 %（3 726 个旋转态像素命中 10 个）（`report/acceptance-recipes.md:188-189`）。

从 `report/acceptance-recipes.md` 照抄一条真实配方（R7，冷上电三步链）。**命令与前置条件**：板子断电 **≥10 s**（让 4.7 kΩ/100 nF 那两只脚彻底放掉）→ 上电 → **只跑** `build/tcl/ps_jtag_boot.tcl` → `program_pl.tcl` → `ps_app_reload.tcl`（顺序不能换，PL 没烧之前应用起不来）→ 全程不碰 KEY1/KEY2；看之前先读 `[STAT] … osd=1` 确认那一格会被画出来，再看屏 `ROT:`（`report/acceptance-recipes.md:94-96`）。**怎么记**：三份 stdout 各存一份（`step1_boot.txt` / `step2_program_pl.txt` / `step3_app.txt`）+ 一份 `state.txt` 汇总 rc，并且把"刷进 PL 的位流 md5"写进同一份汇总——不是写在脑子里（`:98`；凭据 `build/evidence/r118_eyes/state.txt:8-10,16-17`）。
每个"不"意味着什么：
- **不碰按键**：KEY1/KEY2 会改角度，碰了就没有"开机不许自己改状态"这一判（`:93` 的用途句）。
- **断电 ≥10 s 而不是随便断一下**：两只脚的 RC 要放干净，否则上电初态不可信（`:94`）。
- **不换顺序**：PL 没烧之前应用起不来（`:95`）。
- **对照组要再断一次电**：需要按住按键那一组不能在上一次会话里补做（`:104`）。
- **不在链没通时改脚本**：死在 `targets -set 1` 先重连看枚举表（`:101-103`，即 A4 那条）。

### A9. 板级读数的取数口：`src/host/health_read.mjs` 与单步件的"名字契约"

`--battery` / `--geom` 这类一把跑的入口在 `build/board_verify.sh`，但它下面踩着的取数口是 `src/host/` 那几支，读懂一支就读懂了整套读法。

`node src/host/health_read.mjs [--gpio0 41200000] [--gpio1 41210000] [--once] [--gapclr]`（`src/host/health_read.mjs:18-22`）判的是 PS 侧读回 PL 的链路健康快照（V7.6 / P0-A，`:6`）。它的接口设计有三处值得学：

- **不加 AXI 从设备，只用两个已存在的 GPIO**：lane 号写在 GPIO_0 的 `bit[31:27]`，脚本先读回 GPIO_0 原值、**只改这 5 位**、最后把原值写回去，所以 `effect_en/threshold/src_sel` 不受影响；数据从新加的 GPIO_1（只读 32 bit）读（`:10-13`）。这就是"读一个诊断值不许改变板上状态"的实现方式。
- **错号一眼看得出来**：lane 0..9 是 `link_monitor` 的快照，lane 23/24/25..29/30 各有内容（缩放、时延那一组、`dbg_src`），lane 31 的 `bit0`=源时钟消失、`bit1`=源时钟被拉慢（拔线），而 **mux 没定义的 lane 10..22 硬件返回 `0xDEADBEEF`**（兜底那一句 `else if (lm_lane > 5'd9) lm_rd = 32'hDEAD_BEEF;`，`:14-16`）。`--gapclr` 读之前只把"帧间隔统计"（lane3/4/5）归零，其余 lane 仍是自启动以来的累计（`:20-21`）。
- **两遍采样当撕裂守卫**：默认按 `want` 名单（`health_read.mjs:334`：lane0–9 加 25/26/27/28/29/24/23/30/31，共 **19 条**）各读两遍，单调计数器第二遍只允许 ≥ 第一遍，变小就意味着采到了快照刷新的那一拍，会单独报出来；非单调 lane（stall/gap/flags）两遍不同是正常的，只标注不报错（`:24-26`）。前置条件写得很清楚：板子上电、bit 已下载、`hw_server` 在跑（`:22`）。

它还自带一条"判据不能自证"的规矩，与 B 半同源：八个 `why` 组合对的是**手抄的语义表**，"不从 decode 反推，抄过来就等于自证"，再加一条反向对照——把 `why` 整体错移一位后必须被抓到，"抓不到就说明这条判据是假的"（`src/host/health_read.mjs:150-151`）。`eth_live` / `owner_eth` / `drop_words` 这些键就是从这里出来的（`:76-82`、`:54` 给 `drop_words` 的定义："被 fifo_full 挡住而永久消失的 16bit 字数（板上唯一真实丢数据通道）"）。**这把尺子的射程因此被 A6/R6 那条零样本地板管着**：`eth_live=0` 时 `drop_words` 读到的那个 0 记成"未测"、不记成 0（`report/acceptance-recipes.md:82`）。

单步件的名字是**对外契约**，不能随手改：`board/README.md` §2.2 用一张表登记"外面谁按这个名字指它"，三例——
`rdbck.tcl` 被 `board/scripts/board_flash.sh` 与 `build/make_submission.sh:87` 指着（`board/README.md:90`）；
`uart_cap_once.ps1` 被 `build/board_verify.sh:154,172`、`src/host/arb_handover_test.mjs`、`build/tcl/ps_app_reload.tcl` 指着（`:93`）；
`cmd_battery_v81.txt` 是 105 条串口命令的清单本体，被 `src/host/uart_cmd_check.mjs:37` 当默认输入（`:95`）。
`verify_r87.md` 那一条把理由说得更硬：`data/metrics.csv` 有 5 行的证据列指它，"所以这个名字不能改"（`:119`）。同理 `-Cmds` 与 `-File` 的分工也是有原因的：`uart_cmd_script.ps1` 才带得动"逐条灌 + 分段收回显"，而 `uart_cap_once.ps1` 是一发一收（`:93-94`）。

### A10. 复现顺序（八步，标出哪一步动板、哪一步只有人能做）

照 `board/README.md:139-147` 的顺序抄一遍，标注来自同一文件 §2 那张"动板子吗"列（`:74-79`）：

| 步 | 命令 | 动板吗 |
|---|---|---|
| 0 | 先认版本：三件套 md5 前 12 位对回身份表 | 不动 |
| 1 | `vivado -mode batch -source build/tcl/build_system_axigpio.tcl`（或直接开 `board/zynq_video_sys.xpr`） | 不动 |
| 2 | `node build/ps_app.mjs`（要改 PS 侧才需要） | 不动 |
| 3 | `bash board/scripts/board_flash.sh --check`（只读，先确认链是活的） | 不动 |
| 4 | `bash board/scripts/board_flash.sh`（真的把三件套放上板，JTAG） | **会**：第 1 步就 `rst -system` |
| 5 | `bash board/scripts/board_health.sh`（只读快照，落 `board/measured/`） | 不动 |
| 6 | `VP_XSDB=<…>/xsdb.bat bash build/board_verify.sh --battery --geom --round=<这一版>` | 不动（只读 + 发命令） |
| 7 | `bash board/scripts/make_boot_image.sh`（可选：要断电自启才做） | 不动 |
| 8 | `VP_HW_URL=<host:port> vivado -mode batch -source board/tcl/flash_qspi.tcl`，然后把启动档拨到 QSPI、断电重上 | **会**：擦写 flash；**后一半只有人手能做** |

三条边界要记住：第 1 节那两支（`stage_board_projects.tcl` / `stage_vitis_platform.sh`）不在这一列——它们不改板子，改的是 `board/` 这份工程本身（`:149`）；发布前的检查不在本目录，是 `bash build/gates.sh`，而且"读数以它打印的那一行为准，本页不复述任何一条门禁条数"（`:151`，这条自律与 B 半同一精神）；`.xpr` 里 81 处引用写成 `$PPRDIR/../src/...`，**所以这份工程只能放在 `board/` 这一层**，往深挪一级 `src/rtl` 与 `src/constraints` 就全部指不回来（`:42`）。

---

## B. 交付工程化：尺子体系、导出器、改口脚本

### B1. 结论先说

这个项目的特别之处不在 RTL，而在**每一句交付话都被一把尺子盯着"它会不会说谎"**。尺子分三层：

1. **构建/板级事实层**：`build/gates.sh`（盘上报告 vs 阈值，不重跑构建）。
2. **交付形状层**：`build/deliver_spec_check.mjs`、`build/checks/check_repo_consistency.mjs`、`src/host/doc_currency_check.mjs`、`src/host/metric_recheck.mjs`、`src/host/line_cite_check.mjs`。
3. **改写轮守恒层**：`build/r125_fact_hold.mjs`（改文档之后事实记号不许丢）。

共同设计只有一句话：**读不到就记 `NOT_MEASURED`，绝不记通过**。
`check_repo_consistency.mjs:5` 的口径句是"只读，不改任何文件；判定 token 放每行最后一个字段；每条打印分母；缺输入一律 NOT_MEASURED（绝不判通过）"；
`deliver_spec_check.mjs:8-9` 的口径句是"判定词永远放在行尾；`cmp=N` 记的是**做了多少次比较**，不是通过了多少；读不到/没扫到一律 NOT_MEASURED（不许当'没毛病'）"。

### B2. 尺子体系：每把尺子防的是哪一类说谎

**`build/gates.sh`——防"跑完了"被读成"判过了"**
最新那一次留档给的是 `判定 24 项、未判 0 项`（`build/r126_gates.txt:56`），当前状态 **24 项 = 23 绿 / 1 红**，两跑逐字节一致，唯一那条 FAIL 是 `FAIL C5c frame head is not the previous frame's tail …`（`report/06-validation.md:75,47`）；这一版的采纳条件第 4 条写的就是"发布门 24 项里红数 **== 1**（只有声明过的 `C5c`），且检查两跑逐字节一致"（`report/06-validation.md:93`）。
它防的第一类谎是**用结尾那句 `GATES: ALL PASS` 掩盖没判的项**：结尾必须把范围一起念出来，`GATES: ALL PASS` 这一行**只有在"没有一项是因为缺席而没判"时**才允许出现；有 n/a 时换成 `GATES: PARTIAL`，而 `freeze_evidence.sh` 就 grep `ALL PASS` 这个串，于是它自然拒绝冻结这一版（`build/gates.sh:182-184,590-598`，计数器 `NSAY`/`NNA` 在 `:185-194`）。
同一族第二件事：**解析不出来一律当失败**（`build/gates.sh:173-175` 的自检循环把 `wns whs tnsfail whsfail eps bram bramp lut lutp reg dyn crit rerr cdcc` 全部过一遍）。第三件：报告比 RTL 旧（"改完没重跑"）也要念出来——只对 `build/` 这份活目录检查 `find src/rtl -name '*.v' -newer "$bit"`，冻结目录按定义是历史产物，报出来是噪声（`:63-67`；2026-09-24 真踩过：构建还在跑就先跑了一次门禁，全套报告是 30 分钟前的、七项全绿，`:64`）。
第 15 项的形状值得单独学：顶层台架一次要跑 40+ 帧约 75 分钟，放进"构建完就读"的门禁里没人会等 ⇒ 门禁不跑它，但**必须**认一份与当前顶层同一次跑出来的报告（`build/tb_v98_report.txt` 头部两枚 md5 与树里现值必须对得上）。这一项补上的原因就是曾经"`gates 14/14`"与"唯一例化顶层的台架红着"**同时成立**（`build/gates.sh:307-312`）。

**`build/deliver_spec_check.mjs`——防"形状不合规"与"尺子自己空转"**
射程由 `git ls-files` 现算，注释点名原因："手写清单会静默变窄，所以由 git 现算"（`:18-20`）；读到 0 个文件时先打 `C00 SCOPE git ls-files 读到 0 个文件 NOT_MEASURED` 再 FAIL（`:32`）。判据名逐条（去代码里读到的 `id` + `name`）：

| 判据 | 机器名 | 它判什么 |
|---|---|---|
| C0-3 | `file-names-ascii-lowercase` | 文件名纯英文（小写字母/数字/下划线/连字符/点/斜杠），并分开数"中文或空格"与说明件豁免（`:41-52`） |
| C0-4 | `top-level-structure` | 顶层结构固定：多余目录与缺目录分别点名（`:54-68`） |
| C1-1 | `xdc-under-src-constraints` | 活动约束在 `src/constraints`，过程凭据里的 `.xdc` 单列不计入活动集（`:70-77`） |
| C1-2 | `src-placement-per-1.2` | RTL 在 `src/rtl`、PS 裸机固件在 `src/ps`（同级）、PC 侧工具在 `src/host`；顶层八目录之外的**子目录** C0-4 看不见，所以这一条单独量（`:79-118`） |
| C1-3 | `host-dual-impl-entries` | 上位机双实现（`.py`/`.mjs` 同名成对）+ 双击入口（`.bat`/`.sh`）（`:151-168`） |
| C1-4 | `host-readme-3-sections` | `src/host/README.md` 三件事、且**半页**（`lines > 45` 即超）（`:170-178`） |
| C1-5 | `script-header-comments` | 脚本头注释只写用途/输入输出/退出码，并抓"自我描述"（`:181-195`） |
| C-PATHS | `script-src-paths-resolve` | §6.2「路径与仓库实际一致」的机械版：脚本里指向源码目录的输入路径必须在盘上（`:197-230`）。同处一条自律：写死路径会让这条判据自己红在夹具上（`:125`） |
| C-LEN | `sub-readme-length` | §7.6 长度上限：根 README 一页（在 C3 里判）、子 README 半页（`:234-268`） |
| C2-1 | `sim-only-v-files` | `sim/` 只留 `.v`（+ 自带的 `README.md`）（`:273-277`） |
| C2-3 | `tb-header-three-sections` | 每个 testbench 头部三段（功能/激励与检查/预期结果），行为模型不计（`:279-296`） |
| C2-4 | `sim-readme-table-bidirectional` | `sim/README.md` 表格行与 tb **双向**一致：未列 + 幻影分别数，另判"有没有一行运行命令"（`:298-311`） |
| C3 | `root-readme-shape` | 根 README：两节 + 亮点带数 + 目录说明 + 时序 + 中英对应 + 切换链接（`:314-335`） |
| C4 | `build-tcl-and-reports` | build：指定 TCL 名单 + 头部要素 + `build/report/` 归档 + 对照表（`:337-358`）。自认的盲区：它只看 `build/report/` 里有没有"名字带 util/timing 的件"，判的是**文件名不是内容**（`:361`） |
| C5 | `dirs-skills-readme-report` | 四类目录齐 + `skills/README` 四要素 + report 章节齐（`:389-451`） |
| C6 | `license-file` | 开源协议：`LICENSE` 存在且内容识别为 MIT/Apache-2.0（`:455-460`） |
| C7 | `style-red-lines` | 文档风格红线，射程是交付文档、**不含** `report/log` 与 `build/evidence` 过程件；并配 `C7-SELF` 自测（`:462-539`） |

C1-2 有一条值得抄的自律：**判据必须能红**，"否则'换了口径'等于'改了成绩单'"，所以给它自己的对照夹具（`:120`）。

**`build/checks/check_repo_consistency.mjs`——防"文档与仓库互相对不上"**
`row(id, label, detail, verdict)` 每判一项就打一行，并解释为什么不能只在结尾打印："第一版只在结尾打印，卡住＝零输出"（`:23`）。判据名：
C1 声明唯一权威源（缺 `report/declarations.md` 或权威块缺字段 ⇒ 整条不可判，`NOT_MEASURED`，`:60-89`）、
C2 指标数字指得到证据（`data/metrics.csv` 每行的证据路径，`:306-310`）、
C3 文档内路径存活（死引用；豁免分六类逐条打印，"不是静默跳过"，`:326-333`）、
C4 文件名纯小写 ASCII（`:339-352`）、C5 许可与卫生机检（被调脚本超时就记未测而不是判通过，`:357-368`）、
C6 技能包索引一致（`:375`）、C7 验证状态三处一致（`:380-396`）、C8 未决项汇总一致（`:414`）、C9 A/B/C 路径复现演练（`:440-443`）。

**`src/host/doc_currency_check.mjs`——防"文档说的已经不是这一版"**
门禁那行给的是 `文档时效 doc_cur 扫了 79 个文档 红行=0 身份句=3 门禁读数句=2 self 变异 10（D1b 身份句 2 + D1c 门禁读数句 5，含固定点与反买通各一条）+ 对照 4 全过 + 不随包豁免的三条对照全过、全树 0 条、身份句抓到 >= 2、门禁读数句抓到 >= 2 PASS`（`build/r126_gates.txt:50`）。
它防的一类谎很具体：文档里"门禁 N 项 X 绿 / Y 红"那句话**对回基准门禁件本身**（D1c），而且加一层子规则就要同时把**数红行的模式改宽**——`D[123]b?` 不含 `c` ⇒ 新的 D1c 红行会不进射程，这正是"规矩 41(c)"点名的"加了子规则字母却没改计数模式"（`build/gates.sh:465-469`）。
射程口径也在这里：出处在**交付文档**里才判红，日记与注释只报数（`src/host/doc_currency_check.mjs:148-175`，转引 `report/acceptance-recipes.md:152`）。

**`metric_recheck` 与 `line_cite_check`——防"数字与行号是抄来的"**
留档两行（`build/r126_gates.txt:52-53`）：
`文档行号锚点 doc_cite 命中=1293 候选=628 self 15 条对照全过（含厂商豁免 2 条）、硬错 0、命中 >= 300 PASS`；
`数字对账 metric 判=117 首页=63 逐时钟=2/归属=2/百分数=8 csv认领=10/10 红=0 self（csv 两条 fixture + 首页假数 + 逐时钟/归属/百分数/Clock Summary 对照）全过、红 0、判 >= 30 个数、首页 >= 20 个、逐时钟 setup 与 hold 归属各 >= 2 条、余量百分数 >= 6 条、csv 认领两半相等且 >= 8（射程地板） PASS`。
读这两行的重点是**每一个下限都是一条判据**：命中数掉了、或某一层归零，尺子就在空转，而那长得和"全绿"一模一样。

**`build/r125_fact_hold.mjs`——防"改写把事实改没了"，并示范豁免层怎么写**
它比对"改写前（`git show HEAD`）与改写后（工作树）"两份文档里的**事实记号**，一个记号消失就判红；五类记号是 `number / md5 / path / cite / verdict`，全部按"值 → 出现次数"比，"出现两次少一次也要报"（`build/r125_fact_hold.mjs:2,18-25`）。
它为什么单独存在：那一轮把十几份交付文档交给并行的改写任务，"读起来不像 AI"是目的，但真正的红线是**数字/路径/判定词一个不许丢**，那句话不能只靠肉眼抽查（`:7-9`）。它只判"消失"不判"新增"，新增由 `metric_recheck` / `line_cite` 管（`:10`）。
**豁免层的写法是本篇最想传下来的一件事**：每条豁免必须带一个 `need` 字串——改写后的文里**当场数得到它**才准放行；数不到就照旧红，"依据消失 ⇒ 豁免自动失效，不需要再改代码"（`:27-29`）。配套两行输出把豁免本身也纳入射程：
`EXEMPT-REFUSED …（依据串「…」在改写后的文里读不到，豁免失效）`（`:136-137`）与
`EXEMPT-IDLE …（本轮这个记号没少，豁免可从名单删掉）`——"防止豁免名单只增不减"（`:131-134`）。
还有两条更细的守恒：记号少了一种读法 ≠ 记号没了（`30.0` 后接中文句号、`1.5 MB` 并入 `1.5MB`，正则会读成不同 token）⇒ 先按字面数一遍，字面还在就不算消失，但把**降级条数**打出来，"这个数本身是一条判据，异常膨胀就说明记号在漂"（`:94-96,123-124`）；生成件（`report/README.md` 长度列、`report/90-open-items.md`）不比前后、比"现在与生成器是否一致"，因为按 HEAD 差分必然一片红（`:75-93`）。末行形状：`RESULT=… 判 N 份改写件 + M 份生成件…消失记号 X 个 边界降级 Y 个 豁免生效 Z 条 豁免失效 R 条 豁免闲置 I 条 生成件未测 U 份`（`:145`），退出码 `lost ? 1 : (unmeasured ? 3 : 0)`（`:146`）。

### B3. 导出器与包：`build/make_submission.sh`

导出器是"仓库里合理、交出去不合理"这件事的唯一屏障。它的四条判据写在文件头（`build/make_submission.sh:8-19`）：

1. **按引用留凭据**：`build/` 与 `sim/` 跟踪了上千个文件，被交付文档、两份 README、`skills/`、板级操作卡**点名的**才带——"评委复核任何数字走的都是文档里那条指路，没被点名的留档在包里只是噪声"（`:8-10`）。
2. **被否决的轮次不进包**（`HARD_DROP`）：`failed_/red_/rejected/notadopted/_wip/aborted` 这些目录即使被文档点名也不带；文档还指着它们，就说明该改的是文档，不是把它们塞进包（`:11-12`）。
3. **交付名工程化**（`SIM_MAP` + 小写化）：`tb_v98_top_seam.v` 按职责换成 `tb_video_pipeline_top.v`，**改名只发生在导出时**；仓库里那几百处旧名是"当时看到的名字"，改它等于抹掉过程凭据；证据类（`build/reports/` 与 `report/log/`）正文**不参与改写**，新旧名靠生成的 `build/sim/names.md` 对上（`:13-17`）。
4. **导出后自检**：活文档里的路径式指路必须在包内解析得出；被改名台架的旧名与本机绝对路径必须为 0；**任一不过就不落盘**——"这一条是防我自己"（`:18-19`）。

数据来源是**提交**而不是工作树：`git archive --format=tar HEAD | tar -x -C "$TMP"`（`:126`），同处先取 `COMMIT=$(git rev-parse --short HEAD)` 与 `DIRTY=$(git status --porcelain | wc -l)`（`:121-122`）。
`REFUSE`/`FAIL` 语义（每一条都点名"不落盘"）：
- 射程漂移：`REFUSE：活文档射程里 $L/ 一层数到 0，而包内有这个目录 ⇒ 这是射程漂移，不是那一层没有文档`（`:156`）；必看入口缺 ⇒ REFUSE（`:162`）；`REFUSE：射程只数到 $LIVE_N 份活文档，而仓库 git 跟踪的 *.md 有 $REPO_MD_N 份`（`:168`）。
- 表没生成 ⇒ 无取舍依据：`REFUSE：sim/README.md 表格一格台架名都没数到`（`:248`）。
- 凭据搬不全：`REFUSE：板级凭据随包不完整 —— 点名且盘上 $EV_PRESENT 份，搬进包 $EV_MOVED 份；撞名被跳过：…`，并解释那个洞的形状"点名 29 份、只搬 15 份、剩下 14 份被整目录删掉，而引用还被改成了不带目录的样子，死链自检照斜杠形状抓不到"（`:378-381`）。
- 自检自己不许空转：`FAIL：死链自检只扫了 $DEADSCAN 份活文档（射程下限 40）⇒ 这一项什么都没查，不写 $OUT`（`:814`）；扫描面的**形状地板**是 README、README.en、ACCEPTANCE 三份必须在射程里——"今天那个洞的准确形状就是'只扫 ACCEPTANCE'——它不从引用数上看得出来（少扫的文件根本没进引用集）"（`:346-350`）。
- 未声明的红必须为 0：白名单只有一行 `KNOWN_RED_RE='^[ ]*FAIL C5c'`，逐份 `build/reports/*.txt` 数 `FAIL ` 行，`FAIL：随包凭据里有 $redunk 行没声明过的红 ⇒ 不写 $OUT`（`:1043-1058`，声明处另见 `report/known_issues.md:436`）。
- 找不到与这块位流同批的门禁件 ⇒ 不写 `$OUT`，要么先跑出配对报告、要么显式加 `--allow-no-gates`（`:1053-1057`；文件头的 `--allow-no-gates` 用法在 `:21`）。
- 三计数一并打印：`== 自检：死链 $DEAD ／ 旧名残留 $STALE ／ 绝对路径（甲 可执行件 + 乙 复现入口件）$ABSN …==`（`:938`），落地后 MANIFEST 计数与实际文件数必须相等（`:1088-1092`）。
- 拒绝落盘时目录里留的是**上一版**——"上一版看起来就是一份交付物，这是最坏的一种假绿"，所以开局就把"当前这个目录是谁"念出来（`:27-31`）。`rm -rf "$OUT"` 失败必须**当中止处理**：2026-10-02 踩过一次 `Device or resource busy` 之后脚本继续往下走，照样打印"344 个文件 / 死链 0 / 未声明的红 0"，而实际 `find` 数是 0（`:1074-1086`）。

包根中间物按**形状**清扫，不是按名单：`_pruned.txt` 是清扫层的落笔件，落盘前数一下——`FAIL：包根上 _pruned.txt 数到 $_KEEP 份 ⇒ 清扫层没在按形状干活，先别落盘`（`:950-955`）。名单为什么不写死，同一处有自白："`rNN_` 开头的开发件现在由上面的形状规则统一剪掉，不再逐个列名字（**列名就会漏，r92 漏过九个**）"（`:91`）；免剪集合也是一条正则形状：`KEEP_ALWAYS_RE='\.(sh|tcl|py|ps1|bat|xdc|f|v|c|h)$|^src/(rtl|ps|constraints)/|^build/report/|^data/golden/|MANIFEST|README|^submit/|^skills/'`（`:120`），它的由来是 `build/report/` 曾被当成"一次性脚本"整目录剪掉 ⇒ 首页三条凭据全成死链（`:112-114`，台账 #371）。这条规则还诚实写明"它今天兜着什么、明天兜着什么"，并留一句"这条形状规则要跟着改口"（`:116-120`）。

门禁件在**位流匹配**的候选里按 mtime 选最新：先 `BIT12=$(md5sum "$REPO/build/system.bit | cut -c1-12)`，再遍历 `ls -t build/*gates*.txt build/evidence/*gates*.txt build/evidence_r*/*gates*.txt`，只收身份行含 `system.bit md5=$BIT12` 的件，并把 `候选=$GCAND` 与取的是哪一份、它的两条 `md5=` 一起念出来（`:307-331`）。成因写在注释里：2026-10-06 21:03 落包读出来的是 `r118_gates_final.txt`——glob 按**字面序**排，`r118…` 排在 `r126…` 前面，于是包内那份门禁件的身份行写着旧 ELF `d0b07f84a068`，而交付正文写的是板上这颗 `57fa442a7eaf`；身份行是评委交叉核对走的那一行（`:308-312`）。

### B4. 改口（rotation）脚本为什么必须存在

数字变了要同步改口：一轮构建之后"板上跑的是哪一版 / 现役 ELF 是哪颗"这类**活句子**散在多份文档里，手改会漏。所以改口被工具化，`build/r126_rotate.mjs` 的作用句就是"把交付文档里'板上跑的是哪一版 / 现役 ELF 是哪颗'这类活句子按字面规则改口"（`:2`），16 条规则写死在本文件的 `R` 数组里（`:4`）。

幂等判定必须区分**三态**，而且三者相加等于规则数（这是这套脚本的形状）。`r126_rotate.mjs:67-70` 的实际判定：

```js
const hits = t.split(oldS).length - 1;
const newHits = t.split(newS).length - 1;
if (hits === 1) { t = t.replace(oldS, newS); fired++;  console.log(`HIT  …`); }
else if (hits === 0 && newHits >= 1) { already++;      console.log(`OKAY …这条已改口…`); }
else { bad++; console.log(`BAD  …命中 ${hits} 次（期望 1…）⇒ 整批不写`); }
```

三态就是 `HIT`（命中 1 次，改）／`OKAY`（旧文 0 次而新文 ≥1 次，已在别处改口）／`BAD`（其余一切，含命中 2 次这种歧义）。
末行把三态相加对着规则总数念出来：`APPLY|CHECK-ONLY 改口=$fired 已改口=$already 不适用=$skipped 不命中=$bad 规则=${R.length} 文件=${byFile.size}`（`:79`）；`不适用` 单独计是因为带 `B` 标签的规则只属于提交分支那棵树，另一棵树里它们不算不命中（`:6,51,62`）。
"已经改口的不报错、但要念出来，免得看起来'全命中'其实一条没管"（`:15`）——这句话就是幂等判定的目的。
两条防空转的地板：`命中+已改口` 低于 8 ⇒ `REFUSE …⇒ 这条改口波没在判东西` 并退 1（`:80-81`）；改口过程中**行数变了**也判 `BAD`（`:72`）。
写盘永远成批：先全判完再一次性写，"中途发现某条不命中也不能留下半改状态"（`:59,75-77`）；默认模式是 `--check` 只数不写（`:12-13`）。
同一支工具的姊妹件 `build/r124_fix_dead_cites.mjs` 是同一形状：`old` 串按**字面**匹配（不是正则），每条必须命中 `want` 次否则整文件不写（`:12`），末行 `规则 ${EDITS.length} 条 命中不符=${bad} 涉及文件=${touched.size}`（`:83`），`--apply` 时 `REFUSE：有不命中的规则，整批不写（不留半改状态）`（`:85`），并且**行数只许增不减**（`:9`）。

> 任务书点名的 `build/r126_fix_dead_cites.py` 在本仓库不存在；现役的是 `build/r124_fix_dead_cites.mjs` 与 `build/r126_rotate.mjs`（`find` 全仓只回到这两支，另加 `build/r124_sync_c3c9_numbers.mjs`、`build/r125_elf_md5_rotate.mjs`、`build/r125_qspi_wording.mjs`、`build/r125_readme_lengths.mjs`）。本节按现役脚本写。

### B5. 一条通用规矩：尺子的射程会随目录变深而静默变窄

最硬的一条凭据来自 C3 的两次射程修正（`build/checks/check_repo_consistency.mjs:107-118`，注释明写"本轮实测到的，不是推测"）：

- ① 字符类里**没有 `/`** ⇒ `build/evidence/r118_board/board_now.txt` 这种三层路径永远匹配不上：正则吃掉 `build/evidence` 后要求下一字符是分隔符，而它是 `/` ⇒ 整个 token 不成立，**静默不进分母**。当时打印 `检查路径引用=631 死引用=0 PASS`，看着全绿；把 `/` 放进类里，**同一棵树现算抓到 1179 条**（`:109-112`）。
- ② 右边界那条 `(?=[\s)|,，。；;：:]|$)` 把**反引号或全角括号包起来的写法**整体否掉，而中文文档里最常见的指路形状正是两头反引号（`:113-114`）。
- 改法：字符类带 `/`、去掉右边界前瞻（字符类自己就定义了"什么算路径字符"，遇到反引号、全角标点、空白自然收口）；并且**截断上限一并去掉**——"一个 200 字符的上限会制造新的静默（超限的 token 匹配不上＝不算分母），而那正是这条判据要消灭的东西"（`:115-118`，正则现值 `:118`）。

所以本项目把这套动作固化成四条，每一条都能在代码里指到：

| 做法 | 代码证据 |
|---|---|
| 射程用 `find`/`git ls-files` 现算，不列名单 | `deliver_spec_check.mjs:18-20`（"手写清单会静默变窄，所以由 git 现算"）；`make_submission.sh:1000`（"射程 $DEADSCAN 份活文档由 find 现算"）；`r126_rotate.mjs` 之外还有 `gates.sh:67` 的 `find src/rtl … -newer` |
| 打印每层计数（分母） | `check_repo_consistency.mjs:5`"每条打印分母"；`row()` 每判一项即打（`:23`）；`make_submission.sh:331` 把 `候选=$GCAND` 念出来 |
| 加"比较次数下限" | `make_submission.sh:814` 的射程下限 40；`r126_rotate.mjs:81` 的地板 8；`r126_gates.txt:50-55` 的 `命中 >= 300`/`判 >= 30 个数`/`逐条 ok >= 26`/`PASS >= 6 其中变异对照 >= 3`；`board_verify.sh:108` 的"地板 5/5" |
| 读不到就记 NOT_MEASURED，不许当通过 | `check_repo_consistency.mjs:5`；`deliver_spec_check.mjs:9`、`C00 SCOPE`（`:32`）；`gates.sh:173-175`（解析不出来一律当失败）；`r125_fact_hold.mjs:68,146`（无文件可判 ⇒ 记这个状态并退 2）；导出器那一侧**没有** NOT_MEASURED 这个记号，它用同一效果的 `REFUSE` 直接不落盘：`make_submission.sh:171`（射程只数到 N 份活文档 ⇒ 这一层多半没扫成）与 `:251`（台架表一格名都没数到） |

最后一条要点单独说：**文档形状本身是尺子射程的一部分**。上面 ①② 两个洞都不是"文件变多了/变少了"，而是"人把指路写成 `build/x.md`（反引号包住）"或"多嵌了一层目录"这两种**写法**造成的；同理，加了 `D1c` 这种子规则却没把数红行的模式从 `D[123]b?` 改宽，新红行就不进射程（`gates.sh:465-469`）。
所以改文档措辞、加一层目录、给判据起新字母这三类动作，都必须回头问一句"这次改动有没有把哪把尺子的分母弄小"——`r125_fact_hold.mjs:94-96` 的"边界降级条数"与 `check_repo_consistency.mjs:287-289` 的 fixture 表（`NOT_MEASURED 记未测`、`登记行 R* 与表头不进射程`）就是把这句问话写成了代码。

### B6. 可以搬走的四件形状

把 A 与 B 两半压回四条，迁移到别的题目时只换名字不换形状：

1. **动硬件的脚本必须自证"只读路径真的只读"**：`--check` 走的是 `scan_jtag.tcl`，而它替代的那版指着一个**不存在的文件**、抓的标记出自一支会发系统复位的脚本（`board/scripts/board_flash.sh:75-78`）。写"只读"不够，要"被调文件不在就 REFUSE"+ "把比了几次念出来"（`:78,86`）。
2. **判据要能红**：一条不能红的判据等于没写。这条在四个不同层各出现一次——`board_verify.sh` 的"未转码那份必须红"（`:103-105`）、`deliver_spec_check.mjs` 的 C1-2 对照（`:120`）、`health_read.mjs` 的 `why` 错移一位反向对照（`:150-151`）、`make_submission.sh` 的射程下限 40（`:814`）。
3. **数字不许由人抄**：脚本自己产出的**被跟踪**件才算凭据（`board_verify.sh:38-40`，`report/acceptance-recipes.md:111-115` 的 R8）。手抄一次，交付数字就与仓库脱钩了；反面就是"指路必须指到一个真在包里的文件"（`build/board_temp_r97.txt:6-7`）。
4. **改一次口就要改齐一片，所以把它做成工具**：`r126_rotate.mjs` 的三态 + 地板（`:67-70,81`）、`r124_fix_dead_cites.mjs` 的字面命中数与"整批不写"（`:12,85`）、`r125_fact_hold.mjs` 的记号守恒（`:18-25`）。手改会漏，漏了的那一处下一轮就变成"文档说的不是这一版"。

### B7. 本篇不写什么

- **经验总结、教训清单、数字索引在 `LEARNING/06b`**，本篇刻意不列"第几条教训"，也不做数字总表。
- 已知未修的限制不在这里重复，看 `report/known_issues.md`（`board/README.md:134` 同口径）；`C5c` 只在 B2 里作为"唯一声明红"出现一次。
- 时序收敛、资源与逐时钟名册那一半在 `LEARNING/05` 与 `study_docs/main_report_study/05_验证与上板/04_时序与资源的读法.md`；本篇只借它的"结论行 + 判定形状"这一面。

### B8. 核不到所以没写进本篇的项（留作欠账）

- **`cmd /c start` 把 MSYS 反斜杠弄坏 ⇒ 改用 `powershell Start-Process -FilePath` 起 `hw_server`** 这一条：全仓 grep `Start-Process` 只命中 PowerShell 输出件的 `-FilePath`（`board/serial_bytes.ps1:45`、`board/uart_cap_once.ps1:60`），没有把这条链条写成结论的留档 ⇒ 本篇只写 A4 里**有凭据**的那三种处置（`Invalid target`、枚举表重连、一次只插一块板）。
- **`build/r126_fix_dead_cites.py` 不存在**（`find` 全仓只回到 `build/r124_fix_dead_cites.mjs` 与 `build/r126_rotate.mjs`）⇒ B4 按现役两支写，并把这一处不吻合显式标出来。
- **`report/board_pins.md` 里的拨码物理位号**（哪一位开关对应 `MODE[1]`）：本篇只引到 `JTAG 00 / QSPI 10 / SD 11，ON=0`（`report/log/issues.md:14088`）与"两档都读 111"（`pl_config_state_jtagmode_2026-10-06.txt:6`），没有再写"板子第几号拨码开关"，因为仓库里那两句话没有给出位号。
- **一次 QSPI 写入到冷上电之间的等待时长**：137 s 是 `program_hw_cfgmem` 的 elapsed（`flash_qspi_2026-10-05.txt:20`），不是"断电到重上"的时间；后者只有"≥10 s 让 RC 放干净"这一个数（`report/acceptance-recipes.md:94`），本篇不合并成一句话。





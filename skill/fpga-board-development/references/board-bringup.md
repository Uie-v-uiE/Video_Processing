# 上板 — 板上身份、烧写与自启、"设了没反应"的分诊

**这一页有两类读数。** 工具侧的（`write_cfgmem`/`program_hw_cfgmem` 的存在与语法、`md5sum` 的报法、
`bootgen` 的产物形状、`fpga -file` 的选项表）不依赖硬件；另一类**只能上板取**：§1 的 IDCODE/ISC 回读能力、
§2 表格"断电之后"那一列的三个行为、§3 的第 2/4/5 步、§4 的全部五步与第 0 步的挂死形态、§6 的计数器读回。
§7 的代价**两类都不需要板子**：占用与时序都是工具侧读数（`report_utilization` 与实现之后的
`report_timing_summary`，见 `constraints-timing.md` §6），只有"板上跑的是哪一版"那一半要板子。
凡属后一类，在你自己的板子上取到读数之前，它只是"怎么取"，不是结论。

## 1. 板上跑哪一版：靠读回来，不靠文件名，也不只靠 md5

**主判据：在 RTL 里放一个版本/构建号寄存器**（一个只读常量端口接到 GPIO 或状态字的高位就行），
上板读回它。它能回答"此刻在跑的这一版是不是我以为的那版"，而文件哈希回答不了——哈希比的是主机上
那个文件，与板子里配置了什么没有因果关系。纯 FPGA 的 ISC 回读、Zynq 的 JTAG 都拿不到比特流内容
（JTAG 能拿的是 IDCODE 与状态），所以"读回版本号"这条路要**在设计里预留**，不是调试时才想起来加。

**设计里有几块可以单独重配（partial bitstream / PR 区域），这条就要两类读数**：
① 每块各自放一个只读构建号，回答"这一块现在是哪一份镜像"；
② 每块再放一个**重配之后会归零重数的自由运行计数器**（易失标记），回答"刚刚动过的是哪一块"。
只有 ① 判不出后者：同一份镜像整片重配时，所有构建号的读数一个都不变——
"变的那块变了、没动的那几块不变"这半句在那种情况下同样成立，所以它是**确认而不是判别**。
真正能红的是 ②：只有被重配的那一块计数从 0 起，其余各块的计数继续往上涨。
这是"合格的判据是一个会随你的改动而变的量"与 I6"判据必须能红"在重配这件事上的直接推论。
一个全局版本寄存器更不用说：它连"哪一块"都分不出来。
运行时那一侧的入口与签名归属在 `pynq-overlay-development` 的 `references/overlay-metadata.md` §4，
它指向的判据就是这一条。

产物侧的指纹记账回答另一个问题——"这个文件是不是那次构建出来的、后来有没有被改过"。
这件事用系统自带的 `md5sum` 就够了，不需要任何工具：

```bash
md5sum build/top.bit build/app.elf > board/fp.txt   # 记：哪个文件、哪次构建、什么哈希
md5sum -c board/fp.txt                              # 问：这几个文件换过没有
```

**这条命令名在 Vivado 的 Tcl 里不存在，但 `exec` 能把它送出去**（本机两条都在同一会话取过）：
裸写 `md5sum probe.txt` → **rc=1 + `invalid command name "md5sum"`**，
并且日志里先有一条 `WARNING: [Common 17-259] Unknown Tcl command 'md5sum probe.txt'
sending command to the OS shell for execution. It is recommended to use 'exec' …`
（**这条 WARNING 在日志里并不挨在它那条命令旁边**：本机那份会话输出里它落在
"上一条 `puts` 的结果"与"`md5sum probe.txt` 这条命令的回显"**之间**，
同一份日志里 `open_hw_manager: Time (s): …` 也跑到了它自己那行回显的前面。
**所以批处理日志里"消息挨着哪条命令"不能用来归属消息**——要归属就自己打带 tag 的 `puts`，
按 tag 找，别按行邻接找）；写成 **`exec md5sum probe.txt` → rc=0**，交回
`af5597c29467a96523a70787c319f4db *probe.txt`（GNU coreutils 那一族的输出格式，前面带 `*` 表示二进制）。
所以"要在工具会话里算哈希"是可行的，只是必须走 `exec`。
**"缺文件时打什么字样"要先说你跑的是哪一种模式**（本机 GNU coreutils 8.32，两臂都自己跑过）：
- **普通模式 `md5sum a.bin b.bin`**：存在的文件只打一行 `<hash> *a.bin`（rc=0）；
  缺的那个多打一行 `md5sum: b.bin: No such file or directory` 且 **rc=1**；
  混合（一有一缺）就只有这两行加 rc=1——**普通模式没有任何 per-file 状态词**，
  既没有 `OK`/`FAILED`，也**没有 `MISSING`**。所以"用 grep 找 MISSING"在这族上永远找不到，
  这条 0 命中的正向对照就是同一次跑里 `-c` 那一臂（下一条）确实打出了状态词。
- **校验模式 `md5sum -c fp.txt`**：每个条目一行状态——`probe.txt: OK`、
  读不到的那条是 `…: FAILED open or read`（前面还跟一行 `md5sum: …: No such file or directory`）、
  值不符的是 `probe.txt: FAILED`，末尾**两条不同的 WARNING**：
  `WARNING: 1 listed file could not be read` 与 `WARNING: 1 computed checksum did NOT match`，rc=1。
  **这两类坏是不同的行，别合成一个"md5 不匹配"**：一条是文件不在，一条是内容变了。
板上那个 rootfs 若是另一族 `md5sum`，它打什么本机没有读数——**先照上面两臂在板上各跑一次**
（一次全存在、一次故意缺一个），把那一族的原文抄进记录，再写解析。
**判"取到了什么对象"用 `file exists`/`file size`/`file mtime`/`file stat` 这一族**——
注意这一族是 ensemble 子命令，**`info commands {file exists}` 查它是空的**
（本包 `SKILL.md` 用法段记过这个盲区）：证明它们在的写法是**真调一次**
（本机在同一些会话里调过 `file exists`（返回 1/0）与 `file size`（返回字节数），
`file stat` 这一条本机没调过，只到这里存在）。
所以要在工具会话里判"是不是的产物"，取 `file mtime` 加 `size` 这一对，
哈希那一步回到 shell 做——同一个形状的另一个落点见 `onchip-debug.md` §3 的 `.ltx` 判据。

三条使用规矩（不照做就会踩）：

- **固定在同一目录跑**（一般就是工程根）。记录里存的是相对路径，换了 cwd 去 `-c`，
  打出来的是 `md5sum: build/top.bit: No such file or directory` + `build/top.bit: FAILED open or read`
  + `md5sum: WARNING: 2 listed files could not be read`（退出码 1），
  看起来像"产物被人改了"，其实只是你在别的目录里。**读的是 `FAILED open or read` 这一句**：
  `md5sum` 不会给你 `MISSING` 这种专门字样，脚本里等它就等于永远等不到。
- 记录文件本身不是 md5 格式时，它打 `md5sum: <文件>: no properly formatted MD5 checksum lines found`。
  这也是"这次对账没有发生"，不是"对不上"。
- `.bit` 文件头里有构建时间一类字段，源码一行不动重跑一次 `write_bitstream`，哈希也可能变。
  第一次用这套记账时先实测一次"重跑会不会变"，再决定把哈希当身份还是只当变更检测。

对账变红的四种原因，分开处理：产物换了（重建过）；产物没换但记录没更新（忘了记）；
路径不是构建真正输出的那个（脚本产物在 `.../runs/impl_1/xxx.bit`，记录写的是 `build/xxx.bit`——
这种记录会悄悄"永远对得上"，因为它一直在比同一个旧文件）；记录被改坏或不是 md5 格式
（上面那条 `no properly formatted` 就是它）。

## 2. JTAG 易失、配置 Flash 持久、运行时 overlay 又是另一套

| 动作 | 效果 | 断电之后 | 副作用与可逆性 |
|---|---|---|---|
| JTAG 下载 PL（硬件管理器 Program Device / xsdb `fpga -file`） | 直接写配置 SRAM | 配置丢失，回到启动介质那一版（**前提**是启动模式引脚真指向那个介质） | 对**芯片**是可逆的；对**系统**不一定：PS 正在访问 PL 从设备时重配，那笔在途事务可能永不返回（互联挂死、内核 oops），下游外设还会吃到管脚抖动。先停 master、释放句柄、确认没人在用这些管脚，再下载 |
| 写 QSPI/配置 Flash（Vivado 硬件管理器 Tcl：`create_hw_cfgmem` + `set_property PROGRAM.FILE` + `program_hw_cfgmem`；镜像由 `write_cfgmem -format` 出 mcs／hex／bin 之一） | 改变上电默认 | 上电自启这一版 | **擦除不可逆**；从此"板上跑什么"由介质决定，需要现场人员同意。**这一族的名字在 Vivado 批处理与 xsdb 两条命令面上的读数不一样，写在表格下面那段，别在 xsdb 里找 `program_hw_cfgmem`** |
| SD 镜像里的启动文件 | 按模式引脚从 SD 起 | 换卡即换版本 | 卡可拔，但镜像内对引导区的写入不可逆 |
| Linux/PYNQ 运行时加载 overlay | 当前会话内生效 | 是否还在，取决于它有没有被登记成开机重放（`/lib/firmware` + device-tree overlay 那套机制），与前三种规则都不同 | 反复下载会重置 PS 侧握着旧句柄的对象 |

**"擦除不可逆"这句话在工具侧是有开关可读的，别只靠自觉**（本机 2025.2.1 `program_hw_cfgmem -help`
原文取到这几条）：这条命令做的事是 "**Erase, blank check, program, and/or verify** the specified
hw_cfgmem object"，**做哪几件由 `hw_cfgmem` 对象上的属性决定**——
`PROGRAM.ERASE`（"Erases the contents of the flash memory when true"，布尔 0/1）、
`PROGRAM.BLANK_CHECK`（编程前查是否已空）、`PROGRAM.VERIFY`，以及
`PROGRAM.ADDRESS_RANGE`：`use_file` 是"只按这次配置文件占的地址去擦/查/写/验"，
**`entire_device` 是"把整片擦/查/写/验一遍"**。
所以"会不会连别的东西一起擦掉"这件事**在命令之前就能数出来**：把这几个属性逐个读回来打印，
`ADDRESS_RANGE` 是 `entire_device` 还是 `use_file` 要写进当次的记录，
而不是等它跑完再后悔。**擦除前能留的退路也在这条命令旁边**：
`readback_hw_cfgmem -all -file <路径>`（§2 下面那份名单里的名字）先把现有 contents 读回成文件，
这一步不做也不改变任何板上状态。
上面那一行"需要现场人员同意"因此不是流程装饰，而是**这条命令会动到这次范围之外的内容**；
属性读数 + 回读文件这两件事都做到，才谈执行。

**`cfgmem` 这一族的名字在两条命令面上的读数**（同一次安装、各自现取，别互相搬）：

- **Vivado 批处理**：裸会话里 `info commands *cfgmem*` 只给 **1** 个（`write_cfgmem`）；
  `load_features labtools`（rc=0）之后同一个通配给 **8** 个：`create_hw_cfgmem`、`current_hw_cfgmem`、
  `delete_hw_cfgmem`、`get_cfgmem_parts`、`get_hw_cfgmems`、`program_hw_cfgmem`、`readback_hw_cfgmem`、
  `write_cfgmem`。**数到 1 不是"这一族不在"，是还没加载**；对照格是
  `load_features memanalysis` 那种不存在的特性名——rc=1，且计数仍然是 8（说明加载失败不会把名单洗掉）。
  **`program_cfgmem` 这个名字不存在**：加载 labtools 之后直接调用得到 `invalid command name "program_cfgmem"`，
  要的那条带 `hw_`。`write_cfgmem -arch bogus` 报 `[Common 17-170] Unknown option '-arch'`
  （`-arch` 属于 `bootgen`，不属于这一族）。
  **三条补充读数**（另一路复核在本机重跑得到，本页按原文记）：
  ① `load_features` 失败时那句 `17-220` 里的 "Available features are: …" **是"还没加载的那些"**，
  不是允许名单——加载过 `labtools` 之后再问一个错名字，清单里就没有它了。逐臂读数与归属在
  `onchip-debug.md` §1 那条 `load_features` 下面，本页不重抄。
  ② 想证明这一族注册上了，除通配计数还有一条更硬的：加载之后**不带参数**调 `program_hw_cfgmem`
  得到 `[Labtoolstcl 44-346] Config mem object incorrect`——这已经不是"没这条命令"的形状。
  ③ `write_cfgmem -help` 的 `Syntax:` 原样是
  `write_cfgmem [-force] -format <arg> -size <arg> [-interface <arg>] [-checksum]
  [-disablebitswap] [-loadbit <arg>] [-loaddata <arg>] [-loadpdi <arg>] [-quiet] [-verbose] <file>`：
  **表里标 Required 的只有 `-format` 与 `-size`**（`-format` 合法值 `[ BIN | HEX | MCS ]`，
  `-size` 那行原文是"Size of memory that is being targeted in M Bytes (must be power of 2)"），
  **而 `-loadbit` 在选项表里写着 "(Optional)"——但本机不给任何 `load*` 就调它，报的是
  `ERROR: [Common 17-161] Invalid option value '' specified for '-loadbit'.` 且不产出文件**
  （两种给法都试过：不带 `-force` 与带 `-force` 都是这同一条 17-161）。
  **也就是"三个 `load*` 里必须给一个"这件事在 `-help` 里没写在 Required 那一列**——
  所以抄脚本时不只别丢 `-size`，`-loadbit "up 0x0 <bit>"`（或 `-loaddata`/`-loadpdi`）
  也必须有，而它的报错会把原因指到一个你压根没写的选项上。
  上面表格里只写了 `-format`，这是第一处会撞的坑。（那一路本机把三种 `-format` 各调过一次，
  但**产物文件没有逐个核过**——真正要的是板侧编程，本机没 flash 也没接板。）
- **xsdb**（本机这个 2025.2.1 的 xsdb 在 `<安装根>/Vivado/bin/xsdb.bat`，随 Vivado 一起装、**不在 PATH 上**）：
  这一族**一个都没有**——`info commands *cfgmem*` 交出空，`cfgmem`、`pcfgmem`、`program_cfgmem`、
  `program_hw_cfgmem`、`write_cfgmem` 逐个查都是 0，直接调用 `program_cfgmem` 与 `program_hw_cfgmem`
  都报 `invalid command name`。**所以"`program_hw_cfgmem` 要 `load_features labtools` 之后才注册"
  那句只属于 Vivado 这一面，在 xsdb 里找它是白费**。这次扫描的正向对照是同一次里
  `targets` 与 `connect` 两条**有名字**——扫描看得见 xsdb 自己的命令面，所以那个空是真的空。
- 两条命令面之间不通用的还有 `program_cfgmem` 这种"名字像但两边都没有"的：判存在要用
  `invalid command name`，不能用一次 `info commands` 的 0（`SKILL.md` §1 第 9 条那条）。

要确认四件事再动配置 Flash（缺一就别动手）：

1. 模式引脚/跳线指向这个介质（写对了但启动模式不对，症状是"刷了没反应"）。
2. 启动镜像的段构成与目标平台一致。**这是平台强相关的**：Zynq-7000 的 `bootgen` BIF 典型三段是
   FSBL（带 `[bootloader]` 属性）+ PL 位流（`[destination_device=pl]`）+ 应用（`[destination_cpu=...]`）；
   ZynqMP/UltraScale+ 的镜像要的是 pmu_fw、bl31/bl32、u-boot 那一套，段名与工具选项完全不同；
   纯 FPGA（没有硬核处理器）根本没有这种镜像，走 `write_cfgmem` 出 MCS/HEX 直接灌 Flash。
   按你手上的板子与工具文档取一次真实形状，别照抄任何一段 BIF。
3. Flash 器件型号、容量、总线宽度与工具里选的一致（型号不匹配时编程"成功"但读不回）。
4. 应用链接地址是启动后真实的运行地址（从 Flash 起与从 JTAG 起，内存映射可以不同；症状是
   "JTAG 跑得好，自启一跑就挂"）。

### 2.1 镜像生成工具自己的形状，以及"生成成功"这句话的分量

这一段不需要板子，在开发机上就能取读数。

- 顶层选项是**裸关键字**，`bootgen -h` 那张表里能看到 `arch`、`image`、`o`、`w`、`read`、`dump`、
  `verify`、`padimageheader`、`process_bitstream` 等；`-arch bogus` 会被拒：
  `Command line parsing failed with code 1`——arch 是要真值的，不是装饰。
- BIF 里的属性名以 `bootgen -bif_help` 打印的那张表为准（本机那张表里有 `bootloader`、
  `destination_cpu`、`destination_device`、`offset`、`fsbl_config`、`partition`、`init`、
  `load` 这些）。要写 BIF 就先把这张表打出来对着抄，而不是对着记忆抄。

一条实测出来的假绿：只写 `all:{ }` 的 BIF 交给 `bootgen -arch zynq -image t.bif -o out.bin`，
它逐字打这三行就完事：

```
[WARNING]: No partition images given
WARNING: -padimageheader was requested, but no images were specified.

[INFO]   : Bootimage generated successfully
```

并产出 2368 字节的文件——里面没有任何可执行段。注意第二行那句 **`-padimageheader`：命令行里没写它
也会出现**，所以它是"没有镜像可pad"的另一句说法，不能读成"命令行里有 `-padimageheader`"。
**而且这条工具的退出码要看你从哪个入口调它**——把两份记录的分歧查成了"两个都对、条件不同"：
同一句 `-arch bogus`（不带 `-image` 也一样）在两个入口上都打同一行
`[ERROR]  : Command line parsing failed with code 1`，
但走 `bin/bootgen.bat` 时 shell 的 `$?` 是 **0**，走 `bin/bootgen`（一个 `#!/bin/bash` 包装脚本）时是 **1**。
本机两次读数：`.bat` 那一臂两条命令（带/不带 `-image`）都 rc=0；包装脚本那一臂直接跑与
接管道 `${PIPESTATUS[0]}` 都 rc=1。**所以"bootgen 的返回码能不能当门"这个问题没有全局答案，
只有"我这个脚本调的是哪一个"的答案**；要可重复就别看返回码，读 stdout 里有没有
`Bootimage generated successfully` 加上产物文件真存在、大小对得上（上面那条 2368 字节的假绿就是这个形状）。
这一条与 `SKILL.md` §2 的 **I5（板上身份要能读回来）与 I6（判据必须能红）** 是同一条读数的两种详略：
改这里要同步改那一处。**（先前这里写"不变量 9"——`SKILL.md` §2 只有 I1…I6 六条，
那个编号不存在；按 §2 的标题"六条不变量"数过。）**

所以：

1. **退出码在这里不是门。** 只能读 stdout：`[INFO]   : Bootimage generated successfully`
   只说明"它写出了一个文件"；出现 `[ERROR]` 或 `[WARNING]: No partition images given` 时
   `bootgen.bat` 那一臂照样返 0（`bin/bootgen` 包装那一臂返 1——见上面那段，两个入口别混用）。
2. 判据是把产物**再读一次**：`bootgen -read <image>` 打分区表。本机对那份空镜像的 `-read` 报
   `[ERROR]  : Number of partitions read is more than number of supported partititon count.`
   （`partititon` 是工具自己的拼写，写脚本去匹配这句话时别"顺手改正"，改正就匹配不上了），
   或者核对分区数/大小与放进去的段一致。
3. 这一层拿到的仍是**产物侧**证据，与"板上跑的是这一版"是两件事（§1）：
   镜像正确 + 启动模式不对 + Flash 没写进去，任何一条都会让板上行为与产物无关。
4. 换平台（Zynq-7000 / ZynqMP / 纯 FPGA）时先重取这张表：段名与选项集合不一样，
   纯 FPGA 那条路根本没有 BIF，走 `write_cfgmem` 出 MCS/HEX（§2 第 2 条那段说明）。

## 3. 上电自检顺序（每步都要一个读数）

1. **"连上了"不是"接上板了"**（本机没有板，这条是把整步的判据重排过）：
   `open_hw_manager` **rc=0**，`connect_hw_server` 也 **rc=0**、交回的是 `localhost:3121`，
   日志里还有一条 `INFO: [Labtools 27-2222] Launching hw_server...`——
   **它自己会把服务拉起来**，所以"连不上先确认服务在不在"这个顺序在这版上不成立：
   三步全绿而一块板都没接。真正的门是下一条读数：
   `get_hw_devices` 在这里交回 **0 个** +
   `WARNING: [Labtoolstcl 44-128] No matching hw_devices were found.`。
   **所以顺序是：先 `connect_hw_server`，再数 `get_hw_devices` 的个数并把个数原样打出来**
   （本机：`rc=0`、`llength` = **0**、`catch` 的 msg 是**空串**——那条 44-128 只在日志里，
   又一次说明"只打 rc 与 msg"会把它吞掉）；个数为 0 时后面所有 `program_hw_*` 都别跑，
   因为**连 `current_hw_device` 在没有设备时也是 rc=0、msg 空**（本机取过），
   它不会替你拦住下一步。
2. **JTAG 起 PS**：初始化 + 内存写读。初始化那一步用的是 Vitis 生成的 `ps7_init.tcl`
   （**`ps7_init` 不是任何控制台的内建命令**，安装树里也没有现成文件；它是构建产物，
   没有它就换一块板子重跑生成），内存写读用 xsdb 的 `mrd`/`mwr`
   （这两个名字在 Vivado Tcl 里判存在要用 `mrd -help`：本机报 `invalid command name "mrd"`，
   裸 `mrd` 同样——这才是"这条路径上没有"。`help mrd` 给的
   `[Common 17-25] No topics matched 'mrd'` 属于另一路 Tcl 帮助系统，不能当 `-help` 的判决）。
   **别只写一个魔数**：单地址回读只证明那一个地址，地址译码错乱、
   行冲突、容量不足、训练边界都在它之外。**"若干"不能当判据——判据要是一个能红的数**，本机给不出
   板上读数，所以这里给的是取法而不是通过值：抽查点数按容量定，**至少取满 8 个地址**
   （首地址、末地址、容量对半处，再把地址的高位依次单独置 1 各取一个——这一族专门打"高位没参与译码"），
   每个地址写"随地址变化的 pattern"再读回；**判据 = 不一致的点数，必须为 0**，
   并且把"取了几个地址、几个不一致"两个数一起记下（只记"全对"下次没法比）。
   读不回先查初始化脚本、时钟与复位这三样，不要往下走。
3. **编 PL**：`launch_runs ... -to_step write_bitstream` 最常见的位置是 Vivado 批处理；硬件管理器与
   PYNQ 的 tcl/驱动流也能完成位流下载，走哪条要看工程约定，不是只有一条路。
4. **下载 PL + 加载应用**，串口出固件的启动行，控制台拿到提示符。
5. **读回版本寄存器**（第 1 节），对上了再开始功能测试；否则你测的是上一版。

## 4. "设了没反应"分诊：先看这笔写有没有返回

**第 0 步（最省钱的一步）**：区分"写了没起作用"与"这笔访问根本没完成"。PL 没时钟、被复位、或
地址段上没有从设备时，PS 侧对 AXI-Lite 的写可能**永远等不到响应**——GP 口没有超时机制，症状是
CPU 卡在那一行、整机僵住或看门狗复位，而不是"值没生效"。所以：先用一次**读**探活（读到东西说明
互联通路活着），给裸机侧的轮询加有界超时，再来谈"位设错了"。

后面五步按顺序做，每步要一个读数，不要跳步猜。症状很像"PL 坏了"的错通常落在第 3、4 步。

| 步 | 问什么 | 怎么看 |
|---|---|---|
| 1 | 写出去的值真的是我以为的那个吗 | 主机侧打印这次写的字；固件回显**从寄存器读回来的**值，不是回显你想写的值 |
| 2 | PL 真的收到了吗 | 状态读回口（GPIO/lane/VIO probe）读回那个字；或 ILA 抓它进流水线的那一拍 |
| 3 | 位序、极性、单位对得上吗 | 把三张清单并排看：RTL 的位选、固件的移位量、位表文档点名的位（把三份清单并排贴出来，逐位核。抓位选用 `grep -nE "\[[0-9]+\]"`；**不要用 `grep -n "'\d\+"`**——本机它只命中带位宽的十进制常数（`8'd255`、`12'd7`），一条位选都抓不到，拿它当"位选清单"会得到一份看起来很干净的空表）。其中"文档有而 RTL 无"和"固件有而 RTL 无"两个方向会被自动点名；**反方向（RTL 用了某位而文档/固件没提）要人自己看清单**。反相位（1=关）与"标志塞低字节 vs 文档写 [8]/[9]"是两大来源 |
| 4 | 收到之后有人用吗 | 在 RTL 里搜这个信号的消费者；被常量传播删掉、连出去没接、宽度被截成 1 位都在这里 |
| 5 | 生效还需要别的条件吗 | 优先级/门控（某个模式绝对压制另一个模式）、使能位、模式锁；这类"设进去但被更高优先级的来源覆盖"必须读代码确认，不能靠重试 |

写错寄存器地址的症状恰恰也是"设了没反应"，而两个只差一位的地址名最容易误判成硬件坏了——先把
"写到哪个地址、从哪读回"这两行代码打印出来核对，再怀疑 PL。

## 5. 在飞构建与产物竞态

- 构建跑着的时候**不要动它的源**：改动会进这一次构建的中途，产物与源码不再对应，报告也解释不了它。
- 不要同名覆盖正在被别的过程读的产物；要新版本就写带时间戳的目录，最后再发布为固定名。
- 并行跑两个构建要保证**三个名字各各不同**：工程目录、日志路径、**发布用的输出名**（共享工程目录会互相覆盖）。
  这三样是三个独立的检查项，别把它们压成"目录不同就行"。
  **这条说的是"两个工程副本 / 两个工具会话"同时跑**；同一个工程里开两个 run（`impl_1` 与 `impl_2`）
  不算这种——它们各有 `.runs/<run>/` 目录（这时"工程目录"那一项本来就是同一个，不成立），
  共享的是源文件与约束，所以那一侧的规矩是
  "在飞期间不要动源"，走 `vivado-build-run.md` §6。
  **但即便在这种"同一工程两个 run"的情形里，第三项仍然会撞**：两个 run 都 `-to_step write_bitstream`
  时各自在自己的目录里出一份 `.bit`，一旦按上一条"发布为固定名"把它们发到同一个目标名，
  后发的那份就顶掉先发的那份——撞的是发布名，不是 run 目录，所以它不会被 `.runs/<run>/` 那道保护 cover 到。
- 构建脚本的退出码要判：`wait_on_run` 之后不看 STATUS 就当成功，是假绿的标准来源。

## 6. 把每道门变成可数的，并且要能读回来

每条会丢弃数据/超时/未命中的路径都配一个**只增计数器**，并接到一个真的能读回来的地方：
Zynq 裸机最常见的是把一个 `axi_gpio` 配成输入（或专门的读回端口），PS 侧按通道选一条状态字读；
PL 独立跑时用 VIO probe 或一个调试 IO。计数器只有配上"读回通路"才算可观测，配了但没引出来等于没配。

之后判据必须能**人为造红**——把阈值压到环境以下，告警位必须亮；抬到顶，必须灭。两条都跑过，这条
判据才算存在。屏上/LED 只画数值不画告警的设计里，告警只能来自串口或读回口，讲的时候别说"会变色"。

## 7. ILA / VIO 的代价

插调试核会改资源占用、布线和时序，某些情况下还会因为综合选项不同而改变被观察对象本身（合并、复制、
优化掉）。**量级不必等到有板子才知道**：`constraints-timing.md` §6 那张三行表给了一个 ILA 加自动
`dbg_hub` 在 7z020 上的跳变（6→1093 个 LUT、8→1810 个 FF），并且记了那个坑——
**核只是 create+connect 时占用纹丝不动**，别把"没变"读成"没插上"。
同一页还给了同一份设计**布线完成后的两臂时序**：没核 WNS 7.865 / WHS 0.212 干净，带核 WNS 3.775、**WHS −0.653、两个 hold 失败端点**，且最差 setup 路径挂在 `dbg_hub` 的 BSCAN 路上（`Requirement` 33.000 ns，不属于你的功能钟域）——这就是下面第 5 条"取证完要重出一版不含调试核的"的实测理由。本节只谈规矩，不替你的设计给数。

1. 先用版本寄存器确认板上在跑哪一版，**再**信 ILA 抓到的东西（不然你在给上一版的行为找解释）。
2. 采样时钟必须与被采信号同域且**一直在跑**：门控时钟停走时什么都抓不到，这时"没波形"会被误读成
   "逻辑没动"。
3. 触发条件设成错误标志或状态跳变，不要设成"跑一会儿看看"；要抓一整帧就用行/帧级触发条件。
4. 采集深度按要看的窗口算，别默认 1024 就够；一次采不全就重跑，成本是整轮构建。
5. 取证完出**不含调试核**的版本再去做任何"已验证"声明；调试核走 JTAG，与别的客户端共享 hw_server。
   **"写类操作（下载、擦写）要独占、只读客户端能否共存"这一条是流程口径，不是本机读数**
   （没板子，两个客户端抢一条链的形状取不到）；所以别把它当"我挂个只读不影响别人"的许可，
   动手前先列出现存占用者（`SKILL.md` §5 那条），把自己的读与别人的写分开排。

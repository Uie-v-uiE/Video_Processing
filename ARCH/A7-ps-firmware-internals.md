# A7 · PS 固件内部（实现级拆解）

这一卷不讲"PS 到底管什么"这种定位问题（那是 `LEARNING/04` 的 4.1 节），只讲**这颗固件在板上是怎么一步一步跑的**：
启动路径的每一次交接、主循环的每一拍、每一条串口命令改到哪一位、每一步读回为什么要两次总线操作、
SD 卡上的一个字节怎么走到 DDR 的哪个地址、断电重上时 FSBL 看了哪几个字段才决定要不要交接。

材料口径：所有行号都是**这份可读树里真打开过的行**；所有读数都是**留档件里的原文**； 凡是我自己算的，算式就写在旁边。没有一处"大概是"。

---

## 1. 固件骨架：一个 1596 行的 main.c 装了哪六件事

`src/ps/main.c` 一共 1596 行（来源：`src/ps/main.c:1596`），文件头那段注释就是这只固件的责任清单：
UDP 视频数据通路整个在 PL，PS 只做控制面与 SD 本地回放（来源：`src/ps/main.c:2`）。
它按行分成六块，后面每一节对应一块：

| 行段 | 装的是什么 | 关键出口 |
|---|---|---|
| `:38-160` 常数与位定义 | 帧几何、两只 GPIO 的基址、每一位的名字 | `FRAME_ADDR`（来源：`src/ps/main.c:46`） |
| `:145-202` 状态影子 | 固件里唯一的"当前设置" | `cur_split`（来源：`src/ps/main.c:145`） |
| `:204-610` 写寄存器与算法/换算 | 整字合成、gamma 曲线、温度编码 | `ctrl_write`（来源：`src/ps/main.c:208`） |
| `:612-1420` 命令面 | token 化与 20 支派发分支 | `dispatch`（来源：`src/ps/main.c:890`） |
| `:1423-1517` 串口收包状态机 | 缓冲、残包、超长、回显 | `rx_fill`（来源：`src/ps/main.c:1478`） |
| `:1519-1596` `main` | 开机八步与主循环六拍 | `while (1)`（来源：`src/ps/main.c:1587`） |

### 1.1 这一站的数据形状 + 出错时看到什么

- **形状**：帧几何是编译进去的三个常数——`FRAME_W` 取 512、`FRAME_H` 取 300、`FRAME_BYTES` 等于 `FRAME_W * FRAME_H * 2`（来源：`src/ps/main.c:38-40`），算出来 512×300×2 = 307,200 B。
- **形状**：PS 片源落 DDR 的第三个 bank，`FRAME_ADDR` 定为 `0x10100000u`（来源：`src/ps/main.c:46`），RTL 侧对应 `PS_DDR_BASE = 32'h1010_0000`（来源：`src/rtl/top/system_top.v:144`），两边各有一份、必须同值（来源：`src/rtl/top/system_top.v:142-143`）。
- **出错**：这两处地址不一致时不会编译失败、不会综合报错，现象是"PS 片源在屏上不动"，因为搬运机读的是另一块内存（来源：`src/rtl/top/system_top.v:143`）；帧宽/高与位流不一致同样是"没有报错的错位"，`system_top` 里那段注释记的就是这个（来源：`src/rtl/top/system_top.v:135`）。

---

## 2. 启动路径：FSBL→app 的每一次交接

### 2.1 两条进入 `main` 的路

同一个 ELF 有两条被点名的路，区别只在"谁把镜像搬到 CPU 会被交接的地方"。

| 路 | 谁搬镜像 | 交接前 PC | 留档 |
|---|---|---|---|
| JTAG 三步链 | `xsdb` 的 `dow` | `PC_BEFORE_CON: pc: 002000cc`（来源：`board/measured/flash_20261006_1936.txt:125`） | 同件第 122 行打 `DOW: ok`（来源：`board/measured/flash_20261006_1936.txt:124`） |
| QSPI 断电自启 | FSBL 的 `LoadBootImage()` | `Handoff Address: 0x002000CC`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:107`） | 下一行 `SUCCESSFUL_HANDOFF`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:109`） |

两条路的 PC 是同一个数 `0x002000CC`，这不是巧合：它是 `_boot` 的链接地址（来源：`report/log/issues.md:14160`）， 也就是 `ENTRY(_boot)`（来源：`src/ps/lscript_ocm.ld:49`）在基址 `0x00200000`（来源：`src/ps/lscript_ocm.ld:31`）之上的偏移，
0x002000CC − 0x00200000 = 0xCC = 204 B。

### 2.2 `_boot` 之前必须有的三个 .S

`build/ps_app.mjs` 把 BSP 的三个启动文件强制链进来：`asm_vectors.S`、`boot.S`、`translation_table.S`（来源：`build/ps_app.mjs:100`）。
它们的分工写得很直白：`asm_vectors.S` 给 `_vector_table` 与各 handler（handler 会把出错指令地址写进 `DataAbortAddr`/`UndefinedExceptionAddr` 两个全局），`boot.S` 的 `_boot` 设 VBAR、六个模式的栈、CPACR+FPEXC、L2/SCU、开 MMU 然后 `b _start`，`translation_table.S` 给 `MMUTable`（来源：`build/ps_app.mjs:86-88`）。

为什么这是硬要求而不是"规范起见"：漏掉它们的三个后果都在这份仓里兑现过——没人写 CPACR 则第一条 VFP 指令陷 Undefined；没人设 VBAR 则异常表落在 0x0 也就是 `.text` 头上，异常来了就去执行恰好摆在那里的代码，症状长得像"板子自己重启了一遍"；MMU 一直关着则 newlib 的 `memcpy` 走半字快路径时发对齐异常，因为 MMU 关掉时非对齐访问一定 fault，`SCTLR.A=0` 的豁免只在 MMU 开着时成立（来源：`build/ps_app.mjs:92-97`）。板上实测的那两个数是 `dfsr=0x801` 与"出错指令在 memcpy 里"（来源：`build/ps_app.mjs:97`）。

同一族病的另一半在编译选项上：`-mno-unaligned-access`（来源：`build/ps_app.mjs:55`）。它挡的是 `-O2` 把 `ld32()` 的四个逐字节读合并成一条 `ldr r6,[r4,#454]`——objdump 里看得见、源码没写错（来源：`build/ps_app.mjs:48-50`）。那个 `ld32` 就是 FAT32 解析里的小端拼字节函数（来源：`src/ps/sd_play.c:79-82`）。

### 2.3 `main()` 的开机八步，逐步

| 序 | 动作 | 原文 | 出处 |
|---|---|---|---|
| 1 | 异常与两级 cache | `Xil_ExceptionInit();` | 来源：`src/ps/main.c:1523` |
| 2 | 打横幅 | `[BOOT] video_pipeline PL-UDP control plane` | 来源：`src/ps/main.c:1528` |
| 3 | 把 GPIO_0 的三态寄存器清 0 | `Xil_Out32(GPIO_TRI, 0x00000000u);` | 来源：`src/ps/main.c:1529`，`GPIO_TRI` = 基址 +0x04（来源：`src/ps/main.c:50`） |
| 4 | 第一次整字落地 | `ctrl_apply();` | 来源：`src/ps/main.c:1530` |
| 5 | 验 axi_gpio_2 通道 1 | `Xil_Out32(CFG_DATA0, 0x1FFu);` | 来源：`src/ps/main.c:1536` |
| 6 | 验这一通道是不是 32 位 | `Xil_Out32(CFG_DATA0, 0x00780000u);` | 来源：`src/ps/main.c:1542` |
| 7 | 验 gamma 窗口（通道 2） | `Xil_Out32(CFG_DATA1, pat);` | 来源：`src/ps/main.c:1556`，图案 0x5A/0x3C 在 `:1555` |
| 8 | 拉 PS-XADC、可选自动播片 | `xadc_init();` | 来源：`src/ps/main.c:1569` |

第 3 步的横幅只在 app 被下载的那一刻打一次，这一点在板级吃过账：单独开串口捕获只会看到 `[SD]` 的周期回声，要看横幅必须一边重下 app 一边抓（来源：`build/board_verify.sh:150-152`）。

第 5、6 步合起来是一次"写图案再读回来"的配套检查，判据不是"读回 0 就算对"——注释自己说了理由：不存在的从设备常常也返回 0，那种判据不会红（来源：`src/ps/main.c:1532-1535`）。
第 6 步的图案故意放在保留段 `[23:9]` 里：探针不许命令硬件，写 `[29]=1` 会让缩放真的跳一次档（来源：`src/ps/main.c:1539-1541`）。
第 7 步是**另一个寄存器**，通道 1 活着不代表通道 2 在（来源：`src/ps/main.c:1552`），图案刻意让 en=0、wr=0，自检不许顺手把 gamma 打开或往表里灌垃圾（来源：`src/ps/main.c:1553`），收尾回影子值而不是回 0（来源：`src/ps/main.c:1558-1559`）。

### 2.4 主循环的六拍

`while (1)` 的全部就是六句：`uart_poll`、`sd_tick`、`sd_recover_tick`、`ps_keepalive`、`gamma_tick`、`temp_poll`（来源：`src/ps/main.c:1587-1594`）。它们的顺序没有硬件依赖，但每一条都必须是"到点才干活、否则立刻返回"：`ps_keepalive` 没到 100 ms 就返回（来源：`src/ps/main.c:267`）、`gamma_tick` 没到 `gm_ms` 就返回（来源：`src/ps/main.c:353`）、`temp_poll` 没到 `TEMP_POLL_MS` 就返回（来源：`src/ps/main.c:817`，常数取 1000u（来源：`src/ps/main.c:107`））、`sd_tick` 没到 `need` 就返回（来源：`src/ps/main.c:1589` 调的那支在 `src/ps/sd_play.c:854`）。
`sd_recover_tick` 这一拍旁边有固件自己的注解：卡插回来自动重挂并接回回放，每 2 s 一次，最多 30 次（来源：`src/ps/main.c:1590`）。

### 2.5 这一站的数据形状 + 出错时看到什么

- **形状**：一次冷启动在串口上留下的固定前缀是 4 行——`[BOOT]` 横幅、`[CTRL]` 两行、`[CFG]` 两行、`[TEMP]` 一行；断电自启那一份完整留档的顺序正是这个（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:112-117`）。
- **出错**：`[CFG!]` 那一行意味着位流里没有新的 axi_gpio_2、或它不是 32 位，缩放/分割那些高位会被吞，elf 与 bit 不配套（来源：`src/ps/main.c:1546-1548`）。地址是按 `%08x` 打的，不带 `0x` 前缀（来源：`src/ps/main.c:1546`）。
- **形状**：`[TEMP] PS-XADC @F8007100 ok`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:117`）里那个 `F8007100` 不是固件写的常数，它是 `cfg->BaseAddress`（来源：`src/ps/main.c:768`）——PS 侧 XADC 的固定地址，PL 零改动。

---

## 3. 串口命令面：从"一个字节进来"到"某一位被写"

### 3.1 收与切为什么必须分开

设计前提写在注释里：`gamma_set` 一次要写 256 项、每项两次 `usleep(5)`，约 2.6 ms **不回主循环**；而 115200 波特下 Zynq 的 RX FIFO 只有 16 字节，约 1.4 ms 的量（来源：`src/ps/main.c:303-307`）。
算一下这两个数：16 B ÷ 11.52 kB/s = 1.388 ms（来源：`src/ps/main.c:306` 的 FIFO 容量 16 与 `src/ps/main.c:206` 的 115200 ⇒ 11.5 KB/s）。 所以人把一整行**粘**进来时，那 2.6 ms 里到达的字节会从 FIFO 漏掉——"命令要发好几次才有反应"这件事真会丢字符的就是这一段（来源：`src/ps/main.c:306-307`）。

处置是把收字节与切派发拆成两个函数：

| 函数 | 职责 | 绝不做的事 | 出处 |
|---|---|---|---|
| `rx_fill` | 把 RX 里的字节搬进 `cmd_buf`，顺手回显 | 不切词、不派发 | 来源：`src/ps/main.c:1478` |
| `uart_poll` | 判残包、按行切、逐行派发 | 不碰寄存器之外的状态 | 来源：`src/ps/main.c:1426` |
| `uart_keepalive` | 给长流程用的保命口，只调 `rx_fill` | 不重入 `dispatch` | 来源：`src/ps/main.c:1514-1517` |

`uart_keepalive` 为什么不干脆调 `uart_poll`：那会在喂帧或写表的中途改参数（重入派发），一条 `gamma 2.2` 打进 `gamma_set` 的中间、或一次 SD 读帧里冒出一整行，都是没人想要的笑话（来源：`src/ps/main.c:1511-1513`）。 它在 SD 侧的调用点只有一个：`feed_cur` 每搬完一段（几 KB）就调一次（来源：`src/ps/sd_play.c:757`），而 sd_play.c 用一条 extern 声明把它引进来（来源：`src/ps/sd_play.c:740`）。
`gamma_set` 的那 256 项循环里同样调它——但调的是 `rx_fill`，注释写得很准："中途只搬 UART 字节不派发，否则粘进来的行会丢字"（来源：`src/ps/main.c:412`）。

### 3.2 缓冲的三个常数

| 常数 | 值 | 为什么是这个值 | 出处 |
|---|---|---|---|
| `CMD_BUF` | 128 | 旧值 48 且**静默截断**：超长行会被啃掉尾巴还当正常行派发 | 来源：`src/ps/main.c:311` |
| `RX_IDLE_MS` | 3000 | 粘贴与脚本连发都在毫秒级不会被误伤，人手打到一个字的停顿在亚秒级 | 来源：`src/ps/main.c:319`，取法注释在 `:318` |
| `T_MAX` | 8 | 最长一条 `gamma auto 1.20 2.60 20 1500` 要 6 个 token，留两个余量 | 来源：`src/ps/main.c:626`，理由在 `:620-625` |

`T_MAX` 那段还有一句实话：tokenize 是**静默截断**的，超出上限的参数不会被看见，于是"我明明设了步长，它却按默认步长走"（来源：`src/ps/main.c:622-624`）——这是 `#67` 禁止的"收了但什么都不做"。而真正的长度上限其实由缓冲区管：那一段说"48 字节里塞不下 9 个有内容的 token"（来源：`src/ps/main.c:625`），这句写的是**旧**缓冲 48 的量，`CMD_BUF` 抬到 128（来源：`src/ps/main.c:311`）之后这句的算术前提已经变了，但字面还留在文件里。

### 3.3 一个字节进来之后走的三条支

`rx_fill` 的循环体只有三段：每收一个字节都重设残包时基（来源：`src/ps/main.c:1482`）；`CR` 折成 `LF`（来源：`src/ps/main.c:1483`），于是行分隔认 CR 也认 LF，终端发 LF/CR/CRLF 都能用（来源：`src/ps/main.c:1457`）；行尾支与载荷支各自判界。

行尾支的判界是 `#167` 补的一刀，症状写得非常具体：折 CR 之后一行 "CRLF" 会走**两次**"追加行尾"，载荷支有界而换行支没界，127 个载荷字节 + CRLF 时第一次写 `cmd_buf[127]`（合法，最后一格）令 `cmd_len=128`，第二次写 `cmd_buf[128]` —— **越界一字节**，`cmd_len` 变 129，之后派发那两个 `for (i < cmd_len)` 会读到数组外一格（来源：`src/ps/main.c:1485-1492`）。
修完的写法是换行支也判界，行满就不再追加，多出来的那个行尾被丢掉（来源：`src/ps/main.c:1493`）。
板级指纹在 `board/cmd_overflow_probe.sh` 的 O1/O2 两个夹逼位（来源：`src/ps/main.c:1492`），这支脚本自己说它"只夹逼、不修复"（来源：`board/README.md:96`）。

超长行的报告只报一条：`cmd_toolong` 这个旗标置过之后不再刷第二遍（来源：`src/ps/main.c:1501-1505`），而每派发完一行把它清零，新的一行重新允许报一次（来源：`src/ps/main.c:1472`）。

### 3.4 残包（半行）为什么要丢

半行留在缓冲区里可以留到永远——于是脚本发断或终端抖一下之后，"我敲的下一条命令"会与那半行拼成一句谁都没敲过的东西，症状是"板子执行了一句我没打过的话"，注释直接说这是最难查的一类（来源：`src/ps/main.c:315-317`）。

`uart_poll` 的处置有两条，都是被用户报出来的现象逼出来的（来源：`src/ps/main.c:1438-1443`）：

- 只丢"最后一个行尾之后"的那段，写完的行照旧执行（来源：`src/ps/main.c:1444-1451`）；原来这里是直接把整个 `cmd_len` 清 0，而按行派发在这段**之后**才跑，于是缓冲里已经写完的行会陪着尾部残包一起被扔掉（来源：`src/ps/main.c:1439-1440`）。
- 消息改成 **ASCII 打头**：中文提示在 cp936/GBK 的 Windows 控制台里渲染不出来，看着就是一长串空白（来源：`src/ps/main.c:1441-1443`）。打出来的原话是 `[CMD!] dropped %d trailing byte(s): line unfinished for %u ms`（来源：`src/ps/main.c:1447`）。

### 3.5 四个小解析件

| 件 | 语义 | 关键约束 | 出处 |
|---|---|---|---|
| `ci_eq` | 大小写不敏感的**等值** | 两边都折成大写比，走到 0 才判相等 | 来源：`src/ps/main.c:640` |
| `ci_pre` | 大小写不敏感的**前缀** | 只比前缀长度，后面有没有尾巴都算命中 | 来源：`src/ps/main.c:650` |
| `strict_int` | 严格十进制 | 可带 +/-，必须整串吃完；`v > 100000` 直接判 0，因为本文件最大合法值是帧号 4398 | 来源：`src/ps/main.c:661`，那条界在 `:668` |
| `tokenize` | 按空白切 token | `n < T_MAX` 就停，多余参数看不见 | 来源：`src/ps/main.c:677` |

`strict_int` 那条界值 100000 旁边写的"本文件里最大合法值是帧号 4398"（来源：`src/ps/main.c:668`）与卡上实测的 `frames=4398`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:122`）是对得上的：4398 = 8×512 + 302（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:130-131`，前 8 段各 512 帧、第 9 段 302 帧）。

### 3.6 派发的顺序就是语义：前缀先到先赢

`dispatch` 的开头不是动词表，而是一条裸位串的兜底：先 `parse_bits(tk[0], &en)`，只有在**整行只有一个 token** 且数出位来时才按 `pipe` 处理（来源：`src/ps/main.c:896-897`）。
往后是 `PIPE`→`TH`→`SRC`→`ZOOM`→`BILIN`→`OSD`→`ROT`→`SPLIT`→`GAMMA`→`FRAME`→`SD`→`PLAY`→`STOP`→`FILL`→`ECHO`→`AUTOPLAY`→`TEMP`→`STAT`/`STATUS`→`HELP`/`?`（来源：`src/ps/main.c:899`、`:911`、`:921`、`:932`、`:983`、`:1005`、`:1029`、`:1095`、`:1204`、`:1258`、`:1265`、`:1321`、`:1344`、`:1349`、`:1350`、`:1363`、`:1370`、`:1371`、`:1392`）。

这个顺序有一处必须知道的后果：**`ci_pre` 是前缀匹配**。 `bilin` 与 `osd` 走的是 `ci_pre(tk[0], "BILIN")` 与 `ci_pre(tk[0], "OSD")`，注释自己说明"先到先赢"（来源：`src/ps/main.c:1253-1254`），所以那两处后面不再放任何"待接"分支——一条永远走不到的桩会把下一个查 bilin 的人引到 PL 侧去（来源：`src/ps/main.c:1256`）。

参数取法在这份表里出现 8 次，是同一段五行式的写法：`const char *arg = (nt >= 2) ? tk[1] : tk[0] + N;`——`N` 就是动词字母数：`TH` 取 2（来源：`src/ps/main.c:914`）、`SRC` 取 3（来源：`src/ps/main.c:926`）、`ZOOM` 取 4（来源：`src/ps/main.c:937`）、`BILIN` 取 5（来源：`src/ps/main.c:984`，旁边注明"BILIN 是 5 个字母"）、`OSD` 取 3（来源：`src/ps/main.c:1011`）、`GAMMA` 取 5（来源：`src/ps/main.c:1206`）、`FRAME` 取 5（来源：`src/ps/main.c:1259`）、`ECHO` 取 4（来源：`src/ps/main.c:1351`）、`AUTOPLAY` 取 8（来源：`src/ps/main.c:1364`）。
这种"按下标取尾巴"曾经数错过一位：老代码在 `SRC0/SRC1` 那种粘着写法上"取尾字符"时数错过一次（`BILIN1` 那次），所以 `SRC` 这一支改成整串交给 `strict_int`，不再按下标取字符（来源：`src/ps/main.c:922-925`）。

### 3.7 这一站的数据形状 + 出错时看到什么

- **形状**：一行 = 动词 + 至多 3 个参数、大小写不敏感（来源：`src/ps/main.c:613`），最多 8 个 token（来源：`src/ps/main.c:626`），行尾 CR/LF/CRLF 都认（来源：`src/ps/main.c:1483`）。
- **出错**：`[CMD] 不认: <整行>` 之后紧跟一次完整 help（来源：`src/ps/main.c:1467-1468`）。`dispatch` 返回 −1 才走这条路（来源：`src/ps/main.c:1393`），其余每条支都返回 0。
- **出错**：`[CMD!] 这行超过 %d 字节，多出来的丢掉（不是没收到，是太长）`——报的是 `CMD_BUF - 1` 这个数（来源：`src/ps/main.c:1503-1504`），按 128 算就是 127。
- **形状**：一条命令敲下去只有三种结局——写了位（回显带着写进去的值）、明确拒绝（一句话说清该敲什么且一个寄存器都不动）、不认；没有"收了但什么都不做"的第四种（来源：`report/commands.md:18-19`）。

---

## 4. 命令总表：动词、参数、改了哪几位、回声是什么

表里的"改的位"全部指**最终落到哪只从设备的哪一个位段**；`gpio_o` = `0x41200000` 那条 32 位整字（来源：`src/ps/main.c:48-49`），
`cfg1` = `0x41220000` 通道 1（来源：`src/ps/main.c:77-78`），`cfg2` = 同基址 +0x08 的 gamma/温度窗口（来源：`src/ps/main.c:96`）。
所有写位的动作最后都汇到同一个合成式（第 5 节），表里只说"哪个影子变量被改"。

| # | 写法 | 动的影子变量 → 位段 | 成功回声（原文） | 拒绝回声（原文） | 出处 |
|---|---|---|---|---|---|
| 1 | 裸 9 位串 | `cur_sel` → cfg1[8:0] | `[PIPE] sel=%03x 生效:` | 5 位只回等价九位、不写位 | 来源：`src/ps/main.c:896-897` |
| 2 | `pipe <9 位>` | `cur_sel` → cfg1[8:0] | 同上 | 长度 6/7/8 一律拒 | 来源：`src/ps/main.c:899-909` |
| 2b | `pipe show` | 不改 | `[PIPE] sel=%03x 生效:` | — | 来源：`src/ps/main.c:900` |
| 3 | `th <0..255>` / `TH80` | `cur_thr` → gpio_o[15:8] | `[CTRL] AXI_GPIO=0x%08x sel=%03x thr=%d` | `[TH] 要跟十进制 0..255` | 来源：`src/ps/main.c:911-919` |
| 4 | `src auto` | `cur_mode_ovr=0` → gpio_o[24:23] + 翻 [22] | `[SRC] 已钉住 自动（控制权交还按键环）` | — | 来源：`src/ps/main.c:927` |
| 4b | `src 0` | `cur_src=0` → gpio_o[16]；模式 TEST=2 | `[SRC] 已钉住 %s（mode=%u；长按 KEY1 一次即交还给按键环）` | `[SRC] 只认 auto / 0=图卡 1=网络 2=SD` | 来源：`src/ps/main.c:921-930`、`:719-722` |
| 4c | `src 1` | `cur_src=1`；模式 ETH=1 | 同上 | — | 来源：`src/ps/main.c:723-726` |
| 4d | `src 2` | `cur_src=1` + `sd_play(1)` + 模式 SD=3 | 拒绝时先回 `[SD] play refused: %s` | — | 来源：`src/ps/main.c:727-731` |
| 5 | `zoom on/off` / `ZOOM1` | `cur_zoom` → gpio_o[17] | `[CTRL] AXI_GPIO=0x%08x` 两行 | — | 来源：`src/ps/main.c:939-942` |
| 5b | `zoom auto` | `cur_zman=0` → cfg1[29]=0 | `[CTRL]   zoom_step=%d %s (%s)` | — | 来源：`src/ps/main.c:943` |
| 5c | `zoom fit [0/1]` | `cur_split` 的 bit31 → cfg1[31] | `[ZOOM] fit=%d（%s；关掉之后回到%s）` | `[ZOOM] fit 只认 0 或 1（1 = 倍率跟着角度走）` | 来源：`src/ps/main.c:944-960` |
| 5d | `zoom <倍率>` | `cur_zsel`→cfg1[28:26]、`cur_zman=1`→[29] | `[ZOOM] %s → 最近档 %s（八档：%s` | `[ZOOM] 不认的参数` | 来源：`src/ps/main.c:962-981` |
| 6 | `bilin on/off/show` | `cur_bilin` → gpio_o[19] | `[BILIN] bilin=%s` | `[BILIN] 只认 on/off（0/1）或 show` | 来源：`src/ps/main.c:983-1003` |
| 7 | `osd on/off/show` | `cur_osd` → gpio_o[20]（**反相**） | `[OSD] osd=%s` | `[OSD] 只认 on/off（0/1）或 show` | 来源：`src/ps/main.c:1005-1026` |
| 8 | `rot auto [0/1]` | bit9（+ 可能顺带 bit[12:10]=2 与 bit31） | `[ROT] auto=1%s` | `[ROT] auto 只认 0 或 1` | 来源：`src/ps/main.c:1056-1090` |
| 8b | `rot speed <0..7>` | `cur_split` bit[12:10] → cfg1[12:10] | `[ROT] speed=%d 度/帧` | `[ROT] speed 只认 0..7` | 来源：`src/ps/main.c:1045-1055` |
| 8c | `rot show` | 不改 | `[ROT] auto=%u speed=%u deg/frame %s` | — | 来源：`src/ps/main.c:1038-1044` |
| 9 | `split <0..100>` | bit[22:13]=`px`、清 bit23 | `[SPLIT] %d%% -> pos=%u/%u（%s；manual；` | 通用拒绝那一句 | 来源：`src/ps/main.c:1185-1196` |
| 9b | `split px <n>` | bit[22:13]、清 bit23 | `[SPLIT] pos=%u px = %u%%%s（manual）` | `[SPLIT] px 只认 0..%u（当前是%s空间）` | 来源：`src/ps/main.c:1172-1183` |
| 9c | `split screen` / `split video` | bit24 + 缝位按百分比换空间 | `[SPLIT] %s：缝在%s里扫，pos=%u/%u = %u%%%s%s` | 通用拒绝 | 来源：`src/ps/main.c:1155-1170` |
| 9d | `split auto/manual` | 置/清 bit23 | `[SPLIT] auto：缝在 [%u..%u]/16 宽度之间自动扫` | — | 来源：`src/ps/main.c:1116-1129` |
| 9e | `split swap/follow/marker <0/1>` | bit25 / bit24 / bit30 | `[SPLIT] %s=%d（%s）` | `[SPLIT] %s 只认 0 或 1` | 来源：`src/ps/main.c:1130-1148` |
| 9f | `split show` | 不改 | `[SPLIT] pos=%u/%u（%s） = %u%% %s%s%s marker=%s` | — | 来源：`src/ps/main.c:1105-1115` |
| 10 | `gamma <1.00..3.00>` | cfg2 的 en[31]/data[29:22]/idx[21:14]/wr[30] + [13:8] | `[GAMMA] g=%d.%02d mono_bad=%d first=%d last=%d` | `[GAMMA] 要 off / 1.00..3.00（或 100..300），收到的是 \"%s\"` | 来源：`src/ps/main.c:1244-1251`、`:424` |
| 10b | `gamma off` | 只清 cfg2[31] 使能，表保留 | `[GAMMA] off（PL 逐位旁路，表保留）` | — | 来源：`src/ps/main.c:385-393` |
| 10c | `gamma auto [lo hi step ms]` | 同上，但周期推进 | `[GAMMA] auto：%d.%02d..%d.%02d，每 %d ms 走 %d.%02d` | `[GAMMA] auto 的账：100<=lo<hi<=300、0<step<=hi-lo、ms>=200` | 来源：`src/ps/main.c:327-344`、`:1225-1242` |
| 10d | `gamma manual` / `on` / `show` | `gm_auto=0` / 用当前或 2.20 / 不改 | `[GAMMA] auto 停了，停在 g=%d.%02d` | — | 来源：`src/ps/main.c:1210-1224` |
| 11 | `frame <n>` / `FRAME12` | 读 SD → `ps_publish` 翻 gpio_o[18]；再 `ctrl_set_src(1)` | 无专属回声，`[CTRL]` 两行是它的回声 | `[SD] frame 要跟十进制帧号`、`[SD] frame %d failed: %s` | 来源：`src/ps/main.c:1258-1263` |
| 12 | `sd` | 挂载，不改位 | `[SD] FAT32 part_lba=%d spc=%d`（由 `sd_status` 打） | `[SD] mount failed: %s` | 来源：`src/ps/main.c:1317-1318` |
| 12b | `sd files` | 不改 | `[SD] %u file(s), %u frame(s) total` | `[SD] files: 卡还没挂载（先敲 sd）` | 来源：`src/ps/main.c:1271-1281` |
| 12c | `sd file <n>` | `sd_show(first)` → 翻 [18] | `[SD] file #%u %s (%u frame(s)) first=%u` | `[SD] file 只认 0..%u（不认的写法不改任何状态；先看 sd files）` | 来源：`src/ps/main.c:1282-1298` |
| 12d | `sd remount` | 清驱动 `IsReady` 后重挂 | `[SD] remount ok` | `[SD] remount failed: %s` | 来源：`src/ps/main.c:1299-1312` |
| 13 | `play` / `play 1` | `ctrl_set_src(1)` → gpio_o[16]=1 | `[SD] playing (stop / play 0 结束; ETH 有流时会自动让位)` | `[SD] play 只认 0/off/stop 或 1/on（不带参数=开播）` | 来源：`src/ps/main.c:1321-1342` |
| 13b | `play 0/off/stop`、`stop` | `sd_play(0)` | `[SD] stopped at frame %d` | — | 来源：`src/ps/main.c:1328-1331`、`:1344-1348` |
| 14 | `fill` | 直写 DDR 一帧 + `ctrl_set_src(1)` + 翻 [18] | 无专属回声，只有 `[CTRL]` 两行 | — | 来源：`src/ps/main.c:692-709`、`:1349` |
| 15 | `echo [0/1]` | **不改任何寄存器**，只改会话旗标 | `[ECHO] %s（会话内开关；重新下载固件会回到默认 off）` | `[ECHO] 只认 0 或 1` | 来源：`src/ps/main.c:1350-1362` |
| 16 | `autoplay 0/1` | 不改寄存器，只改 `autoplay` | `[SD] autoplay %s (only affects the next boot)` | `[SD] autoplay 要跟 0 或 1` | 来源：`src/ps/main.c:1363-1369` |
| 17 | `temp` | 刷 cfg2[7:0] 的 BCD | `[TEMP] degC=%s%d.%02d raw=0x%04x vccint=%dmv` | `[TEMP] 读不到（开机那行 [TEMP] 说了为什么）raw=NA` | 来源：`src/ps/main.c:853`、`:881` |
| 17b | `temp th <0..200>` | 改会话阈值 | `[TEMP] th=%dC` | `[TEMP] th 要跟十进制 0..200（°C），已退回 85` | 来源：`src/ps/main.c:842-851` |
| 18 | `stat` / `status` | 不改 | `[STAT] ctrl thr=%d src=%d zoom=%d bilin=%d zsel=%d zman=%d pub=%d` | — | 来源：`src/ps/main.c:1371-1390` |
| 19 | `help` / `?` | 不改 | 多行语法表 | — | 来源：`src/ps/main.c:1392`、`:1396-1420` |

### 4.1 这张表里三处"看着像坑、其实是设计"

**其一：`pipe` 的长度只收 9 与 5。** `parse_bits` 数到第 10 个字符就退（来源：`src/ps/main.c:583`），收尾既不是 5 也不是 9 也退（来源：`src/ps/main.c:587`）。
5 位给到时**一个位都不写**，只把等价九位算出来印给他看（来源：`src/ps/main.c:478-489`），翻译表是 `legacy_to_sel`：invert 从 bit4 挪到 bit1、binary 从 bit1 挪到 bit5（来源：`src/ps/main.c:460-469`）。
6/7/8 一律拒的理由写得很具体——老写法把 `pipe 00001100`（8 位）当成"9 位前面补一个 0"，于是用户以为自己设的和屏上显示的是两件事（来源：`src/ps/main.c:573-575`）。
打印顺序必须与 `parse_bits` 同侧（第 0 个字符 = 第 0 位 = gray），反过来打给出的是镜像串，照着敲会开出完全不同的几级，`pipe_len_check` 的 B 段就是拿这个当 FAIL 的（来源：`src/ps/main.c:474-476`）。

**其二：`zoom 1` 与 `zoom 1.0` 是两件事。** 前者沿用 V7 的开关语义（`ZOOM1` = 开呼吸，来源：`src/ps/main.c:934-936`），后者才是"回到 1.00 倍"。
这条重叠不是注释，它被印在拒绝消息里（来源：`src/ps/main.c:979-980`），因为 r53 第一次跑电池就是拿 `zoom 1` 当"回到 1.0x"用，结果把呼吸又打开了（来源：`src/ps/main.c:936`）。
倍率解析 `zoom_parse_x100` 是纯整数：小数最多两位、整数部分上限 999，最终只认 `*out <= 400`（来源：`src/ps/main.c:538`），理由是不为一条串口命令拖进 libm（来源：`src/ps/main.c:523-524`）。
落档用 `zoom_step_near` 拿 `ZOOM_X100` 比距离取最近档（来源：`src/ps/main.c:544-554`），八档表是 25/33/50/75/100/133/150/200（来源：`src/ps/main.c:187`）。

**其三：`split 100` 会被夹到 1023 并明说夹了。** 缝位只有 10 位（来源：`src/ps/main.c:124`），而屏幕宽 1024（来源：`src/ps/main.c:142`），于是 100% 算出的 1024 左移 13 位等于 0x800000 = bit23 = 自动扫描位（来源：`src/ps/main.c:126`）。
两种症状都在板上复现过：`split 100` 这条写口紧接着 `&= ~SPLIT_AUTO_BIT` 会把误置的 auto 清掉，留下的是**缝位变成 0**——要"整屏处理图"得到"整屏原图"，而回显还写着 pos=1024/1024 100%；`split video` + `split px 512` 再 `split screen` 这条写口**不清 auto**，于是缝跳到第 0 列 + 自动扫描悄悄开起来，回显还说"auto 仍开着"（来源：`src/ps/main.c:127-132`）。
现在的夹法交给 `split_pos_clamp`，返回 1 表示夹过、调用方必须在回显里说出来（来源：`src/ps/main.c:162-169`）；百分比回声那个数是由**存进去的值**反算的，不是回显用户输入的 pct（来源：`src/ps/main.c:1190-1191`），所以 30% 会念成 29%、100% 念成 99%（来源：`report/commands.md:203`、`:288`）。

### 4.2 这一站的数据形状 + 出错时看到什么

- **形状**：每条命令最多三种出口，写位的那条一定带 `[CTRL]` 两行——第一行是 gpio_o 的整字与影子值，第二行是缩放档位与"此刻是手动还是呼吸"（来源：`src/ps/main.c:232`、`:237-238`）；`stat` 的字段顺序就是固件那条 `xil_printf`，字段一个不许少、也不许往前插，因为串口电池与 `uart_cmd_check.mjs` 都按前缀解析（来源：`src/ps/main.c:1372-1375`）。
- **出错**：`[GAMMA!] 曲线自检没过（表已写入但**不要**用它演示）`——判据是 `bad != 0u || first != 0u || last != 255u`（来源：`src/ps/main.c:426-427`）；曲线本身是 `out = 255·(in/255)^(1/γ)` 四舍五入（来源：`src/ps/main.c:375-383`），γ=1.00 时表恒等（来源：`src/ps/main.c:375`）。
- **出错**：`[TEMP!] raw=%04x 译出来 %s%d.%02d °C 不像一次真实转换 ⇒ `（来源：`src/ps/main.c:885`）；认不出的 token 一律"不改任何状态"，`sd file` 那一条把这条写在拒绝消息里（来源：`src/ps/main.c:1285-1286`）。

---

## 5. AXI GPIO：写是一张整字，读要两次总线操作

### 5.1 三只从设备、两只控制字、一个窗口

| 从设备 | 基址 | 方向 | 固件里的名字 | RTL 里的名字 |
|---|---|---|---|---|
| axi_gpio_0 | `0x41200000`（来源：`src/ps/main.c:48`） | 输出 32 位 | `GPIO_DATA` = +0x00（来源：`src/ps/main.c:49`）、`GPIO_TRI` = +0x04（来源：`src/ps/main.c:50`） | `gpio_o`（来源：`src/rtl/top/system_top.v:264`） |
| axi_gpio_1 | `0x41210000` | 输入 32 位（只读健康值） | 固件不碰它，只有 `health_read.mjs` 读（来源：`src/host/health_read.mjs:39`） | `gpio1_i`（来源：`src/rtl/top/system_top.v:247`） |
| axi_gpio_2 | `0x41220000`（来源：`src/ps/main.c:77`） | 双通道 ×32 位输出 | `CFG_DATA0` = +0x00（来源：`src/ps/main.c:78`）、`CFG_DATA1` = +0x08（来源：`src/ps/main.c:96`） | `gpio_cfg1_o` / `gpio_cfg2_o`（来源：`src/rtl/top/system_top.v:268`） |

三个基址是构建脚本钉死并回读校验的：`assign_bd_address -offset $want` 分别给 0x41200000 / 0x41210000 / 0x41220000（来源：`build/tcl/build_system_axigpio.tcl:244-246`），随后逐只比对（来源：`build/tcl/build_system_axigpio.tcl:258`），打出来的行形如 `ADDR_LOG $cell want=$want got=$got num_ok=`（来源：`build/tcl/build_system_axigpio.tcl:270`），对不上就 `ADDRESS PINNING FAILED` 并退出（来源：`build/tcl/build_system_axigpio.tcl:274`）。
比对必须在**数值**上做：这个属性经数字一走就显示成十进制，0x41200000 变成 1092616192，字符串比对必然红（来源：`build/tcl/build_system_axigpio.tcl:264-265`）。
为什么地址要硬编码：手工链接的 BSP 不会重新生成 `xparameters.h`，地址变了不会编译失败，只会"写了没反应"（来源：`src/ps/main.c:72-73`）。

### 5.2 `ctrl_write` 的合成式：一张位域表配一行代码

```
v = ((u32)cur_thr << 8) | ((u32)cur_src << 16)
  | ((u32)(cur_zoom ? 1 : 0) << 17) | (pub_lvl << PUBLISH_BIT)
  | ((u32)(cur_bilin ? 1 : 0) << BILIN_BIT)
  | ((u32)(cur_osd ? 0 : 1) << OSD_OFF_BIT)
  | ((cur_mode_ovr & 3u) << MODE_CODE_BIT) | (mode_tog_lvl << MODE_TOG_BIT);
```

上面这五行就是 `gpio_o` 的整字合成（来源：`src/ps/main.c:214-218`），写完是**一次** `Xil_Out32(GPIO_DATA, v);`（来源：`src/ps/main.c:219`）。
`[4:0]` 那五位是 V7 效果的旧位置，**保留但恒写 0**——PL 侧那个入口已经删了；位还占着是因为整字是 32 位，位序一改，`set_src.tcl` 与 `health_read.mjs` 这些按位写的工具就全错位（来源：`src/ps/main.c:211-213`）。
`OSD_OFF_BIT` 为什么是 20：`gpio_o` 的空位只有 20/21/25，其余各有主人（来源：`src/ps/main.c:55-56`）。
反相极性的理由：写 1 = 关掉叠层，复位 = 有 OSD，这样"忘了初始化"不会变成干净画面（来源：`src/ps/main.c:53-54`），默认影子值取 `cur_osd = 1`（来源：`src/ps/main.c:191`）。

同一个函数还写第二只字（来源：`src/ps/main.c:223-225`）：低 9 位是效果选择、`[28:26]` 是缩放档、`[29]` 是手动旗标、`GEOM_MASK` 那 19 位是几何控制字（来源：`src/ps/main.c:220`）。
名字必须看清：`CFG_DATA0` 就是 RTL 的 `gpio_cfg1_o`，gamma 窗口是 `CFG_DATA1(+0x08)`，两个名字差一位，写错字的症状恰恰是"设了没反应"，最容易误判成 PL 坏了（来源：`src/ps/main.c:221-222`）；RTL 侧同一句警告是"别写成 gpio_cfg2_o"（来源：`src/rtl/top/system_top.v:267`）。

### 5.3 19 个几何位拼进 PL 的那一束

PS 侧一个整数 `cur_split` 里的位，到顶层要重排成 19 位端口，拼接式是这一行：

```
.split_ctl({gpio_cfg1_o[31], gpio_cfg1_o[12:10], gpio_cfg1_o[9],
            gpio_cfg1_o[30], gpio_cfg1_o[25:23], gpio_cfg1_o[22:13]}),
```

上面就是 RTL 原文（来源：`src/rtl/top/system_top.v:274-275`），它把 cfg1 的位**倒着**收成 `split_ctl[18:0]`：`[9:0]=pos_px`、`[10]=auto_en`、`[11]=follow`、`[12]=swap`、`[13]=marker_off`、`[14]=rot_auto`、`[17:15]=rot_speed`、`[18]=zoom_fit`（来源：`src/rtl/top/pl_video_top.v:49-50`）。
这 19 位在 PL 里过的是**同一条** `snap_cross`（来源：`src/rtl/top/pl_video_top.v:51`）；固件侧的 `GEOM_MASK` 由 `SPLIT_MASK | ROT_AUTO_BIT | ROT_SPEED_MASK | ZOOM_FIT_BIT` 拼出（来源：`src/ps/main.c:159`）。
为什么挤进同一个字而不新开一条跨域路：新开一条就要多一对 bus/toggle 同步器，而"一个发射触发器扇出到两组目的域"正是 CDC-11 Critical 的签名（来源：`src/ps/main.c:149-152`）。
位图现在有三处读者——`main.c` 的宏、`pl_video_top` 的端口注释、台账 #70 追加——改任何一处必须一次改完（来源：`src/ps/main.c:153-154`）。

`gpio_o` 的其它位也各有归口：`threshold` 接 `[15:8]`、`src_sel` 接 `[16]`（来源：`src/rtl/top/system_top.v:264`），`zoom_en` 接 `[17]`（来源：`src/rtl/top/system_top.v:280`），`bilin_en_axi` 接 `[19]`（来源：`src/rtl/top/system_top.v:286`），`osd_off_axi` 接 `[20]`（来源：`src/rtl/top/system_top.v:287`），`ps_publish` 接 `[18]`（来源：`src/rtl/top/system_top.v:288`），`mode_ovr` 接 `[24:23]`、`mode_ovr_tog` 接 `[22]`（来源：`src/rtl/top/system_top.v:293`），`gapclr_sel` 接 `[26]`（来源：`src/rtl/top/system_top.v:203`）。

### 5.4 两次写：翻转位协议

三处命令必须写两次寄存器，而且**顺序就是这条改动的全部风险**。

**其一，片源模式。** 像素域看到的是一根翻转位 + 一个两位码，它在翻转沿走到 3 级链的末尾那一刻才采码 ⇒ 码必须在沿之前就已经稳定；一次 `Xil_Out32` 同时改码和翻位，对面读到的可能是"新码 + 还没认的沿"或"旧码 + 已认的沿"，覆盖就白丢了，现象是串口回显成功、屏上没变（来源：`src/ps/main.c:503-507`）。
所以 `ctrl_publish_mode` 是两笔：`(void)ctrl_write();` 只更新码、沿保持原值（来源：`src/ps/main.c:511`），然后 `mode_tog_lvl ^= 1u;` 再写第二笔才翻沿（来源：`src/ps/main.c:512-513`）。

**其二，gamma 表项。** PL 看的是 `wr` 的**边沿**而不是电平（来源：`src/rtl/video/gamma_lut.v:5`，端口注释写着"**翻转位**，不是脉冲（脉冲跨不到本域）"（来源：`src/rtl/video/gamma_lut.v:12`）），
所以 `gamma_put` 先摆地址与数据、`wr` 不动（来源：`src/ps/main.c:368`），`usleep(5)`，翻 `gm_w ^= GM_WR;`（来源：`src/ps/main.c:370`），再整字写第二次（来源：`src/ps/main.c:371`），再 `usleep(5)`（来源：`src/ps/main.c:372`）。
两项之间必须 usleep：AXI 连发的间隔可以短到一个像素拍都不到；5 µs ⇒ 256 项约 2.6 ms（来源：`src/ps/main.c:285-287`）。这条约束被明写为"真实的，别删"（来源：`src/ps/main.c:287`）。
手工在 `xsdb` 里写一项同样要两次：只写一次 PL 不会动，这不是坑，是协议（来源：`report/commands.md:328-331`）。

**其三，发布脉冲。** `ps_publish` 就是 `pub_lvl ^= 1u;` 再走一次不出声的 `ctrl_write`（来源：`src/ps/main.c:244-245`）。
它不调 `ctrl_apply` 是修过的账：原来直接调 `ctrl_apply`，于是 30 fps 的回放每秒往串口推约 2 KB（115200 只有 11.5 KB/s，而 `xil_printf` 是轮询等 TX 的阻塞实现），板上实测 PLAY 10 s 收回 28549 B 全是 `[CTRL]` 行（来源：`src/ps/main.c:205-207`）。
算一下那句"约 2 KB"：每帧 2 行、每行约 35 B ⇒ 30 × 70 = 2,100 B/s（来源：`src/ps/main.c:206` 的 30 fps 与 `:232` 的行长）；28549 B ÷ 10 s = 2854.9 B/s，比 2,100 还高，因为那 10 s 里还夹着别的回声（来源：`src/ps/main.c:207` 给的实测字节数）。

### 5.5 两步读回：先写 lane 号，再读值

**读法本身**：先用**已经存在**的 GPIO_0（输出）把 lane 号写到 `gpio_o[31:27]`，再从新加的 GPIO_1（输入）读那一条 32 bit（来源：`src/rtl/top/system_top.v:207-208`）。
为什么不是一组宽寄存器：整套观测面"不加 AXI 从设备，只用两个 GPIO"（来源：`src/host/health_read.mjs:9`）——lane 号写在已存在的 GPIO_0 的 bit[31:27]（来源：`src/host/health_read.mjs:10`），数据从新加的只读 32bit GPIO_1 读（来源：`src/host/health_read.mjs:12`）。
RTL 侧的选路是一张组合表：`wire [4:0] lm_lane = gpio_o[31:27];`（来源：`src/rtl/top/system_top.v:219`），然后 lane31 给心跳两位（来源：`src/rtl/top/system_top.v:238`）、lane30 给 `{16'd0, dbg_src}`（来源：`src/rtl/top/system_top.v:239`）、lane24 与 lane23 各取 `dbg_lat`/`dbg_zoom`（来源：`src/rtl/top/system_top.v:240-241`）、lane25..29 按 `(lm_lane-25)*32` 取（来源：`src/rtl/top/system_top.v:242-243`）、`lm_lane > 5'd9` 且不在这几支里给 `32'hDEAD_BEEF`（来源：`src/rtl/top/system_top.v:244`），其余走 `lm_axi[lm_lane*32 +: 32]`（来源：`src/rtl/top/system_top.v:245`）。
那个 0xDEADBEEF 是判据不是垃圾值："其它越界的 lane → 32'hDEAD_BEEF，好让脚本一眼看出自己写错了号"（来源：`src/rtl/top/system_top.v:211`）。

**第二步之间还要等**：脚本每写完一次 lane 号插一句 `after 20`（来源：`src/host/health_read.mjs:284`）才读值——lane 号这一路要过 GPIO 输入寄存器 + 快照节拍，20 ms 是留给它的余量。
为什么整个读回要"两步"而不是"一次 mrd"：GPIO_1 上任何时刻只有**一条** lane 出来，选谁由 GPIO_0 那 5 位决定（来源：`src/rtl/top/system_top.v:245`）⇒ 写 lane 号本身就是一次改动板上状态的动作，所以脚本必须先读回 GPIO_0 原值、只改这 5 位、最后把原值写回去，`effect_en/threshold/src_sel` 才不受影响（来源：`src/host/health_read.mjs:10-11`）。
掩码就是这一句：`const keep = cur & 0x07ffffff;`——清掉 bit[31:27]，保留控制位（来源：`src/host/health_read.mjs:324`）。
第一步失败必须**直接退出**：第一版在这里失败后继续往下写，结果 keep=0，把 `src_sel` / `effect_en` / `threshold` 全清零了——读诊断的脚本自己改掉了工况（来源：`src/host/health_read.mjs:315-316`），判据代码是 `if (!curRaw)` 后 `process.exit(1)`（来源：`src/host/health_read.mjs:318-321`）。
还原与放核只发生在最后一遍：`mwr -force ${GPIO0} 0x${(restoreTo >>> 0)...}` 之后才 `catch {con}`，"只有最后一步才把 A9 放回去"（来源：`src/host/health_read.mjs:288-290`）。
读 PL 外设为什么要 stop/con：A9 停在断点时 `mrd`/`mwr` 走 CoreSight 直接打到 GP0 从端口，绕过 D-Cache 也不会有 MMU 参与（来源：`src/host/health_read.mjs:257-259`）。

### 5.6 读回顺序是判据的一部分

默认要读的 lane 是一张有序表：`const want = [...Array(10).keys(), 25, 26, 27, 28, 29, 24, 23, 30, 31];`（来源：`src/host/health_read.mjs:334`）。
25 必须排在 24 之前，因为 `system_top` 里 `lat_arm = (lm_lane == 5'd25)` ⇒ 指到 lane25 这件事**本身就是抄快照的触发**；先读 24 会拿到**上一遍**武装的那一轮，与这一遍的 27 对不上，于是那条同源判据恒红，而假红是脚本自己造成的（来源：`src/host/health_read.mjs:328-333`，RTL 侧那句"读的顺序必须是 25→26→27→28→29"在 `src/rtl/top/system_top.v:233-234`）。

两遍读取（`--once` 只读一遍，来源：`src/host/health_read.mjs:40`）的判据按"这条 lane 是不是单调"分家：单调集合是 `[0, 1, 5, 6, 8, 9]`（来源：`src/host/health_read.mjs:51`），非单调（会回卷或被清零）的是 `[2, 3, 4, 7]`（来源：`src/host/health_read.mjs:52`）。 单调 lane 只在**变小**时才算撕烈，变大说明计数器还在走，正是链路活着的证据（来源：`src/host/health_read.mjs:490-492`）；15 fps 推流时 pkts 两遍差了几千是正常的（来源：`src/host/health_read.mjs:49`）。

### 5.7 lane0..9 的位域解码（这一张表 10 条；脚本默认读的是 19 条，见 §5.6 的 `want`）

lane0..9 的**内容定义**在 `link_monitor` 尾部，每条都显式声明成 `[31:0]` 再拼——一行里塞两个字段曾把 lane1 拼成 48 bit、整条总线错位（来源：`src/rtl/eth/link_monitor.v:186`）：

| lane | RTL 表达式 | 含义 | 出处 |
|---|---|---|---|
| 0 | `drop_words` | 被 `fifo_full` 挡住而永久消失的 16bit 字数 | 来源：`src/rtl/eth/link_monitor.v:187`，语义见 `src/host/health_read.mjs:54` |
| 1 | `{err16, bad16}` | 高 16=坏包数，低 16=被作废的帧数 | 来源：`src/rtl/eth/link_monitor.v:188` |
| 2 | `{rows_miss_max, stall_ms}` | 高 16=作废帧最多缺几行，低 16=距上一个完整帧过了多少 ms | 来源：`src/rtl/eth/link_monitor.v:189` |
| 3 | `{16'd0, gap_last}` | 最近一帧间隔 ms | 来源：`src/rtl/eth/link_monitor.v:190` |
| 4 | `{gap_max, gap_min}` | 高 16=max，低 16=min | 来源：`src/rtl/eth/link_monitor.v:191` |
| 5 | `gap_sum` | Σ间隔 ms | 来源：`src/rtl/eth/link_monitor.v:192` |
| 6 | `{16'd0, ep16}` | CDC 从"没满"跳到"满"的次数 | 来源：`src/rtl/eth/link_monitor.v:193` |
| 7 | `{27'd0, flag5}` | 五个标志位 | 来源：`src/rtl/eth/link_monitor.v:194` |
| 8 | `in_pkts` | 收到的 UDP 包数 | 来源：`src/rtl/eth/link_monitor.v:195` |
| 9 | `in_bytes` | 收到的有效字节数 | 来源：`src/rtl/eth/link_monitor.v:196` |

lane1 的高低两半被饱和成 16 位：`bad16` 与 `err16` 都写"超过 0x0000FFFF 就取 0xFFFF"（来源：`src/rtl/eth/link_monitor.v:90-91`）；lane6 的 `ep16` 同理（来源：`src/rtl/eth/link_monitor.v:92`）。
lane7 那五个位的定义（bit0 丢过字 / bit1 作废过帧 / bit2 灌满过 / bit3 流活着 / bit4 间隔已校准）在 RTL 里是从高往低排的，最高一位写作 `gap_valid`（来源：`src/rtl/eth/link_monitor.v:158`），紧接着的一位是 `stall_ms < LIVE_MS`（来源：`src/rtl/eth/link_monitor.v:159`），最低一位是 `drop_words != 0`（来源：`src/rtl/eth/link_monitor.v:162`）；`LIVE_MS` 这个参数默认 200（来源：`src/rtl/eth/link_monitor.v:13`），所以 bit3 念的就是"200 ms 内真的收到过完整帧"——顶层也直接把它当仲裁输入用：`wire eth_live = lm_axi[7*32 + 3];`（来源：`src/rtl/top/system_top.v:255`）。
解码用的两个助手就是一个取半字 `(v >>> (hi ? 16 : 0)) & 0xffff`（来源：`src/host/health_read.mjs:352`）、一个取位 `(v >>> i) & 1`（来源：`src/host/health_read.mjs:353`）。

lane30 的位序唯一出处是顶层那一行拼接：`assign dbg_src = {5'd0, why_ps, 1'd0, ms2, row_busy, fill_busy, owner_eth, eth_live, eth_tb_ok};`（来源：`src/rtl/top/pl_video_top.v:603`），
上位机的解码函数 `decodeSrc` 逐位对齐它（来源：`src/host/health_read.mjs:71-85`）：bit0 时基可信、bit1 有流、bit2 屏幕归 ETH、bit3 PS 引擎搬运中、bit4 ETH 引擎搬运中、`[6:5]` 仲裁看到的模式（格雷码）、`[10:8]` 判决那一拍看到的三个原因位（来源：`src/host/health_read.mjs:76-79`、`src/rtl/top/system_top.v:239`）。
为什么要给到七位（模式 2 位 + 原因 3 位）：#28 第一次板级跑交接判据就红，而三位版本分不开"模式被钉住 / 时基不可信 / both_idle 从不成立 / 判据说谎"四种解释（来源：`src/host/health_read.mjs:367-370`）。
为什么新位只能往上加：lane30 的老读者按位 0..6 解析，改低 8 位会让它们的判据**静默**失效（来源：`src/rtl/top/pl_video_top.v:602`）。
另一条相关的历史读数：`dbg_src` 曾被顶层写成 `[5:0]`，综合只给一条 `Synth 8-689` 警告就把模式高位**静默丢掉**——TEST(10) 读起来像自动(00)、SD(11) 像 ETH(01)（来源：`src/rtl/top/system_top.v:224-226`）。

lane23 的位序唯一出处在文件尾：`assign dbg_zoom = {~z_pix_gone, 11'd0, split_ctl[18] | z_bus_axi[19], z_bus_axi[18:0]};`（来源：`src/rtl/top/pl_video_top.v:688`），展开就是 bit31 像素时基活着、bit19 = zoom_fit（从 r97 起是 `zoom_fit_en | rot_forced`）、bit18 = zman、`[17:15]` = zsel、`[14:12]` = zoom_code、bit11 = zoom_active、bit10 = zoom_dir、`[9:0]` = inv_used、`[30:20]` 留扩展（来源：`src/rtl/top/pl_video_top.v:679-682`、`src/host/health_read.mjs:94-100`）。
这一口为什么必须存在：GPIO 读回来的 zsel/zman 只能证明 **PS 写了这一位**，证明不了 13 级 sel 链把它送到了像素域、更证明不了据此算出的 inv_scale 是对的（来源：`src/rtl/top/pl_video_top.v:645-646`）。
bit19 为什么不能有可无：判据①在拟合模式下**按构造就不成立**，没有它脚本会把一次正常拟合读成档位错乱——那是"尺子先错"不是设计错（来源：`src/rtl/top/pl_video_top.v:683-684`）。
lane25..29 与 lane24 是六个字一组、lane 号 = 25 + 序号，`lane29=c1（等消隐窗口）`、`lane28=c2（整帧搬运）`、`lane27=tot`、`lane26=max`、`lane25={n_meas,clamped}`、`lane24=q_ms`（来源：`src/rtl/top/pl_video_top.v:636-638`），而给出去的是 **q_*（快照）** 不是 live 的 lat_*（来源：`src/rtl/top/pl_video_top.v:639`）。
换算集中在一个常量：`NS_PER_CYC = 10`，因为 fclk0 = 100 MHz ⇒ 1 拍 = 10 ns；PL 里只报拍数、不做除法（来源：`src/host/health_read.mjs:391-399`，硬件侧理由在 `src/rtl/top/pl_video_top.v:621-623`）。

lane31 只有两位：`{30'd0, hb_slow, hb_gone}`，bit0=源时钟没有、bit1=源时钟被拉慢（来源：`src/rtl/top/system_top.v:209`）。
断链时读的是 bit1 而不是 bit0，因为 RTL8211 不停 RXC 而是把它拉到约 2.5 MHz ⇒ `stall_ms` 慢约 48 倍地爬，单看那一位会永远判"活着"（来源：`src/rtl/top/system_top.v:210`、`:252-254`）。

### 5.8 `--gapclr`：唯一那条会写板子的读命令

帧间隔统计的归零入口是 gpio_o[26]（来源：`src/rtl/top/system_top.v:203`）。脚本的做法是拉高 250 ms 再落下（来源：`src/host/health_read.mjs:272`），写两笔：先 `1 << CLR_BIT`（来源：`src/host/health_read.mjs:274`）再原值（来源：`src/host/health_read.mjs:276`）。
为什么是 250 ms：gapclr 是电平，链路里已经 3FF 同步，短脉冲会被拉长到安全宽度（来源：`src/host/health_read.mjs:272`）。 为什么需要这个入口：`gap_max` 是终身保持的，两件事会污染它——上一次实验留下的长空闲、以及修好之前 16bit 毫秒计数还会回卷；没有归零入口，lane3/4/5 就只能当"自启动以来"看（来源：`src/host/health_read.mjs:41-43`）。

### 5.9 这一站的数据形状 + 出错时看到什么

- **形状**：`gpio_o` 的一次典型整字是 0x000A5000（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:113`）。拆开：低 8 位全 0（退役的五位）、`[15:8]` = 0x50 = 80 就是 `thr=80`、bit16=0 就是 `src=0`、bit17=1 就是 `zoom=1`、bit18=0 就是 `pub=0`、bit19=1 就是 `bilin=1`、bit20=0 就是 OSD 开着、`[24:23]`=0 就是 `mode=0`、`[31:27]`=0 就是没选 lane——这一串与同一行末尾的 `sel=000 thr=80 src=0 zoom=1 pub=0 bilin=1 osd=1` 逐位对得上（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:113`）。
- **形状**：`src 2` 之后同一个字变成 0x000B5000（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:132`），差值 0x000B5000 − 0x000A5000 = 0x10000 = 只有 bit16 从 0 变 1，正是 `ctrl_set_src(1)` 的效果（来源：`src/ps/main.c:497-501`）。播放中再拍一张就是 0x000F5000，多出来的 0x40000 = bit18 翻了（来源：`board/measured/health_20261005_1031.txt:19`、`board/measured/flash_20261006_1715.txt:142`）。
- **出错**：`[CFG!] %08x 写 1ff/780000 读回 %03x/%06x —— 位流里没有新的 axi_gpio_2，`（来源：`src/ps/main.c:1546`）；配套关系由 `build/frozen_*` 的 md5 清单管（来源：`src/ps/main.c:76`）。
- **出错**：`[CFG!] %08x 写 %08x 读回 %08x —— gamma 窗口不在位流上（elf/bit 不配套）`（来源：`src/ps/main.c:1561`）。开机两条都绿的样子是 `[CFG] axi_gpio_2 @41220000 ok` 与 `[CFG] gamma window @41220008 ok`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:115-116`）。
- **出错**：读回脚本拿不到 GPIO_0 原值时会拒绝继续并说"否则会踩掉 src_sel/特效/阈值"（来源：`src/host/health_read.mjs:319-320`）；`mrd` 的返回形如 `41200000:   00010000`，**不要**在 Tcl 里 `lindex`/`split` 它——实测拿不到第二段，会把整条链读成 0（来源：`src/host/health_read.mjs:265-267`）。

---

## 6. SD 播放通路：从簇链到一个字节都不拷的落地

### 6.1 卡上应该长什么样（固件认的形状）

`sd_play.c` 的文件头把契约写死了：裸机 FAT32 只读 + XSdPs，不依赖 FatFs / 任何文件系统库（来源：`src/ps/sd_play.c:2`）。
为什么不引库：BSP 的 libsrc 里没有 xilffs（只有 sdps），而卡上的文件布局是本项目自己用 `src/host/make_sd_video.mjs` 生成的——只有 8.3 名、只有簇链，一个只读目录扫描 200 行就够；引入 FatFs 反而多一层没人验过的代码（来源：`src/ps/sd_play.c:4-6`）。

卡上的内容与它的形状（留档原文，来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:120-131`）：

| 项 | 读数 | 算式 / 含义 |
|---|---|---|
| 分区 | `FAT32 part_lba=2048 spc=32 rootclus=2 data_lba=34816` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:121` |
| 簇大小 | `spc=32` ⇒ 32×512 = 16,384 B | 由 `clus_lba` 与 `bpc = spc * 512u` 用的是同一个数（来源：`src/ps/sd_play.c:149`、`:714`） |
| 每段帧数 | 前 8 段各 512 帧、第 9 段 302 帧 | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:123-131` |
| 总帧数 | `frames=4398` | 8×512 + 302 = 4,096 + 302 = 4,398（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:122`） |
| 每帧字节 | `frame=307200B` | 512×300×2（来源：`src/ps/sd_play.c:34`），同一行读数在 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:122` |
| 每段体积 | 512 × 307,200 = 157,286,400 B | 除 2^20 = 150 MiB、除 10^6 = 157.3 MB——`src/ps/sd_play.c:9` 旧版那句写的"153.6 MiB"与这两个数都不等（153.6 只能由 `157286400/1024/1000` 得到，即把 1 MB 当成 1024×1000 B）；注释已在 `eb5933b` 改对，同一行并补了"末块按余数（本卡 VIDEO008=302，共 4398）" |
| 分区上界 | `part_end=62332928` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:135`；part_sect = 62332928 − 2048 = 62,330,880 扇区 ⇒ ×512 = 31,913,410,560 B |
| 合法簇数上界 | `first clusters within 1946818` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:120`；算式就是 `(part_lba + part_sect - data_lba) / spc + 2u`（来源：`src/ps/sd_play.c:523`）：(62332928 − 34816)/32 + 2 = 1,946,816 + 2 = 1,946,818 |

### 6.2 卷参数：`parse_bpb` 读的 9 个偏移

| 读的字节 / 偏移 | 判什么或取出什么 | 出处 |
|---|---|---|
| 510 | MBR 签名 `0xAA55` | 来源：`src/ps/sd_play.c:207` |
| 450 | 分区类型必须 0x0B 或 0x0C，否则报 not FAT32 | 来源：`src/ps/sd_play.c:208-210` |
| 454 / 458 | `part_lba` / `part_sect` | 来源：`src/ps/sd_play.c:212-213` |
| 引导扇区 510-511 与 11 | 再判签名；`bytes/sector != 512 not supported` | 来源：`src/ps/sd_play.c:215-216` |
| 13 / 14 / 16 / 36 | `spc` / `rsvd` / `nfat` / `fatsz` | 来源：`src/ps/sd_play.c:217-220` |
| 44 | `root_clus`（掩掉高 4 位） | 来源：`src/ps/sd_play.c:222` |

三个派生量一行一条：`fat_lba = part_lba + rsvd`、`data_lba = fat_lba + nfat * fatsz`、`FatLba = 0xFFFFFFFFu`（来源：`src/ps/sd_play.c:223-225`）。
用留档反推：rsvd = fat_lba − part_lba = 4396 − 2048 = 2348（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:135-137` 给的 fat_lba 与 :121 给的 part_lba），`nfat*fatsz` = data_lba − fat_lba = 34816 − 4396 = 30,420 扇区。
`fatsz == 0` 或 `spc == 0` 时报的是"FATSz32 or SecPerClus is 0 → FAT16, not supported"（来源：`src/ps/sd_play.c:221`），`root_clus < 2` 报"root cluster invalid"（来源：`src/ps/sd_play.c:226`）。

### 6.3 目录扫描：`dir_lookup` 的三层循环与三个"跳过"

外层走根目录的簇链（来源：`src/ps/sd_play.c:242`），一个簇里逐扇区（来源：`src/ps/sd_play.c:244`），一个扇区里逐 16 个目录项、每项 32 字节（来源：`src/ps/sd_play.c:247-248`）。
守卫是 `guard++ < 4096u`（来源：`src/ps/sd_play.c:242`），也就是最多扫 4096 个簇。
四个跳过各对应一种必须忽略的项：`d[0] == 0x00` 目录到此为止（来源：`src/ps/sd_play.c:249`）、`0xE5` 已删除（来源：`src/ps/sd_play.c:250`）、`d[11] == 0x0F` 是 LFN 而"本项目不产生"（来源：`src/ps/sd_play.c:251`）、`d[11] & 0x08` 是卷标（来源：`src/ps/sd_play.c:252`）。
命中时顺带把文件大小记进 `found_size`：`ld32(&d[28])` 是 `DIR_Entry.FileSize`（来源：`src/ps/sd_play.c:254`），返回的是首簇（来源：`src/ps/sd_play.c:255`）。
名字要经过 `name83`：前 8 大写、不足补空格、扩展名 3 字节（来源：`src/ps/sd_play.c:152-167`），比对是 `memcmp(d, key, 11)`（来源：`src/ps/sd_play.c:253`）。
留档里能看到它算出来的 11 字节键：`k83=564944454F303034_42494E`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:138`）——`56 49 44 45 4F 30 30 34` 就是 "VIDEO004"、`42 49 4E` 就是 "BIN"。

### 6.4 那个大端拼字节的历史 bug：`clus_of`

FAT32 目录项里的首簇是**两个小端字**：偏移 26 是低 16 位、偏移 20 是高 16 位（来源：`src/ps/sd_play.c:230-231`）。现在的写法：

```
static u32 clus_of(const u8 *d) { return ((u32)ld16(&d[20]) << 16) | (u32)ld16(&d[26]); }
```

来源：`src/ps/sd_play.c:233`。旧写法是把 `d[20]<<24 | d[21]<<16` 这样**按大端**拼（来源：`src/ps/sd_play.c:231`），于是"首簇 ≥ 65536"（= 文件起点在数据区 1 GiB 之后）的文件簇号被翻成天文数字（来源：`src/ps/sd_play.c:231-232`）。
1 GiB 这个界是这么来的：65536 簇 × 32 扇区 × 512 B = 1,073,741,824 B（来源：`src/ps/sd_play.c:232` 的"≥65536"与本节上面的 spc=32 读数）。

这条 bug 在屏幕上的表现是著名的"定点坏点"：两次独立长跑（一次并发、一次完全不碰 JTAG）都停在**同一帧号 3584**，而 3584 = 7×512，正好是第 8 个文件 `VIDEO007.BIN` 的**第一帧**；定点跳帧验到 FRAME3583 好、FRAME3584 = SD read failed（来源：`src/ps/sd_play.c:98-101`）。
根因在 09-24 05:4x 结案，写的就是"`dir_lookup` 把 FAT32 目录项的高簇字按大端拼 ⇒ 首簇 ≥65536 的文件…簇号翻错、LBA 冲出分区"（来源：`src/ps/sd_play.c:105-107`）。

判据不是"改完就算"：`dir_selftest` 三段样本 + 两条反例（来源：`src/ps/sd_play.c:267-289`）。用例正是 #50 的现场——真实卡上 VIDEO007.BIN 的高字是 0x0001、低字是 0x0686 ⇒ 必须解出 67206（来源：`src/ps/sd_play.c:263-265`）；核对：0x0001<<16 = 65,536，加 0x0686 = 1,670，合计 67,206。
最后那条反例断言才是要害：它要求"旧写法（两个字节按大端拼）"确实给出 16778886（来源：`src/ps/sd_play.c:265-266`、`:283-285`）——核对：0x01<<24 = 16,777,216，加上 (0x86 | 0x06<<8) = 1,670，合计 16,778,886；新旧必须给出不同答案（来源：`src/ps/sd_play.c:287`）。
注释把这条判据的哲学说明白了：**否则它只是把实现照抄一遍**（来源：`src/ps/sd_play.c:266`）。

### 6.5 META.TXT：另一处指针比较的 bug

清单第一行了 `FRAMES`、`FPS`、`FRAME_BYTES`、`WIDTH`，然后是若干段记录，每段的形状是 `FILEi=名字 FRAMES=n BYTES=b`（来源：`src/ps/sd_play.c:10`）。
`meta_line` 是**行首锚定**：只有行首（或串首/空格/换行之后）匹配 `KEY=` 才认（来源：`src/ps/sd_play.c:292-309`，判据在 `:300`）。

被修掉的那个 bug 在 `kv_u32` 里，它是"从 `KEY=v1 KEY=v2 ...` 里取某个 KEY 的整数值"的函数（来源：`src/ps/sd_play.c:180`）。
原来"命中处必须在串首"这一支写的是 `s == key`——而 `key` 是被查找的**字面量**（"FRAMES" 在 .rodata 里），和指进 `s0` 里的指针永远不相等，于是"关键字出现在串首"这一种恰恰不成立；再巧的是调用方把空格换成了 `'\0'` 才传进来，`s[-1]` 读到的是那个 `'\0'`，三个字符一个都不匹配 ⇒ 板上实测 `FILE0=VIDEO000.BIN FRAMES=100 BYTES=…` 一律报 "META: FILE line without FRAMES"（来源：`src/ps/sd_play.c:186-191`）。
现在的写法是 `s == s0 || s[-1] == ' ' || s[-1] == '\r' || s[-1] == '\n'`（来源：`src/ps/sd_play.c:192`）。
这条被记成"判据要能被独立测试"（来源：`src/ps/sd_play.c:191`），落法就是 `meta_selftest`。

`meta_selftest` 的六个用例（来源：`src/ps/sd_play.c:423-467`，判据串在 `:457-462`）：

| 用例 | 内容与期望 | 钉的是哪条 |
|---|---|---|
| ok / b1 / b2 | 1350 = 900+450 必须过且 `meta_warn == 0`（来源：`src/ps/sd_play.c:459`）；FILE0 行没有 `FRAMES=` 必须被拒；写成 `SFRAMES=` 必须被拒 | 防误匹配那条真被执行到（来源：`src/ps/sd_play.c:431-435`）；否则自检是摆设（来源：`src/ps/sd_play.c:436-439`） |
| b3 | 声明 900、文件里只有 450 ⇒ 必须按 450 收并置 `meta_warn` | 卡在 2099/4398 停住那一幕（来源：`src/ps/sd_play.c:440-442`、`:360-363`） |
| long_ok + NUL | 12 个 FILE 行、长度 > 512 必须过；每段样本在 NUL 之后塞一行假 FILE 记录，解析必须在 NUL 处停住 | 清单跨扇区不能被从中间切断（来源：`src/ps/sd_play.c:443-455`、`:462`）；簇尾垃圾不是截断信号（来源：`src/ps/sd_play.c:409-417`） |

那把真实的刀写在 `long_ok` 的注释里：固件只读 1 个扇区且 `Meta` 只有 512 B，于是尾行的数字被从中间切成 `FRAMES=51`，卡明明是完整的（PC 重生成后 md5 逐字节相同）；这条样本长度本身也是判据的一部分——不 >512 就等于没测到那件事（来源：`src/ps/sd_play.c:443-446`）。
修完的读法改成"读满首簇、上限 = 缓冲区/512"（来源：`src/ps/sd_play.c:500`），具体三段是 `cap = sizeof(Meta) / 512u`、`nsec = (found_size + 511u) / 512u`、再被 `cap` 与 `spc` 各夹一次（来源：`src/ps/sd_play.c:503-511`）。
按 `META.TXT` 现在 712 B（来源：`src/ps/sd_play.c:497`）与缓冲区 4096 B（来源：`src/ps/sd_play.c:44`）算：nsec = (712+511)/512 = 2，cap = 8，spc = 32 ⇒ 真的读 2 个扇区 = 1,024 B；`meta_trunc` 按**文件长度**判而不是缓冲区尾字节（来源：`src/ps/sd_play.c:506-509`），因为簇里文件后面是上一个文件留下的垃圾，拿尾字节当信号会把完整的清单报成截断（来源：`src/ps/sd_play.c:507-508`）。
`parse_meta` 里 `Meta[sizeof(Meta) - 1] = 0;` 先把缓冲区最后一格钉成 NUL（来源：`src/ps/sd_play.c:317`），帧率解析允许 `15` 与 `15.000` 两种写法：带小数点时 `fps_num = fps_num * scale + frac`（来源：`src/ps/sd_play.c:328`）与 `fps_den = scale`（来源：`src/ps/sd_play.c:329`），`fps_num == 0` 退回 15/1（来源：`src/ps/sd_play.c:331`）；默认值是 `fps_num = 15u, fps_den = 1u`（来源：`src/ps/sd_play.c:63`）。留档里那张卡声明的是 `fps=30.000`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:122`）。
`FRAME_BYTES` 与 `WIDTH` 不同值时是**拒挂**，不是警告：一个报"rebuild to match the card"（来源：`src/ps/sd_play.c:333-337`）、一个报"card is for another geometry"（来源：`src/ps/sd_play.c:338-340`）。

### 6.6 挂载的顺序（以及为什么每次上电只有一次机会）

`sd_mount()` 的动作是有顺序的，而前两行是"自我诊断优先"：`if (mounted) { return 0; }`（来源：`src/ps/sd_play.c:475`）→ `meta_selftest()`（来源：`src/ps/sd_play.c:476`）→ `dir_selftest()`（来源：`src/ps/sd_play.c:480`）→ `XSdPs_LookupConfig`（来源：`src/ps/sd_play.c:484`）→ `XSdPs_CfgInitialize`（来源：`src/ps/sd_play.c:486`）→ `XSdPs_CardInitialize`（来源：`src/ps/sd_play.c:489`）→ 读 LBA 0 与 `parse_bpb`（来源：`src/ps/sd_play.c:492-493`）→ `dir_lookup("META.TXT")`（来源：`src/ps/sd_play.c:495`）→ 读清单（来源：`src/ps/sd_play.c:502-514`）→ `parse_meta`（来源：`src/ps/sd_play.c:515`）→ **挂载时就把每个片源文件的首簇量一遍**（来源：`src/ps/sd_play.c:517-537`）→ 才置 `mounted = 1`（来源：`src/ps/sd_play.c:539`）。

那个"量一遍"是 #50 的教训直接买的：簇号翻错的时候挂载、META、前 7 个文件全都正常，直到播到第 8 个才在屏幕上冻住——代价是整整两分钟的演示；所以改成"分区装不下的簇号一定是坏的，不需要等到读到 OUT-OF-RANGE 才知道"（来源：`src/ps/sd_play.c:517-519`）。 探针读过的 FAT 扇区不算数，收尾要把缓存作废（来源：`src/ps/sd_play.c:536`）。

`XSdPs_CfgInitialize` 每个上电周期只成功一次，这条曾被记成 #45；固件把挂载提前到上电，就等于把"那一次"用在上电时刻——卡没插好时后面手敲 `SD` 也会失败（来源：`src/ps/main.c:634-636`）。
2026-09-27 早晨这条被推翻：它其实是**驱动的二次初始化守卫**——`sd_play.c` 把驱动那段"被调用两次就按返回值返回"的判断连同它所在的厂商文件名一起抄进了自己的注释（来源：`src/ps/sd_play.c:555-559`），而仓里没有任何一处清 `IsReady` ⇒ 第二次初始化**永远**在第一步就被挡回（来源：`src/ps/sd_play.c:559-560`）。
留档的 A 侧凭据是改之前卡在不插的状态下敲 `sd remount` 回的 `XSdPs_CfgInitialize failed`（来源：`src/ps/sd_play.c:561-562`、`report/commands.md:361-362`）。

### 6.7 取帧四件套：`frame_map` / `open_at` / `feed_cur` / `show_frame`

| 函数 | 职责 | 关键算式 | 出处 |
|---|---|---|---|
| `frame_map` | 全局帧号 → (文件号, 文件内帧号) | 逐段减 `fframes[i]`，减完就出界 | 来源：`src/ps/sd_play.c:668-676` |
| `open_at` | 打开第 i 个文件并把簇游标推到第 off 帧开头 | `skip = (off * FRAME_BYTES) / bpc`（整簇跳过：只走 FAT，不读数据）、`ff_blk = ((off * FRAME_BYTES) % bpc) / 512u` | 来源：`src/ps/sd_play.c:712-732`，两式在 `:723`、`:729` |
| `feed_cur` | 从当前游标读一帧到 `FRAME_ADDR` | 逐簇读，因为簇链可以不连续；帧内跨簇的边界用目标指针偏移接起来 | 来源：`src/ps/sd_play.c:734-764`，块大小式在 `:747-750` |
| `show_frame` | 三件事：越界判、`open_at`、`feed_cur`，都过了才 `ps_publish()` | 只有"真的去读卡并且读失败"才停心跳 | 来源：`src/ps/sd_play.c:766-788`，发布在 `:786` |

`feed_cur` 每轮的段长是 `nsec = spc - ff_blk`，再被剩余字节夹一次（`if (nsec * 512u > left) nsec = left / 512u`）（来源：`src/ps/sd_play.c:747-749`）；一簇 16,384 B，一帧 307,200 B ⇒ 307200/16384 = 18.75 簇，所以一帧要跨 19 个簇边界（第 19 段只有 12,288 B）。
它的三段护栏是 `bytes == 0u || ff_clus < 2u || ff_clus >= EOC`（来源：`src/ps/sd_play.c:751`），失败报"cluster chain ended early"（来源：`src/ps/sd_play.c:752`）；`last_clus = ff_clus;` 是给失败时打印用的（来源：`src/ps/sd_play.c:755`）。

底层 `read_secs` 还有自己的分块：一次最多 64 扇区 = 32 KB（来源：`src/ps/sd_play.c:86-87`，实现 `:93`）。 读之前还要 flush：驱动读完会 invalidate 目标区间，但**进**去之前若那里有脏行（例如刚跑过 FILL），invalidate 之后脏行仍会被写回，把刚 DMA 进来的数据盖掉（来源：`src/ps/sd_play.c:87-89`，实现 `:95`）。
重试是一次：`for (try = 0; try < 2; try++)`（来源：`src/ps/sd_play.c:108`）；注释对它的定位很克制——重试对定点坏点没用，它只是让偶发的单点抖动不掐断演示（来源：`src/ps/sd_play.c:102-104`）。
失败那一行是全场信息量最大的一行：`[SDRD!] lba=%u n=%u clus=%u part_end=%u ... (data_lba=%u spc=%u fat_lba=%u dst=0x%08x)`，并且自己判 IN-RANGE / OUT-OF-RANGE（来源：`src/ps/sd_play.c:115-122`）；判"簇号越界"还是"合法 LBA 被拒"只看这一个数就够（来源：`src/ps/sd_play.c:113`）。

`show_frame` 与"停心跳"的边界画得很细：`!mounted` 与帧号越界这两条**不停**心跳——那时屏上那张仍是 PS 主动交出去的画，而"越界"是命令被拒，被拒的命令不许顺手改观感（来源：`src/ps/sd_play.c:774-776`）；只有 `open_at` / `feed_cur` 失败才 `card_gone()`（来源：`src/ps/sd_play.c:784-785`）。

### 6.8 播放状态机与节拍

`sd_play(1)` 做的事：置 `playing`、`nxt = 0`、取 `last_t` 与 `rpt_t` 两个时基、`rpt_cnt = fed_cnt`，`fed_t0` 为 0 时才补一次（来源：`src/ps/sd_play.c:813-825`）。
`sd_tick()` 每拍被主循环叫一次（来源：`src/ps/main.c:1589`），它的判据是 `need = ((u64)COUNTS_PER_SECOND * fps_den) / fps_num`（来源：`src/ps/sd_play.c:852`），没到 `need` 就返回（来源：`src/ps/sd_play.c:854`）；到点了 `if (nxt >= total_frames) nxt = 0;` 是循环播放（来源：`src/ps/sd_play.c:856`），成功后 `nxt++`、`fed_cnt++`、`last_t = now`（来源：`src/ps/sd_play.c:869-871`）。
为什么不用"usleep 到下一帧"：那样 UART 命令要等到睡完才被轮询，STOP 会明显发钝；而喂帧本身最长就是一次 300 KB 的 SD 读取，那个时间同时决定了本项目的实际帧率上限（来源：`src/ps/sd_play.c:842-844`）。
读失败这一拍：`playing = 0`、把 `open_idx` 与 `FatLba` 清成"从头走"（来源：`src/ps/sd_play.c:858-864`），再打一行 `[SD] playback stopped at frame %d: %s (PLAY retries`（来源：`src/ps/sd_play.c:865`）。
平均帧率用整数报：`return (u64)fed_cnt * 1000u * (u64)COUNTS_PER_SECOND / dt;`（来源：`src/ps/sd_play.c:838`），因为 `xil_printf` 没有 `%f`（来源：`src/ps/sd_play.c:828`）。 每 100 帧那一行自动打印已经被用户明确要去掉（2026-09-29），但计时基准仍然滚动，否则哪天再开这条打印，第一段的窗口长度会把整段播放都算进去（来源：`src/ps/sd_play.c:872-880`）；数据没丢——`sd` 走 `sd_status()` 打一次 frames/fps/files，`stat` 念 playing 与片长，屏上第 1 行的 FPS 是 PL 侧算的（来源：`src/ps/sd_play.c:874-875`）。

`dir_diag` 是失败时唯一多打的一行，用来把"名字被踩坏 / FAT 那一跳读不出来 / 卷参数变了"三种可能分开（来源：`src/ps/sd_play.c:680-685`）。
它自己踩过一个观察者效应：`dir_lookup`/`fat_next` 内部读失败会把 `err` 改成 "SD read failed"，于是这行诊断**把要报的错覆盖掉了**——第一次跑就打印出 "playback stopped ... : SD read failed" 而不是真正的 "frame file not found"；修法是先存后还（来源：`src/ps/sd_play.c:693-699`）。
顺带说一句：那份留档里 `fat_next=268435455`（= EOC，来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:139`）说明这张卡的根目录只有 1 个簇，而 `src/ps/sd_play.c:684` 的注释讲的是"VIDEO000.BIN 在根目录的**第二个簇**，必须先 `fat_next(root_clus)`"——那是另一张卡的形状。这一处我不推断成因，只把两个读数并排放着。

### 6.9 拔卡之后会发生什么（三段收口）

1. **读失败 → `card_gone()`**：停播、清 `mounted`、清打开的文件号、清 FAT 缓存，然后 `ps_source_lost()`（来源：`src/ps/sd_play.c:583-590`）。为什么必须清 `mounted`：`sd_recover_tick()` 的第一行是 `if (mounted) return;`，拔出卡在这之前没有任何路径把它清 0 ⇒ 自动重挂的门**永远关着**，卡插回来了固件也不再去看它一眼（来源：`src/ps/sd_play.c:576-582`、`:778-783`）。
2. **手工恢复键 `sd remount`**：停播 → 清 `mounted`/簇表/FAT 缓存 → 清 `Sd.IsReady = 0u;`（来源：`src/ps/sd_play.c:572`），整支函数在 `:565-574`→ 再走 `sd_mount()`。注释直接点名驱动那三行代码与原文（来源：`src/ps/sd_play.c:556-558`）。
3. **自动恢复 `sd_recover_tick()`**：`seen_mounted` 与 `want_play` 是**还挂着的那一拍**按 `playing` 记下的（来源：`src/ps/sd_play.c:612-617`），所以 `stop` 之后再插卡不会被"自动开播"（来源：`src/ps/sd_play.c:594-597`）；一旦卡丢了就每 2 s 试一次（来源：`src/ps/sd_play.c:622`）、最多 30 次，没成就停手并**明说**（来源：`src/ps/sd_play.c:625-628`）。
   为什么每拍最多一次、为什么限 2 s：`sd_recover_tick()` 跑在主循环里，而主循环同时是**串口**的服务循环——卡不在位时一次初始化要等 CMD 超时，连着跑几十次，控制台就没人在听了（来源：`src/ps/sd_play.c:598-600`）。

整条链在留档里跑通过一次，顺序可以在同一份件里逐行对上：三次 `[SDRD!]`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:135`）→ `[SDDBG]` 那一行（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:138`）→ 那句停心跳的固件原文在 `src/ps/main.c:277`（留档 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:140` 里中文已成问号）→ `playback stopped at frame 2324`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:141`）→ 第 1 次自动重挂失败 `card absent or CMD sequence failed`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:142`）→ `dir map ok: 9 files`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:143`）→ 第 2 次成功并继续回放（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:144`）。 帧号与文件号也能对上：2324 = 4×512 + 276 ⇒ 落在第 5 段（下标 4）`VIDEO004.BIN` 内第 276 帧（按 `frame_map` 的逐段减法，来源：`src/ps/sd_play.c:671-674`），而 `[SDDBG]` 里念的名字正是它（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:138`）。
两个 `dst` 指针差 0x200 = 512 B（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:135`、`:137`），与那两只 512 字节的扇区缓冲同尺寸（来源：`src/ps/sd_play.c:42-43`）；而它们落在 0x0021E880 / 0x0021EA80，也就是 app 基址 0x00200000（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:73`）之上约 0x1E880 ≈ 125 KB 处——这正是"镜像 ~136 KB"那句的位置口径（来源：`report/log/issues.md:14160`）。
这一轮的尾巴仓里自己也没判：现象是"一个文件放完/切下一个"还是"簇映射在第 2324 帧处断"，**本轮没有判**（来源：`report/log/issues.md:14177-14180`）。

### 6.10 DDR 目标与"零拷贝"这条路

帧的落地路径刻意做成零拷贝：SD 控制器的 DMA 直接写 PL 要读的那块 DDR，写完只发一次发布脉冲 ⇒ PS 不需要 300 KB 的 memcpy，也不需要第二块 DDR 做双缓冲（来源：`src/ps/sd_play.c:12-13`，接口那份同话在 `src/ps/sd_play.h:4-6`）。 协议两行：PS 把一帧 DMA 进 DDR → 翻转 GPIO bit18 → PL 在下一个 frame_start 复制一次；"复制一次"而不是"每帧都复制"是关键——前者让 PS 有整个帧周期可以安全覆写 DDR，后者会在 PS 写到一半时把半张新图 + 半张旧图搬上屏（撕裂）（来源：`src/ps/sd_play.c:15-18`）。
`FRAME_BYTES` 在 sd_play.c 里是独立再定义一次的 `(512u * 300u * 2u)`，旁边注明 RGB565 = 307200 B = 600 扇区（来源：`src/ps/sd_play.c:34`）；`FRAME_ADDR` 同样两份（来源：`src/ps/sd_play.c:35`）。文件头把这条"改这里要同时改 pl_video_top.v 的 BASE_ADDR / IMG_W / IMG_H"写成了要求（来源：`src/ps/sd_play.c:33`）。
为什么必须用第三个 bank：以前是 0x1000_0000，与 ETH 乒乓双 bank 的第 0 块重叠 ⇒ SD/FILL 一边写、ETH 一边读写同一块内存，屏幕上就是"两个片源打架、闪"（板级实测 2026-09-24）；仲裁只管谁用 DDR→帧缓存那台搬运机，管不到谁写 DDR（SD 的 DMA 走 PS 自己的 HP0，不经过 PL），所以只能靠地址分开（来源：`src/ps/main.c:41-45`）。ETH 那两个 bank 是 `BASE_ADDR` 与 `BASE_ADDR + 32'h0008_0000`（来源：`src/rtl/eth/eth_udp_video_top.v:67-68`）。

`FILL` 诊断帧走的是另一条完全不同的路：CPU 逐半字写 DDR，然后一次 cache flush（来源：`src/ps/main.c:706`）、`ctrl_set_src(1)` 与 `ps_publish()`（来源：`src/ps/main.c:708`）。那张图故意用四种极端颜色加顶部一条绿，让"哪一通道丢了"在屏上一眼分得清（来源：`src/ps/main.c:691`）：顶部 8 行绿（0x07E0）、左上红、右上黄、左下蓝、右下白（来源：`src/ps/main.c:699-703`）。 `Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)` 这一句为什么必须有，和 `read_secs` 里那句 flush 是同一件事的两半（来源：`src/ps/sd_play.c:87-89`）。

### 6.11 这一站的数据形状 + 出错时看到什么

- **形状**：一次成功挂载在串口上是 3 类行——`[SD] dir map ok: 9 files, first clusters within 1946818`、`[SD] FAT32 part_lba=... spc=... rootclus=... data_lba=...`、`[SD] frames=... fps=... measured=... files=... frame=...B` 再加每段一行（来源：`src/ps/sd_play.c:533`、`:649`、`:654`、`:660`；实物见 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:120-131`）。
- **形状**：`sd_status()` 那行的 `declared` 与 `measured` 是两个独立量——前者是清单里写的帧率、后者是自开播以来真的喂出去多少帧（来源：`src/ps/sd_play.c:651-653`）；两者不等就是真信号（卡带宽/停顿）（来源：`src/ps/sd_play.c:653`）。刚开播那一张快照里 `fps=30.000 measured=0.000`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:122`）就是"还没喂出第一帧"的形状。
- **出错**：`[SD] WARN <原因>: playing <n> frames only`——清单与文件之和不一致时可播长度取小值（来源：`src/ps/sd_play.c:360-378`、`:661-662`）。
- **出错**：`frame file not found on card` 之后紧跟的那行 `[SDDBG]`（打印在 `src/ps/sd_play.c:702`，调用在 `:720`），它专门用来拆穿"挂载正常"这个假象——挂载阶段打印的文件列表来自 META.TXT 的内容而不是目录扫描（来源：`src/ps/sd_play.c:681-683`）。
- **出错**：`cluster chain too short` 出在 FAT 链比请求的跳数短那一支（来源：`src/ps/sd_play.c:726`）；`not mounted` 出在 `sd_show` 与 `sd_play` 的门上（来源：`src/ps/sd_play.c:770`、`:815`）。
- **出错**：两个 selftest 失败时报的是固件的错而不是卡的错——`META parser SELF-TEST failed (firmware bug, not the card)`（来源：`src/ps/sd_play.c:477`）与 `cluster decode SELF-TEST failed (firmware bug, not the card)`（来源：`src/ps/sd_play.c:481`）；从此 "mount failed" 这句话分得清是固件坏了还是卡不对（来源：`src/ps/sd_play.c:386-387`）。

---

## 7. XADC 片上温度：几个寄存器、一次 BCD、三段对账

为什么读 PS 的 XADC 而不是在 PL 里例化一个 XADC IP：后者会破掉本项目"零厂商 IP"这条主张，而 PS 侧只是几个寄存器 + BSP 里已有的 xadcps 驱动 ⇒ PL 一个 LUT 都不加、CDC 一个触发器都不加（来源：`src/ps/main.c:739-741`）。 采样配置只有一步：`XAdcPs_CfgInitialize`，它干三件事——解锁、置 PS 访问使能位、释放复位（来源：`src/ps/main.c:742-744`）；故意不去改序列器/掉电位，因为那两位都得走命令/读数据 FIFO 的读-改-写握手，多一次握手就多一次把 FIFO 弄失步的机会，而这一条只需要"读得出、读得对"（来源：`src/ps/main.c:744-745`）。上电后 XADC 停在 safe mode，TEMP/VCCINT/VCCAUX 本来就在转换（来源：`src/ps/main.c:742`）。两个通道各读一次：`XADCPS_CH_TEMP`（来源：`src/ps/main.c:855`）与 `XADCPS_CH_VCCINT`（来源：`src/ps/main.c:856`），节拍版在 `temp_poll` 里同样两口（来源：`src/ps/main.c:820-821`）。
换算全程不用 float，因为 `xil_printf` 不是 libc 的 printf、**不认 %f**（来源：`src/ps/main.c:750-751`）：

| 量 | 驱动的等价式 | 固件的定点实现 | 出处 |
|---|---|---|---|
| 温度 | °C = raw16 × 503.975 / 65536 − 273.15 | `temp_mc_of`：`((u64)raw * 503975ULL) >> 16) - 273150` | 来源：`src/ps/main.c:752`、`:754` |
| 电压 | 满量程 3.0 V | `volt_mv_of`：`((u64)raw * 3000ULL) >> 16` | 来源：`src/ps/main.c:755` |

65536 = 2^16 ⇒ 乘完只需右移、没有除法；u64 装得下最大乘积 65535×503975 = 3.30e10（来源：`src/ps/main.c:753`）。
拿两份真实读数验一遍这条链：raw = 0xA955 = 43,349 ⇒ 43349×503975 = 21,846,812,275，右移 16 位得 333,355，减 273,150 = 60,205 毫度 = 60.205 °C，而串口打的是 `degC=60.20`（来源：`board/measured/health_20261005_1031.txt:11`）；raw = 0xAA40 = 43,584 ⇒ 21,965,246,400 右移 16 位得 335,163，减 273,150 = 62,013 = 62.013 °C，串口打的是 `degC=62.01`（来源：`board/measured/health_20261005_1025.txt:11`）。
小数点后只有两位是因为格式串写的是 `"%s%d.%02d"` 配 `a / 1000` 与 `(a / 10) % 100`（来源：`src/ps/main.c:882`）；负号从 `mc` 取、整数与小数都从 `a = |mc|` 取，因为 C 的除法朝零截断，`mc = -400` 时 `mc/1000` 已经是 0，照旧写就会把 −0.40 °C 打成 0.40（来源：`src/ps/main.c:870-871`）。
BCD 上 OSD 那一步是 `temp_code_of`：三道门依次是 VCCINT 必须在 800..1300 mv、温度必须在 −40000..150000 毫度、四舍五入后的整度必须落在 0..99，任何一道不过就返回 `GM_TEMP_NONE`（来源：`src/ps/main.c:786-794`）；过门之后编码是 `/ 10u) << 4`（来源：`src/ps/main.c:793`），位段口径是 `[7:4]=十位、[3:0]=个位 ⇒ 屏上画 `Temp:47C``（来源：`src/ps/main.c:84`）。
写屏的动作只改影子、整字写回，而且**只有编码真的变了才写**——通道 2 是 gamma 窗口的同一个寄存器，多一次没必要的整字写就多一次与 `gamma_put` 抢总线的机会（来源：`src/ps/main.c:796-803`）。
十进制换算为什么在 PS 做而不是在 OSD 做：OSD 那五行字符是一整块组合逻辑，而 `u_pipe/xd_reg → u_osd/g_reg`（27 级）正是 clkout0_1 那一组的 WNS 路径（r63b/r63c/r64b 三份 timing_summary 都指着它）——在屏上再加一次 /100 与 /10 就是往全设计最差的链上加深度（来源：`src/ps/main.c:85-89`）；同一件事的先例是 Latency 那一格从 #59 起就是"换算在 axi 域做完再跨域"（来源：`src/ps/main.c:88-89`）。
屏上画不出可信读数时画 `--` 而不是画一个错数，与 Latency 没有测量时画 `--` 同一规矩；PL 那条链的复位值就是 0xFF，所以 app 起来之前屏上是 `--` 而不是 `00C`（来源：`src/ps/main.c:90-93`），固件侧的影子初值也正是 `GM_TEMP_NONE`（来源：`src/ps/main.c:288`，定义在 `src/ps/main.c:106`）。
这里为什么**不用** `cmd_temp` 那个 `sane` 当门：`sane` 的温度窗是 0..80 °C，量的是"这一格像不像一次台架常识内的读数"；而屏上这一格的本职是"盯着结温往上走"，默认告警阈值就是 85 °C，用 0..80 当门会让最需要看的那一段变 `--`（来源：`src/ps/main.c:779-783`）。

`[TEMP]` 那一行的字段来源逐个：

| 字段 | 从哪来 | 能不能动 | 出处 |
|---|---|---|---|
| `degC` | `XAdcPs_GetAdcData` 的 raw 经 `temp_mc_of` | 只能改环境/负载 | 来源：`src/ps/main.c:855`、`:754` |
| `raw` | 同一个 16 位左对齐字，原样 `%04x` | 只读 | 来源：`src/ps/main.c:882` |
| `vccint` | `XADCPS_CH_VCCINT` 经 `volt_mv_of` | 只读 | 来源：`src/ps/main.c:856`、`:755` |
| `th` | 会话变量 `temp_th_deg`，默认 85 | `temp th <0..200>` 改它 | 来源：`src/ps/main.c:748`、`:844` |
| `over` | `mc >= th` | 跟着 `th` 走 | 来源：`src/ps/main.c:860` |
| `sane` | `mc > 0 && mc < 80000 && mv > 800 && mv < 1300` | 判据，不该改（改它等于改判据） | 来源：`src/ps/main.c:861` |
| `osd` | 编码器输出还原成的三个字符（画不出时 `--`） | 派生 | 来源：`src/ps/main.c:873-880` |
| `gpio` | 从 `CFG_DATA1` 读回来的低字节 = PL 同步链正在采的值 | 派生 | 来源：`src/ps/main.c:883`、`:96` |

于是这一行把三段账一次钉住：`degC`（驱动读数）↔ `osd`（编码器输出）↔ `gpio`（真的写到了 PL），串口电池拿这三者做机器判据、不需要任何人看屏幕（来源：`src/ps/main.c:865-868`）。
阈值为什么可改：判据必须能**人为造红**——室温下的板子永远到不了 85 °C，于是"接了 XADC 但告警从没亮过"和"根本没接"在串口上长得一模一样；把阈值压到环境以下 ⇒ `over` 必须=1，抬到 200 ⇒ 必须=0，这两条都进了串口电池（来源：`src/ps/main.c:828-831`）。
`sane` 防的是"看着对其实是常数"：raw 全 0 会译成 −273.15 °C（永远不会告警也不会告第二次），全 F 会译成 230 °C，两个都被挡下（来源：`src/ps/main.c:831-833`）。
这一族的一条**文档层**注意：`report/commands.md` 给的那一行是格式示例（它自己写的是"现在长这样"，来源：`report/commands.md:219`），其中 `raw=0x9776` 按 `src/ps/main.c:754` 的式子算给 (38774×503975)>>16 = 298,173、减 273,150 = 25,023 ⇒ 25.02 °C，与那一行写的 `degC=34.85` 不等（来源：`report/commands.md:220`）；上面两个真正落盘的读数才与式子自洽。

**这一站的数据形状 + 出错时看到什么**：形状是开机一行 `[TEMP] PS-XADC @F8007100 ok`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:117`）+ 之后每次 `temp` 一行八字段（来源：`src/ps/main.c:881`），屏上是第 5 行那一格，形如 `Temp:47C`（来源：`src/ps/main.c:84`）；两张健康快照里真的画出来的是 `osd=62C gpio=0x62`（来源：`board/measured/health_20261005_1025.txt:11`）与 `osd=60C gpio=0x60`（来源：`board/measured/health_20261005_1031.txt:11`）。出错三种：读不到时 `[TEMP] 读不到（开机那行 [TEMP] 说了为什么）raw=NA`（来源：`src/ps/main.c:853`）、不像真实转换时 `[TEMP!]` 那行（来源：`src/ps/main.c:885`）并要求"这一格的数不许写进报告"（来源：`src/ps/main.c:885-887`）、量程装不下时屏上画 `--` 并另打一条 `[TEMP!]`（来源：`src/ps/main.c:92`）。

---

## 8. 链接与内存：`lscript_ocm.ld` 与"重链到 DDR"差在哪

### 8.1 段表：只有一段留在 OCM，其余全部进了 DDR

| 区域 | ORIGIN | LENGTH | 装了哪些段 | 出处 |
|---|---|---|---|---|
| `ps7_ram_0_S_AXI_BASEADDR` | `0x00200000` | `0x00C00000`（12 MiB） | `.text`（含 `*(.vectors)` 与 `*(.boot)` 打头）、`.note.gnu.build-id`、`.init`、`.fini`、`.rodata`、`.data`、`.got`、`.ctors/.dtors`、`.mmu_tbl`、`.ARM.exidx`、`.preinit/.init/.fini_array`、`.rsa_ac`、`.sdata/.sbss`、`.tdata/.tbss`、`.bss`、`.drvcfg_sec`、`.heap` | 来源：`src/ps/lscript_ocm.ld:31`、`:54-56`、`:281-289` |
| `ps7_ram_1_S_AXI_BASEADDR` | `0xFFFF0000` | `0x0000FE00` | 只有 `.stack` | 来源：`src/ps/lscript_ocm.ld:32`、`:291-317` |

第一段的名字还叫 `ps7_ram_0`，但 ORIGIN 已经从 OCM 的 0x0 挪到 DDR 的 0x00200000（来源：`src/ps/lscript_ocm.ld:19-22`）。文件名仍叫 `lscript_ocm.ld` 是历史名，改名会牵动交付清单与版权登记，留到单独一轮（来源：`src/ps/lscript_ocm.ld:28`，债务也记在 `report/log/issues.md:14184-14186`）。
取值范围 [0x00100000, 0x3FFFFFFF] 的理由：这是 xparameters 里 `ps7_ddr_0` 的窗口，而 `translation_table.S` 也只把这一段映射成 cacheable（来源：`src/ps/lscript_ocm.ld:24-25`）。0x00200000 起留 12 MB，再往上是 PL 三个 bank 用的 0x10000000 / 0x10080000 / 0x10100000，中间这大片没人用（来源：`src/ps/lscript_ocm.ld:26-27`）。

### 8.2 入口为什么是 `_boot`，以及两次改动

`ENTRY(_boot)`（来源：`src/ps/lscript_ocm.ld:49`）。这一行改过两次（来源：`src/ps/lscript_ocm.ld:37-47`）：① FSBL 版写的 `ENTRY(_vector_table)`，配上 `--gc-sections` 之后 main / XSdPs 全被裁掉，产出一个 `.text` 只有 80 字节、**看起来成功了**的 ELF（来源：`src/ps/lscript_ocm.ld:38-40`）；② 当时改成 `_start`，代价是把整条标准启动链一起丢了，`ISSUES #42` 的"JTAG 起不来"、异常落到 0x0 恰好摆着的代码上、以及 newlib memcpy 在 MMU 关闭时发对齐异常，三个症状都是这一个根因（来源：`src/ps/lscript_ocm.ld:42-45`）。现在 `_boot` 设完 VBAR/栈/MMU 之后自己 `b _start`，所以 main/XSdPs 依然可达（来源：`src/ps/lscript_ocm.ld:45-47`）。试过命令行 `-Wl,-e,_boot`：被脚本里的 ENTRY 顶掉了，readelf 入口变成 0x0——别再用 `-e`（来源：`src/ps/lscript_ocm.ld:47`、`build/ps_app.mjs:120-121`）。

### 8.3 ELF 的产出脚本与它的成品自检

`build/ps_app.mjs` 是不用 IDE 直接把 `src/ps` 编成 ELF 的那一支（来源：`build/ps_app.mjs:3`），产物固定在 `ps_app.elf` 这个名字上、落在 `build` 目录（来源：`build/ps_app.mjs:33`）。退出码分三档：输入不在是 2（来源：`build/ps_app.mjs:35-40`）、编译/链接失败是 1（来源：`build/ps_app.mjs:73`）、"链接成功但成品不可执行"是 3（来源：`build/ps_app.mjs:137`）。
它必须自己转发编译器的 stderr，否则 `-Wall`/`-Wextra` 等于没开（来源：`build/ps_app.mjs:68-72`）。链接期三个归档都得给——2025.2 的 BSP 把驱动、standalone、xiltimer 分装成 `libxil.a` / `libxilstandalone.a` / `libxiltimer.a`，而 `_start` 只在中间那个里；少了它入口符号找不到、`--gc-sections` 又把没人引用的 main 裁掉，结果是"链接成功"但镜像是空的（来源：`build/ps_app.mjs:112-116`）。`-lm` 是 gamma 曲线的 `pow` 要的，放在 group 里是因为 newlib 的 libm 反过来依赖 libc（来源：`build/ps_app.mjs:123-124`）。 成品自检的硬要求是六个符号必须在（来源：`build/ps_app.mjs:139-144`）加一条体积下界 `.text < 20000` 就 FATAL（来源：`build/ps_app.mjs:145-148`）。之后是**三条等值判据**：ELF 入口 = `_boot`（来源：`build/ps_app.mjs:168-171`）、`_vector_table` = 第一个 LOAD 的 VirtAddr（来源：`build/ps_app.mjs:185-188`）、该基址在 `[0x00100000, 0x3FEF0000]` 且不为 0（来源：`build/ps_app.mjs:189-192`）；`readelf -l` 取不到 LOAD 行时判"这条判据没跑，不算通过"（来源：`build/ps_app.mjs:180-183`）。三条的由来是"以前这里只判 `_vector_table` 必须在 0x0，而那条恰恰是断电自启起不来的根"（来源：`build/ps_app.mjs:172-177`）。
取入口地址那条正则也修过：readelf 打的是 `0xcc`，以前写 `0*([0-9a-f]+)`，`0` 被 `0*` 吃掉后捕获到空 ⇒ 入口永远被读成 0，**判据本身就是坏的**（来源：`build/ps_app.mjs:158-160`）。
最后一行的形状以 `ENTRY _boot@0x` 打头、中间那句是 `基址在 DDR 窗口内（FSBL 会交接）`（来源：`build/ps_app.mjs:193`）。 一处要提前知道的形状：脚本末尾有一句 `fs.copyFileSync(OUT, path.join(root, 'build', 'ps_app.elf'));`（来源：`build/ps_app.mjs:195`），而 `OUT` 本身就是这个路径（来源：`build/ps_app.mjs:33`）——这一句在源与目的同路径下的行为我没有独立凭据，只把两处并排放着。零依赖的孪生实现是 `build/build_ps_app.py`（来源：`report/host_guide.md:152`），同一轮改造里两条脚本的判据一起换（来源：`report/log/issues.md:14155-14158`）。

### 8.4 BOOT.bin 的产出

`board/scripts/make_boot_image.sh` 把 FSBL + 位流 + 应用打成一个 QSPI 启动镜像（来源：`board/scripts/make_boot_image.sh:2`），三份输入的默认路径与"缺件或为空就 REFUSE"在同一条 `for` 里（来源：`board/scripts/make_boot_image.sh:31-34`）。bif 的形状是实测出来的：`the_design:` + 花括号里逐行一个文件、不写逗号（来源：`board/scripts/make_boot_image.sh:14-16`、`:41-47`），而 FSBL 那一行**必须**带 `[bootloader]`（来源：`board/scripts/make_boot_image.sh:42-43`）。调用形式那行是 `-arch zynq -image` 打头、再 `-w -o` 指定输出（来源：`board/scripts/make_boot_image.sh:50`），报成功但文件不在/为空仍然 REFUSE（来源：`board/scripts/make_boot_image.sh:53`）。末尾打六个数：`BOOT_BYTES`、`BOOT_MD5`、`BIT_MD5`、`BIT_MD5_12`、`APP_MD5`、`FSBL_MD5`（来源：`board/scripts/make_boot_image.sh:55-60`）。
写 flash 是另一支：`create_hw_cfgmem` → `program_hw_cfgmem`，属性表里 `PROGRAM.VERIFY` 置 1（来源：`board/tcl/flash_qspi.tcl:68-74`），而 2025.2.1 的对象没有 `PROGRAM.BBF_FILE`/`START_ADDRESS`/`STATUS`，写死会中断，所以先 `list_property` 再逐个设、缺的只报 SKIP（来源：`board/tcl/flash_qspi.tcl:62-65`、`:79`）；`PROGRAM.ZYNQ_FSBL` 又必须设，缺它报 `[Labtools 27-3203]`（来源：`report/technical-document.md:333-334`）。成败只看 `program_hw_cfgmem` 的返回码 `PROGRAM_RC`（来源：`board/tcl/flash_qspi.tcl:84-85`）。`PROGRAM.VERIFY=1` 那一步是**从 flash 读回逐字节比对**，不是主机侧比对 ⇒ "Verify Operation successful" 只证明片上内容与 BOOT.bin 一致（来源：`board/measured/flash_qspi_2026-10-05.txt:23-25`）。

---

**这一站的数据形状 + 出错时看到什么**：形状是构建脚本最后一行以 `ENTRY _boot@0x` 打头（来源：`build/ps_app.mjs:193`）、镜像 ~136 KB 且 `_boot@0x002000cc`（来源：`report/log/issues.md:14160`），BOOT.bin 的出身由 `BOOT_BYTES`、`BOOT_MD5`、`APP_MD5`、`FSBL_MD5` 这几个数说清（来源：`board/scripts/make_boot_image.sh:55`）。出错分三档：输入不在是退出码 2（来源：`build/ps_app.mjs:37`）、编译/链接失败是 1（来源：`build/ps_app.mjs:73`）、成品不可执行是 3（来源：`build/ps_app.mjs:137`）；判据自己坏掉的样子是那句"readelf 里取不到 LOAD 行 ⇒ 这条判据没跑，不算通过"（来源：`build/ps_app.mjs:181`），而 `PROGRAM.ZYNQ_FSBL` 缺了会报 `[Labtools 27-3203]`（来源：`report/technical-document.md:334`）。

## 9. 断电自启：拨码、BIF、FSBL 的那道 guard

### 9.1 拨码：三档与"软件读不回来"

实测的拨码表是 `JTAG 00 / QSPI 10 / SD 11`，ON=0，只在上电采样（来源：`report/log/issues.md:14088`）。"只在上电采样"的两条后果：拨完码必须断电重上，热插不生效；改了拨码这件事没法用软件直接读回来。
第二条有硬证据：同一支只读探针在 QSPI 档与 JTAG 档各跑一次，`MODE_PIN_M[2:0]` 两档都读 111，分辨不了拨码（来源：`board/measured/pl_config_state_jtagmode_2026-10-06.txt:6`、`report/log/issues.md:14128`）。能分辨的是 DONE(内部/引脚)、EOS、CPU0_STATUS_VALID（来源：`board/measured/pl_config_state_jtagmode_2026-10-06.txt:5`）——两份 `CONFIG_STATUS` 原文分别是 QSPI 档的 `01010110000100000111111111111100`（来源：`board/measured/pl_config_state_qspimode_2026-10-06.txt:24`）与 JTAG 档的 `01010110000000000001111100001100`（来源：`board/measured/pl_config_state_jtagmode_2026-10-06.txt:3`），`BOOT_STATUS` 那边是 QSPI 档 bit0=1（来源：`board/measured/pl_config_state_qspimode_2026-10-06.txt:53`）、JTAG 档全 0（来源：`board/measured/pl_config_state_jtagmode_2026-10-06.txt:4`）。结论那行写得很干净：flash 里有有效镜像时启动 ROM 会配置 PL（DONE=1），JTAG 档没人做这件事（来源：`board/measured/pl_config_state_jtagmode_2026-10-06.txt:7`）。
擦写还有两条规矩：先把启动模式拨到 JTAG 再写（QSPI 档下工具报 `[Xicom 50-100]`，这时它报成功也不可信），以及 `program_flash -erase_all` 在这颗片上失败、扇区擦可用（来源：`report/log/issues.md:14097-14099`）。

### 9.2 `[bootloader]` 这个属性：exit code 不是可启动性的证据

缺它的时候 bootgen 照样报 `Bootimage generated successfully`，但打出来的镜像头分区表偏移那三个字段 IHT+0x10 / +0x14 / +0x20 **全是 0**，启动 ROM 找不到分区、什么都不干；现场症状是"冷上电 + QSPI 档 ⇒ 串口零字节、`DONE` 不亮"（来源：`report/log/issues.md:14090-14092`）。 三条并列依据：厂商镜像同三个位置是 `0x00001700 / 0x00018008 / 0x00018008`；`bootgen -bif_help bootloader` 明写该属性 `SUPPORTED zynq, zynqmp, versal`，样例就是 `[bootloader] fsbl.elf`；补上属性后本工程这份变成 `0x00001700 / 0x0001f6f4 / 0x0001f6f4`（形状一致、数值差来自 FSBL 大小），体积 2,416,156 → 2,436,124（来源：`report/log/issues.md:14093-14096`）。 对照实验先证明板子无罪：把厂商 3,629,312 字节的 `BOOT.BIN` 在 JTAG 档写进同一颗 flash、拨到 `1 0` 冷上电 ⇒ `DONE` 亮，串口打出 `U-Boot 2023.01 ... CPU: Zynq 7z020 / SF: Detected w25q256 ... total 32 MiB`（来源：`report/log/issues.md:14086`，读数存 `board/measured/qspi_vendor_control_2026-10-06.txt`）。这条的意义是：板子、拨码表、启动 ROM、这颗 Winbond、写入流程**全部没问题**，问题只在镜像本身（来源：`report/log/issues.md:14088-14089`）。

### 9.3 FSBL 对"load 地址 0"的行为

`[bootloader]` 修好之后冷上电的**前一半**成立了（位流从 flash 起来），但 app 没跑。那一次的读数四行：`Load Addr: 0x00000000`（来源：`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt:67`）、`Exec Addr: 0x000000CC`（来源：`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt:68`）、`Handoff Address: 0x00000000`（来源：`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt:75`）、`No Execution Address JTAG handoff`（来源：`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt:77`）。
机制读到了源码那一行：平台自带 FSBL 的 `image_mover.c` 里 `LoadBootImage()` 遇到"PS 分区 && Load Address < DDR_START && Load Address==0 && 未签名未加密"直接 `break`，`ExecAddress` 因此从没被赋值；FSBL 的 `main.c` 见 `FsblStartAddr==0` 就转 JTAG handoff 等待，那段注释自己写着 "Loop will break when PS load address zero"（来源：`report/log/issues.md:14114-14117`、`src/ps/lscript_ocm.ld:20-22`、`build/ps_app.mjs:173-175`）。 为什么这不是"换个写法"能绕的：`readelf -l` 实测 `fsbl.elf` 与本应用的第一个 LOAD 都是 `VirtAddr 0x00000000`（OCM 低 192 KB 别名窗），FSBL 若真把 app 装到 0，就是一边执行一边覆盖自己（来源：`report/log/issues.md:14118-14119`）——而 FSBL 与本 app 本来就都在 OCM 那个 0x0 窗口里（来源：`src/ps/lscript_ocm.ld:22-23`）。
⇒ 修法只有一个方向：**应用链到 DDR**（来源：`report/log/issues.md:14120`），具体就是 `ORIGIN` 从 0x0 改 0x00200000（来源：`report/log/issues.md:14150-14151`）加上第 8.3 节那三条等值判据（来源：`report/log/issues.md:14155-14158`）。

### 9.4 成了的那一份长什么样

拨到 `1 0` + 断电重上（窗口 900 s、冷跑第 2 次，来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:2`）之后，串口依次打出下面这一串（"件"= `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt`）：

| 这一段在做什么 | 串口原文（照抄） | 出自 |
|---|---|---|
| 位流从 flash 起来 | `Boot mode is QSPI` 与 `QSPI is in 4-bit mode` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:14` 与 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:19` |
| 分区头 | `Partition Header Offset:0x00000C80` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:25` |
| bitstream 段 | `Load Addr: 0x00000000` 与 `FPGA Done !` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:32` 与 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:66` |
| 应用段 | `Load Addr: 0x00200000` 与 `Exec Addr: 0x002000CC` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:73-74` |
| 交接 | `Handoff Address: 0x002000CC` 再 `SUCCESSFUL_HANDOFF` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:107` 与 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:109` |
| 固件自己 | `[BOOT]`/`[CTRL]`/`[CFG]`/`[TEMP]` 四段 | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:112` |
| SD | 挂载摘要与 `autoplay: playing` | 来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:120` 与 `board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:134` |

`Handoff Address` 与 `Exec Addr` 同为 0x002000CC、且这一次不是 0——这一对就是"FSBL 愿意交接"的现场判据；同一份件还打了两行 21474836481 起步的分区号与 `Partition Count: 21474836485`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:27-26`）：21474836485 减去 5×2^32 = 21,474,836,480 之后低 32 位是 5，而日志实际只 dump 了 4 段头部（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:94`）——这一处打印口径我没有独立凭据，只把数与减法放在一起，不解释成因。
自启状态下的机器验收也跑了：`bash build/board_verify.sh --battery --geom --round=r126` ⇒ `RESULT board_verify PASS（判红的步骤：0）`，串口电池 105 条命令 98.2 s 全过、跑完回到初态、温度格三方对账自洽（来源：`report/log/issues.md:14170-14173`）；同一轮还留了 JTAG 三步链的 GREEN 件，里面 `PC_BEFORE_CON: 002000cc` 与 `GPIO@0x41200000 = 000B5000`（来源：`report/log/issues.md:14175`、实物 `board/measured/flash_20261006_1936.txt:125`、`:144`）。
件数与身份的落点：`BOOT_BYTES 2435868`、`BOOT_MD5 f62b1b8cc3bdc3ca45631c50a0205346`，三份输入里位流仍是 `cd04907e1369`（没动 RTL）、FSBL `46395a8c2ac1`、app `57fa442a7eaf`（来源：`report/log/issues.md:14161-14163`）；板上身份三件套的 12 位 md5 表在 `board/README.md:9-11`，同一组数也印在 `board/measured/flash_20261006_1936.txt:4-6`。
2,436,124（补 `[bootloader]` 之后、重链之前，来源：`report/log/issues.md:14096`）与 2,435,868（重链之后，来源：`report/log/issues.md:14161`）差 256 B——这两份是不同构建的产物，相减只能说明"这两次打出来的镜像本来就差 256 字节"，不能读成"重链让镜像变小了 256 B"。
两条**别念成已修好**的尾巴：① 冷上电那份回显里 SD 播到 frame 2324 报 `frame file not found on card`，随后 `sd remount` 打回 `dir map ok: 9 files` 并继续，本轮没有判（来源：`report/log/issues.md:14177-14180`）；② ELF 换了，凡是把 `d0b07f84a068` 当**现役** ELF 写的活句子都要改口，而引用历史门禁的引文不动（来源：`report/log/issues.md:14181-14183`）——旧 md5 仍留在 `board/measured/health_20261005_1031.txt:7` 这类当时的快照里，那是历史出身不是当前身份（来源：`LEARNING/README.md:38`）。

**这一站的数据形状 + 出错时看到什么**：形状是冷上电那 11 段串口顺序，最关键的两个数是应用分区的 `Load Addr: 0x00200000`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:73`）与 `Handoff Address: 0x002000CC`（来源：`board/measured/qspi_coldboot_selfboot_ok_2026-10-06.txt:107`）——两个都不是 0。出错三种，各指一处：串口零字节 + `DONE` 不亮 ⇒ bif 少了 `[bootloader]`、镜像头分区表偏移全 0（来源：`report/log/issues.md:14091-14092`）；位流起来了但停在 `No Execution Address JTAG handoff`（来源：`board/measured/qspi_coldboot_2026-10-06_fsbl_from_flash.txt:77`）⇒ app 还链在 0x0；`DONE` 亮、串口出 U-Boot ⇒ flash 与写入流程无罪，问题在镜像内容（来源：`report/log/issues.md:14086`）。


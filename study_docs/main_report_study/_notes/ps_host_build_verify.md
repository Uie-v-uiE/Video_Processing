# PS 固件 / 上位机 / 约束与构建流程 / 验证资产 —— 取证笔记

> 取证方式：逐文件读取 + `grep -n` 定位行号，所有结论都带 `file:line`（相对仓库根）。
> 环境：`D:\Xilinx\Prj\pro\Video_Processing`，分支 `main`，HEAD = `7f66175`。
> 工作区有 3 处与 HEAD 不同的地方，直接影响本文若干结论：
> `src/constraints/rk_zynq7020.xdc`（已改未提交）、`build/tcl/sweep_impl_strategy.tcl`（未入库）、
> `build/sweep_summary.txt`（未入库）—— 见 `git status --porcelain`。
> 标注「推断」的条目是从证据外推、未在源码/报告里直接写明的判断。

---

## 一、PS 裸机固件 `src/ps/main.c`（162 行，纯控制面）

### 1.1 骨架与「控制面」边界

- 文件头即声明职责边界：PS 只做 UART 命令 + AXI GPIO，UDP 视频数据面全部在 PL 的 `rtl/eth/*`（`src/ps/main.c:1-7`）；注释里给出两个地址：AXI GPIO `0x41200000`、DDR 帧 `0x10000000`（`src/ps/main.c:5-6`）。
- 头文件只有 `xparameters.h / xil_printf / xil_io / xil_cache / xil_exception / xuartps / sleep`（`src/ps/main.c:8-17`）：**没有任何 XEmac、lwIP、socket、TCP/IP 栈的头文件，也没有任何网络调用** ⇒ 这份固件与网络零关系，网络栈完全不在 PS 里（与 `src/host/HOST_GUIDE.md:23`「板卡 PL IP（RTL 固定参数）」一致）。
- `main()` 流程：`Xil_ExceptionInit` → `Xil_DCacheEnable` → `Xil_ICacheEnable` → `Xil_ExceptionEnable`（`src/ps/main.c:144-147`）→ 打印 `[BOOT]`（149）→ 写 `GPIO_TRI = 0`（150）→ `ctrl_apply()`（151）→ 三条 BOOT 提示（153-155）→ `while(1) uart_poll()`（157-159）。没有中断、没有定时器、没有 OS。
- **「它复位了什么？」—— 什么都没复位。** 全文没有 PCAP / SYSMON / FPGA 复位 / `XCpu*` / 重启调用；`[BOOT]` 只是打印（`src/ps/main.c:149,153-155`）。PL 侧复位由硬件自己解决：上电计数器驱动 `eth_rst_n`（`src/rtl/top/system_top.v:98-102`，24 位计数器在 `sys_clk` 50 MHz 下饱和，约 168 ms 后释放 —— 推断），以太网栈的 `rst_n = eth_rst_n & mmcm_locked`（`src/rtl/top/system_top.v:132`），而 `pl_video_top` 的 `sys_rst_n` 被永久绑 1（`src/rtl/top/system_top.v:162`）。
- 开机第一次 `ctrl_apply()` 写出的字：由初值 `cur_en=0 / cur_thr=80 / cur_src=0 / cur_zoom=1`（`src/ps/main.c:28-31`）+ 拼装式（35-36）得 `0x00025000`（bit17=1、[15:8]=80）——注意它**不等于** `build/tcl/set_src.tcl:8` 写的 `0x00010000`（后者 src=1、threshold=0）。

### 1.2 内存映射访问机制

- 基址与寄存器偏移用宏定义：`AXI_GPIO_BASE 0x41200000u`、`GPIO_DATA = +0x00`、`GPIO_TRI = +0x04`（`src/ps/main.c:24-26`）。
- 唯一一次寄存器写：`Xil_Out32(GPIO_DATA, v)`（`src/ps/main.c:37`）—— 单次 32 位宽、非「读-改-写」，整字重写；`FILL` 分支则用 `volatile u16 *p = (volatile u16 *)FRAME_ADDR` 直接指针写 DDR（`src/ps/main.c:108`）。
- 物理路径：PS 的 `M_AXI_GP0` → `axi_gp0_ic`（1×1）→ `axi_gpio_0/S_AXI`（`build/tcl/build_system_axigpio.tcl:79-82`），GP0 与 GPIO 的 `s_axi_aclk` 都挂在 `FCLK_CLK0`（100 MHz，`build/tcl/build_system_axigpio.tcl:28,59-68`），地址段 `0x41200000`/range 64K（BD 地址编辑器写入的 `SEG_axi_gpio_0_Reg`，本地生成物 `vivado_system/…/design_1.bd:1791`；`vivado_system/` 被 `.gitignore:2` 排除，仓库内可见证据是 `src/ps/main.c:24`、`build/tcl/set_src.tcl:8,13`、`README.md:16`）。

### 1.3 UART 行协议（115200，行尾 CR/LF 由上位机补）

- 收字节：轮询 `XUartPs_IsReceiveData(STDIN_BASEADDRESS)` + `XUartPs_RecvByte`（`src/ps/main.c:86-87`），`STDIN_BASEADDRESS` 来自 BSP 的 `xparameters.h`（PS 预设里 UART0 在 MIO 10..11，`build/tcl/build_system_axigpio.tcl:35`）。
- 行缓冲 `static char buf[32]`，遇 `\n`/`\r` 结束并解析（`src/ps/main.c:84-88`）；第 32 个字符之后的字符被**静默丢弃且不 flush 缓冲**（`src/ps/main.c:136`）⇒ 超长垃圾行的前 31 字符仍会被当成命令解析（推断）。
- 解析优先级（自上而下 `else if`，`src/ps/main.c:92-133`）：
  1. **位串**：`parse_bits()` 成功（`src/ps/main.c:66-80`）→ `ctrl_set_en()`。规则：逐字符只接受 `'0'/'1'`（72），遇 `'\r' '\n' ' '` 停止（71），**最左字符 = bit0**（`en |= bit << n`，74），最多 5 位，第 6 位返回 -1（73）⇒ `"000000"` 不是命令而落未知分支；空串也返回 -1（77）。
  2. `SRC0` / `SRC1`：`strncmp(buf,"SRC0",4)` ⇒ 前缀匹配，`SRC1xyz` 也接受（`src/ps/main.c:94-97`）。
  3. `ZOOM0` / `ZOOM1`：`strncmp(...,5)`（`src/ps/main.c:98-101`）。
  4. `TH<十进制>`：`strncmp(buf,"TH",2) && idx>2` + `atoi(buf+2)`，越界钳到 0..255（`src/ps/main.c:102-106`）⇒ `TH80abc` 解析为 80（atoi 行为，推断）。
  5. `FILL`：PS 写 DDR 诊断色块（`src/ps/main.c:107-127`，见 1.5）。
  6. `STAT`：只回显软件影子值，不读硬件、不读 PL 状态（`src/ps/main.c:128-130`）。
  7. 其余：回显 `[CMD] <行>` + 帮助 `00111 SRC0 SRC1 TH80 ZOOM0 ZOOM1 FILL STAT`（`src/ps/main.c:131-133`，同一份列表也印在 BOOT 阶段 154）。
- 上位机侧协议对齐：115200 8N1、命令后自动补 CR+LF（`src/host/HOST_GUIDE.md:128-131`）；`src/host/serial_ctrl.py:100,102` 另加 `q/quit/exit`、`help/?`（这两个是 PC 侧解释，板端会落到「未知命令」分支）。

### 1.4 控制字位序与写回

- 拼装式（`src/ps/main.c:33-40`）：`v = (cur_en & 0x1F) | (cur_thr << 8) | (cur_src << 16) | (zoom ? 1 : 0) << 17`，一次 32 位写 `0x41200000`；随后 `[CTRL] AXI_GPIO=0x%08x en=%02x thr=%d src=%d zoom=%d` 回显（38-39）。
- 四个 setter 都是「改影子 + 全字重写」：`ctrl_set_en`（42-46，掩 0x1F）、`ctrl_set_thr`（48-52）、`ctrl_set_src`（54-58，`src?1:0`）、`ctrl_set_zoom`（60-64）⇒ 任何命令都会重写整个控制字，不存在按位更新。
- **效果位顺序（左起 bit0）：`gray / binary / blur / sobel / invert`** —— 三处一致：`src/host/HOST_GUIDE.md:149`、`src/rtl/process/proc_pipeline.v:3`（同时 24-28 证明 bypass = `~effect_en[i]`，位=1 即开启）、`report/ARCHITECTURE.md:149`。`bit[15:8]=threshold`、`bit[16]=src_sel(0=彩条 1=视频)`、`bit[17]=zoom_en 预留`（`report/ARCHITECTURE.md:150-152`）。
- **`ZOOM0/1` 是空命令**：PL 侧 `zoom_en` 被常量绑 1（`src/rtl/top/system_top.v:165`），与 `src/ps/main.c:31`「当前 RTL 常开，此位预留给控制」和 `src/ps/main.c:155` 的 BOOT 提示一致；`bit[31:18]` 无人使用（`src/rtl/top/system_top.v:164` 只取 `[4:0]/[15:8]/[16]`）。

### 1.5 `FILL`：唯一一处 PS 直接写帧缓冲内存

- 行为（`src/ps/main.c:107-127`）：以 `FRAME_W=512 / FRAME_H=300 / FRAME_ADDR=0x10000000`（19-22）循环 `512*300` 次 u16 写（110），图案为：`y<8` 绿 `0x07E0`；左上 256×142 红 `0xF800`；右上 黄 `0xFFE0`；左下 蓝 `0x001F`；其余 白 `0xFFFF`（113-122）；随后 `Xil_DCacheFlushRange(0x10000000, 307200)`（125，`FRAME_BYTES` 见 21）并 `ctrl_set_src(1)`（126），打印 `[CMD] FILL diagnostic via PS DDR`（127）。
- 尺寸与 PL 完全对齐：`pl_video_top #(.IMG_W(512), .IMG_H(300), … .BASE_ADDR(32'h1000_0000))`（`src/rtl/top/system_top.v:161`）。
- **它写的正是 PL 的乒乓 bank0**：`BANK0=32'h1000_0000`、`BANK1=BASE_ADDR+32'h0008_0000`（`src/rtl/eth/eth_udp_video_top.v:55-56`；`src/rtl/eth/ddr_bank_commit.v:17-18`）⇒ FILL 与 PL 的入包写入抢同一块内存（bank 间隔 512 KiB，而一帧只有 300 KiB，推断：这是给 1024×600/对齐留的余量）。
- **但 FILL 上屏要求网线断开**：显示侧有两条互斥的 DDR→BRAM 读路径，`axi_frame_writer64`（PS-FILL 消费路径）的 `enable = eth_mode ? 1'b0 : src_sel`、`frame_start = eth_mode ? 1'b0 : ps_frame_start`（`src/rtl/top/pl_video_top.v:327-328`），`eth_mode` 就是同步后的 `eth_link`（225-230），而 `ps_frame_start` 的翻转条件也要求 `!eth_link`（312）⇒ 链路正常时 FILL 的 DDR 内容不会被搬到显示缓存（推断，依据以上三行）。
- 与 `src/ps/README.md` 的三条陈旧说法冲突：BSP 依赖 `xgpio`、路径 `output/system.xsa`、以及「收到第一个完整 UDP 帧后软件自动置 src_sel=1」（`src/ps/README.md:3-6,16`）—— 固件里没有任何自动切源逻辑（`src/ps/main.c` 全文），`src/ps/README.md:11-15` 还写着 EMIO GPIO 映射，而 EMIO 方案早已被弃用（`report/ARCHITECTURE.md:155`「勿用 EMIO：本板 bank2 读回恒 0」、`build/tcl/build_system_axigpio.tcl:39` 显式关闭 EMIO GPIO）。

---

## 二、硬件实际使用的 AXI GPIO 寄存器映射

- IP 配置：`axi_gpio:2.0`，`C_GPIO_WIDTH=32`、`C_ALL_OUTPUTS=1`、`C_INTERRUPT_PRESENT=0`（`build/tcl/build_system_axigpio.tcl:47-52`），`C_IS_DUAL` 未设 ⇒ **单通道 32 位纯输出、无中断**（生成物 `vivado_system/…/design_1.bd:1222-1229` 记录同值）。
- 通道数：1（只有 channel0）；宽度：32 位，全部输出。
- 寄存器：`0x00` = DATA（`src/ps/main.c:25`、`build/tcl/set_src.tcl:13` 的 `mwr -force 0x41200000`）；`0x04` = GPIO_TRI0（`src/ps/main.c:26`）。由于 `C_ALL_OUTPUTS=1`，方向寄存器不可编程 ⇒ `src/ps/main.c:150` 那次 `Xil_Out32(GPIO_TRI, 0)` 是**空操作**（推断，由 IP 参数直接决定）。
- 位 → 含义 → 消费者：
  - `[4:0] effect_en` → `src/rtl/top/system_top.v:164` → `pl_video_top` 的 `effect_en`（`src/rtl/top/pl_video_top.v:17`）→ `effect_ctrl` 两级同步（`src/rtl/process/effect_ctrl.v:12-27`）→ `proc_pipeline` 按位旁路（`src/rtl/process/proc_pipeline.v:3,24-28`）。
  - `[15:8] threshold` → `threshold`（`src/rtl/top/pl_video_top.v:18`）→ 同步后送二值化（`src/rtl/process/effect_ctrl.v:13,26-27`）。
  - `[16] src_sel` → 3 级同步成 `src_sel_pix`（`src/rtl/top/pl_video_top.v:273-278`）→ 源 mux（398、401）、LED1（518）、`status`（520）。
  - `[17] zoom_en`：**未连接**，`system_top.v:165` 绑 `1'b1`。
- 复位默认值：`effect_ctrl` 复位时 threshold=80、en=0（`src/rtl/process/effect_ctrl.v:16-22`）；固件阈值同为 80（`src/ps/main.c:29`）。而 JTAG 流程用的 `set_src.tcl` 写 `0x00010000` ⇒ src=1 且 **threshold=0**（`build/tcl/set_src.tcl:8`）；这条正是 `src/host/measure_v63.mjs:10` 要求的前置「GPIO=0x00010000」。若此时发 `01000` 开二值化，会拿到阈值 0（推断）。
- 到达顶层的连线：`make_bd_pins_external [get_bd_pins axi_gpio_0/gpio_io_o]` 并改名 `GPIO_0_tri_o`（`build/tcl/build_system_axigpio.tcl:97-102`）→ `design_1_wrapper` 端口（`src/rtl/top/system_top.v:77`）→ `wire [31:0] gpio_o`（44）→ `pl_video_top`（161-165）。
- 跨时钟域性质：GPIO 在 `clk_fpga_0`（FCLK 100 MHz）域，被 `clkout0_1`（50 MHz 像素）域采样。`effect_ctrl` 的 `en_meta/en_sync` **没有 `ASYNC_REG` 属性**（`src/rtl/process/effect_ctrl.v:12-13`）⇒ 方法学报告点名一处「Missing property on synchronizer」（`build/methodology.rpt:35,938-941`）；对比 `pl_video_top.v:91,225,273,294,314,468` 与 `src/rtl/video/frame_commit_lock.v:61,68,117`、`src/rtl/eth/ddr_bank_commit.v:50` 都打了 `ASYNC_REG`。

---

## 三、上位机 Node 工具集（`src/host/*.mjs`）

### 3.0 公共设施与三条通路

- 路径统一由 `src/host/repo_path.mjs:10-16` 提供：`ROOT/HOST/MEASURED`，并 `mkdirSync(MEASURED,{recursive:true})`；`host(f)`、`dump(f)` 拼路径，落盘目录固定 `<repo>/data/measured`。
- 与板子通话的三种方式：**UDP**（`video_sender.mjs`、`udp_sink_check.mjs`、`ingress_probe.mjs` 的发包半边）、**JTAG/xsdb 子进程**（`ddr_verify.mjs`、`ingress_probe.mjs`，以及被 `set_src.tcl` 等 xsdb 脚本承担的 GPIO 写）、**串口由 Python 负责**（`src/host/HOST_GUIDE.md:126-133`，`serial_ctrl.py`；.mjs 里没有任何串口代码）。
- xsdb 路径默认写死 `D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat`、`--port 3121`（hw_server）：`src/host/ddr_verify.mjs:28-29`（可 `--xsdb` 覆盖）；`src/host/ingress_probe.mjs:19` 写死且**不可覆盖**，同时仍连着 3121（`src/host/ingress_probe.mjs:66`）。
- **两个脚本因缺 import 而不可用**：`src/host/ddr_holemap.mjs:23` 使用 `MEASURED` 但 11-12 行只 import 了 `path`/`readFileSync` ⇒ 不带文件参数时 `ReferenceError`；`src/host/ingress_probe.mjs:20` 的 `const WS = MEASURED;` 同样没有 import（13-14 行）⇒ **一加载就崩**，该探针目前只能当文档读。

### 3.1 `video_sender.mjs`（225 行）— 推流 + 自描述图案生成器

- 解决的问题：不依赖 python/numpy 也能推流并产出可反解的图案（`src/host/HOST_GUIDE.md:213-214`「判据类工具用 Node 写，是因为验收 PC 上不一定有 python」）。
- 协议：每包 `[u32 LE byte_offset][RGB565 载荷]`，`HDR=4`、`W*H*2=307200`（`src/host/video_sender.mjs:20,177-189`）；一帧 221 包（`Math.ceil(307200/1392)`，199；实测行见 `data/measured/board_measure_15fps.txt:3`）。
- 载荷长度规则：默认 `MTU=1392`，必须是 **8 的倍数**，否则打印警告「包边界会毁掉 64bit 字（规律黑点）」（`src/host/video_sender.mjs:21-24`）；原始依据在 Python 版注释里：1396 不满足（`1396 % 8 == 4`）、1392 满足且 `1392+4+20+8+14=1438<1500`（`src/host/video_sender.py:32-33`）。`--mtu-payload` **只为复现 bug 而存在**（`src/host/video_sender.mjs:22`）。
- 开关：`--ip/--port/--src`（`192.168.1.10 / 5001 / 192.168.1.100`，`src/host/video_sender.mjs:32-34`，bind 失败则退回默认路由 155-158）、`--fps`（默认 15，35）、`--no-pace`/`--pace-mpbps`（默认 15 MB/s，36-37）、`--count`（38）、`--test`（39）、`--dump`（41）、`--wordid-add`（125）、`--mtu-payload`（23）。
- 限速实现：帧内逐包匀速，用 `performance.now()` + `Atomics.wait` + 尾部忙等（`src/host/video_sender.mjs:160-175`），理由写在注释里：15 MB/s 下每包只有 ~93 µs 预算，`Date.now()` 的 1 ms 精度不够。
- `--count` 收口：发完不立刻关 socket，而是等 2000 ms 让内核 tx 队列排空（`src/host/video_sender.mjs:208-216`），注释明确「否则 --count 1~2 的短测会把大部分包丢在发送队列里」。
- 判据：本脚本自身不判 PASS/FAIL；它的可判定性来自图案（第四节）与 `--dump` 落盘的参考帧（`src/host/video_sender.mjs:40-42,200-203`：保留**最后两帧**，`<file>` 与 `<file>.prev`，正好对应乒乓的两个 bank）。

### 3.2 `measure_v63.mjs`（43 行）— 一条命令完成复验

- 定位：「推 `frameid` → **发完** → JTAG 回读两个 bank → 包内相位丢字签名」（`src/host/measure_v63.mjs:3`）。
- **停止推流再回读这条规则**写在文件头：回读要几秒，边推边读会让每个地址段读到不同时刻的帧，命中率统计全部作废（`src/host/measure_v63.mjs:5-6`，并举证「bank0 帧号跨度 130..152 就是这么来的」；同规则另见 `src/host/HOST_GUIDE.md:233-234`、`board/README.md:68`、`skill/frameid_loss_signature.md:13-14`）。
- 开关：`--fps`（默认 15）、`--pace-mpbps`（15）、`--count`（**默认 `ceil(fps*4)+20`**，`src/host/measure_v63.mjs:20-23`）、`--live`（22：边推边读，只跑 6 秒就 `kill` 自己起的 PID，明确「只看 16bit 粒度探针，不看命中率」，`src/host/measure_v63.mjs:8-9,28-33`）。
- 顺序与判据无关的细节：`spawnSync` 推流 → 打印退出码 → `Atomics.wait` 500 ms「让最后一帧落位」→ `ddr_verify.mjs --frameid` → 最后无条件再跑 `ddr_stale.mjs`（`src/host/measure_v63.mjs:35-42`）。前置条件（ps7_init + program bit + set_src + hw_server 在跑）写在 `src/host/measure_v63.mjs:10`。
- PASS/FAIL 判据（继承自 `ddr_stale.mjs`）：最新帧 16bit 命中率 ~100% 且包内六个字节带丢字率全 0 ⇒ 入包链无损（`src/host/ddr_stale.mjs:84-87`、`data/measured/board_measure_15fps.txt:27-29`）。

### 3.3 `ddr_verify.mjs`（261 行）— 只做 JTAG 回读 + 分析

- 解决的问题：**不看屏幕**也能判定 `UDP→reasm→CDC→AXI→DDR` 有没有丢字/错位（`src/host/ddr_verify.mjs:3-5`）。
- 回读常量：`WORDS=38400`（=512×300×2/8）、`BANK0=0x10000000`、`BANK1=0x10080000`、`CHUNK=1000`、`U32=WORDS*2`（`src/host/ddr_verify.mjs:17-20,34`）⇒ 每 bank 76800 个 u32，分 77 次 `mrd -force`。
- 生成的 tcl 脚本要点（`src/host/ddr_verify.mjs:36-56`）：`connect -host localhost -port 3121`；`targets -set -filter {name =~ "*#0"}` 选 A9#0；**`catch {rst -processor}`** 并 `after 200` —— 注释解释得很清楚：Vitis 应用开了 D-Cache，`mrd` 走 A9 端口会读到缓存旧数据，复位并暂停核心可连 MMU/Cache 一起关掉，而 DDR 控制器保持已初始化（`src/host/ddr_verify.mjs:40-44`）；**故意不 `con`**，因为 A9 重跑 boot ROM 会把 SD/QSPI 里的旧 bitstream 刷回 PL（`src/host/ddr_verify.mjs:53`）。这三条即 `board/README.md:64-69` 的「JTAG 回读三条硬规则」。
- 开关：`--bank-only 0|1`、`--xsdb`、`--port`、`--add`（与 `--wordid-add` 对应）、`--frameid`、`--ref <file>`（`src/host/ddr_verify.mjs:28-33,233-242`）；落盘 `data/measured/ddr_dump.out`（58，`dump()` 见 `src/host/repo_path.mjs:14,16`；该文件被 `.gitignore:56` 排除，仓库里只留了解包样本 `data/measured/ddr_dump_20260921_15fps.out.gz`）。
- 三种分析模式：
  1. **默认 wordid 模式** `analyse()`（`src/host/ddr_verify.mjs:69-116`）：期望 `u32 = v|(v<<16)`，其中 `v = ((w>>1)+ADD)&0xffff`（81-84，注释说明「同一个 64bit 内的两个 32bit 都等于 w>>1」）；不匹配时把两个 16bit lane 分类为 `never`（值=0，从未被写）、`stale`（值=零相位图案，即上一轮残留）、`other`（85-93）—— 这就是「相位/空洞判别」；空洞按 16 行为一组归档（95-97,109-114）；末尾打印 `live bank = … → 入包链无空洞 / 有空洞`（256-258）。
  2. **`--frameid` 模式** `analyseFrameId()`（`src/host/ddr_verify.mjs:167-219`）：见 3.4 的反解；输出帧号跨度、`同一字内两 lane 帧号不同的字数`、按字位置 10 段的「新帧占比」、以及 `mixedBands/seamBands` 判据（209-218：mixedBands 小且集中在少数行 ⇒ 整行接缝；遍布全帧 ⇒ 逐字混合）。
  3. **`--ref` 模式** `analyseRef()`（`src/host/ddr_verify.mjs:136-164`）：与 `--dump` 的最后两帧逐 32bit 比对，图案任意；判读文案（253-255）：某个 bank 与「最后一帧」mismatch=0 ⇒ 撕裂不在 DDR 而在显示侧；两个 bank 都不匹配任何一帧 ⇒ DDR 里就是两帧逐字混合，去查乒乓切换时序。
- **一个脚本瑕疵**：`--frameid` 模式下 `hit` 永远为 null、`refs` 为空 ⇒ 结尾必然落到 `else` 打印「两个 bank 都没读到有效 wordid 图案：帧没有写进 DDR」（`src/host/ddr_verify.mjs:249-261`），实测输出里就带着这条假警报（`data/measured/board_measure_15fps.txt:23`，同一次测量上面两行却是 100.0%）。判据不受影响，但读日志的人会被误导。

### 3.4 反解技巧（`ddr_verify` + `ddr_stale` 共用）

- 图案：第 `w` 个 **64 bit** 字的 4 个 16bit lane 全写 `(w + n) & 0xffff`（`src/host/video_sender.mjs:73-82`，n=帧号）。
- 反解：`n_implied = (lane_value - w64) & 0xffff`（`src/host/ddr_verify.mjs:176-177`；`src/host/ddr_stale.mjs:39-43` 在 153600 个 lane 上同样计算，`LANES = WORDS*4`）。
- 由此得到**三个维度**的丢字签名（`src/host/ddr_stale.mjs:5-11` 的文件头把它列成机理对照表；同一份判据在 `skill/frameid_loss_signature.md:15-23` 被写成通用技能）：
  - 包内字节偏移分带 `BANDS=[[0,48],[48,96],[96,192],[192,384],[384,768],[768,1392]]`，`off = (k*2) % PAYLOAD`，`PAYLOAD=1392` 硬编码（`src/host/ddr_stale.mjs:22-23,58-67`）⇒ 呈固定台阶 = 下游平均排空速率跟不上。
  - 连续丢字游程分布 + 最长带 + `≥696`（整包长度一半）段数（`src/host/ddr_stale.mjs:69-81`）。
  - 同一 u32 内两个 16bit 是否属于不同帧 ⇒ 丢在 16bit 粒度（CDC 写侧门控）而非整字（`src/host/ddr_stale.mjs:52-56`）。
- 「换帧是否原子」的判据 = 每个 bank 的**帧号跨度**（健康 = 每 bank 恰好一帧）：`skill/frameid_loss_signature.md:22-23`、`src/host/ddr_verify.mjs:190`。
- 注意：`PAYLOAD` 固定 1392 ⇒ 若上一轮用 `--mtu-payload 1396` 发包，包内分带会整体错位（推断，由 `src/host/ddr_stale.mjs:22,61` 的硬编码得出）。

### 3.5 `ddr_stale.mjs` / `ddr_holemap.mjs` / `ingress_probe.mjs` / `udp_sink_check.mjs`

- `ddr_stale.mjs`：判据核心，输入是上一次 `ddr_verify` 的落盘文件（默认 `data/measured/ddr_dump.out`，可用位置参数覆盖，`src/host/ddr_stale.mjs:19`）；文件头注释仍写着老路径 `build_v6/_ddr_dump.out`（`src/host/ddr_stale.mjs:3`）⇒ 目录重构后注释未同步（`ddr_holemap.mjs:4` 同样如此）。
- `ddr_holemap.mjs`（早期定位用，`src/host/HOST_GUIDE.md:222`）：对 **wordid**（`lo===w>>1`）逐 lane 打 0/1 位图，输出坏游程直方图、最长坏游程（并换算成「占一包百分之几」）与坏 lane 在包内 16 个桶里的分布（`src/host/ddr_holemap.mjs:28-42,44-61,63-71`）；`--bank`（十六进制串，默认 `10000000`）与 `--payload`（默认 1392）可覆盖（9,20-21）。
- `ingress_probe.mjs`：**定点注入**实验——只发 K 个包（图案是「字号 + 固定帧号 TAG」，TAG 默认 200），等 1.5 s 排空，再用 JTAG 把前 `K*MTU/4` 个 u32（= `K*174` 个 64bit 字，1392/8=174）读回来，统计落位率、**从第几个字开始丢**（直接暴露缓冲深度）、丢失间距分布（`src/host/ingress_probe.mjs:3-11,32-37,48-60,62-113`）；注释给出仿真侧的对应结论：`tb_v6_pingpong` 里「端口被独占 N 拍 ⇒ 丢字起始位置恰好等于打包器 FIFO 深度 512」（`skill/frameid_loss_signature.md:30-31`）。
- `udp_sink_check.mjs`：本机环回自检，用 `127.0.0.1:5001` 收，按 `offset==0` 切帧（`src/host/udp_sink_check.mjs:27-37`），判据 = 每帧累计载荷字节 **恰好等于 307200**（44），输出 `frames/complete/incomplete/err`（46）；`--expect-frames` 收够就收工，否则 `--timeout-ms`（默认 20000）后强制出报告（18,53）。它的目的是「把上位机丢包和板端丢包区分开」（3-4）。小瑕疵：文件头声称「按 offset 检查是否有缺洞」，但 `cur.offs` 这个 Set 只被写入（35）从未被读取 ⇒ 实际只有字节总数判据（推断：单包错偏移但长度相同会被漏判）。

---

## 四、`video_sender.mjs` 的自描述测试图案

| `--test` | 图案内容 | 编码了什么 / 判什么 | 证据 |
|---|---|---|---|
| `bars`（默认） | 8 px 横纹整体滚动 + 每帧右移的黄色方块 + 左边缘 8 列「奇偶行洋红/黑」标记 | 黑横纹一眼可见；方块拖影 ⇒ 换帧不原子；行序错乱 ⇒ 左边缘标记 | `src/host/video_sender.mjs:11-13,134-151`（`phase=n%64`、`cx=((n*7)%(W+120))-60`、146-147） |
| `grad` | `(x+2n, 2y, 128)` 缓变渐变 | 量化/色带 | `src/host/video_sender.mjs:14,141-142` |
| `edge` | 整屏逐帧黑白交替（`alt = n&1 ? 255 : 0`） | 换帧原子性：非原子会看到灰行/残影 | `src/host/video_sender.mjs:15,135,139-140` |
| `blocks` | 四象限大色块 + 1~2 px 参考线 + 每帧左移 6 px 的黄块 | 纯色场不会有手机摩尔纹 ⇒ 屏幕上的椒盐点必为真实数据问题 | `src/host/video_sender.mjs:104-121`（`cx=((n*6)%(W+120))-60`，115-116） |
| `hold` | 与帧号完全无关的图案 + 方块固定居中 + 蓝象限 1 px/32 白网格 | **两帧相同却仍撕裂 ⇒ 显示通路问题**；干净 ⇒ 之前的撕裂来自图案被裁切/只在运动时混合 | `src/host/video_sender.mjs:84-103`（注释 85-88） |
| `move` | 白象限内部往返的红块（270..410，永不触边）+ 蓝象限 4 px 粗网格 + 边框/十字参考线 | 重影/拖尾 ⇒ 换帧不原子；若 4 px 粗网格不再闪 ⇒ 之前 1 px 细线闪烁是最近邻缩放走样（落到采样间隙），不是数据问题 | `src/host/video_sender.mjs:52-71`（注释 52-55）；板上验收项 `board/README.md:58` |
| `wordid` | 第 w 个 64bit 字填 `(w + add)`，`--wordid-add` 做相位位移 | 只能验地址映射；加偏移是为了区分「这一帧真丢了」和「上一帧碰巧写过同样的值」 | `src/host/video_sender.mjs:122-132`（注释 123-124）；`src/host/HOST_GUIDE.md:232` |
| `frameid` | 第 w 个 64bit 字填 `(w + 帧号)` ⇒ 回读可反解「这个字是第几帧写进去的」 | **唯一能发现「逐帧丢字」的图案**；定量测换帧滞后与逐字混合程度 | `src/host/video_sender.mjs:73-82`（注释 74-75）；`src/host/HOST_GUIDE.md:232`；`skill/frameid_loss_signature.md:9-12` |

- 关键设计：**像素值同时编码了地址与时间**——`w` 由地址可推知（回读时按 `addr-base` 算出），所以 `value - w` 就是帧号；反过来说，一个恒定图案（值=字号、纯色、棋盘）在结构上「发现不了逐帧丢字」（`skill/frameid_loss_signature.md:12`）。
- `frameid` 的每个 64bit 字内 4 个 lane 写同一个值，因此 `wordid/frameid` 的分辨率是 64 bit（4 像素）；16bit 粒度的丢字靠 `analyseFrameId` 比较同一 u32 的两个半字来暴露（`src/host/ddr_verify.mjs:176-183`）。

---

## 五、约束清单 `src/constraints/rk_zynq7020.xdc`

> 工作区 59 行 / HEAD 55 行（差 4 行注释、少 1 行被删的 `-from`）；这是**全仓库唯一手写的 XDC**（`find` 只此一处 + PS7/IP 的生成 XDC）。

### 5.1 时钟：创建了什么、没创建什么

- `create_clock` 共 **2 条**：
  - `sys_clk`：周期 20.000 ns（50 MHz），引脚 W17 LVCMOS33（`src/constraints/rk_zynq7020.xdc:5-6`）。
  - `eth_rxc`：周期 8.000 ns（125 MHz，RGMII RX 时钟），引脚 Y19 LVCMOS33（`src/constraints/rk_zynq7020.xdc:20,36`）。RGMII 是 DDR 接口，但只声明了单沿时钟，无 `-waveform`/下降沿约束（推断）。
- **`create_generated_clock` = 0**（`grep -c` 结果），MMCM 的三个输出完全交给工具自动推导：综合日志 `INFO: [Timing 38-2] Deriving generated clocks […/rk_zynq7020.xdc:53]`（`vivado_system/zynq_video_sys.runs/impl_1/runme.log:39`）。推导结果确实进了报告：`clkfbout / clkfbout_1 / clkout0_1(20 ns=50 MHz) / clkout1_1(4 ns=250 MHz) / clkout2(5 ns=200 MHz)`（`build/timing_summary.rpt:164-171`），与 `MMCME2_BASE` 参数一一对上：`CLKFBOUT_MULT_F 20 → VCO 1000 MHz`、`CLKOUT0_DIVIDE_F 20 → 50 MHz 像素`、`CLKOUT1_DIVIDE 4 → 250 MHz 5x`、`CLKOUT2_DIVIDE 5 → 200 MHz IDELAY 参考`（`src/rtl/clocks/clk_gen.v:15-29`，BUFG 见 53-56）。
- `clk_fpga_0`（FCLK 100 MHz）**不是本文件创建的**，而是 PS7 IP 生成的 XDC：`create_clock -name clk_fpga_0 -period 10 [get_pins PS7_i/FCLKCLK[0]]` + `set_input_jitter clk_fpga_0 0.3`（`vivado_system/…/design_1_processing_system7_0_0.xdc:20-21`，生成物，`.gitignore:2` 排除）。DDR/FIXED_IO/MIO 的 105 条 `PACKAGE_PIN` 也全在该 IP XDC 里（同文件，例如 `MIO[53]=C12`），所以手写 XDC 里没有 DDR 引脚是**正常的**而不是遗漏。
- **`set_input_delay` = 0、`set_output_delay` = 0**（`grep -c` 均为 0）⇒ 除两条 `create_clock` 外，所有 I/O 时序关系为零。工具侧的直接后果：`check_timing` 报「5 个输入无输入延迟(HIGH) / 2 个输入无输入延迟但有假路径(MEDIUM)」、「6 个输出无输出延迟(HIGH) / 6 个输出无输出延迟但有假路径(MEDIUM)」（`build/timing_summary.rpt:98-110`），方法学 `TIMING-18` 共 7 处点名：`eth_rx_ctl`、`eth_rxd[0..3]`（缺输入延迟）+ `led[0]`、`led[1]`（缺输出延迟）（`build/methodology.rpt:36,943-976`）。
- 其他缺失项（同一 grep 计数均为 0）：`set_clock_uncertainty`、`set_propagated_clock`、`set_max_delay`、`set_bus_skew`、`set_max_fanout`/`DONT_TOUCH`/`KEEP_HIERARCHY`。没有 UART 相关约束，因为 PL 没有 UART 端口（UART0 属 PS，MIO 10..11，`build/tcl/build_system_axigpio.tcl:35`）。
- RGMII RX 的采样相位不用约束而用硬件抽头：`IDELAYE2` `IDELAY_TYPE("FIXED")`、`REFCLK_FREQUENCY 200.0` + `IDELAYCTRL(REFCLK=idelay_clk)`（`src/rtl/eth/rgmii_rx.v:60-71`），`IDELAY_VALUE(15)` 由顶层参数给定（`src/rtl/top/system_top.v:129`）⇒ 15×(1/200 MHz/4)? 具体延迟只能算作 ~7.5 ns 量级（推断：以 200 MHz 参考、每拍 ~78 ps 为常见值，实际数值本报告未核实）。

### 5.2 引脚 / 电平（28 条 `PACKAGE_PIN + IOSTANDARD`）

- 配置电压：`CFGBVS VCCO`、`CONFIG_VOLTAGE 3.3`（`src/constraints/rk_zynq7020.xdc:2-3`）。
- 分类（`src/constraints/rk_zynq7020.xdc:5-34`，共 28 条 `PACKAGE_PIN`+`IOSTANDARD`）：`sys_clk` W17（5）；按键 `key1_n` W18 / `key2_n` V14 输入（8-9）；LED `led[0]` V15 / `led[1]` V13（10-11）；HDMI TMDS 8 脚 **TMDS_33**：`tmds_clk_p/n` W16/Y16、`data_p/n[0]` AA17/AB17、`[1]` U17/V17、`[2]` U15/U16（12-19）；RGMII RX 6 脚 `eth_rxc/eth_rx_ctl/eth_rxd[0..3]` = Y19/V19/W20/W21/U20/V20（20-25）；RGMII TX 6 脚 `eth_tx_clk/eth_tx_ctl/eth_txd[0..3]` = AB22/AB21/T21/U21/AA22/AA21（26-31）；管理面与 PHY 复位 `eth_mdc` AB20、`eth_mdio` AB19、`eth_rst_n` Y21（32-34）。`grep -o "PACKAGE_PIN …" | uniq -d` 无重复引脚。
- **注意：所有 RGMII 脚用 LVCMOS33 而非 LVCMOS18**，而 PS 的 `PRESET_BANK1_VOLTAGE` 设 1.8 V（`build/tcl/build_system_axigpio.tcl:41`）—— 那是 PS MIO bank，与这些 PL 引脚无关（推断）；`led[1]` 上挂着 `src_use`、`led[0]` 上是心跳/拷贝超时告警（`src/rtl/top/pl_video_top.v:516-518`），所以 LED 也是「可观测出口」而不只是装饰。
- 管理面在 RTL 里是桩：`assign eth_mdio = 1'bz; assign eth_mdc = 1'b0;`（`src/rtl/top/system_top.v:103-104`）⇒ PL 不通过 MDIO 配置 PHY（依赖 PHY 上电默认值 —— 推断），因此不需要任何 MDIO 时序约束。

### 5.3 假路径与时钟组

- 6 条 `set_false_path`（`src/constraints/rk_zynq7020.xdc:41-46`；文件里第 7 处匹配是 38 行的注释文本）：
  - `-to eth_rst_n`、`-to eth_tx_clk`、`-to eth_tx_ctl`、`-to eth_txd[*]`（41-44）
  - `-from key1_n`、`-from key2_n`（45-46）
- 37-40 行的注释记录了这次修改的理由：`eth_rst_n` 在 RTL 里是**输出**（`src/rtl/top/system_top.v:41`，由上电计数器驱动 98-102），所以原先的 `set_false_path -from [get_ports eth_rst_n]` 每次综合都报 `CRITICAL WARNING [Constraints 18-513] … -from … contains no valid startpoints`，是**一条空约束**，已删除。该批评有硬证据：旧版（HEAD 版）XDC 的同一条 CRITICAL WARNING 连同 `[Constraints 18-402] 'eth_rst_n' is not a valid startpoint` 就在提交前一次的构建日志里（`vivado_system/zynq_video_sys.runs/synth_1/runme.log:503,505`，行号指向 `rk_zynq7020.xdc:37`）。HEAD 版本同时存在 `-from` 与 `-to` 两行（`git show HEAD:src/constraints/rk_zynq7020.xdc` 第 37-38 行）。
- 方向性复核：`-to` 用在输出端口上确实有效（它会切断寄存器→pad 的输出路径），因此这 4 条不是空约束，而是**主动取消了对 RGMII TX 的一切输出时序检查**；而 `eth_tx_clk` 由 `rgmii_txc = gmii_tx_clk = gmii_rx_clk`（`src/rtl/eth/gmii_to_rgmii.v:39`、`src/rtl/eth/rgmii_tx.v:30`）直连 RX 恢复时钟 ⇒ TX 与 RX 在硬件上本是同步的，本可用 `set_output_delay -clock eth_rxc` 检查，现在被假路径整体豁免（推断，基于这三行连线）。
- 一处可核对的算术差：被 `-to` 假路径覆盖的输出端口共 7 个（`eth_rst_n` + `eth_tx_clk` + `eth_tx_ctl` + `eth_txd[3:0]`），而 `check_timing` 只报「6 ports with no output delay but user has a false path constraint」（`build/timing_summary.rpt:108`）⇒ 差的那 1 个极可能是 `eth_tx_clk`：它是纯时钟直连、没有「寄存器→pad」路径可分析，于是不被计数（推断）。
- 按键：`key1_n/key2_n` 是异步输入，`-from` 方向正确；RTL 内有 2FF 同步 + 计数消抖（`src/rtl/util/key_debounce.v:13,25-26`），但该 2FF **未打 `ASYNC_REG`**（`src/rtl/eth` 之外仅 3 个文件有该属性，见 §2 末）⇒ 对应 `build/methodology.rpt:35` 的 TIMING-10。
- 时钟组（唯一一条 `set_clock_groups`，`src/constraints/rk_zynq7020.xdc:53-56`）：三组异步 —— `eth_rxc` / `-quiet clk_fpga_0` / `-include_generated_clocks sys_clk`。注释 48-52 解释：用 `-include_generated_clocks` 才能把 MMCM 输出（`clkout0_1/clkout1_1/clkout2`）一并抓进 `sys_clk` 组，跨域数据靠 2FF + gray dc_fifo，不做 setup 分析。
- **`-quiet` 只挡住 `get_clocks` 的报错、挡不住命令本身**：综合阶段（PS7 IP 时钟尚未进入设计）出现两条 `CRITICAL WARNING: [Vivado 12-4739] set_clock_groups:No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'` 与 `'-group '`（`vivado_system/zynq_video_sys.runs/synth_1/runme.log:506,508`，行号指向 `rk_zynq7020.xdc:50`，即旧版行号）。实现阶段该组存在，所以最新一次 impl 日志是 `0 Critical Warnings`（`vivado_system/zynq_video_sys.runs/impl_1/runme.log` 末行统计，12:31:56 完成）。
- 唯一非时序项：`set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]`（`src/constraints/rk_zynq7020.xdc:58`）—— 与本主题无关的「理想网络/全局网络」类约束（如 `set_max_fanout`、时钟网络指定）一条也没有（推断：交给工具默认）。

### 5.4 「约束满足」到底说明了什么

- 全设计：WNS `+0.499 ns`、TNS 0、失败端点 0/21253，WHS `+0.060`，WPWS `+0.264`，并打印 `All user specified timing constraints are met.`（`build/timing_summary.rpt:149-154`）；分时钟：`clk_fpga_0` WNS 1.776（12749 端点）、`eth_rxc` WNS 0.499（3463 端点）（`build/timing_summary.rpt:181-182`）。
- 但这只覆盖「被约束的端点」：RGMII RX 缺输入延迟、TX 被假路径豁免、按键被假路径豁免（§5.1/§5.3）⇒ 报告绿灯不等于这些接口安全（推断）。
- CDC 报告 9 行跨域统计（`build/cdc.rpt:15-25`）：3 行 Critical（`eth_rxc→clk_fpga_0` 16 端点其中 14 无 `ASYNC_REG`、`clk_fpga_0→clkout0_1` 16 端点、`eth_rxc→clkout0_1` 33 端点 16 unsafe 17 unknown），`sys_clk→eth_rxc` 多达 1498 端点（1003 safe、493 unknown）。

---

## 六、构建流程

### 6.1 规范入口 `build/tcl/build_system_axigpio.tcl`（149 行）

- 地位：`build/tcl/README.md:28-29` 称其为「仓库内**唯一**的规范构建入口（建工程+BD → 综合 → 实现 → bit/XSA → 报告，全部仓库相对路径；已在干净克隆上验证）」；开发工作位的 `rebuild_v6.tcl/program_v6.tcl` 不入库。
- 步骤：
  1. 相对根路径 + `vivado_system/zynq_video_sys`、器件 **`xc7z020clg484-2`**、输出目录 `build/`（`build/tcl/build_system_axigpio.tcl:2-7`）；`create_project -force`、目标语言 Verilog（9-10）。
  2. RTL 文件列表：目录 `{util clocks video process process/rotate process/zoom axi hdmi eth}` 全量 `*.v` + 单独追加 `top/pl_video_top.v`、`top/system_top.v`（12-18）⇒ **`top/pl_demo_top.v` 有意不进系统工程**；XDC 加到 `constrs_1`（19）。
  3. BD：`create_bd_design design_1`、`processing_system7:5.5`，`apply_bd_automation -config {make_external "FIXED_IO, DDR" Master/Slave "Disable" apply_board_preset "0"}`（21-25）⇒ 不套板卡预设、逐项手配。
  4. **PS 预设**（27-45）：`PCW_FPGA0_PERIPHERAL_FREQMHZ 100`（28）、`EN_CLK0_PORT/EN_RST0_PORT=1`（29）、**`USE_M_AXI_GP0=1`**（30）、`USE_S_AXI_HP0=1` 且 `S_AXI_HP0_DATA_WIDTH 64`（31）、ENET0 MIO16..27 + MDIO MIO52..53（32-34）、UART0 MIO10..11（35）、QSPI 单片选（36）、SD0 MIO40..45 + CD MIO9（37-38）、**`PCW_GPIO_EMIO_GPIO_ENABLE 0`**（39）、bank0 3.3 V / bank1 1.8 V（40-41）、**DDR 颗粒 `MT41K256M16 RE-125`、总线 32 Bit、DRAM 宽度 16 Bits**（42-44）。
  5. `axi_gpio_0`：32 位、全输出、无中断（47-52）。两级 `axi_interconnect 2.1`：`axi_gp0_ic`、`axi_mem_intercon`，均 `NUM_MI=1 NUM_SI=1`（54-57）。
  6. 时钟/复位扇出：`FCLK_CLK0` 打到两套 interconnect 全部 ACLK、`axi_gpio_0/s_axi_aclk`、`S_AXI_HP0_ACLK`、`M_AXI_GP0_ACLK`（59-68）；`FCLK_RESET0_N` 打到全部 ARESETN（70-77）。
  7. 数据通路连接：`M_AXI_GP0 → axi_gp0_ic.S00_AXI`、`axi_gp0_ic.M00_AXI → axi_gpio_0.S_AXI`（79-82）、`axi_mem_intercon.M00_AXI → S_AXI_HP0`（83-84），再把 `axi_mem_intercon/S00_AXI` 外部化并改名 **`M_AXI_HP0`**（86-89）—— 这就是 PL 写 DDR 的端口，`system_top.v:78-93` 逐信号对接，`arcache/awcache=4'b0011`、`arlen` 被裁成 AXI3 的 4 bit（`src/rtl/top/system_top.v:79-86,96`）。
  8. BD 对外端口：`FCLK_CLK0`（`-freq_hz 100000000`，91-92）、`FCLK_RESET0_N`（ACTIVE_LOW，93-95）、`gpio_io_o` → `GPIO_0_tri_o`（97-102），`ASSOCIATED_BUSIF {M_AXI_HP0}`（104），随后 `assign_bd_address / validate_bd_design / save_bd_design`（105-107）—— AXI GPIO 的 `0x41200000` 就是 `assign_bd_address` 给的默认段。
  9. `make_wrapper -top` + 兼容 `.gen/.srcs` 两种落点后加入工程（108-113），`set_property top system_top`（117-118）。
  10. `launch_runs synth_1 -jobs 4` → 查 `PROGRESS != "100%"` 即 `exit 1`（120-125）→ `launch_runs impl_1 -to_step write_bitstream -jobs 4` + `wait_on_run`（126-127）。
  11. bit 复制：`…impl_1/system_top.bit`（找不到则 glob `*.bit`）→ **`build/system.bit`**（129-133）。
  12. 报告：`open_run impl_1` 后 `report_timing_summary` → **`build/timing_summary.rpt`**、`report_utilization` → **`build/utilization.rpt`**（134-136）；`catch` 包住的另外五份：**`cdc.rpt`、`methodology.rpt`、`power.rpt`、`route_status.rpt`、`clock_util.rpt`**（138-143，注释说明 V7 起一并产出、门禁要求功耗与布线状态有对应文件）。
  13. `write_hw_platform -fixed -include_bit -force` → **`build/system.xsa`**（144），最后 `catch {close_project}` + 三行 `BIT:/XSA:/SYSTEM BUILD DONE`（145-148）。
- **不设置任何实现策略或 `STEPS.*` 属性**（全文无 `set_property strategy` / `STEPS.`）⇒ 走 Vivado 默认 `impl_1` 策略；与之对比，只有 `build/tcl/rebuild_opt.tcl:33-35` 会开 `PHYS_OPT_DESIGN.IS_ENABLED`、`POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED` 并把 bitstream 的 `BIN_FILE` 关掉。
- `catch` 包裹报告与 `close_project` ⇒ 报告失败不会让构建失败（推断：CI 式门禁要另判报告文件是否存在）。

### 6.2 上板三件套（顺序不可换）

- 顺序：`ps_jtag_boot → program_pl → set_src → 推流 → 回读`（`build/tcl/program_pl.tcl:5-7`、`build/tcl/ps_jtag_boot.tcl:10`、`board/README.md:13-25`、`report/OVERNIGHT_LOG.md:520`）。
- `ps_jtag_boot.tcl`：`ps7_init.tcl` 路径按「环境变量 `PS7_INIT` → `argv[0]` → glob `*/platform/*/hw/ps7_init.tcl`」三级回退，找不到就报错退出（`build/tcl/ps_jtag_boot.tcl:12-22`）；`targets -set 1` + `rst -system`（DAP 卡住/APB AP transaction error 时先系统复位）+ `after 3000`（29-32）；`source $psinit` → `ps7_init` → `ps7_post_config`（34-39）；**自检**：`mwr -force 0x10000000 0x5A5AA5A5` 后 `mrd` 回读打印 `DDR_ECHO:`（42-45），最后 `con`（46）。注释 6-8 明确：只有 FSBL 会写 SLCR 里 `FPGA_FCM*`（HP 通道缓冲）一类寄存器，ps7_init 的 tcl 版不含 ⇒ `board/README.md:27-29` 补一句「交付态请用 Vitis Run ELF 启动；性能类结论应以 FSBL 启动为准」。
- `program_pl.tcl`：`open_hw_manager → connect_hw_server -allow_non_jtag → open_hw_target`，先打印链上全部器件（13-18），再按 `PART =~ "xc7z020*"` 选器件（20-22，注释与 `scan_jtag.tcl` 都强调**选 xc7z020 而不是 arm_dap**），`PROGRAM.FILE = build/system.bit` + `program_hw_devices`（24-26）。
- `set_src.tcl`：`stop → mwr -force 0x41200000 0x00010000 → puts "GPIO … = [mrd …]" → con`（`build/tcl/set_src.tcl:11-15`），文件头给出位映射 `[16] src_sel / [4:0] effect_en / [15:8] threshold`（2-4）并提示改成 `0x00000000` 回 SRC0（6-7）。
- 回读脚本**不 con**（`src/host/ddr_verify.mjs:53`），因此每轮回读后 A9 停在复位态，下一轮必须重跑三件套（`board/README.md:64-69`、`src/host/HOST_GUIDE.md:234-235`）。

### 6.3 报告/扫描类脚本

- `report_mem_hier.tcl`：打开已有 `impl_1`（失败则退回 `synth_1`）后 `report_utilization -hierarchical -hierarchical_depth 4` → **`build/util_hier.rpt`**，用途注释是「回答 BRAM 被谁吃掉了」（`build/tcl/report_mem_hier.tcl:1-19`）。
- `sweep_impl_strategy.tcl`（未入库）：复用 `vivado_system/zynq_video_sys.xpr`，**不重建 BD、不重跑综合**（5-6 注释：整建约 15 分钟、单策略 5-8 分钟）；默认策略列表 5 个 `Performance_Explore / ExplorePostRoutePhysOpt / ExploreWithRemap / ExtraTimingOpt / BalanceSLRs`，可被 `SWEEP_STRATS` 覆盖（23-27）；每策略 `reset_run impl_1 → set_property strategy → launch → wait`（34-43），非 100% 记 `INCOMPLETE`（44-48）；`report_timing_summary -max_paths 3 -check_summary_only` 到 **`build/sweep_<策略>_timing.rpt`**，再从**报告文本**正则取 `WNS/TNS/失败端点/总端点/WHS`（50-58，注释 50：「属性名跨版本不稳，文本解析最可靠」），`all_constraints_met` 用是否出现 `All user specified timing constraints are met` 判定（59），功耗取 `TOTAL_POWER`（61）；汇总 TSV 写 **`build/sweep_summary.txt`**（28-30,63-67）。注释 15-16 记录一条环境事实：2025.2.1 对本器件**不支持** `Flow_PerfOptimized_high` / `Performance_RetimingTDM` 等策略名。当前提交版 `build/sweep_summary.txt` 只有 1 行表头（`wc -l` = 1）⇒ 本轮扫描尚未产出结论（对应任务 #7 进行中）。
- `apply_cdc_report.tcl`：在已布线设计上重复施加与 XDC 相同的异步时钟组再出 `timing_summary/power/utilization` 三份报告（`build/tcl/apply_cdc_report.tcl:11-19`），并打印全时钟表（20-23）；但第 2 行把 root 硬编码成 `D:/Xilinx/Prj/ADD/Video_Pipeline-main` ⇒ 在本仓库不可直接用（与 `build/tcl/README.md:28-29` 的「全部仓库相对路径」相悖）；`rebuild_opt.tcl:2`、`rebuild_cdc_fix.tcl:2`、`rebuild_zoom_out.tcl:2`、`sim/run_zoom_only.tcl:1` 同样硬编码老工作区路径。
- `crit_path.tcl` **已损坏**：第 1 行是另一台机器的绝对路径 `D:/Software/Xiaomi_MiMo/video/zynq_video_pipeline/…`，且 3-5 行残留字面量 `\]`（heredoc/转义事故），无法被 Vivado 解析（`build/tcl/crit_path.tcl:1-6`）。
- 旧 PL-only 流（`pl_demo_top` + `build/video_pipeline.bit`）：`create_project.tcl`（pl 模式，29-33）、`build_pl_full.tcl`、`synth_pl_only.tcl`、`build_bitstream.tcl`、`program_board.tcl`、`program_system.tcl`、`program_and_check.tcl` —— 其中 `build/tcl/README.md:5-8` 的速查表还在推荐这条老链（含 `output/` 目录，而脚本实际拷到 `build/`：`build_bitstream.tcl:40-42`）。
- **会改写仓库 RTL 的历史脚本（危险）**：`build_system.tcl:113-114,209` 用 `puts` **重新生成 `src/rtl/top/system_top.v`**，且按 `pl_video_top #(.IMG_W(640), .IMG_H(360), …)` 例化（193）、走 EMIO GPIO（39）；`fix_bd_and_top.tcl:57,156,159` 同样生成 `system_top.v`（还 `assign gpio_i = status;` 把状态字从 EMIO 读回）。640×360 与现行 512×300（`src/ps/main.c:19-20`、`src/rtl/top/system_top.v:161`）冲突 ⇒ 只能当版本化石，不能与规范入口混用。`create_project.tcl:38,98` 还能看到 mojibake（`鈥?`），是 UTF-8/GBK 混写的痕迹。
- 部分脚本文件首字节带 UTF-8 BOM（`build_bitstream.tcl:1`、`build_pl_full.tcl:1`、`program_board.tcl:1` 等显示为 `\ufeff#`），Windows 下 Vivado 仍能吃，但属于隐患（推断）。

---

## 七、仿真资产与覆盖

### 7.1 运行器 `sim/run_sim.tcl`

- 全量编译：`src/rtl` 下（含两级子目录）所有 `*.v` + `sim/tb_*.v` 一次 `xvlog`（`sim/run_sim.tcl:34-53`），每个 TB `xelab -debug typical tb -s tb` 后 `xsim -R`（79-85）。
- 环境变量：`SIM_TB`（只跑指定 TB）、`SIM_ONLY`（只编译）、`SIM_VERBOSE`（回显全过程）、`SIM_ARGS`（plusargs，且必须翻成 `--testplusarg key=value`，注释 63 说明裸 `+key=value` 会被 xsim 拒收）（`sim/run_sim.tcl:8-12,55-70,77`）。
- **判据是「grep TB 自己打印的 PASS/FAIL 行」**，取最后 10 条命中（`sim/run_sim.tcl:90-95`）；verdict 逻辑：有命中且无 FAIL → PASS；**无命中 → `NO_ASSERT`，而 `NO_ASSERT` 被计入 `npass`**（`sim/run_sim.tcl:96-102`）⇒ 一个什么都不断言的 TB 也会「通过」（脚本自身的漏洞，非本项目现状：30 个 TB 全部真打印了 PASS）。
- 注释记录历史：V5 时代 `rtl_base/ + rtl_fix/` 的 `overridden` 过滤已随布局废弃；被取代的 `axi_frame_saver.v`、`axi_frame_writer.v` 仍在树里且有自己的 TB（`sim/run_sim.tcl:14-18`）。

### 7.2 覆盖表（`sim/` 共 30 个 `tb_*.v`）

| TB | 断言什么（PASS 条目/机制） | 在回归中 |
|---|---|---|
| `tb_crc32` | CRC 初值、逐字节更新、`clr`、确定性（以太 reflected 算法） | 是（`sim/results/regression_v6.txt:21-27`） |
| `tb_eth_video` | GMII 层 UDP TX→RX 回环 + 视频重组：payload 长度、整帧完成 `sf=1 n_wr=64` | 是（:29-33；注释 :8-9 说明它在第三版曾无法 elaborate，传了不存在的 `BOARD_PORT/DES_PORT`） |
| `tb_proc_gray` | RGB565→灰度公式 | 是（:35-37） |
| `tb_rotate_mapper` | 0° 恒等映射的角点/中心 `(0,0)(32,18)(63,35)` | 是（:39-44） |
| `tb_rotate_window` | 旋转开启时模糊不被强制关闭（`rotate_active=0/1` 两态） | 是（:46-50） |
| `tb_sync_fifo` | 水位、末尾非空 | 是（:52-56） |
| `tb_timing` | 参数化视频时序发生器（16×8 小分辨率）的 hs/vs/de/frame 边界 | 是（:58-60） |
| `tb_uart_decode_bits` | 「`"00111"` → bit0=最左」的软件模型，等价 `main.c` 的 `parse_bits` | 是（:62-64，`sim/tb_uart_decode_bits.v:1-2`） |
| `tb_udp_parser` | 合法 IPv4/UDP 抽 payload、错端口丢弃 | 是（:66-70） |
| `tb_udp_reasm` | 正常整帧、pixel0/1、乱序两次、坏包计数、重复包覆盖、跳帧后再来 | 是（:72-82） |
| `tb_v50_rowmath` | 行号数学；证明 16 bit 截断是真实生产 bug（172 行错） | 是（:84-89） |
| `tb_v50_rows` | 2/4 行时不 commit、全行完成后 commit 一次 | 是（:91-95） |
| `tb_v50_rows_prod` | 生产几何 512×300：10/300 行不 commit、行被碰但字节不足不 commit、300 整行才 commit | 是（:97-102） |
| `tb_v571_allow_lead` | 稳定消隐期 allow 为高、lead 之后/de 之前 allow 必须为低 | 是（:104-108） |
| `tb_v57_first_ar` | `de=1` 期间不得写、allow 抬起后拷贝完成 `wr=64/64` | 是（:110-114） |
| `tb_v57_rdw_copy` | 整帧无丢 beat、只在 allow 时写 | 是（:116-120） |
| `tb_v58_full_done` | 只有全部 BRAM 字写完才脉冲 done；abort 后（wr=16）不得 done | 是（:122-126） |
| `tb_v5_bank` | `completed_base` 锁 bank0、frame_done 后写 bank 翻到 bank1、排空后 idle | 是（:128-133） |
| `tb_v5_copy` | 用 `blank_safe`（H+V 消隐 + 流水排空）窗口完成整帧拷贝 | 是（:135-138） |
| `tb_v5_gated` | 发生过 BRAM 写、写仅在 allow、allow 在 active 期不会粘住（`residue=4158`） | 是（:140-145） |
| `tb_v5_lock` | `copy_base` 锁定 `0x10000000`、done 后 latest pending | 是（:147-151） |
| `tb_v5_saver` | 64 像素 → 16 个字全写、之后 idle | 是（:153-157） |
| `tb_v5_vblast` | 整帧必须在**一个** V-blank allow 窗口内完成，且吞吐可接受 | 是（:159-163） |
| `tb_v6_cover_gate` | 整帧才 commit；干净帧不算坏；丢一包被拒绝；有空洞的帧在线上被计数（OSD `net_bad`）；下一个完整帧再 commit | 是（:165-172） |
| `tb_v6_ingress_integrity` | 用与 `eth_udp_video_top` 相同的胶水把 `frame_reasm→dc_fifo→axi_frame_saver64→AXI 从机` 串起来满速灌 221 包，逐字比对 + 分级计数 | 是（:174-178；默认 PART 模式；手工 `+FULL` = 38400/38400，`+FULL +MISALIGN`（1396 B）在 v6.4 后也 38400/38400，**v6.4 之前是 38290/38400、first bad word=174**（:10-13）；文件头记录板上症状：只有 `lane{0,2}`/`lane{1,3}` 落数据、约 40% lane 从未被写、改包间限速完全不影响比例（`sim/tb_v6_ingress_integrity.v:1-11`） |
| `tb_v6_pingpong` | 原样搬提交/翻 bank glue，连灌 3 帧、AXI 从机带可配置写延迟，按 bank 统计每帧落位率 | 是（:180-183；文件头记录修复前症状「每帧只有约 53% 的字写进自己的 bank，占比 53/26/21」） |
| `tb_v6_vblank_copy` | 生产几何下「一帧能否在一个 V-blank 内落地」：`rate=10/7/6` 均 `done=1`（38441/54894/64036 拍），`rate=4` 溢出 `done=0` | 是（:185-191；窗口 = 25 空行 × 1344 px = 67200 axi 拍，见 `sim/tb_v6_vblank_copy.v:1-10`） |
| `tb_zoom_mapper` | `zoom_ctrl`+`zoom_mapper`：原尺寸最大→缩小→回原循环（`INV_LO=256/INV_HI=512`） | 是（:193-195） |
| `tb_v6_tail_bank` | **帧尾换页 A/B 双向判据**：同激励灌两条链，`TAIL_GUARD=0`（旧）**必须**复现丢尾否则判 FAIL；`TAIL_GUARD=1`（新）**必须**整帧完整 + commit 次数=2 | 是（仅工作区日志；`sim/tb_v6_tail_bank.v:1-16,130-175`） |
| `tb_fb_roundtrip` | 帧缓存 5 类：38400 字写完 → 153600 次逐像素流水回读；读延迟契约（加地址后**下一拍**出数，变 2 拍立刻全红）；分块边界与帧尾定点复核；越界读返回黑；越界写不得污染 | 是（仅工作区日志；`sim/tb_fb_roundtrip.v:1-14`） |

- **回归数字（两份，版本不同）**：
  - 仓库内唯一入库的回归记录：`sim/results/regression_v6.txt:14`「28 个 testbench 全部 PASS，0 失败」，`xvlog rtl=58 tb=28`（:16-18），`SIM DONE pass=28 fail=0`（:196）；日期/版本 2026-09-21 v6.4（:5）。
  - 工作区最新（R04/R05 之后）：`sim/r04_full_regression.log` 与 `sim/r05_full_regression.log` 均 `SIM DONE pass=30 fail=0`（`xvlog rtl=59 tb=30`，30 条 `RESULT … PASS`），但 **`sim/*.log` 被 `.gitignore:55` 排除**，只能靠叙述性文档核对：`report/OVERNIGHT_LOG.md:517`（L1 = 30 个 TB，R03 加 `tb_v6_tail_bank`、R04 加 `tb_fb_roundtrip`，R05 后 30/30 PASS）、`:553`（基线 28 → R03 29 → R04/R05 30）。
- 因此「30/30」目前**在版本库里不可复算**（需要重跑 `sim/run_sim.tcl`）。

### 7.3 仿真覆盖不到的

- PS 固件本身：没有任何 TB 跑 C 代码，`tb_uart_decode_bits` 只是 `parse_bits` 的 Verilog 行为模型（`sim/tb_uart_decode_bits.v:1-2`）；UART/AXI 写、`FILL`、`STAT` 全靠手测（`src/host/HOST_GUIDE.md:134-147` 的命令表 + 串口）。
- 真实 DDR/AXI 时序与时延：TB 里是**可配置写延迟/带宽模型**的 AXI 从机（`sim/tb_v6_vblank_copy.v:8-10` 用 `rate_num beats/10 cycles` 建模 HP0，注释指出 10 = 64bit@100 MHz 的 800 MB/s 峰值；`sim/tb_v6_pingpong.v` 头同）；真实的 PS7/HP0/DDR 控制器行为不在仿真里。
- PHY/RGMII 器件级与时序：`tb_eth_video` 只到 GMII 抽象层（`sim/tb_eth_video.v:1-2`）；1392/1396 这类包边界问题、IDELAY 抽头、TX 假路径（§5.3）都不在仿真判据内。
- HDMI/TMDS 输出、`rgb2dvi`、1024×600 实际显示只有参数化时序模型（`src/rtl/top/pl_video_top.v:504` 例化 `rgb2dvi`，无对应 TB）。
- 综合推断类问题**明确不靠仿真**：`sim/probes/README.md:1-10` 说这些文件「不是仿真 TB，不参与 `run_sim.tcl`」，回答「Vivado 把这段写法综合成什么」（`ramtest.v`：内存写必须独占一个不带异步复位的 always 块，否则 FF 32904 vs 拆开 LUTRAM 864；`fbtest.v`：帧缓存吃 128 个 RAMB36 的原因是地址空间向上取整到 2^16，按 2 的幂拆两块 → 80 个）。
- 显示帧缓存在 R04 之前**没有任何 TB 覆盖**（`report/OVERNIGHT_LOG.md:306`、`sim/tb_fb_roundtrip.v:1`），补 TB 的理由是「报告好不好看完全看不出来」。
- `--no-pace`（不限速）工况在仿真与板级都只做了「允许 `net_bad` 上升但不许卡死」这一条，且记录为**未测**：`report/V6_BOARD_MEASUREMENT.md:117`。

---

## 八、板级「不看屏幕」复验方法与实测数字

### 8.1 方法（`board/README.md` + `skill/frameid_loss_signature.md`）

- 定位：「不看屏幕的复验」被明确写成本项目的**主要验收手段**（`board/README.md:31`）。一条命令 = `node src\host\measure_v63.mjs --fps 15 --count 200`（`board/README.md:37`）。
- 硬件环境：RK-ZYNQ7020-F `xc7z020clg484-2`、12 V、HDMI 1024×600、USB-C（JTAG + UART COM6）、网线接**PL 网口（PHY2）**、PC `192.168.1.100/24`、板 `192.168.1.10:5001`、Vivado/Vitis 2025.2.1（`board/README.md:8-11`）。
- 步骤序列（`board/README.md:19-24`）：构建（bit+XSA+报告）→ `ps_jtag_boot.tcl <ps7_init.tcl>`（起 PS：DDR + FCLK0=100 MHz）→ `program_pl.tcl`（配 PL）→ `set_src.tcl`（`GPIO=0x00010000`）→ `ping -n 2 192.168.1.10`（0% 丢包 = PL 网络栈活着）→ 推流。
- **JTAG 回读地址与手段**：`0x41200000`（写控制字，`build/tcl/set_src.tcl:13`）；回读 `0x10000000` 与 `0x10080000` 各 38400 个 64bit 字 = 76800 个 u32，分 1000 个一组 `mrd -force`（`src/host/ddr_verify.mjs:17-21,36-50`）；`targets -set -filter {name =~ "*#0"}` + `rst -processor`（**否则读到 A9 的 D-Cache**）+ **不 `con`**（**否则 boot ROM 把旧 bit 刷回 PL**）（`src/host/ddr_verify.mjs:39-44,53`；同规则见 `board/README.md:64-69`）；推流与回读分离（`board/README.md:68`、`src/host/HOST_GUIDE.md:233`）。
- 判定标准（`skill/frameid_loss_signature.md:9-23`）：① 图案必须逐帧变化（`frameid`），`n_implied=(value-w)&0xffff`；② 先停流再回读；③ 把丢字按**包内相位 / 空间连续性 / 粒度**三维展开；④ 每 bank 帧号跨度 = 1 ⇒ 换帧原子。失效条件也写明了（:34-40）：无法回读内存的平台、开 D-Cache 的 CPU 侧读回、载荷非 8 倍数（相位会与打包器半截字状态混叠）、只能判数据完整性不判画质。

### 8.2 实测数字（金样文件：`data/measured/board_measure_15fps.txt`）

- 运行条件：`--test frameid` 200 帧 @15 fps、pace 15 MB/s、首帧 `307200 B = 221 pkts`、实测 ~15.1 fps（`data/measured/board_measure_15fps.txt:1-9`）。
- bank0：`u32=76800/76800`，主导帧号 **f198 = 153598 个 lane**，`同一字内两 lane 帧号不同的字数=0`，`含多个帧号的 16 行组=1/19`、次要帧号占比 >12% 的组 = 0（:13-17）。bank1 同构，主导 **f199**（:18-22）。
- 命中率与分带：**最新帧 16bit 命中率 100.0%**；包内六个字节带（0-48/48-96/96-192/192-384/384-768/768-1392 B）丢字率**全 0.0%**；连续丢字带 **1 段、总 2 个 16bit 字、最长 2**、`≥696(整包) 段数 0`（:25-37）。
- 那「跨度上限 27137」正是残留本身：`27137 = (0 - 38399) & 0xffff`（最后一个 64bit 字的两个 lane 读到 0x0000），即 2 个 lane（:14,:19 的 `f27137:2`）——与 `board/README.md:49-51`「bank 最后一个 64bit 字的高半个 u32（帧的最后 4 字节 = 2 像素）偶发读到 0，下一帧同地址即被覆盖 ⇒ 肉眼不可见；`tb_v6_ingress_integrity +FULL` 不复现」完全对应（推断：把 `f27137:2` 反算为「末字两 lane 为 0」）。
- 三档速率对照（`data/measured/README.md:10-15`）：15 fps / 30 fps / 60 fps（18.4 MB/s）三档的「最新帧命中率 100.0%、包内各带全 0.0%、u32 内两 16bit 错帧 0/76800」，修复前为 42~52%、6.7%→54~64%、18.6%；已知残留 2/153600 lane。
- 同源判据的速率表（含「A9 停/A9 在跑」两种工况）：`report/V6_BOARD_MEASUREMENT.md:53-56`（15 fps/80 帧 bank0 #78、bank1 #79；30 fps/200 帧（A9 在跑）#199/#198；60 fps/300 帧 18.4 MB/s；15 fps/200 帧（A9 在跑，交付工况））。
- 扩展 19 轮（`report/OVERNIGHT_LOG.md:406-415`）：15 MB/s@15/30 fps、30 MB/s@30 fps、**不限速 60 fps（400 帧）**、**不限速 120 fps→实测 116 fps ≈36 MB/s（900 帧）**，以及 v6.4 基线 `155d73bc` 的 A1-A8（120 fps→106.6 fps ≈33 MB/s）：每 bank 恰好一帧、`0/76800` 异帧、六带 0.0%、最长丢字带 0、帧尾分带 w90-99 = 100。另有 3 轮 1396 B 载荷 180 帧（`report/OVERNIGHT_LOG.md:427-429`）：同样 100.0%/0 —— 其价值在于把「非 8 倍数载荷造成的半截字推送」在硬件上真正跑到 3.96 万次（:430-434）。
- 分包长度 A/B（同一块板、同一 bit、同一会话）：1396 B → 命中率 99.9%、每帧空洞 **222 个 16bit 字（111 处 ×2）**、洞里是 0x0000（规律散布的黑点）；1392 B → 100.0%、空洞 0~2（`src/host/HOST_GUIDE.md:243-252`；同数据 `docs/V6_BOARD_MEASUREMENT.md:83-86`）。**v6.4 起这条不再是使用约束**：打包器按 16bit lane 驱动 `WSTRB`，1396 那一行复测变 100.0%/0（`src/host/HOST_GUIDE.md:250-252`、`docs/V6_BOARD_MEASUREMENT.md:92-97`）；但默认仍建议 1392（少发重复 beat、便于用包内相位定位）。
- 仍需肉眼的 6 项：SRC0 彩条无横纹、`--test move` 红块无拖影、`--test blocks` 网格不被逐字空洞打断、OSD `eth=`/`net_bad=` 递增、停流后冻结帧干净、拔线 30 s 再插自动恢复（`board/README.md:53-62`）。
- 复算入口：`gunzip data/measured/ddr_dump_20260921_15fps.out.gz && node src/host/ddr_stale.mjs data/measured/…out`（`data/measured/README.md:19-22`；原始回读 76800×2 个 u32 的 `<addr>: <data>` 文本，:5-6）。

---

## 九、最值得注意的是（速记）

1. `ZOOM0/1` 与 `bit[17]` 在硬件里不存在（`src/rtl/top/system_top.v:165` 绑 `1'b1`），固件却照常维护 `cur_zoom`（`src/ps/main.c:31,60-64`）；`Xil_Out32(GPIO_TRI,0)` 也是空操作（IP 全输出，`build/tcl/build_system_axigpio.tcl:48-51`）。
2. `FILL` 是 PS 唯一直接改帧内存的动作，写的正是 PL 的 bank0，而这条路径只在**网线没插**时才可能上屏（`src/ps/main.c:107-127` + `src/rtl/top/pl_video_top.v:225-230,312,327-328`）。
3. 文档三处陈旧：`src/ps/README.md:11-16`（EMIO 映射、「软件自动切源」）、`src/host/HOST_GUIDE.md:120-122`（「不必发 SRC1」——RTL 的源 mux 只看 `src_sel_pix`，`src/rtl/top/pl_video_top.v:289,398-401`）、`build/tcl/README.md:5-8`（推荐已被取代的 PL-only 链与 `output/` 路径）。
4. 手写 XDC 只有 2 条 `create_clock`、**0 条 `create_generated_clock`、0 条 `set_input_delay/set_output_delay`**，RGMII TX 用 4 条 `-to` 假路径整条豁免（`src/constraints/rk_zynq7020.xdc:5-6,36,41-46`），代价由工具自己报出来（`build/timing_summary.rpt:98-110`、`build/methodology.rpt:36,943-976`）。
5. 那条被删掉的 `-from eth_rst_n` 空约束有工具原文佐证（`vivado_system/…/synth_1/runme.log:503,505`），且**修复尚未提交**（HEAD 里 `-from` 和 `-to` 并存），`build/system.bit` 也还是修复前那次构建的产物（bit mtime 08:47 vs XDC mtime 12:25）。
6. `ddr_verify.mjs --frameid` 结尾必然打印「两个 bank 都没读到有效 wordid 图案」（`src/host/ddr_verify.mjs:249-261`，实证 `data/measured/board_measure_15fps.txt:23`）—— 假警报。
7. `ingress_probe.mjs` 因未 import `MEASURED` 而一加载就崩（`src/host/ingress_probe.mjs:13-20`），`ddr_holemap.mjs` 在不带参数时同样崩（`src/host/ddr_holemap.mjs:11-23`）。
8. `run_sim.tcl` 把「什么都没断言」也算 PASS（`sim/run_sim.tcl:96-102`）；30/30 的证据只存在于被 `.gitignore` 排除的日志里，入库记录仍是 v6.4 的 28/28（`sim/results/regression_v6.txt:14`）。
9. `build_system.tcl` / `fix_bd_and_top.tcl` 会**生成并覆盖** `src/rtl/top/system_top.v`，且是 640×360 的老几何（`build/tcl/build_system.tcl:113-114,193`）——与规范入口混用会静默毁掉现网 RTL。
10. `sweep_impl_strategy.tcl`/`sweep_summary.txt` 未入库且汇总表只有表头，说明「策略扫描」这一项还没产出可引用的数据（`build/sweep_summary.txt:1`）。

---
name: dma-cache-coherency
description: 用于定位"PS 与 PL 共用一块内存时读到旧数据/部分新数据/末尾缺字节"这一类搬运与缓存一致性故障。当共享 DDR 的读数在重跑后变了、JTAG 回读与屏上不符、多轮复用同一缓冲区随机错、长度非整缓存行时出错、或需要给搬运通道写封装（发送前 clean、接收后 invalidate、完成判定与可见性屏障）时使用。本工程 PL 侧未例化任何 DMA IP（PS 侧只用 SD 控制器自带 DMA）⇒ 与描述符链、SG 通道相关的断言一律标注【未实测】。
---

## 1. 一句话用途

给 PS↔PL 共享内存的搬运写封装，并按机制定位一致性故障。

## 2. 适用场景

- 当同一地址重复回读出现多个不同值，而写入者只应当写一次时。
- 当"计数器=0/图案=正确"的读数是靠调试器 `mrd` 读 DDR 得到的，而该 DDR 同时被打开着 D-Cache 的处理器访问时。
- 当第一轮传输对、后续轮次随机错，或只有换了一块新缓冲区才对时。
- 当传输末尾若干字节读到 0 或读到上一轮的内容时。
- 当长度不是缓存行整数倍、或缓冲区前后紧邻着别的变量时。
- 当"中断/完成状态位到了，但紧接着读数据仍是旧的"这类时序问题时。
- 当要为一条搬运通道写封装（启动、等待、超时、错误位分诊）而尚未确定一致性路线时。

## 3. 不适用 / 失效条件

- **本工程 PL 侧没有例化任何 DMA IP**：BD 里只有 `processing_system7_0` + `axi_gp0_ic` + `axi_gpio_0/1/2` + `axi_mem_intercon`，PL 侧经 `S_AXI_HP0` 直接读写 PS DDR（`build/tcl/build_system_axigpio.tcl:160-173`），没有 AXI DMA / CDMA / VDMA。⇒ 本条凡是"描述符链、硬件描述符引擎的传输长度寄存器、SG 通道切换"的断言都是**通用做法**，在本工程一律 `【未实测】`，不得当作本仓结论引用。
- **但本工程确实在用一条 DMA**：PS 侧 SD 控制器（`XSdPs`）的 DMA 把帧直接写进 PL 要读的那块 DDR，"写完只发一次发布脉冲"（`src/ps/sd_play.c:12-17`，"零拷贝"是刻意设计）。⇒ 与"PS 侧 DMA 目的缓冲区的缓存维护"有关的写法在本仓有实跑代码与理由（§5.1 路线二、§7 第三条）；与"PL 侧 DMA IP"有关的一切仍是 `【未实测】`。
- 不适用 PL 完全不碰 PS 内存的设计（只走寄存器窗口的场合）：本工程的数据面就是共享 DDR，控制面才走 GPIO 窗口，两者判据不同。
- 不适用 Linux 驱动形态下的 `dma-buf` / CMA / `dma_sync_*`：本条的软件维护写法是裸机 `Xil_*Cache*` 口径，接口名与语义都不通用。
- 不适用 Versal / 无 ACP 或无 HP 同类端口的器件：表 5-A 的"路线一"依赖该器件有一致性端口，没有就只剩路线二。
- 若故障与地址无关（屏上现象与 DDR 读数同时错），先回 `pl-load-verify` 的分层通路确认，本条不覆盖"根本没写进去"这一类。

## 4. 前置条件

- 工具与版本：Vivado / Vitis 2025.2.1，器件 `xc7z020clg484-2`（`report/BUILD.md` §1、`data/metrics.csv` 第 2 行）；裸机侧头文件来自已 generate 过的 zynq BSP（环境变量 `PS_BSP`，`report/BUILD.md` §1 表）。
- 需要的输入文件：本仓的对照件 —— `src/ps/main.c`（`Xil_DCacheEnable()` 与整帧 `Xil_DCacheFlushRange()` 的调用点）、`src/ps/sd_play.c`（读扇区前先 flush 的理由与实现）、`src/rtl/top/system_top.v`（HP0 主设备端口与 `ARCACHE/AWCACHE` 常量）、`src/rtl/axi/axi_frame_writer64.v`（突发长度与 size/burst 常量）。
- 需要的权限或硬件连接状态：JTAG 可达（`hw_server` 3121）；能在"边跑边采"与"halt 后采"两种采样姿态之间切换（这两者的差别就是本条 §6 的一条判据）；串口可控应用（要能停掉正在写 DDR 的那一方）。
- 需要的环境量：`VP_XSDB`（调试器）、可选 `PS7_INIT`。

## 5. 使用方法

### 5.1 表 5-A 两条路线的取舍（给成立条件，不给"通用最佳实践"）

| 路线 | 成立条件（全部满足才可选） | 代价与判据 |
| --- | --- | --- |
| 路线一：硬件一致性端口 | ① 器件提供一致性从端口（AMD 教程引言页对 ACP 的原文定义："Accelerator Coherency Port (ACP): Low-latency access to PL masters, with optional coherency with L1 and L2 cache."）；② PL 主设备确实接到该端口而不是 HP 端口；③ 该端口的位宽/地址可达范围覆盖缓冲区 | 少任一条件就不能选。本工程的 HP 端口按原文定义是"High-Performance (HP) AXI Ports: PL bus masters with high-bandwidth datapaths to the DDR and OCM memories." —— 定义里没有一致性承诺；本仓 HP0 事务的 `ARCACHE/AWCACHE` 被写成常量 `4'b0011`（`src/rtl/top/system_top.v:90,94`），该常量在 AMBA AXI 里的确切位含义本次未能打开协议文档核实 ⇒ `【未核实】` |
| 路线二：软件显式维护（发送前 clean、接收后 invalidate） | ① 能拿到按地址范围的缓存操作接口；② 缓冲区起止可控；③ 所有权交接点明确（同一块内存任一时刻只有一个写者） | 本仓真实走的就是这一条，而且**两个方向都用上了**：(a) PS 写完一整帧后 `Xil_DCacheFlushRange(FRAME_ADDR, FRAME_BYTES)` 再通知 PL 搬（`src/ps/main.c:714-716`）；(b) SD 控制器的 DMA 往目标缓冲区写之前**先 flush**，`src/ps/sd_play.c:84-95` 的注释给的正是这条机制："驱动读完会 invalidate 目标区间，但**进**去之前若那里有脏行（例如刚跑过 FILL），invalidate 之后脏行仍会被写回，把刚 DMA 进来的数据盖掉" ⇒ 只做 invalidate 会坏，必须 flush+invalidate 成对。"PL 写 PS 内存后由 PS invalidate"这一半在本工程没有场景（PL→PS 只经寄存器窗口）⇒ 那半 `【未实测】` |

### 5.2 缓冲区纪律（四件必须显式的事）

| 纪律 | 要满足什么 | 机制依据（本次打开的文件/页） |
| --- | --- | --- |
| 按缓存行对齐**且独占一行** | 缓冲区首尾各自占满整行，前后不许紧挨别的可变变量 | 裸机库的实现里缓存行是 `const u32 cacheline = 32U;`，而 `Xil_DCacheInvalidateRange` 的注释明写：若起止地址不落在缓存行边界，含非对齐地址那一行会"先 flush 再 invalidate"，理由是 `invalidating the same unaligned cache line may result into loss of data.`（`standalone/src/arm/cortexa9/xil_cache.c`）⇒ 相邻变量会被同一行的操作带走 |
| 内存归属（谁写谁读） | 每块缓冲区在某一刻只有一个写者；交接靠一次显式的状态位/脉冲，不靠"sleep 一会儿" | 本仓的反例件在 `board/ddr_churn_r33_pair.md`：修复前 ETH 的两个乒乓 bank 与 PS 片源共用 bank，同一地址 60 次采样读到 `distinct=32`（`CHURNING(有写入)`），把 PS 片源挪到第三个 bank（`0x1010_0000`）后同一探针读到 `distinct=1 wordid_clean=60/60 STATIC`。⇒ "归属"判据可以是这条读数，而不是眼睛 |
| 长度上限与突发边界 | 单次传输长度受通道的长度字段位宽限制；跨 4 KiB 边界与"长度非缓存行整倍数"要单独验 | 本仓没有 DMA 长度寄存器可查。可查的两处：AXI DMA 裸机驱动头文件里的 `#define XAXIDMA_MCHAN_MAX_TRANSFER_LEN 0x00FFFF  /* Max length MCDMA hw supports */`（`XilinxProcessorIPLib/drivers/axidma/src/xaxidma_hw.h`，多通道形态的上限声明），以及本工程 PL 主设备把 AXI4 的 8 位长度字段截成 4 位送进 PS 的做法（`src/rtl/top/system_top.v:73` `wire [3:0] m_awlen_axi3 = m_awlen[3:0];`、`:106` `assign m_arlen_axi3 = m_arlen8[3:0];`，配的常量是 `localparam integer BEATS = 16;` / `arsize = 3'b011` / `arburst = 2'b01`，见 `src/rtl/axi/axi_frame_writer64.v`）⇒ "突发 ≤16 拍、每拍 8 字节、INCR" 是本仓事实；"描述符链怎么切" `【未实测】` |
| 地址可达范围与位宽 | 通道的地址字段位宽必须覆盖缓冲区末地址；超出后的现象要么被夹住要么报解码错 | 本仓 DDR 缓冲地址为 `0x1000_0000 / 0x1008_0000 / 0x1010_0000` 三个 bank，与 `system_top` 的参数一一对应（`src/ps/main.c:41-46` 写明"这个数必须等于 `system_top.v` 的 PS_DDR_BASE / `pl_video_top.v` 的 PS_BASE_ADDR"）。AXI DMA 的错误位里存在解码错这一类（`#define XAXIDMA_ERR_DECODE_MASK 0x00000040 /**< Datamover decode err */`），但本仓没有该 IP ⇒ 触发与观测 `【未实测】` |

### 5.3 完成判定与可见性屏障（写成可判定的检查步骤）

断言：状态位或中断到了，**不等于**数据可见。要判"可见"，按下面四步逐条给结论：

1. 通道是否真的空闲：读状态寄存器的"完成/空闲"位（AXI DMA 裸机头文件里对应 `#define XAXIDMA_IDLE_MASK 0x00000002 /**< DMA channel idle */`，控制/状态寄存器偏移 `#define XAXIDMA_SR_OFFSET 0x00000004 /**< Status */`）。本工程无此寄存器 ⇒ 这一步在本仓 `【未实测】`。
2. 屏障有没有做：`standalone` 的按范围操作在结尾确实发屏障（同文件 `Xil_DCacheFlushRange` / `Xil_DCacheInvalidateRange` 的循环之后都有 `dsb();`）⇒ 若你自己手写维护，必须显式补这一条，否则"维护已发起"与"维护已完成"之间没有次序保证。
3. 数据可见性用**独立第二条通路**验一次：本仓可用的一条是 JTAG 直接回读 DDR 并逐字比对自描述图案（`src/host/ddr_verify.mjs`，图案 `--test wordid`），另一条是 PL 自己数的计数器经寄存器窗口读回（`node src/host/health_read.mjs --json`）。
4. 采样姿态必须写明：`mrd` 经 A9 目标读 DDR 时读到的是缓存内容而不是内存。本仓为此付出的代价被记录在 `board/ddr_churn_r33_pair.md`：`ddr_verify.mjs` 为了躲这个，在回读前先 `catch {rst -processor}`，"而这一下正好把要观察的写入者停掉"⇒ 抓写竞态必须换一支"边跑边采"的探针（`board/ddr_churn_probe.mjs`）。⇒ **"用调试器读到旧数据"与"读到新数据"这两件事，先判采样姿态再判硬件。**

### 5.4 最小封装示例（≤50 行；槽位用 `【填入】`；本示例未实测）

```c
/* 共享内存搬运的最小封装：所有权显式、维护显式、完成判定分两层。
 * 本片段是通用写法示例，未在【填入】所示的任何硬件上跑过 ⇒ 全部判据按【未实测】对待。 */
#define BUF_ADDR        【填入】u32   /* 缓冲区首地址：必须 32B 对齐且独占首尾行 */
#define BUF_BYTES       【填入】u32   /* 必须整缓存行倍数，否则见 Xil_DCacheInvalidateRange 的注释 */
#define CH_CTRL         【填入】u32   /* 通道控制寄存器 */
#define CH_STAT         【填入】u32   /* 通道状态寄存器 */
#define CH_LEN          【填入】u32   /* 传输长度寄存器（本仓无此物：【未实测】） */
#define STAT_DONE       【填入】u32   /* "完成"位掩码 */
#define STAT_ERR        【填入】u32   /* "错误"位掩码（与 DONE 必须是不同的位） */
#define RUN_BIT         【填入】u32   /* "启动"位掩码 */

int xfer_send(u32 len)                 /* PS 写 → PL 读 */
{
    if ((len == 0U) || (len > 【填入】u32 /* 单次上限 */)) return -1;
    if ((BUF_ADDR & 31U) || (len & 31U)) return -2;   /* 非整行：交给 §5.2 的机制解释 */
    Xil_DCacheFlushRange((INTPTR)BUF_ADDR, len);      /* 发送前 clean：本仓真实用法同 main.c:714 */
    Xil_Out32(CH_LEN, len);
    Xil_Out32(CH_CTRL, RUN_BIT);
    for (u32 spin = 0U; spin < 【填入】u32; spin++)
        if ((Xil_In32(CH_STAT) & STAT_DONE) != 0U) break;
    if ((Xil_In32(CH_STAT) & STAT_ERR) != 0U) return -3;
    return ((Xil_In32(CH_STAT) & STAT_DONE) != 0U) ? 0 : -4;   /* 超时=失败，不是 0 */
}

int xfer_recv(u32 len)                 /* PL 写 → PS 读 */
{
    if ((len == 0U) || (len > 【填入】u32)) return -1;
    Xil_DCacheInvalidateRange((INTPTR)BUF_ADDR, len); /* 接收后 invalidate（丢弃脏行；见 §5.2 的行丢失风险）*/
    for (u32 i = 0U; i < len / 4U; i++)                /* 唯一能证明"可见"的一步：读出来自己核对 */
        if (Xil_In32(BUF_ADDR + i * 4U) == 【填入】u32) return -5;  /* 核对图案/期望值 */
    return 0;
}
```

示例声明：以上未编译、未上板 ⇒ `【未实测】`；本仓可复跑的一致性动作只有 `xfer_send` 那半的形态（写完 → flush → 通知 PL），凭据是源码与 §7 的件。

## 6. 判读与失败分叉（常见出错情形的定位方法）

每条给"现象 → 首查 → 判别实验"。本仓没有 `skill/pitfalls/axi-dma-and-memory/` 目录（写作时 `ls skill/` 只有平铺 `.md` 与一个 `zynq-video-rtl-debug/`）⇒ 编号对齐列一律 `【待对齐】`；凡本仓未取证的现象只给排查路径，不给根因。

| # | 现象 | 首查 | 判别实验（必须能做出来的那一条） | 对齐 |
| --- | --- | --- | --- | --- |
| 1 | 读到旧数据（内容与上一轮相同） | 采样姿态：`mrd` 是否经 A9 目标读（读到的是 D-Cache） | 换一种采样姿态重读同一地址：halt 后读 vs 边跑边读。本仓实测过这条差异：`ddr_verify.mjs` 的 `rst -processor` 会把写入者一起停掉，于是"全绿"在坏固件上也成立（件 `board/ddr_churn_r33_pair.md` 的"反例：判据不敏感"段） | 【待对齐】 |
| 2 | 读到部分新数据（同一帧里一半新一半旧） | 所有权交接点在哪一拍；是否边跑边采 | 同一地址连采 N 次看值集大小：本仓探针输出 `distinct=` 就是这个判别量（修复前 `distinct=32 CHURNING(有写入)`，修复后 `distinct=1 STATIC`） | 【待对齐】 |
| 3 | 末尾若干字节缺失 / 读 0 | 长度是否为整字/整行；分包长度与总线数据宽的关系 | 把长度改成数据宽的整数倍再跑同一图案回读：本仓实测形状是"1396 B 分包 ⇒ 每帧 222 个 16bit 洞、洞里是 0x0000；1392 B ⇒ 命中率 100.0 %、洞 0"（`report/log/ISSUES.md` `#29`），且残留的"最后一字高半个 u32 读到 0，8 次末帧读数出现 4 次"登记为未修（`#33`） | 【待对齐】 |
| 4 | 地址越高越错 | 地址字段位宽与可达范围；跨 4 KiB/跨 bank 边界 | 固定长度只搬基址，逐段抬 4 KiB 采一次；若某段起恒错 ⇒ 位宽或映射问题。本仓无 DMA ⇒ 这条只有排查路径，结果 `【未实测】` | 【待对齐】 |
| 5 | 只有第一次传输对 | 第二次是否在复用同一块缓存行（上一轮的脏行被写回） | 第二轮换新缓冲区 vs 复用旧缓冲区各跑一次，比较读数；复用错、换新对 ⇒ 落回 §5.2 第一条纪律。本仓未做过该实验 `【未实测】` | 【待对齐】 |
| 6 | 多轮复用同一缓冲区时随机错 | 每轮的所有权交接是否唯一；完成位是否被上一轮残留置位 | 每轮之间插入一次"回读核对"并计数：本仓对应的可复跑判据是"同一份读数里'流量活着'位与'零丢计数'必须同时成立"（`report/log/ISSUES.md` `#316` 立的规矩） | 【待对齐】 |
| 7 | 长度非整缓存行时错 | 起止是否非对齐 | 用 `Xil_DCacheInvalidateRange` 的注释自证机制：非对齐起止那一行会"先 flush 再 invalidate"，因为纯 invalidate 会丢数据 ⇒ 把长度补成整行，错是否消失。本仓未跑该对照 `【未实测】` | 【待对齐】 |
| 8 | 并发读取寄存器时丢中断/丢事件 | 读的人是不是只有你一个（调试器与正规写路径抢同一个字） | 采完立刻回读控制字，凡"我写进去的位现在不等于我写的"就丢弃该样本并**单独计数**。本仓这条已经变成硬规矩并有件：`report/log/ISSUES.md` `#55` 记录第一版采样把"lane 号被 PS 每帧整字重写抹掉"的样本当真实读数，于是报出并不存在的"掉了 80 次"；r50 重采时 291 条这样样本被丢弃并计数（凭据 `build/frozen_r50_lat/lane30_r50.txt`）。中断语义本身本仓无中断 ⇒ `【未实测】` | 【待对齐】 |
| 9 | 状态位到了但数据仍旧 | §5.3 的四步按序走 | 在第 3 步换用第二条独立通路核对数据；若第 1/2 步通过而第 3 步失败 ⇒ 缺可见性屏障或缺 invalidate。本仓未做过该对照 `【未实测】` | 【待对齐】 |

通过 / 失败 / 读不到输入三态的落法：判别实验做不出来（缺硬件、缺 IP、缺件）一律记 `NOT_MEASURED`，禁止写成"未发现该机制"或"已排除"。

## 7. 已验证的效果

本条的"DMA 封装"与"描述符/中断"部分：**本工程未实现 ⇒ 全部 `【未实测】`**。已验证的只有下面共享内存一致性的三件，均给四要素：

- 所有权归属可以用回读值集判定（§5.2 第二条）
  - 复跑命令：`node board/ddr_churn_probe.mjs 60 25`（前置：已 ps7_init + 已 program bit，`--test wordid` 正在推流，SD 自动播放中）
  - 输入路径：`board/ddr_churn_probe.mjs`；原始输出留档件 `board/ddr_churn_r33_pair.md` 指向的 `ddr_churn_r33_newelf.txt`
  - 期望输出：三个 bank 各自的 `distinct=` 与 `wordid_clean=` 一行；ETH 两 bank `STATIC`、PS 专用 bank `CHURNING(有写入)`
  - 实际输出摘要：`0x10000040 n=60 distinct=1 wordid_clean=60/60 STATIC`、`0x10080040 … STATIC`、`0x10100040 n=60 distinct=32 … CHURNING(有写入)`（修复后固件，PS 片源已挪到第三个 bank）⇒ 判定 PASS
- 调试器采样姿态会伪装成"全绿"（§5.3 第 4 步）
  - 复跑命令：`node src/host/ddr_verify.mjs`（它内部先 `rst -processor` 再回读）
  - 输入路径：`src/host/ddr_verify.mjs` 的 `BANK0=0x10000000` / `BANK1=0x10080000`
  - 期望输出：若判据靠"边跑边写"的现象，该命令必须给出**能区分好坏固件**的差值
  - 实际输出摘要：`board/ddr_churn_r33_pair.md` 明确记载用它判这一条不成立 —— "而这一下正好把要观察的写入者停掉，之后 PL 每 66 ms 就把 bank 重新刷成干净图案，于是'两 bank 全绿'在修复前也照样成立" ⇒ 判定 PASS（结论是"这条判据必须换探针"）
- PS 写 → PL 读的软件维护在本仓真实存在并工作
  - 复跑命令：`powershell -File board/uart_cap_once.ps1 -Seconds 20`（串口看 `[STAT]` 与屏上画面），或走门禁 `bash build/gates.sh`
  - 输入路径：`src/ps/main.c:714` 的 `FILL` 路径 + `build/ps_app.elf`
  - 期望输出：`FILL` 诊断帧能上屏（四象限 + 顶部绿条），屏上内容与写入 DDR 的图案一致
  - 实际输出摘要：`report/log/ISSUES.md` `#47`/`#53` 与 `board/VERIFY_r87.md` 一类的上板验收登记了这一路径可用；本条**没有**留下一份专门证明"漏 flush 会坏"的反例件 ⇒ "漏 flush 的可观察后果"记 `【待验证】`（要跑的是：把 `Xil_DCacheFlushRange` 那一行去掉，重编 ELF，同一探针重采并留档）
- DMA 目的缓冲区"进之前先 flush"这条成对要求（§5.1 路线二的 (b)）：源码与机制说明在 `src/ps/sd_play.c:84-95`（含"invalidate 之后脏行仍会被写回，把刚 DMA 进来的数据盖掉"这句）；**没有**留下一份"去掉这行 flush 就会坏"的反例件 ⇒ 该后果记 `【待验证】`（要跑的是：删掉那一次 `Xil_DCacheFlushRange`、重编 ELF、同一张卡同一帧号回放，比较屏上与 `[SD]` 读数是否出现脏行覆盖的形状）。
- 表 5-A"路线一"、§5.2"长度上限/突发边界"、§6 第 4/5/7/9 条：`【未实测】`，因为本仓没有 PL 侧 DMA IP。

## 8. 提炼来源与边界

<!-- 本仓示例取值 --> - 来源证据（本地文件，逐条点名）：`src/ps/main.c:41-46,714-716`、`src/ps/sd_play.c:84-95`、`src/rtl/top/system_top.v:52-106`（含 `m_awlen_axi3 = m_awlen[3:0]` 与 `ARCACHE/AWCACHE = 4'b0011`）、`src/rtl/axi/axi_frame_writer64.v`（`BEATS = 16`、`arsize`/`arburst` 常量）、`build/tcl/build_system_axigpio.tcl:160-173`（BD 里只有 GPIO + intercon + HP0，无 DMA IP）、`src/host/ddr_verify.mjs`、`board/ddr_churn_probe.mjs`、`board/ddr_churn_r33_pair.md`、`report/log/ISSUES.md` 的 `#29`/`#33`/`#55`/`#59`/`#316`、`report/BUILD.md` §1。
- 外部依据（本次真的打开的页面/文件；URL 与核对日期见同目录 `_proposed-sources.md`）：AMD 裸机库 `standalone/src/arm/cortexa9/xil_cache.c` 与 `xil_cache.h`（缓存行 32B、非对齐行"先 flush 再 invalidate"的原话、函数原型）、`XilinxProcessorIPLib/drivers/axidma/src/xaxidma_hw.h`（状态/控制/长度寄存器与错误位、多通道长度上限宏）、`XilinxProcessorIPLib/drivers/intc/src/xintc_l.h`（中断三级结构的寄存器偏移）、AMD Embedded Design Tutorials 2020.2 引言页（HP/ACP 的定义原文）、PYNQ v2.5.1 Overlay Tutorial 与 v2.5.1 `allocate`、v3.1 `MMIO` 文档页。
- 明确没打开的东西（不许当依据引）：`docs.amd.com` 的 UG585「PL DMA via AXI High-Performance (HP) Interface」页与 PG021/PG041/PG020 产品指南 —— 本次抓取只拿到需要 JS 的占位页（正文为 "Loading application..."），第三方镜像的 UG585 PDF 因 30 MB 超限取回失败 ⇒ 关于 HP 端口是否被 snoop、SDU 行为、描述符格式的一切具体断言在本条一律 `【未核实】`；文档编号（PG/UG 类）本条不写，需要时自行到 AMD 文档中心核对。
- 恒成立 / 平台相关 / 版本相关：流程顺序（先定路线 → 再定缓冲纪律 → 再定完成判定 → 再定位故障）与"所有权交接必须显式"恒成立；端口种类（HP / ACP / 无）、缓存层级（L1+L2 是否在通路上）、地址位宽是平台相关（表 5-A、§5.2）；`Xil_*Cache*` 接口名、AXI DMA 寄存器偏移与宏名是版本相关（随 embeddedsw 版本变，本条引的是取回时那份 master 上的文件）。
- 不再适用的条件：换成 Linux UIO/DMA 驱动形态（维护由内核与 `dma_*` 映射负责，本条的裸机接口全部作废）；换成带一致性端口的器件且 PL 确实接在该端口（路线二退为兜底）；缓冲区不再与别的变量共享缓存行（§5.2 第一条的强约束可放松为仅对齐）；本工程若引入真正的 DMA IP，本条的 `【未实测】` 段落必须逐条替换成实跑读数才能发布。
- 迁移到新题目/新板卡要改的几处：① 器件家族的一致性端口名称与地址可达范围；② 缓存行大小（本条引的是 Cortex-A9 裸机实现里的 32B，别的核要在其对应 BSP 实现里重查）；③ 长度字段位宽与单次上限（若用 AXI DMA/CDMA/VDMA，读它自己那份寄存器文档，不要沿用本条的宏名）；④ 采样姿态：调试器读 DDR 是否经处理器缓存，这一条在每个平台都要重验；⑤ §6 的"对齐"列在 `pitfalls/` 目录建立后填真实编号。

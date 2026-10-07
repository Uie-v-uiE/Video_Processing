# 10 · 帧缓冲、AXI 与仲裁：一帧画面怎么从网线走到屏幕，以及中间那台搬运机归谁

> 这一章的射程：**DDR 帧缓存的组织**（三块 bank、基址、提交脉冲）、`src/rtl/axi/` 的两个读取引擎
> （`axi_frame_writer_gated` / `axi_frame_writer64`）与喂显示侧的读路径、**同一块 bank 上两个写入者的
> 仲裁**（ETH 与 SD 在 HP0 bank0 上的那次实测抢占）、LUTRAM 打包器 `src/rtl/eth/axi_frame_saver64.v`
> （512×100 bit，为什么必须落在 LUTRAM、为什么不能再削）、abort 之后在途拍串帧那个真 bug 和它的修法，
> 以及像素 / AXI / Eth 三个域之间所有跨域点的总账。
>
> 不教 Verilog 语法。每条行为都指到实际打开过的那一行；资源与名册读数按盘上那一份报告：
> `build/utilization.rpt:4` 的文件头打的是 `Date : Sun Oct 4 04:37:30 2026`、`Design State : Routed`，
> `build/cdc.rpt:4` 同一批（`Oct 4 04:37:32`），对应板上 r118 那颗位流
> （`那一轮的逐轮页` 的 B1 名册逐格等于 r114）。重建会原地重写这几份，
> 所以每个数后面都跟着它的行号，方便对着新版本复核。
>
> 前置在第 00 章：bank / 提交 / 在途事务 / 反压 / 三种合法跨域形态
> （`00-prerequisites.md` 的第 4、5、6 节）。这一章只做一件事——把那些概念换成这套代码的行。

---

## 1. 地址地图：这块 DDR 里有三块画布，不是一块

### 1.1 三块 bank 与它们的数字

| 区域 | 基址 | 谁写 | 谁读 | 定义处 |
| --- | --- | --- | --- | --- |
| ETH bank0 | `0x1000_0000` | PL 的打包器（HP0 从设备口） | 显示侧搬运机 `u_row` | `src/rtl/eth/eth_udp_video_top.v:67`、`src/rtl/top/system_top.v:139` |
| ETH bank1 | `0x1008_0000` | 同上（乒乓的另一页） | 同上 | `src/rtl/eth/eth_udp_video_top.v:68` |
| PS 专用 bank | `0x1010_0000` | PS 的 SD DMA / FILL | 显示侧搬运机 `u_aw` | `src/rtl/top/system_top.v:144`、`src/rtl/top/pl_video_top.v:16` |

一帧的字节数由几何唯一决定：`IMG_W*IMG_H*2 = 512*300*2 = 307200`
（`src/rtl/eth/eth_udp_video_top.v:235` 把 `FRAME_BYTES(IMG_W*IMG_H*2)` 显式传给重组器；
这条为什么要显式传，`#158` 记了账——以前不传，用的是 `frame_reasm` 默认值 307200，
它只在 512×300 这一档**偶然相等**，改分辨率就会让"整帧收完"那道门提前成立或永不成立）。

两块 bank 的间隔是 `0x0008_0000` = 524288 字节 > 307200 ⇒ 乒乓两页不重叠；
第三块从 `+1 MB` 起，理由写在 `src/rtl/top/system_top.v:140-144` 的那段注释里，
它是 **`#53` 那次实测抢占之后加进去的**（见第 6.3 节，那一节是本整章的因果核心）。

`src/rtl/top/system_top.v:134-138` 这一段值得逐字读：`VIDEO_W/VIDEO_H/PANE_W/DDR_BASE/PS_DDR_BASE`
被集中成一份 localparam，然后分别传进 `u_eth` 与 `u_pl` 两个例化。注释给出的理由不是"整洁"，
是一个具体的失效模式——两个模块各自都有 parameter，但**没有任何东西阻止两边不一致**，
而不一致的现象是"写进去的帧几何与读出来的显示几何对不上"（整幅错位/撕裂）：
那既不是综合错误，也不是仿真必红，只有上板才看得见。改分辨率因此从"全文搜字面量"变成"改这四行"。

### 1.2 固件里的同一个数是另一份真值

`src/ps/sd_play.c:35` 的 `#define FRAME_ADDR 0x10100000u` 与 `src/ps/main.c:46` 的同名宏，
必须等于 RTL 的 `PS_DDR_BASE`。这条"两个语言各写一遍同一个数"的耦合没有编译期检查，
注释直接写了后果：**差一边就是"PS 片源在屏上不动"**——搬运机读的是另一块内存，
而屏上、串口、`check_timing` 都不会告你（`src/rtl/top/system_top.v:142-143`、
`src/rtl/top/pl_video_top.v:14-15`）。读这类"地址常量"的时候，先问的第二句永远是
"这个数在另一侧还有没有一份，谁保证它们相等"。

### 1.3 两套下标，别混

这条链上有两个都用 `wr_addr[18:…]` 写的下标，单位不同：

- 重组器到打包器：16 bit 字下标。`src/rtl/eth/frame_reasm.v:151` 是 `wr_addr<=off[18:1]`
  （字节偏移除以 2），一路到 `src/rtl/eth/axi_frame_saver64.v:88` 的 `in_widx = wr_addr[18:2]`
  才变成 64 bit 字下标，再在 `src/rtl/eth/axi_frame_saver64.v:110` 用 `{10'd0, cur_widx, 3'b000}`
  乘回字节地址。三个除法/两个乘法都在移位上，因为几何是 2 的幂。
- 搬运机到帧缓存：`src/rtl/axi/axi_frame_writer_gated.v:159` 与 `:170` 交出去的是 `r_pix[18:2]`，
  而 `src/rtl/video/frame_buffer_w64.v:14` 明确写着这个口收的是 64 bit 字下标；
  同一模块的读口 `rd_addr` 收的却是**像素号**，它自己在 `src/rtl/video/frame_buffer_w64.v:53`
  再除一次 4，并用 `rd_addr[1:0]` 选 64 bit 字里的第几个 16 bit lane（`:66`、`:72-79`）。

读这类代码的正确顺序不是"看模块名猜单位"，而是**从端口声明的那行往回追它被谁除过**。
这条链上任何一次单位混用都不会报错，只会让画面错位或者出现均匀的黑点。

---

## 2. 写侧：从 GMII 字节流到一次 AXI 写

### 2.1 四级缓冲，每级吸收的是不同性质的突发

```
frame_reasm（eth_rxc 125 MHz，16bit 写口 + flush 标记）
   ↓ 打包成 36 bit 条目 {flag, addr[18:0], data[15:0]}
dc_fifo（BRAM，8192 条，格雷码指针）
   ↓  axi_clk 100 MHz 侧三级读流水
axi_frame_saver64（LUTRAM 打包器 512×100bit → AXI3 AW/W，在途 8）
   ↓
HP0 → DDR 的某一块 bank
```

`src/rtl/eth/eth_udp_video_top.v:263-265` 是把"数据写"和"flush 标记"压进同一条 36 bit 总线的地方：
`cdc_data = fb_wr_en ? {1'b0, fb_wr_addr, fb_wr_data} : {1'b1, 19'd0, 16'd0}`。
为什么要压进同一条队列，`src/rtl/eth/eth_udp_video_top.v:258-262` 给了数字：
一个 1392 字节的包在 125 MHz 下是**连续线速**进来的（上位机限速只能拉开包间隔，不能拉开包内节拍），
每包 698 个 16 bit 写；原来读侧限成"每 3 个 axi 周期取 1 条" = 66 MB/s < 125 MB/s，
单包就能把 512 深的 CDC 灌满，稳定丢约 46 % 的字，板上的表现是"每隔一个 16bit 空洞"的黑纹。
修法是 1 条/周期（200 MB/s）。这段注释里还有一句容易被跳过的话：**flush 标记永远让路给真实数据写**
（`:262` 末尾与 `src/rtl/eth/frame_reasm.v` 那条 `flush_pend` 的挂起逻辑
`src/rtl/eth/eth_udp_video_top.v:267-271`）。

`src/rtl/eth/eth_udp_video_top.v:307-322` 是 axi 侧的三级读流水：
`fifo_rd → cdc_d1/cdc_d1_v → sav_en/sav_flush`。这三级不是可有可无的管道装饰：
它们的存在正是 `#33` 那个"帧尾 4 字节偶发丢失"能被写进提交判据的原因（第 4.2 节）。

### 2.2 打包器的两个关键设计：在途深度与写选通

`src/rtl/eth/axi_frame_saver64.v:65-74` 是这台模块的心脏：

```
OST = 8            在途 beat 上限
have = (rptr != wptr) && !beat && (outst < OST)
aw_wait / w_wait   本 beat 的 AW / W 各自还没被接收
```

`AWLEN=0 + AW/W 并行挂出`（`src/rtl/eth/axi_frame_saver64.v:2-3`、`:40-44`），
B 通道**永不反压**（`:156` 那一行 `m_axi_bready <= 1'b1` 是无条件的），响应只用来回收计数。
为什么必须这样，文件头第 5-7 行写得比任何论文都直白：v6.2 之前每字走完 `S_AW→S_W→S_B`，
在途深度恒为 1 ⇒ HP0 写延迟（约 40 拍，被显示拷贝抢端口时上百拍）直接成为吞吐上限 ≈20 MB/s，
而主机给 15 MB/s 只有 1.3× 余量，于是"每包固定从第 48 字节起丢字"。
**加深缓冲治不了它**——`src/rtl/eth/axi_frame_saver64.v:7` 那句
"瓶颈是**平均排空速率**不是深度，v6.2 把 CDC 做到 8192 时上板毫无改善"，
是这一章希望留下的第一个可迁移结论：**先看 Little 定律意义上的在途数，再看缓冲**。

`outst` 的增减写法是第二个可迁移点（`src/rtl/eth/axi_frame_saver64.v:157-160`）：
加 1 与减 1 互斥，且减是**只减不回绕**——`outst <= (outst == 4'd0) ? 4'd0 : outst - 4'd1`。
注释给的理由（`:158-159`）：万一上游偶尔多回一个 B，回绕成 15 会让 `have` 永远不成立，
整条入包链就此卡死，症状正是板上那一类"冻结"。宁可少计也不要锁死。
同一族教训在 `#35`（`开发台账`）里从反面出现一次：
xsim 的从机模型用上一拍的 AW 地址配 W、只有 1 个 B 寄存器、用组合 ready 握手，
于是流水化的 master 在仿真里表现出"数据错位 + `outst` 回绕 15 + 永久不排空"——
**看到 master 不排空，先验从机的 B 计数与握手**，这条顺序能省一整夜。

`m_axi_wstrb` 是按 16 bit lane 生成的（`src/rtl/eth/axi_frame_saver64.v:83-84`），
背后是 `:80-82` 那段实测：旧实现恒为 `8'hFF`，"同一个 64bit 字被相邻两包分两次写"时
后一次会把前一次的半字覆盖成 0。分包长度不是 8 的倍数（例如 1396）时，
每帧 111 处 = 222 个 16bit 黑洞，屏上是均匀散布的黑点。
这个 bug 的形状值得记住：**它与速率、与丢包、与时序都无关，只与包长是否为字宽的整数倍有关**，
所以任何"按流量测试"的判据都容易漏掉它——台架要专门喂一个非整倍数的包长。

### 2.3 满的时候丢字：一条按 bug-for-bug 保留的语义

`src/rtl/eth/axi_frame_saver64.v:101-102`：

```
push_now = enable && ((wr_en && idx_chg) || (flush && cur_dirty && !wr_en))
pack_we  = push_now && !fifo_full
```

`变更志` 明写这是 V7.0 重构时**故意不动**的部分
（"满时丢字、flush 仍清 `cur_dirty` 的既有语义按 bug-for-bug 保留，不与 V7.2 混在一个改动里"）。
于是"打包器满 ⇒ 丢一个字"与"这个丢法会不会被统计"就变成两件必须分开回答的事。
板上唯一真实的丢数据通道其实在更上游：`src/rtl/eth/eth_udp_video_top.v:273-283`
把"这一拍的 CDC 写被 `fifo_full` 挡住了"做成了可读数量（`cdc_wr_req` 与 `fifo_full` 送进
`link_monitor`），配套注释解释了为什么必须有它——RGMII 只有 4 数据 + 1 控制，
**板上根本没有 RX_ER 这根线**（`src/rtl/eth/eth_udp_video_top.v:154-157`、
`src/rtl/eth/eth_udp_video_top.v:189` 的 `.gmii_rx_er(1'b0)`），
于是收侧的"坏包"统计在没有自算 FCS 之前是构造性为 0 的死数字。
读这类"看起来多余的观测口"时，先找它的**替代判据是不是不存在**，往往就能读出血缘。

---

## 3. LUTRAM 打包器：512 × 100 bit 为什么只能落在 LUTRAM

### 3.1 三段证据，一段比一段硬

`src/rtl/eth/axi_frame_saver64.v:48-50` 是三个数组，每个 512 格：

```
q_addr[31:0]  q_data[63:0]  q_keep[3:0]      ⇒ 100 bit × 512
```

三个都带 `(* ram_style = "distributed" *)`。这个属性为什么必须写、写成什么形状才生效，
`变更志` 有一份五变体对照表（最小实验 +
逐个 `synth_design -mode out_of_context` 数单元类型；那份 `sim/probes/ramtest.v`
**已不在盘上**；`ls sim/probes/` 现在只剩 `dpfbtest.xpr` 与 `probe4.log`，
所以下表是从台账抄的，重跑要先把那个探针文件重写出来）：

| 变体 | 写法 | FF | LUTRAM | BRAM |
| --- | --- | --- | --- | --- |
| v1 | 数组写放在带异步复位的控制块里、经 task 调用（= 原 RTL 形状） | 32904 | 0 | 0 |
| v2 | 数组写独占一个无复位 always 块，full 折进写使能 | 85 | 864 | 0 |
| v3 | 同 v2 但不加 `ram_style` | 22 | 1 | 1 |
| v4 | 二维数组按字节拆 | 32911 | 0 | 0 |
| v5 | 同 v2，属性写成注释式 | 85 | 864 | 0 |

三条结论，逐条都能落到代码上：

1. **阻碍 RAM 推断的是"数组写与异步复位控制逻辑同处一个 always 块 + task 封装"，不是读口形状。**
   这条直接写在 `src/rtl/eth/axi_frame_saver64.v:104-107`，并且那份代码块
   （`:108-114`）至今是一个不带复位的 `always @(posedge clk)`。
   只加属性没用：综合报 `WARNING [Synth 8-7186] ... is ignored, object 'q_addr[N]' is not inferred
   as ram due to incorrect usage`（`变更志`）。
2. **属性必须显式写 `distributed`**，因为不加时综合器会把它塞进 BRAM（表里 v3 那一行），
   而当时 BRAM 只剩 1.5 个 tile（`变更志`）。
3. **收益是真的**：V6.4 → V7.0 的整机账（`变更志`）——
   Slice Registers 54588（51.30 %）→ 9593（9.02 %），Slice 99.92 % → 34.99 %，
   WNS 只掉 0.031 ns（+0.708 → +0.677，全约束仍满足），回归 28/28。
   也就是说这次改造用 0.031 ns 换回约 4.5 万个寄存器。

今天的落点由 `build/util_hier.rpt:52` 那行确认：`u_saver | axi_frame_saver64`
= **LUTRAMs 928、RAMB36 0、FF 242**。全局那行 `LUT as Distributed RAM = 4044`
（`build/utilization.rpt:38`、`:84`）里超过五分之一是这一个实例。

### 3.2 "512/512 满"：它为什么是承重墙而不是余量

资源紧的时候第一个问题永远是"这块 100 bit × 512 能不能削"。答案由**过载时的峰值占用**给，
不由读代码给。`开发台账`（`#140`）把两把尺子的读数落在两份件上：

| 跑法 | 打包器峰值 | CDC 峰值 | 判定 |
| --- | --- | --- | --- |
| 默认（60 包 / GAP=10230 ≈ 限速 15 MB/s） | 122 / 512 | 3 / 8192 | PASS，零丢（`build/r88_packer_peak_throttled.txt:3`） |
| `+FULL +GAP0`（一整帧 221 包 GMII 线速连灌） | **512 / 512（满）** | **8192 / 8192（满）** | 这条本来就是"过载会丢"的诊断跑，不是采纳跑（`build/r88_packer_peak_gap0.txt:21,23`） |

判词是 `开发台账`：**`FW` 不许降**。线速连灌下打包器 FIFO 是被填满的，
那约 800 个 LUTRAM 是承重墙，不是余量；降 `FW` 等于砍掉入包链上第二级（也是唯一一级）
在 CDC 之外的吸收缓冲。这一条到此为止，不改源。

同一个台账还顺手挡掉了第二个"看起来免费"的刀：`q_addr` 能不能退化成"基址 + 序号"省掉 13 位高位？
不能，理由在代码里而非猜测——`src/rtl/eth/axi_frame_saver64.v:110` 存的是
`pack_base + cur_widx*8` 这个**绝对**地址，而 `pack_base` 会在帧中途随 `!cur_dirty` 换基址
（`src/rtl/eth/axi_frame_saver64.v:91-95`）。队列里还有旧条目时换基址，"序号"就对不上。
判据出处 `开发台账`。

`src/rtl/eth/axi_frame_saver64.v:91-95` 那三行本身也值得停一下：`pack_base` 只在
`!cur_dirty`（正在拼的字为空）时更新，意味着**换 bank 这件事被推到"字边界"上**。
这一处与第 4 节的 `TAIL_GUARD` 是同一场病的两个半边：一个是"别在半个字上换基址"，
一个是"别在半个字还没到时就翻页"。

### 3.3 同一把 recipe 第二次用：显示侧的 skid

`src/rtl/axi/axi_frame_writer_gated.v:50-58` 的 64×83 bit skid 缓冲走的是同一条路，
起因是 `WARNING [Synth 8-4767] Trying to implement RAM 'sk_addr_reg' in registers`，
而它掉进触发器的那份账"约占整机剩余寄存器的一半"（`:50-52`，
另见 `变更志`）。写法照 V7.0 的 recipe：
两个写入点的条件并集恒等于 `do_skid`，合并成一个写脉冲、独占无复位块
（`src/rtl/axi/axi_frame_writer_gated.v:91-99`），读口改异步（`:60-64`）。

代价写在 `变更志`，而且写得很直白：**省 5215 个寄存器的代价是
WNS 掉 0.320 ns**（+0.819 → +0.499），因为分布式 RAM 的异步读口在 100 MHz 域多了一级读选择。
仍 `All user specified timing constraints are met`、0 失败端点，所以接受。
这里可迁移的是那句判断口径：**存储结构的选择是一次交易，账要两头都记**——
只报资源节省、不报余量代价，下一次有人就会拿它当"免费优化"再花一遍构建批。
同一族交易被反过来量第二次是 `#146` 旁边那笔 BRAM 换 setup（帧缓存拆块省 RAMB36、
`eth_rxc` 余量变薄、级数 4→9，`report/40-optimization.md:114` 的 V2 行），
第 9 节把这些"量过并拒绝"的刀收成一张表。

---

## 4. 提交脉冲：一帧"写完了"这件事在两个域里各怎么说

### 4.1 `ddr_bank_commit` 的全部结构

`src/rtl/eth/ddr_bank_commit.v` 只有 81 行，是整条链上最该逐行读的一个文件。
文件头 `:2-7` 先交代了它为什么独立成模块：这段 glue 原来内联在 `eth_udp_video_top` 里，
台架只能**手抄一份**来测，而手抄的副本不会因为真代码改错而变红。
`变更志` 把这件事称为"工程化前置（比补丁更重要）"——
抽出来之后 `tb_v6_pingpong` / `tb_v6_tail_bank` 例化的是上板的实现。

跨域那一半是标准的翻转 + 3 级 + 异或（`src/rtl/eth/ddr_bank_commit.v:36-47`）：
`frame_done` 在 gmii 域把 `frame_done_tog` 翻一位，axi 域用打了 `ASYNC_REG` 的
`fd0/fd1/fd2` 三拍（`:42`），`fd_axi = fd1 ^ fd2`（`:47`）。
为什么用翻转而不是把脉冲直接跨过去，`开发流水账:100-105`
那段注释给了实测理由（第 8.3 节会回到这里）：**两路时钟同源同相时，
电平型同步器与裸采样在相位扫描下逐相位一模一样，只有翻转式能修**。

### 4.2 `TAIL_GUARD`：`saver_idle` 看不见 CDC

`src/rtl/eth/ddr_bank_commit.v:49-51`：

```
tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush
commit_ok    = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle
```

`#33` 的症状是"某个 bank 最后一个 64bit 字的高半个 u32 读到 0，8 次末帧读数出现 4 次，
15/30/60 fps 都会"（`开发台账`）。机理在
`变更志`：换页判据里的 `idle` 只描述打包器自身
（`src/rtl/eth/axi_frame_saver64.v:86` 的定义：
`enable && !cur_dirty && fifo_empty && !beat && (outst == 4'd0)`），
它对 **8192 深的 CDC 与它后面那两级读流水完全不可见**。
打包器满过一次之后，若 `sv_full` 恰好在最后一个字中间放开，本帧最后 2 个 lane 还排在 CDC 里；
此时 `frame_done` 已同步到 axi 域并拉起 `force_flush`，把已到达的半截字推走 ⇒ 打包器排空 ⇒
`saver_idle` ⇒ 翻 bank；随后那 2 个 lane 进打包器时 `pack_base` 已换 bank ⇒
写进**下一帧**的缓冲区。板上是 HDMI 右下角少 2 像素（`src/rtl/eth/ddr_bank_commit.v:6-7`）。
相位相关 ⇒ 4/8 次、与速率无关。

修法就是把"CDC 可见排空"写成判据（上面那五行）。台架的形状也值得学：
`变更志` 的 `sim/tb_v6_tail_bank.v` 是**两条完整入包链**
（各自 `dc_fifo` + `axi_frame_saver64` + commit + AXI 从机）喂同一激励，
`TAIL_GUARD` 一个 0 一个 1，双向判据——旧链必须复现丢尾、新链必须整帧完整，缺一侧即 FAIL。
读数：

```
frame0: 完整 old=8/8 new=8/8
frame1: 完整 old=7/8 (first_bad_word=7)  new=8/8      ← 正是帧尾那一个 64bit 字
commits old=2 new=2                                     ← 换页没有被过度延迟
```

`commits old=2 new=2` 那一行是**反配对**：它拦住"把判据改成永远不提交"这类修法。
一条新判据如果只写"坏的要红"，很容易被修成"整条链不动作"而变绿，这一行就是防这个的。

同一文件被否决的两项也留了记录（`变更志`）：
加 `else if (idle) pack_base <= base_addr;` 是死代码（`!cur_dirty` 在 idle 时必然已成立）；
加超时兜底被换成"CDC 可见排空"，不需要计数器与新状态。

### 4.3 bank 翻转与 `commit_pulse`

`src/rtl/eth/ddr_bank_commit.v:53-77` 是提交侧的时序过程，四条值得逐条念：

- `sav_base = bank ? BANK1 : BANK0`（`:79`）——打包器**当前正在写**的那页。
- `completed_base <= sav_base`（`:68`）——交给显示侧的是"刚才写完的那页"，
  注意它取的是**翻转前**的 `sav_base`：`bank` 在 `:69` 同拍才翻。顺序读反就会显示正在写的那页。
- `commit_pulse <= 1'b1`（`:70`）是**一拍**，且 `:62` 每拍先清零。
  这个脉冲是显示侧唯一知道"有帧可搬"的事件，它的跨域形态在第 5 节。
- `force_flush` 的落回条件 `if (saver_idle && !switch_req) force_flush <= 1'b0`（`:74-75`）
  配 `pack_flush = sav_flush | (force_flush && tail_drained)`（`:80`）：
  flush 请求也受同一个 `tail_drained` 门，不会在数据还没过完 CDC 时插到前面去。

`switch_req` 与 `force_flush` 两个端口在顶层是**悬空的**
（`src/rtl/eth/eth_udp_video_top.v:348-349`）。它们留着是给台架看的——
`sim/tb_v5_bank.v`、`sim/tb_commit_strobe.v` 直接例化这个模块。
读端口表时看到"顶层没接的输入输出"，先分它是**调试口**还是**死代码**，
本仓库对后者的处理是真删（`src/rtl/top/system_top.v:130-133` 记了 `u_eth` 四个统计口
在本层故意不接的理由，以及"一批台架直接读它们"所以端口留着是对的）。

---

## 5. 读侧：搬运机、消隐窗与看门狗

### 5.1 三代读引擎，现役两代

`src/rtl/axi/axi_frame_writer.v:2-3` 的文件头第一句就是"**本树无人例化**"：
现役是 `axi_frame_writer_gated`（逐行拷、消隐期写）与 `axi_frame_writer64`。
它只在 `sim/run_sim.tcl` 的文件清单里挂名。判断"这份 RTL 到底在不在 bit 里"，
`build_system_axigpio.tcl` 的源清单（`src/rtl/top/system_top.v` 为 top，
`build/tcl/build_system_axigpio.tcl:25-29` 把 9 个目录的 `*.v` 全收）只能证明"被编译"，
被编译不等于被例化——所以这份文件自己声明"无人例化"是有价值的写法。

| 引擎 | 例化名 | 用途 | 定义 | 挂载 |
| --- | --- | --- | --- | --- |
| `axi_frame_writer_gated` | `u_row` | ETH：把刚提交的 bank 拉回显示帧缓存，只在 `allow_wr` 那几拍落 BRAM | `src/rtl/axi/axi_frame_writer_gated.v:2-7` | `src/rtl/top/pl_video_top.v:454-469` |
| `axi_frame_writer64` | `u_aw` | PS 片源（SD 回放 / FILL）：整帧拷贝，无消隐门 | `src/rtl/axi/axi_frame_writer64.v:2-3` | `src/rtl/top/pl_video_top.v:692-707` |
| `axi_frame_writer` | 无 | 早期一代，64 bit 读、4 拍展开写 16 bit 口 | `src/rtl/axi/axi_frame_writer.v:2-4` | 不在 bit 里 |

两个现役引擎的差异不在协议，在**写权限**：`u_row` 有 `allow_wr` 与 `abort` 两个门，
`u_aw` 没有。这不是疏忽——`u_aw` 只在 PS 拥有搬运机时被 enable
（`src/rtl/top/pl_video_top.v:696` 的 `.enable(eth_mode ? 1'b0 : src_sel)`），
而它的写口与 `u_row` 在同一个 mux 上（见 6.2），换手时两边不可能同时写。

### 5.2 消隐窗：为什么不能拿 vsync 当搬运起点

`src/rtl/video/frame_commit_lock.v` 是"把提交锁进消隐窗口"的那把锁，两个域：
搬运在 `axi_clk`、判窗口在 `pix_clk`（`:2`）。链路：

1. `blank_safe`（像素域）先 3 拍同步成 `blank_pix`（`:45-57`），再跨回 axi 域打 `d0/d1/d2`
   带 `ASYNC_REG`（`:71-76`），`allow_copy_axi = d1 & d2`。
2. `vsync` 在像素域被用来翻一位 `blank_tog`（`:56-63`），再进 axi 域 3 拍异或成 `vsync_req`（`:64-69`）。
3. **起点取的是窗口的"开张沿"而不是 vsync 沿**：`:78-86` 那段注释给了数字——
   1024×600 的 `V_FP=3, V_SYNC=6`，vsync 只会在 25 行窗口的第 9 行才升起，
   拿它当起点等于扔掉三分之一的搬运预算。所以 `start_copy` 的条件是 `allow_rise || vsync_req`
   （`:117-122`），前者优先。

窗口本身由显示侧算：`src/rtl/top/pl_video_top.v:397-401`
`disp_quiet = (y >= 600) && ((y < 624) || (x <= 1279))`。
`VB_X_GUARD = 1344-65` 那一行注释解释了为什么要早关 64 个消隐像点：
`allow_copy_axi` 过 `frame_commit_lock` 的 CDC 要晚约 5 个像素拍，
不留这段余量，窗口的**尾巴**就会咬进下一行的有效区。这是"CDC 延迟要算进物理窗口"的教科书案例。

预算数字在 `src/rtl/top/pl_video_top.v:442-452`：`VBLANK_AXI_CYC = 67200`
（25 行 × 1344 像素 × 2 个 axi 拍）。诊断逻辑是 `row_done` 时若
`row_copy_cycles > VBLANK_AXI_CYC` 就把 `copy_overrun` **粘滞**置位，直到重新加载 bit 为止，
用 `led[0]` 看。注释把后果也写全了：超窗 ⇒ 换帧跨了两个消隐期 ⇒ 屏幕上同一帧的新旧两半并存 ⇒
运动物体被一条水平缝切开 + 拖影。

### 5.3 搬运机的三条写路径与在途深度

`src/rtl/axi/axi_frame_writer_gated.v:45-47` 定 `MAX_OUT = 4`：
4 个 16 拍的突发在途 ≈ 64 拍，注释说明这个数是按"盖住 HP0/DDR 读延迟、
在 25 行的窗口里保持约 1 拍/周期"选的。一整帧是
`TOTAL_BURSTS = ceil(38400/16) = 2400` 个突发（`:42-44`）。

三条写路径（`:86-89`、`:157-180`）：

- `do_direct`：`r_hit && allow_wr && sk_empty && !dropping` ⇒ R 数据**直写 BRAM**，
  一拍一个 64 bit 字（`:168-174`）。`:5-6` 那句
  "copy finishes inside one display frame → no motion ghosting" 就是靠它。
- `do_skid`：数据进 skid 数组（`:94-99`）。
- `sk_drain`：`allow_wr` 重新成立且 skid 非空时，把排队的字按顺序写进 BRAM（`:157-167`）。

`sk_full` 的门限是 `sk_level >= (64-1)`（`:58`），而 `can_issue` 还额外要求
`sk_level <= 63-BEATS`（`:84`）——**留出整整一个突发的余量**，因为一次 AR 会带回来 16 拍，
而这 16 拍里没有 `allow_wr` 的话全都得进 skid。这类"预算 = 最坏一次突发"的余量写法
是突发接口上必须算的账，不是保守系数。

`done` 的条件在 `:182-186`：`wr_words >= TOTAL_WORDS` **且** `sk_empty` **且**
`!m_axi_arvalid` **且** `outstanding==0` **且** `!sk_drain` **且** `!fb_wr_en`。
六个条件里后四个都是"还有尾巴的时候不许宣布完成"。这条形状与 4.2 的 `tail_drained`
是同一个思想的两次落地，分别守在写侧和读侧。

### 5.4 `#170`：abort 之后在途的读拍会串进下一帧

这是本章最该细讲的一个真 bug，因为它抓的是**协议义务**而不是逻辑错误。

原始形状（`开发台账` 记录的是改前）：
`m_axi_rready = active && !sk_full`，而 abort 那一拍把 `active` 清 0 ⇒ 从下一拍起不再接收任何 R 拍。
问题在于 **AXI 不许 master 撤回已经举起的 `rvalid`**：那些拍不会消失，它们会等在下一帧门口。
下一帧 `start` 之后第一批被接收的拍其实属于上一帧，而写地址是按"本帧第几个字"推进的 ⇒
症状是"整帧平移 + 顶部花"；同时 `outstanding` 在 abort 时被清 0、随后又按这些**旧拍的 rlast**
递减 ⇒ 计数从此与真相不符（第二半条账）。`abort` 不是理论态：`copy_overrun` 那条路会触发它，
而 `abort_tgl` 这个端口的存在本身就是它发生过多次的证据（`开发台账`）。

修法（`src/rtl/axi/axi_frame_writer_gated.v:69-79`、`:115-122`、`:138-146`）是**排空态**而不是关门：

```
drain_left <= outstanding          // 还有几个 burst 的尾巴要丢掉
dropping   = (drain_left != 0)
m_axi_rready = (active && !sk_full) || dropping     // 排空期间照样接收
```

`dropping` 同时关掉 `do_direct` / `do_skid` / `sk_drain` 三个写口（`:87-89`），
所以"接收"与"落 BRAM"被解耦；每个 burst 见到自己的 `rlast` 就减一（`:121`），数到 0 才允许下一帧起头。
排空途中上位机又按了 `start` ⇒ 记一笔 `start_hold`（`:122`、`:125-127`），排空完成那一拍补起。
`:118-119` 那句注释把不补的后果说清楚了：会变成"这一次 start 被吞、屏上一直停在旧帧"，
那是**另一条锁死账**。修一个 bug 时把"不修的另一半会长成什么"写进注释，
是这套代码里反复出现的习惯，值得抄进工程习惯。

`outstanding==0` 时 `drain_left` 也是 0 ⇒ 这一支退化成原来的行为，没有空转（`:143`）。

台架是 `sim/tb_writer_abort.v`，它的文件头（`:20-32`）把全部意义写在一条上：
**响应器必须照协议办事**——`rvalid` 一旦举起来就 held 住，被接收才推进。
如果这里写成"`rready=0` 就把那拍丢掉"，症状根本不会出现 ⇒ 尺子在被测物上做假绿。
B1/B2 两条就是响应器自己的对照（`:32`：abort 的时机必须真的有在途，且那一拍确实还举着没人收）。
画幅故意缩到 64×16 = 256 个字 = 16 个突发，正好能喂出 `MAX_OUT=4` 个在途（`:34-36`）。

三段凭据都在盘上，数字能核对：

| 判据 | 改后（`build/r96_writer_abort_after.txt`） | 变异对照（`build/r96_writer_abort_mutation.txt`） |
| --- | --- | --- |
| B1 前提：abort 那拍确有在途 | PASS，3 个突发未答 | PASS |
| B2 在途拍不许被挡在门外 | PASS | **FAIL** |
| B3 新帧从自己的头开始 | PASS，0 | **FAIL，读到 4** |
| B5 新帧写字数 | PASS，256 | **FAIL，300** |
| B6 新帧不乱序 | PASS，0 | **FAIL，300** |

`B3` 从 0 变 4、`B5` 从 256 变 300、`B6` 从 0 变 300 —— 这三个数就是"旧尾巴污染新帧"的可测形态
（48 = 3 个突发 × 16 拍正好等于 `B5` 多出来的字数，与 `B1` 的 3 对上）。
`开发台账` 还留了一条写判据时的错：B2 最初按**改之前的症状**写成
"要看到 `rvalid=1` 且 `rready=0`" ⇒ 修好之后它反倒红。判据要写成机制断言
（`!inflight || rready`），不能抄当时的现象。

### 5.5 `#171`：`frame_ready` 是电平还是脉冲

`src/rtl/video/frame_commit_lock.v:131-145` 把 `frame_ready_pix` 从"置 1 不清的电平"改成
`frame_ready_pix <= (r1 ^ r2)`（一拍脉冲）。原来的写法（`:136-142` 的注释记录）让
`pl_video_top` 那支 else-if 链里 `frame_ready` **天天为真**，永远抢在 `copy_abort_pix` 之前 ⇒
abort 那一支**不可达**，撕裂帧照样显示、`status` 里的 `eth_ready` 照样读 1
（`开发台账`）。改法有两半：脉冲化 + 顶层换顺序
（`src/rtl/top/pl_video_top.v:524-533`，现在是 `else if (copy_abort_pix)` 在前）。
换顺序那一半的理由是"万一提交沿与 abort 沿真的撞在同一拍，赢的必须是这一帧不可信"
（`开发台账`）。

"改这里安全"的依据也写在同一处，而且是一条可执行检查：**`frame_ready` 在顶层只有一个消费者**
（grep 过，`src/rtl/video/frame_commit_lock.v:141-142`、`src/rtl/top/pl_video_top.v:946`
的 `.eth_new(frame_ready && eth_link_pix)`）。这句话的形态值得记住：
把"我改了这个信号但没牵连别处"从感觉变成一次可复算的检索。

### 5.6 帧缓存的另一半：显示侧只有一个读口，而且它不选边

搬运机只管**写**，读侧的形状决定了"这一帧什么时候真的被看见"。三行接线：

- 写口来自 5.1 那台 mux：`src/rtl/top/pl_video_top.v:716-718` 把
  `eth_mode ? row_* : fill_*` 三对信号合成一份 `aw_wr_en/addr/data`，再在
  `src/rtl/top/pl_video_top.v:732-736` 送进 `u_bilin` 的 `wr_clk(axi_clk) / wr_en / wr_addr / wr_data`。
  **写侧两个引擎、一个口、一份地址流**——这就是 6.2 那句"换手只能在两边都空闲时发生"
  在物理层的样子：mux 上根本没有第二套写通道。
- 读侧 `src/rtl/process/bilin/fb_bilin.v:2-7` 的文件头把账说全了：
  读口挂在 `clk_pix` 50 MHz **单域**（`:11` 那句"没有第二个时钟域"），
  `wr_clk` 只是帧缓存写侧的直通；每个源像素用满它天然的 4 个 50 MHz 拍
  （2 显示列 × 2 显示行），**一个读口每拍一次读，全程不进快域**。
  延迟是"地址寄存 1 拍 + BRAM 1 拍 ⇒ 请求到数据 2 拍"（`:5`、`:39-40`），
  这两个 `1` 正好是顶层 `MIX_D = 3 + 1 + 1 + LATENCY`（`src/rtl/top/pl_video_top.v:354`）里的那两个
  （`src/rtl/top/pl_video_top.v:721-725` 解释为什么换读口不动混色级、skid 与抽头数）。
- 越界的行为两处对齐：`src/rtl/video/frame_buffer_w64.v:67` 的
  `blank <= (rd_addr >= (W*H))` 让填充区回黑，而 `src/rtl/process/bilin/fb_bilin.v:47-54`
  把末行那次 `w_b = w_a + ROW_WORDS` **折回图内**，注释给了硬件与仿真两种坏法
  （`:49-50`：硬件里是 BRAM 上电的 0、xsim 里是 X，而 `X×0 = X` ⇒ 整行被污染）。
  同一件事在两级各挡一次，是因为这两级的"越界"不是同一个条件（一个是像素号、一个是字下标）。

为什么要把这三行单独列成一节：读侧的形状决定了 5.2 那个消隐窗必须存在。
`src/rtl/top/pl_video_top.v:395-396` 的注释写得很直白——显示 BRAM 在每一个有效行里
都持有**一整帧**，所以既没有新旧接缝、也没有读写冲突；
如果允许在有效区写，v5 那条"位置固定的黑线"就是这么来的（拷贝机在半帧处追上了扫描束）。

---

## 6. 仲裁：谁用这台搬运机，以及谁写这块 DDR

### 6.1 为什么"有数据"不是正确答案

`src/rtl/util/src_arb.v:2-16` 那段文件头是本仓库写得最干净的一段动机，值得逐句拆：

- 老写法是 `eth_mode = 3FF(|s_pkts)`。两个问题叠在一起：
  **①** `|s_pkts` 是"自配置以来收到过任何一个包"——PC 的 ARP 就够触发，
  而且**拔网线也不会回 0** ⇒ PS 片源被永久锁死。
  `#47` 修的是它在显示端的表现，`src_arb` 修的是根。
  **②** 就算换成"最近有包"，两个引擎共用同一个 AXI 读口 + 同一个 BRAM 写口，
  选择位在一次拷贝**中途**翻转会留下半开的读突发——老代码里唯一的"互锁"就是那一个选择位本身。
- 于是这件事被拆成两个独立判据：
  **"活着"由 `link_monitor` 用 `stall_ms` 判**（eth_rxc 域，本来就是它的活，
  `src/rtl/eth/link_monitor.v:74`、`:151-165`，`lane7.bit3 = (stall_ms < LIVE_MS)`，
  `src/rtl/eth/link_monitor.v:159`）；
  **"但这个判据必须先确认量它的那个时基还算准"**。

第二条是板级实测逼出来的（`src/rtl/util/src_arb.v:11-14`）：
2026-09-23 量到断链时 RTL8211 不停 RXC 而是把它拉到约 2.5 MHz，`stall_ms` 于是以约 1/48 的速度爬，
`stall_ms < 200` 会连着骗人十几秒 ⇒ 仲裁死占 ETH、SD 接不回画面。
同一件事在 `src/rtl/eth/link_monitor.v:6-8` 与 `src/rtl/eth/snap_cross.v:6-8` 各写一遍，
三处口径一致：**"时钟退化"不等于"时钟消失"**。`snap_cross` 为此把
`hb_slow`（间隔变长）与 `hb_gone`（没有边沿）分成两位（`src/rtl/eth/snap_cross.v:55-65`）。

顶层的接线把这两条并成一个与门：`src/rtl/top/system_top.v:251-256`
`eth_live = lm_axi[7*32+3]`、`eth_tb_ok = !(lm_clk_slow || lm_clk_gone)`，
两者一起送进仲裁（`src/rtl/top/pl_video_top.v:421-425`）。
`src/rtl/util/src_arb.v:49-51` 的取法是**宁可让 PS 接管**：
时基不准时一律当作"没有流"，理由写在注释里——"不要在无法证实的电平上锁死显示端"。

### 6.2 换手只发生在两个引擎都空闲时

```
both_idle = ~row_busy & ~fill_busy                       (src/rtl/util/src_arb.v:48)
if (both_idle) begin owner_eth <= eth_wanted ? 1 : (quiet >= T_OFF_CYC ? 0 : 保持) end   (:67-76)
```

三条设计决定：

1. **手动模式只改"谁想要总线"，不改"什么时候能换手"**（`:41-45`）。
   注释直接说"在输出上加一个 mux 是最容易想到的写法，也是错的"——那会在拷贝中途翻掉选择位，
   留下半开的 AXI 读突发，正是本模块要消灭的那个老毛病。
2. **滞回只往让位方向加**（`:61-64`）：`quiet` 计数器只在 `!eth_wanted` 时爬，ETH 一活就清零
   （回抢不等）。`T_OFF_CYC = 2_000_000` 在 100 MHz 域 = 20 ms（`:18-20`），
   这是**第二级**滞回，第一级是 `stall_ms > LIVE_MS`（默认 200 ms）。
3. **饱和写法**：`if (quiet != 32'hFFFF_FFFF) quiet <= quiet + 1`（`:63`）。
   一个 32 位计数器加到顶再回绕的话，"静默够久"这件事会在 42.9 秒后**再成立一次**，
   而那已经不是原意。

`why_ps` 那三位（`:31-39`、`:73`）是 V8-7 加的原因快照：
`{force_ps, ~eth_live, ~eth_tb_ok}`，且**与 `owner_eth` 在同一个决定点写**。
`#174` 记录的是改前形状——原来 `why_ps` 挂在无条件那一支每拍跟输入刷新，
于是拷贝期间（主人被互锁冻住）翻 `eth_live`，屏上/上位机读到的"为什么 PS 拿着"会跟着变，
而主人一次都没换（`开发台账`）。台架 `sim/tb_src_arb_why.v` 的
`W5` 钉这件事（改前红、读到 `000`，`开发台账`），
`W7` 是它的**反配对**：真换手那一拍必须重新快照（钉成 `src 1` 后拿回屏幕 ⇒ 期望 `100`），
"若把 `#174` 修成 `why_ps` 再也不更新，W5 会变绿而 W7 拦住它"
（`开发台账`）。**每条正向判据配一条反配对**，这条纪律在本章出现了三次
（4.2 的 `commits old=2 new=2`、5.4 的 B1/B2、6.1 的 W5/W7）。

复位值也讲了一次口径：`why_ps <= 3'b011`（`src/rtl/util/src_arb.v:55-59`），
取"没有流 + 时基还没验"，不取 `000`——"`000` 的意思是'一切正常、是被人钉住的'，
那是刚上电时最不该撒的谎"。

### 6.3 `#53`：仲裁七条判据全绿，屏上照样打架

这是"ETH 与 SD 在 HP0 bank0 上抢占"那件实测事，也是第 1.1 节那张三块 bank 表的来历。

`src/rtl/top/pl_video_top.v:13-16` 的那句注释是这一节的题目：
**仲裁只管"谁用 DDR→帧缓存这台搬运机"，管不到"谁写 DDR"**
（SD 的 DMA 走 PS 自己的 HP0 主设备，根本不经过 PL）⇒ 两路同时跑时重叠只能靠地址分开。

`开发台账` 给了完整因果：

- 现象（2026-09-24 用户肉眼报的三条之一）：网线推流与 SD 回放同时跑时，
  屏幕上两路画面互相盖、闪。而 `arb_handover_test.mjs` 的七条判据在同一个 elf 上连跑两遍全绿。
- 根因是**地址重叠**，不是时序竞态：ETH 落 `0x1000_0000 / 0x1008_0000`，
  PS 侧 SD 的 DMA 目的地址 `FRAME_ADDR` 也是 `0x1000_0000` ⇒ SD 每 33 ms 往 ETH 正在填/正在读的那块内存上刷 300 KB。
- 承认的错账（`:958-960`）：之前把"演示口径：一幕只按一个片源"的技术理由划掉了，
  凭据只是"并发 165 s 里 SD 读取路径零失败"——**那测的是读，不是显示**。

修法是给 PS 片源第三块 bank `0x1010_0000`，两边一起改（差一边就是"屏上不动"）：
RTL 侧 `pl_video_top` 新参数 `PS_BASE_ADDR` 只给 `u_aw`
（`src/rtl/top/pl_video_top.v:693`、`:698`），固件侧 `src/ps/sd_play.c:35` 与 `src/ps/main.c:46`
的 `FRAME_ADDR` 同步（现值见 1.2）。

**最该迁走的一条是判据本身。** `开发台账` 记的是一次自我欺骗：
现成的 `src/host/ddr_verify.mjs` 在读之前 `catch {rst -processor}`（为了躲 D-Cache 旧数据，
本身没错），但那一下恰好把要观察的写入者停掉了，之后 PL 每 66 ms 又把 bank 刷干净 ⇒
**修复前的 elf 用它也报 100 % 全绿**。教训一句话：
**会先把被测者停下来的检查器，看不见只有被测者活着才存在的竞态。**
新探针 `board/ddr_churn_probe.mjs` 的差别就是它**不停核、边跑边采**
（文件头 `board/ddr_churn_probe.mjs:5-9`），三个采样点正是那三块 bank
（`board/ddr_churn_probe.mjs:21`：`0x10000040 / 0x10080040 / 0x10100040`），
判据是 `wordid` 自描述图案：ETH bank 里每个 32 bit 字都应等于 `(word>>1)` 复制两遍，
不符合 ⇒ 这一刻这块 bank 装的是别的内容（`board/ddr_churn_probe.mjs:12-14`）。

红绿对照是**同一块 bit 上只换 elf**（`夜轮记录` 的表）：

| | ETH bank0 | ETH bank1 | PS bank |
| --- | --- | --- | --- |
| 修复前 `c00b6553` | 22 个不同值，只有 12/60 是推流内容 | 60/60 干净、静止 | 静止（旧版不写它） |
| 修复后 `dcdce9b9` | 60/60 干净、静止 | 60/60 干净、静止 | 32 个不同值 = SD 帧在翻动 |

"60 次里 48 次 ETH 的 bank0 装的不是 ETH 的画面"是屏幕上那一下闪的机理；
而"只有 bank0 被抢、bank1 没事"正好是根因的预言——**PS 只有一个 `FRAME_ADDR`**
（`开发台账`）。预言与观测对上，才叫把推断升级成量到的事实。
那份原始凭据件 `board/ddr_churn_r33_pair.md` 已不在这棵树上（`ls board/` 只剩探针脚本），
所以这里的表是从台账抄的，抄件位置是 `开发台账` 与
`夜轮记录`；**要重跑就用 `board/ddr_churn_probe.mjs`**，
它不需要重建，但需要一块在跑的板。

### 6.4 mux 的物理位置与"零新增跨域"的观测

搬运机的所有权落到具体线上是 8 行 mux（`src/rtl/top/pl_video_top.v:709-718`）：
AR 五根 + `rready` + 帧缓存写三口。反方向的 ready/valid/data
也各自带一个 `eth_mode ?` 门（`:465`、`:467`、`:703`、`:705`），
即输的那一刻另一侧被关在门外，不会同时有两个 master。

仲裁的可观测口 `dbg_src`（`src/rtl/top/pl_video_top.v:603`）把判决的所有输入摆出来：
`bit0=eth_tb_ok bit1=eth_live bit2=owner_eth bit3=fill_busy bit4=row_busy bit[6:5]=模式 bit[10:8]=why_ps`
（位图正本在 `src/rtl/top/pl_video_top.v:66-67`）。注释给的理由很硬：
只凭 `owner_eth` 回答不了"是谁占着"（时基判错？判据算错？`both_idle` 没成立？还是长按钉住了模式？），
`#28` 第一次上板就撞上这个。另有两条纪律也写在同一处：
**这些位全部本来就在 axi 域 ⇒ 零新增跨域**（`:600-601`，`#26` 那版新加一对像素域 mode 同步器
是白交税，`cdc.rpt` 从 3 端点/0 unsafe 涨到 8/4）；
**新位只往上加**，因为 `lane30` 的老读者按位 0..6 解析，改低 8 位会让它们的判据静默失效（`:602`）。

`#53` 之后仍然留在"只能看屏幕"那一格：并发时不闪。
`开发台账` 明写这条本质上无法用寄存器代替。
**把"机器侧闭环"与"只剩眼睛"分开登记**，是这个仓库交付账本的一个稳定形状。

---

## 7. 三个域之间到底跨了几次

### 7.1 谁和谁被声明成异步

`src/constraints/clock_groups_impl.xdc:28-31` 声明三组互异步：

```
-group [get_clocks eth_rxc]                          125 MHz，PHY 恢复出来的收包时钟
-group [get_clocks -quiet clk_fpga_0]               100 MHz，PS FCLK0，全部 AXI 事务
-group [get_clocks -include_generated_clocks sys_clk]  50/250/200 MHz，含 MMCM 全部生成钟
```

第三组的 `-include_generated_clocks` 不是风格：少了它，`clkout0_1`（像素 50M）会被当成
独立时钟去和 `eth_rxc` 做 setup 分析，历史上是 WNS ≈ −6.7 的假违例
（`src/constraints/clock_groups_impl.xdc:14-17`，对应 `issues.md #18`）。
而 `clk_pix` 与 `clk_pix5x` **有意留在同一组内**（同 MMCM、5:1、0° 相位），
让 TMDS 并串转换按同步路径做 setup 分析——声明成异步反而会漏检（`:25-26`）。

同一文件 `:19-23` 用四行列出"跨域数据由结构保证，不靠时序分析"：

| 跨域 | 结构 | 代码 |
| --- | --- | --- |
| `eth_rxc → clk_fpga_0` 视频流 | 格雷码 + 2FF，BRAM | `src/rtl/eth/dc_fifo.v:45-95` |
| `eth_rxc → clk_fpga_0` 帧事件 | 翻转 + 3FF 边沿检测 | `src/rtl/eth/ddr_bank_commit.v:36-47` |
| `clk_pix → clk_fpga_0` 消隐窗 | 3 级像素 + 3FF | `src/rtl/video/frame_commit_lock.v:45-76` |
| `clk_fpga_0 → clk_pix` 控制字 | 3FF | `src/rtl/top/pl_video_top.v:471-522`、`src/rtl/process/effect_ctrl.v:29-39` |

`build/cdc.rpt` 的读数正好是这四行的"另一半"——工具看到的配对与端点数（列名照 `:15`）：

| 行 | 源 → 目的 | 端点 | Safe | Unsafe | Unknown | 无 ASYNC_REG |
| --- | --- | --- | --- | --- | --- | --- |
| `:17` Critical | `clk_fpga_0 → clkout0_1` | 103 | 102 | **1** | 0 | 2 |
| `:18` Critical | `sys_clk → eth_rxc` | 1968 | 1436 | 2 | 530 | 0 |
| `:20` Warning | `eth_rxc → clk_fpga_0` | 271 | 271 | 0 | 0 | 0 |
| `:23` Info | `eth_rxc → clkout0_1` | 1 | 1 | 0 | 0 | 0 |
| `:24-25` Info | `sys_clk ↔ clkout0_1`（Safely Timed） | 231 / 19 | — | 0 | 0 | 0 |

`eth_rxc → clkout0_1` 只有 1 个端点、`clk_fpga_0 → clkout0_1` 103 个，这两行的**数量级差**
说明像素域与 Eth 域之间几乎不直接跨（都经 AXI 域中转），这与第 6.1 节
`eth_live / eth_tb_ok / owner_eth` 都先落在 axi 域、再由 axi→pix 3FF 的接法一致
（`src/rtl/top/pl_video_top.v:502-522`）。

### 7.2 格雷码指针：`dc_fifo` 的四条形状约束

`src/rtl/eth/dc_fifo.v:35-47` 是写侧的满判据：

- 二进制指针**永不跨域**，跨域的只有格雷码版本（`:81-95`，各在**对方**时钟域打两拍）。
- `full` 用"对端格雷码的最高两位取反、其余相等"判（`:47`），省掉一次二进制比较。
- `#105` 的第二刀把这条从"下一个写指针 `wgray_n`"改成"**当前**写指针 `wgray`"，
  与读侧 `rd_empty = (rgray == wgray_s1)`（`:68`）对称。
  原因是一条最差路径：原式把 14 位加法 + 二进制转格雷 + 比较整条锥体挂在 `wr_en → ENARDEN` 上
  （r87 最差路径 8 级逻辑、0.152 ns，`build/r87_timing_summary.rpt`），改完锥体只剩比较
  （`:40-44`）。副作用是"满判据提前一格"的毛病一起没了：可用深度从 `DEPTH−1` 变成 `DEPTH`，
  由 `sim/tb_cdc_capacity` 的 C1 钉住（改前 8191、改后 8192）。
  `#140` 的顺带读数（`开发台账`）在真实收包链上量到同一件事：
  r85 那天 CDC 峰值 8191/8192，改完 `wr_full` 之后是 8192/8192。
- `#105` 的**第一刀被实测判负**：给 `wr_full` 加 `max_fanout=12` 想让综合复制本地缓冲，
  结果 WNS 从 r81 的 −0.062 掉到 −0.192、失败端点 28 → 34
  （`src/rtl/eth/dc_fifo.v:37-39`）。⚠ 注释点名的凭据 `build/r83_gates.txt` 已不在盘上
  （`ls build/ | grep r83` 命中为空，r81/r83 那两版的 timing 报告被后续构建原地覆盖），
  所以这两个数在本章只是**已登记的读数**，无法复量；要复跑得重做那一刀的隔离构建。
  刀已回滚，结论保留：**扇出不是这一族的瓶颈**。

四颗同步寄存器一起打 `ASYNC_REG`（`src/rtl/eth/dc_fifo.v:22-27`）的理由也写了：
不打属性工具可以挪位、复制、把它们拆到不同区域，亚稳态传播窗口就没保证
（`report_methodology` 的 TIMING-10 就是冲这个来的；今天那份报告里这一类还剩 1 条，
`build/methodology.rpt:35`、`:2238-2241`）。`s1` 与 `s0` 按扫描器定义不算"跨域捕获"，
但官方口径是让整条链待在一起，所以四颗一起标。

### 7.3 两条 `report_cdc` 抓不到的跨域

**第一条：10 ns 脉冲跨到同相的 50 MHz 域。**
`src/rtl/video/frame_commit_lock.v:100-109`：`copy_abort` 是 `axi_clk` 上只有 1 拍（10 ns）的脉冲，
消费者 `eth_has_frame` 在 50 MHz 像素域，两路时钟同源同相（MMCM 出来的 100/50 MHz），
于是翻转沿**正好压在**像素域的采样沿上。那句关键结论：
**电平型 3 级同步在这里并不能修好它（实测与裸采逐相位一模一样）**；
正确形式是翻转式脉冲同步器，与本文件像素域→axi 那一侧的 `blank_tog` 完全对称。
证据是台架相位扫描 `sim/tb_v79_abort_toggle.v`：**错开 4 ns 时裸采 0/3、翻转式 3/3**。
而这条**不会体现在 `report_cdc` 里**——那份报告只有"时钟对 + 端点数"的粒度，不点名信号
（`src/rtl/video/frame_commit_lock.v:104-105`：build#17 与 #18 的 `cdc.rpt` 逐行相同）。
顶层那句"⚠ `copy_abort` **不能**照这个模板同步"（`src/rtl/top/pl_video_top.v:482-483`）
是同一条纪律的第二处落点。

**第二条：组合或树跨域。** `link_active` 原来是 16 位收包计数的**组合或缩**，
却被像素域那三级 `ASYNC_REG` 链的第一拍直接采走（`el0`，
`src/rtl/top/pl_video_top.v:491-496`）。计数器进位的那几拍或树会出毛刺，采进去就是一次假的"链路掉"
（`src/rtl/eth/eth_udp_video_top.v:373-378`，`#209` / CDC-10）。
改法是寄存一拍（`:381-386`）。注意注释里那句
**"判据是结构判据，台架判不了这一条：RTL 仿真没有门延迟，`|s_pkts` 在仿真里永不出毛刺"** ——
这条改动能有的全部凭据是 `build/r98_cdc_details.txt` 里那一行 CDC-10 端点，
以及"改后必须看不见 `eth_rxc>clkout0_1` 这条 Critical 行"。对照今天的 `build/cdc.rpt:23`：
`eth_rxc → clkout0_1` 剩 1 个端点、Unsafe 0。

**第三条（口径而非形态）：U11 那次同步只算行级证据。**
`src/rtl/top/pl_video_top.v:478-481`：`eth_link` 原来是 `eth_rxc` 域电平被像素域**裸采样** 4 处，
而同文件 `src_sel` 早就走 3 级同步——一处对一处错。统一成 3 级（多 60 ns，对毫秒级的"链路断"不可见）。
但注释紧接着限定：**`cdc.rpt` 里那一行端点数 84→51、被标记 16→1，
而这份报告不点名信号 ⇒ 它只能证明"这一类端点变少了"，逐信号的凭据要另写台架。**
这三条连起来就是本章 CDC 部分的结论：**`report_cdc` 是分类器，不是裁判；
凡"这条改动只被 CDC 报告支持"的声明，都要看它点不点得到名。**

---

## 8. 把整条链按一拍一拍念一遍

以下时序全部来自上面的行号，单位是各自域的周期。

**入包到提交（`eth_rxc` 8 ns → `clk_fpga_0` 10 ns）**

1. `frame_reasm` 每两个字节出一个 16 bit 写（`src/rtl/eth/frame_reasm.v:140-168`），
   并且只在 `off < FRAME_BYTES` 时把 `wr_en` 打开（`:152`，`#201` 补的边界：
   原来这三行是无条件的，发包方选的偏移能把字写到帧缓存**之外**，
   而下游 `axi_frame_saver64` 自己没有上界检查；尺子 `sim/tb_reasm_bounds.v` 的 R1，
   改前红凭据 `build/r98_201_before.txt`：越界包发了 2 次写、最大字索引 145 > 128）。
2. 写口与 flush 压进同一条 36 bit 队列（`src/rtl/eth/eth_udp_video_top.v:263-265`），
   进 `dc_fifo`（BRAM 8192 深，`:295-305`）。
3. axi 侧一级 `fifo_rd`、二级 `cdc_d1_v`、三级 `sav_en/sav_flush`
   （`src/rtl/eth/eth_udp_video_top.v:307-322`）。
4. 打包器拼成 64 bit 字，`AWLEN=0`，在途最多 8（`src/rtl/eth/axi_frame_saver64.v:65-74`）。
5. `frame_done` 翻位 → 3 拍 → `switch_req/force_flush`（`src/rtl/eth/ddr_bank_commit.v:36-66`）；
   等 `saver_idle && tail_drained` 才提交（`:49-51`、`:67-73`），出一拍 `commit_pulse` 与 `completed_base`。

**提交到上屏（`clk_fpga_0` 10 ns 与 `clk_pix` 20 ns）**

6. `commit_pulse` 在顶层就是 `eth_commit`（`src/rtl/top/system_top.v:192`、`:312`），
   进 `frame_commit_lock` 的 `commit_req`（`src/rtl/top/pl_video_top.v:432`）；
   那里只做一件事：把它锁进 `pending`，等 `allow_rise || vsync_req` 那一拍发 `start_copy`
   并把 `copy_base` 交出去（`src/rtl/video/frame_commit_lock.v:35-43`、`:111-124`）。
7. `u_row` 在 `enable(eth_mode)` 下起 2400 个突发，最多 4 个在途，
   只有 `allow_wr` 那几拍落 BRAM（`src/rtl/axi/axi_frame_writer_gated.v:79-89`、
   `src/rtl/top/pl_video_top.v:454-469`）。
8. `done` 那一拍过 `ready_tog` → 3 拍 → 异或回像素域，`eth_has_frame <= 1`
   （`src/rtl/video/frame_commit_lock.v:126-145`、`src/rtl/top/pl_video_top.v:524-533`）。
9. 时延被三段量出来：`u_lat` 吃 `commit / copy_start / copy_done / disp_sof_tgl`
   （`src/rtl/top/pl_video_top.v:624-629`），`c1` = 等消隐、`c2` = 搬运、`tot` = 提交→上屏，
   单位是 axi 拍数不是时间；像素域的 `frame_start` 必须先翻位再进 axi 域
   （`src/rtl/top/pl_video_top.v:606-611`：脉冲跨域会被吃掉，`#36` 那一课）。
   换算成时间戳在 `src/host/health_read.mjs` 里做（1 拍 = 10 ns），
   **PL 里不做除法**：r49 在这里把拍数除以 100，除数不是 2 的幂 ⇒ 综合架出组合除法器，
   100 MHz 域直接 WNS −5.014 / 96 个失败端点（`src/rtl/top/pl_video_top.v:621-623`，`#58`）。

这条链上有两处"看起来在优化、其实是把成本搬到别处"的写法值得单独记住：
一是**第 8 步的除法**（时间换算挪到上位机），二是**第 3.3 节的存储结构**（寄存器挪到 LUTRAM，
代价从资源变成余量）。两者都留了数字，所以后人才不必再花一次构建批去发现。

---

## 9. 量过并拒绝的刀：这一章只列与本章对象直接相关的

| 刀 | 对象 | 实测结果 | 处置与出处 |
| --- | --- | --- | --- |
| 打包器 `FW` 从 9 降到 8 | `axi_frame_saver64` 的 512×100bit | 线速连灌下 **512/512 满** | 判"削不得"，`开发台账`；件 `build/r88_packer_peak_gap0.txt:23` |
| `wr_full` 加 `max_fanout=12` | `dc_fifo` | WNS −0.062 → **−0.192**，失败端点 28 → 34 | 回滚，`src/rtl/eth/dc_fifo.v:37-39`（`#105` 第一刀） |
| `q_addr` 退化成"基址+序号" | `axi_frame_saver64.v:110` | 帧中途换基址 ⇒ 序号对不上 | 读代码判掉，`开发台账` |
| Pblock 圈住 `u_cdc` 那 9 块 BRAM | 同上存储的控制邻居 | 全设计 WNS +0.516 → +0.363（落在实测摆幅内，按规矩 35 既不称好也不称坏），`eth_rxc` 最差族**本来就不在名单上**，LUT 14358 → 14357，失败端点 0/50885 不变 | **不采纳**，XDC 与挂载全回退；`开发台账`（`#146`），件 `build/evidence/r89exp_timing_summary.rpt` |
| 显示侧 skid 换 LUTRAM | `axi_frame_writer_gated.v:53-64` | 省 5215 个寄存器，代价 WNS −0.320 ns | **接受**，两头都记账；`变更志` |
| `u_fb` 从 LUTRAM 换回 BRAM 换 setup | 帧缓存存储结构 | RAMB36 93→88，`eth_rxc` WNS +0.516→+0.182，级数 4→9 | **否决**："在不缺资源的地方省资源、在最薄的地方削余量，这笔账是反的"，`report/40-optimization.md:114`（V2） |

第 13 章会把这张表的完整版（策略扫描、同 DCP 重滚、复制广播网 C9、τ 扫档）连件列出来。
本章只留一条与帧缓冲直接相关的结论：**搬运机那台模块的高扇出广播网
`u_pl/u_row/hi_reg_0[0]`（239 引脚、5.690 ns 布线）是 `clk_fpga_0` 最差那条路的唯一大项**
（`极限核对`、`:28-40`），而复制它的刀在 r117 被名册差分判负
（`build/r117_verdict_declined.txt`）——也就是说，帧缓存写口这条物理路径的时序问题
**没有约束侧或复制侧的解**，只剩下一次结构改动。

---

## 10. 自查清单（读完这一章应该能答）

1. 一帧 512×300 是几个字节、几块 bank、间隔多少？为什么第三块从 `+1 MB` 起而不是 `+512 KB`？
   （1.1、`src/rtl/top/system_top.v:140-144`）
2. `off[18:1]`、`wr_addr[18:2]`、`{10'd0, cur_widx, 3'b000}` 三次移位各在换什么单位？
   （1.3，`src/rtl/eth/frame_reasm.v:151`、`src/rtl/eth/axi_frame_saver64.v:88,110`）
3. 为什么把 CDC 从 512 做到 8192 没有改善吞吐，而把 `OST` 从 1 做到 8 有？
   （2.2，`src/rtl/eth/axi_frame_saver64.v:5-7`、`开发台账`）
4. 打包器三个数组如果写成"带异步复位的 always + task"会掉进什么？数字是多少？
   （3.1，`变更志`：FF 32904 / LUTRAM 0）
5. `#33` 的帧尾丢 4 字节，为什么加深 CDC 会让它更容易出现而不是更难？
   （4.2，`变更志`：`idle` 对 CDC 与两级读流水不可见）
6. 为什么 `m_axi_rready` 在 abort 期间必须继续为真？台架的响应器要满足什么条件才算不作假？
   （5.4，`src/rtl/axi/axi_frame_writer_gated.v:75-79`、`sim/tb_writer_abort.v:30-32`）
7. 仲裁为什么不能只看"有没有流"？`eth_tb_ok` 拦的是哪个板级事实？
   （6.1，`src/rtl/util/src_arb.v:11-14`，RXC 被拉到 ≈2.5 MHz）
8. `src_arb` 的判据全绿，屏上为什么还闪？"七条判据"与"打架"之间的缺口在哪个模块外？
   （6.3，`src/rtl/top/pl_video_top.v:13-16`、`开发台账`）
9. `why_ps` 与 `owner_eth` 为什么必须在同一个决定点写？`W7` 那条反配对拦的是哪种修法？
   （6.2，`src/rtl/util/src_arb.v:66-76`、`开发台账`）
10. 三组异步时钟里为什么 `clk_pix` 与 `clk_pix5x` 故意不拆开？少了
    `-include_generated_clocks` 会多出什么假违例？
    （7.1，`src/constraints/clock_groups_impl.xdc:14-17`、`:25-26`）
11. `report_cdc` 查不到的两类跨域是哪两类？各用什么尺子？
    （7.3，`src/rtl/video/frame_commit_lock.v:100-109` 的相位扫描、
    `src/rtl/eth/eth_udp_video_top.v:373-380` 的结构判据）

## 11. 未量 / 边界

- 本章所有资源与 CDC 数来自同一批（2026-10-04 04:37）已布线报告；τ=31 那一版的板侧
  裁决仍未闭合：`收口输入窗模型` 记的是带流 `drop_words=0`
  但同一份件里 `pkt_err=?` / `frames_bad=?`。
- `board/ddr_churn_r33_pair.md`、`board/ddr_churn_r33_newelf.txt` 这两份红绿对照原件
  已不在盘上（`find . -name "*ddr_churn*"` 只命中探针脚本），所以第 6.3 节那张表是从台账抄的，不是从原件读的。
- `build/r96_abort_toggle_regress.txt`（`开发台账` 点名）不在盘上；
  `sim/tb_v79_abort_toggle.v` 在，所以那条回归可复跑，但这里没有跑它，读数仍是台账里那一行。
- 打包器与 CDC 的峰值占用是**台架流量形状的下界**：两份件自己的表头就写了
  "读侧 `sv_full` 阻塞窗口未建模 ⇒ 不是设计界"（`build/r88_packer_peak_throttled.txt:1`、
  `build/r88_packer_peak_gap0.txt:21`）。引用"512/512 满"时，这句话必须一起念。
- `src/rtl/eth/axi_frame_saver.v` 与 `src/rtl/eth/axi_frame_saver_burst.v` 在源清单里被编译，
  但在 `src/rtl/` 内没有例化点（只有 `sim/tb_v5_saver.v` 引用旧那一个）；
  本章按"不在 bit 里"处理，没有为它们建任何账。

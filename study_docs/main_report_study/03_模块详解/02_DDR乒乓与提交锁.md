# 模块详解 02 · DDR 乒乓缓冲与提交锁

> 覆盖：`ddr_bank_commit` / `frame_commit_lock` / `axi_frame_writer_gated` / `axi_frame_writer64`，
> 以及 `frame_reasm` 的提交判据（第五版 v5.1 为时序重写过，一并记在这里）。
> 概念铺垫：[前置知识 03 AXI 与 Zynq 端口](../00_前置知识/03_AXI与Zynq端口.md)、
> [前置知识 04 DDR 与帧缓冲带宽](../00_前置知识/04_DDR与帧缓冲带宽.md)。

---

## 0. 一句话职责与三条不变量

**职责**：把「一帧在 DDR 里已经写好」这件事，变成一个「在显示消隐期内、把整帧原子搬进显示
BRAM」的动作，并且在搬不完的时候**宁可晚一帧也不撕裂**。

三条不变量（整个模块的设计都是为它们服务的）：

| # | 不变量 | 靠什么保证 | 破坏了会看到什么 |
|---|--------|-----------|------------------|
| I1 | 屏幕上不可能同时出现同一帧的新旧两半 | 写 BRAM 只在 `allow_wr` 为真的窗口内（`axi_frame_writer_gated.v:77,79` 两条路都要它） | 水平方向的撕裂线；v5 之前是「固定位置黑线」 |
| I2 | 换 bank 一定发生在一帧搬运完成之后 | `frame_commit_lock` 的 `pending/copy_active` 互锁（`:102-104`） | 搬一半被下一次提交打断 |
| I3 | 拷贝用的基址在整个搬运期间不变 | `base_r` 在 `start_copy` 那拍锁一次（`:108`），之后只读 | 两个 bank 的像素混在同一帧里 |

## 1. 数据通路位置

```
frame_reasm @125M ──frame_done(1拍)──┐
                                     ├─► ddr_bank_commit ──┬─► bank 翻转（下一次写入落哪个 bank）
dc_fifo ─► axi_frame_saver64 ────────┘                     ├─► completed_base（已写完的 bank 基址）
        （写 HP0 → DDR bank0/bank1）                        └─► commit_pulse(1拍 @100M)
                                                              │
                                              ┌───────────────┘
                                              ▼
                            frame_commit_lock @100M ──start_copy(1拍)──► axi_frame_writer_gated
                                    ▲   │                                        │
                       blank_safe   │   └── copy_base = completed_base           │ HP0 读 38400×64bit
                       (像素域)      └── allow_copy_axi = d1&d2 ◄── disp_quiet    ▼
                                                                        frame_buffer_w64 写口 @axi
                                                                        （读口在像素域，见模块详解 03）
```

## 2. DDR 地址映射

| 项 | 值 | 出处 |
|----|----|------|
| bank0 | `0x1000_0000` | `eth_udp_video_top.v:55`，`system_top.v:125/:161` 传入 |
| bank1 | `0x1000_0000 + 0x80000` = `0x1008_0000` | `eth_udp_video_top.v:56`；`ddr_bank_commit.v:18` 另写死一份 |
| bank 间隔 | 524288 B | 一帧只需 307200 B ⇒ 余量 71%，两 bank 不重叠 |
| 整条链占用 | 1 MiB（`0x1000_0000`–`0x1010_0000`） | |
| 入包地址 | `pack_base + cur_widx*8`，`cur_widx = wr_addr[18:2]` | `axi_frame_saver64.v:117,95` |
| 回读地址 | `base_r + burst_idx*128` | `axi_frame_writer_gated.v:124` |
| 兜底常量 | `frame_commit_lock.v:34` `pending_base<=0x1000_0000`、`:99` `copy_base<=0x10000000` | 复位值与真实基址分开 |

> 注意 `wr_addr[18:0]` 的单位是 **16bit 半字索引**（`frame_reasm.v` 里 `wr_addr<=off[18:1]`），
> 而 `frame_buffer_w64` 的 `wr_addr[18:0]` 单位是 **64bit 字索引**。
> 两者都叫 `wr_addr`、都是 19 位，单位差 4 倍。我自己在这上面踩过一次：
> 写 TB 时用字节地址喂 `wr_addr`，结果只有 1/8 的字对
> （[验证与上板 01](../05_验证与上板/01_怎样写出能抓bug的testbench.md) §4）。

## 3. 提交握手：逐拍拆开

### 3.1 `frame_done` 的跨域（125M → 100M）

```verilog
// ddr_bank_commit.v:45-49  （gmii 域）
if (frame_done) frame_done_tog <= ~frame_done_tog;      // 脉冲 → 电平翻转
// ddr_bank_commit.v:50-55  （axi 域，3FF + ASYNC_REG）
fd0<=tog; fd1<=fd0; fd2<=fd1;  fd_axi = fd1 ^ fd2;      // 边沿，宽度正好 1 个 axi 拍
```

为什么是 3 个 FF 而不是 2：翻转信号自身要跨域，取边沿需要 `fd1` 和 `fd2`，
而 `fd0` 是第一个同步级。这套「toggle + 边沿检测」是跨域传事件的两种正规做法之一
（另一种是格雷码计数器），见
[前置知识 02](../00_前置知识/02_时钟复位与CDC.md) §5。

### 3.2 什么时候才允许换页（`TAIL_GUARD` 的全部意义）

```verilog
// ddr_bank_commit.v:58-59
tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
commit_ok    = TAIL_GUARD ? (saver_idle && tail_drained) : saver_idle;
```

`saver_idle` 的定义（`axi_frame_saver64.v:93`）：
`enable && !cur_dirty && fifo_empty && !beat && outst==0` —— 它只看打包器**自己**空不空，
对**前面**那个 8192 深的 `dc_fifo` 和它后面的 3 级读流水**完全不可见**
（注释 `ddr_bank_commit.v:11-14` 就是这么写的）。

后果：帧尾最后几个字节还躺在 CDC FIFO / 读流水里，换页条件就已经成立，
于是「最后 4 字节」（= 2 个像素）落到了**换页之后**，被记到下一个 bank 的开头 ⇒
屏幕最末一行少两个像素，且这个残值会一直显示到下一帧覆盖它。
这就是第五版之前的 P03 问题。修法就是 `tail_drained`：
**把「数据已经彻底流干」这件事显式地、逐段地问一遍**。

`TAIL_GUARD=1` 是板上取值（`eth_udp_video_top.v:258-259`），`=0` 只为了 TB 里 A/B 复现旧行为
（`sim/tb_v6_tail_bank.v` 同时例化两条链，用同一份激励比对两者的差异 —— 这种
「一真一假并排跑」的 TB 写法是我觉得最值钱的套路）。

另外注意 `pack_flush = sav_flush | (force_flush && tail_drained)`（`:88`）：
flush 标记永远给真实数据让路。

### 3.3 提交给显示侧

- `completed_base` → `eth_ddr_base`（`system_top.v:120/149/181`）→ `frame_commit_lock.commit_base`
  → `pending_base` → `copy_base`（`frame_commit_lock.v:106`）→ `u_row.base_addr`
  → 拷贝机 `base_r`（`axi_frame_writer_gated.v:108`）。
- `commit_pulse` → `commit_req`，**axi → axi 同域，不需要 CDC**，打一拍存进 `pending`
  （`frame_commit_lock.v:32-40`）。
- `start_copy` 是**单拍**（`:101` 每拍先清 0，`:105` 置 1）。
- 门条件（`:103-104`）：`!copy_active && !copy_busy && !copy_done && !start_copy && !copy_abort`
  ⇒ **同一时刻只允许一帧在搬**；新提交只能排队，而 `pending` 会被下一次提交**覆盖**
  ⇒ 中间帧被跳过（〔推断〕这是有意的：显示帧率上限由 HDMI 决定，跳帧比撕裂好）。
- 完成回执：`copy_done` 翻转 `ready_tog`（`:112-116`）→ 3FF 进像素域（`:117-124`）
  → `frame_ready_pix` 是**置 1 后不清**的电平，只有 `copy_abort` 会把 `eth_has_frame` 清零。
  ⚠️ 但这条链最终只进 `status`，而 `status` 顶层没端口 ⇒ 全被裁掉（见
  [文件地图](../02_架构/03_模块与文件地图.md) §3）。

## 4. 消隐窗：唯一的裁判

### 4.1 窗口是怎么算出来的

```verilog
// pl_video_top.v:207-211
DISP_V_LINES = 600; DISP_V_LAST = 624; VB_X_GUARD = 1279;   // H_TOTAL(1344) - 65
disp_quiet = (y >= 600) && ((y < 624) || (x <= 1279));
```

| 口径 | 数值 | 来源 |
|------|------|------|
| 名义（25 行 × 1344） | 33600 pix 拍 = **67200 axi 拍** | `video_timing_1024x600.v:18-20` 算得；`pl_video_top.v:199-200` 注释、`report/PERF_REPORT.md:152` 用这个 |
| **RTL 实际放行** | 24×1344 + 1280 = 33536 pix 拍 = **67072 axi 拍** | 第 624 行只放到 x=1279 |
| 越窗判据 | `VBLANK_AXI_CYC = 67200` | `pl_video_top.v:248` |

⇒ 判据比它监控的窗口**松 128 拍**。〔推断〕最后一行留 65 个像素的保护带，是为了让
「窗口关闭」这个事件本身在被同步到 axi 域之后仍然落在消隐期内（同步链有 2~3 拍延迟），
但代码注释没写清，所以只能算推断。

传播延迟：`disp_quiet → blank_safe`（`pl_video_top.v:236`）→ 像素域 3 级
`bs_d0/1/2`（`frame_commit_lock.v:43-54`）→ axi 域 3FF（`:68-72`，`ASYNC_REG`）→
`allow_copy_axi = d1 & d2`（`:73`）。设计自己的口径是「lag ~5 pix cycles through the CDC」
（`pl_video_top.v:205-206` 注释）。

### 4.2 搬不完会发生什么（四条，逐条给代码）

1. **绝不会写进有效期**：直写与 skid 排空两条路都要 `allow_wr`
   （`axi_frame_writer_gated.v:77,79`），发新 AR 也要（`:71-74`）⇒ 窗口一关立刻停，
   屏幕继续显示上一整帧。
2. **不丢数**：`m_axi_rready = active && !sk_full`（`:69`）—— `allow_wr` 掉了也继续收 R，
   直到 63 深 skid 满，然后 rready 拉低、`can_issue` 关门 ⇒ 拷贝**平摊到后续若干个消隐窗**。
3. **越窗会被点亮**：`pl_video_top.v:250-254`，`row_done && row_copy_cycles > 67200`
   ⇒ `copy_overrun<=1`（**粘滞**，只有 `axi_rst_n` 能清）→ `led[0]` 从 1.5 Hz 心跳变 6 Hz 快闪
   （`:516-517`）。这是**不看屏幕也能知道有没有撕裂风险**的板级判据。
4. **硬兜底是看门狗**：`WD_CYC = 2_000_000` axi 拍 ≈ 20 ms ≈ 1.19 个显示帧
   （`frame_commit_lock.v:8`，从未被覆盖）→ `copy_abort` 单拍（`:92`）：
   - 进拷贝机：清 `active/busy/m_arvalid/outstanding/sk_w/sk_r/r_pix/wr_words`，
     `done` 永远不发（`axi_frame_writer_gated.v:118-121`）；
   - 进提交锁：`if (copy_done || copy_abort) copy_active <= 0;`（`:102`）⇒ 允许下一次启动；
   - 进显示侧：`eth_has_frame <= 0`（`pl_video_top.v:283`，**未同步采样**，见
     [时钟与复位](../02_架构/02_时钟与复位树.md) §2）。

### 4.3 实测搬运开销（`tb_v6_vblank_copy`，生产几何 + 限速 slave）

| slave 给 HP0 的让步率 | copy_cycles | 结论 |
|----------------------|-------------|------|
| 10/10（800 MB/s） | **38441** | 一个消隐窗内完成（预算 67200） |
| 7/10（560 MB/s） | 54894 | 同上 |
| 6/10（480 MB/s） | **64036** | 贴着预算 |
| 4/10（320 MB/s） | **1708873** | 溢出到后续多个消隐窗；**不写有效行、不重复、不越界、看门狗不误杀** |

数据出处 `report/V6_ROOT_CAUSE.md:69-73`；板级 `copy_cycles ≤ 67200`、
`copy_overrun` 从未置起、`led[0]` 保持 1.5 Hz（`report/PERF_REPORT.md:154-156`）。
最后一行是关键：**慢到极限时行为退化为「分摊到多个消隐期」，而不是「撕裂」**。
这就是 I1 的价值。

### 4.4 另一条启动触发

`vsync_req`（`frame_commit_lock.v:56-66`）与 `allow_rise`（`:78-83`）并联作为 start 条件。
注释 `:75-77` 解释为什么需要 `allow_rise`：1024×600 的 V_FP=3 + V_SYNC=6 使 vsync
要到窗口开始 9 行之后才上升，白扔三分之一预算；`vsync_req` 保留只为兼容旧 TB。

## 5. 回读机 `axi_frame_writer_gated` 的参数账

| 参数 | 值 | 出处 / 为什么 |
|------|----|--------------|
| 端口 | **HP0**（不是 GP0） | `system_top.v:78-93` 只连了 `M_AXI_HP0_*` |
| AXI 版本 | AXI3 ⇒ `arlen/awlen` 只有 `[3:0]` | `design_1_wrapper.v:104,115` ⇒ **单突发上限 16 拍**，这就是 `BEATS=16` 的来源 |
| 位宽 | 64 bit | `system_top.v:51/62` |
| `arsize` / `arburst` | `3'b011`（8 B/拍=全宽） / `2'b01`（INCR） | `:36-37` |
| `arlen` | 15（16 拍） | `:112,125` |
| 突发数 | `TOTAL_BURSTS = ceil(38400/16) = 2400` | `:43` |
| 在途 | `MAX_OUT=4` 个突发 = 64 拍 | `:46`，注释说明目的是盖住 HP0/DDR 读延迟、在窗口内维持 ~1 拍/周期 |
| skid | `SK=6` ⇒ 64 项，但 `sk_full` 在 `level>=63` ⇒ **有效深度 63**；`can_issue` 另要求 `level<=47`（留 16 拍整包） | `:57,74` |
| skid 实现 | `(* ram_style="distributed" *)`，**异步读**，数组写单独一个无复位块 | `:51-53,59-63,84-89`，注释记录动机：原写法触发 `Synth 8-4767`，64×83 bit 全掉进触发器 |
| `done` 条件 | `wr_words >= TOTAL_WORDS && sk_empty && !arvalid && outstanding==0 && !sk_drain && !fb_wr_en` | `:157-158` ⇒ **每个字都真写进 BRAM 之后**才算完成 |
| 像素↔字 | `r_pix` 每拍 +4；出 BRAM 地址 `fb_wr_addr <= r_pix[18:2]`；skid 里存完整像素号 | `:39,145,86,134` |
| `araddr` 裁剪 | `m_axi_araddr <= base_r + burst_idx*(BEATS*8)` | `:124` |

**两台读机器共用一个 AR/R**：`pl_video_top.v:340-345` 用 `eth_mode ? row_xxx : fill_xxx` 逐个 mux，
`arready/rvalid` 也按模式反过来给门（`:267-268,334-335`）。
〔推断〕模式位在握手中途翻转会把 `arready`/`rvalid` 凭空掐掉；
`eth_mode` 来自 `eth_link`（= `|stat_pkts`，`eth_udp_video_top.v:301`）的 3FF 同步，
只有断流时才可能翻转，所以实际不会撞上。

## 6. 第五版 v5.1：`frame_reasm` 的时序改写

这一节是**唯一一次纯粹为了时序去改功能正确的代码**，值得完整记下来。

### 6.1 症状

`build/timing_summary.rpt` 里 `eth_rxc`（125 MHz）WNS = **+0.499 ns**，
而且**最差的 10 条路径全部同构**：

```
Source:      u_eth/u_udp/u_udp_rx/rec_en_reg/C
Dest:        u_eth/u_reasm/rows_hit_reg[0]/CE
Data Path:   7.159 ns（logic 2.314 / route 4.845）
Logic Levels:11（CARRY4=6 LUT2=1 LUT3=2 LUT6=2）
关键网线：   u_eth/u_reasm/udp_rec_en  fo=50  route = 1.947 ns
起点 SLICE_X79Y41 → 终点 SLICE_X20Y22（横向 59 个列）
```

拆一下这 11 级是什么：v5.0 的提交判据在每个 EOF 周期要算

```verilog
bytes_all = cover + pkt_pay + (p_valid ? 1 : 0);   // 32bit 三操作数加
if (rows_hit >= IMG_H && bytes_all >= FRAME_BYTES) ...
```

也就是「一个 24 bit 进位链（6 个 CARRY4）+ 一个常量比较」，
而它的**第一个输入 `p_valid` 来自 59 列之外**，光是那根网线就吃掉 1.947 ns。

### 6.2 为什么不能简单「加一级流水」

因为 `p_valid && p_eof` 是**同一拍**发生的，判据必须在这一拍出结果；
把加法打一拍会让 `pkt_pay` 少算最后一个字节（v5.0 注释里明确说这个 off-by-one
会让最后一个包永远被拒）。所以只能**改变量的组织方式**，不能加流水。

### 6.3 改法：把「求和 + 比较」换成「饱和累加 + 等值比较」

```verilog
localparam integer CW    = $clog2(FRAME_BYTES + 1);   // 19
localparam [CW-1:0] SAT  = FRAME_BYTES;               // 307200
localparam [CW-1:0] SAT1 = FRAME_BYTES - 1;

reg [CW-1:0] cov;    // 本帧已收到的载荷字节（含当前包），到 SAT 就饱和
reg [CW-1:0] pend;   // 当前包的包内字节 + 包起始偏移，同样饱和

wire bytes_ok = cov_sat  | (cov_end  & p_valid);      // 「+1 之后是否达到帧长」
wire last_pkt = pend_sat | (pend_end & p_valid);
```

为什么这是**等价**的（这一步必须能在答辩里讲清楚）：

1. `cov` 的旧语义是「已完成包累计」，新语义是「旧 cover + 当前包 pkt_pay」，
   也就是旧代码里每次都现场算的那个大和 —— 只是提前一拍算好了。
2. 单调递增 ⇒ `>= FRAME_BYTES` 与 `== FRAME_BYTES` 是同一个问题，所以饱和不丢信息。
3. 两个计数器都在**帧起点**（`hdr < 4`）和**提交**时清零，不会把饱和值传给下一帧。
4. EOF 那一拍的最后一个字节仍然要额外记一笔（`if (p_valid) cov <= cov + 1;`），
   而且因为 Verilog 的「后赋值有效」，它与 S_DATA 分支的自增不会重复计数 ——
   这跟 v5.0 的 `cover <= cover + pkt_pay + p_valid` 是同一个数值。

关键收益：`p_valid` 现在只需要到达**一个 LUT 的一个输入脚**，
它后面的 6 级进位链与常量比较全部消失了。

### 6.4 一处必须诚实记录的语义差异

v5.0 靠「坏包的字节不计入 cover」来让含坏包的帧无法提交；
饱和累加的计数器**没法把已经计进去的字节退回来**。所以新增一个粘滞位：

```verilog
if (p_eof && pkt_active && !p_good) bad_frame <= 1;   // 作废本帧
...
if (rows_hit >= IMG_H[15:0] && bytes_ok && !bad_frame) begin  // 提交判据
```

差异只有一种情况能触发：**零载荷的坏包**（UDP 只有 4 字节头）。
v5.0 会允许该帧提交（字节数没受影响），v5.1 会拒绝。
新规则还更严格地覆盖了「坏包 + 后续重传同一批字节」这种本工程的协议里不存在的场景。
〔结论〕判决集合只可能变小、不可能变大 ⇒ 不会出现「以前不提交、现在提交了」这种危险方向。

### 6.5 附带发现

- **`cover` 这个名字是 SystemVerilog 保留字**（`cover` = 覆盖组/断言），
  任何文件一旦以 `-sv` 编译就会报 `VRFC 10-8549`。工程原来能编是因为回归脚本用
  纯 Verilog 模式。改名 `cov` 才彻底安全。
- 改之前必须先确认**没有 TB 用层次名引用过 `cover/bytes_all/last_pkt`**
  （`grep` 过 `sim/`：只有 `stat_*` 端口被引用），否则重写会静默让 TB 编不过或测错对象。

### 6.6 验证与结果

| 层 | 内容 | 结果 |
|----|------|------|
| L1 | `tb_v6_cover_gate`（提交判据专职 TB） | 6/6 PASS（含「丢包帧被拒」「坏帧只计一次」「下一完整帧恢复」） |
| L1 | 全量回归 30 个 TB | **30/30 PASS**（`sim/r06_regression.log`） |
| L3 | 重新综合 + 实现 | 见 `report/OVERNIGHT_LOG.md` 最新一轮（WNS/BRAM/Util/功耗/方法学/CDC 全门禁） |

## 7. 与上一版（v6.4）的对照：改了哪些文件

| 文件 | 改动 | 为什么 |
|------|------|--------|
| `ddr_bank_commit.v` | **新增**（从 `eth_udp_video_top` 抽出） | 让 TB 能例化**上板实现**而不是手抄一份副本 |
| `ddr_bank_commit.v` | `TAIL_GUARD` + `tail_drained` | 修帧尾 4 字节 |
| `axi_frame_saver64.v` | 打包 FIFO 改 LUTRAM（数组写独占无复位块） | 释放 ~5 万个 FDRE |
| `axi_frame_writer_gated.v` | skid 改 LUTRAM + 两处写点合并成 `do_skid` | 同上（`Synth 8-4767`） |
| `frame_buffer_w64.v` | 38400 单阵列 → 32768+8192 | BRAM 从 98.93% 降到 64.64% |
| `frame_reasm.v` | v5.1 饱和累加 + `bad_frame` | `eth_rxc` WNS +0.499 |
| `rk_zynq7020.xdc` | 删空约束 `set_false_path -from eth_rst_n` | 每次综合 1 条 `Constraints 18-513` |

完整判据与数字见 [版本演进 02](../04_版本演进/02_问题与修复全记录.md)。

## 8. 自测

1. `saver_idle` 为什么不足以作为换页条件？它漏看了哪几级缓冲？
2. 消隐窗的三种口径（名义 / RTL 实际 / 判据）分别是多少？差在哪几拍？为什么这样取？
3. 拷贝机 `done` 的判据里有 6 个与条件，缺一个会分别出什么问题？
4. 为什么 `allow_wr` 掉了之后 `m_axi_rready` 还要保持有效？如果立刻关掉 rready 会怎样？
5. v5.1 的 `bytes_ok` 为什么和 v5.0 的 `bytes_all >= FRAME_BYTES` 等价？
   给出「单调递增」这个前提在代码里由哪三行保证。
6. 如果 `TAIL_GUARD` 退回 0，`tb_v6_tail_bank` 的两条并排链会给出什么不同的输出？
   这个 TB 为什么必须两边都跑？

# 变更记录 · 第五版 V7.x（资源死结与帧尾残留）

本文是**第五版相对第四版的完整优化对比**：每一条改了什么、当时看到什么证据、
判据是什么、数字前后差多少、哪条被否决。原始工程流水（含每轮命令、报告门禁逐条、
被推翻的假设）在 `report/OVERNIGHT_LOG.md`；本文是给它整理的对外版本。
第四版及更早的逐版记录见 `report/CHANGELOG_V6.md` 与 `report/VERSION_LINEAGE.md`。

约定：所有资源/时序数字来自同一份可复现构建
（`vivado -mode batch -source build/tcl/build_system_axigpio.tcl`，器件 `xc7z020clg484-2`）；
板级数字来自同一块板、同一判据（`--test frameid` 推流 → 停止 → JTAG 回读两个 DDR bank →
逐 16bit 反解帧号）。工具 Vivado/Vitis 2025.2.1。

---

## 0. 起点：第四版的功能已经对了，但器件没有余量

| 项 | 第四版（`647160e` 复现构建） | 门禁要求 | 判定 |
|----|------------------------------|----------|------|
| WNS / WHS | +0.708 / +0.064 ns，0 失败端点，全约束满足 | ≥0 | 合格 |
| Block RAM Tile | **138.5 / 140 = 98.93%** | ≤97%（目标 ≤95%） | **不合格** |
| Slice | **13290 / 13300 = 99.92%** | ≤98% | **不合格** |
| Slice Registers | 54588 = **51.30%** | — | 异常偏高 |
| Slice LUTs | 19825 = 37.27% | — | — |
| Total Power | 2.525 W（Dynamic 2.338，Tj 54.1 °C） | 不明显恶化 | 基线 |
| route | 64604 可布线网表全通，0 错误 | Failed Nets = 0 | 合格 |
| methodology / cdc | 170 条检查全为 Warning；CDC 4 条既有 Critical 行 | 无新增 Critical | 合格 |

结论：功能层面无可挑剔，但**三项占用贴着上限**，任何新增（插值行缓存、更深缓冲、双缓冲）都塞不下。
第五版因此不动功能，先查"为什么这些资源是被谁占掉的"。

---

## V7.0（R02）—— 入包打包 FIFO 从触发器改为分布式 RAM

**证据链**：整机 54588 个寄存器里约 5.1 万个来自 `axi_frame_saver64` 的一个 512×100bit 存储
（`q_addr` 32b + `q_data` 64b + `q_keep` 4b × 512）。原注释写死"不可加深：FW=11 直接 DRC UTLZ-1"。
同一时刻器件的分布式 RAM 只用了 1.75%（305/17400）。

**尝试与失败**：只加 `(* ram_style = "distributed" *)` **无效**——综合报
`WARNING [Synth 8-7186] Applying attribute ram_style = "distributed" is ignored,
object 'q_addr[N]' is not inferred as ram due to incorrect usage`。

**定位方式**：不靠猜，写最小对照实验（`sim/probes/ramtest.v` + `probe.tcl`，
5 个变体逐个 `synth_design -mode out_of_context` 后统计单元类型）：

| 变体 | 写法 | FF | LUTRAM | BRAM |
|------|------|----|--------|------|
| v1 | 写在带异步复位的控制块里、经 `task` 调用（= 原 RTL 形状） | **32904** | 0 | 0 |
| v2 | **数组写独占一个无复位 always 块**，`full` 折进写使能 | **85** | **864** | 0 |
| v3 | 同 v2 但不加 `ram_style` | 22 | 1 | **1** |
| v4 | 二维数组按字节拆 | 32911 | 0 | 0 |
| v5 | 同 v2，属性写成 `/* synthesis ram_style=... */` 注释式 | 85 | 864 | 0 |

**结论**：阻碍推断的是"数组写与异步复位控制逻辑同处一个 always 块 + task 封装"，不是读口形状；
v3 说明不加属性时综合器会把它塞进 BRAM——而 BRAM 只剩 1.5 个 tile，所以必须显式写 `distributed`。
本仓库 `dc_fifo.v:46-49` 早就用的是正确写法，`axi_frame_saver64` 是入包链里唯一没跟上的模块。

**改动**：删 `push_word` task；两个调用点合并成一个写脉冲
`push_now = enable && ((wr_en && idx_chg) || (flush && cur_dirty && !wr_en))`（与原 `if/else-if`
优先级逐条件等价）；数组写独占 `always @(posedge clk)`；读口改异步。
**满时丢字、flush 仍清 `cur_dirty` 的既有语义故意按 bug-for-bug 保留**，不与 V7.2 混在一个改动里。

| 项 | V6.4 | V7.0 |
|----|------|------|
| Slice Registers | 54588 (51.30%) | **9593 (9.02%)** |
| Slice LUTs | 19825 (37.27%) | **7858 (14.77%)** |
| Slice | 99.92% | **34.99%** |
| Total Power | 2.525 W | 2.412 W |
| WNS | +0.708 | +0.677（全约束满足） |
| 回归 | 28/28 | 28/28 |

"FW 不可加深"的禁令从此解除（深度不再受 FDRE 上限约束）——这是 V7.1 与后续功能的前提。

---

## V7.2（R03）—— 帧尾 4 字节偶发丢失：判据看不见 CDC

**现象**（第四版遗留、`report/ISSUES.md` 与 `V6_BOARD_MEASUREMENT.md:65` 记录在案）：
512×300 帧最后一个 64bit 字（DDR `+0x4AFF8`）高半 32bit 偶发读回 0，板上 8 次见 4 次，与速率无关，
既有 `tb_v6_ingress_integrity +FULL` 复现不出来。

**根因**：换页判据 `switch_req && saver_idle` 里的 `idle` 只描述打包器自身
（`!cur_dirty && fifo_empty && !beat && outst==0`），对 **8192 深的 CDC 与它后面两级读流水完全不可见**。
打包器满过一次之后，若 `sv_full` 恰好在帧的最后一个字中间放开，本帧最后 2 个 lane 还排在 CDC 里；
此时 `frame_done` 已同步到 axi 域并拉起 `force_flush`，把已到达的半截字推走 ⇒ 打包器排空 ⇒
`saver_idle` ⇒ 翻 bank。随后那 2 个 lane 进打包器时 `pack_base` 已经换 bank ⇒
写进**下一帧**的缓冲区，刚提交的 bank 帧尾停在旧值/0。相位相关 ⇒ 4/8 次、与速率无关。

**工程化前置（比补丁更重要）**：这段 glue 原先内联在 `eth_udp_video_top.v`，
`tb_v6_pingpong` / `tb_v5_bank` 各**手抄一份**来测——手抄的副本不会因为真代码改错而变红。
故抽成独立模块 `src/rtl/eth/ddr_bank_commit.v`（逐行搬迁，逻辑不变），TB 改为**例化上板的实现**：

```verilog
tail_drained = cdc_empty && !cdc_rd && !cdc_d1_v && !sav_en && !sav_flush;
commit_ok    = saver_idle && tail_drained;
pack_flush   = sav_flush | (force_flush && tail_drained);
```

**新判据 `sim/tb_v6_tail_bank.v`**：两条完整入包链（各自 `dc_fifo`+`axi_frame_saver64`+commit+AXI 从机）
喂同一激励，`TAIL_GUARD` 一个 0（V6.4 行为）一个 1（修复），**双向判据**——
旧链必须复现丢尾、新链必须整帧完整，缺一侧即判 FAIL，避免激励退化后"其实没触发机理"的假绿。

```
frame0: 完整 old=8/8 new=8/8
frame1: 完整 old=7/8 (first_bad_word=7)  new=8/8      ← 正是帧尾那一个 64bit 字
commits old=2 new=2                                     ← 换页没有被过度延迟
```

**否决的两项**：① 建议加 `else if (idle) pack_base <= base_addr;`——`!cur_dirty` 在 idle 时必然已成立，
是死代码；② 加超时兜底——改用"CDC 可见排空"作为兜底条件，不需要计数器与新状态。

---

## V7.1（R04）—— 帧缓存地址空间按 2 的幂分块（BRAM 门禁解除）

**证据**：新增层次化报告脚本 `build/tcl/report_mem_hier.tcl` → `build/util_hier.rpt`：

| 实例 | 模块 | RAMB36 | LUT | FF |
|------|------|--------|-----|----|
| `u_fb` | frame_buffer_w64 | **128.03** | 266 | 2 |
| `u_cdc` | dc_fifo | 9.03 | 51 | 126 |
| `u_pipe` | proc_pipeline（行缓存） | 2×RAMB18 | 732 | 288 |

92% 的 BRAM 在一块显示帧缓存上，而 512×300×16bit = 2.4576 Mb 理论下限只要 67 个 tile。

**定位方式**：同样用最小实验而不是读代码猜（`sim/probes/fbtest.v` + `probe2/probe3.tcl`，
同一份数据量只改写法，逐个 out-of-context 综合数 RAMB36）：

| 变体 | 写法 | RAMB36 |
|------|------|--------|
| v0 | 现状 `reg [63:0] mem [0:38400-1]` | 128 |
| v1 | 声明深度直接写 65536 | 128 |
| v2 | 深度取 1024 的整数倍 38912 | 128 |
| v3 | 4 个 16bit 宽 bank 交织（仍单块 38400 深） | 128 |
| v4 | 32bit 宽、38400 深 | 64 |
| **v5** | **按 2 的幂拆两块：32768 + 8192** | **80** |

⇒ 浪费与数组声明深度、位宽、分 bank 方式都无关，是**地址空间被向上填充到 2^16 个字**
（填充率 38400/65536 = 58.6%）决定的；唯一有效解是把地址空间拆成 2 的幂块。

**改动**：`lo[0:32767]` + `hi[0:8191]`；写侧 1bit 块选择；读侧两块同拍都读、用**打一拍后的** `sel_hi`
做 2:1 选择 ⇒ **读延迟仍是 1 拍**（`pl_video_top` 读出走数依赖这个契约）。越界读回黑、越界写忽略
两条 V6.4 行为不变。分块大小由常量函数 `bitsof()` 从 W/H 推导，不硬编码 512×300。

**配套**：此前仓库里**没有任何 TB 覆盖这块帧缓存**。补 `sim/tb_fb_roundtrip.v`：
38400 字全写 + 153672 次**流水式**逐像素回读 + 块边界/帧尾定点复核 + 越界读黑 + 越界写不污染 ⇒ 错 0 次。
流水式回读顺带把"读延迟 = 1 拍"变成可判据（真变 2 拍会整体错位立刻全红）。

| 项 | V7.0 | V7.1 |
|----|------|------|
| Block RAM Tile | 98.93% | **90.5 / 140 = 64.64%** |
| WNS | +0.677 | **+0.819**（比第四版基线还好） |
| methodology | 170 | 186（+16 全是 `u_pl/u_fb/hi_reg_*` 的 SYNTH-6 Warning，逐条查证为第二块 16 个 tile 被逐个报告，非 Critical） |

**门禁的 BRAM 项到此解除。**

---

## V7.3（R05）—— 显示拷贝侧 skid 缓冲同方子

V7.1 之后综合日志仍有 `WARNING [Synth 8-4767] Trying to implement RAM 'sk_addr_reg'/'sk_data_reg'
in registers. Block RAM or DRAM implementation is not possible` —— `axi_frame_writer_gated` 的
64×83bit skid 缓冲一直在掉进触发器，占剩余 9594 个寄存器的约 55%。同 V7.0 的recipe 处理：
两个写入点条件并集恒等于 `do_skid`，合并成独立无复位写块，读口改异步。

| 项 | V7.1 | V7.3 |
|----|------|------|
| Slice Registers | 9.02% | **4.08%** |
| Slice LUTs | 14.58% | **11.87%** |
| Slice | 36.05% | **18.03%** |
| Total Power | 2.362 W | **2.350 W** |
| 可布线网表 | 16139 | **10462** |
| WNS | +0.819 | **+0.499**（代价见下） |

**这一轮的取舍写明白**：省 5215 个寄存器的代价是 WNS 掉 0.320 ns——分布式 RAM 异步读口在 100 MHz
域多了一级读选择。仍 `All user specified timing constraints are met`、0 失败端点，故接受。
要拿回这点余量，路子是把 skid 读口改成提前一拍预取（地址在 `sk_drain` 前一拍就确定），列为可选项。

## V7.4（R06）—— `eth_rxc` 域那条 24 位进位链（时序专项）

V7.3 之后资源全部宽松（Slice 18%、Reg 4%、BRAM 65%），但 WNS 反而从 +0.819 掉到 **+0.499**，
而且 `report_timing` 显示 **`eth_rxc`（125 MHz）最差的 10 条路径全部同构**：

```
Source      u_eth/u_udp/u_udp_rx/rec_en_reg/C
Destination u_eth/u_reasm/rows_hit_reg[0]/CE
Data Path   7.159 ns（logic 2.314 / route 4.845）    Logic Levels 11（CARRY4=6 LUT2=1 LUT3=2 LUT6=2）
其中单根网线 u_eth/u_reasm/udp_rec_en（fo=50）就占 1.947 ns；发起切片 X79Y41 → 终点 X20Y22
```

即 `frame_reasm.v` 里每包末尾要现算 `cover + pkt_pay + 1 >= FRAME_BYTES` 的**三操作数 32 位加法**，
它的进位链挂在那条 1.95 ns 的跨模块网线之后。

**先量策略，再动 RTL**：新增 `build/tcl/sweep_impl_strategy.tcl` 扫 5 个实现策略，
实测把 `impl_1` 显式设成 `Performance_Explore` 后得到 **WNS 0.499 / WHS 0.060，与基线（未指定策略）逐位相同**
⇒ 余量不在策略上。（该脚本本身两次自爆：① `Flow_PerfOptimized_high` 等名字不被本流程支持；
② `report_timing_summary -check_summary_only` 在 2025.2.1 不是合法选项。
脚本与**已跑到的部分结果**一并入库（`build/tcl/sweep_impl_strategy.tcl`、
`build/sweep_summary.txt`），并在文件里写明扫描只完成 1/5 个策略就中断 ⇒
"策略无收益"这个结论只建立在「默认策略 = 基线逐位相同」这一个事实上。）

**改法**：把「现场求和 + 与常量比大小」换成「**饱和累加 + 等值比较**」——
`cov`（本帧字节，含在途包）与 `pend`（在途包的末尾偏移）各自 19 bit、数到 `FRAME_BYTES` 就停，
于是判据变成一次常量等值比较 + 一个与门：

```verilog
wire bytes_ok = cov_sat  | (cov_end  & p_valid);   // 「+1 之后是否够一帧」
wire last_pkt = pend_sat | (pend_end & p_valid);   // 「这是本帧最后一个包吗」
```

等价性依据三条：`cov` 的新值域就是旧代码每拍现算的 `cover+pkt_pay`；计数单调递增使
`>= FRAME_BYTES` 与 `== FRAME_BYTES` 同问；帧起点与提交两处都清零，饱和值不会跨帧继承。
收益：`p_valid` 现在只需到达**一个 LUT 的一个输入脚**，它后面的 6 级 CARRY4 与比较器整条消失。

**一处有意的语义变化**：旧实现靠"坏包字节不计入 cover"来废帧，饱和累加无法退账，
因此新增粘滞位 `bad_frame`，提交判据由两条件与门变三条件。
两版判决只在「零载荷坏包」这一退化情形不同，且新实现只会**更严格**
（不可能出现"以前不提交、现在提交"的危险方向）。

| 项 | V7.3 | **V7.4** |
|----|------|----------|
| WNS（`eth_rxc`） | +0.499 | **+0.974** |
| WHS | +0.060 | +0.066 |
| 失败端点 | 0/21253 | 0/21166 |
| Dynamic Power | 2.338 W | **2.176 W** |
| 像素域 `clkout0_1` WNS | +3.084 | +1.729（布局随网表变化，仍远高于 0） |
| L1 回归 | 30/30 | **30/30**（留档 `sim/results/regression_v7.txt`） |
| L4 板级 | 22 轮全绿 | **新 bit 再跑 3 轮**（15/30 fps + 不限速 60 fps）100.0%、六带 0.0%、丢字带 0 字 |

**顺带一条通用教训**：`cover` 是 SystemVerilog 保留字，文件一旦以 `-sv` 编译即报
`VRFC 10-8549` ⇒ 改名 `cov`。改名前先 `grep` 确认没有 TB 用层次名引用它，否则重写会静默让 TB 测错对象。

---

## V7.5（R07）—— 约束质量：把时钟组挪到只在实现阶段生效

构建日志长期挂着 3 类 CRITICAL WARNING：

| 条数 | 内容 | 处置 |
|------|------|------|
| 1 | `[Constraints 18-513] set_false_path -from ... contains no valid startpoints` | **删除**：`eth_rst_n` 是输出（`system_top.v:41`），这条 `-from` 永远是空集合 |
| 2 | `[Vivado 12-4739] set_clock_groups: No valid object(s) found for '-group [get_clocks -quiet clk_fpga_0]'` | `clk_fpga_0` 由 PS7 IP 的 XDC 创建，综合阶段不存在；**`-quiet` 只压住 `get_clocks`，压不住命令本身 ⇒ 整条 `set_clock_groups` 失效**（连 `eth_rxc`/`sys_clk` 两组一起废） |
| 6~7 | `[BD 41-1348] … connected to asynchronous reset source FCLK_RESET0_N` | **保留**：BD 结构的既有事实，不是本轮引入 |

**为什么拆文件而不是加保护**：第一次尝试在 XDC 里写 `if {[llength [get_clocks -quiet clk_fpga_0]]}`，
立刻得到 `[Designutils 20-1307] Command 'if' is not supported in the xdc constraint file`，
并且**因为整段解析失败，连实现阶段都拿不到时钟组**了 ⇒ XDC 不是普通 Tcl 脚本。
正规解法是按时机分文件：新增 `src/constraints/clock_groups_impl.xdc`，
在 `build/tcl/build_system_axigpio.tcl` 里对它设 `used_in_synthesis false` / `used_in_implementation true`。

**风险预判与证伪**：综合阶段这条约束本来就因命令失败而不存在，所以拆分预期**不改变任何时序数字**；
判据是"若 WNS/端点数/资源与 V7.4 不同就停下重查"。
结果：**门禁数字与 V7.4 逐项一致**（WNS +0.974 / WHS +0.066 / 0 失败端点 / BRAM 64.64% /
`All user specified timing constraints are met.` / Failed Nets 0 / methodology Critical 0），
并且 **`build/system.bit` 与 V7.4 逐字节相同（md5 `7d2cf8ee`）** —— 改动中性被直接证明。
构建日志剩余 CRITICAL WARNING 从 9 条降到 7 条，且这 7 条全是既有的 `BD 41-1348`。

**仍未解决、如实记录的约束缺口**（写清楚比藏着更符合"时序约束"这一考察点）：
`set_input_delay` / `set_output_delay` 各 **0 条**，RGMII TX 由 4 条 `-to` 假路径整条豁免，
RX 侧靠固定 tap 的 `IDELAYE2`（`IDELAY_VALUE=15`）而没有将这段延迟写进约束。
所以「All constraints met」覆盖的是片内路径；**片外接口时序由板级证据支撑**
（ping 0% 丢失 + 逐字命中率 100.0%），而不是由约束证明。
补上真正的 RGMII I/O 约束（DDR 双沿 `-add_delay -clock_fall` + TX 相位）列为未竟项。

---

## V7.6（R08）—— 链路健康自诊断：把"屏上有黑纹"变成运行期可读数

### 动机：现有统计在上板时有一条是死的

`eth_udp_video_top.v:188` 把 `frame_reasm` 的 `p_good` 硬接成 `1'b1`（本设计不查 UDP 校验和），
所以 `stat_bad` 在板上**恒 0**；而真正会吃掉数据的只有一处 ——
`cdc_wr = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full` 里被 `fifo_full` 挡住的那一拍。
在此之前，这条通路唯一的证据是"屏幕出现黑纹"，事后、靠眼、且分不清丢在 CDC 还是 HP0。

### 交付

| 文件 | 作用 |
|------|------|
| `src/rtl/eth/link_monitor.v`（新） | eth_rxc 域统计：`drop_words`、作废帧/坏包、缺行峰值、帧间隔 last/min/max/Σ、`stall_ms` 看门狗、CDC 灌满次数、5 个标志位 |
| `src/rtl/eth/snap_cross.v`（新） | 「准静态总线 + 跳变沿捕获」跨域器，带独立心跳超时 ⇒ 能区分"没数据"和"源时钟没了" |
| `frame_reasm.v` | **只加两个观测口** `frame_abort` / `rows_missed`，验收判据一字未改（diff 里两条被删行都只是被超集替换） |
| `osd_overlay.v` | 新增 L3 `DROP=`（hex 5 位）、L4 `STALL=`（dec 4 位），字模表补 R/O/T/L，`line` 由 `[1:0]` 修成 `[2:0]` |
| `system_top.v` + BD | 第二路 `snap_cross`(100 MHz) + 10 选 1 lane 窗口 + 一条 32bit 只读 AXI GPIO；lane 号走**已有**的 `gpio_o[31:27]` |
| `src/host/health_read.mjs`（新） | JTAG 读回十个 lane + 心跳位；先读回 GPIO_0 原值再读-改-写，最后原样归还（否则会踩掉特效/阈值） |
| `build/tcl/ooc_newmods.tcl`（新） | 三个新模块的 out-of-context 综合 + 带 I/O 延迟的时序预检（1~2 分钟 vs 全流程 15 分钟） |

### 三个只有综合/板级才暴露的 bug（本轮真正的价值）

1. **`ms_last16` 被两个 always 块驱动**。仿真全绿，综合报
   `[Synth 8-6858] multi-driven net Q is connected to at least one constant driver which has
   been preserved, other driver is ignored` ⇒ 板上它只剩 GND 常量驱动，间隔与 stall 基准全废。
2. **1 ms 分频器位宽写死 `[15:0]`**，而 `TC = 125_000_000/1000 = 125000 > 65535` ⇒
   比较恒假、`ms_tick` 在真实参数下永远不来。取证是一句不起眼的
   `WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed.`
   **为什么 26 条断言没抓到它**：TB 为了让"等 200 ms 断流"跑得动，把 `CLK_HZ` 改成 1000
   （TC=1）—— 恰好把这个问题改没了。修法是 `DW = $clog2(TC+1)`，
   并且**再用生产参数例化一份守门**：`PASS production timebase: 62 ms_ticks in 7832805 cycles`。
3. **OSD 的 32bit 十进制除法把第一次 L3 直接打挂**：`WNS −6.765`、19 个违例端点，
   最差路径 `u_pl/u_lm_x/bus_q_reg[31] → u_pl/u_osd/g_reg[3]`，**45 级 / 26.647 ns**。
   修法不是放宽约束，而是把除法从链上摘掉：DROP 改十六进制（取 nibble），
   STALL 先饱和到 14 bit 再**分两拍**算（数字每帧才变一次，晚两拍人眼无感）。
   改完 OSD 最差路径 27 级，且那 27 级是 `x → 行/列除法 → 字模` 的既有形状。

测试台自己也修了两处：`cdc_full` 在**正沿**用阻塞赋值会和 DUT 抢时刻（上升沿检测丢），
以及给 16bit 的 `net_stall` 传 70000 想测饱和、结果先被截成 4464。

### 门禁（V7.5 → V7.6）

| 指标 | V7.5 | V7.6 | 门禁 | 结论 |
|------|------|------|------|------|
| WNS | +0.974 ns | **+0.527 ns** | ≥0 | 过（新逻辑吃掉 0.45 ns 余量） |
| WHS | +0.066 ns | **+0.048 ns** | ≥0 | 过 |
| 失败端点 | 0 | **0** / 23635 | =0 | 过；`All user specified timing constraints are met.` |
| BRAM | 90.5 = 64.64% | **90.5 = 64.64%** | ≤97% | 过（本轮一个 tile 都没加） |
| Slice LUT | 6313 = 11.77% | **7279 = 13.68%** | ≤98% | 过 |
| Slice 站点 | 18.09% | **2943 = 22.13%** | ≤98% | 过 |
| 寄存器 | 4345 = 4.08% | **5783 = 5.44%** | —— | 两路 320bit 快照 + 计数器 |
| DSP | 13 | **13 = 5.91%** | —— | 未增 |
| 功耗 | 2.350 W | **2.361 W**（+0.5%） | 不明显变差 | 过 |
| Failed Nets | 0 | **0**，`Router Completed Successfully` | =0 | 过 |
| methodology Critical | 0 | **0** | 无新增 | 过 |
| cdc Critical 行 | 4 | **4** | 无新增 | 过（详见下） |
| 构建日志 CRITICAL WARNING | 7 | **9** | —— | 新增 2 条都是 `BD 41-1348`，即两个新 BD 单元继承同一既有"异步复位接 FCLK_RESET0_N"结构，非新问题 |
| L1 回归 | 30/30 | **32/32** | 全过 | `sim/results/regression_v76.txt` |

`report_cdc` 的行数没变，但**端点构成变了**，如实记下：`eth_rxc → clkout0_1` 从 33 端点涨到 83，
新增的 50 个全部落在 `Safe` 列（unsafe 仍 16、unknown 仍 17，即本轮没有新增不安全端点）；
`eth_rxc → clk_fpga_0` 这一行有 **1 个 unsafe / 14 个无 ASYNC_REG**，是本轮新加的
100 MHz 那一路 `snap_cross` 里 `bus_q` 的捕获总线 —— 它**故意**不打 `ASYNC_REG`
（那是数据总线不是同步链），安全性由 `SETTLE` 节流 + 边沿后捕获保证，
L1 的 100/100 不撕烈断言就是它的证据。这一点在 `study/03_模块详解/08_链路健康自诊断.md` §4 有完整推导。

**L4（同日 20:15–20:55 补做，板子可访问后）**：`d7e385b6` 上板，JTAG 读回十个 lane，
空闲/推流/停流三态全部符合设计，**22 次两遍读零撕烈**，`stall_ms` 从 0 线性涨到 12142 ms；
`stall_ms` 空闲能涨到 0xFFFF 这一条同时是上面第 2 个缺陷已修好的**板级**证据
（它只会由 `ms_tick` 推进）。数据见 `data/measured/board_measure_r08.md`。
**仍然没有的板级战果，如实写出**：① `--no-pace` 洪水也压不满 CDC（排空 ~200 MB/s > 入包上限
125 MB/s），所以“drop_words 与黑纹同时出现”只有 L1 的强制判据；② `hb_gone` 需要拔网线、
`frames_bad`/`rows_miss_max` 需要定向丢中间包（`video_sender` 还没有 `--drop-packet`），
两项都还没做；③ OSD 两行尚未经肉眼确认。

---

## V7.6b（R09）—— 拔线实验推翻了自己的假设，于是加了 `hb_slow`

用户肉眼确认 OSD 五行（含新的 `DROP=`/`STALL=`）显示正确之后，做了拔线实验：
`--test move` 15 fps 推流，一条 xsdb 会话每秒采一次 lane2/lane8/lane31，共 110 次。

**先看它对的部分**（这份数据同时是 R08 的第二次独立验证）：

* 推流时 `Δpkts/s = 3315 = 15 fps × 221 包/帧`，与上位机标称**逐位吻合**
  （个别秒读到 3536 = 16 帧，是 1 秒采样边界，不是速率漂移）；
* 拔线瞬间 `pkts` 冻结、`stall_ms` 开始爬；插回后 `stall_ms` 立刻归零、`pkts` 恢复增长，
  **全程不重启板子也不重下 bit** ⇒ 自动恢复成立。

**再看被推翻的部分**：`hb_gone` 一次都没有触发。设计假设是"拔线后 RTL8211 停供 RXC"，
板子给的却是**另一种行为**。硬证据不是"lane31 一直是 0"，而是一条定量观察：
断流那 13 秒 `stall_ms` 只从 831 走到 1117，即 **+20.5 计数/秒**而非 1000/秒，
而它的唯一时基是 `ms_tick = (ms_div == 124999)` ⇒ **eth_rxc 当时只有约 2.5 MHz**。
也就是 PHY 没关时钟，而是把它拉慢约 48 倍 —— "有没有沿"检不到，能检的是"沿够不够快"。

**修法**：`snap_cross` 增加 `hb_slow`（心跳间隔 > `SLOW_MS`，默认 5 ms ⇒ 正常 1 ms、
退化 ~50 ms，两侧余量 5× 与 10×）；`osd_stall = (hb_gone | hb_slow) ? 9999 : stall_ms`；
lane31 变成 `{30'd0, hb_slow, hb_gone}`，`health_read.mjs` 分开报两个位。
方向差点写反：第一版比较是 `to_cnt > LIM − SLOW_LIM`，代入真实数字
（`LIM=10_000_000`、1 ms 心跳 ⇒ `to_cnt=9_950_000`）会把**健康**的 1 ms 判成退化；
源时钟变慢 ⇒ 目的域量到的间隔**变长** ⇒ 正确判据是 `to_cnt < LIM − SLOW_CYCLES`。

**口径因此收紧**（这是对外表述必须改的地方）：`stall_ms` 只在链路正常时是真实毫秒；
断链期间它是"越来越久"的序指标。说"没流了"要用 `flags.bit3 流活着` 和 `pkts` 停增，
不要引用那个爬得很慢的毫秒数。

**新工具经验**：`build/tcl/ooc_newmods.tcl` 加了 `OOC_ONLY=<模块>` 入口 —— 同一进程里
连跑三次 `synth_design` 会撞上 Windows 的 `.Xil` 目录锁
（`[Designutils 20-411] ... could not be deleted`）并**静默跳过后面的模块**；
同时明确写进脚本头：**这个 OOC 的数字不是门禁**（它对输入一律加 3 ns 延迟，
`osd_overlay` 因此报 −0.256，而真实 L3 是 +0.527 / All constraints met），
它的用途是抓结构性大链，不是打分。

L1 仍是 **32/32**（一次进程跑完，`SIM DONE pass=32 fail=0`），新增断言：
`hb_slow clear while the heartbeat is at nominal rate`、
`hb_slow asserts when the source clock is degraded (拔线工况)`、
`hb_gone correctly stays clear (它看不见这件事，正是加 hb_slow 的理由)`。

---

## V7.6c（R10）—— 仪表的**量程**缺陷：`gap_ms` 会回卷，于是加宽 + 饱和 + 可清零

R09 的受控拔线实验本来是为了验证 `hb_slow`，结果它同时抓出了仪表自己的一个说谎缺陷：
`gap_max` 读到 **34066 ms** —— 那不是任何一次断链的时长，而是
`gap = ms_now − ms_last` 里 **16bit 毫秒计数绕回的余数**。
前两个缺陷（多驱动、分频器位宽）是"逻辑死了"，这一类是"逻辑活着但给出假数"，
更难发现：它不产生错误行为，只产生**看起来完全合理的错误数值**，
而且 `gap_max` 终身保持 ⇒ 一次长空闲永久污染它，之后更大的间隔还会因为绕回**读起来更小**。

三处修改（缺一层都会以别的形式复发）：

| 改什么 | 为什么 |
|--------|--------|
| `ms16` → `ms32`（32bit 毫秒计，49 天不回卷） | 让差值本身落在能表达的范围里 |
| `gap_new` 一律**饱和**在 `0xFFFF` | `0xFFFF` 的读法是"至少 65.5 s / 超量程"。仪表宁可说超量程，也不给假精确值（与 16bit 显示字段饱和是同一条原则） |
| 新增 `gapclr`：`gpio_o[26]` 经 3FF 同步进来的电平，只清 `gap_*` 并**撤销 have_base 基准** | 终身保持的 max 需要"归零入口"才谈得上当测量用；撤销基准是为了让清零后的第一帧只重建基线、不把"空闲到现在"折进间隔 |

上位机侧对应 `health_read.mjs --gapclr`（拉高 250 ms 后归还 GPIO_0 原值）。
lane 语义现在写死成三条：lane0/1/2/6/8/9 = 自启动以来；lane3/4/5 = 自上次 `--gapclr` 以来；
所有 16bit 字段 = 饱和不回卷。

**门禁（`build/v76c_build.log`）**：WNS +0.408 / WHS +0.035 / 失败端点 0/23698 /
BRAM 64.64% / Slice 21.73% / LUT 13.86% / Reg 5.47% / 2.361 W / Failed Nets 0 /
`All user specified timing constraints are met.` / methodology Critical 0 /
cdc Critical 行 4 / 构建日志 CRITICAL WARNING 9。**L1 32/32**（新增 4 条断言：
>65.5 s 的间隔必须饱和而不是绕回；`gapclr` 清零帧间隔统计并干净地重建基准；
`gapclr` 不许碰别的计数；清零后间隔统计能重新校准）。

WNS 轨迹 R08 +0.527 → R09 +0.669 → R10 +0.408：R08→R09 网表几乎没变却涨了 0.14，
所以这个量级的起伏主要是布局布线抖动，不是我的改动吃掉的方向性余量 —— 但三次都在 +0.4 以上，
**这一域的余量确实已经从 V7.5 的 +0.974 收缩了一半**，记在这里而不是挑好看的报。

**板级对账（`69b84310`）**：`--gapclr` 后 `gap_sum` 从 14185 掉到 1259、`gap_min|max`
从带脏数据的 56/85 收窄到 60/79；随后 14.8 秒里 `gap_sum` 增加 14666，而 15 fps × 66 ms
预测是 14652，**差 0.1%** —— 一条数同时验了 `gap_sum` 算术、`ms32` 时基和"只清 gap_*"的语义。
另外 `frames_bad` 在**推流起始**也会 +1（本次是 1 次、缺 236/300 行），最合理的解释是
ARP 还在解析时帧头包已发出 —— 与拔线重连同一种形状。含义：`frames_bad=1` 可能是启动瞬态
而不是链路质量差，所以**测量前应当 `--gapclr` 并先跑一段预热流**。这条使用条件写进记录，
比把数字藏起来更符合"在线自验证"的口径。

---

## V7.7（R12 + R13）—— 旋转收进右窗、SD 本地回放、以及一次"把自己的测量推翻重来"

三件事在同一条晚上完成，其中第一件是需求，后两件是它顺带暴露出来的账。

### R12 旋转只保留右半窗（用户要求）

`pl_video_top.v` 删掉左路的 `rotate_mapper` 实例与 `sx_l/sy_l/oob_l` 的旋转分支，
左窗固定 `cx_q3/cy_q3`。**风险几乎为零**的理由值得记：`rot_on=0`（angle=0）那条分支
今天就在板上跑着且逐像素正确，本改动只是删掉"angle≠0 时左窗也转"这一行为，
不引入新通路、不动流水深度 ⇒ L1 的判据是"不新增失败"，不是"新路径通过"。

| 门禁（build#12 vs build#10） | 前 | 后 |
|------|------|------|
| WNS / WHS | +0.408 / +0.035 | **+0.540 / +0.042** |
| 失败端点 | 0/23698 | 0/23419 |
| **DSP48** | 13 | **9（−4）** |
| Slice LUT / Reg | 7375 / 5818 | 7193 / 5794 |
| BRAM tile | 90.5（64.64%） | 90.5（不变：三角表本来就是 LUT） |
| 总功耗 | 2.361 W | 2.357 W |

省下的 4 个 DSP48 恰好是插值要用的那类资源 —— 需求与时序/资源账同向，这种机会不多。

### R13 PS 发布握手 + SD 卡本地回放（P1 的固件半边）

- 新增 `src/rtl/util/ps_publish.v`：翻转位 3FF 同步 + 挂起位；`gpio_o[18]` 每翻一次 =
  请求 PL 在下一个 `frame_start` 从 DDR 搬**一次**。原来无条件每帧搬，一旦 PS 正在写就必然撕裂。
- 顺手修掉一处真实亚稳态取用：`fs_tog` 的条件用的是未同步的 `src_sel`，而同文件早有 `src_sel_pix`。
- `src/ps/sd_play.c`：裸机只读 FAT32（BSP 里没有 xilffs）+ `XSdPs` DMA **直接写** PL 要读的那块 DDR，
  零 memcpy、无双缓冲；`build/ps_app.mjs` 脚本化编译（不依赖 IDE 点击路径，才谈得上"从零复现"）。
- `ZOOM0/ZOOM1` 解绑生效 ⇒ `set_src.tcl` 必须改写 `0x00030000`，否则"上电即呼吸"随解绑消失。
- 台架卫生：`run_sim.tcl` 不再把 `NO_ASSERT` 计为 pass。L1 **34/34**。

### 把interp_study 的表推翻重来（一次自我证伪）

给插值收益表加"只补横向/只补纵向"两种取法时，恒等行上出现 `2x2盒 = 99 dB`
（= 逐像素零误差）。硬边缘上任何滤波都不可能零误差 ⇒ 错的是**测量**：
源栅格采在整数坐标，而"理想像"却在 `[sx, sx+1]` 积分 ⇒ 理想像整体平移半像素，
1×1 面积平均在数学上退化成对源栅格做 1×2 盒，于是盒式必然满分。
上一节 R11 追加里"这个指标天然奖励平滑、99 dB 是口径问题"的解释**是错的**。

修正：理想像改成以 (sx,sy) 为中心、边长 k=inv/256 的足迹面积平均；并加
**锚点 + 反向对照**双判据（带限图样恒等下最近邻 ≥45 dB，实测 45.4；故意用旧约定必须低 ≥10 dB，
实测 30.0），任一不满足就 `exit(1)` 不许引用任何表。图样补各向同性带限纹理 ——
原来四种全是单方向图样，对它们说"纵向没收益"是平凡成立、不构成证据。

修正后的结论（完整表 `data/measured/interp_gain_attribution.txt`）：
缩放端增益 100% 在横向；旋转端横/纵各只占 ~20%，其余只有 2D 组合才拿得到；
硬边缘 −3.7 dB、2px 棋盘 −1.5 dB（双线性反而更差）。
⇒ **"只做横向就行"这个诱人的结论是不成立的**，想做旋转插值就必须读两行源数据。
再叠加一条实测：读口每个像素周期恰好一次读、零余量 ⇒ 横向也**不免费**。
但 `clk_pix5x`(250 MHz，同一 MMCM) 每像素给 5 槽，4 抽头够用，且整数同源不是异步 CDC。

## 五版累计（第四版 → 第五版）

| 项 | V6.4 | **V7.5（当前 main）** | 变化 |
|----|------|------------------------|------|
| Slice Registers | 54588 / 51.30% | **4303 / 4.04%** | −92.1% |
| Slice LUTs | 19825 / 37.27% | **6262 / 11.77%** | −68.4% |
| Slice | 13290 / 99.92% | **2406 / 18.09%** | −81.9% |
| Block RAM Tile | 138.5 / 98.93% | **90.5 / 64.64%** | −34.3 个百分点 |
| LUT as Memory | 305 / 1.75% | 1341 / 7.71% | 换用位置（余量仍 92%） |
| Total / Dynamic Power | 2.525 W | **2.350 / 2.176 W** | −6.9% / −6.3% |
| WNS / WHS | +0.708 / +0.064 | **+0.974 / +0.066** | 全约束始终满足；WNS 反而高于第四版 |
| 失败端点 / route errors | 0 / 0 | 0/21166 / 0 | — |
| methodology / cdc | 170 / 4 条既有 Critical | 186 / 同样 4 行 | 无新增 Critical |
| 构建日志 CRITICAL WARNING | 9（含 1 空约束 + 2 时钟组） | **7（全部为既有 BD 41-1348）** | −2 类噪声 |
| 回归仿真 | 28/28 | **30/30**（`sim/results/regression_v7.txt`） | 新增帧尾 A/B 与帧缓存逐像素回读 |
| bit / xsa | `155d73bc` | **`7d2cf8ee`**（1777758 B） | V7.4 与 V7.5 的 bit 逐字节相同 |

**关键性质**：V7.0/7.1/7.3 是纯资源改造（除 V7.2 的修复外功能不变），V7.4 是**纯时序改造**
（提交判决只可能更严格），V7.5 是**纯约束整理**（bit 不变）。
四道门禁（时序 / 资源 / 功耗 / 布线）从两项不合格变为全部合格，且时序始终满足全部约束。

---

## 板级复验（V7.3，22 轮）

`ps_jtag_boot`（DDR_ECHO 正确）→ `program_pl`（`f5c69ca7`）→ `set_src`（0x00010000）→
`ping 192.168.1.10` 0% 丢失 → `--test frameid` 推流 → **停止推流后** JTAG 回读两 bank 逐 16bit 反解帧号。

| 激励 | 每 bank 帧号跨度 | u32 内两 lane 异帧 | 最新帧命中率 | 包内分带丢字率 | 最长连续丢字带 |
|------|------------------|--------------------|--------------|----------------|----------------|
| 15 MB/s @15/30 fps（5 轮） | 恰好一帧 | 0/76800 | **100.0%** | 六带全 0.0% | 0 |
| 30 MB/s @30 fps（2 轮） | 恰好一帧 | 0/76800 | 100.0% | 0.0% | 0 |
| 不限速 60 fps（400 帧） | 恰好一帧 | 0/76800 | 100.0% | 0.0% | 0 |
| 不限速 120 fps（实测 116 fps ≈36 MB/s，900 帧） | 恰好一帧 | 0/76800 | 100.0% | 0.0% | 0 |
| 1396 B 载荷（非 8 倍数，3 轮 180 帧） | 恰好一帧 | 0/76800 | 100.0% | 0.0% | 0 |
| **V7.4/V7.5 新 bit：15 fps × 200 帧** | 恰好一帧（198 / 199） | 0/76800 | 100.0% | 六带全 0.0% | **0 个 16bit 字** |
| **V7.4/V7.5：30 fps × 300 帧** | 恰好一帧（299 / 298） | 0/76800 | 100.0% | 全 0.0% | 0 |
| **V7.4/V7.5：不限速 60 fps × 400 帧** | 恰好一帧（399 / 398） | 0/76800 | 100.0% | 全 0.0% | 0 |

后三行是在 **V7.4 的 `frame_reasm` 改写 + V7.5 的约束拆分之后** 的同一块板、同一会话重测
（V7.4 与 V7.5 的 bit 逐字节相同，故合记），明细与复算命令见
`data/measured/board_measure_r06_r07.md`。⇒ **V7.4 的时序改写对入包链零回归**。

⇒ **三次综合行为改造对入包链零回归**；1396 那几轮另外覆盖了 V7.0 重写的"半截字/keep 掩码"路径
（180 帧 × 220 包 ≈ 3.96 万次半截字推送）。

**未获得的结论（不粉饰）**：把 V6.4 基线 bit（`155d73bc`）烧回板上，用同样四档激励测（6 轮 + 两轮洪水），
当年记录的"帧尾 +0x4AFF8 高半个 u32 读 0、8 次见 4 次"**一次都没有出现**
（仓库自身 `report/V6_BOARD_MEASUREMENT.md:99` 也记过一次"连帧尾残留都没出现"）。
⇒ V7.2 的板级 A/B **没有区分力**，其证据等级只到"机理三段论 + 仿真双向判据"。
同时撤销过程中一个过度推论：中途曾写"文档里已接受的 `--no-pace` 洪水丢包消失了"，
随后 V6.4 基线同样洪水下也是 100%，说明该现象在手头激励下根本没被触发。
要拿到板级判据，需先造出 `sv_full` 落在帧尾的条件（上位机加非 8 倍数载荷开关，或拉长 HP0 占用窗口），
记为未竟项。

---

## 提交对应关系

| 提交 | 内容 |
|------|------|
| `8c30d9c` | `perf(eth)` V7.0 打包 FIFO → 分布式 RAM + 构建脚本补 power/route 报告 |
| `242f6e7` | `fix(eth)` V7.2 换页等 CDC 排空 + `ddr_bank_commit` 抽取 + `tb_v6_tail_bank` |
| `ff7c890` | `perf(video)` V7.1 帧缓存按 2 的幂分块 + `tb_fb_roundtrip` + 层次化报告脚本 |
| `a22a054` | `perf(video)` V7.3 显示侧 skid → 分布式 RAM |
| `1cff7e1`…`3c1b909` | `docs` L4 板级 22 轮结果、xsa 核验、版本谱系记录 |

**分支归位**：第四版存档在 `v4-zero-loss`（= `647160e`）；第五版为 `main`。

---

## V7.8（R18 + R19 + R20）—— 双线性插值真的接进显示通路，以及 250 MHz 读口的三笔账

一句话：**右半窗的缩放/旋转不再是"跳像素"，而是插出来的**；左半窗仍然是逐位不变的原画面。
代价是三笔之前欠着的账（配准常数、字/车道成对、快域算术），全部由这一轮的红色门禁与台架逼出来。

### 为什么值得动显示通路（数据，不是感觉）

`src/host/interp_study.mjs` 对理想"面积平均"参照算 PSNR（模型先被身份锚点与反向对照校验过，
见 CHANGELOG V7.7 / OVERNIGHT_LOG R11 追加 2）：旋转态下**横向补上约 +20%、纵向约 +20%、
两者都做约 +40%** ⇒ 只做横向（看起来最便宜的那一半）等于没做。
而"读两行"必须有 4 个抽头，4 个抽头必须抢读口 ⇒ 真正的改动量在这里，不在乘法器。

### 怎么不花一块 BRAM

| 事实 | 结论 |
|------|------|
| 帧缓存 80 个 RAMB36，全片 140；同一组阵列再加一个**逻辑**读口实测 80→160 | 加读口这条路封死 |
| 片上已有 250 MHz `clk_pix5x`（HDMI 串行化在用），与 50 MHz `clk_pix` 同源同相、整数 5:1 | 每个像素周期有 5 个"快槽"可用 |
| 右窗 4 次抽头读 + 左窗 1 次最近邻读 = 恰好 5 | 读口饱和、零余量，**BRAM 一分不涨** |

实现分三层，每层都有独立台架：`bilin_lerp`（算术，`tb_bilin_lerp`）、
`tap_sched`（5 槽调度 + 抽头装配，`tb_tap_sched`）、`fb_rd5x`（含真实帧缓存的端到端，
`tb_fb_rd5x`：152 样本、右窗对实数双线性模型 ±1 LSB、左窗逐位精确、
并**用"唯一平移量搜索"量出 LAT=5**，同时反向证明 74% 的样本"插值结果≠最近邻"）。

### 三笔被逼出来的账

1. **快域不做算术**（build#14：WNS −1.277、1400 端点）。`clk_pix→clk_pix5x` 只有 4 ns 预算
   （同相派生时钟 ⇒ 最早快沿），把 `base+ROWW` 这类加法放快域就是判红。
   现在 5 个地址全部在慢域算好各打一拍，快域只剩一次 5 选 1 mux。
2. **字号与车道必须同一个沿采集**（台架抓到，非门禁）：左窗地址在 s0 起始沿进快域、
   车道却在 s1 沿采 ⇒ 差一拍。板上级现象是"整列颜色对、左右偏一格且不报错"。
   `tb_tap_sched` 当时 59/61 条左窗判据全错、右窗 60 条全对，一眼定位。
3. **配准常数不能写字面量**：读口晚了 3 拍，顶层彩条链 / 效果链 / `split_display` 的抽位
   全部改为从 `RD_LAT` 推导（`BAR_L_TAP/BAR_R_TAP/PIPE_TAP/SPLIT_TAP`）。
   把 V7.7 的旧值代回公式，恰好暴露两处存在很多版的 1 像素错位：
   `PROC_LAT` 与 `de_d[3]` 的组合差 1 拍（效果链，一直记在 P0-C）、右窗彩条 `bar_r_d2` 差 1 拍。
   **这两处是本轮顺手改的，属于可见行为变化**（彩条只在 SRC0 且肉眼几乎看不出，
   效果链是 1 列平移）⇒ 明早第 10 步专门核对。

### 运行时开关，不留两套通路

`bilin_en` 是 AXI GPIO **bit19**，串口命令 `BILIN0 / BILIN1` 现场切换；关掉时小数被钉成 0，
`bilin_lerp` 在 `fx=fy=0` 时恒等于 `p00`（该性质由 `tb_bilin_lerp` 判据 2 保证），
于是**同一条通路**原样退化成最近邻。`tb_fb_rd5x` 里 23 个"BILIN=0 样本"逐位等于最近邻 ✓。
`set_src.tcl` 默认写 `0x000B0000`（src + zoom + bilin）。

### 门禁（V7.8 全程，三版构建）

| 构建 | 内容 | WNS | 失败端点 | BRAM | 判定 |
|------|------|-----|----------|------|------|
| build#14 | 首版接通（地址算术在快域） | **−1.277**（intra-5x），跨域 −0.605 | 1400/24510 | 90.5（64.64%，**未涨**） | **FAIL**；bit 留在 `build/failed_r19b/` |
| build#15 | 地址算术全部搬回慢域 | **−0.485**（最差路径布线占 84.7%） | 349/24510 | 90.5 | **FAIL**；bit 未保留（被 #16 覆盖，数字在此） |
| build#16 | RTL 同 #15，只把实现策略换成 `Performance_ExtraTimingOpt` | **−0.327**，但 `clk_pix→clk_pix5x` 已转好 **+0.788** | 193/24704（路由 0 错误、14676 根可布线网表全部布通；WHS +0.047） | 90.5 | **FAIL**；bit 留在 `build/failed_r24/` |

资源侧的账（build#16 报告）：`Slice LUTs 8389 / 15.77%`、`Slice Registers 6616 / 6.22%`、
`BRAM 90.5/140` **一个 tile 都没多**（这本来就是这一版的设计目标）、`Dynamic 2.583 W`、
`methodology` Critical 0 新增、`cdc` Critical 仍是那 4 行既有豁免。

**最终处置：V7.8 不进主线。** 整套（RTL + 4 个台架 + 配准常数 + 文档）原样打在 tag
**`v7.8-bilinear-wip`（= 提交 `0d02c2e`）**；主线顶层与几何回到 build#13 的来源 `c9ab9a3`，
残留差异只有三条且都验证为惰性（`process/bilin/*` 未被例化、`video/fb_pack.v` 只给 KU5P 用、
`frame_buffer_w64` 多一根没人接的 `rd_data64`）⇒ 措辞是"与 build#13 **等价**"，不是"逐字节相同"；
明早直接下冻结的 bit 本体，不重跑构建。
对外口径因此是：**双线性插值 = 组件、集成与台架全部完成并通过，250 MHz 分时读口最后
0.327 ns 未收口 ⇒ 不说"板上已有双线性"**。收口的三条候选路径写在
`report/OVERNIGHT_LOG.md` R21 末（Pblock 圈住 `u_rd` + 那 80 个 BRAM tile 最对症）。

## V7.9（R22 + R23）—— 两笔 CDC 账结掉，第二块板开始说话

一句话：**功能面零变化，正确性面三处收紧**；同时 KU5P 从"只会应答"变成"每秒主动上报"，
并第一次走通发送侧（RGMII TX + udp_tx + CRC）。

| 本轮 | 内容 | 判据形态 |
|------|------|----------|
| R22 | `eth_link` 像素域裸采 4 处 → 统一 3 级同步；`effect_ctrl` 的 en/th 补 `ASYNC_REG` | `cdc.rpt`：`eth_rxc→clkout0_1` 端点 **84→51**、被标记 **16→1**；`clk_fpga_0→clkout0_1` 未归类 **13→0** |
| R23 | `copy_abort`（axi 域 1 拍脉冲）→ 翻转式脉冲同步器 `abort_tgl` + 3FF + 异拍 | `tb_v79_abort_toggle` 相位扫描：**裸采 27/30（错开 4 ns 那一档 0/3）、电平 3 级与裸采逐相位相同、翻转式 30/30** |
| R23 | KU5P 遥测 `ku5p_telem`（36 字节大端）+ 自研发送仲裁 `ku5p_tx_arb` | `tb_ku5p_telem`：逐字节拆 Ethernet/IP/UDP 头 + 独立实现算的 CRC 余数判据；`tb_ku5p_tx_arb`：**同一激励下厂商 `eth_ctrl` 帧中间换源 1 次，自研 0 次** |

### 三件只有在"真的把代码用起来"之后才会露出来的事

1. **厂商发送仲裁有一个 `||` 应为 `&&`**（`eth_ctrl.v`，改前 161 行那条 always）：两条独立忙线用 OR 连起来，
   语义是"任一空闲"，而想要的是"全部空闲" ⇒ 正在发的帧会在中间被 ARP 抢走 mux。
   主线今天 `udp_tx_start_en` 恒 0 ⇒ 该条件恒真，ping 回包一直在这个风险下跑，只是窗口窄。
   KU5P 侧换成自研 `ku5p_tx_arb`（规则只有一条：**拿到介质的那帧发完之前谁都不许换**，
   且只认当前 owner 的 `done`）；主线侧本轮也改了 —— 但**不是一行能改完的**：
   符号之外还要补 `arp_pend` 记账位，否则那一拍宽的 `arp_rx_flag` 会被"另一路还忙"吃掉。
   两处改动的完整理由（含台架抓到的"跨块清标志晚一拍 ⇒ `arp_tx_en` 高两拍 ⇒ ARP 发 13 字节"）
   登记在 `report/ISSUES.md` #37，门禁数字见下面的构建表。
2. **`tx_data` 的端口名一样，契约不一样**：厂商 `udp_tx` 的 `tx_req` 在 UDP 头最后一字节
   就提前拉高，而它原来的数据源是带一拍读延迟的同步 FIFO ⇒ 用组合 mux 直接喂会吃掉第 0 字节。
   抓包 dump 一眼看到（线上从 `55 35 50` 开始而不是 `4B 55 35 50`）。
3. **位宽静默截断成对出现**：`localparam [4:0] NBYTES = 5'd36` 变成 4；`case (idx)` 里
   写 `5'd32` 变成 0。抓住它们的是"IP 总长 = 20+8+36"这种**能被算术式表达**的判据，
   不是"包有没有发出去"。

### 方法论上的两条自我更正（都写回文档，不改口径只改理由）

- "copy_abort 大约会漏一半"是我**估**的；相位扫描实测是"对齐全对、错开 4 ns 全丢"。
- "电平型 3 级同步只会更糟"也被自己的台架否掉 —— 实测与裸采**逐相位一致**（一样糟）。
  ⇒ 结论不变（必须用翻转式），但依据从"我觉得"换成"表里那一行"。
- 附带一条最值钱的：**0 ns（板上标称同相）仿真里全对** ⇒ 这类 bug 的形态就是
  "仿真通过、硅片靠运气"，所以判据必须含人为移相。

### 工具与流程事实

- ModelSim AE 2020.1：`vlog` 可用（**它抓到过一处 Vivado 侧不易读的错** —— 标识符先出现在
  端口连接里就成了隐式 1 bit 网，之后的显式声明变重复声明），`vsim` 无授权不能跑
  ⇒ 定位成"交叉编译检查"，仿真仍走 xsim。
- **没被任何台架例化的顶层，只有综合会检查命名端口连接是否存在**：
  `ku5p_eth_top` 把 `.udp_txd` 写成 `.udp_gmii_txd`，40 个台架全绿，`synth_design` 7 秒就报。
  ⇒ 全量回归 `pass=40 fail=0` 与"顶层能被综合"是两件不同的事，都要跑。
- 全量 runner 不能整目录 glob `ku5p/src/rtl`：那里的 `gmii_to_rgmii/rgmii_*` 与
  `src/rtl/eth/` 下同名但是两种器件写法，一次编译里会互相覆盖（"看起来绿、验的不是同一份"）。

### 门禁与版本对应

| build | 内容 | 结果 |
|-------|------|------|
| #17 | V7.7 功能 + R22 两笔 CDC | **WNS +0.447 / WHS +0.066 / 0 失败端点 / BRAM 90.5 / Dynamic 2.183 W**，L1 37/37 → 采纳，归档 `build/frozen_r17_cdc/` |
| **#18** | 再加 R23 的 `abort_tgl` 翻转同步 | **WNS +1.002 / WHS +0.050 / 0 失败端点(23422) / Slice LUT 7184(13.50%) / Reg 5800(5.45%) / BRAM 90.5(64.64%) / Dynamic 2.184 W / 布线 0 错误 / methodology 0 CRITICAL / 日志 CRITICAL WARNING 9（与基线同）**，L1 **40/40** ⇒ **采纳**（md5 `534f7760…`，报告与校验和冻结在 `build/frozen_r18_abort/`；⚠ 那一版**没拷 bit**、MANIFEST 引用的是活路径 `../system.bit`，被 #19 覆盖过 ⇒
07:1x 靠 `git show 7578217:build/system.bit`（md5 核对 = `534f7760`、1855990 B）**复原**进
`frozen_r18_abort/system.bit`；没丢成是因为仓库恰好把 bit 入库，不是流程保证 ⇒ 规矩见 `report/BUILD.md` §7） |
| **#19** | 再加 R24 的厂商发送仲裁修复（ISSUES #37：`||`→`&&` + `arp_pend` 记账位） | **WNS +0.598 / WHS +0.043 / WPWS +0.264 / 0 失败端点(23424) / Slice LUT 7185(13.51%) / Reg 5802(5.45%) / BRAM 90.5(64.64%) / Dynamic 2.184 W（与 #18 完全相同）/ 12503 根可布线网全布通、0 路由错误 / methodology 0 CRITICAL**，L1 **40/40** ⇒ **采纳，明早默认下这一块**（md5 `545a27a1…`，**bit/xsa/elf + 8 份报告成套拷进** `build/frozen_r19_arb/`；回退链 `frozen_r17_cdc/11998af8` → `frozen_r13/0f46ec91`） |

`cdc.rpt` 在 #17 与 #18 之间**逐行相同（只有时间戳差异）**，而且整份报告里搜不到 `abort`、
也搜不到 `eth_link`/`src_sel` 这类信号名 ⇒ 它的粒度是"时钟对 + 端点数"，**不能当逐信号的凭据**。
这一改的凭据只有读代码 + 台架相位扫描（30/30）。这条自我限制也写进了 ISSUES #36。

L1 当前状态：**41/41**（`sim/results/regression_v79_r26.txt`，新增 `tb_v794_osd_glyph` 的 256 码点差分；
上一版 r25 是 40/40，r24 那次是 **39/1**，红的正是 `tb_ku5p_tx_arb` 的 V 组 —— 它抓到 `arp_tx_en` 高了两拍，见 ISSUES #37）。
| **#21** | #19 + **ISSUES #38 收包链上顶层**（`gmii_rx_mac` 自算 FCS-32 + `udp_rx_parser` 端口过滤，`p_good` 接真值） | **WNS +0.770 / WHS +0.027 / 0 失败端点(23615) / Slice LUT 7452(14.01%) / Reg 5906 / BRAM 90.5(64.64%，没涨) / Dynamic 2.183 W / 12861 根全布通 0 错误 / methodology 0 CRITICAL / cdc Critical 行 4（同基线，不新增）**，L1 **43/43** ⇒ **采纳，当时默认下这一块**（后被 #22 取代，见下一行；md5 `f39e2e78`，bit/xsa/elf + 8 份报告成套在 `build/frozen_r21_rx/`）。**结构性观测**：最差路径仍是同一条 OSD 链，级数 27→**26**、CARRY4 10→**9**（R25 那次并行 `case` 的账面效果，在 #20 单次构建里证明不了的东西，这次由报告格式相同的两份量出来了）；WNS 的绝对值依旧落在轮次噪声里，不当收益报。 |
| **#22** | #21 + **P0-C ③ 参数集中化**（`system_top` 里 512/300/基址/端口从两处字面量收成一串 localparam；**值一个没改**） | **WNS +0.566 / WHS +0.044 / 0 失败端点(23612) / Slice LUT 7396(13.90%) / Reg 5903 / BRAM 90.5(64.64%) / Dynamic 2.180 W / 12863 根全布通 0 错误 / methodology 0 CRIT / cdc Critical 行 4（同基线）**，L1 43/43 ⇒ **采纳为当前默认**（md5 `43b76e15`，成套含 bit 在 `build/frozen_r22_param/`）。**这一版顺带量到了噪声本身**：与 #21 逻辑完全等价，却 LUT −56、WNS −0.204 ns、bit 哈希不同 ⇒ 我原来写的中性判据"bit 逐字节相同"是**错的判据**，正确的三条是源码 diff 只有别名替换 + L1 全量 + 门禁全绿 |
| **#23** | #22 + **去掉挡在 PS 片源前面的红色占位**（ISSUES #47：`bram_or_hold` 原来只看粘性的 `eth_link_pix`，网线拔掉 ⇒ 整块显存涂成 `16'hF800` ⇒ `FILL`/SD 回放在屏幕上不可达；改成 `eth_link_pix \| ps_src_seen`，`ps_src_seen` 由像素域已有的 `pub_consume` 置位，不新增跨域） | **WNS +0.740 / WHS +0.042 / 0 失败端点(23613) / Slice LUT 7403(13.92%) / Reg 5904 / BRAM 90.5(64.64%，没涨) / Dynamic 2.178 W / 0 布线错误 / methodology 0 CRIT / cdc Critical 行 4（同基线）**，L1 **43/43**（含唯一例化顶层的 `tb_v6_vblank_copy`）⇒ **采纳为当前默认**（md5 `18443ffd`，bit/xsa/elf + 7 份报告成套在 `build/frozen_r23_srcseen/`；MANIFEST 里写清"演 SD 这一幕前网线必须已经拔着"与为什么不收 `util_hier.rpt`）。**结构增量与意图一致**：端点 +1 = 新那一个触发器、LUT +7、BRAM/功耗不动；WNS 的绝对差仍当噪声看。**板级**：用户眼睛确认屏幕看到 SD 卡视频画面（左原图 / 右同一帧旋转+缩放），同一轮 PS 侧 62 s 抓包 19 个"100 帧窗口"全 29.999 fps（最低 29.495，原始件 board/evidence_r29/play_on_build23.txt）⇒ P1 板级完整通过 |
| **#24**（**不采纳**，被 #25 取代） | #23 + **片源仲裁第一版**（新增 `src/rtl/util/src_arb.v`：`eth_mode` 从 3FF 后的粘性命 `eth_link` 换成 `owner_eth`，只在两个搬运机都空闲时换手、往 PS 方向带 20 ms 滞回；`u_aw.frame_busy` 从悬空改成互锁输入；`pub_consume` 换成新的"活着"位） | **WNS +0.572 / WHS +0.033 / 0 失败端点(23682) / Slice LUT 7454(14.01%) / Reg 5942 / BRAM 90.5(64.64%) / Dynamic 2.164 W / 0 布线错误 / methodology 0 CRIT / cdc Critical 行 3（比基线 4 少一条，原因未查证，门禁只判"不新增"）**，L1 **44/44**（新增 `tb_v796_src_arb`）⇒ **门禁全绿但板级判据红**：插着线、没推流时 PS 片源确实上屏了（FILL 色块 + SD 回放，这是 #23 做不到的），**但"停流后自动交回 SD"没发生** —— 画面钉在最后一帧、`STALL=9999`。根因是喂仲裁的那一位在说谎（RTL8211 断链时把 RXC 拉到 ≈2.5 MHz 而不是停掉 ⇒ `stall_ms` 慢 48 倍 ⇒ `stall_ms<200` 一直为真），不是换手规则错。⇒ 当前默认保持 **#23**，修法（把"时基可不可信"做成仲裁的输入 `eth_tb_ok`）与验证见 #25 |
| **#25**（候选默认，**板级最后一跳待眼睛**） | #24 + **让仲裁先确认"判据可不可信"**：`src_arb` 多一个输入 `eth_tb_ok`（= `!(hb_slow \|\| hb_gone)`，模块内 `eth_wanted = eth_live & eth_tb_ok`）；`system_top` 退回"只取现成信号、不做判断"；`pl_video_top` 的像素域不再复制判据，改成同步**仲裁结果** `owner_eth` 给 `pub_consume`；第一版为仲裁新加的 `link_monitor.lm_live` / `link_live` 端口**整体撤销**（快照那一位没动 ⇒ PS 读回的语义不变）。固件侧另带 ISSUES #50 的两条缓解 ⇒ elf 与 #24 不同 | **WNS +0.593 / WHS +0.047 / 0 失败端点(23674，比 #24 少 8 = 撤掉两处 3FF) / Slice LUT 7475(14.05%) / Reg 5936 / BRAM 90.5(64.64%) / Dynamic 2.150 W / 0 布线错误 / methodology 0 CRIT / cdc Critical 行 3**，L1 **44/44**（构建之后重跑：`sim/results/regression_v79_r33.txt`）；`tb_v796_src_arb` 涨到 23 条，新增 E 段就是那个板级错的复现（`eth_live` 恒 1、只落 `eth_tb_ok` ⇒ 必须让位；默认参数实例在 20 ms 之后也必须让位；时基恢复 ⇒ 立刻抢回）⇒ 成套冻在 `build/frozen_r25_arbfix/`（bit `ad4aa31c`）。**还差两条眼睛的判据**（停流自动交回、交接不闪屏），确认之前默认保持 #23 |
| **#20**（实验，**不采纳**） | #19 + `osd_overlay.glyph_idx` 串行区间比较 → 并行 `case` | **WNS +0.462 / WHS +0.066 / 0 失败端点(23424) / Slice LUT 7100(13.35%，省 85) / Reg 5802 / BRAM 90.5(64.64%) / Dynamic 2.182 W / 0 布线错误 / methodology 0 CRITICAL**，L1 41/41 ⇒ 门禁全绿但**最差路径仍是同一条 OSD 链、还是 27 级（CARRY4 10→9）** ⇒ WNS 那 0.136 ns 落在本设计实测过的轮次噪声里，**不能据一次构建说时序变好或变坏** ⇒ 明早默认保持 #19；RTL 改动保留（等价 + 省 LUT + hold 更好），产物与完整推理成套存档 `build/exp_r20_glyph/` |

`cdc.rpt` 在 #18 与 #19 之间**结构不变**：行、分类、时钟对都一样，只有 `sys_clk↔eth_rxc` 那一行
的端点数 1859→1861（+2，与"仲裁多一级寄存"一致）⇒ 又一次说明它只能看趋势、不能当逐信号的凭据。

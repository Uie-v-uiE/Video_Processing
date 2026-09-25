# 硬件优化日志（时序 / 布局 / 功耗；2026-09-21 增补第四版数据通路修复）

工程：Video_Processing（v3）· Zynq7020 以太网视频 + 右屏无极缩放  
工具：Vivado / Vitis 2025.2.1  
仓库：`D:\Xilinx\Prj\pro\Video_Processing`

---

## 2026-09-18 · 优化前基线

缩放方向已改为「原本=最大 → 缩小循环」，功能上板 OK。

| 时钟域 | WNS | 结论 |
|--------|-----|------|
| clk_fpga_0 | +2.077 | MET |
| eth_rxc | +0.214 | MET（余量紧） |
| sys_clk | +14.897 | MET |
| eth_rxc → clkout0_1 | **−6.748** | FAIL（假跨钟） |

根因：
1. XDC 异步时钟组未含 MMCM 生成钟  
2. icmp `sync_fifo` 异步复位 → 寄存器堆，125M 域路径差  

---

## 2026-09-18 · 优化措施

### 约束 `src/constraints/rk_zynq7020.xdc`

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks eth_rxc] \
  -group [get_clocks -quiet clk_fpga_0] \
  -group [get_clocks -include_generated_clocks sys_clk]
```

跨钟均经 2FF 或 Gray FIFO，不做 setup 分析。Bitstream `COMPRESS TRUE`。

### RTL

| 措施 | 文件 |
|------|------|
| rd_addr 移位加法 + 打拍 | `pl_video_top.v` |
| sideband 与 mapper/proc 延迟对齐 | 同上 |
| CDC `ASYNC_REG` | ze*/ef*/fs*/vt* |
| FIFO 存储去异步复位 + `ram_style=block` | `sync_fifo.v`, `dc_fifo.v` |

### 上位机 / 路径

- `src/host/*`：定时节拍、FFmpeg 查找、ZOOM 串口  
- bat 改为 `src\host`，Python 走 PATH  

---

## 2026-09-18 · 优化后实测

**时序：`All user specified timing constraints are met`**

| 时钟 | WNS |
|------|-----|
| clk_fpga_0 | +0.865 |
| eth_rxc | +0.111 |
| sys_clk | +14.445 |
| clk_pix (clkout0_1) | +1.882 |

| 指标 | 数值 |
|------|------|
| 总功耗 | 2.240 W（动态 2.071 + 静态 0.169） |
| 结温 | 50.8 °C |
| LUT | 10621（19.96%） |
| FF | 20253（19.03%） |
| BRAM Tile | 83（59.29%） |
| DSP | 13（5.91%） |
| bit | ~2.1 MB（COMPRESS） |

产物：`build/system.bit`、`build/system.xsa`（21:40 前后）。

---

## 验证

- [x] `tb_zoom_mapper` PASS  
- [x] Vivado synth/impl/bitstream  
- [x] 全局时序 MET  
- [x] 右屏缩放上板（用户确认）  
- [ ] 优化后 bit 建议再回归：缩放 + 效果 + ETH 推流 + 串口  

---

## 后续可选

- 双线性缩放（`frac_x/frac_y` 已预留）  
- 消隐期写帧缓，减轻拖影  
- eth_rxc 域余量仅约 0.1 ns，加逻辑时注意 FIFO/路径  
- 功耗报告置信度 Low，仅作相对参考  

---

## 变更文件索引

| 文件 | 变更 |
|------|------|
| `src/constraints/rk_zynq7020.xdc` | 异步时钟组、COMPRESS |
| `src/rtl/top/pl_video_top.v` | 缩放通路、rd_addr 打拍、双窗时分 FB |
| `src/rtl/process/zoom/*` | 无极缩放 |
| `src/rtl/eth/sync_fifo.v` `dc_fifo.v` | 自写 FIFO、BRAM 友好 |
| `src/host/*` | 上位机 |
| `report/*` | 全量按 v3 重写 |

---

## 2026-09-21 · 第四版 V6.x：入包链零丢字（数据通路优化，非时序优化）

### 症状
右屏红块移动处**拖影**、黄块一直呈撕裂态、有固定黑横纹；静止画面也撕裂；
与上位机限速（0.2 / 2 / 8 / 15 MB/s）几乎无关 ⇒ 不是流量问题。

### 措施（单变量，逐个被测量证伪或证实）
| # | 变更 | 判据 | 结论 |
|---|------|------|------|
| V6.0 | `frame_reasm`：commit 需 `rows_hit==IMG_H` **且** 累计 `FRAME_BYTES`；修 `p_valid&&p_eof` 同拍 off-by-one；`stat_bad` 每帧只加一次 | `sim/tb_v6_cover_gate.v` | 空洞帧不再被 commit（停流后冻结帧干净） |
| V6.0 | 拷贝窗口收紧到「仅 V-blank + 64 像素尾部保护」+ 提交锁在窗口一开即启动拷贝 | `sim/tb_v6_vblank_copy.v`、`tb_v5_lock.v` | 拷贝预算从 0.31 提到 0.571 拍/周期可用 |
| V6.0 | `axi_frame_writer_gated` 在途 `MAX_OUT` 2→4、`SK=6` | `sim/tb_v5_gated.v`、`tb_v5_copy.v` | 一帧拷贝能收进一个消隐窗口 |
| V6.1 | 入包 CDC 读侧「每 3 拍 1 条」→ **每拍 1 条**；flush 给数据让路 | 板级回读空洞比例 | 黑横纹主因之一（66 MB/s < 线速 125 MB/s 的确定性丢字） |
| V6.1 | 分包 1396 → **1392 B**（8 的倍数） | 半字掩码 `1010/0101` 消失 | 确定性错位消除 |
| V6.2 | CDC 512→8192（BRAM）+ 打包器满时反压；**打包器 FIFO 不可加深**（`FW=11` 触发 DRC UTLZ-1） | 板级 frameid 命中率 | 仿真 100%，**板上无改善** ⇒ 方向错（深度 ≠ 速率） |
| **V6.3** | `axi_frame_saver64` 写通道流水化：AW/W 同拍挂出、各保持到被接收，`OST=8` 在途，B 只回收计数且不回绕 | 包内相位丢字率 + 16bit 粒度 + 命中率 | **15/30/60 fps 全部 100.0%**，各带 0.0%，半字错帧 0/76800 |

| V6.4 | `axi_frame_saver64`：`WSTRB` 由恒 `0xFF` 改成**按 16bit lane 的掩码**（`cur_keep→q_keep→keep_r`） | 1396 分包的板级回读 + `tb_v6_ingress_integrity +FULL +MISALIGN` | 修掉「同一字被相邻两包推送时后一次覆盖前一次」⇒ 屏上均匀散布的黑点（1396 实测每帧 111 处 4 字节洞）；之后入包链对分包长度免疫 |

### 结果
- 时序不降反升：WNS +0.373 → **+0.675 ns**（0 违例）；Registers 49.52%、BRAM 138.5/140。
- 入包写吞吐上限：≈20 MB/s → ≈400 MB/s（握手决定），对 15 MB/s 有 26× 余量。
- 回归：28/28 PASS（v6.4 在同一份仓库目录里重跑，`sim/results/regression_v6.txt`）。
- V6.4 板级验收：1396 B 分包下两个 bank 命中率 **100.0%**、每帧空洞 **0**（v6.3 同条件下是 99.9% / 222 个 16bit 字）。

### 判据方法（本版新增，可复用）
`src/host/video_sender.mjs --test frameid` + `src/host/ddr_verify.mjs --frameid`
+ `src/host/ddr_stale.mjs`（包内相位 / 游程长度 / 粒度三维展开），一条命令
`node src/host/measure_v63.mjs --fps N`。**必须发完再回读**。详见 `skill/frameid_loss_signature.md`。

### 本版变更文件
`src/rtl/eth/{frame_reasm,eth_udp_video_top,axi_frame_saver64}.v`
`src/rtl/axi/{axi_frame_writer_gated,axi_frame_writer64}.v`
`src/rtl/video/{frame_buffer_w64,frame_commit_lock}.v`
`src/rtl/top/{pl_video_top,system_top}.v`
`src/host/*`（Node 工具集）、`sim/tb_v5*.v`、`sim/tb_v6*.v`、`sim/run_sim.tcl`、
`sim/tb_eth_video.v`（修好第三版就失效的参数引用）、
`build/tcl/{build_v6,program_pl,ps_jtag_boot,set_src}.tcl`、`build/*.{bit,xsa,rpt}`、
`report/V6_ROOT_CAUSE.md`、`report/V6_BOARD_MEASUREMENT.md`、`report/AI_COLLABORATION.md`、
`skill/zynq-video-rtl-debug/*`、`skill/frameid_loss_signature.md`

---

## 2026-09-26 · r63 双线性读口的代价，与全设计最紧那两条路径的机制

这一节只放**从报告里抄出来的数**（每一份都点名出处），以及"没量到的东西"明确说不量到。

### 1. 双线性换读口到底花了多少（r62 `build/frozen_r62_geom/` vs r63b `build/evidence_r63b/`）
| 资源 | r62 | r63b | 差 | 口径 |
|---|---|---|---|---|
| Slice LUT | 12958 (24.36 %) | 14116 (26.53 %) | +1158 | `utilization.rpt` |
| Slice 寄存器 | 9491 (8.92 %) | 9856 (9.26 %) | +365 | 同上 |
| Block RAM tile | 96 (68.57 %) | 97 (69.29 %) | **+1** | 同上；RAMB18 6→8 |
| DSP48 | 14 (6.36 %) | 20 (9.09 %) | **+6** | 同上（插值乘法第一次进 DSP） |
| 端点总数 | 33896 | 34561 | +665 | `timing_summary.rpt` |
| 估算功耗 Total / Dynamic | 2.378 / 2.201 W | 2.381 / 2.204 W | +0.003 / +0.003 W | `power.rpt`，**Vivado 默认翻转率** |

要点（可以直接对外讲的那句）：**双线性没有引入任何新的高频时钟域、没有加第二个帧缓存读口** ——
读口仍挂在 50 MHz 像素时钟上，每个源像素用它本来就空着的 4 个拍；
代价换成 +6 个 DSP48、+1158 LUT、1 块 BRAM tile，估算功耗在同一档（+0.13 %）。
背景：2026-09-23 那三次失败的做法是"每像素周期 5 次读 ⇒ 必须 250 MHz ⇒ 5 选 1 地址 mux ⇒ mux→RAMB36 地址脚"，
build#14/#15/#16 分别 −1.277 / −0.485 / −0.327 ⇒ 那条路被 `build/micro_rd/` 三 MODE 探针量死后放弃（#76）。
**不声称**的部分：插值"看起来更好"属眼睛，`board/README.md` 第 29 行是留给用户的判据，本文不代答。

### 2. 全设计最紧的两条路径，现在都有机制（不再只有数字）
`timing_summary.rpt` 里 WNS 与 WHS 同时由 `eth_rxc`（RGMII 收 125 MHz）那一组决定：
* **WHS 的机制**：起点 `u_iddr_rx_ctl`（ILOGIC，走 **BUFIO**，SCD 3.171 ns）→ 1 级 LUT4 →
  终点 `u_rx_mac/m_good_reg`（fabric，走 **BUFG**，DCD 4.854 ns）⇒ **时钟路径偏斜 +1.616 ns**，
  而整条数据路径只有 1.855 ns（预算 8.000 ns）。
  ⇒ 同一份 RTL 两次构建：r62 WHS +0.001、r63b +0.052 —— 这个抖动不是设计变化，是工具在两条时钟树之间掷硬币。
* **已排除的三种"便宜修法"**（写清楚免得重复走）：`set_false_path`（两侧同频同相，是真实同步路径，判假路径=允许采错拍）；
  只搬走 `m_good` 一个计数器（该 IDDR 输出 `fo=22`，机制不变，下一条最差路径顶上）；
  让 fabric 吃 BUFIO（7 系列 BUFIO 只驱动 ILOGIC/OSERDES，做不到）。
* **今天采用的那条（r63c 在验）**：`set_clock_uncertainty -hold 0.500 [get_clocks eth_rxc]`
  —— 与"放松判据"方向相反：给 hold **加**要求，逼工具插延迟把余量做成设计值；
  数据路径还有 ~6 ns setup 余量，垫 0.5 ns 负担得起（`-hold` 不参与 setup 检查）。
  验收：WHS 应从 +0.05 量级升到 ≥ +0.4，且 WNS 不被它压低。凭据 `build/r63c_gates.txt`。
* **仍待用户在场的那条**：把 RGMII RX 的 IDDR 也改用 BUFG + IDELAY 对齐（发射/接收同一棵树），
  它会**移动采样时刻** ⇒ 必须重调 IDELAY 并做 1000M 在线验证（#57）。

### 3. 两处"空转"的资源，量出来了但还没动（各自的正确顺序）
* 死模块 `src/rtl/process/bilin/{fb_rd5x,tap_sched}.v`：`sim/*.v` 与 `src/rtl/**` 里已无任何活引用
  （只在历史日志中出现）⇒ 建议移入 `docs/archive/`，出构建 glob。
  ⚠ 曾猜"它们制造了综合警告噪声"，**量过是错的**：整份 `r63c_build.log` 里 `Synth 8-3332` 只有 7 条，
  全是某个 FSM 的不可达状态，与这两个模块无关 ⇒ 移它们的收益只剩"少一个会让后人误以为必须有 250 MHz 快域的入口"。
* ~~250 MHz 时钟树空转~~ —— **这条已经作废，而且作废得有名有据**（2026-09-26 自查，#79 之后的第二次"先看分布再改尺子"）。
  我写的"`fabric` 负载 0 ⇒ 可去掉一路 MMCM 输出 + 一只 BUFG"读的是 `clock_util.rpt` 第 6 张表 g4 那一行的**第一个 0**：
  那张表的列是 `Slice Loads | IO Loads | Clocking Loads | GT Loads`，g4（`clkout1_1` = `u_pl/u_clk/u_bufg_5x/O → clk_pix5x`）
  真实读数是 **Slice Loads 0 / IO Loads 8**。0 的含义是"没有触发器吃它"，不是"没人吃它"。
  那 8 只 IO 负载是谁：`src/rtl/hdmi/tmds_serializer.v:31` 与 `:69` 两处 `OSERDESE2 .CLK(clk_pix5x)`（MASTER + SLAVE 级联），
  被 `rgb2dvi.v:35/39/43/49` 的**四条通道**各实例化一次 ⇒ 4 × 2 = 8，与报告里的 8 正好对上（数字与出处互相咬合，不是猜的）。
  ⇒ **砍掉这棵树就是把 HDMI 输出砍掉**。T3 这一步到此为止，不再排"深度优化"的队。
  留一条通用教训：**看到"负载 0"先认列名**。7 系列的 OSERDESE2/IODELAY 记在 IO Loads 栏，
  只看 Registers/Slice 一栏会把"只用在建构输出上"的时钟误判成空转。

### 功耗拆到哪去了（r62 → r63b/r63c，都是 `power.rpt` 里同一张按类别的表，同一工具版本）
| 类别 | r62 | r63c | 差 |
|---|---|---|---|
| Dynamic 合计 | 2.201 W | 2.205 W | +4 mW |
| Clocks（10 条网络）| 0.047 | 0.048 | +1 mW |
| Signals | 0.041（19299 根）| 0.048（**21445** 根）| +7 mW |
| Block RAM（tile 96→97）| 0.176 | **0.167** | **−9 mW** |
| DSPs（14→20 个）| 0.007 | 0.007 | 0 |
| Static | 0.177 | 0.178 | +1 mW |
读法（不要过度解释）：**新增的 2146 根网络把信号功耗推高约 7 mW，而帧缓存侧反而省了约 9 mW**
（读口形状换了：每拍一次读、地址由行偏移 + 列 +1 的两级 mux 出来，不再像旧路径那样在末列/末行来回跳），
DSP 从 14 个增加到 20 个但功耗不变（这几个乘法器只在像素节拍的少数拍上翻转）。
上表各项相加不等于合计（差约 4 mW 落在 `Logic`/其余类别，本表没抄那一行）⇒
**引用这张表时只说"合计 +4 mW、BRAM 侧反而省"，不要说"各项已经对平"**。
口径提醒：三份都是 Vivado 默认翻转率估算（没有实测向量），所以它适合回答"新逻辑大概值多少"，
不适合当"实测功耗"对外念；实测要上板量电源轨，那条今天没做（记在这儿，别到提交材料里被写成实测）。

## 4. 「这次绿了」不算答案：这三次的 WNS 到底是谁定的（r63b / r63c / r64b，2026-09-26）

门禁的 WNS 抄的是 `timing_summary.rpt` 里 Design Timing Summary 的第一行 = **所有约束组的最小值**，
而组内最差路径分属两个互不相干的时钟域 ⇒ 每换一次构建就像换一次裁判。逐份报告抄出来的数
（三份都在 `build/evidence_*/timing_summary.rpt`，同一工具版本、同一套源码树之外的东西都没变）：

| 构建 | 门禁 WNS | eth_rxc（125 MHz / 8 ns）组内最差 | clkout0_1（50 MHz 像素 / 20 ns）组内最差 | clk_fpga_0（100 MHz）组内最差 |
|---|---|---|---|---|
| r63b | 0.918 | **0.918** `u_eth/u_cdc/wbin_reg[2]/C → u_eth/u_cdc/mem_reg_6/ENARDEN`，8 级，route 60.2 % | 1.306 `u_pl/u_pipe/xd_reg[7][4] → u_pl/u_osd/g_reg[6]/D`，27 级，route 65.3 % | 1.906 |
| r63c | 0.807 | 0.912 `u_lm/ms32_reg[8] → u_lm/gap_min_reg[2]/CE`，11 级，route 63.8 % | **0.807** 同一条 OSD 字形路径，27 级，route 66.6 % | 1.621 |
| r64b | 0.314 | **0.314** `u_lm/ms32_reg[3] → u_lm/gap_min_reg[1]/CE`，14 级（CARRY4=10 LUT4=2 LUT5=2），route 63.3 % | 0.834 同一条 OSD 字形路径 | 2.323 |

四条读法：
1. **摆动不是"某个模块变差了"，是两个候选轮流当裁判。** 一条在 125 MHz 的 ETH 收包域，一条在 50 MHz 的像素 OSD 域，
   两者谁小谁就是门禁上那个数。所以"这次 WNS 掉了 0.5 ns"这句话单独讲没有任何指向 —— 必须先问"掉的是哪一组"。
2. **两条都是布线主导（60–67 %），不是算术主导。** `u_lm` 那条：`gap_raw = ms32 − ms_last32`（32 位借位链）
   → 饱和判 `> 0xFFFF`（再一次 32 位比较）→ `gap_new < gap_min`（16 位又一条借位链），三段串在**同一拍**里，
   只为一个**每帧才用一次**的统计量（`link_monitor.v:101-103,150`）。OSD 那条 27 级是 R25 并行化的结果，
   数据 18.6–19.1 ns 里路由占 12.2–12.7 ns。
3. **r64b 相对 r63c 只多了一根 `gpio_o[19] → 三级同步 → bilin_en`（像素域的一个输入），ETH 域一行 RTL 没动，
   却把 eth_rxc 组从 0.912 拉到 0.314。** 这就是 #80 说的"掷硬币"的**幅度**：±0.6 ns 是全局拥挤换的，
   不是本地改动的函数。⇒ "改了 A 组、B 组的数也跟着动"既不是异常，也不是"没问题"，而是要如实记下的成本。
4. **不结论（守住口径）**：0.314 仍 ≥ 0、失败端点 0，门禁 PASS；这一节的产出是"下一刀往哪看"，不是"必须现在动"。
   真要动，两把刀：
   * (a) 让 `link_monitor` 的 gap 统计不再在一拍里做"减法 + 饱和 + 比较"。⚠ 它是**仪表**：任何流水化都要先证明
     `frame_done` 与 `ms_tick` 同拍时不会系统性少 1 ms（30 fps 源的帧周期 ≈ 33 个 ms 刻度，与 1 ms 分频**可能锁相**，
     不是"十万分之一"的巧合可以糊过去的量），而 R08–R10 的拔线/gapclr 对账就是它现有的凭据，不能悄悄换掉。
   * (b) 零 RTL 改动的物理刀：**布线后物理综合**没开 —— 凭据是 `vivado_system/zynq_video_sys.runs/impl_1/`
     里只有 `phys_opt_design.pb`（布局后那一次），`runme.log` 里 `Command: phys_opt_design` 只出现一次。
     高扇出网络（这条路径上 `gap_min[15]_i_4_n_0` fo=96、`_i_3_n_0` fo=17）正是它的目标。

## 5. 正在验的是 (b)：布线后 phys_opt（r65，2026-09-26 夜，数字**还没进来**）
* 改动只在构建流程：`build/tcl/build_system_axigpio.tcl` 在 `launch_runs impl_1` 之前按环境变量 `IMPL_PRPO=1`
  打开 `STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED` + 指令 `AggressiveExplore`；**不设这个变量就是今天的默认流程**，
  所以对照不需要重新构建 r64b（`build/evidence_r64b/` 已在案）。
* 判据（与 r64b 同源码、同工具版本，四件事一起看）：① eth_rxc 组 WNS（0.314 → ?）；② 失败端点仍 0；
  ③ WHS 那一族（0.049 / 0.051 / 0.052）不许被压低；④ `power.rpt` 的 Dynamic（r64b 2.205 W）—— 复制高扇出驱动会加功耗，
  涨就报涨了多少，不许只报时序收益。
* 采纳规则：eth_rxc 与 clkout0_1 两组**同时**不退步才把默认打开；任一组退步就保留脚本、默认关闭，
  并把测到的小结写回这一节（包括"开了反而更差"这种答案）。

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
| `docs/*.md` | 全量按 v3 重写 |

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
`src/host/video_sender.mjs --test frameid` + `ddr_verify.mjs --frameid`
+ `ddr_stale.mjs`（包内相位 / 游程长度 / 粒度三维展开），一条命令
`node measure_v63.mjs --fps N`。**必须发完再回读**。详见 `skill/frameid_loss_signature.md`。

### 本版变更文件
`src/rtl/eth/{frame_reasm,eth_udp_video_top,axi_frame_saver64}.v`
`src/rtl/axi/{axi_frame_writer_gated,axi_frame_writer64}.v`
`src/rtl/video/{frame_buffer_w64,frame_commit_lock}.v`
`src/rtl/top/{pl_video_top,system_top}.v`
`src/host/*`（Node 工具集）、`sim/tb_v5*.v`、`sim/tb_v6*.v`、`sim/run_sim.tcl`、
`sim/tb_eth_video.v`（修好第三版就失效的参数引用）、
`build/tcl/{build_v6,program_pl,ps_jtag_boot,set_src}.tcl`、`build/*.{bit,xsa,rpt}`、
`docs/log/V6_ROOT_CAUSE.md`、`docs/log/V6_BOARD_MEASUREMENT.md`、`docs/AI_COLLABORATION.md`、
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

## 6. 把 §4 的教训装进尺子里：门禁现在会**点名** WNS 归哪一组（`build/gates.sh` 第 14 块，记录用不判红）
* 上表仍只判 Design Timing Summary 那一个数（阈值一个字没改）；新增的块把每个 **From==To** 自身时钟组的
  最差 setup/hold 原样抄出来，并在等于门禁 WNS 的那一行后面标 `← 门禁 WNS 就是这一组`。
* **这一块的凭据是"三次构建换裁判"这个已知事实**（检查器自己也要有反例，见 `gates_cdc_test.sh` 同一口径）：
  拿三份归档报告跑，读数必须与 §4 手工抄的逐条一致，且 `←` 必须落在**不同**的组上——
  ```
  r64b  eth_rxc 0.314 ← / clkout0_1 0.834 / clk_fpga_0 2.323        （跑过，一致）
  r63c  clkout0_1 0.807 ← / eth_rxc 0.912 / clk_fpga_0 1.621        （跑过：裁判是**像素组**，证明标记不是写死在 eth 上）
  r63b  eth_rxc 0.918 ← / clkout0_1 1.306 / clk_fpga_0 1.906        （跑过，一致）
  ```
  读不到分组行时打印 `n/a … 这一项未验`，不把空表当通过；跨时钟组的路径（`From!=To`）不在这一块里，
  真由跨组决定 WNS 时会打 `⚠ 门禁 WNS 不来自任何 From==To 组`。
* 顺带被这一块**否掉的第二个假优化**：分组表里 `clkout2`（200 MHz）显示 NA，看着像"又一棵空转的树"。
  查 `clock_util.rpt` 第 5 张表 g6：驱动是 `u_idelay_clkgen/u_bufg_200/O → idelay_clk`，**负载 1**，
  它是 RGMII 那条 IDELAY 的参考时钟（`clk_gen.v:27` 注释 `200 MHz IDELAY ref`）—— 动它就是动采样基准。
  （`pl_video_top.v:149` 那个 `clk_200m_unused` 是 `u_pl/u_clk` 里的另一路，工具已经把没负载的 BUFG 剪掉了：
  时钟树清单里只有 g0~g7 这 8 棵，没有第二棵 200 MHz。）

## 7. §5 的采纳规则当时写成过一个脚本（自检已过、两向都有牙；脚本本身是阶段性的，已退役）

> **2026-09-27 更新（#66 的 A 类清理）**：那个一次性脚本已经删掉，但**规则本身仍然有效**，
> 而且比脚本更长：采纳 = `eth_rxc` 与 `clkout0_1` 两组都不退 + 至少一组变好 + 失败端点 0，
> 并且 Dynamic 若涨必须点名。三对历史归档（r63b↔r63c、r64b↔r63c、r64b↔r64b）当年就是按这条判的，
> 结论还在下面这张表里；要重跑就照本节的手法现写一次，别去找那个文件名。

* 为什么不让"看完报告自己判断"：§5 的规则是"两个竞争组**同时**不退步 + 至少一组真的变好"，
  而人读两份 `timing_summary` 最容易犯的正是 §4 那个错——只念 Design Timing Summary 那一个数。
  脚本不重新解析 Vivado 报告，只吃 `gates.sh` 的输出（含 §6 新加的分组块）⇒ **解析器只有一份**，不会与门禁漂移。
* 判据三合一：① `eth_rxc`、`clkout0_1` 两组 setup 都不许退步（容差 0.001 ns）；② 至少一组变好，否则
  "多跑的布线后综合是白花构建时间"也判不采纳；③ 新构建失败端点必须 0。WHS/功耗**点名不判红**。
* **它自己的反例（两次归档构建对跑，结论必须相反）**：
  ```
  新=r63b 对照=r63c：eth 0.912→0.918、clkout0_1 0.807→1.306 两组都变好 ⇒ AB: ADOPT      ✅
  新=r64b 对照=r63c：eth 0.912→0.314 退步                                              ⇒ AB: REFUSE ✅
  ```
  第二例证明"Design WNS 从 0.807 涨到…"这种单一数字骗不了它——它按组判。
* 诚实记录一次**自检逼出来的假绿**：第一版把 `say` 行里表头名字的空格数算错了（`WNS (ns)` 值在 $3、
  `Slice LUT / 占比` 在 $5、`失败 setup 端点` 在 $4），而且忘了 `say` 的行首有两个空格 ⇒
  `index($0,p)==1` 永不成立 ⇒ WNS/Dynamic/失败端点**五格读成空**，而空值在 awk 里就是 0 ⇒
  它照样打出一条结论（那一轮打的是 REFUSE，纯属两组数据碰巧对上了）。
  现在 `AB_EMPTY` 这道闸在打印表格之前逐格验非空，读成空就 `exit 4`，**不拿空值判"没退步"**。
  这正是"判据不许靠 X / 空集合通过"在工具层的落实。
* 补第三支（跑过的三分支，退出码当场核）：**自己对自己** `r64b vs r64b` ⇒ 两组都不退步、也都没变好 ⇒
  `AB: REFUSE（无收益）`。这一支原来从没被执行过（"没收益"这条分支若不测，就等于"多花一次构建时间也会被当成采纳"）。
  同时补上**结论必须带退出码**：`ADOPT` 才 0，两种 `REFUSE` 都是 1 —— 否则一句 `| tail` 就能把"别开默认"读成"过了"
  （同一个坑在门禁 rc 上踩过一次）。三分支实测：`rc=0 / ADOPT`、`rc=1 / REFUSE（保持默认关）`、`rc=1 / REFUSE（无收益）`。

## 8. r65 的结果：**没收益**，而且它顺手否掉了我自己在 §4 写的一句"掷硬币"（2026-09-26 05:45）
* 这一档**确实开了**（不是空跑）：构建日志 `BUILD_PRPO on AggressiveExplore`、`impl_1` 目录里出现
  `post_route_phys_opt_design.pb`、`runme.log` 里 `Command: phys_opt_design -directive AggressiveExplore`
  是布局后那一条之外的第二次。它自己的话是 `INFO: [Physopt 32-949] No candidate nets found for
  dynamic/static region interface net replication`。
* 结果与 r64b **逐格相同**：分组 setup `eth_rxc 0.314 / clkout0_1 0.834 / clk_fpga_0 2.323`、
  门禁 WNS 0.314、WHS 0.049、Dynamic 2.203 W、LUT 14117/26.54 %、BRAM 97/69.29 %（`build/r65_gates.txt`
  `GATES: ALL PASS`，CDC Critical 3 行不增长）。位流 md5 却不同（`e73db717…` 对 `543f6820…`）。
  ⇒ 采纳脚本判 `AB: REFUSE（无收益）`，**板子保持 r64b 没动**，实验件留在 `build/evidence_r65_notadopted/`
  （`MANIFEST.md5` 里写了 `verdict=REFUSE_no_gain` 与当时的 `git_head`）。
* **要自我更正的那句**：§4 第 3 条我写"r64b 只多一根同步链、ETH 域一行 RTL 没动，eth 组却从 0.912 掉到 0.314
  ⇒ 这是掷硬币"。这次的最小配对（同一份 RTL/约束，只差一个流程开关）显示：**实现结果不自己动**。
  所以 0.912→0.314 不是随机，而是"加了东西之后全局摆放变了"的**确定性后果**；同样地，#80 里
  "同一份 RTL 两次构建 r62 +0.001 / r63b +0.052"那句也站不住 —— r62→r63b 之间隔着双线性读口与那条
  `-hold` 不确定度，**不是同一份 RTL**，那是有因可循的差，不该记在运气账上。
  口径收在这里：只说"这套设计 + 这个流程 + `-jobs 4` + 同一台机器可复现"，不外推到"Vivado 永远确定"。
* 这条结果对优化路线的实际含义：**0.314 这条路径没有物理层的便宜可占**（phys_opt 明确说没有可复制的候选网络）。
  要抬它只剩**逻辑那一刀**：把 `link_monitor` 的"减法 → 饱和 → 比较"拆拍（§4 第 2 条），
  而那一刀的前置条件是我先把仪表口径证清楚（`frame_done` 与 `ms_tick` 同拍不是"十万分之一"，
  两者共享同一时钟根，锁相是可能的）。**#57 的那条 RGMII 结构改法不受影响，仍然是最值钱的一刀，但要用户在场。**

## r83（2026-09-28 深夜）：两刀——一刀有效、一刀无效，都用数说话

| 项 | r81（上一版实装） | r83（本版） | 差 |
|---|---|---|---|
| WNS | −0.062 ns | **−0.192 ns** | 变差 −0.130 |
| TNS / 失败端点 | −0.812 / 28 | −4.242 / 34 | 变差 |
| WHS | +0.056 | +0.050 | 持平 |
| Block RAM Tile | 97.5 / 140（69.64 %） | **95 / 140（67.86 %）** | **省 2.5 块** |

**有效的那一刀（保留）**：`proc_morph` 的两条掩码行缓存原来写成 `reg [0:H_ACTIVE-1] mb0` ——
那是**一根 1024 位的向量**，`mb0[x_in]` 是按位取值，综合器推断不出 RAM（`Synth 8-7186 ... using registers`），
于是两条缓存变成 2×1024 个触发器，外加两个异步读口各一棵 1024:1 的 LUT 树。
改成 `reg mb0 [0:H_ACTIVE-1]`（每元素一格）之后 BRAM 少 2.5 块。
顺手把四处 `ram_style="block"` 改成 `distributed`：那几处读全是异步（组合读出），BRAM 做不到，
旧属性只换来四条 `Synth 8-6849 infeasible` 警告然后自己退回 LUTRAM —— 把话说明白，警告数与实现结果都更可信。

**无效的那一刀（已回滚，r84 里量到确认）**：给 `dc_fifo` 的 `wr_full` 加 `max_fanout=12`，想让综合把高扇出网表复制成
本地缓冲。实测 WNS 从 −0.062 掉到 −0.192、失败端点 28→34，最差路径还是同一族
（`u_cdc/wbin_reg → u_lm/cdc_ep_reg[*]/CE`）。**说明瓶颈不是扇出，是锥体本身**：
14 位加法 → 二进制转格雷 → 14 位等值比较，全在写域一拍里。
回滚之后就是下一行 §r84 那一跑，两刀的贡献确实分开了。

**#105 剩下的两条候选（都还没做，各自都要配判据与一次构建）**
1. 把满判据从"下一拍会不会满"改成"当前已经满"（用寄存过的 `wgray` 而不是 `wgray_n`）——
   锥体里就没有加法器了；代价是必须**留一格余量**（深度按 DEPTH−1 用），否则最后一格会被覆盖。
   这条要新加一条"写满边界不丢字"的判据才能落地。
2. 把 `u_cdc` 的深度从 8192 降下来（它现在是 36 bit × 8192 = 8 块 RAMB36）。
   锥体短 4~5 位、再省 6~7 块 BRAM，但**必须先量出真实吸收需求**：
   写侧 125 MHz、读侧 50 MHz，读只在什么窗口跑 ⇒ 用 `drop_words`/`cdc_ep` 两个计数器在
   板上与台架里各量一次，量完再决定。没量过就改深度，等于拿"零丢包"那句承诺赌。

## r84（2026-09-29 01:13）：回滚那一刀之后，两刀的贡献才真的分开

| 项 | r81（#103 之前） | r83（+#103 +OSD 开关 +morph 一刀 +`max_fanout`） | **r84（= r83 − `max_fanout`）** |
|---|---|---|---|
| WNS | −0.062 ns | −0.192 ns | **−0.094 ns** |
| TNS / 失败 setup 端点 | −0.812 / 28 | −4.242 / 34 | **−0.747 / 16** |
| WHS / WPWS | +0.056 / — | +0.050 / — | **+0.056 / +0.264** |
| Block RAM Tile | 97.5 / 140 | 95 / 140 | 95 / 140（67.86 %） |
| LUT as Logic / as Memory | — | — | 10173 / 4187（19.12 % / 24.06 %） |
| 位流 | — | 2 242 638 B | 2 222 010 B |

三条结论，各自指名出处（`build/timing_summary.rpt` 01:12:48、`build/utilization.rpt`、`build/r84_build_console.txt`）：

1. **归因成立**：撤掉 `dc_fifo` 的 `max_fanout=12` 之后 WNS 从 −0.192 回到 −0.094、失败端点 34→16，
   最差路径还在同一族上 ⇒ 那一刀是**净负贡献**，不是"收益没量出来"。回滚本身也留下一条教训：
   用脚本文本替换做回滚会造出重复声明（`VRFC 10-9364`），改完必须立刻编译一次（提交 df72a82 修的就是它）。
2. **morph 那一刀没有被回滚掩盖**：BRAM 仍是 95 片（省 2.5 块、两条 1024 位向量不再是 2048 个触发器），
   而 WNS 与 r81 的 −0.062 只差 0.032 ns。这一族的量级本来就是"零附近"（learn/30 §82：布局后估计 +0.645、
   布线拉到 −0.062 ⇒ 拥塞不是逻辑深度），所以 0.032 **不记在 morph 头上**，只记"这一轮既没变好也没变坏，
   但失败端点从 28 少到 16"。想把它坐实成"morph 无代价"，需要的是同一棵树连滚两跑做对照，还没做。
3. **#105 仍未收口**：最差路径 `u_eth/u_cdc/wbin_reg[0]/C → u_lm/drop_words_reg[20]/CE`（eth_rxc，8 ns 周期），
   16 个端点全在这一族。上一节那两条结构性候选（"已经满"判据 + 留一格余量、或先量吸收需求再降深度）
   都要**先量再改**，没量过就改 = 拿"零丢包"那句承诺赌。

**为什么 r84 可以带着负 WNS 上板**：r83（−0.192，比它差）已经在板上跑完一整晚并量到了 #112 的 OSD 开关
（`0x000F5000 ↔ 0x001B5000`，bit20 翻转）；今晚要验的两件事（#103 黑线、OSD 开关）都不在这条路径上。
这句话说的是"风险已知"，不是"时序没问题"——门禁第 14 项照旧判红，#105 不收口"全绿"就还差一项。

## r84 之后还能做的（都**还没做**，每一条都要一次构建才敢说收益）

**先把"这一轮的收益长什么样"钉住**：`build/r84_build_console.txt` 里
`Synth 8-6849`（RAM 推断不可行）**0 条**、`Synth 8-7186`（改用寄存器实现）**0 条** ——
把四处 `ram_style="block"` 换成 `distributed` 想要的就是这个：话说明白、警告归零，
而 `Synth 8-6859`（multi-driven）**也是 0**（门禁第 13 项盯的那件事）。
代价写在方法学报告里：`SYNTH-5` 336 条"因时序约束落到分布式 RAM"、`SYNTH-6` 97 条"RAM 时序可能次优"，
`LUT as Memory` 4187（24.06 %）。**这两条计数没有 r83 的同一张表可比（构建会覆盖报告）⇒ 只记录、不归因。**

| 候选 | 出处（现在是警告/事实，不是猜测） | 动它要花什么 |
|---|---|---|
| ~~把 `u_cdc` 的深度降下来~~ **已作废（02:53 量过）** | `build/evidence/r85_cdc_gap0_run.txt`：GMII 线速连灌时 `u_cdc` 峰值占用 **8191/8192（满−1）**、`lost=98544`；限速 15 MB/s 那档只有 **3/8192** 且零丢。⇒ 这 8192 格是**被填满到只差一格**的，它是这条链上唯一的吸收缓冲，降到 1024 会把过载余量砍掉 8 倍，直接危及"116.7 fps 不丢字"那句板上真数 | 不做了（换不到东西）。详见 ISSUES **#120** |
| `dc_fifo` 满判据改"已经满 + 留一格余量"（**#105 现在只剩这一条**） | 最差路径 `u_cdc/wbin_reg[0] → u_lm/drop_words_reg[20]/CE`，eth_rxc 8 ns，16 端点全在这一族；而 #120 量出**满边界真会被踩到**（峰值 = 满−1），所以这条不是纸上功夫 | 一条"写满边界不丢字"的新判据 + 一次构建 |
| `split_display.v:5` 空参数声明 `#()()` | `Synth 8-9397`（只有 SystemVerilog 允许） | 删一对括号；纯语法，风险最低 |
| `split_ctrl.v:53-54` 整型常量位宽 | `Synth 8-9694` invalid size | 看清那两个常量本意再改，可能是真笔误 |
| `src_mode.v:72` 通配 `===` 被替换成 `==` | `Synth 8-589` | 要么写 `==` 要么写明为什么要四态比较 |
| `eth_mdc` 被常量 0 驱动 | `Synth 8-3917`（端口被常量驱动） | 是"这板子没有 MDIO"就注释掉，别留着让下一个人找驱动源 |
| 五个无人例化的遗留件（`line_cache`/`frame_buffer`/`frame_buffer_db`/`axi_frame_writer`/`video_timing_720p`） | 2026-09-29 按"模块名+例化形状"全树 grep；已在各自头部写明"本树无人例化" | 删除要过一遍 `sim/run_sim.tcl` 与 `run_one.sh` 的文件清单，今晚不动 |
| 功耗读数 | `build/power.rpt`：静态 0.177 W、结温 52.5 °C（估算，非实测） | 想要"功耗"这项指标可报，就得给板子加实测口径，别把工具估算写成测量 |

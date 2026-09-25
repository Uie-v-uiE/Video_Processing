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
* 250 MHz 时钟树空转：`clock_util.rpt` 的 `clkout1_1` = `u_pl/u_clk/u_bufg_5x/O → clk_pix5x`，
  **fabric 负载 0**、每次构建仍要为它算一条 4 ns 约束组 ⇒ 可去掉一路 MMCM 输出 + 一只 BUFG。
  收益口径要诚实：**毫瓦级**动态功耗 + 少一棵要收敛的树，不是整数瓦；且必须排在移死模块之后（否则新错来了分不清是谁）。

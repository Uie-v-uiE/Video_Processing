# 硬件优化日志（时序 / 布局 / 功耗；2026-09-21 增补第四版数据通路修复）

工程：Video_Processing（v3）· Zynq7020 以太网视频 + 右屏无极缩放  
工具：Vivado / Vitis 2025.2.1  
仓库：`D:\Xilinx\Prj\ADD\Video_Pipeline-main`

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

### 结果
- 时序不降反升：WNS +0.373 → **+0.675 ns**（0 违例）；Registers 49.52%、BRAM 138.5/140。
- 入包写吞吐上限：≈20 MB/s → ≈400 MB/s（握手决定），对 15 MB/s 有 26× 余量。
- 回归：28/28 PASS（`sim/results/regression_v6.txt`）。

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

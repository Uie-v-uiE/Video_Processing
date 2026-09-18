# 硬件优化日志（时序 / 布局 / 功耗）

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

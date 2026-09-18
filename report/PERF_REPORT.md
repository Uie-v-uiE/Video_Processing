# 性能与资源报告（第三版）

> 版本：v3 · PL UDP offload + 右屏无极缩放 + 目标域效果 + 时序收敛  
> 板卡：RK-ZYNQ7020-F（XC7Z020-CLG484-2）· Vivado 2025.2.1  
> 数据来源：`build/timing_summary.rpt`、`utilization.rpt`、`power.rpt`；功能项已上板验证。

---

## 1. 测量条件

| 项 | 条件 |
|----|------|
| 源 | 512×300 RGB565 |
| 显示 | HDMI 1024×600 @50 MHz 双窗 |
| 网络 | 千兆 UDP 5001，`[u32 offset][payload]`，payload≤1396 |
| 数据面 | PL 硬件协议栈（PS 不参与逐包） |
| 右屏 | 无极缩放 1.0×↔0.5× 循环 + 效果链 |

---

## 2. 版本对比（架构）

| 项 | v1 PS 网口 | v2 PL 网口 | **v3 当前** |
|----|------------|------------|-------------|
| UDP 数据面 | PS lwIP → DDR | PL RGMII→BRAM | 同 v2 + 优化 |
| 右屏 | 效果（line_cache） | 效果 | **缩放循环 + 效果** |
| 旋转 | 有 | 有 | 有，可与缩放叠加 |
| OSD | 无/简 | 有 | FPS / ANG / EN |
| FIFO | IP/软件 | 部分自写 | **全自写 + BRAM 化** |
| 时序 | — | 有跨钟假违例 | **全局 MET** |

---

## 3. 时序（优化后）

**结论：`All user specified timing constraints are met`**

| 时钟 | 周期 | WNS | 状态 |
|------|------|-----|------|
| clk_fpga_0 | 10 ns | +0.865 | MET |
| eth_rxc | 8 ns | +0.111 | MET |
| sys_clk | 20 ns | +14.445 | MET |
| clkout0_1 (clk_pix) | 20 ns | +1.882 | MET |

- 跨钟 eth_rxc ↔ clk_pix：已异步约束，报告中无违例  
- Hold / Pulse：MET  
- 优化前全局 WNS 约 −6.7 ns（假跨钟 + FIFO 寄存器堆）→ 详见 `OPTIMIZATION_LOG.md`

---

## 4. 资源占用（实现后）

| 资源 | 使用 | 占比（7020） |
|------|------|----------------|
| Slice LUT | 10621 | **19.96%** |
| Slice Registers | 20253 | **19.03%** |
| Block RAM Tile | 83 | 59.29% |
| DSP | 13 | 5.91% |

对比优化前：LUT 23.3%→20.0%，FF 23.2%→19.0%（FIFO 推断 BRAM、逻辑整理）。

BRAM 主要占用：frame_buffer 512×300×16b + 协议栈/行缓等。

---

## 5. 功耗（report_power）

| 项 | 数值 |
|----|------|
| Total On-Chip | **2.240 W** |
| Dynamic | 2.071 W |
| Device Static | 0.169 W |
| Junction Temp | 50.8 °C |

说明：vector-less 估算，置信度 Low（复位翻转假设）；适合相对比较。

Bitstream：`COMPRESS TRUE`，bit 约 2.1 MB（未压缩约 4 MB）。

---

## 6. 吞吐与带宽

| 路径 | 计算 | 结论 |
|------|------|------|
| UDP 入口 | 307200 B × 30 fps | ≈9.2 MB/s ≈74 Mbps，千兆余量大 |
| 显示读 | 307200 B × 60 Hz | ≈18.4 MB/s |
| HP0 理论 | 64-bit @100 MHz | 800 MB/s，占用极低 |
| BRAM | 单缓冲 2.34 Mb | 双缓冲放不下 |

PS CPU：主循环仅 `uart_poll`，不参与视频搬移。

---

## 7. 功能验证

| 项 | 结果 |
|----|------|
| `tb_zoom_mapper` | PASS（恒等、0.5× 中心映射、三角波） |
| 其余 sim（gray/timing/rotate/udp…） | PASS（`tb_eth_video` 参数历史问题，与本功能无关） |
| 上板右屏缩放 | 用户确认 OK（1.0× 最大→缩小循环） |
| 效果/旋转/选源/推流 | 与缩放并存可用 |
| 优化后 bit | 已生成；建议再完整回归一次 |

---

## 8. 证据索引

| 类型 | 路径 |
|------|------|
| 时序 | `build/timing_summary.rpt` |
| 资源 | `build/utilization.rpt` |
| 功耗 | `build/power.rpt` |
| 架构 | `report/ARCHITECTURE.md` |
| 优化过程 | `report/OPTIMIZATION_LOG.md` |
| 上位机 | `src/host/HOST_GUIDE.md` |
| 构建 | `build/tcl/build_system_axigpio.tcl` |

---

## 9. 结论

1. 数据面 PL 卸载后延迟确定，PS 仅控制。  
2. 右屏无极缩放与效果/旋转/选源可同时工作。  
3. 时序全局收敛；资源与功耗处于 XC7Z020 合理区间。  
4. 自写 FIFO + OSD 为可复用基础模块。  
5. 可后续升级：双线性插值、消隐期写帧缓减拖影。

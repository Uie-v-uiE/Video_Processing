# 性能与资源报告（第三版 + 第四版 V6.x 增补）

> **时效声明（2026-09-23 加）**：本文里的数字是 **v3 / V6.x 当时**的测量值，保留是为了能对比
> "同一指标在不同版本上的走势"，**不要当成当前值引用**。当前值只有一处权威来源：
> `report/CHANGELOG_V7.md` 的「五版累计」表与 V7.9 门禁表，逐轮原始数字在 `report/OVERNIGHT_LOG.md` §5，
> 演示口径在 `report/DEMO_SCRIPT.md` §2（那一句一定与 `build/system.bit` 的 md5 成套）。
> 同一份数字抄在第二个地方就会漂移，所以这里只给指路、不复制数值。

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

---

## 10. 第四版（V6.x）增补：入包吞吐与数据完整性

### 10.1 优化前后对比（同一判据：JTAG 回读两个 bank，逐 16bit 反解帧号）

| 指标 | 第三版 | V6.1（CDC 读侧 + 分包对齐） | V6.2（CDC 加深 8192 + 反压） | **V6.3（写通道流水化）** |
|------|--------|---------------------------|----------------------------|------------------------|
| 最新帧在自己 bank 命中率 | 23~37% 的字完整、约 40% lane 从未写入 | 单帧 100%，连续推流 42~52% | 42~52%（**无改善**） | **100.0%**（15/30/60 fps） |
| 包内相位丢字率（0–48 B / >48 B） | — | 结构无法观测 | 6.7% / 54~64% | **0.0% / 0.0%** |
| 16bit 粒度错帧（u32 内两 lane 不同帧） | 大量 | — | 18.6% | **0 / 76800** |
| 入包写吞吐上限（估算） | ≈20 MB/s（逐字等 B） | ≈20 MB/s | ≈20 MB/s | **≈400 MB/s**（≤2 拍/字） |
| 板级可跑帧率 | 15 fps 即明显拖影 | 15 fps 仍有拖影 | 同左 | **60 fps / 18.4 MB/s 无丢字** |

### 10.2 时序与资源（V6.3，`build/timing_summary.rpt`、`build/utilization.rpt`）

| 项 | 值 |
|----|----|
| WNS / WHS / WPWS | **+0.675 / +0.053 / +0.264 ns** |
| 违例端点 | 0 / 111287（`All user specified timing constraints are met.`） |
| Slice Registers | 52687 / 106400 = **49.52%** |
| Block RAM Tile | 138.5 / 140 = **98.93%**（V6.2 的 CDC 加深占 +8 tile） |
| 布线占用 | H 30.1% / V 29.2% |

### 10.3 带宽预算（为什么 V-blank 内拷贝一定够）
- 显示拷贝一帧 = 38400 拍（64bit），可用窗口 = 25 行 × 1344 = 33600 pix 周期
  = 67200 个 axi 周期 ⇒ 下限 **0.571 拍/周期 ≈ 457 MB/s**；实测 `copy_cycles ≤ 67200`
  （`copy_overrun` 标志从未置起，`led[0]` 保持 1.5 Hz 心跳）。
- 入包侧给 15 MB/s（1.875 M 字/s），V6.3 后打包器上限 ≈50 M 字/s ⇒ **26×** 余量；
  缓冲（CDC 8192 + 打包器 512 = 4608 字）可吸收 **≈2.5 ms** 的端口完全独占。
  仿真标定：端口被独占 134400 拍（两个完整消隐窗口）仍 100% 落位，268800 拍才按预算失败。

### 10.4 验证
- 28 个 testbench 全 PASS（`sim/results/regression_v6.txt`，在打包后的仓库目录内跑的）。
- 板级：`node src/host/measure_v63.mjs --fps {15,30,60}`，原始输出见
  `data/measured/board_measure_*.txt`。

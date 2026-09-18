# 性能对比报告（优化前 / 优化后）

> 版本：v1（PL UDP offload + 目标域窗滤 + OSD）
> 依据：本仓库 RTL/仿真/设计文档；上板实测项标注「待上板填数」。

## 1. 测量条件

| 项 | 条件 |
|----|------|
| 板卡 | RK-ZYNQ7020-F，XC7Z020-CLG484-2 |
| 源分辨率 | **512×300 RGB565**（维持原分辨率） |
| 显示 | HDMI 1024×600 @ 50 MHz，左右双窗 |
| 网络 | 千兆，UDP 5001，包约 1400 B，协议 `[u32 LE offset][payload]` |
| 优化前 | PS lwIP 收包 + memcpy 写 DDR |
| 优化后 | PL RGMII→MAC→UDP→重组→BRAM/HP0 写 DDR；PS 仅控制面 |

## 2. 帧率对比

| 指标 | 优化前（PS lwIP） | 优化后（PL UDP） | 证据 |
|------|-------------------|------------------|------|
| 目标推流帧率 | 30 fps（上位机） | 30 fps（协议不变） | `sw/host/video_sender.py` |
| 可持续帧率 | 受 CPU 中断/协议栈限制，实测常见 20–30 fps（待填实测） | 线速可达，重组无 CPU 参与 | 设计：1G 链路余量充足 |
| 显示刷新 | 60 Hz 回读 DDR→BRAM | 同左；或 eth 直写 BRAM | `axi_frame_writer` / `frame_reasm` |

**测量方法：** 上位机统计发送 fps；板端 OSD `FPS=` 或 `STAT`；ILA 抓 `frame_done` 周期。

## 3. 端到端延迟（估算 + 测点）

| 阶段 | 优化前 | 优化后 |
|------|--------|--------|
| 网卡→协议栈 | lwIP 中断+拷贝，百微秒–毫秒级 | RGMII DDR 采样，约 8 ns/字节流水 |
| 帧重组 | PS memcpy 按 offset | PL BRAM 写，同拍级 |
| 可见 | 收满帧 flush 后下一显示帧 | eth 直写后下一 vsync；或 DDR 写完后显示回读 |

**建议 ILA 测点：** `rgmii_rx_ctl` 首字节 → `frame_done` → 下一 `vs` 上升沿。

## 4. PS CPU 占用

| 模式 | 说明 |
|------|------|
| 优化前 | 每 UDP 包进中断/回调 + memcpy + 帧满 flush；30 fps×约 220 包/帧 ≈ 6600 包/s，CPU 高占用 |
| 优化后 | 主循环仅 `uart_poll`；**不再参与逐包搬运** | 

**测量方法：** 空闲循环计数或 `ps7_init` 侧全局计数器前后差；对比两版 ELF。

## 5. DDR 带宽

| 方向 | 计算 | 优化前 | 优化后 |
|------|------|--------|--------|
| 写入帧 | 307200 B × fps | PS 写 30 fps → **9.2 MB/s** | PL HP 写 30 fps → **9.2 MB/s**（同量） |
| 显示回读 | 307200 B × 60 Hz | **18.4 MB/s** HP0 读 | 相同；若 eth 直写 BRAM 可省本轮询 |
| 合计 | | ~28 MB/s | ~28 MB/s 或更低（直写 BRAM） |
| HP0 理论 | 64-bit @ 50 MHz → 400 MB/s | 占用 <10% | 同量级 |

> 优化收益主要在 **CPU 卸载与延迟**，不是 DDR 峰值带宽。

## 6. 资源占用（LUT/FF/BRAM/DSP）

| 资源 | 视频流水线（已有） | 新增 PL UDP（估算） | 说明 |
|------|-------------------|---------------------|------|
| LUT | 见 Vivado `report_utilization` | MAC+UDP+reasm 约 1–2k LUT | 待综合填实测 |
| FF | 同上 | 数百 | |
| BRAM | frame_buffer ~2.34 Mbit + line | FIFO 64×36b 可忽略 | 7020 共 4.9 Mbit |
| DSP | 旋转/滤波少量 | UDP 无 DSP | |

**导出命令：**

```tcl
report_utilization -file output/utilization.rpt
report_timing_summary -file output/timing_summary.rpt
```

## 7. 功能优化对比（架构）

| 项 | 优化前 | 优化后 |
|----|--------|--------|
| UDP 数据面 | PS lwIP | **PL RGMII 全硬件** |
| 旋转+窗滤 | angle≠0 强制旁路 blur/sobel | **目标域 3×3，任意角可组合** |
| OSD | 无（模块未接入） | 左上角 FPS/ANG/EN/NET/RUN |
| 坏帧策略 | 丢弃不重传，下一帧恢复 | **保持不变** |
| 协议 | offset 拼帧 | **上位机无需修改** |

## 8. 验证证据索引

| 类型 | 位置 |
|------|------|
| 仿真 UDP 重组 | `sim/tb_udp_reasm.v`（正常/OOS/丢包/重复/跳变） |
| 仿真 UDP 解析 | `sim/tb_udp_parser.v` |
| 仿真旋转+窗滤 | `sim/tb_rotate_window.v` |
| 约束/管脚 | `constraints/rk_zynq7020.xdc`（PHY2） |
| 设计说明 | `docs/ARCHITECTURE.md`、`docs/ROTATION_AND_EFFECTS.md` |
| 上板 | 接 **PL ETH** 口推流；串口 `00111`/`STAT`；HDMI OSD |

## 9. 结论

1. **CPU 卸载**：优化后 PS 不再收 UDP 视频包，控制面独立。
2. **兼容**：上位机协议与端口约定不变（请接板卡 **PL 网口**）。
3. **画质组合**：任意旋转角下 blur/sobel 可用（目标域窗口）。
4. 待上板补充：实测 fps、CPU 占用百分比、ILA 延迟截图、综合资源表。

# PS 方案与 PL 方案的取舍（含最终那一版的结论）

这份记录回答一个问题：视频数据面为什么放在 PL（可编程逻辑），PS（芯片上的 ARM 核）为什么只留控制。
下面依次是三代各自的做法与最终版本的职责切分。结构细节的落点是 `report/architecture.md`，
逐时钟时序读数是 `report/05-timing.md`，板上实测数字是 `data/metrics.csv`。

术语先对齐：GEM0 是 PS 侧的以太网 MAC 外设，lwIP 是跑在 PS 上的软件 TCP/IP 栈；RGMII 是 PL 侧
直连 PHY 芯片的 4 bit 双沿以太网接口；HP0 是 PS 留给 PL 的一个 AXI 主设备端口；FILL 是往 DDR 里
灌诊断图案的调试通道；BRAM 是片上块 RAM，ILA 是集成在 FPGA 里的逻辑分析仪。

## 1. 三代数据面

| | v1 `v1-ps-ethernet` | v2 `v2-pl-ethernet` | **v3 `main`（当前）** |
|--|---------------------|---------------------|------------------------|
| 仓库 | Zynq_Video_Pipeline | Video_Pipeline | Video_Processing |
| 网口 | **PS GEM0 + lwIP** | **PL RGMII PHY2** | 同 v2 |
| UDP 收包 | 软件中断 + memcpy | 硬件解析 | 硬件 |
| 帧重组 | PS 写 DDR | PL frame_reasm→BRAM | 同 v2 + CDC FIFO 优化 |
| 显示 | PL 读 DDR（HP0） | PL 读 BRAM | 同 v2 |
| 屏幕内容 | 效果 | 效果（line_cache） | **缩放循环 + 效果** |
| PS 角色 | 收包 + 控制 | **仅控制** | 仅控制 |

v1 的两个成本是直接的：每个视频包都要进一次软件中断并 memcpy 一次（约 220 包/帧、30 fps），
CPU 占用高，帧到帧的延迟由协议栈与调度决定；v2/v3 把收包、校验、拼帧全做成流水线，
抖动来源变成硬件节拍。代价是 v2/v3 需要自己实现协议栈，调试也更依赖 ILA 与硬件计数器。

---

## 2. 职责划分（当前 v3）

| 职责 | PS | PL |
|------|----|----|
| 以太网 MAC/协议 | —（闲置或调试） | RGMII + ARP/ICMP/UDP |
| 拼帧 / 帧缓 | — | frame_reasm + BRAM |
| 效果 / 旋转 / 缩放 | — | proc / rotate / zoom |
| HDMI / OSD | — | split + osd + TMDS |
| 控制命令 | UART → AXI GPIO | 解码为 en/thr/src/zoom |
| 诊断 FILL | 可写 DDR | HP0 读（可选） |

数据面的字节没有一处经过 PS：ETH 那一路由 PL 自己收包、自己当 AXI 主设备写进 DDR；
SD 回放那一路才由 PS 的 SD 控制器 DMA 写进另一块 bank，写完只翻一次发布位（零拷贝）。

---

## 3. 为何最终选 PL 网口（v3）

| 对比项 | PS lwIP（v1） | PL 硬件（v2/v3） |
|--------|---------------|------------------|
| 延迟 | 中断+协议栈，毫秒级抖动 | 流水线，确定 |
| CPU | 高（约 220 包/帧×30fps） | 接近 0（仅 UART） |
| 丢包恢复 | 依赖栈 | offset 拼帧，坏帧丢弃 |
| 调试 | 软件日志方便 | 需 ILA / 计数 |
| 实现难度 | 中 | 协议栈门槛高 |
| 演示与说明 | 软硬件链路完整 | 硬件能力展示更直接 |

结论：实时视频数据面放 PL；控制面留 PS，软硬件协同由 GPIO 的命令通道与状态通道承担。

---

## 4. 窗口滤波与旋转（目标域）

| 方案 | 说明 | 本工程 |
|------|------|--------|
| A. angle≠0 关窗滤 | 简单 | 旧方案，已废弃 |
| B. 先旋转整帧再滤波 | 双缓冲延迟大 | BRAM 不够，落不了地 |
| C. **目标域 3×3** | 逆映射后在屏幕光栅取窗 | **v2/v3 现行** |

v3 里效果链作用在缩放/旋转之后的屏幕光栅上，分割线一侧给原图、另一侧给处理后的图；
分割线位置由 `split_ctrl` 给，线本身跟着画面一起转（`seam_src`）。早期形态是左右两个独立窗口，
现在整屏只有一个视口。

---

## 5. 缩放方案（v3）

| 方案 | 优 | 劣 |
|------|----|----|
| 流式 bicubic（Algorithm） | 质量高 | 需要 divider 与整行推流，与帧缓存的随机读口不合 |
| **逆映射 + 连续 inv_scale** | 与 rotate/effects/帧缓存兼容 | 最近邻，放大有块感 |
| 逆映射 + 双线性 | 更平滑 | 单口帧缓存取邻域困难，`frac` 已预留 |

---

## 6. 自写 FIFO vs IP

| | 厂商 FIFO IP | 本工程手写 |
|--|--------------|----------------|
| 集成 | 向导生成 | 纯 RTL，可移植 |
| BRAM 推断 | 一般自动 | 需要存储读写不带异步复位 |
| 可控性 | 配置项多 | 指针/同步策略完全可见 |
| 跨钟 | 标准 CDC | 格雷码指针 + 两级同步，已用于 eth_rxc→axi_clk 那一路 |

---

## 7. 迁移兼容与操作前提

- 上位机协议始终为 `[u32 LE offset][RGB565]`，端口 5001
- 网线必须插 PL 那一侧的 RJ45 口（挂在 PHY2 上，管脚表见 `report/board_pins.md`）；v2/v3 的收包逻辑
  只在这块 PHY 上
- v1 分支仍可 `git checkout v1-ps-ethernet` 查看 PS 网口的实现
- 串口命令语义延续；给 PL 加载位流之后必须再运行 PS 的 ELF，板子才会开始干活

---

## 8. 版本分支操作

```bash
git checkout main             # v3 当前
git checkout v1-ps-ethernet   # 初版 PS 网口
git checkout v2-pl-ethernet   # 第二版 PL 网口
```

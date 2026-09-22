# PS 方案 vs PL 方案（含第三版结论）

## 1. 三代数据面

| | v1 `v1-ps-ethernet` | v2 `v2-pl-ethernet` | **v3 `main`（当前）** |
|--|---------------------|---------------------|------------------------|
| 仓库 | Zynq_Video_Pipeline | Video_Pipeline | Video_Processing |
| 网口 | **PS GEM0 + lwIP** | **PL RGMII PHY2** | 同 v2 |
| UDP 收包 | 软件中断 + memcpy | 硬件解析 | 硬件 |
| 帧重组 | PS 写 DDR | PL frame_reasm→BRAM | 同 v2 + CDC FIFO 优化 |
| 显示 | PL 读 DDR（HP0） | PL 读 BRAM | 同 v2 |
| 右屏 | 效果 | 效果（line_cache） | **缩放循环 + 效果** |
| PS 角色 | 收包 + 控制 | **仅控制** | 仅控制 |

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

---

## 3. 为何最终选 PL 网口（v3）

| 对比项 | PS lwIP（v1） | PL 硬件（v2/v3） |
|--------|---------------|------------------|
| 延迟 | 中断+协议栈，毫秒级抖动 | 流水线，确定 |
| CPU | 高（约 220 包/帧×30fps） | 接近 0（仅 UART） |
| 丢包恢复 | 依赖栈 | offset 拼帧，坏帧丢弃 |
| 调试 | 软件日志方便 | 需 ILA / 计数 |
| 实现难度 | 中 | 协议栈门槛高 |
| 演示与说明 | 软硬件链路完整 | **硬件能力展示更直接** |

**结论：** 实时视频数据面放 PL；控制面留 PS，体现软硬件协同。

---

## 4. 窗滤与旋转（目标域）

| 方案 | 说明 | 本工程 |
|------|------|--------|
| A. angle≠0 关窗滤 | 简单 | 旧方案，已废弃 |
| B. 先旋转整帧再滤波 | 双缓冲延迟大 | BRAM 不够 |
| C. **目标域 3×3** | 逆映射后在屏幕光栅取窗 | **v2/v3 现行** |

v3 中效果挂在 **右窗缩放后的光栅** 上，左窗原图对比。

---

## 5. 缩放方案（v3）

| 方案 | 优 | 劣 |
|------|----|----|
| 流式 bicubic（Algorithm） | 质量高 | divider/行推流，与 FB 随机读不合 |
| **逆映射 + 连续 inv_scale** | 与 rotate/effects/FB 兼容 | 最近邻，放大有块感 |
| 逆映射 + 双线性 | 更平滑 | 单口 FB 邻域采样难，预留 frac |

---

## 6. 自写 FIFO vs IP

| | 厂商 FIFO IP | **本工程手写** |
|--|--------------|----------------|
| 集成 | 向导生成 | 纯 RTL，可移植 |
| BRAM 推断 | 一般自动 | 需存储无异步复位 |
| 可控性 | 配置项多 | 指针/同步策略完全可见 |
| 跨钟 | 标准 CDC | Gray + 2FF，已用于 eth→axi |

---

## 7. 迁移兼容

- 上位机协议始终为 `[u32 LE offset][RGB565]`，端口 5001  
- **网线必须插 PL 口**（v2/v3）  
- v1 分支仍可 checkout 查看 PS 网口实现  
- 串口命令语义延续；bit 后需 Run ELF  

---

## 8. 版本分支操作

```bash
git checkout main             # v3 当前
git checkout v1-ps-ethernet   # 初版 PS 网口
git checkout v2-pl-ethernet   # 第二版 PL 网口
```

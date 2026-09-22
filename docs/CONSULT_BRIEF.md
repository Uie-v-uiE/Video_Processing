# 咨询用简报：Zynq7020 视频流水线「花屏/拖影/卡顿」

> 目的：交给其他 AI/工程师做独立分析。**先诊断、再定方案**；不要只改一处寄存器就认为能好。

---

## 1. 项目概况

| 项 | 内容 |
|----|------|
| 板卡 | RK-ZYNQ7020-F，**XC7Z020-CLG484-2** |
| 工具 | Vivado / Vitis **2025.2.1** |
| 路径 | `D:\Xilinx\Prj\noghost\Video_Pipeline-main` |
| 功能 | PC 经 **UDP** 推 RGB565 视频 → **PL 硬件**收包/协议/重组/处理 → **HDMI 双窗**显示 |
| PS 职责 | **仅控制**（UART + AXI GPIO），**不收视频** |
| 源分辨率 | **512×300 RGB565**，一帧 **307200 B** |
| 显示 | HDMI **1024×600 @ 50 MHz**（规格 50.25，误差 0.5%），左原图 / 右处理，垂直 2× |
| 网络 | 板卡 **PL 网口** `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO @ `0x41200000`，UART 115200 |

### 数据通路（当前意图）

```
PC video_sender.py
  UDP: [u32 LE offset][RGB565 payload]  payload≤1396B  约221包/帧
    ↓
PL RGMII (125 MHz eth_rxc) → ARP/ICMP/UDP → frame_reasm
    ↓
【历史】直写 frame_buffer BRAM（显示同时读）→ 拖影
【尝试】BRAM 双缓冲 → 7020 BRAM 不够
【当前】DDR 乒乓 bank0/bank1 + axi_frame_writer 整帧回读 BRAM → 花屏/卡顿更严重
    ↓
rotate + proc_pipeline + OSD → rgb2dvi → HDMI
```

### 关键 RTL

| 文件 | 职责 |
|------|------|
| `src/rtl/eth/eth_udp_video_top.v` | UDP 协议栈 + 重组 + DDR 写 |
| `src/rtl/eth/frame_reasm.v` | offset 拼帧；`frame_done` 用字节累计 |
| `src/rtl/eth/axi_frame_saver.v` | DDR 写 master（曾单拍过慢，后改 64-bit 打包） |
| `src/rtl/axi/axi_frame_writer.v` | DDR→BRAM 整帧回读 |
| `src/rtl/top/pl_video_top.v` | 显示、源切换、BRAM |
| `src/rtl/video/frame_buffer.v` | 512×300×16b 单口双时钟 BRAM |
| `src/host/video_sender.py` | 上位机推流 |

### 资源（综合约）

- LUT ~20%，FF ~20–30%
- **BRAM Tile 曾 82.5/140（~59%）**——单份帧缓约 2.34 Mbit，**双份约 4.68 Mbit，放不下**
- HP0 64-bit @ 100 MHz，理论带宽充足；瓶颈更可能在 **突发/流水/实现** 而非标称带宽

### 上位机协议（已验证可发出完整帧）

- 整帧 RGB565 + 每包 offset，乱序可拼
- 本机已跑通：`bind 192.168.1.100` → `first frame 307200 bytes (221 pkts)`
- 30 fps 时 221 包在 **几毫秒内突发** 打进 FPGA，无 ACK、无重传

---

## 2. 现象

1. **拖影**（人走后原位置残留颜色）——ETH 边收边写显示 BRAM 时最典型  
2. **花屏**（整屏错乱/块状噪声）——多次改 DDR 回读后 **更严重**  
3. **卡顿、像丢了大量帧**  
4. **历史失败**：改架构后全黑、画面错误、花屏反复出现  

**最近状态**：ELF 已下载，推流命令已执行成功，板端仍是 **花屏 + 卡顿严重，无法观看**。  
用户要求：**先不要继续改 RTL**，把问题列清楚，外部分析后再动。

---

## 3. 已确认 / 高度怀疑的技术点

### A. 单缓冲读写竞争（拖影主因，文档已记录）

- UDP **边收边写** 显示 BRAM，HDMI **同时读**  
- 一帧收完约 33 ms（30 fps）；半截新旧像素混显 → 拖影/撕裂  
- 丢包时旧像素长期不覆盖 → **持久残影**  
- **BRAM 真双缓冲在 7020 上资源不够**（ISSUES.md #13，综合数据支持）

### B. DDR 写通路吞吐 / 丢像素（花屏候选）

- ETH 线速突发：约 1 像素 / 2 周期 @ 125 MHz ≈ **峰值 ~62 Mpix/s**  
- 平均 30 fps 仅 ~4.6 Mpix/s，但 **单帧在 ~2–3 ms 内打完**  
- 若 saver 单拍 AXI（~10–20 Mpix/s）或 CDC FIFO 过浅 → **FIFO 溢出丢像素**  
- `frame_done` 若只按重组字节累计，**DDR 未写完也会报完成** → 整帧脏数据上屏 → 花屏  
- 已改：FIFO 加深、64-bit 打包、`idle` 后再 bank 通知——**上板仍花屏**，说明问题可能不止带宽

### C. 显示路径切换 / 整帧回读

- ETH 直写 BRAM：有图但拖影  
- ETH 只写 DDR + writer 回读：曾误关 writer → **全黑**  
- 当前：`fb_ready`（writer 完成一整帧）前显示彩条；之后从 DDR bank 回读  
- **风险**：  
  - HP0 读（writer）与写（saver）**并发仲裁**  
  - writer 整帧拷 BRAM 与扫描显示 **重叠** → 撕裂  
  - bank 切换/CDC 握手错误 → 读错 bank / 读未写完 bank → 花屏  
  - `axi_frame_writer` 地址/拆包错误（历史上有过 CDC 切片错误导致「四幅画」）

### D. frame_reasm / frame_done 可靠性

- `cover` 是 **收到的字节累加**，不是「像素是否齐全」的位图  
- 重复包、部分丢包仍可能凑满字节数 → **误报 frame_done**  
- 丢包导致 cover 不足 → 长期不切换 bank → 冻结或一直显示脏 bank

### E. 时钟域与约束

- `eth_rxc` 125 MHz、`axi_clk`/FCLK 100 MHz、`clk_pix` 50 MHz  
- 多处 toggle + 2FF CDC（frame_done、done_bank、eth_link…）  
- 最近实现 **WNS≈-0.24 ns**（`eth_rxc`→axi，`eth_link` 等同步链）  
- XDC 有历史问题：`set_false_path -from eth_rst_n` 报 **无有效 startpoint**  
- EMIO GPIO 在本板不可用（读回恒 0），控制走 AXI GPIO

### F. 上位机 / 网络行为（可能加重，非唯一根因）

- 30 fps × 221 包 **无间隔突发**，PL UDP 无流控  
- 双网卡时若未 `bind 192.168.1.100`，包可能走 WLAN → 板端收不到  
- 网线插错 PS 口 → 灯可能亮但 PL 栈无包  
- 解码器/分辨率/帧率不匹配一般不会导致「随机花屏」，但会加重卡顿观感  

### G. 其它历史坑（重构时容易再犯）

| 项 | 说明 |
|----|------|
| 行地址 12 位溢出 | `(row+1)<<10` 必须 32 位 |
| CDC 打包切片 | 必须用 `dout[34:16]` 不是错误右移 |
| 0° 旋转旁路 | 旁路后 delay 不一致会流水线错位 |
| Vivado 2025 空 begin/end | 参考工程语法要清理 |
| bit 后 ELF | PS 复位，必须 Vitis Run |
| 构建脚本覆盖 top | 勿用 Tcl 重写 `system_top.v` |

### H. 架构约束（方案空间）

- 7020 **放不下两份 512×300×16 的片上帧缓**  
- 旋转需要 **帧级随机访问** → 不能只做纯扫描 line buffer（除非旋转旁路）  
- DDR 容量足够做乒乓；难点是 **实现正确性 + 峰值写读 + 与显示同步**  
- 也可考虑：降分辨率真双缓冲、去旋转只做线性显示、PS+PL 混合、更大 FPGA  

---

## 4. 已尝试方案与结果

| 方案 | 结果 |
|------|------|
| ETH 直写 BRAM | 画面能出，**拖影** |
| BRAM 双缓冲 `frame_buffer_db` | **资源不够**，无法落地 |
| ETH 只写 DDR + 显示回读（早期） | writer 被错误关闭 → **全黑**；DDR 未通时显示旧图 |
| DDR 乒乓 + 64-bit saver + 完整帧才切源（最近） | 仿真 11/11 PASS；**上板花屏+卡顿更严重** |
| 上位机推流本机验证 | **发送成功**（307200 B / 221 pkt），问题在板端显示/DDR 链路 |

仿真通过 ≠ 上板正确：仿真未覆盖 **真实 HP0 互联、PHY 突发、ILA 级时序、资源布局**。

---

## 5. 建议外部专家重点回答的问题

1. 在 **7020 BRAM 不够双缓冲** 的前提下，消拖影又不花屏的 **推荐架构** 是什么？  
2. DDR 乒乓时，**frame_done 应用什么判据**（覆盖位图？写指针？AXI 写完）才安全？  
3. HP0 **读写并发** 时，显示回读与 ETH 写如何 **仲裁/带宽隔离** 才不易花屏？  
4. 是否应 **放弃旋转随机读**，改为「DDR 顺序扫描 + 行 FIFO 显示」以彻底简化？  
5. 上位机是否应 **帧间隔 + 包间隔 + 帧号/校验 + 简单重传/丢帧通知**？协议要不要改？  
6. 有没有必要 **先回退到「ETH 直写 BRAM + 可接受拖影」** 做基线，再最小改动验证 DDR？  
7. 仿真/ILA 应加哪些点才能区分「DDR 脏数据」vs「显示时序」vs「CDC」？  
8. 时序 WNS 负值与 XDC false_path 是否可能是花屏主因？  

---

## 6. 当前文件与产物

| 路径 | 说明 |
|------|------|
| `build/system.bit` | 最近一次实现（DDR 乒乓版，**上板花屏**） |
| `build/system.xsa` | 对应硬件平台 |
| `src/host/README.md` | 上位机用法（bat 路径已修正） |
| `report/ISSUES.md` | 历史问题记录 |
| `report/ARCHITECTURE.md` | 架构与带宽 |
| `sim/run_sim.tcl` | 行为仿真入口 |

### 上位机推荐试法（降低压力，非根治）

```bat
src\host\run_video.bat D:\UserData\Downloads\aaa.mp4 --fps 15 --gap 0.0005
```

---

## 7. 一句话总结

> **显示侧单缓冲与网络收包并发** 导致拖影；片上双缓冲资源不够；改走 **DDR 乒乓 + 整帧回读** 后，**DDR 写完整性和显示/HP0/CDC 同步** 成为新瓶颈，上板表现为更严重的花屏卡顿。上位机发包本身正常。需要在 **约束（7020 BRAM、峰值 UDP、旋转随机读）下重新选架构**，而不是继续在错误路径上打补丁。

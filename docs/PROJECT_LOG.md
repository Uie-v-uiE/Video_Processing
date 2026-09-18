# 项目记录（个人）

按时间粗记，细节以 `report/` 与 git 历史为准。

## 环境

| 项 | 值 |
|----|-----|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） |
| 工具 | Vivado / Vitis **2025.2.1** |
| 上位机 | Windows + Python 3 |
| 网络 | PC `192.168.1.100` ↔ 板 PL 口 `192.168.1.10:5001` |
| 显示 | HDMI 1024×600 |
| 赛道 | AMD FPGA 创新 · 自主选题 · 初级组 |

## 阶段记录

### 1. 基础通路

- 管脚、原理图、PL 网口确认（BANK33 RGMII）。
- 移植/实现 PL 协议栈：ARP、ICMP、UDP、offset 拼帧。
- frame_buffer + HDMI 双窗 + 彩条。
- **验收：** `ping 192.168.1.10` 通；HDMI 见双窗。

### 2. 效果与旋转

- gray / binary / blur / sobel / invert 五级 + bypass。
- 任意角旋转：Q8 sin/cos ROM + 逆映射。
- PS 串口 + AXI GPIO 控制。
- **验收：** 串口 `10000`、`00111`、按键改角有效。

### 3. 无极缩放移植

- 源：`Algorithm/` 工程（流式 bicubic）。
- 目标：改为帧缓逆映射 + 连续 `inv_scale`（与单口 FB、效果链兼容）。
- 第一版：1.0×→2.0× 放大循环；上板 OK。
- 需求变更：**原始尺寸为最大** → 改为 1.0×→0.5× 缩小循环；上板 OK。
- 仿真：`tb_zoom_mapper` PASS。
- 文档：`report/ZOOM_PORT.md`。

### 4. 时序 / 功耗优化

- 问题：全局 WNS 为负，主要是 eth_rxc→clk_pix 假跨钟 + icmp FIFO 寄存器堆路径。
- 处理：XDC 异步时钟组（含 MMCM 生成钟）；FIFO 存储去异步复位推 BRAM；rd_addr 打拍；COMPRESS。
- **结果：全局时序 MET**；详见 `report/OPTIMIZATION_LOG.md`。
- bit/xsa 更新：`build/system.bit`、`build/system.xsa`。

### 5. 上位机

- 修复 bat 路径、FFmpeg 查找、定时节拍发送。
- 串口工具支持 ZOOM、列端口、单次命令。
- 文档：`src/host/HOST_GUIDE.md`。

### 6. 竞赛仓库整理

- 对照 AMD 选题指南 3.3 自主选题初级组目录要求。
- 英文目录、`.gitignore`、MIT License。
- 个人学习文档 `docs/LEARNING.md`、TCL 教程 `docs/TCL_GUIDE.md`。
- 开源仓库：`https://github.com/Uie-v-uiE/Video_Processing`

## 关键命令备忘

```bat
:: 构建
cd /d D:\Xilinx\Prj\ADD\Video_Pipeline-main
"D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat" -mode batch -source build\tcl\build_system_axigpio.tcl

:: 下载 bit
... program_system.tcl

:: 仿真
... sim\run_sim.tcl

:: 推流
cd src\host
run_sender.bat
```

## 待办 / 可改进

- [ ] 缩放质量：双线性（需行缓或多口 FB）
- [ ] 竞赛设计报告终稿（report/ 下按评分条目组织）
- [ ] skill/ 再补 1～2 项与题目无关的通用 PYNQ/脚本技能（加分）
- [ ] 优化后 bit 再完整上板回归（缩放 + 效果 + 推流）
- [ ] metrics 类实测表（FPS、资源、WNS）整理成一页

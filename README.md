# Zynq7020 以太网视频处理流水线

全国大学生嵌入式芯片与系统设计竞赛 · **FPGA 创新设计赛道（AMD）· 自主选题 · 初级组**

上位机经 **UDP** 推送 RGB565 视频；**PL** 完成 RGMII 收包、ARP/ICMP/UDP、帧重组、图像处理与 HDMI 双窗输出；**PS** 仅做控制面（UART + AXI GPIO）。右屏 **无极缩放** 自动循环（原始尺寸为最大，缩小后再回到原始）。

| 项 | 值 |
|----|-----|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2，符合初级组器件范围） |
| 工具 | Vivado / Vitis **2025.2.1** |
| 源分辨率 | **512×300 RGB565** |
| 显示 | HDMI **1024×600 @ 50 MHz**，左原图 / 右处理+缩放 |
| 网络 | 板卡 PL 口 `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO @ `0x41200000`，UART 115200 |
| 协议 | MIT |
| 开源 | https://github.com/Uie-v-uiE/Video_Processing |

---

## 目录结构（对照竞赛推荐）

竞赛要求目录与文件名为**纯英文**；中文只出现在正文。

```
Video_Processing/                 # 仓库根
├── README.md                     # 本文件：简介 + 复现步骤
├── LICENSE                       # MIT
├── .gitignore
├── src/                          # 设计源码
│   ├── rtl/                      # Verilog（top / eth / video / process / axi / hdmi）
│   ├── ps/                       # 裸机控制（UART + GPIO）
│   ├── host/                     # 上位机 UDP 推流 + 串口
│   │   └── HOST_GUIDE.md         # 上位机使用教程
│   └── constraints/              # 管脚与时序约束
├── sim/                          # 仿真 testbench 与脚本
├── build/                        # 可复现构建 + 报告 + 产物
│   ├── tcl/                      # Vivado TCL（从零构建 / 下载 / 增量）
│   ├── system.bit                # 比特流
│   ├── system.xsa                # Vitis 硬件平台
│   ├── timing_summary.rpt
│   ├── utilization.rpt
│   └── power.rpt
├── board/                        # 上板说明
├── data/golden/                  # 金标参考图
├── skill/                        # 技能包（大模型协作沉淀）
│   └── README.md
├── report/                       # 设计报告与工程文档
│   ├── ARCHITECTURE.md
│   ├── MODULES.md
│   ├── OPTIMIZATION_LOG.md
│   ├── ZOOM_PORT.md
│   └── ...
└── docs/                         # 个人学习与工具笔记
    ├── LEARNING.md               # 模块/架构/知识点详解
    ├── TCL_GUIDE.md              # TCL 基础教程
    └── PROJECT_LOG.md            # 项目时间线
```

| 竞赛推荐名 | 本仓库对应 |
|------------|------------|
| `src/` | `src/` |
| `sim/` | `sim/` |
| `build/` | `build/`（tcl + 报告 + bit/xsa） |
| `board/` | `board/` |
| `data/` | `data/` |
| `skill/` | `skill/` |
| `report/` | `report/` + `docs/` |

---

## 快速复现

### 1. 生成比特流与 XSA

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

产物：`build/system.bit`、`build/system.xsa`  
（若仓库内已有产物，可跳过本步直接下载。）

TCL 说明见 **`docs/TCL_GUIDE.md`**。

### 2. 下载比特流

```bat
%VIVADO% -mode batch -source build\tcl\program_system.tcl
```

### 3. （可选）下载 PS ELF — 串口命令需要

1. Vitis 打开工作区，Platform 指向 `build/system.xsa`
2. 应用源码：`src/ps/main.c`
3. Build → Run  

> 下载 bit 后 PS 会复位，必须再 Run 一次 ELF，串口才有效。  
> **仅看右屏自动缩放**时，下载 bit 即可。

### 4. 仿真

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
```

### 5. 上位机推流

```bat
pip install -r src\host\requirements.txt
cd src\host
run_sender.bat
:: 或
run_video.bat D:\path\to\video.mp4
```

PC 网卡：`192.168.1.100/24`，网线接 **板卡 PL 网口**。  
详细说明：`src/host/HOST_GUIDE.md`。

---

## 串口命令（115200 8N1，CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊 + Sobel + 反色 |
| `SRC0` / `SRC1` | 彩条 / DDR-ETH 视频 |
| `TH80` | 二值化阈值 |
| `ZOOM0` / `ZOOM1` | 右屏缩放 关/开（PL 侧默认常开） |
| `FILL` / `STAT` | 诊断 / 状态 |

效果位顺序：**gray / binary / blur / sobel / invert**（左起 bit0）  
ETH 收到完整帧后自动切视频源。

---

## UDP 协议

```
[u32 小端 byte_offset][RGB565 载荷]
一帧 512×300×2 = 307200 字节，单包载荷 ≤1396
板端按 offset 写帧缓，乱序可拼对；坏帧丢弃
```

---

## 文档索引

| 文件 | 内容 |
|------|------|
| [docs/LEARNING.md](docs/LEARNING.md) | **个人学习文档**：模块、架构、知识点、方案对比 |
| [docs/TCL_GUIDE.md](docs/TCL_GUIDE.md) | **TCL 基础教程** |
| [docs/PROJECT_LOG.md](docs/PROJECT_LOG.md) | 项目时间线与备忘 |
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) | 上位机使用教程 |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | 数据通路、时钟、带宽 |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) | 时序/功耗优化日志 |
| [report/ZOOM_PORT.md](report/ZOOM_PORT.md) | 无极缩放移植说明 |
| [skill/README.md](skill/README.md) | 技能包 |

---

## 关键设计摘要

- **PL 硬件协议栈**：RGMII → ARP/ICMP/UDP → offset 拼帧 → 帧缓  
- **PS 只做控制**：UART → AXI GPIO → 效果 / 选源  
- **右屏无极缩放**：`zoom_ctrl` + `zoom_mapper`，原始尺寸为最大，自动缩小循环  
- **效果链**挂在右窗缩放后的数据流上，左窗原图便于对比  
- **旋转**可与缩放叠加；选源、推流不受影响  
- **时序**：跨钟异步约束 + FIFO BRAM 化，全局 MET（见优化日志）

---

## 许可

MIT License，详见 [LICENSE](LICENSE)。

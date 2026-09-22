# Zynq7020 以太网视频处理与 HDMI 双窗显示


> ## 本分支 = 第一版（PS 以太网）
>
> 数据通路：上位机 UDP → **PS（lwIP）** → PS DDR → PL 经 HP0 读出 → PL 做效果/旋转 → HDMI 双窗。
> PS 既跑协议栈又搬运画面，PL 不碰网络。
>
> **本版本的已知限制（不是 bug，是当时的取舍）**：`angle ≠ 0` 时模糊与 Sobel 被**强制旁路**，
> 只保留点运算类效果（灰度/二值/反色）。原因与实现分别记录在
> `docs/ROTATION_AND_EFFECTS.md`（含角度×效果对照表）与 `rtl/process/proc_pipeline.v:24-25`
> （`wire by2 = ~effect_en[2] | rotate_active;`）。
> 机理：窗口滤波需要**源图扫描顺序上的 3×3 邻域**，而旋转是逆映射，屏幕网格上取到的邻域
> 在源图中不连续。真正让「任意角度 + 窗滤同时可用」的修复在第二版（目标域窗滤）。
>
> 对照其它版本：`main`（第五版）、`v4-zero-loss`、`v3-seamless-zoom`、`v3-ghosting-attempts`、
> `v2-pl-ethernet`。逐版问题与证据见 `main` 分支的 `report/VERSION_LINEAGE.md`。

上位机经 **UDP** 推送 RGB565 视频到 Zynq PS，写入 DDR；PL 侧经 AXI HP0 读出，完成 **5 种图像处理** 与 **0–359° 任意角旋转**，以 **左原图 / 右处理结果** 双窗输出 **HDMI 1024×600**。

| 项 | 值 |
|----|-----|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） |
| 工具 | Vivado / Vitis **2025.2.1** |
| 源分辨率 | 512×300 RGB565 |
| 显示 | 1024×600 @ 50 MHz，左右各 512，垂直 2× |
| 网络 | 板卡 192.168.1.10:5001，PC 192.168.1.100 |
| 控制 | AXI GPIO @ 0x41200000，UART 115200 |
| 许可 | MIT |

---

## 目录结构

```
zynq_video_pipeline/
├── README.md                 本文件
├── LICENSE                   MIT
├── .gitignore
├── rtl/                      PL 源码
│   ├── top/                  system_top, pl_video_top, pl_demo_top
│   ├── video/                时序、彩条、分屏、frame_buffer(_db)、osd_overlay
│   ├── process/              五效果流水线 + rotate/
│   ├── axi/                  axi_frame_writer（HP0 读 DDR）
│   ├── hdmi/                 TMDS 编码串化
│   ├── clocks/               MMCM
│   └── util/                 按键消抖
├── constraints/              管脚与时序 XDC
├── tcl/                      Vivado 一键脚本
├── sim/                      单元仿真
├── scripts/                  金标模型、sin/cos ROM
├── sw/
│   ├── ps/                   裸机源码（与 Vitis 同步）
│   └── host/                 上位机 UDP / 一键脚本
├── skill/                    竞赛技能包
├── docs/                     全部设计文档
├── output/                   bit / xsa / 时序报告
└── sim_out/                  金标图输出
```

**新增文件：**
- `rtl/video/frame_buffer_db.v` — 双缓冲防撕裂
- `rtl/video/osd_overlay.v` — 屏上显示角度/效果/FPS
- `docs/TIMING_REPORT.md` — 时序优化记录 v1→v4
└── output/                   bit / xsa / 报告输出
```

**Vivado 工程：** `vivado_system/`（由 `tcl/build_system_axigpio.tcl` 生成）  
**Vitis 工作区：** `vitis_udp/`（Platform + app_component）  
两者均已 `.gitignore`，可用 TCL 从零复现。

---

## 快速开始

### 1. 生成比特流

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
%VIVADO% -mode batch -source tcl\program_system.tcl
```

### 2. Vitis 编译下载

1. 用 Vitis 打开工作区 `vitis_udp`
2. Platform 需含 **lwip220**（链路速率建议 `CONFIG_LINKSPEED1000`）
3. Build Platform → Build app_component → **Run**

### 3. 推流

```bat
:: 内置动画（自检）
sw\host\run_sender.bat

:: 真实视频（需带 H.264 的完整 FFmpeg）
sw\host\run_video.bat D:\path\to\video.mp4
```

PC 网卡：`192.168.1.100/24`，网线接 **PS ETH**。

---

## 串口命令（115200 8N1，发送加 CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊+Sobel+反色 |
| `00110` | 模糊+Sobel |
| `SRC0` / `SRC1` | 彩条 / DDR 视频 |
| `TH80` | 二值化阈值 |
| `FILL` | 2×2 诊断色块 |
| `STAT` | 帧计数与网口状态 |

效果位：**左起 = bit0**，顺序 gray / binary / blur / sobel / invert。

**旋转时：** angle≠0 自动旁路 blur、sobel（窗口滤波与旋转坐标不兼容）；gray、binary、invert 仍有效。详见 `docs/KNOWLEDGE.md`。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 数据通路、时钟、带宽、模块框图 |
| [docs/KNOWLEDGE.md](docs/KNOWLEDGE.md) | 关键知识点与设计决策 |
| [docs/ISSUES.md](docs/ISSUES.md) | 开发中遇到的问题与修复 |
| [docs/COMPETITION.md](docs/COMPETITION.md) | 2026 AMD 自主选题提交清单 |
| [docs/PROJECT_LAYOUT.md](docs/PROJECT_LAYOUT.md) | 工程路径与复现步骤 |
| [docs/TCL_BUILD_GUIDE.md](docs/TCL_BUILD_GUIDE.md) | **TCL 构建工程详细教程** |
| [docs/ETH_BRINGUP.md](docs/ETH_BRINGUP.md) | 以太网上板 |
| [docs/SYSTEM_BRINGUP.md](docs/SYSTEM_BRINGUP.md) | 系统工程上板 |
| [docs/ROTATION_AND_EFFECTS.md](docs/ROTATION_AND_EFFECTS.md) | 旋转与效果关系 |
| [docs/TIMING_REPORT.md](docs/TIMING_REPORT.md) | 时序分析（需自行导出） |
| [docs/LLM_ASSIST_LOG.md](docs/LLM_ASSIST_LOG.md) | 大模型协作记录 |
| [skill/README.md](skill/README.md) | 可复用技能包 |

---

## 关键设计摘要

- **PS/PL 分工：** PS 做协议与 DDR 写入；PL 做像素流水线与 HDMI
- **控制字：** `en[4:0] | thr[7:8] | src[16]`，经 AXI GPIO GP0
- **DDR 帧：** 0x10000000，512×300×2 = 307200 B；收满一帧 `DCacheFlush` 后再给 PL 读
- **AXI HP0：** 64-bit，16-beat burst（AXI3 上限），每 beat 4 个 RGB565
- **旋转：** 逆映射 + Q8 sin/cos ROM；angle=0 旁路 mapper 保持流水线对齐
- **为何不用 EMIO：** 本板 EMIO bank 读回异常，控制走 GP0 AXI GPIO

---

## 许可与声明

MIT License。面向教学与 FPGA 创新竞赛。使用前请按实际原理图核对管脚与 PHY 型号。

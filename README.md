# Zynq7020 以太网视频处理流水线


> ## 本分支 = 第三版（加入右屏连续缩放；拖影仍未解决）
>
> 本版本新增：**连续（无级）缩放** `src/rtl/process/zoom/zoom_mapper.v` ——
> Q8 定点 `inv_scale`，256 = 1.0×（原始尺寸，最大）↔ 512 = 0.5×，256 级连续可调，
> 与任意角度旋转叠加；效果链挂在缩放后的右窗数据流上（目标域窗滤，沿用第二版方案）。
>
> **必须写清楚的一点：拖影在这个分支上并没有被修好。** 后来的量化判据（自描述图案 +
> JTAG 回读反解帧号）测得这一时期**每帧只有 42~52% 的 64bit 字真正属于它自己那一帧**。
> 为修它走过的三条弯路（BRAM 双缓冲 → DDR 三槽位帧管理 → DDR 双 bank 乒乓但 ETH 路径
> 没接上读回引擎）存档在 `v3-ghosting-attempts` 分支，其中每一条的判据与失败原因都写在里面。
>
> 真正的修复在第四版：入包写通道流水化（V6.3，`OST=8`，B 只回收计数）+
> 按 16bit lane 生成 `WSTRB`（V6.4，消除分包长度敏感的散布黑点）。
> 板级结果：命中率 42~52% → **100.0%**（15/30/60 fps 三档、包内各字节带丢字率 0.0%）。
> 完整根因与测量方法见 `main` 分支 `report/V6_ROOT_CAUSE.md`、`report/CHANGELOG_V6.md`，
> 逐版对应关系见 `report/VERSION_LINEAGE.md`。

基于 Zynq-7000（XC7Z020）的 UDP 视频接收与实时图像处理工程。

上位机通过 **UDP** 推送 **512×300 RGB565** 视频；**PL** 完成 RGMII 收包、ARP/ICMP/UDP、offset 拼帧、图像效果、旋转、无极缩放与 HDMI 双窗输出；**PS** 仅负责控制面（串口 + AXI GPIO）。

| 项目 | 说明 |
|------|------|
| 板卡 | RK-ZYNQ7020-F（XC7Z020-CLG484-2） |
| 工具 | Vivado / Vitis 2025.2.1 |
| 源分辨率 | 512×300 RGB565 |
| 显示 | HDMI 1024×600 @ 50 MHz（左原图 / 右处理+缩放） |
| 网络 | 板卡 PL 口 `192.168.1.10:5001`，PC `192.168.1.100` |
| 控制 | AXI GPIO `@0x41200000`，UART 115200 |
| 开源协议 | MIT |

### 项目简介

本工程在 Zynq-7020 上实现完整的以太网视频处理流水线：上位机以 UDP 推送 512×300 RGB565 画面，PL 侧自研 RGMII/ARP/ICMP/UDP 协议栈与 offset 拼帧写入 BRAM 帧缓，HDMI 1024×600 双窗输出——左窗原图，右窗经灰度/二值/模糊/Sobel/反色等效果链，并做以原始尺寸为最大的无极缩放循环；按键支持 0–359° 任意角旋转。网络跨钟数据经手写 Gray 码 `dc_fifo`，同钟缓存用自建 `sync_fifo`；画面左上角由自写 `osd_overlay` 叠加 FPS、旋转角与效果使能状态。PS 仅通过串口 + AXI GPIO 做控制，延迟确定、便于演示与二次开发。历史版本以 Git 分支保留（PS 网口初版 / PL 网口第二版 / 当前第三版）。

---

## 版本说明

本仓库为 **第三版**，将历史工程以分支形式保留：

| 分支 | 说明 |
|------|------|
| **`main`（当前）** | 第三版：PL 以太网视频流水线 + 效果 / 旋转 / 右屏无极缩放 |
| `v1-ps-ethernet` | 初版：**PS 以太网**（UDP → PS → DDR，PL 经 HP0 读出；来自 [Zynq_Video_Pipeline](https://github.com/Uie-v-uiE/Zynq_Video_Pipeline)） |
| `v2-pl-ethernet` | 第二版：**PL 以太网**（PL 硬件 RGMII/UDP 协议栈；来自 [Video_Pipeline](https://github.com/Uie-v-uiE/Video_Pipeline)） |

```bash
git fetch origin
git checkout main            # 第三版（默认）
git checkout v1-ps-ethernet  # 初版
git checkout v2-pl-ethernet  # 第二版
```

---

## 功能

- PL 硬件网络栈：RGMII → ARP/ICMP/UDP → 帧缓
- UDP offset 协议：乱序可拼帧，坏帧丢弃
- 效果链：灰度 / 二值化 / 模糊 / Sobel / 反色（串口控制）
- 任意角旋转（Q8 sin/cos 逆映射）
- 右屏无极缩放循环（原始尺寸为最大 → 缩小 → 回到原始）
- **自写 OSD 叠加**：左上角实时显示 FPS / 旋转角 ANG / 效果位 EN（3 倍点阵字模）
- **自建 FIFO**：同钟 `sync_fifo` + 跨钟 Gray 码 `dc_fifo`（非 IP 核，RTL 手写）
- 源选择：彩条或 ETH/DDR 视频
- 上位机：UDP 推流 + 串口控制台

---

## 目录结构

```
├── src/
│   ├── rtl/           Verilog（top / eth / video / process / axi / hdmi）
│   ├── ps/            裸机 UART + GPIO 控制
│   ├── host/          上位机推流与串口工具
│   └── constraints/   管脚与时序约束
├── sim/               仿真 testbench 与 TCL
├── build/
│   ├── tcl/           Vivado 可复现构建 / 下载脚本
│   ├── system.bit     比特流
│   ├── system.xsa     Vitis 硬件平台
│   └── *.rpt          时序 / 资源 / 功耗报告
├── board/             上板说明
├── data/golden/       金标参考图
├── skill/             可复用工程笔记
└── report/            架构与实现报告
```

---

## 快速开始

### 1. 生成比特流与 XSA

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

产物：`build/system.bit`、`build/system.xsa`（仓库内若已有可跳过）。

### 2. 下载比特流

```bat
%VIVADO% -mode batch -source build\tcl\program_system.tcl
```

### 3. （可选）下载 PS ELF — 串口命令需要

1. Vitis 打开工作区，Platform 指向 `build/system.xsa`
2. 应用源码：`src/ps/main.c`
3. Build → Run

> 下载 bit 后 PS 会复位，需再次 Run ELF，串口才有效。  
> 仅观察右屏自动缩放时，下载 bit 即可。

### 4. 仿真

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
```

### 5. 上位机推流

```bat
pip install -r src\host\requirements.txt
cd src\host
run_sender.bat
run_video.bat D:\path\to\video.mp4
```

PC 网卡：`192.168.1.100/24`，网线接 **板卡 PL 网口**。  
详见 `src/host/HOST_GUIDE.md`。

---

## 串口命令（115200 8N1，CR+LF）

| 命令 | 作用 |
|------|------|
| `00000` | 关闭全部效果 |
| `10000` | 灰度 |
| `01000` | 二值化 |
| `00111` | 模糊 + Sobel + 反色 |
| `SRC0` / `SRC1` | 彩条 / 视频源 |
| `TH80` | 二值化阈值 |
| `ZOOM0` / `ZOOM1` | 右屏缩放 关/开（PL 默认常开） |
| `FILL` / `STAT` | 诊断 / 状态 |

效果位顺序：**gray / binary / blur / sobel / invert**（bit0 在左）。  
ETH 收到完整帧后自动切到视频源。

---

## UDP 协议

```
[u32 小端 byte_offset][RGB565 载荷]
一帧：512×300×2 = 307200 字节
单包载荷：≤1396 字节
```

板端按 offset 写帧缓；乱序可拼对；丢包丢弃，下一帧恢复。

---

## 文档

| 路径 | 内容 |
|------|------|
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) | 上位机使用说明 |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | 数据通路、时钟、带宽 |
| [report/MODULES.md](report/MODULES.md) | 模块说明 |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) | 时序 / 功耗优化记录 |

---

## 设计要点

- **PL UDP 卸载**：延迟确定，PS 只做控制
- **单口 BRAM 帧缓**：约 2.34 Mb，XC7Z020 放不下双缓冲
- **缩放**：连续 `inv_scale`（Q8）逆映射；效果挂在右窗缩放后的数据流
- **自写 OSD（`osd_overlay.v`）**：  
  在 HDMI 扫描坐标上开窗叠加三行状态——`FPS=xx`、`ANG=xxx`、`EN=xxxxx`。  
  使用内置点阵字模、3 倍放大、玫红色；空格用空白字模，避免显示成「0」。  
  叠加发生在 `split_display` 之后、`rgb2dvi` 之前，不影响左右窗像素数据通路。
- **自建 FIFO（非厂商 IP）**：  
  - `sync_fifo.v`：同钟 FIFO，指针 + 满/空/水位；存储阵列**不加异步复位**，便于综合推断 BRAM（用于 ICMP 缓冲等）。  
  - `dc_fifo.v`：跨时钟 FIFO，**Gray 码指针 + 双级同步**，用于 `eth_rxc`(125 MHz) → `axi_clk`(100 MHz) 视频写路径。  
  手写 FIFO 可控资源与时序，并作为可复用基础模块。
- **时序**：异步时钟组 + FIFO 映射 BRAM，见优化日志

---

## 许可

MIT License，详见 [LICENSE](LICENSE)。

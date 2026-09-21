# Zynq7020 以太网视频处理流水线（第四版：入包链零丢字）

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

本工程在 Zynq-7020 上实现完整的以太网视频处理流水线：上位机以 UDP 推送 512×300 RGB565 画面，PL 侧自研 RGMII/ARP/ICMP/UDP 协议栈与 offset 拼帧，经 CDC 与 AXI 打包写入 **DDR 乒乓 bank**，再由提交锁在显示**消隐窗口**内把整帧原子拷进显示 BRAM；HDMI 1024×600 双窗输出——左窗原图，右窗经灰度/二值/模糊/Sobel/反色等效果链，并做以原始尺寸为最大的无极缩放循环；按键支持 0–359° 任意角旋转。网络跨钟数据经手写 Gray 码 `dc_fifo`，同钟缓存用自建 `sync_fifo`；画面左上角由自写 `osd_overlay` 叠加 FPS、旋转角与效果使能状态。PS 仅通过串口 + AXI GPIO 做控制，延迟确定、便于演示与二次开发。历史版本以 Git 分支保留（PS 网口初版 / PL 网口第二版 / 当前第四版）。

---

## 参赛信息

| 项目 | 内容 |
|------|------|
| 赛道 / 组别 | **自主选题赛道 · 初级组**（选题指南 §3.3） |
| 器件合规 | 初级组器件范围允许 AMD 7 Series / **Zynq-7000** / UltraScale(+)；本作品为 `xc7z020clg484-2` ✓ |
| 提交结构 | 按 §3.3.5.4 推荐目录：`README.md src/ sim/ build/ board/ data/ skill/ report/`（路径全英文） |
| 板级验证 | 已在板上跑通并给出实测判据（`report/V6_BOARD_MEASUREMENT.md`、`data/measured/`） |

> 考察侧重（初级组）= 逻辑设计、状态机、时序约束、接口协议等基本 FPGA 设计能力：
> 见 `src/rtl/eth/`（自写 RGMII/ARP/ICMP/UDP 协议栈与 FIFO）、
> `src/rtl/video/frame_commit_lock.v`（状态机 + 消隐窗口时序约束）、
> `build/timing_summary.rpt`（WNS +0.675 ns、0 违例）。

## 版本说明

| 分支 | 说明 |
|------|------|
| **`main`（当前）** | **第四版**：PL 以太网视频流水线 + 效果 / 旋转 / 右屏无极缩放，并修复入包链丢字（V6.1–V6.4） |
| `v1-ps-ethernet` | 初版：**PS 以太网**（UDP → PS → DDR，PL 经 HP0 读出；来自 [Zynq_Video_Pipeline](https://github.com/Uie-v-uiE/Zynq_Video_Pipeline)） |
| `v2-pl-ethernet` | 第二版：**PL 以太网**（PL 硬件 RGMII/UDP 协议栈；来自 [Video_Pipeline](https://github.com/Uie-v-uiE/Video_Pipeline)） |

第三版（V6 修复之前、含拖影问题的状态）没有单独留分支，它就是 `main` 的父提交链，
用 `git log --first-parent` 或 `git checkout 7cde28d` 即可回到该状态；
第四版相对第三版的改动全部记录在 `report/V6_ROOT_CAUSE.md` 与 `report/OPTIMIZATION_LOG.md`。

```bash
git fetch origin
git checkout main            # 第四版（默认分支）
git checkout v1-ps-ethernet  # 初版
git checkout v2-pl-ethernet  # 第二版
```

### 第四版相对第三版改了什么（一句话版）

屏幕上的「红块撕裂 + 拖影 + 黑横纹」不是显示侧问题，而是 **UDP→DDR 入包链在按固定相位丢字**：
打包器 `axi_frame_saver64` 每写一个 64 bit 字都要等 AXI 写响应 B，在途深度恒为 1，
吞吐被 HP0 往返延迟钉死在 ≈20 MB/s（主机给 15 MB/s，只有 1.3× 余量），显示拷贝一抢端口
就掉到 15 以下 ⇒ 每个 1392 B 包从第 48 字节起按 16 bit 粒度被丢弃。
V6.3 把写通道改成流水化（AW/W 同拍挂出、`OST=8` 在途、B 只回收计数），
板级回读从「最新帧占 42~52%」变成 **100.0%（15/30/60 fps 三档，包内各字节带丢字率 0.0%）**。
随后 V6.4 补掉一个更早的隐患：`WSTRB` 原来恒为 `0xFF`，所以分包长度不是 8 的倍数时
同一个 64bit 字会被相邻两包各推一次、后一次把前一次覆盖成 0 ⇒ 屏上出现**均匀散布的黑点**
（1396 B 分包实测每帧 111 处）。现在 `WSTRB` 按 16bit lane 生成，硬件对分包长度免疫
（1396 复测：命中率 100.0%、空洞 0；仿真 `+MISALIGN` 修复前 38290/38400、修复后全对）。
完整根因、判据方法与复测数据：`report/V6_ROOT_CAUSE.md`、`report/V6_BOARD_MEASUREMENT.md`。

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
│   └── results/regression_v6.txt   第四版回归结果（28/28 PASS）
├── build/
│   ├── tcl/           Vivado 可复现构建 / 下载脚本
│   ├── system.bit     比特流（V6.3）
│   ├── system.xsa     Vitis 硬件平台
│   └── *.rpt          时序 / 资源 / CDC / 方法学报告
├── board/             上板说明与不看屏幕的复验方法
├── data/
│   ├── golden/        金标参考图
│   └── measured/      JTAG 回读实测输出与判据文本
├── skill/             可复用技能包（含 zynq-video-rtl-debug/）
└── report/            架构、优化、性能、根因与协作记录
```

---

## 快速开始

### 1. 生成比特流与 XSA

```bat
cd /d <仓库根目录>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
:: 从零建工程（PS7 + AXI GPIO + HP0 + src\rtl）并出 bit / XSA / 四份报告
%VIVADO% -mode batch -nojournal -log build\build_v6.log -source build\tcl\build_v6.tcl
```

产物：`build/system.bit`、`build/system.xsa`、`build/timing_summary.rpt`、
`build/utilization.rpt`、`build/cdc.rpt`、`build/methodology.rpt`（仓库内若已有可跳过）。
V6.3 实测：WNS **+0.675 ns**、WHS +0.053 ns、111287 端点 0 违例；
Slice Registers 52687（49.52%）、Block RAM 138.5/140（98.93%）。

> 也可分两步：`build/tcl/build_system_axigpio.tcl` 建工程，`build/tcl/build_bitstream.tcl` 出流。
> 已有 `.xpr` 时：`... build\tcl\build_v6.tcl -tclargs D:\path\to\xxx.xpr`。

### 2. 下载比特流

```bat
:: 先起 PS（DDR + FCLK_CLK0=100MHz），再配 PL，最后写 AXI GPIO
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat
%XSDBAT% build\tcl\ps_jtag_boot.tcl   :: 需要 Vitis 平台生成的 ps7_init.tcl，见脚本头
%VIVADO% -mode batch -source build\tcl\program_pl.tcl
%XSDBAT% build\tcl\set_src.tcl         :: 0x41200000 = 0x00010000（SRC1=视频、特效关闭）
```

### 3. （可选）下载 PS ELF — 串口命令需要

1. Vitis 打开工作区，Platform 指向 `build/system.xsa`
2. 应用源码：`src/ps/main.c`
3. Build → Run

> 下载 bit 后 PS 会复位，需再次 Run ELF，串口才有效。  
> 仅观察右屏自动缩放时，下载 bit 即可。

### 4. 仿真（28 个 testbench）

```bat
%VIVADO% -mode batch -nojournal -log sim\xsim.log -source sim\run_sim.tcl
:: 只跑某几个 / 带 plusargs：
::   set SIM_TB=tb_v6_ingress_integrity & set SIM_ARGS=+FULL
:: 结果留档见 sim/results/regression_v6.txt（第四版 28/28 PASS）
```

### 5. 上位机推流

```bat
:: A. Node.js 版（无需任何依赖，含验收用的自描述图案）
node src\host\video_sender.mjs --fps 15 --test move          :: 四象限+红块（看拖影）
node src\host\video_sender.mjs --fps 15 --count 200 --test frameid
node src\host\measure_v63.mjs --fps 15 --count 200           :: 推流→停→JTAG 回读→相位判据

:: B. Python 版（推 mp4 / 摄像头，需要 ffmpeg）
pip install -r src\host\requirements.txt
cd src\host && run_sender.bat && run_video.bat D:\path\to\video.mp4
```

PC 网卡：`192.168.1.100/24`，网线接 **板卡 PL 网口**。默认已开 15 MB/s 帧内限速。
详见 `src/host/HOST_GUIDE.md` 与 `board/README.md`。

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
单包载荷：推荐 **1392 字节**（8 的倍数）。v6.4 起打包器按 16bit lane 驱动 `WSTRB`，
分包长度不再影响正确性；但取 8 的倍数仍可少发约 0.3% 的重复 beat，并保持
「一个包不跨两个 64bit 字」这个便于分析的性质。历史上 1396 会在屏上留下
**均匀散布的黑点**（每帧约 111 处 4 字节洞），机理与实测见 `report/ISSUES.md` #29。
```

板端按 offset 写帧缓；乱序可拼对；丢包丢弃，下一帧恢复。

---

## 文档

| 路径 | 内容 |
|------|------|
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) | 上位机使用说明 |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | 数据通路、时钟、带宽 |
| [report/MODULES.md](report/MODULES.md) | 模块说明 |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) | 时序 / 功耗优化记录（含第四版 V6.x 逐条措施） |
| [report/PERF_REPORT.md](report/PERF_REPORT.md) | 性能与资源报告（含 §10 第四版对比表） |
| [report/ISSUES.md](report/ISSUES.md) | 问题清单（含 [v4] 入包链丢字组 + 症状速查表） |
| [report/V6_ROOT_CAUSE.md](report/V6_ROOT_CAUSE.md) | **第四版根因分析**：判据方法、三次方向纠正、V6.3 修复 |
| [report/V6_BOARD_MEASUREMENT.md](report/V6_BOARD_MEASUREMENT.md) | **第四版板级复测单**：15/30/60 fps 数据、观察项、已知残留 |
| [report/AI_COLLABORATION.md](report/AI_COLLABORATION.md) | 大模型协作记录：提示—判断—被数据推翻的过程与技能包提炼 |
| [skill/README.md](skill/README.md) | 技能包索引（S1–S9） |

---

## 设计要点

- **DDR 乒乓 + V-blank 原子换帧**：入包写 `0x1000_0000 / 0x1008_0000` 两个 bank，
  `frame_commit_lock` 把「新帧就绪」锁到显示消隐窗口上升沿才启动整帧拷贝，
  拷贝未完不换 bank ⇒ 屏幕上不可能出现两帧逐字混合（撕裂）。
  预算：一帧 38400 拍 ÷ 67200 个 axi 周期 = 0.571 拍/周期 ≈ 457 MB/s，实测未越窗。
- **入包写吞吐 = 在途深度 × 64bit ÷ 往返延迟**：`axi_frame_saver64` 一旦逐字等 B 响应，
  在途深度恒为 1 ⇒ 20 MB/s 封顶（这就是第四版之前的拖影根因）。V6.3 流水化后由握手决定。
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

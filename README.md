# 多源视频流多效果变换处理系统

Zynq-7020 上的一条完整视频通路：网线进来，屏幕出去，中间不经过 CPU。

上位机把 512×300、RGB565 的画面切成 UDP 报文发到板上，PL 从 RGMII 一路收到 DDR，再从 DDR 读回来做几何与效果，最后送到 1024×600 的 HDMI。屏幕中间有一条可调的竖缝，左边是原图，右边是同一帧的处理结果。CPU 只负责发命令，不碰一个像素。

## 为什么是这样

这条通路的起点是一个很具体的问题：远端看到的画面，到底是不是完整的、处理过的、当前这一帧？把它拆开就是三个追问——帧收全了吗，处理真的发生了吗，出了问题能不能说清原因。

第一个追问定下了**帧提交的三条件**：整帧字节到齐、每一行都被写过、没有坏包，三条同时成立才换页。所以缺一包的帧不会以半帧或黑条的形式出现，而是根本不出现，屏幕停在上一帧。

第二个追问定下了**同帧对照**：竖缝两侧不是两路视频，而是同一帧的两个取数窗口，共用同一套坐标算子和同一条固定节拍的效果链。缝上的差异只可能来自算法，不会来自两次独立的缩放。

第三个追问定下了**板上的仪表**：作废帧、缺行、坏包、帧间隔、处理窗完整性都做成计数器，串口、网口和 GPIO 读到的是同一组数，并且可以用人为丢包把表打红。

这三件事也决定了"不用现成 IP"：厂商的视频通路把帧当流来搬，中间没有位置放"这一帧收全了吗"的判断，更不会为了对照留两个取数窗口。于是从 RGMII 采样、CRC、ARP/ICMP/UDP、按偏移拼帧、DDR 乒乓，到旋转、缩放、双线性、六级效果、OSD 和 HDMI 时序，全部自己写；器件相关的部分收敛到时钟、DDR 接口和串行器这几处原语。

## 功能

- **三路片源**：网口 UDP 推流、SD 卡裸帧回放、PL 自绘测试图卡，运行时切换，共用同一条显示通路。
- **几何**：0–359° 任意角旋转、八档 0.25×–2.00× 缩放、双线性插值与最近邻可切；倍率可跟随角度自动定标，保证旋转后整幅仍在屏内。
- **效果链**：灰度、反色、3×3 模糊、3×3 锐化、Sobel 边缘、二值化（含判决反相）、腐蚀、膨胀，加一级可旁路的 gamma；九位控制字任意组合，整链延迟固定。
- **同帧 A/B**：竖缝在屏幕列或画面列两种坐标下可调，可左右换位、可隐藏分界线。
- **OSD**：片源与分辨率、帧率、效果投影、角度、倍率、缝位、PL 内时延、片上温度。
- **观测**：串口 `stat`/`temp`/`link`、1 Hz UDP 遥测、AXI GPIO，三处读同一组计数。
- **交互**：板载按键调角度，串口命令控制片源、缩放、效果、分割线与回放。

## 数据流

```text
上位机 ──UDP 5001──> RGMII ─> MAC ─> UDP 过滤 ─> 按帧内偏移重组 ─> 帧提交三条件
                                                                   │
                                                                   ▼
                                                          DDR 乒乓缓存（AXI HP）
                                                                   │
                                      ┌────────────────────────────┴───────────┐
                                      ▼                                        ▼
                              左窗：原图（直通）                    右窗：几何 + 六级效果
                                      └───────────────┬────────────────────────┘
                                                      ▼
                                              OSD 叠字 ─> 1024×600 HDMI
```

PS 只经串口和 AXI GPIO 下发控制字；帧数据不经过 ARM 核。

## 快速开始

```bash
# 1. 建工程、块设计、综合、实现、位流、XSA 与报告
vivado -mode batch -source build/build.tcl

# 2. 跑台架（ModelSim；也可用 build/sim/run_sim.tcl 走 xsim）
MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh rows udp_reasm reasm_bounds \
     udp_telemetry eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor

# 3. 编译 PS 应用（不需要打开 Vitis IDE）
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> PS_OUT=board/project/ps_app.elf \
python build/ps/build_ps_app.py

# 4. 上板并固化
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
VP_HW_URL=localhost:3121 vivado -mode batch -source board/tcl/flash_qspi.tcl

# 5. 推流与观测
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
node src/host/uart_cmd_check.mjs --port COM6
```

完整步骤和每条命令的预期结果在 [`report/reproduction.md`](report/reproduction.md)，串口命令逐条说明在 [`report/commands.md`](report/commands.md)。

## 目录

```text
src/rtl/            PL 源码：顶层、以太网、显示、几何、效果、AXI、HDMI
src/ps/             PS 裸机：main.c、sd_play.c、链接脚本
src/constraints/    引脚、时钟组、准静态 CDC、候选 IO 窗
src/host/           推流、遥测、仪表、自检、串口判据
sim/                仿真台架；sim/results/ 汇总最终判定
build/build.tcl     Vivado 主入口
build/tcl/          Vivado 构建与 board 工程 staging TCL
build/vitis/        Vitis 平台重建脚本
build/ps/           PS 应用直接编译脚本
build/sim/          xsim / ModelSim 运行入口
build/reports/      时序、资源、CDC、功耗、回归与完整视频台架
board/vivado/       Vivado 工程（.xpr + .srcs）
board/vitis/        Vitis 平台描述与 QEMU 参数
board/project/      位流、XSA、PS 应用
board/scripts/      上板、健康检查、串口、镜像打包
board/tcl/          JTAG、QSPI 单步脚本
board/measured/     板上实测日志
board/flash/        BOOT.bin 与打包日志
board/compare/      实测与参考结果的比对
data/inputs/        测试向量
data/golden/        人眼比对参考图
report/             设计、验证、优化、复现、命令手册、接口表、局限
```

## 文档

| 文档 | 内容 |
|---|---|
| [`report/design-report.md`](report/design-report.md) | 设计报告：目标、方案、关键技术、取舍 |
| [`report/verification.md`](report/verification.md) | 验证策略、台架判定与板级结果 |
| [`report/optimization.md`](report/optimization.md) | 时序与资源的优化过程，含被否决的方案 |
| [`report/reproduction.md`](report/reproduction.md) | 从空目录到点亮的完整步骤 |
| [`report/commands.md`](report/commands.md) | 串口命令手册 |
| [`report/interface-table.md`](report/interface-table.md) | 寄存器与接口表 |
| [`report/limits.md`](report/limits.md) | 边界与已知限制 |
| [`report/issues/key-issues.md`](report/issues/key-issues.md) | 关键问题台账：根因与判据 |
| [`sim/README.md`](sim/README.md) | 台架索引与判定口径 |

## 实测

- 8 秒推流收到 241 帧，29.95 fps；干净流下作废计数不增长。
- 灰度单级 + 画面坐标竖缝、185° 旋转下，处理窗完整性计数为 0 且有效。
- 三阶段故障注入：干净流 22.0 fps → 每 100 包丢 1 包时 0 fps、作废约 14.3 次每秒 → 恢复 18.9 fps。
- 停流重启后，硬件记住的最大帧间隔为 22 061 ms。
- 位流写入 QSPI 后断电重上自启，串口 `stat`/`link` 有回显。

## 边界

遥测时延只覆盖 PL 内部（帧提交到开始扫描），不是玻璃到玻璃。RGMII 发侧在 HR bank 上没有 ODELAYE2，0° 转发仍有约 0.845 ns 的 TskewT 保持缺口，90° 与 −45° 两条补偿路线都在板上被否决。画幅停在 512×300 是因为整帧缓存要装进片内 BRAM，再大就得换存储架构。逐条说明在 [`report/limits.md`](report/limits.md)。

## 许可

MIT，见 [`LICENSE`](LICENSE)。

[English version](README_EN.md)

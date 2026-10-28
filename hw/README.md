# 上板工程、脚本与实测输出

`hw/` 放四类东西：板上运行的位流/XSA/固件、可重建的 Vivado 与 Vitis 工程、上板脚本、实测输出。

## 1 板上三件套

| 文件 | 是什么 |
|---|---|
| `project/system.bit` | PL 位流，显示与以太网主通路 |
| `project/system.xsa` | 与位流同批导出的硬件描述，供 Vitis 建平台 |
| `project/ps_app.elf` | PS 裸机应用，命令解析、SD 回放、温度与链路读数 |

三件套按 md5 核对身份，不靠文件名认版本。生成命令与校验值以构建输出为准。

## 2 Vivado 工程

`vivado/zynq_video_sys.xpr` 与 `vivado/zynq_video_sys.srcs/` 是从构建 TCL 生成并整理过的工程，包含：

- 器件 `xc7z020clg484-2`；
- 92 份手写 RTL、1 份 BD wrapper、1 个块设计、3 份生效约束；
- 块设计 `design_1`、PS7 配置、AXI GPIO 与 AXI HP0；
- 源文件路径使用 `$PPRDIR/../../src/...`，工程内没有本机绝对路径。

先跑 `scripts/build.tcl`，产生 `vivado_system/` 与 `scripts/system.bit`/`system.xsa`；再重建并验证：

```bash
vivado -mode batch -nojournal -log scripts/stage.log \
  -source scripts/tcl/stage_board_projects.tcl
```

期望结果：

```text
VERIFY missing_files=0 of 97
VERIFY abs_path_lines=0
STAGE_BOARD_PROJECTS DONE
```

工程不带 `.gen/`、`.runs/`、`.cache/` 等构建产物。BD wrapper 已在 `.srcs/` 内；打开工程后直接综合，Vivado 会按 `design_1.bd` 生成其余输出产物。完整位流由 `scripts/build.tcl` 一条命令构建。

## 3 Vitis 平台

`hw/vitis/` 是平台工程描述：

| 文件 | 内容 |
|---|---|
| `vitis-comp.json` | 两个 domain：`zynq_fsbl` 与 `standalone_ps7_cortexa9_0`；硬件指向 `hw/project/system.xsa` |
| `resources/` | 三个 `qemu_args.txt` |

重建平台与 FSBL：

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<工作目录> <Vitis>/bin/vitis.bat \
  -s scripts/vitis/rebuild_vitis.py 8879
```

期望结果：`Platform Build Finished successfully.`、`GENERATE_RC 0`，并生成 `zynq_fsbl/build/fsbl.elf`。Vitis 2025.2.1 的 `create_app_component` 在本域返回 `StatusCode.INTERNAL`，应用组件建不出来；PS 应用不依赖 IDE，由 `scripts/ps/build_ps_app.py` 直接编译。

PS 应用：

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

## 4 JTAG 上板

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat \
VP_VIVADO_BIN=<Vivado>/bin \
bash hw/scripts/board_flash.sh
```

脚本依次做：扫链、PS `ps7_init`、下载 PL、下载 ELF、回读 AXI GPIO。末行 `FLASH: GREEN` 才算通过。`--check` 只做前置检查与只读扫链，不碰板子。

健康快照：

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash hw/scripts/board_health.sh
```

只读拍一张：串口 `stat,temp,stat`、JTAG 读 GPIO 与 DDR 头、三条异常向量，末行 `HEALTH: GREEN` 才算通过。

## 5 QSPI 固化与冷启动

```bash
VP_VIVADO_BIN=<Vitis>/bin bash hw/scripts/make_boot_image.sh
VP_HW_URL=<host:port> vivado -mode batch -source hw/tcl/flash_qspi.tcl
```

`make_boot_image.sh` 把 FSBL、位流和应用打成一个 `flash/BOOT.bin`；`boot.bif` 里的路径相对 BIF 文件本身，不写本机盘符。`flash_qspi.tcl` 擦除、写入并做硬件回读比对，末行 `PROGRAM_RC 0` 才算通过。写入后断电重上，在串口看启动回显；JTAG 下载是易失的，QSPI 才是断电自启的交付物。

## 6 串口命令

串口是 USB-C 桥的 B 通道，`COM6`，115200 8N1。常用命令：

| 命令 | 作用 |
|---|---|
| `stat` | 控制状态、帧计数、效果选择、几何字 |
| `temp` | XADC 温度、VCCINT、OSD 编码与 GPIO 回读 |
| `link` / `link clr` | 帧间隔的最近值、最小/最大值、累计值和清零 |
| `src auto\|0\|1\|2` | 片源自动、图卡、网络、SD |
| `pipe <九位>` / `pipe show` | 效果链 |
| `zoom on\|off\|auto\|<倍率>` | 缩放 |
| `rot auto\|0\|1` / `rot speed 0..7` | 自动旋转与每帧角度 |
| `split screen\|video <0..100>` | 竖缝模式与位置 |
| `sd files` / `sd file n` / `play` / `stop` | SD 选段、播放、停止 |

串口一次只能被一个程序占用；查看寄存器前先停止推流，流在跑时读到的是中间值。

## 7 网络与主机工具

板卡地址 `192.168.1.10`，PC 地址 `192.168.1.100`，PL 侧 RJ45 直连千兆。

```bash
ping 192.168.1.10
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
```

遥测从 UDP 1234 发出，发给最后一个 ARP 请求方；先 ping 一次板子，再启动监听。Windows 防火墙可能拦截 UDP 1234。

## 8 实测输出

`measured/` 只放支撑结论的一手日志：

| 文件 | 内容 |
|---|---|
| `qspi_program.txt` | QSPI 擦除、写入、回读校验 |
| `cold_boot.txt` | 断电重上后的启动模式、PL 状态、串口回显 |
| `flash_jtag.txt` | JTAG 三步链与 GPIO 回读 |
| `health.txt` | 串口 + JTAG + 异常向量 + XADC 温度快照 |
| `telemetry_8s.txt` | 8 秒推流的 1 Hz 遥测 |
| `link_selftest.txt` | 干净 → 丢包 → 恢复三阶段自检 |
| `uart_battery.txt` | 105 条串口命令电池 |
| `link_gap.txt` | `link clr`、推流、停流后的帧间隔统计 |

历史轮次的原始日志不放在提交目录；需要追溯时看本机归档或 Git 历史。

## 9 人眼验收

机器判不了屏幕。以下三条由现场签收：

- 竖缝两侧是同一帧的原图与处理图，几何关系一致；
- 缩放或旋转时不出现整行错位；
- OSD 各格读数与串口 `stat`、`temp` 一致。

逐项状态与签收人写在 `acceptance.md`。

## 10 目录

```text
project/          位流、XSA、PS 应用
vivado/           Vivado 工程（.xpr + .srcs）
vitis/            Vitis 平台描述
compare/          实测与参考结果对账
tcl/              JTAG、QSPI、工程 staging 脚本
scripts/          一键上板、健康快照、UART、镜像打包
measured/         一手实测日志
flash/            BOOT.bin 与打包日志
```

## 11 注意

- JTAG 报 `Cannot halt processor core` 时，先断电重上，再跑 `board_flash.sh`；不要靠反复 `rst -system` 硬顶。
- 改 PS 固件后必须重编 ELF、重刷、再重打 BOOT.bin；只重编不重刷，板上仍是旧固件。
- 重打 BOOT.bin 后 QSPI 里的镜像不会自动更新，必须重新写 flash 并断电验证。
- 查看寄存器前停止推流；推流中读到的计数是中间值，不是稳定快照。

## 12 保留与移除

取舍标准只有一条：能重建、能复现、或能支撑报告里一个结论的留下；旧轮读数、一次性破坏性探针、被新脚本替代的旧脚本、重复 TCL 去掉。不是按“功能大不大”删。

### 12.1 核心保留

| 内容 | 为什么必须留 |
|---|---|
| `project/system.bit`、`.xsa`、`ps_app.elf` | 板上实际运行的三件套；md5 是身份 |
| `flash/BOOT.bin` | QSPI 冷启动的镜像 |
| `vivado/`、`vitis/` | 可重建的上板工程；不是构建产物副本 |
| `scripts/`、`tcl/` | 上板、健康、UART、QSPI、JTAG 的运行入口 |
| `measured/` 中的当前证据 | 冷启动、帧间隔、遥测、自检、电池、温度、QSPI 回读 |
| `compare/`、`measured/README.md` | 实测与参考结果的对照口径 |

### 12.2 支持性保留

| 内容 | 性质 |
|---|---|
| `measured/pane_integrity.txt` | 显示侧同一 RTL 的 185° 证据；不是本次构建新测，但支撑处理窗结论 |
| `measured/sd_playback.txt` | SD 续播证据；`link` 改动不涉及 SD 路径 |
| `measured/uart_battery_capture.txt` | 105 条命令电池的原始捕获，供逐条复核 |
| `measured/flash_jtag.txt` | JTAG 三步链证据；QSPI 冷启动另见 `cold_boot.txt` |
| `flash/bootgen.log` | 镜像打包日志，证明 BOOT.bin 的生成过程 |

这些文件都很小；删掉不会影响构建，但会让报告里的对应结论失去板上证据，所以保留并标明性质。

### 12.3 移除的内容

| 内容 | 为什么去掉 |
|---|---|
| `output/`、旧 `compare/` 的 cdc/roster/temp/ddr 日志 | 旧轮读数，和当前交付结论不同批；留着会让人拿旧数对当前结论 |
| `raw-vs-golden.md`、`signoff*.md`、`demo_rehearsal.txt` | 旧的人眼/签收记录，已被 `acceptance.md` 与当前实测替代 |
| `uart_capture.txt`、`uart_script_capture.txt` | 每次跑都重写的本机捕获；原始电池捕获已以中性名保留 |
| `cmd_overflow_probe.sh` | 一次性、可能把命令通道钉死的破坏性探针；不属于交付验收 |
| `rebuild_project.sh`、`stage_vitis_platform.sh`、`serial_bytes.ps1` | 被 `scripts/build.tcl`、`scripts/vitis/rebuild_vitis.py`、`uart_cmd_script.ps1` 替代 |
| `sd_boundary_0deg.txt` | 旧轮 SD 边界读数 |
| 旧 `tcl/probe_flash_read.tcl`、`program_and_check.tcl`、`program_system.tcl` | 一次性探针或重复流程；保留的是实际使用的 JTAG/QSPI 脚本 |
| `stage_board_projects.tcl` | 已移到 `scripts/tcl/`，它属于构建链，不属于板上运行脚本 |

一句话：核心文件是“重建/上板必需”，支持性文件是“报告结论的证据”，移除的是“旧轮、一次性、被替代”。


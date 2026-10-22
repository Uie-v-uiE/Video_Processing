# 复现

复现分五步：拿到源码、构建位流、跑台架、构建 PS 应用、上板或固化 QSPI。每一步都给出前置条件、命令和期望结果；没有期望结果的操作不算一步。

## 1 前置条件

| 项 | 要求 |
|---|---|
| 器件 | `xc7z020clg484-2`，Zynq-7020 开发板 |
| 工具 | Vivado / Vitis 2025.2.1；Vitis 自带 `arm-none-eabi-gcc` |
| 主机 | Windows 10/11 或 Linux；Python 3.10+；Node.js 18+（可选，主机工具） |
| 板卡 | PL 侧 RJ45、HDMI 输出、microSD、QSPI、USB-C JTAG/UART 桥 |
| 网络 | PC 有线网卡 `192.168.1.100/24`，板卡 `192.168.1.10/24`，直连千兆 |
| 串口 | FT4232 的 B 通道，`COM6`，115200 8N1 |
| 显示 | 1024×600 HDMI 面板 |

工具路径用环境变量传入，脚本里不写死任何机器路径。

## 2 目录

```text
src/rtl/          PL 源码
src/ps/           PS 裸机固件
src/constraints/  引脚、时钟、CDC 约束
src/host/         PC 侧推流、遥测、仪表、自检
sim/              台架
build/tcl/        构建入口
build/sim/        仿真入口
build/checks/     机检脚本
build/reports/    实现报告
board/            Vivado/Vitis 工程、上板脚本、实测输出
data/             测试输入、金标图像、指标表
skill/            技能包
report/           设计与验证文档
```

## 3 构建位流

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
```

脚本建工程、建块设计、综合、实现、出位流、XSA，并生成时序、资源、CDC、方法学和功耗报告。产物默认在 `build/` 与 `vivado_system/`。只建工程和块设计：

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl -tclargs bd_only
```

期望结果：`BD_ONLY_DONE` 或完整构建结束时的 `BITSTREAM`/报告生成行；时序报告的失败端点为 0。

## 4 重建 Vivado 工程

`board/zynq_video_sys.xpr` 是从构建脚本生成并整理过的工程。重建：

```bash
vivado -mode batch -nojournal -log build/stage.log \
  -source board/tcl/stage_board_projects.tcl
```

期望结果：

```text
VERIFY missing_files=0 of 102
VERIFY abs_path_lines=0
STAGE_BOARD_PROJECTS DONE
```

102 是源文件与约束文件的总数；`missing_files=0` 表示复制出来的工程每个文件都在盘上；`abs_path_lines=0` 表示工程文件里没有本机绝对路径。打开工程后应看到器件 `xc7z020clg484-2`、约束集和块设计。

## 5 重建 Vitis 平台

Vitis 平台描述在 `board/vitis_platform/`。重建平台与 FSBL：

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<工作目录> <Vitis>/bin/vitis.bat \
  -s board/scripts/rebuild_vitis.py 8879
```

期望结果：`Platform Build Finished successfully.`、`GENERATE_RC 0`，并生成 `zynq_fsbl/build/fsbl.elf`。Vitis 2025.2.1 的 `create_app_component` 在本域会返回 `StatusCode.INTERNAL`，这是工具限制；PS 应用不依赖 IDE，直接用下一节的编译脚本。

## 6 构建 PS 应用

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<平台构建生成的 BSP 目录> \
PS_OUT=board/project/ps_app.elf \
python build/build_ps_app.py
```

期望结果：`ENTRY _boot@... _vector_table@... OK`、`OK board/project/ps_app.elf`，`.text` 约 60 KB。脚本会检查 `_start`、`_boot`、`_vector_table`、`MMUTable`、`main` 和 `XSdPs_CardInitialize` 是否在 ELF 里，防止把空镜像下到板上。

## 7 跑台架

快速回归：

```bash
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
```

完整视频台架与专项台架：

```bash
bash build/sim/run_msim.sh video_pipeline_top
```

期望结果：每支台架末尾有 `RESULT ... PASS`；完整视频台架的 C17/C25/C26 专项 PASS，nfail=0。没有判定行的日志不算通过。

## 8 上板（JTAG）

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat \
VP_VIVADO_BIN=<Vivado>/bin \
bash board/scripts/board_flash.sh
```

脚本依次做：扫链、PS `ps7_init`、下载 PL、下载 ELF、回读 AXI GPIO。期望结果：

```text
FLASH: GREEN
```

健康快照：

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash board/scripts/board_health.sh
```

期望结果：串口有 `[STAT]`，JTAG 读到 GPIO 与 DDR 头，三条异常向量为 0，`HEALTH: GREEN`。

## 9 网络与主机工具

```bash
ping 192.168.1.10
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
```

期望结果：

- 8 秒推流约 241 帧，30 fps；
- 13 秒收到 13 个 1 Hz 遥测包，帧计数连续增长；
- 三阶段自检 `PASS`：干净流 ≥ 8 fps，故障段作废 ≥ 5 次/秒且帧率 < 5 fps，恢复流回到干净流水平。

串口命令电池：

```bash
node src/host/uart_cmd_check.mjs --port COM6
```

期望结果：全部命令按预期回声，末态回到初态。

帧间隔统计：

```text
link clr
link
```

期望结果：`gap_last/min/max/sum` 有值，`gap_valid=1`；停流后 `gap_last` 增大，`gap_max` 更新。

## 10 QSPI 固化

```bash
bash board/scripts/make_boot_image.sh
VP_HW_URL=<host:port> vivado -mode batch -source board/tcl/flash_qspi.tcl
```

期望结果：

```text
Erase Operation successful.
Program Operation successful.
Verify Operation successful.
PROGRAM_RC 0
```

写入后断电重上，在串口看启动回显，再跑 `ping`、`stat`、`link` 和遥测。QSPI 镜像包含 FSBL、位流和应用；JTAG 下载是易失的，断电后会回到 QSPI。

## 11 常见问题

**JTAG 报 `Cannot halt processor core`。** PS 可能停在异常状态或 QSPI 启动过程中。先断电重上，再跑 `board_flash.sh`；不要靠反复 `rst -system` 硬顶。

**串口没有回显。** 确认 COM6 没有被终端占用；确认波特率 115200；确认 PL 已配置、PS 应用已下载。`health_read` 的 JTAG 段能读到 GPIO 和 DDR 头，说明 PL 与总线是活的，问题在 PS 或串口。

**ping 不通。** 先确认 PC 网卡是 `192.168.1.100/24`，板卡是 `192.168.1.10`；再确认网线在 PL 侧 RJ45，不是 PS 网口；最后跑 `board_health.sh` 看 PL 是否配置。

**遥测收不到。** 信标发给最后一个 ARP 请求方；先 ping 一次板子，再启动监听。Windows 防火墙可能拦截 UDP 1234。

**SD 不播放。** 先 `sd remount`，再 `sd files` 看卡上段；`sd file n` 选段后 `play`。卡必须是 FAT32，帧序列由 `src/host/make_sd_video.mjs` 生成。

**Vivado 工程打开报 output products 缺失。** 工程文件只带源与约束；块设计的 output products 在 `.gen/` 里，不入库。跑一次 `bd_only` 或完整构建就会生成。

# 复现说明

这份文档从一台空机器开始，写到能在板上看到画面、读到遥测、跑完自检。命令都在仓库根目录执行，工具路径按本机安装位置替换。

## 0. 先定判定口径

复现不是“跑完没报错”。每一步都要有判定行或读数：

- 构建：实现后 WNS、WHS、TNS、THS，失败端点，资源占用。
- 仿真：台架自己的 `RESULT ... PASS` 或 `MSIM DONE fail=0`。
- 上板：ping、帧数、作废、时延、自检 PASS。
- 身份：位流、XSA、固件的 md5 与 `board/README.md` 一致。

读不到输入时写“没测到”，不写“通过”。

## 1. 环境

器件是 `xc7z020clg484-2`。工具是 Vivado / Vitis 2025.2.1、ModelSim SE-64 2020.4、Python 3.12、Node 24。串口是 COM6、115200 8N1。PC 网卡静态地址 `192.168.1.100/24`，板子是 `192.168.1.10`。

本机路径示例：

```text
Vivado:   D:\Software\Vivado\2025.2.1\Vivado\bin
Vitis:    D:\Software\Vivado\2025.2.1\Vitis\bin
ModelSim: D:\Software\ModelSim\modelsim\win64
```

仓库没有 `.git`，所以不要依赖 `git archive` 或提交号；版本身份按位流、XSA、固件的 md5 认。

## 2. 构建

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
```

这条命令建工程、综合、实现、写位流，并把报告放到 `build/`。当前版本用 `build/r162/` 作为产物目录；换目录时设置 `VP_PROJ_SUBDIR` 与 `VP_OUTDIR`，例如：

```bash
VP_PROJ_SUBDIR=vivado_r152 VP_OUTDIR=build/r152 \
  vivado -mode batch -source build/tcl/build_system_axigpio.tcl
```

一次全流程约 20 分钟。综合约 5–6 分钟，实现加 `write_bitstream` 约 7–9 分钟，具体随机器变化。

构建后先看三份报告：

```text
build/r152/timing_summary.rpt
build/r152/utilization.rpt
build/r152/cdc.rpt
```

判定：WNS 与 WHS 为正，TNS 与 THS 为 0，失败端点 0；资源与 `report/04-resources.md` 的表一致。若 WNS 为正但失败端点不为 0，先看报告头是不是同一次实现，不要拿旧报告配新位流。

## 3. 仿真

快速回归用 ModelSim：

```bash
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
```

判定行是 `MSIM DONE fail=0`，每支台架另有自己的 `RESULT ... PASS`。编译日志和逐台架日志在 `build/msim/`。

完整视频台架：

```bash
bash build/sim/run_msim.sh video_pipeline_top
```

它跑满 4,569,600,090 ns，判定行是 `RESULT tb_video_pipeline_top PASS`，0 errors。跑之前确认没有别的 ModelSim 或 xsim 在写同一个 work 目录。

用 xsim 也可以，入口是 `build/sim/run_one.sh <tb>`。脚本会在编译前记录源码指纹，编译失败时不会把旧日志冒充成新结果。

## 4. 上板

### 4.1 装三件套

先起 `hw_server`，再按顺序走三步。顺序不能换：第一步复位系统，第二步配 PL，第三步下载应用并运行。

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat \
VP_VIVADO_BIN=<Vivado>/bin \
VP_BIT=build/r152/system.bit \
  bash board/scripts/board_flash.sh
```

判定：脚本末尾回读 `GPIO@0x41200000`，并打印 `FLASH: GREEN`。如果只做只读检查，加 `--check`，它不会碰板子。

### 4.2 串口与网络

串口打开 COM6，敲 `stat` 应回一行 `[STAT] ...`。PC 网卡配 `192.168.1.100/24`，`ping 192.168.1.10` 应 0% 丢包。

次选：不重新装 PL、只换应用时，可以单独跑 `board/tcl/ps_app_reload.tcl`；它只复位处理器，不碰 PL。

### 4.3 推流、遥测、自检

```bash
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 12
python src/host/link_selftest.py 192.168.1.10 6
```

推流时遥测应显示帧数增长、`lat_ms` 有效、`link=1`；停流后 `lat_ms` 变成 `--`。自检应打印 clean1、fault、clean2 三段并最终 PASS。r156 的参考读数是 240 帧/8.01 秒、29.94 fps，自检 22.2 / 0.2 / 22.0 fps。

### 4.4 串口演示

按 `report/demo_script.md` 走。最短路径是 `src 0`、`split 50`、`split marker 0`、`zoom 1.5`、`rot auto 1`、`pipe 000010000`。屏上第一行应显示 `512X300`，`SRC:` 写当前片源。

## 5. 结果比对

把读回来的数与文档对：

| 项 | 参考值 | 在哪看 |
|---|---|---|
| WNS / WHS | 1.341 ns / 0.025 ns | `build/r171/timing_summary.rpt` |
| 失败端点 | 0 / 56043 | 同上 |
| LUT / FF / BRAM / DSP | 28.13% / 8.55% / 70.00% / 19 | `build/r171/utilization.rpt` |
| 连续流 | 240 帧 / 8.00 s / 30.00 fps | `telemetry_listen.py` |
| 自检 | 18.9 / 0.2 / 22.2 fps | `link_selftest.py` |
| 身份 | `9734f3ec3019` / `f4d4425138a2` / `9ff967573b32` | `md5sum` 与 `board/README.md` |

数值有小的差异是正常的，比如帧率随 PC 和网络状态浮动。差一个数量级，或者身份对不上，就不能算复现成功。

## 6. 平台差异

以上命令在 Windows 的 Git Bash 下跑过。Linux 下需要把工具路径、串口设备名和 `tasklist/taskkill` 那几处换掉；Tcl 脚本本身不依赖平台，但 `board/scripts/*.ps1` 是 PowerShell，Linux 下要改用等价的串口工具。没有在 Linux 上做过完整复现，这一条是边界。

## 7. 不可复现或没做的

**断电自启。** 固件目前是 JTAG 下载，QSPI 里是旧镜像。BOOT.bin 固化需要擦写配置 Flash 并改启动模式，必须由人确认后执行；本次没有做冷启动复验。

**人眼观感。** 屏幕上的模糊是否柔和、边线是否顺眼、185° 底边是否还有肉眼可见的残留，只有看屏幕的人能判。机器读数能证明处理侧没有非灰像素，证明不了显示器和线缆。

**高低温与电压拉偏。** 没有做温度循环和电压余量测试。hold 余量 0.046 ns 是快速工艺角下的静态时序读数，不等于全温区实测。

**PHY 眼图与片外时序。** 没有示波器眼图，也没有量 PHY 到 FPGA 的输入窗。RGMII 的五个收端点当前不在静态时序检查的射程内，这一条是“没测到”，不是“通过”。

## 8. 重建固件（可选）

PS 固件已经从 `src/ps` 重建并上板验证过。要再重建，需要先用当前 XSA 建 Vitis 平台和 standalone BSP，再把 `src/ps/*.c|h` 拷进应用工程，用 `build/build_ps_app.py` 链接。脚本处理了 UTF-8 捕获、startup 汇编路径、非 SDT 的 XADC DeviceId 和只链 `-lxil` 这几处；具体命令与踩坑记录在 `board/README.md` 和 `report/known_issues.md` 第 25 节。

固件重建后必须重新上板跑 `stat`、`temp`、SD 播放和 ETH 推流，才能写成“板上验证过”。只编译通过不算。

# Board bring-up（第四版 V6.x）

相关文档：`report/V6_BOARD_MEASUREMENT.md`（复测数据）、`report/V6_ROOT_CAUSE.md`（根因与判据方法）、
`report/ETH_BRINGUP.md`、`report/BOARD_PINS.md`、`report/AI_COLLABORATION.md`。

## Hardware

- RK-ZYNQ7020-F（`xc7z020clg484-2`），12 V 供电，HDMI **1024×600**，USB-C（JTAG + UART COM6）
- 网线接 **板卡 PL 网口**（PHY2），不是 PS 网口
- PC 有线网卡：静态 `192.168.1.100/24`（板卡 `192.168.1.10:5001`）
- 工具：Vivado / Vitis **2025.2.1**；上位机脚本为 Node.js（无需 python）

## 顺序

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat

%VIVADO% -mode batch -nojournal -log build\build_v6.log -source build\tcl\build_v6.tcl   :: bit + XSA + 报告
%XSDBAT% build\tcl\ps_jtag_boot.tcl  <path\to\ps7_init.tcl>                              :: 起 PS（DDR + FCLK0=100MHz）
%VIVADO% -mode batch -source build\tcl\program_pl.tcl                                     :: 配 PL
%XSDBAT% build\tcl\set_src.tcl                                                            :: GPIO=0x00010000（SRC1、特效关）
ping -n 2 192.168.1.10                                                                    :: 0% 丢包 = PL 网络栈活着
node src\host\video_sender.mjs --fps 15 --test move                                       :: 推流
```

> 交付态可以用 Vitis 里 Run ELF（FSBL）启动 PS；`ps_jtag_boot.tcl` 只是没有 Vitis 工程时的兜底，
> 它不会写 SLCR 里 `FPGA_FCM*` 一类寄存器。两者对本文的判定结论没有影响（判据只依赖 PL 通路），
> 但**性能类结论应以 FSBL 启动为准**。
>
> **2026-09-23 更新（R29）**：跑 PS 应用**不再需要 Vitis/FSBL** —— `build/ps_app.elf` 现在链上了
> 标准启动（`boot.S` 开 CPACR/FPEXC、设 VBAR 与各模式栈、按 BSP 恒等映射打开 MMU），
> 所以纯 JTAG 就能跑：`xsdb build/tcl/ps_app_reload.tcl`（只复位 A9、不动位流），
> 串口应出 `[BOOT]`，实测 `SD` 挂载 + 回放 30.0 fps（判据与坑见 `report/OVERNIGHT_LOG.md` §19、
> ISSUES #42/#44）。上面那条 `set_src.tcl` 在 PS 应用跑起来之后是多余的：应用开机自己写控制字，
> 串口里 `SRC1` / `SRC0` 就是同一件事。`FPGA_FCM*` 那句提醒仍然有效（它只影响性能口径，不影响能不能跑）。

## 不看屏幕的复验（本项目的主要验收手段）

`src/host/measure_v63.mjs` = 推 `frameid` 图案（像素值 = 字号 + 帧号）→ **发完再回读** →
逐 16bit 反解「这个字来自第几帧」→ 打印包内相位丢字率签名。

```bat
node src\host\measure_v63.mjs --fps 15 --count 200
```

判据（V6.3 实测，`data/measured/board_measure_15fps.txt`）：

| 指标 | 修复前 | V6.3 实测 |
|------|--------|-----------|
| 最新帧在自己 bank 的 16bit 命中率 | 42~52% | **100.0%**（15 / 30 / 60 fps 三档） |
| 包内字节偏移 0–48 B / 48 B 之后的丢字率 | 6.7% / 54~64% | **0.0% / 0.0%** |
| u32 内两个 16bit 属于不同帧 | 18.6% | **0 / 76800** |
| 帧号跨度 | 混十几帧 | 相邻两帧（每 bank 恰好一帧） |

已知残留：偶发地，bank 最后一个 64bit 字的高半个 u32（帧的最后 4 字节 = 2 像素）读到 0，
下一帧同地址即被覆盖 ⇒ 肉眼不可见；`sim/tb_v6_ingress_integrity.v +FULL` 不复现，
分析与复现思路见 `report/V6_BOARD_MEASUREMENT.md` §4.1。

## 需要肉眼确认的项

| # | 检查 | 期望 |
|---|------|------|
| 1 | SRC0 彩条（`set_src.tcl` 里改 `0x00000000`） | 干净、无横纹 |
| 2 | `--test move` 动图 | 红块移动处**无拖影**、无固定黑缝 |
| 3 | `--test blocks` + 右屏缩放 | 网格线不再被逐字空洞打断（细线闪烁属缩放算法，非数据问题） |
| 4 | OSD `eth=` / `net_bad=` | 帧计数随推流递增；限速下 `net_bad` 接近 0 |
| 5 | 停流后冻结帧 | 干净（覆盖门限：有空洞就不 commit） |
| 6 | 拔网线 30 s 再插 | 自动恢复推流，不需重下 bit |
| 7 | **（#25 待确认）** 插着线推流 → 停流 | 画面在**零点几秒内**自动交回 SD 播放（不必重配、不必拔线）；#24 在这一条上是红的（判据被退化时钟骗住，见 ISSUES #49） |
| 8 | **（#25 待确认）** 推流过程中 SD 同时在放 | 不出现两路抢画面 / 闪屏；ETH 优先，SD 的发布被挂住等轮次 |

## JTAG 回读的三条硬规则

1. 回读前 `rst -processor`（否则 `mrd` 读到 A9 的 D-Cache），且**不要 `con`**
   （A9 重跑 boot ROM 会把 SD/QSPI 里的旧 bitstream 刷回 PL）；
2. **发完再读**：回读要几秒，边推边读会让每个地址段读到不同时刻的帧；
3. 每次回读都会停住 A9 ⇒ 下一轮复测前重跑 `ps_jtag_boot → program_pl → set_src`。

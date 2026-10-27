# 上板评测路径（已用本机 Vivado 2025.2.1 跑通构建）

## 已完成

| 产物 | 路径 |
|------|------|
| Bitstream + XSA | `fpga/fence_demo.xsa`（约 304 KB，含 bit） |
| Vitis 平台 | `fpga/vitis/platform` |
| **应用 ELF** | `fpga/vitis/app_component/build/app_component.elf`（统一工作区：`vitis_ila/app_component/build/app_component.elf`） |
| 测试集（已链入） | `fpga/software/fence_testset.h` |
| PC 金标准 | `out/board_data/pc_golden.csv` |

## JTAG 运行（板上电后）

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\xsct.bat" "<工程根目录>\fpga\run_classic_ok.tcl"
```

或 Vitis GUI：打开 workspace `fpga/vitis` → 右键 fence_eval → Run As → Launch on Hardware (Single Application Debug)，**JTAG**。

串口：USB-UART，**115200 8N1**。

## 期望串口输出

```text
=== Fence Testset EVAL (Zynq PS / JTAG) ===
scenes=4
EVAL,fence_clean,epochs=121,...
EVAL,fence_urban_mp,epochs=121,...
EVAL,fence_mp_spoof,...
EVAL,fence_denial,...
EVAL,ALL,DONE
See out/board_data/pc_golden.csv for PC reference
```

对照 `pc_golden.csv`：`naive_ff / trusted_ff / hold` 同数量级即通过。

## 构建备注

- 链接需 **-lm**（已在 `Debug/objects.mk` 写入）
- 链接脚本使用 FSBL 的 `lscript.ld` 拷贝
- 重建：`make -C fpga/vitis/app_component/build`（PATH 需含 `Vitis\gnu\aarch32\nt\gcc-arm-none-eabi\bin` 与 `Vitis\gnuwin\bin`）
- 重新导出测试集：`python export_fenceset.py` 后再编译

## Vivado 证据截图

打开 `fpga/vivado_proj/fence_demo.xpr`：

- Block Design
- Utilization（impl_1）
- 与 XSA 文件一起可写入报告附件

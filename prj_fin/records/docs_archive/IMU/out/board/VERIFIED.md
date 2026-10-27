# 板端已验证结论（2026-09-12）

## 通过（可作提交证据）

| 项 | 结果 |
|----|------|
| 程序 | 经典 ELF `fpga/vitis_ws/fence_eval/Debug/fence_eval.elf` |
| 流程 | `fpga` → `ps7_init` → `dow` → `con` → `stop` → `mrd 0xe534` |
| MAGIC | `46454E45` |
| n_scenes | 4 |
| done | 1 |
| clean | naive_ff=0.053, trusted_ff=0.053（与 PC 一致） |

完整对照见 `out/board/jtag_eval_record.md`。

## 已知未通过（不阻塞创意赛）

- **统一 Vitis DDR 应用**：`.vectors` 未真正落到 OCM `0x0`（`mrd 0x0` 为脏数据），启动后跳 `0x8/0x10` 异常。
- **EMIO GPIO / ILA 驱动**：`XGpioPs` 初始化曾导致 CPU/JTAG 跑飞；默认关闭。
- **COM6 串口**：无输出；板端证据用 JTAG 邮箱。

## 创意赛建议

1. **主证据**：PC 数字孪生 `fence_metrics.csv` + 证据图（已有）  
2. **板端加分**：经典 ELF + 邮箱 `mrd 0xe534`（已验证）  
3. **ILA**：可选；需先修好启动再开 GPIO，时间紧可不做  

## 复现（稳定脚本）

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\xsct.bat" "D:\Software\Xiaomi_MiMo\IMU\fpga\run_classic_ok.tcl"
```

若 DAP 卡死：**板断电** 后再跑。

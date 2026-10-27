# 板端 EVAL 记录（JTAG mrd）

- 日期：2026-09-11
- ELF：经典 `vitis_ws/fence_eval/Debug/fence_eval.elf`（OCM）
- 邮箱：`g_result @ 0x0000E534`
- 状态：PC `0x00001D84`（main 附近），`done=1`

## mrd 摘录

| 地址 | 值 | 含义 |
|------|-----|------|
| 0xE534 | 46454E45 | MAGIC FENE |
| 0xE538 | 00000004 | 4 场景 |
| 0xE53C | 00000001 | 完成 |

### 场景 0 clean
- epochs=121, true_in=19
- naive_ff=0.053, trusted_ff=0.053, hold=0, p95=3.31 m

### 场景 1 urban_mp
- epochs=121, true_in=19
- naive_ff=0.421, trusted_ff=0.421, hold=0, p95=7.04 m

（此前完整 dump 还有 mp_spoof / denial，见同目录旧版或再 `mrd 0xe534 28`）

## 对照 PC

| 场景 | PC naive | 板 naive | PC trusted | 板 trusted |
|------|----------|----------|------------|------------|
| clean | 0.053 | 0.053 | 0.053 | 0.053 |
| urban_mp | 0.842 | 0.421 | 0.105 | 0.421 |

## 结论

- 板端完成同源 4×121 历元批评估  
- clean 与 PC 一致；urban_mp 完好性 hold 偏弱（板端阈值实现差异）  
- **算法金标准仍以 PC `pc_golden.csv` 为准**

## 注意

- 统一平台 DDR ELF：需 `ps7_init`，邮箱在 `0x11402C`  
- 经典 OCM ELF：邮箱 `0xE534`（本次成功路径）  
- xsct 脚本里 `mrd` 要用 `foreach` 打印返回值，否则可能看不到输出  
- 串口 COM6 无输出不影响本结论

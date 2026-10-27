# Vitis 截图操作手册（稳定路径）

## 用哪个工程

**用经典工作区（已验证可跑通）：**

```text
<工程根目录>\fpga\vitis
```

**不要**用 `vitis_ila`（DDR 启动有问题，勿截图）。

启动 Vitis：

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\vitis.bat" "<工程根目录>\fpga\vitis"
```

Workspace Directory 填：`<工程根目录>\fpga\vitis`

## 板子准备

1. 板上电，JTAG 接好  
2. **断电再上电一次**（若之前跑过会卡）  
3. 电脑上**只开一个** Vitis，不要同时开 Hardware Manager  

## GUI 操作步骤

### 1. 打开应用

左侧 Project Explorer → **`fence_eval`**

源码在：`fence_eval/src/fence_eval.c` + `fence_testset.h`

### 2. Build（截图点 1）

右键 `fence_eval` → **Build Project**

成功后截图：Console 里的

```text
Finished building target: fence_eval.elf
```

或 Problems 为空。

### 3. Run on Hardware（截图点 2）

右键 `fence_eval` → **Run As → Launch on Hardware**

- 方式选 **JTAG**（不要 SD）  
- 目标：**ARM Cortex-A9 MPCore #0**

若失败：菜单 **Xilinx → Program FPGA** 选  
`<工程根目录>\fpga\vivado_proj\fence_demo.runs\impl_1\system_wrapper.bit`  
（或平台里自带 bit），再 Run。

### 4. 看结果（截图点 3–4）

**方式 A：Memory 视图（推荐，不靠串口）**

1. 若只有 Run，改成 **Debug As → Launch on Hardware**  
2. **Window → Show View → Memory**  
3. 新建 Memory Monitor，地址填：

```text
0x0000E534
```

4. 显示宽度 **4-byte Word**  
5. 等约 10 秒（或 Run 时会刷新）  

**期望值：**

| 地址 | 值 |
|------|-----|
| `0xE534` | `46454E45` |
| `0xE538` | `00000004` |
| `0xE53C` | `00000001` |
| `0xE544` | `00000079`（121） |
| `0xE54C` | `00000035`（clean naive_ff 0.053） |

**方式 B：串口**

115200 8N1。可能无输出，**以 Memory 为准**。

### 5. 建议截图清单

| 文件名 | 内容 |
|--------|------|
| `out/board/01_vitis_workspace.png` | 左侧 fence_eval 工程树 |
| `out/board/02_build_ok.png` | Build 成功 |
| `out/board/03_run_jtag.png` | Run on Hardware / Download 完成 |
| `out/board/04_memory_e534.png` | **Memory 0xE534 指标（核心）** |

### 6. 对照表（写进报告）

| 场景 | 板 naive_ff | 板 trusted_ff | 板 hold |
|------|-------------|---------------|---------|
| clean | 0.053 | 0.053 | 0 |
| urban_mp | 0.421 | 0.421 | 0 |
| mp_spoof | 0.211 | 0.000 | 0.033 |
| denial | 0.263 | 0.053 | 0.033 |

PC 金标准：`out/board_data/pc_golden.csv`

## 一键 TCL（GUI 不顺时用）

```powershell
& "D:\Software\Vivado\2025.2.1\Vitis\bin\xsct.bat" "<工程根目录>\fpga\run_classic_ok.tcl"
```

## 注意

| 事项 | 说明 |
|------|------|
| 工作区 | `fpga/vitis`（经典）与 `vitis_ila`（统一包） |
| GPIO | 源码里 `FENCE_USE_EMIO_GPIO 0`，勿打开 |
| ILA | 不要用 `vitis_ila` 截图 |
| DAP 报错 | 板断电再试 |
| 两个工具抢 JTAG | 只留 Vitis 一个 |

## 答辩话术

> 同源测试集经 JTAG 在 Zynq PS 批处理，结果经调试接口读取，与 PC 金标准对照；clean 场景误扣率一致。

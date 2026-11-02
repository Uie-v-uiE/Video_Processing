# TCL 构建 Vivado 工程教程

从零开始，用 TCL 脚本一键生成完整的 Vivado 工程（含 PS + PL）。

---

## 1. 为什么要用 TCL

| 方式 | 优点 | 缺点 |
|------|------|------|
| GUI 手动建 | 直观 | 慢、难复现、易出错 |
| **TCL 脚本** | **一键重建、可版本控制、可复现** | 需了解脚本结构 |

竞赛要求「可复现」，TCL 是标准做法。

---

## 2. 前置条件

| 项 | 要求 |
|----|------|
| Vivado | 2025.2.1（或其他版本） |
| 许可证 | 已激活 |
| 源码 | `rtl/`、`constraints/` 已就绪 |

---

## 3. 本工程的 TCL 脚本

```
tcl/
├── build_system_axigpio.tcl   ← 主脚本（推荐）
├── build_system.tcl           ← 旧版（EMIO，已弃用）
├── create_project.tcl         ← 仅创建工程
├── program_system.tcl         ← 下载 bit
└── program_board.tcl          ← 下载 PL-only bit
```

**主脚本：`tcl/build_system_axigpio.tcl`**

---

## 4. 一键构建

```bat
cd /d D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl
```

**耗时：** 约 5–15 分钟（取决于机器）

**输出：**
- `output/system.bit` — 比特流
- `output/system.xsa` — 硬件平台文件
- `vivado_system/zynq_video_sys.xpr` — GUI 工程

---

## 5. 脚本逐步解析

### 5.1 创建工程

```tcl
# 设置路径
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado_system]
set proj_name zynq_video_sys
set part xc7z020clg484-2

# 创建工程（-force 覆盖已存在的）
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]
```

**说明：**
- `file dirname [info script]` — 当前 TCL 文件所在目录
- `..` — 上一级（仓库根目录）
- `-part xc7z020clg484-2` — 器件型号
- `-force` — 若工程已存在则覆盖

### 5.2 添加 RTL 源文件

```tcl
# 收集所有 RTL 文件
set rtl_files {}
foreach d {util clocks video process process/rotate axi hdmi} {
  foreach f [glob -nocomplain [file join $root rtl $d *.v]] {
    lappend rtl_files $f
  }
}
lappend rtl_files [file join $root rtl top pl_video_top.v]

# 添加到工程
add_files -norecurse $rtl_files

# 添加约束文件
add_files -fileset constrs_1 -norecurse [file join $root constraints rk_zynq7020.xdc]
```

**说明：**
- `glob` — 匹配通配符 `*.v`
- `lappend` — 追加到列表
- `-norecurse` — 不递归子目录
- `constrs_1` — 约束文件集

### 5.3 创建 Block Design（PS + 互连）

```tcl
create_bd_design design_1

# 添加 PS7 IP
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set ps [get_bd_cells processing_system7_0]

# 自动配置 PS（DDR、FIXED_IO 等）
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
  -config {make_external "FIXED_IO, DDR" ...} $ps
```

### 5.4 配置 PS 参数

```tcl
set_property -dict [list \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
  CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
  CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART0_UART0_IO {MIO 10 .. 11} \
] $ps
```

**关键参数：**

| 参数 | 值 | 说明 |
|------|-----|------|
| `FPGA0_PERIPHERAL_FREQMHZ` | 50 | FCLK0 频率（PL 时钟） |
| `USE_M_AXI_GP0` | 1 | 使能 GP0（控制 AXI GPIO） |
| `USE_S_AXI_HP0` | 1 | 使能 HP0（PL 读 DDR） |
| `S_AXI_HP0_DATA_WIDTH` | 64 | HP0 数据位宽 |
| `ENET0_PERIPHERAL_ENABLE` | 1 | 使能以太网 |
| `UART0_PERIPHERAL_ENABLE` | 1 | 使能串口 |

### 5.5 添加 AXI GPIO

```tcl
# 添加 AXI GPIO IP
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0

# 配置：32 位输出，无中断
set_property -dict [list \
  CONFIG.C_GPIO_WIDTH {32} \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_INTERRUPT_PRESENT {0} \
] [get_bd_cells axi_gpio_0]

# 连接到 GP0
# （apply_bd_automation 自动连接）
```

### 5.6 连接 HP0 到 PL

```tcl
# 创建外部 HP0 端口（PL 侧 master）
# PL 的 axi_frame_writer 作为 master 读 DDR
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI_HP0
# 连接到 PS7 的 S_AXI_HP0
# （通过 AXI Interconnect）
```

### 5.7 生成输出

```tcl
# 生成 BD 输出文件
generate_target all [get_files design_1.bd]

# 创建 wrapper
make_wrapper -files [get_files design_1.bd] -top
add_files -norecurse [file join $proj_dir ${proj_name}.gen sources_1 bd design_1 hdl design_1_wrapper.v]

# 设置顶层
set_property top system_top [current_fileset]

# 综合
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# 实现 + 生成 bit
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 导出 XSA（供 Vitis 使用）
write_hw_platform -fixed -include_bit -force -file [file join $root output system.xsa]

# 拷贝 bit 到 output
file copy -force [file join $proj_dir ${proj_name}.runs impl_1 system_top.bit] \
                 [file join $root output system.bit]
```

---

## 6. 下载到板卡

```bat
%VIVADO% -mode batch -source tcl\program_system.tcl
```

或用 TCL：
```tcl
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
set_property PROGRAM.FILE output/system.bit [current_hw_device]
program_hw_devices [current_hw_device]
```

---

## 7. 常见问题

### 7.1 `create_project` 报错「工程已存在」

加 `-force` 参数覆盖：
```tcl
create_project $proj_name $proj_dir -part $part -force
```

### 7.2 RTL 文件找不到

检查路径：
```tcl
puts [file join $root rtl video *.v]
```
确保 `glob` 能匹配到文件。

### 7.3 综合报错「找不到模块」

检查是否所有 `.v` 都添加了：
```tcl
puts $rtl_files
```

### 7.4 时序不收敛

```tcl
# 查看时序报告
open_run impl_1
report_timing_summary -file output/timing.rpt
```

### 7.5 Vitis 打开 XSA 报错

确保 XSA 是从 `impl_1` 导出的：
```tcl
write_hw_platform -fixed -include_bit -force -file output/system.xsa
```

---

## 8. 完整流程图

```
┌─────────────────────────────────────────┐
│ 1. Vivado TCL 脚本                      │
│    build_system_axigpio.tcl             │
│    ├─ 创建工程                          │
│    ├─ 添加 RTL + 约束                   │
│    ├─ 创建 BD（PS7 + AXI GPIO + HP0）   │
│    ├─ 综合 + 实现                       │
│    ├─ 生成 bit                          │
│    └─ 导出 xsa                          │
└──────────────────┬──────────────────────┘
                   ▼
┌─────────────────────────────────────────┐
│ 2. Vitis                                │
│    ├─ 用 xsa 创建 Platform              │
│    ├─ 勾选 lwip220（速率 1000M）        │
│    ├─ 创建 Application                  │
│    ├─ 写入 main.c                       │
│    └─ Build → Run                       │
└──────────────────┬──────────────────────┘
                   ▼
┌─────────────────────────────────────────┐
│ 3. 板卡                                 │
│    ├─ program_system.tcl 下载 bit       │
│    ├─ Vitis Run 下载 ELF                │
│    └─ 串口/网口验证                     │
└─────────────────────────────────────────┘
```

---

## 9. 修改参数后如何重建

改了 RTL 或参数后：

```bat
:: 1. 重新构建 bit + xsa
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl

:: 2. 下载 bit
%VIVADO% -mode batch -source tcl\program_system.tcl

:: 3. Vitis 里 Build Application（不用重建 Platform）
:: 4. Run
```

**注意：** 若改了 PS 参数（如时钟、外设），需 **重建 Vitis Platform**。

---

## 10. 检查清单

- [ ] `tcl/build_system_axigpio.tcl` 存在
- [ ] `rtl/` 目录下所有 `.v` 文件齐全
- [ ] `constraints/rk_zynq7020.xdc` 存在
- [ ] Vivado 2025.2.1 已安装且许可证有效
- [ ] 运行后 `output/system.bit` 和 `output/system.xsa` 已生成

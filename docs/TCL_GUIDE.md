# TCL 入门教程（面向 Vivado / 本项目）

> 给自己看的基础笔记：先会读会跑，再会改。  
> 配套脚本：`build/tcl/*.tcl`，学习文档见 `docs/LEARNING.md`。

---

## 1. TCL 是什么

TCL（Tool Command Language）是 **命令脚本语言**。Vivado 的 GUI 操作几乎都能写成 TCL；**批处理构建** 就是靠 TCL 保证「别人从零也能复现」。

一句话：

```
命令  参数1  参数2  ...
# 这是注释
```

没有分号结尾要求（一行一条命令）；多行用 `\` 续行。

---

## 2. 在 Windows 上怎么跑 Vivado TCL

### 2.1 批处理模式（本项目最常用）

```bat
cd /d D:\Xilinx\Prj\ADD\Video_Pipeline-main
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

| 参数 | 含义 |
|------|------|
| `-mode batch` | 无界面跑完就退出 |
| `-source xxx.tcl` | 执行脚本 |
| `-log a.log` | 指定日志（可选） |
| `-journal a.jou` | 指定 journal（可选） |

### 2.2 GUI 的 Tcl Console

打开 Vivado → 底部 **Tcl Console**，可粘贴单条命令即时执行，适合调试。

### 2.3 仿真脚本

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
```

---

## 3. 语法最小集（够用 80%）

### 3.1 变量

```tcl
set name "video_pipeline"
set width 512
puts $name
puts "width=$width"
```

- `set` 赋值，`$name` 取值。
- 字符串一般用双引号；`{}` 里的内容**不当变量展开**（写正则、多行时常用）。

### 3.2 列表（list）

```tcl
set files {a.v b.v c.v}
lappend files d.v          ;# 追加
puts [llength $files]      ;# 长度
puts [lindex $files 0]     ;# 第 0 个
```

### 3.3 条件与循环

```tcl
if {$width == 512} {
    puts "VGA pane width"
} else {
    puts "other"
}

foreach f $files {
    puts $f
}

for {set i 0} {$i < 5} {incr i} {
    puts $i
}
```

### 3.4 过程（函数）

```tcl
proc add_files_from_dir {dir} {
    set fs [glob -nocomplain [file join $dir *.v]]
    add_files -norecurse $fs
    puts "added [llength $fs] files from $dir"
}
```

### 3.5 常用命令替换

```tcl
puts [clock seconds]           ;# 命令结果
set p [file join $root src]    ;# 路径拼接
```

---

## 4. 路径处理（本项目脚本里最重要）

```tcl
# info script → 当前 tcl 文件路径
set script_dir [file dirname [info script]]

# 本项目脚本在 build/tcl/，仓库根是上两级：
set root [file normalize [file join $script_dir .. ..]]

set rtl [file join $root src rtl]
puts $rtl
```

| 命令 | 作用 |
|------|------|
| `file dirname` | 目录部分 |
| `file join` | 拼路径（自动加斜杠） |
| `file normalize` | 绝对路径、去掉 `..` |
| `file exists` | 是否存在 |
| `file mkdir` | 建目录 |
| `glob -nocomplain` | 通配列文件，没有则不报错 |

**踩坑：** 若脚本在 `build/tcl`，只用一个 `..` 会指到 `build` 而不是仓库根 → 所有 `src/rtl` 都找不到。

---

## 5. Vivado 常用命令速查

### 5.1 工程

```tcl
create_project zynq_video_sys ./vivado_system -part xc7z020clg484-2 -force
open_project ./vivado_system/zynq_video_sys.xpr
set_property target_language Verilog [current_project]
```

### 5.2 加文件

```tcl
add_files -norecurse [list $root/src/rtl/top/system_top.v]
add_files -fileset constrs_1 -norecurse $root/src/constraints/rk_zynq7020.xdc
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1
```

批量加多个目录（本项目写法）：

```tcl
set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi eth} {
    foreach f [glob -nocomplain [file join $root src rtl $d *.v]] {
        lappend rtl_files $f
    }
}
add_files -norecurse $rtl_files
```

### 5.3 综合 / 实现 / 比特流

```tcl
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# 检查是否成功
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "SYNTH FAILED"
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

### 5.4 打开结果与报告

```tcl
open_run impl_1
report_timing_summary -file $root/build/timing_summary.rpt
report_utilization    -file $root/build/utilization.rpt
report_power          -file $root/build/power.rpt
```

### 5.5 导出 XSA（给 Vitis 用）

```tcl
write_hw_platform -fixed -include_bit -force -file $root/build/system.xsa
```

### 5.6 下载比特流（连着板子时）

```tcl
open_hw_manager
connect_hw_server
open_hw_target
# 选择器件后 program_hw_devices  - 见 build/tcl/program_system.tcl
```

### 5.7 仿真（xsim）

```tcl
# 见 sim/run_sim.tcl：xvlog → xelab → xsim
exec xvlog {*}$rtl_files {*}$tb_files
exec xelab -debug typical tb_zoom_mapper -s tb_zoom_mapper_snap
exec xsim tb_zoom_mapper_snap -R
```

### 5.8 约束相关

```tcl
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property target_constrs_file $xdc [get_filesets constrs_1]
```

---

## 6. 读懂本项目的 TCL 脚本

### 6.1 `build/tcl/build_system_axigpio.tcl`

作用：**从零** 建工程 → 加 RTL/约束 → 建 Block Design（PS7 + AXI GPIO + HP0）→ 综合实现 → 出 bit/xsa。

结构骨架：

```tcl
set root [file normalize [file join [file dirname [info script]] .. ..]]
create_project ...
# 1) 加 RTL 与 XDC
# 2) create_bd_design ... 连 PS、GPIO、互联
# 3) make_wrapper，top 设为 system_top
# 4) launch_runs synth_1 / impl_1
# 5) file copy bit → build/system.bit
# 6) write_hw_platform → build/system.xsa
```

### 6.2 `build/tcl/rebuild_cdc_fix.tcl` / `rebuild_opt.tcl`

作用：打开已有工程，**刷新 RTL/约束后重跑** 综合实现（比从零快一点）。

注意：改过 XDC 时，有时要删掉 `utils_1/imports/synth_1/*.dcp` 增量参考，否则约束可能没完全生效。

### 6.3 `sim/run_sim.tcl`

批量跑 testbench；输出里找 `PASS` / `FAIL`。

### 6.4 `sim/run_zoom_only.tcl`

只编译并仿真 `tb_zoom_mapper`，调试缩放时更快。

---

## 7. 调试技巧

### 7.1 先 `puts` 再跑长流程

```tcl
puts "ROOT=$root"
puts "RTL files: [llength $rtl_files]"
```

### 7.2 用 `catch` 看错误

```tcl
if {[catch {exec xvlog {*}$files} msg]} {
    puts "XVLOG ERROR:"
    puts $msg
    exit 1
}
```

### 7.3 日志里搜关键字

```
ERROR
CRITICAL WARNING
SYNTH FAILED
IMPL FAILED
WNS
```

### 7.4 GUI 里复现批处理步骤

批处理失败时，在 Vivado GUI 打开同一工程，Tcl Console 里逐条执行脚本中的命令，更容易定位。

---

## 8. 写一个自己的最小脚本模板

把下面存成 `my_check.tcl`，改路径后可检查时序：

```tcl
set root "D:/Xilinx/Prj/ADD/Video_Pipeline-main"
set proj [file join $root vivado_system zynq_video_sys.xpr]

open_project $proj
open_run impl_1
report_timing_summary -file [file join $root build timing_my.rpt]
puts "Done. See build/timing_my.rpt"
```

运行：

```bat
%VIVADO% -mode batch -source my_check.tcl
```

---

## 9. 和 Python / Shell 的对比（帮助理解）

| | TCL（Vivado） | Python | bat/PowerShell |
|--|---------------|--------|----------------|
| 强项 | EDA 工具控制 | 上位机、数据 | 系统批处理 |
| 弱项 | 不适合写业务逻辑 | 不直接控 Vivado GUI 流程 | 语法简陋 |
| 本项目 | 构建/仿真/报告 | UDP 推流、串口 | 一键启动 |

---

## 10. 学习路径建议

1. 在 Tcl Console 里手敲：`set`、`puts`、`file join`、`glob`  
2. 读 `sim/run_zoom_only.tcl`（短）  
3. 读 `build/tcl/build_system_axigpio.tcl`（完整流程）  
4. 自己改一处：例如把报告输出到新目录，跑一遍  
5. 试着写「只综合不实现」的小脚本  

---

## 11. 常见报错

| 报错 | 原因 | 处理 |
|------|------|------|
| File ... does not exist | root 少了 `..` | 用 `.. ..` 或打印 `$root` |
| SYNTH FAILED | RTL 语法/端口错 | 看 synth 日志 ERROR |
| cannot add file ... already exists | 重复 add_files | 无害警告，可忽略 |
| No current board_part | 没选 board | 本项目用 part 建工程即可 |
| timing not met | WNS<0 | 看 timing_summary，补约束或改 RTL |
| get_clocks 返回空 | 时钟还没创建 | 生成钟用 `-include_generated_clocks` |

---

## 12. 本仓库 TCL 文件一览

| 文件 | 用途 |
|------|------|
| `build/tcl/build_system_axigpio.tcl` | 全量构建（推荐竞赛复现用） |
| `build/tcl/build_system.tcl` 等 | 其它构建变体 |
| `build/tcl/program_system.tcl` | 下载 bit |
| `build/tcl/rebuild_opt.tcl` | 优化后重跑 |
| `build/tcl/rebuild_cdc_fix.tcl` | CDC/约束修复后重跑 |
| `sim/run_sim.tcl` | 全部仿真 |
| `sim/run_zoom_only.tcl` | 只跑缩放 TB |

---

*原则：脚本里的路径全部基于 `info script` 推仓库根，不要写死别人机器上的绝对路径。*

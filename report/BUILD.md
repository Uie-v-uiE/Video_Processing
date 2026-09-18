# 构建、上板与路径速查

## 1. 本机路径

| 用途 | 路径 |
|------|------|
| 仓库根 | `D:\Xilinx\Prj\video_pl\zynq_video_pipeline\` |
| Vivado | `D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat` |
| Vitis | `D:\Software\Vivado\2025.2.1\Vitis\bin\vitis.bat` |
| Vivado 工程 | `vivado_system\zynq_video_sys.xpr`（gitignore，可用 TCL 重建） |
| Vitis 工作区 | `vitis_udp\` 或 `vitis_prj\` |
| 参考 ETH 工程 | `D:\Xilinx\Resource\ZYNQ7020\RK_demo\FPGA_DEMO\13_UDP_STACK\` |

---

## 2. 常用命令

```bat
cd /d D:\Xilinx\Prj\video_pl\zynq_video_pipeline
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat

:: 从零生成 bit + xsa
%VIVADO% -mode batch -source tcl\build_system_axigpio.tcl

:: 下载 bit
%VIVADO% -mode batch -source tcl\program_system.tcl

:: 仿真
%VIVADO% -mode batch -source sim\run_sim.tcl

:: 金标图
python scripts\golden_model.py

:: 推流
sw\host\run_sender.bat
sw\host\run_video.bat D:\path\to\video.mp4
```

---

## 3. 上板顺序

1. 12V 电源、HDMI 显示器（1024×600）、USB-TYPEC（JTAG+UART）  
2. 网线接 **PL 网口**  
3. `program_system.tcl` 下载 bit  
4. Vitis Run 下载 PS ELF（串口命令）  
5. PC 网卡 `192.168.1.100/24`  
6. `ping 192.168.1.10`  
7. `run_sender.bat` 推流  
8. HDMI 应显示左右双窗 + OSD  

---

## 4. 网络参数

| 项 | 值 |
|----|-----|
| 板卡 PL IP（协议栈过滤端口） | UDP **5001** |
| BOARD_MAC | `00:11:22:33:44:55` |
| BOARD_IP（参数，可改） | `192.168.1.10` |
| PC IP | `192.168.1.100/24` |

---

## 5. 带宽与资源

- 512×300×2 B = 307200 B/帧  
- 30 fps ≈ 9.2 MB/s ≈ 74 Mbps  
- BRAM 帧缓 ≈ 2.34 Mbit（7020 共 4.9 Mbit）  
- 双缓冲放不下 → 未采用  

---

## 6. 导出报告

综合实现后：

```tcl
open_run impl_1
report_timing_summary -file output/timing_summary.rpt
report_utilization -file output/utilization.rpt
```

或直接看 `build_system_axigpio.tcl` 自动导出的 `output/*.rpt`。

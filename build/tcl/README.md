# Vivado TCL 速查

| 脚本 | 用途 |
|------|------|
| `create_project.tcl` | 建工程；参数 `pl`（默认）或 `system` |
| `build_bitstream.tcl` | 综合实现出 bit，拷到 `output/` |
| `program_board.tcl` | JTAG 下载 `output/video_pipeline.bit` |
| `../sim/run_sim.tcl` | 行为仿真 3 个 TB |

## 推荐命令
```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat

:: 1) 纯 PL 冒烟
%VIVADO% -mode batch -source tcl\create_project.tcl -tclargs pl
%VIVADO% -mode batch -source tcl\build_bitstream.tcl -tclargs pl
%VIVADO% -mode batch -source tcl\program_board.tcl

:: 2) 仿真
%VIVADO% -mode batch -source sim\run_sim.tcl

:: 3) 完整 PS+PL
%VIVADO% -mode batch -source tcl\create_project.tcl -tclargs system
%VIVADO% -mode batch -source tcl\build_bitstream.tcl -tclargs system
:: 然后 Vitis 用 output\system.xsa 建平台并编 sw\ps
```

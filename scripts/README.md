# scripts/

可复现构建脚本与综合/实现报告。

| 入口 | 作用 |
|---|---|
| `build.tcl` | Vivado 主入口，转发到 `tcl/build_system_axigpio.tcl`；可加 `-tclargs bd_only` |
| `tcl/build_system_axigpio.tcl` | 建工程、块设计、综合、实现、位流、XSA 与时序/资源/CDC/功耗报告 |
| `tcl/stage_board_projects.tcl` | 把工程整理到 `hw/vivado/` 并现场打开验证 |
| `vitis/rebuild_vitis.py` | 用 XSA 重建 Vitis 平台与 FSBL |
| `ps/build_ps_app.py` | 直接编译 PS 裸机应用，不依赖 Vitis IDE |
| `sim/` | xsim 运行入口 |
| `reports/` | 时序、资源、CDC、功耗、回归与完整视频台架判定 |

文档生成器（技术文档 DOCX/PDF、海报 PPTX 导出）属于本地排版工具，不在本仓库内，也不属于构建链。

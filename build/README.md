# build/

| 入口 | 作用 |
|---|---|
| `tcl/build_system_axigpio.tcl` | 建工程、块设计、综合、实现、出位流、XSA 和报告 |
| `build/sim/run_msim.sh` | 跑台架（从仓库根执行 `bash build/sim/run_msim.sh ...`） |
| `build_ps_app.py` | 直接编译 PS 应用，不依赖 IDE |
| `reports/` | 时序、资源、CDC、功耗、回归与完整视频台架 |
| `make_technical_doc.py` / `make_technical_pdf.py` | 从 `report/design-report.md` 生成 DOCX / PDF |

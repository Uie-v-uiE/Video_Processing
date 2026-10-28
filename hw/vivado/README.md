# Vivado 工程

`zynq_video_sys.xpr` + `zynq_video_sys.srcs/` 是从 `scripts/build.tcl` 生成并整理过的工程：

- 器件 `xc7z020clg484-2`；
- 92 份手写 RTL、1 份 BD wrapper、1 个块设计、3 份生效约束；
- 块设计 `design_1`、PS7、AXI GPIO、AXI HP0；
- 源文件路径 `$PPRDIR/../../src/...`，工程内没有本机绝对路径。

先跑 `scripts/build.tcl`，产生 `vivado_system/` 与 `scripts/system.bit`/`system.xsa`；再重建并验证：

```bash
vivado -mode batch -nojournal -log scripts/stage.log \
  -source scripts/tcl/stage_board_projects.tcl
```

期望：

```text
VERIFY missing_files=0 of 97
VERIFY abs_path_lines=0
STAGE_BOARD_PROJECTS DONE
```

工程不带 `.gen/`、`.runs/`、`.cache/`。BD wrapper 已在 `.srcs/` 内；打开工程后直接综合，Vivado 会按 `design_1.bd` 生成其余输出产物。`bd_only` 只用于单独检查 BD，不生成 wrapper。

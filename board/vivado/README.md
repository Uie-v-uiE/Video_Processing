# Vivado 工程

`zynq_video_sys.xpr` + `zynq_video_sys.srcs/` 是从 `build/build.tcl` 生成并整理过的工程：

- 器件 `xc7z020clg484-2`；
- 99 份 RTL 源文件与 3 份约束；
- 块设计 `design_1`、PS7、AXI GPIO、AXI HP0；
- 源文件路径 `$PPRDIR/../../src/...`，工程内没有本机绝对路径。

重建并验证：

```bash
vivado -mode batch -nojournal -log build/stage.log \
  -source build/tcl/stage_board_projects.tcl
```

期望：

```text
VERIFY missing_files=0 of 102
VERIFY abs_path_lines=0
STAGE_BOARD_PROJECTS DONE
```

工程不带 `.gen/`、`.runs/`、`.cache/`。打开工程后如果提示 output products 缺失，跑一次 `vivado -mode batch -source build/build.tcl -tclargs bd_only` 就会生成。

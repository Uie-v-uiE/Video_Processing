# Vivado project

`zynq_video_sys.xpr` plus `zynq_video_sys.srcs/` is generated and staged by `scripts/build.tcl`:

- part `xc7z020clg484-2`;
- 92 hand-written RTL files, one BD wrapper, one block design, three active constraint sets;
- block design `design_1`, PS7, AXI GPIO, AXI HP0;
- source paths `$PPRDIR/../../src/...`, with no local absolute path.

Run `scripts/build.tcl` first to produce `vivado_system/` and `hw/reports/system.bit` / `system.xsa`, then restage and verify:

```bash
vivado -mode batch -nojournal -log hw/reports/stage.log \
  -source scripts/tcl/stage_board_projects.tcl
```

Expected:

```text
VERIFY missing_files=0 of 97
VERIFY abs_path_lines=0
STAGE_BOARD_PROJECTS DONE
```

The project ships without `.gen/`, `.runs/` or `.cache/`. The BD wrapper is already in `.srcs/`; open the project and synthesise, and Vivado generates the remaining output products from `design_1.bd`. The `bd_only` flow checks the block design alone and does not generate the wrapper.

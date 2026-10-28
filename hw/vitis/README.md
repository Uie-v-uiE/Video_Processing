# Vitis platform

`vitis-comp.json` describes two domains:

| Domain | Processor | Purpose |
|---|---|---|
| `zynq_fsbl` | `ps7_cortexa9_0` | FSBL for QSPI boot |
| `standalone_ps7_cortexa9_0` | `ps7_cortexa9_0` | bare-metal application and BSP |

Hardware points at `hw/project/system.xsa` (paths in `vitis-comp.json` are relative to the repository root); `resources/` holds three QEMU argument files. The actual rebuild runs through `scripts/vitis/rebuild_vitis.py`, which reads the XSA directly and does not depend on the descriptor.

## Rebuild

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<workspace> <Vitis>/bin/vitis.bat \
  -s scripts/vitis/rebuild_vitis.py 8879
```

Expected: `Platform Build Finished successfully.`, `GENERATE_RC 0`, and `zynq_fsbl/build/fsbl.elf`.

`create_app_component` in Vitis 2025.2.1 returns `StatusCode.INTERNAL` on this platform, so application components cannot be created. The PS application does not need the IDE:

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<platform BSP directory> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

After a successful rebuild, `rebuild_vitis.py` leaves the platform and FSBL in the workspace and prints `BSP_DIRS` for the next step. `hw/vitis/` stores only the platform descriptor and QEMU arguments, never the 16 MB-class BSP or build intermediates.

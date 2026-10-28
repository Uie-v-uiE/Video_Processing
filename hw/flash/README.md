# QSPI boot image

| File | Content |
|---|---|
| `BOOT.bin` | FSBL, bitstream and PS application, written to on-board QSPI |
| `fsbl.elf` | the FSBL used for packaging, so the image can be rebuilt as-is |
| `boot.bif` | bootgen image description; paths are relative to the BIF file |
| `bootgen.log` | packaging log |
| `boot_manifest.txt` | MD5 of the three inputs and of the image |

## Repackaging

```bash
VP_VIVADO_BIN=<Vitis>/bin bash hw/scripts/make_boot_image.sh
```

The script takes `fsbl.elf` from the same directory first, then the FSBL generated under `hw/vitis_ws/` (or `VP_FSBL`), then `hw/project/system.bit` and `hw/project/ps_app.elf`, and writes `BOOT.bin`. Paths inside `boot.bif` are relative, so unpacking on another machine carries no local drive letter. The three input readings are recorded in `boot_manifest.txt`.

Expected:

```text
BOOT_IMAGE .../hw/flash/BOOT.bin
BOOT_BYTES ...
BOOT_MD5 ...
FSBL_MD5 ...
BOOT_MANIFEST .../hw/flash/boot_manifest.txt
MAKE_BOOT_IMAGE DONE
```

## Writing QSPI

```bash
VP_HW_URL=<host:port> vivado -mode batch -source hw/tcl/flash_qspi.tcl
```

Expected:

```text
Erase Operation successful.
Program Operation successful.
Verify Operation successful.
PROGRAM_RC 0
```

Power-cycle afterwards and confirm the boot messages and ping. Writing QSPI is irreversible; confirm the image and the boot-mode switch first.

## Notes

- `BOOT.bin` must contain the latest `ps_app.elf`; after rebuilding firmware, repackage and rewrite QSPI.
- bootgen can return 0 even when it cannot read an input; the packaging script checks the log for `[ERROR]` and for the success line, and deletes the old image before generating a new one.
- A JTAG download only affects the current power cycle; after power loss the board boots from QSPI again.

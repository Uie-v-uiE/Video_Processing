# PS bare-metal firmware

`src/ps/` holds the Zynq PS application:

| File | Purpose |
|---|---|
| `main.c` | boot, UART command dispatch, AXI GPIO control and readback, XADC temperature, `link` frame-gap statistics |
| `sd_play.c` / `sd_play.h` | FAT32 parsing, directory lookup, cluster-chain reads, SD frame playback |
| `lscript_ocm.ld` | OCM boot linker script |

The PS never touches pixels. It writes control words, reads health state and writes frames into DDR during SD playback; Ethernet video bytes never pass through it.

## Build

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<BSP from the platform build> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

`PS_BSP` must point at a generated Zynq standalone BSP (with `include/` and `lib/libxil.a`). Without a platform, rebuild one with `scripts/vitis/rebuild_vitis.py` as described in `hw/vitis/README.md`.

The build script checks that `_start`, `_boot`, `_vector_table`, `MMUTable`, `main` and `XSdPs_CardInitialize` are present in the ELF, so an empty image cannot reach the board.

## Boot

- JTAG: `hw/scripts/board_flash.sh` runs `ps7_init` -> PL -> ELF -> GPIO readback.
- QSPI: `hw/scripts/make_boot_image.sh` packs `BOOT.bin`, and `hw/tcl/flash_qspi.tcl` writes it.
- After power loss the board boots from QSPI; a JTAG download is volatile.

## Control word

| Bits | Meaning |
|---|---|
| 8:0 | nine effect bits: grayscale, invert, blur, sharpen, Sobel, threshold, inverted decision, erode, dilate |
| 18:9 | geometry: seam position, auto/follow/swap/marker, rot_auto, rot_speed, zoom_fit |
| 19 | bilinear enable |
| 20 | OSD enable |
| 26 | clear frame-gap statistics |
| 31:27 | AXI GPIO lane number |

New control bits go at the high end; existing bits are never reordered. The RTL definition, the word the firmware writes and the host masks must stay in step.

## Commands

`stat`, `temp`, `link` / `link clr`, `src`, `pipe`, `zoom`, `rot`, `split`, `gamma`, `osd`, `sd`, `play`, `stop`, `fill`, `autoplay`, `th`, `echo`, `help`.

- `link` reads `gap_last/min/max/sum`, `gap_valid` and `live` from the PL `link_monitor`.
- `link clr` clears them before a reading.
- `sd file n` selects a clip and `play` resumes from it.
- `temp` prints XADC temperature, VCCINT, the OSD encoding and the GPIO readback.

The command table, the help lines and the dispatcher must change together; a function that exists in the source but is not wired into `dispatch` makes the board answer "unknown command".

## SD playback

`sd_play.c` parses the FAT32 BPB, directories and cluster chains itself and depends on no filesystem library. The card must be FAT32 and the frame sequence is produced by `src/host/make_sd_video.mjs`. `sd files` lists clips, `sd file n` selects one, `play` starts and `stop` stops.

## Temperature

The XADC supplies die temperature and VCCINT. The `[TEMP]` line prints `degC`, `raw`, `vccint`, `osd` and `gpio`, which puts the driver reading, the OSD encoding and the PL-side synchroniser readback side by side.

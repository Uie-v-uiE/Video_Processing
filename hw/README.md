# Hardware projects, scripts and measurements

`hw/` holds four kinds of material: the artifacts that run on the board (bitstream, XSA, firmware), the rebuildable Vivado and Vitis projects, the board scripts, and the measurement logs.

## 1 The three board artifacts

| File | What it is |
|---|---|
| `project/system.bit` | PL bitstream for the display and Ethernet path |
| `project/system.xsa` | hardware description exported with the bitstream, used by Vitis to build the platform |
| `project/ps_app.elf` | PS bare-metal application: command parsing, SD playback, temperature and link readings |

The three are identified by MD5, not by file name. The generating commands and checksums are whatever the build produced.

## 2 Vivado project

`vivado/zynq_video_sys.xpr` and `vivado/zynq_video_sys.srcs/` are generated and staged by the build TCL and contain:

- the `xc7z020clg484-2` part;
- 92 hand-written RTL files, one BD wrapper, one block design and three active constraint sets;
- block design `design_1`, the PS7 configuration, AXI GPIO and AXI HP0;
- source paths of the form `$PPRDIR/../../src/...`, with no local absolute path.

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

The project ships without `.gen/`, `.runs/` or `.cache/`. The BD wrapper is already inside `.srcs/`; open the project and synthesise, and Vivado generates the remaining output products from `design_1.bd`. The full bitstream comes from the single `scripts/build.tcl` command.

## 3 Vitis platform

`hw/vitis/` describes the platform:

| File | Content |
|---|---|
| `vitis-comp.json` | two domains, `zynq_fsbl` and `standalone_ps7_cortexa9_0`; hardware points at `hw/project/system.xsa` |
| `resources/` | three `qemu_args.txt` files |

Rebuild the platform and FSBL:

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<workspace> <Vitis>/bin/vitis.bat \
  -s scripts/vitis/rebuild_vitis.py 8879
```

Expected: `Platform Build Finished successfully.`, `GENERATE_RC 0`, and `zynq_fsbl/build/fsbl.elf`. `create_app_component` in Vitis 2025.2.1 returns `StatusCode.INTERNAL` on this platform, so application components cannot be created; the PS application does not need the IDE and is compiled by `scripts/ps/build_ps_app.py`.

PS application:

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<BSP from the platform build> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

## 4 JTAG bring-up

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat \
VP_VIVADO_BIN=<Vivado>/bin \
bash hw/scripts/board_flash.sh
```

The script scans the chain, runs PS `ps7_init`, downloads the PL, downloads the ELF and reads back AXI GPIO. Only the final `FLASH: GREEN` counts. `--check` performs the pre-checks and a read-only chain scan without touching the board.

Health snapshot:

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash hw/scripts/board_health.sh
```

It takes one read-only snapshot: `stat,temp,stat` over serial, GPIO and DDR header over JTAG, the three exception vectors, and only `HEALTH: GREEN` counts.

## 5 QSPI and cold boot

```bash
VP_VIVADO_BIN=<Vitis>/bin bash hw/scripts/make_boot_image.sh
VP_HW_URL=<host:port> vivado -mode batch -source hw/tcl/flash_qspi.tcl
```

`make_boot_image.sh` packs FSBL, bitstream and application into `flash/BOOT.bin`; paths inside `boot.bif` are relative to the BIF file itself, never a local drive letter. `flash_qspi.tcl` erases, programs and verifies by hardware readback, and only the final `PROGRAM_RC 0` counts. Power-cycle after writing and watch the boot messages on serial; a JTAG download is volatile, and the QSPI image is the artifact that boots without a host.

## 6 Serial commands

Serial is channel B of the USB-C bridge, `COM6`, 115200 8N1.

| Command | Purpose |
|---|---|
| `stat` | control state, frame counts, effect selection, geometry words |
| `temp` | XADC temperature, VCCINT, OSD encoding and GPIO readback |
| `link` / `link clr` | latest, min/max and cumulative frame gap; clear |
| `src auto\|0\|1\|2` | source: auto, test card, network, SD |
| `pipe <nine bits>` / `pipe show` | effect chain |
| `zoom on\|off\|auto\|<ratio>` | zoom |
| `rot auto\|0\|1` / `rot speed 0..7` | automatic rotation and degrees per frame |
| `split screen\|video <0..100>` | seam mode and position |
| `sd files` / `sd file n` / `play` / `stop` | SD selection and playback |

Only one program may own the serial port at a time. Stop the stream before reading registers; while streaming, most counters are mid-flight values.

## 7 Network and host tools

Board `192.168.1.10`, PC `192.168.1.100`, direct gigabit link on the PL-side RJ45.

```bash
ping 192.168.1.10
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
```

Telemetry leaves from UDP 1234 to the last ARP requester, so ping the board once before starting the listener. Windows Firewall may block UDP 1234.

## 8 Measurements

`measured/` holds only first-hand logs that support a conclusion:

| File | Content |
|---|---|
| `qspi_program.txt` | QSPI erase, program and verify |
| `cold_boot.txt` | boot mode, PL state and serial output after a power cycle |
| `flash_jtag.txt` | three-step JTAG chain and GPIO readback |
| `health.txt` | serial + JTAG + exception vectors + XADC snapshot |
| `telemetry_8s.txt` | 1 Hz telemetry during an 8-second stream |
| `link_selftest.txt` | clean → loss → recovery self-test |
| `uart_battery.txt` | the 105-command battery |
| `link_gap.txt` | frame-gap statistics after `link clr`, streaming and stopping |

Raw logs from earlier rounds are not kept in the deliverable; use the local archive or Git history to trace them.

## 9 Human acceptance

The machine cannot judge a picture. Three items are signed off on site:

- both sides of the seam are the same frame, with matching geometry;
- zooming or rotating produces no whole-row misalignment;
- every OSD field agrees with `stat` and `temp` on the serial port.

Per-item status and sign-off live in `acceptance.md`.

## 10 Layout

```text
project/          bitstream, XSA, PS application
vivado/           Vivado project (.xpr + .srcs)
vitis/            Vitis platform descriptor
compare/          measured-versus-reference reconciliation
tcl/              JTAG, QSPI and staging scripts
scripts/          one-shot bring-up, health, UART, boot-image packaging
measured/         first-hand measurement logs
flash/            BOOT.bin and the packaging log
```

## 11 Cautions

- On `Cannot halt processor core`, power-cycle and rerun `board_flash.sh`; do not fight it with repeated `rst -system`.
- After changing PS firmware, rebuild the ELF, re-download it and repackage BOOT.bin. A rebuild without a re-download leaves the old firmware on the board.
- Repackaging BOOT.bin does not update QSPI; write the flash again and verify after a power cycle.
- Stop the stream before reading registers; counters read mid-stream are not a stable snapshot.

## 12 What is kept and what is not

One rule decides: keep what can be rebuilt, reproduced, or used to support a conclusion in the report; drop old-round readings, one-shot destructive probes, scripts replaced by newer ones, and duplicate TCL. Size is not the criterion.

### 12.1 Core

| Item | Why it must stay |
|---|---|
| `project/system.bit`, `.xsa`, `ps_app.elf` | the three artifacts that actually run; MD5 is the identity |
| `flash/BOOT.bin` | the image that boots from QSPI |
| `vivado/`, `vitis/` | rebuildable board projects, not copies of build output |
| `scripts/`, `tcl/` | entry points for bring-up, health, UART, QSPI and JTAG |
| current evidence in `measured/` | cold boot, frame gaps, telemetry, self-test, battery, temperature, QSPI readback |
| `compare/`, `measured/README.md` | the reconciliation rules between measurement and reference |

### 12.2 Supporting

| Item | Nature |
|---|---|
| `measured/pane_integrity.txt` | 185° evidence from the same RTL; not measured in this build, but it supports the processed-pane conclusion |
| `measured/sd_playback.txt` | SD resume evidence; the `link` change does not touch the SD path |
| `measured/uart_battery_capture.txt` | raw capture of the 105-command battery, for line-by-line rechecking |
| `measured/flash_jtag.txt` | evidence for the three-step JTAG chain; cold boot is in `cold_boot.txt` |
| `flash/bootgen.log` | packaging log showing how BOOT.bin was produced |

These files are small. Deleting them would not break the build, but the matching report conclusions would lose their board evidence, so they stay with their nature stated.

### 12.3 Removed

| Item | Why |
|---|---|
| `output/` and the old cdc/roster/temp/ddr logs in `compare/` | earlier-round readings from a different build; keeping them invites comparing old numbers with current conclusions |
| `raw-vs-golden.md`, `signoff*.md`, `demo_rehearsal.txt` | old human/sign-off records superseded by `acceptance.md` and the current measurements |
| `uart_capture.txt`, `uart_script_capture.txt` | per-run local captures; the raw battery capture is kept under a neutral name |
| `cmd_overflow_probe.sh` | one-shot destructive probe that could wedge the command channel; not part of acceptance |
| `rebuild_project.sh`, `stage_vitis_platform.sh`, `serial_bytes.ps1` | superseded by `scripts/build.tcl`, `scripts/vitis/rebuild_vitis.py` and `uart_cmd_script.ps1` |
| `sd_boundary_0deg.txt` | earlier-round SD boundary reading |
| old `tcl/probe_flash_read.tcl`, `program_and_check.tcl`, `program_system.tcl` | one-shot probes or duplicated flows; the scripts actually used are kept |
| `stage_board_projects.tcl` | moved to `scripts/tcl/`; it belongs to the build chain, not to board operation |

In one line: core files are needed to rebuild or bring up the board, supporting files are the board evidence behind a report conclusion, and what was removed was old, one-shot or superseded.

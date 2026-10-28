# Reproduction

Five steps: get the sources, build the bitstream, run the benches, build the PS application, and either bring up the board over JTAG or write QSPI. Every step lists prerequisites, commands and the expected result — an operation without an expected result does not count as a step.

## 1 Prerequisites

| Item | Requirement |
|---|---|
| Device | `xc7z020clg484-2`, Zynq-7020 development board |
| Tools | Vivado / Vitis 2025.2.1; the `arm-none-eabi-gcc` shipped with Vitis; ModelSim (point `MSIM_BIN` at its install directory for `run_msim.sh`) |
| Host | Windows 10/11 or Linux; Python 3.10+; Node.js 18+ (optional, host tools) |
| Board | PL-side RJ45, HDMI output, microSD, QSPI, USB-C JTAG/UART bridge |
| Network | PC wired NIC `192.168.1.100/24`, board `192.168.1.10/24`, direct gigabit link |
| Serial | FT4232 channel B, `COM6`, 115200 8N1 |
| Display | 1024×600 HDMI panel |

Tool locations arrive through environment variables; no script hardcodes a machine path.

## 2 Layout

```text
src/rtl/           PL sources
src/ps/            PS bare-metal firmware
src/constraints/   pin, clock and CDC constraints
src/host/          host-side streaming, telemetry, dashboard, self-test
sim/               testbenches
scripts/build.tcl  Vivado entry point
scripts/tcl/       Vivado build and board-project staging TCL
scripts/vitis/     Vitis platform rebuild
scripts/ps/        PS application build
scripts/sim/       simulation entry points
hw/reports/        implementation reports
hw/                Vivado/Vitis projects, board scripts, measurements
data/              test inputs, golden images, metrics table
docs/              design and verification documents
```

## 3 Build the bitstream

```bash
vivado -mode batch -source scripts/build.tcl
```

The script creates the project and block design, runs synthesis and implementation, writes the bitstream and XSA, and generates the timing, resource, CDC, methodology and power reports. Outputs go to `hw/reports/` and `vivado_system/`. To build only the project and block design:

```bash
vivado -mode batch -source scripts/build.tcl -tclargs bd_only
```

Expected: `BD_ONLY_DONE`, or the `BITSTREAM` and report lines at the end of a full build; zero failing endpoints in the timing report.

## 4 Rebuild the Vivado project

`hw/vivado/zynq_video_sys.xpr` is the project generated and staged by the build scripts. Run step 3 first so `vivado_system/` and `hw/reports/system.bit` / `system.xsa` exist, then:

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

97 = 92 hand-written RTL files + 1 BD wrapper + 1 block design + 3 active constraint sets. `missing_files=0` means every file of the copied project exists on disk; `abs_path_lines=0` means the project files contain no local absolute path. Opening the project should show `xc7z020clg484-2`, the constraint sets and the block design.

## 5 Rebuild the Vitis platform

The platform descriptor is in `hw/vitis/`. Rebuild the platform and FSBL:

```bash
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<workspace> <Vitis>/bin/vitis.bat \
  -s scripts/vitis/rebuild_vitis.py 8879
```

Expected: `Platform Build Finished successfully.`, `GENERATE_RC 0`, and `zynq_fsbl/build/fsbl.elf` written. `create_app_component` in Vitis 2025.2.1 returns `StatusCode.INTERNAL` on this platform — a tool limitation. The PS application does not need the IDE; the next section compiles it directly.

## 6 Build the PS application

```bash
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<BSP from the platform build> \
PS_OUT=hw/project/ps_app.elf \
python scripts/ps/build_ps_app.py
```

Expected: `ENTRY _boot@... _vector_table@... OK` and `OK hw/project/ps_app.elf`, with `.text` around 60 KB. The script checks that `_start`, `_boot`, `_vector_table`, `MMUTable`, `main` and `XSdPs_CardInitialize` are present in the ELF, so an empty image cannot reach the board unnoticed.

## 7 Run the benches

Quick regression:

```bash
MSIM_BIN=<ModelSim>/win64 bash scripts/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
```

Full-video and special benches:

```bash
MSIM_BIN=<ModelSim>/win64 bash scripts/sim/run_msim.sh video_pipeline_top
```

Expected: `RESULT ... PASS` at the end of every bench; the full-video bench passes C17/C25/C26 with nfail=0. A log without a verdict line is not a pass.

## 8 Board bring-up over JTAG

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat \
VP_VIVADO_BIN=<Vivado>/bin \
bash hw/scripts/board_flash.sh
```

The script scans the chain, runs PS `ps7_init`, downloads the PL, downloads the ELF and reads back AXI GPIO. Expected:

```text
FLASH: GREEN
```

Health snapshot:

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash hw/scripts/board_health.sh
```

Expected: `[STAT]` on the serial port, GPIO and DDR header over JTAG, the three exception-vector labels readable, and `HEALTH: GREEN`.

## 9 Network and host tools

```bash
ping 192.168.1.10
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
```

Expected:

- about 241 frames in 8 seconds, 30 fps;
- 13 beacons in 13 seconds at 1 Hz, with the frame count rising monotonically;
- the three-stage self-test reports `PASS`: clean stream ≥ 8 fps, fault stage ≥ 5 aborts/s with frame rate < 5 fps, recovery back to clean-stream level.

Serial command battery:

```bash
node src/host/uart_cmd_check.mjs --port COM6
```

Expected: every command answers as specified and the final state equals the initial state.

Frame-gap statistics:

```text
link clr
link
```

Expected: `gap_last/min/max/sum` carry values and `gap_valid=1`; after the stream stops, `gap_last` grows and `gap_max` updates.

## 10 Writing QSPI

```bash
VP_VIVADO_BIN=<Vitis>/bin bash hw/scripts/make_boot_image.sh
VP_HW_URL=<host:port> vivado -mode batch -source hw/tcl/flash_qspi.tcl
```

Expected:

```text
Erase Operation successful.
Program Operation successful.
Verify Operation successful.
PROGRAM_RC 0
```

Power-cycle after writing, watch the boot messages on the serial port, then run `ping`, `stat`, `link` and the telemetry listener. The QSPI image contains FSBL, bitstream and application; a JTAG download is volatile and disappears on power loss.

## 11 Common problems

**JTAG reports `Cannot halt processor core`.** The PS may be in an exception state or still booting from QSPI. Power-cycle first, then rerun `board_flash.sh`; do not fight it with repeated `rst -system`.

**No serial echo.** Check that COM6 is not held by a terminal, that the baud rate is 115200, and that the PL is configured with the PS application downloaded. If `health_read` still reads GPIO and the DDR header over JTAG, the PL and bus are alive and the problem is on the PS or serial side.

**Ping fails.** Confirm the PC NIC is `192.168.1.100/24` and the board is `192.168.1.10`; confirm the cable is in the PL-side RJ45, not the PS port; then run `board_health.sh` to see whether the PL is configured.

**No telemetry.** The beacon goes to the last ARP requester — ping the board once before starting the listener. Windows Firewall may block UDP 1234.

**SD does not play.** Run `sd remount`, then `sd files` to list the clips; select with `sd file n` and start with `play`. The card must be FAT32, and the frame sequence is produced by `src/host/make_sd_video.mjs`.

**Vivado reports missing output products.** The project carries sources and constraints only; block-design output products live in `.gen/` and are not committed. Run the `bd_only` flow once or a full build.

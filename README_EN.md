# Multi-Source Video Processing System

A fully hardware video path on Zynq-7020, with an observation instrument that can be read back over the network and the serial port.

A host PC sends 512×300 RGB565 frames as UDP datagrams of at most 1392 bytes to port 5001. The PL receives them from RGMII, passes them through the MAC, UDP filtering and offset-based frame reassembly, and writes complete frames into a DDR ping-pong buffer. The display side reads a frame back, applies scaling, arbitrary-angle rotation, bilinear interpolation and a six-stage effect chain, then overlays OSD text and expands the result ×2 to a 1024×600, 59.5 Hz HDMI output. Pixels never pass through the PS. A vertical seam in the middle of the screen shows the source on the left and the processed version of the same frame on the right; both sides share the same geometry engine and a fixed 15-cycle effect chain.

## Highlights

- **Same-frame A/B seam (comparable)**: the source and processed panes share one geometry engine, one set of row tags and a fixed 15-cycle effect chain, so the seam compares the same frame rather than two independently scaled paths.
- **Frame-commit gates + a falsifiable instrument (trustworthy)**: a frame is committed only when the byte gate, row-coverage bitmap and bad-packet gate all pass; `pane_bad`, `link` frame-gap statistics and three-stage fault injection can all make the instrument fail.
- **Full-PL + QSPI closed loop (deliverable)**: RGMII ingest, frame reassembly, DDR ping-pong, geometry, effects, OSD and HDMI all run in the PL; QSPI cold boot restarts without a host, and serial, UDP telemetry and AXI GPIO read the same counters.

## What can be checked

| Claim | How to check | Reading |
|---|---|---|
| A frame is committed only when complete | Row-coverage bitmap, byte gate, abort counter | 241 frames in 8 s, 29.95 fps; abort count does not grow under a clean stream |
| The processed pane does not leak the source | Non-gray pixel count with only grayscale enabled and split video | `pane_bad=0` at 185°, 30 fps, count valid |
| The instrument can be made to fail | Clean → 1 packet in 100 dropped → clean | 22.0 fps / 0 fps with 14.3 aborts per second / 18.9 fps, PASS |
| Effect latency is configuration-independent | Cycle-by-cycle alignment in the full video bench and OSD latency | Constant 15 pixel clocks; PL-internal frame latency 2–16 ms |
| Frame-gap statistics are readable | Serial `link clr` → stream → stop → restart → `link` | `gap_valid=1` while streaming; `stall` grows after stop; `gap_max=22,061 ms` after restart |
| QSPI cold boot | Write, on-chip verify, power cycle | `DONE=1`, `EOS=1`, no CRC/IDCODE errors; `stat` and `link` respond |
| Timing closes with positive margin | Same script before and after optimisation | WNS 1.029 → 1.341 ns; WHS 0.025 ns; TNS/THS 0; zero failing endpoints |

## Implementation readings

Device: `xc7z020clg484-2`. Tools: Vivado / Vitis 2025.2.1.

| Item | Reading |
|---|---|
| Timing | WNS 1.341 ns, WHS 0.025 ns, TNS = THS = 0, failed endpoints 0 |
| Per-clock setup | `clk_fpga_0` 2.159 ns; `eth_rxc` 3.247 ns; `sys_clk` 14.797 ns; `clkout0_1` 3.264 ns; `clkout3` 1.727 ns |
| Resources | LUT 14,967 (28.13%), FF 9,095 (8.55%), BRAM 98 (70.00%), DSP 19 (8.64%) |
| Simulation | 19 standard regressions, `fail=0`; full-video C17/C25/C26 arms PASS |
| Board | QSPI cold boot, 8 s stream, telemetry, three-stage self-test, 105-command UART battery and temperature all pass |

## Submission mapping

| Requirement | Location |
|---|---|
| Complete source (RTL, PS software) | `src/rtl/`, `src/ps/`, `src/constraints/` |
| Simulation and verification results | `sim/`, `sim/results/`, `build/reports/regression.txt`, `report/verification.md` |
| Synthesis and implementation reports | `build/reports/` |
| Board project, scripts, measurements and comparisons | `board/vivado/`, `board/vitis/`, `board/project/`, `board/scripts/`, `board/tcl/`, `board/measured/`, `board/compare/` |
| Reproducible build scripts | `build/build.tcl`, `build/tcl/`, `build/vitis/`, `build/ps/`, `build/sim/` |
| Skill package | `skill/`, index at `skill/README.md` |
| Design report | `report/design-report.md`, `report/verification.md`, `report/optimization.md`, `report/collaboration/`, `report/skill-distillation.md`, `report/reproduction.md` |

`board/` uses two project folders: `board/vivado/` contains the `.xpr` and `.srcs`; `board/vitis/` contains the platform descriptor and QEMU arguments. Source paths use `$PPRDIR/../../src/...`; there are no absolute host paths in the project.

## TCL build flow and timing convergence

`build/build.tcl` forwards to `build/tcl/build_system_axigpio.tcl`: project and block design, synthesis, implementation, bitstream/XSA, then timing, utilisation, CDC, methodology and power reports. `build/tcl/stage_board_projects.tcl` stages the project into `board/vivado` and opens it for verification.

| Stage | WNS | WHS | Failing endpoints | Note |
|---|---:|---:|---:|---|
| Before optimisation | 1.029 ns | — | — | Worst setup on the cross-MMCM processing-window bus |
| After reset-tree replication | 1.172 ns | — | — | Local link-monitor reset tree duplicated |
| Final | 1.341 ns | 0.025 ns | 0 | TNS/THS = 0; worst path is reset recovery |

Source: `build/reports/build_timing_summary.rpt` and `report/optimization.md`. The final WHS is 0.025 ns; it was around 0.048 ns during optimisation. That final change is placement noise and remains positive, so it is not claimed as an optimisation gain.

## Build and reproduce

```bash
vivado -mode batch -source build/build.tcl
MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<BSP generated by the platform build> \
PS_OUT=board/project/ps_app.elf \
python build/ps/build_ps_app.py
<Vitis>/bin/vitis-server.bat --port 8879 &
sleep 10
VP_VITIS_WS=<workspace> <Vitis>/bin/vitis.bat -s build/vitis/rebuild_vitis.py 8879
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
VP_HW_URL=localhost:3121 vivado -mode batch -source board/tcl/flash_qspi.tcl
python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
python src/host/link_selftest.py 192.168.1.10 6
node src/host/uart_cmd_check.mjs --port COM6
```

The full step-by-step procedure is in [`report/reproduction.md`](report/reproduction.md).
The serial command reference is [`report/commands.md`](report/commands.md) (Chinese); device, toolchain and third-party declarations are in [`report/declarations.md`](report/declarations.md).

## Layout

```text
src/rtl/           PL source: top, Ethernet, display, geometry, effects, AXI, HDMI
src/ps/            PS bare-metal: main.c, sd_play.c, linker script
src/constraints/   pins, clock groups, quasi-static CDC, IO candidates
src/host/          sender, telemetry, dashboard, self-test, UART checks
sim/               92 benches; sim/results/ holds the final verdicts
build/build.tcl    Vivado entry
build/tcl/         Vivado build and board-project staging TCL
build/vitis/       Vitis platform rebuild
build/ps/          PS application build
build/sim/         xsim runner
build/reports/     timing, resources, CDC, power, regressions, full-video bench
board/vivado/      Vivado project (.xpr + .srcs)
board/vitis/       Vitis platform descriptor and QEMU arguments
board/project/     bitstream, XSA, PS application
board/scripts/     board bring-up, health, UART, boot image
board/tcl/         JTAG and QSPI single-step scripts
board/measured/    measured logs
board/flash/       BOOT.bin and packaging log
board/compare/     measured vs reference comparison
data/inputs/       test vectors
data/golden/       human comparison images
data/metrics.csv   metrics table
skill/             skill package distilled from the project
report/            design report, verification, optimization, reproduction, collaboration
```

## Limits

Telemetry latency covers the PL only: from frame commit to the start of scan. It is not glass-to-glass. The RGMII transmit pins are in an HR bank without ODELAYE2; 0° forwarding still has about 0.845 ns of TskewT hold margin missing, and both 90° and −45° were rejected on the board. BRAM at 70% is dominated by the full-frame buffers needed for rotation and bilinear interpolation, so a 512×300 source cannot be raised to 1080p on this device. The 185° thin-line case is closed in RTL and the bench, but an eye check is still recommended. Details are in [`report/limits.md`](report/limits.md).

[中文版](README.md)

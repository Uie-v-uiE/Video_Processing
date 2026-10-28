# Multi-Source Video Processing System

A complete video path inside one FPGA: frames arrive on the Ethernet port, leave on HDMI, and the CPU never touches a pixel.

A host PC sends 512×300 RGB565 frames as UDP datagrams to the board. The PL receives them from RGMII, reassembles frames by intra-frame offset, writes whole frames into a DDR ping-pong buffer, reads them back for geometry and effects, and drives a 1024×600 HDMI output. A movable vertical seam splits the screen between the source frame and the processed version of the same frame. The PS only issues commands.

## Why it looks like this

The starting question was narrow: is what the remote viewer sees the complete, processed, current frame? Split into three, it asks whether the frame arrived whole, whether processing actually happened, and whether a failure can be explained.

The first question became the **three-gate frame commit**: every byte present, every source row written, no bad packet. Only then does the display switch frames, so a frame missing one packet never shows up as half a frame — the screen keeps the previous one.

The second became the **same-frame comparison**: the two panes are two read windows into one frame, sharing one geometry engine and one fixed-latency effect chain. Any difference across the seam can only come from the algorithm, never from two independent scalers.

The third became the **on-chip instrument**: aborted frames, missing rows, bad packets, frame gaps and processed-pane integrity are counters in hardware; serial, UDP telemetry and GPIO read the same numbers, and injected packet loss can turn the instrument red on demand.

Those requirements also explain why there are no vendor video IP blocks here: a stock video pipeline moves frames as a stream, with nowhere to put "is this frame complete", and no reason to keep two read windows for comparison. So RGMII sampling, CRC, ARP/ICMP/UDP, offset-based reassembly, the DDR ping-pong, rotation, scaling, bilinear interpolation, the six-stage effect chain, OSD and HDMI timing are all written in-house; device-specific code is confined to the clocking, DDR interface and serialiser primitives.

## Features

- **Three sources**: UDP stream, SD-card raw-frame playback, and a PL-drawn test card, switched at run time and sharing one display path.
- **Geometry**: arbitrary-angle rotation 0–359°, eight zoom steps 0.25×–2.00×, bilinear or nearest-neighbour; zoom can auto-fit to the current angle.
- **Effects**: grayscale, invert, 3×3 blur, 3×3 sharpen, Sobel, threshold (with inverted decision), erode, dilate, plus a bypassable gamma stage; nine control bits, any combination, fixed total latency.
- **Same-frame A/B**: the seam follows either display columns or image columns, can swap sides and hide its marker.
- **OSD**: source and resolution, frame rate, effect projection, angle, zoom, seam position, PL-internal latency, die temperature.
- **Observation**: serial `stat`/`temp`/`link`, 1 Hz UDP telemetry, AXI GPIO.
- **Controls**: on-board keys for angle, serial commands for everything else.

## Data flow

```text
host ──UDP 5001──> RGMII ─> MAC ─> UDP filter ─> reassembly by offset ─> three-gate commit
                                                                         │
                                                                         ▼
                                                              DDR ping-pong (AXI HP)
                                                                         │
                                        ┌────────────────────────────────┴──────────┐
                                        ▼                                           ▼
                                 left pane: source                    right pane: geometry + effects
                                        └──────────────────┬────────────────────────┘
                                                           ▼
                                                   OSD ─> 1024×600 HDMI
```

## Quick start

```bash
vivado -mode batch -source build/build.tcl

MSIM_BIN=<ModelSim>/win64 bash build/sim/run_msim.sh rows udp_reasm reasm_bounds \
     udp_telemetry eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor

PS_CC=<Vitis>/gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-gcc.exe \
PS_BSP=<BSP from the platform build> PS_OUT=board/project/ps_app.elf \
python build/ps/build_ps_app.py

VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
VP_HW_URL=localhost:3121 vivado -mode batch -source board/tcl/flash_qspi.tcl

python src/host/video_sender.py --demo --seconds 8
python src/host/telemetry_listen.py 13
node src/host/uart_cmd_check.mjs --port COM6
```

Step-by-step instructions with expected output are in [`report/reproduction.md`](report/reproduction.md); the serial command reference is [`report/commands.md`](report/commands.md).

## Layout

```text
src/rtl/           PL source: top, Ethernet, display, geometry, effects, AXI, HDMI
src/ps/            PS bare-metal: main.c, sd_play.c, linker script
src/constraints/   pins, clock groups, quasi-static CDC, IO candidates
src/host/          sender, telemetry, dashboard, self-test, UART checks
sim/               benches; sim/results/ holds final verdicts
build/             Vivado entry, TCL, Vitis platform, PS build, sim runners, reports
board/             Vivado project, Vitis platform, bitstream/XSA/ELF, scripts, measurements
data/              test vectors and comparison images
report/            design, verification, optimization, reproduction, commands, limits
```

## Documentation

| Document | Content |
|---|---|
| [`report/design-report.md`](report/design-report.md) | Design report: goals, architecture, key techniques, trade-offs |
| [`report/verification.md`](report/verification.md) | Verification strategy, bench verdicts, board results |
| [`report/optimization.md`](report/optimization.md) | Timing and resource optimisation, including rejected options |
| [`report/reproduction.md`](report/reproduction.md) | From an empty directory to a running board |
| [`report/commands.md`](report/commands.md) | Serial command reference |
| [`report/interface-table.md`](report/interface-table.md) | Register and interface tables |
| [`report/limits.md`](report/limits.md) | Boundaries and known limitations |
| [`sim/README.md`](sim/README.md) | Bench index and verdict rules |

## Measurements

- 241 frames in an 8-second stream, 29.95 fps; the abort counter stays flat under a clean stream.
- Grayscale-only, image-column seam at 185°: processed-pane integrity count is 0 and valid.
- Three-stage fault injection: 22.0 fps clean → 0 fps with about 14.3 aborts per second at one dropped packet in 100 → 18.9 fps after recovery.
- After a stop and restart, the hardware remembers a maximum frame gap of 22,061 ms.
- With the bitstream in QSPI the board boots without a host, and `stat`/`link` respond.

## Limits

Telemetry latency covers the PL only, from frame commit to the start of scan; it is not glass-to-glass. The RGMII transmit pins sit in a bank without output delay cells, so the forwarding phase stays at 0° and its hold margin is tight; the other two phases were rejected on the board. The frame size stays at 512×300 because the whole frame has to fit in on-chip memory. Details are in [`report/limits.md`](report/limits.md).

## License

MIT, see [`LICENSE`](LICENSE).

[中文版](README.md)

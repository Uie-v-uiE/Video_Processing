# Multi-Source Video Processing System

A fully hardware video path on Zynq-7020, with an observation instrument that can be read back over the network and the serial port.

A host PC sends 512×300 RGB565 frames as UDP datagrams of at most 1392 bytes to port 5001. The PL receives them from RGMII, passes them through the MAC, UDP filtering and offset-based frame reassembly, and writes complete frames into a DDR ping-pong buffer. The display side reads a frame back, applies scaling, arbitrary-angle rotation, bilinear interpolation and a six-stage effect chain, then overlays OSD text and expands the result ×2 to a 1024×600, 59.5 Hz HDMI output. Pixels never pass through the PS. A vertical seam in the middle of the screen shows the source on the left and the processed version of the same frame on the right; both sides share the same geometry engine and a fixed 15-cycle effect chain.

## What can be checked

| Claim | How to check | Reading |
|---|---|---|
| A frame is committed only when complete | Row-coverage bitmap, byte gate, abort counter | 241 frames in 8 s, 29.95 fps; abort count does not grow under a clean stream |
| The processed pane does not leak the source | Non-gray pixel count with only grayscale enabled and split video | `pane_bad=0` at 185°, 30 fps, count valid |
| The instrument can be made to fail | Clean → 1 packet in 100 dropped → clean | 22.0 fps / 0 fps with 14.3 aborts per second / 18.9 fps, PASS |
| Effect latency is configuration-independent | Cycle-by-cycle alignment in the full video bench and OSD latency | Constant 15 pixel clocks; PL-internal frame latency 2–16 ms |
| Frame-gap statistics are readable | Serial `link clr` → stream → stop → `link` | `gap_valid=1` while streaming; `stall` grows after stop; `gap_max=22,061 ms` after restart |

## Implementation readings

Device: `xc7z020clg484-2`. Tools: Vivado / Vitis 2025.2.1.

| Item | Reading |
|---|---|
| Timing | WNS 1.341 ns, WHS 0.025 ns, TNS = THS = 0, failed endpoints 0 |
| Per-clock setup | `clk_fpga_0` 2.159 ns; `eth_rxc` 3.247 ns; `sys_clk` 14.797 ns; `clkout0_1` 3.264 ns; `clkout3` 1.727 ns |
| Resources | LUT 14,967 (28.13%), FF 9,095 (8.55%), BRAM 98 (70.00%), DSP 19 (8.64%) |
| Power / junction | 2.228 W dynamic (2.406 W total) / 52.8 °C, tool estimate with low confidence |
| Simulation | 19 standard regressions (17 plus `eth_ingress_integrity` and `saver_tail_full`), `fail=0`; full-video C17/C25/C26 arms PASS |
| Board | QSPI image written with on-chip verify; cold boot, serial `link`, network telemetry, fault injection, continuous stream and temperature all pass |
| Display | 1024×600 at 59.5 Hz; source 512×300 at 30 fps |

## Build and run

```bash
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
VP_XSDB=<Vitis>/bin/xsdb.bat VP_VIVADO_BIN=<Vivado>/bin bash board/scripts/board_flash.sh
python src/host/video_sender.py --demo --seconds 8
```

PS application build, Vitis platform rebuild, QSPI programming and the full serial acceptance are described in [`report/reproduction.md`](report/reproduction.md). Board scripts and measured outputs are in [`board/README.md`](board/README.md).

## Layout

```text
src/              RTL, PS firmware, constraints, host tools
sim/              unit, integration and full-video benches
build/            build TCL, checkers, implementation reports
board/            Vivado/Vitis projects, board scripts, measured outputs
data/             test inputs, golden images, metrics
skill/            reusable practices distilled from the project
report/           design report, verification, optimization, reproduction
technical_document.pdf/docx
poster.pdf/png
```

## For reviewers

- Technical document: [`technical_document.pdf`](technical_document.pdf) / [`report/design-report.md`](report/design-report.md)
- Poster: [`poster.pdf`](poster.pdf)
- Verification and criteria: [`report/verification.md`](report/verification.md)
- Timing and resource optimization: [`report/optimization.md`](report/optimization.md)
- Reproduction: [`report/reproduction.md`](report/reproduction.md)
- Limits: [`report/limits.md`](report/limits.md)
- LLM collaboration: [`report/llm-collaboration.md`](report/llm-collaboration.md)
- Skill package: [`skill/README.md`](skill/README.md)

## Limits

Telemetry latency covers the PL only: from frame commit to the start of scan. It is not glass-to-glass. The RGMII transmit pins are in an HR bank without ODELAYE2; 0° forwarding still has about 0.845 ns of TskewT hold margin missing, and both 90° and −45° were rejected on the board. BRAM at 70% is dominated by the full-frame buffers needed for rotation and bilinear interpolation, so a 512×300 source cannot be raised to 1080p on this device. The 185° thin-line case is closed in RTL and the bench, but an eye check is still recommended. Details are in [`report/limits.md`](report/limits.md).

[中文版](README.md)

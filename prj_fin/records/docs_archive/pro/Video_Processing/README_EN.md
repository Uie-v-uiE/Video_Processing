# Zynq Real-Time Video Image Processing with Pixel-Level A/B Display

[中文](README.md) · English

## Introduction

The host splits 512×300 RGB565 frames into UDP packets of at most 1392 bytes and sends them to port 5001 on
the board. No software touches individual pixels on this path. The PL recovers GMII from RGMII, reassembles
the Ethernet frame, filters by port and writes the payload into the ping-pong DDR frame buffers as an AXI
master; only the SD path is DMA'd in by the PS. The PL then reads a frame back, runs it through the effect
chain of six pipeline stages switched bit by bit by a 9-bit control word, through zoom and rotation, through
the split blend and the five-line OSD, and drives 1024×600 HDMI through a ×2 expand. Whatever combination of
algorithms is active, the chain latency stays 15 cycles.

One vertical seam splits the screen. The left window shows the original, the right window shows the processed
image in the same coordinate system, and the seam position is a run-time parameter in the range 0 to 100 %.
This layout is both the demo and an instrument: misalignment, dropped columns and out-of-range fill become
visible on both sides of the seam at the same moment.

Three sources feed the chain, the UDP video stream from the network, a pre-converted SD frame sequence, and a
test card drawn by the PL. `src_arb` arbitrates them and a long key press switches. Inside the PL,
`link_monitor` keeps counting received packets, drops and frame gaps. The same counters go to the OSD, can be
read back over AXI GPIO with xsdb, where GPIO_0 selects a lane and GPIO_1 returns its value, and can be
cleared by serial commands. Besides the RTL and the host tools, the repository carries 83 testbenches
(`sim/tb_*.v`) and 49 practice entries decoupled from this topic (`skill/`). The commands further down re-run
every tool report.

## Directory guide

src/ —— 80 .v files in `src/rtl/`, PS-side C in `src/ps/`, 9 .xdc files in `src/constraints/` (2 loaded, 7 candidates/experiments), 26 .mjs and 3 .py host tools in `src/host/`  
sim/ —— 83 .v files at the top level (82 of them `tb_*.v`); the runner line under the table in `sim/README.md`  
build/ —— 7 flow-entry TCL scripts, the checkers, and 7 raw tool reports under `build/report/`  
board/ —— on-board project, the three-step JTAG flashing scripts and measured output (serial captures, board verify)  
data/ —— test data and reference results: 8 sequences in `data/inputs/`, images in `data/golden/`, `data/metrics.csv` with a header row and 32 metric rows (four added by the 2026-10-20 timing-debt round)  
skill/ —— 49 SKILL.md entries; each states scope, usage, failure conditions and verified reuse  
report/ —— design report, failure analysis, reproduction notes and the LLM collaboration record  

## Reproducing from scratch

### Environment

The device is `xc7z020clg484-2`, the ZYNQ7020 CLG484 module on this board, speed grade 2, and constraints follow that board's schematic. Tools: Vivado / Vitis 2025.2.1, Node 24, Python 3.12 (no third-party packages, serial through PowerShell). Every script was re-run from scratch on that version; the steps are in `report/build.md` and the part and version declarations in `report/declarations.md`.

### Build

```bash
vivado -mode batch -source build/build.tcl          # project -> synthesis -> implementation -> bitstream
vivado -mode batch -source build/report.tcl         # re-emit the 7 reports into build/report/
vivado -mode batch -source build/gen_bit.tcl        # archive .bit and .xsa into board/
```

Step-by-step entries are `build/create_project.tcl` / `build/add_sources.tcl` / `build/synth.tcl` / `build/impl.tcl`. One full flow measured about 20 minutes (19 min 30 s), of which synthesis took 10 min 09 s and implementation including `write_bitstream` took 7 min 22 s (log `build/r118_build_console.txt`); another run took the staged chain without implementation: 63 s for the project, 10 min 53 s for synthesis, 1 min 34 s for the reports (`build/evidence/r121_c4_verify.txt`).

### Programming the board and verification

```bash
bash build/board_verify.sh --geom --battery        # geometry checks + the 105-command serial regression, verdict last
bash run_test.sh                                    # one click: ping -> readback -> built-in clip -> counter reconcile
node src/host/video_sender.mjs --test bars          # general sender; any file via src/host/video_sender.py --input
```

Expected: scrolling bars with a yellow block moving right, the OSD second-line FPS cell settling at 29–30, and the `lane8` received-packet delta equal
to the packets sent (difference 0). The three-step JTAG chain is in `board/README.md`.

## Key numbers and their sources

The board now runs r132, bitstream identity `build/system.bit md5=cb907d3e4898` (produced by the run logged in
`build/r132_streamwrap_build.log`; the 2026-10-17 11:36 reports `build/utilization.rpt` / `timing_summary.rpt` / `power.rpt` are that same run).
Every reading below comes from that build. The all-green gate set quoted below is r132, taken from `build/r132_gates.txt`; two passes inside that round went red, and `report/06-validation.md` keeps that account.

Main clocks: pixel clock 50 MHz (`clkout0_1`, H_TOTAL 1344 / V_TOTAL 625, so 59.5 Hz field), PL logic clock 100 MHz (`clk_fpga_0`), Ethernet capture domain 125 MHz (`eth_rxc`); constraints live in `src/constraints/` and cover clocks, I/O delays, clock uncertainty and async groups. After implementation the design-wide worst setup slack is 0.687 ns with failing setup and hold endpoints 0 / 51027, so intra-die paths are met (WNS 0.687 ns / TNS 0 ns / 0 failing endpoints), and both directions are 0.

| Row name (machine-read) | Reading | Source |
| --- | --- | --- |
| Design-wide setup WNS | WNS **0.687 ns**, WHS **0.004 ns**, failing setup/hold endpoints **0 / 51027** (both directions 0. This build does not load the RGMII capture input window, so those 5 receive endpoints are outside timing coverage; see `report/08-limits.md` §4) | `build/timing_summary.rpt` (Design Timing Summary), `data/metrics.csv` rows 4-6 |
| Per-clock setup slack | 125 MHz capture domain `eth_rxc` **0.687 ns** (8.59 % of its 8 ns period, tightest cell design-wide); 100 MHz `clk_fpga_0` **1.571 ns** (15.71 % of 10 ns); 50 MHz display domain `clkout0_1` **3.287 ns** (16.44 % of 20 ns); `sys_clk` **14.294 ns** (71.47 % of 20 ns, the loosest) | `build/timing_summary.rpt` (Intra Clock Table) |
| Hold time | worst cell design-wide is in `eth_rxc`, **0.004 ns**; per-clock WHS `clk_fpga_0` **0.048 ns**, `clkout0_1` **0.067 ns**, `sys_clk` **0.121 ns**, `eth_rxc` **0.004 ns**. Caveat: only `eth_rxc` carries the self-added 0.800 ns hold uncertainty (`src/constraints/rk_zynq7020.xdc:50`), so these four are comparable within a domain only (`report/08-limits.md` §6) | `build/timing_summary.rpt`, `build/hold_paths.rpt`, `build/clock_uncertainty.rpt` |
| BRAM / LUT / FF / DSP | BRAM **96 tiles (68.57 %)** / 140, LUT **14013 (26.34 %)**, FF **8132 (7.64 %)**, DSP **19 (8.64 %)** / 220 | `build/utilization.rpt`, `data/metrics.csv` rows 7-10 |
| Power | dynamic **2.213 W**, on-chip total **2.390 W**; estimated junction temperature **52.6 °C** at 25.0 °C ambient with effective TJA 11.5 °C/W and max ambient 57.4 °C. Tool confidence is **Low**, so this cell is an estimate rather than a measurement | `build/power.rpt`; `data/metrics.csv` rows 20-21 |
| Pre-release checks | the 24-item gate check reads 24 green / 0 red, last line `GATES: ALL PASS (24 items judged)`; the top-level whole-screen rack reads **165 verdicts / 0 FAIL**, last line `RESULT tb_v98_top_seam PASS`, and its header carries the three fingerprints `top_md5=c778dc4416b3 tb_md5=3975c335ab26 rtl_md5=93938780ccd6`, taken from the same run as the working tree | `build/r132_gates.txt`, `build/tb_v98_report.txt`, `build/tb_edge_rim_r132.txt` |

These reports re-run from the three commands above: what `report.tcl` re-emits differs from the archived files in the Date line and the `-file` path
only, byte-identical otherwise (`build/evidence/r121_note_c4.txt`, run log `build/evidence/r121_report_archive.txt`). On the board side the two
100-frame sliding windows on the SD sequence read 29.956 and 29.815 fps (`build/evidence/r87_boot_stat_drain.txt`); the row in `data/metrics.csv`
rounds that to 29.8 – 30.0, while the per-pixel comparison of the 9 select bits in the effect chain and the three sources is judged by the `sim/tb_*.v` benches.

Boundaries and known limitations are registered item by item in `report/08-limits.md` (which dimensions of the HDMI source side were
measured, how the PS-side firmware is rebuilt and re-verified on the board, what is bound to the tool version), defects and deliberately
kept failing items in `report/known_issues.md`, and the consolidated open-items table in `report/90-open-items.md`.

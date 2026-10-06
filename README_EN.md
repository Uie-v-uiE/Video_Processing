# Zynq Real-Time Video Image Processing with Pixel-Level A/B Display

[中文](README.md) · English

## Introduction (what the system does)

The host splits 512×300 RGB565 frames into UDP packets of at most 1392 bytes and sends them to port 5001 on the board. Reception does not go through the PS: the PL recovers GMII from RGMII, reassembles the Ethernet frame, filters by port and writes the payload into the ping-pong DDR frame buffers as an AXI master (only the SD path is DMA'd in by the PS). The PL then reads a frame back, runs the per-bit switchable effect chain (six pipeline stages, a 9-bit control word, one bit per algorithm) plus zoom, rotate and split blend, and drives 1024×600 HDMI through a ×2 expand. One vertical seam splits the screen: left window the original, right window the processed image in the same coordinate system, seam position from the control word (0–100 %). That seam also works as a measuring instrument: misalignment, dropped columns and out-of-range fill show up on both sides of it at once.

Three sources feed it: the UDP video stream from the network, a pre-converted SD frame sequence, and a test card drawn by the PL. `src_arb` arbitrates, a long key press switches. `link_monitor` inside the PL counts received packets, drops and frame gaps. The counters print on the OSD, xsdb reads them back over AXI GPIO (lane select in GPIO_0, value in GPIO_1), and a serial command clears them. Beyond the RTL and the host tools the repository carries 82 testbenches (`sim/tb_*.v`) and 49 practice entries decoupled from this topic (`skills/`); the tool reports re-run with the three commands further down.

## Directory guide

src/ —— 80 .v files in `src/rtl/`, PS-side C in `src/ps/`, 9 .xdc files in `src/constraints/` (2 loaded, 7 candidates/experiments), 26 .mjs and 3 .py host tools in `src/host/`  
sim/ —— 83 .v files at the top level (82 of them `tb_*.v`); the runner line under the table in `sim/README.md`  
build/ —— 7 flow-entry TCL scripts, the checkers, and 7 raw tool reports under `build/report/`  
board/ —— on-board project, the three-step JTAG flashing scripts and measured output (serial captures, board verify)  
data/ —— test data and reference results: 8 sequences in `data/inputs/`, images in `data/golden/`, `data/metrics.csv` with a header row and 28 metric rows  
skills/ —— 49 SKILL.md entries; each states scope, usage, failure conditions and verified reuse  
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

Step-by-step entries are `build/create_project.tcl` / `build/add_sources.tcl` / `build/synth.tcl` / `build/impl.tcl`. One full flow measured about 20 minutes (19 min 30 s): synthesis 10 min 09 s, implementation including `write_bitstream` 7 min 22 s, log in `build/r118_build_console.txt`. Another run took the staged chain without implementation: 63 s for the project, 10 min 53 s for synthesis, 1 min 34 s for the reports, read from `build/evidence/r121_c4_verify.txt`.

### Programming the board and verification

```bash
bash build/board_verify.sh --geom --battery        # geometry checks + the 105-command serial regression, verdict last
bash run_test.sh                                    # one click: ping -> readback -> built-in clip -> counter reconcile
node src/host/video_sender.mjs --test bars          # general sender; any file via src/host/video_sender.py --input
```

Expected: scrolling bars with a yellow block moving right, the OSD second-line FPS cell settling at 29–30, and the `lane8` received-packet delta equal
to the packets sent (difference 0). The three-step JTAG chain is in `board/README.md`.

## Key numbers and their sources

The board now runs r126, bitstream identity `system.bit md5=cd04907e1369` (the identity line is written by the check record itself, `build/r126_gates.txt`; byte-identical archives are in `build/r118_gates_final.txt` and `build/evidence/r118_board/`). Every reading in the table comes from the build that produced that bitstream.

Main clocks: pixel clock 50 MHz (`clkout0_1`, H_TOTAL 1344 / V_TOTAL 625, field 59.5 Hz), PL logic clock 100 MHz (`clk_fpga_0`), Ethernet capture domain 125 MHz (`eth_rxc`). Constraints live in `src/constraints/` and cover clocks, I/O delays, clock uncertainty and async groups. After implementation the design-wide worst setup slack is 0.739 ns; failing setup and hold endpoints are 0 / 51135, WNS 0.739 ns / TNS 0 ns / 0 failing endpoints, both directions 0, so the intra-die paths are met.

| Row name (machine-read) | Reading | Source |
| --- | --- | --- |
| Design-wide setup WNS | WNS **0.739 ns**, WHS **0.052 ns**, failing setup/hold endpoints **0 / 51135** (both directions 0. This build does not load the RGMII capture input window, so `eth_rx_ctl` and `eth_rxd[3:0]`, 5 receive endpoints in total, are outside the scope of the timing check; why the window went back to a candidate file is in `report/08-limits.md` §4) | `build/report/timing_summary.rpt:151`, `data/metrics.csv` rows 4–6 |
| Per-clock setup slack | 125 MHz capture domain `eth_rxc` **0.739 ns** (9.24 % of its 8 ns period, tightest cell design-wide); 100 MHz `clk_fpga_0` **1.850 ns** (18.5 % of 10 ns); 50 MHz display domain `clkout0_1` **3.630 ns** (18.15 % of 20 ns); `sys_clk` **14.876 ns** (74.38 % of 20 ns, widest) | `build/report/timing_summary.rpt` (Intra Clock Table + Clock Summary) |
| Hold time | worst cell design-wide is in `eth_rxc`, **0.052 ns**; per-clock WHS `clk_fpga_0` **0.053 ns**, `clkout0_1` **0.059 ns**, `sys_clk` **0.222 ns**, `eth_rxc` **0.052 ns**. Only the `eth_rxc` domain carries a self-added 0.800 ns hold uncertainty (`src/constraints/rk_zynq7020.xdc:50`); the other three domains have no such line ⇒ the four values rank within a domain only, and a cross-domain ranking needs the uncertainty band completed first (`report/08-limits.md` §6) | `build/report/timing_summary.rpt` (WHS column), `build/hold_paths.rpt`, `build/clock_uncertainty.rpt`; uniform band `build/evidence/r115_unc/summary_hold_after.txt:151`: WHS **-0.747 ns**, 25742 failing, not adopted |
| BRAM / LUT / FF / DSP | BRAM **95.5 tiles (68.21 %)** / 140, LUT **14154 (26.61 %)**, FF **8188 (7.70 %)**, DSP **19 (8.64 %)** / 220 | `build/report/utilization.rpt`, `data/metrics.csv` rows 7–10 |
| Power | dynamic **2.213 W** (on-chip total 2.391 W), estimated junction temperature **52.6 °C**, tool confidence **Low** ⇒ estimate, not measurement | `build/report/power.rpt`, `data/metrics.csv` rows 27–28 |
| Pre-release checks | This page makes no gate-green claim; the authoritative line is the last one printed by `bash build/gates.sh`. For the build on the board the 24-item gate check reads 23 green / 1 red. That one failing item, `C5c`, is a verdict the top-level full-screen testbench makes about itself: output rows in the frame-head band carry the previous frame while the body rows are correct cell by cell. Symptom, the explanations already ruled out and what would close it are in `report/08-limits.md` §1. The newest fully green archive belongs to an earlier build (`build/r75_gates.txt`); it is not this build and the two readings must not be mixed | `build/r118_gates.txt` |

The three commands above re-run these reports: what `report.tcl` re-emits differs from the archived files in the Date line and the `-file` path
only, byte-identical otherwise, with the comparison in `build/evidence/r121_note_c4.txt` and the run log
`build/evidence/r121_report_archive.txt`. On the board the two 100-frame sliding windows on the SD sequence read 29.956 and 29.815 fps
(`build/evidence/r87_boot_stat_drain.txt`); the row in `data/metrics.csv` rounds that to 29.8 – 30.0. The `sim/tb_*.v` files judge the per-pixel
comparison of the 9 select bits in the effect chain and the three sources.

Boundaries and known limitations are registered item by item in 限制清单 (which dimensions of the HDMI source side
were measured, how the PS-side firmware is rebuilt and re-verified on the board, what is bound to the tool version). Defects and deliberately kept
failing items are in 问题清单, the consolidated open items in 未决项集中表.

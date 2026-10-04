# Zynq Real-Time Video Image Processing with Pixel-Level A/B Display

[中文](README.md) · English

## 1. Introduction

The host splits 512×300 RGB565 frames into UDP packets of at most 1392 bytes on port 5001; the PS receives them into DDR, the PL reads the
frame back, runs a 9-stage chain (gray, blur, sharpen, Sobel, morphology, gamma, zoom, rotate, split blend), drives 1024×600 HDMI through a
×2 expand, and draws the statistics into the OSD. `link_monitor` inside the PL keeps counting received packets, drops and frame gaps, and the
host reads those lanes back through xsdb by selecting a lane in GPIO_0 bits[31:27] and taking the value from GPIO_1. Besides the network
source the board plays a pre-converted SD frame sequence and its own test card; `src_arb` arbitrates the three and a long key press switches.

### Highlights

- 0 / 51135: after implementation there are no failing setup or hold endpoints; the design-wide worst setup slack is 0.739 ns (`build/report/timing_summary.rpt`).
- 29.956 / 29.815 fps: the two measured 100-frame sliding windows on the SD pre-converted sequence (evidence `build/evidence/r87_boot_stat_drain.txt`; the row in `data/metrics.csv` rounds it to 29.8 - 30.0).
- 9 stages × 512×300: one chain switchable per pixel; the left window shows the original and the right window the processed image, seam position from the control word (0–100 %).
- 81 testbenches: every key module and known trap has a `sim/tb_*.v` bench; the list is generated from the file header comments by `node build/gen_sim_readme.mjs --apply`.
- 49 skill entries: `skills/` is a topic-decoupled practice package, shape-checked by `node skills/_meta/check-skill-package.mjs` (current value: 0 red).

### Directories

src/ —— 80 .v files in `src/rtl/`, PS-side C in `src/host/ps/`, 9 .xdc files in `src/constraints/` (2 loaded, 7 candidates/experiments), 26 .mjs and 3 .py host tools in `src/host/`  
sim/ —— 84 .v files (81 of them `tb_*.v`); the runner line under the table in `sim/README.md`  
build/ —— 7 flow-entry TCL scripts, the checkers, and 7 raw tool reports under `build/report/`  
board/ —— on-board project, the three-step JTAG flashing scripts and measured output (serial captures, board verify)  
data/ —— test data and reference results: 8 sequences in `data/inputs/`, images in `data/golden/`, 28 metric rows in `data/metrics.csv`  
skills/ —— 49 SKILL.md entries; the README states scope, usage, failure conditions and verified reuse  
report/ —— design report, failure analysis, reproduction notes and the LLM collaboration record  

## 2. Reproduction

### Environment

Device `xc7z020clg484-2`, the string the reports carry (`build/report/utilization.rpt:8`; `build/report/power.rpt:3` reads `Vivado v.2025.2.1`). The board
is a ZYNQ7020 CLG484 speed grade 2; the contest guidance names `xc7z020clg400-1`, a different package and pin count, so constraints follow the real board.
Tools: Vivado / Vitis 2025.2.1 (the guide recommends 2026.1; every script reproduces from scratch on 2025.2.1, `report/build.md`), Node 24, Python 3.12 with no third-party packages (serial uses PowerShell).

### Build

```bash
vivado -mode batch -source build/build.tcl          # project -> synthesis -> implementation -> bitstream
vivado -mode batch -source build/report.tcl         # re-emit the 7 reports into build/report/
vivado -mode batch -source build/gen_bit.tcl        # archive .bit and .xsa into board/
```

Step-by-step entries are `build/create_project.tcl` / `build/add_sources.tcl` / `build/synth.tcl` / `build/impl.tcl`. One full flow measured about 20 minutes: the r118
run ran 04:18:27 -> 04:37:57, 19 min 30 s, of which synthesis took 10 min 09 s and implementation including `write_bitstream` took 7 min 22 s (both
timestamps in `build/r118_build_console.txt`). A staged-chain run without implementation measured 63 s for the project, 10 min 53 s for synthesis and 1 min 34 s for the reports (`build/evidence/r121_c4_verify.txt`).

### Board programming and verification

```bash
bash build/board_verify.sh --geom --battery        # geometry criteria + the 105-command serial battery, verdict last
bash run_test.sh                                    # one click: ping -> readback -> built-in clip -> counter reconcile
node src/host/video_sender.mjs --test bars          # general sender; any file via src/host/video_sender.py --input
```

Expected: scrolling bars with a yellow block moving right, the OSD second-line FPS cell settling at 29–30, and the `lane8`
received-packet delta equal to the packets sent (difference 0). The three-step JTAG chain is in `board/README.md`.

The board currently runs r118: the release gate reads 23 green / 1 red over 24 items, the single red being the declared `C5c` top-level bench
self-verdict (identity line `system.bit md5=cd04907e1369` in `build/r118_gates.txt`; byte-identical final copies in `build/r118_gates_final.txt`
and `build/evidence/r118_board/`). This version claims no 'all gates green'; all-gates-green is r75 (the newest frozen set on disk judging every
item green, `build/r75_gates.txt`), while the board runs r118.

### Timing notes

Main clocks: pixel clock 50 MHz (`clkout0_1`, H_TOTAL 1344 / V_TOTAL 625 ⇒ 59.5 Hz field), PL logic clock 100 MHz
(`clk_fpga_0`), Ethernet RX domain 125 MHz (`eth_rxc`). Constraints live in `src/constraints/` and cover clocks, I/O delays,
clock uncertainty and async clock groups.

| Row name (machine-read) | Reading | Source |
| --- | --- | --- |
| Design-wide setup WNS | WNS **0.739 ns**, WHS **0.052 ns**, failing setup/hold endpoints **0 / 51135** (both 0; this build ships without the RGMII capture input window ⇒ those 5 I/O endpoints are unchecked, unchecked is not met) | `build/report/timing_summary.rpt:151` (re-read), `data/metrics.csv` rows 4–6 |
| Per-clock setup slack | 125 MHz capture domain `eth_rxc` **0.739 ns** (9.24 % of its 8 ns period, tightest cell design-wide); 100 MHz `clk_fpga_0` **1.850 ns** (18.5 % of 10 ns); 50 MHz display domain `clkout0_1` **3.630 ns** (18.15 % of 20 ns); `sys_clk` **14.876 ns** (74.38 % of 20 ns, widest) | `build/report/timing_summary.rpt` (Intra Clock Table + Clock Summary) |
| Hold time | worst cell design-wide is in `eth_rxc`, **0.052 ns**; per-clock WHS `clk_fpga_0` **0.053 ns**, `clkout0_1` **0.059 ns**, `sys_clk` **0.222 ns**, `eth_rxc` **0.052 ns**. Only `eth_rxc` carries the 0.800 ns hold uncertainty added in r79 and the other three domains have no such line ⇒ the four values rank within a domain only, not across domains until the band is completed | `build/report/timing_summary.rpt` (WHS column), `build/hold_paths.rpt`, `build/clock_uncertainty.rpt`; uniform band `build/evidence/r115_unc/summary_hold_after.txt:151`: WHS **-0.747 ns**, 25742 failing, not adopted |
| BRAM / LUT / FF / DSP | BRAM **95.5 tiles (68.21 %)** / 140, LUT **14154 (26.61 %)**, FF **8188 (7.70 %)**, DSP **19 (8.64 %)** / 220 | `build/report/utilization.rpt`, `data/metrics.csv` rows 7–10 |
| Power | dynamic **2.213 W** (on-chip total 2.391 W), estimated junction temperature **52.6 °C**, tool confidence **Low** ⇒ **estimate, not measurement** | `build/report/power.rpt`, `data/metrics.csv` rows 26–27 |

Conclusion: intra-die paths are met (WNS 0.739 ns, TNS 0 ns, 0 failing endpoints) and the reports re-run from the three commands above; the 7 files
`build/report.tcl` re-emits differ from the archived ones in the Date line and the `-file` path only, byte-identical otherwise (`build/evidence/r121_note_c4.txt`; run log `build/evidence/r121_report_archive.txt`).

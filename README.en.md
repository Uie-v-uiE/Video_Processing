[中文](README.md)

# Real-time video processing on Zynq with per-pixel original/processed comparison

A single Zynq-7020 (`xc7z020clg484-2`) runs the whole path: video arrives from
**Gigabit Ethernet, an SD card or an on-chip test card**, the PL scales, rotates and
filters it, and the result leaves as **HDMI 1024x600 at 59.5 Hz** (50 MHz pixel clock, 1344x625 totals) (the processing canvas
is 512x300 RGB565, expanded x2 on the way out). Left of any vertical line on the panel
you see the **unprocessed** picture, right of it the **processed** one in the same
coordinate system. The seam can be fixed, auto-swept, or locked into the image domain
so it travels with rotation and zoom.

That same-frame, per-pixel comparison is the point of the design: it is both a display
mode and **a measuring instrument**. Edge stripes, a one-row offset or a single
out-of-range cell show up without any extra probe, and can be computed from the same
geometry that produced them - which is also what lets a testbench turn them into numbers.

## Features

- **Three sources, arbitrated in hardware**: UDP video over self-written RGMII receive
  logic (with CRC check and corrupt-word counters), local SD playback (own FAT32
  cluster-chain parser, no file-system library), and a dynamic on-chip test card. If a
  source stops heartbeating, another takes over within half a second; the PS only issues
  commands and never sits in the data path.
- **Geometry path**: eight zoom steps (fixed-point reciprocal, no run-time division),
  several rotation angles (sine/cosine ROM with quadrant folding), nearest-neighbour and
  bilinear interpolation switchable at run time.
- **Effect chain**: grayscale, invert, 3x3 box blur, sharpen, Sobel, threshold
  binarisation (with polarity flip), 3x3 erode/dilate - nine control bits, every stage
  bypassable, the chain a constant 15 pipeline stages deep.
- **Comparison display**: seam anywhere from 0 to 100 %, sides swappable, 2-pixel marker
  optional; the original tap is aligned to the processed one by a line delay ring, same
  cycle and same column.
- **On-screen state**: five OSD lines (`N_LINES=5`) - source, angle, zoom step and owner,
  effect code, seam position, frame rate, in-link latency, die temperature.
- **Online self-diagnosis**: received / dropped / corrupt / CRC counters, ping-pong bank
  state and in-link latency, all counted in hardware, shown on the OSD and readable over
  the serial port, so cable-pull and card-pull behaviour can be reconciled afterwards.
- **Reproducible to the bit**: one command builds the bitstream, one script runs the gate
  and the on-board verification, and Vivado's own reports ship with the package. Numbers
  are quoted only where they were measured; estimates (power) are labelled as estimates.

## Reproducing it

```bash
# 1) project, synthesis, implementation, bitstream (Vivado 2025.2.1, command line)
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 2) gate: timing / resources / ports / CDC / doc consistency + full-panel testbench
#    (the item count and verdict are whatever this script prints - nothing else is authoritative)
bash build/gates.sh
# 3) on-board, JTAG only - this project never writes QSPI/SPI flash
<Vitis>/bin/xsdb.bat build/tcl/ps_jtag_boot.tcl
vivado -mode batch -source build/tcl/program_pl.tcl
<Vitis>/bin/xsdb.bat build/tcl/ps_app_reload.tcl
VP_XSDB=<Vitis>/bin/xsdb.bat bash build/board_verify.sh --battery --geom
```

Host side: [src/host/video_sender.py](src/host/video_sender.py) streams **any video file**
(it decodes through ffmpeg when installed, and falls back to a built-in test pattern when
not; every source is scaled to the PL's 512x300 canvas). With the board on your desk,
**double-click [send_demo.bat](send_demo.bat)** - it pings the board first, then streams
the built-in test video. Commands, registers and every criterion are in
[report/HOST_GUIDE.md](report/HOST_GUIDE.md), [report/COMMANDS.md](report/COMMANDS.md),
[report/BUILD.md](report/BUILD.md) and [board/README.md](board/README.md).

## Key numbers (each one names its report)

| Metric | Reading | Source |
|---|---|---|
| Design-wide setup WNS | **0.608 ns** (the board now runs r103, flashed at 21:32 by the three-step JTAG chain, `bit f8439575eec5`; the 20-item gate check reads 19 green / 1 red and that single red is the declared `C5c`), failing setup/hold endpoints **0 / 50868** | `build/timing_summary.rpt`, `build/r103_gates.txt` |
| Per-clock setup slack | 125 MHz receive domain `eth_rxc` **0.608 ns** (7.6 % of its 8 ns period, and the design's worst path); 100 MHz `clk_fpga_0` **1.035 ns** (10.4 %); 50 MHz display domain `clkout0_1` **1.061 ns** (5.3 %); `sys_clk` **14.849 ns** | same file, Intra Clock Table. The delta versus a previous build is neither gain nor loss - the same path measured a 0.4 ns placement swing between builds |
| Hold time | worst **0.053 ns** (125 MHz receive domain `eth_rxc`), display domain **0.056**, 100 MHz `clk_fpga_0` **0.062**, `sys_clk` **0.134** - the thinnest class of margin, and that cell is **1 logic level with 81.0 % route** (`build/hold_paths.rpt`, regenerated this round); quoted **after** the 0.8 ns hold uncertainty this repo imposes | same file |
| BRAM / LUT / FF / DSP | **95 tiles (67.86 %) / 14333 (26.94 %) / 8079 (7.59 %) / 19 (8.64 %)** | `build/utilization.rpt` |
| Power | **2.212 W** dynamic (2.389 W total on-chip), estimated junction temperature **52.6 degC** (tool confidence Low; **an estimate**, no measured current and no SAF file; the on-die XADC reading is a separate path - serial `temp` / the OSD cell) | `build/power.rpt` |
| SD local playback | **29.8 - 30.0 fps** (100-frame sliding window, read back from the board) | [data/metrics.csv](data/metrics.csv) |
| On-board verification | 100-command serial battery PASS, geometry "last hop" 8/8 PASS, `drop_words=0` while streaming | [board/ACCEPTANCE.md](board/ACCEPTANCE.md) |

Trends, which optimisations were rejected by evidence, and why a raw WNS delta is not
accepted as a gain are in [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) and
[report/PERF_REPORT.md](report/PERF_REPORT.md). This page deliberately does not copy them -
the same number written in two places always drifts.

**This page makes no gate-green claim.** Whether a given build passes the gate, how many
items are judged and which one is red is decided only by the line `bash build/gates.sh`
prints (if something fails it says so explicitly instead of rounding it off).

## Layout

| Directory | Contents |
|---|---|
| `src/rtl/` | PL logic, split into `top / video / process / eth / hdmi / clocks / axi / util` |
| `src/ps/` | bare-metal firmware: command parser, register setup, SD playback, counter read-back |
| `src/host/` | PC-side tools: Python streamer, register reader, documentation consistency checks |
| `src/constraints/` | pin and timing constraints |
| `sim/` | testbenches and runners; the one that instantiates the whole video top is the primary geometry/display ruler. `sim/NAMES.md` maps old to new bench names |
| `build/` | reproducible build scripts (`tcl/`, one command produces the bitstream) plus synthesis/implementation reports (flat under `build/` in this repo; the exporter flattens the same set into `build/reports/` inside the submission package) and the gate and on-board read-back runners; build outputs (.bit/.xsa/.elf) land here too - see [build/README.md](build/README.md) |
| `board/` | what runs on the board, how to start it, and what was read back ([board/README.md](board/README.md), [board/ACCEPTANCE.md](board/ACCEPTANCE.md)) |
| `data/` | `golden/` reference images, `measured/` measurements, and `metrics.csv` as the single number table |
| `skill/` | skill cards distilled from the LLM collaboration; each card has six fixed parts: trigger, when it does *not* apply, action, completion criterion, expiry boundary, and the real failure it came from |
| `report/` | delivery documentation: design, optimisation record, command reference, reproduction guide (index in [report/README.md](report/README.md)) |
| `report/log/` | append-only working log (issue ledger, overnight log); kept as process evidence, not quoted as conclusions |

The tree is arranged in the shape the contest asks for (`src/ sim/ build/ board/
data/ skill/ report/`); in the repository the delivery documentation sits in `report/`
and the export step renames it to `report/`, rewriting the cross-references along with
it. What got pruned, and under which rule, is listed item by item in `_pruned.txt`
inside the package, and every path quoted by a shipped document is checked at export
time - if one does not resolve, the package is not written.

## License

MIT, see [LICENSE](LICENSE).

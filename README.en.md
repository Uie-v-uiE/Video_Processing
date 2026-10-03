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
| Design-wide setup WNS | **0.739 ns**, failing setup/hold endpoints **0 / 51135** (0 hold failures of 51135 endpoints). The board now runs r118, flashed 2026-10-04 04:49:50 via the three-step JTAG chain, bit `cd04907e1369`, and `board_verify --geom --battery --round=r118` PASS at PASS; the 24-item gate check reads 23 green / 1 red, the single red being the already-declared `C5c` top-level bench item (`build/r118_gates.txt`). Note that this build carries **no RGMII input window**: r116 attached the measured 1.200/2.800 ns window and the four hard release items went red on the five capture endpoints that were being checked for the first time, so the constraint was withdrawn to a candidate file (`src/constraints/r116_rgmii_input_window.xdc`, reproduce with `VP_R116_IO_WINDOW=1`). Against r114 that is not a loosening - r114 never had it and `仓库内的松动台账（在不随提交包的那份文档目录里）` still has zero rows - but the cost travels with the sentence: those five endpoints are unchecked again, and unchecked is not the same as met (prompt H5). The windowed proof stays on disk: over taps 0-31 the hold and setup intervals do not intersect (hold needs tap >= 44.8, setup <= 21.8) because the two clock trees differ by 3.411 ns across corners while the data side only moves 0.467 ns (`build/evidence/r115_window/probe3_console.txt`) | `build/timing_summary.rpt`, `build/r118_gates.txt`, `build/evidence/r118_bit_md5.txt` |
| Per-clock setup slack | 125 MHz receive domain `eth_rxc` **0.739 ns** (9.24 % of its 8 ns period - still the tightest both absolutely and per cycle), 100 MHz `clk_fpga_0` **1.85 ns** (18.5 %), 50 MHz display domain `clkout0_1` **3.63 ns** (18.15 %), `sys_clk` **14.876 ns** (74.38 %). The diff baseline is r114's official roster (`build/evidence/r114_after_roster_probefmt.txt` -> `build/evidence/r117_roster_diff_vs_r114.txt`), because only the same constraint set and the same generator make the same ruler. One cut shipped: `IDELAY_VALUE` 26 -> 31, the eye centre measured in r116 by scanning taps 0-31 on a routed DCP. C9 (force-replicating the 239-pin broadcast net u_pl/u_row/hi_reg_0[0]) was measured and **declined**: official build r117 did lift `clk_fpga_0` to 2.104 ns - the mechanism itself held, 239 -> 1 pins and 10 replica cells - but `clkout0_1`, `sys_clk` setup and `eth_rxc` setup+hold all moved the other way in the same roster, which fails the strict pre-registered criterion, so the cut was rolled back (H7). The hook stays in the tree (`build/tcl/r117_post_place_hook.tcl`, reproduce with `IMPL_POST_PLACE_HOOK`, bit `beda9298331d`). Measured outcome: all 8 roster pairs reproduce r114 digit for digit (`clk_fpga_0` 18.5 %, `clkout0_1` 18.15 %, `sys_clk` 74.38 %, `eth_rxc` 9.24 %, four hold cells identical; `build/evidence/r118_strict_b1.txt`), so the tap move is provably neutral inside the fabric - the gain it buys is +0.315 ns of eye centre outside the device. `clk_fpga_0` stays at 18.5 %: that cell is the one known to be short of its limit, the matching cut (replication) was measured and declined, so what stands here is an unresolved but proven reading - root cause FANOUT (6.871 ns of a 7.355 ns path is routing, 5.690 ns of it on this single 239-pin net, loads across 99 tiles; `build/evidence/r117_d0/`). Absolute WNS deltas across builds are recorded as neither gain nor loss (rule 35) | `build/timing_summary.rpt`, `build/evidence/r118_after_roster_probefmt.txt`, `build/evidence/r114_after_roster_probefmt.txt` |
| Hold time | the worst cell in the whole design is in `eth_rxc`, **0.052 ns** (3 logic levels, routing 56.48 % of that data path; `build/hold_paths.rpt` regenerated after this route). Per-clock WHS: `clk_fpga_0` **0.053 ns**, `clkout0_1` **0.059 ns**, `sys_clk` **0.222 ns**, `eth_rxc` **0.052 ns**. Two caveats travel with these numbers: this build has no RGMII input window, so the `eth_rxc` figure is the intra-clock family and not the capture I/O (the windowed r116 reported -0.870 there, `build/evidence/r116/r116_io_HOLD.rpt`); and only `eth_rxc` carries the 0.800 ns hold uncertainty added in r79, so the four WHS values are comparable within a domain and not across domains until the band is completed (`不确定度 A/B 那件（在不随提交包的那份文档目录里）` measured WHS -0.747 with 25,742 failing endpoints under a uniform band - deliberately not adopted). C9 only changes replication and load ownership: all eight hold pairs are unchanged in the roster diff | `build/timing_summary.rpt`, `build/hold_paths.rpt`, `build/evidence/r117_roster_diff_vs_r114.txt` |
| BRAM / LUT / FF / DSP | **95.5 tiles (68.21 %) / 14154 (26.61 %) / 8188 (7.70 %) / 19 (8.64 %)** (the price of the r112 cut: the power-on arming gate on the two key-debounce instances costs +66 LUT / +46 FF, the ICMP checksum accumulator 32->20 gives back -31 LUT / -12 FF, so the design net is +35 LUT / +34 FF - closed to the unit by differencing two hierarchical reports (`build/evidence/r112_util_attrib.txt`)) | `build/utilization.rpt` |
| Power | **2.213 W** dynamic (2.391 W total on-chip), estimated junction temperature **52.6 degC** (tool confidence Low; **an estimate**, no measured current and no SAF file; the on-die XADC reading is a separate path - serial `temp` / the OSD cell) | `build/power.rpt` |
| SD local playback | **29.8 - 30.0 fps** (100-frame sliding window, read back from the board) | [data/metrics.csv](data/metrics.csv) |
| On-board verification | 105-command serial battery PASS, geometry "last hop" 10/10 PASS (`build/evidence/r113_board_verify_console.txt`, `RESULT board_verify PASS`, 0 red steps; `drop_words=0` read back this round with no stream running) | [board/ACCEPTANCE.md](board/ACCEPTANCE.md) |

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
data/ skill/ report/`). The delivery documentation already lives in `report/` in the
repository; what the export step renames is the **file names** (pure lower-case English,
as the rules ask: `BUILD.md` → `build.md`, `KNOWN_ISSUES.md` → `known_issues.md`), and the
cross-references inside the documents are rewritten along with them. What got pruned, and
under which rule, is listed item by item in `_pruned.txt`
inside the package, and every path quoted by a shipped document is checked at export
time - if one does not resolve, the package is not written.
**Which checkers actually run inside the package**: `doc_enc_check`, `line_cite_check` (D5),
`doc_currency_check` (D1-D4b) and `metric_recheck` (D6) only read text and reports, and measured
2026-10-02 09:2x all four exit 0 inside the package with 0 hard errors. D1b announces there that it
cannot judge (no bitstream ships), which is a declared "not judged", not a pass. Anything needing the
serial port or the board (`ps_hb_check`, `board_verify`) or a re-run of the RTL benches only works in
the repository.

## License

MIT, see [LICENSE](LICENSE).

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
| Design-wide setup WNS | **0.725 ns** (the board now runs r107, flashed at 17:52 on 2026-10-02 by the three-step JTAG chain, `bit 1f90c795e7e3`; the 22-item gate check reads 21 green / 1 red and that single red is the declared `C5c`), failing setup/hold endpoints **0 / 51005** | `build/timing_summary.rpt`, `build/r107_gates.txt`, `build/r107_board_verify_console.txt` |
| Per-clock setup slack | 125 MHz receive domain `eth_rxc` **0.725 ns** (9.1 % of its 8 ns period, and the design's worst absolute path); 100 MHz `clk_fpga_0` **1.229 ns** (12.3 %); 50 MHz display domain `clkout0_1` **1.224 ns** (6.1 %); `sys_clk` **14.906 ns** (20 ns period, the widest) | `build/timing_summary.rpt`, Intra Clock Table. ⚠ Two different readings have to be quoted, never just one: **absolute WNS is `eth_rxc`, the tightest relative margin is `clkout0_1` at 6.1 %** - that one is the 23-level OSD read cone described in `report/KNOWN_ISSUES.md`, a logic-depth problem, not the fan-out/routing problem on the receive side. ⚠ This round the worst path changed owner: in r106 `eth_rxc` was worst because of the receive-reassembly family (`u_reasm/off_reg -> rows_hit_reg`, 6 of the 8 worst paths); after r107 banks that bitmap the family itself sits at 2.006 ns / 4 levels (both-ends sandwich in `build/r107_reasm_probe.txt`) and the design's worst is now the `u_icmp/u_icmp_tx` IP-header checksum cone - so 0.723 -> 0.725 is written as neither gain nor loss (rule 35); the only claimable fact is "the bottleneck moved". D6 re-derives the percentages itself (numerator = per-clock slack, denominator = that clock's period, both read out of the report), so the four ns figures and the three percentages on this row are computed by the checker, not by me; the r104 sync-miss history of this row stays in the timing section of `report/KNOWN_ISSUES.md` |
| Hold time | the worst cell in the whole design is in `eth_rxc` (125 MHz receive domain; landing point u_eth/u_cdc/wgray_reg[6]/C → u_eth/u_lm/full_d_reg/D) at **0.050 ns**, and that cell has **3 logic levels (CARRY4=2 + LUT6=1)** with routing taking **55.2 %** of its data-path delay (`build/hold_paths.rpt`, regenerated after this round's routing at 15:46); the rest of the per-clock hold numbers: 100 MHz `clk_fpga_0` **0.057 ns**, 50 MHz display domain `clkout0_1` **0.059 ns**, `sys_clk` **0.120 ns** - the thinnest class of margin, quoted **after** the 0.8 ns hold uncertainty this repo imposes. ⚠ **The owning cell moved again**: in r106 it was `arp_rx_flag_reg → arp_pend_reg` in the receive domain (1 level LUT4 / route 80.9 %), in r107 it is still the receive domain but the **CDC grey-code → link-monitor** cell, while the design-wide figure moved by only 0.001 ns. Comparing the global number alone cannot see that, which is why this row carries an ownership criterion (rule 46). The 6 pre-fix reds from the earlier round stay recorded in `build/evidence/r104_holdrow_stale_red.txt` | `build/timing_summary.rpt` (Intra Clock Table, WHS column), `build/hold_paths.rpt` |
| BRAM / LUT / FF / DSP | **95 tiles (67.86 %) / 14323 (26.92 %) / 8156 (7.67 %) / 19 (8.64 %)** (after r107 banks the receive bitmap the LUT count is byte-identical to r106; the +7 registers are the bank index/select logic) | `build/utilization.rpt` |
| Power | **2.213 W** dynamic (2.390 W total on-chip), estimated junction temperature **52.6 degC** (tool confidence Low; **an estimate**, no measured current and no SAF file; the on-die XADC reading is a separate path - serial `temp` / the OSD cell) | `build/power.rpt` |
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

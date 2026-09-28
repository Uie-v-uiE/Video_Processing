[中文](README.md)

# Real-time video processing on Zynq with per-pixel original/processed comparison

A Zynq-7020 (`xc7z020clg484-2`) takes a 512x300 video stream from Gigabit Ethernet,
an SD card or an on-chip test card, scales, rotates and filters it in the PL, and
outputs 1024x600 HDMI. Left of an adjustable vertical seam the panel shows the
**unprocessed** frame, right of it the **processed** one, in the same coordinate
system. The seam can be fixed, auto-swept, or locked into the image domain so that
it rotates and zooms together with the picture.

That per-pixel, same-frame comparison is the core of the design: it is both a
display mode and a measuring instrument. Edge stripes, a one-row offset or a single
out-of-range cell become visible without any extra probe, and are quantifiable from
the same geometry that produced them.

## Features

- **Three sources**: UDP video over RGMII at 1 Gb/s, local SD playback (own FAT32
  cluster-chain parser), and a dynamic on-chip test card. Arbitration and fallback
  live in the PL; the PS only issues commands.
- **Geometry path**: eight zoom steps (fixed-point reciprocal, no run-time division),
  several rotation angles (sine/cosine ROM with quadrant folding), nearest-neighbour
  and bilinear interpolation switchable at run time.
- **Effect chain**: grayscale, invert, 3x3 box blur, sharpen, Sobel, threshold
  binarisation (with polarity flip), 3x3 erode/dilate - nine control bits, every
  stage bypassable, the chain a constant 15 pipeline stages deep.
- **Comparison display**: seam anywhere from 0 to 100 %, sides swappable, 2-pixel
  marker optional; the original tap is delayed by a line-ring so both taps land on
  the same clock cycle and the same column.
- **On-screen state**: four OSD lines - source, angle, zoom step, effect code,
  seam position, frame rate, end-to-end latency, die temperature.
- **Online self-diagnosis**: received/dropped/corrupt/CRC counters, ping-pong bank
  state and in-link latency, counted in hardware, shown on the OSD and readable over
  the serial port; cable-pull and card-pull behaviour can be reconciled afterwards.

## Reproducing it

```bash
# 1) project, synthesis, implementation, bitstream (Vivado 2025.2.1, command line)
vivado -mode batch -source build/tcl/build_system_axigpio.tcl
# 2) twenty gate items: two full-panel benches plus timing/resource/port/doc checks
bash build/gates.sh
# 3) flash over JTAG (this project never writes QSPI) + serial battery + read-back
bash build/board_verify.sh --battery --geom
```

Command list, register map, every criterion and where to look when one turns red:
[docs/COMMANDS.md](docs/COMMANDS.md), [docs/BUILD.md](docs/BUILD.md),
[board/README.md](board/README.md).

## Numbers

The newest gate-green frozen set is r75: twenty of twenty items pass, post-route
WNS +0.287 ns. The full table of utilisation, power, frame rate and latency - each
row naming the report it came from - is in
[docs/PERF_REPORT.md](docs/PERF_REPORT.md); artefacts are archived under
`build/` and `build/evidence/`.

## Layout

| Directory | Contents |
|---|---|
| `src/rtl/` | RTL, split into `top / video / process / eth / hdmi / clocks / axi / util` |
| `src/ps/` | bare-metal firmware: command parser, register setup, SD playback, counter read-back |
| `src/host/` | PC-side tools and self-check scripts (streaming, read-back, doc/command consistency) |
| `sim/` | testbenches and two runners; `tb_v98_top_seam` instantiates the whole video top |
| `build/` | build and gate scripts, `tcl/`, implementation reports, `rNN_gates.txt`, `evidence/` |
| `board/` | on-board procedures, acceptance table, serial captures |
| `data/` | `golden/` reference images, `measured/` measured data |
| `skill/` | reusable skills distilled from the LLM collaboration, each in four parts: when it applies, how to use it, the verified effect (which failure it came from), and when it stops working |
| `docs/` | design report, optimisation log, command reference, reproduction guide |
| `docs/log/` | `ISSUES.md` and `OVERNIGHT_LOG.md` (append-only work log) |

## Where to start reading

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (block diagram and module
responsibilities) -> [docs/PS_VS_PL.md](docs/PS_VS_PL.md) (the hardware/software
split) -> [docs/BACKGROUND_AND_NOVELTY.md](docs/BACKGROUND_AND_NOVELTY.md)
(why it is built this way) -> [board/HANDS_ON.md](board/HANDS_ON.md) (what to look at
on the panel).

## License

MIT, see [LICENSE](LICENSE).

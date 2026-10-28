# PL sources

The top level is `top/system_top.v`; the display path lives in `top/pl_video_top.v`.

## Module map

| Path | Responsibility | Key constraint |
|---|---|---|
| `top/system_top.v` | joins PS7, clocks, Ethernet and display | PS FCLK0 100 MHz; the PHY-recovered clock only reaches IDDR and the FIFO write side |
| `top/pl_video_top.v` | frame buffer, geometry, effects, seam, OSD, TMDS | 50 MHz pixel domain; effect chain fixed at 15 beats |
| `eth/eth_udp_video_top.v` | RGMII -> MAC -> UDP -> reassembly -> AXI write to DDR | ingest and protocol logic at 125 MHz |
| `eth/frame_reasm.v` | offset-based reassembly, row coverage, byte gate, A9 idle timer | commit needs all three conditions |
| `eth/dc_fifo.v` | asynchronous FIFO from ingest to AXI domain | gray-code pointers; not usable as a synchronous FIFO |
| `eth/axi_frame_saver64.v` | 16-to-64-bit packing, AXI burst writes to DDR | the tail word must survive a full FIFO plus flush |
| `video/frame_buffer_w64.v` | 64-bit-wide full-frame buffer, ping-pong | where most of the BRAM goes |
| `process/zoom/zoom_mapper.v` | fixed-point inverse mapping from display to source coordinates | eight zoom steps plus arbitrary angle |
| `process/bilin/fb_bilin.v` | bilinear read port | four neighbours, two-line result buffer |
| `process/proc_pipeline.v` | six-stage effect chain | 15 pixel clocks total |
| `video/split_display.v` | per-pixel choice between source and processed | the seam is only where that select changes |
| `video/osd_overlay.v` | five OSD rows | does not alter seam geometry |
| `eth/link_monitor.v` | frame gaps, aborts, bad packets, flags | `stall`, `gap_last/min/max/sum` |
| `eth/snap_cross.v` | cross-domain snapshot of a quasi-static bus | toggle edge plus whole-beat hold |
| `clocks/clk_gen.v` | pixel and serialiser clocks | pixel and serialiser stay at 5:1 |
| `hdmi/` | TMDS encoding and serialisation | 50 MHz pixel, 250 MHz serialiser |

## Luggage travels with the pixel

A pixel travels the pipeline together with its coordinate tag, out-of-range bit, `de` and frame/source identity. Many single-row colour streaks, seam misalignments and edge fills come from "the pixel arrived but its luggage did not". C22 fixed a row tag lagging by one line; C31 fixed `sx` arriving two lines later than the source tap. Both have checks in `docs/verification.md`.

## Clocks and reset

- The recovered clock `eth_rxc` is used only for IDDR sampling and the asynchronous-FIFO write side.
- Protocol logic runs on `clkout3` at 125 MHz, the display on `clkout0_1` at 50 MHz, the control plane on `clk_fpga_0` at 100 MHz.
- Three crossing classes: asynchronous FIFO, quasi-static snapshot, three-stage synchroniser.
- Resets assert asynchronously and release synchronously in each domain; the worst setup path is reset recovery, documented in `docs/optimization.md`.

## Verification

Before changing RTL, find the matching bench under `sim/`; the full-video bench `tb_video_pipeline_top.v` covers geometry, effects, the seam, the OSD and edges. Final verdicts are in `sim/results/`.

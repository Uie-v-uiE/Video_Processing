# Zynq7020 Ethernet Video Processing Pipeline (Rev 5: resource & ingress re-optimisation)

[中文](README.md) | [English](README.en.md)

A UDP video receiver with a real-time image-processing pipeline on Zynq-7000 (XC7Z020).

A host PC pushes **512×300 RGB565** frames over **UDP**. The **PL** performs RGMII reception,
ARP/ICMP/UDP, offset-based frame reassembly, image effects, rotation, continuous zoom and
dual-window HDMI output. The **PS** is control-plane only (UART + AXI GPIO).

The displayed picture has **three sources**, chosen automatically by an arbiter in the PL:
**network stream > SD-card playback > a moving test card**. The board mounts and plays the SD card
by itself at power-on (`AUTOPLAY0/1` to disable), yields to a live stream and takes the screen back
within a few hundred ms after the stream stops — no cable pulling, no re-programming. `KEY1` short
press still steps rotation by ±1°; a **1.2 s long press** cycles auto / lock-ETH / lock-PS / lock-card.
The hand-over timing is **measured, not observed-by-eye**: four independent runs on the same bit put
the stop-to-hand-back time at **210 / 285 / 406 / 434 ms**, stream-start-to-take-over at 150-253 ms,
with zero unintended flips. A *range* is quoted deliberately: the resolution of that number is the
sampling period (100 or 300 ms depending on how the probe halts the CPU), and the design budget is
200 ms (declare the stream dead) + 20 ms (quiet before yielding) = ~220 ms, which the measurements are
consistent with. Reproduce with `node src/host/arb_handover_test.mjs`; evidence in
`build/frozen_r31_srcmode/arb_handover_green_r31.json`. Everything the arbiter itself sees (current
owner, whether ETH is live, whether its timebase can be trusted, the mode it is honouring, both
engines' busy flags) is mapped onto **AXI GPIO lane 30**, so the verdict needs no one looking at a
screen. What still needs eyes is narrower: that the picture is really alive after the hand-back.

| Item | Value |
|------|-------|
| Board | RK-ZYNQ7020-F (`xc7z020clg484-2`) |
| Tools | Vivado / Vitis 2025.2.1 |
| Source format | 512×300 RGB565 |
| Display | HDMI 1024×600 @ 50 MHz (left = original, right = processed + zoomed) |
| Network | board PL port `192.168.1.10:5001`, PC `192.168.1.100` |
| Control | AXI GPIO `@0x41200000`, UART 115200 |
| Implementation | current default bit (build#23): **WNS +0.740 ns, 0 failing endpoints**, BRAM 64.64 %, Slice LUT 13.92 %, 5904 registers, 2.178 W dynamic. Full table and sources: `report/PERF_REPORT.md`; re-check with `bash build/gates.sh build/frozen_r23_srcseen` |
| Licence | MIT |

## Overview

The design implements a full Ethernet-to-display pipeline on a single Zynq-7020. Frames arrive as
UDP packets carrying `[u32 little-endian byte offset][RGB565 payload]` and are reassembled by a
hand-written PL protocol stack (RGMII RX with IDELAYE2, ARP, ICMP, UDP, CRC32). Reassembled pixels
cross the 125 MHz → 100 MHz clock domain through a hand-written Gray-code FIFO, are packed into
64-bit AXI beats and written into one of two **DDR ping-pong banks**. A commit lock starts an atomic
whole-frame copy into the display BRAM inside the VGA blanking window, so two frames can never be
interleaved on screen. The right window runs the effect chain (gray / binary / box blur / Sobel /
invert) and continuous zoom; rotation is a Q8 sin/cos inverse mapping over 0–359°. An on-screen
overlay (`osd_overlay.v`) reports FPS, angle and enabled effects.

Four parts of the design are worth reading:

1. **Hand-written PL Ethernet stack and FIFOs** — no vendor IP on the ingress path.
2. **The ping-pong + blanking-window commit state machine** — logic and timing working together.
3. **Throughput modelling of the ingress write channel** — why in-flight depth, not buffer depth,
   sets the ceiling (this was proved by measurement after a wrong guess).
4. **Report-driven resource optimisation** — identical functionality, registers from 51.30% to 4.08%.

## Branches / version history

| Branch | Rev | Content |
|--------|-----|---------|
| **`main` (current)** | 5 | Three synthesis-behaviour fixes (ingress packer FIFO and display skid buffer moved to distributed RAM; frame buffer address space split on power-of-two boundaries) plus an ingress-page-switch guard that waits for the CDC to drain. BRAM 98.93%→64.64%, registers 51.30%→4.08%, slices 99.92%→18.03% |
| `dev/night-2026-09-22` (**local only, pending review**) | V7.7→V7.9 | Night-time work on top of Rev 5: link-health self-diagnosis, PS publish handshake, rotation confined to the right pane, three CDC items (`eth_link` synchroniser, `ASYNC_REG` annotations, `copy_abort` toggle synchroniser), and the second board (KU5P) including a one-packet-per-second UDP telemetry report plus a self-written transmit arbiter. Bilinear interpolation is *not* merged — it lives on tag `v7.8-bilinear-wip`. Per-round evidence: `report/OVERNIGHT_LOG.md`; version mapping: `report/VERSION_LINEAGE.md` §6. || `v3-seamless-zoom` | 3 | Continuous right-window zoom. **Ghosting was still unfixed here** (only 42–52% of words belonged to the newest frame) |
| `v4-zero-loss` | 4 | Zero-loss ingress: pipelined write channel (V6.3) + per-16-bit-lane `WSTRB` (V6.4) |
| `v3-ghosting-attempts` | 3 (work in progress) | Three unconverged anti-ghosting attempts: BRAM double buffer → 3-slot DDR frame manager → 2-bank DDR ping-pong (includes the consultation brief and the testbenches of the time) |
| `v2-pl-ethernet` | 2 | Ethernet moved into the PL; rotation × window-filter incompatibility fixed; self-built FIFOs. Ghosting recorded as a known issue |
| `v1-ps-ethernet` | 1 | **PS Ethernet** (lwIP UDP → PS → DDR, PL reads out over HP0); PL effects and rotation |

```bash
git checkout main                  # Rev 5 (default)
git checkout v4-zero-loss           # Rev 4
git checkout v3-seamless-zoom       # Rev 3
git checkout v3-ghosting-attempts   # Rev 3 debugging attempts
git checkout v2-pl-ethernet         # Rev 2
git checkout v1-ps-ethernet         # Rev 1
```

Problem → diagnosis → fix → evidence for every stage:
**[`report/VERSION_LINEAGE.md`](report/VERSION_LINEAGE.md)**.

## What changed in Rev 5

Rev 4 was functionally correct but the device was saturated by *synthesis behaviour* rather than by
the design: 51.30% registers, 99.92% slices, 98.93% BRAM — all three at the ceiling, no room for
any new feature.

1. The 512×100-bit storage of `axi_frame_saver64` was being implemented as **flip-flops** (~51k FDRE,
   94% of the whole design) while 98% of the device's distributed RAM sat idle. Adding a `ram_style`
   attribute alone does not help (`Synth 8-7186` refuses the inference); the real blocker is an array
   write living in the same always block as asynchronous-reset control logic. Splitting them gives
   FF 32904→85 and LUTRAM 864 cells.
2. `frame_buffer_w64` alone consumed **128 of 140 RAMB36 tiles** for data that needs 67. Six
   out-of-context synthesis variants proved the waste is neither the declared depth nor the width but
   the **address space being rounded up to 2^16 words**. Splitting the space into two power-of-two
   blocks (32768 + 8192) measures 80 tiles.
3. The display-copy skid buffer in `axi_frame_writer_gated` had the same defect (`Synth 8-4767`);
   the same recipe applies.

Plus one real functional defect fixed: the **last 4 bytes (2 pixels) of a frame could intermittently
disappear**. The page-switch criterion `saver_idle` is blind to the 8192-entry CDC and the two read
pipeline stages behind it, so if the packer happened to drain in the middle of the last word, the
remaining lanes of that frame were written into the *next* frame's bank. Verified with a two-sided
criterion in simulation (the old logic must reproduce the loss, the new logic must not — either side
failing marks the testbench FAIL).

| Metric | Rev 4 | Rev 5 |
|--------|-------|-------|
| Slice registers | 51.30% | **4.08%** |
| Slice LUTs | 37.27% | **11.87%** |
| Slices | 99.92% | **18.03%** |
| Block RAM tiles | 98.93% | **64.64%** |
| Total power | 2.525 W | **2.350 W** |
| WNS | +0.708 ns | **+0.499 ns** (all constraints met) |
| Regression | 28/28 | **30/30** |
| On board | 15/30/60 fps, 100% hit | **22 runs from 15 to 36 MB/s and at 60/120 fps unpaced: one frame per bank, 100.0% per-lane hit rate** |

Full record, criteria and rejected options: [`report/CHANGELOG_V7.md`](report/CHANGELOG_V7.md),
[`report/OVERNIGHT_LOG.md`](report/OVERNIGHT_LOG.md).

## Features

- PL hardware network stack: RGMII → ARP/ICMP/UDP → frame buffer
- UDP offset protocol: out-of-order packets reassemble; bad frames are dropped
- Effect chain: gray / binary / box blur / Sobel / invert (UART controlled, valid at any rotation angle)
- Arbitrary-angle rotation (Q8 sin/cos inverse mapping, 0–359°) — **right window only**; the left window always shows the unrotated picture
- Local playback from the PS SD socket: raw 512×300 RGB565 frames read by a bare-metal read-only FAT32 (no FatFs, no vendor IP)
- Continuous right-window zoom (Q8 `inv_scale`, 256 = 1.0× ↔ 512 = 0.5×, composable with rotation)
- Hand-written OSD overlay: FPS / angle / effect bits, 3× bitmap glyphs
- Self-built FIFOs: `sync_fifo` (single clock) + `dc_fifo` (Gray-code CDC), no vendor IP
- Self-built ping-pong frame store: two DDR banks + commit lock + atomic blanking-window copy
- Source select: colour bars or Ethernet/DDR video
- Host tools: UDP sender, serial console, and a JTAG read-back measurement suite that decides
  link integrity without looking at the screen
- **Second board (RK-XCKU5P-F, UltraScale+)**: the same self-written Ethernet stack, only the RGMII
  physical layer swapped, meets timing on its own — and it now **reports its own receive statistics
  back to the PC as one UDP packet per second** (`node src/host/ku5p_stats.mjs`). The GMII send
  arbiter is also self-written (it fixes a mid-frame source-switch defect in the vendor multiplexer).
  Bench evidence and numbers: `ku5p/README.md`; board checks are scheduled for daytime.

## Directory layout

```
src/rtl/          Verilog: top / eth / axi / video / process (rotate, zoom) / hdmi / clocks
src/ps/          Bare-metal UART + GPIO control (control plane only)
src/host/        Host sender, serial tooling and JTAG read-back analysis (Node.js first)
src/constraints/ Pin and timing constraints (rk_zynq7020.xdc)
sim/             45 testbenches, repo-relative runner (run_sim.tcl) + single-TB runner (run_one.sh),
                 probes/ (synthesis-behaviour experiments)
build/           tcl/ build+program+report scripts, system.bit, system.xsa, *.rpt
board/           Bring-up notes and screen-free verification method
data/            golden/ reference images, measured/ JTAG dumps and criteria text
skill/           Reusable skill notes (problem pattern → criterion → invalidation condition)
report/          Architecture, modules, optimisation, performance, root cause, lineage, changelogs
```

## Quick start

```bat
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
set XSDBAT=D:\Software\Vivado\2025.2.1\Vitis\bin\xsdb.bat

:: 1. build bitstream + XSA + all reports from scratch
%VIVADO% -mode batch -nojournal -log build\build.log -source build\tcl\build_system_axigpio.tcl

:: 2. bring up PS, program PL, select the video source
%XSDBAT% build\tcl\ps_jtag_boot.tcl
%VIVADO% -mode batch -nojournal -source build\tcl\program_pl.tcl
%XSDBAT% build\tcl\set_src.tcl        :: only if you skip step 2b: the app writes this register itself

:: 2b. PS application (no Vitis project needed) - serial console + SD playback
node build\ps_app.mjs
%XSDBAT% build\tcl\ps_app_reload.tcl   :: rst -processor + download + con; leaves bitstream and GPIO alone

:: 3. simulation (45 testbenches)
%VIVADO% -mode batch -nojournal -log sim\xsim.log -source sim\run_sim.tcl

:: 4. stream and measure
node src\host\video_sender.mjs --fps 30 --count 60 --test frameid
node src\host\ddr_verify.mjs --frameid
node src\host\ddr_stale.mjs
```

Set the PC NIC to `192.168.1.100/24` and plug the cable into the **board's PL Ethernet port**.
The PS application (`src/ps/main.c`) is built by `node build/ps_app.mjs` straight against a
generated BSP - the ELF links the standard startup (`boot.S`: CPACR/FPEXC, VBAR, per-mode stacks,
MMU), so it runs over plain JTAG with **no FSBL and no Vitis project**. Measured: SD-card frame
library mounts and plays back at 30.0 fps on screen (`report/OVERNIGHT_LOG.md` sec. 19).
Since V7.9#24 the PS frame source reaches the screen **with the cable still plugged in**
(the PL now arbitrates the two sources, ISSUES #49); the remaining hop - "stream stops,
picture hands itself back to SD within ~0.2 s" - failed the board check on #24 and is
re-tested on #25. Until that is confirmed by eye, the conservative order still applies:
unplug the Ethernet *before* programming the bitstream for this act. Details in
`src/host/HOST_GUIDE.md` and `board/README.md`.

## UART commands (115200 8N1, terminate with CR+LF)

| Command | Effect |
|---------|--------|
| `00000` | all effects off |
| `10000` | gray |
| `01000` | binary |
| `00111` | blur + Sobel + invert |
| `SRC0` / `SRC1` | colour bars / video source |
| `SD` / `PLAY` / `STOP` / `FRAME<n>` | mount & print the SD frame library / loop-play / stop / show one frame |
| `TH80` | binary threshold |
| `ZOOM0` / `ZOOM1` | right-window zoom off / on (on by default) |
| `BILIN0` / `BILIN1` | right-window bilinear interpolation off / on (AXI GPIO bit 19). Off falls back to nearest neighbour on the **same datapath**. **Not in the mainline right now** — V7.8 closed all but 0.327 ns on the 250 MHz time-multiplexed read port; the full implementation lives on tag `v7.8-bilinear-wip`. With the build#13 bit the pin is unconnected and the command only echoes state |
| `FILL` / `STAT` | diagnostics / status |

Effect bit order: **gray / binary / blur / sobel / invert** (bit 0 leftmost). A complete Ethernet
frame automatically switches the source to video.

## UDP protocol

```
[u32 little-endian byte offset][RGB565 payload]
one frame: 512*300*2 = 307200 bytes
recommended payload per packet: 1392 bytes (a multiple of 8)
```

Packets may arrive out of order; incomplete frames are discarded and the next frame recovers.
Since V6.4 the packer drives `WSTRB` per 16-bit lane, so the split length no longer affects
correctness — a multiple of 8 still saves ~0.3% duplicate beats and keeps the useful property that
one packet never straddles two 64-bit words. Historically a 1396-byte payload left evenly scattered
black dots (~111 4-byte holes per frame); see `report/ISSUES.md` #29.

## Design notes

- **DDR ping-pong + atomic blanking-window swap.** Ingress writes to `0x1000_0000 / 0x1008_0000`;
  `frame_commit_lock` starts the whole-frame copy only on a blanking-window edge. From Rev 5 the page
  switch additionally requires the frame to have fully drained the CDC (`ddr_bank_commit.v`),
  otherwise the frame tail lands in the next frame's bank. Copy budget: 38400 beats over 67200 AXI
  cycles = 0.571 beats/cycle ≈ 457 MB/s, measured inside the window.
- **Ingress throughput = in-flight depth × 64 bits ÷ round-trip latency.** Waiting for B on every
  word pins the in-flight depth at 1 ⇒ ~20 MB/s ceiling — that was the real cause of the ghosting
  before Rev 4. Deepening buffers does **not** substitute for in-flight depth; that was measured and
  the idea discarded.
- **Single-port display frame buffer**: 80 RAMB36 tiles after the power-of-two split (theoretical
  floor 67). A second full frame still does not fit, but the ~49 freed tiles are enough for line
  buffers or interpolation stages.
- **Zoom**: continuous inverse mapping via Q8 `inv_scale`; effects sit on the post-zoom right-window
  raster (target-domain windowing), which is why blur/Sobel remain valid at any rotation angle.
- **Self-built FIFOs**: write ports deliberately live in their own non-reset always block so that
  BRAM / distributed RAM inference succeeds (see the Rev 5 section).
- **Synthesis-behaviour probes** in `sim/probes/` answer "what does this coding style become",
  a question no testbench can answer.

## Documentation

| Path | Content |
|------|---------|
| [report/VERSION_LINEAGE.md](report/VERSION_LINEAGE.md) | Version lineage and problem-handling record: branches, commits, local snapshots, evidence per stage |
| [report/CHANGELOG_V7.md](report/CHANGELOG_V7.md) | Rev 5 full change record and optimisation comparison |
| [report/CHANGELOG_V6.md](report/CHANGELOG_V6.md) | Rev 4 change record (V6.0→V6.4, including the disproved directions) |
| [report/V6_ROOT_CAUSE.md](report/V6_ROOT_CAUSE.md) | Rev 4 root-cause analysis and measurement methodology |
| [report/V6_BOARD_MEASUREMENT.md](report/V6_BOARD_MEASUREMENT.md) | Board measurement sheets per data rate |
| [report/OVERNIGHT_LOG.md](report/OVERNIGHT_LOG.md) | Rev 5 engineering log: per-round motivation, criteria, report gates, board re-verification |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) / [report/MODULES.md](report/MODULES.md) | Datapath, clock domains, bandwidth, module reference |
| [report/ROTATION_AND_EFFECTS.md](report/ROTATION_AND_EFFECTS.md) | Target-domain window filtering with rotation and zoom |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) / [report/PERF_REPORT.md](report/PERF_REPORT.md) | Timing/layout/power optimisation and performance reports |
| [report/ISSUES.md](report/ISSUES.md) | Chronological issue list with a symptom lookup table |
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) / [sim/probes/README.md](sim/probes/README.md) | Host tooling; synthesis-behaviour experiments |

## Licence

MIT — see [LICENSE](LICENSE).

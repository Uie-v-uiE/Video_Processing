# Key issues

Numbering follows the earlier ledger. Only entries that changed the design or the checks are kept; the full process record is not published.

## 1. #27-35 - words dropped in the ingest chain: the real cause of ghosting and black bands

**Symptom** the picture tears even when still; every other 16-bit halfword shows a black band; deeper buffering changes nothing.
**Root cause** UDP payloads were not multiples of 8 bytes, so the packer misaligned every 16-bit halfword deterministically; the packer waited for an AXI B response per word, pinning throughput to the round trip; the FIFO was inferred as flip-flops and blew up the resource budget.
**Check** `tb_udp_reasm` compares words by intra-frame offset; `tb_saver` checks 16-to-64-bit packing, burst length and the tail word.
**Fix** the sender pads payloads to multiples of 8; the packer handshakes write address and data in parallel and only counts B responses; the FIFO uses distributed RAM. **Status** fixed.
**Evidence** `src/rtl/eth/axi_frame_saver64.v`, `sim/tb_udp_reasm.v`, `sim/results/regression.txt`.

## 2. #38 - `p_good` tied high, so the bad-packet counter was dead

**Symptom** the bad-packet count stayed at 0 and the link looked perfect.
**Root cause** `frame_reasm.p_good` was tied to 1 in both board tops, so `stat_bad` had no real input.
**Check** inject bad packets or FCS errors and the count must rise; the dropped-word and aborted-frame flags must be able to set.
**Fix** the MAC bad-packet flag feeds the reassembler, and bad packets are counted separately from aborts. **Status** fixed.
**Evidence** `src/rtl/eth/frame_reasm.v`, `hw/measured/link_selftest.txt`.

## 3. #42 / #44 - PS bring-up: floating point trapped as undefined, hand-linked image lost the boot files

**Symptom** the PS application did not run after a JTAG download and the PC landed in an exception vector; a hand-linked ELF broke four things at once.
**Root cause** CPACR was not enabled, so VFP instructions trapped as Undefined Instruction; the hand-linked standalone image omitted `boot.S`, `asm_vectors.S` and `translation_table.S`, losing entry point, vector table and MMU.
**Check** the ELF must contain `_boot`, `_start`, `_vector_table` and `MMUTable`; exception vectors sit at 0; serial and GPIO readback must both work.
**Fix** the build script forces the three BSP start-up files into the link and self-checks symbols and entry points. **Status** fixed.
**Evidence** `scripts/ps/build_ps_app.py`, `src/ps/lscript_ocm.ld`, `hw/measured/health.txt`.

## 4. #45 - `XSdPs_CfgInitialize` succeeds once per power cycle

**Symptom** the first `sd` mounts, identical later commands fail, and only re-downloading the ELF recovers.
**Root cause** the SD driver initialises once per core power cycle and fails on the second attempt.
**Check** `sd remount` must recover without a power cycle, and a failure must print the next step.
**Response** no automatic mount; after the first failure the firmware suggests `sd remount` or an ELF re-download. This is a workaround, not a root-cause fix. **Status** worked around.
**Evidence** `src/ps/sd_play.c`, `hw/measured/sd_playback.txt`.

## 5. #46 - cumulative average since first play reported as frame rate, off by 20x

**Symptom** the reported fps drifted high after a while and did not match the actual window rate.
**Root cause** the numerator counted every frame since first playback while the denominator used the current window.
**Check** frames gained in the window divided by time gained in the window; the average must sit between min and max.
**Fix** window rate, with the label naming the window; `metrics.mjs` gained a self-consistency check. **Status** fixed.
**Evidence** `src/host/metrics.mjs`, `data/metrics.csv`.

## 6. #48 - reading only the first sector of META.TXT invented a 4-file gap

**Symptom** files existed on the card but the firmware reported a truncated list.
**Root cause** only the first sector of META.TXT was read, cutting the list mid-way.
**Check** the file count from `sd files` must equal the card contents; a list spanning sectors must read completely.
**Fix** read the whole file through the FAT32 cluster chain instead of assuming one sector. **Status** fixed.
**Evidence** `src/ps/sd_play.c`, `hw/measured/sd_playback.txt`.

## 7. #50 - frame 3584 always failed: high cluster word assembled big-endian

**Symptom** the first frame of the eighth file always failed with "file not found".
**Root cause** the high 16 bits of the FAT32 cluster number were assembled big-endian, sending the chain to the wrong cluster.
**Check** playback across a file boundary; `sd file n` followed by `play` resumes from that clip.
**Fix** assemble high and low cluster words little-endian, and stop `play` from zeroing `nxt`. **Status** fixed.
**Evidence** `src/ps/sd_play.c`, `hw/measured/sd_playback.txt`.

## 8. #54 - window stages misaligned data and valid, total latency also wrong

**Symptom** with blur, sharpen, Sobel or morphology enabled, row boundaries shifted and the OSD latency disagreed with the hardware.
**Root cause** window-stage content lagged the row tag by one line, and the top-level latency constant ignored the window stages.
**Check** C22 compares row tags against content line by line; C31 uses a 9-bit row tag frame and checks the tap selected in every pixel.
**Fix** capture input row-tag history `yl1/yl2/yl3` at line start; route the seam `sx` through a two-row ring before `seam_src`. **Status** fixed.
**Evidence** C22/C31 sections of `sim/tb_video_pipeline_top.v`, `sim/results/c31_edge_rim.log`.

## 9. #58 - combinational divider in the 100 MHz domain

**Symptom** WNS -5.014 ns with 96 failing endpoints.
**Root cause** new gating logic implemented a combinational divider in the 100 MHz domain.
**Check** post-implementation WNS at or above zero with no failing endpoints; check which clock domain new logic lands in first.
**Fix** move the division out of the combinational path or replace it with fixed-point shifts. **Status** fixed.
**Evidence** `hw/reports/build_timing_summary.rpt`, `docs/optimization.md`.

## 10. #60 / #61 - two kinds of false green, in the bench and in synthesis

**Symptom** a check went quietly green because both branches skipped on X; synthesis tied a flag driven by two always blocks to a constant, so 56 benches passed while the wire was stuck at 0.
**Root cause** `if (!cond)` is open to X, simulation takes the last assignment while synthesis optimises to a constant.
**Check** a check must be able to turn red; critical flags need a `default` or a single driver; recheck the netlist after synthesis.
**Fix** benches use `!==` or explicit X checks; flags moved to a single always block. **Status** fixed.
**Evidence** the relevant benches in `sim/`, `docs/verification.md`.

## 11. #62 - "0-100% seam" and "fixed two 512-wide windows" were mathematically incompatible

**Symptom** moving the seam broke the geometry of both panes.
**Root cause** two separate geometry paths, with the seam treated as two independent windows.
**Check** one viewport, one address stream, per-pixel selection; moving the seam must not change either side's coordinates.
**Fix** one viewport with a per-pixel select. **Status** fixed.
**Evidence** `src/rtl/video/split_display.v`, `sim/tb_split_ctrl.v`.

## 12. #63 - `zoom 1` and `zoom 1.0` are not the same command

**Symptom** asking for 1.00x with `zoom 1` turned automatic breathing on.
**Root cause** the V7 switch semantics and the V8 ratio semantics collided on the same word.
**Check** the reply must say "switch" or "ratio"; `zoom 1.0` must land on the 1.00 step.
**Fix** the help line and rejection message distinguish them, and `zoom 1.0` goes through ratio parsing. **Status** fixed.
**Evidence** `src/ps/main.c`, `src/host/uart_cmd_check.mjs`.

## 13. #66 - `src 0/1/2` wrote one bit and left the mode override unconnected

**Symptom** after a serial source change the automatic arbiter took the source back.
**Root cause** `src` wrote only `src_sel`; the V8-2 mode override bit was never wired into the control word.
**Check** after switching, lane 30 must report an `owner`/`mode` matching the command, and a long press must release the override.
**Fix** wire the mode override into the control word; `src auto` releases it. **Status** fixed.
**Evidence** `src/ps/main.c`, `src/rtl/top/pl_video_top.v`, `hw/measured/health.txt`.

## 14. #67 - `pipe` accepted 8 bits but interpreted 9

**Symptom** an eight-bit effect string produced stages that disagreed with the display.
**Root cause** the parser accepted 8 bits and zero-padded to 9 internally.
**Check** accept exactly 9 bits; five-bit legacy spellings only return the equivalent string without writing registers; every other length is rejected.
**Fix** the parser accepts 9 bits only and legacy spellings go through the translation path. **Status** fixed.
**Evidence** `src/ps/main.c`, `src/host/uart_cmd_check.mjs`.

## 15. #68 - the colour-stage column tag was 9 columns older than its content

**Symptom** the seam sat in the wrong place under zoom or rotation, with colour bands around it.
**Root cause** `split_display` decided the seam from `x_d[11]` while the two pixel streams only arrived at stage 20, so tag and content were on different beats.
**Check** a 9-bit row-tag frame checked cell by cell; both sides same frame and same coordinates.
**Fix** move the seam decision to the stage where the pixels are, and C31 covers the rotated frame tail. **Status** fixed.
**Evidence** `src/rtl/video/split_display.v`, `sim/results/c31_edge_rim.log`.

## 16. #69 - `board_verify.sh` had no verdict and pipelines ate exit codes

**Symptom** earlier steps failed while the script still exited 0.
**Root cause** no summary verdict line, and `cmd | tee` returns the exit code of `tee`.
**Check** the end must carry one verdict line naming the number of checks and failures, and the exit code must follow it.
**Fix** add the verdict line and three states; use `PIPESTATUS` or explicit checks. **Status** historical script fixed; the final package uses `hw/scripts/board_health.sh` and the verdicts in `hw/measured/`.
**Evidence** `hw/README.md`, `hw/measured/README.md`.

## 17. #98 - first rows of a frame: read-side wrap served one-frame-old content

**Symptom** the top rows showed the tail of the previous frame.
**Root cause** the processing tap advanced one line early and the four window line buffers read content after wrapping.
**Check** C5c requires top rows to carry their own source line; `STREAM_WRAP=1` applies to the continuous stream only.
**Fix** window stages gained `STREAM_WRAP`, and the top-level row tag moved to `cy_chain`, the same ledger as the content. **Status** fixed; the residual cost is four top rows one frame older than the rest of the screen (about 33 ms), which only a human can judge.
**Evidence** `sim/tb_pipe_bypass.v`, `docs/verification.md`, `docs/limits.md`.

## 18. #181 / A9 - tail of one frame and head of the next stitched into a whole frame

**Symptom** after a short silent gap the screen showed a mixed frame.
**Root cause** the reassembler committed on byte count and row coverage alone, so two frames' accounts were joined across the silence.
**Check** the A9 section of `tb_udp_reasm` drops the tail of one frame and the head of the next with more than 4 ms between them, and requires the frames not to mix and the third frame after recovery to be clean.
**Fix** a 4 ms idle timer with a 12-bit prescaler, where `idle_clear` drives one bit into the header-clear cone; both the unprescaled version and the `last_hdr` version were rejected on WNS. **Status** fixed.
**Evidence** `src/rtl/eth/frame_reasm.v`, `sim/tb_udp_reasm.v`, `docs/optimization.md`.

## 19. #507 / #508 - resume cursor and the tail word behind a full FIFO

**Symptom** `play` restarted at frame 0 after `sd file n`, and the tail word was lost when the FIFO was full and flushed.
**Root cause** `play` zeroed `nxt`, and the saver cleared an unfinished tail word on the full-FIFO/flush branch.
**Check** after `sd file 1` and `play`, the frame count exceeds one file; `tb_saver_tail_full` requires 514 of 514 words.
**Fix** `play` resumes from the selected cursor, and the full-FIFO/flush path preserves the tail word. **Status** fixed.
**Evidence** `src/ps/sd_play.c`, `src/rtl/eth/axi_frame_saver64.v`, `sim/results/regression.txt`, `hw/measured/sd_playback.txt`.

## 20. Added in this round - `link` unreachable and a wrong BSP path

**Symptom** `cmd_link` existed in the source but the board answered "unknown command", and the documentation pointed `PS_BSP` at a directory holding only the platform descriptor, so a literal build could not find the BSP.
**Root cause** `cmd_link` was never wired into `dispatch`, and the platform descriptor directory was mistaken for a BSP.
**Check** the board must answer `[LINK] ... gap_valid=...`, and the build script must exit early with directions when the BSP is missing.
**Fix** reconnect the dispatcher and help line, rebuild the ELF and rewrite QSPI; document `PS_BSP` as the generated BSP directory and add the pre-check. **Status** fixed.
**Evidence** `src/ps/main.c`, `hw/measured/link_gap.txt`, `scripts/ps/build_ps_app.py`, `docs/declarations.md`.

## Still open

The RGMII transmit hold gap of about 0.845 ns, the reset-recovery path, the 0.025 ns hold margin, BRAM at 70%, unmeasured end-to-end latency and the HDMI human-eye items. Each is described in [`../limits.md`](../limits.md); none of them belongs in this file as "fixed".

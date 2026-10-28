# `sim/`: how to run the benches and what each answers

A bench answers one question: does this RTL behave as defined in simulation. It does not look at the board or at timing; timing lives in the implementation reports under `hw/reports/`, and board behaviour in the readings under `hw/`.

## Delivered result

19 benches in the standard regression with `fail=0`; the full-video bench passes the C17/C25/C26 specials. Verdict copies are in `sim/results/`: `regression.txt`, `tb_video_pipeline_top_report.txt`, `udp_checksum.txt` and `c31_edge_rim.log`.

## Running one bench

Run from the repository root. With ModelSim:

```bash
MSIM_BIN=<ModelSim>/win64 bash scripts/sim/run_msim.sh tb_crc32
```

`MSIM_BIN` points at ModelSim's `win64` (or Linux) directory. The script compiles all of `src/rtl`, `sim/prim` and the named bench, runs it, and prints `RESULT <tb> PASS` or `FAIL`. With xsim the entry point is `scripts/sim/run_one.sh <tb>` and the verdict line is `VERDICT <tb>: ...`.

Only one simulator may write a given work directory at a time. The script checks this up front and refuses to start if an xsim or ModelSim run already owns it, so two runs cannot mix lines in one log.

## Running all 92

```bash
vivado -mode batch -nojournal -log sim/xsim.log -source scripts/sim/run_sim.tcl
# SIM_TB=tb_crc32,tb_timing runs only the named benches; SIM_ONLY=1 compiles only; SIM_VERBOSE=1 prints the full pipeline
```

Each bench prints one `RESULT <tb> ...` line. A compile failure prints `XVLOG FAILED` and exits with 1; a bench that fails to elaborate prints `RESULT <tb> ELAB_FAIL` and the rest continue.

## Reading a verdict

There are only three outcomes: pass, fail, not measured. The verdict is the last line and a `FAIL` line carries concrete values. Exit codes are distinct: 0 pass, 1 compile or elaboration failure, 2 refused to start, 3 a check failed, 4 no verdict at all.

"Not measured" is not a pass. No verdict line, a missing module at compile time, or an empty sample set all count as not measured, and such a result must never be written up as green.

## Three rules

- The complete list is the 92 `tb_*.v` headers under `sim/`. This page indexes them by verification area and does not duplicate each bench's checks.
- The `v98` and `v103` in some file names are historical iteration numbers and carry no information; what matters is the module under test plus the covered point.
- A passing bench is not a passing board. This layer proves RTL behaviour; board readings and human acceptance live in `hw/acceptance.md` and `docs/verification.md`.

## Grouped by verification area

### Top-level video chain

| Bench | Answers |
|---|---|
| `tb_video_pipeline_top.v` | Top-level coordinate and pattern checks: geometry, row tags, seam and out-of-range fill aligned within one frame |
| `tb_pipe_bypass.v` | An all-bypass chain invents no black or X cells; every input column appears exactly once at the output |
| `tb_display_edge_rim.v` | The effect-window stages clamp top, bottom, left and right edges, with row tags on the same beat |
| `tb_edge_rim_bottom_wrap.v` | Under the wrapped continuous stream, the bottom row's neighbour below is itself, never row 0 of the next frame |
| `tb_edge_rim_wrap_clamp.v` | 3×3 clamping at the image top and bottom under the wrapped stream, with a legacy-behaviour arm that must turn red |
| `tb_edge_rim_wrap_diff.v` | Whether first-row and last-row window effects leak into each other; a negative control proves the ruler can turn red |
| `tb_c8_edge_column.v` | Cell 0 of every row: tap selection and source/processed choice |
| `tb_seam_scan.v` | Seam line width, left/right content selection, `de` pass-through and out-of-range fill |

### Network, reassembly and telemetry

| Bench | Answers |
|---|---|
| `tb_eth_top_rgmii.v` | Full RGMII loop: dual-edge sampling, IDDR/IDELAY, CDC, ARP reply and the returned clock |
| `tb_udp_reasm.v` | In-order, out-of-order, duplicate, bad and broken-then-restarted frames never contaminate each other |
| `tb_rows.v` | A frame with unwritten source rows must not commit; once all rows arrive it commits exactly once |
| `tb_rows_prod.v` | Production 512×300 cases: missing rows, short byte count, and all 300 rows written |
| `tb_cover_gate.v` | A frame missing a packet never commits and counts as bad; complete and recovered frames commit normally |
| `tb_eth_ingress_integrity.v` | Per-stage counters locate dropped words and measure peak CDC and packer FIFO occupancy |
| `tb_udp_telemetry.v` | Telemetry frames captured byte by byte at GMII: DA/SA/IP/UDP/payload/checksum all compared |
| `tb_rx_fcs.v` | Self-check of the receive FCS ruler plus standard-frame validation |
| `tb_gmii_rx_cdc.v` | GMII bytes crossing from the recovered clock to the logic clock are neither lost nor duplicated, and inter-frame gaps survive |

### DDR, frame buffer and commit

| Bench | Answers |
|---|---|
| `tb_fb_roundtrip.v` | 38,400 words written and read back with identical address and data |
| `tb_fb_pingpong.v` | After commit, the bank flips only once the saver is idle; each frame lands in its own commit record |
| `tb_fb_rd5x.v` | The five-read frame-buffer port registers output pixels against requests |
| `tb_tail_bank.v` | The last two lanes of a frame are not flipped into the next frame when back-pressure releases |
| `tb_saver.v` | 64 consecutive 16-bit pixels form one 64-bit burst, and the last two beats drain |
| `tb_writer_abort.v` | In-flight reads after an abort do not leak into the next frame, and the outstanding count returns to zero |
| `tb_commit_strobe.v` | The commit pulse, row tags and coverage conditions land on the same beat |
| `tb_allow_lead.v` | `allow` drops to 0 before `de` rises after `blank_safe` goes low |

### Geometry, effects, OSD and sources

| Bench | Answers |
|---|---|
| `tb_zoom_scan.v` | Zoom scan lines: floor+frac consistency, monotonic source column, fixed centre cell, symmetric out-of-range |
| `tb_zoom_fit_corners.v` | At several angles the fitted zoom keeps all four corners on screen; the 1.00× positive control must clip |
| `tb_zoom_frac.v` | The zoom and rotation branches describe the same cell with their coordinate and fraction |
| `tb_rotate_mapper.v` | 0° is an identity map; 90° keeps the centre in range and produces no X |
| `tb_rotate_window.v` | The effect chain still applies when rotation is on and is not forced to bypass |
| `tb_bilinear_core.v` | Four-tap bilinear identity, boundaries and coefficient combinations |
| `tb_osd_overlay.v` | All five OSD rows character by character, bit-width saturation, source label, effect code and zoom step |
| `tb_osd_glyph_rom.v` | Parallel glyph enables are equivalent to the serial interval comparison |
| `tb_gamma.v` | Gamma LUT write protocol and transparency when `en=0` |
| `tb_test_card.v`, `tb_card_render.v` | Test card still frame, cross-frame change, and per-pixel placement of the whole card |
| `tb_src_life.v` | Reset leaves no source, publishing makes one live, a timeout after silence, and republishing clears it |
| `tb_src_arb.v`, `tb_src_arb_why.v` | Three-source arbitration and the input snapshot taken on the handover beat |

### Control, keys, clocks and low level

| Bench | Answers |
|---|---|
| `tb_link_monitor.v` | Dropped words, bad packets, post-stall snapshots and frame-gap min/last/max/sum |
| `tb_split_ctrl.v` | Seam position, scan direction and automatic/manual switching |
| `tb_zoom_sel.v`, `tb_zoom_snap.v` | Zoom step selection and the cross-domain snapshot |
| `tb_key_boot.v`, `tb_key_powup.v`, `tb_key_long.v` | Power-up value, debounce window, short/long press thresholds |
| `tb_src_mode.v` | Long-press toggle bit mapped to the source-mode gray code |
| `tb_timing.v` | x/y counters, active `de` beats, one `frame_done` per frame |
| `tb_cdc_capacity.v` | Asynchronous FIFO full/empty boundaries and the 8192-slot capacity |
| `tb_crc32.v` | Ethernet reflected CRC: init value, single-byte update and clear |
| `tb_uart_decode_bits.v` | The five 0/1 characters in a serial command mapped to bit order |
| `tb_unisim_sim.v` | Frequency, period and `locked` for the three output clocks |

## All bench files

There are 92 `tb_*.v` files under `sim/`. Each file's header comment carries its own checks:

```text
tb_abort_toggle.v      tb_align.v             tb_allow_lead.v        tb_bank.v
tb_bilinear_core.v     tb_c8_edge_column.v    tb_card_render.v       tb_cdc_capacity.v
tb_commit_strobe.v     tb_copy.v              tb_cover_gate.v        tb_crc32.v
tb_ddr_line_locality.v tb_display_edge_rim.v  tb_edge_rim_bottom.v   tb_edge_rim_bottom_wrap.v
tb_edge_rim_wrap_clamp.v tb_edge_rim_wrap_diff.v tb_eth_ctrl_arb.v   tb_eth_ingress_integrity.v
tb_eth_top_rgmii.v     tb_eth_video.v         tb_fb_bilinear.v       tb_fb_pingpong.v
tb_fb_rd5x.v           tb_fb_roundtrip.v      tb_fb_vblank_copy.v    tb_first_ar.v
tb_fit_rot.v           tb_full_done.v         tb_gamma.v             tb_gated.v
tb_gmii_rx_cdc.v       tb_head_rot_displace.v tb_icmp_len_wrap.v     tb_icmp_ping0.v
tb_icmp_rx_len.v       tb_icmp_tx_cksum.v     tb_ip_csum.v           tb_key_boot.v
tb_key_long.v          tb_key_powup.v         tb_latency.v           tb_link_monitor.v
tb_lock.v              tb_morph.v             tb_osd_glyph_rom.v     tb_osd_overlay.v
tb_pipe_bypass.v       tb_pipe_sel.v          tb_proc_gray.v         tb_ps_publish.v
tb_raw_delay.v         tb_reasm_bounds.v      tb_rotate_mapper.v     tb_rotate_window.v
tb_rowmath.v           tb_rows.v              tb_rows_prod.v         tb_rx_chain.v
tb_rx_fcs.v            tb_saver.v             tb_saver_tail_full.v   tb_seam_bleed.v
tb_seam_scan.v         tb_sharpen.v           tb_shown_rate.v        tb_split_ctrl.v
tb_src_arb.v           tb_src_arb_why.v       tb_src_life.v          tb_src_mode.v
tb_sync_fifo.v         tb_tail_bank.v         tb_tap_sched.v         tb_test_card.v
tb_timing.v            tb_tx_bytes.v          tb_uart_decode_bits.v  tb_udp_parser.v
tb_udp_reasm.v         tb_udp_telemetry.v     tb_unisim_sim.v        tb_vblast.v
tb_video_pipeline_top.v tb_writer_abort.v     tb_zoom_fit_corners.v  tb_zoom_frac.v
tb_zoom_mapper.v       tb_zoom_scan.v         tb_zoom_sel.v          tb_zoom_snap.v
```

## Outside this list

There is no other rule set: how a bench judges, and how many cycles it waits, is written in its header comment, which is the same source this page summarises. When adding or changing a bench, update the header first, then the matching group here and `sim/results/`.

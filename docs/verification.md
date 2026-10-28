# Verification

Verification is not about "it ran". It answers three questions: can a check turn red, does a red check say where to look, and can a green check be reproduced.

## 1 Layers

| Layer | Object | Method | Question answered |
|---|---|---|---|
| Unit | CRC, UDP parsing, reassembly bounds, zoom mapping, bilinear, effect stages, OSD, CDC | Directed stimulus with cycle-by-cycle comparison | Does one module keep its contract? |
| Integration | RGMII → AXI ingest chain; DDR → TMDS display chain | Real interface timing plus end-to-end frame comparison | Are handshakes, latency and back-pressure between modules correct? |
| Full video | Rotation, eight zoom steps, bilinear, six effect stages, seam, OSD, edges | Long frame sequences with per-pixel checks | Does it stay same-frame and same-geometry in combination? |
| Board | Boot, serial, network, telemetry, SD, fault injection, continuous stream | Measured logs plus three-state verdicts | Does it hold on a real board and a real link? |

Every layer prints a verdict line at the end of the log, never in the middle. A log without a verdict line is a process record, not a conclusion.

## 2 Bench matrix

| Bench | Covers | Key check | Result |
|---|---|---|---|
| `tb_crc32` | Ethernet FCS | byte-by-byte match against known vectors | not in the standard regression |
| `tb_udp_parser` | UDP port, length, offset | illegal packets rejected, legal packets passed | not in the standard regression |
| `tb_udp_reasm` | offset-based reassembly | commit/abort under reordering, loss and duplicates | PASS |
| `tb_reasm_bounds` | reassembly bounds | out-of-range offsets must not corrupt the neighbouring row | PASS |
| `tb_rows` | row coverage and commit | a frame with enough bytes but missing rows must not commit | PASS |
| `tb_eth_ingress_integrity` | ingest integrity | bad, short and oversized packets counted and dropped | PASS |
| `tb_saver` | AXI packer into DDR | 16→64-bit packing, burst length, tail word | not in the standard regression |
| `tb_saver_tail_full` | full FIFO plus flush | the tail word survives the flush | PASS |
| `tb_eth_ctrl_arb` | ARP/ICMP/UDP sharing GMII | frames are never cut, length and order correct | PASS |
| `tb_eth_top_rgmii` | RGMII → AXI full chain | end-to-end byte match | PASS |
| `tb_udp_telemetry` | telemetry transmit | Ethernet header, IP, UDP, payload, IP checksum | PASS |
| `tb_link_monitor` | link counters | frame gaps, aborts, bad packets, flags | PASS |
| `tb_zoom_mapper` | inverse zoom mapping | identity at 1.0×, centre at 0.5×, out-of-range | not in the standard regression |
| `tb_zoom_sel` | zoom choice under rotation | the image never rotates out of the panel | not in the standard regression |
| `tb_fb_bilinear` | bilinear read port | four-tap weights and bypass | not in the standard regression |
| `tb_proc_gray` / `tb_sharpen` | effect stages | per-pixel match with the reference model | not in the standard regression |
| `tb_morph` | effect stages | per-pixel match with the reference model | PASS |
| `tb_split_ctrl` | seam position and pixel fetch | same frame and same coordinates on both sides | PASS |
| `tb_split` | seam position and pixel fetch | same frame and same coordinates on both sides | not in the standard regression |
| `tb_osd_overlay` | OSD overlay | glyphs, position, latency | PASS |
| `tb_video_pipeline_top` | full display chain | quick_c17; C17/C25/C26 specials PASS, nfail=0 | PASS |

The standard regression has 19 benches (17 existing plus `eth_ingress_integrity` and `saver_tail_full`) and the delivered summary reads `fail=0`.

Those 19 have verdict lines in `sim/results/regression.txt`. The benches marked "not in the standard regression" keep their sources in `sim/` but ship without logs, so they are not part of the delivered conclusion. The 185° special in the full-video bench is `RESULT tb_video_pipeline_top PASS nfail=0 (quick_c17)`.

## 3 Special checks

### 3.1 Frame commit

The reassembler commits only when every byte has arrived, every source row has been written and no bad packet appeared in the frame. The bench feeds a frame with a full byte count covering only 3/4 of the rows and requires no commit; a mutant that increments the row counter on every written word reports:

```text
FAIL commit with full byte count but only 3/4 rows
```

With the source restored it passes. This check separates the byte gate from the row-coverage gate, and explains why the board's abort counter reports missing rows as a cause rather than a rate.

The A9 section of `tb_udp_reasm` drops the tail of one frame and the head of the next, with more than 4 ms of silence between them; the check requires the two frames not to mix and the third frame after recovery to commit cleanly.

### 3.2 Cross-colour on one row

C22 checks whether the window stages of the effect chain see row tags and data in the same beat. Before the fix, 6 and 48 fully white pixels appeared at the top and bottom edges; after aligning the row tag with a one-line delay from the upstream stage, the count is 0.

C31 uses a 9-bit row tag frame `{1'b1, row[5:0], col[8:0]}` and checks the tap selected in every cell. Before the fix, two full rows at the frame tail had 1028 mismatching cells each under rotation; after routing the seam `sx` through a two-row ring before `seam_src`, the whole frame reads 0 in both swap states.

Both checks carry before/after readings. The full-video report in the package keeps C22's PASS line, the C31 re-verification is `sim/results/c31_edge_rim.log`, and the pre-fix red readings are kept in the project records outside this repository.

### 3.3 UDP checksum

`tb_udp_telemetry` captures bytes from the GMII port at frame offsets and compares the Ethernet header, IP destination, UDP ports and payload byte by byte. The IPv4 header check is: add the ten 16-bit words of the header, including the checksum field, and fold; the result must be `16'hffff`. Omitting one term on purpose makes the bench report `FAIL ip checksum sum=003c`; with the source restored it passes.

### 3.4 The instrument goes red under injected faults

The three-stage self-test uses per-second deltas from the network telemetry, never absolute values:

| Stage | Stimulus | Check | Measured |
|---|---|---|---|
| Clean | built-in pattern, 30 fps | ≥ 8 fps, at most the one boot-time abort, at least one valid latency ≤ 200 ms | 22.0 fps, 0 aborts |
| Fault | drop one packet in 100 | ≥ 5 aborts/s, < 5 fps | 0 fps, 14.3 aborts/s |
| Recovery | clean stream | back to clean-stream level | 18.9 fps, +1 abort (boot) |

Aborts rise and frame rate falls in the fault stage; both return to normal in recovery. The instrument reacts to deliberate damage instead of only showing a nice number.

## 4 Board acceptance

Conditions:

- Board: Zynq-7020 development board, PL-side RJ45, HDMI 1024×600 panel.
- Network: PC wired NIC 192.168.1.100, board 192.168.1.10, direct gigabit link.
- Serial: channel B of the USB-C bridge, COM6, 115200 8N1.
- Boot: QSPI image written, then power-cycled; JTAG only for debug and temporary download.

| Item | Method | Expected | Measured |
|---|---|---|---|
| Cold boot | QSPI write + hardware readback + power cycle | PL DONE and EOS, no CRC/IDCODE error; `stat`/`link` reply; ping 5/5 | pass |
| Continuous stream | `video_sender.py --demo --seconds 8` | about 240 frames in 8 s, 30 fps | 241 frames in 8.05 s = 29.95 fps |
| Telemetry | `telemetry_listen.py 13` after a ping | about 13 beacons, frame count monotonic | 13 beacons |
| Self-test | `link_selftest.py` | all three stages pass | PASS (22.0 / 0 / 18.9 fps) |
| Processed pane | 185°, `split video`, seam at 50%, grayscale only | `pane_bad=0` and valid | pass |
| Frame gaps | `link clr` → stream → stop → restart → `link` | `gap_valid=1` while streaming; `stall` grows after stop; `gap_max` records the long gap | pass (`gap_max=22,061 ms`) |
| Serial commands | 105-command list | every command answers, final state equals initial | pass |
| Temperature | `temp` after continuous streaming | `sane=1`, plausible reading | 61.8–63.8 °C |
| HDMI picture | human eye, continuous run | same frame left/right, matching geometry, OSD agrees with serial; days of running without tearing, flashing or frozen frames; recovery after ETH/SD hot-plug | E1–E5 confirmed; panel colour remains subjective |

## 5 How the checks themselves are checked

- **Mutation contrast**: feed a known-bad input and the check must turn red; restore the source and it must turn green.
- **Repeat runs**: deterministic checks run twice and compare byte for byte; non-deterministic board readings are not compared that way.
- **Three states**: `PASS`, `FAIL`, `NOT_MEASURED`. An unreadable input is never a pass.
- **Evidence pointer**: every conclusion names a log or report, and the verdict line is quoted from the end of that file instead of being paraphrased into "the test passed".

## 6 What is not covered

- HDMI E1–E5 are confirmed on the bench (E1–E3 visually, E4 over days of continuous running, E5 covering ETH and SD hot-plug); panel colour stays subjective with no machine check.
- Telemetry latency excludes encoding, cable and switch, so it is not end-to-end latency.
- The RGMII transmit hold gap is not removed in RTL; the design relies on 0° forwarding and long clean ping runs.
- Power and junction temperature are tool estimates; no board-level power measurement was made.
- Only one 512×300 input is verified. 1080p, multiple inputs and compressed streams are not.

`limits.md` explains each of these, so that "not measured" is never passed off as "passing".

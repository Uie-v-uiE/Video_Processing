# Board acceptance

Acceptance has two halves: what a machine can judge, and what a human must sign off. The machine half must give commands, expectations and logs; the human half needs a signature, because "I looked at it" is not a conclusion.

## 1 Machine acceptance

Prerequisites: board powered, USB-C connected, COM6 not held by a terminal, hw_server listening on 3121, PL configured, PS application downloaded.

```bash
VP_XSDB=<Vitis>/bin/xsdb.bat bash hw/scripts/board_health.sh
```

| Item | Expected | Measured |
|---|---|---|
| Serial | `stat,temp,stat` all answer; first and last `stat` agree except `pub=` | pass |
| JTAG | reads AXI GPIO and eight DDR header words | pass |
| Exception vectors | three labels readable with non-zero values | pass |
| Verdict | `HEALTH: GREEN` | pass |
| QSPI cold boot | after a power cycle PL DONE=1, EOS=1, no CRC/IDCODE error; `stat`/`link` answer; ping 5/5 | pass |

```bash
python src/host/link_selftest.py 192.168.1.10 6
```

| Stage | Expected | Measured |
|---|---|---|
| Clean | at least 8 fps, at most the single boot-time abort, at least one valid latency of 200 ms or less | 22.0 fps, 0 aborts |
| Injected loss | at least 5 aborts/s, under 5 fps | 0 fps, 14.3 aborts/s |
| Recovery | back to clean level | 18.9 fps, +1 abort (boot) |
| Verdict | `PASS link_selftest` | pass |

```bash
python src/host/telemetry_listen.py 13
```

Expect 13 beacons at 1 Hz with a rising frame count. Ping the board once first so it learns the PC MAC and IP.

```bash
node src/host/uart_cmd_check.mjs --port COM6
```

Expect all 105 commands to answer as specified and the final state to equal the initial state. The frame-gap statistics are checked separately:

```text
link clr
link
```

Measured: while streaming `gap_last=28 ms`, `gap_min=16 ms`, `gap_max=49 ms`, `gap_valid=1`; after the stream stops, `stall` grows to 5645 ms while `gap_last` and `gap_max` keep the last frame values; after a restart `gap_max` records the 22,061 ms gap. Pass.

## 2 Human acceptance

Signed off on site:

| # | Item | Check | Signed by | Result | Note |
|---|---|---|---|---|---|
| E1 | Same-frame comparison | left of the seam is the source, right is the same frame processed; geometry matches | visual, on site | nothing abnormal | no instrument record |
| E2 | Geometry edges | zoom or rotation produces no whole-row shift and no unprocessed band at the edges | visual, on site | nothing abnormal | no instrument record |
| E3 | OSD agreement | source size, frame rate, rotation/zoom, seam position and temperature agree with `stat` and `temp` | visual, on site | nothing abnormal | no instrument record |
| E4 | Display stability | ten minutes of continuous running with no tearing, flashing or frozen frames | observed on site | pass | ran for days with nothing abnormal |
| E5 | Fault recovery | after the stream stops the picture holds the last frame and resumes on restart; SD removal falls back | link_selftest plus on-site check | pass | stop/resume covered by the self-test; ETH and SD hot-plug both confirmed on site |

E1 and E2 are the core checks of the design; E3 compares against serial readings; E4 covers continuous stability; E5 covers recovery. Anything unsigned is not written as a pass.

## 3 Current state

All machine checks pass. E1-E3 were inspected on site, E4 ran for days without tearing, flashing or frozen frames, and E5 ETH and SD hot-plug were confirmed. Panel, cable and perceived picture quality are outside the machine checks; `pane_bad=0` does not stand in for them.

## 4 Known limits

- Telemetry latency covers the PL only, not glass-to-glass.
- The RGMII transmit side has about 0.845 ns of TskewT hold margin missing.
- BRAM is at 70%, so the frame cannot grow to 1080p.
- The first few rows of a frame may be one frame older than the rest, and only a human can judge whether that is acceptable.

Details are in `docs/limits.md`.

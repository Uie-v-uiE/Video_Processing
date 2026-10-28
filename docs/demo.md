# Demonstration script

Every part lists three things: the commands to send, what appears on the panel and in the terminal, and the text to put on screen in the edit. Commands are the ones the current firmware accepts; serial is `115200 8N1` on `COM6`, board `192.168.1.10`, video on UDP 5001, telemetry on UDP 1234.

Layout is constant: panel on the right, terminal or dashboard on the left. Pause two seconds after each command before moving on.

## Part 1 - Power-up and identity (15 s)

| Send | What appears | On-screen text |
|---|---|---|
| (power on, no JTAG, no PC) | panel lights after 2-4 s, five OSD rows | `Zynq-7020 · all-PL video path` |
| `stat` | `[STAT] ctrl ... src=... frames=...` | `control word, source, frame count in one readback` |
| `temp` | `[TEMP] degC=62.3 ...` | `XADC temperature reaches the OSD` |

## Part 2 - Network ingest (30 s)

| Send | What appears | On-screen text |
|---|---|---|
| `src 1` | `[SRC] ... ETH` | `source: network stream` |
| `python src/host/video_sender.py --demo --seconds 30` | video on the panel, `SRC:ETH  FPS:30` | `host -> UDP -> RGMII -> DDR` |
| `python src/host/telemetry_listen.py 20` | one line per second with `frames= pkts= bad= aborts= lat_ms= pane_bad=` | `1 Hz telemetry: the board counts` |
| `link` | `[LINK] drop= badpkt= aborts= rows_max= stall= gap_last/min/max live=1` | `link counters, read-only` |

## Part 3 - Zoom and bilinear (40 s)

| Send | What appears | On-screen text |
|---|---|---|
| `zoom off` | nearest-neighbour expansion | `bilinear off: blocky` |
| `bilin on` | same spot turns smooth | `bilinear on: smooth` |
| `zoom 0.5` then `zoom 1.0` then `zoom 1.5` | OSD `Zoom:` steps | `eight fixed steps, 0.25-2.00` |
| `zoom auto` | ratio breathes on its own | `automatic sweep` |

Trap: `zoom 1` is a switch; `zoom 1.0` is the 1.00 ratio.

## Part 4 - Arbitrary-angle rotation (40 s)

| Send | What appears | On-screen text |
|---|---|---|
| `rot auto 1` | the picture starts turning | `arbitrary angle, 2 deg per frame` |
| `rot speed 0` at any angle | motion stops, OSD `Rot:` shows the angle | `angle read from the OSD, as measured` |
| `zoom fit 1` | the image shrinks to fit at any angle | `zoom follows the angle` |
| `rot speed 5` | faster rotation | `seven speed steps` |

There is no serial entry for an absolute angle; drive it with the keys or automatic rotation and report the angle the OSD shows.

## Part 5 - Six-stage effect chain (50 s)

| Send | What appears | On-screen text |
|---|---|---|
| `pipe 000000000` | all effects off | `all stages off` |
| `pipe 100000000` | grayscale | `1 grayscale` |
| `pipe 010000000` | invert | `2 invert` |
| `pipe 001000000` | blur | `3 3x3 blur` |
| `pipe 000100000` | sharpen | `4 3x3 sharpen` |
| `pipe 000010000` | edges | `5 Sobel` |
| `pipe 000001100` | black and white | `6 threshold` |
| `th 120` then `th 200` | white area changes | `threshold 0-255` |
| `gamma 1.8` | right pane changes brightness, left does not | `gamma affects the processed pane only` |

Light up the numbers 1 to 6 one at a time; never say "six effects at once".

## Part 6 - Same-frame seam (40 s)

| Send | What appears | On-screen text |
|---|---|---|
| `pipe 000010000`, `split screen`, `split 50` | one vertical seam, source left, Sobel right | `same frame, source left, processed right` |
| `split auto` (record 8 s) then `split manual` | seam sweeps across, content continuous | `the seam moves, the picture does not tear` |
| `split swap 1` | panes swap, seam position unchanged | `content swaps, the seam does not` |
| `split swap 0` | back again | `both panes share one geometry` |
| `split marker 1` | blue line disappears, seam stays | `the marker is only a marker` |

This is the cheapest convincing shot in the whole video: one command, two pictures, no narration needed.

## Part 7 - Three-gate commit, made visible (60 s)

Open the dashboard first: `python src/host/instrument_dashboard.py 192.168.1.10` (click Ping/ARP once).

| Send | What appears | On-screen text |
|---|---|---|
| `python src/host/udp_push.py --pattern edge --fps 15 --count 600` | full-screen black and white flipping hard | `every frame is committed whole` |
| `python src/host/udp_push.py --pattern edge --fps 15 --count 400 --drop-every 500` | the flip stutters every few frames | `one packet in 500 lost: some frames rejected` |
| `python src/host/udp_push.py --pattern edge --fps 15 --count 400 --drop-every 100` | the picture freezes on one colour | `one packet in 100 lost: no full frame, no switch` |
| (keep the dashboard in frame) | FPS curve falls to 0, `ABORTS` climbs, the event line reads "作废帧 +N（最后一次缺 X 行）" | `bytes, rows, bad packets: all three gates must pass` |
| `python src/host/udp_push.py --pattern edge --fps 15 --count 400` | flipping resumes | `recovery: the counters stop climbing` |

Narration is one sentence: "the packets went out, the screen did not change, because this frame never arrived whole." Do not try to demonstrate the three gates one at a time: a single lost packet fails the byte gate and the row bitmap together, so the picture looks identical and the question "how do you tell them apart" has no on-screen answer. The separation lives in the benches (`tb_udp_reasm` covers reordering and duplicates, `tb_reasm_bounds` covers out-of-range offsets).

## Part 8 - An instrument that can be made to fail (45 s)

| Send | What appears | On-screen text |
|---|---|---|
| `python src/host/link_selftest.py 192.168.1.10 6` | three stages, each printing per-second `frames=/aborts=/bad=` | `clean -> injected loss -> clean` |
| (keep the verdict line in frame) | final verdict and exit code | `the check is a rate, not an absolute` |
| `link clr`, stop the stream for 8 s, `link` | `stall=` climbs from hundreds to thousands of ms | `a dead link is timing too` |
| restart the stream, `link` | `gap_valid=1`, `gap_max=` holds the outage | `the longest gap is remembered` |
| `pipe 100000000`, `split video`, `split 50` | telemetry `pane_bad=0` | `processed-pane integrity: zero` |

## Part 9 - SD playback (30 s, optional)

| Send | What appears | On-screen text |
|---|---|---|
| `sd` | `[SD] ... frames ... fps ... files ...` | `microSD mounted directly` |
| `sd files` | list of raw-frame clips | `RGB565 frame sequences` |
| `play` | playback starts | `PS reads the card, writes DDR, PL displays` |
| `frame 1200` | the picture stops on frame 1200 | `jump to an exact frame` |
| `stop` | playback stops | - |

## Part 10 - Cold boot without a host (30 s)

| Send | What appears | On-screen text |
|---|---|---|
| `src 0` (before power-down) | the panel shows the PL test card, moving on its own | `the card is drawn by the PL, no host needed` |
| (power off 10 s, power on) | black for 2-4 s, then the picture | `the bitstream lives in on-board QSPI` |
| `stat` | `frames=` unchanged | `it answers as soon as it is up` |
| `src 1` and start streaming | `frames=` starts rising | `adding a host needs no reboot` |

Record the power switch and the first lit frame in one unbroken shot. Do not cut a JTAG cable into frame, and do not stage this with the stream already running: that would be a warm state, not a cold boot.

## Part 11 - Closing (15 s)

| Send | What appears | On-screen text |
|---|---|---|
| `python src/host/video_sender.py --demo --seconds 8` | readings scroll past | `241 frames in 8 s, 30 fps` |
| 2 s of the seam sweep | seam crosses again | `same-frame A/B` |
| 2 s of the dashboard curve | curve drops and recovers | `the instrument can fail` |
| 2 s of the cold boot | hand on the switch, screen lights | `it runs without a host` |

## Short cuts

Three-minute version: drop part 9, keep one zoom comparison in part 3, one rotation in part 4, and three effect jumps in part 5.

Ninety-second version: four shots only - `split swap 1`, the freeze under `--drop-every 100` with aborts climbing, the `link_selftest.py` verdict line, and a cold boot lighting the panel.

## Reset before recording

```text
src 1
zoom 1.0
rot auto 0
rot speed 0
split screen
split 50
split swap 0
split marker 0
osd on
pipe 000010000
```

Three commands that are easy to get wrong: `zoom 1` is a switch, `split marker 1` hides the blue line, and in `pipe` the leftmost character is bit0 (grayscale).

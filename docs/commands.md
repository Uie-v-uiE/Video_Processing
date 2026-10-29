# Serial command reference

This reference matches the PS firmware in the repository; the entry points are `dispatch()` and `help` in `src/ps/main.c`. The firmware has the final say: if this page and the board disagree, trust `help` and the reply you actually see.

Serial settings: `115200 8N1`, port discovered per machine (`COM6` in this project). One command per line, terminated by Enter; CR, LF and CRLF are all accepted. Verbs and parameters are case-insensitive. A line may carry at most 128 bytes and 8 tokens; over-long lines are rejected instead of being silently truncated.

Replies are quoted verbatim from the firmware, which prints Chinese.

## 1 Three possible outcomes

1. **Executed** — a control bit is written or a counter is read, and one line with the result comes back.
2. **Rejected** — the parameters are invalid; one line explains what to type, and no register is written.
3. **Unknown** — the verb is not in the table; the firmware replies `[CMD] 不认: <line>` and prints help.

There is no fourth outcome where a command is accepted and does nothing. The command battery `hw/scripts/cmd_battery_v81.txt` and its checker `src/host/uart_cmd_check.mjs` pin exactly these three.

## 2 Status, link and help

| Command | Purpose | Reply | Notes |
|---|---|---|---|
| `help` or `?` | print all syntax | multi-line help | most reliable command table; check it after any firmware change |
| `stat` or `status` | read control word, source, frame counts, effects, geometry and OSD | `[STAT] ctrl thr=... src=... zoom=... bilin=... zsel=... zman=... pub=... sd=... frames=... playing=... sel=... gm=... mode=... geom=... osd=...` | field order is fixed; `pub=` toggles every frame and must be excluded from before/after comparisons |
| `temp` | read PS-XADC temperature, VCCINT, threshold and OSD encoding | `[TEMP] degC=... raw=... vccint=... th=... over=... sane=... osd=... gpio=...` | `sane=1` means the reading looks like a real conversion; `osd=--` means the on-screen value is not trustworthy |
| `temp th 60` | set the temperature alarm threshold | `[TEMP] th=60C` | 0–200 °C; out-of-range falls back to 85 |
| `link` | read the PL link counters | `[LINK] drop=... badpkt=... aborts=... rows_max=... stall=...ms gap_last=... gap_min=... gap_max=... gap_sum=... gap_valid=... live=...` | read-only, never changes the source |
| `link clr` | clear the frame-gap statistics | `[LINK] gap statistics cleared` | start streaming after clearing; `gap_valid` needs at least two frames to become 1 |
| `echo 0` / `echo 1` | disable/enable the board echoing input characters | `[ECHO] ...` | the Vitis serial terminal echoes locally, so keep `echo 0`; PuTTY does not, so use `echo 1`. Enable exactly one, or every character appears twice |

`link` fields:

- `drop` — 32-bit words dropped when the CDC FIFO is full; not network packet loss, and it should stay 0 on a clean stream;
- `badpkt` — bad packets received (FCS/length); a packet the sender never sent does not increment it;
- `aborts` — frames rejected by the byte gate, row-coverage gate or bad-packet gate; one frame increments once even if several packets are missing;
- `rows_max` — worst missing-row count in one abort;
- `stall` — milliseconds since the last valid frame;
- `gap_last` / `gap_min` / `gap_max` / `gap_sum` — latest, minimum, maximum and cumulative frame gap;
- `gap_valid` — whether the gap statistics have been calibrated by at least two frames;
- `live` — whether the link is alive.

## 3 Sources

| Command | Purpose | Reply | Rejected / notes |
|---|---|---|---|
| `src auto` | hand control back to the key ring and pick a source automatically | `[SRC] 已钉住 自动...` | long-pressing KEY1 does the same |
| `src 0` | pin the on-chip test card (TEST) | `[SRC] 已钉住 TEST ...` | the card is drawn by the PL and uses no DDR |
| `src 1` | pin the network stream (ETH) | `[SRC] 已钉住 ETH ...` | the picture comes from the DDR ping-pong |
| `src 2` | pin SD playback and start playing | `[SRC] 已钉住 SD ...` | with an unreadable card the reply is `[SD] play refused: <reason>` |
| `src 3` / `src 9` | no such source | — | `[SRC] 只认 auto / 0=TEST 图卡 / 1=ETH 网络 / 2=SD 卡回放`, state unchanged |

`src 0/1/2` and the on-screen `SRC:` field come from the same state. `SRC:` shows the source actually being displayed, not the one you hoped for.

## 4 Effect chain `pipe`

In `pipe <nine bits>`, the character position is the bit number: leftmost is bit0.

| Bit | Algorithm | Stage |
|---|---|---|
| 0 | grayscale | colour |
| 1 | invert | colour |
| 2 | 3×3 blur | filter |
| 3 | 3×3 sharpen | filter |
| 4 | Sobel edge | edge |
| 5 | threshold (brighter than threshold = white) | threshold |
| 6 | invert the threshold decision (only meaningful with bit5=1) | threshold |
| 7 | erode | morphology |
| 8 | dilate | morphology |

- Nine bits: executed, reply `[PIPE] sel=... 生效: ...`.
- Five bits: **translated, not executed**; the reply names the equivalent nine-bit string.
- Any other length: rejected, no register written.
- `pipe show`: print the stage names for the current nine bits.
- With bit7 and bit8 both set, neither erode nor dilate runs.
- The chain latency is always 15 pixel clocks, no matter which stages are on.

The on-screen `Pipe:` field is not this nine-bit string; it is five digits, each 0–3 naming which algorithm that stage selected. Use `pipe show` to explain it.

## 5 Zoom, bilinear, OSD and threshold

| Command | Purpose | Reply | Rejected / notes |
|---|---|---|---|
| `zoom on` / `zoom off` | start/stop the right-pane automatic breathing (legacy `ZOOM1`/`ZOOM0`) | `[CTRL] ... zoom=1/0` | stopping freezes the current ratio; it is neither a ratio nor the bilinear switch |
| `zoom 1.5` | pick the nearest manual step | `[ZOOM] 1.5 → 最近档 1.50x（八档：...）` | steps: 0.25/0.33/0.50/0.75/1.00/1.33/1.50/2.00 |
| `zoom auto` | return to automatic breathing | `[CTRL] zoom_step=... (自动呼吸)` | — |
| `zoom fit [0/1]` | choose zoom from the rotation angle | `[ZOOM] fit=1...` | no argument means 1; the OSD shows `(Fit)` |
| `bilin on` / `bilin off` | bilinear / nearest neighbour | `[BILIN] bilin=on/off` | visible only at non-integer ratios or while rotating; at 1.00× and 0° the two modes are pixel-identical, not a broken switch |
| `bilin show` | print the switch state and the comparison sequence | multi-line | — |
| `osd on` / `osd off` | show/hide the five text rows | `[OSD] osd=on/off` | only affects the overlay; picture and counters keep running |
| `osd show` | print OSD state | multi-line | — |
| `th 120` | threshold for the binary stage | `[CTRL] ... thr=120` | 0–255, clamped; legacy `TH120` |
| `gamma 1.8` | write the 256-entry gamma curve | `[GAMMA] g=1.80 ...` | 1.00–3.00, also accepts 180; affects the processed pane only |
| `gamma off` / `gamma on` | disable/enable gamma | `[GAMMA] off/...` | table is kept, switching is fast |
| `gamma auto 1.0 3.0 20 2000` | sweep gamma automatically | `[GAMMA] auto：...` | 100≤lo<hi≤300, 0<step≤hi−lo (step is an integer γ×100, 20 = 0.20), ms≥200 |
| `gamma manual` / `gamma show` | stop the sweep / print state | multi-line | — |

`zoom 1` is the old on/off spelling, not 1.00×. Write `zoom 1.0` for a 1.00× ratio. This is the easiest mistake to make during a demonstration. The eight steps (0.25–2.00) are the manual range; automatic breathing only moves between 1.00 and 0.50.

## 6 Geometry: rotation and seam

| Command | Purpose | Reply | Rejected / notes |
|---|---|---|---|
| `rot auto [0/1]` | automatic rotation on/off | `[ROT] auto=1...` / `[ROT] auto=0...` | no argument means 1; enabling auto sets speed to 2 if it was 0 and turns on fit if it was off |
| `rot speed 0..7` | degrees per frame | `[ROT] speed=<n> 度/帧` | 0 = auto on but not stepping; at 60 fps, 1 is about 6 s per turn and 7 about 0.9 s |
| `rot show` | print auto, speed and fit | `[ROT] auto=... speed=... zoom=fit/now` | no angle here; the angle exists only on the OSD `Rot:` field and on KEY1/KEY2 |
| `rot 45` | does not exist | — | there is no serial entry for an absolute angle; step to it with the keys |
| `split screen` | sweep the seam in display columns | `[SPLIT] screen：...` | 0–1024 across the screen |
| `split video` | sweep the seam in image columns, following rotation | `[SPLIT] video：...` | 0–512 across the image |
| `split 50` | seam position in percent | `[SPLIT] 50% -> pos=.../1024...` | 0–100; a partial column truncates, e.g. 30% reports 29% |
| `split px 200` | seam position in absolute columns | `[SPLIT] pos=200 px = ...%` | upper bound is the current space width |
| `split auto` / `split manual` | sweep automatically / stop where it is | `[SPLIT] auto/manual ...` | — |
| `split swap 0/1` | swap the two panes | `[SPLIT] swap=1（只换内容，不换缝位）` | the seam position does not move |
| `split follow 0/1` | choose display columns or image columns | `[SPLIT] follow=...` | same bit as `screen/video` |
| `split marker 0/1` | show/hide the 2 px blue line | `[SPLIT] marker=...` | 0 hides it, 1 shows it (the register bit is marker_off, so the command value is inverted) |
| `split show` | print position, coordinate space and flags | `[SPLIT] pos=...` | — |

`split range` and `split speed` are still build-time parameters; the current command layer rejects them, so keep them out of demonstration scripts.

## 7 SD card and playback

| Command | Purpose | Reply | Rejected / notes |
|---|---|---|---|
| `sd` | remount and print a summary | `[SD] ... frames ... fps ... files ...` | on failure `[SD] mount failed: <reason>` |
| `sd files` | list files | `[SD] N file(s), ... frame(s) total` plus one line per file | run `sd` first if the card is not mounted |
| `sd file 1` | select file 1 | `[SD] file #1 ... first=...` | indices start at 0; out-of-range is rejected |
| `sd remount` | force a remount | `[SD] remount ok` | use after hot-plugging the card |
| `play` / `play 1` | start playback | `[SD] playing ...` | no argument starts playback; `play 0/off/stop` stops |
| `stop` | stop playback | `[SD] stopped; next frame ...` | — |
| `frame 1200` | show frame 1200 only | the panel changes frame; check `stat` | non-decimal or negative values are rejected |
| `autoplay 0/1` | current-session auto-play flag | `[SD] autoplay on/off (session only; reset/re-download returns to 1)` | lives only in this run; reset or re-download returns to 1, so it cannot disable the next boot's SD autoplay |
| `fill` | write a four-colour diagnostic frame | two `[CTRL]` lines plus four colour blocks | for path checks; does not write the SD card |

The card must be FAT32. If `sd files` fails after a hot-plug, wait two or three seconds and run `sd remount`. `src 2` pins SD and starts playback; `src 1` returns to the network source.

## 8 Legacy spellings

Older tools and scripts still contain these:

| Legacy | Current | Note |
|---|---|---|
| `SRC0` / `SRC1` / `SRC2` | `src 0/1/2` | source |
| `ZOOM0` / `ZOOM1` | `zoom off/on` | breathing switch, not a ratio |
| `TH80` | `th 80` | threshold |
| `BILIN0` / `BILIN1` | `bilin off/on` | bilinear |
| `OSD0` / `OSD1` | `osd off/on` | overlay |
| `FRAME12` | `frame 12` | SD frame number |
| `AUTOPLAY0/1` | `autoplay 0/1` | current-session auto-play flag (reset returns to 1) |
| `pipe 11000` / `01010` / `pipe 00000` | none | five-bit spellings are translated but never written to registers |

## 9 The five OSD rows

| Row | Content | Reading |
|---|---|---|
| L0 | `512X300  FPS:30  SRC:ETH` | source size, frame rate, source actually displayed |
| L1 | `Pipe:11000  Th:80  Gamma:1.8` | five-digit effect projection, threshold, gamma |
| L2 | `Rot:45°  Zoom:0.75X(AUTO)` | angle and zoom step; `(Fit)` means zoom follows the angle |
| L3 | `Split:50%  Latency:16MS` | seam position and PL-internal frame latency |
| L4 | `Temp:62C` | XADC temperature; `--` means no trustworthy reading yet |

Row 0 shows the source at 512×300, not the 1024×600 panel. `Latency` covers the PL only; it is not glass-to-glass.

## 10 Restore defaults and self-check

Restore defaults before a demonstration or acceptance run:

```text
src 1
zoom fit 0
zoom 1.0
rot auto 0
rot speed 0
split screen
split 50
split swap 0
split marker 0
osd on
gamma off
pipe 000010000
stat
```

Automatic checks:

```bash
node src/host/uart_cmd_check.mjs --port COM6
node src/host/uart_cmd_check.mjs --replay hw/uart_script_capture.txt
```

The first sends every line of `hw/scripts/cmd_battery_v81.txt` and compares replies; the final `STAT` must equal the first one except for `pub=`. The second judges an existing capture offline. "It echoed something" without a verdict line is not a pass.

## 11 Traps

1. `zoom 1` is a switch; `zoom 1.0` is a 1.00× ratio.
2. The nine-bit `pipe` string and the five-digit `Pipe:` field are different encodings; use `pipe show`.
3. `split swap` changes content only, never the seam position; `split marker 0` hides the blue line (`1` shows it).
4. `rot auto 1` may also set speed to 2 and switch zoom to fit; set `rot speed 2` and `zoom fit 0` first if you do not want that.
5. After `link clr`, `gap_valid` needs at least two frames; `stall` growing after the stream stops is normal.
6. `temp`'s `osd=` and `gpio=` should agree with `degC=`; if they do not, check the PS→PL synchronisation chain before touching the threshold.
7. `aborts` counts frames, while the sender's "dropped N packets" counts packets; do not expect a 1:1 match. `badpkt` only rises for packets that arrive malformed.
7. Enable either the terminal's local echo or the board's `echo`, never both, or every character appears twice.
8. A line carries at most 128 bytes and 8 tokens; send long-parameter commands one at a time.

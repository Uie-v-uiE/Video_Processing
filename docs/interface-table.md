# Interface tables

This page is the shared reference for software, firmware and PL. The bit definitions live in the RTL and in `src/ps/main.c`; this page only indexes them. Changing a bit order means changing all three together.

## 1 Addresses and sources

| Region | Address | Purpose |
|---|---|---|
| ETH ping-pong bank 0 | `0x1000_0000` | network frames, written by the PL over AXI HP0, read by the display |
| ETH ping-pong bank 1 | `0x1008_0000` | second network frame buffer |
| PS source frame | `0x1010_0000` | SD playback and the FILL diagnostic frame, clear of both ETH banks |
| AXI GPIO 0 | `0x4120_0000` | control word and lane select |
| AXI GPIO 1 | `0x4121_0000` | read-only health snapshot |
| AXI GPIO 2 | `0x4122_0000` | channel 1 = `CFG_DATA0`, channel 2 = `CFG_DATA1` |

## 2 Control word at `0x4120_0000`

| Bit | Meaning |
|---|---|
| `[4:0]` | legacy five-bit effect enable; retired, reads back as 0 |
| `[15:8]` | threshold (default 80) |
| `[16]` | `src_sel`: 0 = test card, 1 = DDR |
| `[17]` | `zoom_en`: automatic zoom breathing |
| `[18]` | `publish` |
| `[19]` | `bilin`: 1 = bilinear, 0 = nearest neighbour |
| `[20]` | OSD off (active high) |
| `[22]` | mode toggle |
| `[24:23]` | mode: 00 auto, 01 ETH, 11 SD, 10 TEST |
| `[26]` | `gapclr`: clears the `gap_*` counters in `link_monitor` |
| `[31:27]` | health lane number |

## 3 `0x4122_0000 + 0x00` (`CFG_DATA0`)

| Bit | Meaning |
|---|---|
| `[8:0]` | `stage_sel`: grayscale, invert, blur, sharpen, Sobel, threshold, inverted decision, erode, dilate |
| `[9]` | `rot_auto`: automatic rotation |
| `[12:10]` | `rot_speed`: 0–7° per frame |
| `[22:13]` | `split_pos`: seam position in display columns, 0–1023 (the PS clamps 1024 to 1023 and reports the clamp) |
| `[23]` | `split_auto` |
| `[24]` | `split_follow`: 1 = seam measured in image columns and follows rotation |
| `[25]` | `split_swap`: swaps the two panes only, never the seam position |
| `[28:26]` | `zcode`: one of eight zoom steps from 0.25× to 2.0× |
| `[29]` | `zman`: manual zoom step |
| `[30]` | `split_marker_off`: 1 hides the seam marker |
| `[31]` | `zoom_fit`: zoom chosen from the current angle so the whole image stays on screen |

## 4 `0x4122_0000 + 0x08` (`CFG_DATA1`)

| Bit | Meaning |
|---|---|
| `[31]` | gamma enable |
| `[30]` | gamma write toggle |
| `[29:22]` | gamma data |
| `[21:14]` | gamma table index |
| `[13:8]` | gamma value shown in the OSD (γ×10) |
| `[7:0]` | OSD temperature, two BCD digits: `[7:4]` tens, `[3:0]` units; a nibble above 9 draws `--` |

## 5 Telemetry beacon (UDP 1234, 32 bytes, little-endian)

| Offset | Length | Meaning |
|---:|---:|---|
| 0 | 4 | magic `VDEO` |
| 4 | 1 | version |
| 5 | 1 | bit0 = link alive |
| 6 | 4 | frames received |
| 10 | 4 | packets received |
| 14 | 4 | bad packets |
| 18 | 2 | missing rows in the last abort |
| 20 | 4 | free-running seconds |
| 24 | 2 | aborted frames |
| 26 | 2 | PL-internal latency (ms) |
| 28 | 2 | source port |
| 30 | 1 | bit0 = latency valid, bit1 = processed-pane count valid |
| 31 | 1 | non-gray pixels in the processed pane (saturates at 255) |

The beacon goes to the last ARP requester, so ping the board once before starting the listener.

## 6 Health lanes

| Lane | Content |
|---|---|
| 0 | `drop_words`: 16-bit words blocked by a full FIFO |
| 1 | low 16 = aborted frames, high 16 = bad packets |
| 2 | low 16 = `stall` in ms since the last frame, high 16 = maximum missing rows |
| 3 | `gap_last` (ms) |
| 4 | low 16 = `gap_min`, high 16 = `gap_max` |
| 5 | `gap_sum` (ms) |
| 6 | number of CDC transitions from not-full to full |
| 7 | flags: bit0 dropped words, bit1 aborted frames, bit2 filled up, bit3 stream alive, bit4 gaps calibrated |
| 8 | UDP packets received |
| 9 | valid bytes received |
| 23 | zoom state: ratio, step, manual/fit, direction |
| 30 | source arbitration: owner, mode, reason bits |
| 31 | source clocks: bit0 missing, bit1 slowed |

## 7 Serial commands

| Command | Purpose |
|---|---|
| `stat` | control state, frame counts, effect selection, geometry words |
| `temp` | XADC temperature, VCCINT, OSD encoding, GPIO readback |
| `link` / `link clr` | frame-gap statistics / clear `gap_*` |
| `src auto\|0\|1\|2` | auto, test card, ETH, SD |
| `pipe <nine bits>` / `pipe show` | nine-bit effect chain |
| `zoom on\|off\|auto\|<ratio>` | zoom breathing switch, automatic, manual ratio (`zoom 1` is a switch; `zoom 1.0` is a ratio) |
| `rot auto\|0\|1` / `rot speed 0..7` | automatic rotation / degrees per frame |
| `split screen\|video` / `split <0..100>` / `split swap\|follow\|marker` | seam |
| `gamma <1.00..3.00>\|off\|auto` | gamma |
| `osd on\|off` | OSD |
| `sd files` / `sd file n` / `play` / `stop` | pick and play SD content |
| `frame N` / `fill` / `autoplay` / `th` / `echo` | jump to frame, diagnostic frame, current-session autoplay flag, threshold, echo |

## 8 Video and network constants

| Item | Value |
|---|---|
| Source size / format | 512×300 / RGB565 |
| Display | 1024×600 @ 59.5 Hz |
| Display timing | H 1344 = 1024 + 44 + 88 + 188; V 625 = 600 + 3 + 6 + 16; 50 MHz pixel clock |
| Frame size | 307,200 bytes |
| UDP video input | 5001, payload ≤ 1392 B, first 4 B are the intra-frame offset |
| Telemetry output | 1234, 1 Hz, 32 B |
| Board address | 192.168.1.10 |
| PC address | 192.168.1.100 |
| Serial | COM6, 115200 8N1 |

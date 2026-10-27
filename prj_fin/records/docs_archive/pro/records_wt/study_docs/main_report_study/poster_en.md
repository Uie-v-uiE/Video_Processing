# AMD Finals One-Page Poster — content draft (English, no team information)

> 用途：§六 要求进入决赛的自主选题队伍按 **AMD 提供的 PPT 模板**交一页英文海报，
> **不含队伍信息**，A4 彩色打印。模板还没拿到，所以这里先把**内容与措辞**定稿：
> 拿到模板后逐格填入即可，不必再想一次"写什么"。
> 布局建议（16:9 一页）：左上标题 + 一行定位语 → 右上架构条 → 左中 4 个 novelty →
> 右中指标表（这张表就是全页的权重中心，评委的"性能与资源 20 分"看这里）→
> 底部两行：verification 一句话 + 工具/器件声明。
> 所有数字都出自 `data/metrics.csv`（当前那份报告 = **r97 构建**，且这一版已在 22:15 刷上板：
> `system.bit md5=ef03eea4886e` · `system.xsa md5=a50188e5f789` · `ps_app.elf md5=d0b07f84a068`）。
> 海报上不手抄任何数：改数只改这张表，然后重新生成 pptx。
> 这张表与 `build/timing_summary.rpt` / `utilization.rpt` /
> `power.rpt` 由 `node src/host/metric_recheck.mjs` 逐行对账（本轮判 9 行、红 0）。

## Title / one-line positioning

**Same-Frame Pixel-Level A/B Display: turning the picture itself into an instrument**
A Zynq-7020 SoC receives 512×300 video over GbE, SD card or its own generated pattern,
runs geometry and a nine-stage effect chain entirely in the PL, and shows 1024×600 HDMI
where everything left of an adjustable seam is the unprocessed frame and everything right
is the processed one — same read address, same clock cycle, same column.

## Pipeline (one-line blocks)

`RGMII → self-written UDP/IP/MAC receive chain → DDR frame buffers (ping-pong) →`
`geometry (zoom 0.25–2.00×; rotation with angle-driven auto-fit so the rotated frame always stays on panel;`
`bilinear interpolation on both the zoom and the rotation path) → 9-stage effect chain (15-cycle fixed) →`
`A/B seam mixer → OSD → HDMI/TMDS` , with a bare-metal PS control plane (a few hundred lines)
and a hardware link-health engine read out three ways: on screen, over JTAG, over serial.

## What is new (4 items, each falsifiable)

1. **The display is the measurement**: per-pixel A/B on one scanline; the seam can be fixed,
   swept, or pinned in image domain so it follows zoom/rotation.
2. **Health counted in hardware, not asserted in a report** — received / dropped / corrupt /
   CRC / frame-gap statistics, three independent read-outs, and a source arbiter whose state
   is machine-readable (`SRC:ETH|SD|TEST` on screen is the *actual* selected source).
3. **Bad frames are filtered, not tolerated**: triple commit gate (row bitmap ∧ byte budget ∧ no
   corrupt flag) plus a blanking-window-atomic copy with a watchdog — a torn update is
   discarded and the previous frame is kept. *(Scope: one bad frame cannot pass; two consecutive
   losses, tail-then-head, can still union two frames into one "complete" one — filed, fix pending.)*
4. **Reproducibility engineered, not claimed**: one command runs the gate suite (timing,
   resources, port widths, CDC pairs, document encoding/currency/line-citations) plus two
   full-frame testbenches **pinned by md5 to the RTL they checked**; every criterion must be
   able to turn red, and every fix has a mutation control that reddens exactly one criterion.

## Key metrics (from `data/metrics.csv`)

| Item | Value | Condition |
|---|---|---|
| Display pixel clock / panel | 50 MHz, 1024×600 @ 59.5 Hz | HDMI dual-window |
| End-to-end latency | 33.34 ms mean (min/avg/max 20/33.34/51 ms) | PC → screen, 30 fps paced |
| Frame-interval jitter | 33.33 ms mean (22/33.33/45 ms) | 30 fps, rate-limited |
| Ingress load, zero loss | 0 dropped, 0 corrupt in 9000 frames (300 s) | 15 MB/s, 512×300 RGB565 |
| Overload, not yet lossy | 116.7 fps (≈36 MB/s, 287 Mbps) still no lost word | unthrottled; no "max fps" claimed |
| SD playback rate | 29.8–30.0 fps | pre-converted RGB565 frame sequence |
| Setup WNS / hold WHS / failing endpoints | +0.720 / +0.033 ns / 0 of 50890 | post-route, board build r97 |
| Resources | LUT 14379 (27.03 %) · FF 8079 (7.59 %) · BRAM 95/140 (67.86 %) · DSP 19/220 | same build |
| Dynamic power / junction temp | 2.207 W / 52.5 °C (tool estimate, confidence: Low) | same build |
| On-die temperature, measured | 63.1 – 63.4 °C (XADC; serial `temp`, OSD cell, GPIO bit all agree) | same board, SD playback running |

## Honest boundaries (say them before being asked)

Absolute WNS/WHS deltas are neither gain nor loss here — equivalent sources measured a 0.4 ns placement swing
between builds. One per-pixel criterion is left deliberately red, documenting an unfixed
frame-head wrap-around. On the rotation path the decision "does this pixel need a borrowed row?"
reads only the high byte of a 16-bit remainder, so at oblique angles a small share of pixels
(≈0.4 % in a full-frame recomputation) samples the neighbouring source row instead of the intended
one (filed; the fix and its testbench criterion are scheduled). Only xsim is available, so simulation-only divergences
(out-of-array writes) are closed out with on-board evidence. End-to-end figures are one
round's measurement, not a fleet.

**Tool chain**: Vivado / Vitis 2025.2.1 · device `xc7z020clg484-2` · sources on GitHub
(MIT) · every number above names the report file it came from.

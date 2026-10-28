# Limits and unfixed items

This list records the boundaries that still stand. Fixed problems are not repeated, and nothing unmeasured is written as "should be fine".

## 1 Physical and timing boundaries

**RGMII transmit hold gap.** On this board every RGMII pin sits in an HR bank, which has no ODELAYE2. Forwarding at 0° still leaves about 0.845 ns of TskewT hold margin missing. A 90° phase breaks the link; −45° reduces the gap to 0.366 ns but drops ping to 1 in 6, so both were withdrawn. The production bitstream forwards at 0° and clocks through ODDR, and long ping runs on the board stay clean. The gap follows from the pinout and the bank type; no amount of RTL editing removes it.

**Reset recovery path.** The worst WNS of 1.341 ns comes from the reset-recovery check on `phy_rst_cnt_reg[23] → rst_lm_sync2_reg/CLR`, not from an ordinary data path. Pushing it further means converting the asynchronous resets in several protocol blocks to synchronous resets, or splitting the reset into per-region copies. The first changes reset semantics; the second adds new placement constraints. Neither is done.

**Hold margin.** The worst WHS is 0.025 ns on `u_blur/dout_reg[15] → u_sharp/q22_reg[15]` in the pixel domain, of which 0.346 ns is clock skew. It is positive, but improving it means restructuring the port interfaces, and the risk does not match the gain.

**RGMII input window and HDMI source window.** Both candidate constraint files stay in the repository but are not loaded by default. The RGMII input window cannot be closed inside the legal IDELAY range and turns five I/O endpoints red when loaded; the negative numbers in the HDMI source window came from a unit-scale mistake, not from design debt. Neither is in the production bitstream; both are kept as documented boundaries.

## 2 Resources and frame size

**BRAM at 70%.** Of the 98 BRAM tiles, about 80 hold the full-frame display buffer needed by rotation and bilinear interpolation, 1.5 form the two-row ring for the seam `sx`, about 10 are the asynchronous FIFO in the DDR write direction, and the rest are effect-chain and OSD line buffers. The distribution follows from the geometry scheme; it is not scattered waste.

**No 1080p.** The 512×300 full-frame buffer already takes 70%; 1024×600 needs roughly four times the storage and does not fit. Replacing the full-frame buffer with DDR line buffers or tile processing would cut BRAM but brings new bandwidth and timing problems — an architectural change. The design claims neither 1080p nor a "higher resolution" that a zoom switch cannot deliver.

**Single input.** Only one 512×300 network stream, one SD playback path and the PL test card are verified. Simultaneous inputs, compressed streams and higher frame rates are not.

## 3 What "latency" means here

**Telemetry latency covers the PL only.** It runs from frame commit to the start of scan and includes waiting for blanking and the DDR transfer. Encoding, cable and switch queuing are not included. It is not glass-to-glass latency and must not be described as end-to-end.

**Latency resolution is one frame.** Readings carry ±1 frame of quantisation. After the stream stops, the latency field becomes invalid instead of repeating an old value.

**Frame-gap saturation.** `gap_cnt` is a 17-bit millisecond counter that saturates at `0xFFFF` instead of wrapping, so a maximum is never polluted by a wrap; gaps beyond 65.5 s can only be read as the saturated value.

## 4 Human-eye checks

**HDMI picture.** The 185° thin-line case is closed in RTL and on the bench, with a processed-pane integrity count of 0. E1–E5 (same frame left and right, matching geometry, OSD agreeing with the serial port, days of continuous running, recovery after ETH/SD hot-plug) have been checked on the bench with nothing abnormal seen. Cable quality and panel colour remain subjective.

**Stale rows at the top.** The read side fetches rows ahead, so the first few rows of a frame can be one frame older than the rest of the screen. No offline check can measure this; only a viewer can decide whether it is acceptable. It is not the bottom-edge line from earlier rounds.

## 5 Tools and environment

**Vitis application components.** `create_app_component` in Vitis 2025.2.1 returns `StatusCode.INTERNAL` on this platform, so the application component cannot be created. The PS application does not depend on the IDE; `scripts/ps/build_ps_app.py` compiles it directly. The platform FSBL and BSP rebuild normally.

**Vivado output products.** `hw/vivado/zynq_video_sys.xpr` carries the sources, constraints and block design, but the `.gen/` output products are not committed. If Vivado reports them missing after opening the project, run the `bd_only` flow once or a full build.

**Power and junction temperature.** The Vivado report gives 2.228 W dynamic, 2.406 W total and 52.8 °C junction without a simulation activity file; confidence is low, so the numbers are order-of-magnitude only. The on-chip XADC reads 61.8–63.8 °C under continuous streaming, which is a measurement. The two must not be mixed.

**Porting.** The IDELAY, BUFIO and ODDR usages are bound to 7-series devices, and the AXI GPIO control plane is bound to the current PS configuration. Moving to UltraScale+ or another board requires re-verifying these items rather than copying them.

## 6 Functional boundaries

- No PYNQ overlay. The PS side is bare-metal standalone and the host tools are Python/Node; nothing here claims PYNQ credit.
- No end-to-end latency, encoder delay or network-queue measurements.
- No multi-stream compositing, compressed streams, audio or recording.
- No secure boot, encrypted bitstream or remote update.
- SD playback accepts only pre-converted frame sequences on FAT32, not arbitrary containers; conversion happens on the host.
- Auto-rotation offers speeds of 0–7° per frame but no absolute angle target; absolute angles come from the ±1° keys.

These boundaries do not affect the current demonstration, but they should be stated on site and before deployment, so that "not verified" is never presented as "supported".

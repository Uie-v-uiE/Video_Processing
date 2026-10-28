# Timing and resource optimisation

The goal was never a larger WNS number. It was to move the worst path from "long because of the structure" to "short, as the structure allows", without damaging function, resources or reproducibility. Each round changed one class of thing, then compared against the same regression, the same implementation reports and the same per-clock register.

## 1 State before optimisation

Global WNS was 1.029 ns, with the worst path on the processed-pane bus crossing from the 50 MHz pixel domain into the 125 MHz Ethernet domain. That bus spans two independent MMCMs, so the tool applies a 4 ns setup requirement derived from the shared primary clock — a requirement with no phase boundary anyone can sign off. The design never relies on that 4 ns: the source side holds the value for a whole beat and the destination side samples it on a synchronised toggle, so the bus stays stable for at least one frame.

At the same time, `owner_eth` in the AXI domain had a fan-out of 234, driving address, data and control muxes in the frame mover. The ICMP checksum and the UDP transmit checksum each formed long combinational paths in the 125 MHz domain. The reset tree `rst_l_sync2` drove 3002 asynchronous clear pins and later became the source of the worst path.

## 2 Five rounds

| Round | Change | Observation | Kept? |
|---|---|---|---|
| 1 | Move protocol logic off the PHY-recovered clock; leave only IDDR sampling and the async-FIFO write side on it | Shorter paths in that domain, a clean crossing boundary | Yes |
| 2 | Add `set_max_delay -datapath_only 10 ns` on the processed-pane bus to bound bit-to-bit skew | The 1.029 ns path disappears; 8.7 ns margin | Yes |
| 3 | Add `max_fanout` on `owner_eth` so synthesis replicates it | AXI domain 1.201 → 2.159 ns, cost 8 flip-flops | Yes |
| 4 | Register `stat_bad` into a single bit; split the second-beat ICMP checksum from 6 terms into 4+3 | Ethernet logic domain 1.245 → 1.727 ns | Yes |
| 5 | Split the IPv4 header checksum in UDP transmit from 10 terms in one beat into 4 beats: 5+5+fold+fold | Global WNS 1.172 → 1.341 ns, cost 38 LUTs and 12 FFs | Yes |

The final result is WNS 1.341 ns, WHS 0.025 ns, TNS = THS = 0, zero failing endpoints. The worst path is back on reset recovery — `phy_rst_cnt_reg[23] → rst_lm_sync2_reg/CLR`, data path 1.927 ns of which 1.443 ns is routing. The worst hold is in the pixel domain, `u_blur/dout_reg[15] → u_sharp/q22_reg[15]`: 0.428 ns data, 0.346 ns of it clock skew, 0.025 ns margin. Positive, but thin.

## 3 Per clock

| Clock | Period | WNS | WHS | Note |
|---|---:|---:|---:|---|
| `sys_clk` | 20 ns | 14.797 ns | 0.067 ns | 50 MHz board input |
| `clkout0_1` | 20 ns | 3.264 ns | 0.025 ns | pixel and algorithm domain |
| `eth_rxc` | 8 ns | 3.247 ns | 0.071 ns | PHY-recovered clock, sampling and FIFO write only |
| `clk_fpga_0` | 10 ns | 2.159 ns | 0.060 ns | PS FCLK0, AXI and DDR write side |
| `clkout3` | 8 ns | 1.727 ns | 0.068 ns | Ethernet protocol logic |

The global 1.341 ns is lower than every per-clock setup margin because it comes from a reset-recovery check, which is not part of the ordinary setup table. Reading timing means reading both tables: the global line alone, or the smallest per-clock number alone, gives the wrong conclusion.

## 4 Reset tree

The 3002 asynchronous clear pins on `rst_l_sync2` are one of the largest fan-outs in the design. Three options were tried:

1. `max_fanout` on `rst_l_sync2`: synthesis did not replicate, flip-flop count unchanged, WNS unchanged.
2. Route the reset through a BUFG: WNS dropped from 1.104 to 1.078 ns. Withdrawn.
3. Replicate the link-monitor's local reset tree: WNS rose from 1.104 to 1.172 ns. Kept.

The lesson is that "high fan-out, therefore put it on a global buffer" does not hold. The reset-recovery path is limited by the physical distance from CLR to the register and by the recovery check, not by clock-network quality. Going further means converting several protocol blocks to synchronous reset, which changes semantics, or splitting the reset into per-region copies, which adds placement constraints. The design stops here and documents the boundary.

## 5 Rejected attempts

| Attempt | Expected | Measured | Verdict |
|---|---|---|---|
| post-route `phys_opt` (AggressiveExplore) | squeeze setup further | bit-identical WNS to the default flow | not adopted |
| standalone `phys_opt_design -hold_fix` | improve hold | WHS unchanged | not adopted |
| local reset synchronisers for ARP/ICMP | bring the CLR tree closer | post-route WNS 0.920 ns, worse than before | withdrawn, kept as a counter-example |
| lower `max_fanout` on `rst_l_sync2` from 32 to 8 | reduce fan-out | WNS 1.316 ns, only 12 ps of hold gained | rejected |
| 4 ms idle timeout in frame reassembly | stop mixed-frame commits | bench green, but WNS 0.986 ns | rejected (unprescaled timer sat on the byte/row path) |
| 32-bit `last_hdr` compare in frame reassembly | fix mixed frames | regression passed, WNS 1.293 ns | rejected; the current placement is sensitive to the clear cone |

The value of these attempts is not that they failed — it is that they mark the boundary. On this placement, touching the clear cone of `frame_reasm` costs far more than the few logic levels involved, and pushing reset recovery further has a poor risk-to-gain ratio.

A9 was finally solved in another shape: a 4 ms idle timer with a 12-bit prescaler, where `idle_clear` drives a single bit into the header clear cone and the counter never sits on the byte/row path. The A9 section of `tb_udp_reasm` drops the tail of one frame and the head of the next, with more than 4 ms of silence between them; the check requires the two frames not to mix and the third frame after recovery to commit cleanly. Final WNS 1.341 ns.

## 6 Resource account

| Resource | Used | Share | Where it goes |
|---|---:|---:|---|
| LUT | 14,967 | 28.13% | protocol stack, geometry, effects, OSD |
| FF | 9,095 | 8.55% | pipelines, counters, synchronisers |
| BRAM | 98 tiles | 70.00% | mostly the full-frame buffer |
| DSP48 | 19 | 8.64% | coordinates, interpolation, window arithmetic |

BRAM is the tightest resource. Of the 98 tiles, about 80 hold the full-frame display buffer for rotation and bilinear interpolation, 1.5 form the two-row seam ring, about 10 are the DDR write FIFO, and the rest are effect and OSD line buffers. This is the direct cost of the geometry scheme, not scattered waste. Moving to DDR line buffers or tiling would cut BRAM but adds bandwidth and timing problems — architectural work that does not pay off at this frame size.

The 19 DSPs also add up: `u_lerp` 6, `u_blur` 1, `u_split_ctrl` 1, `u_zfit` 3, `u_zmap` 8. Gamma is a LUTRAM table and uses none, which corrects the intuition that the effect chain eats DSPs.

## 7 Power and temperature

Vivado reports 2.228 W dynamic, 2.406 W total and 52.8 °C junction with no simulation activity file. Confidence is low; treat it as an order of magnitude. The on-chip XADC reads 61.8–63.8 °C during continuous streaming with `sane=1`, which is a measurement. The two must not be quoted interchangeably.

## 8 Physical boundary

The RGMII TskewT specification is ±0.5 ns. This board's RGMII pins sit in an HR bank without ODELAYE2, so 0° forwarding still leaves about 0.845 ns of hold margin missing. A 90° phase breaks the link; −45° cuts the gap to 0.366 ns but drops ping to 1 in 6; both were withdrawn. Production forwards at 0° with the clock through ODDR, and long ping runs stay clean. The gap comes from the pinout and the bank type — a physical boundary, not timing debt that RTL can remove.

## 9 Conclusion

The optimisation has removed the long paths that structure could remove: the processed-pane bus, the arbiter fan-out, the ICMP and UDP checksums, the local reset trees. What remains is reset recovery, which needs a change of reset semantics to improve; a 0.025 ns hold margin, which needs restructured ports; and BRAM at 70%, which is dictated by the full-frame buffer. The current version stops at these three boundaries, with real numbers and a clear account of the cost.

# Sources

`src/` holds the PL sources, the PS bare-metal application, the constraints and the PC-side tools.

| Directory | Content | Entry point |
|---|---|---|
| `src/rtl/` | Verilog: top, Ethernet, display, geometry, effects, AXI, clocks, HDMI | `src/rtl/README.md` |
| `src/ps/` | PS bare metal: `main.c`, `sd_play.c`, linker script | `src/ps/README.md` |
| `src/constraints/` | pins, clock groups, quasi-static CDC, candidate IO windows | `rk_zynq7020.xdc` is the main constraint |
| `src/host/` | host-side streaming, telemetry, dashboard, self-test, serial checks | `src/host/README.md` |

## Reading order

1. Start with the system diagram and clock domains in `docs/design-report.md`, then the RTL top.
2. To follow pixels: `src/rtl/top/pl_video_top.v` -> `video/` -> `process/zoom/` -> `process/bilin/` -> `process/proc_pipeline.v` -> `video/split_display.v` -> `video/osd_overlay.v`.
3. To follow packets: `src/rtl/eth/eth_udp_video_top.v` -> `rgmii_rx.v` -> `gmii_rx_mac.v` -> `udp_rx_parser.v` -> `frame_reasm.v` -> `dc_fifo.v` -> `axi_frame_saver64.v`.
4. To follow control: `dispatch` in `src/ps/main.c` -> AXI GPIO -> the three-stage synchroniser chain in `pl_video_top`.

## Build and simulate

```bash
vivado -mode batch -source scripts/build.tcl
bash scripts/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
```

Build and bench details are in `scripts/README.md` and `sim/README.md`.

# 源码

`src/` 放 PL 源码、PS 裸机、约束和 PC 侧工具。

| 目录 | 内容 | 入口 |
|---|---|---|
| `src/rtl/` | Verilog：顶层、以太网、显示、几何、效果、AXI、时钟、HDMI | `src/rtl/README.md` |
| `src/ps/` | PS 裸机：`main.c`、`sd_play.c`、链接脚本 | `src/ps/README.md` |
| `src/constraints/` | 引脚、时钟组、准静态 CDC、候选 IO 窗 | `rk_zynq7020.xdc` 是主约束 |
| `src/host/` | PC 侧推流、遥测、仪表、自检、串口判据 | `src/host/README.md` |

## 阅读顺序

1. 先读 `report/design-report.md` 的系统图和时钟域，再看 RTL 顶层。
2. 想跟像素走：`src/rtl/top/pl_video_top.v` → `video/` → `process/zoom/` → `process/bilin/` → `process/proc_pipeline.v` → `video/split_display.v` → `video/osd_overlay.v`。
3. 想跟网络走：`src/rtl/eth/eth_udp_video_top.v` → `rgmii_rx.v` → `gmii_rx_mac.v` → `udp_rx_parser.v` → `frame_reasm.v` → `dc_fifo.v` → `axi_frame_saver64.v`。
4. 想跟控制走：`src/ps/main.c` 的 `dispatch` → AXI GPIO → `pl_video_top` 的三级同步链。

## 构建与仿真

```bash
vivado -mode batch -source build/build.tcl
bash build/sim/run_msim.sh rows udp_reasm reasm_bounds udp_telemetry \
     eth_ctrl_arb eth_top_rgmii split_ctrl osd_overlay link_monitor
```

工程与台架的详细说明在 `build/README.md`、`sim/README.md`。

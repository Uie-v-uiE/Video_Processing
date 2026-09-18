# Project Skill: Zynq7020 Ethernet Video Pipeline (0–359° rotate)

## When to use
User works in `zynq_video_pipeline` or asks about RK-ZYNQ7020-F video/HDMI/UDP/rotate.

## Board & tools
- RK-ZYNQ7020-F, `xc7z020clg484-2`
- Vivado/Vitis **2025.2.1** at `D:\Software\Vivado\2025.2.1\`

## Canonical paths
| Item | Path |
|------|------|
| Root | `D:\Software\Xiaomi_MiMo\video\zynq_video_pipeline` |
| Overview | `docs/PROJECT.md` |
| Module docs | `docs/modules/*.md` |
| PL demo top | `rtl/top/pl_demo_top.v` |
| System top | `rtl/top/system_top.v` |
| Create project | `tcl/create_project.tcl` (`pl`/`system`) |
| Synth smoke | `tcl/synth_pl_only.tcl` |
| Build bit | `tcl/build_bitstream.tcl` |
| Program | `tcl/program_board.tcl` |
| Sim | `sim/run_sim.tcl` |
| Golden model | `scripts/golden_model.py` → `sim_out/` |
| Host UDP | `sw/host/video_sender.py` |
| Host UART | `sw/host/serial_ctrl.py` |
| PS app | `sw/ps/main.c` |

## Effect map (left char = bit0)
`gray binary blur sobel invert`
`00111` → 5'b11100 → blur+sobel+invert

## Rotation
- 0–359°, KEY1 +1°, KEY2 −1°
- Q8 sin/cos ROM, center + Y-flip math matching reference Image_Rotate
- Window filters auto-bypass when angle≠0

## Bring-up order
1. `pl` bitstream (colorbar HDMI)
2. Keys rotate
3. `system` + PS elf + UDP frames

## Do not
- Don't change HDMI pins without updating XDC
- Don't use PL Ethernet PHY2 unless asked (PS GEM0 default)
- Don't clamp cos_q8 to 255 — cos(0)=256

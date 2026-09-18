# Board bring-up

See also `report/ETH_BRINGUP.md` and `report/BOARD_PINS.md`.

## Hardware

- Power 12 V, HDMI monitor **1024×600**, USB-C (JTAG + UART)
- Ethernet cable → **PL ETH** (PHY2), not the PS port
- PC NIC: `192.168.1.100/24`

## Order

1. `build/tcl/build_system_axigpio.tcl` → `build/system.bit`
2. `build/tcl/program_system.tcl`
3. Vitis Run `src/ps/main.c` (UART)
4. `ping 192.168.1.10`
5. `src/host/run_sender.bat`

## Expected

- HDMI: dual-pane video + OSD (`FPS=` / `ANG=` / `EN=`)
- Ping replies from `192.168.1.10`
- Moving video; mild ghosting possible (see `report/ISSUES.md`)

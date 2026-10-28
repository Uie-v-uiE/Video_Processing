# Hardware setup

## 1 Board and connectors

| Connector | Connects to | Notes |
|---|---|---|
| 12 V DC | on-board jack | main supply; confirm HDMI, Ethernet and SD are seated before power-up |
| USB-C | PC USB-A | on-board FT4232: channel A is JTAG, channel B is UART (COM6) |
| HDMI OUT | 1024x600 panel | board to panel, one direction |
| RJ45 | PC wired NIC | PL-side PHY (RTL8211F-CG), not the PS port |
| microSD | on-board slot | FAT32, holds the pre-converted frame sequence |
| KEY1 / KEY2 | on-board keys | source select / angle plus or minus one degree |

## 2 Network

| Item | Value |
|---|---|
| Board IP | `192.168.1.10/24` |
| PC wired NIC | `192.168.1.100/24` |
| Video input | UDP 5001 |
| Telemetry output | UDP 1234 |
| Link | direct gigabit; disable NIC power saving and jumbo frames |

Ping `192.168.1.10` before streaming. The reply comes from the PL ICMP responder, so a successful ping checks both the bitstream and the PHY.

## 3 Serial

| Item | Value |
|---|---|
| Port | COM6 (FT4232 channel B) |
| Baud | 115200 |
| Data / parity / stop | 8 / None / 1 |
| Flow control | none |

Only one program may own COM6. The Vitis serial terminal echoes locally; if every character appears twice, run `echo 0`.

## 4 Clocks and reset

| Clock | Source | Use |
|---|---|---|
| `sys_clk` 50 MHz | board oscillator W17 (20 ns constraint) | MMCM and PS reference |
| `clkout0_1` 50 MHz | PL MMCM | pixel, geometry, effect chain |
| `clkout3` 125 MHz | PL MMCM | Ethernet protocol logic |
| `eth_rxc` 125 MHz | PHY-recovered clock | IDDR sampling and async-FIFO write |
| `clk_fpga_0` 100 MHz | PS FCLK0 | AXI control and DDR write side |

Resets assert asynchronously and release synchronously in each domain. The PS reset is driven by `ps7_init` and JTAG `rst -system`; the PL reset by the board key and the internal synchroniser chain.

## 5 Power-up order

1. Seat HDMI, Ethernet and the SD card.
2. Connect USB-C to the PC.
3. Apply 12 V.
4. Wait for boot messages on serial.
5. `ping 192.168.1.10`.
6. Run the JTAG three-step chain only when debugging.

## 6 Power-down and recovery

- Power down before changing DIP switches, the SD card or the Ethernet cable.
- On `Cannot halt processor core`, power off for ten seconds and power up again; repeated `rst -system` makes it worse.
- Confirm the boot mode is set to QSPI before writing, and verify after a power cycle.
- Do not erase the boot medium without a backup; the current QSPI image can be regenerated from `BOOT.bin`.

## 7 Safety boundaries

- QSPI erase is irreversible; confirm the image and the switch position first.
- Do not write the FT4232 EEPROM; changing the USB serial number makes hw_server target the wrong device.
- Do not connect 5 V devices directly to 3.3 V PL I/O.
- Power down before plugging or unplugging HDMI to avoid hot-plug surges.

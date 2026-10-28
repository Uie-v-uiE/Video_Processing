# Device, toolchain and third-party declarations

## 1 Device and board

| Item | Value |
|---|---|
| FPGA | `xc7z020clg484-2` (Zynq-7020, −2 speed grade) |
| Board | `RK-ZYNQ7020-F` |
| External memory | on-board DDR3, QSPI NOR, microSD |
| Network | PL-side RJ45, RTL811F-CG |
| Display | HDMI, 1024×600 panel |

## 2 Toolchain

| Tool | Version / use |
|---|---|
| Vivado | 2025.2.1 — synthesis, implementation, bitstream, XSA, timing/resource/CDC/power reports |
| Vitis | 2025.2.1 — platform and FSBL build; the PS application is also compiled by script |
| Simulation | Vivado xsim; ModelSim as an optional faster regression |
| Host | Python 3 (standard library), Node.js 18+, PowerShell 5+ |
| Optional | ffmpeg, only to decode mp4 into raw frames; the built-in test pattern needs nothing |

Every timing, resource and power number was measured with the tool versions above on `xc7z020clg484-2`. A different tool version or device requires a rerun; the numbers do not carry over.

## 3 Third-party and in-house boundary

- Xilinx supplies the PS7, AXI GPIO and AXI HP IP blocks and the Vitis runtime; copyright stays with their owners.
- The RTL video path, the Ethernet stack, the PS bare-metal firmware and the host-side streaming, telemetry and self-test tools are written for this project. No third-party video-processing IP is used.
- The PHY and AXI slave models used in simulation live in `sim/prim/`. They are project test models and are not claimed to be vendor models.
- This project does not use PYNQ.
- Readings specific to this project come from `hw/reports/` and `hw/measured/`, not from general framework advice.

## 4 Where the deliverables come from

- `hw/project/system.bit`, `system.xsa` and `ps_app.elf` are produced by `scripts/build.tcl`, `scripts/vitis/rebuild_vitis.py` and `scripts/ps/build_ps_app.py`.
- `hw/flash/BOOT.bin` is packaged by `hw/scripts/make_boot_image.sh` from the in-repo FSBL, bitstream and application; the three MD5 sums are in `boot_manifest.txt`.
- `hw/vivado` is the project generated and staged by the build scripts. `hw/vitis` is the platform descriptor; the actual platform is rebuilt by `scripts/vitis/rebuild_vitis.py`.
- The source of the design document is `docs/design-report.md`; typeset copies are rendered from it.

## 5 Reproduction environment

- Network: PC `192.168.1.100/24`, board `192.168.1.10/24`; video on `UDP 5001`, telemetry on `UDP 1234`.
- Serial: `COM6` on this machine, 115200 8N1.
- Tool locations are passed through environment variables — `VP_VIVADO_BIN`, `VP_XSDB`, `VP_VITIS_WS`, `PS_CC`, `PS_BSP`, `MSIM_BIN` — so no script hardcodes a local path.
- Tool versions, device and board are fixed on this page and in the README; every other document refers to the same values.

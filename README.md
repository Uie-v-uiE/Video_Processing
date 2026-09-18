# Zynq7020 Ethernet Video Pipeline

UDP video sink and real-time image pipeline on Zynq-7000 (XC7Z020).

A host PC streams **512×300 RGB565** frames over UDP. The **PL** implements RGMII, ARP/ICMP/UDP, offset-based frame reassembly, image effects, rotation, seamless zoom, and HDMI dual-pane output. The **PS** is control-only (UART + AXI GPIO).

| Item | Value |
|------|--------|
| Board | RK-ZYNQ7020-F (XC7Z020-CLG484-2) |
| Tools | Vivado / Vitis 2025.2.1 |
| Source | 512×300 RGB565 |
| Display | HDMI 1024×600 @ 50 MHz (left original / right processed + zoom) |
| Network | Board PL `192.168.1.10:5001`, PC `192.168.1.100` |
| Control | AXI GPIO `@0x41200000`, UART 115200 |
| License | MIT |

## Features

- PL hardware network stack: RGMII → ARP/ICMP/UDP → frame buffer
- Offset UDP protocol: out-of-order packets reassemble; bad frames dropped
- Effects: gray / binary / box blur / Sobel / invert (serial-controlled)
- Arbitrary-angle rotation (Q8 sin/cos inverse mapping)
- Right-pane seamless zoom loop (original size as maximum → shrink → restore)
- Source select: colorbar or ETH/DDR video
- Host tools: UDP sender + serial console

## Repository layout

```
├── src/
│   ├── rtl/           Verilog (top, eth, video, process, axi, hdmi)
│   ├── ps/            Bare-metal UART + GPIO control
│   ├── host/          UDP sender and serial tools
│   └── constraints/   Pin and timing constraints
├── sim/               Testbenches and simulation TCL
├── build/
│   ├── tcl/           Reproducible Vivado build / program scripts
│   ├── system.bit     Bitstream
│   ├── system.xsa     Hardware platform for Vitis
│   └── *.rpt          Timing / utilization / power reports
├── board/             Board bring-up notes
├── data/golden/       Reference images
├── skill/             Reusable engineering notes
└── report/            Architecture and implementation reports
```

## Quick start

### 1. Build bitstream and XSA

```bat
cd /d <repo_root>
set VIVADO=D:\Software\Vivado\2025.2.1\Vivado\bin\vivado.bat
%VIVADO% -mode batch -source build\tcl\build_system_axigpio.tcl
```

Outputs: `build/system.bit`, `build/system.xsa`

### 2. Program bitstream

```bat
%VIVADO% -mode batch -source build\tcl\program_system.tcl
```

### 3. (Optional) Program PS ELF for serial commands

1. Open workspace in Vitis, platform = `build/system.xsa`
2. Application source: `src/ps/main.c`
3. Build → Run

> Programming the bitstream resets the PS; run the ELF again for UART.
> Right-pane auto-zoom works after bit download alone.

### 4. Simulation

```bat
%VIVADO% -mode batch -source sim\run_sim.tcl
```

### 5. Host streaming

```bat
pip install -r src\host\requirements.txt
cd src\host
run_sender.bat
run_video.bat D:\path\to\video.mp4
```

PC NIC: `192.168.1.100/24`, cable to the **PL** Ethernet port.
See `src/host/HOST_GUIDE.md` for details.

## Serial commands (115200 8N1, CR+LF)

| Command | Action |
|---------|--------|
| `00000` | All effects off |
| `10000` | Grayscale |
| `01000` | Binarize |
| `00111` | Blur + Sobel + invert |
| `SRC0` / `SRC1` | Colorbar / video source |
| `TH80` | Binarize threshold |
| `ZOOM0` / `ZOOM1` | Zoom off/on (PL defaults on) |
| `FILL` / `STAT` | Diagnostics |

Effect bits: **gray / binary / blur / sobel / invert** (bit0 = leftmost).
ETH auto-switches to video after a complete frame.

## UDP protocol

```
[u32 LE byte_offset][RGB565 payload]
Frame: 512×300×2 = 307200 bytes
Payload per datagram: ≤1396 bytes
```

Board writes by offset into the frame buffer; out-of-order is OK; lost packets are dropped.

## Documentation

| Path | Content |
|------|---------|
| [src/host/HOST_GUIDE.md](src/host/HOST_GUIDE.md) | Host software guide |
| [report/ARCHITECTURE.md](report/ARCHITECTURE.md) | Datapath, clocks, bandwidth |
| [report/MODULES.md](report/MODULES.md) | Module overview |
| [report/OPTIMIZATION_LOG.md](report/OPTIMIZATION_LOG.md) | Timing / power optimization notes |

## Design notes

- **PL UDP offload**: deterministic latency; PS stays free for control
- **Single BRAM frame buffer**: ~2.34 Mb; dual buffer does not fit XC7Z020
- **Zoom**: inverse mapping with continuous `inv_scale` (Q8); effects run on the right-pane zoomed stream
- **Timing**: async clock groups + FIFO mapped to BRAM; see optimization log

## License

MIT — see [LICENSE](LICENSE).

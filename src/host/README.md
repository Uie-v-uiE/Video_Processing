# Host tools

`src/host/` holds the PC-side tools: streaming, telemetry, dashboard, self-test, serial checks and JTAG readback. Board firmware is in `src/ps/`, RTL in `src/rtl/`.

## Dependencies

- Python 3.10+ with the standard library only (`argparse`, `socket`, `struct`, `subprocess`); pyserial is not needed.
- Node.js 18+ with built-in modules only (`node:dgram`, `node:child_process`); no third-party packages.
- JTAG readback needs Vitis `xsdb`, passed through `VP_XSDB` or `--xsdb`.
- The serial command check calls `hw/scripts/uart_cmd_script.ps1`, which needs PowerShell and a free COM6.

## Streaming

```bash
python src/host/video_sender.py --demo --seconds 8
python src/host/video_sender.py --input clip.mp4
python src/host/udp_push.py --pattern edge --fps 15 --drop-every 100
```

- Target board `192.168.1.10`, UDP 5001; source fixed at 512x300 RGB565.
- At most 1392 bytes per packet, with the first four bytes carrying the intra-frame offset.
- `--demo` needs no ffmpeg; `--input` does.
- `udp_push.py --drop-every 100` injects faults by dropping one packet in 100.

## Telemetry and dashboard

```bash
python src/host/telemetry_listen.py 13
python src/host/instrument_dashboard.py
```

- Telemetry leaves UDP 1234 at 1 Hz, 32 bytes, addressed to the last ARP requester.
- Ping `192.168.1.10` once before listening, and allow UDP 1234 through Windows Firewall.
- Fields: frames, packets, bad packets, aborts, missing rows, PL-internal latency and processed-pane integrity.

## Self-test

```bash
python src/host/link_selftest.py 192.168.1.10 6
```

Three stages: clean, one packet in 100 dropped, clean again. The checks use per-second deltas:

- clean: at least 8 fps, at most the single boot-time abort, at least one valid latency of 200 ms or less;
- fault: at least 5 aborts/s, under 5 fps;
- recovery: back to clean level.

The last line is `PASS link_selftest` or the stage that failed.

## Serial checks

```bash
node src/host/uart_cmd_check.mjs --port COM6
```

105 commands are compared against their replies and the final state must equal the initial state. The command list is `hw/scripts/cmd_battery_v81.txt`, sent through `hw/scripts/uart_cmd_script.ps1`.

## JTAG readback

```bash
node src/host/health_read.mjs --gpio0 41200000 --gpio1 41210000
node src/host/health_read.mjs --gapclr
```

- Reads the ten PL lanes over AXI GPIO: dropped words, bad packets and aborts, stall, frame gaps, CDC, flags, packet and byte counts.
- `--gapclr` clears the frame-gap statistics (lane 3/4/5) before reading.
- Requires `VP_XSDB` pointing at `xsdb.bat` and hw_server on `localhost:3121`.

## Geometry and metrics

```bash
node src/host/geom_check.mjs
node src/host/metrics.mjs --out hw/evidence --tag clean30
node src/host/metric_recheck.mjs
```

- `geom_check.mjs` checks the last hop of the geometry path: command -> CFG_DATA0 -> lane 23.
- `metrics.mjs` collects frame rate, packet rate, aborts, latency and frame gaps.
- `metric_recheck.mjs` reconciles the numbers in `data/metrics.csv` against the implementation reports.

## One-shot test

```bash
python src/host/one_click_test.py
node src/host/one_click_test.mjs
```

Four steps: ping, connect, send, collect. Each ends with `PASS`, `FAIL` or `NOT_MEASURED`, and the last line is the `ONE-CLICK` summary. Without a board, add `--dry-run` and nothing touches the network or the hardware.

## Options

| Option | Meaning | Default |
|---|---|---|
| `--ip` | board address | `192.168.1.10` |
| `--port` | UDP target port | `5001` |
| `--fps` | stream frame rate | 30 |
| `--pace-mbps` | send rate limit in MB/s, 0 = unlimited | 20 |
| `--gpio0` / `--gpio1` | AXI GPIO base addresses | `41200000` / `41210000` |
| `--xsdb` | xsdb executable | `VP_XSDB` |
| `--dry-run` | print the plan only; no ping, no board, no packets | off |

#!/usr/bin/env python3
"""Listen for the PL UDP telemetry beacon (port 1234, 32-byte payload).

The board sends to the last ARP requester's MAC/IP. Run this script, then make the
PC send one ARP/ping to the board (clear the ARP cache first if needed), and the
beacon will arrive once per second.

Payload (little-endian):
  0..3 "VDEO", 4 version, 5 flags(bit0 link), 6..9 frames, 10..13 pkts,
  14..17 bad, 18..19 rows_missed, 20..23 tick, 28..29 UDP sport.
"""
import socket
import struct
import sys
import time

PORT = 1234

# 总时长（秒），不是空闲超时：信标 1 Hz 到来，空闲超时永远不会触发。
DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 15.0
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", PORT))
s.settimeout(0.5)
print(f"listening udp/{PORT} for {DUR:g}s ...", flush=True)
deadline = time.monotonic() + DUR
nbeacon = 0
while time.monotonic() < deadline:
    try:
        data, addr = s.recvfrom(2048)
    except socket.timeout:
        continue
    if len(data) < 30 or data[0:4] != b"VDEO":
        print(f"{addr} non-beacon {len(data)}B {data.hex()}", flush=True)
        continue
    nbeacon += 1
    ver = data[4]
    flags = data[5]
    frames, pkts, bad = struct.unpack_from("<III", data, 6)
    rows = struct.unpack_from("<H", data, 18)[0]
    aborts = struct.unpack_from("<H", data, 24)[0]
    lat_ms = struct.unpack_from("<H", data, 26)[0]
    pane_bad = data[31]
    pane_ok = (data[30] >> 1) & 1
    lat_ok = data[30] & 1
    tick = int.from_bytes(data[20:24], "little")
    sport = struct.unpack_from("<H", data, 28)[0]
    print(f"{addr[0]} ver={ver} link={flags & 1} frames={frames} pkts={pkts} "
          f"bad={bad} last_abort_rows={rows} aborts={aborts} "
          f"lat_ms={'--' if not lat_ok else lat_ms} "
          f"pane_bad={'--' if not pane_ok else pane_bad} tick={tick} sport={sport}", flush=True)
if nbeacon == 0:
    print("timeout: no beacon (check ARP entry / firewall / board bitstream)")
    sys.exit(1)
print(f"OK {nbeacon} beacon(s) in {DUR:g}s")

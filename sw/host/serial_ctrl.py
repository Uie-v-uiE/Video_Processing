#!/usr/bin/env python3
"""Serial control helper for effect enable string."""
from __future__ import annotations

import argparse
import sys
import time

try:
    import serial
except ImportError:
    print("pip install pyserial")
    raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="e.g. COM5")
    ap.add_argument("--baud", type=int, default=115200)
    args = ap.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.2)
    print(f"[UART] {args.port} @{args.baud}")
    print("Commands: 00111 | 10000 | SRC0 | SRC1 | TH80 | quit")
    print("Serial bitstring: left char = module0 (gray), 5 chars total")
    print("  gray binary blur sobel invert")
    print('  "00111" enables blur+sobel+invert')

    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        if line.lower() in {"q", "quit", "exit"}:
            break
        ser.write((line + "\n").encode("ascii", errors="ignore"))
        time.sleep(0.05)
        while ser.in_waiting:
            sys.stdout.write(ser.read(ser.in_waiting).decode("utf-8", "replace"))
        sys.stdout.flush()
    ser.close()


if __name__ == "__main__":
    main()

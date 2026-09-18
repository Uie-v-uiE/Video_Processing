#!/usr/bin/env python3
"""板卡串口控制台：效果位 / 选源 / 阈值 / 右屏缩放开关.

命令（与 src/ps/main.c 一致，发送时自动补 CR+LF）:
  00000 / 10000 / 00111   效果位 gray binary blur sobel invert（左起 bit0）
  SRC0 / SRC1             彩条 / DDR-ETH 视频
  TH80                    二值化阈值 0..255
  ZOOM0 / ZOOM1           右屏无极缩放 关/开（PL 默认常开，GPIO bit17）
  FILL                    PS 写 DDR 诊断色块
  STAT                    查询状态
  help                    显示帮助
  quit                    退出
"""
from __future__ import annotations

import argparse
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("需要 pyserial:  pip install pyserial")
    raise SystemExit(1)

HELP = """\
效果位 (5 字符, 左=gray):  gray binary blur sobel invert
  00000  全关
  10000  灰度
  01000  二值化
  00111  模糊+Sobel+反色
其他:
  SRC0 / SRC1    彩条 / 视频源
  TH00..TH255    二值化阈值
  ZOOM0 / ZOOM1  右屏缩放 关/开
  FILL / STAT
"""


def list_serial_ports():
    ports = list(list_ports.comports())
    if not ports:
        print("[UART] 未检测到串口")
        return
    print("[UART] 可用串口:")
    for p in ports:
        print(f"  {p.device:10s}  {p.description}")


def main():
    ap = argparse.ArgumentParser(description="Zynq video serial console")
    ap.add_argument("--port", default=None, help="e.g. COM5; omit to list ports")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--cmd", default=None, help="send one command and exit")
    args = ap.parse_args()

    if not args.port:
        list_serial_ports()
        print("用法: serial_ctrl.py --port COM5")
        return

    ser = serial.Serial(args.port, args.baud, timeout=0.15)
    print(f"[UART] {args.port} @{args.baud}")
    time.sleep(0.1)
    while ser.in_waiting:
        sys.stdout.write(ser.read(ser.in_waiting).decode("utf-8", "replace"))
    sys.stdout.flush()

    def send(line: str):
        line = line.strip()
        if not line:
            return
        ser.write((line + "\r\n").encode("ascii", errors="ignore"))
        time.sleep(0.08)
        t_end = time.time() + 0.25
        while time.time() < t_end:
            if ser.in_waiting:
                sys.stdout.write(ser.read(ser.in_waiting).decode("utf-8", "replace"))
                sys.stdout.flush()
                t_end = time.time() + 0.05
            else:
                time.sleep(0.02)

    if args.cmd:
        send(args.cmd)
        ser.close()
        return

    print(HELP)
    while True:
        try:
            line = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        low = line.lower()
        if low in {"q", "quit", "exit"}:
            break
        if low in {"help", "?"}:
            print(HELP)
            continue
        if low in {"list"}:
            list_serial_ports()
            continue
        send(line)
    ser.close()


if __name__ == "__main__":
    main()

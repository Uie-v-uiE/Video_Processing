#!/usr/bin/env python3
"""Zynq 以太网视频上位机 — UDP RGB565 推流.

协议: 每包 [u32 LE byte_offset][RGB565 载荷], 载荷 ≤1396B, 板端按 offset 写帧缓.

示例:
  python video_sender.py                          # 内置动画
  python video_sender.py --video demo.mp4         # 真实视频
  python video_sender.py --image logo.png --fps 25
  python video_sender.py --webcam 0
"""
from __future__ import annotations

import argparse
import math
import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

W, H = 512, 300
FRAME_BYTES = W * H * 2
HDR = 4
MTU_PAYLOAD = 1400 - HDR  # 1396

# 常见 FFmpeg 安装位置（Windows）
_FFMPEG_CANDIDATES = [
    r"C:\Users\wenqu\scoop\apps\ffmpeg\current\bin\ffmpeg.exe",
    r"C:\Users\wenqu\scoop\apps\ffmpeg\9.0.1\bin\ffmpeg.exe",
    r"D:\Software\Ghost\FFmpeg\ffmpeg.exe",
    r"C:\ffmpeg\bin\ffmpeg.exe",
]


def rgb888_to_rgb565(img: np.ndarray) -> bytes:
    """RGB888 uint8 HxWx3 → little-endian RGB565 bytes."""
    r = (img[:, :, 0] >> 3).astype(np.uint16)
    g = (img[:, :, 1] >> 2).astype(np.uint16)
    b = (img[:, :, 2] >> 3).astype(np.uint16)
    pix = (r << 11) | (g << 5) | b
    return pix.astype("<u2").tobytes()


def load_image(path: str | None) -> np.ndarray:
    if path:
        try:
            from PIL import Image

            im = Image.open(path).convert("RGB").resize((W, H), Image.BILINEAR)
            return np.asarray(im, dtype=np.uint8)
        except Exception as e:
            print(f"[WARN] PIL load failed: {e}, using synthetic")
    y = np.linspace(0, 255, H, dtype=np.uint8)[:, None]
    x = np.linspace(0, 255, W, dtype=np.uint8)[None, :]
    img = np.stack([x.repeat(H, 0), y.repeat(W, 1), ((x + y) // 2)], axis=-1)
    return img.astype(np.uint8)


def anim_frame(n: int) -> np.ndarray:
    """内置测试场景：渐变 + 弹球 + 滚动条."""
    t = n * 0.05
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    g = (np.sin(xx * 0.02 + t) * 0.5 + 0.5) * 180 + 40
    b = (np.cos(yy * 0.025 - t * 0.8) * 0.5 + 0.5) * 180 + 40
    r = (np.sin((xx + yy) * 0.015 + t * 0.6) * 0.5 + 0.5) * 160 + 50
    img = np.stack([r, g, b], axis=-1)

    balls = [
        (80, 180, 28, 255, 60, 60),
        (60, 220, 22, 60, 255, 60),
        (100, 140, 18, 60, 60, 255),
        (45, 280, 14, 255, 255, 60),
    ]
    for i, (rx, ry, rad, cr, cg, cb) in enumerate(balls):
        cx = (W * 0.5) + (W * 0.35) * math.sin(t * (1.1 + i * 0.17) + i)
        cy = (H * 0.5) + (H * 0.32) * math.cos(t * (0.9 + i * 0.13) + i * 1.7)
        dx = xx - cx
        dy = yy - cy
        mask = (dx * dx + dy * dy) < (rad * rad)
        img[mask] = (cr, cg, cb)

    bar = ((xx + n * 6) // 16).astype(np.int32) % 3
    strip = np.zeros((H, W, 3), dtype=np.float32)
    strip[:, :, 0] = np.where(bar == 0, 255, 20)
    strip[:, :, 1] = np.where(bar == 1, 255, 20)
    strip[:, :, 2] = np.where(bar == 2, 255, 20)
    img[H - 24 :, :] = strip[H - 24 :, :]

    ph = (n // 3) % 8
    img[8:28, 8:28] = (30, 30, 30)
    img[12:24, 12 + ph * 2 : 16 + ph * 2] = (255, 255, 0)
    return np.clip(img, 0, 255).astype(np.uint8)


def find_ffmpeg() -> str | None:
    for c in _FFMPEG_CANDIDATES:
        if os.path.isfile(c):
            return c
    for p in os.environ.get("PATH", "").split(os.pathsep):
        cand = os.path.join(p, "ffmpeg.exe")
        if os.path.isfile(cand):
            return cand
        cand = os.path.join(p, "ffmpeg")
        if os.path.isfile(cand):
            return cand
    return None


def _decode_jpeg_bytes(jpg: bytes):
    from io import BytesIO
    from PIL import Image

    im = Image.open(BytesIO(jpg)).convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.BILINEAR)
    return np.asarray(im, dtype=np.uint8)


def mjpeg_file_iter(path: str, loop: bool = True):
    from PIL import Image  # noqa: F401

    data = Path(path).read_bytes()
    print(f"[TX] mjpeg file: {path} ({len(data)} bytes)")
    while True:
        i = 0
        n = 0
        while True:
            s = data.find(b"\xff\xd8", i)
            if s < 0:
                break
            e = data.find(b"\xff\xd9", s + 2)
            if e < 0:
                break
            try:
                yield _decode_jpeg_bytes(data[s : e + 2])
                n += 1
            except Exception:
                pass
            i = e + 2
        if not loop:
            break
        print(f"[TX] mjpeg EOF ({n} frames), loop restart")


def ffmpeg_frame_iter(path: str, loop: bool = True):
    ff = find_ffmpeg()
    if not ff:
        raise SystemExit(
            "ffmpeg not found. Install via: winget install Gyan.FFmpeg\n"
            "Or convert to .mjpeg and pass --video file.mjpeg"
        )
    if not os.path.isfile(path):
        raise SystemExit(f"video not found: {path}")

    probe = subprocess.run(
        [ff, "-hide_banner", "-decoders"], capture_output=True, text=True, timeout=20
    )
    if "h264" not in (probe.stdout or ""):
        raise SystemExit(
            "This FFmpeg has no H.264 decoder.\n"
            "Use: winget install Gyan.FFmpeg\n"
            "Or convert to .mjpeg first."
        )

    while True:
        cmd = [
            ff, "-hide_banner", "-loglevel", "error", "-nostdin",
            "-i", path,
            "-an",
            "-vf", f"scale={W}:{H}:flags=lanczos",
            "-f", "mjpeg", "-q:v", "2",
            "-",
        ]
        print(f"[TX] ffmpeg mjpeg pipe: {path}")
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=1024 * 256
        )
        assert proc.stdout is not None
        buf = b""
        while True:
            chunk = proc.stdout.read(65536)
            if not chunk:
                break
            buf += chunk
            while True:
                s = buf.find(b"\xff\xd8")
                if s < 0:
                    buf = b""
                    break
                e = buf.find(b"\xff\xd9", s + 2)
                if e < 0:
                    buf = buf[s:]
                    break
                jpg = buf[s : e + 2]
                buf = buf[e + 2 :]
                try:
                    yield _decode_jpeg_bytes(jpg)
                except Exception:
                    pass
        proc.stdout.close()
        proc.wait()
        if not loop:
            break
        print("[TX] video EOF, loop restart")


def frame_iter(args):
    if args.video:
        low = args.video.lower()
        if low.endswith((".mjpeg", ".mjpg")):
            yield from mjpeg_file_iter(args.video, loop=not args.once)
        else:
            yield from ffmpeg_frame_iter(args.video, loop=not args.once)
    elif args.webcam is not None:
        try:
            import cv2
        except ImportError:
            raise SystemExit("pip install opencv-python for --webcam")
        cap = cv2.VideoCapture(args.webcam)
        if not cap.isOpened():
            raise SystemExit(f"cannot open webcam index {args.webcam}")
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            frame = cv2.resize(frame, (W, H), interpolation=cv2.INTER_AREA)
            yield frame
        cap.release()
    elif args.anim:
        n = 0
        while True:
            yield anim_frame(n)
            n += 1
            if args.max_frames and n >= args.max_frames:
                break
    else:
        base = load_image(args.image)
        n = 0
        while True:
            frame = base.copy()
            xs = (n * 4) % max(W - 8, 1)
            frame[:, xs : xs + 8, :] = 255 - frame[:, xs : xs + 8, :]
            yield frame
            n += 1
            if args.max_frames and n >= args.max_frames:
                break


def send_frame(sock: socket.socket, dest: tuple[str, int], payload: bytes) -> int:
    """按 offset 协议发送一帧，返回包数."""
    pkts = 0
    for off in range(0, len(payload), MTU_PAYLOAD):
        chunk = payload[off : off + MTU_PAYLOAD]
        sock.sendto(struct.pack("<I", off) + chunk, dest)
        pkts += 1
    return pkts


def main():
    ap = argparse.ArgumentParser(
        description="Zynq ETH video UDP sender (512x300 RGB565)"
    )
    ap.add_argument("--ip", default="192.168.1.10", help="board PL IP")
    ap.add_argument("--port", type=int, default=5001)
    ap.add_argument(
        "--src",
        default="192.168.1.100",
        help="PC NIC bind IP; empty string to use default route",
    )
    ap.add_argument("--image", default=None)
    ap.add_argument("--anim", action="store_true")
    ap.add_argument("--video", default=None)
    ap.add_argument("--webcam", type=int, default=None)
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--count", type=int, default=0, help="stop after N frames")
    ap.add_argument(
        "--max-frames",
        type=int,
        default=0,
        help="generator limit for --anim/image (0=unlimited)",
    )
    ap.add_argument("--quiet", action="store_true", help="less log")
    args = ap.parse_args()

    if args.image is None and args.video is None and args.webcam is None:
        args.anim = True
    if args.count:
        args.max_frames = args.max_frames or args.count

    dest = (args.ip, args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
    if args.src:
        try:
            sock.bind((args.src, 0))
            print(f"[TX] bind {args.src}")
        except OSError as e:
            print(f"[WARN] bind {args.src} failed: {e}, using default route")

    period = 1.0 / max(args.fps, 0.1)
    if args.video:
        mode = "video"
    elif args.webcam is not None:
        mode = "webcam"
    elif args.anim:
        mode = "anim"
    else:
        mode = "image"
    print(f"[TX] {args.ip}:{args.port} {W}x{H} RGB565 @ {args.fps:.1f} fps mode={mode}")

    n = 0
    t0 = time.perf_counter()
    next_t = t0
    try:
        for frame in frame_iter(args):
            if frame.shape[0] != H or frame.shape[1] != W:
                frame = np.ascontiguousarray(frame[:H, :W])
            payload = rgb888_to_rgb565(frame)
            if len(payload) != FRAME_BYTES:
                print(f"[ERR] bad frame size {len(payload)}")
                continue
            send_frame(sock, dest, payload)
            n += 1
            if n == 1 and not args.quiet:
                pkts = (len(payload) + MTU_PAYLOAD - 1) // MTU_PAYLOAD
                print(f"[TX] first frame {len(payload)} bytes ({pkts} pkts)")
            if n % 30 == 0 and not args.quiet:
                dt = time.perf_counter() - t0
                print(f"[TX] frames={n} ~{n / max(dt, 0.001):.1f} fps")
            if args.count and n >= args.count:
                break
            # 定时发送：补偿处理耗时，减少抖动
            next_t += period
            delay = next_t - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            else:
                next_t = time.perf_counter()
    except KeyboardInterrupt:
        print("\n[TX] stop")
    finally:
        sock.close()
        dt = time.perf_counter() - t0
        print(f"[TX] sent {n} frames in {dt:.2f}s (~{n / max(dt, 0.001):.1f} fps)")


if __name__ == "__main__":
    main()

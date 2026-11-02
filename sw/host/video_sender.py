#!/usr/bin/env python3
"""Send RGB565 frames to Zynq over UDP (default 192.168.1.10:5001).

Examples:
  python video_sender.py                  # built-in animation
  python video_sender.py --image pic.png  # still + moving stripe
  python video_sender.py --video a.mp4    # real video via FFmpeg
  python video_sender.py --video a.mp4 --loop
"""
from __future__ import annotations

import argparse
import math
import os
import socket
import struct
import subprocess
import time

import numpy as np

W, H = 512, 300
FFMPEG = r"C:\Users\wenqu\scoop\apps\ffmpeg\9.0.1\bin\ffmpeg.exe"
if not os.path.isfile(FFMPEG):
    FFMPEG = r"D:\Software\Ghost\FFmpeg\ffmpeg.exe"


def rgb888_to_rgb565(img: np.ndarray) -> bytes:
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
            return np.asarray(im)
        except Exception as e:
            print(f"[WARN] PIL load failed: {e}, using synthetic")
    y = np.linspace(0, 255, H, dtype=np.uint8)[:, None]
    x = np.linspace(0, 255, W, dtype=np.uint8)[None, :]
    img = np.stack([x.repeat(H, 0), y.repeat(W, 1), ((x + y) // 2)], axis=-1)
    return img.astype(np.uint8)


def anim_frame(n: int) -> np.ndarray:
    """Continuous motion scene: gradient + bouncing balls + scrolling bars."""
    t = n * 0.05
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    # moving diagonal gradient
    g = (np.sin(xx * 0.02 + t) * 0.5 + 0.5) * 180 + 40
    b = (np.cos(yy * 0.025 - t * 0.8) * 0.5 + 0.5) * 180 + 40
    r = (np.sin((xx + yy) * 0.015 + t * 0.6) * 0.5 + 0.5) * 160 + 50
    img = np.stack([r, g, b], axis=-1)

    # bouncing balls
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

    # scrolling vertical bars on bottom strip
    bar = ((xx + n * 6) // 16).astype(np.int32) % 3
    strip = np.zeros((H, W, 3), dtype=np.float32)
    strip[:, :, 0] = np.where(bar == 0, 255, 20)
    strip[:, :, 1] = np.where(bar == 1, 255, 20)
    strip[:, :, 2] = np.where(bar == 2, 255, 20)
    img[H - 24 :, :] = strip[H - 24 :, :]

    # frame counter digit-ish block
    ph = (n // 3) % 8
    img[8:28, 8:28] = (30, 30, 30)
    img[12:24, 12 + ph * 2 : 16 + ph * 2] = (255, 255, 0)

    return np.clip(img, 0, 255).astype(np.uint8)


def find_ffmpeg() -> str | None:
    candidates = [
        FFMPEG,
        r"C:\Users\wenqu\scoop\apps\ffmpeg\current\bin\ffmpeg.exe",
        r"C:\Users\wenqu\scoop\apps\ffmpeg\9.0.1\bin\ffmpeg.exe",
        r"D:\Software\Ghost\FFmpeg\ffmpeg.exe",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    for p in os.environ.get("PATH", "").split(os.pathsep):
        cand = os.path.join(p, "ffmpeg.exe")
        if os.path.isfile(cand):
            return cand
    return None


def mjpeg_file_iter(path: str, loop: bool = True):
    """Play concatenated JPEG / MJPEG file with pure PIL (no FFmpeg)."""
    from io import BytesIO
    from PIL import Image

    data = open(path, "rb").read()
    print(f"[TX] mjpeg file: {path} ({len(data)} bytes)")
    while True:
        i = 0
        while True:
            s = data.find(b"\xff\xd8", i)
            if s < 0:
                break
            e = data.find(b"\xff\xd9", s + 2)
            if e < 0:
                break
            try:
                im = Image.open(BytesIO(data[s : e + 2])).convert("RGB")
                if im.size != (W, H):
                    im = im.resize((W, H), Image.BILINEAR)
                yield np.asarray(im, dtype=np.uint8)
            except Exception:
                pass
            i = e + 2
        if not loop:
            break
        print("[TX] mjpeg EOF, loop restart")


def ffmpeg_frame_iter(path: str, loop: bool = True):
    """Decode video via FFmpeg (requires a full build with H.264)."""
    from io import BytesIO
    from PIL import Image

    ff = find_ffmpeg()
    if not ff:
        raise SystemExit(f"ffmpeg not found at {FFMPEG}")
    if not os.path.isfile(path):
        raise SystemExit(f"video not found: {path}")

    # quick capability check
    probe = subprocess.run(
        [ff, "-hide_banner", "-decoders"],
        capture_output=True, text=True, timeout=15,
    )
    if "h264" not in (probe.stdout or ""):
        raise SystemExit(
            "This FFmpeg has no H.264 decoder (stripped build).\n"
            "Use: winget install Gyan.FFmpeg\n"
            "Or convert video to .mjpeg and pass --video file.mjpeg"
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
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=1024 * 256,
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
                    im = Image.open(BytesIO(jpg)).convert("RGB")
                    if im.size != (W, H):
                        im = im.resize((W, H), Image.BILINEAR)
                    yield np.asarray(im, dtype=np.uint8)
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
            raise SystemExit("cannot open webcam")
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
    else:
        base = load_image(args.image)
        n = 0
        while True:
            frame = base.copy()
            xs = (n * 4) % max(W - 8, 1)
            frame[:, xs : xs + 8, :] = 255 - frame[:, xs : xs + 8, :]
            yield frame
            n += 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip", default="192.168.1.10")
    ap.add_argument("--port", type=int, default=5001)
    ap.add_argument("--src", default="192.168.1.100",
                    help="bind source IP (PC eth NIC); '' to disable")
    ap.add_argument("--image", default=None)
    ap.add_argument("--anim", action="store_true",
                    help="built-in moving scene (default if no image/video)")
    ap.add_argument("--video", default=None, help="mp4/avi/mkv path (FFmpeg)")
    ap.add_argument("--webcam", type=int, default=None)
    ap.add_argument("--once", action="store_true", help="play video once, no loop")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--count", type=int, default=0)
    args = ap.parse_args()
    if args.image is None and args.video is None and args.webcam is None:
        args.anim = True

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
    elif args.anim:
        mode = "anim"
    else:
        mode = "image"
    print(f"[TX] {args.ip}:{args.port} {W}x{H} RGB565 @ {args.fps} fps mode={mode}")
    n = 0
    t0 = time.time()
    try:
        for frame in frame_iter(args):
            payload = rgb888_to_rgb565(frame)
            # each UDP datagram: [u32 LE offset][rgb565 bytes]
            # board writes payload at FRAME_ADDR+offset (handles reorder/loss)
            hdr = 4
            mtu = 1400 - hdr
            for off in range(0, len(payload), mtu):
                chunk = payload[off : off + mtu]
                sock.sendto(struct.pack("<I", off) + chunk, (args.ip, args.port))
            n += 1
            if n == 1:
                print(f"[TX] first frame {len(payload)} bytes ({(len(payload)+mtu-1)//mtu} pkts)")
            if n % 30 == 0:
                dt = time.time() - t0
                print(f"[TX] frames={n} ~{n/max(dt,0.001):.1f} fps")
            if args.count and n >= args.count:
                break
            time.sleep(period)
    except KeyboardInterrupt:
        print("\n[TX] stop")
    finally:
        sock.close()
        print(f"[TX] sent {n} frames")


if __name__ == "__main__":
    main()

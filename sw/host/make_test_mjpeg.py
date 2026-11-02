#!/usr/bin/env python3
"""Build a concatenated MJPEG file from built-in animation (no FFmpeg needed)."""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from video_sender import W, H, anim_frame  # noqa: E402


def main():
    out = os.path.join(os.path.dirname(__file__), "test.mjpeg")
    nframes = 90  # 3 seconds @ 30fps
    with open(out, "wb") as f:
        for n in range(nframes):
            img = Image.fromarray(anim_frame(n))
            import io

            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85)
            f.write(buf.getvalue())
            if n % 30 == 0:
                print(f"frame {n}")
    print(f"wrote {out} ({os.path.getsize(out)} bytes, {nframes} frames)")


if __name__ == "__main__":
    main()

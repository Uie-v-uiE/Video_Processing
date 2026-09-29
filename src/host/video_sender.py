#!/usr/bin/env python3
"""src/host/video_sender.py —— 往板上推**任意视频**（Python 标准库 + 可选 ffmpeg）。

板子这边收的是什么：每包 **[u32 小端 帧内偏移][RGB565 载荷]**，载荷长度必须是 8 的倍数且
≤1392 B；一帧 = 512×300×2 = 307200 B。协议与 `src/rtl/eth/` 的收包链一一对上，
细节同 `src/host/udp_push.py`（那支是判据工具，这一支是"发我想看的视频"）。

分辨率口径先说清楚，别被两处数字绕晕：
  * 面板输出 **1024×600 @ 50 Hz**；
  * PL 的处理画幅是 **512×300**，输出侧做 ×2 展开上屏。
所以推流的目标永远是 512×300；任何分辨率的片源都在这里先缩到 512×300 再发。
BRAM 里那一帧就是 512×300（`build/utilization.rpt` 的 67.86 % 基本是它），
把画幅提到 1024×600 需要四倍 BRAM，这颗器件放不下 —— 不是软件开关的问题。

三种用法：
  python src/host/video_sender.py --demo                 # ping 板子，然后推内置测试视频
  python src/host/video_sender.py --input 我的视频.mp4     # 有 ffmpeg 时解任意格式
  python src/host/video_sender.py --input frames.rgb --raw 1024x600   # 裸帧，纯 Python 缩放

`--demo` 与内置测试图不依赖任何第三方库：装了 ffmpeg 就什么都发得了，没装也能把演示跑完，
这样"复现"不至于卡在一个下载不下来的工具上。
"""
import argparse
import os
import shutil
import socket
import struct
import subprocess
import sys
import time

OUT_W, OUT_H = 512, 300
FRAME_BYTES = OUT_W * OUT_H * 2
HDR = 4
MAX_PAYLOAD = 1392          # 8 的倍数；再大就会 IP 分片，而收包链不分片


def parse_args():
    p = argparse.ArgumentParser(description="向 Zynq 板推任意视频（协议见文件头）",
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog=__doc__.split("三种用法：")[-1])
    p.add_argument("--ip", default="192.168.1.10", help="板的地址（默认 192.168.1.10）")
    p.add_argument("--port", type=int, default=5001)
    p.add_argument("--fps", type=float, default=30.0, help="推流帧率上限（默认 30）")
    p.add_argument("--count", type=int, default=0, help="推多少帧后停（0 = 推完/一直推）")
    p.add_argument("--seconds", type=float, default=12.0, help="--demo 推多久（秒）")
    p.add_argument("--pace-mbps", type=float, default=20.0,
                   help="限速 MB/s；0 = 不限速（找过载点用，演示不要用它）")
    p.add_argument("--input", help="要发的视频：mp4/mov/avi/... 需要 ffmpeg；或裸帧流配 --raw")
    p.add_argument("--raw", metavar="WxH", help="--input 是裸 RGB565 帧流时的源分辨率，如 1024x600")
    p.add_argument("--demo", action="store_true", help="先 ping 板子，再推内置测试视频")
    p.add_argument("--no-ping", action="store_true", help="跳过 ping（板子已知可达时用）")
    return p.parse_args()


def ping_host(ip, timeout_s=2.0):
    """Windows/Linux 都试一次 `ping`。它要的是普通权限，不需要管理员；
    失败只说明"这一下没回"，不等于板子坏了——PL 在忙时 ICMP 也会被拖慢。"""
    for cmd in (["ping", "-n", "1", "-w", "1000", ip], ["ping", "-c", "1", "-W", "1", ip]):
        try:
            r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=timeout_s + 2)
            if r.returncode == 0:
                return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def probe_udp(ip, port, wait_s=1.5):
    """UDP 探一下并听回答：板上的固件对收到的包会回状态，收不到回话不代表链路不通
    （推流本身是单向的），所以这里只报观察，不做判据。"""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(wait_s)
    try:
        s.sendto(b"stat\r\n", (ip, port))
        data, _ = s.recvfrom(2048)
        return data.decode("utf-8", "replace").strip()
    except (OSError, socket.timeout):
        return None
    finally:
        s.close()


def rgb565(v):
    """v = (r,g,b) 0..255 → RGB565 数值（小端两字节按 5-6-5 拼）。"""
    r, g, b = v
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


_ROWS = None


def _rows_cache():
    """渐变底与左上黑框只算一次：每帧重算 15 万个像素是纯 Python，会把帧率压在 20 出头，
    那样"能推多少 fps"的读数就被上位机自己限住了，不再是发送参数的读数。"""
    global _ROWS
    if _ROWS is None:
        rows = []
        for y in range(OUT_H):
            base = rgb565((y * 255 // OUT_H, 64, (255 - y * 255 // OUT_H)))
            if y < 2:
                rows.append(b"\x00\x00" * OUT_W)
            else:
                row = bytearray(struct.pack("<H", base) * OUT_W)
                row[0:4] = b"\x00\x00\x00\x00"          # 左缘两像素黑框，方便看行对齐
                rows.append(bytes(row))
        _ROWS = rows
    return _ROWS


def test_frame(n):
    """内置测试图：竖向渐变底 + 一条每帧下移的白线 + 一个横向移动的红块。
    为什么不用彩条：彩条每一帧都一样，"帧在不在动、换帧是不是整帧原子"就看不出来。"""
    rows = list(_rows_cache())
    rows[n % OUT_H] = struct.pack("<H", rgb565((255, 255, 255))) * OUT_W
    bx = (n * 7) % (OUT_W - 64)
    block = struct.pack("<H", rgb565((255, 0, 0))) * 64
    for y in range(120, 184):
        row = bytearray(rows[y])
        row[bx * 2:(bx + 64) * 2] = block
        rows[y] = bytes(row)
    return b"".join(rows)


def ffmpeg_pipe(path, fps):
    """让 ffmpeg 把任意片源解成 512×300 rgb565le 裸帧，走 stdout。
    返回 (Popen, None) 或 (None, 原因)；调用方负责关闭。"""
    exe = shutil.which("ffmpeg")
    if not exe:
        return None, "没找到 ffmpeg：可以用 --demo 发内置测试图，或先装 ffmpeg 再发自己的视频。"
    cmd = [exe, "-hide_banner", "-loglevel", "error", "-i", path,
           "-vf", "scale=%d:%d" % (OUT_W, OUT_H), "-pix_fmt", "rgb565le",
           "-f", "rawvideo", "-r", "%.6g" % fps, "-"]
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        return None, "ffmpeg 起不来：%s" % e
    return p, None


def resize_raw(frame, sw, sh):
    """裸帧源分辨率不等于 512×300 时做最近邻缩放（纯标准库，够用且不假装是插值）。"""
    if (sw, sh) == (OUT_W, OUT_H):
        return frame
    out = bytearray(FRAME_BYTES)
    for y in range(OUT_H):
        sy = (y * sh) // OUT_H
        src_row = sy * sw * 2
        dst_row = y * OUT_W * 2
        for x in range(OUT_W):
            sx = (x * sw) // OUT_W
            out[dst_row + x * 2: dst_row + x * 2 + 2] = frame[src_row + sx * 2: src_row + sx * 2 + 2]
    return bytes(out)


def send_frame(sock, addr, payload, counters):
    for off in range(0, len(payload), MAX_PAYLOAD):
        chunk = payload[off:off + MAX_PAYLOAD]
        counters[0] += 1
        sock.sendto(struct.pack("<I", off) + chunk, addr)


def main():
    a = parse_args()
    if a.input and not os.path.isfile(a.input):
        print("FATAL: 找不到 --input 文件 %s" % a.input)
        return 2
    src_size = None
    if a.raw:
        try:
            sw, sh = (int(v) for v in a.raw.lower().split("x"))
            src_size = (sw, sh)
        except ValueError:
            print("FATAL: --raw 要写成 WxH，例如 --raw 1024x600")
            return 2

    if not a.no_ping:
        print("[LINK] ping %s ..." % a.ip, flush=True)
        if ping_host(a.ip):
            rep = probe_udp(a.ip, a.port)
            print("[LINK] ping 通；UDP 探针回话：%s" % (rep if rep else "（没回话，推流仍照发）"))
        else:
            print("[LINK] ping 不通。先检查网线/板子是否上电、IP 是不是 %s；"
                  "仍然继续推（ICMP 不通不等于 UDP 不通）。" % a.ip)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    addr = (a.ip, a.port)
    period = 1.0 / a.fps
    bytes_per_sec = a.pace_mbps * 1000 * 1000
    counters = [0]
    t0 = time.monotonic()
    next_t = time.monotonic()
    n = 0
    pipe = None
    fh = None
    print("[TX] -> %s:%d  512x300 RGB565 @%.2gfps  pace=%.1f MB/s" %
          (a.ip, a.port, a.fps, a.pace_mbps), flush=True)
    try:
        if a.input:
            if src_size:
                fh = open(a.input, "rb")
            else:
                pipe, why = ffmpeg_pipe(a.input, a.fps)
                if pipe is None:
                    print("FATAL: " + why)
                    return 2
        while True:
            if a.demo and (time.monotonic() - t0) > a.seconds:
                break
            if a.count and n >= a.count:
                break
            if fh:
                raw_len = src_size[0] * src_size[1] * 2
                chunk = fh.read(raw_len)
                if len(chunk) < raw_len:
                    print("[TX] 裸帧文件读完")
                    break
                payload = resize_raw(chunk, *src_size)
            elif pipe:
                chunk = pipe.stdout.read(FRAME_BYTES)
                if len(chunk) < FRAME_BYTES:
                    print("[TX] 解码结束（最后一帧不完整，丢掉）")
                    break
                payload = chunk
            else:
                payload = test_frame(n)
            send_frame(sock, addr, payload, counters)
            n += 1
            # 两把尺子取**较晚**的那个截止点：字节节奏（找带宽上限用）与帧周期（--fps）。
            # 只按字节算会超过 --fps（实测冲到 65 fps），只按帧算又限不住带宽；
            # 两处都"各等一次"则会互相叠加（第一版就是这样，25 fps 只跑到 20）。
            cost = (FRAME_BYTES + HDR * ((FRAME_BYTES + MAX_PAYLOAD - 1) // MAX_PAYLOAD)) / bytes_per_sec \
                if bytes_per_sec else 0.0
            due = max((next_t + cost) if cost else 0.0, t0 + n * period)
            d = due - time.monotonic()
            if d > 0:
                time.sleep(d)
            next_t = due
    except KeyboardInterrupt:
        print("\n[TX] 中断")
    finally:
        if pipe:
            try:
                pipe.stdout.close()
                pipe.terminate()
                pipe.wait(timeout=3)
            except Exception:                                  # 收尾失败不影响已经发出去的数
                pass
        if fh:
            fh.close()
    dt = time.monotonic() - t0
    print("[TX] %d 帧 / %.2f s = %.2f fps；共发 %d 包" % (n, dt, (n / dt) if dt else 0, counters[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

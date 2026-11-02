#!/usr/bin/env python3
"""src/host/udp_push.py —— 用千兆网往板上推 512×300 RGB565 视频（只用 Python 标准库）。

协议（与 `src/rtl/eth/` 的收包链一一对上）：每包 **[u32 小端 帧内偏移][RGB565 载荷]**，
载荷长度必须是 **8 的倍数**且 ≤1392 B。为什么必须是 8 的倍数：包边界若落在 64 bit DDR 字中间，
打包器对同一个字分两次推送会互相覆盖 ⇒ 屏上出现规律黑点。`--mtu-payload` 故意给非 8 倍数
是**复现**这个缺陷用的对照，不是日常用法。

用途与判据：
  --pattern edge   整屏逐帧黑白交替。这一发是拿来判"换帧是不是原子的"：非原子会看到灰行或残影。
  --file F         把 F 里的裸帧（512*300*2 B 一帧）按 fps 连续推上去；F 由
                   `make_sd_video.mjs`/ffmpeg 一类的工具预转换成 RGB565 即可。
  --drop-every N   每 N 包确定性地丢一包（制造一个洞）。丢的必须是**第几包**可复现，
                   随机丢的话每次读数都不一样，等于没有判据。
                   板上应当看到的不是"缺一块"，而是**整帧不上屏、保留上一帧**（三重提交门限）。

用法：
  python3 src/host/udp_push.py --pattern edge --fps 15 --count 600
  python3 src/host/udp_push.py --file frames.rgb --fps 30 --pace-mbps 15
  python3 src/host/udp_push.py --pattern edge --count 300 --drop-every 500
"""
import argparse
import os
import socket
import struct
import time

W, H = 512, 300
FRAME_BYTES = W * H * 2
HDR = 4
WHITE = (0xF8 << 8) | 0xFC          # RGB565 白：R=31 G=63 B=31
BLACK = 0


def parse_args():
    p = argparse.ArgumentParser(description="UDP 视频推流（协议见文件头）",
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog=__doc__.split("用法：")[-1])
    p.add_argument("--ip", default="192.168.1.10", help="板的地址（默认 192.168.1.10）")
    p.add_argument("--port", type=int, default=5001)
    p.add_argument("--fps", type=float, default=15.0)
    p.add_argument("--count", type=int, default=0, help="推多少帧后停（0 = 一直推）")
    p.add_argument("--pace-mbps", type=float, default=15.0,
                   help="限速，MB/s；0 = 不限速（用来找过载点，不是日常值）")
    p.add_argument("--mtu-payload", type=int, default=1392,
                   help="每包载荷上限；必须是 8 的倍数（理由见文件头）")
    p.add_argument("--pattern", choices=["edge"], default="edge")
    p.add_argument("--file", help="裸 RGB565 帧流文件；不给了就用 --pattern")
    p.add_argument("--drop-every", type=int, default=0, help="每 N 包丢一包（0 = 不丢）")
    return p.parse_args()


def frame_edge(n):
    """整屏逐帧黑白交替。颜色本身不重要，重要的是**每一帧都整屏一样**，
    所以任何"半新半旧"的帧都能在肉眼与台架之外被读出来。"""
    px = WHITE if (n & 1) else BLACK
    return struct.pack("<H", px) * (W * H)


def send_frame(sock, addr, payload, mtu, drop_every, counters):
    """返回这一帧实际发出的包数（丢包不算发出，但计数照记，对账要用）。"""
    pkts = 0
    for off in range(0, len(payload), mtu):
        chunk = payload[off:off + mtu]
        counters[0] += 1
        if drop_every and counters[0] % drop_every == 0:
            counters[1] += 1
            continue
        sock.sendto(struct.pack("<I", off) + chunk, addr)
        pkts += 1
    return pkts


class Pacer:
    """发送节奏按**累计字节数**推时间戳，不靠 sleep 叠加：sleep 会被调度抖动放大，
    而本项目要报的恰恰是帧间隔的抖动。"""

    def __init__(self, mbps):
        self.bytes_per_sec = mbps * 1000 * 1000
        self.next_t = time.monotonic()

    def spend(self, nbytes):
        if not self.bytes_per_sec:
            return
        self.next_t += nbytes / self.bytes_per_sec
        d = self.next_t - time.monotonic()
        if d > 0:
            time.sleep(d)
        else:
            self.next_t = time.monotonic()


def main():
    a = parse_args()
    if a.mtu_payload % 8:
        print("[TX] 警告：--mtu-payload=%d 不是 8 的倍数，包边界会毁掉 64bit 字（规律黑点）。"
              "这是复现缺陷用的对照，日常请给 8 的倍数。" % a.mtu_payload)
    if a.mtu_payload + HDR > 1472:
        print("[TX] 警告：包长 %d B 超过以太网载荷上限，会被 IP 分片，收包链不分片。"
              % (a.mtu_payload + HDR))
    if not a.file and a.pattern != "edge":
        print("FATAL: 要么 --file 给裸帧流，要么 --pattern edge")
        return 2
    fh = None
    if a.file:
        if not os.path.isfile(a.file):
            print("FATAL: 找不到 %s" % a.file)
            return 2
        fh = open(a.file, "rb")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    pacer = Pacer(a.pace_mbps)
    counters = [0, 0]                       # [发出计数（含被丢的）, 丢了几包]
    addr = (a.ip, a.port)
    period = 1.0 / a.fps
    print("[TX] -> %s:%d  %dx%d RGB565 @%.2ffps  pace=%.1f MB/s  %s  drop_every=%d"
          % (a.ip, a.port, W, H, a.fps, a.pace_mbps,
             ("file=" + os.path.basename(a.file)) if a.file else "pattern=edge",
             a.drop_every))
    n, t0, next_t = 0, time.monotonic(), time.monotonic()
    try:
        while True:
            if a.count and n >= a.count:
                break
            if fh:
                payload = fh.read(FRAME_BYTES)
                if len(payload) < FRAME_BYTES:
                    print("[TX] 文件读完（最后一帧不完整，丢掉）")
                    break
            else:
                payload = frame_edge(n)
            send_frame(sock, addr, payload, a.mtu_payload, a.drop_every, counters)
            pacer.spend(len(payload) + HDR * (len(payload) // a.mtu_payload + 1))
            n += 1
            if not a.pace_mbps:
                # 不限速时不再按 fps 停，让"过载"这件事成为被观察的对象而不是被节奏遮住
                continue
            next_t += period
            d = next_t - time.monotonic()
            if d > 0:
                time.sleep(d)
            else:
                next_t = time.monotonic()
    except KeyboardInterrupt:
        print("\n[TX] 中断")
    finally:
        if fh:
            fh.close()
    dt = time.monotonic() - t0
    print("[TX] %d 帧 / %.2f s = %.2f fps；发包含丢共 %d 包，主动丢了 %d 包"
          % (n, dt, (n / dt) if dt else 0, counters[0], counters[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

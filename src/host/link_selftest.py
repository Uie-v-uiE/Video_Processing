#!/usr/bin/env python3
"""link_selftest.py — 用 PL 遥测做一次"视频链路自检"（主机侧，只用标准库）。

三阶段，板子不用断电、不用接串口：
  clean1  正常推 512×300@30fps → frames 应增长、aborts 不动
  fault   注入确定性丢包（每 100 包丢 1 包）→ aborts 应增长、frames 基本不动
  clean2  再推干净流 → frames 恢复增长、aborts 不动

判据是**每秒的变化量**（信标 1 Hz），不是绝对值：
  clean 阶段 frames 增量 ≥ 8/s 且 aborts 增量 == 0
  fault 阶段 aborts 增量 ≥ 5/s 且 frames 增量 < 5/s
任一不满足 → 退出码 1。这就是"仪表能看见故障"的可复现验收。

用法：
  python src/host/link_selftest.py [板卡IP] [每阶段秒数]
"""
import os
import socket
import struct
import subprocess
import sys
import threading
import time

PORT = 1234
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BOARD = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.10"
PHASE = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0

beacons = []
lock = threading.Lock()
stop = threading.Event()


def listener():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", PORT))
    s.settimeout(0.5)
    while not stop.is_set():
        try:
            data, _ = s.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            break
        if len(data) < 30 or data[0:4] != b"VDEO":
            continue
        with lock:
            beacons.append({
                "t": time.monotonic(),
                "frames": struct.unpack_from("<I", data, 6)[0],
                "bad": struct.unpack_from("<I", data, 14)[0],
                "aborts": struct.unpack_from("<H", data, 24)[0],
                "lat_ms": struct.unpack_from("<H", data, 26)[0],
                "lat_ok": data[30] & 1,
            })
    s.close()


def mark():
    with lock:
        return len(beacons)


def stats(i0, i1):
    with lock:
        seg = beacons[i0:i1]
    if len(seg) < 2:
        return None
    dt = seg[-1]["t"] - seg[0]["t"]
    if dt <= 0:
        return None
    return {
        "n": len(seg),
        "dt": dt,
        "fps": (seg[-1]["frames"] - seg[0]["frames"]) / dt,
        "abort_rate": (seg[-1]["aborts"] - seg[0]["aborts"]) / dt,
        "bad_rate": (seg[-1]["bad"] - seg[0]["bad"]) / dt,
        "abort_delta": seg[-1]["aborts"] - seg[0]["aborts"],
        "bad_delta": seg[-1]["bad"] - seg[0]["bad"],
        "lat_ok_n": sum(1 for b in seg if b.get("lat_ok")),
        "lat_max": max((b.get("lat_ms", 0) for b in seg if b.get("lat_ok")), default=0),
    }


def run_stream(seconds, drop):
    if drop:
        cmd = [sys.executable, os.path.join(ROOT, "src", "host", "udp_push.py"),
               "--pattern", "edge", "--fps", "15", "--count", "100000", "--drop-every", "100"]
    else:
        cmd = [sys.executable, os.path.join(ROOT, "src", "host", "video_sender.py"), "--demo"]
    p = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(seconds)
    p.terminate()
    try:
        p.wait(timeout=3)
    except subprocess.TimeoutExpired:
        p.kill()
    time.sleep(1.2)         # 让最后一个信标落地


def phase(name, drop, errors):
    print(f"== {name} {PHASE:g}s ==", flush=True)
    i0 = mark()
    run_stream(PHASE, drop)
    i1 = mark()
    st = stats(i0, i1)
    if st is None:
        print(f"FAIL {name}: only {i1 - i0} beacon(s) — board/ARP/firewall?")
        errors.append(name)
        return
    print(f"   beacons={st['n']} dt={st['dt']:.1f}s  frames={st['fps']:.1f}/s  "
          f"aborts={st['abort_rate']:.1f}/s  bad={st['bad_rate']:.1f}/s  "
          f"lat={st['lat_max']}ms/{st['lat_ok_n']}")
    if drop:
        if st["abort_rate"] >= 5 and st["fps"] < 5:
            print(f"PASS {name}: injected drops are visible in aborts")
        else:
            print(f"FAIL {name}: aborts did not take the bait (abort={st['abort_rate']:.1f}/s, "
                  f"frames={st['fps']:.1f}/s)")
            errors.append(name)
    else:
        # 启动第一帧可能作废一次（发送器从帧中间开始）；允许一次，
        # 但持续丢包（fault 阶段 ≥5 次/秒）仍然过不了这一关。
        # 时延也进判据：干净流至少要有一次有效读数，且不能是离谱的饱和值。
        if (st["fps"] >= 8 and st["abort_delta"] <= 1 and st["bad_delta"] <= 2
                and st["lat_ok_n"] >= 1 and 0 < st["lat_max"] <= 200):
            print(f"PASS {name}: clean stream flows, aborts +{st['abort_delta']} (≤1 startup), "
                  f"lat {st['lat_max']}ms")
        else:
            print(f"FAIL {name}: frames={st['fps']:.1f}/s aborts+{st['abort_delta']} "
                  f"bad+{st['bad_delta']} lat={st['lat_max']}ms ok={st['lat_ok_n']}")
            errors.append(name)


def main():
    try:
        subprocess.run(["ping", "-n", "1", BOARD], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5)
    except Exception:
        pass
    threading.Thread(target=listener, daemon=True).start()
    time.sleep(2.5)
    errors = []
    if mark() == 0:
        print("FAIL no beacon at all: ping the board once to teach it the PC MAC/IP")
        stop.set()
        return 1
    phase("clean1", False, errors)
    phase("fault", True, errors)
    phase("clean2", False, errors)
    stop.set()
    if errors:
        print(f"FAIL link_selftest ({len(errors)} phase(s))")
        return 1
    print("PASS link_selftest: clean→fault→clean all judged from the wire")
    return 0


if __name__ == "__main__":
    sys.exit(main())

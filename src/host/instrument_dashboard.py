#!/usr/bin/env python3
"""instrument_dashboard.py — 板卡网络遥测的实时仪表盘（只用标准库 + Tkinter）。

数据源：PL 每秒发给最后一个 ARP 请求方的 UDP 1234 信标（udp_telemetry.v）。
用法：
  python src/host/instrument_dashboard.py [板卡IP]
  先点 "Ping / ARP"（让板子记住本机 MAC/IP），或自己 ping 一次板子。

显示：链路状态、帧率、包率、坏包/作废帧、最后一次作废缺行数、运行秒数、帧率曲线。
这是"网络化视频节点"的观测端：视频数据走 5001，状态走 1234，两条都在网线上。
"""
import queue
import socket
import struct
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import scrolledtext, ttk

PORT = 1234
BOARD = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.10"

BG = "#101418"
FG = "#d8e2ea"
MUTED = "#7d8b96"
OK = "#39d98a"
WARN = "#ffb020"
ERR = "#ff5c5c"
ACCENT = "#4da3ff"

q = queue.Queue()
stop = threading.Event()


def listener():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", PORT))
    s.settimeout(0.5)
    while not stop.is_set():
        try:
            data, addr = s.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            break
        if len(data) < 30 or data[0:4] != b"VDEO":
            continue
        q.put({
            "t": time.monotonic(),
            "ip": addr[0],
            "ver": data[4],
            "link": data[5] & 1,
            "frames": struct.unpack_from("<I", data, 6)[0],
            "pkts": struct.unpack_from("<I", data, 10)[0],
            "bad": struct.unpack_from("<I", data, 14)[0],
            "rows": struct.unpack_from("<H", data, 18)[0],
            "aborts": struct.unpack_from("<H", data, 24)[0],
            "tick": struct.unpack_from("<I", data, 20)[0],
            "lat_ms": struct.unpack_from("<H", data, 26)[0],
            "lat_ok": data[30] & 1,
            "pane_bad": data[31],
            "pane_ok": (data[30] >> 1) & 1,
        })
    s.close()


class Dash:
    def __init__(self, root):
        self.root = root
        root.title("VDEO Link Instrument — PL UDP telemetry")
        root.configure(bg=BG)
        root.geometry("920x600")
        root.minsize(760, 520)

        top = tk.Frame(root, bg=BG)
        top.pack(fill="x", padx=18, pady=(16, 6))
        tk.Label(top, text="多源视频节点 · 链路仪表", bg=BG, fg=FG,
                 font=("Segoe UI", 18, "bold")).pack(side="left")
        self.peer = tk.Label(top, text=f"udp/{PORT}  ←  {BOARD}", bg=BG, fg=MUTED,
                             font=("Consolas", 10))
        self.peer.pack(side="right")

        tiles = tk.Frame(root, bg=BG)
        tiles.pack(fill="x", padx=18, pady=8)
        self.tiles = {}
        specs = [("LINK", 0), ("FPS", 0), ("PPS", 0), ("LAT", 0),
                 ("BAD", 0), ("ABORTS", 0), ("UPTIME", 0)]
        for i, (name, _) in enumerate(specs):
            f = tk.Frame(tiles, bg="#1a2129", highlightthickness=1,
                         highlightbackground="#26303a")
            f.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 8, 0))
            tiles.columnconfigure(i, weight=1)
            tk.Label(f, text=name, bg="#1a2129", fg=MUTED,
                     font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=12, pady=(10, 0))
            v = tk.Label(f, text="—", bg="#1a2129", fg=FG,
                         font=("Consolas", 20, "bold"))
            v.pack(anchor="w", padx=12, pady=(0, 10))
            self.tiles[name] = v

        mid = tk.Frame(root, bg=BG)
        mid.pack(fill="both", expand=True, padx=18, pady=8)
        left = tk.Frame(mid, bg="#1a2129", highlightthickness=1, highlightbackground="#26303a")
        left.pack(side="left", fill="both", expand=True)
        tk.Label(left, text="帧率（每秒帧数，60 s）", bg="#1a2129", fg=MUTED,
                 font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=12, pady=(10, 0))
        self.canvas = tk.Canvas(left, bg="#1a2129", highlightthickness=0, height=210)
        self.canvas.pack(fill="both", expand=True, padx=10, pady=10)

        right = tk.Frame(mid, bg="#1a2129", highlightthickness=1, highlightbackground="#26303a",
                         width=300)
        right.pack(side="right", fill="y", padx=(10, 0))
        right.pack_propagate(False)
        tk.Label(right, text="事件", bg="#1a2129", fg=MUTED,
                 font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=12, pady=(10, 0))
        self.log = scrolledtext.ScrolledText(right, bg="#1a2129", fg=FG, bd=0,
                                             font=("Consolas", 9), height=12,
                                             insertbackground=FG)
        self.log.pack(fill="both", expand=True, padx=10, pady=10)
        self.log.configure(state="disabled")

        bar = tk.Frame(root, bg=BG)
        bar.pack(fill="x", padx=18, pady=(0, 14))
        self.btn_ping = ttk.Button(bar, text="Ping / ARP（让板子记住本机）",
                                   command=self.do_ping)
        self.btn_ping.pack(side="left")
        ttk.Button(bar, text="清空事件", command=self.clear_log).pack(side="left", padx=8)
        self.note = tk.Label(bar, text="等待信标…", bg=BG, fg=MUTED,
                             font=("Consolas", 9))
        self.note.pack(side="right")

        self.hist = []
        self.last = None
        self.last_rate = None
        self.last_rate_t = None
        self.max_seen = 60
        self.beacons = 0
        self.last_rx = 0.0
        self.last_aborts = None
        self.last_bad = None
        root.after(100, self.poll)
        root.protocol("WM_DELETE_WINDOW", self.close)

    def do_ping(self):
        def run():
            try:
                subprocess.run(["ping", "-n", "1", BOARD],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
            except Exception:
                pass
        threading.Thread(target=run, daemon=True).start()
        self.logline(f"ping {BOARD}（触发 ARP，信标只发给最后一个请求方）")

    def clear_log(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")

    def logline(self, text):
        ts = time.strftime("%H:%M:%S")
        self.log.configure(state="normal")
        self.log.insert("end", f"{ts}  {text}\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def poll(self):
        got = None
        try:
            while True:
                got = q.get_nowait()
        except queue.Empty:
            pass
        if got is not None:
            self.update(got)
        idle = time.monotonic() - self.last_rx if self.last_rx else 1e9
        if self.last_rx and idle > 3.0:
            self.tiles["LINK"].configure(text="NO BEACON", fg=ERR)
        self.root.after(100, self.poll)

    def update(self, b):
        self.last_rx = time.monotonic()
        self.beacons += 1
        if self.beacons == 1:
            self.logline(f"收到 {b['ip']} 的信标，版本 {b['ver']}")
        if self.last is not None:
            dt = b["t"] - self.last["t"]
            if dt > 0:
                fps = (b["frames"] - self.last["frames"]) / dt
                pps = (b["pkts"] - self.last["pkts"]) / dt
                self.tiles["FPS"].configure(text=f"{fps:5.1f}", fg=FG)
                self.tiles["PPS"].configure(text=f"{pps:7.0f}", fg=FG)
                self.hist.append(fps)
                self.hist = self.hist[-self.max_seen:]
                self.draw()
        self.tiles["LINK"].configure(text="UP" if b["link"] else "IDLE",
                                     fg=OK if b["link"] else WARN)
        self.tiles["LAT"].configure(text=(f"{b['lat_ms']} ms" if b["lat_ok"] else "--"),
                                    fg=FG if b["lat_ok"] else MUTED)
        self.tiles["BAD"].configure(text=str(b["bad"]),
                                    fg=ERR if b["bad"] else FG)
        self.tiles["ABORTS"].configure(text=str(b["aborts"]),
                                       fg=WARN if b["aborts"] else FG)
        self.tiles["UPTIME"].configure(text=f"{b['tick']} s", fg=FG)
        pane = "--" if not b["pane_ok"] else str(b["pane_bad"])
        self.note.configure(text=f"{b['ip']}  frames={b['frames']}  pkts={b['pkts']}  "
                                 f"last_abort_rows={b['rows']}  pane_bad={pane}")
        if self.last_aborts is not None and b["aborts"] != self.last_aborts:
            self.logline(f"作废帧 +{b['aborts'] - self.last_aborts}（最后一次缺 {b['rows']} 行）")
        if self.last_bad is not None and b["bad"] != self.last_bad:
            self.logline(f"坏包/作废计数 {self.last_bad} → {b['bad']}")
        self.last_aborts = b["aborts"]
        self.last_bad = b["bad"]
        self.last = b

    def draw(self):
        c = self.canvas
        c.delete("all")
        w = c.winfo_width() or 560
        h = c.winfo_height() or 210
        pad = 8
        vals = self.hist
        if not vals:
            return
        top = max(1.0, max(vals) * 1.15)
        n = max(self.max_seen, len(vals))
        step = (w - 2 * pad) / max(1, n - 1)
        pts = []
        for i, v in enumerate(vals):
            x = pad + i * step
            y = h - pad - (v / top) * (h - 2 * pad)
            pts.extend([x, y])
        if len(pts) >= 4:
            c.create_line(*pts, fill=ACCENT, width=2, smooth=True)
        c.create_text(pad, 4, text=f"{top:.0f}", fill=MUTED, anchor="nw",
                      font=("Consolas", 8))
        c.create_text(w - pad, h - 4, text=f"{len(vals)} s", fill=MUTED, anchor="se",
                      font=("Consolas", 8))

    def close(self):
        stop.set()
        self.root.destroy()


def main():
    threading.Thread(target=listener, daemon=True).start()
    root = tk.Tk()
    Dash(root)
    root.mainloop()
    stop.set()


if __name__ == "__main__":
    main()

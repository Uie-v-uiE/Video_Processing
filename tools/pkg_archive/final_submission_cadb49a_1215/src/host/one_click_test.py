#!/usr/bin/env python3
"""one_click_test.py —— 一键测试工具（上位机 §1.3 两类工具之一的 Python 侧；Node 同名实现见 one_click_test.mjs）。

用途：一条命令做完四步，每步打一行结论（判定词在行尾最后一个字段）：
  ① PING    板卡（--ip）
  ② CONNECT 连上读回口：板侧固件没有 UDP 回包，这条通路是 JTAG —— xsdb 把 lane 号写进 GPIO_0 的
            bit[31:27]、从 GPIO_1 读数（与 src/host/health_read.mjs 同一套 lane、同一组基址），
            lane8 = 收到的 UDP 包数、lane9 = 收到的有效字节数；这一步取它们的基线
  ③ SEND    发内置测试片源：把 data/inputs/ 的裸帧交给 src/host/udp_push.py 去发
            （每包 [u32 小端 帧内偏移][RGB565 载荷] 的协议只有它一份，这里不重写）
  ④ COLLECT 再读一次 lane8/lane9，用增量和「应发的包数/字节数」对账，差额直接打出来
输入：命令行参数（--help 有全表）+ 仓库根相对路径的片源文件。
输出：stdout 每步一行 + 一行 ONE-CLICK 总结论；xsdb 的原始回读留在 data/measured/one_click_*.out。
退出码：0 = 四步全 PASS；1 = 任一步 FAIL（ping 不通 / 读不到寄存器 / 账对不上）；
       2 = 参数或片源文件不对；--dry-run 只打印将要做什么（不 ping、不连板、不发包），恒 0。
"""
import argparse
import os
import re
import subprocess
import sys

FRAME_BYTES = 512 * 300 * 2              # 与 src/host/udp_push.py 的 W/H/RGB565 同源
MTU = 1392                               # 每包载荷上限（必须是 8 的倍数，理由见那支的文件头）
PKTS_PER_FRAME = -(-FRAME_BYTES // MTU)  # 221 包/帧（udp_sink_check.mjs 用的是同一个数）

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MEASURED = os.path.join(ROOT, "data", "measured")

# 结论行里有中文：Windows 控制台默认 GBK，不改码就会打出乱码，而落盘的东西要求 UTF-8
# （同一件事见 build/board_verify.sh 的 to_utf8），Node 那侧写的也是 UTF-8。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (OSError, ValueError):
        pass


def parse_args():
    p = argparse.ArgumentParser(
        description="一键测试四步：ping 板卡 → 连读回口 → 发内置测试片源 → 回收计数对账。"
                    "每步一行结论，判定词在行尾。",
        epilog="四步都不碰的例子：python src/host/one_click_test.py --dry-run")
    p.add_argument("--ip", default="192.168.1.10",
                   help="板卡地址：步骤 ① ping 它、步骤 ③ 发给它（默认 192.168.1.10）")
    p.add_argument("--port", type=int, default=5001,
                   help="UDP 目标端口，转给发送脚本（默认 5001）")
    p.add_argument("--clip", default="data/inputs/wordid_512x300.rgb565",
                   help="内置测试片源，按仓库根相对路径给（默认 data/inputs/wordid_512x300.rgb565）")
    p.add_argument("--frames", type=int, default=5,
                   help="发多少帧；片源不足则整片重复补足后截到该帧数（默认 5）")
    p.add_argument("--fps", type=float, default=15.0,
                   help="转给发送脚本的帧率：udp_push.py 按它分帧停（默认 15）")
    p.add_argument("--pace-mbps", type=float, default=15.0,
                   help="发送限速 MB/s，保护板端入包 FIFO；0 = 不限速（默认 15）")
    p.add_argument("--gpio0", default="41200000",
                   help="写 lane 号的 AXI GPIO_0 基址，十六进制无 0x（默认 41200000）")
    p.add_argument("--gpio1", default="41210000",
                   help="读 lane 值的 AXI GPIO_1 基址，十六进制无 0x（默认 41210000）")
    p.add_argument("--hw-port", type=int, default=3121, help="hw_server 的端口（默认 3121）")
    p.add_argument("--xsdb", default=os.environ.get("VP_XSDB", "xsdb.bat"),
                   help="xsdb 可执行文件（默认环境变量 VP_XSDB，没给则 xsdb.bat）")
    p.add_argument("--dry-run", action="store_true",
                   help="只打印将要做什么：不 ping、不连板、不发包（默认关）")
    return p.parse_args()


def line(n, tag, fields, verdict):
    """一行结论 = `[步/4] 名字 读数…… 判定词`：判定词永远是最后一个字段。"""
    print("[%d/4] %s %s %s" % (n, tag, fields, verdict), flush=True)


def say(n, tag, fields, ok):
    line(n, tag, fields, "PASS" if ok else "FAIL")


# xsdb 的 mrd 返回形如 "41200000:   00010000" ⇒ 整串打出来，由这里按 "地址: 数据" 解析（别在 Tcl 里 split）。
# 地址那一截不进捕获组：group(1) 必须是数据（与 src/host/health_read.mjs 的 VAL_RE 同一个形状）。
VAL_RE = re.compile(r"VAL\s*[0-9a-fA-F]{1,8}:\s*([0-9a-fA-F]{1,8})")


def main():
    a = parse_args()
    gpio0, gpio1 = "0x" + a.gpio0, "0x" + a.gpio1
    clip_rel = a.clip
    clip = clip_rel if os.path.isabs(clip_rel) else os.path.join(ROOT, clip_rel)

    problems = []
    if a.frames < 1:
        problems.append("--frames=%d 要 ≥1 的整数" % a.frames)
    if not (1 <= a.port <= 65535):
        problems.append("--port=%d 不是合法端口" % a.port)
    if a.pace_mbps < 0:
        problems.append("--pace-mbps=%s 不是非负数" % a.pace_mbps)
    if a.fps <= 0:
        problems.append("--fps=%s 要 >0" % a.fps)
    clip_bytes = None
    if not problems:
        if not os.path.isfile(clip):
            problems.append("找不到片源 %s（相对仓库根；--clip 可指到 data/inputs/ 的另一个文件）" % clip_rel)
        else:
            with open(clip, "rb") as fh:
                clip_bytes = fh.read()
            if len(clip_bytes) < FRAME_BYTES:
                problems.append("片源 %s 不足一帧（%d B < %d B）" % (clip_rel, len(clip_bytes), FRAME_BYTES))
    if problems:
        say(0, "SETUP", "参数检查 %s" % "；".join(problems), False)
        return 2

    exp_pkts = a.frames * PKTS_PER_FRAME
    exp_bytes = a.frames * FRAME_BYTES
    # 片源自带的整帧数不够时，udp_push.py 只会发到「文件读完」⇒ 先落一份重复补足后截到
    # frames 帧的裸帧流（Node 那侧是把同一串字节喂 stdin，两边发的字节一模一样）。
    need_repeat = (len(clip_bytes) // FRAME_BYTES) < a.frames
    payload_path = os.path.join(MEASURED, "one_click_payload.rgb565")
    send_file = payload_path if need_repeat else clip
    send_file_shown = "data/measured/one_click_payload.rgb565" if need_repeat else clip_rel

    def materialize_payload():
        os.makedirs(MEASURED, exist_ok=True)
        reps = -(-(a.frames * FRAME_BYTES) // len(clip_bytes))
        with open(payload_path, "wb") as fh:
            fh.write((clip_bytes * reps)[:a.frames * FRAME_BYTES])

    if a.dry_run:
        p1, p2 = ("-n 1 -w 1000", "-c 1 -W 1") if os.name == "nt" else ("-c 1 -W 1", "-n 1 -w 1000")
        line(1, "PING", "将执行 ping %s %s，不通再试 ping %s %s（仍不通则整轮判红并退出 1） 未执行"
             % (p1, a.ip, p2, a.ip), "NOT_MEASURED")
        line(2, "CONNECT", "将用 \"%s\" 连 hw_server localhost:%d：读 %s 原值 → lane 号写 bit[31:27] → 从 %s 取 lane0/1/8/9 基线 → 原值写回 未执行"
             % (a.xsdb, a.hw_port, gpio0, gpio1), "NOT_MEASURED")
        line(3, "SEND", "将执行 python src/host/udp_push.py --ip %s --port %d --fps %s --pace-mbps %s --count %d --file %s ；输入=%s×%d 帧=%d B 预计 %d 包 未执行"
             % (a.ip, a.port, ("%g" % a.fps), ("%g" % a.pace_mbps), a.frames, send_file_shown,
                clip_rel, a.frames, exp_bytes, exp_pkts), "NOT_MEASURED")
        line(4, "COLLECT", "将再读一次 lane0/1/8/9，与预计 %d 包 / %d 字节对账 未执行" % (exp_pkts, exp_bytes), "NOT_MEASURED")
        print("ONE-CLICK dry-run=true clip=%s 存在=是 frames=%d 预计包数=%d 预计字节=%d 未碰网络与板子 NOT_MEASURED"
              % (clip_rel, a.frames, exp_pkts, exp_bytes), flush=True)
        return 0

    try:
        if need_repeat:
            materialize_payload()
        # ---------------- ① ping：两种写法都试一次（Windows 的 -n/-w 与 POSIX 的 -c/-W），同 video_sender.py ----------------
        tries = [["ping", "-n", "1", "-w", "1000", a.ip], ["ping", "-c", "1", "-W", "1", a.ip]] \
            if os.name == "nt" else [["ping", "-c", "1", "-W", "1", a.ip], ["ping", "-n", "1", "-w", "1000", a.ip]]
        ping_ok, ping_tried = False, []
        for c in tries:
            ping_tried.append(" ".join(c))
            try:
                if subprocess.run(c, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                  timeout=4).returncode == 0:
                    ping_ok = True
                    break
            except (OSError, subprocess.SubprocessError):
                continue
        say(1, "PING", "ip=%s tried=\"%s\" reply=%s hint=查供电/网线/IP"
            % (a.ip, " | ".join(ping_tried), "通" if ping_ok else "不通"), ping_ok)
        if not ping_ok:
            return 1

        head = [
            "catch {connect -host localhost -port %d}" % a.hw_port,
            'targets -set -filter {name =~ "*#0"}',
            "catch {stop}",        # A9 停在断点时 mrd/mwr 走 CoreSight 直接打到 GPIO 从端口（health_read 同一套路）
            "after 100",
        ]

        def run_xsdb(lines, tag):
            tcl = os.path.join(MEASURED, "one_click_%s.tcl" % tag)
            out = os.path.join(MEASURED, "one_click_%s.out" % tag)
            os.makedirs(MEASURED, exist_ok=True)
            with open(tcl, "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(lines) + "\n")
            try:
                subprocess.run('"%s" "%s" > "%s" 2>&1' % (a.xsdb, tcl, out), shell=True)
            except OSError:
                pass              # 回读全在 out 里，判定只看文件内容
            os.remove(tcl)
            if not os.path.isfile(out):
                return ""
            with open(out, encoding="utf-8", errors="replace") as fh:
                return fh.read().replace("\r\n", "\n")

        def read_lanes(lanes):
            """读一组 lane：先把 GPIO_0 原值读回来、读完原样还回去 —— 不知道原值就写会踩掉 src_sel/特效/阈值。"""
            cur = VAL_RE.search(run_xsdb(head + ['puts "VAL [mrd -force %s 1]"' % gpio0], "cur"))
            if not cur:
                return {"err": "读不到 %s（hw_server 没起 / 板子没电 / xsdb=%s 指错？）" % (gpio0, a.xsdb)}
            cur_val = int(cur.group(1), 16)
            keep = cur_val & 0x07FFFFFF
            body = list(head)
            for n in lanes:
                body += ["mwr -force %s 0x%x 32" % (gpio0, keep | (n << 27)),
                         "after 20", 'puts "LANE %d"' % n,
                         'puts "VAL [mrd -force %s 1]"' % gpio1]
            body += ["mwr -force %s 0x%x 32" % (gpio0, cur_val), "catch {con}"]   # 原样还回去
            got, lane = {}, -1
            for text_line in run_xsdb(body, "lane").split("\n"):
                m = re.match(r"^LANE (\d+)$", text_line.strip())
                if m:
                    lane = int(m.group(1))
                    continue
                v = VAL_RE.search(text_line)
                if v and lane >= 0:
                    got[lane] = int(v.group(1), 16)
                    lane = -1
            for n in lanes:
                if n not in got:
                    return {"err": "lane%d 没读到值（data/measured/one_click_lane.out 里只有采到的那几条）" % n}
            return {"cur": cur_val, "v": got}

        # ---------------- ② 读回口基线（lane0=drop_words 1=frames_bad|bad_pkts 8=pkts 9=bytes，定义见 health_read.mjs）----
        lanes = [0, 1, 8, 9]
        base = read_lanes(lanes)
        if "err" in base:
            say(2, "CONNECT", "xsdb=\"%s\" hw_server=localhost:%d 读回口拿不到 lane 值 reason=%s"
                % (a.xsdb, a.hw_port, base["err"]), False)
            return 1
        g = lambda n: base["v"][n]
        say(2, "CONNECT", "xsdb=\"%s\" hw_server=localhost:%d gpio0=%s 原值=0x%x "
            "基线 lane8_pkts=%d lane9_bytes=%d lane0_drop_words=%d lane1_frames_bad=%d"
            % (a.xsdb, a.hw_port, gpio0, base["cur"], g(8), g(9), g(0), g(1) & 0xFFFF), True)

        # ---------------- ③ 发送：把字节交给已有的发送脚本，协议不在这里重写 ----------------
        cmd = [sys.executable, os.path.join("src", "host", "udp_push.py"),
               "--ip", a.ip, "--port", str(a.port), "--fps", "%g" % a.fps,
               "--pace-mbps", "%g" % a.pace_mbps, "--count", str(a.frames), "--file", send_file]
        # 子进程默认按控制台码（本机 cp936）打中文 ⇒ 它那句对账会变乱码、下面的正则就抓不到，
        # 所以点名要 UTF-8（与 Node 侧 video_sender.mjs 那行 ASCII 报表同等可解析）。
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=180,
                           env=dict(os.environ, PYTHONIOENCODING="utf-8"))
        sout = (r.stdout or "") + (r.stderr or "")
        # 发送脚本自己报的账：`[TX] N 帧 / …；发包含丢共 M 包，主动丢了 D 包`
        m = re.search(r"\[TX\] (\d+) 帧 / .*发包含丢共 (\d+) 包，主动丢了 (\d+) 包", sout)
        frames_sent = int(m.group(1)) if m else float("nan")
        counted = int(m.group(2)) if m else float("nan")
        dropped = int(m.group(3)) if m else float("nan")
        sent_pkts = counted - dropped if m else float("nan")
        send_ok = bool(m) and r.returncode == 0 and sent_pkts == exp_pkts
        say(3, "SEND", "via=src/host/udp_push.py clip=%s frames=%d 发出帧=%s 发出包=%s 主动丢包=%s 应发包=%d%s"
            % (clip_rel, a.frames, frames_sent, sent_pkts, dropped, exp_pkts,
               "" if send_ok else " 发送脚本输出=%r" % sout.split("\n")[:3][0][:140]), send_ok)

        # ---------------- ④ 回收：增量对账 ----------------
        after = read_lanes(lanes)
        if "err" in after:
            say(4, "COLLECT", "xsdb=\"%s\" 读回失败 reason=%s 差额=拿不到读数" % (a.xsdb, after["err"]), False)
            return 1
        d = lambda n: after["v"][n] - base["v"][n]
        d_pkts, d_bytes = d(8), d(9)
        collect_ok = (d_pkts == exp_pkts) and (d_bytes == exp_bytes)
        say(4, "COLLECT", "lane8_pkts_delta=%d 应发=%d lane9_bytes_delta=%d 应发=%d 差额_pkts=%d 差额_bytes=%d "
            "期间 drop_words=%d frames_bad=%d bad_pkts=%d"
            % (d_pkts, exp_pkts, d_bytes, exp_bytes, d_pkts - exp_pkts, d_bytes - exp_bytes,
               d(0), d(1) & 0xFFFF, (d(1) >> 16) & 0xFFFF), collect_ok)

        fails = (0 if send_ok else 1) + (0 if collect_ok else 1)     # ② 已经 PASS 才走到这里
        print("ONE-CLICK steps=4 ip=%s clip=%s frames=%d 发出包=%s pkts增量=%d bytes增量=%d 判红步数=%d %s"
              % (a.ip, clip_rel, a.frames, sent_pkts, d_pkts, d_bytes, fails,
                 "PASS" if fails == 0 else "FAIL"), flush=True)
        return 0 if fails == 0 else 1
    finally:
        if need_repeat and os.path.isfile(payload_path):
            os.remove(payload_path)


if __name__ == "__main__":
    sys.exit(main())

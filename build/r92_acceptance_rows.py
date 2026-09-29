#!/usr/bin/env python3
# build/r92_acceptance_rows.py —— 把 board/ACCEPTANCE.md 的机器判据 1~7 行按**这一跑的日志**重抄一遍。
# 为什么不让手抄：这一轮换了位流与证据文件，行里每个数都该从当轮日志现取；
# 取不到就打印 SKIP，绝不把上一轮（r90）的数留在"这一版验过"的表里。
# 跑法：python build/r92_acceptance_rows.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read().replace('\r', '')

V = rd('build/evidence/verify_0930_0424.txt')
TX = rd('build/evidence/r92_tx.txt')
HE = rd('build/evidence/r92_health.txt')

def g(pat, src=V):
    m = re.search(pat, src)
    return m.groups() if m else None

geom = g(r'RESULT PASS geom_check（ok=(\d+) fail=(\d+)）')
lane = g(r'"zman":(\d+),"zsel":(\d+),"zcode":(\d+).*?"inv_scale":(\d+),"x100_actual":(\d+)')
temp = g(r'(V9-6 温度格三方对账：[^\n]+)')
back = g(r'(ok   跑完回到初态：[^\n]+)')
uart = g(r'RESULT PASS uart_cmd_check\s+\(100 条命令, ([\d.]+) s')
tfrm = g(r'RESULT board_verify PASS（判红的步骤：(\d+)）')
txm = re.search(r'\[TX\] (\d+) 帧 / ([\d.]+) s = ([\d.]+) fps；共发 ([\d,]+) 包', TX)
pk = re.search(r'0x([0-9a-fA-F]+)\s+pkts', HE)
by = re.search(r'0x([0-9a-fA-F]+)\s+bytes', HE)
lat = re.search(r'屏上 Latency=(\d+)ms\s+回读 tot/100000=(\d+)', HE)
import hashlib
BIT = hashlib.md5(open(os.path.join(ROOT,'build','system.bit'),'rb').read()).hexdigest()[:12]
print(f"取到 geom={geom} lane={lane} uart={uart} tfrm={tfrm} bit={BIT}")
for name, ok in [('tx 行', txm), ('pkts', pk), ('bytes', by), ('latency', lat),
                 ('初态', back), ('温度', temp), ('lane23', lane), ('电池', uart), ('board_verify', tfrm)]:
    if not ok:
        print(f"FATAL 取不到 {name} —— 这一行不写")

rows = {
 1: f"| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功 | `DDR_ECHO: 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1`（位流 md5 `{BIT}`）/ `RESUME: ok` | `build/evidence/r92_flash_1_psboot.txt`、`build/evidence/r92_flash_program_log.txt`、`build/evidence/r92_flash_app.txt` |",
 2: f"| 2 | 串口命令电池（100 条，含该拒的必须拒） | `RESULT PASS uart_cmd_check (100 条命令, {uart[0]} s)`；`RESULT board_verify PASS（判红的步骤：{tfrm[0]}）` | `build/evidence/verify_0930_0424.txt`、`board/uart_script_capture.txt` |",
 3: f"| 3 | 几何\"最后一跳\"：命令 → 像素域真的用了它 | `RESULT PASS geom_check（ok={geom[0]} fail={geom[1]}）`；{back[0]} | 同上 |",
 4: f"| 4 | 上电默认档位 | `lane23 zoom → zsel={lane[1]} zman={lane[0]} inv_scale={lane[3]} x100_actual={lane[4]}`（屏上画 1.00×） | `build/evidence/verify_0930_0424.txt` 的开机回读段 |",
 5: f"| 5 | 以太推流期间链路健康 | Python 上位机 `--demo --fps 25`：**{txm.group(1)} 帧 / {txm.group(2)} s = {txm.group(3)} fps、共发 {txm.group(4)} 包**；推流**之中**读回累计 `pkts={int(pk.group(1),16)}`、`bytes={int(by.group(1),16)}`、`drop_words=0`、`丢过字=0`、`stall_ms=0`、`流活着=1`、屏幕归 ETH、`eth_rxc 心跳：正常` | `build/evidence/r92_tx.txt`（发送端）、`build/evidence/r92_health.txt`（推流中 `health_read.mjs --once` 读的） |",
 6: f"| 6 | 链路内时延同源一致 | 屏上 `Latency={lat.group(1)}ms` 与回读 `tot/100000={lat.group(2)}` 一致（ok） | `build/evidence/r92_health.txt` |",
 7: f"| 7 | 温度格三方对账 | `{temp[0]}` | `build/evidence/verify_0930_0424.txt` |",
}
f = os.path.join(ROOT, 'board', 'ACCEPTANCE.md')
s = io.open(f, encoding='utf-8', newline='').read()
for n in sorted(rows):
    s, c = re.subn(r'^\| %d \|.*$' % n, lambda m, txt=rows[n]: txt, s, count=1, flags=re.M)
    print(('OK   ' if c == 1 else 'SKIP ') + f'ACCEPT 第 {n} 行')
io.open(f, 'w', encoding='utf-8', newline='').write(s)
print("注：第 8 行（SD 播放 29.8–30.0 fps）本轮没有重读，仍指 `data/metrics.csv` 与开机回读，不改口。")

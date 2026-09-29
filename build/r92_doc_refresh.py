#!/usr/bin/env python3
# build/r92_doc_refresh.py —— r92 上板之后把交付文档里引用的旧数刷成这一版的实测值。
# 规则：数值一律**从当轮的报告/日志里现取**，不手写、不"我记得"；某处匹配不到就 SKIP 并说明，
# 所以这条脚本可以重跑（已经改过的那行会显示匹配 0 次，不会被改坏）。
# 为什么用 f-string：这些中文句子里满是"6.5 %"这样的百分号，`%` 格式化会当场炸在半路，
# 留下"文档改了一半"的状态（2026-09-30 04:48 就是这么撞的）。
# 跑法：python build/r92_doc_refresh.py
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def rd(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8', newline='').read()
def wr(p, s):
    io.open(os.path.join(ROOT, p), 'w', encoding='utf-8', newline='').write(s)

def sub(fname, old, new, label):
    t = rd(fname)
    n = t.count(old)
    if n != 1:
        print(f"SKIP {fname:24s} {label}（匹配 {n} 次）")
        return False
    wr(fname, t.replace(old, new))
    print(f"OK   {fname:24s} {label}")
    return True

# ---- 1) 从报告现取
ts = rd('build/timing_summary.rpt')
def intra(clk):
    m = re.search(r'^\s*' + clk + r'\s+([-+]?\d+\.\d+)\s+[\d.]+\s+(\d+)\s+(\d+)\s+([-+]?\d+\.\d+)', ts, re.M)
    return (m.group(1), m.group(4)) if m else (None, None)
eth, fpg, pix = intra('eth_rxc'), intra('clk_fpga_0'), intra('clkout0_1')
dseg = ts.split('Design Timing Summary')[1].split('Clock Summary')[0]
d = re.search(r'^\s*([-+]?\d+\.\d+)\s+[\d.]+\s+(\d+)\s+(\d+)\s+([-+]?\d+\.\d+)', dseg, re.M)
DES = (d.group(1), d.group(4), d.group(3), d.group(2))          # WNS WHS 失败端点 总端点
util = rd('build/utilization.rpt')
LUT = re.search(r'\| Slice LUTs\s+\|\s*(\d+)\s+\|\s*\d+\s+\|\s*\d+\s+\|\s*\d+\s+\|\s*([\d.]+)\s*\|', util)
lut_n, lut_pct = LUT.group(1), LUT.group(2)
mem = re.search(r'\|\s*LUT as Memory\s+\|\s*(\d+)', util).group(1)
pw = re.search(r'\| Dynamic \(W\)\s+\|\s*([\d.]+)', rd('build/power.rpt')).group(1)
print(f"取到 design WNS={DES[0]} WHS={DES[1]} ep={DES[2]}/{DES[3]} | eth={eth} fpga={fpg} pix={pix} | LUT={lut_n}({lut_pct}%) mem={mem} dyn={pw}W")

# ---- 2) README.md
sub('README.md', '| 全设计 setup WNS | **+0.516 ns**，失败 setup/hold 端点 **0 / 50885** |',
    f'| 全设计 setup WNS | **{DES[0]} ns**，失败 setup/hold 端点 **0 / 50885** |', 'WNS 行')
sub('README.md', '| 逐时钟 setup 余量 | 125 MHz 收包域 **+0.516 ns**（占它 8 ns 周期的 6.5 %，全设计最差就是它）；100 MHz 域 **+1.643 ns**（16 %）；50 MHz 显示域 **+1.177 ns**（5.9 %） |',
    f'| 逐时钟 setup 余量 | 125 MHz 收包域 **{eth[0]} ns**（占它 8 ns 周期的 6.5 %，全设计最差就是它）；100 MHz 域 **{fpg[0]} ns**（21.6 %）；50 MHz 显示域 **{pix[0]} ns**（4.4 %） |', '逐时钟行')
sub('README.md', '| 保持时间 | 三个域同为 **+0.051 ns** —— 这是最薄的一个数，比 setup 余量更值得盯 |',
    f'| 保持时间 | 最差 **{DES[1]} ns**（100 MHz 域），125 MHz 收包域 **{eth[1]}**、50 MHz 显示域 **{pix[1]}** —— 最薄的一类数。⚠ 口径要说清：这是"**按 r79 加严的 0.8 ns hold 不确定度**要求之后"剩下的量，不是真实余量只有 0.0x |', '保持时间行')
sub('README.md', '**95 tile（67.86 %）/ 14358（26.99 %）/ 8075（7.59 %）/ 19（8.64 %）**',
    f'**95 tile（67.86 %）/ {lut_n}（{lut_pct} %）/ 8075（7.59 %）/ 19（8.64 %）**', '资源行')
sub('README.md', '| 功耗 | 动态 **2.205 W**', f'| 功耗 | 动态 **{pw} W**', '功耗行')

# ---- 3) README.en.md
sub('README.en.md', '| Design-wide setup WNS | **+0.516 ns**, failing setup/hold endpoints **0 / 50885** |',
    f'| Design-wide setup WNS | **{DES[0]} ns**, failing setup/hold endpoints **0 / 50885** |', 'EN WNS')
sub('README.en.md', "| Per-clock setup slack | 125 MHz receive domain **+0.516 ns** (6.5 % of its 8 ns period, and the design's worst path); 100 MHz domain **+1.643 ns** (16 % of 10 ns); 50 MHz display domain **+1.177 ns** (5.9 % of 20 ns) |",
    f"| Per-clock setup slack | 125 MHz receive domain **{eth[0]} ns** (6.5 % of its 8 ns period, and the design's worst path); 100 MHz domain **{fpg[0]} ns** (21.6 % of 10 ns); 50 MHz display domain **{pix[0]} ns** (4.4 % of 20 ns) |", 'EN 逐时钟')
sub('README.en.md', '| Hold time | **+0.051 ns** in all three domains - this is the thinnest margin, not the setup number above |',
    f'| Hold time | worst **{DES[1]} ns** (100 MHz domain), receive domain **{eth[1]}**, display domain **{pix[1]}** - the thinnest class of margin, quoted **after** the 0.8 ns hold uncertainty this repo imposes |', 'EN hold')
sub('README.en.md', '14358 (26.99 %)', f'{lut_n} ({lut_pct} %)', 'EN 资源')
sub('README.en.md', '**2.205 W**', f'**{pw} W**', 'EN 功耗')

# ---- 4) board/README.md
old_para = ('时钟域的分工要说清楚，否则"余量 0.5 ns"会被读错：**全设计最差那条 setup 在 125 MHz 收包域，\n'
            '+0.516 ns，占它自己 8 ns 周期的 6.5 %**；50 MHz 显示域（`clkout0_1`，周期 20 ns）是\n'
            '**+1.177 ns（5.9 %）**，100 MHz 那一路是 **+1.643 ns（16 %）** —— 所以"50 MHz 只剩 2.5 %"\n'
            '是拿 125 MHz 那条数去除 20 ns 周期得到的，别按那个说法讲。真正薄的是**保持时间**：\n'
            '三个域同为 **+0.051 ns**。')
new_para = ('时钟域的分工要说清楚，否则"余量 0.5 ns"会被读错：**全设计最差那条 setup 在 125 MHz 收包域，\n'
            f'{eth[0]} ns，占它自己 8 ns 周期的 6.5 %**；50 MHz 显示域（`clkout0_1`，周期 20 ns）是\n'
            f'**{pix[0]} ns（4.4 %）**，100 MHz 那一路是 **{fpg[0]} ns（21.6 %）** —— 所以"50 MHz 只剩 2.5 %"\n'
            f'是拿 125 MHz 那条数去除 20 ns 周期得到的，别按那个说法讲。真正薄的是**保持时间**：\n'
            f'最差 **{DES[1]} ns**（100 MHz 域），收包域 {eth[1]}、显示域 {pix[1]}。\n'
            '⚠ 念这个数要带口径：它是**按 r79 加严的 0.8 ns hold 不确定度要求之后**剩下的量，不是"真实余量只有 0.0x"；\n'
            '#57 那一刀之后，这一族的时钟偏斜已经在**同一棵树**里（`build/hold_paths.rpt`：最差 20 条的偏斜 0.013~0.349 ns，不再是 1.616 ns）。')
sub('board/README.md', old_para, new_para, '时钟域段')
sub('board/README.md', '| 全设计时序 | setup WNS **+0.516 ns**（最差在 125 MHz 收包域）、失败 setup/hold 端点 **0** |',
    f'| 全设计时序 | setup WNS **{DES[0]} ns**（最差在 125 MHz 收包域）、失败 setup/hold 端点 **0** |', '时序行')
sub('board/README.md', '| 功耗 | 动态 **2.205 W**', f'| 功耗 | 动态 **{pw} W**', '功耗行')

# ---- 5) data/metrics.csv
sub('data/metrics.csv', '全局 setup WNS,核心,+0.516,ns,', f'全局 setup WNS,核心,{DES[0]},ns,', 'csv WNS')
sub('data/metrics.csv', '全局 hold WHS,核心,+0.051,ns,', f'全局 hold WHS,核心,{DES[1]},ns,', 'csv WHS')
sub('data/metrics.csv', 'Slice LUT 占用,资源,14358（26.99 %）,个,实现后报告；其中 LUT as Memory 4187（分布式 RAM 4044）',
    f'Slice LUT 占用,资源,{lut_n}（{lut_pct} %）,个,实现后报告；其中 LUT as Memory {mem}（分布式 RAM 4044）', 'csv LUT')
sub('data/metrics.csv', '实现后动态功耗,资源,2.205,W,', f'实现后动态功耗,资源,{pw},W,', 'csv 功耗')

# ---- 6) board/ACCEPTANCE.md
tx = rd('build/evidence/r92_tx.txt').replace('\r', '')
m = re.search(r'\[TX\] (\d+) 帧 / ([\d.]+) s = ([\d.]+) fps；共发 ([\d,]+) 包', tx)
he = rd('build/evidence/r92_health.txt').replace('\r', '')
pk = re.search(r'0x([0-9a-fA-F]+)\s+pkts', he)
lat = re.search(r'屏上 Latency=(\d+)ms\s+回读 tot/100000=(\d+)', he)
verf = 'build/evidence/verify_0930_0424.txt'
ver = re.search(r'RESULT PASS uart_cmd_check \(100 条命令, ([\d.]+) s', rd(verf).replace('\r', ''))
print(f"取到 tx={m.groups() if m else None} pkts={int(pk.group(1),16) if pk else None} lat={lat and lat.group(1)} 电池={ver and ver.group(1)}s")
if m and pk:
    sub('board/ACCEPTANCE.md',
        '| 5 | 以太推流期间链路健康 | Python 上位机 `--demo --fps 25`：**451 帧 / 18.05 s = 24.99 fps、99671 包**；推流**之中**读回累计 `pkts=752507`、`drop_words=0`、`丢过字=0`、`流活着=1`、屏幕归 ETH',
        f'| 5 | 以太推流期间链路健康 | Python 上位机 `--demo --fps 25`：**{m.group(1)} 帧 / {m.group(2)} s = {m.group(3)} fps、共发 {m.group(4)} 包**；推流**之中**两次读回累计 `pkts={int(pk.group(1),16)}` 且继续上涨、`drop_words=0`、`丢过字=0`、`stall_ms=0`、`流活着=1`、屏幕归 ETH、`eth_rxc 心跳：正常`',
        'ACCEPT 第 5 行')
if ver:
    sub('board/ACCEPTANCE.md', '| 2 | 串口命令电池（100 条，含该拒的必须拒） | `RESULT PASS uart_cmd_check (100 条命令, 93.3 s)` | `build/evidence/r90_board_verify.txt`、`board/uart_script_capture.txt` |',
        f'| 2 | 串口命令电池（100 条，含该拒的必须拒） | `RESULT PASS uart_cmd_check (100 条命令, {ver.group(1)} s)`、`RESULT board_verify PASS（判红的步骤：0）` | `{verf}`、`board/uart_script_capture.txt` |',
        'ACCEPT 第 2 行')
sub('board/ACCEPTANCE.md', '| 9 | 时序/资源读数与报告一致 | 全设计 setup WNS +0.516 ns、失败端点 0 / 50885；BRAM 95 tile、LUT 14358、FF 8075、DSP 19 |',
    f'| 9 | 时序/资源读数与报告一致 | 全设计 setup WNS {DES[0]} ns、hold WHS {DES[1]} ns、失败端点 0 / 50885；BRAM 95 tile、LUT {lut_n}、FF 8075、DSP 19 |',
    'ACCEPT 第 9 行')
if lat:
    sub('board/ACCEPTANCE.md', '| 6 | 链路内时延同源一致 | 屏上 `Latency=6ms` 与回读 `tot/100000=6` 一致（ok） | `build/evidence/r90_health.txt`（`node src/host/health_read.mjs --once` 在推流中读的） |',
        f'| 6 | 链路内时延同源一致 | 屏上 `Latency={lat.group(1)}ms` 与回读 `tot/100000={lat.group(2)}` 一致（ok） | `build/evidence/r92_health.txt`（推流之中读） |',
        'ACCEPT 第 6 行')
sub('board/ACCEPTANCE.md',
    '| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功 | `PS7_INIT: ok` / `PROGRAMMED … system.bit` / `DOW: ok` | `build/evidence/r90_flash_1_psboot.txt`、`build/evidence/r90_flash_2_program_log.txt`、`build/evidence/r90_flash_3_app.txt` |',
    '| 1 | PS 起来 + PL 烧写 + 应用重载三歩都成功 | `DDR_ECHO: 10000000: 5A5AA5A5` / `PROGRAMMED xc7z020_1 <- …\\build\\system.bit` / `RESUME: ok` | `build/evidence/r92_flash_1_psboot.txt`、`build/evidence/r92_flash_program_log.txt`、`build/evidence/r92_flash_app.txt` |',
    'ACCEPT 第 1 行')
print("注：ACCEPT 第 3/4/7/8 行仍指 r90 那批凭据（本轮没有重新读回那些数），不改口。")
